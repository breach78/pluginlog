import AppKit
import SwiftUI

extension ScheduleMonthDaySchedulePanel {
  func createPreview(
    from startLocation: CGPoint,
    to endLocation: CGPoint
  ) -> ScheduleMonthDayScheduleCreatePreview {
    let start = snappedTimeMinutes(forY: startLocation.y)
    let end = snappedTimeMinutes(forY: endLocation.y)
    let lower = min(start, end)
    let upper = max(start, end)
    let duration = max(Self.minimumDurationMinutes, upper - lower)
    let clampedStart = Self.clampedTimeMinute(lower, durationMinutes: duration)
    return ScheduleMonthDayScheduleCreatePreview(
      timeMinutes: clampedStart,
      durationMinutes: min(duration, (24 * 60) - clampedStart)
    )
  }

  func startMinute(for item: ScheduleMonthItem) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: item.startDate)
    return min(23 * 60 + 45, max(0, (components.hour ?? 0) * 60 + (components.minute ?? 0)))
  }

  func durationMinutes(for item: ScheduleMonthItem) -> Int {
    max(Self.minimumDurationMinutes, item.durationMinutes ?? Self.minimumDurationMinutes)
  }

  func snappedTimeMinutes(forY y: CGFloat) -> Int {
    ScheduleMonthDayInteractionAdapter.snappedTimeMinutes(for: y, metrics: interactionMetrics)
  }

  func y(forMinute minute: Int) -> CGFloat {
    CGFloat(minute) / 60 * Self.hourHeight
  }

  func height(forDuration duration: Int) -> CGFloat {
    max(28, CGFloat(duration) / 60 * Self.hourHeight)
  }

  func itemColor(_ item: ScheduleMonthItem) -> Color {
    ColorHexCodec.color(from: item.colorHex) ?? .accentColor
  }

  func canUpdateSchedule(for item: ScheduleMonthItem) -> Bool {
    guard !item.isBackgroundCalendar else { return false }
    switch item.source {
    case .workspaceTask:
      return true
    case .calendarEvent:
      return item.calendarEvent?.canEditTiming == true
    }
  }

  func canResizeSchedule(for item: ScheduleMonthItem) -> Bool {
    guard canUpdateSchedule(for: item), !item.isAllDay else { return false }
    switch item.source {
    case .workspaceTask:
      return true
    case .calendarEvent:
      return item.calendarEvent?.canEditTiming == true
    }
  }

  var interactionMetrics: ScheduleInteractionMetrics {
    ScheduleMonthDayInteractionAdapter.metrics(
      hourHeight: Self.hourHeight,
      minimumDurationMinutes: Self.minimumDurationMinutes
    )
  }

  static func sortedItems(
    _ items: [ScheduleMonthItem],
    calendar: Calendar
  ) -> [ScheduleMonthItem] {
    items.sorted { itemSortKey($0, calendar: calendar) < itemSortKey($1, calendar: calendar) }
  }

  static func clampedTimeMinute(_ minute: Int, durationMinutes: Int) -> Int {
    let latestStart = max(0, (24 * 60) - durationMinutes)
    return min(latestStart, max(0, minute))
  }

  static func timeLabel(hour: Int) -> String {
    if hour == 0 { return "오전 12" }
    if hour < 12 { return "오전 \(hour)" }
    if hour == 12 { return "오후 12" }
    return "오후 \(hour - 12)"
  }

  static let timeGutterWidth: CGFloat = ScheduleUITokens.MonthDayPanel.timeGutterWidth
  static let hourHeight: CGFloat = ScheduleUITokens.MonthDayPanel.hourHeight
  static let allDayRowHeight: CGFloat = ScheduleUITokens.MonthDayPanel.allDayRowHeight
  static let minimumDurationMinutes = ScheduleUITokens.MonthDayPanel.minimumDurationMinutes
  static let dividerHeight: CGFloat = ScheduleUITokens.MonthDayPanel.dividerHeight
  static let initialVisibleHour = ScheduleUITokens.MonthDayPanel.initialVisibleHour
  static let topScrollID = "schedule-month-detail-time-top"
  static let bottomScrollID = "schedule-month-detail-time-bottom"
  static let nightScrollID = "schedule-month-detail-time-night"
  static let panelCoordinateSpaceName = "schedule-month-detail-panel"
  static var quarterHourHeight: CGFloat { hourHeight / 4 }
  static var timeGridHeight: CGFloat { hourHeight * 24 }

  static func timeScrollID(forQuarter quarter: Int) -> String {
    "schedule-month-detail-time-quarter-\(quarter)"
  }
}
