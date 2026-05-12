import CoreGraphics
import Foundation
import SwiftUI

enum ScheduleUITokens {
  enum Typography {
    static let scheduleItemTitleFontSize: CGFloat = 13
    static let scheduleItemSupplementalFontSize: CGFloat = 11
    static let scheduleItemCompactTimeFontSize: CGFloat = 10.5
    static let scheduleItemAccessoryFontSize: CGFloat = 8
    static let panelHeaderTitleFontSize: CGFloat = 22
    static let panelSectionTitleFontSize: CGFloat = 14
    static let panelBodyFontSize: CGFloat = 15
    static let panelStatusFontSize: CGFloat = 13
    static let chromeLabelFontSize: CGFloat = 10
  }

  enum Spacing {
    static let scheduleItemHorizontalPadding: CGFloat = 8
    static let scheduleItemCompactVerticalPadding: CGFloat = 5
    static let scheduleItemStandardVerticalPadding: CGFloat = 6
    static let scheduleItemExpandedVerticalPadding: CGFloat = 7
    static let scheduleItemContentSpacing: CGFloat = 7
    static let panelSectionSpacing: CGFloat = 18
    static let panelFieldSpacing: CGFloat = 8
    static let quickAddContentPadding: CGFloat = 12
  }

  enum Icon {
    static let scheduleItemMarkerSize: CGFloat = 16
    static let scheduleItemCompletedGlyphFontSize: CGFloat = 10
    static let scheduleItemAccessoryFontSize: CGFloat = Typography.scheduleItemAccessoryFontSize
    static let calendarGlyphFontSize: CGFloat = 8
    static let panelCloseIconFontSize: CGFloat = 20
    static let chromeCalendarIconFontSize: CGFloat = 15
    static let chromeChevronFontSize: CGFloat = 9
    static let chromeSwatchSize: CGFloat = 6
  }

  enum Opacity {
    static let completedScheduleItem = 0.45
    static let completedMonthScheduleItem = 0.384
    static let backgroundCalendarScheduleItem = 0.45
    static let backgroundMonthCalendarItem = 0.48
    static let interactingScheduleItem = 0.22
    static let dragPreviewScheduleItem = 0.72
    static let mutedSecondaryText = 0.55
    static let selectedMonthCellBackground = 0.066
    static let todayMonthCellBackground = 0.055
    static let dragTargetMonthCellBackground = 0.09
  }

  enum Shadow {
    static let dragPreviewOpacity = 0.12
    static let dragPreviewRadius: CGFloat = 5
    static let dragPreviewYOffset: CGFloat = 2
    static let liftedGhostOpacity = 0.18
    static let resizePreviewTaskOpacity = 0.12
    static let resizePreviewTaskRadius: CGFloat = 6
    static let resizePreviewEventOpacity = 0.10
    static let resizePreviewEventRadius: CGFloat = 5
  }

  enum EventBlock {
    static let cornerRadius: CGFloat = 6
    static let chipCornerRadius: CGFloat = 10
    static let colorStripeWidth: CGFloat = 3
    static let calendarStripeForegroundOpacity = 0.88
    static let dayPanelCalendarStripeForegroundOpacity = 0.95
    static let backgroundStripeOpacity = 0.50
    static let chipBackgroundStripeOpacity = 0.48
    static let taskFillOpacity = 0.22
    static let completedTaskFillOpacity = 0.14
    static let preparationFillOpacity = 0.20
    static let completedPreparationFillOpacity = 0.14
    static let eventFillOpacity = 0.14
    static let backgroundCalendarFillOpacity = 0.08
  }

  enum Panel {
    static let headerTitleFontSize: CGFloat = Typography.panelHeaderTitleFontSize
    static let closeIconFontSize: CGFloat = Icon.panelCloseIconFontSize
    static let closeButtonSize: CGFloat = 34
    static let sectionTitleFontSize: CGFloat = Typography.panelSectionTitleFontSize
    static let statusFontSize: CGFloat = Typography.panelStatusFontSize
    static let titleFieldFontSize: CGFloat = 24
    static let noteFontSize: CGFloat = 17
    static let bodyFontSize: CGFloat = Typography.panelBodyFontSize
    static let compactControlHeight: CGFloat = 32
    static let compactControlLabelWidth: CGFloat = 34
    static let noteMinHeight: CGFloat = 170
    static let contentHorizontalPadding: CGFloat = 28
    static let contentBottomPadding: CGFloat = 32
    static let quickAddTitleFontSize: CGFloat = 12
    static let quickAddWidth: CGFloat = 260
    static let quickAddTextFieldHeight: CGFloat = 22
    static let quickAddMenuIconFontSize: CGFloat = 10
  }

