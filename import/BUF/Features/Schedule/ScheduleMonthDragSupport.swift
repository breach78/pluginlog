import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum ScheduleMonthDragItem: Equatable, Sendable {
  case task(UUID)
  case calendarEvent(String)

  var interactionIdentity: ScheduleInteractionItemIdentity {
    switch self {
    case .task(let taskID):
      return .task(taskID)
    case .calendarEvent(let eventID):
      return .calendarEvent(eventID)
    }
  }
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

struct ScheduleMonthDragTargetResolution: Equatable {
  let target: ScheduleInteractionTarget
  let highlightDay: Date?

  static func localMonthTarget(
    originalStartDay: Date,
    startPointerDay: Date,
    currentPointerDay: Date,
    calendar: Calendar
  ) -> ScheduleMonthDragTargetResolution? {
    guard
      let targetDay = ScheduleMonthDragGeometry.movedStartDay(
        originalStartDay: originalStartDay,
        startPointerDay: startPointerDay,
        currentPointerDay: currentPointerDay,
        calendar: calendar
      )
    else {
      return nil
    }
    return ScheduleMonthDragTargetResolution(
      target: .monthDay(targetDay),
      highlightDay: calendar.startOfDay(for: currentPointerDay)
    )
  }

  static func externalMonthTarget(
    targetDay: Date,
    calendar: Calendar
  ) -> ScheduleMonthDragTargetResolution {
    ScheduleMonthDragTargetResolution(
      target: .monthDay(calendar.startOfDay(for: targetDay)),
      highlightDay: nil
    )
  }
}

struct ScheduleMonthDragSessionState: Equatable {
  let startPointerDay: Date?
  let target: ScheduleInteractionTarget
  let highlightDay: Date?

  static func local(
    originalStartDay: Date,
    startPointerDay: Date,
    currentPointerDay: Date,
    calendar: Calendar
  ) -> ScheduleMonthDragSessionState? {
    guard
      let resolution = ScheduleMonthDragTargetResolution.localMonthTarget(
        originalStartDay: originalStartDay,
        startPointerDay: startPointerDay,
        currentPointerDay: currentPointerDay,
        calendar: calendar
      )
    else {
      return nil
    }
    return ScheduleMonthDragSessionState(
      startPointerDay: calendar.startOfDay(for: startPointerDay),
      target: resolution.target,
      highlightDay: resolution.highlightDay
    )
  }

  static func external(
    targetDay: Date,
    calendar: Calendar
  ) -> ScheduleMonthDragSessionState {
    let resolution = ScheduleMonthDragTargetResolution.externalMonthTarget(
      targetDay: targetDay,
      calendar: calendar
    )
    return ScheduleMonthDragSessionState(
      startPointerDay: nil,
      target: resolution.target,
      highlightDay: resolution.highlightDay
    )
  }
}

enum ScheduleScreenPointMapper {
  static func screenPoint(localLocation: CGPoint, in frame: CGRect) -> CGPoint? {
    guard !frame.isNull, frame.width >= 0, frame.height >= 0 else { return nil }
    return CGPoint(
      x: frame.minX + localLocation.x,
      y: frame.maxY - localLocation.y
    )
  }
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

  static func day(
    at point: CGPoint,
    target: ScheduleMonthDropTarget?,
    calendar: Calendar
  ) -> Date? {
    guard let target else { return nil }
    return day(at: point, targets: [target], calendar: calendar)
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

enum ScheduleMonthDetailTargetUpdater {
  static func applyingMovedItem(
    _ item: ScheduleMonthItem,
    to target: ScheduleMonthDetailPanelTarget,
    calendar: Calendar
  ) -> ScheduleMonthDetailPanelTarget {
    let targetDay = calendar.startOfDay(for: target.date)
    var items = target.items.filter { $0.id != item.id }
    if containsItem(item, on: targetDay, calendar: calendar) {
      items.append(item)
    }
    items.sort {
      itemSortKey($0, calendar: calendar) < itemSortKey($1, calendar: calendar)
    }
    return ScheduleMonthDetailPanelTarget(date: target.date, items: items)
  }

  private static func containsItem(
    _ item: ScheduleMonthItem,
    on day: Date,
    calendar: Calendar
  ) -> Bool {
    if item.isAllDay {
      let start = calendar.startOfDay(for: item.startDate)
      let end = calendar.startOfDay(for: item.endDate)
      return start <= day && day < end
    }
    return calendar.isDate(item.startDate, inSameDayAs: day)
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
    guard location.x >= 0, location.x < rowSize.width else { return nil }

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
