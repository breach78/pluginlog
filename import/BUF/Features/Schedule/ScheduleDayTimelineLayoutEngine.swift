import Foundation

struct ScheduleAllDayPlacement: Identifiable, Hashable {
  let id: String
  let itemID: String
  let dayIndex: Int
  let rowIndex: Int
}

struct ScheduleDayTimelineLayout {
  let timed: [ScheduleTimedPlacement]
  let allDay: [ScheduleAllDayPlacement]
}

struct ScheduleDayTimelineLayoutMetrics {
  let minimumTimedDurationMinutes: Int
}

struct ScheduleDayTimelineLayoutEngine {
  var collisionDetector: any ScheduleCollisionDetecting

  init(collisionDetector: any ScheduleCollisionDetecting = DefaultScheduleCollisionDetector()) {
    self.collisionDetector = collisionDetector
  }

  func makeLayout(
    items: [ScheduleEventModel],
    dayIndexByDate: [Date: Int],
    calendar: Calendar = .autoupdatingCurrent,
    metrics: ScheduleDayTimelineLayoutMetrics
  ) -> ScheduleDayTimelineLayout {
    let allDayItems = items.filter(\.isAllDay)
    let timedItems = items.filter { !$0.isAllDay }

    return ScheduleDayTimelineLayout(
      timed: collisionDetector.place(
        timedCandidates(
          for: timedItems,
          dayIndexByDate: dayIndexByDate,
          calendar: calendar,
          metrics: metrics
        )
      ),
      allDay: allDayPlacements(
        for: allDayItems,
        dayIndexByDate: dayIndexByDate,
        calendar: calendar
      )
    )
  }

  private func timedCandidates(
    for items: [ScheduleEventModel],
    dayIndexByDate: [Date: Int],
    calendar: Calendar,
    metrics: ScheduleDayTimelineLayoutMetrics
  ) -> [ScheduleTimedPlacementCandidate] {
    var candidates: [ScheduleTimedPlacementCandidate] = []

    for item in items {
      for segment in timedSegments(
        for: item,
        calendar: calendar,
        metrics: metrics
      ) {
        guard let dayIndex = dayIndexByDate[segment.day] else { continue }
        candidates.append(
          ScheduleTimedPlacementCandidate(
            id: segment.id,
            itemID: item.id,
            dayIndex: dayIndex,
            startMinute: segment.startMinute,
            durationMinutes: segment.durationMinutes,
            endMinute: segment.startMinute + segment.durationMinutes,
            sourceStartDay: segment.sourceStartDay,
            sourceStartMinute: segment.sourceStartMinute,
            sourceDurationMinutes: segment.sourceDurationMinutes,
            isFirstSegment: segment.isFirstSegment,
            isLastSegment: segment.isLastSegment
          )
        )
      }
    }

    return candidates
  }

  private func allDayPlacements(
    for items: [ScheduleEventModel],
    dayIndexByDate: [Date: Int],
    calendar: Calendar
  ) -> [ScheduleAllDayPlacement] {
    var placements: [ScheduleAllDayPlacement] = []
    var occupiedRowsByDay: [Int: Set<Int>] = [:]
    let spans = allDaySpans(for: items, dayIndexByDate: dayIndexByDate, calendar: calendar)

    for span in spans.filter(\.isMultiDay).sorted(by: allDayMultiDaySpanSort) {
      let rowIndex = firstAvailableAllDayRow(
        for: span.dayIndices,
        occupiedRowsByDay: occupiedRowsByDay
      )
      reserveAllDayRow(rowIndex, for: span.dayIndices, occupiedRowsByDay: &occupiedRowsByDay)
      appendPlacements(for: span, rowIndex: rowIndex, to: &placements)
    }

    let singleDaySpansByDay = Dictionary(grouping: spans.filter { !$0.isMultiDay }) {
      $0.dayIndices[0]
    }
    for dayIndex in singleDaySpansByDay.keys.sorted() {
      for span in singleDaySpansByDay[dayIndex, default: []].sorted(by: allDaySpanSort) {
        let rowIndex = firstAvailableAllDayRow(
          for: span.dayIndices,
          occupiedRowsByDay: occupiedRowsByDay
        )
        reserveAllDayRow(rowIndex, for: span.dayIndices, occupiedRowsByDay: &occupiedRowsByDay)
        appendPlacements(for: span, rowIndex: rowIndex, to: &placements)
      }
    }

    return placements.sorted {
      if $0.dayIndex != $1.dayIndex {
        return $0.dayIndex < $1.dayIndex
      }
      if $0.rowIndex != $1.rowIndex {
        return $0.rowIndex < $1.rowIndex
      }
      return $0.itemID < $1.itemID
    }
  }

