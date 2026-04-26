import Foundation

enum ProjectLifecycleIntent: String, Codable, Equatable, Sendable {
  case appDelete
  case remindersDelete
  case obsidianArchive
}

struct ProjectLifecycleRecord: Codable, Equatable, Sendable {
  var projectID: UUID
  var reminderListExternalIdentifier: String
  var noteVaultRelativePath: String?
  var intent: ProjectLifecycleIntent
  var startedAt: Date
  var completedAt: Date?
}

struct ProjectLifecycleStore {
  private struct Payload: Codable, Equatable {
    var schemaVersion: Int
    var records: [ProjectLifecycleRecord]

    static let currentSchemaVersion = 1
    static let empty = Payload(schemaVersion: currentSchemaVersion, records: [])
  }

  private let vaultRootURL: URL
  private let fileManager: FileManager

  init(vaultRootURL: URL, fileManager: FileManager = .default) {
    self.vaultRootURL = vaultRootURL.standardizedFileURL
    self.fileManager = fileManager
  }

  func record(forListIdentifier listIdentifier: String) throws -> ProjectLifecycleRecord? {
    guard let key = normalized(listIdentifier) else { return nil }
    return try loadPayload().records.first {
      normalized($0.reminderListExternalIdentifier) == key
    }
  }

  func shouldSkipImport(forListIdentifier listIdentifier: String) throws -> Bool {
    guard let record = try record(forListIdentifier: listIdentifier) else { return false }
    switch record.intent {
    case .appDelete, .obsidianArchive:
      return true
    case .remindersDelete:
      return false
    }
  }

  func shouldSuppressMissingReminderListDeletion(forListIdentifier listIdentifier: String) throws -> Bool {
    guard let record = try record(forListIdentifier: listIdentifier) else { return false }
    return record.intent == .obsidianArchive
  }

  func recordStarted(
    intent: ProjectLifecycleIntent,
    projectID: UUID,
    reminderListExternalIdentifier: String,
    noteVaultRelativePath: String?,
    at date: Date
  ) throws {
    guard let key = normalized(reminderListExternalIdentifier) else { return }
    var payload = try loadPayload()
    payload.schemaVersion = Payload.currentSchemaVersion
    payload.records.removeAll {
      normalized($0.reminderListExternalIdentifier) == key
    }
    payload.records.append(
      ProjectLifecycleRecord(
        projectID: projectID,
        reminderListExternalIdentifier: key,
        noteVaultRelativePath: noteVaultRelativePath,
        intent: intent,
        startedAt: date,
        completedAt: nil
      )
    )
    try writePayload(payload)
  }

  func markCompleted(
    projectID: UUID,
    reminderListExternalIdentifier: String,
    at date: Date
  ) throws {
    guard let key = normalized(reminderListExternalIdentifier) else { return }
    var payload = try loadPayload()
    guard let index = payload.records.firstIndex(where: {
      $0.projectID == projectID && normalized($0.reminderListExternalIdentifier) == key
    }) else {
      return
    }
    payload.records[index].completedAt = date
    try writePayload(payload)
  }

  private func loadPayload() throws -> Payload {
    let url = stateFileURL
    guard fileManager.fileExists(atPath: url.path) else { return .empty }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty else { return .empty }
    let payload = try JSONDecoder().decode(Payload.self, from: data)
    guard payload.schemaVersion == Payload.currentSchemaVersion else { return .empty }
    return payload
  }

  private func writePayload(_ payload: Payload) throws {
    try fileManager.createDirectory(
      at: stateFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let records = payload.records.sorted {
      $0.reminderListExternalIdentifier.localizedStandardCompare(
        $1.reminderListExternalIdentifier
      ) == .orderedAscending
    }
    let data = try encoder.encode(
      Payload(schemaVersion: Payload.currentSchemaVersion, records: records)
    )
    try data.write(to: stateFileURL, options: .atomic)
  }

  private var stateFileURL: URL {
    ObsidianVaultLayout(vaultRootURL: vaultRootURL, fileManager: fileManager)
      .sidecarRootURL
      .appendingPathComponent("project-lifecycle.json", isDirectory: false)
  }

  private func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
