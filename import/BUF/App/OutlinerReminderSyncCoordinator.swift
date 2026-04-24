import Foundation

@MainActor
extension AppState {
  func evaluateOutlinerReminderConflict(
    reminderExternalIdentifier: String,
    localNormalizedNoteText: String,
    remoteObservation: ReminderNoteSourceObservation,
    runtimeState: ReminderTaskSourceRuntimeState?
  ) -> ReminderNoteSourceConflictDecision {
    ReminderNoteSourceConflictGate.evaluate(
      reminderExternalIdentifier: reminderExternalIdentifier,
      localNormalizedNoteText: localNormalizedNoteText,
      remoteObservation: remoteObservation,
      runtimeState: runtimeState
    )
  }

  func shouldApplyOutlinerRemoteDeletion(
    for reminderIdentifier: String,
    taskState: OutlinerIntegratedTaskState,
    lastLocalWriteAt: Date?,
    now: Date = .now
  ) -> Bool {
    ReminderConflictPolicy.shouldApplyRemoteDeletion(
      outlinerReminderConflictContext(
        for: reminderIdentifier,
        taskState: taskState,
        remoteModifiedAt: nil,
        lastLocalWriteAt: lastLocalWriteAt,
        now: now
      ),
      now: now
    )
  }

  private func outlinerReminderConflictContext(
    for _: String,
    taskState: OutlinerIntegratedTaskState,
    remoteModifiedAt: Date?,
    lastLocalWriteAt: Date?,
    now: Date
  ) -> ReminderConflictPolicy.Context {
    let hasPendingLocalChanges = taskState.isDirty
    let pendingChangeAge: TimeInterval? =
      hasPendingLocalChanges
      ? max(0, now.timeIntervalSince(taskState.localUpdatedAt))
      : nil
    return ReminderConflictPolicy.Context(
      hasPendingLocalChanges: hasPendingLocalChanges,
      pendingChangeAge: pendingChangeAge,
      lastLocalWriteAt: lastLocalWriteAt ?? (hasPendingLocalChanges ? taskState.localUpdatedAt : nil),
      remoteModifiedAt: remoteModifiedAt,
      pushFailureCount: 0
    )
  }
}

extension OutlinerView {
  func refreshLinkedSnapshots() async {
    let projections = nodeBasedProjections()
    var didUpdateSnapshotMetadata = false
    for projection in projections {
      guard liveSync.linkedReminderIdentifier(for: projection) != nil else { continue }
      if let snapshot = await liveSync.refreshProjection(projection, appState: appState) {
        storeSnapshotMetadata(
          for: projection.nodeID,
          snapshot: snapshot,
          triggerAutoPush: false,
          persistState: false
        )
        didUpdateSnapshotMetadata = true
      }
    }
    synchronizeMirrorAuxiliaryState(in: syncedProjects)
    if didUpdateSnapshotMetadata {
      syncEditorSessionState(triggerAutoPush: false)
    }
  }

