import Combine
import Foundation
import SwiftData

/// Phase 13 cleanup boundary freeze:
/// Keep `ProjectDocumentStore` as the app steady-state command dispatcher/facade that
/// composes EventKit, sidecar storage, retained runtime sqlite, attachment, and history services.
/// Phase 2 removes the old integrated persistence surface so the app target no longer
/// carries `.persistDocument`, canonical full `load/loadAll/save`, or the integrated adapter.
enum ProjectTaskNoteField: Sendable {
  case reminderNote
}

enum ProjectAttachmentMutation: Sendable {
  case importFiles(urls: [URL], owner: AttachmentOwner)
  case delete(attachmentID: UUID)
  case move(attachmentID: UUID, owner: AttachmentOwner)
}

extension AttachmentOwner {
  init(ownerType: AttachmentOwnerType, ownerID: UUID) {
    switch ownerType {
    case .project:
      self = .project(ownerID)
    case .task:
      self = .task(ownerID)
    }
  }
}

enum ProjectMutationCommand {
  case setTitle(String)
  case updateProjectNote(String)
  case setProjectColor(String?)
  case setProjectStage(ProjectProgressStage)
  case updateTaskText(taskID: UUID, title: String)
  case patchTaskTitle(contentID: UUID, newText: String)
  case patchBulletText(contentID: UUID, newText: String)
  case updateTaskNote(taskID: UUID, field: ProjectTaskNoteField, value: String)
  case setTaskSchedule(taskID: UUID, day: Date?, timeMinutes: Int?, durationMinutes: Int?)
  case setTaskPresentation(
    taskID: UUID,
    boardStage: BoardStage,
    importance: ImportanceLevel,
    priority: Int,
    isFlagged: Bool
  )
  case setTaskPreparationSchedule(
    taskID: UUID,
    targetCompletedUnits: Int,
    isAllDay: Bool,
    timeMinutes: Int,
    durationMinutes: Int
  )
  case setTaskCompletion(taskID: UUID, isCompleted: Bool, completionDate: Date?)
  case completeRecurringTask(taskID: UUID, occurrenceDate: Date)
  case setPlannedWorkProgress(taskID: UUID, targetCompletedUnits: Int, completedOn: Date)
  case createTask(
    title: String,
    parentTaskID: UUID?,
    rootBulletID: UUID?,
    insertionSlot: Int?,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?
  )
  case addTask(
    title: String,
    parentTaskID: UUID?,
    rootBulletID: UUID?,
    insertionSlot: Int?,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?
  )
  case deleteTask(UUID)
  case moveTask(taskIDs: [UUID], targetProjectID: UUID)
  case moveTaskSequence(taskIDs: [UUID], targetProjectID: UUID)
  case reorderTask(taskIDs: [UUID])
  case setVisibleRootTaskOrder(taskIDs: [UUID])
  case setProjectRootStructure(rootNodes: [ReminderProjectRootNodeRecord])
  case restoreProject
  case setTaskReminderMetadata(
    taskID: UUID,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?,
    modifiedAt: Date?,
    reminderCalendarIdentifier: String?
  )
  case applyAttachmentMutation(ProjectAttachmentMutation)
  case archiveProject
  case deleteProject
}

struct ProjectMutationResult {
  var taskStatesByContentID: [UUID: OutlinerIntegratedTaskState] = [:]
  var didMutateWorkspaceTree: Bool = false
  var deletedWorkspaceNodeIDs: Set<UUID> = []
  var createdTaskID: UUID?
  var indexRefreshPlan: ProjectReadModelRefreshPlan = .none

  static let none = ProjectMutationResult()
}

struct ProjectChangeEvent {
  let projectID: UUID
  let command: ProjectMutationCommand
  let result: ProjectMutationResult
}

struct ProjectTaskScheduleMutationSnapshot: Equatable {
  var isCompleted: Bool
  var completionDate: Date?
  var startDate: Date?
  var dueDate: Date?
  var scheduleHasExplicitTime: Bool
  var scheduledDurationMinutes: Int?
}

enum ProjectReadModelRefreshPlan: Equatable {
  case none
  case incremental(Set<UUID>)
  case full
}

extension ProjectReadModelRefreshPlan {
  var isNone: Bool {
    if case .none = self {
      return true
    }
    return false
  }

  func merged(with other: ProjectReadModelRefreshPlan) -> ProjectReadModelRefreshPlan {
    switch (self, other) {
    case (.full, _), (_, .full):
      return .full
    case let (.incremental(lhs), .incremental(rhs)):
      return .incremental(lhs.union(rhs))
    case (.none, let plan), (let plan, .none):
      return plan
    }
  }
}

struct ProjectPersistResult {
  var taskStatesByContentID: [UUID: OutlinerIntegratedTaskState]
  var indexRefreshPlan: ProjectReadModelRefreshPlan = .none
}

private struct ProjectReadModelTaskFingerprint: Equatable {
  let title: String
  let isCompleted: Bool
  let parentTaskID: UUID?
  let rowOrder: Int
  let dueDate: Date?
  let hasExplicitTime: Bool
  let scheduledDurationMinutes: Int?
  let recurrenceRuleRaw: String?
  let priority: Int
  let reminderNoteText: String
  let attachmentCount: Int
  let requiredWorkDays: Int
  let isFlagged: Bool
}

enum ProjectReadModelRefreshPlanner {
  static func plan(
    previousProject: OutlinerProject?,
    previousTaskStatesByContentID: [UUID: OutlinerIntegratedTaskState],
    currentProject: OutlinerProject,
    currentTaskStatesByContentID: [UUID: OutlinerIntegratedTaskState]
  ) -> ProjectReadModelRefreshPlan {
    guard let previousProject else { return .full }

    let previousFingerprints = taskFingerprints(
      in: previousProject,
      taskStatesByContentID: previousTaskStatesByContentID
    )
    let currentFingerprints = taskFingerprints(
      in: currentProject,
      taskStatesByContentID: currentTaskStatesByContentID
    )

    let previousTaskIDs = Set(previousFingerprints.keys)
    let currentTaskIDs = Set(currentFingerprints.keys)
    guard previousTaskIDs == currentTaskIDs else { return .full }

    var changedTaskIDs: Set<UUID> = []
    for taskID in currentTaskIDs {
      guard let previous = previousFingerprints[taskID],
            let current = currentFingerprints[taskID]
      else {
        return .full
      }

      if previous.parentTaskID != current.parentTaskID || previous.rowOrder != current.rowOrder {
        return .full
      }
      if previous != current {
        changedTaskIDs.insert(taskID)
      }
    }

    return changedTaskIDs.isEmpty ? .none : .incremental(changedTaskIDs)
  }

  private static func taskFingerprints(
    in project: OutlinerProject,
    taskStatesByContentID: [UUID: OutlinerIntegratedTaskState]
  ) -> [UUID: ProjectReadModelTaskFingerprint] {
    var fingerprints: [UUID: ProjectReadModelTaskFingerprint] = [:]
    var rowOrder = 0

    func visit(nodes: [OutlineNode], parentTaskID: UUID?) {
      for node in nodes {
        let nextParentTaskID = node.type.isTask ? node.canonicalID : parentTaskID
        if node.type.isTask {
          let taskState =
            taskStatesByContentID[node.canonicalID]
            ?? OutlinerIntegratedTaskState(
              content: TaskContent(id: node.canonicalID, title: node.text)
            )
          fingerprints[node.canonicalID] = ProjectReadModelTaskFingerprint(
            title: node.text,
            isCompleted: node.type.isCompleted,
            parentTaskID: parentTaskID,
            rowOrder: rowOrder,
            dueDate: taskState.reminderMetadata.dueDate,
            hasExplicitTime: taskState.reminderMetadata.hasExplicitTime,
            scheduledDurationMinutes: taskState.featureSidecar.scheduledDurationMinutes,
            recurrenceRuleRaw: OutlinerIntegratedStore.encodeRecurrence(taskState.reminderMetadata.recurrence),
            priority: taskState.reminderMetadata.priority,
            reminderNoteText: taskState.reminderNoteText,
            attachmentCount: max(taskState.attachmentCount, taskState.featureSidecar.attachmentPreviews.count),
            requiredWorkDays: taskState.featureSidecar.requiredWorkDays,
            isFlagged: taskState.isFlagged
          )
          rowOrder += 1
        }
        visit(nodes: node.children, parentTaskID: nextParentTaskID)
      }
    }

    visit(nodes: project.document.rootNodes, parentTaskID: nil)
    return fingerprints
  }
}

enum ProjectDocumentStoreError: LocalizedError {
  case modelContainerUnavailable
  case canonicalTaskContentMissing(UUID)
  case canonicalProjectMissing(UUID)
  case projectRootBulletMissing(UUID)
  case taskRestoreFailed(UUID)
  case taskDeleteCleanupFailed(UUID)
  case commandRequiresAsync(ProjectMutationCommand)
  case sidecarOwnerCommandUnavailable(AppOwnerField)
  case appStateCommandUnavailable

  var errorDescription: String? {
    switch self {
    case .modelContainerUnavailable:
      return "프로젝트 문서 저장소를 열 수 없습니다."
    case let .canonicalProjectMissing(projectID):
      return "프로젝트를 찾지 못했습니다. (\(projectID.uuidString))"
    case let .canonicalTaskContentMissing(taskID):
      return "할일을 찾지 못했습니다. (\(taskID.uuidString))"
    case let .projectRootBulletMissing(rootBulletID):
      return "프로젝트 루트 bullet을 찾지 못했습니다. (\(rootBulletID.uuidString))"
    case let .taskRestoreFailed(taskID):
      return "삭제된 할일을 복원하지 못했습니다. (\(taskID.uuidString))"
    case let .taskDeleteCleanupFailed(taskID):
      return "삭제된 할일의 Sidecar 정리를 완료하지 못했습니다. (\(taskID.uuidString))"
    case .commandRequiresAsync:
      return "이 명령은 비동기 경로가 필요합니다."
    case let .sidecarOwnerCommandUnavailable(field):
      return "Sidecar owner command를 찾지 못했습니다. (\(field.rawValue))"
    case .appStateCommandUnavailable:
      return "AppState command dispatcher를 찾지 못했습니다."
    }
  }
}

extension ProjectDocumentStore {
  nonisolated static func saveWithSyncPerformanceCounter(_ context: ModelContext) throws {
    SyncPerformanceCounter.recordContextSave()
    try context.save()
  }
}

@MainActor
final class ProjectDocumentStore: ObservableObject {
  let projectID: UUID
  let projectChanged = PassthroughSubject<ProjectChangeEvent, Never>()

  private let contextFactory: @MainActor () -> ModelContext
  private let reminderProjectProvider: ReminderProjectProvider?
  private let projectionSidecarStore: ReminderProjectionSidecarStore?
  private let mirrorPlacementStore: TaskMirrorPlacementStore?
  private let attachmentStore: AttachmentStore?
  private let workspaceTreeRepository: WorkspaceTreeRepository?
  private let indexUpdateQueue: ProjectIndexUpdateQueue?
  private let runtimeSnapshotProvider: (() -> OutlineProjectionRuntimeSnapshot?)?
  private let sidecarOwnerFieldWriter: (@MainActor (AppOwnerFieldWrite) async -> Bool)?
  private let appStateCommandSender: (@MainActor (AppCommand, Bool) async -> Bool)?

  init(
    projectID: UUID,
    modelContainer: ModelContainer,
    reminderProjectProvider: ReminderProjectProvider? = nil,
    projectionSidecarStore: ReminderProjectionSidecarStore? = nil,
    mirrorPlacementStore: TaskMirrorPlacementStore? = nil,
    attachmentStore: AttachmentStore? = nil,
    workspaceTreeRepository: WorkspaceTreeRepository? = nil,
    indexUpdateQueue: ProjectIndexUpdateQueue? = nil,
    runtimeSnapshotProvider: (() -> OutlineProjectionRuntimeSnapshot?)? = nil,
    sidecarOwnerFieldWriter: (@MainActor (AppOwnerFieldWrite) async -> Bool)? = nil,
    appStateCommandSender: (@MainActor (AppCommand, Bool) async -> Bool)? = nil
  ) {
    self.projectID = projectID
    self.contextFactory = { ModelContext(modelContainer) }
    self.reminderProjectProvider = reminderProjectProvider
    self.projectionSidecarStore = projectionSidecarStore
    self.mirrorPlacementStore = mirrorPlacementStore
    self.attachmentStore = attachmentStore
    self.workspaceTreeRepository = workspaceTreeRepository
    self.indexUpdateQueue = indexUpdateQueue
    self.runtimeSnapshotProvider = runtimeSnapshotProvider
    self.sidecarOwnerFieldWriter = sidecarOwnerFieldWriter
    self.appStateCommandSender = appStateCommandSender
  }

  private func currentContext() -> ModelContext {
    contextFactory()
  }

  private func saveIfNotBatching(_ context: ModelContext) throws {
    try Self.saveWithSyncPerformanceCounter(context)
  }

  private func recordMutationIfBatching(_ context: ModelContext) {
    _ = context
  }

  private func enqueueIndexRefresh(_ plan: ProjectReadModelRefreshPlan) {
    guard !plan.isNone else { return }
    guard OutlinerEditingGranularityFlags.useDeferredIndexing else { return }
    indexUpdateQueue?.enqueue(plan, for: projectID)
  }

  private func refreshIndexesSynchronously(
    _ plan: ProjectReadModelRefreshPlan,
    using context: ModelContext
  ) throws {
    guard !plan.isNone else { return }

    switch plan {
    case .none:
      return
    case .full:
      try Self.refreshProjectReadModels(for: projectID, context: context)
    case let .incremental(taskIDs):
      try Self.refreshProjectReadModelsIncrementally(
        for: projectID,
        changedTaskIDs: taskIDs,
        context: context
      )
    }
  }

  private func scheduleIndexRefresh(
    _ plan: ProjectReadModelRefreshPlan,
    using context: ModelContext
  ) throws {
    guard !plan.isNone else { return }

    if OutlinerEditingGranularityFlags.useDeferredIndexing {
      enqueueIndexRefresh(plan)
    } else {
      try refreshIndexesSynchronously(plan, using: context)
      try Self.saveWithSyncPerformanceCounter(context)
    }
  }

  private func emitChangeEvent(
    command: ProjectMutationCommand,
    result: ProjectMutationResult
  ) {
    projectChanged.send(
      ProjectChangeEvent(
        projectID: projectID,
        command: command,
        result: result
      )
    )
  }

  func loadProject() throws -> OutlinerIntegratedStore.Snapshot? {
    guard let runtimeSnapshot = runtimeSnapshotProvider?() else {
      return nil
    }
    return runtimeSnapshotSnapshot(from: runtimeSnapshot)
  }

  func loadRuntimeProjectionSnapshot(
    for projectIDs: Set<UUID>
  ) async throws -> OutlineProjectionRuntimeSnapshot? {
    guard !projectIDs.isEmpty,
      let reminderProjectProvider,
      let runtimeSnapshot = runtimeSnapshotProvider?()
    else {
      return nil
    }

    let requestedReminderListExternalIdentifiers = Set(
      projectIDs.compactMap {
        Self.normalized(runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[$0])
      }
    )
    let mirrorPlacements = try await mirrorPlacementStore?.allRecords() ?? []
    var reminderListIdentifiers = projectIDs.compactMap { projectID in
      Self.normalized(runtimeSnapshot.projectReminderListIdentifierByProjectID[projectID])
        ?? Self.normalized(
          runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[projectID]
        )
    }

    if !requestedReminderListExternalIdentifiers.isEmpty {
      for placement in mirrorPlacements
      where requestedReminderListExternalIdentifiers.contains(
        placement.targetReminderListExternalIdentifier
      ) {
        guard let sourceProject = runtimeSnapshot.projects.first(where: { project in
          project.document.flatten().contains { entry in
            entry.node.type.isTask
              && entry.node.referenceProjectID == nil
              && Self.normalized(entry.node.reminderExternalIdentifier)
                == placement.reminderExternalIdentifier
          }
        }) else {
          continue
        }
        if let sourceReminderListIdentifier =
          Self.normalized(runtimeSnapshot.projectReminderListIdentifierByProjectID[sourceProject.id])
            ?? Self.normalized(
              runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[sourceProject.id]
            )
        {
          reminderListIdentifiers.append(sourceReminderListIdentifier)
        }
      }
    }

    reminderListIdentifiers = Array(
      NSOrderedSet(array: reminderListIdentifiers)
    ) as? [String] ?? []
    guard !reminderListIdentifiers.isEmpty,
      let batch = try await reminderProjectProvider.fetchImportSnapshotBatch(
        forListIdentifiers: reminderListIdentifiers
      ),
      !batch.lists.isEmpty
    else {
      return nil
    }

    let projectConnectionsByReminderListExternalIdentifier: [String: ReminderProjectConnectionSidecarRecord] =
      Dictionary(
      uniqueKeysWithValues: runtimeSnapshot.projectReminderListExternalIdentifierByProjectID.compactMap {
        projectID,
        reminderListExternalIdentifier in
        guard
          let normalizedReminderListExternalIdentifier = Self.normalized(
            reminderListExternalIdentifier
          )
        else {
          return nil
        }
        return (
          normalizedReminderListExternalIdentifier,
          ReminderProjectConnectionSidecarRecord.record(
            projectID: projectID,
            reminderListIdentifier: runtimeSnapshot.projectReminderListIdentifierByProjectID[projectID],
            reminderListExternalIdentifier: normalizedReminderListExternalIdentifier,
            existing: nil
          )
        )
      }
      )

    return OutlineProjectionRuntimeSnapshot.fromSource(
      lists: batch.lists,
      itemsByListIdentifier: batch.itemsByListIdentifier,
      workspaceStructureRecord: runtimeSnapshot.workspaceStructureRecord,
      projectConnectionsByReminderListExternalIdentifier:
        projectConnectionsByReminderListExternalIdentifier,
      projectTaskOrdersByReminderListExternalIdentifier:
        runtimeSnapshot.projectTaskOrderByReminderListExternalIdentifier,
      projectRootStructuresByReminderListExternalIdentifier:
        runtimeSnapshot.projectRootStructureByReminderListExternalIdentifier,
      projectFeatureSidecarsByReminderListExternalIdentifier:
        runtimeSnapshot.projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarsByReminderExternalIdentifier:
        runtimeSnapshot.taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStatesByReminderExternalIdentifier: [:],
      mirrorPlacements: mirrorPlacements
    )
  }

