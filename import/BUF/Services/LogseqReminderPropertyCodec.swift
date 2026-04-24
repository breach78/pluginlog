import Foundation

enum LogseqReminderPropertyCodec {
  struct DecodedDate: Equatable, Sendable {
    let date: Date
    let hasExplicitTime: Bool
  }

  private static let localCalendar = Calendar.autoupdatingCurrent

  static func decodeDate(_ rawValue: String?) -> DecodedDate? {
    guard let normalized = normalized(rawValue) else { return nil }

    if let date = dateFormatter.date(from: normalized) {
      return DecodedDate(date: date, hasExplicitTime: true)
    }
    if let date = dayFormatter.date(from: normalized) {
      return DecodedDate(date: date, hasExplicitTime: false)
    }
    return nil
  }

  static func encodeDate(
    _ date: Date?,
    hasExplicitTime: Bool
  ) -> String? {
    guard let date else { return nil }
    return hasExplicitTime
      ? dateFormatter.string(from: date)
      : dayFormatter.string(from: localCalendar.startOfDay(for: date))
  }

  static func decodeRepeat(_ rawValue: String?) -> String? {
    guard let normalized = normalized(rawValue) else { return nil }

    switch normalized.lowercased() {
    case "daily":
      return "daily|1"
    case "weekly":
      return "weekly|1|"
    case "monthly":
      return "monthly|1"
    case "yearly":
      return "yearly|1"
    default:
      guard let recurrence = OutlinerIntegratedStore.decodeRecurrence(rawValue: normalized) else {
        return nil
      }
      return OutlinerIntegratedStore.encodeRecurrence(recurrence)
    }
  }

  static func encodeRepeat(_ rawValue: String?) -> String? {
    guard let normalized = normalized(rawValue),
      let recurrence = OutlinerIntegratedStore.decodeRecurrence(rawValue: normalized)
    else {
      return nil
    }

    switch recurrence {
    case .daily:
      return "daily"
    case .weekly:
      return "weekly"
    case .monthly:
      return "monthly"
    case .yearly:
      return "yearly"
    }
  }

  static func explicitTimeMinutes(from date: Date?) -> Int? {
    guard let date else { return nil }
    let components = localCalendar.dateComponents([.hour, .minute], from: date)
    let hasExplicitTime = (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0
    guard hasExplicitTime else { return nil }
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  private static func normalized(_ rawValue: String?) -> String? {
    guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawValue.isEmpty
    else {
      return nil
    }
    return rawValue
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()
}
