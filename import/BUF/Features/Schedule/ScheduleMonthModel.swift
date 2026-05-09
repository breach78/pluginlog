import Foundation

enum ScheduleBoardDisplayMode: String, CaseIterable, Identifiable {
  case week
  case month

  var id: String { rawValue }

  var title: String {
    switch self {
    case .week:
      return "주"
    case .month:
      return "월"
    }
  }

  static func resolved(rawValue: String) -> ScheduleBoardDisplayMode {
    ScheduleBoardDisplayMode(rawValue: rawValue) ?? .week
  }
}

enum ScheduleMonthItemSource: Hashable, Sendable {
  case workspaceTask(taskID: UUID, projectID: UUID)
  case calendarEvent(eventID: String)
}

struct ScheduleMonthItem: Identifiable, Hashable, Sendable {
  let id: String
  let source: ScheduleMonthItemSource
  let title: String
  let subtitle: String?
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
  let colorHex: String?
  let isCompleted: Bool
  let isPreparationSlot: Bool
  let isBackgroundCalendar: Bool
  let calendarEvent: ScheduleCalendarEvent?

  var hasExplicitTime: Bool {
    !isAllDay
  }

  var durationMinutes: Int? {
    guard !isAllDay else { return nil }
    let minutes = Int(endDate.timeIntervalSince(startDate) / 60)
    return max(5, minutes)
  }
}

struct ScheduleMonthDetailPanelTarget: Identifiable, Equatable {
  let date: Date
  let items: [ScheduleMonthItem]

  var id: String {
    "\(date.timeIntervalSinceReferenceDate)-\(items.map(\.id).joined(separator: "|"))"
  }
}

struct ScheduleMonthAllDaySpanSegment: Identifiable, Hashable, Sendable {
  let item: ScheduleMonthItem
  let startDayIndex: Int
  let endDayIndex: Int
  let rowIndex: Int
  let startsBeforeWeek: Bool
  let endsAfterWeek: Bool

  var id: String {
    "\(item.id)-\(startDayIndex)-\(endDayIndex)-\(rowIndex)"
  }

  var daySpanCount: Int {
    max(1, endDayIndex - startDayIndex + 1)
  }

  func covers(dayIndex: Int) -> Bool {
    startDayIndex <= dayIndex && dayIndex <= endDayIndex
  }
}

struct ScheduleMonthLayout: Sendable {
  let visibleDays: [Date]
  let itemsByDay: [Date: [ScheduleMonthItem]]
  let weeks: [ScheduleMonthWeekLayout]
}

struct ScheduleMonthWeekLayout: Identifiable, Sendable {
  let weekStart: Date
  let weekDays: [Date]
  let monthStart: Date
  let days: [ScheduleMonthDayLayout]
  let allDaySegments: [ScheduleMonthAllDaySpanSegment]

  var id: Date {
    weekStart
  }
}

struct ScheduleMonthDayLayout: Identifiable, Sendable {
  let day: Date
  let normalizedDay: Date
  let allItems: [ScheduleMonthItem]
  let inlineItems: [ScheduleMonthItem]

  var id: Date {
    normalizedDay
  }
}

enum ScheduleMonthLayoutBuilder {
  static func build(
    containing anchorDate: Date,
    items: [ScheduleMonthItem],
    calendar: Calendar
  ) -> ScheduleMonthLayout {
    let visibleDays = ScheduleMonthContinuousWindow.visibleDays(
      containing: anchorDate,
      calendar: calendar
    )
    let itemsByDay = ScheduleMonthCalendar.itemsByDay(
      items: items,
      visibleDays: visibleDays,
      calendar: calendar
    )
    let weeks = stride(from: 0, to: visibleDays.count, by: 7).map { offset in
      let weekDays = Array(visibleDays[offset..<min(offset + 7, visibleDays.count)])
      let days = weekDays.map { day in
        let normalizedDay = calendar.startOfDay(for: day)
        let allItems = itemsByDay[normalizedDay] ?? []
        return ScheduleMonthDayLayout(
          day: day,
          normalizedDay: normalizedDay,
          allItems: allItems,
          inlineItems: ScheduleMonthSpanLayout.inlineItems(from: allItems)
        )
      }
      let weekItems = uniqueItems(in: days)
      return ScheduleMonthWeekLayout(
        weekStart: weekDays.first ?? calendar.startOfDay(for: anchorDate),
        weekDays: weekDays,
        monthStart: displayMonthStart(for: weekDays, fallback: anchorDate, calendar: calendar),
        days: days,
        allDaySegments: ScheduleMonthSpanLayout.allDayCalendarSegments(
          for: weekDays,
          items: weekItems,
          calendar: calendar
        )
      )
    }

    return ScheduleMonthLayout(
      visibleDays: visibleDays,
      itemsByDay: itemsByDay,
      weeks: weeks
    )
  }