  enum Chrome {
    static let calendarPickerTitleFontSize: CGFloat = 11
    static let calendarPickerLegendFontSize: CGFloat = 10
    static let calendarPickerLegendIconFontSize: CGFloat = 8
    static let calendarMenuHeight: CGFloat = 24
    static let calendarIconFontSize: CGFloat = Icon.chromeCalendarIconFontSize
    static let calendarChevronFontSize: CGFloat = Icon.chromeChevronFontSize
    static let calendarSwatchSize: CGFloat = Icon.chromeSwatchSize
    static let dayHeaderDayFontSize: CGFloat = 15
    static let dayHeaderMonthFontSize: CGFloat = 8
    static let dayHeaderWeekdayFontSize: CGFloat = 10
    static let dayHeaderBadgeSize: CGFloat = 24
  }

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
    static let scheduleItemFontScale: CGFloat = ScheduleItem.boardFontScale
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
    static let itemRowHeight: CGFloat = MonthCell.itemRowHeight
    static let itemRowSpacing: CGFloat = 1
    static let allDaySpanHeight: CGFloat = 18
    static let allDaySpanRowHeight: CGFloat = 20
    static let weekdayHeaderHeight: CGFloat = 28
    static let monthHeaderHeight: CGFloat = 58
    static let cellMinHeight: CGFloat = 72
    static let gridLineOpacity = 0.10
    static let todayBadgeFillOpacity = 0.88
  }

  enum MonthCell {
    static let dayNumberFontSize: CGFloat = Typography.scheduleItemTitleFontSize
    static let overflowFontSize: CGFloat = Typography.scheduleItemTitleFontSize
    static let allDayIconFontSize: CGFloat = Icon.calendarGlyphFontSize
    static let allDayTitleFontSize: CGFloat = Typography.scheduleItemTitleFontSize
    static let itemTitleFontSize: CGFloat = Typography.scheduleItemTitleFontSize
    static let itemTimeFontSize: CGFloat = Typography.scheduleItemCompactTimeFontSize
    static let itemRowHeight: CGFloat = 18
    static let markerControlWidth: CGFloat = 16
    static let taskMarkerSize: CGFloat = 10
    static let completedTaskIconFontSize: CGFloat = Icon.scheduleItemCompletedGlyphFontSize
    static let allDayCalendarIconFontSize: CGFloat = Icon.calendarGlyphFontSize
    static let calendarStripeWidth: CGFloat = EventBlock.colorStripeWidth
    static let timedCalendarStripeHeight: CGFloat = 14
    static let dragFeedbackSize: CGFloat = 24
    static let dragFeedbackTaskOutlineSize: CGFloat = 12
    static let dragFeedbackTimedCalendarStripeWidth: CGFloat = 4
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
    static let boardFontScale: CGFloat = 1.265
    static let titleFontSize: CGFloat = 11.5
    static let supplementalFontSize: CGFloat = 9.2
    static let monthTitleFontSize: CGFloat = Typography.scheduleItemTitleFontSize
    static let monthSupplementalFontSize: CGFloat = Typography.scheduleItemCompactTimeFontSize
    static let dayPanelTitleFontSize: CGFloat = Typography.scheduleItemTitleFontSize
    static let dayPanelSupplementalFontSize: CGFloat = Typography.scheduleItemSupplementalFontSize
    static let colorStripeWidth: CGFloat = EventBlock.colorStripeWidth
    static let markerSize: CGFloat = Icon.scheduleItemMarkerSize
    static let completedOpacity = Opacity.completedScheduleItem
    static let interactingOpacity = Opacity.interactingScheduleItem
    static let dragPreviewOpacity = Opacity.dragPreviewScheduleItem
    static let secondaryTextOpacityMultiplier = 0.6
  }

  enum DayPanelRow {
    static let allDayRowHeight: CGFloat = 24
    static let markerColumnWidth: CGFloat = 26
    static let taskMarkerSize: CGFloat = Icon.scheduleItemMarkerSize
    static let titleFontSize: CGFloat = ScheduleItem.dayPanelTitleFontSize
    static let supplementalFontSize: CGFloat = ScheduleItem.dayPanelSupplementalFontSize
    static let horizontalPadding: CGFloat = Spacing.scheduleItemHorizontalPadding
    static let verticalPadding: CGFloat = Spacing.scheduleItemExpandedVerticalPadding
    static let colorStripeWidth: CGFloat = EventBlock.colorStripeWidth
    static let openHitAreaTaskWidth: CGFloat = 34
    static let resizeHandleHeight: CGFloat = 10
    static let interactingOpacity = Opacity.interactingScheduleItem
    static let baseMutedOpacity = Opacity.completedScheduleItem
    static let dragPreviewOpacity = Opacity.dragPreviewScheduleItem
  }
}
