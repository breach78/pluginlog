import Combine
import Foundation
import SwiftData

struct RuntimeProjectionTaskLocation {
  let projectIndex: Int
  let node: OutlineNode
}

@MainActor
extension AppState {
  @discardableResult
  func recomputeCachedRuntimeProjectionProjects(
    _ projectIDs: Set<UUID>
  ) async -> Bool {
    let resolvedProjectIDs = Set(projectIDs)
    guard !resolvedProjectIDs.isEmpty else { return false }
    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else {
      syncStatus = "Scoped recompute skipped (projection unavailable)"
      return false
    }

    var payload = loadRuntimeProjectionSidecarPayload()
    let disconnectedProjectIDs = payload.cutDuplicateProjectReminderConnections()
    guard let anchorProjectID = resolvedProjectIDs.sorted(by: { $0.uuidString < $1.uuidString }).first,
      let store = projectDocumentStore(for: anchorProjectID)
    else {
      syncStatus = "Scoped recompute skipped (store unavailable)"
      return false
    }

    guard await patchRuntimeProjectionProjects(
      from: store,
      projectIDs: resolvedProjectIDs,
      snapshot: &snapshot,
      payload: &payload
    ) else {
      syncStatus = "Scoped recompute skipped (scoped recompute failed)"
      return false
    }

    let affectedProjectIDs = resolvedProjectIDs.union(disconnectedProjectIDs)
    await invalidateWorkspaceProjectCaches(for: affectedProjectIDs)
    await syncWorkspaceProjectIdentities(for: affectedProjectIDs, snapshot: snapshot)
    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    saveRuntimeProjectionSidecarPayload(payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
    bumpWorkspaceTreeRevision()
    syncStarted = true
    return true
  }

  @discardableResult
  func removeCachedRuntimeProjectionProjects(
    _ projectIDs: Set<UUID>
  ) async -> Bool {
    let resolvedProjectIDs = Set(projectIDs)
    guard !resolvedProjectIDs.isEmpty else { return false }

    var payload = loadRuntimeProjectionSidecarPayload()
    let disconnectedProjectIDs = payload.cutDuplicateProjectReminderConnections()
    saveRuntimeProjectionSidecarPayload(payload)

    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else { return true }

    for projectID in resolvedProjectIDs {
      snapshot.removeProject(projectID: projectID)
    }

    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
    await invalidateWorkspaceProjectCaches(
      for: resolvedProjectIDs.union(disconnectedProjectIDs)
    )
    if !disconnectedProjectIDs.isEmpty {
      await syncWorkspaceProjectIdentities(for: disconnectedProjectIDs, snapshot: snapshot)
    }
    bumpWorkspaceTreeRevision()
    syncStarted = true
    return true
  }

  @discardableResult
  func handleExternalOwnerChangeCommand(
    _ command: ExternalOwnerChangeCommand,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    if waitForEditorIdle
      && (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty)
    {
      guard await waitForEditorToBecomeIdle() else { return false }
    }

    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else {
      syncStatus = "External owner change skipped (projection unavailable)"
      return false
    }

    let affectedProjectIDs = affectedProjectIDs(for: command, snapshot: snapshot)
    guard !affectedProjectIDs.isEmpty else {
      syncStatus = "External owner change skipped (scope unresolved)"
      return false
    }
    guard let anchorProjectID = affectedProjectIDs.sorted(by: { $0.uuidString < $1.uuidString }).first,
      let store = projectDocumentStore(for: anchorProjectID)
    else {
      syncStatus = "External owner change skipped (store unavailable)"
      return false
    }

    var payload = loadRuntimeProjectionSidecarPayload()
    guard await patchRuntimeProjectionProjects(
      from: store,
      projectIDs: affectedProjectIDs,
      snapshot: &snapshot,
      payload: &payload
    ) else {
      syncStatus = "External owner change skipped (scoped recompute failed)"
      return false
    }

    await invalidateWorkspaceProjectCaches(for: affectedProjectIDs)
    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    saveRuntimeProjectionSidecarPayload(payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
    bumpWorkspaceTreeRevision()
    syncStarted = true
    syncStatus = externalOwnerChangeStatusText(for: command, projectIDs: affectedProjectIDs)
    return true
  }

  func observeProjectDocumentStore(_ store: ProjectDocumentStore, projectID: UUID) {
    projectDocumentStoreChangeCancellables[projectID]?.cancel()
    projectDocumentStoreChangeCancellables[projectID] = store.projectChanged.sink {
      [weak self, weak store] event in
      guard let self, let store else { return }
      Task { @MainActor [weak self, weak store] in
        guard let self, let store else { return }
        await self.handleProjectDocumentChangeEvent(event, store: store)
      }
    }
  }

  func patchCachedRuntimeProjectionForCreatedProject(_ projectID: UUID) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      _ = await self.recomputeCachedRuntimeProjectionProjects([projectID])
    }
  }