  func pullRemoteChanges() async {
    guard firstSyncCompleted || !resolvedReminderLinksByContentID().isEmpty else { return }
    guard !hasLocalSyncWorkInFlight else {
      hasPendingRemotePull = true
      return
    }

    let projections = nodeBasedProjections()
    let remoteIndex = await liveSync.fetchRemoteReminderIndex(for: projections, appState: appState)
    guard liveSync.errorMessage == nil else { return }

    var updatedDocument = document
    var didChangeFromRemote = false
    var didUpdateSnapshotMetadata = false
    var remoteAppliedContentIDs: Set<UUID> = []
    var normalizationContentIDs: Set<UUID> = []

    let orderedProjections = projections.sorted {
      if $0.taskLine.indentDepth == $1.taskLine.indentDepth {
        return $0.sourceLineNumber < $1.sourceLineNumber
      }
      return $0.taskLine.indentDepth < $1.taskLine.indentDepth
    }

    for projection in orderedProjections {
      guard let linkedID = liveSync.linkedReminderIdentifier(for: projection) else {
        continue
      }

      let taskState = resolvedTaskState(for: projection.contentID, defaultTitle: projection.title)
      if hasUnresolvedReminderConflict(taskState) {
        continue
      }

      guard let remote = remoteIndex[projection.contentID] else {
        guard appState.shouldApplyOutlinerRemoteDeletion(
          for: linkedID,
          taskState: taskState,
          lastLocalWriteAt: liveSync.lastLocalWriteDate(for: linkedID)
        ) else {
          continue
        }
        removeReminderMetadata(for: linkedID, nodeID: projection.nodeID, triggerAutoPush: false)
        liveSync.unlinkProjection(projection)
        didChangeFromRemote = true
        continue
      }

      let reminderExternalIdentifier =
        normalizedNonEmptyString(remote.reminderExternalIdentifier)
        ?? normalizedNonEmptyString(taskState.reminderExternalIdentifier)
        ?? projection.contentID.uuidString.lowercased()
      let remoteObservation = remoteNoteObservation(from: remote)
      let conflictDecision = appState.evaluateOutlinerReminderConflict(
        reminderExternalIdentifier: reminderExternalIdentifier,
        localNormalizedNoteText: projection.encodedReminderNote,
        remoteObservation: remoteObservation,
        runtimeState: noteSourceRuntimeState(for: reminderExternalIdentifier)
      )

      if case let .conflict(conflictState) = conflictDecision {
        persistReminderNoteConflictState(conflictState, for: projection, remote: remote)
        liveSync.publishStatusMessage("동시에 수정된 note가 있어 자동 병합을 멈췄습니다.")
        didUpdateSnapshotMetadata = true
        continue
      }

      let currentTitle = projection.title
      var didUpdateFromRemote = false
      if case .applyRemote = conflictDecision,
         let importResult = applyRemoteNoteSourceImport(remote, to: projection, in: &updatedDocument)
      {
        didUpdateFromRemote = true
        if importResult.requiresNormalizationWrite {
          normalizationContentIDs.insert(projection.contentID)
        }
      }

      if remote.title != currentTitle {
        updatedDocument.updateNode(id: projection.nodeID) { $0.text = remote.title }
        didUpdateFromRemote = true
      }

      let currentCompleted = projection.taskLine.marker == .done
      if remote.isCompleted != currentCompleted {
        updatedDocument.updateNode(id: projection.nodeID) { node in
          node.type = .task(completed: remote.isCompleted)
        }
        didUpdateFromRemote = true
      }

      if didUpdateFromRemote {
        didChangeFromRemote = true
        remoteAppliedContentIDs.insert(projection.contentID)
      }
      if reminderNoteConflictState(for: reminderExternalIdentifier) != nil {
        persistReminderNoteConflictState(nil, for: projection, remote: remote)
      }
      recordObservedNoteSourceImport(
        reminderExternalIdentifier: reminderExternalIdentifier,
        remoteObservation: remoteObservation,
        rawPreservationPayloadRaw: remote.rawPreservationPayloadRaw
      )
      if storeObservedRemoteImport(remote, for: projection) {
        didUpdateSnapshotMetadata = true
      }
      didUpdateSnapshotMetadata = true
    }

    if didChangeFromRemote {
      commitDocumentChange(
        updatedDocument,
        pushUndoSnapshot: false,
        triggerAutoPush: false,
        commitReminderNoteDirectly: false
      )
      pendingReminderPushContentIDs.subtract(remoteAppliedContentIDs.subtracting(normalizationContentIDs))
    } else {
      synchronizeMirrorAuxiliaryState(in: syncedProjects)
      if didUpdateSnapshotMetadata {
        syncEditorSessionState(triggerAutoPush: false)
      }
    }
    if !normalizationContentIDs.isEmpty {
      enqueueReminderPushContentIDs(normalizationContentIDs)
      scheduleAutoPush(after: .milliseconds(150))
    }
  }

  func scheduleAutoPush(after delay: Duration = .milliseconds(1500)) {
    if isAutoPushing {
      hasPendingAutoPush = true
      return
    }

    autoPushTask?.cancel()
    autoPushTask = Task { @MainActor in
      do {
        try await Task.sleep(for: delay)
      } catch {
        autoPushTask = nil
        return
      }
      guard !Task.isCancelled else {
        autoPushTask = nil
        return
      }
      guard !shouldDeferPendingReminderPushForEditingFocus else {
        autoPushTask = nil
        hasPendingAutoPush = true
        rememberPendingReminderPushDeferralAnchorIfNeeded()
        return
      }
      autoPushTask = nil
      await pushLocalChanges()
    }
  }

