import Foundation

enum TimelineProjectListWindowSnapshotFactory {
  static func snapshot(
    projectID: UUID,
    title: String,
    colorHex: String?,
    projectNoteText: String,
    entries: [ScheduleSliceEntry],
    calendar: Calendar = .autoupdatingCurrent
  ) -> TimelineProjectListWindowSnapshot {
    TimelineProjectListWindowSnapshot(
      projectID: projectID,
      title: TimelineBoardReadPath.timelinePreviewTitle(for: title),
      colorHex: colorHex,
      projectNoteText: projectNoteText,
      tasks: orderedEntries(projectID: projectID, entries: entries).map { entry in
        taskSnapshot(for: entry, calendar: calendar)
      }
    )
  }

  static func orderedEntries(
    projectID: UUID,
    entries: [ScheduleSliceEntry]
  ) -> [ScheduleSliceEntry] {
    let visibleEntries = TimelineBoardReadPath.projectListWindowEntries(from: entries)
    let orderedTaskIDs = TimelineProjectTaskManualOrderStore.orderedTaskIDs(
      visibleEntries.map(\.taskID),
      using: TimelineProjectTaskManualOrderStore.projectOrder(for: projectID)
    )
    let entriesByTaskID = Dictionary(uniqueKeysWithValues: visibleEntries.map { ($0.taskID, $0) })
    return orderedTaskIDs.compactMap { entriesByTaskID[$0] }
  }

  static func defaultEditableEntry(
    projectID: UUID,
    entries: [ScheduleSliceEntry]
  ) -> ScheduleSliceEntry? {
    orderedEntries(projectID: projectID, entries: entries).first
  }

  static func taskSnapshot(
    for entry: ScheduleSliceEntry,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TimelineProjectListWindowSnapshot.Task {
    TimelineProjectListWindowSnapshot.Task(
      id: entry.taskID,
      title: TimelineBoardReadPath.timelinePreviewTitle(for: entry.title),
      dateText: dateText(for: entry),
      notePreviewText: notePreviewText(for: entry),
      metadataIndicators: metadataIndicators(for: entry),
      isCompleted: entry.isCompleted,
      isOverdue: isOverdue(entry, calendar: calendar)
    )
  }

  static func metadataIndicators(
    for entry: ScheduleSliceEntry
  ) -> TimelineProjectListWindowSnapshot.Task.MetadataIndicators {
    metadataIndicators(
      noteText: entry.reminderNoteText,
      attachmentCount: entry.attachmentCount
    )
  }

  static func metadataIndicators(
    noteText: String,
    attachmentCount: Int
  ) -> TimelineProjectListWindowSnapshot.Task.MetadataIndicators {
    let noteTextWithoutAttachmentLinks =
      TaskEditAttachmentService.noteTextByRemovingAttachmentLinks(from: noteText)
    let trimmedNoteText = noteTextWithoutAttachmentLinks
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return TimelineProjectListWindowSnapshot.Task.MetadataIndicators(
      hasNote: !trimmedNoteText.isEmpty,
      attachmentCount: max(0, attachmentCount)
        + TaskEditAttachmentService.attachmentLinkCount(in: noteText)
    )
  }

  static func notePreviewText(for entry: ScheduleSliceEntry) -> String? {
    guard entry.hasReminderNoteContent else { return nil }
    return notePreviewText(for: entry.reminderNoteText)
  }

  static func notePreviewText(for noteText: String) -> String? {
    let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  static func dateText(for entry: ScheduleSliceEntry) -> String? {
    guard
      let date = ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: entry.dueDate,
        startDate: entry.startDate,
        displayedDate: entry.displayedDate
      )
    else {
      return nil
    }

    if entry.scheduleHasExplicitTime {
      return compactDateTimeText(for: date)
    }

    return compactDateText(for: date)
  }

  static func isOverdue(
    _ entry: ScheduleSliceEntry,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Bool {
    guard !entry.isCompleted else { return false }
    guard
      let date = ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: entry.dueDate,
        startDate: entry.startDate,
        displayedDate: entry.displayedDate
      )
    else {
      return false
    }
    return calendar.startOfDay(for: date) < calendar.startOfDay(for: .now)
  }

  private static func compactDateText(for date: Date) -> String {
    let components = Calendar.autoupdatingCurrent.dateComponents([.month, .day], from: date)
    return [
      twoDigitText(components.month ?? 0),
      twoDigitText(components.day ?? 0),
    ].joined(separator: "-")
  }

  private static func compactDateTimeText(for date: Date) -> String {
    let components = Calendar.autoupdatingCurrent.dateComponents(
      [.month, .day, .hour, .minute],
      from: date
    )
    return [
      compactDateText(for: date),
      "\(twoDigitText(components.hour ?? 0)):\(twoDigitText(components.minute ?? 0))",
    ].joined(separator: " ")
  }

  private static func twoDigitText(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
  }
}
