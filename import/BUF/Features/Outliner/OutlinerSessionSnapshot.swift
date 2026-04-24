import CryptoKit
import Foundation

struct OutlinerTaskSidecarMetadata: Codable, Equatable {
  var requiredWorkDays: Int
  var scheduledDurationMinutes: Int?
  var attachmentPreviews: [OutlinerAttachmentPreview]

  init(
    requiredWorkDays: Int = 0,
    scheduledDurationMinutes: Int? = nil,
    attachmentPreviews: [OutlinerAttachmentPreview] = []
  ) {
    self.requiredWorkDays = requiredWorkDays
    self.scheduledDurationMinutes = scheduledDurationMinutes
    self.attachmentPreviews = attachmentPreviews
  }

  private enum CodingKeys: String, CodingKey {
    case requiredWorkDays
    case scheduledDurationMinutes
    case attachmentPreviews
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    requiredWorkDays = try container.decodeIfPresent(Int.self, forKey: .requiredWorkDays) ?? 0
    scheduledDurationMinutes = try container.decodeIfPresent(
      Int.self,
      forKey: .scheduledDurationMinutes
    )
    attachmentPreviews = try container.decodeIfPresent(
      [OutlinerAttachmentPreview].self,
      forKey: .attachmentPreviews
    ) ?? []
  }
}

struct ReminderMetadataSnapshot: Codable, Equatable {
  var dueDate: Date?
  var completionDate: Date?
  var hasExplicitTime: Bool
  var recurrence: OutlinerRecurrenceSample?
  var priority: Int

  init(
    dueDate: Date? = nil,
    completionDate: Date? = nil,
    hasExplicitTime: Bool = false,
    recurrence: OutlinerRecurrenceSample? = nil,
    priority: Int = 0
  ) {
    self.dueDate = dueDate
    self.completionDate = completionDate
    self.hasExplicitTime = hasExplicitTime
    self.recurrence = recurrence
    self.priority = priority
  }

  private enum CodingKeys: String, CodingKey {
    case dueDate
    case completionDate
    case hasExplicitTime
    case recurrence
    case priority
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
    completionDate = try container.decodeIfPresent(Date.self, forKey: .completionDate)
    hasExplicitTime = try container.decodeIfPresent(Bool.self, forKey: .hasExplicitTime) ?? false
    recurrence = try container.decodeIfPresent(OutlinerRecurrenceSample.self, forKey: .recurrence)
    priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
  }
}

struct ReminderWorkspaceStructureRecord: Codable, Equatable {
  var orderedReminderListExternalIdentifiersRaw: String
  var createdAt: Date
  var updatedAt: Date
}

struct ReminderProjectTaskOrderRecord: Codable, Equatable {
  var reminderListExternalIdentifier: String
  var orderedTopLevelReminderExternalIdentifiersRaw: String
  var createdAt: Date
  var updatedAt: Date
}

struct ReminderTaskFeatureSidecarRecord: Codable, Equatable {
  var reminderExternalIdentifier: String
  var attachmentManifestRaw: String
  var scheduledDurationMinutes: Int?
  var ownedCalendarEventExternalIdentifier: String?
  var boardStageRaw: String?
  var importanceRaw: String?
  var isFlagged: Bool
  var requiredWorkDays: Int
  var completedWorkUnits: Int
  var completedWorkUnitDatesRaw: String
  var preparationScheduleOverridesRaw: String
  var createdAt: Date
  var updatedAt: Date

  init(
    reminderExternalIdentifier: String,
    attachmentManifestRaw: String,
    scheduledDurationMinutes: Int?,
    ownedCalendarEventExternalIdentifier: String?,
    boardStageRaw: String?,
    importanceRaw: String?,
    isFlagged: Bool = false,
    requiredWorkDays: Int,
    completedWorkUnits: Int,
    completedWorkUnitDatesRaw: String,
    preparationScheduleOverridesRaw: String,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.reminderExternalIdentifier = reminderExternalIdentifier
    self.attachmentManifestRaw = attachmentManifestRaw
    self.scheduledDurationMinutes = scheduledDurationMinutes
    self.ownedCalendarEventExternalIdentifier = ownedCalendarEventExternalIdentifier
    self.boardStageRaw = boardStageRaw
    self.importanceRaw = importanceRaw
    self.isFlagged = isFlagged
    self.requiredWorkDays = requiredWorkDays
    self.completedWorkUnits = completedWorkUnits
    self.completedWorkUnitDatesRaw = completedWorkUnitDatesRaw
    self.preparationScheduleOverridesRaw = preparationScheduleOverridesRaw
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case reminderExternalIdentifier
    case attachmentManifestRaw
    case scheduledDurationMinutes
    case ownedCalendarEventExternalIdentifier
    case boardStageRaw
    case importanceRaw
    case isFlagged
    case requiredWorkDays
    case completedWorkUnits
    case completedWorkUnitDatesRaw
    case preparationScheduleOverridesRaw
    case createdAt
    case updatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    reminderExternalIdentifier = try container.decode(String.self, forKey: .reminderExternalIdentifier)
    attachmentManifestRaw = try container.decode(String.self, forKey: .attachmentManifestRaw)
    scheduledDurationMinutes = try container.decodeIfPresent(
      Int.self,
      forKey: .scheduledDurationMinutes
    )
    ownedCalendarEventExternalIdentifier = try container.decodeIfPresent(
      String.self,
      forKey: .ownedCalendarEventExternalIdentifier
    )
    boardStageRaw = try container.decodeIfPresent(String.self, forKey: .boardStageRaw)
    importanceRaw = try container.decodeIfPresent(String.self, forKey: .importanceRaw)
    isFlagged = try container.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
    requiredWorkDays = try container.decode(Int.self, forKey: .requiredWorkDays)
    completedWorkUnits = try container.decode(Int.self, forKey: .completedWorkUnits)
    completedWorkUnitDatesRaw = try container.decode(String.self, forKey: .completedWorkUnitDatesRaw)
    preparationScheduleOverridesRaw = try container.decode(
      String.self,
      forKey: .preparationScheduleOverridesRaw
    )
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)

    struct LegacyKey: CodingKey {
      var stringValue: String
      var intValue: Int? { nil }
      init?(intValue: Int) { nil }
      init?(stringValue: String) { self.stringValue = stringValue }
    }

    let legacyContainer = try decoder.container(keyedBy: LegacyKey.self)
    _ = try legacyContainer.decodeIfPresent(
      String.self,
      forKey: LegacyKey(stringValue: "app" + "NoteMarkdown")!
    )
    _ = try legacyContainer.decodeIfPresent(
      String.self,
      forKey: LegacyKey(stringValue: "block" + "Reason")!
    )
  }
}

struct ReminderProjectFeatureSidecarRecord: Codable, Equatable {
  var reminderListExternalIdentifier: String
  var projectNoteMarkdown: String
  var localStartDate: Date?
  var localDeadline: Date?
  var progressStageRaw: String?
  var boardOrder: Int?
  var attachmentManifestRaw: String
  var createdAt: Date
  var updatedAt: Date
}

struct ReminderProjectConnectionSidecarRecord: Codable, Equatable {
  var projectID: UUID
  var reminderListIdentifier: String?
  var reminderListExternalIdentifier: String
  var createdAt: Date
  var updatedAt: Date
}

struct ReminderTaskSourceRuntimeState: Codable, Equatable {
  var reminderExternalIdentifier: String
  var lastImportedNormalizedNoteHash: String?
  var lastExportedNormalizedNoteHash: String?
  var lastObservedReminderModifiedAt: Date?
  var lastObservedReminderRawPayloadRaw: String?
  var noteConflictStateRaw: String?
}

enum OutlineProjectionEngine {
  case noteSource
  case metadataSnapshot
  case appSidecar
  case combined
}

