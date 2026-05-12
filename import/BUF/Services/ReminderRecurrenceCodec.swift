@preconcurrency import EventKit
import Foundation

enum ReminderRecurrenceDescriptor: Equatable, Sendable {
  case none
  case daily(interval: Int)
  case weekly(interval: Int, weekdays: [Int])
  case monthly(interval: Int)
  case monthlyByDay(interval: Int, days: [Int])
  case monthlyByWeekday(interval: Int, weekdays: [ReminderRecurrenceWeekdayOrdinal])
  case yearly(interval: Int)
  case unsupported(rawValue: String)

  var rawValue: String? {
    switch self {
    case .none:
      return nil
    case .daily(let interval):
      return "daily|\(Self.normalizedInterval(interval))"
    case .weekly(let interval, let weekdays):
      return "weekly|\(Self.normalizedInterval(interval))|\(Self.csv(Self.normalizedWeekdays(weekdays)))"
    case .monthly(let interval):
      return "monthly|\(Self.normalizedInterval(interval))"
    case .monthlyByDay(let interval, let days):
      return "monthly|\(Self.normalizedInterval(interval))|days=\(Self.csv(Self.normalizedMonthDays(days)))"
    case .monthlyByWeekday(let interval, let weekdays):
      let encoded = weekdays
        .map { weekday in
          "\(weekday.weekday):\(weekday.weekNumber)"
        }
        .joined(separator: ",")
      return "monthly|\(Self.normalizedInterval(interval))|weekdays=\(encoded)"
    case .yearly(let interval):
      return "yearly|\(Self.normalizedInterval(interval))"
    case .unsupported(let rawValue):
      return rawValue
    }
  }

  var isUnsupported: Bool {
    if case .unsupported = self { return true }
    return false
  }

  static func parse(_ rawValue: String?) -> ReminderRecurrenceDescriptor {
    guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawValue.isEmpty
    else {
      return .none
    }

    let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard let frequency = parts.first?.lowercased() else { return .unsupported(rawValue: rawValue) }
    let interval = normalizedInterval(parts.dropFirst().first.flatMap(Int.init) ?? 1)

    switch frequency {
    case "daily":
      return .daily(interval: interval)
    case "weekly":
      let weekdays = parts.dropFirst(2).first.map(parseIntList) ?? []
      return .weekly(interval: interval, weekdays: normalizedWeekdays(weekdays))
    case "monthly":
      guard let selector = parts.dropFirst(2).first, !selector.isEmpty else {
        return .monthly(interval: interval)
      }
      if let rawDays = selector.dropPrefix("day=") ?? selector.dropPrefix("days=") {
        return .monthlyByDay(interval: interval, days: normalizedMonthDays(parseIntList(String(rawDays))))
      }
      if let rawWeekdays = selector.dropPrefix("weekday=") ?? selector.dropPrefix("weekdays=") {
        let weekdays = rawWeekdays.split(separator: ",").compactMap { component in
          ReminderRecurrenceWeekdayOrdinal.parse(String(component))
        }
        return weekdays.isEmpty
          ? .unsupported(rawValue: rawValue)
          : .monthlyByWeekday(interval: interval, weekdays: weekdays)
      }
      return .unsupported(rawValue: rawValue)
    case "yearly":
      return .yearly(interval: interval)
    default:
      return .unsupported(rawValue: rawValue)
    }
  }

  private static func normalizedInterval(_ value: Int) -> Int {
    max(1, value)
  }

  private static func normalizedWeekdays(_ values: [Int]) -> [Int] {
    Array(Set(values.filter { EKWeekday(rawValue: $0) != nil })).sorted()
  }

  private static func normalizedMonthDays(_ values: [Int]) -> [Int] {
    Array(Set(values.filter { (1...31).contains($0) })).sorted()
  }

  private static func parseIntList(_ rawValue: String) -> [Int] {
    rawValue.split(separator: ",").compactMap { Int($0) }
  }

  private static func csv(_ values: [Int]) -> String {
    values.map(String.init).joined(separator: ",")
  }
}

struct ReminderRecurrenceWeekdayOrdinal: Equatable, Sendable {
  var weekday: Int
  var weekNumber: Int

  init(weekday: Int, weekNumber: Int) {
    self.weekday = weekday
    self.weekNumber = min(5, max(-5, weekNumber))
  }

