import Foundation
import SwiftData

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

  var boardStage: BoardStage {
    BoardStage(rawValue: boardStageRaw ?? "") ?? .now
  }

  var importance: ImportanceLevel {
    ImportanceLevel(rawValue: importanceRaw ?? "") ?? .minor
  }
}

struct TaskIdentityBridgeRecord: Codable, Equatable {
  var taskID: UUID
  var reminderExternalIdentifier: String
  var ownerProjectID: UUID
  var createdAt: Date
  var updatedAt: Date
}

private struct TaskIdentityBridgePayload: Codable, Equatable {
  var records: [TaskIdentityBridgeRecord]

  static let empty = TaskIdentityBridgePayload(records: [])
}

private struct TaskIdentityBridgeFileStore {
  let fileURL: URL

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  private static let decoder = JSONDecoder()

  func load(fileManager: FileManager = .default) -> TaskIdentityBridgePayload? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }
    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }
    return try? Self.decoder.decode(TaskIdentityBridgePayload.self, from: data)
  }

  func save(
    _ payload: TaskIdentityBridgePayload,
    fileManager: FileManager = .default
  ) throws {
    let parentURL = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: parentURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let data = try Self.encoder.encode(payload)
    try data.write(to: fileURL, options: .atomic)
  }
}

enum TaskIdentityBridgeStore {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var fileStore: TaskIdentityBridgeFileStore?
  private nonisolated(unsafe) static var recordsByTaskID: [UUID: TaskIdentityBridgeRecord] = [:]
  private nonisolated(unsafe) static var recordsByReminderExternalIdentifier:
    [String: TaskIdentityBridgeRecord] = [:]

  static func install(dataDirectory: URL?) {
    lock.lock()
    defer { lock.unlock() }

    if let dataDirectory {
      fileStore = TaskIdentityBridgeFileStore(
        fileURL: dataDirectory.appendingPathComponent(
          "task-identity-bridge.json",
          isDirectory: false
        )
      )
    } else {
      fileStore = nil
    }

    let payload = fileStore?.load() ?? .empty
    load(payload)
  }

  static func reset() {
    install(dataDirectory: nil)
  }

  static func seed(from runtimeSnapshot: OutlineProjectionRuntimeSnapshot?) {
    guard let runtimeSnapshot else { return }

    lock.lock()
    defer { lock.unlock() }

    var records = recordsByTaskID
    for project in runtimeSnapshot.projects {
      for entry in project.document.flatten() where entry.node.type.isTask {
        guard
          let reminderExternalIdentifier = normalized(entry.node.reminderExternalIdentifier)
        else {
          continue
        }

        let existing = records[entry.node.canonicalID]
        if entry.node.id != entry.node.canonicalID, existing != nil {
          continue
        }
        let record = TaskIdentityBridgeRecord(
          taskID: entry.node.canonicalID,
          reminderExternalIdentifier: reminderExternalIdentifier,
          ownerProjectID: project.id,
          createdAt: existing?.createdAt ?? .now,
          updatedAt: .now
        )
        records[entry.node.canonicalID] = record
      }
    }

    store(records)
  }

  static func reminderExternalIdentifier(for taskID: UUID) -> String? {
    record(for: taskID)?.reminderExternalIdentifier
  }

  static func taskID(for reminderExternalIdentifier: String) -> UUID? {
    lock.lock()
    defer { lock.unlock() }
    return recordsByReminderExternalIdentifier[reminderExternalIdentifier]?.taskID
  }

  static func record(for taskID: UUID) -> TaskIdentityBridgeRecord? {
    lock.lock()
    defer { lock.unlock() }
    return recordsByTaskID[taskID]
  }

  static func upsert(
    taskID: UUID,
    reminderExternalIdentifier: String,
    ownerProjectID: UUID
  ) {
    guard let reminderExternalIdentifier = normalized(reminderExternalIdentifier) else { return }

    lock.lock()
    defer { lock.unlock() }

    var records = recordsByTaskID
    let existing = records[taskID]
    records[taskID] = TaskIdentityBridgeRecord(
      taskID: taskID,
      reminderExternalIdentifier: reminderExternalIdentifier,
      ownerProjectID: ownerProjectID,
      createdAt: existing?.createdAt ?? .now,
      updatedAt: .now
    )
    store(records)
  }

