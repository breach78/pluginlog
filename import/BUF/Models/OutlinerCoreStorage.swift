import Foundation
import SwiftData

enum OutlinerCoreStorageRole: String, Codable, CaseIterable {
  case projectCanonical
  case taskCanonical
  case taskPlacement
  case workspaceNodeReadBridge
  case derivedTaskReadCache
  case cloneReadBridge
}

enum TaskPlacementSourceKind: String, Codable, CaseIterable {
  case primary
  case clone
}

struct TaskMirrorMigrationQuarantineRecord: Codable, Hashable, Sendable {
  var projectID: UUID
  var reason: String
}

struct ProjectRecordCanonicalSnapshot: Equatable, Sendable {
  var id: UUID
  var title: String
  var colorHex: String?
  var reminderListIdentifier: String
  var reminderListExternalIdentifier: String
  var noteMarkdown: String
  var progressStageRaw: String
  var isArchived: Bool
  var archivedAt: Date?
  var startDate: Date?
  var deadline: Date?
  var workspaceParentID: UUID?
  var workspaceSortKey: Int64?
  var workspaceKindRaw: String?
  var createdAt: Date
  var updatedAt: Date
}

struct ProjectSummaryRecord: Codable, Equatable, Sendable {
  var openRootTaskCount: Int
  var completedRootTaskCount: Int
  var undatedOpenRootTaskCount: Int
  var overdueOpenRootTaskCount: Int
  var todayTaskCount: Int
  var nextUpcomingDate: Date?
  var deadline: Date?
  var stageRaw: String
  var progress: Double
  var latestTaskUpdatedAt: Date?
  var title: String? = nil
  var colorHex: String? = nil
  var isArchived: Bool? = nil
}

struct ScheduleSliceEntry: Codable, Equatable, Hashable, Sendable {
  var taskID: UUID
  var parentTaskID: UUID?
  var title: String
  var displayedDate: Date?
  var startDate: Date?
  var dueDate: Date?
  var scheduleHasExplicitTime: Bool
  var scheduledDurationMinutes: Int?
  var isCompleted: Bool
  var completionDate: Date?
  var recurrenceRuleRaw: String?
  var attachmentCount: Int
  var reminderNoteText: String
  var requiredWorkDays: Int
  var completedWorkUnits: Int
  var completedWorkUnitDates: [Date]
  var preparationScheduleOverridesRaw: String
  var rowOrder: Int
  var priority: Int
  var isFlagged: Bool
  var isArchived: Bool
  var localUpdatedAt: Date
  var createdAt: Date

  var renderFingerprint: Int {
    var hasher = Hasher()
    hasher.combine(taskID)
    hasher.combine(parentTaskID)
    hasher.combine(title)
    hasher.combine(displayedDate?.timeIntervalSinceReferenceDate)
    hasher.combine(startDate?.timeIntervalSinceReferenceDate)
    hasher.combine(dueDate?.timeIntervalSinceReferenceDate)
    hasher.combine(scheduleHasExplicitTime)
    hasher.combine(scheduledDurationMinutes)
    hasher.combine(isCompleted)
    hasher.combine(completionDate?.timeIntervalSinceReferenceDate)
    hasher.combine(recurrenceRuleRaw)
    hasher.combine(attachmentCount)
    hasher.combine(reminderNoteText)
    hasher.combine(requiredWorkDays)
    hasher.combine(completedWorkUnits)
    hasher.combine(completedWorkUnitDates)
    hasher.combine(preparationScheduleOverridesRaw)
    hasher.combine(rowOrder)
    hasher.combine(priority)
    hasher.combine(isFlagged)
    hasher.combine(isArchived)
    hasher.combine(localUpdatedAt.timeIntervalSinceReferenceDate)
    hasher.combine(createdAt.timeIntervalSinceReferenceDate)
    return hasher.finalize()
  }

  func taskRowSnapshot(projectID: UUID) -> TaskRowSnapshot {
    TaskRowSnapshot(
      id: taskID,
      workspaceNodeID: projectID,
      parentTaskID: parentTaskID,
      title: title,
      isCompleted: isCompleted,
      completionDate: completionDate,
      displayedDate: displayedDate,
      startDate: startDate,
      dueDate: dueDate,
      scheduleHasExplicitTime: scheduleHasExplicitTime,
      scheduledDurationMinutes: scheduledDurationMinutes,
      recurrenceRuleRaw: recurrenceRuleRaw,
      attachmentCount: attachmentCount,
      reminderNoteText: reminderNoteText,
      hasReminderNote: !reminderNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      requiredWorkDays: requiredWorkDays,
      completedWorkUnits: completedWorkUnits,
      completedWorkUnitDates: completedWorkUnitDates,
      preparationScheduleOverridesRaw: preparationScheduleOverridesRaw,
      rowOrder: rowOrder,
      priority: priority,
      isFlagged: isFlagged,
      isArchived: isArchived,
      localUpdatedAt: localUpdatedAt,
      createdAt: createdAt,
      renderFingerprint: renderFingerprint
    )
  }
}

