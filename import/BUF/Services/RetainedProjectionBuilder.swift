import CryptoKit
import Foundation

enum RetainedProjectionBuilder {
  struct Source: Equatable, Sendable {
    var pages: [LogseqProjectPageStore.PageSnapshot]
    var projectBindings: [ProjectBinding] = []
    var taskBindings: [TaskBinding] = []
  }

  struct ProjectBinding: Equatable, Sendable {
    let projectID: UUID
    let reminderListExternalIdentifier: String
  }

  struct TaskBinding: Equatable, Sendable {
    let projectID: UUID
    let taskID: UUID
    let reminderExternalIdentifier: String?
    let calendarEventExternalIdentifier: String?
  }

  enum Error: LocalizedError, Equatable {
    case duplicateProjectID(UUID)
    case duplicateReminderListExternalIdentifier(String)
    case duplicateTaskID(UUID)
    case duplicateReminderExternalIdentifier(String)
    case duplicateCalendarEventExternalIdentifier(String)
    case damagedProjectIdentity(pageTitle: String)
    case conflictingProjectIdentity(pageTitle: String)
    case damagedTaskIdentity(projectTitle: String, taskTitle: String)
    case missingPageForProjectBinding(projectID: UUID, reminderListExternalIdentifier: String)
    case orphanTaskBinding(taskID: UUID)

    var errorDescription: String? {
      switch self {
      case .duplicateProjectID(let projectID):
        return "중복된 retained project id가 발견되었습니다. (\(projectID.uuidString))"
      case .duplicateReminderListExternalIdentifier(let identifier):
        return "중복된 reminder list external id가 발견되었습니다. (\(identifier))"
      case .duplicateTaskID(let taskID):
        return "중복된 retained task id가 발견되었습니다. (\(taskID.uuidString))"
      case .duplicateReminderExternalIdentifier(let identifier):
        return "중복된 reminder external id가 발견되었습니다. (\(identifier))"
      case .duplicateCalendarEventExternalIdentifier(let identifier):
        return "중복된 calendar event external id가 발견되었습니다. (\(identifier))"
      case .damagedProjectIdentity(let pageTitle):
        return "프로젝트 hidden identity가 손상되어 retained projection을 만들 수 없습니다. (\(pageTitle))"
      case .conflictingProjectIdentity(let pageTitle):
        return "페이지 project identity와 reminder identity가 충돌합니다. (\(pageTitle))"
      case .damagedTaskIdentity(let projectTitle, let taskTitle):
        return "할일 hidden identity가 손상되어 retained projection을 만들 수 없습니다. (\(projectTitle) / \(taskTitle))"
      case .missingPageForProjectBinding(let projectID, let reminderListExternalIdentifier):
        return "retained project binding에 대응하는 페이지를 찾지 못했습니다. (\(projectID.uuidString), \(reminderListExternalIdentifier))"
      case .orphanTaskBinding(let taskID):
        return "retained task binding이 안전하게 연결될 할일을 찾지 못했습니다. (\(taskID.uuidString))"
      }
    }
  }

  private struct IndexedTask {
    let projectID: UUID
    let task: RetainedTask
  }