  func patchCachedRuntimeProjectionForWorkspaceOrder(_ orderedProjectIDs: [UUID]) {
    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else { return }
    var payload = loadRuntimeProjectionSidecarPayload()
    guard patchRuntimeProjectionWorkspaceOrder(
      orderedProjectIDs,
      snapshot: &snapshot,
      payload: &payload
    ) else {
      return
    }
    saveRuntimeProjectionSidecarPayload(payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
    bumpWorkspaceTreeRevision()
  }

  private func handleProjectDocumentChangeEvent(
    _ event: ProjectChangeEvent,
    store: ProjectDocumentStore
  ) async {
    var payload = loadRuntimeProjectionSidecarPayload()

    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else {
      patchProjectionSidecarPayloadOnly(for: event, payload: &payload)
      saveRuntimeProjectionSidecarPayload(payload)
      return
    }

    switch event.command {
    case let .setTitle(rawTitle):
      let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedTitle = title.isEmpty ? OutlinerProject.defaultTitle : title
      snapshot.setProjectTitle(projectID: event.projectID, title: resolvedTitle)

    case let .updateProjectNote(note):
      mutateProjectFeatureRecord(
        projectID: event.projectID,
        snapshot: &snapshot,
        payload: &payload
      ) { record in
        record.projectNoteMarkdown = note
      }

    case let .setProjectColor(colorHex):
      snapshot.setProjectColor(projectID: event.projectID, colorHex: normalizedProjectionValue(colorHex))

    case let .setProjectStage(stage):
      mutateProjectFeatureRecord(
        projectID: event.projectID,
        snapshot: &snapshot,
        payload: &payload
      ) { record in
        record.progressStageRaw = stage.storageRawValue
      }

    case let .updateTaskText(taskID, title):
      if !snapshot.updateTaskNodes(contentID: taskID, title: title, isCompleted: nil) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .patchTaskTitle(contentID, newText):
      if !snapshot.updateNodeText(matching: contentID, newText: newText) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .patchBulletText(contentID, newText):
      if !snapshot.updateNodeText(matching: contentID, newText: newText) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .updateTaskNote(taskID, field, value):
      switch field {
      case .reminderNote:
        if !patchReminderNoteSubtree(
          taskID: taskID,
          note: value,
          snapshot: &snapshot,
          payload: &payload
        ) {
          if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
        }
      }

    case let .setTaskSchedule(taskID, day, timeMinutes, durationMinutes):
      if !patchTaskSchedule(
        taskID: taskID,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes,
        snapshot: &snapshot,
        payload: &payload
      ) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .setTaskPresentation(taskID, boardStage, importance, priority, isFlagged):
      if !patchTaskPresentation(
        taskID: taskID,
        boardStage: boardStage,
        importance: importance,
        priority: priority,
        isFlagged: isFlagged,
        snapshot: &snapshot,
        payload: &payload
      ) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .setTaskPreparationSchedule(taskID, targetCompletedUnits, _, timeMinutes, durationMinutes):
      if !patchTaskPreparationSchedule(
        taskID: taskID,
        targetCompletedUnits: targetCompletedUnits,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes,
        snapshot: &snapshot,
        payload: &payload
      ) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .setTaskCompletion(taskID, isCompleted, completionDate):
      if !snapshot.patchTaskCompletion(
        contentID: taskID,
        isCompleted: isCompleted,
        completionDate: completionDate
      ) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .completeRecurringTask(taskID, occurrenceDate):
      if !snapshot.patchTaskCompletion(
        contentID: taskID,
        isCompleted: true,
        completionDate: occurrenceDate
      ) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .setPlannedWorkProgress(taskID, targetCompletedUnits, completedOn):
      if !patchTaskProgress(
        taskID: taskID,
        targetCompletedUnits: targetCompletedUnits,
        completedOn: completedOn,
        snapshot: &snapshot,
        payload: &payload
      ) {
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case let .setProjectRootStructure(rootNodes):
      if !patchProjectRootStructure(
        projectID: event.projectID,
        rootNodes: rootNodes,
        snapshot: &snapshot,
        payload: &payload
      ) {
        if await patchRuntimeProjectionProjects(
          from: store,
          projectIDs: [event.projectID],
          snapshot: &snapshot,
          payload: &payload
        ) {
          break
        }
        if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }
      }

    case .createTask,
      .addTask,
      .deleteTask,
      .reorderTask,
      .setVisibleRootTaskOrder:
      if await patchRuntimeProjectionProjects(
        from: store,
        projectIDs: [event.projectID],
        snapshot: &snapshot,
        payload: &payload
      ) {
        break
      }
      if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }

    case let .moveTask(_, targetProjectID),
      let .moveTaskSequence(_, targetProjectID):
      if await patchRuntimeProjectionProjects(
        from: store,
        projectIDs: [event.projectID, targetProjectID],
        snapshot: &snapshot,
        payload: &payload
      ) {
        break
      }
      if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }

    case .setTaskReminderMetadata, .applyAttachmentMutation:
      if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }

    case .restoreProject:
      if await reloadRuntimeProjectionProject(projectID: event.projectID) { return }

