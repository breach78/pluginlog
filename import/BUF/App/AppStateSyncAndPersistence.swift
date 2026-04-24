@preconcurrency import EventKit
import Foundation

@MainActor
extension AppState {
  func ensureCompletedReminderSyncEnabled() {
    let wasDisabled =
      !includeCompletedSyncEnabled
      || !UserDefaults.standard.bool(forKey: Self.includeCompletedSyncEnabledKey)
    includeCompletedSyncEnabled = true
    UserDefaults.standard.set(true, forKey: Self.includeCompletedSyncEnabledKey)

    if wasDisabled {
      refreshReminderSourceNow()
    }
  }

  func refreshReminderSourceNow(reason: SyncReason = .manual) {
    guard !isInitialSyncRunning else { return }
    isInitialSyncRunning = true
    syncStatus = "Refreshing"

    Task { [weak self] in
      guard let self, let reminderSourceObserver = self.reminderSourceObserver else {
        await MainActor.run {
          self?.isInitialSyncRunning = false
        }
        return
      }

      if self.syncStarted {
        await reminderSourceObserver.refresh(reason: reason)
      } else {
        await reminderSourceObserver.bootstrap()
      }

      await MainActor.run {
        self.syncStarted = self.cachedOutlinerRuntimeProjectionSnapshot != nil || self.syncStarted
        self.isInitialSyncRunning = false
        self.syncStatus = reminderSourceObserver.status
      }
    }
  }

  @discardableResult
  func handleReminderSourceInvalidation(
    reason: SyncReason,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    if waitForEditorIdle
      && (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty)
    {
      guard await waitForEditorToBecomeIdle() else { return false }
    }

    guard hasInitialSyncConsent else { return false }
    refreshDefaultReminderCalendarIdentifier()
    guard let runtimeSnapshot = cachedOutlinerRuntimeProjectionSnapshot else {
      guard let bootstrapSnapshot = await loadRuntimeProjectionSnapshotFromSource() else {
        syncStatus = "Refresh failed: projection bootstrap unavailable"
        return false
      }

      installCachedRuntimeProjectionSnapshot(bootstrapSnapshot)
      isOutlinerProjectionBootstrapPending = false
      await reconcileManagedLogseqPagesWithReminderSource()
      syncStarted = true
      syncStatus = "Refreshed (\(reason.rawValue))"
      return true
    }
    let affectedProjectIDs = Set(runtimeSnapshot.projects.map(\.id))
    guard await recomputeCachedRuntimeProjectionProjects(affectedProjectIDs) else {
      return false
    }

    await reconcileManagedLogseqPagesWithReminderSource()
    syncStarted = true
    syncStatus = "Refreshed (\(reason.rawValue))"
    return true
  }

