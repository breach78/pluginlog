import Foundation

enum ReminderScheduleMetadataCodec {
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

  static func encodeDate(_ date: Date?, hasExplicitTime: Bool) -> String? {
    guard let date else { return nil }
    return hasExplicitTime
      ? dateFormatter.string(from: date)
      : dayFormatter.string(from: localCalendar.startOfDay(for: date))
  }

  static func decodeRepeat(_ rawValue: String?) -> String? {
    guard let normalized = normalized(rawValue) else { return nil }
    let value = normalized.lowercased()
    if value == "daily" || value.hasPrefix("daily|") { return "daily|1" }
    if value == "weekly" || value.hasPrefix("weekly|") { return "weekly|1|" }
    if value == "monthly" || value.hasPrefix("monthly|") { return "monthly|1" }
    if value == "yearly" || value.hasPrefix("yearly|") { return "yearly|1" }
    return nil
  }

  static func encodeRepeat(_ rawValue: String?) -> String? {
    guard let normalized = normalized(rawValue) else { return nil }
    let value = normalized.lowercased()
    switch value {
    case "daily":
      return "daily"
    case "weekly":
      return "weekly"
    case "monthly":
      return "monthly"
    case "yearly":
      return "yearly"
    default:
      if value.hasPrefix("daily|") { return "daily" }
      if value.hasPrefix("weekly|") { return "weekly" }
      if value.hasPrefix("monthly|") { return "monthly" }
      if value.hasPrefix("yearly|") { return "yearly" }
      return nil
    }
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