    case .archiveProject, .deleteProject:
      snapshot.removeProject(projectID: event.projectID)

    }

    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    saveRuntimeProjectionSidecarPayload(payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
  }

  private func patchProjectionSidecarPayloadOnly(
    for event: ProjectChangeEvent,
    payload: inout ReminderProjectionSidecarPayload
  ) {
    switch event.command {
    case let .updateProjectNote(note):
      mutateProjectFeaturePayload(projectID: event.projectID, payload: &payload) { record in
        record.projectNoteMarkdown = note
      }
    case .updateTaskText:
      break
    case let .setProjectStage(stage):
      mutateProjectFeaturePayload(projectID: event.projectID, payload: &payload) { record in
        record.progressStageRaw = stage.storageRawValue
      }
    case .setProjectColor, .setTitle, .setTaskCompletion, .completeRecurringTask, .createTask,
      .addTask, .deleteTask, .moveTask, .moveTaskSequence, .reorderTask, .setVisibleRootTaskOrder,
      .restoreProject, .archiveProject, .deleteProject, .setTaskReminderMetadata,
      .applyAttachmentMutation:
      break
    case let .setProjectRootStructure(rootNodes):
      mutateProjectRootStructurePayload(
        projectID: event.projectID,
        rootNodes: rootNodes,
        payload: &payload
      )
    case let .updateTaskNote(taskID, field, value):
      guard let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(taskID: taskID) else {
        return
      }
      mutateTaskFeaturePayload(
        reminderExternalIdentifier: reminderExternalIdentifier,
        payload: &payload
      ) { record in
        switch field {
        case .reminderNote:
          break
        }
      }
    case let .setTaskSchedule(taskID, _, _, durationMinutes):
      guard let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(taskID: taskID) else {
        return
      }
      mutateTaskFeaturePayload(
        reminderExternalIdentifier: reminderExternalIdentifier,
        payload: &payload
      ) { record in
        record.scheduledDurationMinutes = durationMinutes
      }
    case let .setTaskPresentation(taskID, boardStage, importance, _, isFlagged):
      guard let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(taskID: taskID) else {
        return
      }
      mutateTaskFeaturePayload(
        reminderExternalIdentifier: reminderExternalIdentifier,
        payload: &payload
      ) { record in
        record.boardStageRaw = boardStage.rawValue
        record.importanceRaw = importance.rawValue
        record.isFlagged = isFlagged
      }
    case let .setTaskPreparationSchedule(taskID, targetCompletedUnits, _, timeMinutes, durationMinutes):
      guard let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(taskID: taskID) else {
        return
      }
      mutateTaskFeaturePayload(
        reminderExternalIdentifier: reminderExternalIdentifier,
        payload: &payload
      ) { record in
        record.requiredWorkDays = max(record.requiredWorkDays, targetCompletedUnits)
        let override = ProjectDocumentStore.TaskPreparationScheduleSnapshot(
          isAllDay: false,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes
        )
        var overrides = decodePreparationScheduleOverrides(record.preparationScheduleOverridesRaw)
        overrides[targetCompletedUnits] = override
        record.preparationScheduleOverridesRaw = encodePreparationScheduleOverrides(overrides)
      }
    case let .setPlannedWorkProgress(taskID, targetCompletedUnits, completedOn):
      guard let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(taskID: taskID) else {
        return
      }
      mutateTaskFeaturePayload(
        reminderExternalIdentifier: reminderExternalIdentifier,
        payload: &payload
      ) { record in
        record.completedWorkUnits = max(0, targetCompletedUnits)
        let recordedAt = Calendar.autoupdatingCurrent.startOfDay(for: completedOn)
        let dates = Array(repeating: recordedAt, count: max(0, targetCompletedUnits))
        record.completedWorkUnitDatesRaw = encodeCompletedWorkUnitDates(dates)
      }
    case let .patchTaskTitle(taskID, _), let .patchBulletText(taskID, _):
      _ = taskID
    }
  }

  func patchRuntimeProjectionProjects(
    from store: ProjectDocumentStore,
    projectIDs: some Sequence<UUID>,
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) async -> Bool {
    let affectedProjectIDs = Set(projectIDs)
    guard !affectedProjectIDs.isEmpty else { return false }
    guard
      let patchedSnapshot = try? await store.loadRuntimeProjectionSnapshot(for: affectedProjectIDs),
      affectedProjectIDs.isSubset(of: Set(patchedSnapshot.projects.map(\.id)))
    else {
      return false
    }

    for projectID in affectedProjectIDs {
      snapshot.purgePatchedProjectTransientMaps(projectID: projectID)
    }
    snapshot = patchedSnapshot.mergedForAppCache(
      existing: snapshot,
      preferredProjectID: snapshot.currentProjectID
    )
    snapshot.syncSidecarState(payload: payload)
    return true
  }

  private func reloadRuntimeProjectionProject(projectID: UUID) async -> Bool {
    await recomputeCachedRuntimeProjectionProjects([projectID])
  }

  private func affectedProjectIDs(
    for command: ExternalOwnerChangeCommand,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> Set<UUID> {
    switch command {
    case let .reminderProjectListsChanged(_, reminderListIdentifiers, reminderListExternalIdentifiers):
      let normalizedIdentifiers = Set(reminderListIdentifiers.compactMap(normalizedProjectionValue))
      let normalizedExternalIdentifiers = Set(
        reminderListExternalIdentifiers.compactMap(normalizedProjectionValue)
      )

      return Set(
        snapshot.projects.compactMap { project in
          let listIdentifier = normalizedProjectionValue(
            snapshot.projectReminderListIdentifierByProjectID[project.id]
          )
          let listExternalIdentifier = normalizedProjectionValue(
            snapshot.projectReminderListExternalIdentifierByProjectID[project.id]
          )
          let matchesIdentifier = listIdentifier.map { normalizedIdentifiers.contains($0) } ?? false
          let matchesExternalIdentifier =
            listExternalIdentifier.map { normalizedExternalIdentifiers.contains($0) } ?? false
          return matchesIdentifier || matchesExternalIdentifier ? project.id : nil
        }
      )
    }
  }

  private func externalOwnerChangeStatusText(
    for command: ExternalOwnerChangeCommand,
    projectIDs: Set<UUID>
  ) -> String {
    switch command {
    case let .reminderProjectListsChanged(reason, _, _):
      return "Refreshed scoped projection (\(reason.rawValue), \(projectIDs.count) project)"
    }
  }

  private func patchTaskSchedule(
    taskID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) -> Bool {
    guard let location = snapshot.taskLocation(for: taskID) else { return false }

    let metadata = reminderMetadataSnapshot(
      existing: snapshot.reminderMetadata(for: location.node)
        ?? snapshot.reminderMetadataByNodeID[location.node.id],
      day: day,
      timeMinutes: timeMinutes
    )
    let didUpdateMetadata = snapshot.updateReminderMetadata(
      contentID: taskID,
      reminderIdentifier: normalizedProjectionValue(location.node.reminderIdentifier),
      metadata: metadata
    )
    let didUpdateFeature = mutateTaskFeatureRecord(
      taskID: taskID,
      snapshot: &snapshot,
      payload: &payload
    ) { record in
      record.scheduledDurationMinutes = durationMinutes
    }
    return didUpdateMetadata || didUpdateFeature
  }

  private func patchTaskPresentation(
    taskID: UUID,
    boardStage: BoardStage,
    importance: ImportanceLevel,
    priority: Int,
    isFlagged: Bool,
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) -> Bool {
    let didUpdateMetadata = snapshot.updateReminderMetadata(
      contentID: taskID,
      reminderIdentifier: snapshot.taskLocation(for: taskID).flatMap {
        normalizedProjectionValue($0.node.reminderIdentifier)
      },
      metadata: snapshot.taskLocation(for: taskID).map { location in
        var metadata = snapshot.reminderMetadata(for: location.node)
          ?? snapshot.reminderMetadataByNodeID[location.node.id]
          ?? .empty
        metadata.priority = priority
        return metadata
      }
    )
    let didUpdateFeature = mutateTaskFeatureRecord(
      taskID: taskID,
      snapshot: &snapshot,
      payload: &payload
    ) { record in
      record.boardStageRaw = boardStage.rawValue
      record.importanceRaw = importance.rawValue
      record.isFlagged = isFlagged
    }
    return didUpdateMetadata || didUpdateFeature
  }

  private func patchTaskPreparationSchedule(
    taskID: UUID,
    targetCompletedUnits: Int,
    timeMinutes: Int,
    durationMinutes: Int,
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) -> Bool {
    mutateTaskFeatureRecord(
      taskID: taskID,
      snapshot: &snapshot,
      payload: &payload
    ) { record in
      record.requiredWorkDays = max(record.requiredWorkDays, targetCompletedUnits)
      let override = ProjectDocumentStore.TaskPreparationScheduleSnapshot(
        isAllDay: false,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
      var overrides = decodePreparationScheduleOverrides(record.preparationScheduleOverridesRaw)
      overrides[targetCompletedUnits] = override
      record.preparationScheduleOverridesRaw = encodePreparationScheduleOverrides(overrides)
    }
  }

  private func patchTaskProgress(
    taskID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date,
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) -> Bool {
    mutateTaskFeatureRecord(
      taskID: taskID,
      snapshot: &snapshot,
      payload: &payload
    ) { record in
      let recordedAt = Calendar.autoupdatingCurrent.startOfDay(for: completedOn)
      record.completedWorkUnits = max(0, targetCompletedUnits)
      record.completedWorkUnitDatesRaw = encodeCompletedWorkUnitDates(
        Array(repeating: recordedAt, count: max(0, targetCompletedUnits))
      )
    }
  }

  private func patchReminderNoteSubtree(
    taskID: UUID,
    note: String,
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) -> Bool {
    guard let location = snapshot.taskLocation(for: taskID),
      let reminderExternalIdentifier = normalizedProjectionValue(location.node.reminderExternalIdentifier)
    else {
      return false
    }

    let overriddenDocument = ReminderNoteSourceCodec.parseReminderRawNote(note)
    let tasksByExternalIdentifier = snapshot.runtimeTaskSnapshots(
      overridingSourceDocuments: [reminderExternalIdentifier: overriddenDocument]
    )
    guard let taskSnapshot = tasksByExternalIdentifier[reminderExternalIdentifier] else {
      return false
    }

    let loadedTree = ReminderNoteSourceLoader.loadTaskTree(
      from: taskSnapshot,
      tasksByExternalIdentifier: tasksByExternalIdentifier,
      taskFeatureSidecarsByReminderExternalIdentifier: payload.taskFeatureSidecarByReminderExternalIdentifier
    )
    let remappedTree = loadedTree.preservingRootNodeID(location.node.id)

    let previousNodeIDs = location.node.allNodeIDs
    snapshot.projects[location.projectIndex].document.updateNode(id: location.node.id) { node in
      node.text = remappedTree.root.text
      node.type = remappedTree.root.type
      node.children = remappedTree.root.children
      node.referenceProjectID = remappedTree.root.referenceProjectID
      node.isCollapsed = remappedTree.root.isCollapsed
      node.migratedTaskItemID = remappedTree.root.migratedTaskItemID
      node.reminderIdentifier = remappedTree.root.reminderIdentifier
      node.reminderExternalIdentifier = remappedTree.root.reminderExternalIdentifier
      node.attachments = remappedTree.root.attachments
    }

    for nodeID in previousNodeIDs {
      snapshot.reminderMetadataByNodeID.removeValue(forKey: nodeID)
      snapshot.featureSidecarByNodeID.removeValue(forKey: nodeID)
    }
    snapshot.reminderMetadataByNodeID.merge(
      remappedTree.reminderMetadataByNodeID,
      uniquingKeysWith: { _, rhs in rhs }
    )
    snapshot.featureSidecarByNodeID.merge(
      remappedTree.featureSidecarByNodeID,
      uniquingKeysWith: { _, rhs in rhs }
    )
    if let reminderIdentifier = normalizedProjectionValue(taskSnapshot.reminderIdentifier) {
      snapshot.reminderMetadataByReminderIdentifier[reminderIdentifier] = taskSnapshot.reminderMetadata
    }

    var runtimeState =
      snapshot.taskSourceRuntimeStateByReminderExternalIdentifier[reminderExternalIdentifier]
      ?? ReminderTaskSourceRuntimeState(
        reminderExternalIdentifier: reminderExternalIdentifier,
        lastImportedNormalizedNoteHash: nil,
        lastExportedNormalizedNoteHash: nil,
        lastObservedReminderModifiedAt: nil,
        lastObservedReminderRawPayloadRaw: nil,
        noteConflictStateRaw: nil
      )
    runtimeState.lastExportedNormalizedNoteHash = ReminderNoteSourceMutationService.hash(
      for: overriddenDocument.normalizedText
    )
    snapshot.taskSourceRuntimeStateByReminderExternalIdentifier[reminderExternalIdentifier] = runtimeState
    return true
  }

  private func mutateProjectFeatureRecord(
    projectID: UUID,
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload,
    mutate: (inout ReminderProjectFeatureSidecarRecord) -> Void
  ) {
    mutateProjectFeaturePayload(projectID: projectID, payload: &payload, mutate: mutate)
    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
  }

  private func mutateTaskFeatureRecord(
    taskID: UUID,
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload,
    mutate: (inout ReminderTaskFeatureSidecarRecord) -> Void
  ) -> Bool {
    guard let location = snapshot.taskLocation(for: taskID),
      let reminderExternalIdentifier = normalizedProjectionValue(
        location.node.reminderExternalIdentifier
      )
    else {
      return false
    }

    let reminderIdentifier = normalizedProjectionValue(location.node.reminderIdentifier)
    let metadata =
      payload.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier]?.featureSidecarMetadata
      ?? snapshot.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier]?
        .featureSidecarMetadata
      ?? snapshot.featureSidecarByNodeID[location.node.id]
      ?? snapshot.featureSidecarByReminderIdentifier[reminderIdentifier ?? ""]
      ?? OutlinerTaskSidecarMetadata()
    var record =
      payload.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier]
      ?? snapshot.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier]
      ?? AppFeatureMutationService.taskFeatureRecord(
        reminderExternalIdentifier: reminderExternalIdentifier,
        featureSidecar: metadata
      )
    mutate(&record)

    if record.hasMeaningfulContent {
      payload.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier] = record
    } else {
      payload.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
        forKey: reminderExternalIdentifier
      )
    }
    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    snapshot.syncTaskFeatureSidecarNodeMaps(
      contentID: taskID,
      reminderIdentifier: reminderIdentifier,
      record: payload.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier]
    )
    return true
  }

  private func mutateProjectFeaturePayload(
    projectID: UUID,
    payload: inout ReminderProjectionSidecarPayload,
    mutate: (inout ReminderProjectFeatureSidecarRecord) -> Void
  ) {
    guard let reminderListExternalIdentifier = resolvedProjectReminderListExternalIdentifier(projectID: projectID)
    else {
      return
    }
    var record =
      payload.projectFeatureSidecarByReminderListExternalIdentifier[reminderListExternalIdentifier]
      ?? ReminderProjectFeatureMutationService.projectFeatureRecord(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        projectNoteMarkdown: "",
        localStartDate: nil,
        localDeadline: nil,
        progressStageRaw: nil,
        boardOrder: nil,
        existing: nil
      )
    mutate(&record)
    if record.hasMeaningfulContent {
      payload.projectFeatureSidecarByReminderListExternalIdentifier[reminderListExternalIdentifier] =
        record
    } else {
      payload.projectFeatureSidecarByReminderListExternalIdentifier.removeValue(
        forKey: reminderListExternalIdentifier
      )
    }
  }

  private func mutateTaskFeaturePayload(
    reminderExternalIdentifier: String,
    payload: inout ReminderProjectionSidecarPayload,
    mutate: (inout ReminderTaskFeatureSidecarRecord) -> Void
  ) {
    let normalizedReminderExternalIdentifier = normalizedProjectionValue(reminderExternalIdentifier)
    guard let normalizedReminderExternalIdentifier else { return }
    var record =
      payload.taskFeatureSidecarByReminderExternalIdentifier[normalizedReminderExternalIdentifier]
      ?? AppFeatureMutationService.taskFeatureRecord(
        reminderExternalIdentifier: normalizedReminderExternalIdentifier,
        featureSidecar: OutlinerTaskSidecarMetadata()
      )
    mutate(&record)
    if record.hasMeaningfulContent {
      payload.taskFeatureSidecarByReminderExternalIdentifier[normalizedReminderExternalIdentifier] =
        record
    } else {
      payload.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
        forKey: normalizedReminderExternalIdentifier
      )
    }
  }

  private func mutateProjectRootStructurePayload(
    projectID: UUID,
    rootNodes: [ReminderProjectRootNodeRecord],
    payload: inout ReminderProjectionSidecarPayload
  ) {
    guard let reminderListExternalIdentifier = resolvedProjectReminderListExternalIdentifier(projectID: projectID)
    else {
      return
    }
    payload.projectRootStructureByReminderListExternalIdentifier[reminderListExternalIdentifier] =
      ReminderProjectRootStructureMutationService.record(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        rootNodes: rootNodes,
        existing: payload.projectRootStructureByReminderListExternalIdentifier[
          reminderListExternalIdentifier]
      )
    let orderedTopLevelReminderExternalIdentifiers = rootNodes.compactMap { record -> String? in
      guard case let .task(reminderExternalIdentifier, _) = record else { return nil }
      return normalizedProjectionValue(reminderExternalIdentifier)
    }
    payload.projectTaskOrderByReminderListExternalIdentifier[reminderListExternalIdentifier] =
      ReminderProjectTaskOrderMutationService.record(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        orderedTopLevelReminderExternalIdentifiers: orderedTopLevelReminderExternalIdentifiers,
        existing: payload.projectTaskOrderByReminderListExternalIdentifier[
          reminderListExternalIdentifier]
      )
  }

  private func patchProjectRootStructure(
    projectID: UUID,
    rootNodes: [ReminderProjectRootNodeRecord],
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) -> Bool {
    mutateProjectRootStructurePayload(
      projectID: projectID,
      rootNodes: rootNodes,
      payload: &payload
    )

    guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == projectID }),
      let reminderListExternalIdentifier = resolvedProjectReminderListExternalIdentifier(projectID: projectID),
      let record = payload.projectRootStructureByReminderListExternalIdentifier[
        reminderListExternalIdentifier]
    else {
      return false
    }

    snapshot.projects[projectIndex].document.rootNodes = ReminderProjectRootStructureCodec.rebuildRootNodes(
      from: record,
      existingNodes: snapshot.projects[projectIndex].document.rootNodes
    )
    return true
  }

  private func updateProjectionOrderingPayload(
    snapshot: OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) {
    let orderedReminderListExternalIdentifiers = snapshot.projects.compactMap { project in
      normalizedProjectionValue(
        snapshot.projectReminderListExternalIdentifierByProjectID[project.id]
      )
    }
    if orderedReminderListExternalIdentifiers.isEmpty {
      payload.workspaceStructureRecord = nil
    } else {
      payload.workspaceStructureRecord = ReminderWorkspaceStructureMutationService.record(
        orderedReminderListExternalIdentifiers: orderedReminderListExternalIdentifiers,
        existing: payload.workspaceStructureRecord
      )
    }

    for project in snapshot.projects {
      guard let reminderListExternalIdentifier = normalizedProjectionValue(
        snapshot.projectReminderListExternalIdentifierByProjectID[project.id]
      ) else {
        continue
      }
      let orderedTopLevelReminderExternalIdentifiers: [String] = project.document.rootNodes.compactMap { node in
        guard node.type.isTask else { return nil }
        return normalizedProjectionValue(node.reminderExternalIdentifier)
      }
      payload.projectTaskOrderByReminderListExternalIdentifier[reminderListExternalIdentifier] =
        ReminderProjectTaskOrderMutationService.record(
          reminderListExternalIdentifier: reminderListExternalIdentifier,
          orderedTopLevelReminderExternalIdentifiers: orderedTopLevelReminderExternalIdentifiers,
          existing: payload.projectTaskOrderByReminderListExternalIdentifier[
            reminderListExternalIdentifier]
        )
      payload.projectRootStructureByReminderListExternalIdentifier[reminderListExternalIdentifier] =
        ReminderProjectRootStructureMutationService.record(
          reminderListExternalIdentifier: reminderListExternalIdentifier,
          rootNodes: ReminderProjectRootStructureCodec.rootNodes(from: project.document.rootNodes),
          existing: payload.projectRootStructureByReminderListExternalIdentifier[
            reminderListExternalIdentifier]
        )
    }
  }

  func patchRuntimeProjectionWorkspaceOrder(
    _ orderedProjectIDs: [UUID],
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: inout ReminderProjectionSidecarPayload
  ) -> Bool {
    let normalizedProjectIDs = Array(NSOrderedSet(array: orderedProjectIDs)) as? [UUID]
      ?? orderedProjectIDs
    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
    var reorderedProjects: [OutlinerProject] = normalizedProjectIDs.compactMap { projectsByID[$0] }
    let movedProjectIDs = Set(reorderedProjects.map(\.id))
    reorderedProjects.append(
      contentsOf: snapshot.projects.filter { !movedProjectIDs.contains($0.id) }
    )
    guard !reorderedProjects.isEmpty else { return false }

    snapshot.projects = reorderedProjects
    updateProjectionOrderingPayload(snapshot: snapshot, payload: &payload)
    snapshot.workspaceStructureRecord = payload.workspaceStructureRecord
    return true
  }

  func syncRuntimeProjectionSidecarState(
    snapshot: inout OutlineProjectionRuntimeSnapshot,
    payload: ReminderProjectionSidecarPayload
  ) {
    snapshot.syncSidecarState(payload: payload)
  }

  func resolvedProjectReminderListExternalIdentifier(projectID: UUID) -> String? {
    normalizedProjectionValue(
      cachedOutlinerRuntimeProjectionSnapshot?
        .projectReminderListExternalIdentifierByProjectID[projectID]
    )
  }

  private func resolvedTaskReminderExternalIdentifier(taskID: UUID) -> String? {
    cachedOutlinerRuntimeProjectionSnapshot?.taskLocation(for: taskID).flatMap {
      normalizedProjectionValue($0.node.reminderExternalIdentifier)
    }
  }

  func loadRuntimeProjectionSidecarPayload() -> ReminderProjectionSidecarPayload {
    var payload = runtimeProjectionSidecarStore()?.load() ?? .empty
    payload.stripAppMemoryReadModels()
    let severedProjectIDs = payload.cutDuplicateProjectReminderConnections()
    if severedProjectIDs.isEmpty == false {
      saveRuntimeProjectionSidecarPayload(payload)
    }
    return payload
  }

  func saveRuntimeProjectionSidecarPayload(_ payload: ReminderProjectionSidecarPayload) {
    guard let store = runtimeProjectionSidecarStore() else { return }
    try? store.save(payload.sanitizedForPersistence())
  }

  func runtimeProjectionSidecarStore() -> ReminderProjectionSidecarStore? {
    ReminderProjectionSidecarStoreFactory.make(
      dataDirectory: storageCoordinator.paths?.dataDirectory
    )
  }

  func normalizedProjectionValue(_ value: String?) -> String? {
    ReminderProjectionIdentity.normalized(value)
  }

  private func reminderMetadataSnapshot(
    existing: ReminderMetadataSnapshot?,
    day: Date?,
    timeMinutes: Int?
  ) -> ReminderMetadataSnapshot {
    var metadata = existing ?? .empty
    if let day {
      let dayStart = Calendar.autoupdatingCurrent.startOfDay(for: day)
      if let timeMinutes {
        metadata.dueDate = Calendar.autoupdatingCurrent.date(
          byAdding: .minute,
          value: timeMinutes,
          to: dayStart
        )
        metadata.hasExplicitTime = true
      } else {
        metadata.dueDate = dayStart
        metadata.hasExplicitTime = false
      }
    } else {
      metadata.dueDate = nil
      metadata.hasExplicitTime = false
    }
    return metadata
  }

  private func decodePreparationScheduleOverrides(
    _ raw: String
  ) -> [Int: ProjectDocumentStore.TaskPreparationScheduleSnapshot] {
    guard let data = raw.data(using: .utf8) else { return [:] }
    return (try? JSONDecoder().decode([Int: ProjectDocumentStore.TaskPreparationScheduleSnapshot].self, from: data))
      ?? [:]
  }

  private func encodePreparationScheduleOverrides(
    _ overrides: [Int: ProjectDocumentStore.TaskPreparationScheduleSnapshot]
  ) -> String {
    guard let data = try? JSONEncoder().encode(overrides),
      let raw = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return raw
  }

  private func encodeCompletedWorkUnitDates(_ dates: [Date]) -> String {
    guard let data = try? JSONEncoder().encode(dates),
      let raw = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return raw
  }
}

