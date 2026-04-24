import Foundation

@MainActor
extension AppState {
  @discardableResult
  func send(
    _ command: AppCommand,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    switch command {
    case let .taskScheduleSplit(write):
      return await performTaskScheduleSplitWrite(write)

    case let .taskPresentationSplit(write):
      return await performTaskPresentationSplitWrite(write)

    case let .writeOwnerField(ownerStore, write):
      switch ownerStore {
      case .sidecar:
        return await handleSidecarOwnerFieldWrite(
          write,
          waitForEditorIdle: waitForEditorIdle
        )
      case .reminder:
        return await handleReminderOwnerFieldWrite(
          write,
          waitForEditorIdle: waitForEditorIdle
        )
      case .calendar:
        return await handleCalendarOwnerFieldWrite(
          write,
          waitForEditorIdle: waitForEditorIdle
        )
      }

    case let .externalOwnerChange(ownerStore, ownerIDs, changedFields):
      switch ownerStore {
      case .sidecar:
        return await handleSidecarExternalOwnerChange(
          ownerIDs: ownerIDs,
          changedFields: changedFields,
          waitForEditorIdle: waitForEditorIdle
        )
      case .reminder:
        return await handleReminderExternalOwnerChange(
          ownerIDs: ownerIDs,
          changedFields: changedFields,
          waitForEditorIdle: waitForEditorIdle
        )
      case .calendar:
        return await handleCalendarExternalOwnerChange(
          ownerIDs: ownerIDs,
          changedFields: changedFields,
          waitForEditorIdle: waitForEditorIdle
        )
      }
    }
  }

  @discardableResult
  private func handleSidecarOwnerFieldWrite(
    _ write: AppOwnerFieldWrite,
    waitForEditorIdle: Bool
  ) async -> Bool {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else { return false }
    }

    var payload = loadRuntimeProjectionSidecarPayload()
    var affectedProjectIDs = payload.cutDuplicateProjectReminderConnections()
    let syncSubject: String
    var workspaceOrderedProjectIDs: [UUID]?
    var removedTaskRuntimeStateReminderExternalIdentifiers: [String] = []

