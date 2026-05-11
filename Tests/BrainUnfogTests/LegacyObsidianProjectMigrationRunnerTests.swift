import XCTest
@testable import BrainUnfog

final class LegacyObsidianProjectMigrationRunnerTests: XCTestCase {
  func testRunIfNeededMarksCombinedMigrationComplete() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    try await store.prepare()
    try await store.upsertProject(
      projectID: UUID(),
      reminderListIdentifier: "list-1",
      reminderListExternalIdentifier: "list-1",
      title: "Project",
      colorHex: nil,
      modifiedAt: Date(timeIntervalSinceReferenceDate: 100)
    )

    try await LegacyObsidianProjectMigrationRunner.runIfNeeded(
      containerRootURL: containerRoot,
      vaultRootURL: vaultRoot
    )

    let metadataValue = try await store.metadataValue(
      forKey: LegacyObsidianProjectMigrationRunner.metadataKey
    )
    XCTAssertEqual(metadataValue, LegacyObsidianProjectMigrationRunner.completedValue)
  }

  func testRunIfNeededDoesNotReadLegacyFilesAfterCombinedCompletionMetadataExists() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let projectID = UUID()
    let taskID = ReminderProjectionIdentity.taskID(for: "legacy-task")
    try await store.upsertProject(
      projectID: projectID,
      reminderListIdentifier: "list-1",
      reminderListExternalIdentifier: "list-1",
      title: "Project",
      colorHex: nil,
      modifiedAt: Date(timeIntervalSinceReferenceDate: 100)
    )
    try await store.upsertTask(
      projectID: projectID,
      taskID: taskID,
      reminderIdentifier: "legacy-task",
      reminderExternalIdentifier: "legacy-task",
      title: "Task",
      noteText: "",
      isCompleted: false,
      completionDate: nil,
      dueDate: Date(timeIntervalSinceReferenceDate: 200),
      hasExplicitTime: true,
      durationMinutes: nil,
      modifiedAt: Date(timeIntervalSinceReferenceDate: 100)
    )
    try await store.setMetadataValue(
      LegacyObsidianProjectMigrationRunner.completedValue,
      forKey: LegacyObsidianProjectMigrationRunner.metadataKey
    )

    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    try """
    - [ ] Long task
      %% brain-unfog: {"reminder_external_id":"legacy-task","duration":120} %%
    """.write(
      to: projectsRoot.appendingPathComponent("Project.md"),
      atomically: true,
      encoding: .utf8
    )

    try await LegacyObsidianProjectMigrationRunner.runIfNeeded(
      containerRootURL: containerRoot,
      vaultRootURL: vaultRoot
    )

    let task = try await store.taskReference(projectID: projectID, taskID: taskID)
    XCTAssertNil(task.durationMinutes)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "LegacyObsidianProjectMigrationRunnerTests-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
