import XCTest
@testable import BrainUnfogHarness

final class ObsidianChangedProjectProjectionRefreshTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testRefreshOnlyLoadsTouchedProjectNotes() async throws {
    let vaultURL = try makeVault()
    let firstURL = try writeProject(
      projectMarkdown(listID: "LIST-1", taskID: "TASK-1", title: "First"),
      named: "First.md",
      in: vaultURL
    )
    _ = try writeProject(
      projectMarkdown(listID: "LIST-2", taskID: "TASK-2", title: "Second"),
      named: "Second.md",
      in: vaultURL
    )
    let firstProjectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")

    let result = try await ObsidianChangedProjectProjectionRefresh.refresh(
      changedFileURLs: [firstURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vaultURL),
      projectIDs: [firstProjectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)

    XCTAssertEqual(surface.projectSnapshots.keys.sorted { $0.uuidString < $1.uuidString }, [firstProjectID])
    XCTAssertEqual(surface.projectSnapshots[firstProjectID]?.title, "First")
  }

  func testRefreshKeepsCalendarBridgeReadOnlyForTimedTasks() async throws {
    let vaultURL = try makeVault()
    let projectURL = try writeProject(
      """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      ---

      - [ ] Timed task
        %% brain-unfog: {"reminder_external_id":"TASK-1","date":"2026-04-25","time":"14:30","duration":45} %%
      """,
      named: "Timed.md",
      in: vaultURL
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "TASK-1")

    let result = try await ObsidianChangedProjectProjectionRefresh.refresh(
      changedFileURLs: [projectURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vaultURL),
      projectIDs: [projectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)

    XCTAssertEqual(surface.scheduleEntriesByProjectID[projectID]?.first?.scheduledDurationMinutes, 45)
    XCTAssertEqual(surface.calendarBridgeDecisionsByTaskID[taskID], .noAction)
  }

  func testRefreshIgnoresOutsideFilesWithoutFallback() async throws {
    let vaultURL = try makeVault()
    let outsideURL = vaultURL.appendingPathComponent("Outside.md")
    try projectMarkdown(listID: "LIST-OUT", taskID: "TASK-OUT", title: "Outside")
      .write(to: outsideURL, atomically: true, encoding: .utf8)
    let requestedProjectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-OUT")

    let result = try await ObsidianChangedProjectProjectionRefresh.refresh(
      changedFileURLs: [outsideURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vaultURL),
      projectIDs: [requestedProjectID],
      calendar: Self.calendar
    )

    XCTAssertEqual(result, .blocked(.partialProjectCoverage(missingProjectIDs: [requestedProjectID])))
  }

  func testRefreshFailsClosedForDuplicateIDsInChangedFiles() async throws {
    let vaultURL = try makeVault()
    let firstURL = try writeProject(
      projectMarkdown(listID: "LIST-1", taskID: "TASK-DUP", title: "First"),
      named: "First.md",
      in: vaultURL
    )
    let secondURL = try writeProject(
      projectMarkdown(listID: "LIST-2", taskID: "TASK-DUP", title: "Second"),
      named: "Second.md",
      in: vaultURL
    )

    let result = try await ObsidianChangedProjectProjectionRefresh.refresh(
      changedFileURLs: [firstURL, secondURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vaultURL),
      projectIDs: [],
      calendar: Self.calendar
    )

    XCTAssertEqual(
      result,
      .blocked(.identityFailure(.duplicateReminderExternalIdentifier("TASK-DUP")))
    )
  }

  func testRefreshFailsClosedForDamagedRequestedProjectCoverage() async throws {
    let vaultURL = try makeVault()
    let brokenURL = try writeProject(
      """
      ---
      reminder_list_external_id: LIST-BROKEN
      ---

      - [ ] Broken
        %% brain-unfog: {"reminder_external_id": %%
      """,
      named: "Broken.md",
      in: vaultURL
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-BROKEN")

    let result = try await ObsidianChangedProjectProjectionRefresh.refresh(
      changedFileURLs: [brokenURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vaultURL),
      projectIDs: [projectID],
      calendar: Self.calendar
    )

    XCTAssertEqual(result, .blocked(.partialProjectCoverage(missingProjectIDs: [projectID])))
  }

  func testDamagedChangedFileDoesNotBlockUnrelatedValidChangedProject() async throws {
    let vaultURL = try makeVault()
    let brokenURL = try writeProject(
      """
      ---
      reminder_list_external_id: LIST-BROKEN
      ---

      - [ ] Broken
        %% brain-unfog: {"reminder_external_id": %%
      """,
      named: "Broken.md",
      in: vaultURL
    )
    let validURL = try writeProject(
      projectMarkdown(listID: "LIST-OK", taskID: "TASK-OK", title: "Valid"),
      named: "Valid.md",
      in: vaultURL
    )
    let validProjectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-OK")

    let result = try await ObsidianChangedProjectProjectionRefresh.refresh(
      changedFileURLs: [brokenURL, validURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vaultURL),
      projectIDs: [validProjectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)

    XCTAssertEqual(surface.projectSnapshots[validProjectID]?.title, "Valid")
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private func makeVault() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ObsidianChangedProjection-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  @discardableResult
  private func writeProject(
    _ markdown: String,
    named fileName: String,
    in vaultURL: URL
  ) throws -> URL {
    let projectsURL = vaultURL.appendingPathComponent("raw/projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    let fileURL = projectsURL.appendingPathComponent(fileName)
    try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  private func projectMarkdown(listID: String, taskID: String, title: String) -> String {
    """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: \(listID)
    ---

    - [ ] \(title)
      %% brain-unfog: {"reminder_external_id":"\(taskID)"} %%
    """
  }
}

private extension RetainedWorkspaceSurfaceProjectionLoadResult {
  var loadedProjection: RetainedWorkspaceSurfaceProjection? {
    guard case .loaded(let projection) = self else { return nil }
    return projection
  }
}
