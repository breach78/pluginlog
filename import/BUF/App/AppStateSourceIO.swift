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
