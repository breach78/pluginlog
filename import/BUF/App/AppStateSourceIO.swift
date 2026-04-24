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
    let watcher = LogseqPagesDirectoryWatcher(pagesRootURL: pagesRootURL) { [weak self] changedFiles in
      await self?.handleLogseqPagesDirectoryChange(changedFiles)
    }
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
        store: pageStore
      )
      let shouldProvisionFromLogseq = reason != .eventStoreChanged
      let provisioningResult = shouldProvisionFromLogseq
        ? try await RetainedLogseqProjectProvisioningSync.sync(
          store: pageStore,
          reminderProjectProvider: reminderProjectProvider
        )
        : RetainedLogseqProjectProvisioningSync.SyncResult(
          createdProjectCount: 0,
          createdTaskCount: 0,
          projectRecords: [],
          taskRecords: []
        )
      TaskIdentityBridgeStore.replaceAll(
        projects: result.projectRecords + provisioningResult.projectRecords,
        tasks: result.taskRecords + provisioningResult.taskRecords
      )
      syncStatus =
        "Synced \(result.importedProjectCount + provisioningResult.createdProjectCount) lists / \(result.importedTaskCount + provisioningResult.createdTaskCount) tasks"
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "reconcileManagedLogseqPagesWithReminderSource failed")
      syncStatus = "Reminder sync failed"
    }
  }

  func handleLogseqPagesDirectoryChange(_ changedFiles: [URL]) async {
    guard !changedFiles.isEmpty, let pageStore = logseqProjectPageStore() else { return }
    do {
      guard try await reminderProjectProvider.requestAccess() else {
        syncStatus = "Reminders access denied"
        return
      }
      let result = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
        fileURLs: changedFiles,
        store: pageStore,
        reminderProjectProvider: reminderProjectProvider
      )
      applyRetainedLogseqProvisioningResult(result)
      if result.createdProjectCount > 0 || result.createdTaskCount > 0 {
        syncStatus = "Synced \(result.createdProjectCount) lists / \(result.createdTaskCount) tasks"
      }
      bumpWorkspaceTreeRevision()
      scheduleLogseqParentCompletionCascade(for: changedFiles)
    } catch {
      reportError(error, logMessage: "handleLogseqPagesDirectoryChange failed")
      syncStatus = "Logseq sync failed"
    }
  }

  func scheduleLogseqParentCompletionCascade(for fileURLs: [URL]) {
    let markdownFileURLs = fileURLs
      .filter { $0.pathExtension.lowercased() == "md" }
      .map { $0.resolvingSymlinksInPath().standardizedFileURL }
    guard !markdownFileURLs.isEmpty else { return }

    pendingLogseqParentCompletionCascadeFileURLs.formUnion(markdownFileURLs)
    logseqParentCompletionCascadeTask?.cancel()
    let delay = logseqParentCompletionCascadeDelay
    logseqParentCompletionCascadeTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      await self?.applyPendingLogseqParentCompletionCascade()
    }
  }

  func applyPendingLogseqParentCompletionCascade() async {
    let fileURLs = Array(pendingLogseqParentCompletionCascadeFileURLs)
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
    pendingLogseqParentCompletionCascadeFileURLs.removeAll(keepingCapacity: true)
    logseqParentCompletionCascadeTask = nil
    guard !fileURLs.isEmpty, let pageStore = logseqProjectPageStore() else { return }

    do {
      let changedFiles = try await pageStore.completeDescendantTasksUnderCompletedParents(in: fileURLs)
      guard !changedFiles.isEmpty else { return }
      guard try await reminderProjectProvider.requestAccess() else {
        syncStatus = "Reminders access denied"
        return
      }
      let result = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
        fileURLs: changedFiles,
        store: pageStore,
        reminderProjectProvider: reminderProjectProvider
      )
      applyRetainedLogseqProvisioningResult(result)
      syncStatus = "Synced completed subtasks"
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "applyPendingLogseqParentCompletionCascade failed")
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

  func persistManagedLogseqPages(for projectIDs: Set<UUID>) async {
    _ = projectIDs
    bumpWorkspaceTreeRevision()
  }
}
