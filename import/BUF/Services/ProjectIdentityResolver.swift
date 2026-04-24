import Foundation

struct ProjectIdentityTaskRecord: Equatable {
  let id: UUID
  let title: String
  let reminderNoteText: String
  let reminderExternalIdentifier: String?
  let reminderOwnerProjectID: UUID?
  let reminderOwnerCalendarID: String?
  let isCompleted: Bool
  let completionDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let scheduleHasExplicitTime: Bool
  let scheduledDurationMinutes: Int?
  let priority: Int
  let recurrenceRuleRaw: String?
  let isFlagged: Bool
  let boardStageRaw: String?
  let importanceRaw: String?
  let requiredWorkDays: Int
  let completedWorkUnits: Int
  let completedWorkUnitDatesRaw: String
  let preparationScheduleOverridesRaw: String
  let localUpdatedAt: Date
  let createdAt: Date
}

struct TaskIdentityBridgeRecord: Codable, Equatable {
  var taskID: UUID
  var title: String
  var reminderExternalIdentifier: String?
  var ownerProjectID: UUID
  var createdAt: Date
  var updatedAt: Date
}

struct ProjectIdentityBridgeRecord: Codable, Equatable {
  var projectID: UUID
  var title: String
  var reminderListExternalIdentifier: String?
  var createdAt: Date
  var updatedAt: Date
}

private struct TaskIdentityBridgePayload: Codable, Equatable {
  var projects: [ProjectIdentityBridgeRecord]
  var tasks: [TaskIdentityBridgeRecord]

  static let empty = TaskIdentityBridgePayload(projects: [], tasks: [])
}

enum TaskIdentityBridgeStore {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var fileURL: URL?
  private nonisolated(unsafe) static var projectsByID: [UUID: ProjectIdentityBridgeRecord] = [:]
  private nonisolated(unsafe) static var tasksByID: [UUID: TaskIdentityBridgeRecord] = [:]

  static func install(dataDirectory: URL?) {
    lock.lock()
    defer { lock.unlock() }
    fileURL = dataDirectory?.appendingPathComponent("retained-identity-bridge.json")
    load()
  }

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    fileURL = nil
    projectsByID = [:]
    tasksByID = [:]
  }

  static func upsertProject(
    projectID: UUID,
    title: String,
    reminderListExternalIdentifier: String?
  ) {
    lock.lock()
    projectsByID[projectID] = ProjectIdentityBridgeRecord(
      projectID: projectID,
      title: title,
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      createdAt: projectsByID[projectID]?.createdAt ?? .now,
      updatedAt: .now
    )
    persistLocked()
    lock.unlock()
  }

  static func upsertTask(
    taskID: UUID,
    title: String,
    reminderExternalIdentifier: String?,
    ownerProjectID: UUID
  ) {
    lock.lock()
    tasksByID[taskID] = TaskIdentityBridgeRecord(
      taskID: taskID,
      title: title,
      reminderExternalIdentifier: reminderExternalIdentifier,
      ownerProjectID: ownerProjectID,
      createdAt: tasksByID[taskID]?.createdAt ?? .now,
      updatedAt: .now
    )
    persistLocked()
    lock.unlock()
  }

  static func replaceAll(
    projects: [ProjectIdentityBridgeRecord],
    tasks: [TaskIdentityBridgeRecord]
  ) {
    lock.lock()
    let existingProjects = projectsByID
    let existingTasks = tasksByID
    projectsByID = Dictionary(
      uniqueKeysWithValues: projects.map { record in
        var next = record
        next.createdAt = existingProjects[record.projectID]?.createdAt ?? record.createdAt
        return (record.projectID, next)
      }
    )
    tasksByID = Dictionary(
      uniqueKeysWithValues: tasks.map { record in
        var next = record
        next.createdAt = existingTasks[record.taskID]?.createdAt ?? record.createdAt
        return (record.taskID, next)
      }
    )
    persistLocked()
    lock.unlock()
  }

  static func projectID(for taskID: UUID) -> UUID? {
    lock.lock()
    defer { lock.unlock() }
    return tasksByID[taskID]?.ownerProjectID
  }

  static func projectTitle(for projectID: UUID) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return projectsByID[projectID]?.title
  }

  static func projectRecords() -> [ProjectIdentityBridgeRecord] {
    lock.lock()
    defer { lock.unlock() }
    return Array(projectsByID.values)
  }

  static func projectIDs() -> Set<UUID> {
    lock.lock()
    defer { lock.unlock() }
    return Set(projectsByID.keys)
  }

  static func taskRecord(for taskID: UUID) -> ProjectIdentityTaskRecord? {
    lock.lock()
    defer { lock.unlock() }
    guard let record = tasksByID[taskID] else { return nil }
    return ProjectIdentityTaskRecord(
      id: record.taskID,
      title: record.title,
      reminderNoteText: "",
      reminderExternalIdentifier: record.reminderExternalIdentifier,
      reminderOwnerProjectID: record.ownerProjectID,
      reminderOwnerCalendarID: nil,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: nil,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      boardStageRaw: nil,
      importanceRaw: nil,
      requiredWorkDays: 0,
      completedWorkUnits: 0,
      completedWorkUnitDatesRaw: "",
      preparationScheduleOverridesRaw: "",
      localUpdatedAt: record.updatedAt,
      createdAt: record.createdAt
    )
  }

  private static func load() {
    guard let fileURL,
      let data = try? Data(contentsOf: fileURL),
      let payload = try? JSONDecoder().decode(TaskIdentityBridgePayload.self, from: data)
    else {
      projectsByID = [:]
      tasksByID = [:]
      return
    }
    projectsByID = Dictionary(uniqueKeysWithValues: payload.projects.map { ($0.projectID, $0) })
    tasksByID = Dictionary(uniqueKeysWithValues: payload.tasks.map { ($0.taskID, $0) })
  }

  private static func persistLocked() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let payload = TaskIdentityBridgePayload(
        projects: Array(projectsByID.values),
        tasks: Array(tasksByID.values)
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(payload)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.sync.error(
        "retained identity bridge persist failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
