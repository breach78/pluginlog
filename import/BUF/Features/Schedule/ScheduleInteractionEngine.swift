import CoreGraphics
import Foundation

enum ScheduleInteractionSurfaceKind: Equatable, Sendable {
  case week
  case month
  case dayPanel
}

enum ScheduleInteractionItemIdentity: Equatable, Sendable {
  case task(UUID)
  case calendarEvent(String)
}

enum ScheduleInteractionTarget: Equatable, Sendable {
  case allDay(Date)
  case timed(day: Date, minute: Int)
  case monthDay(Date)
  case outside
  case invalid
}

enum ScheduleInteractionCommand: Equatable, Sendable {
  case moveTask(taskID: UUID, day: Date?, timeMinutes: Int?, durationMinutes: Int?)
  case resizeTask(taskID: UUID, day: Date, timeMinutes: Int, durationMinutes: Int)
  case moveCalendarEvent(eventID: String, day: Date, timeMinutes: Int?, durationMinutes: Int?)
  case resizeCalendarEvent(eventID: String, day: Date, timeMinutes: Int, durationMinutes: Int)
}

enum ScheduleInteractionEngine {
  static func timedTarget(
    visibleDay: Date,
    scheduleY: CGFloat,
    metrics: ScheduleInteractionMetrics,
    calendar: Calendar
  ) -> ScheduleInteractionTarget {
    let relativeMinute = snappedRelativeMinutes(for: scheduleY, metrics: metrics)
    let resolved = resolvedDateAndMinute(
      relativeMinute: relativeMinute,
      visibleDay: visibleDay,
      calendar: calendar
    )
    return .timed(day: resolved.day, minute: resolved.timeMinutes)
  }

