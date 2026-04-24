import Foundation

struct RetainedTaskCommandResult: Equatable, Sendable {
  let projectID: UUID
  let taskID: UUID
  let calendarBridgeDecision: RetainedCalendarBridgeDecision
  let calendarWriteMarker: RetainedCalendarBridgeWriteMarker?
}

struct RetainedCalendarBridgeWriteMarker: Equatable, Hashable, Sendable {
  enum Operation: String, Equatable, Hashable, Sendable {
    case upsertOwnedEvent
    case removeOwnedEvent
  }

  let taskID: UUID
  let operation: Operation
  let externalIdentifier: String?
  let title: String?
  let startDate: Date?
  let durationMinutes: Int?
}

enum RetainedCalendarBridgeWriteLoopGuard {
  static func marker(
    taskID: UUID,
    decision: RetainedCalendarBridgeDecision
  ) -> RetainedCalendarBridgeWriteMarker? {
    switch decision {
    case .noAction, .failClosed:
      return nil
    case .upsert(let request):
      return RetainedCalendarBridgeWriteMarker(
        taskID: taskID,
        operation: .upsertOwnedEvent,
        externalIdentifier: request.externalIdentifier,
        title: request.title,
        startDate: request.startDate,
        durationMinutes: request.durationMinutes
      )
    case .removeOwnedEvent(let externalIdentifier):
      return RetainedCalendarBridgeWriteMarker(
        taskID: taskID,
        operation: .removeOwnedEvent,
        externalIdentifier: externalIdentifier,
        title: nil,
        startDate: nil,
        durationMinutes: nil
      )
    }
  }

  static func shouldSuppressEcho(
    marker: RetainedCalendarBridgeWriteMarker,
    activeMarkers: Set<RetainedCalendarBridgeWriteMarker>
  ) -> Bool {
    activeMarkers.contains(marker)
  }
}

enum RetainedTaskCommandError: LocalizedError, Equatable {
  case graphNotConfigured
  case retainedProjectionFailed(String)
  case projectNotFound(UUID)
  case taskNotFound(UUID)
  case unmanagedTask(UUID)
  case missingReminderExternalIdentifier(UUID)
  case unsafeProjectPage(UUID)
  case reminderOwnerUnresolved(UUID)
  case rollbackFailed(writeError: String, rollbackError: String)

  var errorDescription: String? {
    switch self {
    case .graphNotConfigured:
      return "Logseq graph is not configured for retained task writes."
    case .retainedProjectionFailed(let message):
      return "Retained task write blocked: \(message)"
    case .projectNotFound(let projectID):
      return "Retained project not found: \(projectID.uuidString)"
    case .taskNotFound(let taskID):
      return "Retained task not found: \(taskID.uuidString)"
    case .unmanagedTask(let taskID):
      return "Retained task is not in the managed Logseq task section: \(taskID.uuidString)"
    case .missingReminderExternalIdentifier(let taskID):
      return "Retained task is missing reminder_external_id:: \(taskID.uuidString)"
    case .unsafeProjectPage(let projectID):
      return "Retained project page cannot be safely updated in this slice: \(projectID.uuidString)"
    case .reminderOwnerUnresolved(let taskID):
      return "Reminder owner could not be resolved for retained task: \(taskID.uuidString)"
    case .rollbackFailed(let writeError, let rollbackError):
      return "Retained task write failed and Logseq rollback failed. write=\(writeError) rollback=\(rollbackError)"
    }
  }
}

@MainActor
enum RetainedTaskCommandService {
  static func setTaskCompletion(
    graphRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let context = try await commandContext(
      graphRootURL: graphRootURL,
      projectID: projectID,
      taskID: taskID
    )
    let reminderReference = try reminderReference(for: context.task, taskID: taskID)
    var managedTasks = context.page.managedTasks
    managedTasks[context.managedTaskIndex].isCompleted = isCompleted

    try await writeManagedTasks(managedTasks, using: context)
    do {
      guard try reminderProjectProvider.setTaskCompletion(
        for: reminderReference,
        isCompleted: isCompleted,
        completionDate: isCompleted ? (completionDate ?? .now) : nil
      ) != nil else {
        throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
      }
    } catch {
      try await rollbackLogseqWrite(
        context: context,
        expectedManagedTasks: managedTasks,
        writeError: error
      )
    }

    return try result(
      projectID: projectID,
      taskID: taskID,
      page: context.page,
      managedTasks: managedTasks
    )
  }

  static func setTaskSchedule(
    graphRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar = .autoupdatingCurrent,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let context = try await commandContext(
      graphRootURL: graphRootURL,
      projectID: projectID,
      taskID: taskID
    )
    let reminderReference = try reminderReference(for: context.task, taskID: taskID)
    let dueDate = scheduledDate(day: day, timeMinutes: timeMinutes, calendar: calendar)
    let hasExplicitTime = dueDate != nil && timeMinutes != nil
    var managedTasks = context.page.managedTasks
    managedTasks[context.managedTaskIndex].date = LogseqReminderPropertyCodec.encodeDate(
      dueDate,
      hasExplicitTime: hasExplicitTime
    )
    managedTasks[context.managedTaskIndex].duration = normalizedDuration(
      durationMinutes,
      hasExplicitTime: hasExplicitTime
    )

    try await writeManagedTasks(managedTasks, using: context)
    do {
      guard try reminderProjectProvider.setTaskSchedule(
        for: reminderReference,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime
      ) != nil else {
        throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
      }
    } catch {
      try await rollbackLogseqWrite(
        context: context,
        expectedManagedTasks: managedTasks,
        writeError: error
      )
    }

    return try result(
      projectID: projectID,
      taskID: taskID,
      page: context.page,
      managedTasks: managedTasks
    )
  }