  static func build(_ source: Source) throws -> RetainedWorkspaceSnapshot {
    let projectBindings = try normalizedProjectBindings(source.projectBindings)
    let taskBindings = try normalizedTaskBindings(source.taskBindings)

    var projects: [RetainedProject] = []
    var tasksByID: [UUID: IndexedTask] = [:]

    var seenProjectIDs: Set<UUID> = []
    var seenReminderListExternalIdentifiers: Set<String> = []
    var seenTaskIDs: Set<UUID> = []
    var seenReminderExternalIdentifiers: Set<String> = []
    var seenCalendarEventExternalIdentifiers: Set<String> = []

    for page in source.pages.sorted(by: pageSort) {
      let reminderListExternalIdentifier = normalizedIdentifier(page.reminderListExternalIdentifier)
      guard let projectID = try resolvedProjectID(
        from: page,
        reminderListExternalIdentifier: reminderListExternalIdentifier
      ) else {
        if let damagedTask = firstTaskWithRetainedIdentity(in: page) {
          throw Error.damagedTaskIdentity(projectTitle: page.title, taskTitle: damagedTask.title)
        }
        continue
      }

      guard seenProjectIDs.insert(projectID).inserted else {
        throw Error.duplicateProjectID(projectID)
      }
      if let reminderListExternalIdentifier {
        guard seenReminderListExternalIdentifiers.insert(reminderListExternalIdentifier).inserted else {
          throw Error.duplicateReminderListExternalIdentifier(reminderListExternalIdentifier)
        }
      }

      let tasks = try buildTasks(
        page: page,
        projectID: projectID,
        seenTaskIDs: &seenTaskIDs,
        seenReminderExternalIdentifiers: &seenReminderExternalIdentifiers,
        seenCalendarEventExternalIdentifiers: &seenCalendarEventExternalIdentifiers,
        tasksByID: &tasksByID
      )

      projects.append(
        RetainedProject(
          identity: RetainedProjectIdentity(
            projectID: projectID,
            reminderListExternalIdentifier: reminderListExternalIdentifier
          ),
          fileURL: page.fileURL,
          title: page.title,
          noteMarkdown: page.noteMarkdown,
          tasks: tasks,
          usesProjectTag: page.usesProjectTag,
          isBUFOwned: page.isBUFOwned,
          hasManagedTaskSection: page.hasManagedTaskSection,
          canSafelyPersistProjectNote: page.canSafelyPersistProjectNote
        )
      )
    }

    let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.identity.projectID, $0) })

    for binding in projectBindings {
      guard let project = projectsByID[binding.projectID] else {
        throw Error.missingPageForProjectBinding(
          projectID: binding.projectID,
          reminderListExternalIdentifier: binding.reminderListExternalIdentifier
        )
      }
      guard project.identity.reminderListExternalIdentifier == binding.reminderListExternalIdentifier else {
        throw Error.missingPageForProjectBinding(
          projectID: binding.projectID,
          reminderListExternalIdentifier: binding.reminderListExternalIdentifier
        )
      }
    }

    for binding in taskBindings {
      guard let indexedTask = tasksByID[binding.taskID] else {
        throw Error.orphanTaskBinding(taskID: binding.taskID)
      }
      guard indexedTask.projectID == binding.projectID else {
        throw Error.orphanTaskBinding(taskID: binding.taskID)
      }
      if binding.reminderExternalIdentifier != indexedTask.task.identity.reminderExternalIdentifier {
        throw Error.orphanTaskBinding(taskID: binding.taskID)
      }
      if binding.calendarEventExternalIdentifier != indexedTask.task.identity.calendarEventExternalIdentifier {
        throw Error.orphanTaskBinding(taskID: binding.taskID)
      }
    }

    return RetainedWorkspaceSnapshot(projects: projects)
  }

  private static func buildTasks(
    page: LogseqProjectPageStore.PageSnapshot,
    projectID: UUID,
    seenTaskIDs: inout Set<UUID>,
    seenReminderExternalIdentifiers: inout Set<String>,
    seenCalendarEventExternalIdentifiers: inout Set<String>,
    tasksByID: inout [UUID: IndexedTask]
  ) throws -> [RetainedTask] {
    let records = page.managedTasks.map { ($0, true) } + page.externalTasks.map { ($0, false) }

    return try records.map { record, isManagedTask in
      let identity = try buildTaskIdentity(
        record,
        projectTitle: page.title,
        seenTaskIDs: &seenTaskIDs,
        seenReminderExternalIdentifiers: &seenReminderExternalIdentifiers,
        seenCalendarEventExternalIdentifiers: &seenCalendarEventExternalIdentifiers
      )

      let task = RetainedTask(
        identity: identity,
        title: record.title,
        isCompleted: record.isCompleted,
        schedule: buildTaskSchedule(record),
        isManagedTask: isManagedTask
      )

      if let taskID = identity.taskID {
        tasksByID[taskID] = IndexedTask(
          projectID: projectID,
          task: task
        )
      }

      return task
    }
  }

  private static func buildTaskIdentity(
    _ record: LogseqProjectPageStore.TaskRecord,
    projectTitle: String,
    seenTaskIDs: inout Set<UUID>,
    seenReminderExternalIdentifiers: inout Set<String>,
    seenCalendarEventExternalIdentifiers: inout Set<String>
  ) throws -> RetainedTaskIdentity {
    let reminderExternalIdentifier = normalizedIdentifier(record.reminderExternalIdentifier)
    let calendarEventExternalIdentifier = normalizedIdentifier(record.calendarEventExternalIdentifier)

    let reminderDerivedTaskID = reminderExternalIdentifier.map(ReminderProjectionIdentity.taskID(for:))
    if let taskID = record.taskID,
       let reminderDerivedTaskID,
       taskID != reminderDerivedTaskID
    {
      throw Error.damagedTaskIdentity(projectTitle: projectTitle, taskTitle: record.title)
    }

    let taskID = reminderDerivedTaskID ?? record.taskID

    if taskID == nil && calendarEventExternalIdentifier != nil {
      throw Error.damagedTaskIdentity(projectTitle: projectTitle, taskTitle: record.title)
    }

    if let reminderExternalIdentifier {
      guard seenReminderExternalIdentifiers.insert(reminderExternalIdentifier).inserted else {
        throw Error.duplicateReminderExternalIdentifier(reminderExternalIdentifier)
      }
    }
    if let calendarEventExternalIdentifier {
      guard seenCalendarEventExternalIdentifiers.insert(calendarEventExternalIdentifier).inserted else {
        throw Error.duplicateCalendarEventExternalIdentifier(calendarEventExternalIdentifier)
      }
    }
    if let taskID {
      guard seenTaskIDs.insert(taskID).inserted else {
        throw Error.duplicateTaskID(taskID)
      }
    }

    return RetainedTaskIdentity(
      taskID: taskID,
      reminderExternalIdentifier: reminderExternalIdentifier,
      calendarEventExternalIdentifier: calendarEventExternalIdentifier
    )
  }

  private static func buildTaskSchedule(
    _ record: LogseqProjectPageStore.TaskRecord
  ) -> RetainedTaskSchedule {
    let decodedDate = LogseqReminderPropertyCodec.decodeDate(record.date)

    return RetainedTaskSchedule(
      rawDate: normalizedIdentifier(record.date),
      parsedDate: decodedDate?.date,
      hasExplicitTime: decodedDate?.hasExplicitTime ?? false,
      rawDuration: normalizedIdentifier(record.duration),
      durationMinutes: parsedDurationMinutes(record.duration),
      rawRepeatRule: normalizedIdentifier(record.repeatRule),
      canonicalRepeatRule: LogseqReminderPropertyCodec.decodeRepeat(record.repeatRule)
    )
  }

  private static func normalizedProjectBindings(
    _ bindings: [ProjectBinding]
  ) throws -> [ProjectBinding] {
    var bindingsByProjectID: [UUID: ProjectBinding] = [:]
    var bindingsByReminderListExternalIdentifier: [String: ProjectBinding] = [:]

    for binding in bindings {
      let normalized = ProjectBinding(
        projectID: binding.projectID,
        reminderListExternalIdentifier: try normalizedRequiredIdentifier(binding.reminderListExternalIdentifier)
      )

      if let existing = bindingsByProjectID[normalized.projectID], existing != normalized {
        throw Error.missingPageForProjectBinding(
          projectID: normalized.projectID,
          reminderListExternalIdentifier: normalized.reminderListExternalIdentifier
        )
      }
      if let existing = bindingsByReminderListExternalIdentifier[normalized.reminderListExternalIdentifier],
        existing != normalized
      {
        throw Error.duplicateReminderListExternalIdentifier(normalized.reminderListExternalIdentifier)
      }

      bindingsByProjectID[normalized.projectID] = normalized
      bindingsByReminderListExternalIdentifier[normalized.reminderListExternalIdentifier] = normalized
    }

    return bindingsByProjectID.values.sorted {
      $0.projectID.uuidString.localizedStandardCompare($1.projectID.uuidString) == .orderedAscending
    }
  }

  private static func firstTaskWithRetainedIdentity(
    in page: LogseqProjectPageStore.PageSnapshot
  ) -> LogseqProjectPageStore.TaskRecord? {
    let records = page.managedTasks + page.externalTasks
    return records.first {
      $0.taskID != nil
        || normalizedIdentifier($0.reminderExternalIdentifier) != nil
        || normalizedIdentifier($0.calendarEventExternalIdentifier) != nil
    }
  }

  private static func normalizedTaskBindings(
    _ bindings: [TaskBinding]
  ) throws -> [TaskBinding] {
    var bindingsByTaskID: [UUID: TaskBinding] = [:]
    var bindingsByReminderExternalIdentifier: [String: TaskBinding] = [:]
    var bindingsByCalendarEventExternalIdentifier: [String: TaskBinding] = [:]

    for binding in bindings {
      let normalized = TaskBinding(
        projectID: binding.projectID,
        taskID: binding.taskID,
        reminderExternalIdentifier: normalizedIdentifier(binding.reminderExternalIdentifier),
        calendarEventExternalIdentifier: normalizedIdentifier(binding.calendarEventExternalIdentifier)
      )

      if let existing = bindingsByTaskID[normalized.taskID], existing != normalized {
        throw Error.orphanTaskBinding(taskID: normalized.taskID)
      }
      if let reminderExternalIdentifier = normalized.reminderExternalIdentifier,
        let existing = bindingsByReminderExternalIdentifier[reminderExternalIdentifier],
        existing != normalized
      {
        throw Error.duplicateReminderExternalIdentifier(reminderExternalIdentifier)
      }
      if let calendarEventExternalIdentifier = normalized.calendarEventExternalIdentifier,
        let existing = bindingsByCalendarEventExternalIdentifier[calendarEventExternalIdentifier],
        existing != normalized
      {
        throw Error.duplicateCalendarEventExternalIdentifier(calendarEventExternalIdentifier)
      }

      bindingsByTaskID[normalized.taskID] = normalized
      if let reminderExternalIdentifier = normalized.reminderExternalIdentifier {
        bindingsByReminderExternalIdentifier[reminderExternalIdentifier] = normalized
      }
      if let calendarEventExternalIdentifier = normalized.calendarEventExternalIdentifier {
        bindingsByCalendarEventExternalIdentifier[calendarEventExternalIdentifier] = normalized
      }
    }

    return bindingsByTaskID.values.sorted {
      $0.taskID.uuidString.localizedStandardCompare($1.taskID.uuidString) == .orderedAscending
    }
  }

  private static func parsedDurationMinutes(_ rawValue: String?) -> Int? {
    guard let rawValue = normalizedIdentifier(rawValue), let minutes = Int(rawValue), minutes > 0 else {
      return nil
    }
    return minutes
  }

  private static func pageSort(
    lhs: LogseqProjectPageStore.PageSnapshot,
    rhs: LogseqProjectPageStore.PageSnapshot
  ) -> Bool {
    let titleCompare = lhs.title.localizedStandardCompare(rhs.title)
    if titleCompare != .orderedSame {
      return titleCompare == .orderedAscending
    }
    return lhs.fileURL.lastPathComponent.localizedStandardCompare(rhs.fileURL.lastPathComponent)
      == .orderedAscending
  }

  private static func normalizedRequiredIdentifier(_ value: String) throws -> String {
    guard let normalized = normalizedIdentifier(value) else {
      throw Error.damagedProjectIdentity(pageTitle: value)
    }
    return normalized
  }

  private static func isConsistentProjectIdentity(
    projectID: UUID,
    reminderListExternalIdentifier: String?
  ) -> Bool {
    guard let reminderListExternalIdentifier else { return true }
    return projectID == derivedProjectID(for: reminderListExternalIdentifier)
  }

  private static func resolvedProjectID(
    from page: LogseqProjectPageStore.PageSnapshot,
    reminderListExternalIdentifier: String?
  ) throws -> UUID? {
    if let projectID = page.projectID {
      guard isConsistentProjectIdentity(
        projectID: projectID,
        reminderListExternalIdentifier: reminderListExternalIdentifier
      ) else {
        throw Error.conflictingProjectIdentity(pageTitle: page.title)
      }
      return projectID
    }
    return reminderListExternalIdentifier.map(derivedProjectID(for:))
  }

  static func derivedProjectID(for reminderListExternalIdentifier: String) -> UUID {
    deterministicUUID(namespace: "reminder-project", key: reminderListExternalIdentifier)
  }

  private static func deterministicUUID(namespace: String, key: String) -> UUID {
    let digest = SHA256.hash(data: Data("\(namespace)|\(key)".utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