struct SearchCorpusCandidateRecord: Codable, Equatable, Hashable, Sendable {
  var kindRaw: Int
  var fieldText: String
  var preview: String

  var kind: WorkspaceSearchMatchKind {
    WorkspaceSearchMatchKind(rawValue: kindRaw) ?? .taskAttachment
  }

  init(kind: WorkspaceSearchMatchKind, fieldText: String, preview: String) {
    self.kindRaw = kind.rawValue
    self.fieldText = fieldText
    self.preview = preview
  }
}

struct SearchCorpusEntry: Codable, Equatable, Hashable, Sendable {
  var id: String
  var entityKindRaw: Int
  var dispositionRaw: Int
  var projectID: UUID
  var taskID: UUID?
  var title: String
  var subtitlePrefix: String
  var candidates: [SearchCorpusCandidateRecord]
  var corpus: String
  var isExcludedFromSearch: Bool

  var entityKind: WorkspaceSearchEntityKind {
    WorkspaceSearchEntityKind(rawValue: entityKindRaw) ?? .task
  }

  var disposition: WorkspaceSearchResultDisposition {
    WorkspaceSearchResultDisposition(rawValue: dispositionRaw) ?? .regular
  }
}

struct TaskContentCanonicalSnapshot: Equatable, Sendable {
  var id: UUID
  var title: String
  var contentKindRaw: String
  var childContentIDs: [UUID]
  var reminderIdentifier: String?
  var reminderExternalIdentifier: String?
  var reminderOwnerProjectID: UUID?
  var reminderOwnerCalendarID: String?
  var parentTaskRemoteExternalIdentifier: String?
  var isCompleted: Bool
  var completionDate: Date?
  var startDate: Date?
  var dueDate: Date?
  var scheduleHasExplicitTime: Bool
  var scheduledDurationMinutes: Int?
  var priority: Int
  var recurrenceRuleRaw: String?
  var isFlagged: Bool
  var boardStageRaw: String?
  var importanceRaw: String?
  var reminderNoteText: String
  var reminderRawPayloadRaw: String?
  var attachmentCount: Int
  var requiredWorkDays: Int
  var completedWorkUnits: Int
  var completedWorkUnitDatesRaw: String
  var preparationScheduleOverridesRaw: String
  var remoteLastModifiedAt: Date?
  var localUpdatedAt: Date
  var createdAt: Date
}

struct TaskPlacementSnapshot: Equatable, Sendable {
  var id: UUID
  var stablePlacementKey: String
  var sourceKind: TaskPlacementSourceKind
  var contentID: UUID
  var projectID: UUID
  var parentPlacementID: UUID?
  var rowOrder: Int
  var isCollapsed: Bool
  var createdAt: Date
  var updatedAt: Date
}

@Model
final class ProjectRecord {
  @Attribute(.unique) var id: UUID
  var progressStageRaw: String
  @Attribute(originalName: "isDirty") var storedIsDirty: Bool?
  var isArchived: Bool
  var archivedAt: Date?
  var startDate: Date?
  var deadline: Date?
  var noteMarkdown: String
  var readModelMetadataRaw: String
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID,
    progressStageRaw: String = ProjectProgressStage.do.storageRawValue,
    isDirty: Bool = false,
    isArchived: Bool = false,
    archivedAt: Date? = nil,
    startDate: Date? = nil,
    deadline: Date? = nil,
    noteMarkdown: String = "",
    readModelMetadataRaw: String = "",
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.progressStageRaw = progressStageRaw
    self.storedIsDirty = isDirty
    self.isArchived = isArchived
    self.archivedAt = archivedAt
    self.startDate = startDate
    self.deadline = deadline
    self.noteMarkdown = noteMarkdown
    self.readModelMetadataRaw = readModelMetadataRaw
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  var isDirty: Bool {
    get { storedIsDirty ?? false }
    set { storedIsDirty = newValue }
  }
}