  private static func uniqueItems(in days: [ScheduleMonthDayLayout]) -> [ScheduleMonthItem] {
    var seen: Set<String> = []
    var result: [ScheduleMonthItem] = []
    for day in days {
      for item in day.allItems where seen.insert(item.id).inserted {
        result.append(item)
      }
    }
    return result
  }

  private static func displayMonthStart(
    for weekDays: [Date],
    fallback: Date,
    calendar: Calendar
  ) -> Date {
    let weekStart = weekDays.first ?? fallback
    let middleOfWeek = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
    return ScheduleMonthCalendar.monthStart(containing: middleOfWeek, calendar: calendar)
  }
}

struct ScheduleMonthItemCacheKey: Equatable {
  let taskSignature: Int
  let visibleEventsSignature: Int
  let calendarIdentifier: Calendar.Identifier
  let timeZoneIdentifier: String
}

@MainActor
final class ScheduleMonthItemCache {
  private var cachedKey: ScheduleMonthItemCacheKey?
  private var cachedItems: [ScheduleMonthItem] = []

  static func signature(
    taskSignature: Int,
    visibleEventsSignature: Int,
    calendar: Calendar
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(taskSignature)
    hasher.combine(visibleEventsSignature)
    hasher.combine(calendar.identifier)
    hasher.combine(calendar.timeZone.identifier)
    return hasher.finalize()
  }

  func items(
    taskSnapshot: ScheduleTaskSnapshotCache,
    projection: ScheduleCalendarOverlayProjection,
    calendar: Calendar
  ) -> [ScheduleMonthItem] {
    let key = ScheduleMonthItemCacheKey(
      taskSignature: taskSnapshot.signature,
      visibleEventsSignature: projection.visibleEventsSignature,
      calendarIdentifier: calendar.identifier,
      timeZoneIdentifier: calendar.timeZone.identifier
    )
    if cachedKey == key {
      return cachedItems
    }

    let items = ScheduleMonthItemFactory.items(
      workspaceTasks: taskSnapshot.taskDescriptors,
      foregroundEvents: projection.foregroundEvents,
      backgroundEvents: projection.backgroundEvents,
      calendar: calendar
    )
    cachedKey = key
    cachedItems = items
    return items
  }
}

struct ScheduleMonthLayoutCacheKey: Equatable {
  let visibleRangeLowerBound: Date
  let visibleRangeUpperBound: Date
  let itemsSignature: Int
  let calendarIdentifier: Calendar.Identifier
  let firstWeekday: Int
  let timeZoneIdentifier: String
}

@MainActor
final class ScheduleMonthLayoutCache {
  private var cachedKey: ScheduleMonthLayoutCacheKey?
  private var cachedLayout: ScheduleMonthLayout?

  func layout(
    containing anchorDate: Date,
    items: [ScheduleMonthItem],
    itemsSignature: Int,
    calendar: Calendar
  ) -> ScheduleMonthLayout {
    let visibleRange = ScheduleMonthContinuousWindow.visibleDateRange(
      containing: anchorDate,
      calendar: calendar
    )
    let key = ScheduleMonthLayoutCacheKey(
      visibleRangeLowerBound: visibleRange.lowerBound,
      visibleRangeUpperBound: visibleRange.upperBound,
      itemsSignature: itemsSignature,
      calendarIdentifier: calendar.identifier,
      firstWeekday: calendar.firstWeekday,
      timeZoneIdentifier: calendar.timeZone.identifier
    )
    if cachedKey == key, let cachedLayout {
      return cachedLayout
    }

    let layout = ScheduleMonthLayoutBuilder.build(
      containing: anchorDate,
      items: items,
      calendar: calendar
    )
    cachedKey = key
    cachedLayout = layout
    return layout
  }
}

