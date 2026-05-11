import XCTest
@testable import BrainUnfog

final class LegacyObsidianProjectStageMigrationTests: XCTestCase {
  func testExtractsLegacyProjectStagesByReminderListExternalIdentifier() throws {
    let vaultRoot = try makeTemporaryDirectory()
    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    try """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: list-1
    분류:
      - Area
    ---
    """.write(
      to: projectsRoot.appendingPathComponent("Project.md"),
      atomically: true,
      encoding: .utf8
    )

    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let stages = try LegacyObsidianProjectStageMigration.projectStages(
      vaultRootURL: vaultRoot
    )

    XCTAssertEqual(stages, [projectID: .area])
  }

  func testRunIfNeededRestoresDefaultAppOwnedProjectStage() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 250)
    )
    try writeLegacyProject(
      vaultRoot: vaultRoot,
      listIdentifier: "list-1",
      stage: .later
    )

    try await LegacyObsidianProjectStageMigration.runIfNeeded(
      store: store,
      vaultRootURL: vaultRoot
    )

    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let project = try XCTUnwrap(snapshot.projects.first)
    XCTAssertEqual(project.progressStage, .later)
  }

  func testRunIfNeededDoesNotOverrideExistingNonDefaultAppOwnedProjectStage() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 250)
    )
    _ = try await store.updateProjectStage(
      projectID: projectID,
      stage: .decide,
      modifiedAt: Date(timeIntervalSinceReferenceDate: 260)
    )
    try writeLegacyProject(
      vaultRoot: vaultRoot,
      listIdentifier: "list-1",
      stage: .area
    )

    try await LegacyObsidianProjectStageMigration.runIfNeeded(
      store: store,
      vaultRootURL: vaultRoot
    )

    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let project = try XCTUnwrap(snapshot.projects.first)
    XCTAssertEqual(project.progressStage, .decide)
  }

  func testRunIfNeededMarksCompleteWithoutCreatingLegacyProjectsDirectory() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())

    try await LegacyObsidianProjectStageMigration.runIfNeeded(
      store: store,
      vaultRootURL: vaultRoot
    )

    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: projectsRoot.path))
    let metadataValue = try await store.metadataValue(
      forKey: LegacyObsidianProjectStageMigration.metadataKey
    )
    XCTAssertEqual(metadataValue, LegacyObsidianProjectStageMigration.completedValue)
  }

  private func writeLegacyProject(
    vaultRoot: URL,
    listIdentifier: String,
    stage: ProjectProgressStage
  ) throws {
    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    try """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: \(listIdentifier)
    분류:
      - \(stage.title)
    ---
    """.write(
      to: projectsRoot.appendingPathComponent("\(listIdentifier).md"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "LegacyObsidianProjectStageMigrationTests-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