extension OutlineProjectionRuntimeSnapshot {
  mutating func upsertProject(_ project: OutlinerProject) {
    if let index = projects.firstIndex(where: { $0.id == project.id }) {
      projects[index] = project
    } else {
      projects.append(project)
    }
    if projects.contains(where: { $0.id == currentProjectID }) == false {
      currentProjectID = projects.first?.id ?? currentProjectID
    }
  }

  mutating func setProjectTitle(projectID: UUID, title: String) {
    guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
    projects[index].title = title
  }

  mutating func setProjectColor(projectID: UUID, colorHex: String?) {
    if let colorHex {
      projectColorHexByProjectID[projectID] = colorHex
    } else {
      projectColorHexByProjectID.removeValue(forKey: projectID)
    }
  }

  mutating func removeProject(projectID: UUID) {
    purgeProjectNodeMaps(projectID: projectID)
    projects.removeAll { $0.id == projectID }
    projectReminderListIdentifierByProjectID.removeValue(forKey: projectID)
    projectReminderListExternalIdentifierByProjectID.removeValue(forKey: projectID)
    projectColorHexByProjectID.removeValue(forKey: projectID)
    projectFeatureSidecarByProjectID.removeValue(forKey: projectID)
    if currentProjectID == projectID {
      currentProjectID = projects.first?.id ?? currentProjectID
    }
  }