struct OutlineProjectionRuntimeSnapshot: Equatable {
  var projects: [OutlinerProject]
  var currentProjectID: UUID
  var featureSidecarByReminderIdentifier: [String: OutlinerTaskSidecarMetadata]
  var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata]
  var reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot]
  var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot]
  var projectReminderListIdentifierByProjectID: [UUID: String]
  var projectReminderListExternalIdentifierByProjectID: [UUID: String]
  var projectColorHexByProjectID: [UUID: String]
  var reminderModifiedAtByReminderExternalIdentifier: [String: Date]
  var workspaceStructureRecord: ReminderWorkspaceStructureRecord?
  var projectTaskOrderByReminderListExternalIdentifier: [String: ReminderProjectTaskOrderRecord]
  var projectRootStructureByReminderListExternalIdentifier:
    [String: ReminderProjectRootStructureRecord]
  var projectFeatureSidecarByProjectID: [UUID: ReminderProjectFeatureSidecarRecord]
  var projectFeatureSidecarByReminderListExternalIdentifier:
    [String: ReminderProjectFeatureSidecarRecord]
  var taskFeatureSidecarByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord]
  var taskSourceRuntimeStateByReminderExternalIdentifier: [String: ReminderTaskSourceRuntimeState]
  var projectionEngine: OutlineProjectionEngine

  init(
    projects: [OutlinerProject],
    currentProjectID: UUID,
    featureSidecarByReminderIdentifier: [String: OutlinerTaskSidecarMetadata],
    featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata],
    reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot],
    reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot],
    projectReminderListIdentifierByProjectID: [UUID: String],
    projectReminderListExternalIdentifierByProjectID: [UUID: String],
    projectColorHexByProjectID: [UUID: String],
    reminderModifiedAtByReminderExternalIdentifier: [String: Date],
    workspaceStructureRecord: ReminderWorkspaceStructureRecord?,
    projectTaskOrderByReminderListExternalIdentifier: [String: ReminderProjectTaskOrderRecord],
    projectRootStructureByReminderListExternalIdentifier:
      [String: ReminderProjectRootStructureRecord] = [:],
    projectFeatureSidecarByProjectID: [UUID: ReminderProjectFeatureSidecarRecord],
    projectFeatureSidecarByReminderListExternalIdentifier:
      [String: ReminderProjectFeatureSidecarRecord],
    taskFeatureSidecarByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord],
    taskSourceRuntimeStateByReminderExternalIdentifier: [String: ReminderTaskSourceRuntimeState],
    projectionEngine: OutlineProjectionEngine
  ) {
    self.projects = projects
    self.currentProjectID = currentProjectID
    self.featureSidecarByReminderIdentifier = featureSidecarByReminderIdentifier
    self.featureSidecarByNodeID = featureSidecarByNodeID
    self.reminderMetadataByReminderIdentifier = reminderMetadataByReminderIdentifier
    self.reminderMetadataByNodeID = reminderMetadataByNodeID
    self.projectReminderListIdentifierByProjectID = projectReminderListIdentifierByProjectID
    self.projectReminderListExternalIdentifierByProjectID =
      projectReminderListExternalIdentifierByProjectID
    self.projectColorHexByProjectID = projectColorHexByProjectID
    self.reminderModifiedAtByReminderExternalIdentifier =
      reminderModifiedAtByReminderExternalIdentifier
    self.workspaceStructureRecord = workspaceStructureRecord
    self.projectTaskOrderByReminderListExternalIdentifier =
      projectTaskOrderByReminderListExternalIdentifier
    self.projectRootStructureByReminderListExternalIdentifier =
      projectRootStructureByReminderListExternalIdentifier
    self.projectFeatureSidecarByProjectID = projectFeatureSidecarByProjectID
    self.projectFeatureSidecarByReminderListExternalIdentifier =
      projectFeatureSidecarByReminderListExternalIdentifier
    self.taskFeatureSidecarByReminderExternalIdentifier =
      taskFeatureSidecarByReminderExternalIdentifier
    self.taskSourceRuntimeStateByReminderExternalIdentifier =
      taskSourceRuntimeStateByReminderExternalIdentifier
    self.projectionEngine = projectionEngine
  }
}

extension OutlineProjectionRuntimeSnapshot {
  func reminderMetadata(for node: OutlineNode) -> ReminderMetadataSnapshot? {
    guard
      let reminderIdentifier = node.reminderIdentifier?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !reminderIdentifier.isEmpty
    else {
      return nil
    }
    return reminderMetadataByReminderIdentifier[reminderIdentifier]
  }
}

struct OutlinerSessionSnapshot {
  let projects: [OutlinerProject]
  let currentProjectID: UUID
  let reminderLinks: [UUID: String]
  let featureSidecarByReminderIdentifier: [String: OutlinerTaskSidecarMetadata]
  let featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata]
  let reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot]
  let reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot]
  let workspaceStructureRecord: ReminderWorkspaceStructureRecord?
  let projectTaskOrderByReminderListExternalIdentifier: [String: ReminderProjectTaskOrderRecord]
  let projectRootStructureByReminderListExternalIdentifier:
    [String: ReminderProjectRootStructureRecord]
  let projectFeatureSidecarByReminderListExternalIdentifier:
    [String: ReminderProjectFeatureSidecarRecord]
  let taskFeatureSidecarByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord]
  let taskSourceRuntimeStateByReminderExternalIdentifier: [String: ReminderTaskSourceRuntimeState]
  let firstSyncCompleted: Bool

  init(
    projects: [OutlinerProject],
    currentProjectID: UUID,
    reminderLinks: [UUID: String],
    featureSidecarByReminderIdentifier: [String: OutlinerTaskSidecarMetadata],
    featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata],
    reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot],
    reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot],
    workspaceStructureRecord: ReminderWorkspaceStructureRecord?,
    projectTaskOrderByReminderListExternalIdentifier: [String: ReminderProjectTaskOrderRecord],
    projectRootStructureByReminderListExternalIdentifier:
      [String: ReminderProjectRootStructureRecord] = [:],
    projectFeatureSidecarByReminderListExternalIdentifier:
      [String: ReminderProjectFeatureSidecarRecord],
    taskFeatureSidecarByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord],
    taskSourceRuntimeStateByReminderExternalIdentifier:
      [String: ReminderTaskSourceRuntimeState],
    firstSyncCompleted: Bool
  ) {
    self.projects = projects
    self.currentProjectID = currentProjectID
    self.reminderLinks = reminderLinks
    self.featureSidecarByReminderIdentifier = featureSidecarByReminderIdentifier
    self.featureSidecarByNodeID = featureSidecarByNodeID
    self.reminderMetadataByReminderIdentifier = reminderMetadataByReminderIdentifier
    self.reminderMetadataByNodeID = reminderMetadataByNodeID
    self.workspaceStructureRecord = workspaceStructureRecord
    self.projectTaskOrderByReminderListExternalIdentifier =
      projectTaskOrderByReminderListExternalIdentifier
    self.projectRootStructureByReminderListExternalIdentifier =
      projectRootStructureByReminderListExternalIdentifier
    self.projectFeatureSidecarByReminderListExternalIdentifier =
      projectFeatureSidecarByReminderListExternalIdentifier
    self.taskFeatureSidecarByReminderExternalIdentifier =
      taskFeatureSidecarByReminderExternalIdentifier
    self.taskSourceRuntimeStateByReminderExternalIdentifier =
      taskSourceRuntimeStateByReminderExternalIdentifier
    self.firstSyncCompleted = firstSyncCompleted
  }
}

extension OutlinerSessionSnapshot {
  func mergedForAppCache(
    existing: OutlinerSessionSnapshot?,
    preferredProjectID: UUID?
  ) -> OutlinerSessionSnapshot {
    guard preferredProjectID != nil, let existing else {
      return self
    }

    let mergedProjects = Self.mergeProjects(projects, into: existing.projects)
    let mergedProjectIDs = Set(mergedProjects.map(\.id))
    let resolvedCurrentProjectID =
      mergedProjectIDs.contains(currentProjectID) ? currentProjectID
      : mergedProjectIDs.contains(existing.currentProjectID) ? existing.currentProjectID
      : mergedProjects.first?.id ?? currentProjectID

    return OutlinerSessionSnapshot(
      projects: mergedProjects,
      currentProjectID: resolvedCurrentProjectID,
      reminderLinks: existing.reminderLinks.merging(reminderLinks) { _, new in new },
      featureSidecarByReminderIdentifier:
        existing.featureSidecarByReminderIdentifier.merging(featureSidecarByReminderIdentifier) {
          _, new in new
        },
      featureSidecarByNodeID:
        existing.featureSidecarByNodeID.merging(featureSidecarByNodeID) { _, new in new },
      reminderMetadataByReminderIdentifier:
        existing.reminderMetadataByReminderIdentifier.merging(reminderMetadataByReminderIdentifier) {
          _, new in new
        },
      reminderMetadataByNodeID:
        existing.reminderMetadataByNodeID.merging(reminderMetadataByNodeID) { _, new in new },
      workspaceStructureRecord: workspaceStructureRecord ?? existing.workspaceStructureRecord,
      projectTaskOrderByReminderListExternalIdentifier:
        existing.projectTaskOrderByReminderListExternalIdentifier.merging(
          projectTaskOrderByReminderListExternalIdentifier
        ) { _, new in new },
      projectRootStructureByReminderListExternalIdentifier:
        existing.projectRootStructureByReminderListExternalIdentifier.merging(
          projectRootStructureByReminderListExternalIdentifier
        ) { _, new in new },
      projectFeatureSidecarByReminderListExternalIdentifier:
        existing.projectFeatureSidecarByReminderListExternalIdentifier.merging(
          projectFeatureSidecarByReminderListExternalIdentifier
        ) { _, new in new },
      taskFeatureSidecarByReminderExternalIdentifier:
        existing.taskFeatureSidecarByReminderExternalIdentifier.merging(
          taskFeatureSidecarByReminderExternalIdentifier
        ) { _, new in new },
      taskSourceRuntimeStateByReminderExternalIdentifier:
        existing.taskSourceRuntimeStateByReminderExternalIdentifier.merging(
          taskSourceRuntimeStateByReminderExternalIdentifier
        ) { _, new in new },
      firstSyncCompleted: firstSyncCompleted || existing.firstSyncCompleted
    )
  }

