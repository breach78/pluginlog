import Foundation

struct TaskDeletionUndoState: Sendable {
  let id: UUID
  let reminderExternalIdentifier: String?
  let title: String
  let isCompleted: Bool
  let completionDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let scheduleHasExplicitTime: Bool
  let scheduledDurationMinutes: Int?
  let priority: Int
  let recurrenceRuleRaw: String?
  let isFlagged: Bool
  let reminderNoteText: String
  let attachmentCount: Int
  let boardStageRaw: String
  let importanceRaw: String
  let rowOrder: Int
  let requiredWorkDays: Int
  let completedWorkUnits: Int
  let completedWorkUnitDatesRaw: String
  let preparationScheduleOverridesRaw: String
  let createdAt: Date
}

enum TaskDeletionUndoPlacement: Sendable, Equatable {
  case taskParent(taskID: UUID, insertionSlot: Int)
  case projectRoot(rootBulletID: UUID?, insertionSlot: Int)
}

struct TaskDeletionUndoNodeSnapshot: Sendable {
  let task: TaskDeletionUndoState
  let insertionSlot: Int?
  let children: [TaskDeletionUndoNodeSnapshot]
  let attachmentSnapshots: [DeletedAttachmentSnapshot]
}

struct TaskDeletionUndoSnapshot: Sendable {
  let projectID: UUID
  let placement: TaskDeletionUndoPlacement
  let root: TaskDeletionUndoNodeSnapshot
  let sequenceAssignments: [UUID: String]

  var task: TaskDeletionUndoState { root.task }
}
