import XCTest
@testable import BrainUnfog

final class RetainedTaskCommandErrorPolicyTests: XCTestCase {
  func testMatchesTaskNotFoundForSameTask() {
    let taskID = UUID()

    XCTAssertTrue(
      RetainedTaskCommandErrorPolicy.isTaskNotFound(
        RetainedTaskCommandError.taskNotFound(taskID),
        taskID: taskID
      )
    )
  }

  func testIgnoresTaskNotFoundForDifferentTask() {
    XCTAssertFalse(
      RetainedTaskCommandErrorPolicy.isTaskNotFound(
        RetainedTaskCommandError.taskNotFound(UUID()),
        taskID: UUID()
      )
    )
  }
}
