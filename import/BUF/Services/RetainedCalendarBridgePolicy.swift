import Foundation

enum RetainedCalendarBridgePolicy {
  static func decision(
    for task: RetainedTask,
    ambiguousOwnedEventIdentifiers: Set<String> = []
  ) -> RetainedCalendarBridgeDecision {
    // Reminder-backed tasks are rendered as Schedule blocks, not mirrored into Calendar events.
    _ = task
    _ = ambiguousOwnedEventIdentifiers
    return .noAction
  }
}
