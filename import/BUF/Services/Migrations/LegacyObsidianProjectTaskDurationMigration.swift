import Foundation

enum LegacyObsidianProjectTaskDurationMigration {
  static let metadataKey = "legacy_task_duration_repair_v1"
  static let completedValue = "1"

  static func runIfNeeded(
    store: AppOwnedWorkspaceStore,
    vaultRootURL: URL,
    fileManager: FileManager = .default
  ) async throws {
    guard try await store.metadataValue(forKey: metadataKey) != completedValue else {
      return
    }
    let supplements = try taskSupplements(vaultRootURL: vaultRootURL, fileManager: fileManager)
    if !supplements.isEmpty {
      try await store.fillMissingTaskDurations(supplements)
    }
    try await store.setMetadataValue(completedValue, forKey: metadataKey)
  }

  static func taskSupplements(
    vaultRootURL: URL,
    fileManager: FileManager = .default
  ) throws -> [AppOwnedWorkspaceStore.TaskSupplement] {
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
      return []
    }

    var durationsByExternalIdentifier: [String: Int] = [:]
    var conflictedExternalIdentifiers: Set<String> = []
    for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
      let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard resourceValues.isRegularFile == true,
        let markdown = try? String(contentsOf: url, encoding: .utf8)
      else {
        continue
      }
      let note = ObsidianProjectNoteParser.parse(markdown)
      for task in note.tasks {
        guard let externalIdentifier = normalized(task.metadata?.reminderExternalIdentifier),
          let durationMinutes = task.metadata?.durationMinutes,
          durationMinutes > 0
        else {
          continue
        }

        if let existingDuration = durationsByExternalIdentifier[externalIdentifier],
          existingDuration != durationMinutes
        {
          durationsByExternalIdentifier.removeValue(forKey: externalIdentifier)
          conflictedExternalIdentifiers.insert(externalIdentifier)
          continue
        }
        guard !conflictedExternalIdentifiers.contains(externalIdentifier) else {
          continue
        }
        durationsByExternalIdentifier[externalIdentifier] = durationMinutes
      }
    }

    return durationsByExternalIdentifier
      .map { externalIdentifier, durationMinutes in
        AppOwnedWorkspaceStore.TaskSupplement(
          taskID: ReminderProjectionIdentity.taskID(for: externalIdentifier),
          durationMinutes: durationMinutes
        )
      }
      .sorted { $0.taskID.uuidString < $1.taskID.uuidString }
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
