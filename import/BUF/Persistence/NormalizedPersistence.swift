import Foundation
import SQLite3
import SwiftData

/// Phase 13 cleanup boundary freeze:
/// This file is retained runtime sqlite/read infrastructure, not a legacy deletion target.
/// `workspace_nodes_runtime`, `tasks_runtime`, `task_project_clone_placements`,
/// `attachment_references`, and `NormalizedDocumentReferenceRepository` remain app steady-state.
enum WorkspaceNodeKind: String, Codable, CaseIterable {
    case rootSpace
    case folder
    case project
    case smartCollection
}

enum AttachmentReferenceStorageKind: String, Codable, CaseIterable {
    case copiedFile
    case securityScopedBookmark
}

struct WorkspaceNodeRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var parentID: UUID?
    var kind: WorkspaceNodeKind
    var title: String
    var noteMarkdown: String
    var colorHex: String?
    var iconName: String?
    var sortKey: Int64
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var canonicalProjectID: UUID?
    var reminderListIdentifier: String?
    var reminderListExternalIdentifier: String?

    init(
        id: UUID,
        parentID: UUID?,
        kind: WorkspaceNodeKind,
        title: String,
        noteMarkdown: String,
        colorHex: String?,
        iconName: String?,
        sortKey: Int64,
        isArchived: Bool,
        createdAt: Date,
        updatedAt: Date,
        canonicalProjectID: UUID? = nil,
        reminderListIdentifier: String?,
        reminderListExternalIdentifier: String?
    ) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.title = title
        self.noteMarkdown = noteMarkdown
        self.colorHex = colorHex
        self.iconName = iconName
        self.sortKey = sortKey
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.canonicalProjectID = canonicalProjectID ?? (kind == .project ? id : nil)
        self.reminderListIdentifier = reminderListIdentifier
        self.reminderListExternalIdentifier = reminderListExternalIdentifier
    }

    var projectID: UUID? {
        kind == .project ? (canonicalProjectID ?? id) : nil
    }
}

struct TaskRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var workspaceNodeID: UUID
    var canonicalProjectID: UUID?
    var reminderIdentifier: String?
    var reminderExternalIdentifier: String?
    var parentTaskID: UUID?
    var parentTaskRemoteExternalIdentifier: String?
    var title: String
    var isCompleted: Bool
    var completionDate: Date?
    var startDate: Date?
    var dueDate: Date?
    var scheduleHasExplicitTime: Bool
    var scheduledDurationMinutes: Int?
    var priority: Int
    var recurrenceRuleRaw: String?
    var isFlagged: Bool
    var reminderNoteText: String
    var attachmentCount: Int
    var lastSyncedReminderTitle: String = ""
    var lastSyncedReminderNoteBody: String = ""
    var lastSyncedReminderModifiedAt: Date? = nil
    var reminderNoteConflictExcerpt: String? = nil
    var boardStageRaw: String
    var importanceRaw: String
    var rowOrder: Int
    var requiredWorkDays: Int
    var completedWorkUnits: Int
    var completedWorkUnitDatesRaw: String
    var preparationScheduleOverridesRaw: String
    var isArchived: Bool
    var archivedAt: Date?
    var isDirty: Bool
    var remoteLastModifiedAt: Date?
    var localUpdatedAt: Date
    var createdAt: Date

    init(
        id: UUID,
        workspaceNodeID: UUID,
        canonicalProjectID: UUID? = nil,
        reminderIdentifier: String?,
        reminderExternalIdentifier: String?,
        parentTaskID: UUID? = nil,
        parentTaskRemoteExternalIdentifier: String? = nil,
        title: String,
        isCompleted: Bool,
        completionDate: Date?,
        startDate: Date?,
        dueDate: Date?,
        scheduleHasExplicitTime: Bool,
        scheduledDurationMinutes: Int?,
        priority: Int,
        recurrenceRuleRaw: String?,
        isFlagged: Bool,
        reminderNoteText: String,
        attachmentCount: Int,
        lastSyncedReminderTitle: String = "",
        lastSyncedReminderNoteBody: String = "",
        lastSyncedReminderModifiedAt: Date? = nil,
        reminderNoteConflictExcerpt: String? = nil,
        boardStageRaw: String,
        importanceRaw: String,
        rowOrder: Int,
        requiredWorkDays: Int,
        completedWorkUnits: Int,
        completedWorkUnitDatesRaw: String,
        preparationScheduleOverridesRaw: String,
        isArchived: Bool,
        archivedAt: Date?,
        isDirty: Bool,
        remoteLastModifiedAt: Date?,
        localUpdatedAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.workspaceNodeID = workspaceNodeID
        self.canonicalProjectID = canonicalProjectID
        self.reminderIdentifier = reminderIdentifier
        self.reminderExternalIdentifier = reminderExternalIdentifier
        self.parentTaskID = parentTaskID
        self.parentTaskRemoteExternalIdentifier = parentTaskRemoteExternalIdentifier
        self.title = title
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.startDate = startDate
        self.dueDate = dueDate
        self.scheduleHasExplicitTime = scheduleHasExplicitTime
        self.scheduledDurationMinutes = scheduledDurationMinutes
        self.priority = priority
        self.recurrenceRuleRaw = recurrenceRuleRaw
        self.isFlagged = isFlagged
        self.reminderNoteText = reminderNoteText
        self.attachmentCount = attachmentCount
        self.lastSyncedReminderTitle = lastSyncedReminderTitle
        self.lastSyncedReminderNoteBody = lastSyncedReminderNoteBody
        self.lastSyncedReminderModifiedAt = lastSyncedReminderModifiedAt
        self.reminderNoteConflictExcerpt = reminderNoteConflictExcerpt
        self.boardStageRaw = boardStageRaw
        self.importanceRaw = importanceRaw
        self.rowOrder = rowOrder
        self.requiredWorkDays = requiredWorkDays
        self.completedWorkUnits = completedWorkUnits
        self.completedWorkUnitDatesRaw = completedWorkUnitDatesRaw
        self.preparationScheduleOverridesRaw = preparationScheduleOverridesRaw
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.isDirty = isDirty
        self.remoteLastModifiedAt = remoteLastModifiedAt
        self.localUpdatedAt = localUpdatedAt
        self.createdAt = createdAt
    }

    var projectID: UUID? {
        canonicalProjectID
    }
}

struct TaskProjectClonePlacementRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var taskID: UUID
    var projectID: UUID
    var parentTaskID: UUID?
    var rowOrder: Int
    var createdAt: Date
    var updatedAt: Date
}

