import Foundation

enum ObsidianProjectDeletionSync {
  struct DeleteResult: Equatable, Sendable {
    let deletedProjectID: UUID
    let deletedReminderListExternalIdentifier: String
    let deletedProjectFileURL: URL
  }

  @MainActor
  static func deleteProject(
    vaultRootURL: URL?,
    projectID: UUID,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date = .now
  ) async throws -> DeleteResult {
    guard let vaultRootURL else {
      throw RetainedTaskCommandError.obsidianVaultNotConfigured
    }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultRootURL)
    let snapshots = try await store.loadProjectNotesInScope()
    try validateNotes(snapshots.map(\.note))
    guard let snapshot = snapshots.first(where: { retainedProjectID(for: $0) == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    guard let listID = normalized(snapshot.note.reminderListExternalIdentifier) else {
      throw RetainedTaskCommandError.unsafeProjectNote(projectID)
    }

    let lifecycleStore = ProjectLifecycleStore(vaultRootURL: vaultRootURL)
    try lifecycleStore.recordStarted(
      intent: .appDelete,
      projectID: projectID,
      reminderListExternalIdentifier: listID,
      noteVaultRelativePath: snapshot.vaultRelativePath,
      at: now
    )
    try reminderProjectProvider.removeProjectList(identifier: listID)
    let result = try await deleteLocalProject(
      snapshot: snapshot,
      store: store,
      vaultRootURL: vaultRootURL,
      projectID: projectID,
      listIdentifier: listID
    )
    try lifecycleStore.markCompleted(
      projectID: projectID,
      reminderListExternalIdentifier: listID,
      at: now
    )
    return result
  }

  static func deleteLocalProjectForMissingReminderList(
    snapshot: ObsidianProjectMarkdownStore.Snapshot,
    store: ObsidianProjectMarkdownStore,
    vaultRootURL: URL,
    intent: ProjectLifecycleIntent = .remindersDelete,
    now: Date
  ) async throws -> DeleteResult? {
    guard let listID = normalized(snapshot.note.reminderListExternalIdentifier) else {
      return nil
    }
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: listID)
    let lifecycleStore = ProjectLifecycleStore(vaultRootURL: vaultRootURL)
    try lifecycleStore.recordStarted(
      intent: intent,
      projectID: projectID,
      reminderListExternalIdentifier: listID,
      noteVaultRelativePath: snapshot.vaultRelativePath,
      at: now
    )
    let result = try await deleteLocalProject(
      snapshot: snapshot,
      store: store,
      vaultRootURL: vaultRootURL,
      projectID: projectID,
      listIdentifier: listID
    )
    try lifecycleStore.markCompleted(
      projectID: projectID,
      reminderListExternalIdentifier: listID,
      at: now
    )
    return result
  }

  private static func deleteLocalProject(
    snapshot: ObsidianProjectMarkdownStore.Snapshot,
    store: ObsidianProjectMarkdownStore,
    vaultRootURL: URL,
    projectID: UUID,
    listIdentifier: String
  ) async throws -> DeleteResult {
    try await store.removeProjectNote(
      snapshot,
      expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: snapshot)
    )
    try cleanupDeletedProjectSidecars(
      vaultRootURL: vaultRootURL,
      note: snapshot.note,
      projectID: projectID,
      listIdentifier: listIdentifier
    )
    return DeleteResult(
      deletedProjectID: projectID,
      deletedReminderListExternalIdentifier: listIdentifier,
      deletedProjectFileURL: snapshot.fileURL
    )
  }

  static func cleanupDeletedProjectSidecars(
    vaultRootURL: URL,
    note: ObsidianProjectNote,
    projectID: UUID,
    listIdentifier: String
  ) throws {
    for task in note.tasks {
      ReminderSyncBaselineStore.remove(reminderExternalIdentifier: task.reminderExternalIdentifier)
    }
    TaskIdentityBridgeStore.removeProjects(projectIDs: [projectID])
    try ObsidianReminderOutlineStateStore(vaultRootURL: vaultRootURL)
      .removeListOutline(forListID: listIdentifier)
    try ObsidianReminderArchiveStore(vaultRootURL: vaultRootURL)
      .remove(forListIdentifier: listIdentifier)
  }

  private static func retainedProjectID(
    for snapshot: ObsidianProjectMarkdownStore.Snapshot
  ) -> UUID? {
    guard let listID = normalized(snapshot.note.reminderListExternalIdentifier) else {
      return nil
    }
    return RetainedProjectionBuilder.derivedProjectID(for: listID)
  }

  private static func validateNotes(_ notes: [ObsidianProjectNote]) throws {
    for issue in ObsidianProjectNoteValidation.issues(in: notes) {
      switch issue {
      case .duplicateReminderListExternalIdentifier(let identifier):
        throw RetainedProjectionBuilder.Error.duplicateReminderListExternalIdentifier(identifier)
      case .duplicateReminderExternalIdentifier(let identifier):
        throw RetainedProjectionBuilder.Error.duplicateReminderExternalIdentifier(identifier)
      case .damagedTaskMetadata(let line, let rawLine):
        throw RetainedTaskCommandError.retainedProjectionFailed(
          "damaged task metadata at line \(line): \(rawLine)"
        )
      }
    }
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
