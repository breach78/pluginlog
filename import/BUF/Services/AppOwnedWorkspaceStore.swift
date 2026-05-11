import Foundation
import SQLite3

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
  private static let localCompletedRecurringMarker = "::app-completed::"

  enum ReminderImportCoverage: Sendable {
    case full
    case listedProjectsOnly
    case nonDestructive
  }

  struct ProjectReference: Equatable, Sendable {
    let projectID: UUID
    let reminderListIdentifier: String
    let reminderListExternalIdentifier: String?
    let title: String
  }

  struct TaskReference: Equatable, Sendable {
    let projectID: UUID
    let taskID: UUID
    let reminderIdentifier: String
    let reminderExternalIdentifier: String?
    let title: String
    let noteText: String
    let isCompleted: Bool
    let completionDate: Date?
    let dueDate: Date?
    let hasExplicitTime: Bool
    let durationMinutes: Int?
    let recurrenceRuleRaw: String?
    let priority: Int
  }

  struct ProjectSupplement: Equatable, Sendable {
    let projectID: UUID
    let noteMarkdown: String
    let progressStageRaw: String
    let startDate: Date?
    let deadline: Date?
    let isArchived: Bool
    let colorHex: String?
    let boardOrder: Int?

    init(
      projectID: UUID,
      noteMarkdown: String,
      progressStageRaw: String,
      startDate: Date?,
      deadline: Date?,
      isArchived: Bool,
      colorHex: String?,
      boardOrder: Int? = nil
    ) {
      self.projectID = projectID
      self.noteMarkdown = noteMarkdown
      self.progressStageRaw = progressStageRaw
      self.startDate = startDate
      self.deadline = deadline
      self.isArchived = isArchived
      self.colorHex = colorHex
      self.boardOrder = boardOrder
    }
  }

  struct TaskSupplement: Equatable, Sendable {
    let taskID: UUID
    let durationMinutes: Int?

    let rowOrder: Int?

    init(taskID: UUID, durationMinutes: Int?, rowOrder: Int? = nil) {
      self.taskID = taskID
      self.durationMinutes = durationMinutes
      self.rowOrder = rowOrder
    }
  }

  private struct ReminderImportPlan {
    let projectsToUpsert: [ProjectUpsert]
    let tasksToUpsert: [TaskUpsert]
    let taskIDsToDelete: Set<UUID>
    let projectIDsToDelete: Set<UUID>
  }

  private struct ProjectUpsert {
    let list: ReminderListImportSnapshot
    let projectID: UUID
  }

  private struct TaskUpsert {
    let item: ReminderItemImportSnapshot
    let list: ReminderListImportSnapshot
    let projectID: UUID
    let taskID: UUID
    let rowOrder: Int
  }

  let sqliteURL: URL
  let fileManager: FileManager

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
    return try hasImportedWorkspace(db)
  }

  private func hasImportedWorkspace(_ db: OpaquePointer) throws -> Bool {
    try scalarInt(db, sql: "SELECT COUNT(*) FROM app_projects;") > 0
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

  func metadataValue(forKey key: String) throws -> String? {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    return try scalarText(
      db,
      sql: "SELECT value FROM app_metadata WHERE key = \(sqlStringLiteral(key));"
    )
  }

  func setMetadataValue(_ value: String, forKey key: String) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try upsertMetadata(db, key: key, value: value)
  }

  func replaceReminderSnapshot(
    _ batch: ReminderImportSnapshotBatch,
    importedAt: Date = .now,
    coverage: ReminderImportCoverage = .nonDestructive
  ) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try exec(db, "BEGIN IMMEDIATE TRANSACTION;")
    do {
      if coverage == .full,
        batch.lists.isEmpty,
        batch.itemsByListIdentifier.values.allSatisfy(\.isEmpty),
        try hasImportedWorkspace(db)
      {
        try exec(db, "COMMIT;")
        return
      }
      let preservedProjectSupplements = try loadProjectSupplements(db, preservesImportedColor: true)
      let preservedTaskSupplements = try loadTaskSupplements(db)
      let preservedCompletedRecurringOccurrences = try loadLocalCompletedRecurringOccurrenceRows(db)
      let taskIdentityResolver = try loadTaskIdentityResolver(db)
      let plan = try buildReminderImportPlan(
        db,
        batch: batch,
        coverage: coverage,
        taskIdentityResolver: taskIdentityResolver
      )
      try upsertMetadata(db, key: "last_reminders_import_at", value: String(importedAt.timeIntervalSinceReferenceDate))

      for project in plan.projectsToUpsert {
        _ = try insertProject(db, list: project.list, importedAt: importedAt)
      }
      for task in plan.tasksToUpsert {
        _ = try insertTask(
          db,
          item: task.item,
          list: task.list,
          rowOrder: task.rowOrder,
          taskIdentityResolver: taskIdentityResolver,
          resolvedTaskID: task.taskID
        )
      }
      try deleteTasks(db, taskIDs: plan.taskIDsToDelete)
      try deleteProjects(db, projectIDs: plan.projectIDsToDelete)
      try mergeProjectSupplements(
        db,
        supplements: preservedProjectSupplements,
        colorAssignmentSQL: "color_hex = COALESCE(color_hex, ?)"
      )
      try mergeTaskSupplements(
        db,
        supplements: preservedTaskSupplements,
        durationAssignmentSQL: "scheduled_duration_minutes = COALESCE(?, scheduled_duration_minutes)",
        rowOrderAssignmentSQL: "row_order = COALESCE(?, row_order)"
      )
      try restoreLocalCompletedRecurringOccurrences(db, rows: preservedCompletedRecurringOccurrences)
      try exec(db, "COMMIT;")
    } catch {
      try? exec(db, "ROLLBACK;")
      throw error
    }
  }

  func mergeProjectSupplements(_ supplements: [ProjectSupplement]) throws {
    guard !supplements.isEmpty else { return }
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try mergeProjectSupplements(
      db,
      supplements: supplements,
      colorAssignmentSQL: "color_hex = COALESCE(?, color_hex)"
    )
  }

  func mergeTaskSupplements(_ supplements: [TaskSupplement]) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try mergeTaskSupplements(
      db,
      supplements: supplements,
      durationAssignmentSQL: "scheduled_duration_minutes = COALESCE(?, scheduled_duration_minutes)",
      rowOrderAssignmentSQL: "row_order = COALESCE(?, row_order)"
    )
  }

  func fillMissingTaskDurations(_ supplements: [TaskSupplement]) throws {
    let durationSupplements = supplements.filter { $0.durationMinutes != nil }
    guard !durationSupplements.isEmpty else { return }
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try mergeTaskSupplements(
      db,
      supplements: durationSupplements,
      durationAssignmentSQL: "scheduled_duration_minutes = COALESCE(scheduled_duration_minutes, ?)",
      rowOrderAssignmentSQL: "row_order = COALESCE(?, row_order)",
      overwritePersistedDurations: false
    )
  }

  @discardableResult
  func upsertProject(
    projectID: UUID,
    reminderListIdentifier: String,
    reminderListExternalIdentifier: String?,
    title: String,
    colorHex: String?,
    modifiedAt: Date
  ) throws -> ProjectReference {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try exec(db, "BEGIN IMMEDIATE TRANSACTION;")
    do {
      try execute(
        db,
        """
        INSERT OR IGNORE INTO app_projects (
          id, reminder_list_identifier, reminder_list_external_identifier, title, color_hex, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?);
        """,
        bindings: [
          .text(projectID.uuidString),
          .text(reminderListIdentifier),
          .optionalText(normalized(reminderListExternalIdentifier)),
          .text(title),
          .optionalText(normalized(colorHex)),
          .double(modifiedAt.timeIntervalSinceReferenceDate),
        ]
      )
      try execute(
        db,
        """
        UPDATE app_projects
        SET reminder_list_identifier = ?, reminder_list_external_identifier = ?,
          title = ?, color_hex = COALESCE(?, color_hex), updated_at = ?
        WHERE id = ?;
        """,
        bindings: [
          .text(reminderListIdentifier),
          .optionalText(normalized(reminderListExternalIdentifier)),
          .text(title),
          .optionalText(normalized(colorHex)),
          .double(modifiedAt.timeIntervalSinceReferenceDate),
          .text(projectID.uuidString),
        ]
      )
      try exec(db, "COMMIT;")
    } catch {
      try? exec(db, "ROLLBACK;")
      throw error
    }
    return try projectReference(projectID: projectID)
  }

  private func mergeTaskSupplements(
    _ db: OpaquePointer,
    supplements: [TaskSupplement],
    durationAssignmentSQL: String,
    rowOrderAssignmentSQL: String,
    overwritePersistedDurations: Bool = true
  ) throws {
    guard !supplements.isEmpty else { return }
    for supplement in supplements {
      try execute(
        db,
        """
        UPDATE app_tasks
        SET \(durationAssignmentSQL), \(rowOrderAssignmentSQL)
        WHERE id = ?;
        """,
        bindings: [
          .optionalInt(supplement.durationMinutes),
          .optionalInt(supplement.rowOrder),
          .text(supplement.taskID.uuidString),
        ]
      )
      if let durationMinutes = supplement.durationMinutes, durationMinutes > 0 {
        if overwritePersistedDurations {
          try upsertTaskDurationSupplement(
            db,
            taskID: supplement.taskID,
            reminderExternalIdentifier: nil,
            durationMinutes: durationMinutes
          )
        } else {
          try insertMissingTaskDurationSupplement(
            db,
            taskID: supplement.taskID,
            reminderExternalIdentifier: nil,
            durationMinutes: durationMinutes
          )
        }
      }
    }
  }

  @discardableResult
  func updateProjectTitle(projectID: UUID, title: String, modifiedAt: Date) throws -> ProjectReference {
    try updateProject(
      projectID: projectID,
      assignments: "title = ?",
      bindings: [.text(title)],
      modifiedAt: modifiedAt
    )
  }

  @discardableResult
  func updateProjectColor(projectID: UUID, colorHex: String?, modifiedAt: Date) throws -> ProjectReference {
    try updateProject(
      projectID: projectID,
      assignments: "color_hex = ?",
      bindings: [.optionalText(normalized(colorHex))],
      modifiedAt: modifiedAt
    )
  }

  @discardableResult
  func updateProjectStage(projectID: UUID, stage: ProjectProgressStage, modifiedAt: Date) throws -> ProjectReference {
    try updateProject(
      projectID: projectID,
      assignments: "progress_stage = ?",
      bindings: [.text(stage.storageRawValue)],
      modifiedAt: modifiedAt
    )
  }

  func updateProjectBoardOrders(_ boardOrdersByProjectID: [UUID: Int?]) throws {
    guard !boardOrdersByProjectID.isEmpty else { return }
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try exec(db, "BEGIN IMMEDIATE TRANSACTION;")
    do {
      for (projectID, boardOrder) in boardOrdersByProjectID {
        try execute(
          db,
          """
          UPDATE app_projects
          SET board_order = ?
          WHERE id = ?;
          """,
          bindings: [
            .optionalInt(boardOrder),
            .text(projectID.uuidString),
          ]
        )
        try upsertProjectSupplementFromCurrentRow(db, projectID: projectID)
      }
      try exec(db, "COMMIT;")
    } catch {
      try? exec(db, "ROLLBACK;")
      throw error
    }
  }

  func restoreLegacyProjectStagesIfDefault(_ stagesByProjectID: [UUID: ProjectProgressStage]) throws {
    guard !stagesByProjectID.isEmpty else { return }
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try exec(db, "BEGIN IMMEDIATE TRANSACTION;")
    do {
      let modifiedAt = Date().timeIntervalSinceReferenceDate
      for (projectID, stage) in stagesByProjectID {
        try execute(
          db,
          """
          UPDATE app_projects
          SET progress_stage = ?, updated_at = ?
          WHERE id = ? AND (progress_stage = ? OR lower(progress_stage) = ?);
          """,
          bindings: [
            .text(stage.storageRawValue),
            .double(modifiedAt),
            .text(projectID.uuidString),
            .text(ProjectProgressStage.do.storageRawValue),
            .text(ProjectProgressStage.do.title.lowercased()),
          ]
        )
        try upsertProjectSupplementFromCurrentRow(db, projectID: projectID)
      }
      try exec(db, "COMMIT;")
    } catch {
      try? exec(db, "ROLLBACK;")
      throw error
    }
  }

  private func mergeProjectSupplements(
    _ db: OpaquePointer,
    supplements: [ProjectSupplement],
    colorAssignmentSQL: String
  ) throws {
    guard !supplements.isEmpty else { return }
    for supplement in supplements {
      try execute(
        db,
        """
        UPDATE app_projects
        SET note_markdown = ?, progress_stage = ?, start_date = ?, deadline = ?,
          is_archived = ?, \(colorAssignmentSQL), board_order = COALESCE(?, board_order)
        WHERE id = ?;
        """,
        bindings: [
          .text(supplement.noteMarkdown),
          .text(supplement.progressStageRaw),
          .optionalDouble(supplement.startDate?.timeIntervalSinceReferenceDate),
          .optionalDouble(supplement.deadline?.timeIntervalSinceReferenceDate),
          .int(supplement.isArchived ? 1 : 0),
          .optionalText(normalized(supplement.colorHex)),
          .optionalInt(supplement.boardOrder),
          .text(supplement.projectID.uuidString),
        ]
      )
      try upsertProjectSupplement(db, supplement: supplement)
    }
  }

  private func upsertProjectSupplementFromCurrentRow(_ db: OpaquePointer, projectID: UUID) throws {
    let rows = try query(
      db,
      """
      SELECT id, note_markdown, progress_stage, start_date, deadline, is_archived, color_hex,
        board_order
      FROM app_projects
      WHERE id = '\(projectID.uuidString)';
      """,
    ) { statement in
      ProjectSupplement(
        projectID: projectID,
        noteMarkdown: columnText(statement, 1) ?? "",
        progressStageRaw: columnText(statement, 2) ?? ProjectProgressStage.do.storageRawValue,
        startDate: columnDouble(statement, 3).map(Date.init(timeIntervalSinceReferenceDate:)),
        deadline: columnDouble(statement, 4).map(Date.init(timeIntervalSinceReferenceDate:)),
        isArchived: columnInt(statement, 5) == 1,
        colorHex: columnText(statement, 6),
        boardOrder: columnInt(statement, 7)
      )
    }
    guard let supplement = rows.first else { return }
    try upsertProjectSupplement(db, supplement: supplement)
  }

  private func upsertProjectSupplement(_ db: OpaquePointer, supplement: ProjectSupplement) throws {
    try execute(
      db,
      """
      INSERT INTO app_project_supplements (
        project_id, note_markdown, progress_stage, start_date, deadline, is_archived,
        color_hex, board_order, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(project_id) DO UPDATE SET
        note_markdown = excluded.note_markdown,
        progress_stage = excluded.progress_stage,
        start_date = excluded.start_date,
        deadline = excluded.deadline,
        is_archived = excluded.is_archived,
        color_hex = excluded.color_hex,
        board_order = excluded.board_order,
        updated_at = excluded.updated_at;
      """,
      bindings: [
        .text(supplement.projectID.uuidString),
        .text(supplement.noteMarkdown),
        .text(supplement.progressStageRaw),
        .optionalDouble(supplement.startDate?.timeIntervalSinceReferenceDate),
        .optionalDouble(supplement.deadline?.timeIntervalSinceReferenceDate),
        .int(supplement.isArchived ? 1 : 0),
        .optionalText(normalized(supplement.colorHex)),
        .optionalInt(supplement.boardOrder),
        .double(Date().timeIntervalSinceReferenceDate),
      ]
    )
  }

  private func updateProject(
    projectID: UUID,
    assignments: String,
    bindings: [Binding],
    modifiedAt: Date
  ) throws -> ProjectReference {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try execute(
      db,
      "UPDATE app_projects SET \(assignments), updated_at = ? WHERE id = ?;",
      bindings: bindings + [
        .double(modifiedAt.timeIntervalSinceReferenceDate),
        .text(projectID.uuidString),
      ]
    )
    try upsertProjectSupplementFromCurrentRow(db, projectID: projectID)
    return try projectReference(projectID: projectID)
  }

  func loadRetainedWorkspaceSnapshot(projectIDs: [UUID]) throws -> RetainedWorkspaceSnapshot {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)

    let requestedProjectIDs = Set(projectIDs)
    let selectedProjects = try loadProjects(db, projectIDs: requestedProjectIDs)
    let tasksByProjectID = try loadTasksByProjectID(db, projectIDs: requestedProjectIDs)
    let projectNotesByProjectID = try loadProjectNoteMarkdownByProjectID(
      db,
      projectIDs: requestedProjectIDs
    )

    return RetainedWorkspaceSnapshot(
      projects: selectedProjects.map { project in
        RetainedProject(
          identity: RetainedProjectIdentity(
            projectID: project.projectID,
            reminderListExternalIdentifier: project.reminderListExternalIdentifier
          ),
          fileURL: sqliteURL,
          title: project.title,
          noteMarkdown: projectNotesByProjectID[project.projectID] ?? project.noteMarkdown,
          tasks: tasksByProjectID[project.projectID] ?? [],
          usesProjectTag: true,
          isBUFOwned: true,
          hasManagedTaskSection: true,
          canSafelyPersistProjectNote: true,
          isArchived: project.isArchived,
          colorHex: project.colorHex,
          localStartDate: project.startDate,
          localDeadline: project.deadline,
          progressStage: ProjectProgressStage.fromStorageValue(project.progressStageRaw) ?? .do,
          boardOrder: project.boardOrder,
          updatedAt: project.updatedAt
        )
      }
    )
  }

  func projectReference(projectID: UUID) throws -> ProjectReference {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    let rows = try query(
      db,
      """
      SELECT reminder_list_identifier, reminder_list_external_identifier, title
      FROM app_projects WHERE id = '\(projectID.uuidString)';
      """
    ) { statement in
      ProjectReference(
        projectID: projectID,
        reminderListIdentifier: columnText(statement, 0) ?? "",
        reminderListExternalIdentifier: columnText(statement, 1),
        title: columnText(statement, 2) ?? ""
      )
    }
    guard let reference = rows.first, !reference.reminderListIdentifier.isEmpty else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    return reference
  }

  func taskReference(projectID: UUID, taskID: UUID) throws -> TaskReference {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    let rows = try query(
      db,
      """
      SELECT reminder_identifier, reminder_external_identifier, title, note_text, is_completed,
        completion_date, due_date, schedule_has_explicit_time, scheduled_duration_minutes,
        recurrence_rule_raw, priority
      FROM app_tasks WHERE project_id = '\(projectID.uuidString)' AND id = '\(taskID.uuidString)';
      """
    ) { statement in
      TaskReference(
        projectID: projectID,
        taskID: taskID,
        reminderIdentifier: columnText(statement, 0) ?? "",
        reminderExternalIdentifier: columnText(statement, 1),
        title: columnText(statement, 2) ?? "",
        noteText: columnText(statement, 3) ?? "",
        isCompleted: columnInt(statement, 4) == 1,
        completionDate: columnDouble(statement, 5).map(Date.init(timeIntervalSinceReferenceDate:)),
        dueDate: columnDouble(statement, 6).map(Date.init(timeIntervalSinceReferenceDate:)),
        hasExplicitTime: columnInt(statement, 7) == 1,
        durationMinutes: columnInt(statement, 8).flatMap { $0 > 0 ? $0 : nil },
        recurrenceRuleRaw: columnText(statement, 9),
        priority: columnInt(statement, 10) ?? 0
      )
    }
    guard let reference = rows.first, !reference.reminderIdentifier.isEmpty else {
      throw RetainedTaskCommandError.taskNotFound(taskID)
    }
    return reference
  }

  func projectNoteTaskReference(projectID: UUID) throws -> TaskReference? {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    let rows = try query(
      db,
      """
      SELECT id
      FROM app_tasks
      WHERE project_id = \(sqlStringLiteral(projectID.uuidString))
        AND title = \(sqlStringLiteral(ProjectNoteReminderPolicy.title))
        AND priority = \(ProjectNoteReminderPolicy.lowPriority)
      ORDER BY row_order, modified_at DESC
      LIMIT 1;
      """
    ) { statement in
      UUID(uuidString: columnText(statement, 0) ?? "")
    }
    guard let taskID = rows.compactMap({ $0 }).first else { return nil }
    return try taskReference(projectID: projectID, taskID: taskID)
  }

  func upsertTask(
    projectID: UUID,
    taskID: UUID,
    reminderIdentifier: String,
    reminderExternalIdentifier: String?,
    title: String,
    noteText: String,
    isCompleted: Bool,
    completionDate: Date?,
    dueDate: Date?,
    hasExplicitTime: Bool,
    durationMinutes: Int?,
    recurrenceRuleRaw: String? = nil,
    completedRecurringSignatureRuleRaw: String? = nil,
    priority: Int = 0,
    modifiedAt: Date,
    appendIfMissing: Bool = true
  ) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    let existingRowOrder = try existingTaskRowOrder(db, taskID: taskID)
    let rowOrder: Int
    if let existingRowOrder {
      rowOrder = existingRowOrder
    } else if appendIfMissing {
      rowOrder = try nextTaskRowOrder(db, projectID: projectID)
    } else {
      rowOrder = 0
    }
    try execute(
      db,
      """
      INSERT OR REPLACE INTO app_tasks (
        id, project_id, reminder_identifier, reminder_external_identifier, parent_task_id,
        title, note_text, is_completed, completion_date, start_date, due_date,
        schedule_has_explicit_time, scheduled_duration_minutes, priority, recurrence_rule_raw,
        completed_recurring_signature_rule_raw, is_flagged, required_work_days, attachment_count,
        created_at, modified_at, row_order
      ) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, 0, 0, 0, ?, ?, ?);
      """,
      bindings: [
        .text(taskID.uuidString),
        .text(projectID.uuidString),
        .text(reminderIdentifier),
        .optionalText(normalized(reminderExternalIdentifier)),
        .text(title),
        .text(noteText),
        .int(isCompleted ? 1 : 0),
        .optionalDouble(completionDate?.timeIntervalSinceReferenceDate),
        .optionalDouble(dueDate?.timeIntervalSinceReferenceDate),
        .int(hasExplicitTime ? 1 : 0),
        .optionalInt(durationMinutes),
        .int(priority),
        .optionalText(normalized(recurrenceRuleRaw)),
        .optionalText(normalized(completedRecurringSignatureRuleRaw)),
        .double(modifiedAt.timeIntervalSinceReferenceDate),
        .double(modifiedAt.timeIntervalSinceReferenceDate),
        .int(rowOrder),
      ]
    )
    if hasExplicitTime, let durationMinutes, durationMinutes > 0 {
      try upsertTaskDurationSupplement(
        db,
        taskID: taskID,
        reminderExternalIdentifier: reminderExternalIdentifier,
        durationMinutes: durationMinutes
      )
    } else if !hasExplicitTime {
      try deleteTaskDurationSupplement(db, taskID: taskID)
    }
  }

  private func upsertTaskDurationSupplement(
    _ db: OpaquePointer,
    taskID: UUID,
    reminderExternalIdentifier: String?,
    durationMinutes: Int
  ) throws {
    try execute(
      db,
      """
      INSERT INTO app_task_supplements (
        task_id, reminder_external_identifier, scheduled_duration_minutes, updated_at
      ) VALUES (?, ?, ?, ?)
      ON CONFLICT(task_id) DO UPDATE SET
        reminder_external_identifier = COALESCE(excluded.reminder_external_identifier, reminder_external_identifier),
        scheduled_duration_minutes = excluded.scheduled_duration_minutes,
        updated_at = excluded.updated_at;
      """,
      bindings: [
        .text(taskID.uuidString),
        .optionalText(normalized(reminderExternalIdentifier)),
        .int(durationMinutes),
        .double(Date().timeIntervalSinceReferenceDate),
      ]
    )
  }

  private func insertMissingTaskDurationSupplement(
    _ db: OpaquePointer,
    taskID: UUID,
    reminderExternalIdentifier: String?,
    durationMinutes: Int
  ) throws {
    try execute(
      db,
      """
      INSERT OR IGNORE INTO app_task_supplements (
        task_id, reminder_external_identifier, scheduled_duration_minutes, updated_at
      ) VALUES (?, ?, ?, ?);
      """,
      bindings: [
        .text(taskID.uuidString),
        .optionalText(normalized(reminderExternalIdentifier)),
        .int(durationMinutes),
        .double(Date().timeIntervalSinceReferenceDate),
      ]
    )
  }

  private func deleteTaskDurationSupplement(_ db: OpaquePointer, taskID: UUID) throws {
    try execute(
      db,
      "DELETE FROM app_task_supplements WHERE task_id = ?;",
      bindings: [.text(taskID.uuidString)]
    )
  }

  @discardableResult
  func upsertLocalCompletedRecurringOccurrence(
    projectID: UUID,
    sourceTask: TaskReference,
    completionDate: Date,
    modifiedAt: Date
  ) throws -> UUID? {
    guard let externalIdentifier = Self.localCompletedRecurringExternalIdentifier(
      baseExternalIdentifier: sourceTask.reminderExternalIdentifier,
      dueDate: sourceTask.dueDate,
      hasExplicitTime: sourceTask.hasExplicitTime
    ) else {
      return nil
    }
    let taskID = ReminderProjectionIdentity.taskID(for: externalIdentifier)
    try upsertTask(
      projectID: projectID,
      taskID: taskID,
      reminderIdentifier: "app-completed:\(externalIdentifier)",
      reminderExternalIdentifier: externalIdentifier,
      title: sourceTask.title,
      noteText: sourceTask.noteText,
      isCompleted: true,
      completionDate: completionDate,
      dueDate: sourceTask.dueDate,
      hasExplicitTime: sourceTask.hasExplicitTime,
      durationMinutes: sourceTask.durationMinutes,
      recurrenceRuleRaw: nil,
      completedRecurringSignatureRuleRaw: sourceTask.recurrenceRuleRaw,
      priority: sourceTask.priority,
      modifiedAt: modifiedAt,
      appendIfMissing: true
    )
    return taskID
  }

  func deleteLocalCompletedRecurringOccurrence(
    projectID: UUID,
    baseExternalIdentifier: String?,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws {
    guard let externalIdentifier = Self.localCompletedRecurringExternalIdentifier(
      baseExternalIdentifier: baseExternalIdentifier,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime
    ) else {
      return
    }
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try execute(
      db,
      "DELETE FROM app_tasks WHERE project_id = ? AND reminder_external_identifier = ?;",
      bindings: [
        .text(projectID.uuidString),
        .text(externalIdentifier),
      ]
    )
  }

  func moveTask(taskID: UUID, toProjectID projectID: UUID) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try execute(
      db,
      "UPDATE app_tasks SET project_id = ?, row_order = ? WHERE id = ?;",
      bindings: [
        .text(projectID.uuidString),
        .int(nextTaskRowOrder(db, projectID: projectID)),
        .text(taskID.uuidString),
      ]
    )
  }

  func reorderOpenTasks(projectID: UUID, orderedTaskIDs: [UUID]) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    let rows = try loadTaskOrderRows(db, projectID: projectID)
    guard !rows.isEmpty else { return }

    var seenOrderedTaskIDs = Set<UUID>()
    let existingOpenTaskIDs = rows.filter { !$0.isCompleted }.map(\.taskID)
    let existingOpenTaskIDSet = Set(existingOpenTaskIDs)
    let requestedOpenTaskIDs = orderedTaskIDs.filter { taskID in
      existingOpenTaskIDSet.contains(taskID) && seenOrderedTaskIDs.insert(taskID).inserted
    }
    let nextOpenTaskIDs = requestedOpenTaskIDs
      + existingOpenTaskIDs.filter { !seenOrderedTaskIDs.contains($0) }
    let nextTaskIDs = nextOpenTaskIDs + rows.filter(\.isCompleted).map(\.taskID)
    guard nextTaskIDs != rows.map(\.taskID) else { return }

    try exec(db, "BEGIN IMMEDIATE TRANSACTION;")
    do {
      for (index, taskID) in nextTaskIDs.enumerated() {
        try execute(
          db,
          "UPDATE app_tasks SET row_order = ? WHERE project_id = ? AND id = ?;",
          bindings: [
            .int(index),
            .text(projectID.uuidString),
            .text(taskID.uuidString),
          ]
        )
      }
      try exec(db, "COMMIT;")
    } catch {
      try? exec(db, "ROLLBACK;")
      throw error
    }
  }

  func deleteTask(taskID: UUID) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try execute(
      db,
      "DELETE FROM app_tasks WHERE id = ?;",
      bindings: [.text(taskID.uuidString)]
    )
  }

  func deleteProject(projectID: UUID) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try migrate(db)
    try exec(db, "BEGIN IMMEDIATE TRANSACTION;")
    do {
      try execute(
        db,
        "DELETE FROM app_tasks WHERE project_id = ?;",
        bindings: [.text(projectID.uuidString)]
      )
      try execute(
        db,
        "DELETE FROM app_projects WHERE id = ?;",
        bindings: [.text(projectID.uuidString)]
      )
      try exec(db, "COMMIT;")
    } catch {
      try? exec(db, "ROLLBACK;")
      throw error
    }
  }

  private func buildReminderImportPlan(
    _ db: OpaquePointer,
    batch: ReminderImportSnapshotBatch,
    coverage: ReminderImportCoverage,
    taskIdentityResolver: TaskIdentityResolver
  ) throws -> ReminderImportPlan {
    var projectsToUpsert: [ProjectUpsert] = []
    var tasksToUpsert: [TaskUpsert] = []
    var importedProjectIDs = Set<UUID>()
    var importedTaskIDsByProjectID: [UUID: Set<UUID>] = [:]

    func appendList(_ list: ReminderListImportSnapshot, items: [ReminderItemImportSnapshot]) {
      let projectID = projectID(for: list)
      projectsToUpsert.append(ProjectUpsert(list: list, projectID: projectID))
      importedProjectIDs.insert(projectID)
      importedTaskIDsByProjectID[projectID] = importedTaskIDsByProjectID[projectID] ?? []
      for (index, item) in items.enumerated() {
        let taskIdentity = normalized(item.externalIdentifier) ?? item.identifier
        let taskID = taskIdentityResolver.taskID(
          for: item,
          projectID: projectID,
          fallbackIdentity: taskIdentity
        )
        tasksToUpsert.append(
          TaskUpsert(
            item: item,
            list: list,
            projectID: projectID,
            taskID: taskID,
            rowOrder: index
          )
        )
        importedTaskIDsByProjectID[projectID, default: []].insert(taskID)
      }
    }

    let listsByIdentifier = Dictionary(uniqueKeysWithValues: batch.lists.map { ($0.identifier, $0) })
    for list in batch.lists {
      appendList(list, items: batch.itemsByListIdentifier[list.identifier] ?? [])
    }
    for (listIdentifier, items) in batch.itemsByListIdentifier where listsByIdentifier[listIdentifier] == nil {
      let fallbackList = ReminderListImportSnapshot(
        identifier: listIdentifier,
        externalIdentifier: listIdentifier,
        title: items.first?.sourceListTitle ?? "Imported Reminders",
        colorHex: nil
      )
      appendList(fallbackList, items: items)
    }

    let taskIDsToDelete: Set<UUID>
    let projectIDsToDelete: Set<UUID>
    switch coverage {
    case .full:
      taskIDsToDelete = try taskIDsMissingFromReminderSnapshot(
        db,
        importedTaskIDsByProjectID: importedTaskIDsByProjectID
      )
      projectIDsToDelete = try projectIDsMissingFromReminderSnapshot(
        db,
        importedProjectIDs: importedProjectIDs
      )
    case .listedProjectsOnly:
      taskIDsToDelete = try taskIDsMissingFromReminderSnapshot(
        db,
        importedTaskIDsByProjectID: importedTaskIDsByProjectID
      )
      projectIDsToDelete = []
    case .nonDestructive:
      taskIDsToDelete = []
      projectIDsToDelete = []
    }

    return ReminderImportPlan(
      projectsToUpsert: projectsToUpsert,
      tasksToUpsert: tasksToUpsert,
      taskIDsToDelete: taskIDsToDelete,
      projectIDsToDelete: projectIDsToDelete
    )
  }

  private func projectID(for list: ReminderListImportSnapshot) -> UUID {
    let identity = normalized(list.externalIdentifier) ?? list.identifier
    return RetainedProjectionBuilder.derivedProjectID(for: identity)
  }

  private func insertProject(
    _ db: OpaquePointer,
    list: ReminderListImportSnapshot,
    importedAt: Date
  ) throws -> UUID {
    let projectID = projectID(for: list)
    try execute(
      db,
      """
      INSERT INTO app_projects (
        id, reminder_list_identifier, reminder_list_external_identifier, title, color_hex, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        reminder_list_identifier = excluded.reminder_list_identifier,
        reminder_list_external_identifier = excluded.reminder_list_external_identifier,
        title = excluded.title,
        color_hex = COALESCE(excluded.color_hex, app_projects.color_hex),
        updated_at = excluded.updated_at;
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
    return projectID
  }

  private func insertTask(
    _ db: OpaquePointer,
    item: ReminderItemImportSnapshot,
    list: ReminderListImportSnapshot,
    rowOrder: Int,
    taskIdentityResolver: TaskIdentityResolver,
    resolvedTaskID: UUID? = nil
  ) throws -> UUID {
    let projectIdentity = normalized(list.externalIdentifier) ?? list.identifier
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: projectIdentity)
    let taskIdentity = normalized(item.externalIdentifier) ?? item.identifier
    let taskID = resolvedTaskID ?? taskIdentityResolver.taskID(
      for: item,
      projectID: projectID,
      fallbackIdentity: taskIdentity
    )
    let parentTaskID = normalized(item.parentExternalIdentifier).map(ReminderProjectionIdentity.taskID(for:))
    try execute(
      db,
      """
      INSERT INTO app_tasks (
        id, project_id, reminder_identifier, reminder_external_identifier, parent_task_id,
        title, note_text, is_completed, completion_date, start_date, due_date,
        schedule_has_explicit_time, scheduled_duration_minutes, priority, recurrence_rule_raw,
        is_flagged, required_work_days, attachment_count, created_at, modified_at, row_order
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        project_id = excluded.project_id,
        reminder_identifier = excluded.reminder_identifier,
        reminder_external_identifier = excluded.reminder_external_identifier,
        parent_task_id = excluded.parent_task_id,
        title = excluded.title,
        note_text = excluded.note_text,
        is_completed = excluded.is_completed,
        completion_date = excluded.completion_date,
        start_date = excluded.start_date,
        due_date = excluded.due_date,
        schedule_has_explicit_time = excluded.schedule_has_explicit_time,
        scheduled_duration_minutes = COALESCE(
          excluded.scheduled_duration_minutes,
          app_tasks.scheduled_duration_minutes
        ),
        priority = excluded.priority,
        recurrence_rule_raw = excluded.recurrence_rule_raw,
        is_flagged = excluded.is_flagged,
        required_work_days = excluded.required_work_days,
        attachment_count = excluded.attachment_count,
        modified_at = excluded.modified_at;
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
    return taskID
  }

  private func taskIDsMissingFromReminderSnapshot(
    _ db: OpaquePointer,
    importedTaskIDsByProjectID: [UUID: Set<UUID>]
  ) throws -> Set<UUID> {
    var taskIDsToDelete = Set<UUID>()
    for (projectID, taskIDs) in importedTaskIDsByProjectID {
      let existingTaskIDs = try query(
        db,
        """
        SELECT id
        FROM app_tasks
        WHERE project_id = \(sqlStringLiteral(projectID.uuidString))
          AND (
            reminder_external_identifier IS NULL
            OR reminder_external_identifier NOT LIKE \(sqlStringLiteral("%\(Self.localCompletedRecurringMarker)%"))
          );
        """
      ) { statement -> UUID in
        guard let taskID = UUID(uuidString: columnText(statement, 0) ?? "") else {
          throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid task id")
        }
        return taskID
      }
      taskIDsToDelete.formUnion(Set(existingTaskIDs).subtracting(taskIDs))
    }
    return taskIDsToDelete
  }

  private func projectIDsMissingFromReminderSnapshot(
    _ db: OpaquePointer,
    importedProjectIDs: Set<UUID>
  ) throws -> Set<UUID> {
    let existingProjectIDs = try query(
      db,
      """
      SELECT id
      FROM app_projects;
      """
    ) { statement -> UUID in
      guard let projectID = UUID(uuidString: columnText(statement, 0) ?? "") else {
        throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid project id")
      }
      return projectID
    }
    return Set(existingProjectIDs).subtracting(importedProjectIDs)
  }

  private func deleteTasks(_ db: OpaquePointer, taskIDs: Set<UUID>) throws {
    guard !taskIDs.isEmpty else { return }
    let deletedTaskIDs = taskIDs
      .map { sqlStringLiteral($0.uuidString) }
      .sorted()
      .joined(separator: ", ")
    try exec(
      db,
      """
      DELETE FROM app_tasks
      WHERE id IN (\(deletedTaskIDs));
      """
    )
  }

  private func deleteProjects(_ db: OpaquePointer, projectIDs: Set<UUID>) throws {
    guard !projectIDs.isEmpty else { return }
    let deletedProjectIDs = projectIDs
      .map { sqlStringLiteral($0.uuidString) }
      .sorted()
      .joined(separator: ", ")
    try exec(
      db,
      """
      DELETE FROM app_projects
      WHERE id IN (\(deletedProjectIDs));
      """
    )
  }

  private struct StoredProject {
    let projectID: UUID
    let reminderListExternalIdentifier: String?
    let title: String
    let colorHex: String?
    let noteMarkdown: String
    let progressStageRaw: String
    let startDate: Date?
    let deadline: Date?
    let isArchived: Bool
    let boardOrder: Int?
    let updatedAt: Date
  }

  private func loadProjectSupplements(
    _ db: OpaquePointer,
    preservesImportedColor: Bool
  ) throws -> [ProjectSupplement] {
    var supplementsByProjectID: [UUID: ProjectSupplement] = [:]
    let projectRows = try query(
      db,
      """
      SELECT id, note_markdown, progress_stage, start_date, deadline, is_archived, color_hex,
        board_order
      FROM app_projects;
      """
    ) { statement in
      guard let projectID = UUID(uuidString: columnText(statement, 0) ?? "") else {
        throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid project id")
      }
      return ProjectSupplement(
        projectID: projectID,
        noteMarkdown: columnText(statement, 1) ?? "",
        progressStageRaw: columnText(statement, 2) ?? ProjectProgressStage.do.storageRawValue,
        startDate: columnDouble(statement, 3).map(Date.init(timeIntervalSinceReferenceDate:)),
        deadline: columnDouble(statement, 4).map(Date.init(timeIntervalSinceReferenceDate:)),
        isArchived: columnInt(statement, 5) == 1,
        colorHex: preservesImportedColor ? columnText(statement, 6) : nil,
        boardOrder: columnInt(statement, 7)
      )
    }
    for supplement in projectRows {
      supplementsByProjectID[supplement.projectID] = supplement
    }

    let persistentRows = try query(
      db,
      """
      SELECT project_id, note_markdown, progress_stage, start_date, deadline, is_archived,
        color_hex, board_order
      FROM app_project_supplements;
      """
    ) { statement -> ProjectSupplement? in
      guard let projectID = UUID(uuidString: columnText(statement, 0) ?? "") else {
        return nil
      }
      let existing = supplementsByProjectID[projectID]
      return ProjectSupplement(
        projectID: projectID,
        noteMarkdown: columnText(statement, 1) ?? existing?.noteMarkdown ?? "",
        progressStageRaw: columnText(statement, 2) ?? existing?.progressStageRaw
          ?? ProjectProgressStage.do.storageRawValue,
        startDate: columnDouble(statement, 3).map(Date.init(timeIntervalSinceReferenceDate:)),
        deadline: columnDouble(statement, 4).map(Date.init(timeIntervalSinceReferenceDate:)),
        isArchived: columnInt(statement, 5) == 1,
        colorHex: preservesImportedColor ? (columnText(statement, 6) ?? existing?.colorHex) : nil,
        boardOrder: columnInt(statement, 7) ?? existing?.boardOrder
      )
    }
    for supplement in persistentRows.compactMap({ $0 }) {
      supplementsByProjectID[supplement.projectID] = supplement
    }
    return supplementsByProjectID.values.sorted { $0.projectID.uuidString < $1.projectID.uuidString }
  }

  private func loadTaskSupplements(_ db: OpaquePointer) throws -> [TaskSupplement] {
    var supplementsByTaskID: [UUID: TaskSupplement] = [:]
    let taskRows = try query(
      db,
      """
      SELECT id, scheduled_duration_minutes, row_order
      FROM app_tasks;
      """
    ) { statement in
      guard let taskID = UUID(uuidString: columnText(statement, 0) ?? "") else {
        throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid task id")
      }
      return TaskSupplement(
        taskID: taskID,
        durationMinutes: columnInt(statement, 1).flatMap { $0 > 0 ? $0 : nil },
        rowOrder: columnInt(statement, 2)
      )
    }
    for supplement in taskRows {
      supplementsByTaskID[supplement.taskID] = supplement
    }

    let persistentDurationRows = try query(
      db,
      """
      SELECT task_id, scheduled_duration_minutes
      FROM app_task_supplements
      WHERE scheduled_duration_minutes IS NOT NULL AND scheduled_duration_minutes > 0;
      """
    ) { statement -> (UUID, Int)? in
      guard let taskID = UUID(uuidString: columnText(statement, 0) ?? ""),
        let durationMinutes = columnInt(statement, 1),
        durationMinutes > 0
      else {
        return nil
      }
      return (taskID, durationMinutes)
    }
    for row in persistentDurationRows.compactMap({ $0 }) {
      let existing = supplementsByTaskID[row.0]
      supplementsByTaskID[row.0] = TaskSupplement(
        taskID: row.0,
        durationMinutes: row.1,
        rowOrder: existing?.rowOrder
      )
    }
    return supplementsByTaskID.values.sorted { $0.taskID.uuidString < $1.taskID.uuidString }
  }

  private struct StoredTaskOrderRow {
    let taskID: UUID
    let isCompleted: Bool
  }

  private struct LocalCompletedRecurringOccurrenceRow {
    let taskID: String
    let projectID: String
    let reminderIdentifier: String
    let reminderExternalIdentifier: String
    let title: String
    let noteText: String
    let completionDate: Date?
    let startDate: Date?
    let dueDate: Date?
    let hasExplicitTime: Bool
    let durationMinutes: Int?
    let signatureRecurrenceRuleRaw: String?
    let priority: Int
    let isFlagged: Bool
    let requiredWorkDays: Int
    let attachmentCount: Int
    let createdAt: Date
    let modifiedAt: Date
    let rowOrder: Int
  }

  private struct LocalCompletedRecurringRestoreIdentity {
    let taskID: String
    let reminderIdentifier: String
    let reminderExternalIdentifier: String
    let signatureRecurrenceRuleRaw: String?
  }

  private struct ActiveRecurringTaskMatch {
    let externalIdentifier: String
    let recurrenceRuleRaw: String
    let anchorPhaseRaw: String?
  }

  private struct TaskIdentityResolver {
    let idsByIdentifier: [String: UUID]
    let idsByExternalIdentifier: [String: UUID]
    let recurringIDsBySignature: [RecurringTaskSignature: UUID]

    func taskID(
      for item: ReminderItemImportSnapshot,
      projectID: UUID,
      fallbackIdentity: String
    ) -> UUID {
      if let externalIdentifier = normalizedValue(item.externalIdentifier),
        let existingID = idsByExternalIdentifier[externalIdentifier]
      {
        return existingID
      }
      if let identifier = normalizedValue(item.identifier),
        let existingID = idsByIdentifier[identifier]
      {
        return existingID
      }
      if !item.isCompleted,
        let recurrenceRuleRaw = normalizedValue(item.recurrenceRuleRaw),
        let existingID = recurringIDsBySignature[
          RecurringTaskSignature(
            projectID: projectID,
            title: item.title,
            noteText: item.notes,
            recurrenceRuleRaw: recurrenceRuleRaw,
            startDate: item.startDate,
            dueDate: item.dueDate,
            hasExplicitTime: item.scheduleHasExplicitTime
          )
        ]
      {
        return existingID
      }
      return ReminderProjectionIdentity.taskID(for: fallbackIdentity)
    }

    private func normalizedValue(_ value: String?) -> String? {
      guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      else {
        return nil
      }
      return value
    }
  }

  private struct RecurringTaskSignature: Hashable {
    let projectID: UUID
    let title: String
    let noteText: String
    let recurrenceRuleRaw: String
    let anchorPhaseRaw: String?

    init(
      projectID: UUID,
      title: String,
      noteText: String,
      recurrenceRuleRaw: String,
      startDate: Date?,
      dueDate: Date?,
      hasExplicitTime: Bool
    ) {
      self.projectID = projectID
      self.title = Self.normalizedText(title)
      self.noteText = Self.normalizedText(noteText)
      self.recurrenceRuleRaw = Self.normalizedText(recurrenceRuleRaw)
      self.anchorPhaseRaw = Self.anchorPhaseRaw(
        recurrenceRuleRaw: recurrenceRuleRaw,
        startDate: startDate,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime
      )
    }

    private static func normalizedText(_ value: String) -> String {
      value
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func anchorPhaseRaw(
      recurrenceRuleRaw: String,
      startDate: Date?,
      dueDate: Date?,
      hasExplicitTime _: Bool
    ) -> String? {
      guard let anchorDate = dueDate ?? startDate else { return nil }
      let parts = normalizedText(recurrenceRuleRaw)
        .lowercased()
        .split(separator: "|", omittingEmptySubsequences: false)
      let frequency = parts.first.map(String.init) ?? ""
      let interval = max(1, parts.dropFirst().first.flatMap { Int($0) } ?? 1)

      switch frequency {
      case "daily":
        let dayIndex = Int(floor(anchorCalendar.startOfDay(for: anchorDate).timeIntervalSinceReferenceDate / 86_400))
        return "daily|\(interval)|\(positiveModulo(dayIndex, interval))"
      case "weekly":
        let weekIndex = Int(floor(anchorCalendar.startOfDay(for: anchorDate).timeIntervalSinceReferenceDate / (7 * 86_400)))
        return "weekly|\(interval)|\(positiveModulo(weekIndex, interval))"
      case "monthly":
        let components = anchorCalendar.dateComponents([.year, .month], from: anchorDate)
        guard let year = components.year, let month = components.month else { return nil }
        return "monthly|\(interval)|\(positiveModulo(year * 12 + month, interval))"
      case "yearly":
        let year = anchorCalendar.component(.year, from: anchorDate)
        return "yearly|\(interval)|\(positiveModulo(year, interval))"
      default:
        return nil
      }
    }

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
      let remainder = value % modulus
      return remainder >= 0 ? remainder : remainder + modulus
    }

    private static let anchorCalendar: Calendar = {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .autoupdatingCurrent
      return calendar
    }()
  }

  private func loadTaskIdentityResolver(_ db: OpaquePointer) throws -> TaskIdentityResolver {
    let rows = try query(
      db,
      """
      SELECT id, project_id, reminder_identifier, reminder_external_identifier, title, note_text, is_completed,
        recurrence_rule_raw, start_date, due_date, schedule_has_explicit_time
      FROM app_tasks
      ORDER BY is_completed ASC, modified_at DESC;
      """
    ) { statement -> (UUID, UUID, String?, String?, RecurringTaskSignature?) in
      guard let taskID = UUID(uuidString: columnText(statement, 0) ?? ""),
        let projectID = UUID(uuidString: columnText(statement, 1) ?? "")
      else {
        throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid task id")
      }
      let identifier = normalized(columnText(statement, 2))
      let externalIdentifier = normalized(columnText(statement, 3))
      let isCompleted = columnInt(statement, 6) == 1
      let recurrenceRuleRaw = normalized(columnText(statement, 7))
      let startDate = columnDouble(statement, 8).map(Date.init(timeIntervalSinceReferenceDate:))
      let dueDate = columnDouble(statement, 9).map(Date.init(timeIntervalSinceReferenceDate:))
      let hasExplicitTime = columnInt(statement, 10) == 1
      let signature = (!isCompleted ? recurrenceRuleRaw : nil).map { recurrenceRuleRaw in
        RecurringTaskSignature(
          projectID: projectID,
          title: columnText(statement, 4) ?? "",
          noteText: columnText(statement, 5) ?? "",
          recurrenceRuleRaw: recurrenceRuleRaw,
          startDate: startDate,
          dueDate: dueDate,
          hasExplicitTime: hasExplicitTime
        )
      }
      return (taskID, projectID, identifier, externalIdentifier, signature)
    }

    var idsByIdentifier: [String: UUID] = [:]
    var idsByExternalIdentifier: [String: UUID] = [:]
    var recurringIDsBySignature: [RecurringTaskSignature: UUID] = [:]
    var ambiguousRecurringSignatures = Set<RecurringTaskSignature>()
    for row in rows {
      if let identifier = row.2, idsByIdentifier[identifier] == nil {
        idsByIdentifier[identifier] = row.0
      }
      if let externalIdentifier = row.3, idsByExternalIdentifier[externalIdentifier] == nil {
        idsByExternalIdentifier[externalIdentifier] = row.0
      }
      guard let signature = row.4,
        !ambiguousRecurringSignatures.contains(signature)
      else {
        continue
      }
      if let existingID = recurringIDsBySignature[signature], existingID != row.0 {
        recurringIDsBySignature.removeValue(forKey: signature)
        ambiguousRecurringSignatures.insert(signature)
      } else {
        recurringIDsBySignature[signature] = row.0
      }
    }
    return TaskIdentityResolver(
      idsByIdentifier: idsByIdentifier,
      idsByExternalIdentifier: idsByExternalIdentifier,
      recurringIDsBySignature: recurringIDsBySignature
    )
  }

  private func loadTaskOrderRows(
    _ db: OpaquePointer,
    projectID: UUID
  ) throws -> [StoredTaskOrderRow] {
    try query(
      db,
      """
      SELECT id, is_completed
      FROM app_tasks
      WHERE project_id = '\(projectID.uuidString)'
      ORDER BY is_completed, row_order, title COLLATE NOCASE;
      """
    ) { statement in
      guard let taskID = UUID(uuidString: columnText(statement, 0) ?? "") else {
        throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid task id")
      }
      return StoredTaskOrderRow(
        taskID: taskID,
        isCompleted: columnInt(statement, 1) == 1
      )
    }
  }

  private func loadLocalCompletedRecurringOccurrenceRows(
    _ db: OpaquePointer
  ) throws -> [LocalCompletedRecurringOccurrenceRow] {
    try query(
      db,
      """
      SELECT id, project_id, reminder_identifier, reminder_external_identifier, title, note_text,
        completion_date, start_date, due_date, schedule_has_explicit_time,
        scheduled_duration_minutes, completed_recurring_signature_rule_raw, priority, is_flagged,
        required_work_days, attachment_count, created_at, modified_at, row_order
      FROM app_tasks
      WHERE is_completed = 1
        AND reminder_external_identifier LIKE \(sqlStringLiteral("%\(Self.localCompletedRecurringMarker)%"));
      """
    ) { statement in
      LocalCompletedRecurringOccurrenceRow(
        taskID: columnText(statement, 0) ?? "",
        projectID: columnText(statement, 1) ?? "",
        reminderIdentifier: columnText(statement, 2) ?? "",
        reminderExternalIdentifier: columnText(statement, 3) ?? "",
        title: columnText(statement, 4) ?? "",
        noteText: columnText(statement, 5) ?? "",
        completionDate: columnDouble(statement, 6).map(Date.init(timeIntervalSinceReferenceDate:)),
        startDate: columnDouble(statement, 7).map(Date.init(timeIntervalSinceReferenceDate:)),
        dueDate: columnDouble(statement, 8).map(Date.init(timeIntervalSinceReferenceDate:)),
        hasExplicitTime: columnInt(statement, 9) == 1,
        durationMinutes: columnInt(statement, 10).flatMap { $0 > 0 ? $0 : nil },
        signatureRecurrenceRuleRaw: normalized(columnText(statement, 11)),
        priority: columnInt(statement, 12) ?? 0,
        isFlagged: columnInt(statement, 13) == 1,
        requiredWorkDays: columnInt(statement, 14) ?? 0,
        attachmentCount: columnInt(statement, 15) ?? 0,
        createdAt: Date(timeIntervalSinceReferenceDate: columnDouble(statement, 16) ?? 0),
        modifiedAt: Date(timeIntervalSinceReferenceDate: columnDouble(statement, 17) ?? 0),
        rowOrder: columnInt(statement, 18) ?? 0
      )
    }
  }

  private func restoreLocalCompletedRecurringOccurrences(
    _ db: OpaquePointer,
    rows: [LocalCompletedRecurringOccurrenceRow]
  ) throws {
    for row in rows {
      guard let restoreIdentity = try localCompletedRecurringRestoreIdentity(db, row: row) else {
        continue
      }
      if restoreIdentity.taskID != row.taskID {
        try execute(
          db,
          "DELETE FROM app_tasks WHERE id = ?;",
          bindings: [.text(row.taskID)]
        )
      }
      try execute(
        db,
        """
        INSERT OR REPLACE INTO app_tasks (
          id, project_id, reminder_identifier, reminder_external_identifier, parent_task_id,
          title, note_text, is_completed, completion_date, start_date, due_date,
          schedule_has_explicit_time, scheduled_duration_minutes, priority, recurrence_rule_raw,
          completed_recurring_signature_rule_raw, is_flagged, required_work_days, attachment_count,
          created_at, modified_at, row_order
        ) VALUES (?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?);
        """,
        bindings: [
          .text(restoreIdentity.taskID),
          .text(row.projectID),
          .text(restoreIdentity.reminderIdentifier),
          .text(restoreIdentity.reminderExternalIdentifier),
          .text(row.title),
          .text(row.noteText),
          .optionalDouble(row.completionDate?.timeIntervalSinceReferenceDate),
          .optionalDouble(row.startDate?.timeIntervalSinceReferenceDate),
          .optionalDouble(row.dueDate?.timeIntervalSinceReferenceDate),
          .int(row.hasExplicitTime ? 1 : 0),
          .optionalInt(row.durationMinutes),
          .int(row.priority),
          .optionalText(restoreIdentity.signatureRecurrenceRuleRaw),
          .int(row.isFlagged ? 1 : 0),
          .int(row.requiredWorkDays),
          .int(row.attachmentCount),
          .double(row.createdAt.timeIntervalSinceReferenceDate),
          .double(row.modifiedAt.timeIntervalSinceReferenceDate),
          .int(row.rowOrder),
        ]
      )
    }
  }

  private func localCompletedRecurringRestoreIdentity(
    _ db: OpaquePointer,
    row: LocalCompletedRecurringOccurrenceRow
  ) throws -> LocalCompletedRecurringRestoreIdentity? {
    guard let activeMatch = try activeRecurringTaskMatch(db, matching: row),
      let reminderExternalIdentifier = Self.localCompletedRecurringExternalIdentifier(
        baseExternalIdentifier: activeMatch.externalIdentifier,
        dueDate: row.dueDate,
        hasExplicitTime: row.hasExplicitTime
      )
    else {
      return nil
    }
    return LocalCompletedRecurringRestoreIdentity(
      taskID: ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier).uuidString,
      reminderIdentifier: "app-completed:\(reminderExternalIdentifier)",
      reminderExternalIdentifier: reminderExternalIdentifier,
      signatureRecurrenceRuleRaw: row.signatureRecurrenceRuleRaw ?? activeMatch.recurrenceRuleRaw
    )
  }

  private func activeRecurringTaskMatch(
    _ db: OpaquePointer,
    matching row: LocalCompletedRecurringOccurrenceRow
  ) throws -> ActiveRecurringTaskMatch? {
    if let baseExternalIdentifier = Self.localCompletedRecurringBaseIdentifier(
      from: row.reminderExternalIdentifier
    ),
      let exactMatch = try activeRecurringTaskMatch(
        db,
        projectID: row.projectID,
        externalIdentifier: baseExternalIdentifier
      )
    {
      return exactMatch
    }
    guard let recurrenceRuleRaw = row.signatureRecurrenceRuleRaw else { return nil }
    let anchorPhaseRaw = RecurringTaskSignature.anchorPhaseRaw(
      recurrenceRuleRaw: recurrenceRuleRaw,
      startDate: row.startDate,
      dueDate: row.dueDate,
      hasExplicitTime: row.hasExplicitTime
    )
    if let exactSignatureMatch = try uniqueActiveRecurringTaskMatch(
      db,
      projectID: row.projectID,
      title: row.title,
      noteText: row.noteText,
      recurrenceRuleRaw: recurrenceRuleRaw,
      anchorPhaseRaw: anchorPhaseRaw,
      requiresNoteMatch: true
    ) {
      return exactSignatureMatch
    }
    return try uniqueActiveRecurringTaskMatch(
      db,
      projectID: row.projectID,
      title: row.title,
      noteText: row.noteText,
      recurrenceRuleRaw: recurrenceRuleRaw,
      anchorPhaseRaw: anchorPhaseRaw,
      requiresNoteMatch: false
    )
  }

  private func activeRecurringTaskMatch(
    _ db: OpaquePointer,
    projectID: String,
    externalIdentifier: String
  ) throws -> ActiveRecurringTaskMatch? {
    try query(
      db,
      """
      SELECT reminder_external_identifier, recurrence_rule_raw, start_date, due_date,
        schedule_has_explicit_time
      FROM app_tasks
      WHERE project_id = \(sqlStringLiteral(projectID))
        AND reminder_external_identifier = \(sqlStringLiteral(externalIdentifier))
        AND is_completed = 0
        AND recurrence_rule_raw IS NOT NULL
      LIMIT 1;
      """
    ) { statement -> ActiveRecurringTaskMatch? in
      guard let externalIdentifier = normalized(columnText(statement, 0)),
        let recurrenceRuleRaw = normalized(columnText(statement, 1))
      else {
        return nil
      }
      let startDate = columnDouble(statement, 2).map(Date.init(timeIntervalSinceReferenceDate:))
      let dueDate = columnDouble(statement, 3).map(Date.init(timeIntervalSinceReferenceDate:))
      let hasExplicitTime = columnInt(statement, 4) == 1
      return ActiveRecurringTaskMatch(
        externalIdentifier: externalIdentifier,
        recurrenceRuleRaw: recurrenceRuleRaw,
        anchorPhaseRaw: RecurringTaskSignature.anchorPhaseRaw(
          recurrenceRuleRaw: recurrenceRuleRaw,
          startDate: startDate,
          dueDate: dueDate,
          hasExplicitTime: hasExplicitTime
        )
      )
    }.compactMap { $0 }.first
  }

  private func uniqueActiveRecurringTaskMatch(
    _ db: OpaquePointer,
    projectID: String,
    title: String,
    noteText: String,
    recurrenceRuleRaw: String,
    anchorPhaseRaw: String?,
    requiresNoteMatch: Bool
  ) throws -> ActiveRecurringTaskMatch? {
    let noteClause = requiresNoteMatch
      ? "AND note_text = \(sqlStringLiteral(noteText))"
      : ""
    let rows = try query(
      db,
      """
      SELECT reminder_external_identifier, recurrence_rule_raw, start_date, due_date,
        schedule_has_explicit_time
      FROM app_tasks
      WHERE project_id = \(sqlStringLiteral(projectID))
        AND title = \(sqlStringLiteral(title))
        \(noteClause)
        AND recurrence_rule_raw = \(sqlStringLiteral(recurrenceRuleRaw))
        AND reminder_external_identifier IS NOT NULL
        AND is_completed = 0;
      """
    ) { statement -> ActiveRecurringTaskMatch? in
      guard let externalIdentifier = normalized(columnText(statement, 0)),
        let recurrenceRuleRaw = normalized(columnText(statement, 1))
      else {
        return nil
      }
      let startDate = columnDouble(statement, 2).map(Date.init(timeIntervalSinceReferenceDate:))
      let dueDate = columnDouble(statement, 3).map(Date.init(timeIntervalSinceReferenceDate:))
      let hasExplicitTime = columnInt(statement, 4) == 1
      return ActiveRecurringTaskMatch(
        externalIdentifier: externalIdentifier,
        recurrenceRuleRaw: recurrenceRuleRaw,
        anchorPhaseRaw: RecurringTaskSignature.anchorPhaseRaw(
          recurrenceRuleRaw: recurrenceRuleRaw,
          startDate: startDate,
          dueDate: dueDate,
          hasExplicitTime: hasExplicitTime
        )
      )
    }
    let matches = rows
      .compactMap { $0 }
      .filter { match in
        guard let anchorPhaseRaw else { return true }
        return match.anchorPhaseRaw == anchorPhaseRaw
      }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private func loadProjects(
    _ db: OpaquePointer,
    projectIDs: Set<UUID> = []
  ) throws -> [StoredProject] {
    try query(
      db,
      """
      SELECT id, reminder_list_external_identifier, title, color_hex, note_markdown,
        progress_stage, start_date, deadline, is_archived, board_order, updated_at
      FROM app_projects
      \(projectFilterClause(column: "id", projectIDs: projectIDs))
      ORDER BY title COLLATE NOCASE;
      """
    ) { statement in
      guard let projectID = UUID(uuidString: columnText(statement, 0) ?? "") else {
        throw AppOwnedWorkspaceStoreError.invalidSQLiteValue("invalid project id")
      }
      return StoredProject(
        projectID: projectID,
        reminderListExternalIdentifier: columnText(statement, 1),
        title: columnText(statement, 2) ?? "",
        colorHex: columnText(statement, 3),
        noteMarkdown: columnText(statement, 4) ?? "",
        progressStageRaw: columnText(statement, 5) ?? ProjectProgressStage.do.storageRawValue,
        startDate: columnDouble(statement, 6).map(Date.init(timeIntervalSinceReferenceDate:)),
        deadline: columnDouble(statement, 7).map(Date.init(timeIntervalSinceReferenceDate:)),
        isArchived: columnInt(statement, 8) == 1,
        boardOrder: columnInt(statement, 9),
        updatedAt: Date(timeIntervalSinceReferenceDate: columnDouble(statement, 10) ?? 0)
      )
    }
  }

  private func loadTasksByProjectID(
    _ db: OpaquePointer,
    projectIDs: Set<UUID> = []
  ) throws -> [UUID: [RetainedTask]] {
    var result: [UUID: [RetainedTask]] = [:]
    let rows = try query(
      db,
      """
      SELECT project_id, id, reminder_external_identifier, title, note_text, is_completed,
        due_date, start_date, schedule_has_explicit_time, scheduled_duration_minutes,
        recurrence_rule_raw, priority
      FROM app_tasks
      \(projectFilterClause(column: "project_id", projectIDs: projectIDs))
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
      let priority = columnInt(statement, 11) ?? 0
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
          isManagedTask: true,
          priority: priority
        )
      )
    }
    for (projectID, task) in rows {
      result[projectID, default: []].append(task)
    }
    return result.mapValues { tasks in
      ProjectNoteReminderPolicy.visibleTasks(
        tasksHidingShadowedCompletedRecurringOccurrences(tasks)
      )
    }
  }

  private func loadProjectNoteMarkdownByProjectID(
    _ db: OpaquePointer,
    projectIDs: Set<UUID> = []
  ) throws -> [UUID: String] {
    let rows = try query(
      db,
      """
      SELECT project_id, note_text
      FROM app_tasks
      WHERE title = \(sqlStringLiteral(ProjectNoteReminderPolicy.title))
        AND priority = \(ProjectNoteReminderPolicy.lowPriority)
        \(projectFilterClausePrefix(column: "project_id", projectIDs: projectIDs, conjunction: "AND"))
      ORDER BY project_id, row_order, modified_at DESC;
      """
    ) { statement -> (UUID, String)? in
      guard let projectID = UUID(uuidString: columnText(statement, 0) ?? "") else {
        return nil
      }
      return (projectID, columnText(statement, 1) ?? "")
    }
    var result: [UUID: String] = [:]
    for row in rows.compactMap({ $0 }) where result[row.0] == nil {
      result[row.0] = row.1
    }
    return result
  }

  private func projectFilterClause(column: String, projectIDs: Set<UUID>) -> String {
    guard !projectIDs.isEmpty else { return "" }
    let quotedProjectIDs = projectIDs
      .map { sqlStringLiteral($0.uuidString) }
      .sorted()
      .joined(separator: ", ")
    return "WHERE \(column) IN (\(quotedProjectIDs))"
  }

  private func projectFilterClausePrefix(
    column: String,
    projectIDs: Set<UUID>,
    conjunction: String
  ) -> String {
    guard !projectIDs.isEmpty else { return "" }
    let quotedProjectIDs = projectIDs
      .map { sqlStringLiteral($0.uuidString) }
      .sorted()
      .joined(separator: ", ")
    return "\(conjunction) \(column) IN (\(quotedProjectIDs))"
  }

  static func isLocalCompletedRecurringExternalIdentifier(_ externalIdentifier: String?) -> Bool {
    normalizedValue(externalIdentifier)?.contains(localCompletedRecurringMarker) ?? false
  }

  private func tasksHidingShadowedCompletedRecurringOccurrences(
    _ tasks: [RetainedTask]
  ) -> [RetainedTask] {
    let activeRecurringTasks = tasks.filter { task in
      !task.isCompleted && task.schedule.canonicalRepeatRule != nil
    }
    let activeRecurringExternalIdentifiers = Set(
      activeRecurringTasks.compactMap(\.identity.reminderExternalIdentifier)
    )
    let activeRecurringCandidates = activeRecurringTasks.map { task in
      ActiveRecurringTaskCandidate(
        signature: RecurringTaskContentSignature(
          title: task.title,
          noteText: task.noteText
        ),
        dueDate: task.schedule.parsedDate
      )
    }
    guard !activeRecurringExternalIdentifiers.isEmpty || !activeRecurringCandidates.isEmpty else {
      return tasks
    }
    return tasks.filter { task in
      guard task.isCompleted else { return true }
      if Self.isLocalCompletedRecurringExternalIdentifier(task.identity.reminderExternalIdentifier) {
        return true
      }
      if let externalIdentifier = task.identity.reminderExternalIdentifier,
        let baseIdentifier = completedRecurringBaseIdentifier(from: externalIdentifier),
        activeRecurringExternalIdentifiers.contains(baseIdentifier)
      {
        return false
      }
      guard let completedCandidate = completedRecurringTaskCandidate(for: task)
      else {
        return true
      }
      return !activeRecurringCandidates.contains { activeCandidate in
        activeCandidate.signature == completedCandidate.signature
      }
    }
  }

  private struct ActiveRecurringTaskCandidate {
    let signature: RecurringTaskContentSignature
    let dueDate: Date?
  }

  private struct CompletedRecurringTaskCandidate {
    let signature: RecurringTaskContentSignature
    let dueDate: Date?
  }

  private struct RecurringTaskContentSignature: Hashable {
    let title: String

    init(title: String, noteText: String) {
      // Completed Reminder occurrences can retain an older note body after the
      // active recurring item is edited, so note text is not a stable match key.
      self.title = Self.normalizedText(title)
      _ = noteText
    }

    private static func normalizedText(_ value: String) -> String {
      value
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private func completedRecurringBaseIdentifier(
    from externalIdentifier: String
  ) -> String? {
    let marker = "::completed::"
    guard let markerRange = externalIdentifier.range(of: marker) else { return nil }
    let baseIdentifier = String(externalIdentifier[..<markerRange.lowerBound])
    return baseIdentifier.isEmpty ? nil : baseIdentifier
  }

  private static func localCompletedRecurringExternalIdentifier(
    baseExternalIdentifier: String?,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) -> String? {
    guard let baseExternalIdentifier = normalizedValue(baseExternalIdentifier) else {
      return nil
    }
    let occurrenceKey = ReminderScheduleMetadataCodec.encodeDate(
      dueDate,
      hasExplicitTime: hasExplicitTime
    ) ?? "undated"
    return "\(baseExternalIdentifier)\(localCompletedRecurringMarker)\(occurrenceKey)"
  }

  private static func localCompletedRecurringBaseIdentifier(
    from externalIdentifier: String
  ) -> String? {
    guard let markerRange = externalIdentifier.range(of: localCompletedRecurringMarker) else {
      return nil
    }
    let baseIdentifier = String(externalIdentifier[..<markerRange.lowerBound])
    return baseIdentifier.isEmpty ? nil : baseIdentifier
  }

  private static func normalizedValue(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  private func completedRecurringTaskCandidate(
    for task: RetainedTask
  ) -> CompletedRecurringTaskCandidate? {
    return CompletedRecurringTaskCandidate(
      signature: RecurringTaskContentSignature(
        title: task.title,
        noteText: task.noteText
      ),
      dueDate: task.schedule.parsedDate
    )
  }

}