  static func parse(_ rawValue: String) -> ReminderRecurrenceWeekdayOrdinal? {
    let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let weekday = Int(parts[0]),
      EKWeekday(rawValue: weekday) != nil,
      let weekNumber = Int(parts[1]),
      weekNumber != 0
    else {
      return nil
    }
    return ReminderRecurrenceWeekdayOrdinal(weekday: weekday, weekNumber: weekNumber)
  }
}

enum ReminderRecurrenceCodec {
  static func recurrenceRules(fromRawValue rawValue: String?) -> [EKRecurrenceRule]? {
    switch ReminderRecurrenceDescriptor.parse(rawValue) {
    case .none, .unsupported:
      return nil
    case .daily(let interval):
      return [EKRecurrenceRule(recurrenceWith: .daily, interval: interval, end: nil)]
    case .weekly(let interval, let weekdays):
      let daysOfWeek = weekdays.compactMap { rawValue -> EKRecurrenceDayOfWeek? in
        guard let weekday = EKWeekday(rawValue: rawValue) else { return nil }
        return EKRecurrenceDayOfWeek(weekday)
      }
      return [EKRecurrenceRule(
        recurrenceWith: .weekly,
        interval: interval,
        daysOfTheWeek: daysOfWeek.isEmpty ? nil : daysOfWeek,
        daysOfTheMonth: nil,
        monthsOfTheYear: nil,
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nil,
        end: nil
      )]
    case .monthly(let interval):
      return [EKRecurrenceRule(recurrenceWith: .monthly, interval: interval, end: nil)]
    case .monthlyByDay(let interval, let days):
      return [EKRecurrenceRule(
        recurrenceWith: .monthly,
        interval: interval,
        daysOfTheWeek: nil,
        daysOfTheMonth: days.map(NSNumber.init(value:)),
        monthsOfTheYear: nil,
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nil,
        end: nil
      )]
    case .monthlyByWeekday(let interval, let weekdays):
      let daysOfWeek = weekdays.compactMap { ordinal -> EKRecurrenceDayOfWeek? in
        guard let weekday = EKWeekday(rawValue: ordinal.weekday) else { return nil }
        return EKRecurrenceDayOfWeek(weekday, weekNumber: ordinal.weekNumber)
      }
      return [EKRecurrenceRule(
        recurrenceWith: .monthly,
        interval: interval,
        daysOfTheWeek: daysOfWeek.isEmpty ? nil : daysOfWeek,
        daysOfTheMonth: nil,
        monthsOfTheYear: nil,
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nil,
        end: nil
      )]
    case .yearly(let interval):
      return [EKRecurrenceRule(recurrenceWith: .yearly, interval: interval, end: nil)]
    }
  }

  static func rawValue(from rules: [EKRecurrenceRule]?) -> String? {
    guard let first = rules?.first else { return nil }

    switch first.frequency {
    case .daily:
      return ReminderRecurrenceDescriptor.daily(interval: first.interval).rawValue
    case .weekly:
      let weekdays = (first.daysOfTheWeek ?? [])
        .map(\.dayOfTheWeek.rawValue)
      return ReminderRecurrenceDescriptor.weekly(interval: first.interval, weekdays: weekdays).rawValue
    case .monthly:
      if let days = first.daysOfTheMonth?.compactMap(\.intValue), !days.isEmpty {
        return ReminderRecurrenceDescriptor.monthlyByDay(interval: first.interval, days: days).rawValue
      }
      if let daysOfWeek = first.daysOfTheWeek, !daysOfWeek.isEmpty {
        let weekdays = daysOfWeek.map {
          ReminderRecurrenceWeekdayOrdinal(
            weekday: $0.dayOfTheWeek.rawValue,
            weekNumber: $0.weekNumber
          )
        }
        return ReminderRecurrenceDescriptor.monthlyByWeekday(
          interval: first.interval,
          weekdays: weekdays
        ).rawValue
      }
      return ReminderRecurrenceDescriptor.monthly(interval: first.interval).rawValue
    case .yearly:
      return ReminderRecurrenceDescriptor.yearly(interval: first.interval).rawValue
    @unknown default:
      return nil
    }
  }
}

private extension String {
  func dropPrefix(_ prefix: String) -> Substring? {
    guard lowercased().hasPrefix(prefix) else { return nil }
    return dropFirst(prefix.count)
  }
}
