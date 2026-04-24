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
    } catch {
      reportError(error, logMessage: "prepareProjectNoteStore failed")
    }
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

  func reconcileManagedLogseqPagesWithReminderSource() async {
    guard let pageStore = logseqProjectPageStore() else {
      syncStatus = "Logseq graph not configured"
      return
    }
    guard let gateway = reminderProjectProvider.reminderGateway else {
      syncStatus = "Reminders unavailable"
      return
    }

    do {
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
      TaskIdentityBridgeStore.replaceAll(
        projects: result.projectRecords,
        tasks: result.taskRecords
      )
      syncStatus = "Synced \(result.importedProjectCount) lists / \(result.importedTaskCount) tasks"
      bumpWorkspaceTreeRevision()
    } catch {
      reportError(error, logMessage: "reconcileManagedLogseqPagesWithReminderSource failed")
      syncStatus = "Reminder sync failed"
    }
  }

  func persistManagedLogseqPages(for projectIDs: Set<UUID>) async {
    _ = projectIDs
    bumpWorkspaceTreeRevision()
  }
}