  static func remove(taskID: UUID) {
    lock.lock()
    defer { lock.unlock() }

    var records = recordsByTaskID
    records.removeValue(forKey: taskID)
    store(records)
  }

  static func remove(reminderExternalIdentifier: String) {
    guard let reminderExternalIdentifier = normalized(reminderExternalIdentifier) else { return }

    lock.lock()
    defer { lock.unlock() }

    let records = Dictionary(
      uniqueKeysWithValues: recordsByTaskID.filter {
        $0.value.reminderExternalIdentifier != reminderExternalIdentifier
      }
    )
    store(records)
  }

  private static func load(_ payload: TaskIdentityBridgePayload) {
    let uniqueRecords = payload.records.reduce(into: [UUID: TaskIdentityBridgeRecord]()) {
      partialResult,
      record in
      partialResult[record.taskID] = record
    }
    recordsByTaskID = uniqueRecords
    recordsByReminderExternalIdentifier = uniqueRecords.reduce(
      into: [String: TaskIdentityBridgeRecord]()
    ) { partialResult, pair in
      partialResult[pair.value.reminderExternalIdentifier] = pair.value
    }
  }

  private static func store(_ recordsByTaskID: [UUID: TaskIdentityBridgeRecord]) {
    self.recordsByTaskID = recordsByTaskID
    recordsByReminderExternalIdentifier = recordsByTaskID.reduce(
      into: [String: TaskIdentityBridgeRecord]()
    ) { partialResult, pair in
      partialResult[pair.value.reminderExternalIdentifier] = pair.value
    }

    let payload = TaskIdentityBridgePayload(
      records: recordsByTaskID.values.sorted { lhs, rhs in
        lhs.taskID.uuidString < rhs.taskID.uuidString
      }
    )
    try? fileStore?.save(payload)
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

private struct ProjectIdentityRuntimeTaskProjection {
  let taskID: UUID
  let ownerProjectID: UUID
  let ownerCalendarIdentifier: String?
  let title: String
  let reminderNoteText: String
  let isCompleted: Bool
  let reminderExternalIdentifier: String?
  let reminderMetadata: ReminderMetadataSnapshot?
  let featureSidecar: ReminderTaskFeatureSidecarRecord?
  let localUpdatedAt: Date
  let createdAt: Date
}

enum ProjectIdentityResolver {
  static func projectID(for taskID: UUID, in snapshot: OutlineProjectionRuntimeSnapshot?) -> UUID? {
    runtimeTaskProjection(for: taskID, in: snapshot)?.ownerProjectID
  }

  static func taskTitle(for taskID: UUID, in snapshot: OutlineProjectionRuntimeSnapshot?) -> String? {
    runtimeTaskProjection(for: taskID, in: snapshot)?.title
  }

  static func taskExists(_ taskID: UUID, in snapshot: OutlineProjectionRuntimeSnapshot?) -> Bool {
    runtimeTaskProjection(for: taskID, in: snapshot) != nil
  }

  @MainActor
  static func ownerProjectID(
    forTaskID taskID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    reminderGateway: ReminderGateway,
    context: ModelContext,
    dataDirectory: URL?
  ) -> UUID? {
    taskRecord(
      forTaskID: taskID,
      runtimeSnapshot: runtimeSnapshot,
      reminderGateway: reminderGateway,
      context: context,
      dataDirectory: dataDirectory
    )?.reminderOwnerProjectID
  }

  @MainActor
  static func taskRecord(
    forTaskID taskID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    reminderGateway: ReminderGateway,
    context: ModelContext,
    dataDirectory: URL?
  ) -> ProjectIdentityTaskRecord? {
    _ = reminderGateway
    _ = context
    _ = dataDirectory

    if let projection = runtimeTaskProjection(for: taskID, in: runtimeSnapshot) {
      if let reminderExternalIdentifier = projection.reminderExternalIdentifier {
        TaskIdentityBridgeStore.upsert(
          taskID: taskID,
          reminderExternalIdentifier: reminderExternalIdentifier,
          ownerProjectID: projection.ownerProjectID
        )
      }

      return buildProjectionTaskRecord(projection)
    }

    return nil
  }

  @MainActor
  static func projectNoteMarkdown(
    forProjectID projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    context: ModelContext
  ) -> String? {
    _ = context
    if let record = runtimeProjectRecord(forProjectID: projectID, in: runtimeSnapshot) {
      return record.projectNoteMarkdown
    }
    return nil
  }

  @MainActor
  static func projectTitle(
    forProjectID projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    reminderGateway: ReminderGateway,
    dataDirectory: URL?,
    context: ModelContext
  ) -> String {
    _ = dataDirectory
    _ = context
    _ = reminderGateway
    if let record = runtimeProjectRecord(forProjectID: projectID, in: runtimeSnapshot) {
      return record.title
    }
    return OutlinerProject.defaultTitle
  }

  @MainActor
  static func isActiveProject(
    _ projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    reminderGateway: ReminderGateway,
    dataDirectory: URL?,
    context: ModelContext
  ) -> Bool {
    _ = dataDirectory
    _ = context
    _ = reminderGateway
    return runtimeProjectRecord(forProjectID: projectID, in: runtimeSnapshot) != nil
  }

  private static func runtimeTaskProjection(
    for taskID: UUID,
    in snapshot: OutlineProjectionRuntimeSnapshot?
  ) -> ProjectIdentityRuntimeTaskProjection? {
    guard let snapshot else { return nil }

    if let projection = directRuntimeTaskProjection(for: taskID, in: snapshot) {
      return projection
    }

    guard
      let reminderExternalIdentifier = TaskIdentityBridgeStore.record(for: taskID)?
        .reminderExternalIdentifier,
      let bridgedProjection = runtimeTaskProjection(
        forReminderExternalIdentifier: reminderExternalIdentifier,
        requestedTaskID: taskID,
        in: snapshot
      )
    else {
      return nil
    }

    return bridgedProjection
  }

  private static func directRuntimeTaskProjection(
    for taskID: UUID,
    in snapshot: OutlineProjectionRuntimeSnapshot
  ) -> ProjectIdentityRuntimeTaskProjection? {
    var fallbackProjection: ProjectIdentityRuntimeTaskProjection?
    for project in snapshot.projects {
      for entry in project.document.flatten() where entry.node.type.isTask && entry.node.canonicalID == taskID {
        let projection = runtimeTaskProjection(
          for: entry.node,
          ownerProjectID: project.id,
          requestedTaskID: taskID,
          in: snapshot
        )
        if entry.node.id == entry.node.canonicalID {
          return projection
        }
        fallbackProjection = fallbackProjection ?? projection
      }
    }

    return fallbackProjection
  }

  private static func runtimeTaskProjection(
    forReminderExternalIdentifier reminderExternalIdentifier: String,
    requestedTaskID: UUID,
    in snapshot: OutlineProjectionRuntimeSnapshot
  ) -> ProjectIdentityRuntimeTaskProjection? {
    let normalizedReminderExternalIdentifier = normalized(reminderExternalIdentifier)
    guard let normalizedReminderExternalIdentifier else { return nil }

    var fallbackProjection: ProjectIdentityRuntimeTaskProjection?
    for project in snapshot.projects {
      for entry in project.document.flatten() where entry.node.type.isTask {
        guard normalized(entry.node.reminderExternalIdentifier) == normalizedReminderExternalIdentifier else {
          continue
        }
        let projection = runtimeTaskProjection(
          for: entry.node,
          ownerProjectID: project.id,
          requestedTaskID: requestedTaskID,
          in: snapshot
        )
        if entry.node.id == entry.node.canonicalID {
          return projection
        }
        fallbackProjection = fallbackProjection ?? projection
      }
    }

    return fallbackProjection
  }

  private static func runtimeTaskProjection(
    for node: OutlineNode,
    ownerProjectID: UUID,
    requestedTaskID: UUID,
    in snapshot: OutlineProjectionRuntimeSnapshot
  ) -> ProjectIdentityRuntimeTaskProjection {
    let reminderExternalIdentifier = normalized(node.reminderExternalIdentifier)
    let featureSidecar = reminderExternalIdentifier.flatMap {
      snapshot.taskFeatureSidecarByReminderExternalIdentifier[$0]
    }
    let remoteModifiedAt = reminderExternalIdentifier.flatMap {
      snapshot.reminderModifiedAtByReminderExternalIdentifier[$0]
    }
    let localUpdatedAt = [featureSidecar?.updatedAt, remoteModifiedAt].compactMap { $0 }.max()
      ?? .distantPast
    let createdAt = featureSidecar?.createdAt ?? localUpdatedAt

    return ProjectIdentityRuntimeTaskProjection(
      taskID: requestedTaskID,
      ownerProjectID: ownerProjectID,
      ownerCalendarIdentifier: snapshot.projectReminderListIdentifierByProjectID[ownerProjectID],
      title: node.text,
      reminderNoteText: ReminderNoteSourceMutationService.plan(for: node) {
        $0.reminderExternalIdentifier
      }.normalizedNoteText,
      isCompleted: node.type.isCompleted,
      reminderExternalIdentifier: reminderExternalIdentifier,
      reminderMetadata: snapshot.reminderMetadata(for: node),
      featureSidecar: featureSidecar,
      localUpdatedAt: localUpdatedAt,
      createdAt: createdAt
    )
  }

  private static func runtimeProjectRecord(
    forProjectID projectID: UUID,
    in snapshot: OutlineProjectionRuntimeSnapshot?
  ) -> WorkspaceProjectRuntimeRecord? {
    WorkspaceProjectRuntimeRecordBuilder.records(
      from: snapshot,
      projectIDs: [projectID]
    )[projectID]
  }

  private static func buildProjectionTaskRecord(
    _ projection: ProjectIdentityRuntimeTaskProjection
  ) -> ProjectIdentityTaskRecord {
    ProjectIdentityTaskRecord(
      id: projection.taskID,
      title: projection.title,
      reminderNoteText: projection.reminderNoteText,
      reminderExternalIdentifier: normalized(projection.reminderExternalIdentifier),
      reminderOwnerProjectID: projection.ownerProjectID,
      reminderOwnerCalendarID: normalized(projection.ownerCalendarIdentifier),
      isCompleted: projection.isCompleted,
      completionDate: projection.reminderMetadata?.completionDate,
      startDate: nil,
      dueDate: projection.reminderMetadata?.dueDate,
      scheduleHasExplicitTime: projection.reminderMetadata?.hasExplicitTime ?? false,
      scheduledDurationMinutes: projection.featureSidecar?.scheduledDurationMinutes,
      priority: max(0, min(9, projection.reminderMetadata?.priority ?? 0)),
      recurrenceRuleRaw: OutlinerIntegratedStore.encodeRecurrence(
        projection.reminderMetadata?.recurrence
      ),
      isFlagged: projection.featureSidecar?.isFlagged ?? false,
      boardStageRaw: projection.featureSidecar?.boardStageRaw,
      importanceRaw: projection.featureSidecar?.importanceRaw,
      requiredWorkDays: projection.featureSidecar?.requiredWorkDays ?? 0,
      completedWorkUnits: projection.featureSidecar?.completedWorkUnits ?? 0,
      completedWorkUnitDatesRaw: projection.featureSidecar?.completedWorkUnitDatesRaw ?? "",
      preparationScheduleOverridesRaw: projection.featureSidecar?.preparationScheduleOverridesRaw
        ?? "",
      localUpdatedAt: projection.localUpdatedAt,
      createdAt: projection.createdAt
    )
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
