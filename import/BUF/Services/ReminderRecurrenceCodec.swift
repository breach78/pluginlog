@preconcurrency import EventKit
import Foundation

enum ReminderRecurrenceCodec {
  static func recurrenceRules(fromRawValue rawValue: String?) -> [EKRecurrenceRule]? {
    guard let recurrence = OutlinerIntegratedStore.decodeRecurrence(rawValue: rawValue) else {
      return nil
    }

    switch recurrence {
    case let .daily(interval):
      return [EKRecurrenceRule(recurrenceWith: .daily, interval: max(1, interval), end: nil)]
    case let .weekly(interval, weekdays):
      let daysOfWeek = weekdays.compactMap { rawValue -> EKRecurrenceDayOfWeek? in
        guard let weekday = EKWeekday(rawValue: rawValue) else { return nil }
        return EKRecurrenceDayOfWeek(weekday)
      }
      return [EKRecurrenceRule(
        recurrenceWith: .weekly,
        interval: max(1, interval),
        daysOfTheWeek: daysOfWeek.isEmpty ? nil : daysOfWeek,
        daysOfTheMonth: nil,
        monthsOfTheYear: nil,
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nil,
        end: nil
      )]
    case let .monthly(interval):
      return [EKRecurrenceRule(recurrenceWith: .monthly, interval: max(1, interval), end: nil)]
    case let .yearly(interval):
      return [EKRecurrenceRule(recurrenceWith: .yearly, interval: max(1, interval), end: nil)]
    }
  }

  static func rawValue(from rules: [EKRecurrenceRule]?) -> String? {
    guard let first = rules?.first else { return nil }

    switch first.frequency {
    case .daily:
      return "daily|\(max(1, first.interval))"
    case .weekly:
      let weekdays = (first.daysOfTheWeek ?? [])
        .map(\.dayOfTheWeek.rawValue)
        .sorted()
        .map(String.init)
        .joined(separator: ",")
      return "weekly|\(max(1, first.interval))|\(weekdays)"
    case .monthly:
      return "monthly|\(max(1, first.interval))"
    case .yearly:
      return "yearly|\(max(1, first.interval))"
    @unknown default:
      return nil
    }
  }
}