  fileprivate static func mergeProjects(
    _ updatedProjects: [OutlinerProject],
    into existingProjects: [OutlinerProject]
  ) -> [OutlinerProject] {
    guard !existingProjects.isEmpty else { return updatedProjects }
    guard !updatedProjects.isEmpty else { return existingProjects }

    var updatedByID = Dictionary(uniqueKeysWithValues: updatedProjects.map { ($0.id, $0) })
    var mergedProjects = existingProjects.map { project in
      updatedByID.removeValue(forKey: project.id) ?? project
    }

    if !updatedByID.isEmpty {
      let appendedProjects = updatedProjects.filter { updatedByID[$0.id] != nil }
      mergedProjects.append(contentsOf: appendedProjects)
    }

    return mergedProjects
  }
}

struct ReminderProjectionSidecarPayload: Codable, Equatable {
  var workspaceStructureRecord: ReminderWorkspaceStructureRecord?
  var projectConnectionSidecarByReminderListExternalIdentifier:
    [String: ReminderProjectConnectionSidecarRecord]
  var projectTaskOrderByReminderListExternalIdentifier: [String: ReminderProjectTaskOrderRecord]
  var projectRootStructureByReminderListExternalIdentifier:
    [String: ReminderProjectRootStructureRecord]
  var projectFeatureSidecarByReminderListExternalIdentifier:
    [String: ReminderProjectFeatureSidecarRecord]
  var taskFeatureSidecarByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord]
  var taskSourceRuntimeStateByReminderExternalIdentifier: [String: ReminderTaskSourceRuntimeState]

  private enum CodingKeys: String, CodingKey {
    case workspaceStructureRecord
    case projectConnectionSidecarByReminderListExternalIdentifier
    case projectTaskOrderByReminderListExternalIdentifier
    case projectRootStructureByReminderListExternalIdentifier
    case projectFeatureSidecarByReminderListExternalIdentifier
    case taskFeatureSidecarByReminderExternalIdentifier
    case taskSourceRuntimeStateByReminderExternalIdentifier
  }

  init(
    workspaceStructureRecord: ReminderWorkspaceStructureRecord?,
    projectConnectionSidecarByReminderListExternalIdentifier:
      [String: ReminderProjectConnectionSidecarRecord] = [:],
    projectTaskOrderByReminderListExternalIdentifier: [String: ReminderProjectTaskOrderRecord],
    projectRootStructureByReminderListExternalIdentifier:
      [String: ReminderProjectRootStructureRecord] = [:],
    projectFeatureSidecarByReminderListExternalIdentifier:
      [String: ReminderProjectFeatureSidecarRecord],
    taskFeatureSidecarByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord],
    taskSourceRuntimeStateByReminderExternalIdentifier:
      [String: ReminderTaskSourceRuntimeState]
  ) {
    self.workspaceStructureRecord = workspaceStructureRecord
    self.projectConnectionSidecarByReminderListExternalIdentifier =
      projectConnectionSidecarByReminderListExternalIdentifier
    self.projectTaskOrderByReminderListExternalIdentifier =
      projectTaskOrderByReminderListExternalIdentifier
    self.projectRootStructureByReminderListExternalIdentifier =
      projectRootStructureByReminderListExternalIdentifier
    self.projectFeatureSidecarByReminderListExternalIdentifier =
      projectFeatureSidecarByReminderListExternalIdentifier
    self.taskFeatureSidecarByReminderExternalIdentifier =
      taskFeatureSidecarByReminderExternalIdentifier
    self.taskSourceRuntimeStateByReminderExternalIdentifier =
      taskSourceRuntimeStateByReminderExternalIdentifier
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    workspaceStructureRecord = try container.decodeIfPresent(
      ReminderWorkspaceStructureRecord.self,
      forKey: .workspaceStructureRecord
    )
    projectConnectionSidecarByReminderListExternalIdentifier =
      try container.decodeIfPresent(
        [String: ReminderProjectConnectionSidecarRecord].self,
        forKey: .projectConnectionSidecarByReminderListExternalIdentifier
      ) ?? [:]
    projectTaskOrderByReminderListExternalIdentifier =
      try container.decodeIfPresent(
        [String: ReminderProjectTaskOrderRecord].self,
        forKey: .projectTaskOrderByReminderListExternalIdentifier
      ) ?? [:]
    projectRootStructureByReminderListExternalIdentifier =
      try container.decodeIfPresent(
        [String: ReminderProjectRootStructureRecord].self,
        forKey: .projectRootStructureByReminderListExternalIdentifier
      ) ?? [:]
    projectFeatureSidecarByReminderListExternalIdentifier =
      try container.decodeIfPresent(
        [String: ReminderProjectFeatureSidecarRecord].self,
        forKey: .projectFeatureSidecarByReminderListExternalIdentifier
      ) ?? [:]
    taskFeatureSidecarByReminderExternalIdentifier =
      try container.decodeIfPresent(
        [String: ReminderTaskFeatureSidecarRecord].self,
        forKey: .taskFeatureSidecarByReminderExternalIdentifier
      ) ?? [:]
    taskSourceRuntimeStateByReminderExternalIdentifier =
      try container.decodeIfPresent(
        [String: ReminderTaskSourceRuntimeState].self,
        forKey: .taskSourceRuntimeStateByReminderExternalIdentifier
      ) ?? [:]
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(workspaceStructureRecord, forKey: .workspaceStructureRecord)
    try container.encode(
      projectConnectionSidecarByReminderListExternalIdentifier,
      forKey: .projectConnectionSidecarByReminderListExternalIdentifier
    )
    try container.encode(
      projectTaskOrderByReminderListExternalIdentifier,
      forKey: .projectTaskOrderByReminderListExternalIdentifier
    )
    try container.encode(
      projectRootStructureByReminderListExternalIdentifier,
      forKey: .projectRootStructureByReminderListExternalIdentifier
    )
    try container.encode(
      projectFeatureSidecarByReminderListExternalIdentifier,
      forKey: .projectFeatureSidecarByReminderListExternalIdentifier
    )
    try container.encode(
      taskFeatureSidecarByReminderExternalIdentifier,
      forKey: .taskFeatureSidecarByReminderExternalIdentifier
    )
    try container.encode(
      taskSourceRuntimeStateByReminderExternalIdentifier,
      forKey: .taskSourceRuntimeStateByReminderExternalIdentifier
    )
  }

  static let empty = ReminderProjectionSidecarPayload(
    workspaceStructureRecord: nil,
    projectConnectionSidecarByReminderListExternalIdentifier: [:],
    projectTaskOrderByReminderListExternalIdentifier: [:],
    projectRootStructureByReminderListExternalIdentifier: [:],
    projectFeatureSidecarByReminderListExternalIdentifier: [:],
    taskFeatureSidecarByReminderExternalIdentifier: [:],
    taskSourceRuntimeStateByReminderExternalIdentifier: [:]
  )

  mutating func stripAppMemoryReadModels() {
    taskSourceRuntimeStateByReminderExternalIdentifier = [:]
  }

  func sanitizedForPersistence() -> ReminderProjectionSidecarPayload {
    var sanitized = self
    sanitized.stripAppMemoryReadModels()
    return sanitized
  }
}

