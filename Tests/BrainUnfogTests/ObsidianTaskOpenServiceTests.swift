import XCTest
@testable import BrainUnfog

@MainActor
final class ObsidianTaskOpenServiceTests: XCTestCase {
  func testOpenProjectNoteUsesObsidianPathURIWithoutWritingMarkdown() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "ObsidianOpenProject")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let fileURL = try writeProjectNote(
      vault: vaultURL,
      fileName: "Project.md",
      body: projectMarkdown(listID: "LIST-1", taskID: "TASK-1", blockID: nil)
    )
    try FileManager.default.createDirectory(
      at: vaultURL.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    let obsidianConfigBefore = try directoryListing(at: vaultURL.appendingPathComponent(".obsidian"))
    let sidecarURL = vaultURL.appendingPathComponent(".buf", isDirectory: true)
    let before = try String(contentsOf: fileURL, encoding: .utf8)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    let opener = RecordingDocumentOpener()

    try await ObsidianTaskOpenService.openProjectNote(
      vaultRootURL: vaultURL,
      projectID: projectID,
      documentOpener: opener
    )

    XCTAssertEqual(opener.openedURLs.count, 1)
    XCTAssertEqual(opener.openedURLs[0].scheme, "obsidian")
    XCTAssertEqual(opener.openedURLs[0].host, "open")
    XCTAssertTrue(opener.openedURLs[0].absoluteString.contains("path="))
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), before)
    XCTAssertEqual(
      try directoryListing(at: vaultURL.appendingPathComponent(".obsidian")),
      obsidianConfigBefore
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
  }

  func testOpenTaskWithBlockIdentifierUsesHelperFocusURI() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "Obsidian Vault 한글")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    try writeProjectNote(
      vault: vaultURL,
      fileName: "Project Name 한글.md",
      body: projectMarkdown(listID: "LIST-1", taskID: "TASK-1", blockID: "^buf-TASK-1")
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "TASK-1")
    let opener = RecordingDocumentOpener()

    try await ObsidianTaskOpenService.openTask(
      vaultRootURL: vaultURL,
      projectID: projectID,
      taskID: taskID,
      documentOpener: opener
    )

    let opened = try XCTUnwrap(opener.openedURLs.first)
    XCTAssertEqual(opened.scheme, "obsidian")
    XCTAssertEqual(opened.host, ObsidianDeepLinking.taskFocusAction)
    XCTAssertFalse(opened.absoluteString.contains("vault="))
    XCTAssertTrue(opened.absoluteString.contains("path=%2F"))
    XCTAssertTrue(opened.absoluteString.contains("file=raw%2Fprojects%2FProject%20Name%20"))
    XCTAssertTrue(opened.absoluteString.contains("block=%5Ebuf-TASK-1"))
    XCTAssertTrue(opened.absoluteString.contains("reminder_external_id=TASK-1"))
  }

  func testOpenTaskWithoutBlockIdentifierUsesHelperFocusURIWithTaskIDFallback() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "ObsidianOpenNoBlock")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    try writeProjectNote(
      vault: vaultURL,
      fileName: "Project.md",
      body: projectMarkdown(listID: "LIST-1", taskID: "TASK-1", blockID: nil)
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "TASK-1")
    let opener = RecordingDocumentOpener()

    try await ObsidianTaskOpenService.openTask(
      vaultRootURL: vaultURL,
      projectID: projectID,
      taskID: taskID,
      documentOpener: opener
    )

    let opened = try XCTUnwrap(opener.openedURLs.first)
    XCTAssertEqual(opened.scheme, "obsidian")
    XCTAssertEqual(opened.host, ObsidianDeepLinking.taskFocusAction)
    XCTAssertTrue(opened.absoluteString.contains("path=%2F"))
    XCTAssertTrue(opened.absoluteString.contains("file=raw%2Fprojects%2FProject.md"))
    XCTAssertFalse(opened.absoluteString.contains("block="))
    XCTAssertTrue(opened.absoluteString.contains("reminder_external_id=TASK-1"))
  }

  func testOpenFailureFallsBackToMarkdownFileURL() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "ObsidianOpenFallback")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let fileURL = try writeProjectNote(
      vault: vaultURL,
      fileName: "Project.md",
      body: projectMarkdown(listID: "LIST-1", taskID: "TASK-1", blockID: "^buf-TASK-1")
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "TASK-1")
    let opener = RecordingDocumentOpener(failFirstOpen: true)

    try await ObsidianTaskOpenService.openTask(
      vaultRootURL: vaultURL,
      projectID: projectID,
      taskID: taskID,
      documentOpener: opener
    )

    XCTAssertEqual(opener.openedURLs.count, 2)
    XCTAssertEqual(opener.openedURLs[0].scheme, "obsidian")
    XCTAssertEqual(opener.openedURLs[1], fileURL.standardizedFileURL)
  }

  func testDuplicateTaskIDsFailClosedBeforeOpen() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "ObsidianOpenDuplicate")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    try writeProjectNote(
      vault: vaultURL,
      fileName: "A.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      ---

      - [ ] One
        %% brain-unfog: {"reminder_external_id":"TASK-DUP"} %%
      - [ ] Two
        %% brain-unfog: {"reminder_external_id":"TASK-DUP"} %%
      """
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "TASK-DUP")
    let opener = RecordingDocumentOpener()

    do {
      try await ObsidianTaskOpenService.openTask(
        vaultRootURL: vaultURL,
        projectID: projectID,
        taskID: taskID,
        documentOpener: opener
      )
      XCTFail("Duplicate task ids must fail closed.")
    } catch let error as ObsidianTaskOpenServiceError {
      XCTAssertEqual(error, .duplicateReminderExternalIdentifier("TASK-DUP"))
    }
    XCTAssertTrue(opener.openedURLs.isEmpty)
  }

  func testUnrelatedDamagedMetadataDoesNotBlockOpeningMatchedProject() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "ObsidianOpenUnrelatedDamaged")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    try writeProjectNote(
      vault: vaultURL,
      fileName: "Project.md",
      body: projectMarkdown(listID: "LIST-1", taskID: "TASK-1", blockID: nil)
    )
    try writeProjectNote(
      vault: vaultURL,
      fileName: "Broken.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-2
      ---

      - [ ] Broken
        %% brain-unfog: {"reminder_external_id": %%
      """
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    let opener = RecordingDocumentOpener()

    try await ObsidianTaskOpenService.openProjectNote(
      vaultRootURL: vaultURL,
      projectID: projectID,
      documentOpener: opener
    )

    XCTAssertEqual(opener.openedURLs.count, 1)
    XCTAssertEqual(opener.openedURLs[0].scheme, "obsidian")
  }

  func testMissingCurrentIdentityFailsClosedWithoutTitleFallback() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "ObsidianOpenMissingIdentity")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    try writeProjectNote(
      vault: vaultURL,
      fileName: "Looks Like The Project.md",
      body: projectMarkdown(listID: "LIST-OTHER", taskID: "TASK-1", blockID: nil)
    )
    let missingProjectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-MISSING")
    let opener = RecordingDocumentOpener()

    do {
      try await ObsidianTaskOpenService.openProjectNote(
        vaultRootURL: vaultURL,
        projectID: missingProjectID,
        documentOpener: opener
      )
      XCTFail("Missing current identity must fail closed.")
    } catch let error as ObsidianTaskOpenServiceError {
      XCTAssertEqual(error, .projectNotFound(missingProjectID))
    }
    XCTAssertTrue(opener.openedURLs.isEmpty)
  }

  func testMissingProjectsDirectoryFailsClosedWithoutCreatingFolders() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "ObsidianOpenNoProjects")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-MISSING")
    let opener = RecordingDocumentOpener()

    do {
      try await ObsidianTaskOpenService.openProjectNote(
        vaultRootURL: vaultURL,
        projectID: projectID,
        documentOpener: opener
      )
      XCTFail("Missing raw/projects must fail closed for open-only actions.")
    } catch let error as ObsidianTaskOpenServiceError {
      XCTAssertEqual(error, .projectNotFound(projectID))
    }

    XCTAssertTrue(opener.openedURLs.isEmpty)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: vaultURL.appendingPathComponent("raw/projects", isDirectory: true).path
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: vaultURL.appendingPathComponent(".buf", isDirectory: true).path
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: vaultURL.appendingPathComponent(".obsidian", isDirectory: true).path
      )
    )
  }

  func testDamagedMetadataFailsClosedBeforeOpen() async throws {
    let vaultURL = try makeTemporaryDirectory(prefix: "ObsidianOpenDamaged")
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    try writeProjectNote(
      vault: vaultURL,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      ---

      - [ ] Broken
        %% brain-unfog: {"reminder_external_id": %%
      """
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "LIST-1")
    let opener = RecordingDocumentOpener()

    do {
      try await ObsidianTaskOpenService.openProjectNote(
        vaultRootURL: vaultURL,
        projectID: projectID,
        documentOpener: opener
      )
      XCTFail("Damaged metadata must fail closed.")
    } catch let error as ObsidianTaskOpenServiceError {
      guard case .damagedTaskMetadata = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertTrue(opener.openedURLs.isEmpty)
  }

  private final class RecordingDocumentOpener: PlatformDocumentOpening {
    var openedURLs: [URL] = []
    var failFirstOpen: Bool

    init(failFirstOpen: Bool = false) {
      self.failFirstOpen = failFirstOpen
    }

    func open(_ url: URL) throws {
      openedURLs.append(url.isFileURL ? url.standardizedFileURL : url)
      if failFirstOpen {
        failFirstOpen = false
        throw TestOpenError.failed
      }
    }

    func revealInFiles(_ urls: [URL]) {
      openedURLs.append(contentsOf: urls.map(\.standardizedFileURL))
    }
  }

  private enum TestOpenError: Error {
    case failed
  }

  @discardableResult
  private func writeProjectNote(vault: URL, fileName: String, body: String) throws -> URL {
    let projectsURL = vault.appendingPathComponent("raw/projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    let fileURL = projectsURL.appendingPathComponent(fileName)
    try body.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL.standardizedFileURL
  }

  private func projectMarkdown(
    listID: String,
    taskID: String,
    blockID: String?
  ) -> String {
    let blockSuffix = blockID.map { " \($0)" } ?? ""
    return """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: \(listID)
    ---

    - [ ] Task\(blockSuffix)
      %% brain-unfog: {"reminder_external_id":"\(taskID)"} %%
    """
  }

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func directoryListing(at url: URL) throws -> [String] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
  }
}
