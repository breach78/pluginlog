import XCTest
@testable import BrainUnfog

@MainActor
final class RemindersAppOpenServiceTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    TaskIdentityBridgeStore.reset()
  }

  override func tearDown() async throws {
    TaskIdentityBridgeStore.reset()
    try await super.tearDown()
  }

  func testOpenProjectListUsesReminderListIdentifierFromBridge() async throws {
    let projectID = UUID()
    let executor = RecordingRemindersAppScriptExecutor()
    let preparer = RecordingRemindersAppPreparer()
    TaskIdentityBridgeStore.upsertProject(
      projectID: projectID,
      title: "Project",
      reminderListExternalIdentifier: "LIST-1"
    )

    try await RemindersAppOpenService.openProjectList(
      projectID: projectID,
      scriptExecutor: executor,
      appPreparer: preparer
    )

    XCTAssertEqual(preparer.prepareCount, 1)
    XCTAssertEqual(executor.sources.count, 1)
    XCTAssertTrue(executor.sources[0].contains("tell application id \"com.apple.reminders\""))
    XCTAssertTrue(executor.sources[0].contains("show list id \"LIST-1\""))
  }

  func testOpenProjectListPrefersRuntimeIdentifier() async throws {
    let projectID = UUID()
    let executor = RecordingRemindersAppScriptExecutor()
    let preparer = RecordingRemindersAppPreparer()
    TaskIdentityBridgeStore.upsertProject(
      projectID: projectID,
      title: "Project",
      reminderListExternalIdentifier: "STALE-LIST"
    )

    try await RemindersAppOpenService.openProjectList(
      projectID: projectID,
      listExternalIdentifier: "LIVE-LIST",
      scriptExecutor: executor,
      appPreparer: preparer
    )

    XCTAssertTrue(executor.sources[0].contains("show list id \"LIVE-LIST\""))
    XCTAssertFalse(executor.sources[0].contains("STALE-LIST"))
  }

  func testOpenTaskUsesReminderURLIdentifier() async throws {
    let projectID = UUID()
    let taskID = UUID()
    let executor = RecordingRemindersAppScriptExecutor()
    let preparer = RecordingRemindersAppPreparer()
    TaskIdentityBridgeStore.upsertTask(
      taskID: taskID,
      title: "Task",
      reminderExternalIdentifier: "TASK-1",
      ownerProjectID: projectID
    )

    try await RemindersAppOpenService.openTask(
      taskID: taskID,
      scriptExecutor: executor,
      appPreparer: preparer
    )

    XCTAssertEqual(preparer.prepareCount, 1)
    XCTAssertEqual(executor.sources.count, 1)
    XCTAssertTrue(
      executor.sources[0].contains("show reminder id \"x-apple-reminder://TASK-1\"")
    )
  }

  func testOpenTaskDoesNotDoublePrefixReminderURLIdentifier() async throws {
    let projectID = UUID()
    let taskID = UUID()
    let executor = RecordingRemindersAppScriptExecutor()
    let preparer = RecordingRemindersAppPreparer()
    TaskIdentityBridgeStore.upsertTask(
      taskID: taskID,
      title: "Task",
      reminderExternalIdentifier: "x-apple-reminder://TASK-1",
      ownerProjectID: projectID
    )

    try await RemindersAppOpenService.openTask(
      taskID: taskID,
      scriptExecutor: executor,
      appPreparer: preparer
    )

    XCTAssertTrue(
      executor.sources[0].contains("show reminder id \"x-apple-reminder://TASK-1\"")
    )
    XCTAssertFalse(executor.sources[0].contains("x-apple-reminder://x-apple-reminder://"))
  }

  func testOpenTaskRetriesOnceWhenRemindersReportsNotRunning() async throws {
    let projectID = UUID()
    let taskID = UUID()
    let executor = RecordingRemindersAppScriptExecutor()
    executor.errorsToThrow = [
      RemindersAppOpenServiceError.scriptFailed("Reminders got an error: Application isn't running.")
    ]
    let preparer = RecordingRemindersAppPreparer()
    TaskIdentityBridgeStore.upsertTask(
      taskID: taskID,
      title: "Task",
      reminderExternalIdentifier: "TASK-1",
      ownerProjectID: projectID
    )

    try await RemindersAppOpenService.openTask(
      taskID: taskID,
      scriptExecutor: executor,
      appPreparer: preparer
    )

    XCTAssertEqual(preparer.prepareCount, 2)
    XCTAssertEqual(executor.sources.count, 2)
  }

  func testOpenTaskFailsWithoutReminderBinding() async {
    let taskID = UUID()
    let executor = RecordingRemindersAppScriptExecutor()
    let preparer = RecordingRemindersAppPreparer()

    do {
      try await RemindersAppOpenService.openTask(
        taskID: taskID,
        scriptExecutor: executor,
        appPreparer: preparer
      )
      XCTFail("Expected missing reminder binding to fail.")
    } catch {
      XCTAssertEqual(error as? RemindersAppOpenServiceError, .taskReminderNotFound(taskID))
    }
    XCTAssertEqual(preparer.prepareCount, 0)
    XCTAssertTrue(executor.sources.isEmpty)
  }
}

@MainActor
private final class RecordingRemindersAppScriptExecutor: RemindersAppScriptExecuting {
  var sources: [String] = []
  var errorsToThrow: [Error] = []

  func execute(_ source: String) throws {
    sources.append(source)
    if !errorsToThrow.isEmpty {
      throw errorsToThrow.removeFirst()
    }
  }
}

@MainActor
private final class RecordingRemindersAppPreparer: RemindersAppPreparing {
  var prepareCount = 0

  func prepareRemindersApp() async throws {
    prepareCount += 1
  }
}