extension OutlineProjectionRuntimeSnapshot {
  func mergedForAppCache(
    existing: OutlineProjectionRuntimeSnapshot?,
    preferredProjectID: UUID?
  ) -> OutlineProjectionRuntimeSnapshot {
    guard preferredProjectID != nil, let existing else {
      return self
    }

    let mergedProjects = OutlinerSessionSnapshot.mergeProjects(projects, into: existing.projects)
    let mergedProjectIDs = Set(mergedProjects.map(\.id))
    let resolvedCurrentProjectID =
      mergedProjectIDs.contains(currentProjectID) ? currentProjectID
      : mergedProjectIDs.contains(existing.currentProjectID) ? existing.currentProjectID
      : mergedProjects.first?.id ?? currentProjectID

    return OutlineProjectionRuntimeSnapshot(
      projects: mergedProjects,
      currentProjectID: resolvedCurrentProjectID,
      featureSidecarByReminderIdentifier:
        existing.featureSidecarByReminderIdentifier.merging(featureSidecarByReminderIdentifier) {
          _, new in new
        },
      featureSidecarByNodeID:
        existing.featureSidecarByNodeID.merging(featureSidecarByNodeID) { _, new in new },
      reminderMetadataByReminderIdentifier:
        existing.reminderMetadataByReminderIdentifier.merging(reminderMetadataByReminderIdentifier) {
          _, new in new
        },
      reminderMetadataByNodeID:
        existing.reminderMetadataByNodeID.merging(reminderMetadataByNodeID) { _, new in new },
      projectReminderListIdentifierByProjectID:
        existing.projectReminderListIdentifierByProjectID.merging(
          projectReminderListIdentifierByProjectID
        ) { _, new in new },
      projectReminderListExternalIdentifierByProjectID:
        existing.projectReminderListExternalIdentifierByProjectID.merging(
          projectReminderListExternalIdentifierByProjectID
        ) { _, new in new },
      projectColorHexByProjectID:
        existing.projectColorHexByProjectID.merging(projectColorHexByProjectID) { _, new in new },
      reminderModifiedAtByReminderExternalIdentifier:
        existing.reminderModifiedAtByReminderExternalIdentifier.merging(
          reminderModifiedAtByReminderExternalIdentifier
        ) { _, new in new },
      workspaceStructureRecord: workspaceStructureRecord ?? existing.workspaceStructureRecord,
      projectTaskOrderByReminderListExternalIdentifier:
        existing.projectTaskOrderByReminderListExternalIdentifier.merging(
          projectTaskOrderByReminderListExternalIdentifier
        ) { _, new in new },
      projectRootStructureByReminderListExternalIdentifier:
        existing.projectRootStructureByReminderListExternalIdentifier.merging(
          projectRootStructureByReminderListExternalIdentifier
        ) { _, new in new },
      projectFeatureSidecarByProjectID:
        existing.projectFeatureSidecarByProjectID.merging(projectFeatureSidecarByProjectID) {
          _, new in new
        },
      projectFeatureSidecarByReminderListExternalIdentifier:
        existing.projectFeatureSidecarByReminderListExternalIdentifier.merging(
          projectFeatureSidecarByReminderListExternalIdentifier
        ) { _, new in new },
      taskFeatureSidecarByReminderExternalIdentifier:
        existing.taskFeatureSidecarByReminderExternalIdentifier.merging(
          taskFeatureSidecarByReminderExternalIdentifier
        ) { _, new in new },
      taskSourceRuntimeStateByReminderExternalIdentifier:
        existing.taskSourceRuntimeStateByReminderExternalIdentifier.merging(
          taskSourceRuntimeStateByReminderExternalIdentifier
        ) { _, new in new },
      projectionEngine: projectionEngine
    )
  }
}

struct ReminderProjectionSidecarStore {
  let fileURL: URL

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  private static let decoder = JSONDecoder()

  func load(fileManager: FileManager = .default) -> ReminderProjectionSidecarPayload? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }
    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }
    guard let payload = try? Self.decoder.decode(ReminderProjectionSidecarPayload.self, from: data)
    else {
      return nil
    }
    let sanitizedPayload = payload.sanitizedForPersistence()
    if sanitizedPayload != payload {
      try? save(sanitizedPayload, fileManager: fileManager)
    }
    return sanitizedPayload
  }

  func save(
    _ payload: ReminderProjectionSidecarPayload,
    fileManager: FileManager = .default
  ) throws {
    let parentURL = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: parentURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let data = try Self.encoder.encode(payload.sanitizedForPersistence())
    try data.write(to: fileURL, options: .atomic)
  }
}

enum ReminderProjectionSidecarStoreFactory {
  static func make(dataDirectory: URL?) -> ReminderProjectionSidecarStore? {
    guard let dataDirectory else { return nil }
    return ReminderProjectionSidecarStore(
      fileURL: dataDirectory.appendingPathComponent(
        "reminder-projection-sidecars.json",
        isDirectory: false
      )
    )
  }
}

struct WorkspaceProjectRuntimeRecord: Equatable {
  let id: UUID
  let title: String
  let colorHex: String?
  let reminderListIdentifier: String?
  let reminderListExternalIdentifier: String?
  let projectNoteMarkdown: String
  let localStartDate: Date?
  let localDeadline: Date?
  let progressStageRaw: String?
  let boardOrder: Int?
  let createdAt: Date
  let updatedAt: Date
  let isArchived: Bool
}

enum WorkspaceProjectRuntimeRecordBuilder {
  static func records(
    from runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    projectIDs: [UUID]
  ) -> [UUID: WorkspaceProjectRuntimeRecord] {
    guard let runtimeSnapshot else { return [:] }
    let requestedProjectIDs = Set(projectIDs)

    return runtimeSnapshot.projects.reduce(into: [:]) { partialResult, project in
      guard requestedProjectIDs.isEmpty || requestedProjectIDs.contains(project.id) else { return }
      let featureSidecar = runtimeSnapshot.projectFeatureSidecarByProjectID[project.id]
      let latestReminderModifiedAt = project.document.flatten().compactMap { entry -> Date? in
        guard entry.node.type.isTask,
          let reminderExternalIdentifier = entry.node.reminderExternalIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !reminderExternalIdentifier.isEmpty
        else {
          return nil
        }
        return runtimeSnapshot.reminderModifiedAtByReminderExternalIdentifier[
          reminderExternalIdentifier]
      }.max()
      let updatedAt = [featureSidecar?.updatedAt, latestReminderModifiedAt].compactMap { $0 }.max()
        ?? .distantPast
      let createdAt = featureSidecar?.createdAt ?? updatedAt

      partialResult[project.id] = WorkspaceProjectRuntimeRecord(
        id: project.id,
        title: project.title,
        colorHex: runtimeSnapshot.projectColorHexByProjectID[project.id],
        reminderListIdentifier: runtimeSnapshot.projectReminderListIdentifierByProjectID[project.id],
        reminderListExternalIdentifier:
          runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[project.id],
        projectNoteMarkdown: featureSidecar?.projectNoteMarkdown ?? "",
        localStartDate: featureSidecar?.localStartDate,
        localDeadline: featureSidecar?.localDeadline,
        progressStageRaw: featureSidecar?.progressStageRaw,
        boardOrder: featureSidecar?.boardOrder,
        createdAt: createdAt,
        updatedAt: updatedAt,
        isArchived: false
      )
    }
  }
}

@MainActor
enum ReminderSourceProjectionSnapshotLoader {
  static func load(
    gateway: ReminderGateway,
    dataDirectory: URL?,
    normalizedSQLiteURL: URL?
  ) async throws -> OutlineProjectionRuntimeSnapshot {
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    let lists = try await provider.fetchAllLists()
    let itemsByListIdentifier = try await provider.fetchItemsByList(for: lists)
    let sidecarPayload = ReminderProjectionSidecarReadService.loadSanitizedPayload(
      dataDirectory: dataDirectory
    )
    let mirrorPlacements: [TaskMirrorPlacementRecord] =
      if let normalizedSQLiteURL {
        (try? await TaskMirrorPlacementStore(databaseURL: normalizedSQLiteURL).allRecords()) ?? []
      } else {
        []
      }

    return OutlineProjectionRuntimeSnapshot.fromSource(
      lists: lists,
      itemsByListIdentifier: itemsByListIdentifier,
      workspaceStructureRecord: sidecarPayload.workspaceStructureRecord,
      projectConnectionsByReminderListExternalIdentifier:
        sidecarPayload.projectConnectionSidecarByReminderListExternalIdentifier,
      projectTaskOrdersByReminderListExternalIdentifier:
        sidecarPayload.projectTaskOrderByReminderListExternalIdentifier,
      projectRootStructuresByReminderListExternalIdentifier:
        sidecarPayload.projectRootStructureByReminderListExternalIdentifier,
      projectFeatureSidecarsByReminderListExternalIdentifier:
        sidecarPayload.projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarsByReminderExternalIdentifier:
        sidecarPayload.taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStatesByReminderExternalIdentifier: [:],
      mirrorPlacements: mirrorPlacements
    )
  }
}

extension ReminderWorkspaceStructureRecord {
  var orderedReminderListExternalIdentifiers: [String] {
    ReminderProjectionOrderCodec.decode(orderedReminderListExternalIdentifiersRaw)
  }

