import CryptoKit
import Foundation
import SQLite3

struct TaskMirrorPlacementRecord: Identifiable, Codable, Equatable, Hashable {
  var id: UUID
  var reminderExternalIdentifier: String
  var targetReminderListExternalIdentifier: String
  var normalizedParentReminderExternalIdentifier: String?
  var rowOrder: Int
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID? = nil,
    reminderExternalIdentifier: String,
    targetReminderListExternalIdentifier: String,
    normalizedParentReminderExternalIdentifier: String? = nil,
    rowOrder: Int,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    let normalizedReminderExternalIdentifier =
      ReminderProjectionIdentity.normalized(reminderExternalIdentifier) ?? reminderExternalIdentifier
    let normalizedTargetReminderListExternalIdentifier =
      ReminderProjectionIdentity.normalized(targetReminderListExternalIdentifier)
      ?? targetReminderListExternalIdentifier
    let normalizedParentReminderExternalIdentifier =
      ReminderProjectionIdentity.normalized(normalizedParentReminderExternalIdentifier)

    self.id =
      id
      ?? Self.deterministicID(
        reminderExternalIdentifier: normalizedReminderExternalIdentifier,
        targetReminderListExternalIdentifier: normalizedTargetReminderListExternalIdentifier,
        normalizedParentReminderExternalIdentifier: normalizedParentReminderExternalIdentifier
      )
    self.reminderExternalIdentifier = normalizedReminderExternalIdentifier
    self.targetReminderListExternalIdentifier = normalizedTargetReminderListExternalIdentifier
    self.normalizedParentReminderExternalIdentifier = normalizedParentReminderExternalIdentifier
    self.rowOrder = rowOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  var targetProjectID: UUID {
    ReminderProjectionIdentity.projectID(for: targetReminderListExternalIdentifier)
  }

  static func deterministicID(
    reminderExternalIdentifier: String,
    targetReminderListExternalIdentifier: String,
    normalizedParentReminderExternalIdentifier: String? = nil
  ) -> UUID {
    let normalizedParentReminderExternalIdentifier =
      ReminderProjectionIdentity.normalized(normalizedParentReminderExternalIdentifier) ?? "root"
    return deterministicUUID(
      namespace: "task-mirror-placement",
      key:
        "\(reminderExternalIdentifier)|\(targetReminderListExternalIdentifier)|\(normalizedParentReminderExternalIdentifier)"
    )
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
}

actor TaskMirrorPlacementStore {
  private let databaseURL: URL
  private let fileManager: FileManager
  private var hasEnsuredSchema = false

  init(databaseURL: URL, fileManager: FileManager = .default) {
    self.databaseURL = databaseURL
    self.fileManager = fileManager
  }

  func allRecords() throws -> [TaskMirrorPlacementRecord] {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try ensureSchema()

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, reminder_external_identifier, target_reminder_list_external_identifier,
             normalized_parent_reminder_external_identifier, row_order, created_at, updated_at
      FROM task_project_clone_placements
      WHERE reminder_external_identifier IS NOT NULL
        AND reminder_external_identifier != ''
        AND target_reminder_list_external_identifier IS NOT NULL
        AND target_reminder_list_external_identifier != ''
      ORDER BY target_reminder_list_external_identifier ASC, row_order ASC, created_at ASC;
      """,
      in: db,
      statement: &statement
    )

    var records: [TaskMirrorPlacementRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      records.append(try Self.decodeRecord(from: statement))
    }
    return records
  }

  func records(
    for reminderExternalIdentifier: String
  ) throws -> [TaskMirrorPlacementRecord] {
    let normalizedReminderExternalIdentifier =
      ReminderProjectionIdentity.normalized(reminderExternalIdentifier)
    guard let normalizedReminderExternalIdentifier else { return [] }

    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try ensureSchema()

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, reminder_external_identifier, target_reminder_list_external_identifier,
             normalized_parent_reminder_external_identifier, row_order, created_at, updated_at
      FROM task_project_clone_placements
      WHERE reminder_external_identifier = ?1
      ORDER BY row_order ASC, created_at ASC;
      """,
      in: db,
      statement: &statement
    )
    try bind(normalizedReminderExternalIdentifier, at: 1, to: statement)

    var records: [TaskMirrorPlacementRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      records.append(try Self.decodeRecord(from: statement))
    }
    return records
  }

