import Foundation

struct TimelineProjectListWindowSnapshot: Equatable {
  struct Task: Identifiable, Equatable {
    struct MetadataIndicators: Equatable {
      let hasNote: Bool
      let attachmentCount: Int
      let isRecurring: Bool

      static let empty = MetadataIndicators(
        hasNote: false,
        attachmentCount: 0,
        isRecurring: false
      )

      var isEmpty: Bool {
        !hasNote && attachmentCount <= 0 && !isRecurring
      }
    }

    let id: UUID
    let title: String
    let dateText: String?
    let notePreviewText: String?
    let metadataIndicators: MetadataIndicators
    let isCompleted: Bool
    let isOverdue: Bool

    init(
      id: UUID,
      title: String,
      dateText: String?,
      notePreviewText: String?,
      metadataIndicators: MetadataIndicators = .empty,
      isCompleted: Bool,
      isOverdue: Bool
    ) {
      self.id = id
      self.title = title
      self.dateText = dateText
      self.notePreviewText = notePreviewText
      self.metadataIndicators = metadataIndicators
      self.isCompleted = isCompleted
      self.isOverdue = isOverdue
    }
  }

  let projectID: UUID
  let title: String
  let colorHex: String?
  let projectNoteText: String
  let tasks: [Task]

  init(
    projectID: UUID,
    title: String,
    colorHex: String?,
    projectNoteText: String = "",
    tasks: [Task]
  ) {
    self.projectID = projectID
    self.title = title
    self.colorHex = colorHex
    self.projectNoteText = projectNoteText
    self.tasks = tasks
  }
}

struct TimelineProjectListTaskRow: Identifiable {
  let id: UUID
  let task: TimelineProjectListWindowSnapshot.Task
}

enum TimelineProjectListScrollTarget {
  static func task(_ taskID: UUID) -> String {
    "task:\(taskID.uuidString)"
  }

  static func draft(_ anchor: TimelineProjectListDraftAnchor) -> String {
    switch anchor {
    case .beginning:
      return "draft:beginning"
    case .after(let taskID):
      return "draft:after:\(taskID.uuidString)"
    }
  }
}

struct TimelineProjectMoveOption: Identifiable, Equatable {
  let id: UUID
  let title: String
}

enum TimelineProjectListPresentation {
  case window
  case embedded
}

struct TimelineProjectListActions {
  let onToggleTaskCompletion: (UUID, Bool) async -> Bool
  let onEditTask: (UUID) -> Void
  let onReorderTasks: (UUID, [UUID], Bool) -> Void
  let onCreateTask: (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?
  let onRenameTask: (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?
  let onDeleteTask: (UUID, UUID) async -> Bool
  let onRenameProject: (UUID, String) -> Void
  let onSaveProjectNote: (UUID, String) async -> String?
  let moveOptions: () -> [TimelineProjectMoveOption]
  let onMoveTask: (UUID, UUID, UUID) async -> Bool

  init(
    onToggleTaskCompletion: @escaping (UUID, Bool) async -> Bool,
    onEditTask: @escaping (UUID) -> Void,
    onReorderTasks: @escaping (UUID, [UUID], Bool) -> Void,
    onCreateTask: @escaping (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onRenameTask: @escaping (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onDeleteTask: @escaping (UUID, UUID) async -> Bool,
    onRenameProject: @escaping (UUID, String) -> Void,
    onSaveProjectNote: @escaping (UUID, String) async -> String? = { _, _ in nil },
    moveOptions: @escaping () -> [TimelineProjectMoveOption] = { [] },
    onMoveTask: @escaping (UUID, UUID, UUID) async -> Bool = { _, _, _ in false }
  ) {
    self.onToggleTaskCompletion = onToggleTaskCompletion
    self.onEditTask = onEditTask
    self.onReorderTasks = onReorderTasks
    self.onCreateTask = onCreateTask
    self.onRenameTask = onRenameTask
    self.onDeleteTask = onDeleteTask
    self.onRenameProject = onRenameProject
    self.onSaveProjectNote = onSaveProjectNote
    self.moveOptions = moveOptions
    self.onMoveTask = onMoveTask
  }
}

struct TimelineProjectListInlineEditorConfiguration {
  let initialExpandedTaskID: UUID?
  let initialFocus: TimelineTaskEditInitialFocus
  let workspaceTreeRevision: Int
  let vaultRootURL: URL?
  let initialFields: (TimelineProjectListWindowSnapshot.Task) -> RetainedTaskEditFields
  let loadFields: (UUID, RetainedTaskEditFields) async -> RetainedTaskEditFields
  let saveFields: (UUID, RetainedTaskEditFields) async throws -> Void
  let onSyncEditingChanged: (UUID, Bool) -> Void
  let onSyncEditingActivity: () -> Void
}

enum TimelineProjectListTaskOrderPolicy {
  static func reorderedTasks(
    _ orderedTaskIDs: [UUID],
    tasksByID: [UUID: TimelineProjectListWindowSnapshot.Task]
  ) -> [TimelineProjectListWindowSnapshot.Task] {
    orderedTaskIDs.compactMap { tasksByID[$0] }
  }

  static func openTaskIDs(
    from tasks: [TimelineProjectListWindowSnapshot.Task]
  ) -> [UUID] {
    tasks.filter { !$0.isCompleted }.map(\.id)
  }
}
