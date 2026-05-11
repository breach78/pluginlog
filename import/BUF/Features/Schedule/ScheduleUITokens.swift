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