  @discardableResult
  func handleExternalProjectMetadataInvalidation(
    projectID: UUID,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalProjectMetadataInvalidation(
      projectIDs: [projectID],
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func handleExternalProjectMetadataInvalidation(
    projectIDs: [UUID],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalSidecarProjectInvalidation(
      projectIDs: projectIDs,
      changedField: .projectMetadata,
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func handleExternalProjectTreeStructureInvalidation(
    projectID: UUID,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalProjectTreeStructureInvalidation(
      projectIDs: [projectID],
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func handleExternalProjectTreeStructureInvalidation(
    projectIDs: [UUID],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalSidecarProjectInvalidation(
      projectIDs: projectIDs,
      changedField: .treeStructure,
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func handleExternalProjectOrderingInvalidation(
    projectIDs: [UUID],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalSidecarProjectInvalidation(
      projectIDs: projectIDs,
      changedField: .ordering,
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func handleExternalProjectAppSupplementInvalidation(
    ownerIDs: [UUID],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    await handleExternalSidecarProjectInvalidation(
      projectIDs: ownerIDs,
      changedField: .appSupplement,
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func handleExternalReminderListMetadataInvalidation(
    ownerIDs: [String],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    let normalizedOwnerIDs = Array(NSOrderedSet(array: ownerIDs.compactMap(normalizedProjectionValue)))
      as? [String] ?? []
    guard !normalizedOwnerIDs.isEmpty else {
      syncStatus = "Reminder external change skipped (scope unresolved)"
      return false
    }

    return await send(
      .externalOwnerChange(
        ownerStore: .reminder,
        ownerIDs: normalizedOwnerIDs,
        changedFields: [.listMetadata]
      ),
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func handleExternalReminderTaskInvalidation(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    let normalizedOwnerIDs = Array(NSOrderedSet(array: ownerIDs.compactMap(normalizedProjectionValue)))
      as? [String] ?? []
    guard !normalizedOwnerIDs.isEmpty else {
      syncStatus = "Reminder external change skipped (scope unresolved)"
      return false
    }
    let resolvedChangedFields = normalizedReminderTaskExternalChangeFields(changedFields)
    guard !resolvedChangedFields.isEmpty else {
      syncStatus = "Reminder external change skipped (unsupported field)"
      return false
    }

    return await send(
      .externalOwnerChange(
        ownerStore: .reminder,
        ownerIDs: normalizedOwnerIDs,
        changedFields: resolvedChangedFields
      ),
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func handleExternalCalendarEventInvalidation(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    let normalizedOwnerIDs = Array(NSOrderedSet(array: ownerIDs.compactMap(normalizedProjectionValue)))
      as? [String] ?? []
    guard !normalizedOwnerIDs.isEmpty else {
      syncStatus = "Calendar external change skipped (scope unresolved)"
      return false
    }
    let resolvedChangedFields = normalizedCalendarEventExternalChangeFields(changedFields)
    guard !resolvedChangedFields.isEmpty else {
      syncStatus = "Calendar external change skipped (unsupported field)"
      return false
    }

    return await send(
      .externalOwnerChange(
        ownerStore: .calendar,
        ownerIDs: normalizedOwnerIDs,
        changedFields: resolvedChangedFields
      ),
      waitForEditorIdle: waitForEditorIdle
    )
  }

  private func normalizedReminderTaskExternalChangeFields(
    _ changedFields: [AppOwnerField]
  ) -> [AppOwnerField] {
    let resolvedChangedFields = AppOwnerField.reminderTaskExternalChangeFields.filter {
      changedFields.contains($0)
    }
    return resolvedChangedFields.isEmpty
      ? AppOwnerField.reminderTaskExternalChangeFields
      : resolvedChangedFields
  }

  private func normalizedCalendarEventExternalChangeFields(
    _ changedFields: [AppOwnerField]
  ) -> [AppOwnerField] {
    let resolvedChangedFields = AppOwnerField.calendarEventExternalChangeFields.filter {
      changedFields.contains($0)
    }
    return resolvedChangedFields.isEmpty
      ? AppOwnerField.calendarEventExternalChangeFields
      : resolvedChangedFields
  }

  @discardableResult
  private func handleExternalSidecarProjectInvalidation(
    projectIDs: [UUID],
    changedField: AppOwnerField,
    waitForEditorIdle: Bool
  ) async -> Bool {
    let ownerIDs =
      Array(NSOrderedSet(array: projectIDs.map(\.uuidString))) as? [String] ?? []
    guard !ownerIDs.isEmpty else {
      syncStatus = "Sidecar external change skipped (scope unresolved)"
      return false
    }

    return await send(
      .externalOwnerChange(
        ownerStore: .sidecar,
        ownerIDs: ownerIDs,
        changedFields: [changedField]
      ),
      waitForEditorIdle: waitForEditorIdle
    )
  }

  func acceptInitialSyncConsentAndStart() {
    setInitialSyncConsentPreference(granted: true)
  }

  var shouldPromptForInitialSyncConsent: Bool {
    modelContainer != nil && !hasSyncConsentDecision && !syncStarted && !isInitialSyncRunning
  }

  func autoBootstrapSyncIfNeeded(projectCount: Int) {
    guard projectCount == 0 else { return }
    guard !didAutoBootstrapSync else { return }
    guard !isInitialSyncRunning else { return }
    guard hasInitialSyncConsent else { return }

    didAutoBootstrapSync = true
    refreshReminderSourceNow(reason: .bootstrap)
  }

  func startDocumentReferenceObservationIfNeeded(
    presenterPool: DocumentReferencePresenterPool
  ) {
    documentReferenceObservationTask?.cancel()
    documentReferenceObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for await event in presenterPool.changes {
        guard !Task.isCancelled else { return }
        documentReferenceChangeEvents[event.referenceID] = event
      }
    }
  }
}

enum WorkspaceOverlaySnapshotMerge {
  static func mergedSourceSnapshot(
    _ snapshot: NormalizedSourceSnapshot,
    workspaceTreeRepository: WorkspaceTreeRepository?
  ) async throws -> NormalizedSourceSnapshot {
    guard let workspaceTreeRepository else { return snapshot }

    do {
      let overlay = try await workspaceTreeRepository.subtree(
        nodeID: NormalizedSourceSnapshot.rootNodeID,
        includeArchived: true
      )
      return NormalizedWorkspaceOverlayMerge.merged(source: snapshot, overlay: overlay)
    } catch WorkspaceTreeRepositoryError.rootNodeMissing {
      return snapshot
    } catch WorkspaceTreeRepositoryError.nodeNotFound {
      return snapshot
    }
  }
}
