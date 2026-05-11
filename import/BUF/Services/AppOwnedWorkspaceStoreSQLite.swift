import Foundation
import SQLite3

private let appOwnedSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension AppOwnedWorkspaceStore {
  enum Binding {
    case text(String)
    case optionalText(String?)
    case int(Int)
    case optionalInt(Int?)
    case double(Double)
    case optionalDouble(Double?)
  }

  func openDatabase() throws -> OpaquePointer {
    try fileManager.createDirectory(
      at: sqliteURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var db: OpaquePointer?
    guard sqlite3_open(sqliteURL.path, &db) == SQLITE_OK, let db else {
      let message = db.map(errorMessage) ?? "unknown"
      sqlite3_close(db)
      throw AppOwnedWorkspaceStoreError.openFailed(message)
    }
    sqlite3_busy_timeout(db, 5000)
    return db
  }

  func migrate(_ db: OpaquePointer) throws {
    try exec(db, "PRAGMA foreign_keys = ON;")
    if try schemaVersion(db) == "5" {
      return
    }
    try exec(
      db,
      """
      CREATE TABLE IF NOT EXISTS app_metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      );
      """
    )
    try exec(
      db,
      """
      CREATE TABLE IF NOT EXISTS app_projects (
        id TEXT PRIMARY KEY NOT NULL,
        reminder_list_identifier TEXT NOT NULL,
        reminder_list_external_identifier TEXT,
        title TEXT NOT NULL,
        color_hex TEXT,
        note_markdown TEXT NOT NULL DEFAULT '',
        progress_stage TEXT NOT NULL DEFAULT 'do',
        start_date REAL,
        deadline REAL,
        is_archived INTEGER NOT NULL DEFAULT 0,
        board_order INTEGER,
        updated_at REAL NOT NULL
      );
      """
    )
    try addColumnIfMissing(db, table: "app_projects", definition: "note_markdown TEXT NOT NULL DEFAULT ''")
    try addColumnIfMissing(db, table: "app_projects", definition: "progress_stage TEXT NOT NULL DEFAULT 'do'")
    try addColumnIfMissing(db, table: "app_projects", definition: "start_date REAL")
    try addColumnIfMissing(db, table: "app_projects", definition: "deadline REAL")
    try addColumnIfMissing(db, table: "app_projects", definition: "is_archived INTEGER NOT NULL DEFAULT 0")
    try addColumnIfMissing(db, table: "app_projects", definition: "board_order INTEGER")
    try exec(
      db,
      """
      CREATE TABLE IF NOT EXISTS app_tasks (
        id TEXT PRIMARY KEY NOT NULL,
        project_id TEXT NOT NULL,
        reminder_identifier TEXT NOT NULL,
        reminder_external_identifier TEXT,
        parent_task_id TEXT,
        title TEXT NOT NULL,
        note_text TEXT NOT NULL,
        is_completed INTEGER NOT NULL,
        completion_date REAL,
        start_date REAL,
        due_date REAL,
        schedule_has_explicit_time INTEGER NOT NULL,
        scheduled_duration_minutes INTEGER,
        priority INTEGER NOT NULL,
        recurrence_rule_raw TEXT,
        completed_recurring_signature_rule_raw TEXT,
        is_flagged INTEGER NOT NULL,
        required_work_days INTEGER NOT NULL,
        attachment_count INTEGER NOT NULL,
        created_at REAL NOT NULL,
        modified_at REAL NOT NULL,
        row_order INTEGER NOT NULL,
        FOREIGN KEY(project_id) REFERENCES app_projects(id) ON DELETE CASCADE
      );
      """
    )
    try addColumnIfMissing(db, table: "app_tasks", definition: "completed_recurring_signature_rule_raw TEXT")
    try exec(db, "CREATE INDEX IF NOT EXISTS idx_app_tasks_project_order ON app_tasks(project_id, row_order);")
    try exec(
      db,
      """
      CREATE TABLE IF NOT EXISTS app_task_supplements (
        task_id TEXT PRIMARY KEY NOT NULL,
        reminder_external_identifier TEXT,
        scheduled_duration_minutes INTEGER,
        updated_at REAL NOT NULL
      );
      """
    )
    try exec(
      db,
      """
      CREATE INDEX IF NOT EXISTS idx_app_task_supplements_external_identifier
      ON app_task_supplements(reminder_external_identifier);
      """
    )
    try exec(
      db,
      """
      CREATE TABLE IF NOT EXISTS app_project_supplements (
        project_id TEXT PRIMARY KEY NOT NULL,
        note_markdown TEXT NOT NULL,
        progress_stage TEXT NOT NULL,
        start_date REAL,
        deadline REAL,
        is_archived INTEGER NOT NULL,
        color_hex TEXT,
        board_order INTEGER,
        updated_at REAL NOT NULL
      );
      """
    )
    try seedTaskSupplements(db)
    try seedProjectSupplements(db)
    try upsertMetadata(db, key: "schema_version", value: "5")
  }

  func execute(_ db: OpaquePointer, _ sql: String, bindings: [Binding]) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw AppOwnedWorkspaceStoreError.prepareFailed(errorMessage(db))
    }
    defer { sqlite3_finalize(statement) }
    let expectedBindingCount = Int(sqlite3_bind_parameter_count(statement))
    guard expectedBindingCount == bindings.count else {
      throw AppOwnedWorkspaceStoreError.invalidSQLiteValue(
        "SQLite binding count mismatch: expected \(expectedBindingCount), got \(bindings.count)"
      )
    }
    for (index, binding) in bindings.enumerated() {
      try bind(binding, to: statement, at: Int32(index + 1))
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw AppOwnedWorkspaceStoreError.stepFailed(errorMessage(db))
    }
  }

  func query<T>(
    _ db: OpaquePointer,
    _ sql: String,
    map: (OpaquePointer) throws -> T
  ) throws -> [T] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw AppOwnedWorkspaceStoreError.prepareFailed(errorMessage(db))
    }
    defer { sqlite3_finalize(statement) }

    var values: [T] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_ROW {
        values.append(try map(statement))
      } else if status == SQLITE_DONE {
        return values
      } else {
        throw AppOwnedWorkspaceStoreError.stepFailed(errorMessage(db))
      }
    }
  }

  func scalarInt(_ db: OpaquePointer, sql: String) throws -> Int {
    try query(db, sql) { statement in
      columnInt(statement, 0) ?? 0
    }.first ?? 0
  }

  func scalarText(_ db: OpaquePointer, sql: String) throws -> String? {
    try query(db, sql) { statement in
      columnText(statement, 0)
    }.first ?? nil
  }

  func existingTaskRowOrder(_ db: OpaquePointer, taskID: UUID) throws -> Int? {
    try scalarIntOptional(
      db,
      sql: "SELECT row_order FROM app_tasks WHERE id = '\(taskID.uuidString)';"
    )
  }

  func nextTaskRowOrder(_ db: OpaquePointer, projectID: UUID) throws -> Int {
    (try scalarIntOptional(
      db,
      sql: "SELECT MAX(row_order) FROM app_tasks WHERE project_id = '\(projectID.uuidString)';"
    ) ?? -1) + 1
  }

  func scalarIntOptional(_ db: OpaquePointer, sql: String) throws -> Int? {
    try query(db, sql) { statement in
      columnInt(statement, 0)
    }.first ?? nil
  }

  func upsertMetadata(_ db: OpaquePointer, key: String, value: String) throws {
    try execute(
      db,
      "INSERT OR REPLACE INTO app_metadata (key, value) VALUES (?, ?);",
      bindings: [.text(key), .text(value)]
    )
  }

  func exec(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw AppOwnedWorkspaceStoreError.stepFailed(errorMessage(db))
    }
  }

  func addColumnIfMissing(
    _ db: OpaquePointer,
    table: String,
    definition: String
  ) throws {
    guard let columnName = definition.split(whereSeparator: \.isWhitespace).first else {
      throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("missing column name in migration")
    }
    guard try !columnExists(db, table: table, column: String(columnName)) else {
      return
    }
    do {
      try exec(db, "ALTER TABLE \(table) ADD COLUMN \(definition);")
    } catch {
      let message = errorMessage(db).lowercased()
      guard message.contains("duplicate column name") else {
        throw error
      }
    }
  }

  func seedTaskSupplements(_ db: OpaquePointer) throws {
    try exec(
      db,
      """
      INSERT OR IGNORE INTO app_task_supplements (
        task_id, reminder_external_identifier, scheduled_duration_minutes, updated_at
      )
      SELECT id, reminder_external_identifier, scheduled_duration_minutes, modified_at
      FROM app_tasks
      WHERE scheduled_duration_minutes IS NOT NULL AND scheduled_duration_minutes > 0;
      """
    )
  }

  func seedProjectSupplements(_ db: OpaquePointer) throws {
    try exec(
      db,
      """
      INSERT OR IGNORE INTO app_project_supplements (
        project_id, note_markdown, progress_stage, start_date, deadline, is_archived,
        color_hex, board_order, updated_at
      )
      SELECT id, note_markdown, progress_stage, start_date, deadline, is_archived,
        color_hex, board_order, updated_at
      FROM app_projects;
      """
    )
  }

  func schemaVersion(_ db: OpaquePointer) throws -> String? {
    guard try tableExists(db, table: "app_metadata") else {
      return nil
    }
    return try scalarText(db, sql: "SELECT value FROM app_metadata WHERE key = 'schema_version';")
  }

  func tableExists(_ db: OpaquePointer, table: String) throws -> Bool {
    try scalarInt(
      db,
      sql: """
      SELECT COUNT(*) FROM sqlite_master
      WHERE type = 'table' AND name = \(sqlStringLiteral(table));
      """
    ) > 0
  }

  func columnExists(_ db: OpaquePointer, table: String, column: String) throws -> Bool {
    try query(db, "PRAGMA table_info(\(quotedIdentifier(table)));") { statement in
      columnText(statement, 1)
    }.contains(column)
  }

  func bind(_ binding: Binding, to statement: OpaquePointer, at index: Int32) throws {
    let status: Int32
    switch binding {
    case .text(let value):
      status = sqlite3_bind_text(statement, index, value, -1, appOwnedSQLiteTransient)
    case .optionalText(let value):
      if let value {
        status = sqlite3_bind_text(statement, index, value, -1, appOwnedSQLiteTransient)
      } else {
        status = sqlite3_bind_null(statement, index)
      }
    case .int(let value):
      status = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    case .optionalInt(let value):
      if let value {
        status = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
      } else {
        status = sqlite3_bind_null(statement, index)
      }
    case .double(let value):
      status = sqlite3_bind_double(statement, index, value)
    case .optionalDouble(let value):
      if let value {
        status = sqlite3_bind_double(statement, index, value)
      } else {
        status = sqlite3_bind_null(statement, index)
      }
    }
    guard status == SQLITE_OK else {
      throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("SQLite bind failed at index \(index)")
    }
  }

  func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
      let text = sqlite3_column_text(statement, index)
    else {
      return nil
    }
    return String(cString: text)
  }

  func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int64(statement, index))
  }

  func columnDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return sqlite3_column_double(statement, index)
  }

  func errorMessage(_ db: OpaquePointer) -> String {
    String(cString: sqlite3_errmsg(db))
  }

  func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  func sqlStringLiteral(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "''"))'"
  }

  func quotedIdentifier(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}
