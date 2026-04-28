import XCTest
@testable import BrainUnfog

final class ObsidianProjectMarkdownStoreTests: XCTestCase {
  func testPrepareAndWriteCreatesRawProjectsDirectoryAndRoundTripsFixture() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStoreRoundTrip")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let note = ObsidianProjectNoteParser.parse(
      """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      ---

      - [ ] Task
        %% brain-unfog: {"reminder_external_id":"TASK-1","date":"2026-04-25","time":"14:00"} %%
      """
    )

    let snapshot = try await store.writeProjectNote(note, preferredFileName: "Project")

    XCTAssertEqual(snapshot.vaultRelativePath, "raw/projects/Project.md")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: vaultURL.appendingPathComponent("raw/projects").path
      )
    )
    XCTAssertEqual(snapshot.note.reminderListExternalIdentifier, "LIST-1")
    XCTAssertEqual(snapshot.note.tasks.first?.reminderExternalIdentifier, "TASK-1")
  }

  func testLoadProjectNotesScansOnlyRawProjectsMarkdownFiles() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStoreScope")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let projectsURL = vaultURL.appendingPathComponent("raw/projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: projectsURL.appendingPathComponent("nested", isDirectory: true),
      withIntermediateDirectories: true
    )
    try projectMarkdown(listID: "LIST-1").write(
      to: projectsURL.appendingPathComponent("InScope.md"),
      atomically: true,
      encoding: .utf8
    )
    try projectMarkdown(listID: "LIST-NESTED").write(
      to: projectsURL.appendingPathComponent("nested/Nested.md"),
      atomically: true,
      encoding: .utf8
    )
    try projectMarkdown(listID: "LIST-OUTSIDE").write(
      to: vaultURL.appendingPathComponent("Outside.md"),
      atomically: true,
      encoding: .utf8
    )
    try "plain".write(
      to: projectsURL.appendingPathComponent("Ignored.txt"),
      atomically: true,
      encoding: .utf8
    )

    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let snapshots = try await store.loadProjectNotesInScope()

    XCTAssertEqual(snapshots.map(\.vaultRelativePath), ["raw/projects/InScope.md"])
  }

  func testChangedFileLoadReturnsOnlyRawProjectsMarkdownFilesInScope() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStoreChangedFiles")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let projectsURL = vaultURL.appendingPathComponent("raw/projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    let changedURL = projectsURL.appendingPathComponent("Changed.md")
    let ordinaryURL = projectsURL.appendingPathComponent("Ordinary.md")
    let outsideURL = vaultURL.appendingPathComponent("Outside.md")
    try projectMarkdown(listID: "LIST-1").write(to: changedURL, atomically: true, encoding: .utf8)
    try "- [ ] Ordinary".write(to: ordinaryURL, atomically: true, encoding: .utf8)
    try projectMarkdown(listID: "LIST-OUTSIDE").write(to: outsideURL, atomically: true, encoding: .utf8)

    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let snapshots = try await store.loadProjectNotesInScope(at: [
      changedURL,
      ordinaryURL,
      outsideURL,
    ])

    XCTAssertEqual(snapshots.map(\.vaultRelativePath), ["raw/projects/Changed.md"])
  }

  func testChangedFileLoadIgnoresNestedTraversalAndSymlinkEscapes() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStorePathScope")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let projectsURL = vaultURL.appendingPathComponent("raw/projects", isDirectory: true)
    let outsideURL = vaultURL.appendingPathComponent("Outside.md")
    try FileManager.default.createDirectory(
      at: projectsURL.appendingPathComponent("nested", isDirectory: true),
      withIntermediateDirectories: true
    )
    let directURL = projectsURL.appendingPathComponent("Direct.md")
    let nestedURL = projectsURL.appendingPathComponent("nested/Nested.md")
    let symlinkURL = projectsURL.appendingPathComponent("Escape.md")
    try projectMarkdown(listID: "LIST-DIRECT").write(to: directURL, atomically: true, encoding: .utf8)
    try projectMarkdown(listID: "LIST-NESTED").write(to: nestedURL, atomically: true, encoding: .utf8)
    try projectMarkdown(listID: "LIST-OUTSIDE").write(to: outsideURL, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideURL)

    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let snapshots = try await store.loadProjectNotesInScope(at: [
      directURL,
      nestedURL,
      symlinkURL,
      projectsURL.appendingPathComponent("../projects/Direct.md"),
      outsideURL,
    ])

    XCTAssertEqual(snapshots.map(\.vaultRelativePath), ["raw/projects/Direct.md"])
  }

  func testCreateProjectStubCreatesTaggedNoteWithInitialBulletAndUniqueName() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStoreCreateProjectStub")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)

    let first = try await store.createProjectStub()
    let second = try await store.createProjectStub()

    XCTAssertEqual(first.vaultRelativePath, "raw/projects/새 프로젝트.md")
    XCTAssertEqual(second.vaultRelativePath, "raw/projects/새 프로젝트 2.md")
    XCTAssertEqual(first.note.tags, ["프로젝트"])
    XCTAssertNil(first.note.reminderListExternalIdentifier)
    XCTAssertEqual(first.note.bodyMarkdown, "- ")
    XCTAssertEqual(try String(contentsOf: first.fileURL, encoding: .utf8), """
    ---
    tags:
      - 프로젝트
    ---
    - 
    """)
  }

  func testWriteNoOpForLineEndingOnlyEquivalentContent() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStoreNoOp")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let note = ObsidianProjectNoteParser.parse(projectMarkdown(listID: "LIST-1"))

    let snapshot = try await store.writeProjectNote(note, preferredFileName: "NoOp.md")
    let lfContent = try String(contentsOf: snapshot.fileURL, encoding: .utf8)
    try lfContent
      .replacingOccurrences(of: "\n", with: "\r\n")
      .write(to: snapshot.fileURL, atomically: true, encoding: .utf8)
    let beforeMTime = try XCTUnwrap(
      snapshot.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    )

    _ = try await store.writeProjectNote(note, preferredFileName: "NoOp.md")

    let afterMTime = try XCTUnwrap(
      snapshot.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    )
    XCTAssertEqual(afterMTime, beforeMTime)
  }

  func testWriteFailsClosedWhenExistingReminderListIdentityConflictsOrIsMissing() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStoreIdentityConflict")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let original = try await store.writeProjectNote(
      ObsidianProjectNoteParser.parse(projectMarkdown(listID: "LIST-1")),
      preferredFileName: "Project.md"
    )
    let conflicting = ObsidianProjectNoteParser.parse(projectMarkdown(listID: "LIST-2"))

    do {
      _ = try await store.writeProjectNote(
        conflicting,
        preferredFileName: "Project.md",
        expectedBaseline: .init(snapshot: original)
      )
      XCTFail("Expected conflicting identity to fail closed")
    } catch ObsidianProjectMarkdownStore.StoreError.conflictingReminderListIdentity(
      let existing,
      let requested
    ) {
      XCTAssertEqual(existing, "LIST-1")
      XCTAssertEqual(requested, "LIST-2")
    }

    let fileContents = try String(contentsOf: original.fileURL, encoding: .utf8)
    XCTAssertTrue(fileContents.contains("reminder_list_external_id: LIST-1"))
    XCTAssertFalse(fileContents.contains("reminder_list_external_id: LIST-2"))

    let unownedURL = vaultURL.appendingPathComponent("raw/projects/Unowned.md")
    try """
    ---
    tags:
      - 프로젝트
    ---

    - [ ] Existing unowned
    """.write(to: unownedURL, atomically: true, encoding: .utf8)

    do {
      _ = try await store.writeProjectNote(
        ObsidianProjectNoteParser.parse(projectMarkdown(listID: "LIST-3")),
        preferredFileName: "Unowned.md"
      )
      XCTFail("Expected missing existing identity to fail closed")
    } catch ObsidianProjectMarkdownStore.StoreError.conflictingReminderListIdentity(
      let existing,
      let requested
    ) {
      XCTAssertNil(existing)
      XCTAssertEqual(requested, "LIST-3")
    }
  }

  func testWriteRequiresFreshBaselineForExistingFileMutation() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStoreBaseline")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let original = try await store.writeProjectNote(
      ObsidianProjectNoteParser.parse(projectMarkdown(listID: "LIST-1")),
      preferredFileName: "Project.md"
    )
    let updated = ObsidianProjectNoteParser.parse(
      projectMarkdown(listID: "LIST-1")
        + "\n\n- [ ] Another task\n"
    )

    do {
      _ = try await store.writeProjectNote(updated, preferredFileName: "Project.md")
      XCTFail("Expected missing baseline to fail closed")
    } catch ObsidianProjectMarkdownStore.StoreError.missingExpectedBaseline {
      // Expected.
    }

    try (original.rawMarkdown + "\nExternal edit\n")
      .write(to: original.fileURL, atomically: true, encoding: .utf8)
    do {
      _ = try await store.writeProjectNote(
        updated,
        preferredFileName: "Project.md",
        expectedBaseline: .init(snapshot: original)
      )
      XCTFail("Expected stale baseline to fail closed")
    } catch ObsidianProjectMarkdownStore.StoreError.staleExpectedBaseline {
      // Expected.
    }
  }

  func testRenameProjectNoteMovesFileAndKeepsReminderIdentity() async throws {
    let vaultURL = try makeTemporaryDirectory(named: "ObsidianStoreRename")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let original = try await store.writeProjectNote(
      ObsidianProjectNoteParser.parse(projectMarkdown(listID: "LIST-1")),
      preferredFileName: "Old Project.md"
    )

    let renamed = try await store.renameProjectNote(
      original,
      preferredFileName: "New/Project",
      expectedBaseline: .init(snapshot: original)
    )

    XCTAssertEqual(renamed.vaultRelativePath, "raw/projects/New-Project.md")
    XCTAssertEqual(renamed.note.reminderListExternalIdentifier, "LIST-1")
    XCTAssertFalse(FileManager.default.fileExists(atPath: original.fileURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.fileURL.path))
  }

  private func projectMarkdown(listID: String) -> String {
    """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: \(listID)
    ---

    - [ ] Task
      %% brain-unfog: {"reminder_external_id":"TASK-\(listID)"} %%
    """
  }

  private func makeTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
