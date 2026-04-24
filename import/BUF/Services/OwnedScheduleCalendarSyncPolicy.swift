import Foundation

enum OwnedScheduleCalendarSyncPolicy {
  struct TaskScheduleValue: Equatable, Sendable {
    let day: Date
    let timeMinutes: Int?
    let durationMinutes: Int?
  }

  static func upsertRequest(
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    durationMinutes: Int?,
    existingExternalIdentifier: String?
  ) -> OwnedScheduleCalendarEventUpsertRequest? {
    guard
      let dueDate,
      hasExplicitTime,
      let normalizedDurationMinutes = normalizedDurationMinutes(durationMinutes)
    else {
      return nil
    }

    return OwnedScheduleCalendarEventUpsertRequest(
      externalIdentifier: normalizedIdentifier(existingExternalIdentifier),
      title: title,
      startDate: dueDate,
      durationMinutes: normalizedDurationMinutes
    )
  }

  static func taskScheduleValue(
    for event: ScheduleCalendarEvent,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TaskScheduleValue {
    let startDay = calendar.startOfDay(for: event.startDate)
    let timeMinutes: Int?
    let durationMinutes: Int?

    if event.isAllDay {
      timeMinutes = nil
      durationMinutes = nil
    } else {
      let components = calendar.dateComponents([.hour, .minute], from: event.startDate)
      timeMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
      durationMinutes = normalizedDurationMinutes(
        Int(event.endDate.timeIntervalSince(event.startDate) / 60)
      )
    }

    return TaskScheduleValue(
      day: startDay,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )
  }

  private static func normalizedDurationMinutes(_ durationMinutes: Int?) -> Int? {
    guard let durationMinutes, durationMinutes > 0 else { return nil }
    return max(5, durationMinutes)
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