  private func runtimeSnapshotSnapshot(
    from runtimeSnapshot: OutlineProjectionRuntimeSnapshot
  ) -> OutlinerIntegratedStore.Snapshot? {
    guard let project = runtimeSnapshot.projects.first(where: { $0.id == projectID }) else {
      return nil
    }

    let treeIndex = OutlineTreeIndex(document: project.document)
    var taskStatesByContentID: [UUID: OutlinerIntegratedTaskState] = [:]

    for entry in project.document.flatten() where entry.node.type.isTask {
      let reminderIdentifier = Self.normalized(entry.node.reminderIdentifier)
      let reminderExternalIdentifier = Self.normalized(entry.node.reminderExternalIdentifier)
      let reminderMetadata =
        reminderIdentifier.flatMap { runtimeSnapshot.reminderMetadataByReminderIdentifier[$0] }
        ?? runtimeSnapshot.reminderMetadataByNodeID[entry.node.id]
        ?? ReminderMetadataSnapshot()
      let taskFeatureRecord = reminderExternalIdentifier.flatMap {
        runtimeSnapshot.taskFeatureSidecarByReminderExternalIdentifier[$0]
      }
      let taskFeatureMetadata =
        taskFeatureRecord?.featureSidecarMetadata
        ?? runtimeSnapshot.featureSidecarByNodeID[entry.node.id]
        ?? OutlinerTaskSidecarMetadata()
      let reminderNoteText = ReminderNoteSourceMutationService.plan(
        for: entry.node,
        reminderExternalIdentifierResolver: { node in
          Self.normalized(node.reminderExternalIdentifier)
        }
      )
      .document
      .normalizedText
      let modifiedAt = reminderExternalIdentifier.flatMap {
        runtimeSnapshot.reminderModifiedAtByReminderExternalIdentifier[$0]
      }
      let parentTaskRemoteExternalIdentifier = treeIndex.parentOf(id: entry.node.id)
        .flatMap { treeIndex.findNode(id: $0) }
        .flatMap { parentNode in
          parentNode.type.isTask ? Self.normalized(parentNode.reminderExternalIdentifier) : nil
        }

      let content = TaskContent(
        id: entry.node.canonicalID,
        title: entry.node.text,
        reminderIdentifier: reminderIdentifier,
        reminderExternalIdentifier: reminderExternalIdentifier,
        reminderOwnerProjectID: projectID,
        reminderOwnerCalendarID: Self.normalized(
          runtimeSnapshot.projectReminderListIdentifierByProjectID[projectID]
        ),
        parentTaskRemoteExternalIdentifier: parentTaskRemoteExternalIdentifier,
        isCompleted: entry.node.type.isCompleted,
        dueDate: reminderMetadata.dueDate,
        scheduleHasExplicitTime: reminderMetadata.hasExplicitTime,
        scheduledDurationMinutes: taskFeatureRecord?.scheduledDurationMinutes,
        priority: reminderMetadata.priority,
        isFlagged: taskFeatureRecord?.isFlagged ?? false,
        boardStageRaw: taskFeatureRecord?.boardStageRaw,
        importanceRaw: taskFeatureRecord?.importanceRaw,
        reminderNoteText: reminderNoteText,
        attachmentCount: 0,
        lastSyncedReminderTitle: entry.node.text,
        lastSyncedReminderNoteBody: reminderNoteText,
        lastSyncedReminderModifiedAt: modifiedAt,
        requiredWorkDays: taskFeatureRecord?.requiredWorkDays ?? taskFeatureMetadata.requiredWorkDays,
        completedWorkUnits: taskFeatureRecord?.completedWorkUnits ?? 0,
        completedWorkUnitDatesRaw: taskFeatureRecord?.completedWorkUnitDatesRaw ?? "",
        preparationScheduleOverridesRaw: taskFeatureRecord?.preparationScheduleOverridesRaw ?? "",
        isDirty: false,
        remoteLastModifiedAt: modifiedAt,
        localUpdatedAt: taskFeatureRecord?.updatedAt ?? modifiedAt ?? .now,
        createdAt: taskFeatureRecord?.createdAt ?? modifiedAt ?? .now
      )
      taskStatesByContentID[entry.node.canonicalID] = OutlinerIntegratedTaskState(content: content)
    }

    return OutlinerIntegratedStore.Snapshot(
      projects: [project],
      taskStatesByContentID: taskStatesByContentID
    )
  }

  func deleteTaskWithUndoSnapshot(taskID: UUID) async throws -> TaskDeletionUndoSnapshot? {
    let context = currentContext()
    guard let snapshot = try captureTaskDeletionUndoSnapshot(taskID: taskID, context: context) else {
      return nil
    }
    do {
      try await deleteTaskPermanently(taskID: taskID)
    } catch {
      try restoreDeletedAttachments(in: snapshot.root, context: context)
      throw error
    }
    return snapshot
  }

  func restoreDeletedTaskFromUndoSnapshot(_ snapshot: TaskDeletionUndoSnapshot) async throws {
    guard snapshot.projectID == projectID else { return }
    let context = currentContext()
    if runtimeTaskDeletionContext(for: snapshot.task.id) != nil
      || TaskIdentityBridgeStore.record(for: snapshot.task.id) != nil
    {
      return
    }

    switch snapshot.placement {
    case let .taskParent(parentTaskID, insertionSlot):
      try await restoreDeletedTaskNode(
        snapshot.root,
        parentTaskID: parentTaskID,
        rootBulletID: nil,
        insertionSlot: insertionSlot,
        context: context
      )

    case let .projectRoot(rootBulletID, insertionSlot):
      try await restoreDeletedTaskNode(
        snapshot.root,
        parentTaskID: nil,
        rootBulletID: rootBulletID,
        insertionSlot: insertionSlot,
        context: context
      )
    }

    SequentialTaskService.persistAssignments(snapshot.sequenceAssignments, for: projectID)
    SequentialTaskService.postAssignmentsDidChange(projectIDs: [projectID])
  }

  @discardableResult
  func applyImmediateCommand(
    _ command: ProjectMutationCommand,
    shouldEmitChangeEvent: Bool = true
  ) throws -> ProjectMutationResult {
    let result: ProjectMutationResult
    switch command {
    case let .setProjectColor(colorHex):
      try writeProjectColorViaOwnerCommand(colorHex)
      result = .none

    case .setProjectStage:
      throw ProjectDocumentStoreError.commandRequiresAsync(command)

    case let .updateTaskText(taskID, title):
      try writeTaskTitleViaOwnerCommand(taskID: taskID, rawTitle: title)
      result = .none

    case let .patchTaskTitle(contentID, newText),
      let .patchBulletText(contentID, newText):
      result = ProjectMutationResult(
        indexRefreshPlan: try persistPatchedNodeText(contentID: contentID, newText: newText)
      )

    case let .updateTaskNote(taskID, field, value):
      try writeTaskNoteViaOwnerCommand(taskID: taskID, field: field, rawValue: value)
      result = .none

    case let .setTaskSchedule(taskID, day, timeMinutes, durationMinutes):
      throw ProjectDocumentStoreError.commandRequiresAsync(command)

    case let .setTaskPresentation(taskID, boardStage, importance, priority, isFlagged):
      throw ProjectDocumentStoreError.commandRequiresAsync(command)

    case let .setTaskPreparationSchedule(
      taskID,
      targetCompletedUnits,
      isAllDay,
      timeMinutes,
      durationMinutes
    ):
      try persistTaskPreparationSchedule(
        taskID: taskID,
        targetCompletedUnits: targetCompletedUnits,
        isAllDay: isAllDay,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
      result = .none

    case let .setTaskCompletion(taskID, isCompleted, completionDate):
      try writeTaskCompletionViaOwnerCommand(
        taskID: taskID,
        isCompleted: isCompleted,
        completionDate: completionDate
      )
      result = .none

    case let .completeRecurringTask(taskID, occurrenceDate):
      try writeRecurringTaskCompletionViaOwnerCommand(
        taskID: taskID,
        occurrenceDate: occurrenceDate
      )
      result = .none

    case let .setPlannedWorkProgress(taskID, targetCompletedUnits, completedOn):
      try persistPlannedWorkProgress(
        taskID: taskID,
        targetCompletedUnits: targetCompletedUnits,
        completedOn: completedOn
      )
      result = .none

    case .createTask, .addTask:
      throw ProjectDocumentStoreError.commandRequiresAsync(command)

    case .moveTask,
      .moveTaskSequence:
      throw ProjectDocumentStoreError.commandRequiresAsync(command)

    case let .reorderTask(taskIDs),
      let .setVisibleRootTaskOrder(taskIDs):
      try persistVisibleRootTaskOrderDirectly(taskIDs: taskIDs)
      result = .none

    case let .setProjectRootStructure(rootNodes):
      _ = try persistProjectRootStructureDirectly(rootNodes, context: currentContext())
      result = .none

    case let .setTaskReminderMetadata(
      taskID,
      reminderIdentifier,
      reminderExternalIdentifier,
      modifiedAt,
      reminderCalendarIdentifier
    ):
      try persistTaskReminderMetadata(
        taskID: taskID,
        reminderIdentifier: reminderIdentifier,
        reminderExternalIdentifier: reminderExternalIdentifier,
        modifiedAt: modifiedAt,
        reminderCalendarIdentifier: reminderCalendarIdentifier
      )
      result = .none

    case let .applyAttachmentMutation(mutation):
      try applyAttachmentMutation(mutation)
      result = .none

    case .archiveProject:
      try archiveProject()
      result = .none

    case .restoreProject:
      try restoreProject()
      result = .none

    case .setTitle,
      .updateProjectNote,
      .deleteTask,
      .deleteProject:
      throw ProjectDocumentStoreError.commandRequiresAsync(command)
    }

    if shouldEmitChangeEvent {
      emitChangeEvent(command: command, result: result)
    }
    return result
  }

  @discardableResult
  func applyCommand(_ command: ProjectMutationCommand) async throws -> ProjectMutationResult {
    let result: ProjectMutationResult
    var shouldEmitChangeEvent = true
    switch command {
    case let .setTitle(rawTitle):
      let didMutateWorkspaceTree = try await persistProjectTitle(rawTitle)
      result = ProjectMutationResult(didMutateWorkspaceTree: didMutateWorkspaceTree)

    case let .updateProjectNote(note):
      try await persistProjectNote(note)
      shouldEmitChangeEvent = false
      result = .none

    case let .setProjectStage(stage):
      try await persistProjectStage(stage)
      shouldEmitChangeEvent = false
      result = .none

    case let .deleteTask(taskID):
      try await deleteTaskPermanently(taskID: taskID)
      result = .none

    case let .moveTask(taskIDs, targetProjectID),
      let .moveTaskSequence(taskIDs, targetProjectID):
      try await moveTaskSequence(taskIDs: taskIDs, targetProjectID: targetProjectID)
      result = .none

    case let .createTask(title, parentTaskID, rootBulletID, insertionSlot, day, timeMinutes, durationMinutes),
      let .addTask(title, parentTaskID, rootBulletID, insertionSlot, day, timeMinutes, durationMinutes):
      result = ProjectMutationResult(
        createdTaskID: try await createTaskViaOwnerTreeWrite(
          title: title,
          parentTaskID: parentTaskID,
          rootBulletID: rootBulletID,
          insertionSlot: insertionSlot,
          day: day,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes
        )
      )

    case let .setTaskSchedule(taskID, day, timeMinutes, durationMinutes):
      try await persistTaskSchedule(
        taskID: taskID,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
      result = .none

    case let .setTaskPresentation(taskID, boardStage, importance, priority, isFlagged):
      try await persistTaskPresentation(
        taskID: taskID,
        boardStage: boardStage,
        importance: importance,
        priority: priority,
        isFlagged: isFlagged
      )
      result = .none

    case let .updateTaskNote(taskID, field, value):
      try await applyTaskNoteOwnerWrite(
        taskID: taskID,
        field: field,
        rawValue: value
      )
      result = .none

    case let .setTaskCompletion(taskID, isCompleted, completionDate):
      try await applyTaskCompletionOwnerWrite(
        taskID: taskID,
        isCompleted: isCompleted,
        completionDate: completionDate
      )
      result = .none

    case let .completeRecurringTask(taskID, occurrenceDate):
      try await applyRecurringTaskCompletionOwnerWrite(
        taskID: taskID,
        occurrenceDate: occurrenceDate
      )
      result = .none

    case let .reorderTask(taskIDs),
      let .setVisibleRootTaskOrder(taskIDs):
      try await persistVisibleRootTaskOrder(taskIDs: taskIDs)
      result = .none

    case let .setProjectRootStructure(rootNodes):
      _ = try await persistProjectRootStructure(rootNodes, context: currentContext())
      result = .none

    case .patchTaskTitle:
      result = try applyImmediateCommand(command, shouldEmitChangeEvent: false)

    case .patchBulletText:
      result = try applyImmediateCommand(command, shouldEmitChangeEvent: false)

    case .setProjectColor,
      .updateTaskText,
      .setTaskPreparationSchedule,
      .setPlannedWorkProgress,
      .restoreProject,
      .setTaskReminderMetadata,
      .applyAttachmentMutation,
      .archiveProject:
      result = try applyImmediateCommand(command, shouldEmitChangeEvent: false)

    case .deleteProject:
      let deletedWorkspaceNodeIDs = try await deleteProjectPermanently()
      result = ProjectMutationResult(deletedWorkspaceNodeIDs: deletedWorkspaceNodeIDs)
    }

    if shouldEmitChangeEvent {
      emitChangeEvent(command: command, result: result)
    }
    return result
  }

  private func persistProjectTitle(_ rawTitle: String) async throws -> Bool {
    let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedTitle = trimmed.isEmpty ? OutlinerProject.defaultTitle : trimmed
    let context = currentContext()

    let previousTitle = Self.normalized(
      runtimeSnapshotProvider?()?.projects.first(where: { $0.id == projectID })?.title
    ) ?? OutlinerProject.defaultTitle
    guard previousTitle != resolvedTitle else {
      return false
    }
    guard let reminderListIdentifier = try resolvedProjectReminderListIdentifier(context: context)
    else {
      return false
    }
    let write: AppOwnerFieldWrite = .listMetadata(
      ReminderListMetadataWrite(
        projectID: projectID,
        reminderListIdentifier: reminderListIdentifier,
        reminderListExternalIdentifier: try resolvedProjectReminderListExternalIdentifier(
          context: context
        ),
        mutation: .title(resolvedTitle)
      )
    )
    let didWrite: Bool
    if let appStateCommandSender {
      didWrite = await appStateCommandSender(
        .writeOwnerField(ownerStore: .reminder, write: write),
        false
      )
    } else if let sidecarOwnerFieldWriter = sidecarOwnerFieldWriter {
      didWrite = await sidecarOwnerFieldWriter(write)
    } else {
      return false
    }
    guard didWrite else {
      return false
    }
    recordMutationIfBatching(context)

    return try await syncWorkspaceProjectIdentity(
      resolvedTitle: resolvedTitle,
      reminderListIdentifier: try resolvedProjectReminderListIdentifier(context: context),
      reminderListExternalIdentifier: try resolvedProjectReminderListExternalIdentifier(
        context: context
      )
    )
  }

  private func persistProjectStage(_ stage: ProjectProgressStage) async throws {
    let context = currentContext()
    let previousStage = currentProjectFeatureRecord()?.progressStageRaw
      .flatMap(Int.init)
      .flatMap(ProjectProgressStage.init(rawValue:))
      ?? .do
    guard previousStage != stage else { return }
    _ = try await writeProjectStageViaOwnerCommand(stage, context: context)
  }

  private func resolvedProjectReminderListIdentifier(context: ModelContext) throws -> String? {
    _ = context
    if let runtimeIdentifier = Self.normalized(
      runtimeSnapshotProvider?()?.projectReminderListIdentifierByProjectID[projectID]
    ) {
      return runtimeIdentifier
    }
    if let runtimeExternalIdentifier = Self.normalized(
      runtimeSnapshotProvider?()?.projectReminderListExternalIdentifierByProjectID[projectID]
    ) {
      return runtimeExternalIdentifier
    }
    return nil
  }

  private func resolvedProjectReminderListExternalIdentifier(context: ModelContext) throws -> String? {
    _ = context
    if let runtimeExternalIdentifier = Self.normalized(
      runtimeSnapshotProvider?()?.projectReminderListExternalIdentifierByProjectID[projectID]
    ) {
      return runtimeExternalIdentifier
    }
    if let runtimeIdentifier = Self.normalized(
      runtimeSnapshotProvider?()?.projectReminderListIdentifierByProjectID[projectID]
    ) {
      return runtimeIdentifier
    }
    return nil
  }

  private func writeProjectStageViaOwnerCommand(
    _ stage: ProjectProgressStage,
    context: ModelContext
  ) async throws -> Bool {
    guard try await writeProjectMetadata(.progressStage(stage)) else {
      return false
    }
    ProjectProgressStage.touchBoardOrderRevision()
    recordMutationIfBatching(context)
    return true
  }

  private func persistProjectNoteDirectly(
    _ note: String,
    context: ModelContext
  ) async throws -> Bool {
    guard try await writeProjectMetadata(.projectNote(note)) else {
      return false
    }
    recordMutationIfBatching(context)
    return true
  }

  private func writeProjectMetadata(_ mutation: ProjectMetadataMutation) async throws -> Bool {
    guard let sidecarOwnerFieldWriter else {
      throw ProjectDocumentStoreError.sidecarOwnerCommandUnavailable(.projectMetadata)
    }
    return await sidecarOwnerFieldWriter(
      .projectMetadata(
        ProjectMetadataWrite(
          projectID: projectID,
          mutation: mutation
        )
      )
    )
  }

  private func writeProjectTreeStructure(
    projectID targetProjectID: UUID,
    rootNodes: [ReminderProjectRootNodeRecord]
  ) async throws -> Bool {
    guard let sidecarOwnerFieldWriter else {
      throw ProjectDocumentStoreError.sidecarOwnerCommandUnavailable(.treeStructure)
    }
    return await sidecarOwnerFieldWriter(
      .treeStructure(
        ProjectTreeStructureWrite(
          projectID: targetProjectID,
          rootNodes: rootNodes
        )
      )
    )
  }

  private func writeProjectOrdering(
    projectID targetProjectID: UUID,
    orderedTopLevelReminderExternalIdentifiers: [String]
  ) async throws -> Bool {
    guard let sidecarOwnerFieldWriter else {
      throw ProjectDocumentStoreError.sidecarOwnerCommandUnavailable(.ordering)
    }
    return await sidecarOwnerFieldWriter(
      .ordering(
        ProjectOrderingWrite(
          mutation: .project(
            projectID: targetProjectID,
            orderedTopLevelReminderExternalIdentifiers: orderedTopLevelReminderExternalIdentifiers
          )
        )
      )
    )
  }

  private func persistProjectRootStructure(
    _ rootNodes: [ReminderProjectRootNodeRecord],
    context: ModelContext
  ) async throws -> Bool {
    if sidecarOwnerFieldWriter != nil {
      guard try await writeProjectTreeStructure(projectID: projectID, rootNodes: rootNodes) else {
        return false
      }
      recordMutationIfBatching(context)
      return true
    }
    return try persistProjectRootStructureDirectly(rootNodes, context: context)
  }

  private func persistProjectRootStructureDirectly(
    _ rootNodes: [ReminderProjectRootNodeRecord],
    context: ModelContext
  ) throws -> Bool {
    guard let projectionSidecarStore,
      let reminderListExternalIdentifier = try resolvedProjectReminderListExternalIdentifier(
        context: context
      )
    else {
      return false
    }

    _ = ReminderProjectionSidecarMutationService.mutateProjectRootStructure(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      mutation: { record in
        record.rootNodes = rootNodes
      },
      store: projectionSidecarStore
    )
    recordMutationIfBatching(context)
    return true
  }

  private func runtimeTaskNode(taskID: UUID) -> OutlineNode? {
    let bridgedReminderExternalIdentifier = Self.normalized(
      TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID)
    )
    for project in runtimeSnapshotProvider?()?.projects ?? [] {
      for entry in project.document.flatten() where entry.node.type.isTask {
        if entry.node.canonicalID == taskID {
          return entry.node
        }
        guard let bridgedReminderExternalIdentifier else { continue }
        if Self.normalized(entry.node.reminderExternalIdentifier) == bridgedReminderExternalIdentifier {
          return entry.node
        }
      }
    }
    return nil
  }

  private struct RuntimeTaskCommandState {
    let taskID: UUID
    let title: String
    let reminderIdentifier: String?
    let reminderExternalIdentifier: String?
    let reminderNoteText: String
    let isCompleted: Bool
    let completionDate: Date?
    let startDate: Date?
    let dueDate: Date?
    let scheduleHasExplicitTime: Bool
    let scheduledDurationMinutes: Int?
    let priority: Int
    let recurrenceRuleRaw: String?
    let boardStage: BoardStage
    let importance: ImportanceLevel
    let isFlagged: Bool
    let requiredWorkDays: Int
    let completedWorkUnits: Int
    let completedWorkUnitDatesRaw: String
    let preparationScheduleOverridesRaw: String
    let createdAt: Date
  }

  private func currentProjectFeatureRecord() -> ReminderProjectFeatureSidecarRecord? {
    if let runtimeRecord = runtimeSnapshotProvider?()?.projectFeatureSidecarByProjectID[projectID] {
      return runtimeRecord
    }
    return nil
  }

  private func runtimeTaskCommandState(
    taskID: UUID,
    context: ModelContext,
    includeRemoteSnapshot: Bool = false
  ) throws -> RuntimeTaskCommandState? {
    let runtimeSnapshot = runtimeSnapshotProvider?()
    let runtimeNode = runtimeTaskNode(taskID: taskID)
    let reminderExternalIdentifier =
      Self.normalized(runtimeNode?.reminderExternalIdentifier)
      ?? Self.normalized(TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID))
    let taskFeatureRecord = reminderExternalIdentifier.flatMap {
      runtimeSnapshot?.taskFeatureSidecarByReminderExternalIdentifier[$0]
    }
    let reminderMetadata = runtimeNode.flatMap { runtimeSnapshot?.reminderMetadata(for: $0) }

    let remoteSnapshot: ReminderTaskRemoteSnapshot?
    if includeRemoteSnapshot,
      let reminderProjectProvider,
      let taskReference = try resolvedReminderTaskReference(taskID: taskID, context: context)
    {
      remoteSnapshot = try reminderProjectProvider.taskSnapshot(for: taskReference)
    } else {
      remoteSnapshot = nil
    }

    let normalizedDateStorage = ReminderTaskDateCanonicalizer.normalizedStorage(
      dueDate: remoteSnapshot?.dueDate ?? reminderMetadata?.dueDate,
      startDate: remoteSnapshot?.startDate
    )

    return RuntimeTaskCommandState(
      taskID: taskID,
      title: Self.normalized(remoteSnapshot?.title) ?? runtimeNode?.text ?? "",
      reminderIdentifier: Self.normalized(remoteSnapshot?.identifier)
        ?? Self.normalized(runtimeNode?.reminderIdentifier),
      reminderExternalIdentifier: reminderExternalIdentifier,
      reminderNoteText: ReminderNoteSourceCodec.bulletNoteText(from: remoteSnapshot?.noteText),
      isCompleted: remoteSnapshot?.isCompleted ?? runtimeNode?.type.isCompleted ?? false,
      completionDate: remoteSnapshot?.completionDate,
      startDate: normalizedDateStorage.startDate,
      dueDate: normalizedDateStorage.dueDate,
      scheduleHasExplicitTime: remoteSnapshot?.hasExplicitTime ?? reminderMetadata?.hasExplicitTime
        ?? false,
      scheduledDurationMinutes: taskFeatureRecord?.scheduledDurationMinutes,
      priority: remoteSnapshot?.priority ?? reminderMetadata?.priority ?? 0,
      recurrenceRuleRaw: OutlinerIntegratedStore.encodeRecurrence(reminderMetadata?.recurrence),
      boardStage: taskFeatureRecord?.boardStageRaw.flatMap(BoardStage.init(rawValue:)) ?? .now,
      importance: taskFeatureRecord?.importanceRaw.flatMap(ImportanceLevel.init(rawValue:))
        ?? .minor,
      isFlagged: taskFeatureRecord?.isFlagged ?? false,
      requiredWorkDays: max(0, taskFeatureRecord?.requiredWorkDays ?? 0),
      completedWorkUnits: max(0, taskFeatureRecord?.completedWorkUnits ?? 0),
      completedWorkUnitDatesRaw: taskFeatureRecord?.completedWorkUnitDatesRaw ?? "",
      preparationScheduleOverridesRaw: taskFeatureRecord?.preparationScheduleOverridesRaw ?? "",
      createdAt: taskFeatureRecord?.createdAt ?? remoteSnapshot?.modifiedAt ?? .now
    )
  }

