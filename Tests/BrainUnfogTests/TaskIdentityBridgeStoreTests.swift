import XCTest
@testable import BrainUnfog

final class TaskIdentityBridgeStoreTests: XCTestCase {
  override func tearDown() {
    TaskIdentityBridgeStore.reset()
    super.tearDown()
  }

  func testReplaceAllMergesDuplicateTaskRecordsWithoutCrashing() {
    let projectID = UUID()
    let taskID = UUID()
    let olderDate = Date(timeIntervalSince1970: 100)
    let newerDate = Date(timeIntervalSince1970: 200)

    TaskIdentityBridgeStore.replaceAll(
      projects: [
        ProjectIdentityBridgeRecord(
          projectID: projectID,
          title: "Project",
          reminderListExternalIdentifier: "list-1",
          createdAt: olderDate,
          updatedAt: olderDate
        ),
      ],
      tasks: [
        TaskIdentityBridgeRecord(
          taskID: taskID,
          title: "Older",
          reminderExternalIdentifier: "reminder-1",
          ownerProjectID: projectID,
          createdAt: olderDate,
          updatedAt: olderDate
        ),
        TaskIdentityBridgeRecord(
          taskID: taskID,
          title: "Newer",
          reminderExternalIdentifier: "reminder-1",
          ownerProjectID: projectID,
          createdAt: newerDate,
          updatedAt: newerDate
        ),
      ]
    )

    let record = TaskIdentityBridgeStore.taskRecord(for: taskID)
    XCTAssertEqual(record?.title, "Newer")
    XCTAssertEqual(record?.createdAt, olderDate)
    XCTAssertEqual(record?.localUpdatedAt, newerDate)
  }

  func testReplaceAllMergesDuplicateProjectRecordsWithoutCrashing() {
    let projectID = UUID()
    let olderDate = Date(timeIntervalSince1970: 100)
    let newerDate = Date(timeIntervalSince1970: 200)

    TaskIdentityBridgeStore.replaceAll(
      projects: [
        ProjectIdentityBridgeRecord(
          projectID: projectID,
          title: "Older",
          reminderListExternalIdentifier: "list-1",
          createdAt: olderDate,
          updatedAt: olderDate
        ),
        ProjectIdentityBridgeRecord(
          projectID: projectID,
          title: "Newer",
          reminderListExternalIdentifier: "list-1",
          createdAt: newerDate,
          updatedAt: newerDate
        ),
      ],
      tasks: []
    )

    let record = TaskIdentityBridgeStore.projectRecords().first
    XCTAssertEqual(record?.title, "Newer")
    XCTAssertEqual(record?.createdAt, olderDate)
    XCTAssertEqual(record?.updatedAt, newerDate)
  }

  func testUpsertAllPreservesExistingRecordsWhileMergingIncomingRecords() {
    let existingProjectID = UUID()
    let incomingProjectID = UUID()
    let existingTaskID = UUID()
    let incomingTaskID = UUID()
    let olderDate = Date(timeIntervalSince1970: 100)
    let newerDate = Date(timeIntervalSince1970: 200)

    TaskIdentityBridgeStore.replaceAll(
      projects: [
        ProjectIdentityBridgeRecord(
          projectID: existingProjectID,
          title: "Existing",
          reminderListExternalIdentifier: "list-existing",
          createdAt: olderDate,
          updatedAt: olderDate
        ),
      ],
      tasks: [
        TaskIdentityBridgeRecord(
          taskID: existingTaskID,
          title: "Existing Task",
          reminderExternalIdentifier: "task-existing",
          ownerProjectID: existingProjectID,
          createdAt: olderDate,
          updatedAt: olderDate
        ),
      ]
    )

    TaskIdentityBridgeStore.upsertAll(
      projects: [
        ProjectIdentityBridgeRecord(
          projectID: incomingProjectID,
          title: "Incoming",
          reminderListExternalIdentifier: "list-incoming",
          createdAt: newerDate,
          updatedAt: newerDate
        ),
      ],
      tasks: [
        TaskIdentityBridgeRecord(
          taskID: incomingTaskID,
          title: "Incoming Task",
          reminderExternalIdentifier: "task-incoming",
          ownerProjectID: incomingProjectID,
          createdAt: newerDate,
          updatedAt: newerDate
        ),
      ]
    )

    XCTAssertEqual(TaskIdentityBridgeStore.projectRecords().count, 2)
    XCTAssertEqual(TaskIdentityBridgeStore.taskRecord(for: existingTaskID)?.title, "Existing Task")
    XCTAssertEqual(TaskIdentityBridgeStore.taskRecord(for: incomingTaskID)?.title, "Incoming Task")
  }
}