    switch write {
    case let .reminderListBinding(connection):
      guard let reminderListExternalIdentifier = normalizedProjectionValue(
        connection.reminderListExternalIdentifier
      ) else {
        syncStatus = "Sidecar mapping write skipped (invalid external identifier)"
        return false
      }
      payload.upsertProjectReminderConnection(
        projectID: connection.projectID,
        reminderListIdentifier: connection.reminderListIdentifier,
        reminderListExternalIdentifier: reminderListExternalIdentifier
      )
      affectedProjectIDs.insert(connection.projectID)
      syncSubject = "Sidecar mapping"

    case let .removeReminderListBinding(projectID):
      payload.removeProjectReminderConnection(projectID: projectID)
      affectedProjectIDs.insert(projectID)
      syncSubject = "Sidecar mapping"

    case let .projectMetadata(write):
      guard
        let reminderListExternalIdentifier = resolvedProjectReminderListExternalIdentifier(
          projectID: write.projectID,
          payload: payload
        )
      else {
        syncStatus = "Sidecar project metadata write skipped (owner unresolved)"
        return false
      }
      payload.mutateProjectMetadata(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        mutation: write.mutation
      )
      affectedProjectIDs.insert(write.projectID)
      syncSubject = "Sidecar project metadata"

    case let .treeStructure(write):
      guard let reminderListExternalIdentifier = resolvedProjectReminderListExternalIdentifier(
        projectID: write.projectID,
        payload: payload
      ) else {
        syncStatus = "Sidecar tree structure write skipped (owner unresolved)"
        return false
      }
      payload.mutateProjectTreeStructure(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        rootNodes: write.rootNodes
      )
      affectedProjectIDs.insert(write.projectID)
      syncSubject = "Sidecar tree structure"

    case let .ordering(write):
      switch write.mutation {
      case let .project(projectID, orderedTopLevelReminderExternalIdentifiers):
        guard let reminderListExternalIdentifier = resolvedProjectReminderListExternalIdentifier(
          projectID: projectID,
          payload: payload
        ) else {
          syncStatus = "Sidecar ordering write skipped (owner unresolved)"
          return false
        }
        payload.mutateProjectOrdering(
          reminderListExternalIdentifier: reminderListExternalIdentifier,
          orderedTopLevelReminderExternalIdentifiers: orderedTopLevelReminderExternalIdentifiers
        )
        affectedProjectIDs.insert(projectID)
      case let .workspace(orderedProjectIDs):
        let normalizedProjectIDs = Array(NSOrderedSet(array: orderedProjectIDs)) as? [UUID]
          ?? orderedProjectIDs
        guard !normalizedProjectIDs.isEmpty else {
          syncStatus = "Sidecar ordering write skipped (empty scope)"
          return false
        }
        workspaceOrderedProjectIDs = normalizedProjectIDs
        affectedProjectIDs.formUnion(normalizedProjectIDs)
      }
      syncSubject = "Sidecar ordering"

    case let .appSupplement(write):
      guard
        let supplementResult = mutateAppSupplement(
          write,
          payload: &payload
        ),
        !supplementResult.affectedProjectIDs.isEmpty
      else {
        syncStatus = "Sidecar app supplement write skipped (owner unresolved)"
        return false
      }
      affectedProjectIDs.formUnion(supplementResult.affectedProjectIDs)
      removedTaskRuntimeStateReminderExternalIdentifiers =
        supplementResult.removedTaskRuntimeStateReminderExternalIdentifiers
      syncSubject = "Sidecar app supplement"

    case .listMetadata,
      .taskFields,
      .eventFields:
      syncStatus = "Sidecar write skipped (unsupported field)"
      return false
    }

    saveRuntimeProjectionSidecarPayload(payload)

    guard !affectedProjectIDs.isEmpty else {
      syncStatus = "\(syncSubject) write skipped (empty scope)"
      return false
    }

    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else {
      syncStatus = "\(syncSubject) saved"
      return true
    }

    snapshot.syncSidecarState(payload: payload)
    for reminderExternalIdentifier in removedTaskRuntimeStateReminderExternalIdentifiers {
      snapshot.taskSourceRuntimeStateByReminderExternalIdentifier.removeValue(
        forKey: reminderExternalIdentifier
      )
    }
    installCachedRuntimeProjectionSnapshot(snapshot)

    if let workspaceOrderedProjectIDs {
      _ = patchRuntimeProjectionWorkspaceOrder(
        workspaceOrderedProjectIDs,
        snapshot: &snapshot,
        payload: &payload
      )
    } else {
      let scopedProjectIDs = affectedProjectIDs.intersection(Set(snapshot.projects.map(\.id)))
      if let anchorProjectID = scopedProjectIDs.sorted(by: { $0.uuidString < $1.uuidString }).first,
        let store = projectDocumentStore(for: anchorProjectID)
      {
        var recomputePayload = payload
        if await patchRuntimeProjectionProjects(
          from: store,
          projectIDs: scopedProjectIDs,
          snapshot: &snapshot,
          payload: &recomputePayload
        ) {
          payload = recomputePayload
        }
      }
    }

    await invalidateWorkspaceProjectCaches(for: affectedProjectIDs)
    await syncWorkspaceProjectIdentities(
      for: affectedProjectIDs,
      snapshot: snapshot
    )
    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    saveRuntimeProjectionSidecarPayload(payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
    bumpWorkspaceTreeRevision()
    syncStarted = true
    syncStatus = "\(syncSubject) updated (\(affectedProjectIDs.count) project)"
    return true
  }

  @discardableResult
  private func handleSidecarExternalOwnerChange(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool
  ) async -> Bool {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else { return false }
    }

