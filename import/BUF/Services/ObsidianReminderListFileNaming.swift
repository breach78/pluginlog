import Foundation

struct ObsidianReminderListFileNaming {
  private let duplicateTitleCounts: [String: Int]

  init(titles: [String]) {
    var counts: [String: Int] = [:]
    for title in titles {
      counts[Self.titleKey(title), default: 0] += 1
    }
    duplicateTitleCounts = counts
  }

  /// Keeps human-readable filenames stable while making same-title Reminder lists distinct.
  func preferredFileName(title: String, externalIdentifier: String) -> String {
    guard (duplicateTitleCounts[Self.titleKey(title)] ?? 0) > 1 else {
      return title
    }
    return "\(title) - \(Self.shortIdentifier(externalIdentifier))"
  }

  private static func titleKey(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func shortIdentifier(_ identifier: String) -> String {
    String(identifier.prefix(8))
  }
}
