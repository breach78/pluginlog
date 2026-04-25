import Foundation
import SwiftData

extension AppState {
  func logseqProjectPageStore() -> LogseqProjectPageStore? {
    guard let logseqGraphRootURL else { return nil }
    return LogseqProjectPageStore(
      pagesRootURL: logseqGraphRootURL.appendingPathComponent("pages", isDirectory: true)
    )
  }

  func prepareProjectNoteStore() async {
    guard let pageStore = logseqProjectPageStore() else { return }
    do {
      try await pageStore.preparePagesDirectory()
      configureLogseqPagesDirectoryWatcher()
    } catch {
      reportError(error, logMessage: "prepareProjectNoteStore failed")
    }
  }

  func configureLogseqPagesDirectoryWatcher() {
    logseqPagesDirectoryWatcher?.stop()
    guard let logseqGraphRootURL else {
      logseqPagesDirectoryWatcher = nil
      return
    }
    let pagesRootURL = logseqGraphRootURL.appendingPathComponent("pages", isDirectory: true)
    let watcher = LogseqPagesDirectoryWatcher(
      pagesRootURL: pagesRootURL,
      fastHandler: { [weak self] in
        self?.bumpWorkspaceTreeRevision()
      },
      handler: { [weak self] changedFiles in
        await self?.handleLogseqPagesDirectoryChange(changedFiles)
      }
    )
    logseqPagesDirectoryWatcher = watcher
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

  func stopLogseqPagesDirectoryWatcher() {
    logseqPagesDirectoryWatcher?.stop()
    logseqPagesDirectoryWatcher = nil
  }

  func loadProjectNoteFromSource(projectID: UUID, context: ModelContext) async -> String? {
    _ = context
    guard let pageStore = logseqProjectPageStore() else { return nil }
    do {
      let pages = try await pageStore.loadProjectPagesInScope()
      return pages.first(where: { $0.projectID == projectID })?.noteMarkdown
    } catch {
      reportError(error, logMessage: "loadProjectNoteFromSource failed")
      return nil
    }
  }

  func persistProjectNoteToSource(_ note: String, projectID: UUID, context: ModelContext) async {
    _ = context
    guard let pageStore = logseqProjectPageStore() else { return }
    do {
      let pages = try await pageStore.loadProjectPagesInScope()
      guard let page = pages.first(where: { $0.projectID == projectID }) else { return }
      try await pageStore.upsertPage(
        .init(
          projectID: projectID,
          title: page.title,
          reminderListExternalIdentifier: page.reminderListExternalIdentifier
        ),
        noteMarkdown: note,
        managedTasks: page.managedTasks
      )
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "persistProjectNoteToSource failed")
    }
  }

  func refreshAllProjectNotesFromSource(context: ModelContext) async {
    _ = context
  }