enum ReminderTaskDateCanonicalizer {
    static func unifiedDate(
        dueDate: Date?,
        startDate: Date?,
        displayedDate: Date? = nil
    ) -> Date? {
        dueDate ?? startDate ?? displayedDate
    }

    static func normalizedStorage(
        dueDate: Date?,
        startDate: Date?,
        displayedDate: Date? = nil
    ) -> (startDate: Date?, dueDate: Date?) {
        (nil, unifiedDate(dueDate: dueDate, startDate: startDate, displayedDate: displayedDate))
    }
}

extension TaskRecord {
    var reminderDate: Date? {
        ReminderTaskDateCanonicalizer.unifiedDate(dueDate: dueDate, startDate: startDate)
    }

    func normalizedReminderDateStorage() -> TaskRecord {
        var copy = self
        let normalized = ReminderTaskDateCanonicalizer.normalizedStorage(
            dueDate: dueDate,
            startDate: startDate
        )
        copy.startDate = normalized.startDate
        copy.dueDate = normalized.dueDate
        return copy
    }
}

struct AttachmentReferenceRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var ownerTypeRaw: String
    var ownerID: UUID
    var storageKind: AttachmentReferenceStorageKind
    var relativePath: String?
    var bookmarkData: Data?
    var originalFilename: String
    var mimeType: String
    var byteSize: Int64
    var sha256: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct CalendarEventMirrorRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var externalIdentifier: String
    var calendarIdentifier: String
    var title: String
    var notes: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var lastSeenAt: Date
}

struct NormalizedSourceDigest: Codable, Hashable {
    var projectCount: Int
    var taskCount: Int
    var taskClonePlacementCount: Int
    var attachmentCount: Int
    var latestProjectUpdatedAt: Date?
    var latestTaskUpdatedAt: Date?
    var latestTaskClonePlacementUpdatedAt: Date?
    var latestAttachmentUpdatedAt: Date?
}

struct NormalizedSourceSnapshot: Codable, Hashable {
    static let rootNodeID: UUID = {
        guard let id = UUID(uuidString: "36B2B17B-5E7D-4697-9A0D-4D39E03B2D89") else {
            preconditionFailure("Normalized workspace root node UUID must be valid")
        }
        return id
    }()

    var digest: NormalizedSourceDigest
    var workspaceNodes: [WorkspaceNodeRecord]
    var tasks: [TaskRecord]
    var taskClonePlacements: [TaskProjectClonePlacementRecord]
    var attachments: [AttachmentReferenceRecord]
    var calendarEventMirrors: [CalendarEventMirrorRecord]
}

struct NormalizedMigrationReport: Equatable {
    var didMigrate: Bool
    var workspaceNodeCount: Int
    var taskCount: Int
    var taskClonePlacementCount: Int
    var attachmentCount: Int
}

struct NormalizedProjectRefreshState: Sendable, Equatable {
    var projectIDs: Set<UUID>
    var workspaceNodeIDs: Set<UUID>
    var projectNodeIDs: Set<UUID>
    var taskIDs: Set<UUID>
    var reminderListIdentifiers: Set<String>

    init(
        projectIDs: Set<UUID>,
        workspaceNodeIDs: Set<UUID> = [],
        projectNodeIDs: Set<UUID> = [],
        taskIDs: Set<UUID> = [],
        reminderListIdentifiers: Set<String> = []
    ) {
        self.projectIDs = projectIDs
        self.workspaceNodeIDs = workspaceNodeIDs
        self.projectNodeIDs = projectNodeIDs
        self.taskIDs = taskIDs
        self.reminderListIdentifiers = reminderListIdentifiers
    }
}

private struct NormalizedProjectSlice {
    var workspaceNodes: [WorkspaceNodeRecord]
    var tasks: [TaskRecord]
    var taskClonePlacements: [TaskProjectClonePlacementRecord]
    var attachments: [AttachmentReferenceRecord]
}

extension NormalizedSourceSnapshot {
    fileprivate func projectSlice(for projectIDs: Set<UUID>) -> NormalizedProjectSlice {
        guard !projectIDs.isEmpty else {
            return NormalizedProjectSlice(
                workspaceNodes: [],
                tasks: [],
                taskClonePlacements: [],
                attachments: []
            )
        }

        var childrenByParentID: [UUID: [WorkspaceNodeRecord]] = [:]
        for node in workspaceNodes {
            guard let parentID = node.parentID else { continue }
            childrenByParentID[parentID, default: []].append(node)
        }

        var affectedNodeIDs: Set<UUID> = []
        var pendingNodeIDs = Array(projectIDs)
        while let nextNodeID = pendingNodeIDs.popLast() {
            guard affectedNodeIDs.insert(nextNodeID).inserted else { continue }
            for child in childrenByParentID[nextNodeID] ?? [] {
                pendingNodeIDs.append(child.id)
            }
        }

        let slicedWorkspaceNodes = workspaceNodes.filter { affectedNodeIDs.contains($0.id) }
        let projectNodeIDs = Set(slicedWorkspaceNodes.filter { $0.kind == .project }.map(\.id))
        let slicedTasks = tasks.filter { task in
            affectedNodeIDs.contains(task.workspaceNodeID)
                || task.projectID.map(projectIDs.contains) == true
        }
        let taskIDs = Set(slicedTasks.map(\.id))
        let slicedTaskClonePlacements = taskClonePlacements.filter { projectIDs.contains($0.projectID) }
        let slicedAttachments = attachments.filter { attachment in
            switch attachment.ownerTypeRaw {
            case AttachmentOwnerType.project.rawValue:
                return projectNodeIDs.contains(attachment.ownerID)
            case AttachmentOwnerType.task.rawValue:
                return taskIDs.contains(attachment.ownerID)
            default:
                return false
            }
        }
        return NormalizedProjectSlice(
            workspaceNodes: slicedWorkspaceNodes,
            tasks: slicedTasks,
            taskClonePlacements: slicedTaskClonePlacements,
            attachments: slicedAttachments
        )
    }
}

enum NormalizedPersistenceError: LocalizedError {
    case sqliteOpenFailed(String)
    case sqlitePrepareFailed(String)
    case sqliteStepFailed(String)
    case sqliteExecFailed(String)
    case metadataDecodeFailed

    var errorDescription: String? {
        switch self {
        case .sqliteOpenFailed(let message):
            return "정규 SQLite DB 열기 실패: \(message)"
        case .sqlitePrepareFailed(let message):
            return "정규 SQLite statement 준비 실패: \(message)"
        case .sqliteStepFailed(let message):
            return "정규 SQLite 쓰기 실패: \(message)"
        case .sqliteExecFailed(let message):
            return "정규 SQLite schema 적용 실패: \(message)"
        case .metadataDecodeFailed:
            return "정규 SQLite metadata 해석 실패"
        }
    }
}

