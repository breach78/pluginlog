import Foundation
import SwiftData

extension AppState {
  func prepareProjectNoteStore() async {
    guard let obsidianVaultRootURL else { return }
    do {
      try await ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
        .prepareProjectDirectory()
      stopObsidianProjectDirectoryWatcher()
    } catch {
      reportError(error, logMessage: "prepareObsidianProjectNoteStore failed")
    }
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
    _ = context
    guard let obsidianVaultRootURL else { return nil }
    do {
      let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
        .loadProjectNotesInScope()
      return snapshots.first { snapshot in
        guard let listID = snapshot.note.reminderListExternalIdentifier else { return false }
        return RetainedProjectionBuilder.derivedProjectID(for: listID) == projectID
      }?.note.bodyMarkdown
    } catch {
      reportError(error, logMessage: "loadProjectNoteFromSource failed")
      return nil
    }
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
    guard let obsidianVaultRootURL else {
      syncStatus = "Obsidian vault not configured"
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
      if try await persistAppOwnedReminderSnapshot(batch, reason: reason, importedAt: importedAt) != nil {
        let records = AppOwnedReminderBridgeRecordMapper.records(from: batch, importedAt: importedAt)
        replaceObsidianBridgeRecords(projects: records.projects, tasks: records.tasks)
        syncStatus = "Imported app-owned \(records.projects.count) lists / \(records.tasks.count) tasks"
        bumpWorkspaceTreeRevision()
        return
      }
      let store = ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
      if reason == .bootstrap, try await shouldRunReminderFirstBootstrap(store: store) {
        let result = try await ObsidianReminderBootstrapSync.sync(
          batch: batch,
          store: store
        )
        applyObsidianBootstrapResult(result)
        syncStatus = "Synced \(result.importedProjectCount) lists / \(result.importedTaskCount) tasks to Obsidian"
      } else {
        let result = try await ObsidianReminderImportSync.sync(
          batch: batch,
          store: store
        )
        if reason == .bootstrap || reason == .manual {
          replaceObsidianBridgeRecords(
            projects: result.projectRecords,
            tasks: result.taskRecords
          )
        } else {
          applyObsidianImportResult(result)
        }
        syncStatus = "Imported Obsidian \(result.importedProjectCount) lists / \(result.importedTaskCount) tasks / updated \(result.updatedTaskCount) / deleted \(result.deletedTaskCount) / projects deleted \(result.deletedProjectCount)"
      }
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
    if let obsidianVaultRootURL {
      do {
        let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
          .loadProjectNotesInScope()
        try await store.mergeProjectSupplements(appOwnedProjectSupplements(from: snapshots))
        let retainedSnapshot = try ObsidianRetainedProjectionAdapter.build(
          snapshots: snapshots,
          calendar: .autoupdatingCurrent
        )
        try await store.mergeTaskSupplements(appOwnedTaskSupplements(from: retainedSnapshot))
      } catch {
        AppLogger.storage.error(
          "app-owned project supplement import failed: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
    try await store.setProjectionReadEnabled(true)
    return store
  }

  private func appOwnedProjectSupplements(
    from snapshots: [ObsidianProjectMarkdownStore.Snapshot]
  ) -> [AppOwnedWorkspaceStore.ProjectSupplement] {
    snapshots.compactMap { snapshot in
      guard let frontmatter = snapshot.note.frontmatter,
        let listID = frontmatter.reminderListExternalIdentifier
      else {
        return nil
      }
      return AppOwnedWorkspaceStore.ProjectSupplement(
        projectID: RetainedProjectionBuilder.derivedProjectID(for: listID),
        noteMarkdown: snapshot.note.bodyMarkdown,
        progressStageRaw: frontmatter.projectStage.storageRawValue,
        startDate: ReminderScheduleMetadataCodec.decodeDate(frontmatter.startDate)?.date,
        deadline: ReminderScheduleMetadataCodec.decodeDate(frontmatter.deadline)?.date,
        isArchived: frontmatter.isArchived,
        colorHex: frontmatter.colorHex
      )
    }
  }

  private func appOwnedTaskSupplements(
    from snapshot: RetainedWorkspaceSnapshot
  ) -> [AppOwnedWorkspaceStore.TaskSupplement] {
    snapshot.tasks.compactMap { task in
      guard let taskID = task.identity.taskID else { return nil }
      return AppOwnedWorkspaceStore.TaskSupplement(
        taskID: taskID,
        durationMinutes: task.schedule.durationMinutes
      )
    }
  }

  private func shouldRunReminderFirstBootstrap(
    store: ObsidianProjectMarkdownStore
  ) async throws -> Bool {
    try await store.loadProjectNotesInScope().isEmpty
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

  func applyObsidianImportResult(_ result: ObsidianReminderImportSync.SyncResult) {
    TaskIdentityBridgeStore.upsertAll(
      projects: result.projectRecords,
      tasks: result.taskRecords
    )
    TaskIdentityBridgeStore.removeProjects(projectIDs: Set(result.deletedProjectIDs))
  }

  func applyObsidianBootstrapResult(_ result: ObsidianReminderBootstrapSync.SyncResult) {
    replaceObsidianBridgeRecords(
      projects: result.projectRecords,
      tasks: result.taskRecords
    )
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
