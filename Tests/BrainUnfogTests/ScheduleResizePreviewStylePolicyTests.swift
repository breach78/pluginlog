import XCTest
@testable import BrainUnfog

final class ScheduleResizePreviewStylePolicyTests: XCTestCase {
  func testActiveResizePreviewUsesOpaqueTargetBlock() {
    XCTAssertEqual(ScheduleResizePreviewStylePolicy.targetBlockOpacity, 0.96, accuracy: 0.001)
  }

  func testOriginalBlockIsHiddenWhileResizePreviewIsActive() {
    XCTAssertEqual(
      ScheduleResizePreviewStylePolicy.sourceBlockOpacity(isResizing: true, isDragging: false),
      0,
      accuracy: 0.001
    )
  }
}
