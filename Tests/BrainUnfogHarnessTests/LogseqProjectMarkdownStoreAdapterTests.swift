import XCTest
@testable import BrainUnfogHarness

final class LogseqProjectMarkdownStoreAdapterTests: XCTestCase {
  func testAdapterDelegatesToExistingLogseqProjectPageStore() async throws {
    let graphURL = try makeTemporaryDirectory(named: "LogseqAdapter")
    defer { try? FileManager.default.removeItem(at: graphURL) }
    let pagesURL = graphURL.appendingPathComponent("pages", isDirectory: true)
    let store = LogseqProjectPageStore(pagesRootURL: pagesURL)
    let adapter = LogseqProjectMarkdownStoreAdapter(store: store)

    _ = try await store.upsertPage(
      .init(
        projectID: UUID(),
        title: "Adapter Project",
        reminderListExternalIdentifier: "LIST-1"
      ),
      noteMarkdown: "Adapter note",
      managedTasks: [
        .init(
          title: "Task",
          isCompleted: false,
          reminderExternalIdentifier: "TASK-1"
        )
      ]
    )

    let snapshots = try await adapter.loadProjectNotesInScope()

    XCTAssertEqual(snapshots.map(\.title), ["Adapter Project"])
    XCTAssertEqual(snapshots.first?.reminderListExternalIdentifier, "LIST-1")
    XCTAssertEqual(snapshots.first?.externalTasks.first?.reminderExternalIdentifier, "TASK-1")
  }

  private func makeTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
