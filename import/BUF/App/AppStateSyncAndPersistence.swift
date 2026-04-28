import Foundation

@MainActor
extension AppState {
  var shouldPromptForInitialSyncConsent: Bool {
    hasCompletedInitialSetup && !hasSyncConsentDecision
  }

  func ensureCompletedReminderSyncEnabled() {
    includeCompletedSyncEnabled = true
    UserDefaults.standard.set(true, forKey: Self.includeCompletedSyncEnabledKey)
  }

  func refreshReminderSourceNow(reason: SyncReason = .manual) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      _ = await self.performReminderSourceRefresh(reason: reason)
    }
  }

  @discardableResult
  func performReminderSourceRefresh(reason: SyncReason) async -> Bool {
    guard !isInitialSyncRunning else {
      queueReminderSourceRefresh(reason: reason)
      return false
    }
    isInitialSyncRunning = true
    defer {
      isInitialSyncRunning = false
      if let pendingReason = pendingReminderSourceRefreshReason {
        pendingReminderSourceRefreshReason = nil
        Task { @MainActor [weak self] in
          _ = await self?.performReminderSourceRefresh(reason: pendingReason)
        }
      }
    }

    await reconcileObsidianVaultWithReminderSource(reason: reason)
    syncStarted = true
    if syncStatus != "Reminders access denied", syncStatus != "Reminder sync failed" {
      syncStatus = "Refreshed (\(reason.rawValue))"
    }
    return syncStatus != "Reminders access denied" && syncStatus != "Reminder sync failed"
  }

  func queueReminderSourceRefresh(reason: SyncReason) {
    pendingReminderSourceRefreshReason = coalescedReminderSourceRefreshReason(
      existing: pendingReminderSourceRefreshReason,
      incoming: reason
    )
  }

  private func coalescedReminderSourceRefreshReason(
    existing: SyncReason?,
    incoming: SyncReason
  ) -> SyncReason {
    guard let existing else { return incoming }
    return refreshReasonPriority(incoming) > refreshReasonPriority(existing) ? incoming : existing
  }

  private func refreshReasonPriority(_ reason: SyncReason) -> Int {
    switch reason {
    case .bootstrap:
      return 4
    case .manual:
      return 3
    case .eventStoreChanged:
      return 2
    case .periodic:
      return 1
    }
  }

  @discardableResult
  func handleReminderSourceInvalidation(
    reason: SyncReason,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    guard await waitForEditorIdleIfNeeded(waitForEditorIdle) else { return false }
    return await performReminderSourceRefresh(reason: reason)
  }

  @discardableResult
  func handleExternalProjectMetadataInvalidation(
    projectID: UUID,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalProjectMetadataInvalidation(projectIDs: [projectID], waitForEditorIdle: waitForEditorIdle)
  }

  @discardableResult
  func handleExternalProjectMetadataInvalidation(
    projectIDs: [UUID],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    guard await waitForEditorIdleIfNeeded(waitForEditorIdle) else { return false }
    _ = projectIDs
    bumpWorkspaceTreeRevision()
    return true
  }

  @discardableResult
  func handleExternalProjectTreeStructureInvalidation(
    projectID: UUID,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalProjectMetadataInvalidation(projectID: projectID, waitForEditorIdle: waitForEditorIdle)
  }

  @discardableResult
  func handleExternalProjectTreeStructureInvalidation(
    projectIDs: [UUID],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalProjectMetadataInvalidation(projectIDs: projectIDs, waitForEditorIdle: waitForEditorIdle)
  }

  @discardableResult
  func handleExternalProjectOrderingInvalidation(
    projectIDs: [UUID],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalProjectMetadataInvalidation(projectIDs: projectIDs, waitForEditorIdle: waitForEditorIdle)
  }

  @discardableResult
  func handleExternalProjectAppSupplementInvalidation(
    ownerIDs: [UUID],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalProjectMetadataInvalidation(projectIDs: ownerIDs, waitForEditorIdle: waitForEditorIdle)
  }

  @discardableResult
  func handleExternalReminderListMetadataInvalidation(
    ownerIDs: [String],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    guard !ownerIDs.isEmpty else { return false }
    guard await waitForEditorIdleIfNeeded(waitForEditorIdle) else { return false }
    return await performReminderSourceRefresh(reason: .eventStoreChanged)
  }

  @discardableResult
  func handleExternalReminderTaskInvalidation(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    guard !ownerIDs.isEmpty else { return false }
    _ = changedFields
    guard await waitForEditorIdleIfNeeded(waitForEditorIdle) else { return false }
    return await performReminderSourceRefresh(reason: .eventStoreChanged)
  }

  @discardableResult
  func handleExternalCalendarEventInvalidation(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    _ = ownerIDs
    _ = changedFields
    guard await waitForEditorIdleIfNeeded(waitForEditorIdle) else { return false }
    bumpWorkspaceTreeRevision()
    return true
  }

  func acceptInitialSyncConsentAndStart() {
    setInitialSyncConsentPreference(granted: true)
    refreshReminderSourceNow(reason: .bootstrap)
  }

  func autoBootstrapSyncIfNeeded(projectCount: Int) {
    _ = projectCount
    requestStartupSyncIfNeeded()
  }

  private func waitForEditorIdleIfNeeded(_ shouldWait: Bool) async -> Bool {
    guard shouldWait else { return true }
    return await waitForEditorToBecomeIdle()
  }
}