  func pushLocalChanges(
    requestedContentIDs: Set<UUID>? = nil,
    directCommit: Bool = false
  ) async {
    guard !shouldDeferPendingReminderPushForEditingFocus else {
      if directCommit {
        hasPendingDirectReminderNoteCommit = true
      } else {
        hasPendingAutoPush = true
        rememberPendingReminderPushDeferralAnchorIfNeeded()
      }
      return
    }
    clearPendingReminderPushDeferralAnchor()

    let requestedPushContentIDs = requestedContentIDs ?? pendingReminderPushContentIDs
    let projections = nodeBasedProjections(
      for: requestedPushContentIDs.isEmpty ? nil : requestedPushContentIDs
    )
    let activeProjectionContentIDs = Set(projections.map(\.contentID))
    let missingProjectionContentIDs =
      requestedPushContentIDs.isEmpty ? [] : requestedPushContentIDs.subtracting(activeProjectionContentIDs)

    appState.beginEditorSession(
      id: outlinerSyncSessionID,
      syncRelevant: true,
      syncKind: .subtree,
      projectID: currentProjectID
    )
    isAutoPushing = true
    defer {
      appState.endEditorSession(id: outlinerSyncSessionID)
      isAutoPushing = false
      if hasPendingAutoPush {
        hasPendingAutoPush = false
        scheduleAutoPush()
      } else if hasPendingDirectReminderNoteCommit && !directCommit {
        hasPendingDirectReminderNoteCommit = false
        commitPendingReminderNoteSourceDirectSaveIfNeeded(
          excluding: reminderPushEditingBoundary
        )
      } else if hasPendingRemotePull {
        hasPendingRemotePull = false
        Task { @MainActor in
          await pullRemoteChanges()
        }
      }
      if !directCommit {
        scheduleProjectDetailSnapshotReloadAfterDeferralIfNeeded()
      }
    }
    var didMutateRuntimeSyncState = false
    let removalReferences = missingProjectionContentIDs
      .sorted(by: { $0.uuidString < $1.uuidString })
      .compactMap { pendingRemovalReference(for: $0) }

    var removedContentIDs: Set<UUID> = []
    do {
      let removedReferences = try await appState.removeReminderTasks(removalReferences)
      removedContentIDs = Set(removedReferences.map(\.taskID))
      for reference in removedReferences {
        liveSync.unlinkContentID(reference.taskID)
        if let reminderExternalIdentifier = normalizedNonEmptyString(reference.reminderExternalIdentifier) {
          removeTaskFeatureSidecarByReminderExternalIdentifier(for: reminderExternalIdentifier)
          removeTaskSourceRuntimeStateByReminderExternalIdentifier(for: reminderExternalIdentifier)
        }
        clearTaskSessionOverlay(for: reference.taskID)
        didMutateRuntimeSyncState = true
      }
    } catch {
      appState.errorMessage = error.localizedDescription
    }
    if !removedContentIDs.isEmpty {
      pendingReminderPushContentIDs.subtract(removedContentIDs)
    }
    guard !projections.isEmpty else {
      if didMutateRuntimeSyncState {
        synchronizeMirrorAuxiliaryState(in: syncedProjects)
        syncEditorSessionState(triggerAutoPush: false)
      }
      return
    }

    let remoteIndex = await liveSync.fetchRemoteReminderIndex(for: projections, appState: appState)
    guard liveSync.errorMessage == nil else { return }

    let orderedProjectionContentIDs = projections
      .sorted {
        if $0.taskLine.indentDepth == $1.taskLine.indentDepth {
          return $0.sourceLineNumber > $1.sourceLineNumber
        }
        return $0.taskLine.indentDepth > $1.taskLine.indentDepth
      }
      .map(\.contentID)

    var didPushAnyProjection = false
    var pushedContentIDs: Set<UUID> = []
    var createdReminderReferencesForRollback: [ReminderTaskReference] = []
    let projectReminderListIdentifiersByProjectID =
      appState.cachedOutlinerRuntimeProjectionSnapshot?.projectReminderListIdentifierByProjectID
      ?? [:]
    for contentID in orderedProjectionContentIDs {
      guard let projection = nodeBasedProjections(for: [contentID]).first else { continue }
      let taskState = resolvedTaskState(for: projection.contentID, defaultTitle: projection.title)
      if hasUnresolvedReminderConflict(taskState) {
        liveSync.publishStatusMessage("conflict가 남아 있는 task는 해제 전까지 reminder sync를 멈춥니다.")
        continue
      }

      guard let calendarIdentifier = resolvedOwnerCalendarIdentifier(
        for: projection,
        projectReminderListIdentifiersByProjectID: projectReminderListIdentifiersByProjectID
      ) else {
        continue
      }

      let noteSourceRuntimeState = noteSourceRuntimeState(
        for: projection.reminderExternalIdentifier ?? taskState.reminderExternalIdentifier
      )
      var effectiveEncodedReminderNote = projection.encodedReminderNote
      var effectiveRemoteModifiedAt = projection.remoteLastModifiedAt
      if let remote = remoteIndex[projection.contentID] {
        let reminderExternalIdentifier =
          normalizedNonEmptyString(remote.reminderExternalIdentifier)
          ?? normalizedNonEmptyString(taskState.reminderExternalIdentifier)
          ?? projection.contentID.uuidString.lowercased()
        let remoteObservation = remoteNoteObservation(from: remote)
        switch appState.evaluateOutlinerReminderConflict(
          reminderExternalIdentifier: reminderExternalIdentifier,
          localNormalizedNoteText: projection.encodedReminderNote,
          remoteObservation: remoteObservation,
          runtimeState: noteSourceRuntimeState
        ) {
        case let .conflict(conflictState):
          persistReminderNoteConflictState(conflictState, for: projection, remote: remote)
          didMutateRuntimeSyncState = true
          liveSync.publishStatusMessage("동시에 수정된 note가 있어 자동 병합 없이 conflict로 남겨 두었습니다.")
          continue
        case let .applyRemote(remoteObservation):
          effectiveEncodedReminderNote = remoteObservation.normalizedNoteText
          effectiveRemoteModifiedAt = remote.lastModifiedAt
        case .noRemoteNoteChange:
          effectiveRemoteModifiedAt = remote.lastModifiedAt
        }
      }
      let noteSourceMutation = ReminderNoteSourceMutationPlan(
        document: ReminderNoteSourceDocument(
          normalizedText: effectiveEncodedReminderNote,
          ast: ReminderNoteSourceCodec.parse(effectiveEncodedReminderNote).ast
        ),
        normalizedNoteHash: ReminderNoteSourceMutationService.hash(for: effectiveEncodedReminderNote)
      )
      if ReminderNoteSourceMutationService.shouldSkipWrite(
        exportHash: noteSourceMutation.normalizedNoteHash,
        runtimeState: noteSourceRuntimeState,
        remoteModifiedAt: effectiveRemoteModifiedAt
      ) {
        pushedContentIDs.insert(projection.contentID)
        continue
      }

      let operationRecord = ReminderSyncPendingOperationRecord(
        contentID: projection.contentID,
        projectID: projection.reminderOwnerProjectID ?? currentProjectID,
        calendarIdentifier: calendarIdentifier,
        reminderIdentifier: projection.reminderIdentifier,
        reminderExternalIdentifier: projection.reminderExternalIdentifier,
        baselineRemoteLastModifiedAt: projection.remoteLastModifiedAt,
        title: projection.title,
        isCompleted: projection.taskLine.marker == .done,
        unifiedReminderDate: projection.syncContract.reminderPayload.dueDate,
        hasExplicitTime: projection.syncContract.reminderPayload.hasExplicitTime,
        priority: projection.syncContract.reminderPayload.priority,
        recurrenceRuleRaw: OutlinerIntegratedStore.encodeRecurrence(
          projection.syncContract.reminderPayload.recurrence
        ),
        parentExternalIdentifier: projection.parentTaskRemoteExternalIdentifier,
        reminderNoteText: effectiveEncodedReminderNote,
        reminderRawPayloadRaw: taskState.reminderRawPayloadRaw,
        localUpdatedAt: projection.localUpdatedAt
      )
      let createdReminderDidNotExist =
        normalizedNonEmptyString(taskState.reminderIdentifier) == nil
        && normalizedNonEmptyString(taskState.reminderExternalIdentifier) == nil
        && liveSync.linkedReminderIdentifier(for: projection) == nil

      if let snapshot = await liveSync.saveProjection(
        projection,
        calendarIdentifier: calendarIdentifier,
        encodedNoteOverride: effectiveEncodedReminderNote,
        pendingOperationRecord: operationRecord,
        appState: appState
      ) {
        if directCommit && createdReminderDidNotExist {
          createdReminderReferencesForRollback.append(
            ReminderTaskReference(
              taskID: projection.contentID,
              reminderIdentifier: snapshot.reminderIdentifier,
              reminderExternalIdentifier: snapshot.reminderExternalIdentifier
            )
          )
        }
        pushedContentIDs.insert(projection.contentID)
        persistReminderNoteConflictState(nil, for: projection)
        updateTaskSourceRuntimeState(
          for: snapshot,
          exportedHash: noteSourceMutation.normalizedNoteHash
        )
        storeSidecarMetadata(
          for: snapshot.reminderIdentifier,
          projection: projection,
          requiredWorkDaysOverride: snapshot.requiredWorkDays == 0 ? nil : snapshot.requiredWorkDays,
          triggerAutoPush: false,
          persistState: false
        )
        storeSnapshotMetadata(
          for: projection.nodeID,
          snapshot: snapshot,
          triggerAutoPush: false,
          persistState: false
        )
        didPushAnyProjection = true
        didMutateRuntimeSyncState = true
      } else if directCommit && !createdReminderReferencesForRollback.isEmpty {
        await rollbackDirectReminderCommitOrphans(createdReminderReferencesForRollback)
        break
      }
    }
    if didPushAnyProjection {
      firstSyncCompleted = true
    }
    synchronizeMirrorAuxiliaryState(in: syncedProjects)
    if didMutateRuntimeSyncState {
      syncEditorSessionState(triggerAutoPush: false)
    }

    if !pushedContentIDs.isEmpty {
      pendingReminderPushContentIDs.subtract(pushedContentIDs)
    }
  }