    let handlesReminderListBinding = changedFields.contains(.reminderListBinding)
    let handlesProjectMetadata = changedFields.contains(.projectMetadata)
    let handlesTreeStructure = changedFields.contains(.treeStructure)
    let handlesOrdering = changedFields.contains(.ordering)
    let handlesAppSupplement = changedFields.contains(.appSupplement)
    guard
      handlesReminderListBinding || handlesProjectMetadata || handlesTreeStructure || handlesOrdering
        || handlesAppSupplement
    else {
      syncStatus = "Sidecar external change skipped (unsupported field)"
      return false
    }

    var payload = loadRuntimeProjectionSidecarPayload()
    let disconnectedProjectIDs = payload.cutDuplicateProjectReminderConnections()
    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else {
      syncStatus = "Sidecar external change skipped (projection unavailable)"
      return false
    }

    var affectedProjectIDs = disconnectedProjectIDs
    if handlesReminderListBinding {
      affectedProjectIDs.formUnion(payload.affectedProjectIDs(forOwnerIDs: ownerIDs))
    }
    if handlesProjectMetadata {
      affectedProjectIDs.formUnion(
        payload.affectedProjectIDsForProjectMetadataOwnerIDs(ownerIDs)
      )
    }
    if handlesTreeStructure || handlesOrdering {
      affectedProjectIDs.formUnion(
        payload.affectedProjectIDsForProjectScopedOwnerIDs(ownerIDs)
      )
    }
    if handlesAppSupplement {
      affectedProjectIDs.formUnion(
        affectedProjectIDsForAppSupplementOwnerIDs(
          ownerIDs,
          snapshot: snapshot
        )
      )
    }
    guard !affectedProjectIDs.isEmpty else {
      syncStatus = "Sidecar external change skipped (scope unresolved)"
      return false
    }

    let scopedProjectIDs = affectedProjectIDs.intersection(Set(snapshot.projects.map(\.id)))
    if let anchorProjectID = scopedProjectIDs.sorted(by: { $0.uuidString < $1.uuidString }).first,
      let store = projectDocumentStore(for: anchorProjectID)
    {
      var recomputePayload = payload
      guard await patchRuntimeProjectionProjects(
        from: store,
        projectIDs: scopedProjectIDs,
        snapshot: &snapshot,
        payload: &recomputePayload
      ) else {
        syncStatus = "Sidecar external change skipped (scoped recompute failed)"
        return false
      }
      payload = recomputePayload
    }
    if handlesOrdering,
      let workspaceOrderedProjectIDs = workspaceOrderedProjectIDs(
        payload: payload,
        snapshot: snapshot
      )
    {
      _ = patchRuntimeProjectionWorkspaceOrder(
        workspaceOrderedProjectIDs,
        snapshot: &snapshot,
        payload: &payload
      )
    }

    await invalidateWorkspaceProjectCaches(for: affectedProjectIDs)
    await syncWorkspaceProjectIdentities(
      for: affectedProjectIDs,
      snapshot: snapshot
    )
    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    saveRuntimeProjectionSidecarPayload(payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
    bumpWorkspaceTreeRevision()
    syncStarted = true
    syncStatus = "Scoped sidecar refresh (\(affectedProjectIDs.count) project)"
    return true
  }

