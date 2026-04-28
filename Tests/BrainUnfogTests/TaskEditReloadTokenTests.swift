import XCTest
@testable import BrainUnfog

final class TaskEditReloadTokenTests: XCTestCase {
  func testWorkspaceTaskEditReloadTokenChangesWithWorkspaceRevision() {
    let projectID = UUID(uuidString: "00000000-0000-5000-8000-000000000001")!
    let taskID = UUID(uuidString: "00000000-0000-5000-8000-000000000002")!

    let before = TaskEditReloadToken.workspacePanel(
      projectID: projectID,
      taskID: taskID,
      workspaceTreeRevision: 10
    )
    let after = TaskEditReloadToken.workspacePanel(
      projectID: projectID,
      taskID: taskID,
      workspaceTreeRevision: 11
    )

    XCTAssertNotEqual(before, after)
  }

  func testWorkspaceTaskEditReloadTokenIncludesTaskIdentity() {
    let projectID = UUID(uuidString: "00000000-0000-5000-8000-000000000001")!
    let firstTaskID = UUID(uuidString: "00000000-0000-5000-8000-000000000002")!
    let secondTaskID = UUID(uuidString: "00000000-0000-5000-8000-000000000003")!

    let first = TaskEditReloadToken.workspacePanel(
      projectID: projectID,
      taskID: firstTaskID,
      workspaceTreeRevision: 10
    )
    let second = TaskEditReloadToken.workspacePanel(
      projectID: projectID,
      taskID: secondTaskID,
      workspaceTreeRevision: 10
    )

    XCTAssertNotEqual(first, second)
  }
}
