import XCTest
@testable import BrainUnfogHarness

final class TimelineBoardReadPathTests: XCTestCase {
  func testLoadingStateStopsWhenRetainedReadIsBlocked() {
    let projectID = UUID()

    XCTAssertFalse(
      TimelineBoardReadPath.shouldShowLoadingState(
        projectIDs: [projectID],
        workspaceProjectSnapshots: [:],
        scheduleEntriesByProjectID: [:],
        readBlocker: .partialProjectCoverage(missingProjectIDs: [projectID])
      )
    )
  }

  func testLoadingStateRequiresIncompleteCoverageWithoutBlocker() {
    let projectID = UUID()

    XCTAssertTrue(
      TimelineBoardReadPath.shouldShowLoadingState(
        projectIDs: [projectID],
        workspaceProjectSnapshots: [:],
        scheduleEntriesByProjectID: [:],
        readBlocker: nil
      )
    )
  }

  func testLoadingStateStopsWhenCoverageIsComplete() {
    let projectID = UUID()

    XCTAssertFalse(
      TimelineBoardReadPath.shouldShowLoadingState(
        projectIDs: [projectID],
        workspaceProjectSnapshots: [projectID: makeProject(projectID: projectID)],
        scheduleEntriesByProjectID: [projectID: []],
        readBlocker: nil
      )
    )
  }

  private func makeProject(projectID: UUID) -> WorkspaceProjectRuntimeRecord {
    WorkspaceProjectRuntimeRecord(
      id: projectID,
      title: "Project",
      colorHex: nil,
      reminderListIdentifier: nil,
      reminderListExternalIdentifier: nil,
      projectNoteMarkdown: "",
      localStartDate: nil,
      localDeadline: nil,
      progressStageRaw: nil,
      boardOrder: nil,
      createdAt: .distantPast,
      updatedAt: .distantPast,
      isArchived: false
    )
  }
}
