import Foundation

enum ProjectDetailTaskDateSortMode: String, Codable, Hashable, Sendable, CaseIterable {
  case none
  case recent
  case oldest
}

struct TaskRowSnapshot: Identifiable, Hashable, Sendable {
  let id: UUID
  let workspaceNodeID: UUID
  let parentTaskID: UUID?
  let reminderExternalIdentifier: String?
  let title: String
  let isCompleted: Bool
  let completionDate: Date?
  let displayedDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let scheduleHasExplicitTime: Bool
  let scheduledDurationMinutes: Int?
  let recurrenceRuleRaw: String?
  let attachmentCount: Int
  let reminderNoteText: String
  let hasReminderNote: Bool
  let requiredWorkDays: Int
  let completedWorkUnits: Int
  let completedWorkUnitDates: [Date]
  let preparationScheduleOverridesRaw: String
  let rowOrder: Int
  let priority: Int
  let isFlagged: Bool
  let isArchived: Bool
  let localUpdatedAt: Date
  let createdAt: Date
  let renderFingerprint: Int

  init(
    id: UUID,
    workspaceNodeID: UUID,
    parentTaskID: UUID?,
    reminderExternalIdentifier: String? = nil,
    title: String,
    isCompleted: Bool,
    completionDate: Date?,
    displayedDate: Date?,
    startDate: Date?,
    dueDate: Date?,
    scheduleHasExplicitTime: Bool,
    scheduledDurationMinutes: Int?,
    recurrenceRuleRaw: String?,
    attachmentCount: Int,
    reminderNoteText: String,
    hasReminderNote: Bool,
    requiredWorkDays: Int,
    completedWorkUnits: Int,
    completedWorkUnitDates: [Date],
    preparationScheduleOverridesRaw: String,
    rowOrder: Int,
    priority: Int,
    isFlagged: Bool,
    isArchived: Bool,
    localUpdatedAt: Date,
    createdAt: Date,
    renderFingerprint: Int
  ) {
    self.id = id
    self.workspaceNodeID = workspaceNodeID
    self.parentTaskID = parentTaskID
    self.reminderExternalIdentifier = reminderExternalIdentifier
    self.title = title
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.displayedDate = displayedDate
    self.startDate = startDate
    self.dueDate = dueDate
    self.scheduleHasExplicitTime = scheduleHasExplicitTime
    self.scheduledDurationMinutes = scheduledDurationMinutes
    self.recurrenceRuleRaw = recurrenceRuleRaw
    self.attachmentCount = attachmentCount
    self.reminderNoteText = reminderNoteText
    self.hasReminderNote = hasReminderNote
    self.requiredWorkDays = requiredWorkDays
    self.completedWorkUnits = completedWorkUnits
    self.completedWorkUnitDates = completedWorkUnitDates
    self.preparationScheduleOverridesRaw = preparationScheduleOverridesRaw
    self.rowOrder = rowOrder
    self.priority = priority
    self.isFlagged = isFlagged
    self.isArchived = isArchived
    self.localUpdatedAt = localUpdatedAt
    self.createdAt = createdAt
    self.renderFingerprint = renderFingerprint
  }
}

extension TaskRowSnapshot {
  var reminderDate: Date? {
    ReminderTaskDateCanonicalizer.unifiedDate(
      dueDate: dueDate,
      startDate: startDate,
      displayedDate: displayedDate
    )
  }
}

struct AttachmentReferencePreviewSnapshot: Identifiable, Hashable, Sendable {
  let id: UUID
  let ownerID: UUID
  let originalFilename: String
  let mimeType: String
  let byteSize: Int64
  let updatedAt: Date
}

struct AttachmentSummarySnapshot: Hashable, Sendable {
  let ownerType: AttachmentOwnerType
  let ownerID: UUID
  let totalCount: Int
  let latestUpdatedAt: Date?
  let previews: [AttachmentReferencePreviewSnapshot]
  let summaryFingerprint: Int
}

struct SubtreeAggregateSnapshot: Hashable, Sendable {
  let nodeID: UUID
  let descendantProjectCount: Int
  let descendantFolderCount: Int
  let descendantImportedGroupCount: Int
  let directTaskCount: Int
  let subtreeTaskCount: Int
  let openTaskCount: Int
  let completedTaskCount: Int
  let archivedTaskCount: Int
  let attachmentCount: Int
  let latestTaskUpdatedAt: Date?
}

enum ProjectDetailRootStructureNodeKind: String, Codable, Hashable, Sendable {
  case task
  case bullet
  case mirror
}

struct ProjectDetailRootStructureNodeSnapshot: Identifiable, Hashable, Sendable {
  let id: UUID
  let parentNodeID: UUID?
  let kind: ProjectDetailRootStructureNodeKind
  let title: String
  let taskID: UUID?
  let children: [ProjectDetailRootStructureNodeSnapshot]

  init(
    id: UUID,
    parentNodeID: UUID?,
    kind: ProjectDetailRootStructureNodeKind,
    title: String,
    taskID: UUID? = nil,
    children: [ProjectDetailRootStructureNodeSnapshot] = []
  ) {
    self.id = id
    self.parentNodeID = parentNodeID
    self.kind = kind
    self.title = title
    self.taskID = taskID
    self.children = children
  }
}

struct ProjectDetailSnapshot: Hashable, Sendable {
  let node: WorkspaceNodeRecord
  let projectStartDate: Date?
  let projectDeadline: Date?
  let breadcrumb: [WorkspaceNodeRecord]
  let childNodes: [WorkspaceNodeRecord]
  let taskRows: [TaskRowSnapshot]
  let rootStructureNodes: [ProjectDetailRootStructureNodeSnapshot]
  let projectAttachmentSummary: AttachmentSummarySnapshot
  let taskAttachmentSummaries: [AttachmentSummarySnapshot]
  let aggregate: SubtreeAggregateSnapshot
  let includeArchived: Bool
  let includeCompleted: Bool
  let taskSortMode: ProjectDetailTaskDateSortMode
  let computedAt: Date

  init(
    node: WorkspaceNodeRecord,
    projectStartDate: Date?,
    projectDeadline: Date?,
    breadcrumb: [WorkspaceNodeRecord],
    childNodes: [WorkspaceNodeRecord],
    taskRows: [TaskRowSnapshot],
    rootStructureNodes: [ProjectDetailRootStructureNodeSnapshot] = [],
    projectAttachmentSummary: AttachmentSummarySnapshot,
    taskAttachmentSummaries: [AttachmentSummarySnapshot],
    aggregate: SubtreeAggregateSnapshot,
    includeArchived: Bool,
    includeCompleted: Bool,
    taskSortMode: ProjectDetailTaskDateSortMode,
    computedAt: Date
  ) {
    self.node = node
    self.projectStartDate = projectStartDate
    self.projectDeadline = projectDeadline
    self.breadcrumb = breadcrumb
    self.childNodes = childNodes
    self.taskRows = taskRows
    self.rootStructureNodes = rootStructureNodes
    self.projectAttachmentSummary = projectAttachmentSummary
    self.taskAttachmentSummaries = taskAttachmentSummaries
    self.aggregate = aggregate
    self.includeArchived = includeArchived
    self.includeCompleted = includeCompleted
    self.taskSortMode = taskSortMode
    self.computedAt = computedAt
  }

  var taskAttachmentSummariesByOwnerID: [UUID: AttachmentSummarySnapshot] {
    Dictionary(uniqueKeysWithValues: taskAttachmentSummaries.map { ($0.ownerID, $0) })
  }
}