  private func resolvedReminderTaskReference(
    taskID: UUID,
    context: ModelContext
  ) throws -> ReminderTaskReference? {
    _ = context
    let runtimeNode = runtimeTaskNode(taskID: taskID)
    let reminderIdentifier = Self.normalized(runtimeNode?.reminderIdentifier)
    let reminderExternalIdentifier =
      Self.normalized(runtimeNode?.reminderExternalIdentifier)
      ?? Self.normalized(TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID))
    guard reminderExternalIdentifier != nil || reminderIdentifier != nil else {
      return nil
    }

    return ReminderTaskReference(
      taskID: taskID,
      reminderIdentifier: reminderIdentifier,
      reminderExternalIdentifier: reminderExternalIdentifier
    )
  }

  private func resolvedReminderExternalIdentifier(
    taskID: UUID,
    context: ModelContext
  ) throws -> String? {
    _ = context
    return Self.normalized(runtimeTaskNode(taskID: taskID)?.reminderExternalIdentifier)
      ?? Self.normalized(TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID))
  }

  private func recordDirectTaskMutation(
    _ metadata: ReminderTaskRemoteMetadata?,
    taskID: UUID,
    context: ModelContext
  ) {
    guard let reminderExternalIdentifier = Self.normalized(metadata?.externalIdentifier) else {
      recordMutationIfBatching(context)
      return
    }
    TaskIdentityBridgeStore.upsert(
      taskID: taskID,
      reminderExternalIdentifier: reminderExternalIdentifier,
      ownerProjectID: projectID
    )
    recordMutationIfBatching(context)
  }

  @discardableResult
  private func mutateTaskFeatureSidecar(
    taskID: UUID,
    context: ModelContext,
    mutation: (inout ReminderTaskFeatureSidecarRecord) -> Void
  ) throws -> Bool {
    guard let reminderExternalIdentifier = try resolvedReminderExternalIdentifier(
      taskID: taskID,
      context: context
    ) else {
      return false
    }
    return mutateTaskFeatureSidecar(
      reminderExternalIdentifier: reminderExternalIdentifier,
      mutation: mutation,
      context: context
    )
  }

  @discardableResult
  private func mutateTaskFeatureSidecar(
    reminderExternalIdentifier: String,
    mutation: (inout ReminderTaskFeatureSidecarRecord) -> Void,
    context: ModelContext
  ) -> Bool {
    guard let projectionSidecarStore else { return false }

    _ = ReminderProjectionSidecarMutationService.mutateTaskFeature(
      reminderExternalIdentifier: reminderExternalIdentifier,
      mutation: mutation,
      store: projectionSidecarStore
    )
    return true
  }

  private func dispatchReminderTaskFieldWrite(
    taskID: UUID,
    mutation: ReminderTaskFieldsMutation,
    context: ModelContext
  ) throws -> Bool {
    guard let appStateCommandSender else {
      throw ProjectDocumentStoreError.appStateCommandUnavailable
    }
    guard let taskReference = try resolvedReminderTaskReference(taskID: taskID, context: context) else {
      throw ProjectDocumentStoreError.canonicalTaskContentMissing(taskID)
    }

    let write: AppOwnerFieldWrite = .taskFields(
      ReminderTaskFieldsWrite(
        projectID: projectID,
        taskID: taskID,
        reminderIdentifier: taskReference.reminderIdentifier,
        reminderExternalIdentifier: taskReference.reminderExternalIdentifier,
        mutation: mutation
      )
    )

    Task { @MainActor in
      _ = await appStateCommandSender(
        .writeOwnerField(ownerStore: .reminder, write: write),
        false
      )
    }
    return true
  }

  private func dispatchReminderTaskFieldWriteAwaiting(
    taskID: UUID,
    mutation: ReminderTaskFieldsMutation,
    context: ModelContext
  ) async throws -> Bool {
    guard let appStateCommandSender else {
      throw ProjectDocumentStoreError.appStateCommandUnavailable
    }
    guard let taskReference = try resolvedReminderTaskReference(taskID: taskID, context: context) else {
      throw ProjectDocumentStoreError.canonicalTaskContentMissing(taskID)
    }

    let write: AppOwnerFieldWrite = .taskFields(
      ReminderTaskFieldsWrite(
        projectID: projectID,
        taskID: taskID,
        reminderIdentifier: taskReference.reminderIdentifier,
        reminderExternalIdentifier: taskReference.reminderExternalIdentifier,
        mutation: mutation
      )
    )

    return await appStateCommandSender(
      .writeOwnerField(ownerStore: .reminder, write: write),
      false
    )
  }

  private func updateParentTaskReminderNote(
    taskID: UUID,
    noteText: String,
    context: ModelContext
  ) async throws {
    guard let parentTaskReference = try resolvedReminderTaskReference(taskID: taskID, context: context) else {
      throw ProjectDocumentStoreError.canonicalTaskContentMissing(taskID)
    }
    let normalizedReminderExternalIdentifier = Self.normalized(
      parentTaskReference.reminderExternalIdentifier
        ?? runtimeTaskNode(taskID: taskID)?.reminderExternalIdentifier
        ?? TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID)
    )
    let normalizedNoteText = ReminderNoteSourceCodec.normalize(noteText)

    _ = try await dispatchReminderTaskFieldWriteAwaiting(
      taskID: taskID,
      mutation: .note(normalizedNoteText),
      context: context
    )

    if let normalizedReminderExternalIdentifier {
      TaskIdentityBridgeStore.upsert(
        taskID: taskID,
        reminderExternalIdentifier: normalizedReminderExternalIdentifier,
        ownerProjectID: projectID
      )
    }
    recordMutationIfBatching(context)
  }

  private func dispatchTaskScheduleSplitWrite(
    taskID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) async throws -> Bool {
    guard let appStateCommandSender else {
      throw ProjectDocumentStoreError.appStateCommandUnavailable
    }
    return await appStateCommandSender(
      .taskScheduleSplit(
        TaskScheduleSplitWrite(
          projectID: projectID,
          taskID: taskID,
          day: day,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes
        )
      ),
      false
    )
  }

  private func dispatchTaskPresentationSplitWrite(
    taskID: UUID,
    boardStage: BoardStage,
    importance: ImportanceLevel,
    priority: Int,
    isFlagged: Bool
  ) async throws -> Bool {
    guard let appStateCommandSender else {
      throw ProjectDocumentStoreError.appStateCommandUnavailable
    }
    return await appStateCommandSender(
      .taskPresentationSplit(
        TaskPresentationSplitWrite(
          projectID: projectID,
          taskID: taskID,
          boardStage: boardStage,
          importance: importance,
          priority: priority,
          isFlagged: isFlagged
        )
      ),
      false
    )
  }

  private func writeProjectColorViaOwnerCommand(_ colorHex: String?) throws {
    let normalizedColorHex = Self.normalized(colorHex)
    let currentColorHex = Self.normalized(
      runtimeSnapshotProvider?()?.projectColorHexByProjectID[projectID]
    )
    guard currentColorHex != normalizedColorHex else { return }

    let context = currentContext()
    guard
      let appStateCommandSender,
      let reminderListIdentifier = try resolvedProjectReminderListIdentifier(context: context),
      let reminderListExternalIdentifier = try resolvedProjectReminderListExternalIdentifier(
        context: context
      )
    else {
      return
    }

    let write: AppOwnerFieldWrite = .listMetadata(
      ReminderListMetadataWrite(
        projectID: projectID,
        reminderListIdentifier: reminderListIdentifier,
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        mutation: .colorHex(normalizedColorHex)
      )
    )

    Task {
      guard await appStateCommandSender(
        .writeOwnerField(ownerStore: .reminder, write: write),
        false
      ) else {
        return
      }
      recordMutationIfBatching(context)
    }
  }

  private func persistProjectNote(_ note: String) async throws {
    let context = currentContext()
    let previousNote = currentProjectFeatureRecord()?.projectNoteMarkdown ?? ""
    guard previousNote != note else { return }
    guard try await persistProjectNoteDirectly(note, context: context) else { return }
    let now = Date()

    ProjectHistoryService.recordProjectNoteSaved(
      projectID: projectID,
      note: note,
      occurredAt: now,
      in: context
    )
    try Self.saveWithSyncPerformanceCounter(context)
  }

  private func writeTaskTitleViaOwnerCommand(taskID: UUID, rawTitle: String) throws {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }

    let context = currentContext()
    let previousState = try runtimeTaskCommandState(taskID: taskID, context: context)
    guard previousState?.title != title else { return }
    guard try dispatchReminderTaskFieldWrite(
      taskID: taskID,
      mutation: .title(title),
      context: context
    ) else {
      return
    }
    let now = Date()
    ProjectHistoryService.recordTaskUpdated(
      projectID: projectID,
      taskID: taskID,
      taskTitle: title,
      previousTitle: previousState?.title ?? "",
      occurredAt: now,
      in: context
    )
    try Self.saveWithSyncPerformanceCounter(context)
  }

  private func persistPatchedNodeText(
    contentID: UUID,
    newText: String
  ) throws -> ProjectReadModelRefreshPlan {
    let context = currentContext()
    guard let content = try Self.fetchTaskContent(for: contentID, context: context) else {
      throw ProjectDocumentStoreError.canonicalTaskContentMissing(contentID)
    }
    guard content.title != newText else { return .none }

    let now = Date()
    content.title = newText
    content.localUpdatedAt = now
    content.isDirty = true

    let record = try Self.ensureProjectRecord(for: projectID, context: context)
    record.updatedAt = now

    try saveIfNotBatching(context)
    let refreshPlan: ProjectReadModelRefreshPlan = .incremental([contentID])
    try scheduleIndexRefresh(refreshPlan, using: context)
    return refreshPlan
  }

  private func writeTaskNoteViaOwnerCommand(
    taskID: UUID,
    field: ProjectTaskNoteField,
    rawValue: String
  ) throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(
      taskID: taskID,
      context: context,
      includeRemoteSnapshot: field == .reminderNote
    )

    switch field {
    case .reminderNote:
      guard previousState?.reminderNoteText != rawValue else { return }
      guard try dispatchReminderTaskFieldWrite(
        taskID: taskID,
        mutation: .note(ReminderNoteSourceCodec.normalize(rawValue)),
        context: context
      ) else {
        return
      }
      ProjectHistoryService.recordTaskReminderNoteSaved(
        projectID: projectID,
        taskID: taskID,
        taskTitle: previousState?.title ?? "",
        note: rawValue,
        occurredAt: .now,
        in: context
      )
      try Self.saveWithSyncPerformanceCounter(context)
      return
    }
  }

  private func applyTaskNoteOwnerWrite(
    taskID: UUID,
    field: ProjectTaskNoteField,
    rawValue: String
  ) async throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(
      taskID: taskID,
      context: context,
      includeRemoteSnapshot: field == .reminderNote
    )

    switch field {
    case .reminderNote:
      guard previousState?.reminderNoteText != rawValue else { return }
      guard try await dispatchReminderTaskFieldWriteAwaiting(
        taskID: taskID,
        mutation: .note(ReminderNoteSourceCodec.normalize(rawValue)),
        context: context
      ) else {
        return
      }
      ProjectHistoryService.recordTaskReminderNoteSaved(
        projectID: projectID,
        taskID: taskID,
        taskTitle: previousState?.title ?? "",
        note: rawValue,
        occurredAt: .now,
        in: context
      )
      try Self.saveWithSyncPerformanceCounter(context)
    }
  }

  private func persistTaskSchedule(
    taskID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) async throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(
      taskID: taskID,
      context: context,
      includeRemoteSnapshot: true
    )
    let nextStorage = Self.scheduleStorage(
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )
    let previousScheduleState = ProjectTaskScheduleMutationSnapshot(
      isCompleted: previousState?.isCompleted ?? false,
      completionDate: previousState?.completionDate,
      startDate: previousState?.startDate,
      dueDate: previousState?.dueDate,
      scheduleHasExplicitTime: previousState?.scheduleHasExplicitTime ?? false,
      scheduledDurationMinutes: previousState?.scheduledDurationMinutes
    )
    let nextScheduleState = ProjectTaskScheduleMutationSnapshot(
      isCompleted: previousState?.isCompleted ?? false,
      completionDate: previousState?.completionDate,
      startDate: nextStorage.startDate,
      dueDate: nextStorage.dueDate,
      scheduleHasExplicitTime: nextStorage.hasExplicitTime,
      scheduledDurationMinutes: nextStorage.durationMinutes
    )
    guard previousScheduleState != nextScheduleState else { return }
    guard try await dispatchTaskScheduleSplitWrite(
      taskID: taskID,
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    ) else {
      return
    }
    let now = Date()
    if let summary = ProjectHistoryService.taskScheduleChangeSummary(
      previousState: previousScheduleState,
      nextState: nextScheduleState
    ) {
      ProjectHistoryService.recordTaskScheduleChanged(
        projectID: projectID,
        taskID: taskID,
        taskTitle: previousState?.title ?? "",
        summary: summary,
        occurredAt: now,
        in: context
      )
      try Self.saveWithSyncPerformanceCounter(context)
    }
  }

  private func persistTaskPresentation(
    taskID: UUID,
    boardStage: BoardStage,
    importance: ImportanceLevel,
    priority: Int,
    isFlagged: Bool
  ) async throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(taskID: taskID, context: context)
    guard
      previousState?.boardStage != boardStage
        || previousState?.importance != importance
        || previousState?.priority != priority
        || previousState?.isFlagged != isFlagged
    else {
      return
    }
    _ = try await dispatchTaskPresentationSplitWrite(
      taskID: taskID,
      boardStage: boardStage,
      importance: importance,
      priority: priority,
      isFlagged: isFlagged
    )
  }

  private func persistTaskPreparationSchedule(
    taskID: UUID,
    targetCompletedUnits: Int,
    isAllDay: Bool,
    timeMinutes: Int,
    durationMinutes: Int
  ) throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(taskID: taskID, context: context)
    let normalizedRequiredWorkDays = max(0, previousState?.requiredWorkDays ?? 0)
    guard targetCompletedUnits > 0, targetCompletedUnits < normalizedRequiredWorkDays else {
      return
    }

    let normalizedTime = min(max(0, timeMinutes), 23 * 60 + 45)
    let normalizedDuration = max(5, durationMinutes)
    var overrides = Self.decodedPreparationScheduleOverrides(
      raw: previousState?.preparationScheduleOverridesRaw ?? ""
    )
    let previousSchedule = overrides[targetCompletedUnits]
      ?? TaskPreparationScheduleSnapshot(
        isAllDay: true,
        timeMinutes: 9 * 60,
        durationMinutes: previousState?.scheduledDurationMinutes ?? 60
      )

    guard
      previousSchedule.isAllDay != isAllDay
        || previousSchedule.timeMinutes != normalizedTime
        || previousSchedule.durationMinutes != normalizedDuration
    else {
      return
    }

    overrides[targetCompletedUnits] = TaskPreparationScheduleSnapshot(
      isAllDay: isAllDay,
      timeMinutes: normalizedTime,
      durationMinutes: normalizedDuration
    )
    _ = try mutateTaskFeatureSidecar(taskID: taskID, context: context) { record in
      record.preparationScheduleOverridesRaw = Self.encodedPreparationScheduleOverrides(overrides)
    }
  }

  private func writeTaskCompletionViaOwnerCommand(
    taskID: UUID,
    isCompleted: Bool,
    completionDate: Date?
  ) throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(
      taskID: taskID,
      context: context,
      includeRemoteSnapshot: true
    )
    let now = Date()
    let resolvedCompletionDate = isCompleted ? (completionDate ?? now) : nil
    guard
      previousState?.isCompleted != isCompleted
        || previousState?.completionDate != resolvedCompletionDate
    else {
      return
    }
    guard try dispatchReminderTaskFieldWrite(
      taskID: taskID,
      mutation: .completion(
        isCompleted: isCompleted,
        completionDate: resolvedCompletionDate
      ),
      context: context
    ) else {
      return
    }
    if previousState?.isCompleted != isCompleted {
      ProjectHistoryService.recordTaskCompletionChange(
        projectID: projectID,
        taskID: taskID,
        taskTitle: previousState?.title ?? "",
        isCompleted: isCompleted,
        completionDate: resolvedCompletionDate,
        localUpdatedAt: now,
        in: context
      )
      try Self.saveWithSyncPerformanceCounter(context)
    }
  }

  private func applyTaskCompletionOwnerWrite(
    taskID: UUID,
    isCompleted: Bool,
    completionDate: Date?
  ) async throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(
      taskID: taskID,
      context: context,
      includeRemoteSnapshot: true
    )
    let now = Date()
    let resolvedCompletionDate = isCompleted ? (completionDate ?? now) : nil
    guard
      previousState?.isCompleted != isCompleted
        || previousState?.completionDate != resolvedCompletionDate
    else {
      return
    }
    guard try await dispatchReminderTaskFieldWriteAwaiting(
      taskID: taskID,
      mutation: .completion(
        isCompleted: isCompleted,
        completionDate: resolvedCompletionDate
      ),
      context: context
    ) else {
      return
    }
    if previousState?.isCompleted != isCompleted {
      ProjectHistoryService.recordTaskCompletionChange(
        projectID: projectID,
        taskID: taskID,
        taskTitle: previousState?.title ?? "",
        isCompleted: isCompleted,
        completionDate: resolvedCompletionDate,
        localUpdatedAt: now,
        in: context
      )
      try Self.saveWithSyncPerformanceCounter(context)
    }
  }

  private func writeRecurringTaskCompletionViaOwnerCommand(
    taskID: UUID,
    occurrenceDate: Date
  ) throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(
      taskID: taskID,
      context: context,
      includeRemoteSnapshot: true
    )
    let now = Date()

    guard Self.normalized(previousState?.recurrenceRuleRaw) != nil else {
      try writeTaskCompletionViaOwnerCommand(
        taskID: taskID,
        isCompleted: true,
        completionDate: now
      )
      return
    }

    let resolvedCompletionDate = now
    guard previousState?.isCompleted != true || previousState?.completionDate == nil else { return }
    guard try dispatchReminderTaskFieldWrite(
      taskID: taskID,
      mutation: .completion(
        isCompleted: true,
        completionDate: resolvedCompletionDate
      ),
      context: context
    ) else {
      return
    }
    if previousState?.isCompleted != true {
      ProjectHistoryService.recordTaskCompletionChange(
        projectID: projectID,
        taskID: taskID,
        taskTitle: previousState?.title ?? "",
        isCompleted: true,
        completionDate: resolvedCompletionDate,
        localUpdatedAt: now,
        in: context
      )
      try Self.saveWithSyncPerformanceCounter(context)
    }
  }

  private func applyRecurringTaskCompletionOwnerWrite(
    taskID: UUID,
    occurrenceDate: Date
  ) async throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(
      taskID: taskID,
      context: context,
      includeRemoteSnapshot: true
    )
    let now = Date()

    guard Self.normalized(previousState?.recurrenceRuleRaw) != nil else {
      try await applyTaskCompletionOwnerWrite(
        taskID: taskID,
        isCompleted: true,
        completionDate: now
      )
      return
    }

    let resolvedCompletionDate = now
    _ = occurrenceDate
    guard previousState?.isCompleted != true || previousState?.completionDate == nil else { return }
    guard try await dispatchReminderTaskFieldWriteAwaiting(
      taskID: taskID,
      mutation: .completion(
        isCompleted: true,
        completionDate: resolvedCompletionDate
      ),
      context: context
    ) else {
      return
    }
    if previousState?.isCompleted != true {
      ProjectHistoryService.recordTaskCompletionChange(
        projectID: projectID,
        taskID: taskID,
        taskTitle: previousState?.title ?? "",
        isCompleted: true,
        completionDate: resolvedCompletionDate,
        localUpdatedAt: now,
        in: context
      )
      try Self.saveWithSyncPerformanceCounter(context)
    }
  }

  private func persistPlannedWorkProgress(
    taskID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date
  ) throws {
    let context = currentContext()
    let previousState = try runtimeTaskCommandState(taskID: taskID, context: context)
    let recordedAt = Calendar.autoupdatingCurrent.startOfDay(for: completedOn)

    let normalizedRequiredWorkDays = max(0, previousState?.requiredWorkDays ?? 0)
    let normalizedTarget = max(0, min(targetCompletedUnits, normalizedRequiredWorkDays))
    guard previousState?.completedWorkUnits != normalizedTarget else { return }

    var dates = Self.decodedCompletedWorkUnitDates(
      raw: previousState?.completedWorkUnitDatesRaw ?? "",
      requiredCount: previousState?.completedWorkUnits ?? 0,
      defaultDate: completedOn
    )
    if normalizedTarget > (previousState?.completedWorkUnits ?? 0) {
      dates.append(
        contentsOf: Array(
          repeating: recordedAt,
          count: normalizedTarget - (previousState?.completedWorkUnits ?? 0)
        )
      )
    } else {
      dates = Array(dates.prefix(normalizedTarget))
    }

    _ = try mutateTaskFeatureSidecar(taskID: taskID, context: context) { record in
      record.completedWorkUnits = normalizedTarget
      record.completedWorkUnitDatesRaw = Self.encodedCompletedWorkUnitDates(dates)
    }
  }

  private func persistTaskReminderMetadata(
    taskID: UUID,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?,
    modifiedAt: Date?,
    reminderCalendarIdentifier: String?
  ) throws {
    let normalizedIdentifier = Self.normalized(reminderIdentifier)
    let normalizedExternalIdentifier = Self.normalized(reminderExternalIdentifier)
    if let normalizedExternalIdentifier {
      TaskIdentityBridgeStore.upsert(
        taskID: taskID,
        reminderExternalIdentifier: normalizedExternalIdentifier,
        ownerProjectID: projectID
      )
    } else {
      TaskIdentityBridgeStore.remove(taskID: taskID)
    }
    _ = normalizedIdentifier
    _ = modifiedAt
    _ = reminderCalendarIdentifier
  }

  private func createTaskViaOwnerTreeWrite(
    title: String,
    parentTaskID: UUID?,
    rootBulletID: UUID?,
    insertionSlot: Int?,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    taskIDOverride: UUID? = nil,
    noteText: String = "",
    recordHistory: Bool = true
  ) async throws -> UUID? {
    guard sidecarOwnerFieldWriter != nil else {
      throw ProjectDocumentStoreError.sidecarOwnerCommandUnavailable(.treeStructure)
    }

    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let context = currentContext()
    let now = Date()
    let taskID = taskIDOverride ?? UUID()
    let nextStorage = Self.scheduleStorage(
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )

    guard let reminderProjectProvider,
      let reminderListIdentifier = try resolvedProjectReminderListIdentifier(context: context)
    else { return nil }

    let reminderListExternalIdentifier = try resolvedProjectReminderListExternalIdentifier(
      context: context
    )
    let metadata = try reminderProjectProvider.createTaskReminder(
      inProject: reminderListIdentifier,
      title: trimmed,
      dueDate: nextStorage.dueDate,
      hasExplicitTime: nextStorage.hasExplicitTime,
      noteText: noteText
    )
    guard
      let metadata,
      let reminderExternalIdentifier = Self.normalized(metadata.externalIdentifier)
    else {
      return nil
    }

    TaskIdentityBridgeStore.upsert(
      taskID: taskID,
      reminderExternalIdentifier: reminderExternalIdentifier,
      ownerProjectID: projectID
    )

    let createdTaskReference = ReminderTaskReference(
      taskID: taskID,
      reminderIdentifier: metadata.identifier,
      reminderExternalIdentifier: reminderExternalIdentifier
    )

    do {
      if let parentTaskID {
        try await insertCreatedTaskAnchor(
          reminderExternalIdentifier: reminderExternalIdentifier,
          intoParentTask: parentTaskID,
          insertionSlot: insertionSlot,
          context: context
        )
      } else {
        try await insertCreatedTaskIntoProjectRootStructure(
          reminderExternalIdentifier: reminderExternalIdentifier,
          reminderListExternalIdentifier: reminderListExternalIdentifier,
          rootBulletID: rootBulletID,
          insertionSlot: insertionSlot,
          context: context
        )
      }
    } catch {
      _ = try? reminderProjectProvider.deleteReminderTask(for: createdTaskReference)
      TaskIdentityBridgeStore.remove(taskID: taskID)
      throw error
    }

    if recordHistory {
      ProjectHistoryService.recordTaskCreated(
        projectID: projectID,
        taskID: taskID,
        taskTitle: trimmed,
        occurredAt: now,
        in: context
      )
    }
    try saveIfNotBatching(context)
    return taskID
  }

  private func createTaskCanonically(
    taskID: UUID,
    title: String,
    parentTaskID: UUID?,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    noteText: String,
    context: ModelContext,
    now: Date,
    recordHistory: Bool
  ) throws -> UUID? {
    let record = try Self.ensureProjectRecord(for: projectID, context: context)
    let nextRowOrder = try Self.nextTaskRowOrder(
      in: projectID,
      parentTaskID: parentTaskID,
      context: context
    )

    let content = TaskContent(
      id: taskID,
      title: title,
      reminderOwnerProjectID: projectID,
      reminderOwnerCalendarID: Self.normalized(record.projectReminderListIdentifier),
      isDirty: true,
      localUpdatedAt: now,
      createdAt: now
    )
    let nextStorage = Self.scheduleStorage(
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )
    content.startDate = nextStorage.startDate
    content.dueDate = nextStorage.dueDate
    content.scheduleHasExplicitTime = nextStorage.hasExplicitTime
    content.scheduledDurationMinutes = nextStorage.durationMinutes
    content.reminderNoteText = ReminderNoteSourceCodec.normalize(noteText)
    context.insert(content)

    let placementID = UUID()
    let parentPlacementID = try Self.primaryPlacementID(
      for: parentTaskID,
      projectID: projectID,
      context: context
    )
    let placement = TaskPlacement(
      id: placementID,
      stablePlacementKey: "outliner:\(placementID.uuidString.lowercased())",
      sourceKindRaw: TaskPlacementSourceKind.primary.rawValue,
      contentID: taskID,
      projectID: projectID,
      parentPlacementID: parentPlacementID,
      rowOrder: nextRowOrder,
      createdAt: now,
      updatedAt: now
    )
    context.insert(placement)

    if let parentTaskID, let parentContent = try Self.fetchTaskContent(for: parentTaskID, context: context) {
      var childIDs = parentContent.childContentIDs
      childIDs.append(taskID)
      parentContent.childContentIDs = childIDs
      parentContent.localUpdatedAt = now
      parentContent.isDirty = true
    }

    record.updatedAt = now
    if recordHistory {
      ProjectHistoryService.recordTaskCreated(
        projectID: projectID,
        taskID: taskID,
        taskTitle: title,
        occurredAt: now,
        in: context
      )
    }
    try Self.refreshProjectReadModels(for: projectID, context: context, projectRecord: record)
    try saveIfNotBatching(context)
    return taskID
  }

  private func insertCreatedTaskAnchor(
    reminderExternalIdentifier: String,
    intoParentTask parentTaskID: UUID,
    insertionSlot: Int?,
    context: ModelContext
  ) async throws {
    guard let reminderProjectProvider,
      let parentTaskReference = try resolvedReminderTaskReference(taskID: parentTaskID, context: context),
      let parentSnapshot = try reminderProjectProvider.taskSnapshot(for: parentTaskReference),
      let updatedDocument = ReminderNoteSourceMutationService.insertingChildAnchor(
        reminderExternalIdentifier,
        into: parentSnapshot.noteText,
        at: insertionSlot
      )
    else {
      throw ProjectDocumentStoreError.canonicalTaskContentMissing(parentTaskID)
    }

    try await updateParentTaskReminderNote(
      taskID: parentTaskID,
      noteText: updatedDocument.normalizedText,
      context: context
    )
  }

  private func insertCreatedTaskIntoProjectRootStructure(
    reminderExternalIdentifier: String,
    reminderListExternalIdentifier: String?,
    rootBulletID: UUID?,
    insertionSlot: Int?,
    context: ModelContext
  ) async throws {
    guard sidecarOwnerFieldWriter != nil else {
      throw ProjectDocumentStoreError.sidecarOwnerCommandUnavailable(.treeStructure)
    }

    guard let reminderListExternalIdentifier = Self.normalized(reminderListExternalIdentifier) else {
      if rootBulletID == nil {
        return
      }
      throw ProjectDocumentStoreError.projectRootBulletMissing(rootBulletID!)
    }

    let currentRootNodes =
      runtimeSnapshotProvider?()
      .flatMap { runtimeSnapshot in
        runtimeSnapshot.projects.first(where: { $0.id == projectID }).map { project in
          ReminderProjectRootStructureCodec.rootNodes(from: project.document.rootNodes)
        }
      }
      ?? []

    guard let updatedRootNodes = ReminderProjectRootStructureMutationService.insertingTask(
      reminderExternalIdentifier: reminderExternalIdentifier,
      into: currentRootNodes,
      parentRootBulletID: rootBulletID,
      insertionSlot: insertionSlot
    ) else {
      if rootBulletID == nil {
        return
      }
      throw ProjectDocumentStoreError.projectRootBulletMissing(rootBulletID!)
    }

    guard try await persistProjectRootStructure(updatedRootNodes, context: context) else {
      if rootBulletID == nil {
        return
      }
      throw ProjectDocumentStoreError.projectRootBulletMissing(rootBulletID!)
    }
  }

  private struct RuntimeTaskDeletionContext {
    let project: OutlinerProject
    let rootNode: OutlineNode
    let parentNode: OutlineNode?
    let subtreeTaskNodes: [OutlineNode]
  }

  private func deleteTaskPermanently(taskID: UUID) async throws {
    let context = currentContext()
    guard try await deleteTaskDirectly(taskID: taskID, context: context) else {
      throw ProjectDocumentStoreError.canonicalTaskContentMissing(taskID)
    }
  }

  private func deleteTaskDirectly(
    taskID: UUID,
    context: ModelContext
  ) async throws -> Bool {
    guard let reminderProjectProvider,
      let deletionContext = runtimeTaskDeletionContext(for: taskID)
    else {
      return false
    }

    let rootNode = deletionContext.rootNode
    guard let rootReminderExternalIdentifier = Self.normalized(rootNode.reminderExternalIdentifier) else {
      return false
    }

    switch deletionContext.parentNode?.type {
    case .task:
      let parentTaskID = try resolvedSourceTaskID(for: deletionContext.parentNode!, context: context)
      try await removeDeletedTaskAnchor(
        reminderExternalIdentifier: rootReminderExternalIdentifier,
        fromParentTask: parentTaskID,
        context: context
      )
    case .bullet, .reference, nil:
      try await removeDeletedTaskFromProjectRootStructure(
        nodeID: rootNode.id,
        project: deletionContext.project,
        context: context
      )
    }

    let subtreeTaskNodes = deletionContext.subtreeTaskNodes
    let subtreeTaskIDs = try subtreeTaskNodes.map { node in
      try resolvedSourceTaskID(for: node, context: context)
    }
    let subtreeReminderExternalIdentifiers = subtreeTaskNodes.compactMap {
      Self.normalized($0.reminderExternalIdentifier)
    }
    for (sourceTaskID, taskNode) in zip(subtreeTaskIDs.reversed(), subtreeTaskNodes.reversed()) {
      let taskReference = ReminderTaskReference(
        taskID: sourceTaskID,
        reminderIdentifier: Self.normalized(taskNode.reminderIdentifier),
        reminderExternalIdentifier: Self.normalized(taskNode.reminderExternalIdentifier)
      )
      guard try reminderProjectProvider.deleteReminderTask(for: taskReference) else {
        return false
      }
    }

    if let mirrorPlacementStore, !subtreeReminderExternalIdentifiers.isEmpty {
      try await mirrorPlacementStore.removeAll(
        reminderExternalIdentifiers: subtreeReminderExternalIdentifiers
      )
    }

    if let attachmentStore {
      let taskOwnerType = AttachmentOwnerType.task.rawValue
      for subtreeTaskID in subtreeTaskIDs {
        let attachments = try context.fetch(
          FetchDescriptor<AttachmentEntity>(
            predicate: #Predicate {
              $0.ownerTypeRaw == taskOwnerType && $0.ownerID == subtreeTaskID
            }
          )
        )
        for attachment in attachments {
          try attachmentStore.deletePermanent(attachment, in: context)
        }
      }
    }

    persistSequenceAssignmentsAfterTaskDeletion(
      removedTaskIDs: Set(subtreeTaskIDs),
      project: deletionContext.project
    )

    TaskIdentityBridgeStore.remove(taskID: taskID)
    for reminderExternalIdentifier in subtreeReminderExternalIdentifiers {
      TaskIdentityBridgeStore.remove(reminderExternalIdentifier: reminderExternalIdentifier)
    }

    ProjectHistoryService.recordTaskDeleted(
      projectID: projectID,
      taskID: taskID,
      taskTitle: rootNode.text,
      occurredAt: .now,
      in: context
    )
    try saveIfNotBatching(context)
    return true
  }

  private func runtimeTaskDeletionContext(for taskID: UUID) -> RuntimeTaskDeletionContext? {
    if let runtimeSnapshot = runtimeSnapshotProvider?(),
      let project = runtimeSnapshot.projects.first(where: { $0.id == projectID }),
      let deletionContext = taskDeletionContext(for: taskID, in: project)
    {
      return deletionContext
    }
    return nil
  }

  private func taskDeletionContext(
    for taskID: UUID,
    in project: OutlinerProject
  ) -> RuntimeTaskDeletionContext? {
    let bridgedReminderExternalIdentifier = Self.normalized(
      TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID)
    )
    let flattenedEntries = project.document.flatten().filter { entry in
      guard entry.node.type.isTask else { return false }
      if entry.node.canonicalID == taskID {
        return true
      }
      guard let bridgedReminderExternalIdentifier else { return false }
      return Self.normalized(entry.node.reminderExternalIdentifier) == bridgedReminderExternalIdentifier
    }
    guard
      let entry =
        flattenedEntries.first(where: { $0.node.id == $0.node.canonicalID })
        ?? flattenedEntries.first
    else {
      return nil
    }

    let parentNode = OutlineNodeTreeNavigator.parentOf(
      id: entry.node.id,
      in: project.document.rootNodes
    )
    .flatMap { OutlineNodeTreeNavigator.findNode(id: $0, in: project.document.rootNodes) }

    return RuntimeTaskDeletionContext(
      project: project,
      rootNode: entry.node,
      parentNode: parentNode,
      subtreeTaskNodes: taskNodes(in: entry.node)
    )
  }

  private func taskNodes(in rootNode: OutlineNode) -> [OutlineNode] {
    var nodes: [OutlineNode] = rootNode.type.isTask ? [rootNode] : []
    for child in rootNode.children {
      nodes.append(contentsOf: taskNodes(in: child))
    }
    return nodes
  }

  private func resolvedSourceTaskID(
    for node: OutlineNode,
    context: ModelContext
  ) throws -> UUID {
    _ = context
    if let reminderExternalIdentifier = Self.normalized(node.reminderExternalIdentifier) {
      if let bridgedTaskID = TaskIdentityBridgeStore.taskID(for: reminderExternalIdentifier) {
        return bridgedTaskID
      }
    }
    return node.canonicalID
  }

  private func captureTaskDeletionUndoSnapshot(
    taskID: UUID,
    context: ModelContext
  ) throws -> TaskDeletionUndoSnapshot? {
    guard let deletionContext = runtimeTaskDeletionContext(for: taskID) else { return nil }
    guard
      let placement = try taskDeletionUndoPlacement(
        rootNode: deletionContext.rootNode,
        parentNode: deletionContext.parentNode,
        project: deletionContext.project,
        context: context
      )
    else {
      return nil
    }

    let root = try captureTaskDeletionUndoNode(
      deletionContext.rootNode,
      insertionSlot: nil,
      context: context
    )
    return TaskDeletionUndoSnapshot(
      projectID: projectID,
      placement: placement,
      root: root,
      sequenceAssignments: SequentialTaskService.loadAssignments(for: projectID)
    )
  }

  private func taskDeletionUndoPlacement(
    rootNode: OutlineNode,
    parentNode: OutlineNode?,
    project: OutlinerProject,
    context: ModelContext
  ) throws -> TaskDeletionUndoPlacement? {
    if let parentNode, parentNode.type.isTask {
      guard let insertionSlot = parentNode.children.firstIndex(where: { $0.id == rootNode.id }) else {
        return nil
      }
      return .taskParent(
        taskID: try resolvedSourceTaskID(for: parentNode, context: context),
        insertionSlot: insertionSlot
      )
    }

    if let parentNode, case .bullet = parentNode.type {
      guard let insertionSlot = parentNode.children.firstIndex(where: { $0.id == rootNode.id }) else {
        return nil
      }
      return .projectRoot(rootBulletID: parentNode.id, insertionSlot: insertionSlot)
    }

    guard let insertionSlot = project.document.rootNodes.firstIndex(where: { $0.id == rootNode.id }) else {
      return nil
    }
    return .projectRoot(rootBulletID: nil, insertionSlot: insertionSlot)
  }

  private func captureTaskDeletionUndoNode(
    _ node: OutlineNode,
    insertionSlot: Int?,
    context: ModelContext
  ) throws -> TaskDeletionUndoNodeSnapshot {
    let taskID = try resolvedSourceTaskID(for: node, context: context)
    let attachmentSnapshots = try captureTaskAttachmentUndoSnapshots(
      taskID: taskID,
      context: context
    )

    var childSnapshots: [TaskDeletionUndoNodeSnapshot] = []
    childSnapshots.reserveCapacity(node.children.count)
    for (childIndex, childNode) in node.children.enumerated() where childNode.type.isTask {
      childSnapshots.append(
        try captureTaskDeletionUndoNode(
          childNode,
          insertionSlot: childIndex,
          context: context
        )
      )
    }

    return TaskDeletionUndoNodeSnapshot(
      task: try captureTaskDeletionUndoState(
        taskID: taskID,
        for: node,
        attachmentCount: attachmentSnapshots.count,
        context: context
      ),
      insertionSlot: insertionSlot,
      children: childSnapshots,
      attachmentSnapshots: attachmentSnapshots
    )
  }

  private func captureTaskDeletionUndoState(
    taskID: UUID,
    for node: OutlineNode,
    attachmentCount: Int,
    context: ModelContext
  ) throws -> TaskDeletionUndoState {
    let runtimeState = try runtimeTaskCommandState(
      taskID: taskID,
      context: context,
      includeRemoteSnapshot: true
    )
    let reminderExternalIdentifier = Self.normalized(node.reminderExternalIdentifier)
      ?? runtimeState?.reminderExternalIdentifier
      ?? Self.normalized(TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID))
    return TaskDeletionUndoState(
      id: taskID,
      reminderExternalIdentifier: reminderExternalIdentifier,
      title: runtimeState?.title.isEmpty == false ? runtimeState?.title ?? node.text : node.text,
      isCompleted: runtimeState?.isCompleted ?? node.type.isCompleted,
      completionDate: runtimeState?.completionDate,
      startDate: runtimeState?.startDate,
      dueDate: runtimeState?.dueDate,
      scheduleHasExplicitTime: runtimeState?.scheduleHasExplicitTime ?? false,
      scheduledDurationMinutes: runtimeState?.scheduledDurationMinutes,
      priority: runtimeState?.priority ?? 0,
      recurrenceRuleRaw: runtimeState?.recurrenceRuleRaw,
      isFlagged: runtimeState?.isFlagged ?? false,
      reminderNoteText: runtimeState?.reminderNoteText ?? "",
      attachmentCount: attachmentCount,
      boardStageRaw: runtimeState?.boardStage.rawValue ?? BoardStage.now.rawValue,
      importanceRaw: runtimeState?.importance.rawValue ?? ImportanceLevel.minor.rawValue,
      rowOrder: 0,
      requiredWorkDays: runtimeState?.requiredWorkDays ?? 0,
      completedWorkUnits: runtimeState?.completedWorkUnits ?? 0,
      completedWorkUnitDatesRaw: runtimeState?.completedWorkUnitDatesRaw ?? "",
      preparationScheduleOverridesRaw: runtimeState?.preparationScheduleOverridesRaw ?? "",
      createdAt: runtimeState?.createdAt ?? .now
    )
  }

  private func reminderTaskSnapshot(
    taskID: UUID,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?
  ) throws -> ReminderTaskRemoteSnapshot? {
    guard let reminderProjectProvider else { return nil }
    guard Self.normalized(reminderIdentifier) != nil || Self.normalized(reminderExternalIdentifier) != nil else {
      return nil
    }
    return try reminderProjectProvider.taskSnapshot(
      for: ReminderTaskReference(
        taskID: taskID,
        reminderIdentifier: reminderIdentifier,
        reminderExternalIdentifier: reminderExternalIdentifier
      )
    )
  }

  private func restoreDeletedTaskNode(
    _ snapshot: TaskDeletionUndoNodeSnapshot,
    parentTaskID: UUID?,
    rootBulletID: UUID?,
    insertionSlot: Int,
    context: ModelContext
  ) async throws {
    let taskState = snapshot.task
    guard
      let restoredTaskID = try await createTaskViaOwnerTreeWrite(
        title: taskState.title,
        parentTaskID: parentTaskID,
        rootBulletID: rootBulletID,
        insertionSlot: insertionSlot,
        day: taskState.dueDate ?? taskState.startDate,
        timeMinutes: Self.explicitTimeMinutes(
          from: taskState.dueDate ?? taskState.startDate,
          hasExplicitTime: taskState.scheduleHasExplicitTime
        ),
        durationMinutes: taskState.scheduledDurationMinutes,
        taskIDOverride: taskState.id,
        noteText: taskState.reminderNoteText,
        recordHistory: false
      )
    else {
      throw ProjectDocumentStoreError.taskRestoreFailed(taskState.id)
    }

    try await restoreDeletedTaskState(taskState, taskID: restoredTaskID, context: context)

    for childSnapshot in snapshot.children {
      try await restoreDeletedTaskNode(
        childSnapshot,
        parentTaskID: restoredTaskID,
        rootBulletID: nil,
        insertionSlot: childSnapshot.insertionSlot ?? 0,
        context: context
      )
    }

    if let attachmentStore {
      for attachmentSnapshot in snapshot.attachmentSnapshots {
        _ = try attachmentStore.restoreDeletedAttachment(attachmentSnapshot, in: context)
      }
    }
  }

  private func restoreDeletedAttachments(
    in snapshot: TaskDeletionUndoNodeSnapshot,
    context: ModelContext
  ) throws {
    if let attachmentStore {
      for attachmentSnapshot in snapshot.attachmentSnapshots {
        _ = try attachmentStore.restoreDeletedAttachment(attachmentSnapshot, in: context)
      }
    }
    for childSnapshot in snapshot.children {
      try restoreDeletedAttachments(in: childSnapshot, context: context)
    }
  }

  private func restoreDeletedTaskState(
    _ state: TaskDeletionUndoState,
    taskID: UUID,
    context: ModelContext
  ) async throws {
    _ = try await dispatchTaskPresentationSplitWrite(
      taskID: taskID,
      boardStage: BoardStage(rawValue: state.boardStageRaw) ?? .now,
      importance: ImportanceLevel(rawValue: state.importanceRaw) ?? .minor,
      priority: state.priority,
      isFlagged: state.isFlagged
    )

    if state.isCompleted || state.completionDate != nil {
      _ = try await dispatchReminderTaskFieldWriteAwaiting(
        taskID: taskID,
        mutation: .completion(
          isCompleted: state.isCompleted,
          completionDate: state.completionDate
        ),
        context: context
      )
    }

    _ = try mutateTaskFeatureSidecar(taskID: taskID, context: context) { record in
      record.boardStageRaw = state.boardStageRaw
      record.importanceRaw = state.importanceRaw
      record.isFlagged = state.isFlagged
      record.scheduledDurationMinutes = state.scheduledDurationMinutes
      record.requiredWorkDays = max(0, state.requiredWorkDays)
      record.completedWorkUnits = max(0, state.completedWorkUnits)
      record.completedWorkUnitDatesRaw = state.completedWorkUnitDatesRaw
      record.preparationScheduleOverridesRaw = state.preparationScheduleOverridesRaw
    }
  }

  private func captureTaskAttachmentUndoSnapshots(
    taskID: UUID,
    context: ModelContext
  ) throws -> [DeletedAttachmentSnapshot] {
    guard let attachmentStore else { return [] }
    let taskOwnerType = AttachmentOwnerType.task.rawValue
    let attachments = try context.fetch(
      FetchDescriptor<AttachmentEntity>(
        predicate: #Predicate {
          $0.ownerTypeRaw == taskOwnerType && $0.ownerID == taskID
        }
      )
    )

    var snapshots: [DeletedAttachmentSnapshot] = []
    snapshots.reserveCapacity(attachments.count)
    for attachment in attachments {
      snapshots.append(try attachmentStore.deleteWithUndoSnapshot(attachment, in: context))
    }
    return snapshots
  }

  private func persistSequenceAssignmentsAfterTaskDeletion(
    removedTaskIDs: Set<UUID>,
    project: OutlinerProject
  ) {
    guard !removedTaskIDs.isEmpty else { return }
    let filteredAssignments = SequentialTaskService.loadAssignments(for: projectID)
      .filter { removedTaskIDs.contains($0.key) == false }
    let remainingEntries = project.document.flatten().compactMap { entry -> SequentialTaskEntry? in
      guard entry.node.type.isTask, removedTaskIDs.contains(entry.node.canonicalID) == false else {
        return nil
      }
      return SequentialTaskEntry(
        id: entry.node.canonicalID,
        isCompleted: entry.node.type.isCompleted
      )
    }
    let normalizedAssignments = SequentialTaskService.normalizedAssignments(
      entries: remainingEntries,
      assignments: filteredAssignments
    )
    SequentialTaskService.persistAssignments(normalizedAssignments, for: projectID)
    SequentialTaskService.postAssignmentsDidChange(projectIDs: [projectID])
  }

  private static func explicitTimeMinutes(
    from date: Date?,
    hasExplicitTime: Bool
  ) -> Int? {
    guard hasExplicitTime, let date else { return nil }
    let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  private func removeDeletedTaskAnchor(
    reminderExternalIdentifier: String,
    fromParentTask parentTaskID: UUID,
    context: ModelContext
  ) async throws {
    guard let reminderProjectProvider,
      let parentTaskReference = try resolvedReminderTaskReference(taskID: parentTaskID, context: context),
      let parentSnapshot = try reminderProjectProvider.taskSnapshot(for: parentTaskReference),
      let updatedDocument = ReminderNoteSourceMutationService.removingChildAnchor(
        reminderExternalIdentifier,
        from: parentSnapshot.noteText
      )
    else {
      throw ProjectDocumentStoreError.canonicalTaskContentMissing(parentTaskID)
    }

    try await updateParentTaskReminderNote(
      taskID: parentTaskID,
      noteText: updatedDocument.normalizedText,
      context: context
    )
  }

  private func removeDeletedTaskFromProjectRootStructure(
    nodeID: UUID,
    project: OutlinerProject,
    context: ModelContext
  ) async throws {
    var updatedDocument = project.document
    guard updatedDocument.removeNode(id: nodeID) != nil else { return }
    _ = try await persistProjectRootStructure(
      ReminderProjectRootStructureCodec.rootNodes(from: updatedDocument.rootNodes),
      context: context
    )
  }

  private enum DirectTaskSequenceMoveOutcome {
    case applied
    case noOp
    case unavailable
  }

  private struct DirectTaskMoveNodeContext {
    let taskID: UUID
    let rootNode: OutlineNode
    let reminderExternalIdentifier: String
    let isMirrorPlacement: Bool
    let subtreeTaskNodes: [OutlineNode]
  }

  private struct DirectTaskMoveProjectContext {
    let sourceProject: OutlinerProject
    let targetProject: OutlinerProject
    let sourceReminderListIdentifier: String
    let sourceReminderListExternalIdentifier: String
    let targetReminderListIdentifier: String
    let targetReminderListExternalIdentifier: String
  }

  private func moveTaskSequence(
    taskIDs: [UUID],
    targetProjectID: UUID
  ) async throws {
    let normalizedTaskIDs = Array(NSOrderedSet(array: taskIDs)) as? [UUID] ?? taskIDs
    guard !normalizedTaskIDs.isEmpty else { return }

    let context = currentContext()
    let now = Date()
    switch try await moveTaskSequenceDirectly(
      taskIDs: normalizedTaskIDs,
      targetProjectID: targetProjectID,
      context: context,
      movedAt: now
    ) {
    case .applied, .noOp:
      return
    case .unavailable:
      throw ProjectDocumentStoreError.canonicalProjectMissing(targetProjectID)
    }
  }

  private func moveTaskSequenceDirectly(
    taskIDs: [UUID],
    targetProjectID: UUID,
    context: ModelContext,
    movedAt: Date
  ) async throws -> DirectTaskSequenceMoveOutcome {
    guard targetProjectID != projectID else {
      return .noOp
    }
    guard let reminderProjectProvider,
      let moveProjectContext = directTaskMoveProjectContext(targetProjectID: targetProjectID)
    else {
      return .unavailable
    }

    guard let sourceTaskMoveContexts = directTaskMoveRootContexts(
      taskIDs: taskIDs,
      sourceProject: moveProjectContext.sourceProject,
      targetProject: moveProjectContext.targetProject
    ) else {
      return .noOp
    }
    guard !sourceTaskMoveContexts.isEmpty else { return .noOp }
    if sourceTaskMoveContexts.contains(where: \.isMirrorPlacement), mirrorPlacementStore == nil {
      return .unavailable
    }

    let targetProjectRootNodes = ReminderProjectRootStructureCodec.rootNodes(
      from: moveProjectContext.targetProject.document.rootNodes
    )
    let movedTargetRootNodes = try directMovedTargetRootNodes(
      sourceTaskMoveContexts: sourceTaskMoveContexts,
      existingTargetRootNodes: targetProjectRootNodes
    )
    guard let movedTargetRootNodes else { return .noOp }

    var updatedSourceDocument = moveProjectContext.sourceProject.document
    for sourceTaskMoveContext in sourceTaskMoveContexts {
      guard updatedSourceDocument.removeNode(id: sourceTaskMoveContext.rootNode.id) != nil else {
        return .noOp
      }
    }
    let movedSourceRootNodes = ReminderProjectRootStructureCodec.rootNodes(
      from: updatedSourceDocument.rootNodes
    )

    // Direct write fallback was intentionally removed to enforce owner pipeline-only updates.
    let sourceRootStructure = ReminderProjectRootStructureMutationService.record(
      reminderListExternalIdentifier: moveProjectContext.sourceReminderListExternalIdentifier,
      rootNodes: movedSourceRootNodes,
      existing: nil,
      now: movedAt
    )
    let targetRootStructure = ReminderProjectRootStructureMutationService.record(
      reminderListExternalIdentifier: moveProjectContext.targetReminderListExternalIdentifier,
      rootNodes: movedTargetRootNodes,
      existing: nil,
      now: movedAt
    )

    let primaryTaskReferences = try directPrimaryMoveTaskReferences(
      sourceTaskMoveContexts: sourceTaskMoveContexts,
      context: context
    )
    var movedPrimaryTaskReferences: [ReminderTaskReference] = []
    var appliedMirrorMoveContexts: [DirectTaskMoveNodeContext] = []

    do {
      for taskReference in primaryTaskReferences {
        guard
          try reminderProjectProvider.moveTaskReminder(
            for: taskReference,
            toProject: moveProjectContext.targetReminderListIdentifier
          ) != nil
        else {
          throw ProjectDocumentStoreError.canonicalTaskContentMissing(taskReference.taskID)
        }
        movedPrimaryTaskReferences.append(taskReference)
        guard let reminderExternalIdentifier = Self.normalized(taskReference.reminderExternalIdentifier)
        else {
          throw ProjectDocumentStoreError.canonicalTaskContentMissing(taskReference.taskID)
        }
        TaskIdentityBridgeStore.upsert(
          taskID: taskReference.taskID,
          reminderExternalIdentifier: reminderExternalIdentifier,
          ownerProjectID: targetProjectID
        )
      }

      if let mirrorPlacementStore {
        for (index, sourceTaskMoveContext) in sourceTaskMoveContexts.enumerated()
        where sourceTaskMoveContext.isMirrorPlacement
        {
          let reminderExternalIdentifier = sourceTaskMoveContext.reminderExternalIdentifier
          _ = try await mirrorPlacementStore.remove(
            reminderExternalIdentifier: reminderExternalIdentifier,
            targetReminderListExternalIdentifier:
              moveProjectContext.sourceReminderListExternalIdentifier
          )
          _ = try await mirrorPlacementStore.upsert(
            reminderExternalIdentifier: reminderExternalIdentifier,
            targetReminderListExternalIdentifier:
              moveProjectContext.targetReminderListExternalIdentifier,
            normalizedParentReminderExternalIdentifier: nil,
            rowOrder: index,
            now: movedAt
          )
          appliedMirrorMoveContexts.append(sourceTaskMoveContext)
        }
      }

      guard
        try await writeProjectTreeStructure(
          projectID: projectID,
          rootNodes: sourceRootStructure.rootNodes
        ),
        try await writeProjectTreeStructure(
          projectID: targetProjectID,
          rootNodes: targetRootStructure.rootNodes
        )
      else {
        throw ProjectDocumentStoreError.sidecarOwnerCommandUnavailable(.treeStructure)
      }
    } catch {
      let originalSourceRootNodes =
        ReminderProjectRootStructureCodec.rootNodes(from: moveProjectContext.sourceProject.document.rootNodes)
      let originalTargetRootNodes =
        ReminderProjectRootStructureCodec.rootNodes(from: moveProjectContext.targetProject.document.rootNodes)
      _ = try? await writeProjectTreeStructure(
        projectID: projectID,
        rootNodes: originalSourceRootNodes
      )
      _ = try? await writeProjectTreeStructure(
        projectID: targetProjectID,
        rootNodes: originalTargetRootNodes
      )

      for sourceTaskMoveContext in appliedMirrorMoveContexts.reversed() {
        let reminderExternalIdentifier = sourceTaskMoveContext.reminderExternalIdentifier
        if let mirrorPlacementStore {
          let sourceRowOrder =
            sourceTaskMoveContexts.firstIndex(where: {
              $0.reminderExternalIdentifier == reminderExternalIdentifier
            }) ?? 0
          _ = try? await mirrorPlacementStore.remove(
            reminderExternalIdentifier: reminderExternalIdentifier,
            targetReminderListExternalIdentifier:
              moveProjectContext.targetReminderListExternalIdentifier
          )
          _ = try? await mirrorPlacementStore.upsert(
            reminderExternalIdentifier: reminderExternalIdentifier,
            targetReminderListExternalIdentifier:
              moveProjectContext.sourceReminderListExternalIdentifier,
            normalizedParentReminderExternalIdentifier: nil,
            rowOrder: sourceRowOrder,
            now: movedAt
          )
        }
      }

      for taskReference in movedPrimaryTaskReferences.reversed() {
        _ = try? reminderProjectProvider.moveTaskReminder(
          for: taskReference,
          toProject: moveProjectContext.sourceReminderListIdentifier
        )
        if let reminderExternalIdentifier = Self.normalized(taskReference.reminderExternalIdentifier) {
          TaskIdentityBridgeStore.upsert(
            taskID: taskReference.taskID,
            reminderExternalIdentifier: reminderExternalIdentifier,
            ownerProjectID: projectID
          )
        }
      }
      throw error
    }

    recordMutationIfBatching(context)
    return .applied
  }

  private func directTaskMoveProjectContext(
    targetProjectID: UUID
  ) -> DirectTaskMoveProjectContext? {
    guard let runtimeSnapshot = runtimeSnapshotProvider?(),
      let sourceProject = runtimeSnapshot.projects.first(where: { $0.id == projectID }),
      let targetProject = runtimeSnapshot.projects.first(where: { $0.id == targetProjectID }),
      let sourceReminderListIdentifier = Self.normalized(
        runtimeSnapshot.projectReminderListIdentifierByProjectID[projectID]
      ),
      let sourceReminderListExternalIdentifier = Self.normalized(
        runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[projectID]
      ),
      let targetReminderListIdentifier = Self.normalized(
        runtimeSnapshot.projectReminderListIdentifierByProjectID[targetProjectID]
      ),
      let targetReminderListExternalIdentifier = Self.normalized(
        runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[targetProjectID]
      )
    else {
      return nil
    }

    return DirectTaskMoveProjectContext(
      sourceProject: sourceProject,
      targetProject: targetProject,
      sourceReminderListIdentifier: sourceReminderListIdentifier,
      sourceReminderListExternalIdentifier: sourceReminderListExternalIdentifier,
      targetReminderListIdentifier: targetReminderListIdentifier,
      targetReminderListExternalIdentifier: targetReminderListExternalIdentifier
    )
  }

  private func directTaskMoveRootContexts(
    taskIDs: [UUID],
    sourceProject: OutlinerProject,
    targetProject: OutlinerProject
  ) -> [DirectTaskMoveNodeContext]? {
    let targetVisibleTaskIDs = Set(
      targetProject.document.flatten().compactMap { entry -> UUID? in
        entry.node.type.isTask ? entry.node.canonicalID : nil
      }
    )

    let sourceRootNodes = sourceProject.document.rootNodes
    var result: [DirectTaskMoveNodeContext] = []
    result.reserveCapacity(taskIDs.count)

    for taskID in taskIDs {
      guard
        let rootNode = directTaskMoveRootNode(
          taskID: taskID,
          sourceRootNodes: sourceRootNodes
        ),
        let reminderExternalIdentifier = Self.normalized(rootNode.reminderExternalIdentifier)
      else {
        return nil
      }

      let subtreeTaskNodes = taskNodes(in: rootNode)
      let subtreeTaskIDs = Set(subtreeTaskNodes.map(\.canonicalID))
      guard targetVisibleTaskIDs.isDisjoint(with: subtreeTaskIDs) else {
        return []
      }

      result.append(
        DirectTaskMoveNodeContext(
          taskID: taskID,
          rootNode: rootNode,
          reminderExternalIdentifier: reminderExternalIdentifier,
          isMirrorPlacement: rootNode.referenceProjectID != nil || rootNode.isCloneInstance,
          subtreeTaskNodes: subtreeTaskNodes
        )
      )
    }

    return result
  }

  private func directTaskMoveRootNode(
    taskID: UUID,
    sourceRootNodes: [OutlineNode]
  ) -> OutlineNode? {
    let bridgedReminderExternalIdentifier = Self.normalized(
      TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID)
    )
    return sourceRootNodes.first { rootNode in
      guard rootNode.type.isTask else { return false }
      if rootNode.canonicalID == taskID {
        return true
      }
      guard let bridgedReminderExternalIdentifier else { return false }
      return Self.normalized(rootNode.reminderExternalIdentifier) == bridgedReminderExternalIdentifier
    }
  }

  private func directPrimaryMoveTaskReferences(
    sourceTaskMoveContexts: [DirectTaskMoveNodeContext],
    context: ModelContext
  ) throws -> [ReminderTaskReference] {
    var taskReferences: [ReminderTaskReference] = []
    for sourceTaskMoveContext in sourceTaskMoveContexts where !sourceTaskMoveContext.isMirrorPlacement {
      for taskNode in sourceTaskMoveContext.subtreeTaskNodes {
        guard let reminderExternalIdentifier = Self.normalized(taskNode.reminderExternalIdentifier)
        else {
          throw ProjectDocumentStoreError.canonicalTaskContentMissing(taskNode.canonicalID)
        }
        let sourceTaskID = try resolvedSourceTaskID(for: taskNode, context: context)
        taskReferences.append(
          ReminderTaskReference(
            taskID: sourceTaskID,
            reminderIdentifier: nil,
            reminderExternalIdentifier: reminderExternalIdentifier
          )
        )
      }
    }
    return taskReferences
  }

  private func directMovedTargetRootNodes(
    sourceTaskMoveContexts: [DirectTaskMoveNodeContext],
    existingTargetRootNodes: [ReminderProjectRootNodeRecord]
  ) throws -> [ReminderProjectRootNodeRecord]? {
    var targetRootNodes = existingTargetRootNodes
    for (index, sourceTaskMoveContext) in sourceTaskMoveContexts.enumerated() {
      let updatedRootNodes =
        sourceTaskMoveContext.isMirrorPlacement
        ? ReminderProjectRootStructureMutationService.insertingMirror(
          reminderExternalIdentifier: sourceTaskMoveContext.reminderExternalIdentifier,
          into: targetRootNodes,
          parentRootBulletID: nil,
          insertionSlot: index
        )
        : ReminderProjectRootStructureMutationService.insertingTask(
          reminderExternalIdentifier: sourceTaskMoveContext.reminderExternalIdentifier,
          into: targetRootNodes,
          parentRootBulletID: nil,
          insertionSlot: index
        )
      guard let updatedRootNodes else { return nil }
      targetRootNodes = updatedRootNodes
    }
    return targetRootNodes
  }

  private func persistVisibleRootTaskOrder(taskIDs: [UUID]) async throws {
    let normalizedTaskIDs = Array(NSOrderedSet(array: taskIDs)) as? [UUID] ?? taskIDs
    guard !normalizedTaskIDs.isEmpty else { return }

    let context = currentContext()
    let orderedReminderExternalIdentifiers = try normalizedTaskIDs.compactMap {
      try resolvedReminderExternalIdentifier(taskID: $0, context: context)
    }
    guard orderedReminderExternalIdentifiers.count == normalizedTaskIDs.count else { return }

    let didPersist = try await writeProjectOrdering(
      projectID: projectID,
      orderedTopLevelReminderExternalIdentifiers: orderedReminderExternalIdentifiers
    )
    guard didPersist else { return }
    recordMutationIfBatching(context)
    try saveIfNotBatching(context)
  }

  private func persistVisibleRootTaskOrderDirectly(taskIDs: [UUID]) throws {
    let normalizedTaskIDs = Array(NSOrderedSet(array: taskIDs)) as? [UUID] ?? taskIDs
    guard !normalizedTaskIDs.isEmpty else { return }

    let context = currentContext()
    let orderedReminderExternalIdentifiers = try normalizedTaskIDs.compactMap {
      try resolvedReminderExternalIdentifier(taskID: $0, context: context)
    }
    guard orderedReminderExternalIdentifiers.count == normalizedTaskIDs.count else { return }

    let currentRootNodes: [ReminderProjectRootNodeRecord]?
    if let runtimeSnapshot = runtimeSnapshotProvider?(),
      let project = runtimeSnapshot.projects.first(where: { $0.id == projectID })
    {
      currentRootNodes = ReminderProjectRootStructureCodec.rootNodes(from: project.document.rootNodes)
    } else {
      currentRootNodes = nil
    }

    guard
      let currentRootNodes,
      let reorderedRootNodes = ReminderProjectRootStructureMutationService.reorderedRootTaskRecords(
        in: currentRootNodes,
        orderedReminderExternalIdentifiers: orderedReminderExternalIdentifiers
      ),
      reorderedRootNodes != currentRootNodes
    else {
      return
    }

    let didPersist = try persistProjectRootStructureDirectly(
      reorderedRootNodes,
      context: context
    )
    guard didPersist else { return }
    try saveIfNotBatching(context)
  }

  private func archiveProject() throws {
    let context = currentContext()
    let record = try Self.ensureProjectRecord(for: projectID, context: context)
    guard !record.isArchived else { return }

    let contentIDs = try Self.projectContentIDs(for: projectID, context: context)
    let contentsByID = try Self.fetchTaskContents(for: contentIDs, context: context)
    let now = Date()

    for content in contentsByID.values where !content.isCompleted || content.completionDate == nil {
      content.isCompleted = true
      content.completionDate = now
      content.localUpdatedAt = now
      content.isDirty = false
    }

    if let reminderProjectProvider,
      let calendarIdentifier = Self.normalized(record.projectReminderListIdentifier)
    {
      try reminderProjectProvider.removeProjectList(identifier: calendarIdentifier)
    }
    record.isArchived = true
    record.archivedAt = now
    record.updatedAt = now
    record.isDirty = false

    if let attachmentStore {
      let projectType = AttachmentOwnerType.project.rawValue
      let taskType = AttachmentOwnerType.task.rawValue
      let projectAttachments = try context.fetch(
        FetchDescriptor<AttachmentEntity>(
          predicate: #Predicate {
            $0.ownerTypeRaw == projectType && $0.ownerID == projectID && !$0.isArchived
          }
        )
      )
      for attachment in projectAttachments {
        try attachmentStore.moveToArchive(attachment, in: context)
      }

      for taskID in contentIDs {
        let taskAttachments = try context.fetch(
          FetchDescriptor<AttachmentEntity>(
            predicate: #Predicate {
              $0.ownerTypeRaw == taskType && $0.ownerID == taskID && !$0.isArchived
            }
          )
        )
        for attachment in taskAttachments {
          try attachmentStore.moveToArchive(attachment, in: context)
        }
      }
    }

    ProjectHistoryService.recordProjectArchived(
      projectID: projectID,
      projectTitle: Self.resolvedProjectTitle(for: record),
      occurredAt: now,
      in: context
    )
    try Self.refreshProjectSummary(for: projectID, context: context, projectRecord: record)
    try saveIfNotBatching(context)
  }

  private func restoreProject() throws {
    let context = currentContext()
    let record = try Self.ensureProjectRecord(for: projectID, context: context)
    guard record.isArchived else { return }

    let now = Date()
    let contentIDs = try Self.projectContentIDs(for: projectID, context: context)
    var taskMetadataByTaskID: [UUID: ReminderTaskRemoteMetadata] = [:]
    if let reminderProjectProvider {
      let restoreResult = try reminderProjectProvider.restoreArchivedProject(
        try Self.archivedProjectSnapshotForRestore(
          projectRecord: record,
          context: context
        )
      )
      taskMetadataByTaskID = restoreResult.taskMetadataByTaskID
      record.projectReminderListIdentifier = restoreResult.list.identifier
      record.projectReminderListExternalIdentifier = restoreResult.list.externalIdentifier
    }

    if let attachmentStore {
      let projectOwnerType = AttachmentOwnerType.project.rawValue
      let taskOwnerType = AttachmentOwnerType.task.rawValue
      let projectAttachments = try context.fetch(
        FetchDescriptor<AttachmentEntity>(
          predicate: #Predicate {
            $0.ownerTypeRaw == projectOwnerType && $0.ownerID == projectID && $0.isArchived
          }
        )
      )
      for attachment in projectAttachments {
        try attachmentStore.restoreFromArchive(attachment, in: context)
      }

      for taskID in contentIDs {
        let taskAttachments = try context.fetch(
          FetchDescriptor<AttachmentEntity>(
            predicate: #Predicate {
              $0.ownerTypeRaw == taskOwnerType && $0.ownerID == taskID && $0.isArchived
            }
          )
        )
        for attachment in taskAttachments {
          try attachmentStore.restoreFromArchive(attachment, in: context)
        }
      }
    }

    let contentsByID = try Self.fetchTaskContents(for: contentIDs, context: context)
    for (taskID, content) in contentsByID {
      if let metadata = taskMetadataByTaskID[taskID] {
        content.reminderIdentifier = metadata.identifier
        content.reminderExternalIdentifier = metadata.externalIdentifier
        content.remoteLastModifiedAt = metadata.modifiedAt
        if let reminderExternalIdentifier = Self.normalized(metadata.externalIdentifier) {
          TaskIdentityBridgeStore.upsert(
            taskID: taskID,
            reminderExternalIdentifier: reminderExternalIdentifier,
            ownerProjectID: projectID
          )
        } else {
          TaskIdentityBridgeStore.remove(taskID: taskID)
        }
      }
      content.isDirty = false
      content.localUpdatedAt = now
    }

    record.isArchived = false
    record.archivedAt = nil
    record.updatedAt = now
    record.isDirty = false

    ProjectHistoryService.recordProjectRestored(
      projectID: projectID,
      projectTitle: Self.resolvedProjectTitle(for: record),
      occurredAt: now,
      in: context
    )
    try Self.refreshProjectReadModels(for: projectID, context: context, projectRecord: record)
    try saveIfNotBatching(context)
  }

  private func applyAttachmentMutation(_ mutation: ProjectAttachmentMutation) throws {
    guard let attachmentStore else { return }
    let context = currentContext()
    let now = Date()
    var affectedProjectIDs: Set<UUID> = [projectID]

    switch mutation {
    case let .importFiles(urls, owner):
      guard !urls.isEmpty else { return }
      for url in urls {
        _ = try attachmentStore.import(from: url, owner: owner, in: context)
      }
      affectedProjectIDs.formUnion(try Self.affectedProjectIDs(for: owner, context: context))

    case let .delete(attachmentID):
      guard let attachment = try Self.fetchAttachment(id: attachmentID, context: context) else { return }
      let owner = AttachmentOwner(
        ownerType: attachment.ownerType,
        ownerID: attachment.ownerID
      )
      affectedProjectIDs.formUnion(try Self.affectedProjectIDs(for: owner, context: context))
      _ = try attachmentStore.deleteWithUndoSnapshot(attachment, in: context)

    case let .move(attachmentID, owner):
      guard let attachment = try Self.fetchAttachment(id: attachmentID, context: context) else { return }
      let currentOwner = AttachmentOwner(
        ownerType: attachment.ownerType,
        ownerID: attachment.ownerID
      )
      affectedProjectIDs.formUnion(try Self.affectedProjectIDs(for: currentOwner, context: context))
      affectedProjectIDs.formUnion(try Self.affectedProjectIDs(for: owner, context: context))
      try attachmentStore.move(attachment, to: owner, in: context)
    }

    for affectedProjectID in affectedProjectIDs {
      let record = try Self.ensureProjectRecord(for: affectedProjectID, context: context)
      record.updatedAt = now
      try Self.refreshProjectReadModels(for: affectedProjectID, context: context, projectRecord: record)
    }
    try saveIfNotBatching(context)
  }

  private func deleteProjectPermanently() async throws -> Set<UUID> {
    let context = currentContext()
    let record = try Self.ensureProjectRecord(for: projectID, context: context)
    let reminderCalendarID = Self.normalized(record.projectReminderListIdentifier) ?? ""
    let projectTitle = Self.resolvedProjectTitle(for: record)
    let projectContentIDs = try Self.projectContentIDs(for: projectID, context: context)
    let taskCount = projectContentIDs.count
    let linkedWorkspaceNodeIDs = try await linkedWorkspaceProjectNodeIDs(for: record)

    if let reminderProjectProvider {
      try reminderProjectProvider.removeProjectList(identifier: reminderCalendarID)
    }

    let projectType = AttachmentOwnerType.project.rawValue
    let taskType = AttachmentOwnerType.task.rawValue
    if let attachmentStore {
      let projectAttachments = try context.fetch(
        FetchDescriptor<AttachmentEntity>(
          predicate: #Predicate {
            $0.ownerTypeRaw == projectType && $0.ownerID == projectID
          }
        )
      )
      for attachment in projectAttachments {
        try attachmentStore.deletePermanent(attachment, in: context)
      }

      for taskID in projectContentIDs {
        let taskAttachments = try context.fetch(
          FetchDescriptor<AttachmentEntity>(
            predicate: #Predicate {
              $0.ownerTypeRaw == taskType && $0.ownerID == taskID
            }
          )
        )
        for attachment in taskAttachments {
          try attachmentStore.deletePermanent(attachment, in: context)
        }
      }
    }

    for taskID in projectContentIDs {
      guard let task = try Self.fetchTaskContent(for: taskID, context: context) else { continue }
      ProjectHistoryService.recordTaskDeleted(
        projectID: projectID,
        taskID: task.id,
        taskTitle: task.title,
        in: context
      )
    }

    try deleteCanonicalProjectState(in: context)

    ProjectHistoryService.recordProjectDeleted(
      projectID: projectID,
      projectTitle: projectTitle,
      taskCount: taskCount,
      in: context
    )
    try Self.saveWithSyncPerformanceCounter(context)

    var deletedNodeIDs = Set<UUID>()
    if let workspaceTreeRepository {
      deletedNodeIDs = try await workspaceTreeRepository.deleteSubtreesPermanently(
        rootNodeIDs: linkedWorkspaceNodeIDs
      )
    }

    return deletedNodeIDs
  }

  private func deleteCanonicalProjectState(in context: ModelContext) throws {
    let placementDescriptor = FetchDescriptor<TaskPlacement>(
      predicate: #Predicate<TaskPlacement> { $0.projectID == projectID }
    )
    let projectPlacements = try context.fetch(placementDescriptor)
    let projectContentIDs = Set(projectPlacements.map(\.contentID))
    for placement in projectPlacements {
      context.delete(placement)
    }

    if let record = try context.fetch(
      FetchDescriptor<ProjectRecord>(
        predicate: #Predicate<ProjectRecord> { $0.id == projectID }
      )
    ).first {
      context.delete(record)
    }

    if let scheduleIndexRecord = try context.fetch(
      FetchDescriptor<ProjectScheduleIndexRecord>(
        predicate: #Predicate<ProjectScheduleIndexRecord> { $0.projectID == projectID }
      )
    ).first {
      context.delete(scheduleIndexRecord)
    }

    if let searchIndexRecord = try context.fetch(
      FetchDescriptor<ProjectSearchIndexRecord>(
        predicate: #Predicate<ProjectSearchIndexRecord> { $0.projectID == projectID }
      )
    ).first {
      context.delete(searchIndexRecord)
    }

    let remainingPlacements = try context.fetch(FetchDescriptor<TaskPlacement>())
    let remainingContentIDs = Set(remainingPlacements.map(\.contentID))
    let orphanedContentIDs = projectContentIDs.subtracting(remainingContentIDs)
    guard !orphanedContentIDs.isEmpty else { return }

    let identifiers = Array(orphanedContentIDs)
    let contentDescriptor = FetchDescriptor<TaskContent>(
      predicate: #Predicate<TaskContent> { identifiers.contains($0.id) }
    )
    for content in try context.fetch(contentDescriptor) {
      context.delete(content)
    }
  }

  private func syncWorkspaceProjectIdentity(
    resolvedTitle: String,
    reminderListIdentifier: String?,
    reminderListExternalIdentifier: String?
  ) async throws -> Bool {
    guard let workspaceTreeRepository else { return false }
    let linkedNodes = try await workspaceTreeRepository.fetchProjectNodes(
      canonicalProjectID: projectID,
      includeArchived: true
    )

    for node in linkedNodes {
      _ = try await workspaceTreeRepository.updateProjectIdentity(
        of: node.id,
        title: resolvedTitle,
        colorHex: node.colorHex,
        reminderListIdentifier: node.reminderListIdentifier
          ?? Self.normalized(reminderListIdentifier),
        reminderListExternalIdentifier: node.reminderListExternalIdentifier
          ?? Self.normalized(reminderListExternalIdentifier)
      )
    }

    return !linkedNodes.isEmpty
  }

  private func linkedWorkspaceProjectNodeIDs(for projectRecord: ProjectRecord) async throws -> [UUID] {
    guard let workspaceTreeRepository else { return [] }
    return try await workspaceTreeRepository.fetchProjectNodes(
      canonicalProjectID: projectRecord.id,
      includeArchived: true
    ).map(\.id)
  }

  @MainActor
  static func createProject(
    title rawTitle: String,
    modelContainer: ModelContainer,
    reminderProjectProvider: ReminderProjectProvider,
    workspaceTreeRepository: WorkspaceTreeRepository? = nil
  ) async throws -> UUID? {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }

    let granted = try await reminderProjectProvider.requestAccess()
    guard granted else { return nil }

    let list = try reminderProjectProvider.createProjectList(title: title)
    let context = ModelContext(modelContainer)
    let now = Date()
    let projectID = UUID()
    let record = try ensureProjectRecord(for: projectID, context: context)
    record.applyCanonicalIdentity(
      title: list.title,
      colorHex: list.colorHex,
      reminderListIdentifier: list.identifier,
      reminderListExternalIdentifier: list.externalIdentifier
    )
    record.createdAt = now
    record.updatedAt = now
    record.isDirty = false

    if let workspaceTreeRepository,
      try await workspaceTreeRepository.fetchProjectNodes(
        canonicalProjectID: projectID,
        includeArchived: true
      ).isEmpty
    {
      _ = try await workspaceTreeRepository.createProject(
        title: list.title,
        colorHex: list.colorHex,
        noteMarkdown: record.noteMarkdown,
        canonicalProjectID: projectID,
        reminderListIdentifier: list.identifier,
        reminderListExternalIdentifier: list.externalIdentifier
      )
    }

    ProjectHistoryService.recordProjectCreated(
      projectID: projectID,
      projectTitle: list.title,
      occurredAt: now,
      in: context
    )
    try refreshProjectReadModels(for: projectID, context: context, projectRecord: record)
    try Self.saveWithSyncPerformanceCounter(context)
    return projectID
  }
}