enum ScheduleMonthSpanLayout {
  static func inlineItems(from items: [ScheduleMonthItem]) -> [ScheduleMonthItem] {
    items
      .filter { !isAllDayCalendarSpanItem($0) }
      .sorted(by: inlineItemSort)
  }

  static func visibleAllDayRowCount(
    on dayIndex: Int,
    segments: [ScheduleMonthAllDaySpanSegment],
    visibleRowLimit: Int
  ) -> Int {
    let maxVisibleRowIndex = segments
      .filter { $0.rowIndex < visibleRowLimit && $0.covers(dayIndex: dayIndex) }
      .map(\.rowIndex)
      .max()

    return maxVisibleRowIndex.map { $0 + 1 } ?? 0
  }

  static func hiddenAllDayItemCount(
    on dayIndex: Int,
    segments: [ScheduleMonthAllDaySpanSegment],
    visibleRowLimit: Int
  ) -> Int {
    segments.filter {
      $0.rowIndex >= visibleRowLimit && $0.covers(dayIndex: dayIndex)
    }.count
  }

  static func allDayCalendarSegments(
    for weekDays: [Date],
    items: [ScheduleMonthItem],
    calendar: Calendar
  ) -> [ScheduleMonthAllDaySpanSegment] {
    guard let firstDay = weekDays.first.map(calendar.startOfDay(for:)),
          let lastDay = weekDays.last.map(calendar.startOfDay(for:)) else {
      return []
    }

    let candidates = items.compactMap { item -> SpanCandidate? in
      guard isAllDayCalendarSpanItem(item) else { return nil }

      let itemStartDay = calendar.startOfDay(for: item.startDate)
      let itemEndDay = calendar.startOfDay(for: ScheduleMonthCalendar.effectiveInclusiveEndDate(for: item))
      guard itemStartDay <= lastDay, itemEndDay >= firstDay else { return nil }

      let segmentStartDay = maxDate(itemStartDay, firstDay)
      let segmentEndDay = minDate(itemEndDay, lastDay)
      let startDayIndex = calendar.dateComponents([.day], from: firstDay, to: segmentStartDay).day ?? 0
      let endDayIndex = calendar.dateComponents([.day], from: firstDay, to: segmentEndDay).day ?? startDayIndex

      return SpanCandidate(
        item: item,
        startDayIndex: max(0, min(6, startDayIndex)),
        endDayIndex: max(0, min(6, endDayIndex)),
        startsBeforeWeek: itemStartDay < firstDay,
        endsAfterWeek: itemEndDay > lastDay
      )
    }
    .sorted { lhs, rhs in
      if lhs.startDayIndex != rhs.startDayIndex {
        return lhs.startDayIndex < rhs.startDayIndex
      }
      if lhs.endDayIndex != rhs.endDayIndex {
        return lhs.endDayIndex > rhs.endDayIndex
      }
      return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
    }

    var rowEndIndexes: [Int] = []
    var segments: [ScheduleMonthAllDaySpanSegment] = []

    for candidate in candidates {
      let rowIndex = rowEndIndexes.firstIndex { $0 < candidate.startDayIndex }
        ?? rowEndIndexes.count

      if rowIndex == rowEndIndexes.count {
        rowEndIndexes.append(candidate.endDayIndex)
      } else {
        rowEndIndexes[rowIndex] = candidate.endDayIndex
      }

      segments.append(
        ScheduleMonthAllDaySpanSegment(
          item: candidate.item,
          startDayIndex: candidate.startDayIndex,
          endDayIndex: candidate.endDayIndex,
          rowIndex: rowIndex,
          startsBeforeWeek: candidate.startsBeforeWeek,
          endsAfterWeek: candidate.endsAfterWeek
        )
      )
    }

    return segments
  }

