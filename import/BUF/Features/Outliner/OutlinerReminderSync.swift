import Foundation

extension OutlinerView {
  func storeSidecarMetadata(
    for reminderIdentifier: String,
    projection: OutlinerReminderProjection,
    requiredWorkDaysOverride: Int? = nil,
    triggerAutoPush: Bool = true,
    persistState: Bool = true
  ) {
    let existingCompletionDate = resolvedReminderMetadata(for: projection.nodeID).completionDate
    persistFeatureSidecarMetadata(
      OutlinerTaskSidecarMetadata(
        requiredWorkDays: requiredWorkDaysOverride ?? projection.syncContract.requiredWorkDays,
        scheduledDurationMinutes: projection.syncContract.scheduledDurationMinutes,
        attachmentPreviews: projection.syncContract.attachmentPreviews
      ),
      for: projection.nodeID,
      reminderIdentifier: reminderIdentifier,
      triggerAutoPush: triggerAutoPush,
      persistState: persistState
    )
    persistReminderMetadata(
      ReminderMetadataSnapshot(
        dueDate: projection.syncContract.reminderPayload.dueDate,
        completionDate: projection.taskLine.marker == .done ? existingCompletionDate : nil,
        hasExplicitTime: projection.syncContract.reminderPayload.hasExplicitTime,
        recurrence: projection.syncContract.reminderPayload.recurrence,
        priority: projection.syncContract.reminderPayload.priority
      ),
      for: projection.nodeID,
      reminderIdentifier: reminderIdentifier,
      triggerAutoPush: triggerAutoPush,
      persistState: false
    )
  }

  func storeSnapshotMetadata(
    for nodeID: UUID,
    snapshot: OutlinerLiveReminderSnapshot,
    triggerAutoPush: Bool = false,
    persistState: Bool = true,
    queueReminderPush: Bool = true
  ) {
    var metadata = resolvedReminderMetadata(for: nodeID)
    metadata.dueDate = snapshot.dueDate
    metadata.completionDate = snapshot.completionDate
    metadata.hasExplicitTime = snapshot.hasExplicitTime
    metadata.recurrence = snapshot.recurrence
    metadata.priority = snapshot.priority
    persistReminderMetadata(
      metadata,
      for: nodeID,
      reminderIdentifier: snapshot.reminderIdentifier,
      triggerAutoPush: triggerAutoPush,
      persistState: persistState,
      queueReminderPush: queueReminderPush
    )

    guard let contentID = resolvedContentID(for: nodeID) else { return }
    appState.installRuntimeProjectionReminderIdentity(
      for: contentID,
      reminderIdentifier: snapshot.reminderIdentifier,
      reminderExternalIdentifier: snapshot.reminderExternalIdentifier,
      modifiedAt: snapshot.lastModifiedAt
    )
    clearTaskSessionOverlay(for: contentID)
    updateTaskSourceRuntimeState(for: snapshot)
  }

  func applyQuickReminderTokens(for nodeID: UUID, text: String) -> String {
    let result = OutlinerQuickReminderParser.parse(
      text: text,
      existingMetadata: resolvedReminderMetadata(for: nodeID)
    )
    guard result.hasMetadataChanges else { return text }

    updateReminderMetadata(for: nodeID, saveDirectly: false) { metadata in
      if let dueDirective = result.dueDirective {
        switch dueDirective {
        case let .set(date, hasExplicitTime):
          metadata.dueDate = date
          metadata.hasExplicitTime = hasExplicitTime
        case .clear:
          metadata.dueDate = nil
          metadata.hasExplicitTime = false
        }
      }

      if let recurrenceDirective = result.recurrenceDirective {
        switch recurrenceDirective {
        case let .set(recurrence):
          metadata.recurrence = recurrence
        case .clear:
          metadata.recurrence = nil
        }
      }

      if let priority = result.priority {
        metadata.priority = priority
      }
    }

    return result.cleanedText
  }

  func stageReminderMetadataForPendingCommit(
    _ metadata: ReminderMetadataSnapshot,
    for nodeID: UUID,
    reminderIdentifier: String? = nil
  ) {
    persistReminderMetadata(
      metadata,
      for: nodeID,
      reminderIdentifier: reminderIdentifier,
      triggerAutoPush: false,
      persistState: true,
      queueReminderPush: false
    )
  }