  func rollbackDirectReminderCommitOrphans(_ createdReferences: [ReminderTaskReference]) async {
    let orderedReferences = createdReferences.reversed()

    let removedReferences: [ReminderTaskReference]
    do {
      removedReferences = try await appState.removeReminderTasks(Array(orderedReferences))
    } catch {
      appState.errorMessage = error.localizedDescription
      return
    }

    var didRollbackAny = false
    for reference in removedReferences {
      didRollbackAny = true
      liveSync.unlinkContentID(reference.taskID)
      if let reminderExternalIdentifier = normalizedNonEmptyString(reference.reminderExternalIdentifier) {
        removeTaskFeatureSidecarByReminderExternalIdentifier(for: reminderExternalIdentifier)
        removeTaskSourceRuntimeStateByReminderExternalIdentifier(
          for: reminderExternalIdentifier
        )
      }
      clearTaskSessionOverlay(for: reference.taskID)
    }

    guard didRollbackAny else { return }
    liveSync.publishStatusMessage(
      "child reminder 생성 뒤 parent note 저장이 실패해 새 reminder를 되돌렸습니다. 다시 시도해 주세요."
    )
    syncEditorSessionState(triggerAutoPush: false)
  }

  func remoteNoteObservation(
    from remote: OutlinerRemoteReminderImport
  ) -> ReminderNoteSourceObservation {
    ReminderNoteSourceObservation(
      normalizedNoteText: remote.parsedBody,
      normalizedNoteHash: ReminderNoteSourceMutationService.hash(for: remote.parsedBody),
      remoteModifiedAt: remote.lastModifiedAt
    )
  }