  mutating func purgeProjectNodeMaps(projectID: UUID) {
    guard let project = projects.first(where: { $0.id == projectID }) else { return }
    for entry in project.document.flatten() {
      reminderMetadataByNodeID.removeValue(forKey: entry.node.id)
      featureSidecarByNodeID.removeValue(forKey: entry.node.id)
    }
  }

  mutating func purgePatchedProjectTransientMaps(projectID: UUID) {
    guard let project = projects.first(where: { $0.id == projectID }) else { return }
    for entry in project.document.flatten() {
      reminderMetadataByNodeID.removeValue(forKey: entry.node.id)
      featureSidecarByNodeID.removeValue(forKey: entry.node.id)

      guard entry.node.type.isTask else { continue }
      if let reminderIdentifier = ReminderProjectionIdentity.normalized(entry.node.reminderIdentifier) {
        reminderMetadataByReminderIdentifier.removeValue(forKey: reminderIdentifier)
        featureSidecarByReminderIdentifier.removeValue(forKey: reminderIdentifier)
      }
      if let reminderExternalIdentifier = ReminderProjectionIdentity.normalized(
        entry.node.reminderExternalIdentifier
      ) {
        reminderModifiedAtByReminderExternalIdentifier.removeValue(
          forKey: reminderExternalIdentifier
        )
      }
    }
  }

