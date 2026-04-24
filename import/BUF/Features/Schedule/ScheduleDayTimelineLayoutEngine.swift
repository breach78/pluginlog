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
            endMinute: segment.startMinute + segment.durationMinutes
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
    var grouped: [Int: [ScheduleEventModel]] = [:]

    for item in items {
      for day in allDayDays(for: item, calendar: calendar) {
        guard let dayIndex = dayIndexByDate[day] else { continue }
        grouped[dayIndex, default: []].append(item)
      }
    }

    var placements: [ScheduleAllDayPlacement] = []
    for dayIndex in grouped.keys.sorted() {
      let sortedItems = grouped[dayIndex, default: []]
        .sorted { lhs, rhs in
          if lhs.isPreparationSlot != rhs.isPreparationSlot {
            return !lhs.isPreparationSlot && rhs.isPreparationSlot
          }
          if lhs.subtitle != rhs.subtitle {
            return (lhs.subtitle ?? "") < (rhs.subtitle ?? "")
          }
          return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

      for (rowIndex, item) in sortedItems.enumerated() {
        placements.append(
          ScheduleAllDayPlacement(
            id: "\(item.id)-all-day-\(dayIndex)",
            itemID: item.id,
            dayIndex: dayIndex,
            rowIndex: rowIndex
          )
        )
      }
    }

    return placements
  }

  private func timedSegments(
    for item: ScheduleEventModel,
    calendar: Calendar,
    metrics: ScheduleDayTimelineLayoutMetrics
  ) -> [(id: String, day: Date, startMinute: Int, durationMinutes: Int)] {
    let boundedEndDate =
      item.endDate > item.startDate
      ? item.endDate
      : calendar.date(
        byAdding: .minute,
        value: metrics.minimumTimedDurationMinutes,
        to: item.startDate
      ) ?? item.startDate

    var result: [(id: String, day: Date, startMinute: Int, durationMinutes: Int)] = []
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
          )
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
}