  func resolvedReminderReadOnlySurface(for nodeID: UUID) -> ReminderSyncReadOnlySurface? {
    guard let contentID = resolvedContentID(for: nodeID) else { return nil }
    let taskState = resolvedTaskState(
      for: contentID,
      defaultTitle: resolvedNode(id: nodeID, in: syncedProjects)?.text ?? ""
    )
    guard taskState.reminderBacked || normalizedNonEmptyString(taskState.reminderRawPayloadRaw) != nil else {
      return nil
    }
    return ReminderSyncReadOnlySurfaceBuilder.make(from: taskState.reminderRawPayloadRaw)
  }

  func hasUnresolvedReminderConflict(_ taskState: OutlinerIntegratedTaskState) -> Bool {
    reminderNoteConflictState(for: taskState.reminderExternalIdentifier) != nil
  }

  func resolvedReminderConflictSurface(
    for nodeID: UUID
  ) -> OutlineNodeReminderConflictSurface? {
    guard let contentID = resolvedContentID(for: nodeID) else { return nil }
    let taskState = resolvedTaskState(
      for: contentID,
      defaultTitle: resolvedNode(id: nodeID, in: syncedProjects)?.text ?? ""
    )
    let conflictState = reminderNoteConflictState(for: taskState.reminderExternalIdentifier)
    guard let excerpt = conflictState?.excerpt
      ?? normalizedNonEmptyString(taskState.reminderNoteConflictExcerpt)
    else {
      return nil
    }

    let ownerTitle = taskState.ownerProjectID.flatMap { ownerProjectID in
      syncedProjects.first(where: { $0.id == ownerProjectID })?.title
    } ?? syncedProjects.first(where: { $0.id == currentProjectID })?.title ?? "현재 프로젝트"

    let actionsEnabled = taskState.ownerProjectID == nil || taskState.ownerProjectID == currentProjectID
    return OutlineNodeReminderConflictSurface(
      ownerLabel: ownerTitle,
      excerpt: excerpt,
      diffPreview: conflictState?.diffPreview,
      isDiffExpanded: expandedReminderConflictDiffContentIDs.contains(contentID),
      actionsEnabled: actionsEnabled,
      isBusy: reminderConflictResolutionContentIDs.contains(contentID)
    )
  }

