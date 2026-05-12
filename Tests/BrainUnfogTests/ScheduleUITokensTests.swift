import XCTest
@testable import BrainUnfog

final class ScheduleUITokensTests: XCTestCase {
  func testBoardTokensKeepExistingScheduleGridDimensions() {
    XCTAssertEqual(ScheduleUITokens.Board.titleColumnWidth, 76)
    XCTAssertEqual(ScheduleUITokens.Board.dayColumnWidth, 168 * 1.7)
    XCTAssertEqual(ScheduleUITokens.Board.dateHeaderHeight, 32)
    XCTAssertEqual(ScheduleUITokens.Board.allDayRowHeight, 24)
    XCTAssertEqual(ScheduleUITokens.Board.hourHeight, 46.8, accuracy: 0.001)
    XCTAssertEqual(ScheduleUITokens.Board.timedBlockInset, 4)
    XCTAssertEqual(ScheduleUITokens.Board.timedBlockColumnSpacing, 3)
    XCTAssertEqual(ScheduleUITokens.Board.allDayChipHorizontalInset, 5)
  }

  func testWeekAndDayPanelUseSharedTimeScale() {
    XCTAssertEqual(ScheduleUITokens.TimeScale.hourHeight, 46.8, accuracy: 0.001)
    XCTAssertEqual(ScheduleUITokens.Board.hourHeight, ScheduleUITokens.TimeScale.hourHeight)
    XCTAssertEqual(ScheduleUITokens.MonthDayPanel.hourHeight, ScheduleUITokens.TimeScale.hourHeight)
    XCTAssertEqual(
      ScheduleUITokens.MonthDayPanel.timeAxisLabelTopPadding,
      ScheduleUITokens.Board.timeAxisLabelTopPadding
    )
    XCTAssertEqual(
      ScheduleUITokens.MonthDayPanel.timeAxisLabelTrailingPadding,
      ScheduleUITokens.Board.timeAxisLabelTrailingPadding
    )
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

  func testScheduleItemRenderingFilesUseSharedTokensForRepeatedMetrics() throws {
    let forbiddenRawMetrics: [String: [String]] = [
      "import/BUF/Features/Schedule/ScheduleBoardTimedBlocks.swift": [
        ".padding(.horizontal, 8)",
        ".padding(.leading, 10)",
        ".padding(.trailing, 8)",
        "recurrenceIndicator(fontSize: 9.5)",
        "recurrenceIndicator(fontSize: 9)",
        ".secondary.opacity(0.78)",
      ],
      "import/BUF/Features/Schedule/ScheduleEventRenderingLayer.swift": [
        "cornerRadius: 6",
        "cornerRadius: 10",
        ".opacity(0.88)",
        ".frame(width: 3)",
        "color.opacity(0.11)",
        "color.opacity(0.95)",
        "Color.white.opacity(0.5)",
        "Color.white.opacity(0.48)",
      ],
      "import/BUF/Features/Schedule/ScheduleMonthDayCell.swift": [
        ".font(.system(size: 13",
        ".font(.system(size: 10.5",
        ".font(.system(size: 10",
        ".font(.system(size: 8",
        ".frame(width: 16",
        ".frame(width: 10, height: 10)",
        ".frame(width: 3, height: 14)",
        "return 0.384",
        "return 0.48",
        ".secondary.opacity(0.55)",
        "Color.accentColor.opacity(0.09)",
        "Color.accentColor.opacity(0.066)",
        "Color.accentColor.opacity(0.055)",
      ],
      "import/BUF/Features/Schedule/ScheduleMonthDayScheduleRows.swift": [
        ".font(.system(size: 13",
        ".font(.system(size: 11",
        ".font(.system(size: 8",
        ".frame(height: 24)",
        ".frame(width: 26, height: 24)",
        ".frame(width: 3)",
        ".frame(width: 34)",
        ".frame(height: 10)",
        ".frame(width: 16, height: 16)",
        ".frame(width: 18, height: 18)",
        "isInteracting ? 0.22",
        "? 0.45 : 1",
        ".opacity(0.72)",
        "color.opacity(0.18)",
        "color.opacity(0.95)",
      ],
    ]

    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    var failures: [String] = []
    for (relativePath, forbiddenPatterns) in forbiddenRawMetrics {
      let source = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
      for pattern in forbiddenPatterns where source.contains(pattern) {
        failures.append("\(relativePath) still contains \(pattern)")
      }
    }

    XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
  }

  func testPanelChromeAndOverlayFilesUseSharedTokensForRepeatedMetrics() throws {
    let forbiddenRawMetrics: [String: [String]] = [
      "import/BUF/Features/Schedule/ScheduleBoardChrome.swift": [
        ".font(.system(size: 11",
        ".font(.system(size: 10",
        ".font(.system(size: 9",
        ".font(.system(size: 8",
        ".font(.system(size: 15",
        ".frame(height: 24)",
        ".frame(width: 6, height: 6)",
        ".frame(width: 24, height: 24)",
        "windowBackgroundColor).opacity(0.94)",
      ],
      "import/BUF/Features/Schedule/ScheduleBoardChromeRows.swift": [
        ".font(.system(size: 13",
        ".font(.system(size: 9",
        "Color.primary.opacity(0.3)",
        "Color.primary.opacity(0.25)",
        "calendarColor.opacity(0.55)",
      ],
      "import/BUF/Features/Schedule/ScheduleBoardTimedChrome.swift": [
        "color.opacity(0.95)",
        "color.opacity(0.9)",
        "Color.white.opacity(0.84)",
        "0.78 * ScheduleItemVisualStyle.secondaryTextOpacityMultiplier",
        "isBackgroundCalendar ? 0.68 : 1.0",
        "Color.accentColor.opacity(0.08)",
        "Color.primary.opacity(0.02)",
        "Color.accentColor.opacity(0.045)",
        "Color.primary.opacity(0.018)",
      ],
      "import/BUF/Features/Schedule/ScheduleBoardTimedOverlays.swift": [
        ".padding(.top, 6)",
        ".padding(.trailing, 8)",
        "Color.black.opacity(0.18)",
        "color.opacity(0.72)",
        ".font(.system(size: 10",
        "color.opacity(0.92)",
        "windowBackgroundColor).opacity(0.58)",
        "Color.primary.opacity(0.08)",
        "Color.black.opacity(0.12)",
        "Color.black.opacity(0.1)",
        ".font(.system(size: 12",
        ".primary.opacity(0.88)",
        ".font(.system(size: 11",
        ".padding(.horizontal, 10)",
        ".padding(.vertical, 8)",
        "Color.accentColor.opacity(0.14)",
        "Color.accentColor.opacity(0.6)",
      ],
      "import/BUF/Features/Schedule/ScheduleCalendarEventEditPanel.swift": [
        ".font(.system(size: 24",
        ".font(.system(size: 22",
        ".font(.system(size: 20",
        ".font(.system(size: 17",
        ".font(.system(size: 15",
        ".font(.system(size: 14",
        ".font(.system(size: 13",
        ".font(.system(size: 10",
        ".padding(.horizontal, 28)",
        ".padding(.bottom, 32)",
        ".frame(width: 34",
        ".frame(minHeight: 170)",
        ".frame(width: 260",
        ".padding(12)",
        ".frame(width: 284",
        ".frame(height: 32)",
      ],
      "import/BUF/Features/Schedule/ScheduleMonthDetailPanel.swift": [
        ".font(.system(size: 18",
        ".font(.system(size: 13",
        ".font(.system(size: 12",
        ".frame(width: 28",
        ".padding(.horizontal, 18)",
        ".padding(.vertical, 14)",
      ],
      "import/BUF/Features/Schedule/ScheduleQuickAddContextMenu.swift": [
        ".font(.system(size: 12",
        ".font(.system(size: 10",
        ".frame(height: 22)",
        ".padding(.horizontal, 10)",
        ".padding(.vertical, 8)",
        ".padding(12)",
        ".frame(width: 260)",
      ],
    ]

    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    var failures: [String] = []
    for (relativePath, forbiddenPatterns) in forbiddenRawMetrics {
      let source = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
      for pattern in forbiddenPatterns where source.contains(pattern) {
        failures.append("\(relativePath) still contains \(pattern)")
      }
    }

    XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
  }
}
