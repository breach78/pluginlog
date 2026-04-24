import XCTest
@testable import BrainUnfogHarness

final class LogseqPagesChangeTrackerTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testChangedMarkdownFilesIgnoresNonMarkdownFiles() throws {
    let pagesRoot = try makePagesRoot()
    let tracker = LogseqPagesChangeTracker()
    let markdownURL = pagesRoot.appendingPathComponent("Project.md", isDirectory: false)
    let textURL = pagesRoot.appendingPathComponent("Project.txt", isDirectory: false)
    try "tags:: 프로젝트\n".write(to: markdownURL, atomically: true, encoding: .utf8)
    try "ignore\n".write(to: textURL, atomically: true, encoding: .utf8)

    let changedFiles = tracker.changedMarkdownFiles(in: pagesRoot)

    XCTAssertEqual(changedFiles.map(\.lastPathComponent), ["Project.md"])
  }

  func testAppAuthoredMarkdownWriteDoesNotReportChangeLoop() throws {
    let pagesRoot = try makePagesRoot()
    let tracker = LogseqPagesChangeTracker()
    let markdownURL = pagesRoot.appendingPathComponent("Project.md", isDirectory: false)
    try "tags:: 프로젝트\n".write(to: markdownURL, atomically: true, encoding: .utf8)
    _ = tracker.changedMarkdownFiles(in: pagesRoot)

    try "tags:: 프로젝트\nreminder_list_external_id:: list-1\n".write(
      to: markdownURL,
      atomically: true,
      encoding: .utf8
    )
    tracker.recordAppAuthoredWrite(to: markdownURL)
    XCTAssertEqual(tracker.changedMarkdownFiles(in: pagesRoot), [])

    try "tags:: 프로젝트\nreminder_list_external_id:: list-1\n- TODO External\n".write(
      to: markdownURL,
      atomically: true,
      encoding: .utf8
    )
    XCTAssertEqual(tracker.changedMarkdownFiles(in: pagesRoot).map(\.lastPathComponent), ["Project.md"])
  }

  func testAppAuthoredWriteTrackingToleratesConcurrentWatcherCallbacks() throws {
    let pagesRoot = try makePagesRoot()
    let tracker = LogseqPagesChangeTracker()
    let markdownURL = pagesRoot.appendingPathComponent("Project.md", isDirectory: false)
    try "tags:: 프로젝트\n".write(to: markdownURL, atomically: true, encoding: .utf8)
    _ = tracker.changedMarkdownFiles(in: pagesRoot)

    DispatchQueue.concurrentPerform(iterations: 200) { index in
      if index.isMultiple(of: 2) {
        tracker.recordAppAuthoredWrite(to: markdownURL)
      } else {
        _ = tracker.changedMarkdownFiles(in: pagesRoot)
      }
    }

    _ = tracker.changedMarkdownFiles(in: pagesRoot)
  }

  private func makePagesRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("LogseqPagesChangeTrackerTests-\(UUID().uuidString)", isDirectory: true)
    let pagesRoot = root.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return pagesRoot
  }
}