  func records(
    targetReminderListExternalIdentifier: String
  ) throws -> [TaskMirrorPlacementRecord] {
    let normalizedTargetReminderListExternalIdentifier =
      ReminderProjectionIdentity.normalized(targetReminderListExternalIdentifier)
    guard let normalizedTargetReminderListExternalIdentifier else { return [] }

    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try ensureSchema()

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, reminder_external_identifier, target_reminder_list_external_identifier,
             normalized_parent_reminder_external_identifier, row_order, created_at, updated_at
      FROM task_project_clone_placements
      WHERE target_reminder_list_external_identifier = ?1
      ORDER BY row_order ASC, created_at ASC;
      """,
      in: db,
      statement: &statement
    )
    try bind(normalizedTargetReminderListExternalIdentifier, at: 1, to: statement)

    var records: [TaskMirrorPlacementRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      records.append(try Self.decodeRecord(from: statement))
    }
    return records
  }

  func upsert(
    reminderExternalIdentifier: String,
    targetReminderListExternalIdentifier: String,
    normalizedParentReminderExternalIdentifier: String? = nil,
    rowOrder: Int,
    now: Date = .now
  ) throws -> TaskMirrorPlacementRecord? {
    guard
      let normalizedReminderExternalIdentifier = ReminderProjectionIdentity.normalized(
        reminderExternalIdentifier),
      let normalizedTargetReminderListExternalIdentifier = ReminderProjectionIdentity.normalized(
        targetReminderListExternalIdentifier)
    else {
      return nil
    }

    let existing =
      try records(
        targetReminderListExternalIdentifier: normalizedTargetReminderListExternalIdentifier
      ).first {
        $0.reminderExternalIdentifier == normalizedReminderExternalIdentifier
          && $0.normalizedParentReminderExternalIdentifier
            == ReminderProjectionIdentity.normalized(normalizedParentReminderExternalIdentifier)
      }
    let record = TaskMirrorPlacementRecord(
      id: existing?.id,
      reminderExternalIdentifier: normalizedReminderExternalIdentifier,
      targetReminderListExternalIdentifier: normalizedTargetReminderListExternalIdentifier,
      normalizedParentReminderExternalIdentifier: normalizedParentReminderExternalIdentifier,
      rowOrder: max(0, rowOrder),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now
    )

    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try ensureSchema()

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      INSERT INTO task_project_clone_placements(
        id, task_id, project_id, parent_task_id, reminder_external_identifier,
        target_reminder_list_external_identifier, normalized_parent_reminder_external_identifier,
        row_order, created_at, updated_at
      ) VALUES (?1, '', '', NULL, ?2, ?3, ?4, ?5, ?6, ?7)
      ON CONFLICT(id) DO UPDATE SET
        reminder_external_identifier = excluded.reminder_external_identifier,
        target_reminder_list_external_identifier = excluded.target_reminder_list_external_identifier,
        normalized_parent_reminder_external_identifier = excluded.normalized_parent_reminder_external_identifier,
        row_order = excluded.row_order,
        updated_at = excluded.updated_at;
      """,
      in: db,
      statement: &statement
    )
    try bind(record.id.uuidString, at: 1, to: statement)
    try bind(record.reminderExternalIdentifier, at: 2, to: statement)
    try bind(record.targetReminderListExternalIdentifier, at: 3, to: statement)
    try bind(record.normalizedParentReminderExternalIdentifier, at: 4, to: statement)
    try bind(record.rowOrder, at: 5, to: statement)
    try bind(record.createdAt, at: 6, to: statement)
    try bind(record.updatedAt, at: 7, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }

