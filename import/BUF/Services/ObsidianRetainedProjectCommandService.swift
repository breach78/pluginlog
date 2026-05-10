import Foundation

@MainActor
enum ObsidianRetainedProjectCommandService {
  static func setProjectTitle(
    vaultRootURL: URL?,
    projectID: UUID,
    title rawTitle: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    if let appOwnedStore = try await AppOwnedRetainedTaskCommandService.enabledStore(vaultRootURL: vaultRootURL) {
      return try await AppOwnedRetainedProjectCommandService.setProjectTitle(
        vaultRootURL: vaultRootURL,
        store: appOwnedStore,
        projectID: projectID,
        title: rawTitle,
        reminderProjectProvider: reminderProjectProvider
      )
    }
    throw legacyObsidianStorageDisabled()
  }

  static func setProjectStage(
    vaultRootURL: URL?,
    projectID: UUID,
    stage: ProjectProgressStage
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    if let appOwnedStore = try await AppOwnedRetainedTaskCommandService.enabledStore(vaultRootURL: vaultRootURL) {
      return try await AppOwnedRetainedProjectCommandService.setProjectStage(
        vaultRootURL: vaultRootURL,
        store: appOwnedStore,
        projectID: projectID,
        stage: stage
      )
    }
    throw legacyObsidianStorageDisabled()
  }

  static func setProjectNote(
    vaultRootURL: URL?,
    projectID: UUID,
    noteText: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> String {
    if let appOwnedStore = try await AppOwnedRetainedTaskCommandService.enabledStore(vaultRootURL: vaultRootURL) {
      return try await AppOwnedRetainedProjectCommandService.setProjectNote(
        vaultRootURL: vaultRootURL,
        store: appOwnedStore,
        projectID: projectID,
        noteText: noteText,
        reminderProjectProvider: reminderProjectProvider
      )
    }
    throw RetainedTaskCommandError.retainedProjectionFailed(
      "project note reminders require app-owned workspace storage"
    )
  }

  static func setProjectColor(
    vaultRootURL: URL?,
    projectID: UUID,
    colorHex: String?,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    if let appOwnedStore = try await AppOwnedRetainedTaskCommandService.enabledStore(vaultRootURL: vaultRootURL) {
      return try await AppOwnedRetainedProjectCommandService.setProjectColor(
        vaultRootURL: vaultRootURL,
        store: appOwnedStore,
        projectID: projectID,
        colorHex: colorHex,
        reminderProjectProvider: reminderProjectProvider
      )
    }
    throw legacyObsidianStorageDisabled()
  }

  private static func legacyObsidianStorageDisabled() -> RetainedTaskCommandError {
    RetainedTaskCommandError.retainedProjectionFailed(
      "legacy Obsidian project/task markdown storage is disabled"
    )
  }

  private struct CommandContext {
    let store: ObsidianProjectMarkdownStore
    let snapshot: ObsidianProjectMarkdownStore.Snapshot
  }

  private static func commandContext(
    vaultRootURL: URL?,
    projectID: UUID
  ) async throws -> CommandContext {
    guard let vaultRootURL else {
      throw RetainedTaskCommandError.obsidianVaultNotConfigured
    }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultRootURL)
    let snapshots = try await store.loadProjectNotesInScope()
    try validateNotes(snapshots.map(\.note))
    guard let snapshot = snapshots.first(where: { retainedProjectID(for: $0) == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    guard snapshot.note.reminderListExternalIdentifier != nil else {
      throw RetainedTaskCommandError.unsafeProjectNote(projectID)
    }
    return CommandContext(store: store, snapshot: snapshot)
  }

  private static func writeProject(
    using context: CommandContext,
    mutate: (inout ObsidianProjectFrontmatter) -> Void
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    guard var frontmatter = context.snapshot.note.frontmatter else {
      throw RetainedTaskCommandError.unsafeProjectNote(retainedProjectID(for: context.snapshot) ?? UUID())
    }
    mutate(&frontmatter)
    var note = context.snapshot.note
    note.frontmatter = frontmatter
    try validateNotes([note])
    return try await context.store.writeProjectNote(
      note,
      preferredFileName: context.snapshot.fileURL.lastPathComponent,
      expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: context.snapshot)
    )
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