private let normalizedSQLiteBusyTimeoutMilliseconds: Int32 = 5_000
private let normalizedSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private let normalizedRuntimeWorkspaceNodesCreateViewSQL = """
CREATE VIEW workspace_nodes_runtime AS
SELECT
    id,
    parent_id,
    kind,
    title,
    note_markdown,
    color_hex,
    icon_name,
    sort_key,
    is_archived,
    created_at,
    updated_at,
    canonical_project_id,
    reminder_list_identifier,
    reminder_list_external_identifier
FROM workspace_nodes;
"""

private let normalizedRuntimeTasksCreateViewSQL = """
CREATE VIEW tasks_runtime AS
SELECT
    t.id,
    t.workspace_node_id,
    COALESCE(
        t.canonical_project_id,
        (
            SELECT wn.canonical_project_id
            FROM workspace_nodes_runtime wn
            WHERE wn.id = t.workspace_node_id
        ),
        t.workspace_node_id
    ) AS canonical_project_id,
    t.reminder_identifier,
    t.reminder_external_identifier,
    t.parent_task_id,
    t.parent_task_remote_external_identifier,
    t.title,
    t.is_completed,
    t.completion_date,
    t.start_date,
    t.due_date,
    t.schedule_has_explicit_time,
    t.scheduled_duration_minutes,
    t.priority,
    t.recurrence_rule_raw,
    t.is_flagged,
    t.reminder_note_text,
    t.app_note_markdown,
    t.attachment_count,
    t.board_stage_raw,
    t.importance_raw,
    t.row_order,
    t.block_reason,
    t.required_work_days,
    t.completed_work_units,
    t.completed_work_unit_dates_raw,
    t.preparation_schedule_overrides_raw,
    t.is_archived,
    t.archived_at,
    t.is_dirty,
    t.remote_last_modified_at,
    t.local_updated_at,
    t.created_at,
    t.last_synced_reminder_title,
    t.last_synced_reminder_note_body,
    t.last_synced_reminder_modified_at,
    t.reminder_note_conflict_excerpt
FROM tasks t;
"""

func openNormalizedSQLiteConnection(
    at databaseURL: URL,
    fileManager: FileManager = .default,
    additionalPragmas: [String] = []
) throws -> OpaquePointer? {
    let parentDirectory = databaseURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

    var db: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
        let message = db.flatMap(normalizedSQLiteMessage) ?? "unknown"
        sqlite3_close(db)
        throw NormalizedPersistenceError.sqliteOpenFailed(message)
    }

    guard sqlite3_busy_timeout(db, normalizedSQLiteBusyTimeoutMilliseconds) == SQLITE_OK else {
        let message = normalizedSQLiteMessage(db)
        sqlite3_close(db)
        throw NormalizedPersistenceError.sqliteExecFailed(message)
    }

    do {
        try executeNormalizedSQLite("PRAGMA journal_mode=WAL;", in: db)
        try executeNormalizedSQLite("PRAGMA synchronous=NORMAL;", in: db)
        for pragma in additionalPragmas {
            try executeNormalizedSQLite(pragma, in: db)
        }
        try NormalizedRetainedRuntimeSQLiteSchema.ensureCompatibilityColumnsIfNeeded(in: db)
        try ensureNormalizedRuntimeReadViewsIfPossible(in: db)
        return db
    } catch {
        sqlite3_close(db)
        throw error
    }
}

private func ensureNormalizedRuntimeReadViewsIfPossible(in db: OpaquePointer?) throws {
    guard try normalizedSQLiteObjectExists(named: "workspace_nodes", type: "table", in: db),
      try normalizedSQLiteObjectExists(named: "tasks", type: "table", in: db)
    else {
      return
    }

    if try !normalizedSQLiteObjectExists(named: "workspace_nodes_runtime", type: "view", in: db) {
      try executeNormalizedSQLite(normalizedRuntimeWorkspaceNodesCreateViewSQL, in: db)
    }
    if try !normalizedSQLiteObjectExists(named: "tasks_runtime", type: "view", in: db) {
      try executeNormalizedSQLite(normalizedRuntimeTasksCreateViewSQL, in: db)
    }
}

private func normalizedSQLiteObjectExists(
    named name: String,
    type: String,
    in db: OpaquePointer?
) throws -> Bool {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    guard sqlite3_prepare_v2(
      db,
      "SELECT 1 FROM sqlite_master WHERE type = ?1 AND name = ?2 LIMIT 1;",
      -1,
      &statement,
      nil
    ) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqlitePrepareFailed(normalizedSQLiteMessage(db))
    }

    guard sqlite3_bind_text(statement, 1, type, -1, normalizedSQLiteTransient) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed("bind sqlite object type failed")
    }
    guard sqlite3_bind_text(statement, 2, name, -1, normalizedSQLiteTransient) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed("bind sqlite object name failed")
    }

    return sqlite3_step(statement) == SQLITE_ROW
}

private func executeNormalizedSQLite(_ sql: String, in db: OpaquePointer?) throws {
    var errorPointer: UnsafeMutablePointer<Int8>?
    guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
        let message = errorPointer.map { String(cString: $0) } ?? normalizedSQLiteMessage(db)
        sqlite3_free(errorPointer)
        throw NormalizedPersistenceError.sqliteExecFailed(message)
    }
}

private func normalizedSQLiteMessage(_ db: OpaquePointer?) -> String {
    guard let db, let message = sqlite3_errmsg(db) else { return "unknown" }
    return String(cString: message)
}

/// Retained runtime sqlite read layer used by workspace/tree/document sidecar consumers.
enum NormalizedRuntimeReadSchema {
    static func ensureInstalled(
        at databaseURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try RuntimeSidecarSQLiteBootstrap.ensureInstalled(
            databaseURL: databaseURL,
            fileManager: fileManager
        )
    }
}

