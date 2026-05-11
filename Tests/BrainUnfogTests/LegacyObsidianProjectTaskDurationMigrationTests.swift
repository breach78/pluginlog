import XCTest
@testable import BrainUnfog

final class LegacyObsidianProjectTaskDurationMigrationTests: XCTestCase {
  func testExtractsLegacyDurationsByReminderExternalIdentifier() throws {
    let vaultRoot = try makeTemporaryDirectory()
    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    try """
    - [ ] Long task
      %% brain-unfog: {"reminder_external_id":"legacy-task","date":"2026-05-02","time":"09:30","duration":120} %%

    - [ ] No duration
      %% brain-unfog: {"reminder_external_id":"no-duration"} %%
    """.write(
      to: projectsRoot.appendingPathComponent("Project.md"),
      atomically: true,
      encoding: .utf8
    )

    let supplements = try LegacyObsidianProjectTaskDurationMigration.taskSupplements(
      vaultRootURL: vaultRoot
    )

    XCTAssertEqual(
      supplements,
      [
        AppOwnedWorkspaceStore.TaskSupplement(
          taskID: ReminderProjectionIdentity.taskID(for: "legacy-task"),
          durationMinutes: 120
        )
      ]
    )
  }

  func testSkipsConflictingLegacyDurationsForSameReminderExternalIdentifier() throws {
    let vaultRoot = try makeTemporaryDirectory()
    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    try """
    - [ ] First
      %% brain-unfog: {"reminder_external_id":"legacy-task","duration":120} %%
    """.write(
      to: projectsRoot.appendingPathComponent("One.md"),
      atomically: true,
      encoding: .utf8
    )
    try """
    - [ ] Second
      %% brain-unfog: {"reminder_external_id":"legacy-task","duration":180} %%
    """.write(
      to: projectsRoot.appendingPathComponent("Two.md"),
      atomically: true,
      encoding: .utf8
    )

    let supplements = try LegacyObsidianProjectTaskDurationMigration.taskSupplements(
      vaultRootURL: vaultRoot
    )

    XCTAssertTrue(supplements.isEmpty)
  }

  func testRunIfNeededMarksCompleteWithoutCreatingLegacyProjectsDirectory() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    try await store.prepare()

    try await LegacyObsidianProjectTaskDurationMigration.runIfNeeded(
      store: store,
      vaultRootURL: vaultRoot
    )

    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: projectsRoot.path))
    let metadataValue = try await store.metadataValue(
      forKey: LegacyObsidianProjectTaskDurationMigration.metadataKey
    )
    XCTAssertEqual(metadataValue, LegacyObsidianProjectTaskDurationMigration.completedValue)
  }

  func testRunIfNeededDoesNotReadLegacyFilesAfterCompletionMetadataExists() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
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
      LegacyObsidianProjectTaskDurationMigration.completedValue,
      forKey: LegacyObsidianProjectTaskDurationMigration.metadataKey
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

    try await LegacyObsidianProjectTaskDurationMigration.runIfNeeded(
      store: store,
      vaultRootURL: vaultRoot
    )

    let task = try await store.taskReference(projectID: projectID, taskID: taskID)
    XCTAssertNil(task.durationMinutes)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "LegacyObsidianProjectTaskDurationMigrationTests-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