  static func movePreview(
    originalTimeMinutes: Int?,
    originalDurationMinutes: Int?,
    target: ScheduleInteractionTarget,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleInteractionPreview? {
    switch target {
    case .allDay(let day):
      return ScheduleInteractionPreview(day: day, timeMinutes: nil, durationMinutes: nil)
    case .monthDay(let day):
      return ScheduleInteractionPreview(
        day: day,
        timeMinutes: originalTimeMinutes,
        durationMinutes: originalTimeMinutes == nil ? nil : originalDurationMinutes
      )
    case .timed(let day, let minute):
      let duration = max(
        metrics.timedMinimumDurationMinutes,
        originalDurationMinutes ?? metrics.timedMinimumDurationMinutes
      )
      return ScheduleInteractionPreview(
        day: day,
        timeMinutes: minute,
        durationMinutes: duration
      )
    case .outside, .invalid:
      return nil
    }
  }

  static func resizePreview(
    originalDay: Date,
    originalTimeMinutes: Int,
    originalDurationMinutes: Int,
    isStartEdge: Bool,
    edgeScheduleY: CGFloat,
    targetDay: Date,
    metrics: ScheduleInteractionMetrics,
    calendar: Calendar
  ) -> ScheduleInteractionPreview {
    let startDate = date(
      day: originalDay,
      minute: originalTimeMinutes,
      calendar: calendar
    )
    let endDate =
      calendar.date(
        byAdding: .minute,
        value: originalDurationMinutes,
        to: startDate
      ) ?? startDate
    let edgeDate = date(
      visibleDay: targetDay,
      relativeMinute: snappedRelativeMinutes(for: edgeScheduleY, metrics: metrics),
      calendar: calendar
    )

    let proposedStart: Date
    let proposedEnd: Date
    if isStartEdge {
      let latestStart =
        calendar.date(
          byAdding: .minute,
          value: -metrics.timedMinimumDurationMinutes,
          to: endDate
        ) ?? endDate
      proposedStart = min(edgeDate, latestStart)
      proposedEnd = endDate
    } else {
      proposedStart = startDate
      proposedEnd = maxDate(
        edgeDate,
        calendar.date(
          byAdding: .minute,
          value: metrics.timedMinimumDurationMinutes,
          to: startDate
        ) ?? startDate
      )
    }

    let proposedStartDay = calendar.startOfDay(for: proposedStart)
    let day = calendar.isDate(proposedStart, inSameDayAs: originalDay)
      ? originalDay
      : proposedStartDay
    let minute = minuteOffset(from: proposedStartDay, to: proposedStart, calendar: calendar)
    let duration = max(
      metrics.timedMinimumDurationMinutes,
      minuteOffset(from: proposedStart, to: proposedEnd, calendar: calendar)
    )
    return ScheduleInteractionPreview(day: day, timeMinutes: minute, durationMinutes: duration)
  }

  static func command(
    for identity: ScheduleInteractionItemIdentity,
    operation: ScheduleInteractionOperation,
    preview: ScheduleInteractionPreview
  ) -> ScheduleInteractionCommand? {
    guard let day = preview.day else { return nil }
    switch (identity, operation) {
    case (.task(let taskID), .move):
      return .moveTask(
        taskID: taskID,
        day: day,
        timeMinutes: preview.timeMinutes,
        durationMinutes: preview.durationMinutes
      )
    case (.task(let taskID), .resize):
      guard let timeMinutes = preview.timeMinutes, let durationMinutes = preview.durationMinutes else {
        return nil
      }
      return .resizeTask(
        taskID: taskID,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    case (.calendarEvent(let eventID), .move):
      return .moveCalendarEvent(
        eventID: eventID,
        day: day,
        timeMinutes: preview.timeMinutes,
        durationMinutes: preview.durationMinutes
      )
    case (.calendarEvent(let eventID), .resize):
      guard let timeMinutes = preview.timeMinutes, let durationMinutes = preview.durationMinutes else {
        return nil
      }
      return .resizeCalendarEvent(
        eventID: eventID,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    }
  }

  private static func snappedRelativeMinutes(
    for scheduleY: CGFloat,
    metrics: ScheduleInteractionMetrics
  ) -> Int {
    Int((scheduleY / metrics.quarterHourHeight).rounded()) * 15
  }

  private static func resolvedDateAndMinute(
    relativeMinute: Int,
    visibleDay: Date,
    calendar: Calendar
  ) -> (day: Date, timeMinutes: Int) {
    let date = date(visibleDay: visibleDay, relativeMinute: relativeMinute, calendar: calendar)
    let dayStart = calendar.startOfDay(for: date)
    let day = calendar.isDate(date, inSameDayAs: visibleDay) ? visibleDay : dayStart
    return (day, minuteOffset(from: dayStart, to: date, calendar: calendar))
  }

  private static func date(
    day: Date,
    minute: Int,
    calendar: Calendar
  ) -> Date {
    calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: day)) ?? day
  }

  private static func date(
    visibleDay: Date,
    relativeMinute: Int,
    calendar: Calendar
  ) -> Date {
    calendar.date(
      byAdding: .minute,
      value: relativeMinute,
      to: calendar.startOfDay(for: visibleDay)
    ) ?? visibleDay
  }

  private static func minuteOffset(
    from start: Date,
    to end: Date,
    calendar: Calendar
  ) -> Int {
    calendar.dateComponents([.minute], from: start, to: end).minute ?? 0
  }

  private static func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
    lhs > rhs ? lhs : rhs
  }
}

enum ScheduleInteractionOperation: Equatable, Sendable {
  case move
  case resize
}

extension ScheduleInteractionCommand {
  func schedulePreview(fallbackDay: Date? = nil) -> ScheduleInteractionPreview {
    switch self {
    case .moveTask(_, let day, let timeMinutes, let durationMinutes):
      return ScheduleInteractionPreview(
        day: day ?? fallbackDay,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    case .resizeTask(_, let day, let timeMinutes, let durationMinutes):
      return ScheduleInteractionPreview(
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    case .moveCalendarEvent(_, let day, let timeMinutes, let durationMinutes):
      return ScheduleInteractionPreview(
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    case .resizeCalendarEvent(_, let day, let timeMinutes, let durationMinutes):
      return ScheduleInteractionPreview(
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    }
  }
}