    return record
  }

  @discardableResult
  func remove(
    reminderExternalIdentifier: String,
    targetReminderListExternalIdentifier: String
  ) throws -> Bool {
    guard
      let normalizedReminderExternalIdentifier = ReminderProjectionIdentity.normalized(
        reminderExternalIdentifier),
      let normalizedTargetReminderListExternalIdentifier = ReminderProjectionIdentity.normalized(
        targetReminderListExternalIdentifier)
    else {
      return false
    }

    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try ensureSchema()

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      DELETE FROM task_project_clone_placements
      WHERE reminder_external_identifier = ?1
        AND target_reminder_list_external_identifier = ?2;
      """,
      in: db,
      statement: &statement
    )
    try bind(normalizedReminderExternalIdentifier, at: 1, to: statement)
    try bind(normalizedTargetReminderListExternalIdentifier, at: 2, to: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }
    return sqlite3_changes(db) > 0
  }

  func removeAll(
    reminderExternalIdentifiers: some Sequence<String>
  ) throws {
    let normalizedReminderExternalIdentifiers = Array(
      Set(reminderExternalIdentifiers.compactMap(ReminderProjectionIdentity.normalized))
    ).sorted()
    guard !normalizedReminderExternalIdentifiers.isEmpty else { return }

    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try ensureSchema()

    try execute(
      """
      DELETE FROM task_project_clone_placements
      WHERE reminder_external_identifier IN (\(Self.quotedTextList(normalizedReminderExternalIdentifiers)));
      """,
      in: db
    )
  }

  func nextRootRowOrder(
    in targetReminderListExternalIdentifier: String
  ) throws -> Int {
    let existingRecords = try records(
      targetReminderListExternalIdentifier: targetReminderListExternalIdentifier
    )
    return (existingRecords.map(\.rowOrder).max() ?? -1) + 1
  }

  private func ensureSchema() throws {
    guard !hasEnsuredSchema else { return }
    try NormalizedRuntimeReadSchema.ensureInstalled(at: databaseURL, fileManager: fileManager)
    hasEnsuredSchema = true
  }

  private func openDatabase() throws -> OpaquePointer? {
    try openNormalizedSQLiteConnection(
      at: databaseURL,
      fileManager: fileManager
    )
  }

  private func execute(_ sql: String, in db: OpaquePointer?) throws {
    var errorPointer: UnsafeMutablePointer<Int8>?
    guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
      let message = errorPointer.map { String(cString: $0) } ?? Self.sqliteMessage(db)
      sqlite3_free(errorPointer)
      throw NormalizedPersistenceError.sqliteExecFailed(message)
    }
  }

  private func prepare(_ sql: String, in db: OpaquePointer?, statement: inout OpaquePointer?)
    throws
  {
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqlitePrepareFailed(Self.sqliteMessage(db))
    }
  }

  private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer?) throws {
    if let value {
      guard sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient) == SQLITE_OK else {
        throw NormalizedPersistenceError.sqliteStepFailed("bind text failed")
      }
    } else {
      guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
        throw NormalizedPersistenceError.sqliteStepFailed("bind null failed")
      }
    }
  }

  private func bind(_ value: Int, at index: Int32, to statement: OpaquePointer?) throws {
    guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed("bind int failed")
    }
  }

  private func bind(_ value: Date, at index: Int32, to statement: OpaquePointer?) throws {
    guard sqlite3_bind_double(statement, index, value.timeIntervalSince1970) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed("bind date failed")
    }
  }

  private static func decodeRecord(from statement: OpaquePointer?) throws -> TaskMirrorPlacementRecord {
    guard
      let id = columnUUID(statement, index: 0),
      let reminderExternalIdentifier = columnText(statement, index: 1),
      let targetReminderListExternalIdentifier = columnText(statement, index: 2)
    else {
      throw NormalizedPersistenceError.metadataDecodeFailed
    }

    return TaskMirrorPlacementRecord(
      id: id,
      reminderExternalIdentifier: reminderExternalIdentifier,
      targetReminderListExternalIdentifier: targetReminderListExternalIdentifier,
      normalizedParentReminderExternalIdentifier: columnText(statement, index: 3),
      rowOrder: Int(sqlite3_column_int64(statement, 4)),
      createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
      updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
    )
  }

  private static func columnUUID(_ statement: OpaquePointer?, index: Int32) -> UUID? {
    guard let rawValue = columnText(statement, index: index) else { return nil }
    return UUID(uuidString: rawValue)
  }

  private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
  }

  private static func quotedTextList(_ values: [String]) -> String {
    values
      .map { $0.replacingOccurrences(of: "'", with: "''") }
      .map { "'\($0)'" }
      .joined(separator: ",")
  }

  private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  private static func sqliteMessage(_ db: OpaquePointer?) -> String {
    guard let db, let message = sqlite3_errmsg(db) else { return "unknown" }
    return String(cString: message)
  }
}