  private func timedSegments(
    for item: ScheduleEventModel,
    calendar: Calendar,
    metrics: ScheduleDayTimelineLayoutMetrics
  ) -> [
    (
      id: String,
      day: Date,
      startMinute: Int,
      durationMinutes: Int,
      sourceStartDay: Date,
      sourceStartMinute: Int,
      sourceDurationMinutes: Int,
      isFirstSegment: Bool,
      isLastSegment: Bool
    )
  ] {
    let boundedEndDate =
      item.endDate > item.startDate
      ? item.endDate
      : calendar.date(
        byAdding: .minute,
        value: metrics.minimumTimedDurationMinutes,
        to: item.startDate
      ) ?? item.startDate

    let sourceStartDay = calendar.startOfDay(for: item.startDate)
    let sourceComponents = calendar.dateComponents([.hour, .minute], from: item.startDate)
    let sourceStartMinute = (sourceComponents.hour ?? 0) * 60 + (sourceComponents.minute ?? 0)
    let sourceDurationMinutes = max(
      metrics.minimumTimedDurationMinutes,
      Int(boundedEndDate.timeIntervalSince(item.startDate) / 60)
    )

    var result: [
      (
        id: String,
        day: Date,
        startMinute: Int,
        durationMinutes: Int,
        sourceStartDay: Date,
        sourceStartMinute: Int,
        sourceDurationMinutes: Int,
        isFirstSegment: Bool,
        isLastSegment: Bool
      )
    ] = []
    var cursor = item.startDate
    var segmentIndex = 0

    while cursor < boundedEndDate {
      let day = calendar.startOfDay(for: cursor)
      guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      let segmentEnd = min(nextDay, boundedEndDate)
      let components = calendar.dateComponents([.hour, .minute], from: cursor)
      let startMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
      let rawDuration = Int(segmentEnd.timeIntervalSince(cursor) / 60)
      let durationMinutes = max(metrics.minimumTimedDurationMinutes, rawDuration)

      result.append(
        (
          id: "\(item.id)-segment-\(segmentIndex)",
          day: day,
          startMinute: min(startMinute, 23 * 60 + 45),
          durationMinutes: min(
            durationMinutes,
            max(metrics.minimumTimedDurationMinutes, (24 * 60) - startMinute)
          ),
          sourceStartDay: sourceStartDay,
          sourceStartMinute: sourceStartMinute,
          sourceDurationMinutes: sourceDurationMinutes,
          isFirstSegment: segmentIndex == 0,
          isLastSegment: segmentEnd >= boundedEndDate
        )
      )

      cursor = segmentEnd
      segmentIndex += 1
    }

    return result
  }

  private func allDayDays(for item: ScheduleEventModel, calendar: Calendar) -> [Date] {
    let startDay = calendar.startOfDay(for: item.startDate)
    let exclusiveEndDay = calendar.startOfDay(for: item.endDate)
    let resolvedEndDay =
      exclusiveEndDay > startDay
      ? exclusiveEndDay
      : calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay

    var result: [Date] = []
    var cursor = startDay

    while cursor < resolvedEndDay {
      result.append(cursor)
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }

    return result
  }

  private struct AllDaySpan {
    let item: ScheduleEventModel
    let dayIndices: [Int]
    let isMultiDay: Bool
  }

  private func allDaySpans(
    for items: [ScheduleEventModel],
    dayIndexByDate: [Date: Int],
    calendar: Calendar
  ) -> [AllDaySpan] {
    items.compactMap { item in
      let allDays = allDayDays(for: item, calendar: calendar)
      let visibleDayIndices = Set(allDays.compactMap { dayIndexByDate[$0] }).sorted()
      guard !visibleDayIndices.isEmpty else { return nil }
      return AllDaySpan(
        item: item,
        dayIndices: visibleDayIndices,
        isMultiDay: allDays.count > 1
      )
    }
  }

  private func allDayMultiDaySpanSort(_ lhs: AllDaySpan, _ rhs: AllDaySpan) -> Bool {
    if lhs.item.startDate != rhs.item.startDate {
      return lhs.item.startDate < rhs.item.startDate
    }
    if lhs.dayIndices.count != rhs.dayIndices.count {
      return lhs.dayIndices.count > rhs.dayIndices.count
    }
    return allDaySpanSort(lhs, rhs)
  }

  private func allDaySpanSort(_ lhs: AllDaySpan, _ rhs: AllDaySpan) -> Bool {
    if lhs.item.isPreparationSlot != rhs.item.isPreparationSlot {
      return !lhs.item.isPreparationSlot && rhs.item.isPreparationSlot
    }
    if lhs.item.subtitle != rhs.item.subtitle {
      return (lhs.item.subtitle ?? "") < (rhs.item.subtitle ?? "")
    }
    return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
  }

  private func firstAvailableAllDayRow(
    for dayIndices: [Int],
    occupiedRowsByDay: [Int: Set<Int>]
  ) -> Int {
    var rowIndex = 0
    while dayIndices.contains(where: { occupiedRowsByDay[$0]?.contains(rowIndex) == true }) {
      rowIndex += 1
    }
    return rowIndex
  }

  private func reserveAllDayRow(
    _ rowIndex: Int,
    for dayIndices: [Int],
    occupiedRowsByDay: inout [Int: Set<Int>]
  ) {
    for dayIndex in dayIndices {
      occupiedRowsByDay[dayIndex, default: []].insert(rowIndex)
    }
  }

  private func appendPlacements(
    for span: AllDaySpan,
    rowIndex: Int,
    to placements: inout [ScheduleAllDayPlacement]
  ) {
    for dayIndex in span.dayIndices {
      placements.append(
        ScheduleAllDayPlacement(
          id: "\(span.item.id)-all-day-\(dayIndex)",
          itemID: span.item.id,
          dayIndex: dayIndex,
          rowIndex: rowIndex
        )
      )
    }
  }
}
