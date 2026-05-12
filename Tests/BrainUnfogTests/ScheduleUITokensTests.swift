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

  func testCurrentTimeAndGridTokensKeepExistingScheduleScale() {
    XCTAssertEqual(ScheduleUITokens.Board.gridLineOpacity, 0.08)
    XCTAssertEqual(ScheduleUITokens.Board.minorGridLineOpacity, 0.02)
    XCTAssertEqual(ScheduleUITokens.Board.gridLineWidth, 1)
    XCTAssertEqual(ScheduleUITokens.Board.allDayAxisBackgroundOpacity, 0.96)
    XCTAssertEqual(ScheduleUITokens.Board.timeAxisBackgroundOpacity, 0.98)
    XCTAssertEqual(ScheduleUITokens.Board.allDayAxisLabelFontSize, 9)
    XCTAssertEqual(ScheduleUITokens.Board.timeAxisLabelFontSize, 10)
    XCTAssertEqual(ScheduleUITokens.Board.currentTimeLineHeight, 2)
    XCTAssertEqual(ScheduleUITokens.Board.currentTimeChipFontSize, 9)
    XCTAssertEqual(ScheduleUITokens.Board.currentTimeChipHorizontalPadding, 4)
    XCTAssertEqual(ScheduleUITokens.Board.postponeRegularZoneWidth, 26)
    XCTAssertEqual(ScheduleUITokens.MonthDayPanel.currentTimeDotSize, 7)
    XCTAssertEqual(ScheduleUITokens.MonthDayPanel.currentTimeDotYOffset, 3.5)
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

  func testScheduleItemTokensCentralizeSharedRenderingMetrics() {
    XCTAssertEqual(ScheduleUITokens.ScheduleItem.titleFontSize, 11.5)
    XCTAssertEqual(ScheduleUITokens.ScheduleItem.supplementalFontSize, 9.2)
    XCTAssertEqual(ScheduleUITokens.ScheduleItem.boardFontScale, 1.265)
    XCTAssertEqual(
      ScheduleItemVisualStyle.secondaryTextOpacityMultiplier,
      ScheduleUITokens.ScheduleItem.secondaryTextOpacityMultiplier
    )

    XCTAssertEqual(
      ScheduleUITokens.ScheduleItem.monthTitleFontSize,
      ScheduleUITokens.Typography.scheduleItemTitleFontSize
    )
    XCTAssertEqual(
      ScheduleUITokens.ScheduleItem.dayPanelTitleFontSize,
      ScheduleUITokens.Typography.scheduleItemTitleFontSize
    )
    XCTAssertEqual(
      ScheduleUITokens.ScheduleItem.dayPanelSupplementalFontSize,
      ScheduleUITokens.Typography.scheduleItemSupplementalFontSize
    )
    XCTAssertEqual(
      ScheduleUITokens.ScheduleItem.colorStripeWidth,
      ScheduleUITokens.EventBlock.colorStripeWidth
    )
    XCTAssertEqual(
      ScheduleUITokens.ScheduleItem.completedOpacity,
      ScheduleUITokens.Opacity.completedScheduleItem
    )
  }

  func testMonthAndDayPanelRowTokensKeepExistingItemLayoutScale() {
    XCTAssertEqual(ScheduleUITokens.MonthCell.itemRowHeight, ScheduleUITokens.Month.itemRowHeight)
    XCTAssertEqual(ScheduleMonthLayoutMetrics.itemRowHeight, ScheduleUITokens.MonthCell.itemRowHeight)
    XCTAssertEqual(ScheduleUITokens.MonthCell.markerControlWidth, 16)
    XCTAssertEqual(ScheduleUITokens.MonthCell.taskMarkerSize, 10)
    XCTAssertEqual(ScheduleUITokens.MonthCell.calendarStripeWidth, ScheduleUITokens.EventBlock.colorStripeWidth)
    XCTAssertEqual(ScheduleUITokens.MonthCell.timedCalendarStripeHeight, 14)

    XCTAssertEqual(ScheduleUITokens.DayPanelRow.allDayRowHeight, 24)
    XCTAssertEqual(ScheduleUITokens.DayPanelRow.markerColumnWidth, 26)
    XCTAssertEqual(ScheduleUITokens.DayPanelRow.taskMarkerSize, ScheduleUITokens.Icon.scheduleItemMarkerSize)
    XCTAssertEqual(ScheduleUITokens.DayPanelRow.colorStripeWidth, ScheduleUITokens.EventBlock.colorStripeWidth)
    XCTAssertEqual(ScheduleUITokens.DayPanelRow.interactingOpacity, ScheduleUITokens.Opacity.interactingScheduleItem)
  }

  func testPanelAndChromeTokensKeepExistingControlScale() {
    XCTAssertEqual(ScheduleUITokens.Panel.headerTitleFontSize, 22)
    XCTAssertEqual(ScheduleUITokens.Panel.closeButtonSize, 34)
    XCTAssertEqual(ScheduleUITokens.Panel.sectionTitleFontSize, 14)
    XCTAssertEqual(ScheduleUITokens.Panel.compactControlHeight, 32)
    XCTAssertEqual(ScheduleUITokens.Panel.quickAddWidth, 260)
    XCTAssertEqual(ScheduleUITokens.Chrome.calendarMenuHeight, 24)
    XCTAssertEqual(ScheduleUITokens.Chrome.calendarIconFontSize, 15)
    XCTAssertEqual(ScheduleUITokens.Chrome.calendarSwatchSize, 6)
  }
}
