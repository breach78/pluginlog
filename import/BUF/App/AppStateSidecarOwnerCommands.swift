import Foundation

@MainActor
extension AppState {
  @discardableResult
  func send(
    _ command: AppCommand,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    _ = waitForEditorIdle
    switch command {
    case let .externalOwnerChange(ownerStore, ownerIDs, changedFields):
      switch ownerStore {
      case .reminder:
        return await handleExternalReminderTaskInvalidation(
          ownerIDs: ownerIDs,
          changedFields: changedFields,
          waitForEditorIdle: false
        )
      case .calendar:
        return await handleExternalCalendarEventInvalidation(
          ownerIDs: ownerIDs,
          changedFields: changedFields,
          waitForEditorIdle: false
        )
      case .sidecar:
        bumpWorkspaceTreeRevision()
        return true
      }
    }
  }
}