  mutating func syncSidecarState(payload: ReminderProjectionSidecarPayload) {
    applyProjectConnectionSidecarState(
      payload.projectConnectionSidecarByReminderListExternalIdentifier
    )
    workspaceStructureRecord = payload.workspaceStructureRecord
    projectTaskOrderByReminderListExternalIdentifier =
      payload.projectTaskOrderByReminderListExternalIdentifier
    projectRootStructureByReminderListExternalIdentifier =
      payload.projectRootStructureByReminderListExternalIdentifier
    projectFeatureSidecarByReminderListExternalIdentifier =
      payload.projectFeatureSidecarByReminderListExternalIdentifier
    taskFeatureSidecarByReminderExternalIdentifier =
      payload.taskFeatureSidecarByReminderExternalIdentifier
    projectFeatureSidecarByProjectID = projectReminderListExternalIdentifierByProjectID
      .reduce(into: [:]) { partialResult, entry in
        guard let reminderListExternalIdentifier = ReminderProjectionIdentity.normalized(entry.value),
          let record = payload.projectFeatureSidecarByReminderListExternalIdentifier[
            reminderListExternalIdentifier]
        else {
          return
        }
        partialResult[entry.key] = record
      }
  }

  func taskLocation(for taskID: UUID) -> RuntimeProjectionTaskLocation? {
    for (projectIndex, project) in projects.enumerated() {
      if let node = project.document.flatten().first(where: {
        $0.node.type.isTask && $0.node.canonicalID == taskID
      })?.node {
        return RuntimeProjectionTaskLocation(projectIndex: projectIndex, node: node)
      }
    }
    return nil
  }