private struct ProjectRecordIdentityMetadata: Codable, Equatable {
  var title: String?
  var colorHex: String?
  var reminderListIdentifier: String?
  var reminderListExternalIdentifier: String?
  var workspaceParentID: UUID?
  var workspaceSortKey: Int64?
  var workspaceKindRaw: String?
  var summary: ProjectSummaryRecord?
}

extension ProjectRecord {
  static let storageRole: OutlinerCoreStorageRole = .projectCanonical

  private static let metadataEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let metadataDecoder = JSONDecoder()

  private var identityMetadata: ProjectRecordIdentityMetadata {
    get {
      guard let data = readModelMetadataRaw.data(using: .utf8) else {
        return ProjectRecordIdentityMetadata()
      }
      return
        (try? Self.metadataDecoder.decode(ProjectRecordIdentityMetadata.self, from: data))
        ?? ProjectRecordIdentityMetadata()
    }
    set {
      if let data = try? Self.metadataEncoder.encode(newValue),
        let rawValue = String(data: data, encoding: .utf8)
      {
        readModelMetadataRaw = rawValue
      } else {
        readModelMetadataRaw = ""
      }
    }
  }

  var projectTitle: String {
    get { identityMetadata.title ?? "" }
    set {
      var metadata = identityMetadata
      metadata.title = newValue
      identityMetadata = metadata
    }
  }

  var projectColorHex: String? {
    get { identityMetadata.colorHex }
    set {
      var metadata = identityMetadata
      metadata.colorHex = newValue
      identityMetadata = metadata
    }
  }

  var projectReminderListIdentifier: String {
    get { identityMetadata.reminderListIdentifier ?? "" }
    set {
      var metadata = identityMetadata
      metadata.reminderListIdentifier = newValue
      identityMetadata = metadata
    }
  }

  var projectReminderListExternalIdentifier: String {
    get { identityMetadata.reminderListExternalIdentifier ?? "" }
    set {
      var metadata = identityMetadata
      metadata.reminderListExternalIdentifier = newValue
      identityMetadata = metadata
    }
  }

  var projectWorkspaceParentID: UUID? {
    get { identityMetadata.workspaceParentID }
    set {
      var metadata = identityMetadata
      metadata.workspaceParentID = newValue
      identityMetadata = metadata
    }
  }

  var projectWorkspaceSortKey: Int64? {
    get { identityMetadata.workspaceSortKey }
    set {
      var metadata = identityMetadata
      metadata.workspaceSortKey = newValue
      identityMetadata = metadata
    }
  }

  var projectWorkspaceKindRaw: String? {
    get { identityMetadata.workspaceKindRaw }
    set {
      var metadata = identityMetadata
      metadata.workspaceKindRaw = newValue
      identityMetadata = metadata
    }
  }

  var projectWorkspaceKind: WorkspaceNodeKind? {
    get {
      guard let rawValue = projectWorkspaceKindRaw else { return nil }
      return WorkspaceNodeKind(rawValue: rawValue)
    }
    set {
      projectWorkspaceKindRaw = newValue?.rawValue
    }
  }

  var projectSummaryRecord: ProjectSummaryRecord? {
    get { identityMetadata.summary }
    set {
      var metadata = identityMetadata
      metadata.summary = newValue
      identityMetadata = metadata
    }
  }

  var resolvedTitle: String {
    let trimmed = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? OutlinerProject.defaultTitle : trimmed
  }

