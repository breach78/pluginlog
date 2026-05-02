import Foundation

enum TimelineProjectListWindowSnapshotFactory {
  static func snapshot(
    projectID: UUID,
    title: String,
    colorHex: String?,
    entries: [ScheduleSliceEntry],
    calendar: Calendar = .autoupdatingCurrent
  ) -> TimelineProjectListWindowSnapshot {
    TimelineProjectListWindowSnapshot(
      projectID: projectID,
      title: TimelineBoardReadPath.timelinePreviewTitle(for: title),
      colorHex: colorHex,
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
      isCompleted: entry.isCompleted,
      isOverdue: isOverdue(entry, calendar: calendar)
    )
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

    let locale = Locale(identifier: "ko_KR")
    if entry.scheduleHasExplicitTime {
      return date.formatted(
        .dateTime
          .locale(locale)
          .month(.abbreviated)
          .day()
          .hour(.twoDigits(amPM: .omitted))
          .minute(.twoDigits)
      )
    }

    return date.formatted(.dateTime.locale(locale).month(.abbreviated).day())
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
}
