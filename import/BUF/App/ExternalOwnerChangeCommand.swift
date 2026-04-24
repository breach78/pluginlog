import Foundation

enum ExternalOwnerChangeCommand: Sendable {
  case reminderProjectListsChanged(
    reason: SyncReason,
    reminderListIdentifiers: [String],
    reminderListExternalIdentifiers: [String]
  )
}

