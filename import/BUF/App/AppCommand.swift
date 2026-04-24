import Foundation

enum AppOwnerStore: String, Sendable {
  case reminder
  case calendar
  case sidecar
}

enum AppOwnerField: String, Sendable {
  case reminderListBinding
  case projectMetadata
  case treeStructure
  case ordering
  case appSupplement
  case listMetadata
  case taskFields
  case eventFields
  case title
  case isCompleted
  case note
  case dueDate
  case recurrence
  case metadata
  case startDate
  case endDate
  case isAllDay
  case calendarId
}

extension AppOwnerField {
  static let reminderTaskExternalChangeFields: [AppOwnerField] = [
    .title,
    .isCompleted,
    .note,
    .dueDate,
    .recurrence,
    .metadata,
  ]

  static let calendarEventExternalChangeFields: [AppOwnerField] = [
    .title,
    .startDate,
    .endDate,
    .isAllDay,
    .recurrence,
    .calendarId,
  ]
}

struct ProjectReminderConnectionWrite: Sendable {
  let projectID: UUID
  let reminderListIdentifier: String?
  let reminderListExternalIdentifier: String
}

enum ProjectMetadataMutation: Sendable {
  case projectNote(String)
  case progressStage(ProjectProgressStage)
}

struct ProjectMetadataWrite: Sendable {
  let projectID: UUID
  let mutation: ProjectMetadataMutation
}

struct ProjectTreeStructureWrite: Sendable {
  let projectID: UUID
  let rootNodes: [ReminderProjectRootNodeRecord]
}

enum ProjectOrderingMutation: Sendable {
  case project(
    projectID: UUID,
    orderedTopLevelReminderExternalIdentifiers: [String]
  )
  case workspace(orderedProjectIDs: [UUID])
}

struct ProjectOrderingWrite: Sendable {
  let mutation: ProjectOrderingMutation
}

enum AppSupplementMutation: Sendable {
  case projectBoardOrder(projectID: UUID, boardOrder: Int?)
  case taskScheduledDuration(taskID: UUID, scheduledDurationMinutes: Int?)
  case taskPresentation(
    taskID: UUID,
    boardStage: BoardStage,
    importance: ImportanceLevel,
    isFlagged: Bool
  )
  case taskPlannedWorkProgress(
    taskID: UUID,
    completedWorkUnits: Int,
    completedWorkUnitDatesRaw: String
  )
  case removeDeletedTaskSidecars(
    projectID: UUID,
    reminderExternalIdentifiers: [String]
  )
  case removeProjectSidecars(
    projectID: UUID,
    reminderListExternalIdentifier: String,
    reminderExternalIdentifiers: [String]
  )
  case restoreArchivedProjectSidecars(
    projectID: UUID,
    reminderListExternalIdentifier: String,
    archiveBundle: ArchivedProjectBundle,
    restoredTaskIdentities: [RestoredArchivedTaskIdentity]
  )
}

struct AppSupplementWrite: Sendable {
  let mutation: AppSupplementMutation
}

enum ReminderListMetadataMutation: Sendable {
  case title(String)
  case colorHex(String?)
}

struct ReminderListMetadataWrite: Sendable {
  let projectID: UUID
  let reminderListIdentifier: String
  let reminderListExternalIdentifier: String?
  let mutation: ReminderListMetadataMutation
}

enum ReminderTaskFieldsMutation: Sendable {
  case title(String)
  case note(String)
  case schedule(dueDate: Date?, hasExplicitTime: Bool)
  case completion(isCompleted: Bool, completionDate: Date?)
  case recurrence(String?)
  case presentationPriority(Int)
}

struct ReminderTaskFieldsWrite: Sendable {
  let projectID: UUID
  let taskID: UUID
  let reminderIdentifier: String?
  let reminderExternalIdentifier: String?
  let mutation: ReminderTaskFieldsMutation
}

struct TaskScheduleSplitWrite: Sendable {
  let projectID: UUID
  let taskID: UUID
  let day: Date?
  let timeMinutes: Int?
  let durationMinutes: Int?
}

struct TaskPresentationSplitWrite: Sendable {
  let projectID: UUID
  let taskID: UUID
  let boardStage: BoardStage
  let importance: ImportanceLevel
  let priority: Int
  let isFlagged: Bool
}

enum CalendarEventFieldsMutation: Sendable {
  case timing(
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  )
}

struct CalendarEventFieldsWrite: Sendable {
  let event: ScheduleCalendarEvent
  let mutation: CalendarEventFieldsMutation
}

enum AppOwnerFieldWrite: Sendable {
  case reminderListBinding(ProjectReminderConnectionWrite)
  case removeReminderListBinding(projectID: UUID)
  case projectMetadata(ProjectMetadataWrite)
  case treeStructure(ProjectTreeStructureWrite)
  case ordering(ProjectOrderingWrite)
  case appSupplement(AppSupplementWrite)
  case listMetadata(ReminderListMetadataWrite)
  case taskFields(ReminderTaskFieldsWrite)
  case eventFields(CalendarEventFieldsWrite)
}

enum AppCommand: Sendable {
  case taskScheduleSplit(TaskScheduleSplitWrite)
  case taskPresentationSplit(TaskPresentationSplitWrite)
  case writeOwnerField(ownerStore: AppOwnerStore, write: AppOwnerFieldWrite)
  case externalOwnerChange(
    ownerStore: AppOwnerStore,
    ownerIDs: [String],
    changedFields: [AppOwnerField]
  )
}
