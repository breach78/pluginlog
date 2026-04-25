import Foundation
import SwiftData

extension AppState {
  func prepareProjectNoteStore() async {
    guard let obsidianVaultRootURL else { return }
    do {
      try await ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
        .prepareProjectDirectory()
      configureObsidianProjectDirectoryWatcher()
    } catch {
      reportError(error, logMessage: "prepareObsidianProjectNoteStore failed")
    }
  }

  func configureObsidianProjectDirectoryWatcher() {
    obsidianProjectDirectoryWatcher?.stop()
    guard let obsidianVaultRootURL else {
      obsidianProjectDirectoryWatcher = nil
      return
    }
    let watcher = ObsidianProjectDirectoryWatcher(
      vaultRootURL: obsidianVaultRootURL,
      fastHandler: { [weak self] in
        self?.bumpWorkspaceTreeRevision()
      },
      handler: { [weak self] changedFiles in
        await self?.handleObsidianProjectDirectoryChange(changedFiles)
      }
    )
    obsidianProjectDirectoryWatcher = watcher
    watcher.start()
  }

  func configureReminderSourceObservation() {
    reminderSourceObserver?.stop()
    let observer = ReminderSourceObserver(
      gateway: reminderGateway,
      invalidateSource: { [weak self] reason in
        guard let self else { return false }
        return await self.performReminderSourceRefresh(reason: reason)
      },
      handleExternalOwnerChange: { [weak self] command in
        guard let self else { return false }
        return await self.send(command, waitForEditorIdle: false)
      }
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
      let lists = try await snapshotProvider.fetchAllLists()
      let itemsByListIdentifier = try await snapshotProvider.fetchItemsByList(for: lists)
      let batch = ReminderImportSnapshotBatch(
        lists: lists,
        itemsByListIdentifier: itemsByListIdentifier
      )
      if reason == .bootstrap {
        let result = try await ObsidianReminderBootstrapSync.sync(
          batch: batch,
          store: ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
        )
        syncStatus = "Synced \(result.importedProjectCount) lists / \(result.importedTaskCount) tasks to Obsidian"
      } else {
        let result = try await ObsidianReminderImportSync.sync(
          batch: batch,
          store: ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
        )
        applyObsidianImportResult(result)
        syncStatus = "Imported Obsidian \(result.importedProjectCount) lists / \(result.importedTaskCount) tasks / updated \(result.updatedTaskCount) / deleted \(result.deletedTaskCount)"
      }
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "reconcileObsidianVaultWithReminderSource failed")
      syncStatus = "Reminder sync failed"
    }
  }

  func handleObsidianProjectDirectoryChange(_ changedFiles: [URL]) async {
    AppLogger.sync.info(
      "obsidian project note change detected files=\(changedFiles.count, privacy: .public) initialSync=\(self.isInitialSyncRunning, privacy: .public)"
    )
    guard !isInitialSyncRunning else {
      bumpWorkspaceTreeRevision()
      return
    }
    guard !changedFiles.isEmpty, let obsidianVaultRootURL else { return }

    do {
      let store = ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
      let result = try await ObsidianChangedProjectProjectionRefresh.refresh(
        changedFileURLs: changedFiles,
        store: store,
        projectIDs: []
      )
      switch result {
      case .loaded:
        syncStatus = "Obsidian changes ready"
      case .blocked(let blocker):
        syncStatus = "Obsidian refresh blocked"
        if blocker.shouldPresentGlobalError {
          errorMessage = blocker.userMessage
        }
      }

      guard try await reminderProjectProvider.requestAccess() else {
        AppLogger.sync.error("obsidian project change skipped because reminders access is denied")
        syncStatus = "Reminders access denied"
        bumpWorkspaceTreeRevision()
        return
      }
      let provisioningResult = try await ObsidianReminderProvisioningSync.syncChangedNotes(
        fileURLs: changedFiles,
        store: store,
        reminderProjectProvider: reminderProjectProvider
      )
      applyObsidianProvisioningResult(provisioningResult)
      if provisioningResult.createdProjectCount > 0
        || provisioningResult.createdTaskCount > 0
        || provisioningResult.updatedTaskCount > 0
        || provisioningResult.deletedTaskCount > 0
      {
        recordAppAuthoredReminderPush()
        syncStatus = "Synced Obsidian \(provisioningResult.createdProjectCount) lists / \(provisioningResult.createdTaskCount) tasks / updated \(provisioningResult.updatedTaskCount) / deleted \(provisioningResult.deletedTaskCount)"
      }
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "handleObsidianProjectDirectoryChange failed")
      syncStatus = "Obsidian refresh failed"
    }
  }

  func applyObsidianProvisioningResult(_ result: ObsidianReminderProvisioningSync.SyncResult) {
    for projectRecord in result.projectRecords {
      TaskIdentityBridgeStore.upsertProject(
        projectID: projectRecord.projectID,
        title: projectRecord.title,
        reminderListExternalIdentifier: projectRecord.reminderListExternalIdentifier
      )
    }
    for taskRecord in result.taskRecords {
      TaskIdentityBridgeStore.upsertTask(
        taskID: taskRecord.taskID,
        title: taskRecord.title,
        reminderExternalIdentifier: taskRecord.reminderExternalIdentifier,
        ownerProjectID: taskRecord.ownerProjectID
      )
    }
  }

  func applyObsidianImportResult(_ result: ObsidianReminderImportSync.SyncResult) {
    for projectRecord in result.projectRecords {
      TaskIdentityBridgeStore.upsertProject(
        projectID: projectRecord.projectID,
        title: projectRecord.title,
        reminderListExternalIdentifier: projectRecord.reminderListExternalIdentifier
      )
    }
    for taskRecord in result.taskRecords {
      TaskIdentityBridgeStore.upsertTask(
        taskID: taskRecord.taskID,
        title: taskRecord.title,
        reminderExternalIdentifier: taskRecord.reminderExternalIdentifier,
        ownerProjectID: taskRecord.ownerProjectID
      )
    }
  }

  func persistManagedProjectNotes(for projectIDs: Set<UUID>) async {
    _ = projectIDs
    bumpWorkspaceTreeRevision()
  }
}