  func reconcileManagedLogseqPagesWithReminderSource(reason: SyncReason) async {
    guard let pageStore = logseqProjectPageStore() else {
      syncStatus = "Logseq graph not configured"
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
      let result = try await RetainedReminderImportSync.sync(
        batch: ReminderImportSnapshotBatch(
          lists: lists,
          itemsByListIdentifier: itemsByListIdentifier
        ),
        store: pageStore,
        conflictPolicy: reminderImportConflictPolicy(for: reason)
      )
      let provisioningResult: RetainedLogseqProjectProvisioningSync.SyncResult
      if let provisioningMode = logseqProvisioningModeAfterImport(reason: reason) {
        provisioningResult = try await RetainedLogseqProjectProvisioningSync.sync(
          store: pageStore,
          reminderProjectProvider: reminderProjectProvider,
          mode: provisioningMode
        )
      } else {
        provisioningResult = RetainedLogseqProjectProvisioningSync.SyncResult(
          createdProjectCount: 0,
          createdTaskCount: 0,
          projectRecords: [],
          taskRecords: []
        )
      }
      TaskIdentityBridgeStore.replaceAll(
        projects: result.projectRecords + provisioningResult.projectRecords,
        tasks: result.taskRecords + provisioningResult.taskRecords
      )
      let syncedProjectCount = result.importedProjectCount + provisioningResult.createdProjectCount
      let syncedTaskCount = result.importedTaskCount + provisioningResult.createdTaskCount
      syncStatus = provisioningResult.deletedTaskCount > 0
        ? "Synced \(syncedProjectCount) lists / \(syncedTaskCount) tasks / deleted \(provisioningResult.deletedTaskCount)"
        : "Synced \(syncedProjectCount) lists / \(syncedTaskCount) tasks"
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "reconcileManagedLogseqPagesWithReminderSource failed")
      syncStatus = "Reminder sync failed"
    }
  }

  func reminderImportConflictPolicy(
    for reason: SyncReason
  ) -> LogseqProjectPageStore.ReminderImportConflictPolicy {
    switch reason {
    case .bootstrap, .eventStoreChanged, .manual, .periodic:
      return .mergeWithBaseline
    }
  }

  func shouldProvisionFromLogseqAfterImport(reason: SyncReason) -> Bool {
    logseqProvisioningModeAfterImport(reason: reason) == .fullPush
  }

  func logseqProvisioningModeAfterImport(
    reason: SyncReason
  ) -> RetainedLogseqProjectProvisioningSync.SyncMode? {
    switch reason {
    case .bootstrap, .manual:
      return .fullPush
    case .eventStoreChanged, .periodic:
      return nil
    }
  }

  func handleLogseqPagesDirectoryChange(_ changedFiles: [URL]) async {
    AppLogger.sync.info(
      "logseq page change detected files=\(changedFiles.count, privacy: .public) initialSync=\(self.isInitialSyncRunning, privacy: .public)"
    )
    guard !isInitialSyncRunning else {
      queueReminderSourceRefresh(reason: .manual)
      return
    }
    guard !changedFiles.isEmpty, let pageStore = logseqProjectPageStore() else { return }
    do {
      let filesToSync = uniqueLogseqPageFileURLs(changedFiles)
      guard try await reminderProjectProvider.requestAccess() else {
        AppLogger.sync.error("logseq page change skipped because reminders access is denied")
        syncStatus = "Reminders access denied"
        return
      }
      let result = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
        fileURLs: filesToSync,
        store: pageStore,
        reminderProjectProvider: reminderProjectProvider
      )
      applyRetainedLogseqProvisioningResult(result)
      AppLogger.sync.info(
        "logseq page change synced createdProjects=\(result.createdProjectCount, privacy: .public) createdTasks=\(result.createdTaskCount, privacy: .public) deletedTasks=\(result.deletedTaskCount, privacy: .public) taskRecords=\(result.taskRecords.count, privacy: .public)"
      )
      if result.createdProjectCount > 0
        || result.createdTaskCount > 0
        || result.deletedTaskCount > 0
        || !result.projectRecords.isEmpty
        || !result.taskRecords.isEmpty
      {
        recordLogseqAuthoredReminderPush()
      }
      if result.createdProjectCount > 0 || result.createdTaskCount > 0 || result.deletedTaskCount > 0 {
        syncStatus = result.deletedTaskCount > 0
          ? "Synced \(result.createdProjectCount) lists / \(result.createdTaskCount) tasks / deleted \(result.deletedTaskCount)"
          : "Synced \(result.createdProjectCount) lists / \(result.createdTaskCount) tasks"
      }
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "handleLogseqPagesDirectoryChange failed")
      syncStatus = "Logseq sync failed"
    }
  }

  func applyRetainedLogseqProvisioningResult(
    _ result: RetainedLogseqProjectProvisioningSync.SyncResult
  ) {
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

  func uniqueLogseqPageFileURLs(_ fileURLs: [URL]) -> [URL] {
    Array(
      Set(
        fileURLs
          .filter { $0.pathExtension.lowercased() == "md" }
          .map { $0.resolvingSymlinksInPath().standardizedFileURL }
      )
    )
    .sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
  }

  func persistManagedLogseqPages(for projectIDs: Set<UUID>) async {
    _ = projectIDs
    bumpWorkspaceTreeRevision()
  }
}
