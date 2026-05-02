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
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw RetainedTaskCommandError.retainedProjectionFailed("empty project title")
    }
    let context = try await commandContext(vaultRootURL: vaultRootURL, projectID: projectID)
    guard let listID = context.snapshot.note.reminderListExternalIdentifier else {
      throw RetainedTaskCommandError.unsafeProjectNote(projectID)
    }
    let remote = try reminderProjectProvider.setProjectTitle(identifier: listID, title: title)
    let resolvedTitle = normalized(remote?.title) ?? title
    return try await context.store.renameProjectNote(
      context.snapshot,
      preferredFileName: resolvedTitle,
      expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: context.snapshot)
    )
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
    let context = try await commandContext(vaultRootURL: vaultRootURL, projectID: projectID)
    return try await writeProject(using: context) { frontmatter in
      frontmatter.projectStage = stage
    }
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
    let context = try await commandContext(vaultRootURL: vaultRootURL, projectID: projectID)
    guard let listID = context.snapshot.note.reminderListExternalIdentifier else {
      throw RetainedTaskCommandError.unsafeProjectNote(projectID)
    }
    let remote = try reminderProjectProvider.setProjectColor(identifier: listID, colorHex: colorHex)
    let resolvedColor = normalized(remote?.colorHex) ?? normalized(colorHex)
    return try await writeProject(using: context) { frontmatter in
      frontmatter.colorHex = resolvedColor
    }
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