  func projection(for nodeID: UUID) -> OutlinerReminderProjection? {
    nodeBasedProjections().first(where: { $0.nodeID == nodeID })
  }

  func applyRemoteNoteSourceImport(
    _ remote: OutlinerRemoteReminderImport,
    to projection: OutlinerReminderProjection,
    in updatedDocument: inout OutlineDocument
  ) -> ReminderNoteSourceImportService.Result? {
    let currentNode =
      OutlineNodeTreeNavigator.findNode(id: projection.nodeID, in: updatedDocument.rootNodes)
      ?? resolvedNode(id: projection.nodeID, in: syncedProjects)
    guard let currentNode else { return nil }

    let parentReminderExternalIdentifier =
      normalizedNonEmptyString(currentNode.reminderExternalIdentifier)
      ?? normalizedNonEmptyString(projection.reminderExternalIdentifier)
      ?? normalizedNonEmptyString(remote.reminderExternalIdentifier)
      ?? projection.contentID.uuidString.lowercased()

    let importResult = ReminderNoteSourceImportService.materializeChildren(
      from: ReminderNoteSourceDocument(
        normalizedText: remote.parsedBody,
        ast: ReminderNoteSourceCodec.parse(remote.parsedBody).ast
      ),
      preservingExistingChildren: currentNode.children,
      parentReminderExternalIdentifier: parentReminderExternalIdentifier
    )
    updatedDocument.updateNode(id: projection.nodeID) { node in
      node.children = importResult.children
    }
    return importResult
  }

  func resolveReminderConflict(for nodeID: UUID, action: OutlineNodeReminderConflictAction) {
    guard let contentID = resolvedContentID(for: nodeID) else { return }
    if action == .openDiff {
      if expandedReminderConflictDiffContentIDs.contains(contentID) {
        expandedReminderConflictDiffContentIDs.remove(contentID)
      } else {
        expandedReminderConflictDiffContentIDs.insert(contentID)
      }
      return
    }
    guard !reminderConflictResolutionContentIDs.contains(contentID) else { return }

    reminderConflictResolutionContentIDs.insert(contentID)
    Task { @MainActor in
      defer {
        reminderConflictResolutionContentIDs.remove(contentID)
      }
      await resolveReminderConflictNow(for: nodeID, contentID: contentID, action: action)
    }
  }