/// Runtime tables and views that stay alive after old-model cutover.
enum NormalizedRetainedRuntimeSQLiteSchema {
    static func install(in db: OpaquePointer?) throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS workspace_nodes (
                id TEXT PRIMARY KEY,
                parent_id TEXT,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                note_markdown TEXT NOT NULL,
                color_hex TEXT,
                icon_name TEXT,
                sort_key INTEGER NOT NULL,
                is_archived INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                canonical_project_id TEXT,
                reminder_list_identifier TEXT,
                reminder_list_external_identifier TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_workspace_nodes_parent_sort ON workspace_nodes(parent_id, sort_key);",
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                workspace_node_id TEXT NOT NULL,
                canonical_project_id TEXT,
                reminder_identifier TEXT,
                reminder_external_identifier TEXT,
                parent_task_id TEXT,
                parent_task_remote_external_identifier TEXT,
                title TEXT NOT NULL,
                is_completed INTEGER NOT NULL,
                completion_date REAL,
                start_date REAL,
                due_date REAL,
                schedule_has_explicit_time INTEGER NOT NULL,
                scheduled_duration_minutes INTEGER,
                priority INTEGER NOT NULL,
                recurrence_rule_raw TEXT,
                is_flagged INTEGER NOT NULL,
                reminder_note_text TEXT NOT NULL,
                app_note_markdown TEXT NOT NULL,
                attachment_count INTEGER NOT NULL,
                board_stage_raw TEXT NOT NULL,
                importance_raw TEXT NOT NULL,
                row_order INTEGER NOT NULL,
                block_reason TEXT NOT NULL,
                required_work_days INTEGER NOT NULL,
                completed_work_units INTEGER NOT NULL,
                completed_work_unit_dates_raw TEXT NOT NULL,
                preparation_schedule_overrides_raw TEXT NOT NULL,
                is_archived INTEGER NOT NULL,
                archived_at REAL,
                is_dirty INTEGER NOT NULL,
                remote_last_modified_at REAL,
                local_updated_at REAL NOT NULL,
                created_at REAL NOT NULL,
                last_synced_reminder_title TEXT NOT NULL DEFAULT '',
                last_synced_reminder_note_body TEXT NOT NULL DEFAULT '',
                last_synced_reminder_modified_at REAL,
                reminder_note_conflict_excerpt TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_tasks_workspace_row_order ON tasks(workspace_node_id, row_order, created_at);",
            """
            CREATE TABLE IF NOT EXISTS task_project_clone_placements (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                parent_task_id TEXT,
                reminder_external_identifier TEXT,
                target_reminder_list_external_identifier TEXT,
                normalized_parent_reminder_external_identifier TEXT,
                row_order INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_task_clone_placements_project_parent_row_order ON task_project_clone_placements(project_id, parent_task_id, row_order, created_at);",
            "CREATE INDEX IF NOT EXISTS idx_task_clone_placements_task ON task_project_clone_placements(task_id);",
            "CREATE INDEX IF NOT EXISTS idx_task_clone_placements_target_parent_row_order ON task_project_clone_placements(target_reminder_list_external_identifier, normalized_parent_reminder_external_identifier, row_order, created_at);",
            "CREATE INDEX IF NOT EXISTS idx_task_clone_placements_reminder_external_identifier ON task_project_clone_placements(reminder_external_identifier);",
            """
            CREATE TABLE IF NOT EXISTS attachment_references (
                id TEXT PRIMARY KEY,
                owner_type_raw TEXT NOT NULL,
                owner_id TEXT NOT NULL,
                storage_kind TEXT NOT NULL,
                relative_path TEXT,
                bookmark_data BLOB,
                original_filename TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                byte_size INTEGER NOT NULL,
                sha256 TEXT NOT NULL,
                is_archived INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_attachment_refs_owner ON attachment_references(owner_type_raw, owner_id);",
        ]

        for statement in statements {
            try executeNormalizedSQLite(statement, in: db)
        }
        try ensureCompatibilityColumnsIfNeeded(in: db)
        try executeNormalizedSQLite(
            "CREATE INDEX IF NOT EXISTS idx_tasks_workspace_parent_row_order ON tasks(workspace_node_id, parent_task_id, row_order, created_at);",
            in: db
        )
        try ensureNormalizedRuntimeReadViewsIfPossible(in: db)
    }

    static func ensureWorkspaceRootExists(in db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(
            db,
            "SELECT COUNT(*) FROM workspace_nodes WHERE id = ?1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw NormalizedPersistenceError.sqlitePrepareFailed(normalizedSQLiteMessage(db))
        }

        guard sqlite3_bind_text(
            statement,
            1,
            NormalizedSourceSnapshot.rootNodeID.uuidString,
            -1,
            normalizedSQLiteTransient
        ) == SQLITE_OK else {
            throw NormalizedPersistenceError.sqliteStepFailed("bind workspace root id failed")
        }

        let hasRoot = sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) > 0
        guard !hasRoot else { return }

        sqlite3_finalize(statement)
        statement = nil

