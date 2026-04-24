import Foundation
import SQLite3

enum WorkspaceTreeRepositoryError: LocalizedError, Equatable {
  case rootNodeMissing
  case nodeNotFound
  case taskNotFound
  case invalidParent
  case cannotMoveRoot
  case cannotMoveIntoDescendant
  case siblingNotFound
  case siblingParentMismatch

  var errorDescription: String? {
    switch self {
    case .rootNodeMissing:
      return "워크스페이스 루트 노드를 찾지 못했습니다."
    case .nodeNotFound:
      return "워크스페이스 노드를 찾지 못했습니다."
    case .taskNotFound:
      return "워크스페이스 할 일을 찾지 못했습니다."
    case .invalidParent:
      return "이 노드는 해당 부모 아래에 둘 수 없습니다."
    case .cannotMoveRoot:
      return "루트 노드는 이동할 수 없습니다."
    case .cannotMoveIntoDescendant:
      return "노드를 자기 자신의 하위 노드 아래로 이동할 수 없습니다."
    case .siblingNotFound:
      return "기준 형제 노드를 찾지 못했습니다."
    case .siblingParentMismatch:
      return "기준 형제 노드의 부모가 이동 대상 부모와 다릅니다."
    }
  }
}

struct WorkspaceSubtreeSnapshot: Equatable, Sendable {
  var root: WorkspaceNodeRecord
  var nodes: [WorkspaceNodeRecord]
  var tasks: [TaskRecord]
}