  func resolveReminderConflictNow(
    for nodeID: UUID,
    contentID: UUID,
    action: OutlineNodeReminderConflictAction
  ) async {
    let taskState = resolvedTaskState(
      for: contentID,
      defaultTitle: resolvedNode(id: nodeID, in: syncedProjects)?.text ?? ""
    )
    guard hasUnresolvedReminderConflict(taskState) else { return }

    if let ownerProjectID = taskState.ownerProjectID, ownerProjectID != currentProjectID {
      liveSync.publishStatusMessage("conflict 해제는 owner project에서만 수행할 수 있습니다.")
      return
    }

    switch action {
    case .keepLocal:
      guard let currentProjection = projection(for: nodeID) else { return }
      persistReminderNoteConflictState(nil, for: currentProjection)
      enqueueReminderPushContentIDs([contentID])
      syncEditorSessionState(triggerAutoPush: false)
      liveSync.publishStatusMessage("로컬 버전을 유지하고 reminder sync를 다시 시도합니다.")
      await pushLocalChanges()

    case .adoptRemote:
      guard let projection = projection(for: nodeID) else { return }
      guard let snapshot = await liveSync.refreshProjection(projection, appState: appState) else {
        return
      }
      let remoteImport = OutlinerRemoteReminderImport(
        contentID: projection.contentID,
        reminderIdentifier: snapshot.reminderIdentifier,
        reminderExternalIdentifier: snapshot.reminderExternalIdentifier,
        calendarIdentifier: snapshot.calendarIdentifier,
        rawPreservationPayloadRaw: snapshot.rawPreservationPayloadRaw,
        title: snapshot.title,
        encodedNote: snapshot.encodedNote,
        parsedBody: snapshot.parsedBody,
        dueDateText: snapshot.dueDateText,
        recurrenceText: snapshot.recurrenceText,
        requiredWorkDays: snapshot.requiredWorkDays,
        isCompleted: snapshot.isCompleted,
        completionDate: snapshot.completionDate,
        lastModifiedText: snapshot.lastModifiedText,
        lastModifiedAt: snapshot.lastModifiedAt,
        dueDate: snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime,
        recurrence: snapshot.recurrence,
        priority: snapshot.priority
      )
      var updatedDocument = document
      let importResult = applyRemoteNoteSourceImport(
        remoteImport,
        to: projection,
        in: &updatedDocument
      )
      if snapshot.title != projection.title {
        updatedDocument.updateNode(id: nodeID) { $0.text = snapshot.title }
      }
      if snapshot.isCompleted != (projection.taskLine.marker == .done) {
        updatedDocument.updateNode(id: nodeID) { node in
          node.type = .task(completed: snapshot.isCompleted)
        }
      }
      if importResult?.requiresNormalizationWrite == true {
        enqueueReminderPushContentIDs([projection.contentID])
      }
      persistReminderNoteConflictState(nil, for: projection, remote: remoteImport)
      recordObservedNoteSourceImport(
        reminderExternalIdentifier: snapshot.reminderExternalIdentifier,
        remoteObservation: remoteNoteObservation(from: remoteImport),
        rawPreservationPayloadRaw: snapshot.rawPreservationPayloadRaw
      )
      storeSnapshotMetadata(for: nodeID, snapshot: snapshot, triggerAutoPush: false)
      if updatedDocument != document {
        commitDocumentChange(
          updatedDocument,
          triggerAutoPush: false,
          commitReminderNoteDirectly: false
        )
        if importResult?.requiresNormalizationWrite == true {
          scheduleAutoPush(after: .milliseconds(150))
        } else {
          pendingReminderPushContentIDs.remove(projection.contentID)
        }
      } else {
        syncEditorSessionState(triggerAutoPush: false)
      }
      liveSync.publishStatusMessage("원격 버전을 채택했습니다.")

    case .openDiff:
      return
    }
  }
}
