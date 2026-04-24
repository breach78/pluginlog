import Foundation

@MainActor
extension AppState {
  @discardableResult
  func removeReminderTasks(_ references: [ReminderTaskReference]) async -> Bool {
    _ = references
    bumpWorkspaceTreeRevision()
    return true
  }
}