  private static func isAllDayCalendarSpanItem(_ item: ScheduleMonthItem) -> Bool {
    guard item.isAllDay else { return false }
    if case .calendarEvent = item.source {
      return true
    }
    return false
  }

  private static func inlineItemSort(_ lhs: ScheduleMonthItem, _ rhs: ScheduleMonthItem) -> Bool {
    let lhsPriority = inlineItemPriority(lhs)
    let rhsPriority = inlineItemPriority(rhs)
    if lhsPriority != rhsPriority {
      return lhsPriority < rhsPriority
    }
    if lhs.startDate != rhs.startDate {
      return lhs.startDate < rhs.startDate
    }
    if lhs.isCompleted != rhs.isCompleted {
      return !lhs.isCompleted && rhs.isCompleted
    }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }

  private static func inlineItemPriority(_ item: ScheduleMonthItem) -> Int {
    switch item.source {
    case .calendarEvent:
      return 0
    case .workspaceTask:
      return 1
    }
  }

  private static func minDate(_ lhs: Date, _ rhs: Date) -> Date {
    lhs < rhs ? lhs : rhs
  }

  private static func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
    lhs > rhs ? lhs : rhs
  }

  private struct SpanCandidate {
    let item: ScheduleMonthItem
    let startDayIndex: Int
    let endDayIndex: Int
    let startsBeforeWeek: Bool
    let endsAfterWeek: Bool
  }
}

enum ScheduleMonthCalendar {
  static func monthStart(containing date: Date, calendar: Calendar) -> Date {
    let components = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: components).map(calendar.startOfDay(for:)) ?? calendar.startOfDay(for: date)
  }

  static func visibleDays(containing date: Date, calendar: Calendar) -> [Date] {
    let anchorDay = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: anchorDay)
    let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
    let firstVisibleDay = calendar.date(byAdding: .day, value: -leadingDays, to: anchorDay)
      ?? anchorDay

    return (0..<42).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: firstVisibleDay)
    }
  }

  static func visibleDateRange(containing date: Date, calendar: Calendar) -> ClosedRange<Date> {
    let days = visibleDays(containing: date, calendar: calendar)
    let lower = days.first ?? calendar.startOfDay(for: date)
    let lastDay = days.last ?? lower
    let upper = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
    return lower...upper
  }

  static func itemsByDay(
    items: [ScheduleMonthItem],
    visibleDays: [Date],
    calendar: Calendar
  ) -> [Date: [ScheduleMonthItem]] {
    let visibleDaySet = Set(visibleDays.map { calendar.startOfDay(for: $0) })
    var grouped: [Date: [ScheduleMonthItem]] = [:]

    for item in items {
      let startDay = calendar.startOfDay(for: item.startDate)
      let effectiveEndDate = effectiveInclusiveEndDate(for: item)
      let endDay = calendar.startOfDay(for: effectiveEndDate)
      let dayCount = max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)

      for offset in 0...dayCount {
        guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
        guard visibleDaySet.contains(day) else { continue }
        grouped[day, default: []].append(item)
      }
    }

    return grouped.mapValues { $0.sorted(by: itemSort) }
  }

  static func effectiveInclusiveEndDate(for item: ScheduleMonthItem) -> Date {
    guard item.isAllDay, item.endDate > item.startDate else {
      return max(item.endDate, item.startDate)
    }
    return item.endDate.addingTimeInterval(-1)
  }

  private static func itemSort(_ lhs: ScheduleMonthItem, _ rhs: ScheduleMonthItem) -> Bool {
    if lhs.isAllDay != rhs.isAllDay {
      return lhs.isAllDay && !rhs.isAllDay
    }
    if lhs.startDate != rhs.startDate {
      return lhs.startDate < rhs.startDate
    }
    if lhs.isCompleted != rhs.isCompleted {
      return !lhs.isCompleted && rhs.isCompleted
    }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }
}

enum ScheduleMonthContinuousWindow {
  static let defaultMonthRadius = 3

