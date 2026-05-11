import Foundation

enum LegacyObsidianProjectStageMigration {
  static let metadataKey = "legacy_obsidian_project_stage_migration_v1"
  static let completedValue = "1"

  static func runIfNeeded(
    store: AppOwnedWorkspaceStore,
    vaultRootURL: URL,
    fileManager: FileManager = .default
  ) async throws {
    guard try await store.metadataValue(forKey: metadataKey) != completedValue else {
      return
    }
    let stages = try projectStages(vaultRootURL: vaultRootURL, fileManager: fileManager)
    if !stages.isEmpty {
      try await store.restoreLegacyProjectStagesIfDefault(stages)
    }
    try await store.setMetadataValue(completedValue, forKey: metadataKey)
  }

  static func projectStages(
    vaultRootURL: URL,
    fileManager: FileManager = .default
  ) throws -> [UUID: ProjectProgressStage] {
    let projectsRootURL = ObsidianVaultLayout(
      vaultRootURL: vaultRootURL,
      fileManager: fileManager
    ).rawProjectsRootURL
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: projectsRootURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue,
      let enumerator = fileManager.enumerator(
        at: projectsRootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else {
      return [:]
    }

    var stagesByListIdentifier: [String: ProjectProgressStage] = [:]
    var conflictedListIdentifiers: Set<String> = []
    for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
      let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard resourceValues.isRegularFile == true,
        let markdown = try? String(contentsOf: url, encoding: .utf8)
      else {
        continue
      }
      let note = ObsidianProjectNoteParser.parse(markdown)
      guard let listIdentifier = normalized(note.reminderListExternalIdentifier),
        let stage = note.frontmatter?.projectStage
      else {
        continue
      }

      if let existingStage = stagesByListIdentifier[listIdentifier], existingStage != stage {
        stagesByListIdentifier.removeValue(forKey: listIdentifier)
        conflictedListIdentifiers.insert(listIdentifier)
        continue
      }
      guard !conflictedListIdentifiers.contains(listIdentifier) else {
        continue
      }
      stagesByListIdentifier[listIdentifier] = stage
    }

    return Dictionary(uniqueKeysWithValues: stagesByListIdentifier.map { listIdentifier, stage in
      (RetainedProjectionBuilder.derivedProjectID(for: listIdentifier), stage)
    })
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