  var canonicalSnapshot: ProjectRecordCanonicalSnapshot {
    ProjectRecordCanonicalSnapshot(
      id: id,
      title: projectTitle,
      colorHex: projectColorHex,
      reminderListIdentifier: projectReminderListIdentifier,
      reminderListExternalIdentifier: projectReminderListExternalIdentifier,
      noteMarkdown: noteMarkdown,
      progressStageRaw: progressStageRaw,
      isArchived: isArchived,
      archivedAt: archivedAt,
      startDate: startDate,
      deadline: deadline,
      workspaceParentID: projectWorkspaceParentID,
      workspaceSortKey: projectWorkspaceSortKey,
      workspaceKindRaw: projectWorkspaceKindRaw,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  func applyCanonicalIdentity(
    title: String,
    colorHex: String?,
    reminderListIdentifier: String,
    reminderListExternalIdentifier: String
  ) {
    projectTitle = title
    projectColorHex = colorHex
    projectReminderListIdentifier = reminderListIdentifier
    projectReminderListExternalIdentifier = reminderListExternalIdentifier
  }

  func applyWorkspacePlacement(from node: WorkspaceNodeRecord?) {
    projectWorkspaceParentID = node?.parentID
    projectWorkspaceSortKey = node?.sortKey
    projectWorkspaceKind = node?.kind
  }
}

@Model
final class ProjectScheduleIndexRecord {
  @Attribute(.unique) var projectID: UUID
  var entriesRaw: String
  var updatedAt: Date

  init(
    projectID: UUID,
    entriesRaw: String = "[]",
    updatedAt: Date = .now
  ) {
    self.projectID = projectID
    self.entriesRaw = entriesRaw
    self.updatedAt = updatedAt
  }
}

extension ProjectScheduleIndexRecord {
  private static let entriesEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let entriesDecoder = JSONDecoder()

  var entries: [ScheduleSliceEntry] {
    get {
      guard let data = entriesRaw.data(using: .utf8) else { return [] }
      return (try? Self.entriesDecoder.decode([ScheduleSliceEntry].self, from: data)) ?? []
    }
    set {
      if let data = try? Self.entriesEncoder.encode(newValue),
        let rawValue = String(data: data, encoding: .utf8)
      {
        entriesRaw = rawValue
      } else {
        entriesRaw = "[]"
      }
    }
  }
}

@Model
final class ProjectSearchIndexRecord {
  @Attribute(.unique) var projectID: UUID
  var entriesRaw: String
  var updatedAt: Date

  init(
    projectID: UUID,
    entriesRaw: String = "[]",
    updatedAt: Date = .now
  ) {
    self.projectID = projectID
    self.entriesRaw = entriesRaw
    self.updatedAt = updatedAt
  }
}

extension ProjectSearchIndexRecord {
  private static let entriesEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let entriesDecoder = JSONDecoder()

  var entries: [SearchCorpusEntry] {
    get {
      guard let data = entriesRaw.data(using: .utf8) else { return [] }
      return (try? Self.entriesDecoder.decode([SearchCorpusEntry].self, from: data)) ?? []
    }
    set {
      if let data = try? Self.entriesEncoder.encode(newValue),
        let rawValue = String(data: data, encoding: .utf8)
      {
        entriesRaw = rawValue
      } else {
        entriesRaw = "[]"
      }
    }
  }
}

@Model
final class TaskContent {
  @Attribute(.unique) var id: UUID

  var title: String
  var contentKindRaw: String
  var childContentIDsRaw: String

  var reminderIdentifier: String?
  var reminderExternalIdentifier: String?
  var reminderOwnerProjectID: UUID?
  var reminderOwnerCalendarID: String?
  var parentTaskRemoteExternalIdentifier: String?

  var isCompleted: Bool
  var completionDate: Date?
  var startDate: Date?
  var dueDate: Date?
  var scheduleHasExplicitTime: Bool
  var scheduledDurationMinutes: Int?
  var priority: Int
  var recurrenceRuleRaw: String?
  var isFlagged: Bool
  var boardStageRaw: String?
  var importanceRaw: String?

  var reminderNoteText: String
  var reminderRawPayloadRaw: String?
  var attachmentCount: Int
  var lastSyncedReminderTitle: String = ""
  var lastSyncedReminderNoteBody: String = ""
  var lastSyncedReminderModifiedAt: Date? = nil
  var reminderNoteConflictExcerpt: String? = nil
  var requiredWorkDays: Int
  var completedWorkUnits: Int
  var completedWorkUnitDatesRaw: String
  var preparationScheduleOverridesRaw: String
  var mirrorQuarantineRecordsRaw: String?

  var isDirty: Bool
  var remoteLastModifiedAt: Date?
  var localUpdatedAt: Date
  var createdAt: Date

  init(
    id: UUID,
    title: String,
    contentKindRaw: String = "task",
    childContentIDsRaw: String = "[]",
    reminderIdentifier: String? = nil,
    reminderExternalIdentifier: String? = nil,
    reminderOwnerProjectID: UUID? = nil,
    reminderOwnerCalendarID: String? = nil,
    parentTaskRemoteExternalIdentifier: String? = nil,
    isCompleted: Bool = false,
    completionDate: Date? = nil,
    startDate: Date? = nil,
    dueDate: Date? = nil,
    scheduleHasExplicitTime: Bool = false,
    scheduledDurationMinutes: Int? = nil,
    priority: Int = 0,
    recurrenceRuleRaw: String? = nil,
    isFlagged: Bool = false,
    boardStageRaw: String? = nil,
    importanceRaw: String? = nil,
    reminderNoteText: String = "",
    reminderRawPayloadRaw: String? = nil,
    attachmentCount: Int = 0,
    lastSyncedReminderTitle: String = "",
    lastSyncedReminderNoteBody: String = "",
    lastSyncedReminderModifiedAt: Date? = nil,
    reminderNoteConflictExcerpt: String? = nil,
    requiredWorkDays: Int = 0,
    completedWorkUnits: Int = 0,
    completedWorkUnitDatesRaw: String = "",
    preparationScheduleOverridesRaw: String = "",
    mirrorQuarantineRecordsRaw: String? = nil,
    isDirty: Bool = false,
    remoteLastModifiedAt: Date? = nil,
    localUpdatedAt: Date = .now,
    createdAt: Date = .now
  ) {
    self.id = id
    self.title = title
    self.contentKindRaw = contentKindRaw
    self.childContentIDsRaw = childContentIDsRaw
    self.reminderIdentifier = reminderIdentifier
    self.reminderExternalIdentifier = reminderExternalIdentifier
    self.reminderOwnerProjectID = reminderOwnerProjectID
    self.reminderOwnerCalendarID = reminderOwnerCalendarID
    self.parentTaskRemoteExternalIdentifier = parentTaskRemoteExternalIdentifier
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.startDate = startDate
    self.dueDate = dueDate
    self.scheduleHasExplicitTime = scheduleHasExplicitTime
    self.scheduledDurationMinutes = scheduledDurationMinutes
    self.priority = priority
    self.recurrenceRuleRaw = recurrenceRuleRaw
    self.isFlagged = isFlagged
    self.boardStageRaw = boardStageRaw
    self.importanceRaw = importanceRaw
    self.reminderNoteText = reminderNoteText
    self.reminderRawPayloadRaw = reminderRawPayloadRaw
    self.attachmentCount = attachmentCount
    self.lastSyncedReminderTitle = lastSyncedReminderTitle
    self.lastSyncedReminderNoteBody = lastSyncedReminderNoteBody
    self.lastSyncedReminderModifiedAt = lastSyncedReminderModifiedAt
    self.reminderNoteConflictExcerpt = reminderNoteConflictExcerpt
    self.requiredWorkDays = requiredWorkDays
    self.completedWorkUnits = completedWorkUnits
    self.completedWorkUnitDatesRaw = completedWorkUnitDatesRaw
    self.preparationScheduleOverridesRaw = preparationScheduleOverridesRaw
    self.mirrorQuarantineRecordsRaw = mirrorQuarantineRecordsRaw
    self.isDirty = isDirty
    self.remoteLastModifiedAt = remoteLastModifiedAt
    self.localUpdatedAt = localUpdatedAt
    self.createdAt = createdAt
  }
}

extension TaskContent {
  static let storageRole: OutlinerCoreStorageRole = .taskCanonical

  private static let rawValueEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let rawValueDecoder = JSONDecoder()

  var childContentIDs: [UUID] {
    get {
      guard let data = childContentIDsRaw.data(using: .utf8) else { return [] }
      return (try? Self.rawValueDecoder.decode([UUID].self, from: data)) ?? []
    }
    set {
      if let data = try? Self.rawValueEncoder.encode(newValue),
        let rawValue = String(data: data, encoding: .utf8)
      {
        childContentIDsRaw = rawValue
      } else {
        childContentIDsRaw = "[]"
      }
    }
  }

  var mirrorQuarantineRecords: [TaskMirrorMigrationQuarantineRecord] {
    get {
      guard let rawValue = mirrorQuarantineRecordsRaw,
        let data = rawValue.data(using: .utf8)
      else { return [] }
      return
        (try? Self.rawValueDecoder.decode([TaskMirrorMigrationQuarantineRecord].self, from: data))
        ?? []
    }
    set {
      let normalizedRecords = newValue
        .sorted { lhs, rhs in
          if lhs.projectID == rhs.projectID {
            return lhs.reason < rhs.reason
          }
          return lhs.projectID.uuidString < rhs.projectID.uuidString
        }

      if let data = try? Self.rawValueEncoder.encode(normalizedRecords),
        let rawValue = String(data: data, encoding: .utf8)
      {
        mirrorQuarantineRecordsRaw = rawValue
      } else {
        mirrorQuarantineRecordsRaw = "[]"
      }
    }
  }

  var canonicalSnapshot: TaskContentCanonicalSnapshot {
    TaskContentCanonicalSnapshot(
      id: id,
      title: title,
      contentKindRaw: contentKindRaw,
      childContentIDs: childContentIDs,
      reminderIdentifier: reminderIdentifier,
      reminderExternalIdentifier: reminderExternalIdentifier,
      reminderOwnerProjectID: reminderOwnerProjectID,
      reminderOwnerCalendarID: reminderOwnerCalendarID,
      parentTaskRemoteExternalIdentifier: parentTaskRemoteExternalIdentifier,
      isCompleted: isCompleted,
      completionDate: completionDate,
      startDate: startDate,
      dueDate: dueDate,
      scheduleHasExplicitTime: scheduleHasExplicitTime,
      scheduledDurationMinutes: scheduledDurationMinutes,
      priority: priority,
      recurrenceRuleRaw: recurrenceRuleRaw,
      isFlagged: isFlagged,
      boardStageRaw: boardStageRaw,
      importanceRaw: importanceRaw,
      reminderNoteText: reminderNoteText,
      reminderRawPayloadRaw: reminderRawPayloadRaw,
      attachmentCount: attachmentCount,
      requiredWorkDays: requiredWorkDays,
      completedWorkUnits: completedWorkUnits,
      completedWorkUnitDatesRaw: completedWorkUnitDatesRaw,
      preparationScheduleOverridesRaw: preparationScheduleOverridesRaw,
      remoteLastModifiedAt: remoteLastModifiedAt,
      localUpdatedAt: localUpdatedAt,
      createdAt: createdAt
    )
  }

  var boardStage: BoardStage {
    get { BoardStage(rawValue: boardStageRaw ?? "") ?? .now }
    set { boardStageRaw = newValue.rawValue }
  }

  var importance: ImportanceLevel {
    get { ImportanceLevel(rawValue: importanceRaw ?? "") ?? .minor }
    set { importanceRaw = newValue.rawValue }
  }
}

extension TaskContentCanonicalSnapshot {
  var boardStage: BoardStage {
    BoardStage(rawValue: boardStageRaw ?? "") ?? .now
  }

  var importance: ImportanceLevel {
    ImportanceLevel(rawValue: importanceRaw ?? "") ?? .minor
  }
}

@Model
final class TaskPlacement {
  @Attribute(.unique) var id: UUID
  @Attribute(.unique, originalName: "legacyPlacementKey") var storedStablePlacementKey: String

  var sourceKindRaw: String
  var contentID: UUID
  var projectID: UUID
  var parentPlacementID: UUID?
  var rowOrder: Int
  var isCollapsed: Bool
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    stablePlacementKey: String,
    sourceKindRaw: String,
    contentID: UUID,
    projectID: UUID,
    parentPlacementID: UUID? = nil,
    rowOrder: Int = 0,
    isCollapsed: Bool = false,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.storedStablePlacementKey = stablePlacementKey
    self.sourceKindRaw = sourceKindRaw
    self.contentID = contentID
    self.projectID = projectID
    self.parentPlacementID = parentPlacementID
    self.rowOrder = rowOrder
    self.isCollapsed = isCollapsed
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

extension TaskPlacement {
  static let storageRole: OutlinerCoreStorageRole = .taskPlacement

  var sourceKind: TaskPlacementSourceKind {
    get { TaskPlacementSourceKind(rawValue: sourceKindRaw) ?? .primary }
    set { sourceKindRaw = newValue.rawValue }
  }

  var stablePlacementKey: String {
    get { storedStablePlacementKey }
    set { storedStablePlacementKey = newValue }
  }

  var placementSnapshot: TaskPlacementSnapshot {
    TaskPlacementSnapshot(
      id: id,
      stablePlacementKey: stablePlacementKey,
      sourceKind: sourceKind,
      contentID: contentID,
      projectID: projectID,
      parentPlacementID: parentPlacementID,
      rowOrder: rowOrder,
      isCollapsed: isCollapsed,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}

extension WorkspaceNodeRecord {
  static let storageRole: OutlinerCoreStorageRole = .workspaceNodeReadBridge
}

extension TaskRecord {
  static let storageRole: OutlinerCoreStorageRole = .derivedTaskReadCache
}

extension TaskProjectClonePlacement {
  static let storageRole: OutlinerCoreStorageRole = .cloneReadBridge
}

extension TaskProjectClonePlacementRecord {
  static let storageRole: OutlinerCoreStorageRole = .cloneReadBridge
}
