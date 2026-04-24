import Foundation

enum ReminderConflictPolicy {
  struct Context: Sendable, Equatable {
    let hasPendingLocalChanges: Bool
    let pendingChangeAge: TimeInterval?
    let lastLocalWriteAt: Date?
    let remoteModifiedAt: Date?
    let pushFailureCount: Int
  }

  static let pendingChangeStalenessThreshold: TimeInterval = 300
  static let recentLocalDeletionGracePeriod: TimeInterval = 8

  static func shouldApplyRemoteMutation(_ context: Context) -> Bool {
    if context.hasPendingLocalChanges, !hasStalePendingChange(context) {
      return false
    }

    guard let lastLocalWriteAt = context.lastLocalWriteAt else { return true }
    guard let remoteModifiedAt = context.remoteModifiedAt else { return false }
    return remoteModifiedAt > lastLocalWriteAt
  }

  static func shouldApplyRemoteDeletion(_ context: Context, now: Date = .now) -> Bool {
    if context.hasPendingLocalChanges, !hasStalePendingChange(context) {
      return false
    }

    guard let lastLocalWriteAt = context.lastLocalWriteAt else { return true }
    return now.timeIntervalSince(lastLocalWriteAt) > recentLocalDeletionGracePeriod
  }

  private static func hasStalePendingChange(_ context: Context) -> Bool {
    guard let pendingChangeAge = context.pendingChangeAge else { return false }
    return pendingChangeAge > pendingChangeStalenessThreshold
  }
}