  mutating func updateTaskNodes(
    contentID: UUID,
    title: String?,
    isCompleted: Bool?
  ) -> Bool {
    var didUpdate = false
    for index in projects.indices {
      let matchingNodeIDs = projects[index].document.flatten().compactMap { entry -> UUID? in
        guard entry.node.type.isTask, entry.node.canonicalID == contentID else { return nil }
        return entry.node.id
      }
      guard !matchingNodeIDs.isEmpty else { continue }
      didUpdate = true
      for nodeID in matchingNodeIDs {
        projects[index].document.updateNode(id: nodeID) { node in
          if let title {
            node.text = title
          }
          if let isCompleted {
            node.type = .task(completed: isCompleted)
          }
        }
      }
    }
    return didUpdate
  }

  mutating func patchTaskCompletion(
    contentID: UUID,
    isCompleted: Bool,
    completionDate: Date?
  ) -> Bool {
    let didUpdate = updateTaskNodes(contentID: contentID, title: nil, isCompleted: isCompleted)
    guard didUpdate else { return false }

    let resolvedCompletionDate = isCompleted ? (completionDate ?? .now) : nil
    for index in projects.indices {
      for entry in projects[index].document.flatten()
      where entry.node.type.isTask && entry.node.canonicalID == contentID {
        let reminderIdentifier =
          ReminderProjectionIdentity.normalized(entry.node.reminderIdentifier)
          ?? ReminderProjectionIdentity.normalized(entry.node.reminderExternalIdentifier)
        let metadata =
          reminderIdentifier.flatMap { reminderMetadataByReminderIdentifier[$0] }
          ?? reminderMetadataByNodeID[entry.node.id]
          ?? .empty
        let updatedMetadata = ReminderMetadataSnapshot(
          dueDate: metadata.dueDate,
          completionDate: resolvedCompletionDate,
          hasExplicitTime: metadata.hasExplicitTime,
          recurrence: metadata.recurrence,
          priority: metadata.priority
        )
        reminderMetadataByNodeID[entry.node.id] = updatedMetadata
        if let reminderIdentifier {
          reminderMetadataByReminderIdentifier[reminderIdentifier] = updatedMetadata
        }
      }
    }

    return true
  }

