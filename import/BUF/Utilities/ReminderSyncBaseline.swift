import Foundation

struct ReminderSyncBaseline: Equatable, Sendable {
  var lastSyncedReminderTitle: String
  var lastSyncedReminderNoteBody: String
  var lastSyncedReminderModifiedAt: Date?
  var reminderNoteConflictExcerpt: String?

  init(
    lastSyncedReminderTitle: String,
    lastSyncedReminderNoteBody: String,
    lastSyncedReminderModifiedAt: Date? = nil,
    reminderNoteConflictExcerpt: String? = nil
  ) {
    self.lastSyncedReminderTitle = lastSyncedReminderTitle
    self.lastSyncedReminderNoteBody = lastSyncedReminderNoteBody
    self.lastSyncedReminderModifiedAt = lastSyncedReminderModifiedAt
    self.reminderNoteConflictExcerpt = reminderNoteConflictExcerpt
  }

  init(
    reminderTitle: String,
    parsedNote: ReminderNoteCodec.ParsedNote,
    modifiedAt: Date? = nil,
    conflictExcerpt: String? = nil
  ) {
    self.init(
      lastSyncedReminderTitle: reminderTitle,
      lastSyncedReminderNoteBody: parsedNote.body,
      lastSyncedReminderModifiedAt: modifiedAt,
      reminderNoteConflictExcerpt: conflictExcerpt
    )
  }
}
