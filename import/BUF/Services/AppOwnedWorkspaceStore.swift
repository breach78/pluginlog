import Foundation
import SQLite3

private let appOwnedSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum AppOwnedWorkspaceStoreError: LocalizedError {
  case openFailed(String)
  case prepareFailed(String)
  case stepFailed(String)
  case invalidSQLiteValue(String)

  var errorDescription: String? {
    switch self {
    case .openFailed(let message):
      return "App-owned workspace SQLite open failed: \(message)"
    case .prepareFailed(let message):
      return "App-owned workspace SQLite prepare failed: \(message)"
    case .stepFailed(let message):
      return "App-owned workspace SQLite step failed: \(message)"
    case .invalidSQLiteValue(let message):
      return "App-owned workspace SQLite value is invalid: \(message)"
    }
  }
}

actor AppOwnedWorkspaceStore {
  private let sqliteURL: URL
  private let fileManager: FileManager

  init(containerRootURL: URL, fileManager: FileManager = .default) {
    self.sqliteURL = ContainerPaths(root: containerRootURL.standardizedFileURL).sqliteURL
    self.fileManager = fileManager
  }

  init(sqliteURL: URL, fileManager: FileManager = .default) {
    self.sqliteURL = sqliteURL.standardizedFileURL
    self.fileManager = fileManager
  }

  static func containerRootURL(forVaultRootURL vaultRootURL: URL) -> URL {
    ObsidianVaultLayout(vaultRootURL: vaultRootURL).sidecarRootURL
  }

  static func storeForVaultRootURL(_ vaultRootURL: URL) -> AppOwnedWorkspaceStore {
    AppOwnedWorkspaceStore(containerRootURL: containerRootURL(forVaultRootURL: vaultRootURL))
  }

  func prepare() throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
  }

  func hasImportedWorkspace() throws -> Bool {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    return try scalarInt(db, sql: "SELECT COUNT(*) FROM app_projects;") > 0
  }

  func setProjectionReadEnabled(_ isEnabled: Bool) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try upsertMetadata(db, key: "projection_read_enabled", value: isEnabled ? "1" : "0")
  }

  func isProjectionReadEnabled() throws -> Bool {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    return try scalarText(db, sql: "SELECT value FROM app_metadata WHERE key = 'projection_read_enabled';") == "1"
  }

  func replaceReminderSnapshot(
    _ batch: ReminderImportSnapshotBatch,
    importedAt: Date = .now
  ) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try exec(db, "BEGIN IMMEDIATE TRANSACTION;")
    do {
      try exec(db, "DELETE FROM app_tasks;")
      try exec(db, "DELETE FROM app_projects;")
      try upsertMetadata(db, key: "last_reminders_import_at", value: String(importedAt.timeIntervalSinceReferenceDate))

      let listsByIdentifier = Dictionary(uniqueKeysWithValues: batch.lists.map { ($0.identifier, $0) })
      for list in batch.lists {
        try insertProject(db, list: list, importedAt: importedAt)
        let items = batch.itemsByListIdentifier[list.identifier] ?? []
        for (index, item) in items.enumerated() {
          try insertTask(db, item: item, list: list, rowOrder: index)
        }
      }

      for (listIdentifier, items) in batch.itemsByListIdentifier where listsByIdentifier[listIdentifier] == nil {
        let fallbackList = ReminderListImportSnapshot(
          identifier: listIdentifier,
          externalIdentifier: listIdentifier,
          title: items.first?.sourceListTitle ?? "Imported Reminders",
          colorHex: nil
        )
        try insertProject(db, list: fallbackList, importedAt: importedAt)
        for (index, item) in items.enumerated() {
          try insertTask(db, item: item, list: fallbackList, rowOrder: index)
        }
      }
      try exec(db, "COMMIT;")
    } catch {
      try? exec(db, "ROLLBACK;")
      throw error
    }
  }

  func loadRetainedWorkspaceSnapshot(projectIDs: [UUID]) throws -> RetainedWorkspaceSnapshot {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)

    let requestedProjectIDs = Set(projectIDs)
    let allProjects = try loadProjects(db)
    let selectedProjects = requestedProjectIDs.isEmpty
      ? allProjects
      : allProjects.filter { requestedProjectIDs.contains($0.projectID) }
    let tasksByProjectID = try loadTasksByProjectID(db)

    return RetainedWorkspaceSnapshot(
      projects: selectedProjects.map { project in
        RetainedProject(
          identity: RetainedProjectIdentity(
            projectID: project.projectID,
            reminderListExternalIdentifier: project.reminderListExternalIdentifier
          ),
          fileURL: sqliteURL,
          title: project.title,
          noteMarkdown: "",
          tasks: tasksByProjectID[project.projectID] ?? [],
          usesProjectTag: true,
          isBUFOwned: true,
          hasManagedTaskSection: true,
          canSafelyPersistProjectNote: true,
          isArchived: false,
          colorHex: project.colorHex,
          updatedAt: project.updatedAt
        )
      }
    )
  }

  private func openDatabase() throws -> OpaquePointer {
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
    return db
  }

  private func migrate(_ db: OpaquePointer) throws {
    try exec(db, "PRAGMA foreign_keys = ON;")
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
        updated_at REAL NOT NULL
      );
      """
    )
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
    try exec(db, "CREATE INDEX IF NOT EXISTS idx_app_tasks_project_order ON app_tasks(project_id, row_order);")
    try upsertMetadata(db, key: "schema_version", value: "1")
  }

  private func insertProject(
    _ db: OpaquePointer,
    list: ReminderListImportSnapshot,
    importedAt: Date
  ) throws {
    let identity = normalized(list.externalIdentifier) ?? list.identifier
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: identity)
    try execute(
      db,
      """
      INSERT OR REPLACE INTO app_projects (
        id, reminder_list_identifier, reminder_list_external_identifier, title, color_hex, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?);
      """,
      bindings: [
        .text(projectID.uuidString),
        .text(list.identifier),
        .optionalText(normalized(list.externalIdentifier)),
        .text(list.title),
        .optionalText(normalized(list.colorHex)),
        .double(importedAt.timeIntervalSinceReferenceDate),
      ]
    )
  }

  private func insertTask(
    _ db: OpaquePointer,
    item: ReminderItemImportSnapshot,
    list: ReminderListImportSnapshot,
    rowOrder: Int
  ) throws {
    let projectIdentity = normalized(list.externalIdentifier) ?? list.identifier
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: projectIdentity)
    let taskIdentity = normalized(item.externalIdentifier) ?? item.identifier
    let taskID = ReminderProjectionIdentity.taskID(for: taskIdentity)
    let parentTaskID = normalized(item.parentExternalIdentifier).map(ReminderProjectionIdentity.taskID(for:))
    try execute(
      db,
      """
      INSERT OR REPLACE INTO app_tasks (
        id, project_id, reminder_identifier, reminder_external_identifier, parent_task_id,
        title, note_text, is_completed, completion_date, start_date, due_date,
        schedule_has_explicit_time, scheduled_duration_minutes, priority, recurrence_rule_raw,
        is_flagged, required_work_days, attachment_count, created_at, modified_at, row_order
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """,
      bindings: [
        .text(taskID.uuidString),
        .text(projectID.uuidString),
        .text(item.identifier),
        .optionalText(normalized(item.externalIdentifier)),
        .optionalText(parentTaskID?.uuidString),
        .text(item.title),
        .text(item.notes),
        .int(item.isCompleted ? 1 : 0),
        .optionalDouble(item.completionDate?.timeIntervalSinceReferenceDate),
        .optionalDouble(item.startDate?.timeIntervalSinceReferenceDate),
        .optionalDouble(item.dueDate?.timeIntervalSinceReferenceDate),
        .int(item.scheduleHasExplicitTime ? 1 : 0),
        .optionalInt(item.scheduledDurationMinutes),
        .int(item.priority),
        .optionalText(normalized(item.recurrenceRuleRaw)),
        .int(item.isFlagged ? 1 : 0),
        .int(item.requiredWorkDays),
        .int(item.attachmentCount),
        .double(item.createdAt.timeIntervalSinceReferenceDate),
        .double(item.modifiedAt.timeIntervalSinceReferenceDate),
        .int(rowOrder),
      ]
    )
  }

  private struct StoredProject {
    let projectID: UUID
    let reminderListExternalIdentifier: String?
    let title: String
    let colorHex: String?
    let updatedAt: Date
  }

  private func loadProjects(_ db: OpaquePointer) throws -> [StoredProject] {
    try query(
      db,
      "SELECT id, reminder_list_external_identifier, title, color_hex, updated_at FROM app_projects ORDER BY title COLLATE NOCASE;"
    ) { statement in
      guard let projectID = UUID(uuidString: columnText(statement, 0) ?? "") else {
        throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid project id")
      }
      return StoredProject(
        projectID: projectID,
        reminderListExternalIdentifier: columnText(statement, 1),
        title: columnText(statement, 2) ?? "",
        colorHex: columnText(statement, 3),
        updatedAt: Date(timeIntervalSinceReferenceDate: columnDouble(statement, 4) ?? 0)
      )
    }
  }

  private func loadTasksByProjectID(_ db: OpaquePointer) throws -> [UUID: [RetainedTask]] {
    var result: [UUID: [RetainedTask]] = [:]
    let rows = try query(
      db,
      """
      SELECT project_id, id, reminder_external_identifier, title, note_text, is_completed,
        due_date, start_date, schedule_has_explicit_time, scheduled_duration_minutes, recurrence_rule_raw
      FROM app_tasks
      ORDER BY project_id, row_order, title COLLATE NOCASE;
      """
    ) { statement -> (UUID, RetainedTask) in
      guard let projectID = UUID(uuidString: columnText(statement, 0) ?? ""),
        let taskID = UUID(uuidString: columnText(statement, 1) ?? "")
      else {
        throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid task id")
      }
      let dueDate = columnDouble(statement, 6).map(Date.init(timeIntervalSinceReferenceDate:))
      let startDate = columnDouble(statement, 7).map(Date.init(timeIntervalSinceReferenceDate:))
      let scheduleDate = dueDate ?? startDate
      let hasExplicitTime = columnInt(statement, 8) == 1
      let durationMinutes = columnInt(statement, 9).flatMap { $0 > 0 ? $0 : nil }
      let recurrenceRuleRaw = columnText(statement, 10)
      let rawDate = ReminderScheduleMetadataCodec.encodeDate(
        scheduleDate,
        hasExplicitTime: hasExplicitTime
      )
      return (
        projectID,
        RetainedTask(
          identity: RetainedTaskIdentity(
            taskID: taskID,
            reminderExternalIdentifier: columnText(statement, 2),
            calendarEventExternalIdentifier: nil
          ),
          title: columnText(statement, 3) ?? "",
          noteText: columnText(statement, 4) ?? "",
          isCompleted: columnInt(statement, 5) == 1,
          schedule: RetainedTaskSchedule(
            rawDate: rawDate,
            parsedDate: scheduleDate,
            hasExplicitTime: hasExplicitTime,
            rawDuration: durationMinutes.map(String.init),
            durationMinutes: durationMinutes,
            rawRepeatRule: recurrenceRuleRaw,
            canonicalRepeatRule: recurrenceRuleRaw
          ),
          isManagedTask: true
        )
      )
    }
    for (projectID, task) in rows {
      result[projectID, default: []].append(task)
    }
    return result
  }

  private enum Binding {
    case text(String)
    case optionalText(String?)
    case int(Int)
    case optionalInt(Int?)
    case double(Double)
    case optionalDouble(Double?)
  }

  private func execute(_ db: OpaquePointer, _ sql: String, bindings: [Binding]) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw AppOwnedWorkspaceStoreError.prepareFailed(errorMessage(db))
    }
    defer { sqlite3_finalize(statement) }
    for (index, binding) in bindings.enumerated() {
      bind(binding, to: statement, at: Int32(index + 1))
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw AppOwnedWorkspaceStoreError.stepFailed(errorMessage(db))
    }
  }

  private func query<T>(
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

  private func scalarInt(_ db: OpaquePointer, sql: String) throws -> Int {
    try query(db, sql) { statement in
      columnInt(statement, 0) ?? 0
    }.first ?? 0
  }

  private func scalarText(_ db: OpaquePointer, sql: String) throws -> String? {
    try query(db, sql) { statement in
      columnText(statement, 0)
    }.first ?? nil
  }

  private func upsertMetadata(_ db: OpaquePointer, key: String, value: String) throws {
    try execute(
      db,
      "INSERT OR REPLACE INTO app_metadata (key, value) VALUES (?, ?);",
      bindings: [.text(key), .text(value)]
    )
  }

  private func exec(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw AppOwnedWorkspaceStoreError.stepFailed(errorMessage(db))
    }
  }

  private func bind(_ binding: Binding, to statement: OpaquePointer, at index: Int32) {
    switch binding {
    case .text(let value):
      sqlite3_bind_text(statement, index, value, -1, appOwnedSQLiteTransient)
    case .optionalText(let value):
      if let value {
        sqlite3_bind_text(statement, index, value, -1, appOwnedSQLiteTransient)
      } else {
        sqlite3_bind_null(statement, index)
      }
    case .int(let value):
      sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    case .optionalInt(let value):
      if let value {
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
      } else {
        sqlite3_bind_null(statement, index)
      }
    case .double(let value):
      sqlite3_bind_double(statement, index, value)
    case .optionalDouble(let value):
      if let value {
        sqlite3_bind_double(statement, index, value)
      } else {
        sqlite3_bind_null(statement, index)
      }
    }
  }

  private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
      let text = sqlite3_column_text(statement, index)
    else {
      return nil
    }
    return String(cString: text)
  }

  private func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int64(statement, index))
  }

  private func columnDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return sqlite3_column_double(statement, index)
  }

  private func errorMessage(_ db: OpaquePointer) -> String {
    String(cString: sqlite3_errmsg(db))
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