  func commitReminderMetadataDirectSave(
    for nodeID: UUID,
    overrideMetadata: ReminderMetadataSnapshot? = nil,
    reminderIdentifierOverride: String? = nil
  ) {
    guard let projection = projection(for: nodeID) else {
      liveSync.publishStatusMessage("현재 task의 reminder 메타데이터를 저장할 수 없습니다.")
      return
    }
    let taskState = resolvedTaskState(for: projection.contentID, defaultTitle: projection.title)
    guard !hasUnresolvedReminderConflict(taskState) else {
      liveSync.publishStatusMessage("conflict가 남아 있어 메타데이터 저장을 멈춥니다.")
      return
    }
    guard let calendarIdentifier = resolvedOwnerCalendarIdentifier(for: projection) else {
      return
    }

    let effectiveMetadata = overrideMetadata ?? resolvedReminderMetadata(for: nodeID)
    let metadataPlan = ReminderMetadataMutationPlan(
      title: projection.title,
      isCompleted: projection.taskLine.marker == .done,
      dueDate: effectiveMetadata.dueDate,
      hasExplicitTime: effectiveMetadata.hasExplicitTime,
      recurrence: effectiveMetadata.recurrence,
      priority: max(0, min(9, effectiveMetadata.priority))
    )
    Task { @MainActor in
      await commitReminderMetadataDirectSaveNow(
        for: nodeID,
        projection: projection,
        calendarIdentifier: calendarIdentifier,
        metadataPlan: metadataPlan,
        reminderIdentifierOverride: reminderIdentifierOverride
      )
    }
  }

  func commitReminderMetadataDirectSaveNow(
    for nodeID: UUID,
    projection: OutlinerReminderProjection,
    calendarIdentifier: String,
    metadataPlan: ReminderMetadataMutationPlan,
    reminderIdentifierOverride: String? = nil
  ) async {
    guard let snapshot = await liveSync.saveProjectionMetadata(
      projection,
      calendarIdentifier: calendarIdentifier,
      metadataPlanOverride: metadataPlan,
      appState: appState
    ) else {
      let failureMessage = liveSync.errorMessage ?? "리마인더 메타데이터 저장에 실패했습니다."
      appState.errorMessage = failureMessage
      liveSync.publishStatusMessage("리마인더 메타데이터 저장에 실패했습니다. 다시 시도해 주세요.")
      return
    }

    storeSnapshotMetadata(
      for: nodeID,
      snapshot: snapshot,
      triggerAutoPush: false,
      persistState: true,
      queueReminderPush: false
    )

    if let reminderIdentifierOverride,
       reminderIdentifierOverride != snapshot.reminderIdentifier
    {
      removeReminderMetadataByReminderIdentifier(for: reminderIdentifierOverride)
    }
  }

  func setReminderDuePreset(_ preset: OutlinerReminderQuickDuePreset, for nodeID: UUID) {
    let hasExplicitTime = resolvedReminderMetadata(for: nodeID).hasExplicitTime
    setReminderDueDate(
      preset.resolvedDate(hasExplicitTime: hasExplicitTime),
      hasExplicitTime: hasExplicitTime,
      for: nodeID
    )
  }

  func clearReminderDue(for nodeID: UUID) {
    updateReminderMetadata(for: nodeID) { metadata in
      metadata.dueDate = nil
      metadata.hasExplicitTime = false
    }
  }

  func setReminderDueDate(_ dueDate: Date, hasExplicitTime: Bool, for nodeID: UUID) {
    let calendar = Calendar.autoupdatingCurrent
    let normalizedDate = hasExplicitTime ? dueDate : calendar.startOfDay(for: dueDate)
    updateReminderMetadata(for: nodeID) { metadata in
      metadata.dueDate = normalizedDate
      metadata.hasExplicitTime = hasExplicitTime
    }
  }

  func setReminderRecurrence(_ recurrence: OutlinerRecurrenceSample?, for nodeID: UUID) {
    updateReminderMetadata(for: nodeID) { metadata in
      metadata.recurrence = recurrence
    }
  }

