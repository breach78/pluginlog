import Foundation

enum AppOwnedReminderBackupReason: String, Codable, Equatable, Sendable {
  case bootstrap
  case manual
  case eventStoreChanged
  case migration

  init(syncReason: SyncReason) {
    switch syncReason {
    case .bootstrap:
      self = .bootstrap
    case .manual:
      self = .manual
    case .eventStoreChanged:
      self = .eventStoreChanged
    case .periodic:
      self = .migration
    }
  }
}

struct AppOwnedReminderBackupSnapshot: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let reason: AppOwnedReminderBackupReason
  let createdAt: Date
  let batch: ReminderImportSnapshotBatch
}

struct AppOwnedReminderBackupStore {
  let containerRootURL: URL
  let fileManager: FileManager

  init(containerRootURL: URL, fileManager: FileManager = .default) {
    self.containerRootURL = containerRootURL.standardizedFileURL
    self.fileManager = fileManager
  }

  var backupsRootURL: URL {
    containerRootURL
      .appendingPathComponent("backups", isDirectory: true)
      .appendingPathComponent("reminders", isDirectory: true)
  }

  @discardableResult
  func savePreMigrationSnapshot(
    _ batch: ReminderImportSnapshotBatch,
    reason: AppOwnedReminderBackupReason,
    createdAt: Date = .now
  ) throws -> URL {
    try fileManager.createDirectory(at: backupsRootURL, withIntermediateDirectories: true)
    let snapshot = AppOwnedReminderBackupSnapshot(
      schemaVersion: 1,
      reason: reason,
      createdAt: createdAt,
      batch: batch
    )
    let url = backupsRootURL.appendingPathComponent(
      "pre-migration-\(timestampString(createdAt))-\(UUID().uuidString).json",
      isDirectory: false
    )
    try Self.encoder.encode(snapshot).write(to: url, options: .atomic)
    return url
  }

  func loadSnapshot(at url: URL) throws -> AppOwnedReminderBackupSnapshot {
    let data = try Data(contentsOf: url)
    return try Self.decoder.decode(AppOwnedReminderBackupSnapshot.self, from: data)
  }

  private func timestampString(_ date: Date) -> String {
    Self.timestampFormatter.string(from: date)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()
}
