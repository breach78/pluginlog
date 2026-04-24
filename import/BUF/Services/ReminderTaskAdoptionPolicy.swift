import Foundation

struct ReminderTaskAdoptionPolicy {
  static func uniqueMatch<T>(
    from matches: [T]
  ) -> T? {
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  static func allowsExternalReminderAdoption(
    candidateCalendarIdentifier: String?,
    targetReminderListIdentifier: String?
  ) -> Bool {
    guard
      let candidateCalendarIdentifier = normalized(candidateCalendarIdentifier),
      let targetReminderListIdentifier = normalized(targetReminderListIdentifier)
    else {
      return false
    }

    return candidateCalendarIdentifier == targetReminderListIdentifier
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