extension ProjectDocumentStore {
  struct TaskPreparationScheduleSnapshot: Codable, Equatable, Hashable {
    let isAllDay: Bool
    let timeMinutes: Int
    let durationMinutes: Int
  }

  struct TaskScheduleStorageSnapshot: Equatable {
    let startDate: Date?
    let dueDate: Date?
    let hasExplicitTime: Bool
    let durationMinutes: Int?
  }

  nonisolated static func fetchTaskContent(
    for taskID: UUID,
    context: ModelContext
  ) throws -> TaskContent? {
    let descriptor = FetchDescriptor<TaskContent>(
      predicate: #Predicate<TaskContent> { $0.id == taskID }
    )
    return try context.fetch(descriptor).first
  }

  nonisolated static func fetchTaskContent(
    forReminderExternalIdentifier reminderExternalIdentifier: String,
    context: ModelContext
  ) throws -> TaskContent? {
    let reminderExternalIdentifier = reminderExternalIdentifier.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !reminderExternalIdentifier.isEmpty else { return nil }

    let descriptor = FetchDescriptor<TaskContent>(
      predicate: #Predicate<TaskContent> {
        $0.reminderExternalIdentifier == reminderExternalIdentifier
      }
    )
    return try context.fetch(descriptor).first
  }

  nonisolated static func decodedCompletedWorkUnitDates(
    raw: String,
    requiredCount: Int,
    defaultDate: Date?
  ) -> [Date] {
    guard requiredCount > 0 else { return [] }

    let decoded: [Date]
    if
      !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let values = try? JSONDecoder().decode([TimeInterval].self, from: data)
    {
      decoded = values.filter(\.isFinite).map(Date.init(timeIntervalSince1970:))
    } else {
      decoded = []
    }

    if decoded.count >= requiredCount {
      return Array(decoded.prefix(requiredCount))
    }

    let normalizedDefaultDate = defaultDate ?? .now
    return decoded + Array(repeating: normalizedDefaultDate, count: requiredCount - decoded.count)
  }

  static func encodedCompletedWorkUnitDates(_ dates: [Date]) -> String {
    guard !dates.isEmpty else { return "" }
    let encoded = dates.map(\.timeIntervalSince1970)
    guard
      let data = try? JSONEncoder().encode(encoded),
      let raw = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return raw
  }

  static func scheduleStorage(
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TaskScheduleStorageSnapshot {
    guard let day else {
      return TaskScheduleStorageSnapshot(
        startDate: nil,
        dueDate: nil,
        hasExplicitTime: false,
        durationMinutes: nil
      )
    }

    let normalizedDay = calendar.startOfDay(for: day)
    guard let timeMinutes else {
      return TaskScheduleStorageSnapshot(
        startDate: nil,
        dueDate: normalizedDay,
        hasExplicitTime: false,
        durationMinutes: nil
      )
    }

    let boundedMinutes = min(max(0, timeMinutes), 23 * 60 + 59)
    let hours = boundedMinutes / 60
    let minutes = boundedMinutes % 60
    let timedDate =
      calendar.date(
        bySettingHour: hours,
        minute: minutes,
        second: 0,
        of: normalizedDay
      ) ?? normalizedDay

    return TaskScheduleStorageSnapshot(
      startDate: nil,
      dueDate: timedDate,
      hasExplicitTime: true,
      durationMinutes: max(
        5,
        durationMinutes ?? WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
      )
    )
  }

  static func defaultPreparationSchedule(
    for content: TaskContent,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TaskPreparationScheduleSnapshot {
    let anchorDate = ReminderTaskDateCanonicalizer.unifiedDate(
      dueDate: content.dueDate,
      startDate: content.startDate
    )
    let timeMinutes: Int
    if content.scheduleHasExplicitTime, let anchorDate {
      let components = calendar.dateComponents([.hour, .minute], from: anchorDate)
      timeMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
    } else {
      timeMinutes = WorkspaceTaskScheduleEventStore.defaultPreparationTimeMinutes
    }

    return TaskPreparationScheduleSnapshot(
      isAllDay: true,
      timeMinutes: timeMinutes,
      durationMinutes: max(
        5,
        content.scheduledDurationMinutes ?? WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
      )
    )
  }

  static func decodedPreparationScheduleOverrides(raw: String) -> [Int: TaskPreparationScheduleSnapshot] {
    guard !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([Int: TaskPreparationScheduleSnapshot].self, from: data)
    else {
      return [:]
    }

    return decoded
      .filter { key, _ in key > 0 }
      .reduce(into: [Int: TaskPreparationScheduleSnapshot]()) { result, entry in
        result[entry.key] = TaskPreparationScheduleSnapshot(
          isAllDay: entry.value.isAllDay,
          timeMinutes: min(max(0, entry.value.timeMinutes), 23 * 60 + 45),
          durationMinutes: max(5, entry.value.durationMinutes)
        )
      }
  }

  static func encodedPreparationScheduleOverrides(
    _ overrides: [Int: TaskPreparationScheduleSnapshot]
  ) -> String {
    let normalized = overrides
      .filter { key, _ in key > 0 }
      .reduce(into: [Int: TaskPreparationScheduleSnapshot]()) { result, entry in
        result[entry.key] = TaskPreparationScheduleSnapshot(
          isAllDay: entry.value.isAllDay,
          timeMinutes: min(max(0, entry.value.timeMinutes), 23 * 60 + 45),
          durationMinutes: max(5, entry.value.durationMinutes)
        )
      }
    guard
      let data = try? JSONEncoder().encode(normalized),
      let raw = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return raw
  }

  static func nextTaskRowOrder(
    in projectID: UUID,
    parentTaskID: UUID?,
    context: ModelContext
  ) throws -> Int {
    if let parentTaskID {
      let parentPlacementID = try primaryPlacementID(
        for: parentTaskID,
        projectID: projectID,
        context: context
      )
      let descriptor = FetchDescriptor<TaskPlacement>(
        predicate: #Predicate<TaskPlacement> {
          $0.projectID == projectID && $0.parentPlacementID == parentPlacementID
        }
      )
      let placements = try context.fetch(descriptor)
      return (placements.map(\.rowOrder).max() ?? -1) + 1
    }

    let descriptor = FetchDescriptor<TaskPlacement>(
      predicate: #Predicate<TaskPlacement> {
        $0.projectID == projectID && $0.parentPlacementID == nil
      }
    )
    let placements = try context.fetch(descriptor)
    return (placements.map(\.rowOrder).max() ?? -1) + 1
  }

  static func primaryPlacementID(
    for taskID: UUID?,
    projectID: UUID,
    context: ModelContext
  ) throws -> UUID? {
    guard let taskID else { return nil }
    let primarySourceKindRaw = TaskPlacementSourceKind.primary.rawValue
    let descriptor = FetchDescriptor<TaskPlacement>(
      predicate: #Predicate<TaskPlacement> {
        $0.projectID == projectID && $0.contentID == taskID && $0.sourceKindRaw == primarySourceKindRaw
      }
    )
    return try context.fetch(descriptor).first?.id
  }

  static func projectContentIDs(
    for projectID: UUID,
    context: ModelContext
  ) throws -> Set<UUID> {
    let descriptor = FetchDescriptor<TaskPlacement>(
      predicate: #Predicate<TaskPlacement> { $0.projectID == projectID }
    )
    return Set(try context.fetch(descriptor).map(\.contentID))
  }

  static func persistVisibleRootTaskOrder(
    in projectID: UUID,
    orderedVisibleTaskIDs: [UUID],
    context: ModelContext,
    now: Date
  ) throws -> Bool {
    let orderedIDs = Array(NSOrderedSet(array: orderedVisibleTaskIDs)) as? [UUID] ?? orderedVisibleTaskIDs
    guard !orderedIDs.isEmpty else { return false }

    let descriptor = FetchDescriptor<TaskPlacement>(
      predicate: #Predicate<TaskPlacement> {
        $0.projectID == projectID && $0.parentPlacementID == nil
      }
    )
    let rootPlacements = try context.fetch(descriptor)
    let placementsByTaskID = Dictionary(uniqueKeysWithValues: rootPlacements.map { ($0.contentID, $0) })
    guard orderedIDs.allSatisfy({ placementsByTaskID[$0] != nil }) else { return false }

    let trailingPlacements = rootPlacements
      .filter { !orderedIDs.contains($0.contentID) }
      .sorted {
        if $0.rowOrder == $1.rowOrder {
          return $0.createdAt < $1.createdAt
        }
        return $0.rowOrder < $1.rowOrder
      }
    let reordered = orderedIDs.compactMap { placementsByTaskID[$0] } + trailingPlacements
    var didChange = false
    for (index, placement) in reordered.enumerated() {
      if placement.rowOrder != index {
        placement.rowOrder = index
        didChange = true
      }
      placement.updatedAt = now
    }
    return didChange
  }

  static func moveCanonicalTaskSequence(
    taskIDs: [UUID],
    sourceProjectID: UUID,
    targetProjectID: UUID,
    context: ModelContext,
    movedAt: Date
  ) throws {
    let orderedTaskIDs = taskIDs
    let rootPlacementsDescriptor = FetchDescriptor<TaskPlacement>(
      predicate: #Predicate<TaskPlacement> {
        $0.projectID == sourceProjectID && orderedTaskIDs.contains($0.contentID)
      }
    )
    let rootPlacements = try context.fetch(rootPlacementsDescriptor)
    let rootPlacementsByTaskID = Dictionary(uniqueKeysWithValues: rootPlacements.map { ($0.contentID, $0) })
    guard orderedTaskIDs.allSatisfy({ rootPlacementsByTaskID[$0] != nil }) else { return }

    let allSourcePlacements = try context.fetch(
      FetchDescriptor<TaskPlacement>(
        predicate: #Predicate<TaskPlacement> { $0.projectID == sourceProjectID }
      )
    )
    let allTargetPlacements = sourceProjectID == targetProjectID
      ? allSourcePlacements
      : try context.fetch(
        FetchDescriptor<TaskPlacement>(
          predicate: #Predicate<TaskPlacement> { $0.projectID == targetProjectID }
        )
      )

    let allContentIDs = Set(
      allSourcePlacements.map(\.contentID)
        + allTargetPlacements.map(\.contentID)
    )
    let contentsByID = try fetchTaskContents(for: allContentIDs, context: context)

    func subtreeContentIDs(for rootTaskID: UUID) -> Set<UUID> {
      var stack: [UUID] = [rootTaskID]
      var visited: Set<UUID> = []
      while let current = stack.popLast() {
        guard visited.insert(current).inserted else { continue }
        if let children = contentsByID[current]?.childContentIDs {
          stack.append(contentsOf: children.reversed())
        }
      }
      return visited
    }

    let movedSubtreeContentIDs = orderedTaskIDs.reduce(into: Set<UUID>()) { ids, taskID in
      ids.formUnion(subtreeContentIDs(for: taskID))
    }

    let movedPlacements = allSourcePlacements.filter { movedSubtreeContentIDs.contains($0.contentID) }
    for placement in movedPlacements {
      placement.projectID = targetProjectID
      placement.updatedAt = movedAt
    }

    let movedRootPlacements = orderedTaskIDs.compactMap { rootPlacementsByTaskID[$0] }
    let remainingSourceRootPlacements = allSourcePlacements
      .filter {
        $0.parentPlacementID == nil
          && !orderedTaskIDs.contains($0.contentID)
      }
      .sorted {
        if $0.rowOrder == $1.rowOrder {
          return $0.createdAt < $1.createdAt
        }
        return $0.rowOrder < $1.rowOrder
      }

    let existingTargetRootPlacements = allTargetPlacements
      .filter {
        $0.parentPlacementID == nil
          && !orderedTaskIDs.contains($0.contentID)
      }
      .sorted {
        if $0.rowOrder == $1.rowOrder {
          return $0.createdAt < $1.createdAt
        }
        return $0.rowOrder < $1.rowOrder
      }

    if sourceProjectID == targetProjectID {
      let reorderedRootPlacements = movedRootPlacements + remainingSourceRootPlacements
      for (index, placement) in reorderedRootPlacements.enumerated() {
        placement.rowOrder = index
        placement.updatedAt = movedAt
      }
      return
    }

    for (index, placement) in remainingSourceRootPlacements.enumerated() {
      placement.rowOrder = index
      placement.updatedAt = movedAt
    }

    let reorderedTargetPlacements = movedRootPlacements + existingTargetRootPlacements
    for (index, placement) in reorderedTargetPlacements.enumerated() {
      placement.rowOrder = index
      placement.updatedAt = movedAt
    }
  }

  func refreshIndexes(using plan: ProjectReadModelRefreshPlan) async throws {
    guard !plan.isNone else { return }

    let context = currentContext()
    switch plan {
    case .none:
      return
    case .full:
      try Self.refreshProjectReadModels(for: projectID, context: context)
    case let .incremental(taskIDs):
      try Self.refreshProjectReadModelsIncrementally(
        for: projectID,
        changedTaskIDs: taskIDs,
        context: context
      )
    }

    try Self.saveWithSyncPerformanceCounter(context)
  }

  func refreshIndexesIncrementally(for taskIDs: Set<UUID>) async throws {
    try await refreshIndexes(using: .incremental(taskIDs))
  }

  static func buildProjectSummary(
    for project: OutlinerProject,
    projectRecord: ProjectRecord,
    contentsByID: [UUID: TaskContent]
  ) -> ProjectSummaryRecord {
    let documentContentIDs = Set(project.document.flatten().map(\.node.canonicalID))
    let latestTaskUpdatedAt = documentContentIDs.compactMap { contentID in
      contentsByID[contentID]?.localUpdatedAt
    }.max()
    let scheduleEntries = taskScheduleDescriptors(in: project).map { descriptor in
      buildScheduleSliceEntry(
        descriptor: descriptor,
        projectRecord: projectRecord,
        content: contentsByID[descriptor.contentID],
        attachmentCount: contentsByID[descriptor.contentID]?.attachmentCount ?? 0
      )
    }
    return buildProjectSummary(
      from: scheduleEntries,
      projectRecord: projectRecord,
      latestTaskUpdatedAt: latestTaskUpdatedAt
    )
  }

  static func buildProjectSummary(
    from scheduleEntries: [ScheduleSliceEntry],
    projectRecord: ProjectRecord,
    latestTaskUpdatedAt: Date?
  ) -> ProjectSummaryRecord {
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: .now)
    let stage =
      Int(projectRecord.progressStageRaw)
      .flatMap(ProjectProgressStage.init(rawValue:))
      ?? .do

    let rootTasks = scheduleEntries.filter { $0.parentTaskID == nil }
    var openRootTaskCount = 0
    var completedRootTaskCount = 0
    var undatedOpenRootTaskCount = 0
    var overdueOpenRootTaskCount = 0
    var todayTaskCount = 0
    var upcomingDates: [Date] = []

    for task in rootTasks {
      if task.isCompleted {
        completedRootTaskCount += 1
        continue
      }

      openRootTaskCount += 1

      guard let dueDate = task.dueDate else {
        undatedOpenRootTaskCount += 1
        continue
      }

      let day = calendar.startOfDay(for: dueDate)
      if day < today {
        overdueOpenRootTaskCount += 1
      }
      if day == today {
        todayTaskCount += 1
      }
      if day >= today {
        upcomingDates.append(day)
      }
    }

    return ProjectSummaryRecord(
      openRootTaskCount: openRootTaskCount,
      completedRootTaskCount: completedRootTaskCount,
      undatedOpenRootTaskCount: undatedOpenRootTaskCount,
      overdueOpenRootTaskCount: overdueOpenRootTaskCount,
      todayTaskCount: todayTaskCount,
      nextUpcomingDate: upcomingDates.min(),
      deadline: projectRecord.deadline,
      stageRaw: stage.storageRawValue,
      progress: stage.progressValue,
      latestTaskUpdatedAt: latestTaskUpdatedAt,
      title: resolvedProjectTitle(for: projectRecord),
      colorHex: projectRecord.projectColorHex,
      isArchived: projectRecord.isArchived
    )
  }

  static func projectTitle(for projectID: UUID, context: ModelContext) -> String {
    let descriptor = FetchDescriptor<ProjectRecord>(
      predicate: #Predicate<ProjectRecord> { $0.id == projectID }
    )
    let record = try? context.fetch(descriptor).first
    let trimmed = record?.projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      return trimmed
    }
    return OutlinerProject.defaultTitle
  }

  private static func projectSnapshotForReadModels(
    projectID: UUID,
    context: ModelContext,
    projectRecord: ProjectRecord
  ) throws -> OutlinerIntegratedStore.Snapshot? {
    let placements = try context.fetch(
      FetchDescriptor<TaskPlacement>(
        predicate: #Predicate<TaskPlacement> { $0.projectID == projectID },
        sortBy: [
          SortDescriptor(\.rowOrder, order: .forward),
          SortDescriptor(\.createdAt, order: .forward),
        ]
      )
    )
    guard !placements.isEmpty else { return nil }

    let contentIDs = Set(placements.map(\.contentID))
    let contentsByID = try fetchTaskContents(for: contentIDs, context: context)
    let childPlacementsByParentID = Dictionary(grouping: placements) { $0.parentPlacementID }
    let rootPlacements = childPlacementsByParentID[nil, default: []]
      .sorted(by: canonicalPlacementComparator(_:_:))
    let rootNodes = rootPlacements.compactMap {
      canonicalProjectNode(
        from: $0,
        contentsByID: contentsByID,
        childPlacementsByParentID: childPlacementsByParentID
      )
    }

    return OutlinerIntegratedStore.Snapshot(
      projects: [
        OutlinerProject(
          id: projectID,
          title: resolvedProjectTitle(for: projectRecord),
          document: rootNodes.isEmpty
            ? OutlineDocument(rootNodes: [])
            : OutlineDocument(rootNodes: rootNodes)
        )
      ],
      taskStatesByContentID: Dictionary(
        uniqueKeysWithValues: contentsByID.values.map { content in
          (content.id, OutlinerIntegratedTaskState(content: content))
        }
      )
    )
  }

  private static func canonicalPlacementComparator(_ lhs: TaskPlacement, _ rhs: TaskPlacement) -> Bool {
    if lhs.rowOrder != rhs.rowOrder {
      return lhs.rowOrder < rhs.rowOrder
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private static func canonicalProjectNode(
    from placement: TaskPlacement,
    contentsByID: [UUID: TaskContent],
    childPlacementsByParentID: [UUID?: [TaskPlacement]]
  ) -> OutlineNode? {
    guard let content = contentsByID[placement.contentID] else { return nil }
    let childPlacements = childPlacementsByParentID[placement.id, default: []]
      .sorted(by: canonicalPlacementComparator(_:_:))
    let children = childPlacements.compactMap {
      canonicalProjectNode(
        from: $0,
        contentsByID: contentsByID,
        childPlacementsByParentID: childPlacementsByParentID
      )
    }
    let kind: OutlineNodeType
    switch content.contentKindRaw {
    case "task":
      kind = .task(completed: content.isCompleted)
    case "reference":
      if let parsed = OutlineDocument.parseBlockReference(content.title) {
        kind = .reference(targetID: parsed.targetID)
      } else {
        kind = .bullet
      }
    default:
      kind = .bullet
    }

    let text: String
    let referenceProjectID: UUID?
    if case .reference = kind {
      let parsed = OutlineDocument.parseBlockReference(content.title)
      text = parsed?.alias ?? ""
      referenceProjectID = parsed?.projectID
    } else {
      text = content.title
      referenceProjectID = nil
    }

    return OutlineNode(
      id: placement.id,
      canonicalID: content.id,
      text: text,
      type: kind,
      referenceProjectID: referenceProjectID,
      children: children,
      isCollapsed: placement.isCollapsed,
      reminderIdentifier: content.reminderIdentifier,
      reminderExternalIdentifier: content.reminderExternalIdentifier
    )
  }

  static func refreshProjectSummary(
    for projectID: UUID,
    context: ModelContext,
    projectRecord: ProjectRecord? = nil
  ) throws {
    try refreshProjectReadModels(for: projectID, context: context, projectRecord: projectRecord)
  }

  static func refreshProjectReadModelsIncrementally(
    for projectID: UUID,
    changedTaskIDs: Set<UUID>,
    context: ModelContext,
    projectRecord: ProjectRecord? = nil
  ) throws {
    guard !changedTaskIDs.isEmpty else { return }

    let record = try projectRecord ?? ensureProjectRecord(for: projectID, context: context)
    let snapshot = try projectSnapshotForReadModels(
      projectID: projectID,
      context: context,
      projectRecord: record
    )
    let project =
      snapshot?.projects.first
      ?? OutlinerProject(
        id: projectID,
        title: resolvedProjectTitle(for: record),
        document: OutlineDocument(rootNodes: [])
      )
    let activeTaskIDs = Set(project.document.flatten().map(\.node.canonicalID))
    let contentsByID = try fetchTaskContents(for: activeTaskIDs, context: context)
    try refreshProjectReadModelsIncrementally(
      for: project,
      changedTaskIDs: changedTaskIDs,
      context: context,
      projectRecord: record,
      contentsByID: contentsByID
    )
  }

  static func refreshProjectReadModels(
    for projectID: UUID,
    context: ModelContext,
    projectRecord: ProjectRecord? = nil
  ) throws {
    let record = try projectRecord ?? ensureProjectRecord(for: projectID, context: context)
    let snapshot = try projectSnapshotForReadModels(
      projectID: projectID,
      context: context,
      projectRecord: record
    )
    let project =
      snapshot?.projects.first
      ?? OutlinerProject(
        id: projectID,
        title: resolvedProjectTitle(for: record),
        document: OutlineDocument(rootNodes: [])
      )
    let contentIDs =
      snapshot.map { Set($0.taskStatesByContentID.keys) }
      ?? Set(project.document.flatten().map(\.node.canonicalID))
    let contentsByID = try fetchTaskContents(for: contentIDs, context: context)
    try refreshProjectReadModels(
      for: project,
      context: context,
      projectRecord: record,
      contentsByID: contentsByID
    )
  }

  static func refreshProjectReadModels(
    for project: OutlinerProject,
    context: ModelContext,
    projectRecord: ProjectRecord,
    contentsByID: [UUID: TaskContent]
  ) throws {
    let contentIDs = Set(project.document.flatten().map(\.node.canonicalID))
    let attachmentCountsByOwnerID = try attachmentCounts(taskIDs: contentIDs, context: context)
    let scheduleEntries = buildScheduleSliceEntries(
      for: project,
      projectRecord: projectRecord,
      contentsByID: contentsByID,
      attachmentCountsByOwnerID: attachmentCountsByOwnerID
    )
    let latestTaskUpdatedAt = contentIDs.compactMap { contentsByID[$0]?.localUpdatedAt }.max()
    projectRecord.projectSummaryRecord = buildProjectSummary(
      from: scheduleEntries,
      projectRecord: projectRecord,
      latestTaskUpdatedAt: latestTaskUpdatedAt
    )
  }

  static func refreshProjectReadModelsIncrementally(
    for project: OutlinerProject,
    changedTaskIDs: Set<UUID>,
    context: ModelContext,
    projectRecord: ProjectRecord,
    contentsByID: [UUID: TaskContent]
  ) throws {
    let descriptors = taskScheduleDescriptors(in: project)
    let activeTaskIDs = Set(descriptors.map(\.contentID))
    let effectiveChangedTaskIDs = changedTaskIDs.intersection(activeTaskIDs)
    guard !effectiveChangedTaskIDs.isEmpty else { return }

    let attachmentCountsByOwnerID = try attachmentCounts(
      taskIDs: activeTaskIDs,
      context: context
    )
    let mergedScheduleEntries = descriptors.map { descriptor in
      return buildScheduleSliceEntry(
        descriptor: descriptor,
        projectRecord: projectRecord,
        content: contentsByID[descriptor.contentID],
        attachmentCount: attachmentCountsByOwnerID[descriptor.contentID]
          ?? contentsByID[descriptor.contentID]?.attachmentCount
          ?? 0
      )
    }

    let latestTaskUpdatedAt = activeTaskIDs.compactMap { contentsByID[$0]?.localUpdatedAt }.max()
    projectRecord.projectSummaryRecord = buildProjectSummary(
      from: mergedScheduleEntries,
      projectRecord: projectRecord,
      latestTaskUpdatedAt: latestTaskUpdatedAt
    )
  }

  nonisolated static func ensureProjectRecord(
    for projectID: UUID,
    context: ModelContext
  ) throws -> ProjectRecord {
    let descriptor = FetchDescriptor<ProjectRecord>(
      predicate: #Predicate<ProjectRecord> { $0.id == projectID }
    )
    if let existing = try context.fetch(descriptor).first {
      return existing
    }

    let created = ProjectRecord(id: projectID)
    context.insert(created)
    return created
  }

  static func fetchProjectRecord(
    for projectID: UUID,
    context: ModelContext
  ) throws -> ProjectRecord? {
    let descriptor = FetchDescriptor<ProjectRecord>(
      predicate: #Predicate<ProjectRecord> { $0.id == projectID }
    )
    return try context.fetch(descriptor).first
  }

  static func fetchPlacement(
    id: UUID,
    context: ModelContext
  ) throws -> TaskPlacement? {
    let descriptor = FetchDescriptor<TaskPlacement>(
      predicate: #Predicate<TaskPlacement> { $0.id == id }
    )
    return try context.fetch(descriptor).first
  }

  static func fetchAttachment(
    id: UUID,
    context: ModelContext
  ) throws -> AttachmentEntity? {
    let descriptor = FetchDescriptor<AttachmentEntity>(
      predicate: #Predicate<AttachmentEntity> { $0.id == id }
    )
    return try context.fetch(descriptor).first
  }

  static func projectID(
    for taskID: UUID,
    context: ModelContext
  ) throws -> UUID? {
    if let content = try fetchTaskContent(for: taskID, context: context),
      let ownerProjectID = content.reminderOwnerProjectID
    {
      return ownerProjectID
    }

    let descriptor = FetchDescriptor<TaskPlacement>(
      predicate: #Predicate<TaskPlacement> { $0.contentID == taskID }
    )
    if let placement = try context.fetch(descriptor).first {
      return placement.projectID
    }

    return nil
  }

  static func attachmentCounts(
    taskIDs: Set<UUID>,
    context: ModelContext
  ) throws -> [UUID: Int] {
    guard !taskIDs.isEmpty else { return [:] }
    let ownerType = AttachmentOwnerType.task.rawValue
    let identifiers = Array(taskIDs)
    let attachments = try context.fetch(
      FetchDescriptor<AttachmentEntity>(
        predicate: #Predicate {
          $0.ownerTypeRaw == ownerType && identifiers.contains($0.ownerID)
        }
      )
    )
    return attachments.reduce(into: [UUID: Int]()) { result, attachment in
      result[attachment.ownerID, default: 0] += 1
    }
  }

  static func affectedProjectIDs(
    for owner: AttachmentOwner,
    context: ModelContext
  ) throws -> Set<UUID> {
    switch owner {
    case let .project(projectID):
      return [projectID]
    case let .task(taskID):
      guard let projectID = try projectID(for: taskID, context: context) else { return [] }
      return [projectID]
    }
  }

  static func archivedProjectSnapshotForRestore(
    projectRecord: ProjectRecord,
    context: ModelContext
  ) throws -> ReminderArchivedProjectSnapshot {
    ReminderArchivedProjectSnapshot(
      projectID: projectRecord.id,
      title: resolvedProjectTitle(for: projectRecord),
      colorHex: projectRecord.projectColorHex,
      tasks: try archivedTaskSnapshotsForRestore(
        projectID: projectRecord.id,
        context: context
      )
    )
  }

  static func archivedTaskSnapshotsForRestore(
    projectID: UUID,
    context: ModelContext
  ) throws -> [ReminderArchivedTaskSnapshot] {
    let contentIDs = try projectContentIDs(for: projectID, context: context)
    let contentsByID = try fetchTaskContents(for: contentIDs, context: context)
    let placements = try context.fetch(
      FetchDescriptor<TaskPlacement>(
        predicate: #Predicate<TaskPlacement> { $0.projectID == projectID },
        sortBy: [
          SortDescriptor(\.rowOrder, order: .forward),
          SortDescriptor(\.createdAt, order: .forward),
        ]
      )
    )

    return placements.compactMap { placement in
      guard let content = contentsByID[placement.contentID] else { return nil }
      let unifiedReminderDate = ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: content.dueDate,
        startDate: content.startDate
      )
      return ReminderArchivedTaskSnapshot(
        taskID: content.id,
        title: content.title,
        isCompleted: content.isCompleted,
        completionDate: content.completionDate,
        unifiedReminderDate: unifiedReminderDate,
        priority: content.priority,
        reminderNoteText: content.reminderNoteText,
        attachmentCount: content.attachmentCount
      )
    }
  }

  static func resolvedProjectTitle(for record: ProjectRecord) -> String {
    let trimmed = record.projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      return trimmed
    }
    return OutlinerProject.defaultTitle
  }

  static func fetchTaskContents(
    for contentIDs: Set<UUID>,
    context: ModelContext
  ) throws -> [UUID: TaskContent] {
    guard !contentIDs.isEmpty else { return [:] }
    let identifiers = Array(contentIDs)
    let descriptor = FetchDescriptor<TaskContent>(
      predicate: #Predicate<TaskContent> { identifiers.contains($0.id) }
    )
    let contents = try context.fetch(descriptor)
    return Dictionary(uniqueKeysWithValues: contents.map { ($0.id, $0) })
  }

  static func fetchProjectSnapshots(
    for projectIDs: [UUID],
    context: ModelContext
  ) throws -> [UUID: ProjectRecordCanonicalSnapshot] {
    let normalizedProjectIDs = Array(Set(projectIDs))
    guard !normalizedProjectIDs.isEmpty else { return [:] }
    let descriptor = FetchDescriptor<ProjectRecord>(
      predicate: #Predicate<ProjectRecord> { normalizedProjectIDs.contains($0.id) }
    )
    let records = try context.fetch(descriptor)
    return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.canonicalSnapshot) })
  }

  static func fetchAllProjectSnapshots(
    context: ModelContext
  ) throws -> [UUID: ProjectRecordCanonicalSnapshot] {
    let records = try context.fetch(FetchDescriptor<ProjectRecord>())
    return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.canonicalSnapshot) })
  }

  static func fetchProjectSummaries(
    for projectIDs: [UUID],
    context: ModelContext
  ) throws -> [UUID: ProjectSummaryRecord] {
    let normalizedProjectIDs = Array(Set(projectIDs))
    guard !normalizedProjectIDs.isEmpty else { return [:] }
    let descriptor = FetchDescriptor<ProjectRecord>(
      predicate: #Predicate<ProjectRecord> { normalizedProjectIDs.contains($0.id) }
    )
    let records = try context.fetch(descriptor)
    var summaries: [UUID: ProjectSummaryRecord] = [:]
    summaries.reserveCapacity(records.count)
    for record in records {
      guard let summary = record.projectSummaryRecord else { continue }
      summaries[record.id] = summary
    }
    return summaries
  }

  static func fetchAllProjectSummaries(
    context: ModelContext
  ) throws -> [UUID: ProjectSummaryRecord] {
    let records = try context.fetch(FetchDescriptor<ProjectRecord>())
    var summaries: [UUID: ProjectSummaryRecord] = [:]
    summaries.reserveCapacity(records.count)
    for record in records {
      guard let summary = record.projectSummaryRecord else { continue }
      summaries[record.id] = summary
    }
    return summaries
  }

  static func fetchScheduleSliceEntries(
    for projectIDs: [UUID],
    context: ModelContext
  ) throws -> [UUID: [ScheduleSliceEntry]] {
    let normalizedProjectIDs = Array(Set(projectIDs))
    guard !normalizedProjectIDs.isEmpty else { return [:] }
    let descriptor = FetchDescriptor<ProjectScheduleIndexRecord>(
      predicate: #Predicate<ProjectScheduleIndexRecord> { normalizedProjectIDs.contains($0.projectID) }
    )
    let records = try context.fetch(descriptor)
    return Dictionary(uniqueKeysWithValues: records.map { ($0.projectID, $0.entries) })
  }

  static func fetchSearchCorpusEntries(
    for projectIDs: [UUID],
    context: ModelContext
  ) throws -> [UUID: [SearchCorpusEntry]] {
    let normalizedProjectIDs = Array(Set(projectIDs))
    guard !normalizedProjectIDs.isEmpty else { return [:] }
    let descriptor = FetchDescriptor<ProjectSearchIndexRecord>(
      predicate: #Predicate<ProjectSearchIndexRecord> { normalizedProjectIDs.contains($0.projectID) }
    )
    let records = try context.fetch(descriptor)
    return Dictionary(uniqueKeysWithValues: records.map { ($0.projectID, $0.entries) })
  }

  static func ensureProjectScheduleIndexRecord(
    for projectID: UUID,
    context: ModelContext
  ) throws -> ProjectScheduleIndexRecord {
    let descriptor = FetchDescriptor<ProjectScheduleIndexRecord>(
      predicate: #Predicate<ProjectScheduleIndexRecord> { $0.projectID == projectID }
    )
    if let existing = try context.fetch(descriptor).first {
      return existing
    }

    let created = ProjectScheduleIndexRecord(projectID: projectID)
    context.insert(created)
    return created
  }

  static func ensureProjectSearchIndexRecord(
    for projectID: UUID,
    context: ModelContext
  ) throws -> ProjectSearchIndexRecord {
    let descriptor = FetchDescriptor<ProjectSearchIndexRecord>(
      predicate: #Predicate<ProjectSearchIndexRecord> { $0.projectID == projectID }
    )
    if let existing = try context.fetch(descriptor).first {
      return existing
    }

    let created = ProjectSearchIndexRecord(projectID: projectID)
    context.insert(created)
    return created
  }

  private struct TaskScheduleDescriptor {
    let contentID: UUID
    let title: String
    let parentTaskID: UUID?
    let rowOrder: Int
    let isCompleted: Bool
  }

  private static func taskScheduleDescriptors(in project: OutlinerProject) -> [TaskScheduleDescriptor] {
    var descriptors: [TaskScheduleDescriptor] = []

    func visit(nodes: [OutlineNode], parentTaskID: UUID?) {
      for node in nodes {
        let nextParentTaskID = node.type.isTask ? node.canonicalID : parentTaskID
        if node.type.isTask {
          descriptors.append(
            TaskScheduleDescriptor(
              contentID: node.canonicalID,
              title: node.text,
              parentTaskID: parentTaskID,
              rowOrder: descriptors.count,
              isCompleted: node.type.isCompleted
            )
          )
        }
        visit(nodes: node.children, parentTaskID: nextParentTaskID)
      }
    }

    visit(nodes: project.document.rootNodes, parentTaskID: nil)
    return descriptors
  }

  private static func buildScheduleSliceEntry(
    descriptor: TaskScheduleDescriptor,
    projectRecord: ProjectRecord,
    content: TaskContent?,
    attachmentCount: Int
  ) -> ScheduleSliceEntry {
    let displayedDate = ReminderTaskDateCanonicalizer.unifiedDate(
      dueDate: content?.dueDate,
      startDate: content?.startDate
    )
    return ScheduleSliceEntry(
      taskID: descriptor.contentID,
      parentTaskID: descriptor.parentTaskID,
      title: content?.title ?? descriptor.title,
      displayedDate: displayedDate,
      startDate: content?.startDate,
      dueDate: content?.dueDate,
      scheduleHasExplicitTime: content?.scheduleHasExplicitTime ?? false,
      scheduledDurationMinutes: content?.scheduledDurationMinutes,
      isCompleted: content?.isCompleted ?? descriptor.isCompleted,
      completionDate: content?.completionDate,
      recurrenceRuleRaw: content?.recurrenceRuleRaw,
      attachmentCount: attachmentCount,
      reminderNoteText: content?.reminderNoteText ?? "",
      requiredWorkDays: content?.requiredWorkDays ?? 0,
      completedWorkUnits: content?.completedWorkUnits ?? 0,
      completedWorkUnitDates: decodedCompletedWorkUnitDates(
        raw: content?.completedWorkUnitDatesRaw ?? "",
        requiredCount: content?.completedWorkUnits ?? 0,
        defaultDate: content?.completionDate ?? content?.localUpdatedAt ?? projectRecord.updatedAt
      ),
      preparationScheduleOverridesRaw: content?.preparationScheduleOverridesRaw ?? "",
      rowOrder: descriptor.rowOrder,
      priority: content?.priority ?? 0,
      isFlagged: content?.isFlagged ?? false,
      isArchived: projectRecord.isArchived,
      localUpdatedAt: content?.localUpdatedAt ?? projectRecord.updatedAt,
      createdAt: content?.createdAt ?? projectRecord.createdAt
    )
  }

  static func buildScheduleSliceEntries(
    for project: OutlinerProject,
    projectRecord: ProjectRecord,
    contentsByID: [UUID: TaskContent],
    attachmentFilenamesByOwnerID: [UUID: [String]]
  ) -> [ScheduleSliceEntry] {
    buildScheduleSliceEntries(
      for: project,
      projectRecord: projectRecord,
      contentsByID: contentsByID,
      attachmentCountsByOwnerID: attachmentFilenamesByOwnerID.mapValues(\.count)
    )
  }

  static func buildScheduleSliceEntries(
    for project: OutlinerProject,
    projectRecord: ProjectRecord,
    contentsByID: [UUID: TaskContent],
    attachmentCountsByOwnerID: [UUID: Int]
  ) -> [ScheduleSliceEntry] {
    taskScheduleDescriptors(in: project).map { descriptor in
      buildScheduleSliceEntry(
        descriptor: descriptor,
        projectRecord: projectRecord,
        content: contentsByID[descriptor.contentID],
        attachmentCount: attachmentCountsByOwnerID[descriptor.contentID]
          ?? contentsByID[descriptor.contentID]?.attachmentCount
          ?? 0
      )
    }
  }

  private static func buildProjectSearchCorpusEntry(
    for project: OutlinerProject,
    projectRecord: ProjectRecord,
    attachmentFilenames: [String]
  ) -> SearchCorpusEntry {
    let resolvedTitle = resolvedProjectTitle(for: projectRecord)
    let projectCandidates: [SearchCorpusCandidateRecord] = [
      SearchCorpusCandidateRecord(kind: .projectTitle, fieldText: resolvedTitle, preview: resolvedTitle),
      SearchCorpusCandidateRecord(
        kind: .projectNote,
        fieldText: projectRecord.noteMarkdown,
        preview: projectRecord.noteMarkdown
      ),
    ] + attachmentFilenames.map {
      SearchCorpusCandidateRecord(kind: .projectAttachment, fieldText: $0, preview: $0)
    }

    return SearchCorpusEntry(
      id: "workspace-project-\(project.id.uuidString)",
      entityKindRaw: WorkspaceSearchEntityKind.project.rawValue,
      dispositionRaw: (
        projectRecord.isArchived
          ? WorkspaceSearchResultDisposition.archivedProject
          : .regular
      ).rawValue,
      projectID: project.id,
      taskID: nil,
      title: resolvedTitle,
      subtitlePrefix: resolvedTitle,
      candidates: projectCandidates,
      corpus: ([resolvedTitle, projectRecord.noteMarkdown] + attachmentFilenames)
        .joined(separator: "\n"),
      isExcludedFromSearch: false
    )
  }

  private static func buildTaskSearchCorpusEntry(
    task: ScheduleSliceEntry,
    project: OutlinerProject,
    projectRecord: ProjectRecord,
    attachmentFilenames: [String]
  ) -> SearchCorpusEntry {
    let resolvedTitle = resolvedProjectTitle(for: projectRecord)
    let displayTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "제목 없는 할일"
      : task.title
    let taskCandidates: [SearchCorpusCandidateRecord] = [
      SearchCorpusCandidateRecord(kind: .taskTitle, fieldText: task.title, preview: task.title),
      SearchCorpusCandidateRecord(
        kind: .taskReminderNote,
        fieldText: task.reminderNoteText,
        preview: task.reminderNoteText
      ),
    ] + attachmentFilenames.map {
      SearchCorpusCandidateRecord(kind: .taskAttachment, fieldText: $0, preview: $0)
    }

    return SearchCorpusEntry(
      id: "workspace-task-\(task.taskID.uuidString)",
      entityKindRaw: WorkspaceSearchEntityKind.task.rawValue,
      dispositionRaw: (
        task.isCompleted
          ? WorkspaceSearchResultDisposition.completedTask
          : .regular
      ).rawValue,
      projectID: project.id,
      taskID: task.taskID,
      title: displayTitle,
      subtitlePrefix: resolvedTitle,
      candidates: taskCandidates,
      corpus: ([task.title, task.reminderNoteText] + attachmentFilenames)
        .joined(separator: "\n"),
      isExcludedFromSearch: task.isCompleted
        && !(task.recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    )
  }

  static func buildSearchCorpusEntries(
    for project: OutlinerProject,
    projectRecord: ProjectRecord,
    scheduleEntries: [ScheduleSliceEntry],
    attachmentFilenamesByOwnerID: [UUID: [String]]
  ) -> [SearchCorpusEntry] {
    var entries: [SearchCorpusEntry] = [
      buildProjectSearchCorpusEntry(
        for: project,
        projectRecord: projectRecord,
        attachmentFilenames: attachmentFilenamesByOwnerID[project.id] ?? []
      )
    ]

    guard !projectRecord.isArchived else { return entries }

    for task in scheduleEntries {
      entries.append(
        buildTaskSearchCorpusEntry(
          task: task,
          project: project,
          projectRecord: projectRecord,
          attachmentFilenames: attachmentFilenamesByOwnerID[task.taskID] ?? []
        )
      )
    }

    return entries
  }

  static func fetchAttachmentFilenamesByOwnerID(
    ownerIDs: Set<UUID>,
    context: ModelContext
  ) throws -> [UUID: [String]] {
    guard !ownerIDs.isEmpty else { return [:] }
    let attachmentDescriptor = FetchDescriptor<AttachmentEntity>(
      predicate: #Predicate<AttachmentEntity> { ownerIDs.contains($0.ownerID) && !$0.isArchived }
    )
    let attachments = try context.fetch(attachmentDescriptor)
    var filenamesByOwnerID: [UUID: [String]] = [:]
    for attachment in attachments {
      filenamesByOwnerID[attachment.ownerID, default: []].append(attachment.originalFilename)
    }
    return filenamesByOwnerID
  }

  private static func linkedWorkspaceProjectNodes(
    projectRecord: ProjectRecord,
    repository: WorkspaceTreeRepository
  ) async throws -> [WorkspaceNodeRecord] {
    try await repository.fetchProjectNodes(
      canonicalProjectID: projectRecord.id,
      includeArchived: true
    )
  }

  static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