  private struct CommandContext {
    let store: LogseqProjectPageStore
    let page: LogseqProjectPageStore.PageSnapshot
    let task: RetainedTask
    let managedTaskIndex: Int
  }

  private static func commandContext(
    graphRootURL: URL?,
    projectID: UUID,
    taskID: UUID
  ) async throws -> CommandContext {
    guard let graphRootURL else {
      throw RetainedTaskCommandError.graphNotConfigured
    }

    let store = LogseqProjectPageStore(
      pagesRootURL: graphRootURL.appendingPathComponent("pages", isDirectory: true)
    )
    let pages: [LogseqProjectPageStore.PageSnapshot]
    do {
      pages = try await store.loadProjectPagesInScope()
    } catch {
      throw RetainedTaskCommandError.retainedProjectionFailed(error.localizedDescription)
    }

    let snapshot: RetainedWorkspaceSnapshot
    do {
      snapshot = try RetainedProjectionBuilder.build(.init(pages: pages))
    } catch {
      throw RetainedTaskCommandError.retainedProjectionFailed(error.localizedDescription)
    }

    guard let project = snapshot.projects.first(where: { $0.identity.projectID == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    guard let task = project.tasks.first(where: { $0.identity.taskID == taskID }) else {
      throw RetainedTaskCommandError.taskNotFound(taskID)
    }
    guard task.isManagedTask else {
      throw RetainedTaskCommandError.unmanagedTask(taskID)
    }
    guard task.identity.reminderExternalIdentifier != nil else {
      throw RetainedTaskCommandError.missingReminderExternalIdentifier(taskID)
    }
    guard let page = pages.first(where: { $0.projectID == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    guard page.canSafelyPersistProjectNote, page.hasManagedTaskSection else {
      throw RetainedTaskCommandError.unsafeProjectPage(projectID)
    }
    guard let managedTaskIndex = page.managedTasks.firstIndex(where: { $0.taskID == taskID }) else {
      throw RetainedTaskCommandError.unmanagedTask(taskID)
    }

    return CommandContext(
      store: store,
      page: page,
      task: task,
      managedTaskIndex: managedTaskIndex
    )
  }

  private static func writeManagedTasks(
    _ managedTasks: [LogseqProjectPageStore.TaskRecord],
    using context: CommandContext
  ) async throws {
    guard !ManagedLogseqSyncHardening.hasAmbiguousManagedTaskIdentities(managedTasks) else {
      throw RetainedTaskCommandError.retainedProjectionFailed("ambiguous managed task identity")
    }
    try await context.store.updateManagedTasks(
      in: context.page,
      expectedManagedTasks: context.page.managedTasks,
      managedTasks: managedTasks
    )
  }

  private static func rollbackLogseqWrite(
    context: CommandContext,
    expectedManagedTasks: [LogseqProjectPageStore.TaskRecord],
    writeError: Error
  ) async throws -> Never {
    do {
      try await context.store.updateManagedTasks(
        in: context.page,
        expectedManagedTasks: expectedManagedTasks,
        managedTasks: context.page.managedTasks
      )
    } catch {
      throw RetainedTaskCommandError.rollbackFailed(
        writeError: writeError.localizedDescription,
        rollbackError: error.localizedDescription
      )
    }
    throw writeError
  }

  private static func reminderReference(
    for task: RetainedTask,
    taskID: UUID
  ) throws -> ReminderTaskReference {
    guard let reminderExternalIdentifier = task.identity.reminderExternalIdentifier else {
      throw RetainedTaskCommandError.missingReminderExternalIdentifier(taskID)
    }
    return ReminderTaskReference(
      taskID: taskID,
      reminderIdentifier: nil,
      reminderExternalIdentifier: reminderExternalIdentifier
    )
  }

  private static func result(
    projectID: UUID,
    taskID: UUID,
    page: LogseqProjectPageStore.PageSnapshot,
    managedTasks: [LogseqProjectPageStore.TaskRecord]
  ) throws -> RetainedTaskCommandResult {
    var updatedPage = page
    updatedPage.managedTasks = managedTasks
    let snapshot = try RetainedProjectionBuilder.build(.init(pages: [updatedPage]))
    guard let task = snapshot.tasks.first(where: { $0.identity.taskID == taskID }) else {
      throw RetainedTaskCommandError.taskNotFound(taskID)
    }
    let calendarBridgeDecision = RetainedCalendarBridgePolicy.decision(for: task)
    return RetainedTaskCommandResult(
      projectID: projectID,
      taskID: taskID,
      calendarBridgeDecision: calendarBridgeDecision,
      calendarWriteMarker: RetainedCalendarBridgeWriteLoopGuard.marker(
        taskID: taskID,
        decision: calendarBridgeDecision
      )
    )
  }

  private static func scheduledDate(
    day: Date?,
    timeMinutes: Int?,
    calendar: Calendar
  ) -> Date? {
    guard let day else { return nil }
    let normalizedDay = calendar.startOfDay(for: day)
    guard let timeMinutes else { return normalizedDay }
    let boundedMinutes = min(max(0, timeMinutes), 23 * 60 + 59)
    return calendar.date(
      bySettingHour: boundedMinutes / 60,
      minute: boundedMinutes % 60,
      second: 0,
      of: normalizedDay
    ) ?? normalizedDay
  }

  private static func normalizedDuration(
    _ durationMinutes: Int?,
    hasExplicitTime: Bool
  ) -> String? {
    guard hasExplicitTime, let durationMinutes, durationMinutes > 0 else { return nil }
    return String(durationMinutes)
  }
}
