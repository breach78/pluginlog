import CoreGraphics
import Foundation

enum ScheduleMonthDragItem: Equatable, Sendable {
  case task(UUID)
  case calendarEvent(String)
}

struct ScheduleMonthDragFeedback: Equatable {
  let source: ScheduleMonthItemSource
  let colorHex: String?
  let isCompleted: Bool
  let isAllDay: Bool
  let weekStart: Date
  let location: CGPoint

  init(item: ScheduleMonthItem, weekStart: Date, location: CGPoint) {
    source = item.source
    colorHex = item.colorHex
    isCompleted = item.isCompleted
    isAllDay = item.isAllDay
    self.weekStart = weekStart
    self.location = location
  }
}

enum ScheduleMonthDragSupport {
  static func dragItem(for item: ScheduleMonthItem) -> ScheduleMonthDragItem? {
    guard !item.isPreparationSlot else { return nil }
    switch item.source {
    case .workspaceTask(let taskID, _):
      return .task(taskID)
    case .calendarEvent(let eventID):
      guard item.calendarEvent?.canEditTiming == true else { return nil }
      return .calendarEvent(eventID)
    }
  }
}

enum ScheduleMonthDragGeometry {
  static func day(
    at location: CGPoint,
    weekStart: Date,
    rowSize: CGSize,
    calendar: Calendar
  ) -> Date? {
    let daysPerWeek = 7
    guard rowSize.width > 0, rowSize.height > 0 else { return nil }
    let columnWidth = rowSize.width / CGFloat(daysPerWeek)
    guard columnWidth > 0 else { return nil }

    let rawColumn = Int(floor(location.x / columnWidth))
    let column = min(daysPerWeek - 1, max(0, rawColumn))
    let rowDelta = Int(floor(location.y / rowSize.height))
    let dayOffset = rowDelta * daysPerWeek + column
    return calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
      .map(calendar.startOfDay(for:))
  }

  static func movedStartDay(
    originalStartDay: Date,
    startPointerDay: Date,
    currentPointerDay: Date,
    calendar: Calendar
  ) -> Date? {
    let dayDelta = calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: startPointerDay),
      to: calendar.startOfDay(for: currentPointerDay)
    ).day ?? 0
    return calendar.date(byAdding: .day, value: dayDelta, to: calendar.startOfDay(for: originalStartDay))
      .map(calendar.startOfDay(for:))
  }
}
