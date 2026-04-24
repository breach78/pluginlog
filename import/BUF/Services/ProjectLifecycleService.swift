import Foundation
import SwiftData

enum ProjectLifecycleServiceError: LocalizedError {
  case runtimeProjectMissing(UUID)
  case reminderListIdentityMissing(UUID)
  case reminderSnapshotMissing(UUID)
  case archiveBundleUnavailable(UUID)
  case restoredReminderIdentityMissing(UUID)

  var errorDescription: String? {
    switch self {
    case let .runtimeProjectMissing(projectID):
      return "프로젝트 source snapshot을 찾지 못했습니다. (\(projectID.uuidString))"
    case let .reminderListIdentityMissing(projectID):
      return "프로젝트 reminder list identity를 찾지 못했습니다. (\(projectID.uuidString))"
    case let .reminderSnapshotMissing(taskID):
      return "할일 reminder snapshot을 찾지 못했습니다. (\(taskID.uuidString))"
    case let .archiveBundleUnavailable(projectID):
      return "아카이브 번들을 찾지 못했습니다. (\(projectID.uuidString))"
    case let .restoredReminderIdentityMissing(taskID):
      return "복원된 reminder identity를 찾지 못했습니다. (\(taskID.uuidString))"
    }
  }
}

struct ProjectLifecycleCreateResult {
  let projectID: UUID
  let reminderListIdentifier: String
  let reminderListExternalIdentifier: String
  let didMutateWorkspaceTree: Bool
}

struct ProjectLifecycleArchiveResult {
  let archivedProjectID: UUID
  let reminderListExternalIdentifier: String
  let taskReminderExternalIdentifiers: [String]
}

struct ProjectLifecycleRestoreResult {
  let archivedProjectID: UUID
  let restoredProjectID: UUID
  let reminderListIdentifier: String
  let reminderListExternalIdentifier: String
  let archiveBundle: ArchivedProjectBundle
  let restoredTaskIdentities: [RestoredArchivedTaskIdentity]
}

struct ProjectLifecycleDeleteResult {
  let deletedProjectID: UUID
  let deletedWorkspaceNodeIDs: Set<UUID>
  let reminderListExternalIdentifier: String
  let taskReminderExternalIdentifiers: [String]
}

struct RestoredArchivedTaskIdentity: Sendable, Equatable {
  let archivedTaskID: UUID
  let restoredTaskID: UUID
  let reminderIdentifier: String
  let reminderExternalIdentifier: String
}

@MainActor
enum ProjectLifecycleService {
  static func createProject(
    title rawTitle: String,
    parentNodeID: UUID? = nil,
    reminderProjectProvider: ReminderProjectProvider,
    workspaceTreeRepository: WorkspaceTreeRepository?,
    historyContext: ModelContext? = nil
  ) async throws -> ProjectLifecycleCreateResult? {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }

    let granted = try await reminderProjectProvider.requestAccess()
    guard granted else { return nil }

    let list = try reminderProjectProvider.createProjectList(title: title)
    let projectID = ReminderProjectionIdentity.projectID(for: list.externalIdentifier)
    var didMutateWorkspaceTree = false

    if let workspaceTreeRepository,
      try await workspaceTreeRepository.fetchProjectNodes(
        canonicalProjectID: projectID,
        includeArchived: true
      ).isEmpty
    {
      _ = try await workspaceTreeRepository.createProject(
        title: list.title,
        parentID: parentNodeID,
        colorHex: list.colorHex,
        canonicalProjectID: projectID,
        reminderListIdentifier: list.identifier,
        reminderListExternalIdentifier: list.externalIdentifier
      )
      didMutateWorkspaceTree = true
    }

    if let historyContext {
      ProjectHistoryService.recordProjectCreated(
        projectID: projectID,
        projectTitle: list.title,
        in: historyContext
      )
      try ProjectDocumentStore.saveWithSyncPerformanceCounter(historyContext)
    }

