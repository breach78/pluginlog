import Foundation

extension Notification.Name {
  static let reminderAppEditingEscapePressed = Notification.Name("reminderApp.editingEscapePressed")
  static let reminderAppFocusWorkspaceSearchRequested = Notification.Name(
    "reminderApp.focusWorkspaceSearchRequested")
  static let reminderAppJournalEntriesDidChange = Notification.Name(
    "reminderApp.journalEntriesDidChange")
  static let reminderAppTaskSequenceAssignmentsDidChange = Notification.Name(
    "reminderApp.taskSequenceAssignmentsDidChange")
}