  init(
    orderedReminderListExternalIdentifiers: [String],
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.init(
      orderedReminderListExternalIdentifiersRaw: ReminderProjectionOrderCodec.encode(
        orderedReminderListExternalIdentifiers),
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}

extension ReminderProjectTaskOrderRecord {
  var orderedTopLevelReminderExternalIdentifiers: [String] {
    ReminderProjectionOrderCodec.decode(orderedTopLevelReminderExternalIdentifiersRaw)
  }

  init(
    reminderListExternalIdentifier: String,
    orderedTopLevelReminderExternalIdentifiers: [String],
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.init(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      orderedTopLevelReminderExternalIdentifiersRaw: ReminderProjectionOrderCodec.encode(
        orderedTopLevelReminderExternalIdentifiers),
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}

extension ReminderTaskFeatureSidecarRecord {
  var featureSidecarMetadata: OutlinerTaskSidecarMetadata {
    OutlinerTaskSidecarMetadata(
      requiredWorkDays: max(0, requiredWorkDays),
      scheduledDurationMinutes: scheduledDurationMinutes,
      attachmentPreviews: []
    )
  }

  var hasMeaningfulContent: Bool {
    !attachmentManifestRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || scheduledDurationMinutes != nil
      || (ownedCalendarEventExternalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty == false)
      || (boardStageRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      || (importanceRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      || isFlagged
      || requiredWorkDays > 0
      || completedWorkUnits > 0
      || !completedWorkUnitDatesRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !preparationScheduleOverridesRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

extension ReminderProjectFeatureSidecarRecord {
  var hasMeaningfulContent: Bool {
    !projectNoteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || localStartDate != nil
      || localDeadline != nil
      || (progressStageRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      || boardOrder != nil
      || !attachmentManifestRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

extension ReminderProjectConnectionSidecarRecord {
  static func record(
    projectID: UUID,
    reminderListIdentifier: String?,
    reminderListExternalIdentifier: String,
    existing: ReminderProjectConnectionSidecarRecord?,
    now: Date = .now
  ) -> ReminderProjectConnectionSidecarRecord {
    ReminderProjectConnectionSidecarRecord(
      projectID: projectID,
      reminderListIdentifier: ReminderProjectionIdentity.normalized(reminderListIdentifier),
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now
    )
  }
}

extension ReminderListImportSnapshot {
  var resolvedReminderListExternalIdentifier: String {
    ReminderProjectionIdentity.normalized(externalIdentifier) ?? identifier
  }
}

extension ReminderItemImportSnapshot {
  var resolvedReminderExternalIdentifier: String {
    ReminderProjectionIdentity.normalized(externalIdentifier) ?? identifier
  }

  var reminderMetadataSnapshot: ReminderMetadataSnapshot {
    ReminderMetadataSnapshot(
      dueDate: dueDate,
      completionDate: completionDate,
      hasExplicitTime: scheduleHasExplicitTime,
      recurrence: OutlinerIntegratedStore.decodeRecurrence(rawValue: recurrenceRuleRaw),
      priority: priority
    )
  }

  var noteSourceDocument: ReminderNoteSourceDocument {
    ReminderNoteSourceCodec.parseReminderRawNote(notes)
  }
}

extension ReminderNoteSourceNode {
  var depth: Int {
    switch self {
    case let .bullet(_, depth), let .childAnchor(_, depth):
      return depth
    }
  }
}

enum ReminderProjectionOrderCodec {
  private static let decoder = JSONDecoder()
  private static let encoder = JSONEncoder()

  static func decode(_ raw: String) -> [String] {
    guard let data = raw.data(using: .utf8),
          let decoded = try? decoder.decode([String].self, from: data)
    else {
      return []
    }
    return decoded.compactMap { identifier in
      ReminderProjectionIdentity.normalized(identifier)
    }
  }

  static func encode(_ orderedIdentifiers: [String]) -> String {
    let normalized = orderedIdentifiers.compactMap(ReminderProjectionIdentity.normalized)
    guard let data = try? encoder.encode(normalized),
          let raw = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return raw
  }

  static func reorder<T>(
    _ values: [T],
    orderedIdentifiers: [String],
    identifier: (T) -> String
  ) -> [T] {
    let keyedValues = Dictionary(
      values.map { value in
        (identifier(value), value)
      },
      uniquingKeysWith: { lhs, _ in lhs }
    )
    var ordered: [T] = []
    var consumed: Set<String> = []

    for key in orderedIdentifiers {
      guard let value = keyedValues[key], consumed.insert(key).inserted else { continue }
      ordered.append(value)
    }

    let remainder = values
      .filter { consumed.contains(identifier($0)) == false }
      .sorted { lhs, rhs in
        identifier(lhs).localizedStandardCompare(identifier(rhs)) == .orderedAscending
      }
    ordered.append(contentsOf: remainder)
    return ordered
  }
}

enum ReminderProjectionIdentity {
  private static let emptyProjectionUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

  static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          value.isEmpty == false
    else {
      return nil
    }
    return value
  }

  static func emptyProjectID() -> UUID {
    emptyProjectionUUID
  }

  static func projectID(for reminderListExternalIdentifier: String) -> UUID {
    deterministicUUID(namespace: "reminder-project", key: reminderListExternalIdentifier)
  }

  static func taskID(for reminderExternalIdentifier: String) -> UUID {
    deterministicUUID(namespace: "reminder-task", key: reminderExternalIdentifier)
  }

  static func noteNodeID(
    parentReminderExternalIdentifier: String,
    path: [Int],
    text: String
  ) -> UUID {
    deterministicUUID(
      namespace: "reminder-note-node",
      key: "\(parentReminderExternalIdentifier)|\(path.map(String.init).joined(separator: "."))|\(text)"
    )
  }

  private static func deterministicUUID(namespace: String, key: String) -> UUID {
    let digest = SHA256.hash(data: Data("\(namespace)|\(key)".utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}

enum ReminderMetadataSnapshotEngine {
  struct TaskSnapshot: Equatable {
    var reminderIdentifier: String
    var reminderExternalIdentifier: String
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    var modifiedAt: Date
    var reminderMetadata: ReminderMetadataSnapshot
    var sourceDocument: ReminderNoteSourceDocument
  }

  struct ProjectSnapshot: Equatable {
    var projectID: UUID
    var reminderListIdentifier: String
    var reminderListExternalIdentifier: String
    var title: String
    var colorHex: String?
    var orderedTopLevelTasks: [TaskSnapshot]
    var tasksByExternalIdentifier: [String: TaskSnapshot]
  }

  struct MirrorRootSnapshot: Equatable {
    var placement: TaskMirrorPlacementRecord
    var task: TaskSnapshot
    var sourceProjectID: UUID?
  }

  static func projectSnapshots(
    lists: [ReminderListImportSnapshot],
    itemsByListIdentifier: [String: [ReminderItemImportSnapshot]],
    workspaceStructureRecord: ReminderWorkspaceStructureRecord? = nil,
    projectConnectionsByReminderListExternalIdentifier:
      [String: ReminderProjectConnectionSidecarRecord] = [:],
    projectTaskOrdersByReminderListExternalIdentifier: [String: ReminderProjectTaskOrderRecord] = [:]
  ) -> [ProjectSnapshot] {
    let unorderedProjects = lists.map { list -> ProjectSnapshot in
      let reminderListExternalIdentifier = list.resolvedReminderListExternalIdentifier
      let projectConnection =
        projectConnectionsByReminderListExternalIdentifier[reminderListExternalIdentifier]
      let resolvedProjectID =
        projectConnection?.projectID
        ?? ReminderProjectionIdentity.projectID(for: reminderListExternalIdentifier)
      let resolvedReminderListIdentifier =
        ReminderProjectionIdentity.normalized(projectConnection?.reminderListIdentifier)
        ?? list.identifier
      let taskSnapshots = itemsByListIdentifier[list.identifier, default: []].map { item in
        TaskSnapshot(
          reminderIdentifier: item.identifier,
          reminderExternalIdentifier: item.resolvedReminderExternalIdentifier,
          title: item.title,
          isCompleted: item.isCompleted,
          createdAt: item.createdAt,
          modifiedAt: item.modifiedAt,
          reminderMetadata: item.reminderMetadataSnapshot,
          sourceDocument: item.noteSourceDocument
        )
      }
      let tasksByExternalIdentifier = Dictionary(
        taskSnapshots.map { ($0.reminderExternalIdentifier, $0) },
        uniquingKeysWith: { lhs, _ in lhs }
      )
      let anchoredChildIdentifiers = Set(
        taskSnapshots.flatMap { task in
          task.sourceDocument.ast.compactMap { node -> String? in
            guard case let .childAnchor(reminderExternalIdentifier, _) = node else { return nil }
            return reminderExternalIdentifier
          }
        }
      )
      let topLevelTasks = taskSnapshots.filter { task in
        anchoredChildIdentifiers.contains(task.reminderExternalIdentifier) == false
      }
      let orderedTopLevelTasks = ReminderProjectionOrderCodec.reorder(
        topLevelTasks,
        orderedIdentifiers: projectTaskOrdersByReminderListExternalIdentifier[
          reminderListExternalIdentifier
        ]?.orderedTopLevelReminderExternalIdentifiers ?? [],
        identifier: { $0.reminderExternalIdentifier }
      )

      return ProjectSnapshot(
        projectID: resolvedProjectID,
        reminderListIdentifier: resolvedReminderListIdentifier,
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        title: list.title,
        colorHex: list.colorHex,
        orderedTopLevelTasks: orderedTopLevelTasks,
        tasksByExternalIdentifier: tasksByExternalIdentifier
      )
    }

    return ReminderProjectionOrderCodec.reorder(
      unorderedProjects,
      orderedIdentifiers: workspaceStructureRecord?.orderedReminderListExternalIdentifiers ?? [],
      identifier: { $0.reminderListExternalIdentifier }
    )
  }
}

enum ReminderNoteSourceLoader {
  struct LoadedTaskTree: Equatable {
    var root: OutlineNode
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata]
  }

  static func loadTaskTree(
    from task: ReminderMetadataSnapshotEngine.TaskSnapshot,
    tasksByExternalIdentifier: [String: ReminderMetadataSnapshotEngine.TaskSnapshot],
    taskFeatureSidecarsByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord] = [:],
    ancestorTaskExternalIdentifiers: Set<String> = []
  ) -> LoadedTaskTree {
    let taskNodeID = ReminderProjectionIdentity.taskID(for: task.reminderExternalIdentifier)
    var consumedAnchorIdentifiers: Set<String> = []
    var cursor = 0
    let childResult = materializeNodes(
      from: task.sourceDocument.ast,
      cursor: &cursor,
      depth: 0,
      parentReminderExternalIdentifier: task.reminderExternalIdentifier,
      tasksByExternalIdentifier: tasksByExternalIdentifier,
      taskFeatureSidecarsByReminderExternalIdentifier: taskFeatureSidecarsByReminderExternalIdentifier,
      consumedAnchorIdentifiers: &consumedAnchorIdentifiers,
      ancestorTaskExternalIdentifiers: ancestorTaskExternalIdentifiers.union(
        [task.reminderExternalIdentifier]),
      parentPath: []
    )

    let rootNode = OutlineNode(
      id: taskNodeID,
      canonicalID: taskNodeID,
      text: task.title,
      type: .task(completed: task.isCompleted),
      children: childResult.nodes,
      reminderIdentifier: task.reminderIdentifier,
      reminderExternalIdentifier: task.reminderExternalIdentifier
    )
    var reminderMetadataByNodeID = childResult.reminderMetadataByNodeID
    reminderMetadataByNodeID[taskNodeID] = task.reminderMetadata
    var featureSidecarByNodeID = childResult.featureSidecarByNodeID
    if let sidecar = taskFeatureSidecarsByReminderExternalIdentifier[task.reminderExternalIdentifier] {
      featureSidecarByNodeID[taskNodeID] = sidecar.featureSidecarMetadata
    }

    return LoadedTaskTree(
      root: rootNode,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      featureSidecarByNodeID: featureSidecarByNodeID
    )
  }

  private struct MaterializedNodes {
    var nodes: [OutlineNode]
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata]
  }

  private static func materializeNodes(
    from ast: ReminderNoteAST,
    cursor: inout Int,
    depth: Int,
    parentReminderExternalIdentifier: String,
    tasksByExternalIdentifier: [String: ReminderMetadataSnapshotEngine.TaskSnapshot],
    taskFeatureSidecarsByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord],
    consumedAnchorIdentifiers: inout Set<String>,
    ancestorTaskExternalIdentifiers: Set<String>,
    parentPath: [Int]
  ) -> MaterializedNodes {
    var nodes: [OutlineNode] = []
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot] = [:]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata] = [:]

    while cursor < ast.count {
      let sourceNode = ast[cursor]
      let sourceDepth = sourceNode.depth
      if sourceDepth < depth {
        break
      }

      if sourceDepth > depth {
        guard nodes.isEmpty == false else {
          cursor += 1
          continue
        }
        let childPath = parentPath + [nodes.count - 1]
        let childResult = materializeNodes(
          from: ast,
          cursor: &cursor,
          depth: sourceDepth,
          parentReminderExternalIdentifier: parentReminderExternalIdentifier,
          tasksByExternalIdentifier: tasksByExternalIdentifier,
          taskFeatureSidecarsByReminderExternalIdentifier: taskFeatureSidecarsByReminderExternalIdentifier,
          consumedAnchorIdentifiers: &consumedAnchorIdentifiers,
          ancestorTaskExternalIdentifiers: ancestorTaskExternalIdentifiers,
          parentPath: childPath
        )
        nodes[nodes.count - 1].children.append(contentsOf: childResult.nodes)
        reminderMetadataByNodeID.merge(
          childResult.reminderMetadataByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        featureSidecarByNodeID.merge(
          childResult.featureSidecarByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        continue
      }

      let nodePath = parentPath + [nodes.count]
      cursor += 1
      switch sourceNode {
      case let .bullet(text, _):
        let nodeID = ReminderProjectionIdentity.noteNodeID(
          parentReminderExternalIdentifier: parentReminderExternalIdentifier,
          path: nodePath,
          text: text
        )
        var bulletNode = OutlineNode(
          id: nodeID,
          canonicalID: nodeID,
          text: text,
          type: .bullet
        )
        let childResult = materializeNodes(
          from: ast,
          cursor: &cursor,
          depth: depth + 1,
          parentReminderExternalIdentifier: parentReminderExternalIdentifier,
          tasksByExternalIdentifier: tasksByExternalIdentifier,
          taskFeatureSidecarsByReminderExternalIdentifier: taskFeatureSidecarsByReminderExternalIdentifier,
          consumedAnchorIdentifiers: &consumedAnchorIdentifiers,
          ancestorTaskExternalIdentifiers: ancestorTaskExternalIdentifiers,
          parentPath: nodePath
        )
        bulletNode.children = childResult.nodes
        nodes.append(bulletNode)
        reminderMetadataByNodeID.merge(
          childResult.reminderMetadataByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        featureSidecarByNodeID.merge(
          childResult.featureSidecarByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )

      case let .childAnchor(reminderExternalIdentifier, _):
        guard consumedAnchorIdentifiers.insert(reminderExternalIdentifier).inserted else {
          skipMalformedInlineChildren(from: ast, cursor: &cursor, deeperThan: depth)
          continue
        }

        guard let childTask = tasksByExternalIdentifier[reminderExternalIdentifier],
              ancestorTaskExternalIdentifiers.contains(reminderExternalIdentifier) == false
        else {
          let fallbackID = ReminderProjectionIdentity.noteNodeID(
            parentReminderExternalIdentifier: parentReminderExternalIdentifier,
            path: nodePath,
            text: "\(ReminderNoteSourceCodec.childAnchorPrefix)\(reminderExternalIdentifier)"
          )
          nodes.append(
            OutlineNode(
              id: fallbackID,
              canonicalID: fallbackID,
              text: "\(ReminderNoteSourceCodec.childAnchorPrefix)\(reminderExternalIdentifier)",
              type: .bullet
            )
          )
          skipMalformedInlineChildren(from: ast, cursor: &cursor, deeperThan: depth)
          continue
        }

        let childTree = loadTaskTree(
          from: childTask,
          tasksByExternalIdentifier: tasksByExternalIdentifier,
          taskFeatureSidecarsByReminderExternalIdentifier: taskFeatureSidecarsByReminderExternalIdentifier,
          ancestorTaskExternalIdentifiers: ancestorTaskExternalIdentifiers
        )
        nodes.append(childTree.root)
        reminderMetadataByNodeID.merge(
          childTree.reminderMetadataByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        featureSidecarByNodeID.merge(
          childTree.featureSidecarByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        skipMalformedInlineChildren(from: ast, cursor: &cursor, deeperThan: depth)
      }
    }

    return MaterializedNodes(
      nodes: nodes,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      featureSidecarByNodeID: featureSidecarByNodeID
    )
  }

  private static func skipMalformedInlineChildren(
    from ast: ReminderNoteAST,
    cursor: inout Int,
    deeperThan depth: Int
  ) {
    while cursor < ast.count, ast[cursor].depth > depth {
      cursor += 1
    }
  }
}

extension OutlineProjectionRuntimeSnapshot {
  static func fromSource(
    lists: [ReminderListImportSnapshot],
    itemsByListIdentifier: [String: [ReminderItemImportSnapshot]],
    workspaceStructureRecord: ReminderWorkspaceStructureRecord? = nil,
    projectConnectionsByReminderListExternalIdentifier:
      [String: ReminderProjectConnectionSidecarRecord] = [:],
    projectTaskOrdersByReminderListExternalIdentifier: [String: ReminderProjectTaskOrderRecord] = [:],
    projectRootStructuresByReminderListExternalIdentifier:
      [String: ReminderProjectRootStructureRecord] = [:],
    projectFeatureSidecarsByReminderListExternalIdentifier:
      [String: ReminderProjectFeatureSidecarRecord] = [:],
    taskFeatureSidecarsByReminderExternalIdentifier:
      [String: ReminderTaskFeatureSidecarRecord] = [:],
    taskSourceRuntimeStatesByReminderExternalIdentifier:
      [String: ReminderTaskSourceRuntimeState] = [:],
    mirrorPlacements: [TaskMirrorPlacementRecord] = []
  ) -> OutlineProjectionRuntimeSnapshot {
    let projectSnapshots = ReminderMetadataSnapshotEngine.projectSnapshots(
      lists: lists,
      itemsByListIdentifier: itemsByListIdentifier,
      workspaceStructureRecord: workspaceStructureRecord,
      projectConnectionsByReminderListExternalIdentifier:
        projectConnectionsByReminderListExternalIdentifier,
      projectTaskOrdersByReminderListExternalIdentifier: projectTaskOrdersByReminderListExternalIdentifier
    )
    let projectSnapshotsByReminderListExternalIdentifier = Dictionary(
      uniqueKeysWithValues: projectSnapshots.map {
        ($0.reminderListExternalIdentifier, $0)
      }
    )
    let globalTasksByExternalIdentifier = projectSnapshots.reduce(
      into: [String: ReminderMetadataSnapshotEngine.TaskSnapshot]()
    ) { partialResult, snapshot in
      for (reminderExternalIdentifier, task) in snapshot.tasksByExternalIdentifier {
        partialResult[reminderExternalIdentifier] = partialResult[reminderExternalIdentifier] ?? task
      }
    }
    let sourceProjectIDByReminderExternalIdentifier = projectSnapshots.reduce(
      into: [String: UUID]()
    ) { partialResult, snapshot in
      for reminderExternalIdentifier in snapshot.tasksByExternalIdentifier.keys {
        partialResult[reminderExternalIdentifier] = snapshot.projectID
      }
    }
    let mirrorRootsByReminderListExternalIdentifier = normalizedMirrorRoots(
      mirrorPlacements: mirrorPlacements,
      projectSnapshotsByReminderListExternalIdentifier:
        projectSnapshotsByReminderListExternalIdentifier,
      globalTasksByExternalIdentifier: globalTasksByExternalIdentifier,
      sourceProjectIDByReminderExternalIdentifier: sourceProjectIDByReminderExternalIdentifier
    )

    var projects: [OutlinerProject] = []
    var featureSidecarByReminderIdentifier: [String: OutlinerTaskSidecarMetadata] = [:]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata] = [:]
    var reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot] = [:]
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot] = [:]
    var projectReminderListIdentifierByProjectID: [UUID: String] = [:]
    var projectReminderListExternalIdentifierByProjectID: [UUID: String] = [:]
    var projectColorHexByProjectID: [UUID: String] = [:]
    var reminderModifiedAtByReminderExternalIdentifier: [String: Date] = [:]
    var projectRootStructureByReminderListExternalIdentifier:
      [String: ReminderProjectRootStructureRecord] = [:]
    var projectFeatureSidecarByProjectID: [UUID: ReminderProjectFeatureSidecarRecord] = [:]
    var projectFeatureSidecarByReminderListExternalIdentifier:
      [String: ReminderProjectFeatureSidecarRecord] = [:]
    var taskFeatureSidecarByReminderExternalIdentifier:
      [String: ReminderTaskFeatureSidecarRecord] = [:]
    var activeTaskRuntimeStatesByReminderExternalIdentifier:
      [String: ReminderTaskSourceRuntimeState] = [:]

    for projectSnapshot in projectSnapshots {
      let mirrorRoots = mirrorRootsByReminderListExternalIdentifier[
        projectSnapshot.reminderListExternalIdentifier
      ] ?? []
      projectReminderListIdentifierByProjectID[projectSnapshot.projectID] =
        projectSnapshot.reminderListIdentifier
      projectReminderListExternalIdentifierByProjectID[projectSnapshot.projectID] =
        projectSnapshot.reminderListExternalIdentifier
      if let colorHex = projectSnapshot.colorHex {
        projectColorHexByProjectID[projectSnapshot.projectID] = colorHex
      }

      let orderedRootEntries = orderedRootEntries(
        baseTasks: projectSnapshot.orderedTopLevelTasks,
        mirrorRoots: mirrorRoots
      )
      let rootStructureRecord = projectRootStructuresByReminderListExternalIdentifier[
        projectSnapshot.reminderListExternalIdentifier]
      if let rootStructureRecord {
        projectRootStructureByReminderListExternalIdentifier[
          projectSnapshot.reminderListExternalIdentifier
        ] = rootStructureRecord
      }
      let mirrorRootsByReminderExternalIdentifier = Dictionary(
        mirrorRoots.map { ($0.task.reminderExternalIdentifier, $0) },
        uniquingKeysWith: { lhs, _ in lhs }
      )
      var rootNodes: [OutlineNode] = []
      var consumedBaseReminderExternalIdentifiers: Set<String> = []
      var consumedMirrorReminderExternalIdentifiers: Set<String> = []

      if let rootStructureRecord {
        let materializedRootStructure = ReminderProjectRootStructureCodec.materialize(
          record: rootStructureRecord,
          projectSnapshot: projectSnapshot,
          globalTasksByExternalIdentifier: globalTasksByExternalIdentifier,
          mirrorRootsByReminderExternalIdentifier: mirrorRootsByReminderExternalIdentifier,
          taskFeatureSidecarsByReminderExternalIdentifier:
            taskFeatureSidecarsByReminderExternalIdentifier
        )
        rootNodes = materializedRootStructure.rootNodes
        featureSidecarByNodeID.merge(
          materializedRootStructure.featureSidecarByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        reminderMetadataByNodeID.merge(
          materializedRootStructure.reminderMetadataByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        consumedBaseReminderExternalIdentifiers =
          materializedRootStructure.consumedBaseReminderExternalIdentifiers
        consumedMirrorReminderExternalIdentifiers =
          materializedRootStructure.consumedMirrorReminderExternalIdentifiers
      }

      for entry in orderedRootEntries {
        switch entry {
        case .base(let task):
          guard consumedBaseReminderExternalIdentifiers.contains(task.reminderExternalIdentifier) == false
          else {
            continue
          }
          let taskTree = ReminderNoteSourceLoader.loadTaskTree(
            from: task,
            tasksByExternalIdentifier: projectSnapshot.tasksByExternalIdentifier,
            taskFeatureSidecarsByReminderExternalIdentifier:
              taskFeatureSidecarsByReminderExternalIdentifier
          )
          featureSidecarByNodeID.merge(
            taskTree.featureSidecarByNodeID,
            uniquingKeysWith: { _, rhs in rhs }
          )
          reminderMetadataByNodeID.merge(
            taskTree.reminderMetadataByNodeID,
            uniquingKeysWith: { _, rhs in rhs }
          )
          rootNodes.append(taskTree.root)

        case .mirror(let mirrorRoot):
          guard
            consumedMirrorReminderExternalIdentifiers.contains(
              mirrorRoot.task.reminderExternalIdentifier) == false
          else {
            continue
          }
          let taskTree = ReminderNoteSourceLoader.loadTaskTree(
            from: mirrorRoot.task,
            tasksByExternalIdentifier: globalTasksByExternalIdentifier,
            taskFeatureSidecarsByReminderExternalIdentifier:
              taskFeatureSidecarsByReminderExternalIdentifier
          )
          let mirroredTree = mirroredTaskTree(
            from: taskTree,
            placement: mirrorRoot.placement,
            sourceProjectID: mirrorRoot.sourceProjectID
          )
          featureSidecarByNodeID.merge(
            mirroredTree.featureSidecarByNodeID,
            uniquingKeysWith: { _, rhs in rhs }
          )
          reminderMetadataByNodeID.merge(
            mirroredTree.reminderMetadataByNodeID,
            uniquingKeysWith: { _, rhs in rhs }
          )
          rootNodes.append(mirroredTree.root)
        }
      }

      for task in projectSnapshot.tasksByExternalIdentifier.values {
        reminderMetadataByReminderIdentifier[task.reminderIdentifier] = task.reminderMetadata
        reminderModifiedAtByReminderExternalIdentifier[task.reminderExternalIdentifier] =
          task.modifiedAt
        if let featureSidecar = taskFeatureSidecarsByReminderExternalIdentifier[
          task.reminderExternalIdentifier]
        {
          featureSidecarByReminderIdentifier[task.reminderIdentifier] =
            featureSidecar.featureSidecarMetadata
          taskFeatureSidecarByReminderExternalIdentifier[task.reminderExternalIdentifier] =
            featureSidecar
        }
        if let runtimeState = taskSourceRuntimeStatesByReminderExternalIdentifier[
          task.reminderExternalIdentifier]
        {
          activeTaskRuntimeStatesByReminderExternalIdentifier[task.reminderExternalIdentifier] =
            runtimeState
        }
      }

      if let projectFeatureSidecar = projectFeatureSidecarsByReminderListExternalIdentifier[
        projectSnapshot.reminderListExternalIdentifier]
      {
        projectFeatureSidecarByProjectID[projectSnapshot.projectID] = projectFeatureSidecar
        projectFeatureSidecarByReminderListExternalIdentifier[
          projectSnapshot.reminderListExternalIdentifier] = projectFeatureSidecar
      }

      projects.append(
        OutlinerProject(
          id: projectSnapshot.projectID,
          title: projectSnapshot.title,
          document: OutlineDocument(rootNodes: rootNodes)
        )
      )
    }

    return OutlineProjectionRuntimeSnapshot(
      projects: projects,
      currentProjectID: projects.first?.id ?? ReminderProjectionIdentity.emptyProjectID(),
      featureSidecarByReminderIdentifier: featureSidecarByReminderIdentifier,
      featureSidecarByNodeID: featureSidecarByNodeID,
      reminderMetadataByReminderIdentifier: reminderMetadataByReminderIdentifier,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      projectReminderListIdentifierByProjectID: projectReminderListIdentifierByProjectID,
      projectReminderListExternalIdentifierByProjectID:
        projectReminderListExternalIdentifierByProjectID,
      projectColorHexByProjectID: projectColorHexByProjectID,
      reminderModifiedAtByReminderExternalIdentifier: reminderModifiedAtByReminderExternalIdentifier,
      workspaceStructureRecord: workspaceStructureRecord,
      projectTaskOrderByReminderListExternalIdentifier: projectTaskOrdersByReminderListExternalIdentifier,
      projectRootStructureByReminderListExternalIdentifier:
        projectRootStructureByReminderListExternalIdentifier,
      projectFeatureSidecarByProjectID: projectFeatureSidecarByProjectID,
      projectFeatureSidecarByReminderListExternalIdentifier:
        projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarByReminderExternalIdentifier:
        taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStateByReminderExternalIdentifier:
        activeTaskRuntimeStatesByReminderExternalIdentifier,
      projectionEngine: .combined
    )
  }

  private enum RootProjectionEntry {
    case base(ReminderMetadataSnapshotEngine.TaskSnapshot)
    case mirror(ReminderMetadataSnapshotEngine.MirrorRootSnapshot)

    var rowOrder: Int {
      switch self {
      case .base:
        return Int.max
      case .mirror(let root):
        return root.placement.rowOrder
      }
    }

    var createdAt: Date {
      switch self {
      case .base(let task):
        return task.createdAt
      case .mirror(let root):
        return root.placement.createdAt
      }
    }

    var tieBreaker: String {
      switch self {
      case .base(let task):
        return task.reminderExternalIdentifier
      case .mirror(let root):
        return root.task.reminderExternalIdentifier
      }
    }
  }

  private static func orderedRootEntries(
    baseTasks: [ReminderMetadataSnapshotEngine.TaskSnapshot],
    mirrorRoots: [ReminderMetadataSnapshotEngine.MirrorRootSnapshot]
  ) -> [RootProjectionEntry] {
    let baseEntries = baseTasks.enumerated().map { index, task in
      RootProjectionEntry.base(
        ReminderMetadataSnapshotEngine.TaskSnapshot(
          reminderIdentifier: task.reminderIdentifier,
          reminderExternalIdentifier: task.reminderExternalIdentifier,
          title: task.title,
          isCompleted: task.isCompleted,
          createdAt: task.createdAt,
          modifiedAt: task.modifiedAt,
          reminderMetadata: task.reminderMetadata,
          sourceDocument: task.sourceDocument
        )
      )
    }

    let mergedEntries = baseEntries + mirrorRoots.map { .mirror($0) }
    return mergedEntries.enumerated().sorted { lhs, rhs in
      let lhsEntry = lhs.element
      let rhsEntry = rhs.element
      let lhsRowOrder = lhsEntry.rowOrder == Int.max ? lhs.offset : lhsEntry.rowOrder
      let rhsRowOrder = rhsEntry.rowOrder == Int.max ? rhs.offset : rhsEntry.rowOrder
      if lhsRowOrder != rhsRowOrder {
        return lhsRowOrder < rhsRowOrder
      }
      if lhsEntry.createdAt != rhsEntry.createdAt {
        return lhsEntry.createdAt < rhsEntry.createdAt
      }
      return lhsEntry.tieBreaker < rhsEntry.tieBreaker
    }.map(\.element)
  }

  private static func normalizedMirrorRoots(
    mirrorPlacements: [TaskMirrorPlacementRecord],
    projectSnapshotsByReminderListExternalIdentifier:
      [String: ReminderMetadataSnapshotEngine.ProjectSnapshot],
    globalTasksByExternalIdentifier: [String: ReminderMetadataSnapshotEngine.TaskSnapshot],
    sourceProjectIDByReminderExternalIdentifier: [String: UUID]
  ) -> [String: [ReminderMetadataSnapshotEngine.MirrorRootSnapshot]] {
    var selectedRootsByTargetListExternalIdentifier:
      [String: [ReminderMetadataSnapshotEngine.MirrorRootSnapshot]] = [:]
    let orderedPlacements = mirrorPlacements.sorted { lhs, rhs in
      if lhs.targetReminderListExternalIdentifier != rhs.targetReminderListExternalIdentifier {
        return lhs.targetReminderListExternalIdentifier < rhs.targetReminderListExternalIdentifier
      }
      if lhs.rowOrder != rhs.rowOrder {
        return lhs.rowOrder < rhs.rowOrder
      }
      if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
      }
      return lhs.reminderExternalIdentifier < rhs.reminderExternalIdentifier
    }

    for placement in orderedPlacements {
      guard
        let targetProjectSnapshot = projectSnapshotsByReminderListExternalIdentifier[
          placement.targetReminderListExternalIdentifier
        ],
        let task = globalTasksByExternalIdentifier[placement.reminderExternalIdentifier]
      else {
        continue
      }

      if targetProjectSnapshot.tasksByExternalIdentifier[placement.reminderExternalIdentifier] != nil {
        continue
      }

      let existingRoots =
        selectedRootsByTargetListExternalIdentifier[placement.targetReminderListExternalIdentifier]
        ?? []
      if existingRoots.contains(where: {
        $0.task.reminderExternalIdentifier == placement.reminderExternalIdentifier
      }) {
        continue
      }
      if existingRoots.contains(where: {
        taskIsDescendant(
          placement.reminderExternalIdentifier,
          of: $0.task.reminderExternalIdentifier,
          globalTasksByExternalIdentifier: globalTasksByExternalIdentifier
        )
      }) {
        continue
      }

      selectedRootsByTargetListExternalIdentifier[
        placement.targetReminderListExternalIdentifier,
        default: []
      ].append(
        ReminderMetadataSnapshotEngine.MirrorRootSnapshot(
          placement: placement,
          task: task,
          sourceProjectID: sourceProjectIDByReminderExternalIdentifier[
            placement.reminderExternalIdentifier]
        )
      )
    }

    return selectedRootsByTargetListExternalIdentifier
  }

  private static func taskIsDescendant(
    _ reminderExternalIdentifier: String,
    of ancestorReminderExternalIdentifier: String,
    globalTasksByExternalIdentifier: [String: ReminderMetadataSnapshotEngine.TaskSnapshot]
  ) -> Bool {
    guard reminderExternalIdentifier != ancestorReminderExternalIdentifier,
      let ancestorTask = globalTasksByExternalIdentifier[ancestorReminderExternalIdentifier]
    else {
      return false
    }

    var stack = ancestorTask.sourceDocument.ast.compactMap { node -> String? in
      guard case let .childAnchor(reminderExternalIdentifier, _) = node else { return nil }
      return reminderExternalIdentifier
    }
    var visited: Set<String> = []

    while let nextReminderExternalIdentifier = stack.popLast() {
      guard visited.insert(nextReminderExternalIdentifier).inserted else { continue }
      if nextReminderExternalIdentifier == reminderExternalIdentifier {
        return true
      }
      if let task = globalTasksByExternalIdentifier[nextReminderExternalIdentifier] {
        stack.append(
          contentsOf: task.sourceDocument.ast.compactMap { node -> String? in
            guard case let .childAnchor(reminderExternalIdentifier, _) = node else { return nil }
            return reminderExternalIdentifier
          }
        )
      }
    }

    return false
  }

  static func mirroredTaskTree(
    from tree: ReminderNoteSourceLoader.LoadedTaskTree,
    placement: TaskMirrorPlacementRecord,
    sourceProjectID: UUID?
  ) -> ReminderNoteSourceLoader.LoadedTaskTree {
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot] = [:]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata] = [:]

    func clone(node: OutlineNode, path: [Int]) -> OutlineNode {
      let nextMirroredNodeID = mirroredNodeID(
        placementID: placement.id,
        canonicalID: node.canonicalID,
        path: path
      )
      let mirroredChildren = node.children.enumerated().map { index, child in
        clone(node: child, path: path + [index])
      }
      if let metadata = tree.reminderMetadataByNodeID[node.id] {
        reminderMetadataByNodeID[nextMirroredNodeID] = metadata
      }
      if let featureSidecar = tree.featureSidecarByNodeID[node.id] {
        featureSidecarByNodeID[nextMirroredNodeID] = featureSidecar
      }
      return OutlineNode(
        id: nextMirroredNodeID,
        canonicalID: node.canonicalID,
        text: node.text,
        type: node.type,
        referenceProjectID: sourceProjectID,
        children: mirroredChildren,
        isCollapsed: node.isCollapsed,
        migratedTaskItemID: node.migratedTaskItemID,
        reminderIdentifier: node.reminderIdentifier,
        reminderExternalIdentifier: node.reminderExternalIdentifier,
        attachments: node.attachments
      )
    }

    let root = clone(node: tree.root, path: [])
    return ReminderNoteSourceLoader.LoadedTaskTree(
      root: root,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      featureSidecarByNodeID: featureSidecarByNodeID
    )
  }

  private static func mirroredNodeID(
    placementID: UUID,
    canonicalID: UUID,
    path: [Int]
  ) -> UUID {
    let digest = SHA256.hash(
      data: Data(
        "mirror-node|\(placementID.uuidString)|\(canonicalID.uuidString)|\(path.map(String.init).joined(separator: "."))"
          .utf8
      )
    )
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}