    return ProjectLifecycleCreateResult(
      projectID: projectID,
      reminderListIdentifier: list.identifier,
      reminderListExternalIdentifier: list.externalIdentifier,
      didMutateWorkspaceTree: didMutateWorkspaceTree
    )
  }

  static func archiveProject(
    projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    sidecarPayload: ReminderProjectionSidecarPayload,
    modelContainer: ModelContainer,
    reminderProjectProvider: ReminderProjectProvider,
    archiveBundleStore: ArchivedProjectBundleStore?,
    attachmentStore: AttachmentStore?,
    workspaceTreeRepository: WorkspaceTreeRepository?
  ) async throws -> ProjectLifecycleArchiveResult {
    let projectState = try activeProjectState(
      projectID: projectID,
      runtimeSnapshot: runtimeSnapshot
    )
    let archiveBundle = try await buildArchiveBundle(
      from: projectState,
      reminderProjectProvider: reminderProjectProvider,
      sidecarPayload: sidecarPayload,
      workspaceTreeRepository: workspaceTreeRepository
    )
    try archiveBundleStore?.save(archiveBundle)

    try reminderProjectProvider.removeProjectList(identifier: projectState.reminderListIdentifier)

    let context = ModelContext(modelContainer)
    try archiveAttachments(
      projectID: projectID,
      taskIDs: archiveBundle.taskBundles.map(\.archivedTaskID),
      attachmentStore: attachmentStore,
      context: context
    )
    try await archiveWorkspaceNodes(
      nodeIDs: archiveBundle.workspaceNodeIDs,
      repository: workspaceTreeRepository
    )
    try deleteCanonicalProjectState(
      projectID: projectID,
      context: context
    )
    ProjectHistoryService.recordProjectArchived(
      projectID: projectID,
      projectTitle: archiveBundle.title,
      occurredAt: archiveBundle.archivedAt,
      in: context
    )
    try ProjectDocumentStore.saveWithSyncPerformanceCounter(context)
    clearTaskIdentityBridge(for: archiveBundle.taskBundles)

    return ProjectLifecycleArchiveResult(
      archivedProjectID: projectID,
      reminderListExternalIdentifier: archiveBundle.reminderListExternalIdentifier,
      taskReminderExternalIdentifiers: archiveBundle.taskBundles.map(\.reminderExternalIdentifier)
    )
  }

  static func restoreProject(
    archivedProjectID: UUID,
    modelContainer: ModelContainer,
    reminderProjectProvider: ReminderProjectProvider,
    archiveBundleStore: ArchivedProjectBundleStore?,
    mirrorPlacementStore: TaskMirrorPlacementStore?,
    attachmentStore: AttachmentStore?,
    workspaceTreeRepository: WorkspaceTreeRepository?
  ) async throws -> ProjectLifecycleRestoreResult {
    guard let archiveBundle = archiveBundleStore?.bundle(for: archivedProjectID) else {
      throw ProjectLifecycleServiceError.archiveBundleUnavailable(archivedProjectID)
    }

    let restoreResult = try reminderProjectProvider.restoreArchivedProject(
      reminderArchivedProjectSnapshot(from: archiveBundle)
    )
    let restoredProjectID = ReminderProjectionIdentity.projectID(
      for: restoreResult.list.externalIdentifier
    )
    let restoredTaskIdentityMap = try restoredTaskIdentities(
      taskBundles: archiveBundle.taskBundles,
      restoreResult: restoreResult,
      restoredProjectID: restoredProjectID
    )

    if let mirrorPlacementStore {
      try await remapMirrorPlacementsForRestoredProject(
        archiveBundle: archiveBundle,
        restoreResult: restoreResult,
        restoredTaskIdentityMap: restoredTaskIdentityMap,
        mirrorPlacementStore: mirrorPlacementStore
      )
    }

    let context = ModelContext(modelContainer)
    try restoreAttachments(
      archiveBundle: archiveBundle,
      restoredProjectID: restoredProjectID,
      restoredTaskIdentityMap: restoredTaskIdentityMap,
      attachmentStore: attachmentStore,
      context: context
    )
    try await restoreWorkspaceNodes(
      archiveBundle: archiveBundle,
      restoredProjectID: restoredProjectID,
      restoreResult: restoreResult,
      repository: workspaceTreeRepository
    )
    ProjectHistoryService.recordProjectRestored(
      projectID: restoredProjectID,
      projectTitle: restoreResult.list.title,
      in: context
    )
    try ProjectDocumentStore.saveWithSyncPerformanceCounter(context)
    clearTaskIdentityBridge(for: archiveBundle.taskBundles)
    restoredTaskIdentityMap.values.forEach { identity in
      TaskIdentityBridgeStore.upsert(
        taskID: identity.taskID,
        reminderExternalIdentifier: identity.reminderExternalIdentifier,
        ownerProjectID: restoredProjectID
      )
    }
    try archiveBundleStore?.remove(projectID: archivedProjectID)

    return ProjectLifecycleRestoreResult(
      archivedProjectID: archivedProjectID,
      restoredProjectID: restoredProjectID,
      reminderListIdentifier: restoreResult.list.identifier,
      reminderListExternalIdentifier: restoreResult.list.externalIdentifier,
      archiveBundle: archiveBundle,
      restoredTaskIdentities: restoredTaskIdentityMap.values
        .sorted { $0.archivedTaskID.uuidString < $1.archivedTaskID.uuidString }
        .map { identity in
          RestoredArchivedTaskIdentity(
            archivedTaskID: identity.archivedTaskID,
            restoredTaskID: identity.taskID,
            reminderIdentifier: identity.reminderIdentifier,
            reminderExternalIdentifier: identity.reminderExternalIdentifier
          )
        }
    )
  }

  static func deleteProject(
    projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    modelContainer: ModelContainer,
    reminderProjectProvider: ReminderProjectProvider,
    archiveBundleStore: ArchivedProjectBundleStore?,
    mirrorPlacementStore: TaskMirrorPlacementStore?,
    attachmentStore: AttachmentStore?,
    workspaceTreeRepository: WorkspaceTreeRepository?
  ) async throws -> ProjectLifecycleDeleteResult {
    let archiveBundle = archiveBundleStore?.bundle(for: projectID)
    let activeProjectState = try activeProjectStateIfAvailable(
      projectID: projectID,
      runtimeSnapshot: runtimeSnapshot
    )
    let deletionReference =
      try await deletionReference(
        requestedProjectID: projectID,
        activeProjectState: activeProjectState,
        archiveBundle: archiveBundle,
        workspaceTreeRepository: workspaceTreeRepository
      )

    if let reminderListIdentifier = deletionReference.activeReminderListIdentifier {
      try reminderProjectProvider.removeProjectList(identifier: reminderListIdentifier)
    }

    let context = ModelContext(modelContainer)
    try deleteAttachmentsPermanently(
      projectID: deletionReference.projectID,
      taskIDs: deletionReference.taskIDs,
      attachmentStore: attachmentStore,
      context: context
    )
    try await removeMirrorPlacements(
      deletionReference: deletionReference,
      mirrorPlacementStore: mirrorPlacementStore
    )
    try deleteCanonicalProjectState(
      projectID: deletionReference.projectID,
      context: context
    )
    ProjectHistoryService.recordProjectDeleted(
      projectID: deletionReference.projectID,
      projectTitle: deletionReference.title,
      taskCount: deletionReference.taskIDs.count,
      in: context
    )
    try ProjectDocumentStore.saveWithSyncPerformanceCounter(context)
    clearTaskIdentityBridge(
      reminderExternalIdentifiers: deletionReference.taskReminderExternalIdentifiers,
      taskIDs: deletionReference.taskIDs
    )

    let deletedWorkspaceNodeIDs =
      try await deleteWorkspaceNodes(
        nodeIDs: deletionReference.workspaceNodeIDs,
        repository: workspaceTreeRepository
      )
    try archiveBundleStore?.remove(projectID: projectID)

    return ProjectLifecycleDeleteResult(
      deletedProjectID: deletionReference.projectID,
      deletedWorkspaceNodeIDs: deletedWorkspaceNodeIDs,
      reminderListExternalIdentifier: deletionReference.reminderListExternalIdentifier,
      taskReminderExternalIdentifiers: deletionReference.taskReminderExternalIdentifiers
    )
  }

  private struct ActiveProjectState {
    let project: OutlinerProject
    let title: String
    let colorHex: String?
    let reminderListIdentifier: String
    let reminderListExternalIdentifier: String
  }

  private struct DeletionReference {
    let projectID: UUID
    let title: String
    let activeReminderListIdentifier: String?
    let reminderListExternalIdentifier: String
    let taskIDs: [UUID]
    let taskReminderExternalIdentifiers: [String]
    let workspaceNodeIDs: [UUID]
  }

  private struct RestoredTaskIdentity {
    let archivedTaskID: UUID
    let taskID: UUID
    let reminderIdentifier: String
    let reminderExternalIdentifier: String
  }

  private static func activeProjectState(
    projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?
  ) throws -> ActiveProjectState {
    guard let activeProjectState = try activeProjectStateIfAvailable(
      projectID: projectID,
      runtimeSnapshot: runtimeSnapshot
    ) else {
      throw ProjectLifecycleServiceError.runtimeProjectMissing(projectID)
    }
    return activeProjectState
  }

  private static func activeProjectStateIfAvailable(
    projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?
  ) throws -> ActiveProjectState? {
    guard let runtimeSnapshot,
      let project = runtimeSnapshot.projects.first(where: { $0.id == projectID })
    else {
      return nil
    }

    let title = project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? OutlinerProject.defaultTitle
      : project.title
    guard
      let reminderListIdentifier = normalized(
        runtimeSnapshot.projectReminderListIdentifierByProjectID[project.id]
      ),
      let reminderListExternalIdentifier = normalized(
        runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[project.id]
      )
    else {
      throw ProjectLifecycleServiceError.reminderListIdentityMissing(projectID)
    }

    return ActiveProjectState(
      project: project,
      title: title,
      colorHex: runtimeSnapshot.projectColorHexByProjectID[project.id],
      reminderListIdentifier: reminderListIdentifier,
      reminderListExternalIdentifier: reminderListExternalIdentifier
    )
  }

  private static func buildArchiveBundle(
    from state: ActiveProjectState,
    reminderProjectProvider: ReminderProjectProvider,
    sidecarPayload: ReminderProjectionSidecarPayload,
    workspaceTreeRepository: WorkspaceTreeRepository?
  ) async throws -> ArchivedProjectBundle {
    let payload = sidecarPayload
    let sourceTaskNodes = sourceTaskNodes(in: state.project)
    let taskBundles = try sourceTaskNodes.map { node in
      let reference = ReminderTaskReference(
        taskID: node.canonicalID,
        reminderIdentifier: normalized(node.reminderIdentifier),
        reminderExternalIdentifier: normalized(node.reminderExternalIdentifier)
      )
      guard let snapshot = try reminderProjectProvider.taskSnapshot(for: reference) else {
        throw ProjectLifecycleServiceError.reminderSnapshotMissing(node.canonicalID)
      }
      return ArchivedProjectTaskBundle(
        archivedTaskID: node.canonicalID,
        reminderIdentifier: snapshot.identifier,
        reminderExternalIdentifier: snapshot.externalIdentifier ?? snapshot.identifier,
        title: snapshot.title,
        isCompleted: snapshot.isCompleted,
        completionDate: snapshot.completionDate,
        unifiedReminderDate: ReminderTaskDateCanonicalizer.unifiedDate(
          dueDate: snapshot.dueDate,
          startDate: snapshot.startDate
        ),
        priority: snapshot.priority,
        reminderNoteText: snapshot.noteText
      )
    }

    let taskExternalIdentifierByTaskID = Dictionary(
      uniqueKeysWithValues: taskBundles.map { ($0.archivedTaskID, $0.reminderExternalIdentifier) }
    )
    let taskFeatureSidecarByTaskID = taskExternalIdentifierByTaskID.reduce(
      into: [UUID: ReminderTaskFeatureSidecarRecord]()
    ) { partialResult, entry in
      if let record = payload.taskFeatureSidecarByReminderExternalIdentifier[entry.value] {
        partialResult[entry.key] = record
      }
    }
    let workspaceNodeIDs =
      try await workspaceTreeRepository?.fetchProjectNodes(
        canonicalProjectID: state.project.id,
        includeArchived: true
      ).map(\.id) ?? []
    let workspaceOrderIndex = payload.workspaceStructureRecord?.orderedReminderListExternalIdentifiers
      .firstIndex(of: state.reminderListExternalIdentifier)

    return ArchivedProjectBundle(
      archivedProjectID: state.project.id,
      title: state.title,
      colorHex: state.colorHex,
      archivedAt: .now,
      reminderListIdentifier: state.reminderListIdentifier,
      reminderListExternalIdentifier: state.reminderListExternalIdentifier,
      workspaceNodeIDs: workspaceNodeIDs,
      workspaceOrderIndex: workspaceOrderIndex,
      projectRootStructure: payload.projectRootStructureByReminderListExternalIdentifier[
        state.reminderListExternalIdentifier
      ],
      projectTaskOrder: payload.projectTaskOrderByReminderListExternalIdentifier[
        state.reminderListExternalIdentifier
      ],
      projectFeature: payload.projectFeatureSidecarByReminderListExternalIdentifier[
        state.reminderListExternalIdentifier
      ],
      taskBundles: taskBundles,
      taskFeatureSidecarByTaskID: taskFeatureSidecarByTaskID,
      taskSourceRuntimeStateByTaskID: [:]
    )
  }

  private static func reminderArchivedProjectSnapshot(
    from bundle: ArchivedProjectBundle
  ) -> ReminderArchivedProjectSnapshot {
    ReminderArchivedProjectSnapshot(
      projectID: bundle.archivedProjectID,
      title: bundle.title,
      colorHex: bundle.colorHex,
      tasks: bundle.taskBundles.map { task in
        ReminderArchivedTaskSnapshot(
          taskID: task.archivedTaskID,
          title: task.title,
          isCompleted: task.isCompleted,
          completionDate: task.completionDate,
          unifiedReminderDate: task.unifiedReminderDate,
          priority: task.priority,
          reminderNoteText: task.reminderNoteText,
          attachmentCount: 0
        )
      }
    )
  }

  private static func restoredTaskIdentities(
    taskBundles: [ArchivedProjectTaskBundle],
    restoreResult: ReminderProjectRestoreResult,
    restoredProjectID: UUID
  ) throws -> [UUID: RestoredTaskIdentity] {
    try taskBundles.reduce(into: [UUID: RestoredTaskIdentity]()) { partialResult, task in
      guard let metadata = restoreResult.taskMetadataByTaskID[task.archivedTaskID],
        let restoredReminderIdentifier = normalized(metadata.identifier),
        let restoredReminderExternalIdentifier = normalized(
          metadata.externalIdentifier ?? metadata.identifier
        )
      else {
        throw ProjectLifecycleServiceError.restoredReminderIdentityMissing(task.archivedTaskID)
      }

      partialResult[task.archivedTaskID] = RestoredTaskIdentity(
        archivedTaskID: task.archivedTaskID,
        taskID: ReminderProjectionIdentity.taskID(for: restoredReminderExternalIdentifier),
        reminderIdentifier: restoredReminderIdentifier,
        reminderExternalIdentifier: restoredReminderExternalIdentifier
      )
    }
  }

  static func restoredPayload(
    from archiveBundle: ArchivedProjectBundle,
    restoredReminderListExternalIdentifier: String,
    restoredTaskIdentities: [RestoredArchivedTaskIdentity],
    payload: ReminderProjectionSidecarPayload
  ) -> ReminderProjectionSidecarPayload {
    var updatedPayload = payload
    let newReminderListExternalIdentifier = restoredReminderListExternalIdentifier
    let oldReminderListExternalIdentifier = archiveBundle.reminderListExternalIdentifier
    let restoredReminderExternalIdentifierByArchivedTaskID = Dictionary(
      uniqueKeysWithValues: restoredTaskIdentities.map {
        ($0.archivedTaskID, $0.reminderExternalIdentifier)
      }
    )

    var orderedIdentifiers = updatedPayload.workspaceStructureRecord?.orderedReminderListExternalIdentifiers ?? []
    orderedIdentifiers.removeAll { $0 == oldReminderListExternalIdentifier }
    let insertionIndex = min(
      max(0, archiveBundle.workspaceOrderIndex ?? orderedIdentifiers.count),
      orderedIdentifiers.count
    )
    orderedIdentifiers.insert(newReminderListExternalIdentifier, at: insertionIndex)
    updatedPayload.workspaceStructureRecord = workspaceStructureRecord(
      orderedReminderListExternalIdentifiers: orderedIdentifiers,
      existing: updatedPayload.workspaceStructureRecord
    )

    if var projectRootStructure = archiveBundle.projectRootStructure {
      projectRootStructure.reminderListExternalIdentifier = newReminderListExternalIdentifier
      projectRootStructure.rootNodes = projectRootStructure.rootNodes.map {
        remappedRootNode(
          $0,
          restoredReminderExternalIdentifierByArchivedTaskID:
            restoredReminderExternalIdentifierByArchivedTaskID,
          archivedTaskBundles: archiveBundle.taskBundles
        )
      }
      updatedPayload.projectRootStructureByReminderListExternalIdentifier[
        newReminderListExternalIdentifier
      ] = projectRootStructure
    }

    if var projectTaskOrder = archiveBundle.projectTaskOrder {
      projectTaskOrder.reminderListExternalIdentifier = newReminderListExternalIdentifier
      projectTaskOrder.orderedTopLevelReminderExternalIdentifiersRaw = ReminderProjectionOrderCodec.encode(
        ReminderProjectionOrderCodec.decode(projectTaskOrder.orderedTopLevelReminderExternalIdentifiersRaw).map {
          remappedReminderExternalIdentifier(
            $0,
            restoredReminderExternalIdentifierByArchivedTaskID:
              restoredReminderExternalIdentifierByArchivedTaskID,
            archivedTaskBundles: archiveBundle.taskBundles
          ) ?? $0
        }
      )
      updatedPayload.projectTaskOrderByReminderListExternalIdentifier[
        newReminderListExternalIdentifier
      ] = projectTaskOrder
    }

    if var projectFeature = archiveBundle.projectFeature {
      projectFeature.reminderListExternalIdentifier = newReminderListExternalIdentifier
      updatedPayload.projectFeatureSidecarByReminderListExternalIdentifier[
        newReminderListExternalIdentifier
      ] = projectFeature
    }

    for taskBundle in archiveBundle.taskBundles {
      guard let restoredIdentity = restoredTaskIdentities.first(where: {
        $0.archivedTaskID == taskBundle.archivedTaskID
      }) else { continue }
      if var taskFeature = archiveBundle.taskFeatureSidecarByTaskID[taskBundle.archivedTaskID] {
        taskFeature.reminderExternalIdentifier = restoredIdentity.reminderExternalIdentifier
        updatedPayload.taskFeatureSidecarByReminderExternalIdentifier[
          restoredIdentity.reminderExternalIdentifier
        ] = taskFeature
      }
    }

    return updatedPayload
  }

  private static func remappedRootNode(
    _ node: ReminderProjectRootNodeRecord,
    restoredReminderExternalIdentifierByArchivedTaskID: [UUID: String],
    archivedTaskBundles: [ArchivedProjectTaskBundle]
  ) -> ReminderProjectRootNodeRecord {
    switch node {
    case let .task(reminderExternalIdentifier, indent):
      guard let remappedReminderExternalIdentifier = remappedReminderExternalIdentifier(
        reminderExternalIdentifier,
        restoredReminderExternalIdentifierByArchivedTaskID: restoredReminderExternalIdentifierByArchivedTaskID,
        archivedTaskBundles: archivedTaskBundles
      ) else {
        return node
      }
      return .task(reminderExternalIdentifier: remappedReminderExternalIdentifier, indent: indent)

    case let .mirror(reminderExternalIdentifier, indent):
      guard let remappedReminderExternalIdentifier = remappedReminderExternalIdentifier(
        reminderExternalIdentifier,
        restoredReminderExternalIdentifierByArchivedTaskID: restoredReminderExternalIdentifierByArchivedTaskID,
        archivedTaskBundles: archivedTaskBundles
      ) else {
        return node
      }
      return .mirror(
        reminderExternalIdentifier: remappedReminderExternalIdentifier,
        indent: indent
      )

    case .bullet:
      return node
    }
  }

  private static func remappedReminderExternalIdentifier(
    _ reminderExternalIdentifier: String,
    restoredReminderExternalIdentifierByArchivedTaskID: [UUID: String],
    archivedTaskBundles: [ArchivedProjectTaskBundle]
  ) -> String? {
    guard
      let archivedTaskID = archivedTaskBundles.first(where: {
        $0.reminderExternalIdentifier == reminderExternalIdentifier
      })?.archivedTaskID
    else {
      return nil
    }
    return restoredReminderExternalIdentifierByArchivedTaskID[archivedTaskID]
  }

  private static func archiveAttachments(
    projectID: UUID,
    taskIDs: [UUID],
    attachmentStore: AttachmentStore?,
    context: ModelContext
  ) throws {
    guard let attachmentStore else { return }
    for attachment in try attachments(ownerType: .project, ownerIDs: [projectID], context: context)
      where !attachment.isArchived
    {
      try attachmentStore.moveToArchive(attachment, in: context)
    }
    for attachment in try attachments(ownerType: .task, ownerIDs: taskIDs, context: context)
      where !attachment.isArchived
    {
      try attachmentStore.moveToArchive(attachment, in: context)
    }
  }

  private static func restoreAttachments(
    archiveBundle: ArchivedProjectBundle,
    restoredProjectID: UUID,
    restoredTaskIdentityMap: [UUID: RestoredTaskIdentity],
    attachmentStore: AttachmentStore?,
    context: ModelContext
  ) throws {
    guard let attachmentStore else { return }

    for attachment in try attachments(
      ownerType: .project,
      ownerIDs: [archiveBundle.archivedProjectID],
      context: context
    ) where attachment.isArchived {
      attachment.ownerID = restoredProjectID
      try attachmentStore.restoreFromArchive(attachment, in: context)
    }

    for taskBundle in archiveBundle.taskBundles {
      guard let restoredIdentity = restoredTaskIdentityMap[taskBundle.archivedTaskID] else { continue }
      for attachment in try attachments(
        ownerType: .task,
        ownerIDs: [taskBundle.archivedTaskID],
        context: context
      ) where attachment.isArchived {
        attachment.ownerID = restoredIdentity.taskID
        try attachmentStore.restoreFromArchive(attachment, in: context)
      }
    }
  }

  private static func deleteAttachmentsPermanently(
    projectID: UUID,
    taskIDs: [UUID],
    attachmentStore: AttachmentStore?,
    context: ModelContext
  ) throws {
    guard let attachmentStore else { return }
    for attachment in try attachments(ownerType: .project, ownerIDs: [projectID], context: context) {
      try attachmentStore.deletePermanent(attachment, in: context)
    }
    for attachment in try attachments(ownerType: .task, ownerIDs: taskIDs, context: context) {
      try attachmentStore.deletePermanent(attachment, in: context)
    }
  }

  private static func attachments(
    ownerType: AttachmentOwnerType,
    ownerIDs: [UUID],
    context: ModelContext
  ) throws -> [AttachmentEntity] {
    let normalizedOwnerIDs = Array(Set(ownerIDs))
    guard !normalizedOwnerIDs.isEmpty else { return [] }
    let ownerTypeRaw = ownerType.rawValue
    return try context.fetch(
      FetchDescriptor<AttachmentEntity>(
        predicate: #Predicate {
          $0.ownerTypeRaw == ownerTypeRaw && normalizedOwnerIDs.contains($0.ownerID)
        }
      )
    )
  }

  private static func archiveWorkspaceNodes(
    nodeIDs: [UUID],
    repository: WorkspaceTreeRepository?
  ) async throws {
    guard let repository else { return }
    for nodeID in nodeIDs {
      try await repository.archiveSubtree(nodeID)
    }
  }

  private static func restoreWorkspaceNodes(
    archiveBundle: ArchivedProjectBundle,
    restoredProjectID: UUID,
    restoreResult: ReminderProjectRestoreResult,
    repository: WorkspaceTreeRepository?
  ) async throws {
    guard let repository else { return }

    let archivedNodes = try await repository.fetchProjectNodes(
      canonicalProjectID: archiveBundle.archivedProjectID,
      includeArchived: true
    )
    if archivedNodes.isEmpty {
      _ = try await repository.createProject(
        title: restoreResult.list.title,
        colorHex: restoreResult.list.colorHex,
        canonicalProjectID: restoredProjectID,
        reminderListIdentifier: restoreResult.list.identifier,
        reminderListExternalIdentifier: restoreResult.list.externalIdentifier
      )
      return
    }

    for node in archivedNodes {
      _ = try await repository.relinkProjectIdentity(
        of: node.id,
        canonicalProjectID: restoredProjectID,
        title: restoreResult.list.title,
        colorHex: restoreResult.list.colorHex,
        reminderListIdentifier: restoreResult.list.identifier,
        reminderListExternalIdentifier: restoreResult.list.externalIdentifier
      )
      try await repository.restoreSubtree(node.id)
    }
  }

  private static func deleteWorkspaceNodes(
    nodeIDs: [UUID],
    repository: WorkspaceTreeRepository?
  ) async throws -> Set<UUID> {
    guard let repository else { return [] }
    return try await repository.deleteSubtreesPermanently(rootNodeIDs: nodeIDs)
  }

  private static func remapMirrorPlacementsForRestoredProject(
    archiveBundle: ArchivedProjectBundle,
    restoreResult: ReminderProjectRestoreResult,
    restoredTaskIdentityMap: [UUID: RestoredTaskIdentity],
    mirrorPlacementStore: TaskMirrorPlacementStore
  ) async throws {
    let archivedReminderExternalIdentifiers = archiveBundle.taskBundles.map(\.reminderExternalIdentifier)
    let restoredReminderExternalIdentifiersByArchived = Dictionary(
      uniqueKeysWithValues: archiveBundle.taskBundles.compactMap { taskBundle in
        restoredTaskIdentityMap[taskBundle.archivedTaskID].map {
          (taskBundle.reminderExternalIdentifier, $0.reminderExternalIdentifier)
        }
      }
    )
    let existingRecords = try await mirrorPlacementStore.allRecords()
    let recordsToRemap = existingRecords.filter {
      archivedReminderExternalIdentifiers.contains($0.reminderExternalIdentifier)
        || $0.targetReminderListExternalIdentifier == archiveBundle.reminderListExternalIdentifier
        || archivedReminderExternalIdentifiers.contains(
          $0.normalizedParentReminderExternalIdentifier ?? ""
        )
    }

    for record in recordsToRemap {
      _ = try await mirrorPlacementStore.remove(
        reminderExternalIdentifier: record.reminderExternalIdentifier,
        targetReminderListExternalIdentifier: record.targetReminderListExternalIdentifier
      )

      let remappedReminderExternalIdentifier =
        restoredReminderExternalIdentifiersByArchived[record.reminderExternalIdentifier]
        ?? record.reminderExternalIdentifier
      let remappedTargetReminderListExternalIdentifier =
        record.targetReminderListExternalIdentifier == archiveBundle.reminderListExternalIdentifier
        ? restoreResult.list.externalIdentifier
        : record.targetReminderListExternalIdentifier
      let remappedParentReminderExternalIdentifier =
        record.normalizedParentReminderExternalIdentifier.flatMap {
          restoredReminderExternalIdentifiersByArchived[$0] ?? $0
        }
      _ = try await mirrorPlacementStore.upsert(
        reminderExternalIdentifier: remappedReminderExternalIdentifier,
        targetReminderListExternalIdentifier: remappedTargetReminderListExternalIdentifier,
        normalizedParentReminderExternalIdentifier: remappedParentReminderExternalIdentifier,
        rowOrder: record.rowOrder,
        now: record.updatedAt
      )
    }
  }

  private static func removeMirrorPlacements(
    deletionReference: DeletionReference,
    mirrorPlacementStore: TaskMirrorPlacementStore?
  ) async throws {
    guard let mirrorPlacementStore else { return }
    try await mirrorPlacementStore.removeAll(
      reminderExternalIdentifiers: deletionReference.taskReminderExternalIdentifiers
    )

    let inboundRecords = try await mirrorPlacementStore.records(
      targetReminderListExternalIdentifier: deletionReference.reminderListExternalIdentifier
    )
    for record in inboundRecords {
      _ = try await mirrorPlacementStore.remove(
        reminderExternalIdentifier: record.reminderExternalIdentifier,
        targetReminderListExternalIdentifier: record.targetReminderListExternalIdentifier
      )
    }
  }

  private static func deleteCanonicalProjectState(
    projectID: UUID,
    context: ModelContext
  ) throws {
    _ = projectID
    _ = context
    // Phase 13 steady-state runtime no longer registers canonical reminder/task/project owners.
    // Legacy canonical rows remain reachable only through dedicated migration/diagnostics stacks.
  }

  private static func sourceTaskNodes(
    in project: OutlinerProject
  ) -> [OutlineNode] {
    var nodesByID: [UUID: OutlineNode] = [:]
    for entry in project.document.flatten() where entry.node.type.isTask {
      guard TaskIdentityBridgeStore.record(for: entry.node.canonicalID)?.ownerProjectID == project.id else {
        continue
      }
      nodesByID[entry.node.canonicalID] = entry.node
    }
    return nodesByID.values.sorted { lhs, rhs in
      lhs.canonicalID.uuidString < rhs.canonicalID.uuidString
    }
  }

  private static func deletionReference(
    requestedProjectID: UUID,
    activeProjectState: ActiveProjectState?,
    archiveBundle: ArchivedProjectBundle?,
    workspaceTreeRepository: WorkspaceTreeRepository?
  ) async throws -> DeletionReference {
    if let activeProjectState {
      let taskNodes = sourceTaskNodes(in: activeProjectState.project)
      let workspaceNodeIDs =
        try await workspaceTreeRepository?.fetchProjectNodes(
          canonicalProjectID: requestedProjectID,
          includeArchived: true
        ).map(\.id) ?? []
      return DeletionReference(
        projectID: requestedProjectID,
        title: activeProjectState.title,
        activeReminderListIdentifier: activeProjectState.reminderListIdentifier,
        reminderListExternalIdentifier: activeProjectState.reminderListExternalIdentifier,
        taskIDs: taskNodes.map(\.canonicalID),
        taskReminderExternalIdentifiers: taskNodes.compactMap {
          normalized($0.reminderExternalIdentifier)
        },
        workspaceNodeIDs: workspaceNodeIDs
      )
    }

    guard let archiveBundle else {
      throw ProjectLifecycleServiceError.archiveBundleUnavailable(requestedProjectID)
    }
    return DeletionReference(
      projectID: archiveBundle.archivedProjectID,
      title: archiveBundle.title,
      activeReminderListIdentifier: nil,
      reminderListExternalIdentifier: archiveBundle.reminderListExternalIdentifier,
      taskIDs: archiveBundle.taskBundles.map(\.archivedTaskID),
      taskReminderExternalIdentifiers: archiveBundle.taskBundles.map(\.reminderExternalIdentifier),
      workspaceNodeIDs: archiveBundle.workspaceNodeIDs
    )
  }

  private static func workspaceStructureRecord(
    orderedReminderListExternalIdentifiers: [String],
    existing: ReminderWorkspaceStructureRecord?
  ) -> ReminderWorkspaceStructureRecord {
    ReminderWorkspaceStructureRecord(
      orderedReminderListExternalIdentifiersRaw: ReminderProjectionOrderCodec.encode(
        orderedReminderListExternalIdentifiers
      ),
      createdAt: existing?.createdAt ?? .now,
      updatedAt: .now
    )
  }

  private static func clearTaskIdentityBridge(
    for taskBundles: [ArchivedProjectTaskBundle]
  ) {
    clearTaskIdentityBridge(
      reminderExternalIdentifiers: taskBundles.map(\.reminderExternalIdentifier),
      taskIDs: taskBundles.map(\.archivedTaskID)
    )
  }

  private static func clearTaskIdentityBridge(
    reminderExternalIdentifiers: [String],
    taskIDs: [UUID]
  ) {
    taskIDs.forEach { TaskIdentityBridgeStore.remove(taskID: $0) }
    reminderExternalIdentifiers.forEach { TaskIdentityBridgeStore.remove(reminderExternalIdentifier: $0) }
  }

  private static func normalized(_ value: String?) -> String? {
    ReminderProjectionIdentity.normalized(value)
  }
}
