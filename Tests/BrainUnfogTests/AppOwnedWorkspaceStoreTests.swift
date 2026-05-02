import XCTest
@testable import BrainUnfog

final class AppOwnedWorkspaceStoreTests: XCTestCase {
  func testPrepareCreatesEmptySQLiteStore() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())

    try await store.prepare()

    let hasImportedWorkspace = try await store.hasImportedWorkspace()
    XCTAssertFalse(hasImportedWorkspace)
  }

  func testReplaceReminderSnapshotBuildsRetainedWorkspaceSnapshot() async throws {
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
    let createdAt = Date(timeIntervalSinceReferenceDate: 200)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Project",
          colorHex: "#2255aa"
        )
      ],
      itemsByListIdentifier: [
        "list-1": [
          ReminderItemImportSnapshot(
            identifier: "task-1",
            externalIdentifier: "task-1",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "Project",
            title: "Task",
            notes: "note",
            attachmentCount: 2,
            isCompleted: false,
            completionDate: nil,
            startDate: nil,
            dueDate: dueDate,
            scheduleHasExplicitTime: false,
            scheduledDurationMinutes: nil,
            priority: 1,
            recurrenceRuleRaw: "daily",
            isFlagged: true,
            requiredWorkDays: 3,
            createdAt: createdAt,
            modifiedAt: createdAt
          )
        ]
      ]
    )

    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    let project = try XCTUnwrap(snapshot.projects.first)
    let task = try XCTUnwrap(project.tasks.first)
    let hasImportedWorkspace = try await store.hasImportedWorkspace()
    XCTAssertTrue(hasImportedWorkspace)
    XCTAssertEqual(project.identity.projectID, RetainedProjectionBuilder.derivedProjectID(for: "list-1"))
    XCTAssertEqual(project.title, "Project")
    XCTAssertEqual(project.colorHex, "#2255aa")
    XCTAssertEqual(task.identity.taskID, ReminderProjectionIdentity.taskID(for: "task-1"))
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "task-1")
    XCTAssertEqual(task.title, "Task")
    XCTAssertEqual(task.noteText, "note")
    XCTAssertEqual(task.schedule.parsedDate, dueDate)
    XCTAssertEqual(task.schedule.rawRepeatRule, "daily")
  }

  func testLoadPrefersAppOwnedStoreWhenSQLiteHasImportedRows() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: vaultRoot.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    let containerRoot = ObsidianVaultLayout(vaultRootURL: vaultRoot).sidecarRootURL
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let createdAt = Date(timeIntervalSinceReferenceDate: 300)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Stored Project",
          colorHex: nil
        )
      ],
      itemsByListIdentifier: [:]
    )
    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    try await store.setProjectionReadEnabled(true)

    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: vaultRoot,
      projectIDs: [],
      calendar: Self.calendar
    )
    let projection: RetainedWorkspaceSurfaceProjection
    switch result {
    case .loaded(let loadedProjection):
      projection = loadedProjection
    case .blocked(let blocker):
      return XCTFail("Expected app-owned projection, got \(blocker)")
    }

    XCTAssertEqual(
      projection.projectSnapshots[RetainedProjectionBuilder.derivedProjectID(for: "list-1")]?.title,
      "Stored Project"
    )
  }

  func testLoadFallsBackToLegacySourceUntilProjectionReadIsEnabled() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: vaultRoot.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    let store = AppOwnedWorkspaceStore(
      containerRootURL: ObsidianVaultLayout(vaultRootURL: vaultRoot).sidecarRootURL
    )
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Shadow Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 400)
    )

    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: vaultRoot,
      projectIDs: [],
      calendar: Self.calendar
    )

    switch result {
    case .loaded(let projection):
      XCTAssertNil(projection.projectSnapshots[RetainedProjectionBuilder.derivedProjectID(for: "list-1")])
    case .blocked:
      break
    }
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppOwnedWorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
