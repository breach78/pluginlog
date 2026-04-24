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
      return "Retained task is not in an editable Logseq task block: \(taskID.uuidString)"
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
    let updatedTasks = updatedTaskCollections(from: context) { task in
      task.isCompleted = isCompleted
    }

    try await writeTasks(updatedTasks, using: context)
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
        expectedTasks: updatedTasks,
        writeError: error
      )
    }

    return try result(
      projectID: projectID,
      taskID: taskID,
      page: context.page,
      tasks: updatedTasks
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
    let updatedTasks = updatedTaskCollections(from: context) { task in
      task.date = LogseqReminderPropertyCodec.encodeDate(
        dueDate,
        hasExplicitTime: hasExplicitTime
      )
      task.duration = normalizedDuration(
        durationMinutes,
        hasExplicitTime: hasExplicitTime
      )
    }

    try await writeTasks(updatedTasks, using: context)
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
        expectedTasks: updatedTasks,
        writeError: error
      )
    }

    return try result(
      projectID: projectID,
      taskID: taskID,
      page: context.page,
      tasks: updatedTasks
    )
  }

  private struct CommandContext {
    let store: LogseqProjectPageStore
    let page: LogseqProjectPageStore.PageSnapshot
    let task: RetainedTask
    let location: TaskLocation
  }

  private enum TaskLocation {
    case managed(Int)
    case external(Int)
  }

  private struct UpdatedTaskCollections {
    var managedTasks: [LogseqProjectPageStore.TaskRecord]
    var externalTasks: [LogseqProjectPageStore.TaskRecord]
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
    guard task.identity.reminderExternalIdentifier != nil else {
      throw RetainedTaskCommandError.missingReminderExternalIdentifier(taskID)
    }
    guard let page = pages.first(where: { retainedProjectID(for: $0) == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    guard let location = taskLocation(in: page, taskID: taskID) else {
      throw RetainedTaskCommandError.unmanagedTask(taskID)
    }
    switch location {
    case .managed:
      guard page.canSafelyPersistProjectNote, page.hasManagedTaskSection else {
        throw RetainedTaskCommandError.unsafeProjectPage(projectID)
      }
    case .external:
      guard page.reminderListExternalIdentifier != nil else {
        throw RetainedTaskCommandError.unsafeProjectPage(projectID)
      }
    }

    return CommandContext(
      store: store,
      page: page,
      task: task,
      location: location
    )
  }

  private static func taskLocation(
    in page: LogseqProjectPageStore.PageSnapshot,
    taskID: UUID
  ) -> TaskLocation? {
    if let managedTaskIndex = page.managedTasks.firstIndex(where: { retainedTaskID(for: $0) == taskID }) {
      return .managed(managedTaskIndex)
    }
    if let externalTaskIndex = page.externalTasks.firstIndex(where: { retainedTaskID(for: $0) == taskID }) {
      return .external(externalTaskIndex)
    }
    return nil
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

  private static func updatedTaskCollections(
    from context: CommandContext,
    mutate: (inout LogseqProjectPageStore.TaskRecord) -> Void
  ) -> UpdatedTaskCollections {
    var managedTasks = context.page.managedTasks
    var externalTasks = context.page.externalTasks
    switch context.location {
    case .managed(let index):
      mutate(&managedTasks[index])
    case .external(let index):
      mutate(&externalTasks[index])
    }
    return UpdatedTaskCollections(
      managedTasks: managedTasks,
      externalTasks: externalTasks
    )
  }

  private static func writeTasks(
    _ tasks: UpdatedTaskCollections,
    using context: CommandContext
  ) async throws {
    switch context.location {
    case .managed:
      try await writeManagedTasks(tasks.managedTasks, using: context)
    case .external(let index):
      try await context.store.updateExternalTask(
        in: context.page,
        expectedExternalTasks: context.page.externalTasks,
        taskIndex: index,
        task: tasks.externalTasks[index]
      )
    }
  }

  private static func rollbackLogseqWrite(
    context: CommandContext,
    expectedTasks: UpdatedTaskCollections,
    writeError: Error
  ) async throws -> Never {
    do {
      try await writeTasks(
        UpdatedTaskCollections(
          managedTasks: context.page.managedTasks,
          externalTasks: context.page.externalTasks
        ),
        using: rollbackContext(context, expectedTasks: expectedTasks)
      )
    } catch {
      throw RetainedTaskCommandError.rollbackFailed(
        writeError: writeError.localizedDescription,
        rollbackError: error.localizedDescription
      )
    }
    throw writeError
  }

  private static func rollbackContext(
    _ context: CommandContext,
    expectedTasks: UpdatedTaskCollections
  ) -> CommandContext {
    var page = context.page
    page.managedTasks = expectedTasks.managedTasks
    page.externalTasks = expectedTasks.externalTasks
    return CommandContext(
      store: context.store,
      page: page,
      task: context.task,
      location: context.location
    )
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

  private static func retainedProjectID(
    for page: LogseqProjectPageStore.PageSnapshot
  ) -> UUID? {
    if let projectID = page.projectID {
      return projectID
    }
    guard let reminderListExternalIdentifier = normalizedIdentifier(
      page.reminderListExternalIdentifier
    ) else {
      return nil
    }
    return RetainedProjectionBuilder.derivedProjectID(for: reminderListExternalIdentifier)
  }

  private static func retainedTaskID(
    for task: LogseqProjectPageStore.TaskRecord
  ) -> UUID? {
    if let reminderExternalIdentifier = normalizedIdentifier(task.reminderExternalIdentifier) {
      let reminderDerivedTaskID = ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
      guard task.taskID == nil || task.taskID == reminderDerivedTaskID else {
        return nil
      }
      return reminderDerivedTaskID
    }
    return task.taskID
  }

  private static func result(
    projectID: UUID,
    taskID: UUID,
    page: LogseqProjectPageStore.PageSnapshot,
    tasks: UpdatedTaskCollections
  ) throws -> RetainedTaskCommandResult {
    var updatedPage = page
    updatedPage.managedTasks = tasks.managedTasks
    updatedPage.externalTasks = tasks.externalTasks
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

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
