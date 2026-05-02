import XCTest
@testable import BrainUnfog

final class AppOwnedReminderBackupStoreTests: XCTestCase {
  func testSavePreMigrationSnapshotWritesRecoverableJSONIntoBufBackups() throws {
    let root = try makeTemporaryDirectory()
    let store = AppOwnedReminderBackupStore(containerRootURL: root)
    let createdAt = Date(timeIntervalSinceReferenceDate: 100)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Project",
          colorHex: "#ff0000"
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
            attachmentCount: 0,
            isCompleted: false,
            completionDate: nil,
            startDate: nil,
            dueDate: nil,
            scheduleHasExplicitTime: false,
            scheduledDurationMinutes: nil,
            priority: 0,
            recurrenceRuleRaw: nil,
            isFlagged: false,
            requiredWorkDays: 0,
            createdAt: createdAt,
            modifiedAt: createdAt
          )
        ]
      ]
    )

    let url = try store.savePreMigrationSnapshot(batch, reason: .bootstrap, createdAt: createdAt)
    let restored = try store.loadSnapshot(at: url)

    XCTAssertTrue(url.path.contains("/backups/reminders/"))
    XCTAssertEqual(restored.schemaVersion, 1)
    XCTAssertEqual(restored.reason, .bootstrap)
    XCTAssertEqual(restored.batch, batch)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppOwnedReminderBackupStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