  private func mutateAppSupplement(
    _ write: AppSupplementWrite,
    payload: inout ReminderProjectionSidecarPayload
  ) -> (
    affectedProjectIDs: Set<UUID>,
    removedTaskRuntimeStateReminderExternalIdentifiers: [String]
  )? {
    switch write.mutation {
    case let .projectBoardOrder(projectID, boardOrder):
      guard let reminderListExternalIdentifier = resolvedProjectReminderListExternalIdentifier(
        projectID: projectID,
        payload: payload
      ) else {
        return nil
      }
      payload.mutateProjectBoardOrder(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        boardOrder: boardOrder
      )
      return ([projectID], [])

    case let .taskScheduledDuration(taskID, scheduledDurationMinutes):
      guard
        let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(
          taskID: taskID
        )
      else {
        return nil
      }
      payload.mutateTaskAppSupplement(
        reminderExternalIdentifier: reminderExternalIdentifier
      ) { record in
        record.scheduledDurationMinutes = scheduledDurationMinutes
      }
      return (resolvedTaskOwnerProjectIDs(taskID: taskID), [])

    case let .taskPresentation(taskID, boardStage, importance, isFlagged):
      guard
        let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(
          taskID: taskID
        )
      else {
        return nil
      }
      payload.mutateTaskAppSupplement(
        reminderExternalIdentifier: reminderExternalIdentifier
      ) { record in
        record.boardStageRaw = boardStage.rawValue
        record.importanceRaw = importance.rawValue
        record.isFlagged = isFlagged
      }
      return (resolvedTaskOwnerProjectIDs(taskID: taskID), [])

    case let .taskPlannedWorkProgress(taskID, completedWorkUnits, completedWorkUnitDatesRaw):
      guard
        let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(
          taskID: taskID
        )
      else {
        return nil
      }
      payload.mutateTaskAppSupplement(
        reminderExternalIdentifier: reminderExternalIdentifier
      ) { record in
        record.completedWorkUnits = completedWorkUnits
        record.completedWorkUnitDatesRaw = completedWorkUnitDatesRaw
      }
      return (resolvedTaskOwnerProjectIDs(taskID: taskID), [])

    case let .removeDeletedTaskSidecars(projectID, reminderExternalIdentifiers):
      let normalizedReminderExternalIdentifiers =
        Array(
          NSOrderedSet(
            array: reminderExternalIdentifiers.compactMap(normalizedProjectionValue)
          )
        ) as? [String] ?? []
      for reminderExternalIdentifier in normalizedReminderExternalIdentifiers {
        payload.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
          forKey: reminderExternalIdentifier
        )
      }
      return ([projectID], normalizedReminderExternalIdentifiers)

    case let .removeProjectSidecars(
      projectID,
      reminderListExternalIdentifier,
      reminderExternalIdentifiers
    ):
      guard
        let normalizedReminderListExternalIdentifier = normalizedProjectionValue(
          reminderListExternalIdentifier
        )
      else {
        return nil
      }
      let normalizedReminderExternalIdentifiers =
        Array(
          NSOrderedSet(
            array: reminderExternalIdentifiers.compactMap(normalizedProjectionValue)
          )
        ) as? [String] ?? []
      payload.projectRootStructureByReminderListExternalIdentifier.removeValue(
        forKey: normalizedReminderListExternalIdentifier
      )
      payload.projectTaskOrderByReminderListExternalIdentifier.removeValue(
        forKey: normalizedReminderListExternalIdentifier
      )
      payload.projectFeatureSidecarByReminderListExternalIdentifier.removeValue(
        forKey: normalizedReminderListExternalIdentifier
      )
      for reminderExternalIdentifier in normalizedReminderExternalIdentifiers {
        payload.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
          forKey: reminderExternalIdentifier
        )
      }
      let orderedReminderListExternalIdentifiers = payload.workspaceStructureRecord?
        .orderedReminderListExternalIdentifiers
        .filter { $0 != normalizedReminderListExternalIdentifier } ?? []
      payload.workspaceStructureRecord = ReminderWorkspaceStructureMutationService.record(
        orderedReminderListExternalIdentifiers: orderedReminderListExternalIdentifiers,
        existing: payload.workspaceStructureRecord
      )
      return ([projectID], normalizedReminderExternalIdentifiers)