        let now = Date().timeIntervalSince1970
        guard sqlite3_prepare_v2(
            db,
            """
            INSERT INTO workspace_nodes(
                id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key,
                is_archived, created_at, updated_at, canonical_project_id, reminder_list_identifier,
                reminder_list_external_identifier
            ) VALUES (?1, NULL, ?2, ?3, ?4, NULL, ?5, 0, 0, ?6, ?7, NULL, NULL, NULL);
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw NormalizedPersistenceError.sqlitePrepareFailed(normalizedSQLiteMessage(db))
        }

        guard sqlite3_bind_text(
            statement,
            1,
            NormalizedSourceSnapshot.rootNodeID.uuidString,
            -1,
            normalizedSQLiteTransient
        ) == SQLITE_OK,
            sqlite3_bind_text(statement, 2, WorkspaceNodeKind.rootSpace.rawValue, -1, normalizedSQLiteTransient) == SQLITE_OK,
            sqlite3_bind_text(statement, 3, "Workspace", -1, normalizedSQLiteTransient) == SQLITE_OK,
            sqlite3_bind_text(statement, 4, "", -1, normalizedSQLiteTransient) == SQLITE_OK,
            sqlite3_bind_text(statement, 5, "tray.full", -1, normalizedSQLiteTransient) == SQLITE_OK
        else {
            throw NormalizedPersistenceError.sqliteStepFailed("bind workspace root seed failed")
        }
        sqlite3_bind_double(statement, 6, now)
        sqlite3_bind_double(statement, 7, now)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NormalizedPersistenceError.sqliteStepFailed(normalizedSQLiteMessage(db))
        }
    }

    static func ensureCompatibilityColumnsIfNeeded(in db: OpaquePointer?) throws {
        if try normalizedSQLiteObjectExists(named: "workspace_nodes", type: "table", in: db) {
            try ensureColumn(
                named: "canonical_project_id",
                definition: "TEXT",
                inTable: "workspace_nodes",
                in: db
            )
            try migrateLegacyProjectColumnIfNeeded(
                inTable: "workspace_nodes",
                legacyColumnName: "legacy_project_id",
                canonicalColumnName: "canonical_project_id",
                in: db
            )
            try ensureColumn(
                named: "reminder_list_identifier",
                definition: "TEXT",
                inTable: "workspace_nodes",
                in: db
            )
            try ensureColumn(
                named: "reminder_list_external_identifier",
                definition: "TEXT",
                inTable: "workspace_nodes",
                in: db
            )
        }

        if try normalizedSQLiteObjectExists(named: "tasks", type: "table", in: db) {
            try ensureColumn(
                named: "canonical_project_id",
                definition: "TEXT",
                inTable: "tasks",
                in: db
            )
            try migrateLegacyProjectColumnIfNeeded(
                inTable: "tasks",
                legacyColumnName: "legacy_project_id",
                canonicalColumnName: "canonical_project_id",
                in: db
            )
            try ensureColumn(
                named: "parent_task_id",
                definition: "TEXT",
                inTable: "tasks",
                in: db
            )
            try ensureColumn(
                named: "parent_task_remote_external_identifier",
                definition: "TEXT",
                inTable: "tasks",
                in: db
            )
            try ensureColumn(
                named: "last_synced_reminder_title",
                definition: "TEXT NOT NULL DEFAULT ''",
                inTable: "tasks",
                in: db
            )
            try ensureColumn(
                named: "last_synced_reminder_note_body",
                definition: "TEXT NOT NULL DEFAULT ''",
                inTable: "tasks",
                in: db
            )
            try ensureColumn(
                named: "last_synced_reminder_modified_at",
                definition: "REAL",
                inTable: "tasks",
                in: db
            )
            try ensureColumn(
                named: "reminder_note_conflict_excerpt",
                definition: "TEXT",
                inTable: "tasks",
                in: db
            )
        }

        if try normalizedSQLiteObjectExists(named: "task_project_clone_placements", type: "table", in: db) {
            try ensureColumn(
                named: "reminder_external_identifier",
                definition: "TEXT",
                inTable: "task_project_clone_placements",
                in: db
            )
            try ensureColumn(
                named: "target_reminder_list_external_identifier",
                definition: "TEXT",
                inTable: "task_project_clone_placements",
                in: db
            )
            try ensureColumn(
                named: "normalized_parent_reminder_external_identifier",
                definition: "TEXT",
                inTable: "task_project_clone_placements",
                in: db
            )
        }
    }

    private static func ensureColumn(
        named columnName: String,
        definition: String,
        inTable tableName: String,
        in db: OpaquePointer?
    ) throws {
        guard try !table(named: tableName, hasColumn: columnName, in: db) else { return }
        try executeNormalizedSQLite(
            "ALTER TABLE \(tableName) ADD COLUMN \(columnName) \(definition);",
            in: db
        )
    }

    private static func migrateLegacyProjectColumnIfNeeded(
        inTable tableName: String,
        legacyColumnName: String,
        canonicalColumnName: String,
        in db: OpaquePointer?
    ) throws {
        guard try table(named: tableName, hasColumn: legacyColumnName, in: db),
            try table(named: tableName, hasColumn: canonicalColumnName, in: db)
        else {
            return
        }

        try executeNormalizedSQLite(
            """
            UPDATE \(tableName)
            SET \(canonicalColumnName) = \(legacyColumnName)
            WHERE \(canonicalColumnName) IS NULL
              AND \(legacyColumnName) IS NOT NULL;
            """,
            in: db
        )
    }

    private static func table(named tableName: String, hasColumn columnName: String, in db: OpaquePointer?) throws -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(tableName));", -1, &statement, nil) == SQLITE_OK else {
            throw NormalizedPersistenceError.sqlitePrepareFailed(normalizedSQLiteMessage(db))
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, index: 1) == columnName {
                return true
            }
        }
        return false
    }

    private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }
}

/// Legacy snapshot import tables kept only for migration and maintenance paths.
private enum NormalizedLegacyMigrationSQLiteSchema {
    static let schemaVersion: Int32 = 4

    static func install(in db: OpaquePointer?) throws {
        try executeNormalizedSQLite(
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
            in: db
        )
        try executeNormalizedSQLite(
            """
            CREATE TABLE IF NOT EXISTS calendar_event_mirrors (
                id TEXT PRIMARY KEY,
                external_identifier TEXT NOT NULL,
                calendar_identifier TEXT NOT NULL,
                title TEXT NOT NULL,
                notes TEXT NOT NULL,
                start_date REAL NOT NULL,
                end_date REAL NOT NULL,
                is_all_day INTEGER NOT NULL,
                last_seen_at REAL NOT NULL
            );
            """,
            in: db
        )
        try executeNormalizedSQLite(
            "CREATE INDEX IF NOT EXISTS idx_calendar_event_mirrors_external ON calendar_event_mirrors(external_identifier);",
            in: db
        )
        try executeNormalizedSQLite("PRAGMA user_version = \(schemaVersion);", in: db)
    }
}

/// Legacy normalized snapshot import/write coordinator.
///
/// Product runtime bootstrap must go through `RuntimeSidecarSQLiteBootstrap` so legacy
/// migration tables never become the active runtime entrypoint again.
final class NormalizedPersistenceCoordinator {
    private enum MetadataKey {
        static let sourceDigest = "sourceDigest"
        static let migratedAt = "migratedAt"
    }

    private static let schemaVersion: Int32 = 4
    private let databaseURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(databaseURL: URL, fileManager: FileManager = .default) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    func shouldRefresh(sourceSQLiteURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return true }
        let sourceDate = Self.latestRevisionDate(forSQLiteAt: sourceSQLiteURL, fileManager: fileManager)
        let normalizedDate = Self.latestRevisionDate(forSQLiteAt: databaseURL, fileManager: fileManager)
        return sourceDate > normalizedDate
    }

    func prepareSchema() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try installSchema(in: db)
    }

    func migrateIfNeeded(from snapshot: NormalizedSourceSnapshot) throws -> NormalizedMigrationReport {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        try installSchema(in: db)

        let encodedDigest = try encoder.encode(snapshot.digest)
        let digestString = String(decoding: encodedDigest, as: UTF8.self)
        if try currentMetadataValue(for: MetadataKey.sourceDigest, in: db) == digestString {
            return NormalizedMigrationReport(
                didMigrate: false,
                workspaceNodeCount: snapshot.workspaceNodes.count,
                taskCount: snapshot.tasks.count,
                taskClonePlacementCount: snapshot.taskClonePlacements.count,
                attachmentCount: snapshot.attachments.count
            )
        }

        try execute("BEGIN IMMEDIATE TRANSACTION;", in: db)
        do {
            try execute("DELETE FROM workspace_nodes;", in: db)
            try execute("DELETE FROM tasks;", in: db)
            try execute("DELETE FROM task_project_clone_placements;", in: db)
            try execute("DELETE FROM attachment_references;", in: db)
            try execute("DELETE FROM calendar_event_mirrors;", in: db)

            try insertWorkspaceNodes(snapshot.workspaceNodes, into: db)
            try insertTasks(snapshot.tasks, into: db)
            try insertTaskClonePlacements(snapshot.taskClonePlacements, into: db)
            try insertAttachments(snapshot.attachments, into: db)
            try insertCalendarEventMirrors(snapshot.calendarEventMirrors, into: db)

            try setMetadataValue(digestString, for: MetadataKey.sourceDigest, in: db)
            try setMetadataValue(String(Date().timeIntervalSince1970), for: MetadataKey.migratedAt, in: db)
            try execute("COMMIT;", in: db)
        } catch {
            try? execute("ROLLBACK;", in: db)
            throw error
        }

        return NormalizedMigrationReport(
            didMigrate: true,
            workspaceNodeCount: snapshot.workspaceNodes.count,
            taskCount: snapshot.tasks.count,
            taskClonePlacementCount: snapshot.taskClonePlacements.count,
            attachmentCount: snapshot.attachments.count
        )
    }

    func refreshProjects(
        from snapshot: NormalizedSourceSnapshot,
        for projectIDs: Set<UUID>,
        existingState: NormalizedProjectRefreshState
    ) throws -> NormalizedMigrationReport {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        try installSchema(in: db)

        let encodedDigest = try encoder.encode(snapshot.digest)
        let digestString = String(decoding: encodedDigest, as: UTF8.self)
        if try currentMetadataValue(for: MetadataKey.sourceDigest, in: db) == digestString {
            return NormalizedMigrationReport(
                didMigrate: false,
                workspaceNodeCount: snapshot.workspaceNodes.count,
                taskCount: snapshot.tasks.count,
                taskClonePlacementCount: snapshot.taskClonePlacements.count,
                attachmentCount: snapshot.attachments.count
            )
        }

        let slice = snapshot.projectSlice(for: projectIDs)
        let rootNode = snapshot.workspaceNodes.first(where: { $0.id == NormalizedSourceSnapshot.rootNodeID })
            ?? WorkspaceNodeRecord(
                id: NormalizedSourceSnapshot.rootNodeID,
                parentID: nil,
                kind: .rootSpace,
                title: "Workspace",
                noteMarkdown: "",
                colorHex: nil,
                iconName: "tray.full",
                sortKey: 0,
                isArchived: false,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                canonicalProjectID: nil,
                reminderListIdentifier: nil,
                reminderListExternalIdentifier: nil
            )

        try execute("BEGIN IMMEDIATE TRANSACTION;", in: db)
        do {
            try upsertWorkspaceRoot(rootNode, into: db)
            try deleteAttachments(
                projectNodeIDs: existingState.projectNodeIDs,
                taskIDs: existingState.taskIDs,
                in: db
            )
            try deleteTaskClonePlacements(projectIDs: existingState.projectIDs, in: db)
            try deleteTasks(
                taskIDs: existingState.taskIDs,
                projectIDs: existingState.projectIDs,
                in: db
            )
            try deleteWorkspaceNodes(nodeIDs: existingState.workspaceNodeIDs, in: db)

            try insertWorkspaceNodes(slice.workspaceNodes, into: db)
            try insertTasks(slice.tasks, into: db)
            try insertTaskClonePlacements(slice.taskClonePlacements, into: db)
            try insertAttachments(slice.attachments, into: db)

            try setMetadataValue(digestString, for: MetadataKey.sourceDigest, in: db)
            try setMetadataValue(String(Date().timeIntervalSince1970), for: MetadataKey.migratedAt, in: db)
            try execute("COMMIT;", in: db)
        } catch {
            try? execute("ROLLBACK;", in: db)
            throw error
        }

        return NormalizedMigrationReport(
            didMigrate: true,
            workspaceNodeCount: snapshot.workspaceNodes.count,
            taskCount: snapshot.tasks.count,
            taskClonePlacementCount: snapshot.taskClonePlacements.count,
            attachmentCount: snapshot.attachments.count
        )
    }

    func debugTableCounts() throws -> [String: Int] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try installSchema(in: db)

        return [
            "workspace_nodes": try countRows(in: "workspace_nodes", db: db),
            "tasks": try countRows(in: "tasks", db: db),
            "task_project_clone_placements": try countRows(in: "task_project_clone_placements", db: db),
            "attachment_references": try countRows(in: "attachment_references", db: db),
            "calendar_event_mirrors": try countRows(in: "calendar_event_mirrors", db: db),
        ]
    }

    static func latestRevisionDate(forSQLiteAt url: URL, fileManager: FileManager = .default) -> Date {
        let candidates = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ]
        return candidates.reduce(.distantPast) { current, candidate in
            guard
                let values = try? candidate.resourceValues(forKeys: [.contentModificationDateKey]),
                let date = values.contentModificationDate
            else {
                return current
            }
            return max(current, date)
        }
    }

    private func openDatabase() throws -> OpaquePointer? {
        try openNormalizedSQLiteConnection(
            at: databaseURL,
            fileManager: fileManager,
            additionalPragmas: ["PRAGMA foreign_keys=OFF;"]
        )
    }

    private func installSchema(in db: OpaquePointer?) throws {
        try NormalizedRetainedRuntimeSQLiteSchema.install(in: db)
        try NormalizedLegacyMigrationSQLiteSchema.install(in: db)
    }

    private static func ensureRuntimeReadViews(in db: OpaquePointer?) throws {
        try ensureNormalizedRuntimeReadViewsIfPossible(in: db)
    }

    private func ensureTaskColumn(
        named columnName: String,
        definition: String,
        in db: OpaquePointer?
    ) throws {
        guard try !taskTableHasColumn(named: columnName, in: db) else { return }
        try execute(
            "ALTER TABLE tasks ADD COLUMN \(columnName) \(definition);",
            in: db
        )
    }

    private func taskTableHasColumn(named columnName: String, in db: OpaquePointer?) throws -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare("PRAGMA table_info(tasks);", in: db, statement: &statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            if Self.columnText(statement, index: 1) == columnName {
                return true
            }
        }
        return false
    }

    private func currentMetadataValue(for key: String, in db: OpaquePointer?) throws -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare("SELECT value FROM metadata WHERE key = ?1;", in: db, statement: &statement)
        try bind(key, at: 1, to: statement)

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            return Self.columnText(statement, index: 0)
        }
        if stepResult == SQLITE_DONE {
            return nil
        }
        throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }

    private func setMetadataValue(_ value: String, for key: String, in db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(
            "INSERT INTO metadata(key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
            in: db,
            statement: &statement
        )
        try bind(key, at: 1, to: statement)
        try bind(value, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
        }
    }

    private func insertWorkspaceNodes(_ records: [WorkspaceNodeRecord], into db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(
            """
            INSERT INTO workspace_nodes(
                id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key, is_archived,
                created_at, updated_at, canonical_project_id, reminder_list_identifier, reminder_list_external_identifier
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14);
            """,
            in: db,
            statement: &statement
        )

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(record.id.uuidString, at: 1, to: statement)
            try bind(record.parentID?.uuidString, at: 2, to: statement)
            try bind(record.kind.rawValue, at: 3, to: statement)
            try bind(record.title, at: 4, to: statement)
            try bind(record.noteMarkdown, at: 5, to: statement)
            try bind(record.colorHex, at: 6, to: statement)
            try bind(record.iconName, at: 7, to: statement)
            try bind(record.sortKey, at: 8, to: statement)
            try bind(record.isArchived, at: 9, to: statement)
            try bind(record.createdAt, at: 10, to: statement)
            try bind(record.updatedAt, at: 11, to: statement)
            try bind(record.canonicalProjectID?.uuidString, at: 12, to: statement)
            try bind(record.reminderListIdentifier, at: 13, to: statement)
            try bind(record.reminderListExternalIdentifier, at: 14, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
            }
        }
    }

    private func upsertWorkspaceRoot(_ root: WorkspaceNodeRecord, into db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(
            """
            INSERT INTO workspace_nodes(
                id, parent_id, kind, title, note_markdown, color_hex, icon_name, sort_key, is_archived,
                created_at, updated_at, canonical_project_id, reminder_list_identifier, reminder_list_external_identifier
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
            ON CONFLICT(id) DO UPDATE SET
                parent_id = excluded.parent_id,
                kind = excluded.kind,
                title = excluded.title,
                note_markdown = excluded.note_markdown,
                color_hex = excluded.color_hex,
                icon_name = excluded.icon_name,
                sort_key = excluded.sort_key,
                is_archived = excluded.is_archived,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                canonical_project_id = excluded.canonical_project_id,
                reminder_list_identifier = excluded.reminder_list_identifier,
                reminder_list_external_identifier = excluded.reminder_list_external_identifier;
            """,
            in: db,
            statement: &statement
        )

        try bind(root.id.uuidString, at: 1, to: statement)
        try bind(root.parentID?.uuidString, at: 2, to: statement)
        try bind(root.kind.rawValue, at: 3, to: statement)
        try bind(root.title, at: 4, to: statement)
        try bind(root.noteMarkdown, at: 5, to: statement)
        try bind(root.colorHex, at: 6, to: statement)
        try bind(root.iconName, at: 7, to: statement)
        try bind(root.sortKey, at: 8, to: statement)
        try bind(root.isArchived, at: 9, to: statement)
        try bind(root.createdAt, at: 10, to: statement)
        try bind(root.updatedAt, at: 11, to: statement)
        try bind(root.canonicalProjectID?.uuidString, at: 12, to: statement)
        try bind(root.reminderListIdentifier, at: 13, to: statement)
        try bind(root.reminderListExternalIdentifier, at: 14, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
        }
    }

    private func insertTasks(_ records: [TaskRecord], into db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
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

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(record.id.uuidString, at: 1, to: statement)
            try bind(record.workspaceNodeID.uuidString, at: 2, to: statement)
            try bind(record.canonicalProjectID?.uuidString, at: 3, to: statement)
            try bind(record.reminderIdentifier, at: 4, to: statement)
            try bind(record.reminderExternalIdentifier, at: 5, to: statement)
            try bind(record.parentTaskID?.uuidString, at: 6, to: statement)
            try bind(record.parentTaskRemoteExternalIdentifier, at: 7, to: statement)
            try bind(record.title, at: 8, to: statement)
            try bind(record.isCompleted, at: 9, to: statement)
            try bind(record.completionDate, at: 10, to: statement)
            try bind(record.startDate, at: 11, to: statement)
            try bind(record.dueDate, at: 12, to: statement)
            try bind(record.scheduleHasExplicitTime, at: 13, to: statement)
            try bind(record.scheduledDurationMinutes.map(Int64.init), at: 14, to: statement)
            try bind(Int64(record.priority), at: 15, to: statement)
            try bind(record.recurrenceRuleRaw, at: 16, to: statement)
            try bind(record.isFlagged, at: 17, to: statement)
            try bind(record.reminderNoteText, at: 18, to: statement)
            try bind("", at: 19, to: statement)
            try bind(Int64(record.attachmentCount), at: 20, to: statement)
            try bind(record.boardStageRaw, at: 21, to: statement)
            try bind(record.importanceRaw, at: 22, to: statement)
            try bind(Int64(record.rowOrder), at: 23, to: statement)
            try bind("", at: 24, to: statement)
            try bind(Int64(record.requiredWorkDays), at: 25, to: statement)
            try bind(Int64(record.completedWorkUnits), at: 26, to: statement)
            try bind(record.completedWorkUnitDatesRaw, at: 27, to: statement)
            try bind(record.preparationScheduleOverridesRaw, at: 28, to: statement)
            try bind(record.isArchived, at: 29, to: statement)
            try bind(record.archivedAt, at: 30, to: statement)
            try bind(record.isDirty, at: 31, to: statement)
            try bind(record.remoteLastModifiedAt, at: 32, to: statement)
            try bind(record.localUpdatedAt, at: 33, to: statement)
            try bind(record.createdAt, at: 34, to: statement)
            try bind(record.lastSyncedReminderTitle, at: 35, to: statement)
            try bind(record.lastSyncedReminderNoteBody, at: 36, to: statement)
            try bind(record.lastSyncedReminderModifiedAt, at: 37, to: statement)
            try bind(record.reminderNoteConflictExcerpt, at: 38, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
            }
        }
    }

    private func insertTaskClonePlacements(
        _ records: [TaskProjectClonePlacementRecord],
        into db: OpaquePointer?
    ) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(
            """
            INSERT INTO task_project_clone_placements(
                id, task_id, project_id, parent_task_id, row_order, created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7);
            """,
            in: db,
            statement: &statement
        )

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(record.id.uuidString, at: 1, to: statement)
            try bind(record.taskID.uuidString, at: 2, to: statement)
            try bind(record.projectID.uuidString, at: 3, to: statement)
            try bind(record.parentTaskID?.uuidString, at: 4, to: statement)
            try bind(Int64(record.rowOrder), at: 5, to: statement)
            try bind(record.createdAt, at: 6, to: statement)
            try bind(record.updatedAt, at: 7, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
            }
        }
    }

    private func insertAttachments(_ records: [AttachmentReferenceRecord], into db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(
            """
            INSERT INTO attachment_references(
                id, owner_type_raw, owner_id, storage_kind, relative_path, bookmark_data, original_filename,
                mime_type, byte_size, sha256, is_archived, created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13);
            """,
            in: db,
            statement: &statement
        )

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(record.id.uuidString, at: 1, to: statement)
            try bind(record.ownerTypeRaw, at: 2, to: statement)
            try bind(record.ownerID.uuidString, at: 3, to: statement)
            try bind(record.storageKind.rawValue, at: 4, to: statement)
            try bind(record.relativePath, at: 5, to: statement)
            try bind(record.bookmarkData, at: 6, to: statement)
            try bind(record.originalFilename, at: 7, to: statement)
            try bind(record.mimeType, at: 8, to: statement)
            try bind(record.byteSize, at: 9, to: statement)
            try bind(record.sha256, at: 10, to: statement)
            try bind(record.isArchived, at: 11, to: statement)
            try bind(record.createdAt, at: 12, to: statement)
            try bind(record.updatedAt, at: 13, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
            }
        }
    }

    private func insertCalendarEventMirrors(_ records: [CalendarEventMirrorRecord], into db: OpaquePointer?) throws {
        guard !records.isEmpty else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(
            """
            INSERT INTO calendar_event_mirrors(
                id, external_identifier, calendar_identifier, title, notes, start_date, end_date,
                is_all_day, last_seen_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9);
            """,
            in: db,
            statement: &statement
        )

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(record.id.uuidString, at: 1, to: statement)
            try bind(record.externalIdentifier, at: 2, to: statement)
            try bind(record.calendarIdentifier, at: 3, to: statement)
            try bind(record.title, at: 4, to: statement)
            try bind(record.notes, at: 5, to: statement)
            try bind(record.startDate, at: 6, to: statement)
            try bind(record.endDate, at: 7, to: statement)
            try bind(record.isAllDay, at: 8, to: statement)
            try bind(record.lastSeenAt, at: 9, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
            }
        }
    }

    private func deleteAttachments(
        projectNodeIDs: Set<UUID>,
        taskIDs: Set<UUID>,
        in db: OpaquePointer?
    ) throws {
        var predicates: [String] = []
        if !projectNodeIDs.isEmpty {
            predicates.append(
                """
                (owner_type_raw = '\(AttachmentOwnerType.project.rawValue)'
                 AND owner_id IN (\(quotedTextList(projectNodeIDs.map(\.uuidString)))))
                """
            )
        }
        if !taskIDs.isEmpty {
            predicates.append(
                """
                (owner_type_raw = '\(AttachmentOwnerType.task.rawValue)'
                 AND owner_id IN (\(quotedTextList(taskIDs.map(\.uuidString)))))
                """
            )
        }

        guard !predicates.isEmpty else { return }
        try execute(
            """
            DELETE FROM attachment_references
            WHERE \(predicates.joined(separator: " OR "));
            """,
            in: db
        )
    }

    private func deleteTaskClonePlacements(projectIDs: Set<UUID>, in db: OpaquePointer?) throws {
        guard !projectIDs.isEmpty else { return }
        try execute(
            """
            DELETE FROM task_project_clone_placements
            WHERE project_id IN (\(quotedTextList(projectIDs.map(\.uuidString))));
            """,
            in: db
        )
    }

    private func deleteTasks(
        taskIDs: Set<UUID>,
        projectIDs: Set<UUID>,
        in db: OpaquePointer?
    ) throws {
        var predicates: [String] = []
        if !taskIDs.isEmpty {
            predicates.append("id IN (\(quotedTextList(taskIDs.map(\.uuidString))))")
        }
        if !projectIDs.isEmpty {
            predicates.append("canonical_project_id IN (\(quotedTextList(projectIDs.map(\.uuidString))))")
        }

        guard !predicates.isEmpty else { return }
        try execute(
            """
            DELETE FROM tasks
            WHERE \(predicates.joined(separator: " OR "));
            """,
            in: db
        )
    }

    private func deleteWorkspaceNodes(nodeIDs: Set<UUID>, in db: OpaquePointer?) throws {
        guard !nodeIDs.isEmpty else { return }
        try execute(
            """
            DELETE FROM workspace_nodes
            WHERE id IN (\(quotedTextList(nodeIDs.map(\.uuidString))))
              AND id != '\(NormalizedSourceSnapshot.rootNodeID.uuidString)';
            """,
            in: db
        )
    }

    private func countRows(in tableName: String, db: OpaquePointer?) throws -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare("SELECT COUNT(*) FROM \(tableName);", in: db, statement: &statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
        }
        return Int(sqlite3_column_int64(statement, 0))
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
            let result = sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransientDestructor)
            guard result == SQLITE_OK else {
                throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
            }
        } else {
            let result = sqlite3_bind_null(statement, index)
            guard result == SQLITE_OK else {
                throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
            }
        }
    }

    private func bind(_ value: Int64?, at index: Int32, to statement: OpaquePointer?) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_int64(statement, index, value)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
        }
    }

    private func bind(_ value: Bool, at index: Int32, to statement: OpaquePointer?) throws {
        let result = sqlite3_bind_int(statement, index, value ? 1 : 0)
        guard result == SQLITE_OK else {
            throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
        }
    }

    private func bind(_ value: Date?, at index: Int32, to statement: OpaquePointer?) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
        }
    }

    private func bind(_ value: Data?, at index: Int32, to statement: OpaquePointer?) throws {
        let result: Int32
        if let value {
            result = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), Self.sqliteTransientDestructor)
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
        }
    }

    private static func sqliteMessage(_ db: OpaquePointer?) -> String {
        guard let db, let message = sqlite3_errmsg(db) else {
            return "unknown"
        }
        return String(cString: message)
    }

    private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func quotedTextList(_ values: [String]) -> String {
        values
            .sorted()
            .map(Self.quotedSQLiteText)
            .joined(separator: ", ")
    }

    private static func quotedSQLiteText(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
