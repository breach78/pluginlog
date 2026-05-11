import Foundation
import SwiftData

extension AppState {
  func prepareProjectNoteStore() async {
    stopObsidianProjectDirectoryWatcher()
  }

  func configureObsidianProjectDirectoryWatcher() {
    obsidianProjectDirectoryWatcher?.stop()
    obsidianProjectDirectoryWatcher = nil
  }

  func configureReminderSourceObservation() {
    reminderSourceObserver?.stop()
    let observer = ReminderSourceObserver(
      gateway: reminderGateway,
      invalidateSource: { [weak self] reason in
        guard let self else { return false }
        return await self.handleReminderSourceInvalidation(reason: reason)
      },
      handleExternalOwnerChange: { [weak self] command in
        guard let self else { return false }
        return await self.send(command, waitForEditorIdle: true)
      },
      authorizationStatusProvider: reminderAuthorizationStatusProvider
    )
    reminderSourceObserver = observer
    Task { @MainActor [weak observer] in
      await observer?.startObserving()
    }
  }

  func stopObsidianProjectDirectoryWatcher() {
    obsidianProjectDirectoryWatcher?.stop()
    obsidianProjectDirectoryWatcher = nil
  }

  func loadProjectNoteFromSource(projectID: UUID, context: ModelContext) async -> String? {
    _ = projectID
    _ = context
    return nil
  }

  func persistProjectNoteToSource(_ note: String, projectID: UUID, context: ModelContext) async {
    _ = note
    _ = projectID
    _ = context
    errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "project-note-direct-edit")
  }

  func refreshAllProjectNotesFromSource(context: ModelContext) async {
    _ = context
  }

  func reconcileObsidianVaultWithReminderSource(reason: SyncReason) async {
    guard obsidianVaultRootURL != nil else {
      syncStatus = "Vault path not configured"
      return
    }
    guard let gateway = reminderProjectProvider.reminderGateway else {
      syncStatus = "Reminders unavailable"
      return
    }

    do {
      guard try await reminderProjectProvider.requestAccess() else {
        syncStatus = "Reminders access denied"
        return
      }
      let snapshotProvider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
      let batch = try await snapshotProvider.fetchAllBatch()
      let importedAt = Date.now
      if let appOwnedStore = try await persistAppOwnedReminderSnapshot(
        batch,
        reason: reason,
        importedAt: importedAt
      ) {
        let retainedSnapshot = try await appOwnedStore.loadRetainedWorkspaceSnapshot(projectIDs: [])
        let records = AppOwnedReminderBridgeRecordMapper.records(
          from: retainedSnapshot,
          importedAt: importedAt
        )
        replaceObsidianBridgeRecords(projects: records.projects, tasks: records.tasks)
        syncStatus = "Imported app-owned \(records.projects.count) lists / \(records.tasks.count) tasks"
        bumpWorkspaceTreeRevision()
        return
      }
      syncStatus = "App-owned workspace storage unavailable"
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "reconcileObsidianVaultWithReminderSource failed")
      syncStatus = "Reminder sync failed"
    }
  }

  private func persistAppOwnedReminderSnapshot(
    _ batch: ReminderImportSnapshotBatch,
    reason: SyncReason,
    importedAt: Date
  ) async throws -> AppOwnedWorkspaceStore? {
    guard let containerRootURL = storageCoordinator.paths?.root else { return nil }
    if reason == .bootstrap || reason == .manual {
      _ = try AppOwnedReminderBackupStore(containerRootURL: containerRootURL)
        .savePreMigrationSnapshot(
          batch,
          reason: AppOwnedReminderBackupReason(syncReason: reason),
          createdAt: importedAt
        )
    }
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRootURL)
    try await store.replaceReminderSnapshot(batch, importedAt: importedAt)
    try await runLegacyObsidianProjectMigrationsIfNeeded(store: store)
    try await store.setProjectionReadEnabled(true)
    return store
  }

  func runLegacyObsidianProjectMigrationsIfNeeded() async {
    do {
      guard let containerRootURL = storageCoordinator.paths?.root else { return }
      let store = AppOwnedWorkspaceStore(containerRootURL: containerRootURL)
      guard try await store.hasImportedWorkspace() else { return }
      try await runLegacyObsidianProjectMigrationsIfNeeded(store: store)
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(
        error,
        logMessage: "runLegacyObsidianProjectMigrationsIfNeeded failed"
      )
    }
  }

  private func runLegacyObsidianProjectMigrationsIfNeeded(
    store: AppOwnedWorkspaceStore
  ) async throws {
    guard let obsidianVaultRootURL else { return }
    try await LegacyObsidianProjectTaskDurationMigration.runIfNeeded(
      store: store,
      vaultRootURL: obsidianVaultRootURL
    )
    try await LegacyObsidianProjectStageMigration.runIfNeeded(
      store: store,
      vaultRootURL: obsidianVaultRootURL
    )
  }

  func handleObsidianProjectDirectoryChange(_ changedFiles: [URL]) async {
    AppLogger.sync.info(
      "obsidian project note change ignored files=\(changedFiles.count, privacy: .public)"
    )
    guard !changedFiles.isEmpty else {
      return
    }
    syncStatus = "Obsidian file changes ignored"
  }

  func persistAppOwnedProjectTaskOrder(projectID: UUID, orderedTaskIDs: [UUID]) async {
    do {
      guard let store = try await AppOwnedRetainedTaskCommandService.enabledStore(
        vaultRootURL: obsidianVaultRootURL
      ) else {
        return
      }
      try await store.reorderOpenTasks(projectID: projectID, orderedTaskIDs: orderedTaskIDs)
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "persistAppOwnedProjectTaskOrder failed")
    }
  }

  func replaceObsidianBridgeRecords(
    projects: [ProjectIdentityBridgeRecord],
    tasks: [TaskIdentityBridgeRecord]
  ) {
    TaskIdentityBridgeStore.replaceAll(projects: projects, tasks: tasks)
  }

  func persistManagedProjectNotes(for projectIDs: Set<UUID>) async {
    _ = projectIDs
    bumpWorkspaceTreeRevision()
  }
}