  static func visibleDays(
    containing date: Date,
    monthRadius: Int = defaultMonthRadius,
    calendar: Calendar
  ) -> [Date] {
    let range = visibleDateRange(containing: date, monthRadius: monthRadius, calendar: calendar)
    var days: [Date] = []
    var current = range.lowerBound

    while current < range.upperBound {
      days.append(current)
      guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
        break
      }
      current = next
    }

    return days
  }

  static func visibleDateRange(
    containing date: Date,
    monthRadius: Int = defaultMonthRadius,
    calendar: Calendar
  ) -> ClosedRange<Date> {
    let lowerAnchor = calendar.date(byAdding: .month, value: -monthRadius, to: date) ?? date
    let upperAnchor = calendar.date(byAdding: .month, value: monthRadius, to: date) ?? date
    let lowerRange = ScheduleMonthCalendar.visibleDateRange(containing: lowerAnchor, calendar: calendar)
    let upperRange = ScheduleMonthCalendar.visibleDateRange(containing: upperAnchor, calendar: calendar)
    return lowerRange.lowerBound...upperRange.upperBound
  }

  static func weekStart(containing date: Date, calendar: Calendar) -> Date {
    ScheduleMonthCalendar.visibleDays(containing: date, calendar: calendar).first
      ?? calendar.startOfDay(for: date)
  }
}

enum ScheduleMonthOverflowPolicy {
  static let titleAndPaddingHeight: CGFloat = 34
  static let rowHeight: CGFloat = 19

  static func visibleItemLimit(cellHeight: CGFloat) -> Int {
    let available = max(0, cellHeight - titleAndPaddingHeight)
    return max(1, Int(floor(available / rowHeight)))
  }
}

enum ScheduleMonthItemFactory {
  static func items(
    workspaceTasks: [WorkspaceScheduleTaskDescriptor],
    foregroundEvents: [ScheduleCalendarEvent],
    backgroundEvents: [ScheduleCalendarEvent],
    calendar: Calendar
  ) -> [ScheduleMonthItem] {
    let taskItems = WorkspaceTaskScheduleEventStore.items(
      from: workspaceTasks,
      calendar: calendar
    )
    .map { item(from: $0, isBackgroundCalendar: false, calendarEvent: nil) }

    let foregroundItems = foregroundEvents.map {
      item(from: $0, isBackgroundCalendar: false)
    }
    let backgroundItems = backgroundEvents.map {
      item(from: $0, isBackgroundCalendar: true)
    }

    return (taskItems + foregroundItems + backgroundItems).sorted { lhs, rhs in
      if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
      return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
  }

  private static func item(
    from model: ScheduleEventModel,
    isBackgroundCalendar: Bool,
    calendarEvent: ScheduleCalendarEvent?
  ) -> ScheduleMonthItem {
    ScheduleMonthItem(
      id: model.id,
      source: model.source.monthItemSource,
      title: model.title,
      subtitle: model.subtitle,
      startDate: model.startDate,
      endDate: model.endDate,
      isAllDay: model.isAllDay,
      colorHex: model.colorHex,
      isCompleted: model.isCompleted,
      isPreparationSlot: model.isPreparationSlot,
      isBackgroundCalendar: isBackgroundCalendar,
      calendarEvent: calendarEvent
    )
  }

  private static func item(
    from event: ScheduleCalendarEvent,
    isBackgroundCalendar: Bool
  ) -> ScheduleMonthItem {
    ScheduleMonthItem(
      id: "calendar-\(event.id)",
      source: .calendarEvent(eventID: event.id),
      title: event.title,
      subtitle: event.calendarTitle,
      startDate: event.startDate,
      endDate: event.endDate,
      isAllDay: event.isAllDay,
      colorHex: event.calendarColorHex,
      isCompleted: false,
      isPreparationSlot: false,
      isBackgroundCalendar: isBackgroundCalendar,
      calendarEvent: event
    )
  }
}

private extension ScheduleEventSource {
  var monthItemSource: ScheduleMonthItemSource {
    switch self {
    case .workspaceTask(let taskID, let projectID):
      return .workspaceTask(taskID: taskID, projectID: projectID)
    case .calendarEvent(let eventID):
      return .calendarEvent(eventID: eventID)
    }
  }
}
