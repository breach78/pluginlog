import Foundation

enum ObsidianRetainedProjectionAdapter {
  static func build(
    snapshots: [ObsidianProjectMarkdownStore.Snapshot],
    calendar: Calendar = .autoupdatingCurrent
  ) throws -> RetainedWorkspaceSnapshot {
    try validateNotes(snapshots.map(\.note))

    let projects = try snapshots
      .sorted(by: snapshotSort)
      .compactMap { snapshot in
        try buildProject(from: snapshot, calendar: calendar)
      }

    return RetainedWorkspaceSnapshot(projects: projects)
  }

  private static func buildProject(
    from snapshot: ObsidianProjectMarkdownStore.Snapshot,
    calendar: Calendar
  ) throws -> RetainedProject? {
    let note = snapshot.note
    let title = projectTitle(from: snapshot)
    guard note.tasks.allSatisfy({ !$0.metadataIsDamaged }) else {
      return nil
    }
    guard let listID = normalized(note.reminderListExternalIdentifier) else {
      return nil
    }

    return RetainedProject(
      identity: RetainedProjectIdentity(
        projectID: RetainedProjectionBuilder.derivedProjectID(for: listID),
        reminderListExternalIdentifier: listID
      ),
      fileURL: snapshot.fileURL,
      title: title,
      noteMarkdown: note.bodyMarkdown,
      tasks: note.tasks.map { buildTask($0, calendar: calendar) },
      usesProjectTag: note.isProjectTagged,
      isBUFOwned: true,
      hasManagedTaskSection: false,
      canSafelyPersistProjectNote: false,
      isArchived: note.frontmatter?.isArchived ?? false,
      colorHex: normalized(note.frontmatter?.colorHex),
      localStartDate: parseDate(note.frontmatter?.startDate, time: nil, calendar: calendar),
      localDeadline: parseDate(note.frontmatter?.deadline, time: nil, calendar: calendar),
      progressStage: note.frontmatter?.projectStage ?? .do,
      updatedAt: snapshot.contentModificationDate ?? .distantPast
    )
  }

  private static func buildTask(
    _ task: ObsidianProjectTask,
    calendar: Calendar
  ) -> RetainedTask {
    if task.metadataIsDamaged { return unboundTask(task, calendar: calendar) }

    let reminderID = normalized(task.reminderExternalIdentifier)
    let taskID = reminderID.map(ReminderProjectionIdentity.taskID(for:))
    return RetainedTask(
      identity: RetainedTaskIdentity(
        taskID: taskID,
        reminderExternalIdentifier: reminderID,
        calendarEventExternalIdentifier: nil
      ),
      title: task.title,
      noteText: ObsidianReminderImportFormatting.reminderNoteText(for: task),
      isCompleted: task.isCompleted,
      schedule: buildSchedule(task.metadata, calendar: calendar),
      isManagedTask: reminderID != nil
    )
  }

  private static func buildSchedule(
    _ metadata: ObsidianTaskMetadata?,
    calendar: Calendar
  ) -> RetainedTaskSchedule {
    let rawDate = normalized(metadata?.date)
    let rawTime = normalized(metadata?.time)
    let parsedDate = parseDate(rawDate, time: rawTime, calendar: calendar)
    let repeatRule = normalized(metadata?.repeatRule)

    return RetainedTaskSchedule(
      rawDate: rawDate,
      parsedDate: parsedDate,
      hasExplicitTime: parsedDate != nil && rawTime != nil,
      rawDuration: metadata?.durationMinutes.map(String.init),
      durationMinutes: metadata?.durationMinutes.flatMap { $0 > 0 ? $0 : nil },
      rawRepeatRule: repeatRule,
      canonicalRepeatRule: canonicalRepeatRule(repeatRule)
    )
  }

  private static func canonicalRepeatRule(_ rawValue: String?) -> String? {
    guard let rawValue = normalized(rawValue) else { return nil }
    let value = rawValue.lowercased()

    if value == "daily" || value.hasPrefix("daily|") { return "daily|1" }
    if value == "weekly" || value.hasPrefix("weekly|") { return "weekly|1|" }
    if value == "monthly" || value.hasPrefix("monthly|") { return "monthly|1" }
    if value == "yearly" || value.hasPrefix("yearly|") { return "yearly|1" }
    if value == "reminder" { return "reminder" }
    return nil
  }

  private static func validateNotes(
    _ notes: [ObsidianProjectNote]
  ) throws {
    for issue in ObsidianProjectNoteValidation.issues(in: notes) {
      switch issue {
      case .duplicateReminderListExternalIdentifier(let identifier):
        throw RetainedProjectionBuilder.Error.duplicateReminderListExternalIdentifier(identifier)
      case .duplicateReminderExternalIdentifier(let identifier):
        throw RetainedProjectionBuilder.Error.duplicateReminderExternalIdentifier(identifier)
      case .damagedTaskMetadata:
        continue
      }
    }
  }

  private static func unboundTask(
    _ task: ObsidianProjectTask,
    calendar: Calendar
  ) -> RetainedTask {
    RetainedTask(
      identity: RetainedTaskIdentity(
        taskID: nil,
        reminderExternalIdentifier: nil,
        calendarEventExternalIdentifier: nil
      ),
      title: task.title,
      noteText: ObsidianReminderImportFormatting.reminderNoteText(for: task),
      isCompleted: task.isCompleted,
      schedule: buildSchedule(task.metadata, calendar: calendar),
      isManagedTask: false
    )
  }

  private static func parseDate(
    _ date: String?,
    time: String?,
    calendar: Calendar
  ) -> Date? {
    guard let dateComponents = parseDayComponents(date) else { return nil }
    let timeComponents = parseTimeComponents(time) ?? (hour: 0, minute: 0)
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = dateComponents.year
    components.month = dateComponents.month
    components.day = dateComponents.day
    components.hour = timeComponents.hour
    components.minute = timeComponents.minute
    guard let parsed = calendar.date(from: components) else { return nil }
    let validated = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)
    guard validated.year == dateComponents.year,
      validated.month == dateComponents.month,
      validated.day == dateComponents.day,
      validated.hour == timeComponents.hour,
      validated.minute == timeComponents.minute
    else {
      return nil
    }
    return parsed
  }

  private static func parseDayComponents(
    _ value: String?
  ) -> (year: Int, month: Int, day: Int)? {
    guard let value else { return nil }
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2]),
      (1...12).contains(month),
      (1...31).contains(day)
    else {
      return nil
    }
    return (year, month, day)
  }

  private static func parseTimeComponents(
    _ value: String?
  ) -> (hour: Int, minute: Int)? {
    guard let value else { return nil }
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let hour = Int(parts[0]),
      let minute = Int(parts[1]),
      (0...23).contains(hour),
      (0...59).contains(minute)
    else {
      return nil
    }
    return (hour, minute)
  }

  private static func projectTitle(from snapshot: ObsidianProjectMarkdownStore.Snapshot) -> String {
    snapshot.fileURL.deletingPathExtension().lastPathComponent
  }

  private static func snapshotSort(
    _ lhs: ObsidianProjectMarkdownStore.Snapshot,
    _ rhs: ObsidianProjectMarkdownStore.Snapshot
  ) -> Bool {
    lhs.vaultRelativePath.localizedStandardCompare(rhs.vaultRelativePath) == .orderedAscending
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
