import XCTest
@testable import BrainUnfog

final class TimelinePriorityBoundaryPolicyTests: XCTestCase {
  func testShowsBoundaryOnlyBetweenDifferentPriorityStages() {
    XCTAssertTrue(
      TimelinePriorityBoundaryPolicy.shouldShowBoundary(
        sortMode: .priority,
        previousStage: .do,
        currentStage: .decide
      )
    )

    XCTAssertFalse(
      TimelinePriorityBoundaryPolicy.shouldShowBoundary(
        sortMode: .priority,
        previousStage: .area,
        currentStage: .area
      )
    )
  }

  func testDoesNotShowBoundaryOutsidePrioritySort() {
    XCTAssertFalse(
      TimelinePriorityBoundaryPolicy.shouldShowBoundary(
        sortMode: .manual,
        previousStage: .do,
        currentStage: .later
      )
    )
  }
}
