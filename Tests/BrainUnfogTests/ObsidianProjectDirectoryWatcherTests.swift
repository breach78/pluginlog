import XCTest
@testable import BrainUnfog

@MainActor
final class ObsidianProjectDirectoryWatcherTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testChangedProjectMarkdownFilesIgnoresNonProjectFiles() throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let tracker = ObsidianProjectChangeTracker()
    let projectURL = projectsURL.appendingPathComponent("Project.md")
    let textURL = projectsURL.appendingPathComponent("Project.txt")
    let outsideURL = vaultURL.appendingPathComponent("Outside.md")
    let nestedURL = projectsURL.appendingPathComponent("nested/Nested.md")
    let symlinkURL = projectsURL.appendingPathComponent("Escape.md")
    try FileManager.default.createDirectory(
      at: nestedURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try projectMarkdown(listID: "LIST-1").write(to: projectURL, atomically: true, encoding: .utf8)
    try "ignored".write(to: textURL, atomically: true, encoding: .utf8)
    try projectMarkdown(listID: "LIST-OUT").write(to: outsideURL, atomically: true, encoding: .utf8)
    try projectMarkdown(listID: "LIST-NESTED").write(to: nestedURL, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideURL)

    let changedFiles = tracker.changedProjectMarkdownFiles(in: projectsURL)

    XCTAssertEqual(changedFiles.map(\.lastPathComponent), ["Project.md"])
  }

  func testDefaultWatcherDebounceLeavesTenSecondsOfIdleTimeBeforeSync() {
    XCTAssertEqual(ObsidianProjectDirectoryWatcher.defaultDebounceNanoseconds, 10_000_000_000)
    XCTAssertLessThan(
      ObsidianProjectDirectoryWatcher.defaultFastDebounceNanoseconds,
      ObsidianProjectDirectoryWatcher.defaultDebounceNanoseconds
    )
    XCTAssertFalse(ObsidianProjectDirectoryWatcher.defaultFastPollingEnabled)
  }

  func testAppAuthoredObsidianMarkdownWriteDoesNotReportChangeLoop() throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let tracker = ObsidianProjectChangeTracker()
    let projectURL = projectsURL.appendingPathComponent("Project.md")
    try projectMarkdown(listID: "LIST-1").write(to: projectURL, atomically: true, encoding: .utf8)
    _ = tracker.changedProjectMarkdownFiles(in: projectsURL)

    try projectMarkdown(listID: "LIST-1", taskID: "TASK-2")
      .write(to: projectURL, atomically: true, encoding: .utf8)
    tracker.recordAppAuthoredWrite(to: projectURL)

    XCTAssertEqual(tracker.changedProjectMarkdownFiles(in: projectsURL), [])
  }

  func testDeletedProjectFileDoesNotBecomeChangedFileCandidate() throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let tracker = ObsidianProjectChangeTracker()
    let projectURL = projectsURL.appendingPathComponent("Project.md")
    try projectMarkdown(listID: "LIST-1").write(to: projectURL, atomically: true, encoding: .utf8)
    _ = tracker.changedProjectMarkdownFiles(in: projectsURL)

    try FileManager.default.removeItem(at: projectURL)

    XCTAssertEqual(tracker.changedProjectMarkdownFiles(in: projectsURL), [])
  }

  func testRenamedProjectFileReportsOnlyNewDirectMarkdownCandidate() throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let tracker = ObsidianProjectChangeTracker()
    let originalURL = projectsURL.appendingPathComponent("Original.md")
    let renamedURL = projectsURL.appendingPathComponent("Renamed.md")
    try projectMarkdown(listID: "LIST-1").write(to: originalURL, atomically: true, encoding: .utf8)
    _ = tracker.changedProjectMarkdownFiles(in: projectsURL)

    try FileManager.default.moveItem(at: originalURL, to: renamedURL)

    XCTAssertEqual(tracker.changedProjectMarkdownFiles(in: projectsURL).map(\.lastPathComponent), ["Renamed.md"])
  }

  func testWatcherCoalescesRepeatedChangesAndReschedulesIdleDebounce() async throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let projectURL = projectsURL.appendingPathComponent("Project.md")
    try projectMarkdown(listID: "LIST-1").write(to: projectURL, atomically: true, encoding: .utf8)

    let detected = expectation(description: "debounced watcher reports one coalesced change")
    var handlerCalls = 0
    let watcher = ObsidianProjectDirectoryWatcher(
      vaultRootURL: vaultURL,
      debounceNanoseconds: 120_000_000,
      pollingNanoseconds: 40_000_000
    ) { changedFiles in
      handlerCalls += 1
      XCTAssertEqual(changedFiles.map(\.lastPathComponent), ["Project.md"])
      detected.fulfill()
    }
    watcher.start()
    defer { watcher.stop() }

    try await Task.sleep(nanoseconds: 80_000_000)
    try projectMarkdown(listID: "LIST-1", taskID: "TASK-2")
      .write(to: projectURL, atomically: true, encoding: .utf8)
    try await Task.sleep(nanoseconds: 60_000_000)
    try projectMarkdown(listID: "LIST-1", taskID: "TASK-3")
      .write(to: projectURL, atomically: true, encoding: .utf8)

    await fulfillment(of: [detected], timeout: 2)
    XCTAssertEqual(handlerCalls, 1)
  }

  func testWatcherReceivesExistingProjectFileContentChangeWithoutPolling() async throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let projectURL = projectsURL.appendingPathComponent("Project.md")
    try projectMarkdown(listID: "LIST-1").write(to: projectURL, atomically: true, encoding: .utf8)

    let detected = expectation(description: "file events report existing project file content change")
    let watcher = ObsidianProjectDirectoryWatcher(
      vaultRootURL: vaultURL,
      debounceNanoseconds: 120_000_000,
      pollingNanoseconds: nil
    ) { changedFiles in
      XCTAssertEqual(changedFiles.map(\.lastPathComponent), ["Project.md"])
      detected.fulfill()
    }
    watcher.start()
    defer { watcher.stop() }

    try await Task.sleep(nanoseconds: 120_000_000)
    try projectMarkdown(listID: "LIST-1", taskID: "TASK-2")
      .write(to: projectURL, atomically: true, encoding: .utf8)

    await fulfillment(of: [detected], timeout: 2)
  }

  func testWatcherAccumulatesDifferentProjectFilesDuringOneIdleWindow() async throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let firstURL = projectsURL.appendingPathComponent("A.md")
    let secondURL = projectsURL.appendingPathComponent("B.md")
    try projectMarkdown(listID: "LIST-A").write(to: firstURL, atomically: true, encoding: .utf8)
    try projectMarkdown(listID: "LIST-B").write(to: secondURL, atomically: true, encoding: .utf8)

    let detected = expectation(description: "debounced watcher reports both changed project files")
    let watcher = ObsidianProjectDirectoryWatcher(
      vaultRootURL: vaultURL,
      debounceNanoseconds: 120_000_000,
      pollingNanoseconds: 40_000_000
    ) { changedFiles in
      XCTAssertEqual(changedFiles.map(\.lastPathComponent), ["A.md", "B.md"])
      detected.fulfill()
    }
    watcher.start()
    defer { watcher.stop() }

    try await Task.sleep(nanoseconds: 80_000_000)
    try projectMarkdown(listID: "LIST-A", taskID: "TASK-A-2")
      .write(to: firstURL, atomically: true, encoding: .utf8)
    try await Task.sleep(nanoseconds: 60_000_000)
    try projectMarkdown(listID: "LIST-B", taskID: "TASK-B-2")
      .write(to: secondURL, atomically: true, encoding: .utf8)

    await fulfillment(of: [detected], timeout: 2)
  }

  func testFastInvalidationHintDoesNotConsumeDebouncedSyncChange() async throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let projectURL = projectsURL.appendingPathComponent("Project.md")
    try projectMarkdown(listID: "LIST-1").write(to: projectURL, atomically: true, encoding: .utf8)

    let fastDetected = expectation(description: "fast hint reports projection invalidation")
    let syncDetected = expectation(description: "debounced sync still receives changed file")
    let watcher = ObsidianProjectDirectoryWatcher(
      vaultRootURL: vaultURL,
      debounceNanoseconds: 120_000_000,
      fastDebounceNanoseconds: 10_000_000_000,
      pollingNanoseconds: nil,
      fastPollingNanoseconds: 40_000_000,
      fastHandler: {
        fastDetected.fulfill()
      }
    ) { changedFiles in
      if changedFiles.map(\.lastPathComponent) == ["Project.md"] {
        syncDetected.fulfill()
      }
    }
    watcher.start()
    defer { watcher.stop() }

    try await Task.sleep(nanoseconds: 80_000_000)
    try projectMarkdown(listID: "LIST-1", taskID: "TASK-2")
      .write(to: projectURL, atomically: true, encoding: .utf8)

    await fulfillment(of: [fastDetected, syncDetected], timeout: 2)
  }

  func testFileEventsDriveFastHintAndDebouncedSyncWithoutPolling() async throws {
    let vaultURL = try makeVault()
    let projectsURL = try makeProjectsDirectory(in: vaultURL)
    let projectURL = projectsURL.appendingPathComponent("Project.md")
    try projectMarkdown(listID: "LIST-1").write(to: projectURL, atomically: true, encoding: .utf8)

    let fastDetected = expectation(description: "file event reports fast projection invalidation")
    let syncDetected = expectation(description: "file event reports debounced sync change")
    let watcher = ObsidianProjectDirectoryWatcher(
      vaultRootURL: vaultURL,
      debounceNanoseconds: 120_000_000,
      fastDebounceNanoseconds: 40_000_000,
      pollingNanoseconds: nil,
      fastPollingNanoseconds: nil,
      fastHandler: {
        fastDetected.fulfill()
      }
    ) { changedFiles in
      XCTAssertEqual(changedFiles.map(\.lastPathComponent), ["Project.md"])
      syncDetected.fulfill()
    }
    watcher.start()
    defer { watcher.stop() }

    try await Task.sleep(nanoseconds: 120_000_000)
    try projectMarkdown(listID: "LIST-1", taskID: "TASK-2")
      .write(to: projectURL, atomically: true, encoding: .utf8)

    await fulfillment(of: [fastDetected, syncDetected], timeout: 2)
  }

  private func makeVault() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ObsidianProjectWatcher-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  private func makeProjectsDirectory(in vaultURL: URL) throws -> URL {
    let projectsURL = vaultURL.appendingPathComponent("raw/projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    return projectsURL
  }

  private func projectMarkdown(listID: String, taskID: String = "TASK-1") -> String {
    """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: \(listID)
    ---

    - [ ] Task
      %% brain-unfog: {"reminder_external_id":"\(taskID)"} %%
    """
  }
}
