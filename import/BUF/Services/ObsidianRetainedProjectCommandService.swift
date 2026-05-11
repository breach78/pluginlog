import Foundation

@MainActor
enum ObsidianRetainedProjectCommandService {
  static func setProjectTitle(
    vaultRootURL: URL?,
    projectID: UUID,
    title rawTitle: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> AppOwnedProjectSnapshot {
    if let appOwnedStore = try await AppOwnedRetainedTaskCommandService.enabledStore(vaultRootURL: vaultRootURL) {
      return try await AppOwnedRetainedProjectCommandService.setProjectTitle(
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
  ) async throws -> AppOwnedProjectSnapshot {
    if let appOwnedStore = try await AppOwnedRetainedTaskCommandService.enabledStore(vaultRootURL: vaultRootURL) {
      return try await AppOwnedRetainedProjectCommandService.setProjectStage(
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
  ) async throws -> AppOwnedProjectSnapshot {
    if let appOwnedStore = try await AppOwnedRetainedTaskCommandService.enabledStore(vaultRootURL: vaultRootURL) {
      return try await AppOwnedRetainedProjectCommandService.setProjectColor(
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
}
