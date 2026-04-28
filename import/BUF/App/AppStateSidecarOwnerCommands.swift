import Foundation

@MainActor
extension AppState {
  @discardableResult
  func send(
    _ command: AppCommand,
    waitForEditorIdle: Bool = true
  ) async -> Bool {
    switch command {
    case let .externalOwnerChange(ownerStore, ownerIDs, changedFields):
      switch ownerStore {
      case .reminder:
        return await handleExternalReminderTaskInvalidation(
          ownerIDs: ownerIDs,
          changedFields: changedFields,
          waitForEditorIdle: waitForEditorIdle
        )
      case .calendar:
        return await handleExternalCalendarEventInvalidation(
          ownerIDs: ownerIDs,
          changedFields: changedFields,
          waitForEditorIdle: waitForEditorIdle
        )
      case .sidecar:
        guard await waitForEditorToBecomeIdleIfRequested(waitForEditorIdle) else { return false }
        bumpWorkspaceTreeRevision()
        return true
      }
    }
  }

  private func waitForEditorToBecomeIdleIfRequested(_ shouldWait: Bool) async -> Bool {
    guard shouldWait else { return true }
    return await waitForEditorToBecomeIdle()
  }
}
