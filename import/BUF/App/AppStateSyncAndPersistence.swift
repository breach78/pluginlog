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
    guard !isInitialSyncRunning else { return }
    isInitialSyncRunning = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.reconcileManagedLogseqPagesWithReminderSource()
      self.syncStarted = true
      self.isInitialSyncRunning = false
      self.syncStatus = "Refreshed (\(reason.rawValue))"
    }
  }

  @discardableResult
  func handleReminderSourceInvalidation(
    reason: SyncReason,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    _ = waitForEditorIdle
    refreshReminderSourceNow(reason: reason)
    return true
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
    _ = waitForEditorIdle
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
    _ = ownerIDs
    _ = waitForEditorIdle
    bumpWorkspaceTreeRevision()
    return true
  }

  @discardableResult
  func handleExternalReminderTaskInvalidation(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    _ = ownerIDs
    _ = changedFields
    _ = waitForEditorIdle
    bumpWorkspaceTreeRevision()
    return true
  }

  @discardableResult
  func handleExternalCalendarEventInvalidation(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    _ = ownerIDs
    _ = changedFields
    _ = waitForEditorIdle
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
}