    case let .restoreArchivedProjectSidecars(
      projectID,
      reminderListExternalIdentifier,
      archiveBundle,
      restoredTaskIdentities
    ):
      guard let normalizedReminderListExternalIdentifier = normalizedProjectionValue(
        reminderListExternalIdentifier
      ) else {
        return nil
      }
      payload = ProjectLifecycleService.restoredPayload(
        from: archiveBundle,
        restoredReminderListExternalIdentifier: normalizedReminderListExternalIdentifier,
        restoredTaskIdentities: restoredTaskIdentities,
        payload: payload
      )
      let removedReminderExternalIdentifiers =
        archiveBundle.taskBundles.map(\.reminderExternalIdentifier).compactMap(normalizedProjectionValue)
      return ([projectID], removedReminderExternalIdentifiers)
    }
  }

  private func resolvedTaskReminderExternalIdentifier(taskID: UUID) -> String? {
    if let reminderExternalIdentifier = cachedOutlinerRuntimeProjectionSnapshot?
      .taskLocation(for: taskID)?
      .node
      .reminderExternalIdentifier
    {
      return normalizedProjectionValue(reminderExternalIdentifier)
    }
    return normalizedProjectionValue(TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID))
  }

  private func resolvedTaskOwnerProjectIDs(taskID: UUID) -> Set<UUID> {
    if let snapshot = cachedOutlinerRuntimeProjectionSnapshot,
      let location = snapshot.taskLocation(for: taskID)
    {
      return [snapshot.projects[location.projectIndex].id]
    }
    if let projectID = TaskIdentityBridgeStore.record(for: taskID)?.ownerProjectID {
      return [projectID]
    }
    return []
  }

  private func affectedProjectIDsForAppSupplementOwnerIDs(
    _ ownerIDs: [String],
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> Set<UUID> {
    let resolvedUUIDs = Set(ownerIDs.compactMap(UUID.init(uuidString:)))
    guard !resolvedUUIDs.isEmpty else { return [] }

    var affectedProjectIDs = Set(
      snapshot.projects.compactMap { project in
        resolvedUUIDs.contains(project.id) ? project.id : nil
      }
    )

    for taskID in resolvedUUIDs {
      if let location = snapshot.taskLocation(for: taskID) {
        affectedProjectIDs.insert(snapshot.projects[location.projectIndex].id)
      }
    }

    return affectedProjectIDs
  }

  private func resolvedProjectReminderListExternalIdentifier(
    projectID: UUID,
    payload: ReminderProjectionSidecarPayload
  ) -> String? {
    if let reminderListExternalIdentifier = payload
      .projectConnectionSidecarByReminderListExternalIdentifier
      .first(where: { $0.value.projectID == projectID })?
      .key
    {
      return normalizedProjectionValue(reminderListExternalIdentifier)
    }
    return resolvedProjectReminderListExternalIdentifier(projectID: projectID)
  }

  private func workspaceOrderedProjectIDs(
    payload: ReminderProjectionSidecarPayload,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> [UUID]? {
    guard let workspaceStructureRecord = payload.workspaceStructureRecord else { return nil }

    let payloadProjectIDsByExternalIdentifier = payload
      .projectConnectionSidecarByReminderListExternalIdentifier
      .reduce(into: [String: UUID]()) { partialResult, entry in
        partialResult[entry.key] = entry.value.projectID
      }
    let snapshotProjectIDsByExternalIdentifier = Dictionary(
      uniqueKeysWithValues: snapshot.projectReminderListExternalIdentifierByProjectID.compactMap { entry in
        normalizedProjectionValue(entry.value).map { ($0, entry.key) }
      }
    )
    let orderedProjectIDs = workspaceStructureRecord.orderedReminderListExternalIdentifiers.compactMap {
      payloadProjectIDsByExternalIdentifier[$0] ?? snapshotProjectIDsByExternalIdentifier[$0]
    }
    return orderedProjectIDs.isEmpty ? nil : orderedProjectIDs
  }

  func syncWorkspaceProjectIdentities(
    for projectIDs: Set<UUID>,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) async {
    guard let workspaceTreeRepository else { return }

    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
    for projectID in projectIDs {
      guard let project = projectsByID[projectID] else { continue }
      let linkedNodes =
        (try? await workspaceTreeRepository.fetchProjectNodes(
          canonicalProjectID: projectID,
          includeArchived: true
        )) ?? []
      for node in linkedNodes {
        _ = try? await workspaceTreeRepository.updateProjectIdentity(
          of: node.id,
          title: project.title,
          colorHex: snapshot.projectColorHexByProjectID[projectID],
          reminderListIdentifier: snapshot.projectReminderListIdentifierByProjectID[projectID],
          reminderListExternalIdentifier:
            snapshot.projectReminderListExternalIdentifierByProjectID[projectID]
        )
      }
    }
  }
}

extension ReminderProjectionSidecarPayload {
  mutating func cutDuplicateProjectReminderConnections() -> Set<UUID> {
    guard !projectConnectionSidecarByReminderListExternalIdentifier.isEmpty else {
      return []
    }

    func shouldReplace(_ lhs: ReminderProjectConnectionSidecarRecord, _ rhs: ReminderProjectConnectionSidecarRecord)
      -> Bool
    {
      lhs.updatedAt != rhs.updatedAt ? lhs.updatedAt > rhs.updatedAt
        : lhs.projectID.uuidString > rhs.projectID.uuidString
    }

    var bestByExternalIdentifier: [String: ReminderProjectConnectionSidecarRecord] = [:]

    for (key, record) in projectConnectionSidecarByReminderListExternalIdentifier {
      guard let normalizedListIdentifier = ReminderProjectionIdentity.normalized(key) else {
        continue
      }

      let sanitizedRecord = ReminderProjectConnectionSidecarRecord(
        projectID: record.projectID,
        reminderListIdentifier: ReminderProjectionIdentity.normalized(record.reminderListIdentifier),
        reminderListExternalIdentifier: normalizedListIdentifier,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt
      )

      if let existing = bestByExternalIdentifier[normalizedListIdentifier],
        !shouldReplace(sanitizedRecord, existing)
      {
        continue
      }
      bestByExternalIdentifier[normalizedListIdentifier] = sanitizedRecord
    }

    var bestByProjectID: [UUID: ReminderProjectConnectionSidecarRecord] = [:]
    for record in bestByExternalIdentifier.values {
      if let existing = bestByProjectID[record.projectID], !shouldReplace(record, existing) {
        continue
      }
      bestByProjectID[record.projectID] = record
    }

    let normalizedConnections = Dictionary(uniqueKeysWithValues: bestByProjectID.values.map {
      ($0.reminderListExternalIdentifier, $0)
    })
    let beforeProjectIDs = Set(
      projectConnectionSidecarByReminderListExternalIdentifier.values.map(\.projectID)
    )
    let afterProjectIDs = Set(normalizedConnections.values.map(\.projectID))
    guard beforeProjectIDs != afterProjectIDs else {
      projectConnectionSidecarByReminderListExternalIdentifier = normalizedConnections
      return []
    }

    projectConnectionSidecarByReminderListExternalIdentifier = normalizedConnections
    return beforeProjectIDs.subtracting(afterProjectIDs)
  }

  mutating func upsertProjectReminderConnection(
    projectID: UUID,
    reminderListIdentifier: String?,
    reminderListExternalIdentifier: String,
    now: Date = .now
  ) {
    projectConnectionSidecarByReminderListExternalIdentifier =
      projectConnectionSidecarByReminderListExternalIdentifier.filter { key, value in
        value.projectID != projectID || key == reminderListExternalIdentifier
      }

    projectConnectionSidecarByReminderListExternalIdentifier[reminderListExternalIdentifier] =
      ReminderProjectConnectionSidecarRecord.record(
        projectID: projectID,
        reminderListIdentifier: reminderListIdentifier,
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        existing: projectConnectionSidecarByReminderListExternalIdentifier[
          reminderListExternalIdentifier
        ],
        now: now
      )
  }

  mutating func removeProjectReminderConnection(projectID: UUID) {
    projectConnectionSidecarByReminderListExternalIdentifier =
      projectConnectionSidecarByReminderListExternalIdentifier.filter { _, value in
        value.projectID != projectID
      }
  }

  mutating func mutateProjectMetadata(
    reminderListExternalIdentifier: String,
    mutation: ProjectMetadataMutation
  ) {
    var record =
      projectFeatureSidecarByReminderListExternalIdentifier[reminderListExternalIdentifier]
      ?? ReminderProjectFeatureMutationService.projectFeatureRecord(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        projectNoteMarkdown: "",
        localStartDate: nil,
        localDeadline: nil,
        progressStageRaw: nil,
        boardOrder: nil,
        existing: nil
      )

    switch mutation {
    case let .projectNote(note):
      record.projectNoteMarkdown = note

    case let .progressStage(stage):
      record.progressStageRaw = stage.storageRawValue
    }

    if record.hasMeaningfulContent {
      projectFeatureSidecarByReminderListExternalIdentifier[reminderListExternalIdentifier] =
        record
    } else {
      projectFeatureSidecarByReminderListExternalIdentifier.removeValue(
        forKey: reminderListExternalIdentifier
      )
    }
  }

  mutating func mutateProjectTreeStructure(
    reminderListExternalIdentifier: String,
    rootNodes: [ReminderProjectRootNodeRecord]
  ) {
    projectRootStructureByReminderListExternalIdentifier[reminderListExternalIdentifier] =
      ReminderProjectRootStructureMutationService.record(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        rootNodes: rootNodes,
        existing: projectRootStructureByReminderListExternalIdentifier[
          reminderListExternalIdentifier
        ]
      )

    mutateProjectOrdering(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      orderedTopLevelReminderExternalIdentifiers: rootNodes.compactMap { record in
        guard case let .task(reminderExternalIdentifier, _) = record else { return nil }
        return reminderExternalIdentifier
      }
    )
  }

  mutating func mutateProjectOrdering(
    reminderListExternalIdentifier: String,
    orderedTopLevelReminderExternalIdentifiers: [String]
  ) {
    let normalizedOrderedTopLevelReminderExternalIdentifiers =
      Array(
        NSOrderedSet(
          array: orderedTopLevelReminderExternalIdentifiers.compactMap(ReminderProjectionIdentity.normalized)
        )
      ) as? [String] ?? []

    projectTaskOrderByReminderListExternalIdentifier[reminderListExternalIdentifier] =
      ReminderProjectTaskOrderMutationService.record(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        orderedTopLevelReminderExternalIdentifiers: normalizedOrderedTopLevelReminderExternalIdentifiers,
        existing: projectTaskOrderByReminderListExternalIdentifier[
          reminderListExternalIdentifier
        ]
      )

    if let existingRootStructure = projectRootStructureByReminderListExternalIdentifier[
      reminderListExternalIdentifier
    ],
      let reorderedRootNodes = ReminderProjectRootStructureMutationService.reorderedRootTaskRecords(
        in: existingRootStructure.rootNodes,
        orderedReminderExternalIdentifiers: normalizedOrderedTopLevelReminderExternalIdentifiers
      )
    {
      projectRootStructureByReminderListExternalIdentifier[reminderListExternalIdentifier] =
        ReminderProjectRootStructureMutationService.record(
          reminderListExternalIdentifier: reminderListExternalIdentifier,
          rootNodes: reorderedRootNodes,
          existing: existingRootStructure
        )
    }
  }

  mutating func mutateProjectBoardOrder(
    reminderListExternalIdentifier: String,
    boardOrder: Int?
  ) {
    var record =
      projectFeatureSidecarByReminderListExternalIdentifier[reminderListExternalIdentifier]
      ?? ReminderProjectFeatureMutationService.projectFeatureRecord(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        projectNoteMarkdown: "",
        localStartDate: nil,
        localDeadline: nil,
        progressStageRaw: nil,
        boardOrder: nil,
        existing: nil
      )

    record.boardOrder = boardOrder
    if record.hasMeaningfulContent {
      projectFeatureSidecarByReminderListExternalIdentifier[reminderListExternalIdentifier] =
        record
    } else {
      projectFeatureSidecarByReminderListExternalIdentifier.removeValue(
        forKey: reminderListExternalIdentifier
      )
    }
  }

  mutating func mutateTaskAppSupplement(
    reminderExternalIdentifier: String,
    mutate: (inout ReminderTaskFeatureSidecarRecord) -> Void
  ) {
    var record =
      taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier]
      ?? AppFeatureMutationService.taskFeatureRecord(
        reminderExternalIdentifier: reminderExternalIdentifier,
        featureSidecar: OutlinerTaskSidecarMetadata()
      )
    mutate(&record)

    if record.hasMeaningfulContent {
      taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier] = record
    } else {
      taskFeatureSidecarByReminderExternalIdentifier.removeValue(
        forKey: reminderExternalIdentifier
      )
    }
  }

  func affectedProjectIDs(forOwnerIDs ownerIDs: [String]) -> Set<UUID> {
    let normalizedOwnerIDs = Set(ownerIDs.compactMap(ReminderProjectionIdentity.normalized))
    guard !normalizedOwnerIDs.isEmpty else { return [] }

    return Set(
      projectConnectionSidecarByReminderListExternalIdentifier.compactMap { key, value in
        normalizedOwnerIDs.contains(key)
          || value.reminderListIdentifier.map(normalizedOwnerIDs.contains) == true
          || normalizedOwnerIDs.contains(value.projectID.uuidString)
          ? value.projectID
          : nil
      }
    )
  }

  func affectedProjectIDsForProjectMetadataOwnerIDs(_ ownerIDs: [String]) -> Set<UUID> {
    var resolvedProjectIDs = Set(ownerIDs.compactMap(UUID.init(uuidString:)))
    let normalizedOwnerIDs = Set(ownerIDs.compactMap(ReminderProjectionIdentity.normalized))
    guard !normalizedOwnerIDs.isEmpty else { return resolvedProjectIDs }

    for (reminderListExternalIdentifier, connection)
      in projectConnectionSidecarByReminderListExternalIdentifier
    {
      guard normalizedOwnerIDs.contains(reminderListExternalIdentifier) else { continue }
      resolvedProjectIDs.insert(connection.projectID)
    }
    return resolvedProjectIDs
  }

  func affectedProjectIDsForProjectScopedOwnerIDs(_ ownerIDs: [String]) -> Set<UUID> {
    affectedProjectIDsForProjectMetadataOwnerIDs(ownerIDs)
  }
}