  mutating func updateNodeText(matching identifier: UUID, newText: String) -> Bool {
    var didUpdate = false
    for index in projects.indices {
      let matchingNodeIDs = projects[index].document.flatten().compactMap { entry -> UUID? in
        guard entry.node.id == identifier || entry.node.canonicalID == identifier else {
          return nil
        }
        return entry.node.id
      }
      guard !matchingNodeIDs.isEmpty else { continue }
      didUpdate = true
      for nodeID in matchingNodeIDs {
        projects[index].document.updateNode(id: nodeID) { node in
          node.text = newText
        }
      }
    }
    return didUpdate
  }

  mutating func updateReminderMetadata(
    contentID: UUID,
    reminderIdentifier: String?,
    metadata: ReminderMetadataSnapshot?
  ) -> Bool {
    guard let metadata else { return false }
    let matchingNodeIDs = projects.flatMap { project in
      project.document.flatten().compactMap { entry -> UUID? in
        guard entry.node.type.isTask, entry.node.canonicalID == contentID else { return nil }
        return entry.node.id
      }
    }
    guard !matchingNodeIDs.isEmpty else { return false }
    for nodeID in matchingNodeIDs {
      reminderMetadataByNodeID[nodeID] = metadata
    }
    if let reminderIdentifier = ReminderProjectionIdentity.normalized(reminderIdentifier) {
      reminderMetadataByReminderIdentifier[reminderIdentifier] = metadata
    }
    return true
  }

  mutating func syncTaskFeatureSidecarNodeMaps(
    contentID: UUID,
    reminderIdentifier: String?,
    record: ReminderTaskFeatureSidecarRecord?
  ) {
    let matchingNodeIDs = projects.flatMap { project in
      project.document.flatten().compactMap { entry -> UUID? in
        guard entry.node.type.isTask, entry.node.canonicalID == contentID else { return nil }
        return entry.node.id
      }
    }
    guard !matchingNodeIDs.isEmpty else { return }

    if let record {
      let metadata = record.featureSidecarMetadata
      for nodeID in matchingNodeIDs {
        featureSidecarByNodeID[nodeID] = metadata
      }
      if let reminderIdentifier = ReminderProjectionIdentity.normalized(reminderIdentifier) {
        featureSidecarByReminderIdentifier[reminderIdentifier] = metadata
      }
    } else {
      for nodeID in matchingNodeIDs {
        featureSidecarByNodeID.removeValue(forKey: nodeID)
      }
      if let reminderIdentifier = ReminderProjectionIdentity.normalized(reminderIdentifier) {
        featureSidecarByReminderIdentifier.removeValue(forKey: reminderIdentifier)
      }
    }
  }

  func runtimeTaskSnapshots(
    overridingSourceDocuments: [String: ReminderNoteSourceDocument] = [:]
  ) -> [String: ReminderMetadataSnapshotEngine.TaskSnapshot] {
    var snapshots: [String: ReminderMetadataSnapshotEngine.TaskSnapshot] = [:]

    for project in projects {
      for entry in project.document.flatten() where entry.node.type.isTask {
        guard let reminderExternalIdentifier = ReminderProjectionIdentity.normalized(
          entry.node.reminderExternalIdentifier
        ) else {
          continue
        }
        let reminderIdentifier = ReminderProjectionIdentity.normalized(entry.node.reminderIdentifier)
          ?? reminderExternalIdentifier
        let sourceDocument =
          overridingSourceDocuments[reminderExternalIdentifier]
          ?? ReminderNoteSourceMutationService.plan(
            for: entry.node,
            reminderExternalIdentifierResolver: { node in
              ReminderProjectionIdentity.normalized(node.reminderExternalIdentifier)
            }
          ).document
        let reminderMetadata =
          reminderMetadataByReminderIdentifier[reminderIdentifier]
          ?? reminderMetadataByNodeID[entry.node.id]
          ?? .empty
        let modifiedAt = reminderModifiedAtByReminderExternalIdentifier[reminderExternalIdentifier]
          ?? .distantPast

        snapshots[reminderExternalIdentifier] = ReminderMetadataSnapshotEngine.TaskSnapshot(
          reminderIdentifier: reminderIdentifier,
          reminderExternalIdentifier: reminderExternalIdentifier,
          title: entry.node.text,
          isCompleted: entry.node.type.isCompleted,
          createdAt: modifiedAt,
          modifiedAt: modifiedAt,
          reminderMetadata: reminderMetadata,
          sourceDocument: sourceDocument
        )
      }
    }

    return snapshots
  }
}

private extension ReminderNoteSourceLoader.LoadedTaskTree {
  func preservingRootNodeID(_ rootID: UUID) -> ReminderNoteSourceLoader.LoadedTaskTree {
    guard root.id != rootID else { return self }

    let remappedRoot = OutlineNode(
      id: rootID,
      canonicalID: root.canonicalID,
      text: root.text,
      type: root.type,
      referenceProjectID: root.referenceProjectID,
      children: root.children,
      isCollapsed: root.isCollapsed,
      migratedTaskItemID: root.migratedTaskItemID,
      reminderIdentifier: root.reminderIdentifier,
      reminderExternalIdentifier: root.reminderExternalIdentifier,
      attachments: root.attachments
    )
    var reminderMetadataByNodeID = reminderMetadataByNodeID
    if let rootMetadata = reminderMetadataByNodeID.removeValue(forKey: root.id) {
      reminderMetadataByNodeID[rootID] = rootMetadata
    }
    var featureSidecarByNodeID = featureSidecarByNodeID
    if let rootFeature = featureSidecarByNodeID.removeValue(forKey: root.id) {
      featureSidecarByNodeID[rootID] = rootFeature
    }
    return ReminderNoteSourceLoader.LoadedTaskTree(
      root: remappedRoot,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      featureSidecarByNodeID: featureSidecarByNodeID
    )
  }
}

private extension OutlineNode {
  var allNodeIDs: [UUID] {
    [id] + children.flatMap(\.allNodeIDs)
  }
}
