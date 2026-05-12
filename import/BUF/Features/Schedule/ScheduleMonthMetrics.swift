import SwiftUI

enum ScheduleMonthLayoutMetrics {
  static let dayNumberHeight: CGFloat = ScheduleUITokens.Month.dayNumberHeight
  static let dayCellTopPadding: CGFloat = ScheduleUITokens.Month.dayCellTopPadding
  static let dayCellHorizontalPadding: CGFloat = ScheduleUITokens.Month.dayCellHorizontalPadding
  static let itemRowHeight: CGFloat = ScheduleUITokens.Month.itemRowHeight
  static let itemRowSpacing: CGFloat = ScheduleUITokens.Month.itemRowSpacing
  static let allDaySpanHeight: CGFloat = ScheduleUITokens.Month.allDaySpanHeight
  static let allDaySpanRowHeight: CGFloat = ScheduleUITokens.Month.allDaySpanRowHeight
  static let allDaySpanTopOffset: CGFloat = dayCellTopPadding + dayNumberHeight + itemRowSpacing
}
