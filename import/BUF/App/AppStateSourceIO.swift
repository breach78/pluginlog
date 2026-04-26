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
      pollingNanoseconds: nil,
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
        if let catchUpResult = try await reconcileObsidianLocalChangesWithReminderSource(
          store: store,
          reason: reason
        ) {
          applyObsidianFullReconciliationResult(
            importResult: result,
            provisioningResult: catchUpResult
          )
          if catchUpResult.createdProjectCount > 0
            || catchUpResult.createdTaskCount > 0
            || catchUpResult.updatedTaskCount > 0
            || catchUpResult.deletedTaskCount > 0
            || catchUpResult.archivedProjectCount > 0
            || catchUpResult.restoredProjectCount > 0
          {
            recordAppAuthoredReminderPush()
          }
        } else if reason == .bootstrap || reason == .manual {
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

  private func reconcileObsidianLocalChangesWithReminderSource(
    store: ObsidianProjectMarkdownStore,
    reason: SyncReason
  ) async throws -> ObsidianReminderProvisioningSync.SyncResult? {
    guard reason == .bootstrap || reason == .manual else { return nil }
    let snapshots = try await resolveObsidianArchiveConfirmations(
      in: try await store.loadProjectNotesInScope(),
      store: store
    )
    guard !snapshots.isEmpty else { return nil }
    let result = try await ObsidianReminderProvisioningSync.syncLoadedSnapshots(
      snapshots: snapshots,
      store: store,
      reminderProjectProvider: reminderProjectProvider,
      now: .now
    )
    try finalizeObsidianArchivedProjectNotes(result)
    return result
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
      let changedSnapshots = try await resolveObsidianArchiveConfirmations(
        in: try await store.loadProjectNotesInScope(at: changedFiles),
        store: store
      )
      let provisioningResult = try await ObsidianReminderProvisioningSync.syncLoadedSnapshots(
        snapshots: changedSnapshots,
        store: store,
        reminderProjectProvider: reminderProjectProvider,
        now: .now
      )
      try finalizeObsidianArchivedProjectNotes(provisioningResult)
      applyObsidianProvisioningResult(provisioningResult)
      if provisioningResult.createdProjectCount > 0
        || provisioningResult.createdTaskCount > 0
        || provisioningResult.updatedTaskCount > 0
        || provisioningResult.deletedTaskCount > 0
        || provisioningResult.archivedProjectCount > 0
        || provisioningResult.restoredProjectCount > 0
      {
        recordAppAuthoredReminderPush()
        syncStatus = "Synced Obsidian \(provisioningResult.createdProjectCount) lists / \(provisioningResult.createdTaskCount) tasks / updated \(provisioningResult.updatedTaskCount) / deleted \(provisioningResult.deletedTaskCount) / archived \(provisioningResult.archivedProjectCount) / restored \(provisioningResult.restoredProjectCount)"
      }
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "handleObsidianProjectDirectoryChange failed")
      syncStatus = "Obsidian refresh failed"
    }
  }

  private func resolveObsidianArchiveConfirmations(
    in snapshots: [ObsidianProjectMarkdownStore.Snapshot],
    store: ObsidianProjectMarkdownStore
  ) async throws -> [ObsidianProjectMarkdownStore.Snapshot] {
    guard let obsidianVaultRootURL else { return snapshots }
    let archiveStore = ObsidianReminderArchiveStore(vaultRootURL: obsidianVaultRootURL)
    var resolved: [ObsidianProjectMarkdownStore.Snapshot] = []
    for snapshot in snapshots {
      guard snapshot.note.frontmatter?.isArchived == true,
        let listIdentifier = snapshot.note.reminderListExternalIdentifier,
        try archiveStore.load(forListIdentifier: listIdentifier) == nil
      else {
        resolved.append(snapshot)
        continue
      }

      let request = ObsidianArchiveConfirmationRequest(
        projectTitle: snapshot.fileURL.deletingPathExtension().lastPathComponent,
        vaultRelativePath: snapshot.vaultRelativePath
      )
      guard confirmObsidianArchive(request) else {
        resolved.append(try await cancelObsidianArchive(snapshot, store: store))
        continue
      }
      resolved.append(snapshot)
    }
    return resolved
  }

  private func cancelObsidianArchive(
    _ snapshot: ObsidianProjectMarkdownStore.Snapshot,
    store: ObsidianProjectMarkdownStore
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    var note = snapshot.note
    guard var frontmatter = note.frontmatter else { return snapshot }
    frontmatter.isArchived = false
    note.frontmatter = frontmatter
    return try await store.writeProjectNote(
      note,
      preferredFileName: snapshot.fileURL.lastPathComponent,
      expectedBaseline: .init(snapshot: snapshot)
    )
  }

  private func finalizeObsidianArchivedProjectNotes(
    _ result: ObsidianReminderProvisioningSync.SyncResult
  ) throws {
    guard !result.archivedProjectFileURLs.isEmpty || !result.archivedProjectIDs.isEmpty else {
      return
    }
    if let obsidianVaultRootURL {
      try moveArchivedObsidianProjectNotes(
        result.archivedProjectFileURLs,
        vaultRootURL: obsidianVaultRootURL
      )
    }
    TaskIdentityBridgeStore.removeProjects(projectIDs: Set(result.archivedProjectIDs))
  }

  private func moveArchivedObsidianProjectNotes(
    _ fileURLs: [URL],
    vaultRootURL: URL,
    fileManager: FileManager = .default
  ) throws {
    guard !fileURLs.isEmpty else { return }
    let layout = ObsidianVaultLayout(vaultRootURL: vaultRootURL, fileManager: fileManager)
    try fileManager.createDirectory(at: layout.rawArchiveRootURL, withIntermediateDirectories: true)

    for fileURL in fileURLs {
      let sourceURL = fileURL.standardizedFileURL
      guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
      let destinationURL = uniqueArchiveDestinationURL(
        for: sourceURL,
        archiveRootURL: layout.rawArchiveRootURL,
        fileManager: fileManager
      )
      try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }
  }

  private func uniqueArchiveDestinationURL(
    for sourceURL: URL,
    archiveRootURL: URL,
    fileManager: FileManager
  ) -> URL {
    let baseName = sourceURL.deletingPathExtension().lastPathComponent
    let pathExtension = sourceURL.pathExtension
    var candidate = archiveRootURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
    var suffix = 2
    while fileManager.fileExists(atPath: candidate.path) {
      let fileName = pathExtension.isEmpty
        ? "\(baseName) \(suffix)"
        : "\(baseName) \(suffix).\(pathExtension)"
      candidate = archiveRootURL.appendingPathComponent(fileName, isDirectory: false)
      suffix += 1
    }
    return candidate
  }

  func applyObsidianProvisioningResult(_ result: ObsidianReminderProvisioningSync.SyncResult) {
    TaskIdentityBridgeStore.upsertAll(
      projects: result.projectRecords,
      tasks: result.taskRecords
    )
    TaskIdentityBridgeStore.removeProjects(projectIDs: Set(result.archivedProjectIDs))
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

  func applyObsidianFullReconciliationResult(
    importResult: ObsidianReminderImportSync.SyncResult,
    provisioningResult: ObsidianReminderProvisioningSync.SyncResult
  ) {
    let archivedProjectIDs = Set(provisioningResult.archivedProjectIDs)
    let deletedProjectIDs = Set(importResult.deletedProjectIDs)
    replaceObsidianBridgeRecords(
      projects: (importResult.projectRecords + provisioningResult.projectRecords)
        .filter { !archivedProjectIDs.contains($0.projectID) }
        .filter { !deletedProjectIDs.contains($0.projectID) },
      tasks: (importResult.taskRecords + provisioningResult.taskRecords)
        .filter { !archivedProjectIDs.contains($0.ownerProjectID) }
        .filter { !deletedProjectIDs.contains($0.ownerProjectID) }
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