  func cycleReminderRecurrence(for nodeID: UUID) {
    let nextRecurrence: OutlinerRecurrenceSample?
    switch resolvedReminderMetadata(for: nodeID).recurrence {
    case nil:
      nextRecurrence = .daily(interval: 1)
    case .daily:
      nextRecurrence = .weekly(interval: 1, weekdays: [])
    case .weekly:
      nextRecurrence = .monthly(interval: 1)
    case .monthly:
      nextRecurrence = .yearly(interval: 1)
    case .yearly:
      nextRecurrence = nil
    }
    setReminderRecurrence(nextRecurrence, for: nodeID)
  }

  func setReminderPriority(_ priority: Int, for nodeID: UUID) {
    updateReminderMetadata(for: nodeID) { metadata in
      metadata.priority = priority
    }
  }

  func cycleReminderPriority(for nodeID: UUID) {
    let nextPriority: Int
    switch resolvedReminderMetadata(for: nodeID).priority {
    case 1...4:
      nextPriority = 5
    case 5:
      nextPriority = 9
    case 6...9:
      nextPriority = 0
    default:
      nextPriority = 1
    }
    setReminderPriority(nextPriority, for: nodeID)
  }

  func refreshCurrentProjectAccentColorHex() {
    let nextColorHex = appState.cachedOutlinerRuntimeProjectionSnapshot?
      .projectColorHexByProjectID[currentProjectID]
    if currentProjectAccentColorHex != nextColorHex {
      currentProjectAccentColorHex = nextColorHex
    }
  }

  func existingOutlineChildrenByStableID(
    in nodes: [OutlineNode]
  ) -> [String: OutlineNode] {
    var nodesByStableID: [String: OutlineNode] = [:]

    func visit(_ nodes: [OutlineNode]) {
      for node in nodes {
        nodesByStableID[node.canonicalID.uuidString.lowercased()] = node
        visit(node.children)
      }
    }

    visit(nodes)
    return nodesByStableID
  }

  func resolvedOwnerCalendarIdentifier(
    for projection: OutlinerReminderProjection,
    projectReminderListIdentifiersByProjectID: [UUID: String]? = nil
  ) -> String? {
    let projectReminderListIdentifiersByProjectID =
      projectReminderListIdentifiersByProjectID
      ?? appState.cachedOutlinerRuntimeProjectionSnapshot?.projectReminderListIdentifierByProjectID
      ?? [:]
    let taskState = resolvedTaskState(for: projection.contentID, defaultTitle: projection.title)
    let ownerStatus = appState.resolvedOutlinerReminderOwnerStatus(
      for: taskState,
      currentProjectID: currentProjectID,
      visibleProjectIDs: Set(syncedProjects.map(\.id)),
      projectReminderListIdentifiersByProjectID: projectReminderListIdentifiersByProjectID
    )

    return handleOwnerStatus(
      ownerStatus,
      for: projection,
      projectReminderListIdentifiersByProjectID: projectReminderListIdentifiersByProjectID
    )
  }

  private func handleOwnerStatus(
    _ ownerStatus: OutlinerReminderOwnerStatus,
    for projection: OutlinerReminderProjection,
    projectReminderListIdentifiersByProjectID: [UUID: String]
  ) -> String? {

    switch ownerStatus {
    case let .resolved(projectID, calendarIdentifier):
      guard projectID == currentProjectID else {
        liveSync.publishStatusMessage("owner project에서만 outbound sync를 수행합니다.")
        return nil
      }
      return calendarIdentifier
    case .ownerMissing:
      let calendarIdentifier =
        normalizedNonEmptyString(projectReminderListIdentifiersByProjectID[currentProjectID])
      guard projection.reminderIdentifier == nil,
        let calendarIdentifier,
        !calendarIdentifier.isEmpty
      else {
        liveSync.publishStatusMessage("owner가 없어 이 리마인더는 실험창에서 push할 수 없습니다.")
        return nil
      }
      return calendarIdentifier
    case .ownerPermissionLost:
      liveSync.publishStatusMessage("owner calendar 접근 권한이 없어 push를 중단합니다.")
      return nil
    case .ownerDrift:
      liveSync.publishStatusMessage("owner drift가 감지되어 push를 중단합니다.")
      return nil
    }
  }

}
