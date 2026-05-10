import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum ScheduleMonthDragItem: Equatable, Sendable {
  case task(UUID)
  case calendarEvent(String)
}

enum ScheduleMonthDragPayload {
  static let type = UTType(exportedAs: "com.brainunfog.schedule-month-item")
  static let typeIdentifier = type.identifier
  static let textTypeIdentifier = UTType.text.identifier
  static let plainTextTypeIdentifier = UTType.plainText.identifier
  static let utf8PlainTextTypeIdentifier = UTType.utf8PlainText.identifier
  static let dropTypeIdentifiers = [
    typeIdentifier,
    utf8PlainTextTypeIdentifier,
    plainTextTypeIdentifier,
    textTypeIdentifier,
  ]
  private static let taskPrefix = "buf-schedule-task:"
  private static let calendarEventPrefix = "buf-schedule-calendar-event:"

  static func payloadString(for item: ScheduleMonthDragItem) -> String {
    switch item {
    case .task(let taskID):
      return "\(taskPrefix)\(taskID.uuidString)"
    case .calendarEvent(let eventID):
      return "\(calendarEventPrefix)\(eventID)"
    }
  }

  static func itemProvider(for item: ScheduleMonthDragItem) -> NSItemProvider {
    let payload = payloadString(for: item)
    let provider = NSItemProvider(object: payload as NSString)
    provider.registerDataRepresentation(
      forTypeIdentifier: typeIdentifier,
      visibility: .all
    ) { completion in
      completion(payload.data(using: .utf8), nil)
      return nil
    }
    return provider
  }

  static func parseItem(from item: NSSecureCoding?) -> ScheduleMonthDragItem? {
    if let data = item as? Data,
      let payload = String(data: data, encoding: .utf8)
    {
      return parseItem(from: payload)
    }
    guard let payload = DragPayloadCodec.decodeTextPayload(from: item) else { return nil }
    return parseItem(from: payload)
  }

  static func parseItem(from payload: String) -> ScheduleMonthDragItem? {
    let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix(taskPrefix) {
      return UUID(uuidString: String(trimmed.dropFirst(taskPrefix.count))).map {
        .task($0)
      }
    }
    if trimmed.hasPrefix(calendarEventPrefix) {
      let eventID = String(trimmed.dropFirst(calendarEventPrefix.count))
      return eventID.isEmpty ? nil : .calendarEvent(eventID)
    }
    return nil
  }
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

struct ScheduleMonthDropTarget: Equatable {
  let day: Date
  let frame: CGRect
}

enum ScheduleMonthDropTargetResolver {
  static func day(
    at point: CGPoint,
    targets: [ScheduleMonthDropTarget],
    calendar: Calendar
  ) -> Date? {
    targets.first { target in
      !target.frame.isNull && target.frame.contains(point)
    }
    .map { calendar.startOfDay(for: $0.day) }
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
