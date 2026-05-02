import Foundation

@MainActor
enum AppOwnedRetainedProjectCommandService {
  static func setProjectTitle(
    vaultRootURL: URL?,
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    title rawTitle: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw RetainedTaskCommandError.retainedProjectionFailed("empty project title")
    }
    let project = try await store.projectReference(projectID: projectID)
    let remote = try reminderProjectProvider.setProjectTitle(
      identifier: project.reminderListIdentifier,
      title: title
    )
    let resolvedTitle = normalized(remote?.title) ?? title
    try await store.updateProjectTitle(projectID: projectID, title: resolvedTitle, modifiedAt: .now)
    TaskIdentityBridgeStore.upsertProject(
      projectID: projectID,
      title: resolvedTitle,
      reminderListExternalIdentifier: project.reminderListExternalIdentifier ?? project.reminderListIdentifier
    )
    return try await syntheticSnapshot(
      vaultRootURL: vaultRootURL,
      store: store,
      projectID: projectID
    )
  }

  static func setProjectStage(
    vaultRootURL: URL?,
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    stage: ProjectProgressStage
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    try await store.updateProjectStage(projectID: projectID, stage: stage, modifiedAt: .now)
    return try await syntheticSnapshot(
      vaultRootURL: vaultRootURL,
      store: store,
      projectID: projectID
    )
  }

  static func setProjectColor(
    vaultRootURL: URL?,
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    colorHex: String?,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    let project = try await store.projectReference(projectID: projectID)
    let remote = try reminderProjectProvider.setProjectColor(
      identifier: project.reminderListIdentifier,
      colorHex: colorHex
    )
    let resolvedColor = normalized(remote?.colorHex) ?? normalized(colorHex)
    try await store.updateProjectColor(projectID: projectID, colorHex: resolvedColor, modifiedAt: .now)
    return try await syntheticSnapshot(
      vaultRootURL: vaultRootURL,
      store: store,
      projectID: projectID
    )
  }

  private static func syntheticSnapshot(
    vaultRootURL: URL?,
    store: AppOwnedWorkspaceStore,
    projectID: UUID
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    guard let vaultRootURL else {
      throw RetainedTaskCommandError.obsidianVaultNotConfigured
    }
    let workspace = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    guard let project = workspace.projects.first(where: { $0.identity.projectID == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    let sqliteURL = ContainerPaths(
      root: AppOwnedWorkspaceStore.containerRootURL(forVaultRootURL: vaultRootURL)
    ).sqliteURL
    let frontmatter = ObsidianProjectFrontmatter(
      tags: ["프로젝트"],
      reminderListExternalIdentifier: project.identity.reminderListExternalIdentifier,
      colorHex: project.colorHex,
      projectStage: project.progressStage,
      startDate: ReminderScheduleMetadataCodec.encodeDate(project.localStartDate, hasExplicitTime: false),
      deadline: ReminderScheduleMetadataCodec.encodeDate(project.localDeadline, hasExplicitTime: false),
      preservedLines: [],
      isArchived: project.isArchived
    )
    let note = ObsidianProjectNote(
      frontmatter: frontmatter,
      bodyMarkdown: project.noteMarkdown,
      tasks: [],
      diagnostics: [],
      normalizedContentHash: "app-owned:\(projectID.uuidString):\(project.updatedAt.timeIntervalSinceReferenceDate)"
    )
    return ObsidianProjectMarkdownStore.Snapshot(
      fileURL: sqliteURL,
      vaultRelativePath: ".buf/data/main.sqlite",
      note: note,
      rawMarkdown: "",
      contentModificationDate: project.updatedAt
    )
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
