import XCTest
@testable import BrainUnfog

final class AppOwnedReminderBridgeRecordMapperTests: XCTestCase {
  func testRecordsMapReminderBatchToBridgeRecords() {
    let importedAt = Date(timeIntervalSinceReferenceDate: 700)
    let createdAt = Date(timeIntervalSinceReferenceDate: 650)
    let modifiedAt = Date(timeIntervalSinceReferenceDate: 690)
    let records = AppOwnedReminderBridgeRecordMapper.records(
      from: ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-identifier",
            externalIdentifier: "list-external",
            title: "Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [
          "list-identifier": [
            ReminderItemImportSnapshot(
              identifier: "task-identifier",
              externalIdentifier: "task-external",
              parentExternalIdentifier: nil,
              sourceListIdentifier: "list-identifier",
              sourceListTitle: "Project",
              title: "Task",
              notes: "",
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
              modifiedAt: modifiedAt
            )
          ]
        ]
      ),
      importedAt: importedAt
    )

    XCTAssertEqual(records.projects.first?.projectID, RetainedProjectionBuilder.derivedProjectID(for: "list-external"))
    XCTAssertEqual(records.projects.first?.title, "Project")
    XCTAssertEqual(records.projects.first?.reminderListExternalIdentifier, "list-external")
    XCTAssertEqual(records.tasks.first?.taskID, ReminderProjectionIdentity.taskID(for: "task-external"))
    XCTAssertEqual(records.tasks.first?.ownerProjectID, RetainedProjectionBuilder.derivedProjectID(for: "list-external"))
    XCTAssertEqual(records.tasks.first?.createdAt, createdAt)
    XCTAssertEqual(records.tasks.first?.updatedAt, modifiedAt)
  }

  func testRecordsIncludeFallbackProjectsForOrphanedItemBuckets() {
    let importedAt = Date(timeIntervalSinceReferenceDate: 800)
    let records = AppOwnedReminderBridgeRecordMapper.records(
      from: ReminderImportSnapshotBatch(
        lists: [],
        itemsByListIdentifier: [
          "missing-list": [
            ReminderItemImportSnapshot(
              identifier: "task-identifier",
              externalIdentifier: nil,
              parentExternalIdentifier: nil,
              sourceListIdentifier: "missing-list",
              sourceListTitle: "Fallback",
              title: "Task",
              notes: "",
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
              createdAt: importedAt,
              modifiedAt: importedAt
            )
          ]
        ]
      ),
      importedAt: importedAt
    )

    XCTAssertEqual(records.projects.first?.projectID, RetainedProjectionBuilder.derivedProjectID(for: "missing-list"))
    XCTAssertEqual(records.projects.first?.title, "Fallback")
    XCTAssertEqual(records.tasks.first?.ownerProjectID, RetainedProjectionBuilder.derivedProjectID(for: "missing-list"))
  }
}
