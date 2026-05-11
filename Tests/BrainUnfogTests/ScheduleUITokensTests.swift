import XCTest
@testable import BrainUnfog

final class ScheduleUITokensTests: XCTestCase {
  func testBoardTokensKeepExistingScheduleGridDimensions() {
    XCTAssertEqual(ScheduleUITokens.Board.titleColumnWidth, 76)
    XCTAssertEqual(ScheduleUITokens.Board.dayColumnWidth, 168 * 1.7)
    XCTAssertEqual(ScheduleUITokens.Board.dateHeaderHeight, 32)
    XCTAssertEqual(ScheduleUITokens.Board.allDayRowHeight, 24)
    XCTAssertEqual(ScheduleUITokens.Board.hourHeight, 52)
    XCTAssertEqual(ScheduleUITokens.Board.timedBlockInset, 4)
    XCTAssertEqual(ScheduleUITokens.Board.timedBlockColumnSpacing, 3)
    XCTAssertEqual(ScheduleUITokens.Board.allDayChipHorizontalInset, 5)
  }

  func testMonthTokensKeepExistingCalendarLayoutScale() {
    XCTAssertEqual(ScheduleUITokens.Month.dayNumberHeight, 24)
    XCTAssertEqual(ScheduleUITokens.Month.dayCellTopPadding, 5)
    XCTAssertEqual(ScheduleUITokens.Month.itemRowHeight, 18)
    XCTAssertEqual(ScheduleUITokens.Month.allDaySpanRowHeight, 20)
    XCTAssertEqual(ScheduleUITokens.Month.weekdayHeaderHeight, 28)
    XCTAssertEqual(ScheduleUITokens.Month.monthHeaderHeight, 58)
    XCTAssertEqual(ScheduleUITokens.Month.cellMinHeight, 72)
    XCTAssertEqual(ScheduleUITokens.Month.gridLineOpacity, 0.10)
  }

  func testInteractionTokensFeedPreviewPolicies() {
    XCTAssertEqual(ScheduleUITokens.Interaction.dragSourcePlaceholderOpacity, 0.34)
    XCTAssertEqual(ScheduleUITokens.Interaction.dragGhostOpacity, 0.86)
    XCTAssertEqual(ScheduleUITokens.Interaction.dragGhostScale, 1.015)
    XCTAssertEqual(ScheduleUITokens.Interaction.resizeTargetBlockOpacity, 0.96)
    XCTAssertEqual(
      ScheduleResizePreviewStylePolicy.sourceBlockOpacity(isResizing: false, isDragging: true),
      ScheduleUITokens.Interaction.dragSourcePlaceholderOpacity
    )
    XCTAssertEqual(
      ScheduleResizePreviewStylePolicy.targetBlockOpacity,
      ScheduleUITokens.Interaction.resizeTargetBlockOpacity
    )
  }
}
