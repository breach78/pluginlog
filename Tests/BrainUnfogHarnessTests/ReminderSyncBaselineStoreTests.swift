import XCTest
@testable import BrainUnfogHarness

final class ReminderSyncBaselineStoreTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    ReminderSyncBaselineStore.reset()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testUpsertManyPersistsAllBaselineUpdates() throws {
    let dataRoot = try makeTemporaryDirectory()
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let now = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 25))
    )

    ReminderSyncBaselineStore.upsertMany([
      update(identifier: "task-1", title: "One", now: now),
      update(identifier: "task-2", title: "Two", now: now),
      update(identifier: "task-3", title: "Three", now: now),
    ])

    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-1")?.state.title, "One")
    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-2")?.state.title, "Two")
    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-3")?.state.title, "Three")
    let fileURL = dataRoot.appendingPathComponent("retained-sync-baselines.json")
    let persisted = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertEqual(persisted.components(separatedBy: "reminderExternalIdentifier").count - 1, 3)
  }

  func testUpsertManyDoesNotRewriteUnchangedBaselines() throws {
    let dataRoot = try makeTemporaryDirectory()
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let firstWriteAt = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 25))
    )
    let secondWriteAt = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 26))
    )

    ReminderSyncBaselineStore.upsertMany([
      update(identifier: "task-1", title: "One", now: firstWriteAt),
    ])
    ReminderSyncBaselineStore.upsertMany([
      update(
        identifier: "task-1",
        title: "One",
        remoteModifiedAt: firstWriteAt,
        now: secondWriteAt
      ),
    ])

    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-1")?.updatedAt, firstWriteAt)
  }

  private func update(
    identifier: String,
    title: String,
    remoteModifiedAt: Date? = nil,
    now: Date
  ) -> ReminderSyncTaskBaselineUpdate {
    ReminderSyncTaskBaselineUpdate(
      reminderExternalIdentifier: identifier,
      state: ReminderSyncTaskState(
        title: title,
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt ?? now,
      now: now
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }
}