extension OutlineProjectionRuntimeSnapshot {
  func withProjectConnectionSidecarState(
    _ connections: [String: ReminderProjectConnectionSidecarRecord]
  ) -> OutlineProjectionRuntimeSnapshot {
    var copy = self
    copy.applyProjectConnectionSidecarState(connections)
    return copy
  }

  mutating func applyProjectConnectionSidecarState(
    _ connections: [String: ReminderProjectConnectionSidecarRecord]
  ) {
    guard !connections.isEmpty else { return }

    let oldExternalIdentifiers = Set(connections.values.map(\.projectID))
    for projectID in oldExternalIdentifiers {
      projectReminderListIdentifierByProjectID.removeValue(forKey: projectID)
      projectReminderListExternalIdentifierByProjectID.removeValue(forKey: projectID)
    }

    for connection in connections.values {
      if let reminderListIdentifier = ReminderProjectionIdentity.normalized(
        connection.reminderListIdentifier
      ) {
        projectReminderListIdentifierByProjectID[connection.projectID] = reminderListIdentifier
      } else {
        projectReminderListIdentifierByProjectID.removeValue(forKey: connection.projectID)
      }
      projectReminderListExternalIdentifierByProjectID[connection.projectID] =
        connection.reminderListExternalIdentifier
    }
  }
}
