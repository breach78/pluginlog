@preconcurrency import EventKit
import Foundation

enum ReminderRecurrenceCodec {
  static func recurrenceRules(fromRawValue rawValue: String?) -> [EKRecurrenceRule]? {
    guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawValue.isEmpty
    else {
      return nil
    }

    let parts = rawValue.lowercased().split(separator: "|", omittingEmptySubsequences: false)
    let frequency = parts.first.map(String.init) ?? rawValue.lowercased()
    let interval = parts.dropFirst().first.flatMap { Int($0) } ?? 1

    switch frequency {
    case "daily":
      return [EKRecurrenceRule(recurrenceWith: .daily, interval: max(1, interval), end: nil)]
    case "weekly":
      let weekdays = parts.dropFirst(2).first?.split(separator: ",").compactMap { Int($0) } ?? []
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
    case "monthly":
      return [EKRecurrenceRule(recurrenceWith: .monthly, interval: max(1, interval), end: nil)]
    case "yearly":
      return [EKRecurrenceRule(recurrenceWith: .yearly, interval: max(1, interval), end: nil)]
    default:
      return nil
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
