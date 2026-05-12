import CoreGraphics
import Foundation
import SwiftUI

enum ScheduleUITokens {
  enum Board {
    static let titleColumnWidth: CGFloat = 76
    static let dayColumnWidth: CGFloat = 168 * 1.7
    static let dateHeaderHeight: CGFloat = 32
    static let allDayRowHeight: CGFloat = 24
    static let allDayRailPadding: CGFloat = 6
    static let allDayRailExtraVisibleHeight: CGFloat = 8
    static let hourHeight: CGFloat = 52
    static let timedBlockInset: CGFloat = 4
    static let timedBlockColumnSpacing: CGFloat = 3
    static let allDayChipHorizontalInset: CGFloat = 5
    static let scheduleDayHeaderOverlayWidth: CGFloat = 260
    static let scheduleDayHeaderShowDelay: TimeInterval = 0.18
    static let scheduleOverlayDetachGraceDelay: TimeInterval = 0.08
    static let scheduleItemFontScale: CGFloat = 1.265
    static let selectionHighlightColor = Color(red: 1.0, green: 0.93, blue: 0.82)
    static let gridLineOpacity = 0.08
    static let minorGridLineOpacity = 0.02
    static let gridLineWidth: CGFloat = 1
    static let allDayAxisBackgroundOpacity = 0.96
    static let timeAxisBackgroundOpacity = 0.98
    static let allDayAxisLabelFontSize: CGFloat = 9
    static let timeAxisLabelFontSize: CGFloat = 10
    static let axisLabelTrailingPadding: CGFloat = 6
    static let timeAxisLabelTopPadding: CGFloat = 2
    static let timeAxisLabelTrailingPadding: CGFloat = 8
    static let currentTimeLineOpacity = 0.78
    static let currentTimeLineHeight: CGFloat = 2
    static let currentTimeChipFontSize: CGFloat = 9
    static let currentTimeChipForegroundOpacity = 0.9
    static let currentTimeChipHorizontalPadding: CGFloat = 4
    static let currentTimeChipVerticalPadding: CGFloat = 1.5
    static let currentTimeChipXOffset: CGFloat = 2
    static let currentTimeChipYOffset: CGFloat = 14
    static let postponeCompactZoneWidth: CGFloat = 24
    static let postponeRegularZoneWidth: CGFloat = 26
    static let postponeCompactButtonSize: CGFloat = 18
    static let postponeRegularButtonSize: CGFloat = 20
    static let postponeCompactIconSize: CGFloat = 9
    static let postponeRegularIconSize: CGFloat = 10
    static let postponeBackgroundOpacity = 0.96
    static let postponeIconXOffset: CGFloat = 0.5
    static let postponeShadowFullOpacity = 0.08
    static let postponeShadowReducedOpacity = 0.04
    static let postponeShadowRadius: CGFloat = 3
    static let postponeShadowYOffset: CGFloat = 1
  }

  enum Month {
    static let dayNumberHeight: CGFloat = 24
    static let dayCellTopPadding: CGFloat = 5
    static let dayCellHorizontalPadding: CGFloat = 6
    static let itemRowHeight: CGFloat = 18
    static let itemRowSpacing: CGFloat = 1
    static let allDaySpanHeight: CGFloat = 18
    static let allDaySpanRowHeight: CGFloat = 20
    static let weekdayHeaderHeight: CGFloat = 28
    static let monthHeaderHeight: CGFloat = 58
    static let cellMinHeight: CGFloat = 72
    static let gridLineOpacity = 0.10
    static let todayBadgeFillOpacity = 0.88
  }

  enum MonthDayPanel {
    static let timeGutterWidth: CGFloat = 64
    static let hourHeight: CGFloat = 56
    static let allDayRowHeight: CGFloat = 30
    static let minimumDurationMinutes = 30
    static let dividerHeight: CGFloat = 1
    static let initialVisibleHour = 18
    static let hiddenIndicatorFontSize: CGFloat = 8.4
    static let hiddenIndicatorOpacity = 0.68
    static let hiddenIndicatorWidth: CGFloat = 18
    static let hiddenIndicatorHeight: CGFloat = 12
    static let timeAxisFontSize: CGFloat = 10
    static let majorGridLineOpacity = 0.45
    static let minorGridLineOpacity = 0.25
    static let currentTimeLineOpacity = 0.78
    static let currentTimeDotOpacity = 0.9
    static let currentTimeLineHeight: CGFloat = 2
    static let currentTimeDotSize: CGFloat = 7
    static let currentTimeDotXOffset: CGFloat = 1
    static let currentTimeDotYOffset: CGFloat = 3.5
    static let dropTargetFillOpacity = 0.18
    static let dropTargetStrokeOpacity = 0.55
  }

  enum Interaction {
    static let dragSourcePlaceholderOpacity = 0.34
    static let dragGhostOpacity = 0.86
    static let dragGhostScale: CGFloat = 1.015
    static let dragGhostShadowRadius: CGFloat = 10
    static let dragGhostShadowYOffset: CGFloat = 4
    static let resizeTargetBlockOpacity = 0.96
  }

  enum ScheduleItem {
    static let titleFontSize: CGFloat = 11.5
    static let supplementalFontSize = titleFontSize * 0.8
    static let secondaryTextOpacityMultiplier = 0.6
  }
}