actor WorkspaceTreeRepository {
  private struct ResolvedTaskParent {
    let requestedParentID: UUID
    let storageNodeID: UUID
  }

  private let databaseURL: URL
  private let fileManager = FileManager.default
  private var hasEnsuredSchema = false

  init(databaseURL: URL) {
    self.databaseURL = databaseURL
  }

  nonisolated var dataDirectoryURL: URL {
    databaseURL.deletingLastPathComponent()
  }

  func rootNode() throws -> WorkspaceNodeRecord {
    guard let node = try fetchNode(id: NormalizedSourceSnapshot.rootNodeID) else {
      throw WorkspaceTreeRepositoryError.rootNodeMissing
    }
    return node
  }

  func fetchNode(id: UUID) throws -> WorkspaceNodeRecord? {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key, is_archived,
             created_at, updated_at, canonical_project_id, reminder_list_identifier,
             reminder_list_external_identifier
      FROM workspace_nodes_runtime
      WHERE id = ?1;
      """,
      in: db,
      statement: &statement
    )
    try bind(id.uuidString, at: 1, to: statement)

    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return try Self.decodeWorkspaceNode(from: statement)
  }

  func childNodes(parentID: UUID?, includeArchived: Bool = false) throws -> [WorkspaceNodeRecord] {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    let resolvedParentID = parentID ?? NormalizedSourceSnapshot.rootNodeID
    try prepare(
      """
      SELECT id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key, is_archived,
             created_at, updated_at, canonical_project_id, reminder_list_identifier,
             reminder_list_external_identifier
      FROM workspace_nodes_runtime
      WHERE parent_id = ?1 AND (?2 != 0 OR is_archived = 0)
      ORDER BY sort_key ASC, created_at ASC;
      """,
      in: db,
      statement: &statement
    )
    try bind(resolvedParentID.uuidString, at: 1, to: statement)
    try bind(includeArchived ? 1 : 0, at: 2, to: statement)

    var results: [WorkspaceNodeRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(try Self.decodeWorkspaceNode(from: statement))
    }
    return results
  }

  func projectNodes(includeArchived: Bool = true) throws -> [WorkspaceNodeRecord] {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key, is_archived,
             created_at, updated_at, canonical_project_id, reminder_list_identifier,
             reminder_list_external_identifier
      FROM workspace_nodes_runtime
      WHERE kind = 'project' AND (?1 != 0 OR is_archived = 0)
      ORDER BY parent_id ASC, sort_key ASC, created_at ASC;
      """,
      in: db,
      statement: &statement
    )
    try bind(includeArchived ? 1 : 0, at: 1, to: statement)

    var results: [WorkspaceNodeRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(try Self.decodeWorkspaceNode(from: statement))
    }
    return results
  }

  func fetchProjectNodes(
    canonicalProjectID: UUID,
    includeArchived: Bool = true
  ) throws -> [WorkspaceNodeRecord] {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key, is_archived,
             created_at, updated_at, canonical_project_id, reminder_list_identifier,
             reminder_list_external_identifier
      FROM workspace_nodes_runtime
      WHERE kind = 'project'
        AND (canonical_project_id = ?1 OR id = ?1)
        AND (?2 != 0 OR is_archived = 0)
      ORDER BY parent_id ASC, sort_key ASC, created_at ASC;
      """,
      in: db,
      statement: &statement
    )
    try bind(canonicalProjectID.uuidString, at: 1, to: statement)
    try bind(includeArchived ? 1 : 0, at: 2, to: statement)

    var results: [WorkspaceNodeRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(try Self.decodeWorkspaceNode(from: statement))
    }
    return results
  }

  func fetchTask(id: UUID) throws -> TaskRecord? {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    return try fetchTaskDirect(id: id, db: db)
  }

  func subtree(nodeID: UUID, includeArchived: Bool = true) throws -> WorkspaceSubtreeSnapshot {
    guard let root = try fetchNode(id: nodeID) else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    let nodes = try fetchDescendantNodes(nodeID: nodeID, includeArchived: includeArchived, db: db)
    let nodeIDs = Set(nodes.map(\.id))
    let tasks = try fetchTasks(nodeIDs: nodeIDs, includeArchived: includeArchived, db: db)
    return WorkspaceSubtreeSnapshot(root: root, nodes: nodes, tasks: tasks)
  }

  func breadcrumb(nodeID: UUID) throws -> [WorkspaceNodeRecord] {
    var nextID: UUID? = nodeID
    var items: [WorkspaceNodeRecord] = []

    while let currentID = nextID {
      guard let node = try fetchNode(id: currentID) else {
        throw WorkspaceTreeRepositoryError.nodeNotFound
      }
      items.append(node)
      nextID = node.parentID
    }

    return items.reversed()
  }

  func createProject(
    title: String,
    parentID: UUID? = nil,
    colorHex: String? = nil,
    iconName: String? = nil,
    noteMarkdown: String = "",
    canonicalProjectID: UUID? = nil,
    reminderListIdentifier: String? = nil,
    reminderListExternalIdentifier: String? = nil
  ) throws -> WorkspaceNodeRecord {
    try createNode(
      kind: .project,
      title: title,
      parentID: parentID,
      colorHex: colorHex,
      iconName: iconName,
      noteMarkdown: noteMarkdown,
      canonicalProjectID: canonicalProjectID,
      reminderListIdentifier: reminderListIdentifier,
      reminderListExternalIdentifier: reminderListExternalIdentifier
    )
  }

  func createFolder(
    title: String,
    parentID: UUID? = nil,
    colorHex: String? = nil,
    iconName: String? = nil
  ) throws -> WorkspaceNodeRecord {
    try createNode(
      kind: .folder,
      title: title,
      parentID: parentID,
      colorHex: colorHex,
      iconName: iconName,
      noteMarkdown: "",
      canonicalProjectID: nil,
      reminderListIdentifier: nil,
      reminderListExternalIdentifier: nil
    )
  }

  func updateNote(of nodeID: UUID, markdown: String) throws -> WorkspaceNodeRecord {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    guard try fetchNodeDirect(id: nodeID, db: db) != nil else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }

    let now = Date()
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      UPDATE workspace_nodes
      SET note_markdown = ?1,
          updated_at = ?2
      WHERE id = ?3;
      """,
      in: db,
      statement: &statement
    )
    try bind(markdown, at: 1, to: statement)
    try bind(now, at: 2, to: statement)
    try bind(nodeID.uuidString, at: 3, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }

    guard let updated = try fetchNode(id: nodeID) else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }
    return updated
  }

  func updateProjectIdentity(
    of nodeID: UUID,
    title: String,
    colorHex: String?,
    reminderListIdentifier: String?,
    reminderListExternalIdentifier: String?
  ) throws -> WorkspaceNodeRecord {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    guard try fetchNodeDirect(id: nodeID, db: db) != nil else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }

    let now = Date()
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      UPDATE workspace_nodes
      SET title = ?1,
          color_hex = ?2,
          reminder_list_identifier = ?3,
          reminder_list_external_identifier = ?4,
          updated_at = ?5
      WHERE id = ?6;
      """,
      in: db,
      statement: &statement
    )
    try bind(title, at: 1, to: statement)
    try bind(colorHex, at: 2, to: statement)
    try bind(reminderListIdentifier, at: 3, to: statement)
    try bind(reminderListExternalIdentifier, at: 4, to: statement)
    try bind(now, at: 5, to: statement)
    try bind(nodeID.uuidString, at: 6, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }

    guard let updated = try fetchNodeDirect(id: nodeID, db: db) else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }
    return updated
  }

  func relinkProjectIdentity(
    of nodeID: UUID,
    canonicalProjectID: UUID,
    title: String,
    colorHex: String?,
    reminderListIdentifier: String?,
    reminderListExternalIdentifier: String?
  ) throws -> WorkspaceNodeRecord {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    guard try fetchNodeDirect(id: nodeID, db: db) != nil else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }

    let now = Date()
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      UPDATE workspace_nodes
      SET canonical_project_id = ?1,
          title = ?2,
          color_hex = ?3,
          reminder_list_identifier = ?4,
          reminder_list_external_identifier = ?5,
          updated_at = ?6
      WHERE id = ?7;
      """,
      in: db,
      statement: &statement
    )
    try bind(canonicalProjectID.uuidString, at: 1, to: statement)
    try bind(title, at: 2, to: statement)
    try bind(colorHex, at: 3, to: statement)
    try bind(reminderListIdentifier, at: 4, to: statement)
    try bind(reminderListExternalIdentifier, at: 5, to: statement)
    try bind(now, at: 6, to: statement)
    try bind(nodeID.uuidString, at: 7, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }

    guard let updated = try fetchNodeDirect(id: nodeID, db: db) else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }
    return updated
  }

  func createTask(
    title: String,
    parentNodeID: UUID,
    parentTaskID: UUID? = nil,
    reminderIdentifier: String? = nil,
    reminderExternalIdentifier: String? = nil,
    parentTaskRemoteExternalIdentifier: String? = nil,
    remoteLastModifiedAt: Date? = nil
  ) throws -> TaskRecord {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    let resolvedParent = try resolveTaskParent(parentNodeID, db: db)
    let now = Date()
    let task = TaskRecord(
      id: UUID(),
      workspaceNodeID: resolvedParent.storageNodeID,
      canonicalProjectID: nil,
      reminderIdentifier: reminderIdentifier,
      reminderExternalIdentifier: reminderExternalIdentifier,
      parentTaskID: parentTaskID,
      parentTaskRemoteExternalIdentifier: parentTaskRemoteExternalIdentifier,
      title: title,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: nil,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      reminderNoteText: "",
      attachmentCount: 0,
      boardStageRaw: BoardStage.now.rawValue,
      importanceRaw: ImportanceLevel.minor.rawValue,
      rowOrder: try nextTaskRowOrder(
        parentNodeID: resolvedParent.storageNodeID,
        parentTaskID: parentTaskID,
        db: db
      ),
      requiredWorkDays: 0,
      completedWorkUnits: 0,
      completedWorkUnitDatesRaw: "",
      preparationScheduleOverridesRaw: "",
      isArchived: false,
      archivedAt: nil,
      isDirty: false,
      remoteLastModifiedAt: remoteLastModifiedAt,
      localUpdatedAt: now,
      createdAt: now
    )

    try insertTask(task, db: db)
    return task
  }

  func updateTaskReminderNote(
    of taskID: UUID,
    reminderText: String,
    remoteLastModifiedAt: Date? = nil
  ) throws -> TaskRecord {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    guard try fetchTaskDirect(id: taskID, db: db) != nil else {
      throw WorkspaceTreeRepositoryError.taskNotFound
    }

    let now = Date()
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      UPDATE tasks
      SET reminder_note_text = ?1,
          remote_last_modified_at = ?2,
          local_updated_at = ?3
      WHERE id = ?4;
      """,
      in: db,
      statement: &statement
    )
    try bind(reminderText, at: 1, to: statement)
    try bind(remoteLastModifiedAt, at: 2, to: statement)
    try bind(now, at: 3, to: statement)
    try bind(taskID.uuidString, at: 4, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }

    guard let updated = try fetchTaskDirect(id: taskID, db: db) else {
      throw WorkspaceTreeRepositoryError.taskNotFound
    }
    return updated
  }

  func promoteTaskToProject(
    taskID: UUID,
    parentNodeID: UUID,
    title: String,
    noteMarkdown: String,
    colorHex: String? = nil,
    iconName: String? = nil,
    canonicalProjectID: UUID? = nil,
    reminderListIdentifier: String? = nil,
    reminderListExternalIdentifier: String? = nil
  ) throws -> WorkspaceNodeRecord {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    guard try fetchTaskDirect(id: taskID, db: db) != nil else {
      throw WorkspaceTreeRepositoryError.taskNotFound
    }
    try validateParent(parentNodeID, db: db)

    let now = Date()
    let node = WorkspaceNodeRecord(
      id: UUID(),
      parentID: parentNodeID,
      kind: .project,
      title: title,
      noteMarkdown: noteMarkdown,
      colorHex: colorHex,
      iconName: iconName,
      sortKey: try nextSortKey(parentID: parentNodeID, db: db),
      isArchived: false,
      createdAt: now,
      updatedAt: now,
      canonicalProjectID: canonicalProjectID,
      reminderListIdentifier: reminderListIdentifier,
      reminderListExternalIdentifier: reminderListExternalIdentifier
    )

    try execute("BEGIN IMMEDIATE TRANSACTION;", in: db)
    do {
      try insertNode(node, db: db)
      try transferTaskAttachmentsToProject(
        taskID: taskID,
        projectNodeID: node.id,
        updatedAt: now,
        db: db
      )
      try deleteTaskRecord(taskID: taskID, db: db)
      try execute("COMMIT;", in: db)
    } catch {
      try? execute("ROLLBACK;", in: db)
      throw error
    }

    return node
  }

  func moveNode(
    _ nodeID: UUID,
    toParent newParentID: UUID?,
    afterSibling siblingID: UUID? = nil
  ) throws -> WorkspaceNodeRecord {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    guard let node = try fetchNode(id: nodeID) else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }
    guard node.id != NormalizedSourceSnapshot.rootNodeID else {
      throw WorkspaceTreeRepositoryError.cannotMoveRoot
    }
    try validateParent(newParentID, db: db)
    try validateMove(nodeID: nodeID, newParentID: newParentID, db: db)

    let insertionSortKey = try resolveInsertionSortKey(parentID: newParentID, afterSibling: siblingID, db: db)
    let now = Date()

    try execute("BEGIN IMMEDIATE TRANSACTION;", in: db)
    do {
      try shiftSiblingSortKeys(
        parentID: newParentID,
        startingAt: insertionSortKey,
        db: db
      )
      try updateNodeParentAndSortKey(
        nodeID: nodeID,
        parentID: newParentID,
        sortKey: insertionSortKey,
        updatedAt: now,
        db: db
      )
      try execute("COMMIT;", in: db)
    } catch {
      try? execute("ROLLBACK;", in: db)
      throw error
    }

    guard let moved = try fetchNode(id: nodeID) else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }
    return moved
  }

  func archiveSubtree(_ nodeID: UUID, archivedAt: Date = .now) throws {
    try mutateArchiveState(nodeID: nodeID, isArchived: true, archivedAt: archivedAt)
  }

  func restoreSubtree(_ nodeID: UUID) throws {
    try mutateArchiveState(nodeID: nodeID, isArchived: false, archivedAt: nil)
  }

  func deleteSubtreesPermanently(rootNodeIDs: [UUID]) throws -> Set<UUID> {
    let uniqueRootIDs = Array(Set(rootNodeIDs))
    guard !uniqueRootIDs.isEmpty else { return [] }

    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    var descendantNodeIDs: Set<UUID> = []
    for rootNodeID in uniqueRootIDs {
      guard try fetchNodeDirect(id: rootNodeID, db: db) != nil else { continue }
      let descendants = try fetchDescendantNodes(nodeID: rootNodeID, includeArchived: true, db: db)
      descendantNodeIDs.formUnion(descendants.map(\.id))
    }

    guard !descendantNodeIDs.isEmpty else { return [] }
    let descendantTasks = try fetchTasks(nodeIDs: descendantNodeIDs, includeArchived: true, db: db)
    let taskIDs = Set(descendantTasks.map(\.id))

    try execute("BEGIN IMMEDIATE TRANSACTION;", in: db)
    do {
      try deleteAttachmentReferences(
        ownerType: .task,
        ownerIDs: Array(taskIDs),
        db: db
      )
      try deleteTasks(workspaceNodeIDs: Array(descendantNodeIDs), db: db)
      try deleteAttachmentReferences(
        ownerType: .project,
        ownerIDs: Array(descendantNodeIDs),
        db: db
      )
      try deleteWorkspaceNodes(nodeIDs: Array(descendantNodeIDs), db: db)
      try execute("COMMIT;", in: db)
    } catch {
      try? execute("ROLLBACK;", in: db)
      throw error
    }

    return descendantNodeIDs
  }

  private func createNode(
    kind: WorkspaceNodeKind,
    title: String,
    parentID: UUID?,
    colorHex: String?,
    iconName: String?,
    noteMarkdown: String,
    canonicalProjectID: UUID?,
    reminderListIdentifier: String?,
    reminderListExternalIdentifier: String?
  ) throws -> WorkspaceNodeRecord {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    try validateParent(parentID, db: db)
    let now = Date()
    let node = WorkspaceNodeRecord(
      id: UUID(),
      parentID: parentID ?? NormalizedSourceSnapshot.rootNodeID,
      kind: kind,
      title: title,
      noteMarkdown: noteMarkdown,
      colorHex: colorHex,
      iconName: iconName,
      sortKey: try nextSortKey(parentID: parentID ?? NormalizedSourceSnapshot.rootNodeID, db: db),
      isArchived: false,
      createdAt: now,
      updatedAt: now,
      canonicalProjectID: canonicalProjectID,
      reminderListIdentifier: reminderListIdentifier,
      reminderListExternalIdentifier: reminderListExternalIdentifier
    )

    try insertNode(node, db: db)
    return node
  }

  private func insertNode(_ node: WorkspaceNodeRecord, db: OpaquePointer?) throws {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      INSERT INTO workspace_nodes(
        id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key, is_archived,
        created_at, updated_at, canonical_project_id, reminder_list_identifier,
        reminder_list_external_identifier
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14);
      """,
      in: db,
      statement: &statement
    )
    try bind(node.id.uuidString, at: 1, to: statement)
    try bind(node.parentID?.uuidString, at: 2, to: statement)
    try bind(node.kind.rawValue, at: 3, to: statement)
    try bind(node.title, at: 4, to: statement)
    try bind(node.noteMarkdown, at: 5, to: statement)
    try bind(node.colorHex, at: 6, to: statement)
    try bind(node.iconName, at: 7, to: statement)
    try bind(node.sortKey, at: 8, to: statement)
    try bind(node.isArchived, at: 9, to: statement)
    try bind(node.createdAt, at: 10, to: statement)
    try bind(node.updatedAt, at: 11, to: statement)
    try bind(node.canonicalProjectID?.uuidString, at: 12, to: statement)
    try bind(node.reminderListIdentifier, at: 13, to: statement)
    try bind(node.reminderListExternalIdentifier, at: 14, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }
  }

  private func insertTask(_ rawTask: TaskRecord, db: OpaquePointer?) throws {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    let task = rawTask.normalizedReminderDateStorage()
    try prepare(
      """
      INSERT INTO tasks(
        id, workspace_node_id, canonical_project_id, reminder_identifier, reminder_external_identifier,
        parent_task_id, parent_task_remote_external_identifier,
        title, is_completed, completion_date, start_date, due_date, schedule_has_explicit_time,
        scheduled_duration_minutes, priority, recurrence_rule_raw, is_flagged, reminder_note_text,
        app_note_markdown, attachment_count, board_stage_raw, importance_raw, row_order, block_reason,
        required_work_days, completed_work_units, completed_work_unit_dates_raw,
        preparation_schedule_overrides_raw, is_archived, archived_at, is_dirty,
        remote_last_modified_at, local_updated_at, created_at, last_synced_reminder_title,
        last_synced_reminder_note_body, last_synced_reminder_modified_at, reminder_note_conflict_excerpt
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38);
      """,
      in: db,
      statement: &statement
    )
    try bind(task.id.uuidString, at: 1, to: statement)
    try bind(task.workspaceNodeID.uuidString, at: 2, to: statement)
    try bind(task.canonicalProjectID?.uuidString, at: 3, to: statement)
    try bind(task.reminderIdentifier, at: 4, to: statement)
    try bind(task.reminderExternalIdentifier, at: 5, to: statement)
    try bind(task.parentTaskID?.uuidString, at: 6, to: statement)
    try bind(task.parentTaskRemoteExternalIdentifier, at: 7, to: statement)
    try bind(task.title, at: 8, to: statement)
    try bind(task.isCompleted, at: 9, to: statement)
    try bind(task.completionDate, at: 10, to: statement)
    try bind(task.startDate, at: 11, to: statement)
    try bind(task.dueDate, at: 12, to: statement)
    try bind(task.scheduleHasExplicitTime, at: 13, to: statement)
    try bind(task.scheduledDurationMinutes.map(Int64.init), at: 14, to: statement)
    try bind(Int64(task.priority), at: 15, to: statement)
    try bind(task.recurrenceRuleRaw, at: 16, to: statement)
    try bind(task.isFlagged, at: 17, to: statement)
    try bind(task.reminderNoteText, at: 18, to: statement)
    try bind("", at: 19, to: statement)
    try bind(Int64(task.attachmentCount), at: 20, to: statement)
    try bind(task.boardStageRaw, at: 21, to: statement)
    try bind(task.importanceRaw, at: 22, to: statement)
    try bind(Int64(task.rowOrder), at: 23, to: statement)
    try bind("", at: 24, to: statement)
    try bind(Int64(task.requiredWorkDays), at: 25, to: statement)
    try bind(Int64(task.completedWorkUnits), at: 26, to: statement)
    try bind(task.completedWorkUnitDatesRaw, at: 27, to: statement)
    try bind(task.preparationScheduleOverridesRaw, at: 28, to: statement)
    try bind(task.isArchived, at: 29, to: statement)
    try bind(task.archivedAt, at: 30, to: statement)
    try bind(task.isDirty, at: 31, to: statement)
    try bind(task.remoteLastModifiedAt, at: 32, to: statement)
    try bind(task.localUpdatedAt, at: 33, to: statement)
    try bind(task.createdAt, at: 34, to: statement)
    try bind(task.lastSyncedReminderTitle, at: 35, to: statement)
    try bind(task.lastSyncedReminderNoteBody, at: 36, to: statement)
    try bind(task.lastSyncedReminderModifiedAt, at: 37, to: statement)
    try bind(task.reminderNoteConflictExcerpt, at: 38, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }
  }

  private func mutateArchiveState(
    nodeID: UUID,
    isArchived: Bool,
    archivedAt: Date?
  ) throws {
    try ensureSchema()
    let db = try openDatabase()
    defer { sqlite3_close(db) }

    guard try fetchNode(id: nodeID) != nil else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }

    let descendants = try fetchDescendantNodes(nodeID: nodeID, includeArchived: true, db: db)
    let descendantIDs = descendants.map(\.id)
    let now = Date()
    let archivedAtSQL: String = archivedAt.map { String($0.timeIntervalSince1970) } ?? "NULL"

    try execute("BEGIN IMMEDIATE TRANSACTION;", in: db)
    do {
      for descendantID in descendantIDs {
        try execute(
          """
          UPDATE workspace_nodes
          SET is_archived = \(isArchived ? 1 : 0),
              updated_at = \(now.timeIntervalSince1970)
          WHERE id = '\(descendantID.uuidString)';
          """,
          in: db
        )
      }

      for descendantID in descendantIDs {
        try execute(
          """
          UPDATE tasks
          SET is_archived = \(isArchived ? 1 : 0),
              archived_at = \(archivedAtSQL),
              local_updated_at = \(now.timeIntervalSince1970)
          WHERE workspace_node_id = '\(descendantID.uuidString)';
          """,
          in: db
        )
      }

      try execute("COMMIT;", in: db)
    } catch {
      try? execute("ROLLBACK;", in: db)
      throw error
    }
  }

  private func validateParent(_ parentID: UUID?, db: OpaquePointer?) throws {
    let resolvedParentID = parentID ?? NormalizedSourceSnapshot.rootNodeID
    guard let parent = try fetchNodeDirect(id: resolvedParentID, db: db) else {
      throw WorkspaceTreeRepositoryError.invalidParent
    }
    guard [.rootSpace, .folder, .project].contains(parent.kind) else {
      throw WorkspaceTreeRepositoryError.invalidParent
    }
  }

  private func resolveTaskParent(
    _ parentID: UUID,
    db: OpaquePointer?
  ) throws -> ResolvedTaskParent {
    if let parent = try fetchNodeDirect(id: parentID, db: db) {
      guard [.rootSpace, .folder, .project].contains(parent.kind) else {
        throw WorkspaceTreeRepositoryError.invalidParent
      }
      return ResolvedTaskParent(requestedParentID: parentID, storageNodeID: parentID)
    }

    if let projectNodeID = try resolveProjectNodeIDForRootBullet(parentID, db: db) {
      return ResolvedTaskParent(requestedParentID: parentID, storageNodeID: projectNodeID)
    }

    throw WorkspaceTreeRepositoryError.invalidParent
  }

  private func validateMove(nodeID: UUID, newParentID: UUID?, db: OpaquePointer?) throws {
    guard let newParentID else { return }
    let descendants = try fetchDescendantNodes(nodeID: nodeID, includeArchived: true, db: db)
    let descendantIDs = Set(descendants.map(\.id))
    if descendantIDs.contains(newParentID) {
      throw WorkspaceTreeRepositoryError.cannotMoveIntoDescendant
    }
  }

  private func nextSortKey(parentID: UUID, db: OpaquePointer?) throws -> Int64 {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT COALESCE(MAX(sort_key), -1) + 1
      FROM workspace_nodes
      WHERE parent_id = ?1;
      """,
      in: db,
      statement: &statement
    )
    try bind(parentID.uuidString, at: 1, to: statement)

    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return sqlite3_column_int64(statement, 0)
  }

  private func nextTaskRowOrder(
    parentNodeID: UUID,
    parentTaskID: UUID?,
    db: OpaquePointer?
  ) throws -> Int {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT COALESCE(MAX(row_order), -1) + 1
      FROM tasks
      WHERE workspace_node_id = ?1
        AND (
          (?2 IS NULL AND parent_task_id IS NULL)
          OR parent_task_id = ?2
        );
      """,
      in: db,
      statement: &statement
    )
    try bind(parentNodeID.uuidString, at: 1, to: statement)
    try bind(parentTaskID?.uuidString, at: 2, to: statement)

    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int64(statement, 0))
  }

  private func resolveProjectNodeIDForRootBullet(
    _ bulletID: UUID,
    db: OpaquePointer?
  ) throws -> UUID? {
    try ReminderProjectionSidecarReadService.resolveProjectNodeIDForRootBullet(
      bulletID,
      dataDirectory: dataDirectoryURL
    ) { reminderListExternalIdentifier in
      try fetchProjectNodeID(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        db: db
      )
    }
  }

  private func fetchProjectNodeID(
    reminderListExternalIdentifier: String,
    db: OpaquePointer?
  ) throws -> UUID? {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id
      FROM workspace_nodes_runtime
      WHERE reminder_list_external_identifier = ?1
        AND kind = ?2
      ORDER BY created_at ASC
      LIMIT 1;
      """,
      in: db,
      statement: &statement
    )
    try bind(reminderListExternalIdentifier, at: 1, to: statement)
    try bind(WorkspaceNodeKind.project.rawValue, at: 2, to: statement)

    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return UUID(uuidString: String(cString: sqlite3_column_text(statement, 0)))
  }

  private func resolveInsertionSortKey(
    parentID: UUID?,
    afterSibling siblingID: UUID?,
    db: OpaquePointer?
  ) throws -> Int64 {
    let resolvedParentID = parentID ?? NormalizedSourceSnapshot.rootNodeID
    guard let siblingID else {
      return try nextSortKey(parentID: resolvedParentID, db: db)
    }

    guard let sibling = try fetchNodeDirect(id: siblingID, db: db) else {
      throw WorkspaceTreeRepositoryError.siblingNotFound
    }
    guard sibling.parentID == resolvedParentID else {
      throw WorkspaceTreeRepositoryError.siblingParentMismatch
    }
    return sibling.sortKey + 1
  }

  private func shiftSiblingSortKeys(
    parentID: UUID?,
    startingAt sortKey: Int64,
    db: OpaquePointer?
  ) throws {
    let resolvedParentID = parentID ?? NormalizedSourceSnapshot.rootNodeID
    try execute(
      """
      UPDATE workspace_nodes
      SET sort_key = sort_key + 1
      WHERE parent_id = '\(resolvedParentID.uuidString)'
        AND sort_key >= \(sortKey);
      """,
      in: db
    )
  }

  private func updateNodeParentAndSortKey(
    nodeID: UUID,
    parentID: UUID?,
    sortKey: Int64,
    updatedAt: Date,
    db: OpaquePointer?
  ) throws {
    let resolvedParentID = parentID ?? NormalizedSourceSnapshot.rootNodeID
    try execute(
      """
      UPDATE workspace_nodes
      SET parent_id = '\(resolvedParentID.uuidString)',
          sort_key = \(sortKey),
          updated_at = \(updatedAt.timeIntervalSince1970)
      WHERE id = '\(nodeID.uuidString)';
      """,
      in: db
    )
  }

  private func fetchDescendantNodes(
    nodeID: UUID,
    includeArchived: Bool,
    db: OpaquePointer?
  ) throws -> [WorkspaceNodeRecord] {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      WITH RECURSIVE descendants AS (
        SELECT id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key,
               is_archived, created_at, updated_at, canonical_project_id, reminder_list_identifier,
               reminder_list_external_identifier
        FROM workspace_nodes_runtime
        WHERE id = ?1
        UNION ALL
        SELECT w.id, w.parent_id, w.kind, w.title, w.note_markdown, w.color_hex, w.icon_name,
               w.sort_key, w.is_archived, w.created_at, w.updated_at, w.canonical_project_id,
               w.reminder_list_identifier, w.reminder_list_external_identifier
        FROM workspace_nodes_runtime w
        JOIN descendants d ON w.parent_id = d.id
      )
      SELECT *
      FROM descendants
      WHERE (?2 != 0 OR is_archived = 0)
      ORDER BY sort_key ASC, created_at ASC;
      """,
      in: db,
      statement: &statement
    )
    try bind(nodeID.uuidString, at: 1, to: statement)
    try bind(includeArchived ? 1 : 0, at: 2, to: statement)

    var results: [WorkspaceNodeRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(try Self.decodeWorkspaceNode(from: statement))
    }
    return results
  }

  private func fetchTasks(
    nodeIDs: Set<UUID>,
    includeArchived: Bool,
    db: OpaquePointer?
  ) throws -> [TaskRecord] {
    guard !nodeIDs.isEmpty else { return [] }
    let ids = nodeIDs.map(\.uuidString).joined(separator: "','")
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT
        id, workspace_node_id, canonical_project_id, reminder_identifier, reminder_external_identifier,
        parent_task_id, parent_task_remote_external_identifier,
        title, is_completed, completion_date, start_date, due_date, schedule_has_explicit_time,
        scheduled_duration_minutes, priority, recurrence_rule_raw, is_flagged, reminder_note_text,
        app_note_markdown, attachment_count, board_stage_raw, importance_raw, row_order,
        block_reason, required_work_days, completed_work_units, completed_work_unit_dates_raw,
        preparation_schedule_overrides_raw, is_archived, archived_at, is_dirty,
        remote_last_modified_at, local_updated_at, created_at,
        last_synced_reminder_title, last_synced_reminder_note_body,
        last_synced_reminder_modified_at, reminder_note_conflict_excerpt
      FROM tasks_runtime
      WHERE workspace_node_id IN ('\(ids)')
        AND (?1 != 0 OR is_archived = 0)
      ORDER BY workspace_node_id ASC, row_order ASC, created_at ASC;
      """,
      in: db,
      statement: &statement
    )
    try bind(includeArchived ? 1 : 0, at: 1, to: statement)

    var results: [TaskRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(try Self.decodeTask(from: statement))
    }
    return results
  }

  private func fetchNodeDirect(id: UUID, db: OpaquePointer?) throws -> WorkspaceNodeRecord? {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key, is_archived,
             created_at, updated_at, canonical_project_id, reminder_list_identifier,
             reminder_list_external_identifier
      FROM workspace_nodes_runtime
      WHERE id = ?1;
      """,
      in: db,
      statement: &statement
    )
    try bind(id.uuidString, at: 1, to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return try Self.decodeWorkspaceNode(from: statement)
  }

  private func fetchTaskDirect(id: UUID, db: OpaquePointer?) throws -> TaskRecord? {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT
        id, workspace_node_id, canonical_project_id, reminder_identifier, reminder_external_identifier,
        parent_task_id, parent_task_remote_external_identifier,
        title, is_completed, completion_date, start_date, due_date, schedule_has_explicit_time,
        scheduled_duration_minutes, priority, recurrence_rule_raw, is_flagged, reminder_note_text,
        app_note_markdown, attachment_count, board_stage_raw, importance_raw, row_order,
        block_reason, required_work_days, completed_work_units, completed_work_unit_dates_raw,
        preparation_schedule_overrides_raw, is_archived, archived_at, is_dirty,
        remote_last_modified_at, local_updated_at, created_at,
        last_synced_reminder_title, last_synced_reminder_note_body,
        last_synced_reminder_modified_at, reminder_note_conflict_excerpt
      FROM tasks_runtime
      WHERE id = ?1;
      """,
      in: db,
      statement: &statement
    )
    try bind(id.uuidString, at: 1, to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return try Self.decodeTask(from: statement)
  }

  private func transferTaskAttachmentsToProject(
    taskID: UUID,
    projectNodeID: UUID,
    updatedAt: Date,
    db: OpaquePointer?
  ) throws {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      UPDATE attachment_references
      SET owner_type_raw = ?1,
          owner_id = ?2,
          updated_at = ?3
      WHERE owner_type_raw = ?4
        AND owner_id = ?5;
      """,
      in: db,
      statement: &statement
    )
    try bind(AttachmentOwnerType.project.rawValue, at: 1, to: statement)
    try bind(projectNodeID.uuidString, at: 2, to: statement)
    try bind(updatedAt, at: 3, to: statement)
    try bind(AttachmentOwnerType.task.rawValue, at: 4, to: statement)
    try bind(taskID.uuidString, at: 5, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }
  }

  private func deleteTaskRecord(taskID: UUID, db: OpaquePointer?) throws {
    try execute(
      """
      DELETE FROM tasks
      WHERE id = '\(taskID.uuidString)';
      """,
      in: db
    )
  }

  private func deleteAttachmentReferences(
    ownerType: AttachmentOwnerType,
    ownerIDs: [UUID],
    db: OpaquePointer?
  ) throws {
    guard !ownerIDs.isEmpty else { return }
    let ownerIDList = quotedUUIDList(ownerIDs)
    try execute(
      """
      DELETE FROM attachment_references
      WHERE owner_type_raw = '\(ownerType.rawValue)'
        AND owner_id IN (\(ownerIDList));
      """,
      in: db
    )
  }

  private func deleteTasks(workspaceNodeIDs: [UUID], db: OpaquePointer?) throws {
    guard !workspaceNodeIDs.isEmpty else { return }
    let nodeIDList = quotedUUIDList(workspaceNodeIDs)
    try execute(
      """
      DELETE FROM tasks
      WHERE workspace_node_id IN (\(nodeIDList));
      """,
      in: db
    )
  }

  private func deleteWorkspaceNodes(nodeIDs: [UUID], db: OpaquePointer?) throws {
    guard !nodeIDs.isEmpty else { return }
    let nodeIDList = quotedUUIDList(nodeIDs)
    try execute(
      """
      DELETE FROM workspace_nodes
      WHERE id IN (\(nodeIDList));
      """,
      in: db
    )
  }

  private func quotedUUIDList(_ ids: [UUID]) -> String {
    ids
      .map(\.uuidString)
      .sorted()
      .map { "'\($0)'" }
      .joined(separator: ",")
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

  private func prepare(_ sql: String, in db: OpaquePointer?, statement: inout OpaquePointer?) throws {
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

  private func bind(_ value: Bool, at index: Int32, to statement: OpaquePointer?) throws {
    try bind(value ? 1 : 0, at: index, to: statement)
  }

  private func bind(_ value: Int, at index: Int32, to statement: OpaquePointer?) throws {
    guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed("bind int failed")
    }
  }

  private func bind(_ value: Int64, at index: Int32, to statement: OpaquePointer?) throws {
    guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed("bind int64 failed")
    }
  }

  private func bind(_ value: Int64?, at index: Int32, to statement: OpaquePointer?) throws {
    if let value {
      try bind(value, at: index, to: statement)
    } else {
      guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
        throw NormalizedPersistenceError.sqliteStepFailed("bind int64 null failed")
      }
    }
  }

  private func bind(_ value: Date?, at index: Int32, to statement: OpaquePointer?) throws {
    if let value {
      guard sqlite3_bind_double(statement, index, value.timeIntervalSince1970) == SQLITE_OK else {
        throw NormalizedPersistenceError.sqliteStepFailed("bind date failed")
      }
    } else {
      guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
        throw NormalizedPersistenceError.sqliteStepFailed("bind date null failed")
      }
    }
  }

  private static func decodeWorkspaceNode(from statement: OpaquePointer?) throws -> WorkspaceNodeRecord {
    guard
      let id = columnUUID(statement, index: 0),
      let kindRaw = columnText(statement, index: 2),
      let kind = WorkspaceNodeKind(rawValue: kindRaw),
      let title = columnText(statement, index: 3),
      let noteMarkdown = columnText(statement, index: 4)
    else {
      throw NormalizedPersistenceError.metadataDecodeFailed
    }

    return WorkspaceNodeRecord(
      id: id,
      parentID: columnUUID(statement, index: 1),
      kind: kind,
      title: title,
      noteMarkdown: noteMarkdown,
      colorHex: columnText(statement, index: 5),
      iconName: columnText(statement, index: 6),
      sortKey: sqlite3_column_int64(statement, 7),
      isArchived: sqlite3_column_int(statement, 8) != 0,
      createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
      updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
      canonicalProjectID: columnUUID(statement, index: 11),
      reminderListIdentifier: columnText(statement, index: 12),
      reminderListExternalIdentifier: columnText(statement, index: 13)
    )
  }

  private static func decodeTask(from statement: OpaquePointer?) throws -> TaskRecord {
    guard
      let id = columnUUID(statement, index: 0),
      let workspaceNodeID = columnUUID(statement, index: 1),
      let title = columnText(statement, index: 7),
      let reminderNoteText = columnText(statement, index: 17),
      let boardStageRaw = columnText(statement, index: 20),
      let importanceRaw = columnText(statement, index: 21),
      let completedWorkUnitDatesRaw = columnText(statement, index: 26),
      let preparationScheduleOverridesRaw = columnText(statement, index: 27)
    else {
      throw NormalizedPersistenceError.metadataDecodeFailed
    }

    let lastSyncedReminderTitle = columnText(statement, index: 34) ?? ""
    let lastSyncedReminderNoteBody = columnText(statement, index: 35) ?? ""

    return TaskRecord(
      id: id,
      workspaceNodeID: workspaceNodeID,
      canonicalProjectID: columnUUID(statement, index: 2),
      reminderIdentifier: columnText(statement, index: 3),
      reminderExternalIdentifier: columnText(statement, index: 4),
      parentTaskID: columnUUID(statement, index: 5),
      parentTaskRemoteExternalIdentifier: columnText(statement, index: 6),
      title: title,
      isCompleted: sqlite3_column_int(statement, 8) != 0,
      completionDate: columnDate(statement, index: 9),
      startDate: columnDate(statement, index: 10),
      dueDate: columnDate(statement, index: 11),
      scheduleHasExplicitTime: sqlite3_column_int(statement, 12) != 0,
      scheduledDurationMinutes: columnOptionalInt(statement, index: 13),
      priority: Int(sqlite3_column_int64(statement, 14)),
      recurrenceRuleRaw: columnText(statement, index: 15),
      isFlagged: sqlite3_column_int(statement, 16) != 0,
      reminderNoteText: reminderNoteText,
      attachmentCount: Int(sqlite3_column_int64(statement, 19)),
      lastSyncedReminderTitle: lastSyncedReminderTitle,
      lastSyncedReminderNoteBody: lastSyncedReminderNoteBody,
      lastSyncedReminderModifiedAt: columnDate(statement, index: 36),
      reminderNoteConflictExcerpt: columnText(statement, index: 37),
      boardStageRaw: boardStageRaw,
      importanceRaw: importanceRaw,
      rowOrder: Int(sqlite3_column_int64(statement, 22)),
      requiredWorkDays: Int(sqlite3_column_int64(statement, 24)),
      completedWorkUnits: Int(sqlite3_column_int64(statement, 25)),
      completedWorkUnitDatesRaw: completedWorkUnitDatesRaw,
      preparationScheduleOverridesRaw: preparationScheduleOverridesRaw,
      isArchived: sqlite3_column_int(statement, 28) != 0,
      archivedAt: columnDate(statement, index: 29),
      isDirty: sqlite3_column_int(statement, 30) != 0,
      remoteLastModifiedAt: columnDate(statement, index: 31),
      localUpdatedAt: columnDate(statement, index: 32) ?? .distantPast,
      createdAt: columnDate(statement, index: 33) ?? .distantPast
    ).normalizedReminderDateStorage()
  }

  private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: pointer)
  }

  private static func columnUUID(_ statement: OpaquePointer?, index: Int32) -> UUID? {
    guard let value = columnText(statement, index: index) else { return nil }
    return UUID(uuidString: value)
  }

  private static func columnDate(_ statement: OpaquePointer?, index: Int32) -> Date? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
  }

  private static func columnOptionalInt(_ statement: OpaquePointer?, index: Int32) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int64(statement, index))
  }

  private static var sqliteTransient: sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  }

  private static func sqliteMessage(_ db: OpaquePointer?) -> String {
    guard let db, let message = sqlite3_errmsg(db) else { return "unknown" }
    return String(cString: message)
  }
}
