import XCTest
@testable import BrainUnfog

final class ObsidianRetainedProjectionAdapterTests: XCTestCase {
  func testBuildMapsObsidianProjectNoteIntoRetainedSnapshot() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      ---

      Project notes.

      - [ ] Timed task ^buf-TASK-1
        %% brain-unfog: {"reminder_external_id":"TASK-1","date":"2026-04-25","time":"14:30","duration":45,"repeat":"weekly"} %%
      """,
      named: "Launch.md",
      in: vaultURL
    )

    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let snapshots = try await store.loadProjectNotesInScope()
    let retained = try ObsidianRetainedProjectionAdapter.build(
      snapshots: snapshots,
      calendar: Self.calendar
    )

    let project = try XCTUnwrap(retained.projects.first)
    let expectedProjectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    XCTAssertEqual(project.identity.projectID, expectedProjectID)
    XCTAssertEqual(project.identity.reminderListExternalIdentifier, "LIST-1")
    XCTAssertEqual(project.title, "Launch")
    XCTAssertEqual(project.fileURL.lastPathComponent, "Launch.md")
    XCTAssertTrue(project.usesProjectTag)
    XCTAssertFalse(project.hasManagedTaskSection)
    XCTAssertFalse(project.canSafelyPersistProjectNote)

    let task = try XCTUnwrap(project.tasks.first)
    XCTAssertEqual(task.identity.taskID, ReminderProjectionIdentity.taskID(for: "TASK-1"))
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "TASK-1")
    XCTAssertNil(task.identity.calendarEventExternalIdentifier)
    XCTAssertEqual(task.title, "Timed task")
    XCTAssertFalse(task.isCompleted)
    XCTAssertEqual(
      task.schedule.parsedDate,
      Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 14, minute: 30))
    )
    XCTAssertTrue(task.schedule.hasExplicitTime)
    XCTAssertEqual(task.schedule.rawDuration, "45")
    XCTAssertEqual(task.schedule.durationMinutes, 45)
    XCTAssertEqual(task.schedule.rawRepeatRule, "weekly")
    XCTAssertEqual(task.schedule.canonicalRepeatRule, "weekly|1|")
  }

  func testDuplicateObsidianReminderTaskIDFailsClosed() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      projectMarkdown(listID: "LIST-1", taskID: "TASK-DUP", title: "A"),
      named: "A.md",
      in: vaultURL
    )
    try writeProject(
      projectMarkdown(listID: "LIST-2", taskID: "TASK-DUP", title: "B"),
      named: "B.md",
      in: vaultURL
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)

    do {
      let snapshots = try await store.loadProjectNotesInScope()
      _ = try ObsidianRetainedProjectionAdapter.build(
        snapshots: snapshots,
        calendar: Self.calendar
      )
      XCTFail("Duplicate Obsidian reminder task IDs must block projection.")
    } catch let error as RetainedProjectionBuilder.Error {
      XCTAssertEqual(error, .duplicateReminderExternalIdentifier("TASK-DUP"))
    }
  }

  func testReminderRepeatMarkerKeepsTaskRecurringWithoutOwningRecurrenceDetails() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      ---
      - [ ] Repeating task
        %% brain-unfog: {"reminder_external_id":"TASK-1","repeat":"reminder"} %%
      """,
      named: "Repeats.md",
      in: vaultURL
    )
    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
      .loadProjectNotesInScope()

    let retained = try ObsidianRetainedProjectionAdapter.build(
      snapshots: snapshots,
      calendar: Self.calendar
    )

    let task = try XCTUnwrap(retained.projects.first?.tasks.first)
    XCTAssertEqual(task.schedule.rawRepeatRule, "reminder")
    XCTAssertEqual(task.schedule.canonicalRepeatRule, "reminder")
  }

  func testBuildCarriesObsidianTaskNoteIntoRetainedTask() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      ---
      - [ ] Task with note
        %% brain-unfog: {"reminder_external_id":"TASK-1"} %%
        - First note line
        - Second note line
      """,
      named: "Notes.md",
      in: vaultURL
    )
    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
      .loadProjectNotesInScope()

    let retained = try ObsidianRetainedProjectionAdapter.build(
      snapshots: snapshots,
      calendar: Self.calendar
    )

    let task = try XCTUnwrap(retained.projects.first?.tasks.first)
    XCTAssertEqual(task.noteText, "First note line\nSecond note line")
  }

  func testDuplicateObsidianReminderListIDFailsClosed() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      projectMarkdown(listID: "LIST-DUP", taskID: "TASK-1", title: "A"),
      named: "A.md",
      in: vaultURL
    )
    try writeProject(
      projectMarkdown(listID: "LIST-DUP", taskID: "TASK-2", title: "B"),
      named: "B.md",
      in: vaultURL
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)

    do {
      let snapshots = try await store.loadProjectNotesInScope()
      _ = try ObsidianRetainedProjectionAdapter.build(
        snapshots: snapshots,
        calendar: Self.calendar
      )
      XCTFail("Duplicate Obsidian reminder list IDs must block projection.")
    } catch let error as RetainedProjectionBuilder.Error {
      XCTAssertEqual(error, .duplicateReminderListExternalIdentifier("LIST-DUP"))
    }
  }

  func testDamagedObsidianTaskMetadataExcludesDamagedProjectOnly() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      """
      ---
      reminder_list_external_id: LIST-1
      ---

      - [ ] Broken
        %% brain-unfog: {"reminder_external_id": %%
      """,
      named: "Broken.md",
      in: vaultURL
    )
    try writeProject(
      projectMarkdown(listID: "LIST-OK", taskID: "TASK-OK", title: "Valid"),
      named: "Valid.md",
      in: vaultURL
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)

    let snapshots = try await store.loadProjectNotesInScope()
    let retained = try ObsidianRetainedProjectionAdapter.build(
      snapshots: snapshots,
      calendar: Self.calendar
    )

    XCTAssertEqual(retained.projects.map(\.title), ["Valid"])
  }

  func testReminderTaskInNoteWithoutListIDIsNotProjected() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      """
      ---
      tags: [프로젝트]
      ---

      - [ ] Orphan task
        %% brain-unfog: {"reminder_external_id":"TASK-1"} %%
      """,
      named: "Orphan.md",
      in: vaultURL
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)

    let snapshots = try await store.loadProjectNotesInScope()
    let retained = try ObsidianRetainedProjectionAdapter.build(
      snapshots: snapshots,
      calendar: Self.calendar
    )

    XCTAssertTrue(retained.projects.isEmpty)
  }

  func testLegacyBrainUnfogIdentityFieldsDoNotCreateProjectionIdentities() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      """
      ---
      tags: [프로젝트]
      brain_unfog_project_id: 30AEF9F5-10DC-4FBB-B9B6-1DD694BC77F3
      ---

      - [ ] Legacy task
        %% brain-unfog: {"brain_unfog_task_id":"B49E8D12-F2EA-4E75-8DE2-0C8E06BB263B","date":"2026-04-25"} %%
      """,
      named: "Legacy.md",
      in: vaultURL
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)

    let snapshots = try await store.loadProjectNotesInScope()
    let retained = try ObsidianRetainedProjectionAdapter.build(
      snapshots: snapshots,
      calendar: Self.calendar
    )

    XCTAssertTrue(retained.projects.isEmpty)
  }

  func testSurfaceProjectionDoesNotLoadLegacyObsidianProjectsWithoutAppOwnedImport() async throws {
    let vaultURL = try makeVault()
    _ = try writeProject(
      projectMarkdown(listID: "LIST-1", taskID: "TASK-1", title: "Obsidian task"),
      named: "Obsidian Project.md",
      in: vaultURL
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")

    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: vaultURL,
      projectIDs: [projectID],
      calendar: Self.calendar
    )

    XCTAssertEqual(
      result,
      .blocked(.loadFailed("App-owned workspace has not imported Reminders yet."))
    )
  }

  func testSurfaceProjectionIgnoresLegacyObsidianProjectNotesWithoutAppOwnedImport() async throws {
    let vaultURL = try makeVault()
    try writeProject(
      projectMarkdown(listID: "LIST-1", taskID: "TASK-SHARED", title: "Requested task"),
      named: "Requested.md",
      in: vaultURL
    )
    try writeProject(
      projectMarkdown(listID: "LIST-2", taskID: "TASK-SHARED", title: "Unrelated task"),
      named: "Unrelated.md",
      in: vaultURL
    )
    let requestedProjectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")

    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: vaultURL,
      projectIDs: [requestedProjectID],
      calendar: Self.calendar
    )

    XCTAssertEqual(
      result,
      .blocked(.loadFailed("App-owned workspace has not imported Reminders yet."))
    )
  }

  func testSurfaceProjectionReadDoesNotRewriteObsidianMarkdown() async throws {
    let vaultURL = try makeVault()
    let fileURL = try writeProject(
      projectMarkdown(listID: "LIST-1", taskID: "TASK-1", title: "Read-only"),
      named: "Read-only.md",
      in: vaultURL
    )
    let originalContent = try String(contentsOf: fileURL, encoding: .utf8)
    let originalAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")

    _ = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: vaultURL,
      projectIDs: [projectID],
      calendar: Self.calendar
    )

    let currentContent = try String(contentsOf: fileURL, encoding: .utf8)
    let currentAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    XCTAssertEqual(currentContent, originalContent)
    XCTAssertEqual(
      currentAttributes[.modificationDate] as? Date,
      originalAttributes[.modificationDate] as? Date
    )
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private func projectMarkdown(
    listID: String,
    taskID: String,
    title: String
  ) -> String {
    """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: \(listID)
    ---

    - [ ] \(title)
      %% brain-unfog: {"reminder_external_id":"\(taskID)","date":"2026-04-25","time":"14:30","duration":45} %%
    """
  }

  @discardableResult
  private func writeProject(
    _ markdown: String,
    named fileName: String,
    in vaultURL: URL
  ) throws -> URL {
    let projectsURL = vaultURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    let fileURL = projectsURL.appendingPathComponent(fileName)
    try markdown.write(
      to: fileURL,
      atomically: true,
      encoding: .utf8
    )
    return fileURL
  }

  private func makeVault() throws -> URL {
    try makeTemporaryDirectory()
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ObsidianRetainedProjection-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

private extension RetainedWorkspaceSurfaceProjectionLoadResult {
  var loadedProjection: RetainedWorkspaceSurfaceProjection? {
    guard case .loaded(let projection) = self else { return nil }
    return projection
  }
}
