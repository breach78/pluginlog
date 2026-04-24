import Foundation

struct ReminderSyncPendingOperationRecord: Codable, Equatable, Sendable {
  let operationID: UUID
}

final class ReminderSyncRecoveryJournalStore {
  func unfinishedOperationsSorted() -> [ReminderSyncPendingOperationRecord] { [] }
  func enqueue(_ record: ReminderSyncPendingOperationRecord) -> ReminderSyncPendingOperationRecord {
    record
  }
  func markFinished(operationID: UUID) {
    _ = operationID
  }
}

final class ReminderSyncEditGate {
  enum SessionKind: Sendable {
    case generic
  }

  struct SweepResult: Sendable {
    let cancelledSessionIDs: [String]
    let forcedManualRevalidateCount: Int
  }

  func beginSession(
    sessionID: String,
    ownerWindowID: String?,
    kind: SessionKind,
    contentID: UUID?,
    projectID: UUID?
  ) {
    _ = sessionID
    _ = ownerWindowID
    _ = kind
    _ = contentID
    _ = projectID
  }

  func endSession(sessionID: String) {
    _ = sessionID
  }

  func heartbeatAllSessions() {}

  func cancelSessionsOwnedByWindow(_ ownerWindowID: String) {
    _ = ownerWindowID
  }

  func sweepOrphanedSessions(
    activeOwnerWindowIDs: Set<String>,
    now: Date
  ) -> SweepResult {
    _ = activeOwnerWindowIDs
    _ = now
    return SweepResult(cancelledSessionIDs: [], forcedManualRevalidateCount: 0)
  }
}
