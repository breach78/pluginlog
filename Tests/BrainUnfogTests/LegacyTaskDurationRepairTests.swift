import XCTest
@testable import BrainUnfog

final class LegacyTaskDurationRepairTests: XCTestCase {
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

    let supplements = try LegacyTaskDurationRepair.taskSupplements(vaultRootURL: vaultRoot)

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

    let supplements = try LegacyTaskDurationRepair.taskSupplements(vaultRootURL: vaultRoot)

    XCTAssertTrue(supplements.isEmpty)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("LegacyTaskDurationRepairTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
