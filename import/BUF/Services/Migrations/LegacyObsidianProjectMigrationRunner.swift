import Foundation

enum LegacyObsidianProjectMigrationRunner {
  static let metadataKey = "legacy_obsidian_project_migrations_completed_v1"
  static let completedValue = "1"

  static func runIfNeeded(
    containerRootURL: URL?,
    vaultRootURL: URL?
  ) async throws {
    guard let containerRootURL, let vaultRootURL else { return }
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRootURL)
    guard try await store.hasImportedWorkspace() else { return }
    guard try await store.metadataValue(forKey: metadataKey) != completedValue else { return }
    try await LegacyObsidianProjectTaskDurationMigration.runIfNeeded(
      store: store,
      vaultRootURL: vaultRootURL
    )
    try await LegacyObsidianProjectStageMigration.runIfNeeded(
      store: store,
      vaultRootURL: vaultRootURL
    )
    try await store.setMetadataValue(completedValue, forKey: metadataKey)
  }
}
