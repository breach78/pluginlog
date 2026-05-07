import XCTest
@testable import BrainUnfog

final class ScheduleBackgroundLabelAvoidancePolicyTests: XCTestCase {
  func testBackgroundLabelMovesBelowOverlappingForegroundBlock() {
    let background = ScheduleBackgroundLabelAvoidanceBlock(
      dayIndex: 0,
      startMinute: 9 * 60,
      endMinute: 17 * 60
    )
    let foreground = ScheduleBackgroundLabelAvoidanceBlock(
      dayIndex: 0,
      startMinute: 9 * 60,
      endMinute: 10 * 60
    )

    let offset = ScheduleBackgroundLabelAvoidancePolicy.topOffset(
      for: background,
      foregroundBlocks: [foreground],
      hourHeight: 80,
      labelHeight: 36,
      gap: 4
    )

    XCTAssertGreaterThan(offset, 80)
  }

  func testBackgroundLabelStaysAtTopWhenForegroundDoesNotOverlap() {
    let background = ScheduleBackgroundLabelAvoidanceBlock(
      dayIndex: 0,
      startMinute: 9 * 60,
      endMinute: 17 * 60
    )
    let foreground = ScheduleBackgroundLabelAvoidanceBlock(
      dayIndex: 0,
      startMinute: 18 * 60,
      endMinute: 19 * 60
    )

    let offset = ScheduleBackgroundLabelAvoidancePolicy.topOffset(
      for: background,
      foregroundBlocks: [foreground],
      hourHeight: 80,
      labelHeight: 36,
      gap: 4
    )

    XCTAssertEqual(offset, 0, accuracy: 0.001)
  }
}
