import Foundation

struct ScheduleEventSnapshot {
  let items: [ScheduleEventModel]
  let calendarSources: [ScheduleCalendarSource]
  let accessDenied: Bool

  var itemsByID: [String: ScheduleEventModel] {
    Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
  }
}

struct WorkspaceScheduleTaskDescriptor: Hashable {
  let projectID: UUID
  let projectTitle: String
  let projectColorHex: String?
  let taskRow: TaskRowSnapshot
}

enum WorkspaceTaskScheduleEventStore {
  struct PreparationScheduleOverride: Codable, Hashable {
    let isAllDay: Bool
    let timeMinutes: Int
    let durationMinutes: Int
  }

  static let defaultScheduledDurationMinutes = 30
  static let defaultPreparationTimeMinutes = 9 * 60

  static func items(
    from tasks: [WorkspaceScheduleTaskDescriptor],
    calendar: Calendar = .autoupdatingCurrent
  ) -> [ScheduleEventModel] {
    tasks
      .flatMap { descriptor -> [ScheduleEventModel] in
        var items: [ScheduleEventModel] = []
        if let scheduledItem = makeTaskEvent(descriptor: descriptor, calendar: calendar) {
          items.append(scheduledItem)
        }
        items.append(contentsOf: makePreparationItems(descriptor: descriptor, calendar: calendar))
        return items
      }
      .sorted(by: scheduleEventSort)
  }

  static func scheduledDay(
    for task: TaskRowSnapshot,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Date? {
    guard let anchorDate = task.reminderDate else { return nil }
    return calendar.startOfDay(for: anchorDate)
  }

  static func scheduledTimeMinutes(
    for task: TaskRowSnapshot,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Int? {
    guard task.scheduleHasExplicitTime, let anchorDate = task.reminderDate else { return nil }
    let components = calendar.dateComponents([.hour, .minute], from: anchorDate)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  static func normalizedScheduledDurationMinutes(for task: TaskRowSnapshot) -> Int? {
    guard let scheduledDurationMinutes = task.scheduledDurationMinutes else { return nil }
    return max(5, scheduledDurationMinutes)
  }

  static func scheduledEndDate(
    for task: TaskRowSnapshot,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Date? {
    guard let anchorDate = task.reminderDate, task.scheduleHasExplicitTime else {
      return nil
    }
    let durationMinutes =
      normalizedScheduledDurationMinutes(for: task) ?? defaultScheduledDurationMinutes
    return calendar.date(byAdding: .minute, value: durationMinutes, to: anchorDate)
  }

  static func resolvedPreparationSchedule(
    for task: TaskRowSnapshot,
    targetCompletedUnits: Int
  ) -> PreparationScheduleOverride? {
    let normalizedRequiredWorkDays = max(0, task.requiredWorkDays)
    guard targetCompletedUnits > 0, targetCompletedUnits < normalizedRequiredWorkDays else {
      return nil
    }

    let overrides = decodedPreparationOverrides(from: task.preparationScheduleOverridesRaw)
    if let override = overrides[targetCompletedUnits] {
      return PreparationScheduleOverride(
        isAllDay: override.isAllDay,
        timeMinutes: min(max(0, override.timeMinutes), 23 * 60 + 45),
        durationMinutes: max(5, override.durationMinutes)
      )
    }

    return PreparationScheduleOverride(
      isAllDay: true,
      timeMinutes: scheduledTimeMinutes(for: task) ?? defaultPreparationTimeMinutes,
      durationMinutes: normalizedScheduledDurationMinutes(for: task) ?? defaultScheduledDurationMinutes
    )
  }

  static func isRecurring(_ task: TaskRowSnapshot) -> Bool {
    !(task.recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }

  private static func decodedPreparationOverrides(
    from raw: String
  ) -> [Int: PreparationScheduleOverride] {
    guard !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([Int: PreparationScheduleOverride].self, from: data)
    else {
      return [:]
    }

    return decoded.filter { key, _ in key > 0 }
  }

  private static func makeTaskEvent(
    descriptor: WorkspaceScheduleTaskDescriptor,
    calendar: Calendar
  ) -> ScheduleEventModel? {
    let task = descriptor.taskRow
    guard let scheduledDay = scheduledDay(for: task, calendar: calendar) else { return nil }

    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    if task.scheduleHasExplicitTime,
      let anchorDate = task.reminderDate,
      let resolvedEndDate = scheduledEndDate(for: task, calendar: calendar)
    {
      startDate = anchorDate
      endDate = max(resolvedEndDate, anchorDate)
      isAllDay = false
    } else {
      startDate = scheduledDay
      endDate = calendar.date(byAdding: .day, value: 1, to: scheduledDay) ?? scheduledDay
      isAllDay = true
    }

    return ScheduleEventModel(
      id: "workspace-task-\(task.id.uuidString)",
      source: .workspaceTask(taskID: task.id, projectID: descriptor.projectID),
      title: task.title,
      subtitle: descriptor.projectTitle,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      colorHex: descriptor.projectColorHex,
      isCompleted: task.isCompleted,
      isPreparationSlot: false,
      targetCompletedWorkUnits: nil,
      capabilities: [.reveal, .complete, .drag, .resize]
    )
  }

  private static func makePreparationItems(
    descriptor: WorkspaceScheduleTaskDescriptor,
    calendar: Calendar
  ) -> [ScheduleEventModel] {
    let task = descriptor.taskRow
    guard !task.isCompleted,
      let scheduledDay = scheduledDay(for: task, calendar: calendar)
    else {
      return []
    }

    let requiredWorkDays = max(0, task.requiredWorkDays)
    let completedWorkUnits = max(0, min(task.completedWorkUnits, requiredWorkDays))
    guard requiredWorkDays > 0, completedWorkUnits < requiredWorkDays else {
      return []
    }

    var items: [ScheduleEventModel] = []
    items.reserveCapacity(requiredWorkDays - completedWorkUnits)

    for index in completedWorkUnits..<requiredWorkDays {
      let targetCompletedUnits = index + 1
      let daysBeforeScheduledDay = requiredWorkDays - targetCompletedUnits
      guard daysBeforeScheduledDay > 0,
        let slotDay = calendar.date(byAdding: .day, value: -daysBeforeScheduledDay, to: scheduledDay),
        let slotSchedule = resolvedPreparationSchedule(
          for: task,
          targetCompletedUnits: targetCompletedUnits
        )
      else {
        continue
      }

      let startDate: Date
      let endDate: Date
      if slotSchedule.isAllDay {
        startDate = slotDay
        endDate = calendar.date(byAdding: .day, value: 1, to: slotDay) ?? slotDay
      } else {
        guard let slotDate = calendar.date(
          bySettingHour: slotSchedule.timeMinutes / 60,
          minute: slotSchedule.timeMinutes % 60,
          second: 0,
          of: slotDay
        ) else {
          continue
        }

        startDate = slotDate
        endDate = calendar.date(byAdding: .minute, value: slotSchedule.durationMinutes, to: slotDate)
          ?? slotDate
      }

      items.append(
        ScheduleEventModel(
          id: "workspace-task-\(task.id.uuidString)-prep-\(targetCompletedUnits)",
          source: .workspaceTask(taskID: task.id, projectID: descriptor.projectID),
          title: task.title,
          subtitle: descriptor.projectTitle,
          startDate: startDate,
          endDate: endDate,
          isAllDay: slotSchedule.isAllDay,
          colorHex: descriptor.projectColorHex,
          isCompleted: false,
          isPreparationSlot: true,
          targetCompletedWorkUnits: targetCompletedUnits,
          capabilities: [.reveal, .complete, .drag, .resize]
        )
      )
    }

    return items
  }

  private static func scheduleEventSort(_ lhs: ScheduleEventModel, _ rhs: ScheduleEventModel) -> Bool {
    if lhs.startDate != rhs.startDate {
      return lhs.startDate < rhs.startDate
    }
    if lhs.endDate != rhs.endDate {
      return lhs.endDate < rhs.endDate
    }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }
}

enum CalendarScheduleEventStore {
  static func items(from events: [ScheduleCalendarEvent]) -> [ScheduleEventModel] {
    events.map { event in
      var capabilities: ScheduleEventCapabilities = []
      if event.revealIdentifier != nil {
        capabilities.insert(.reveal)
      }
      if event.canEditTiming {
        capabilities.insert(.drag)
        if !event.isAllDay {
          capabilities.insert(.resize)
        }
      }

      return ScheduleEventModel(
        id: "calendar-\(event.id)",
        source: .calendarEvent(eventID: event.id),
        title: event.title,
        subtitle: event.calendarTitle,
        startDate: event.startDate,
        endDate: event.endDate,
        isAllDay: event.isAllDay,
        colorHex: event.calendarColorHex,
        isCompleted: false,
        isPreparationSlot: false,
        targetCompletedWorkUnits: nil,
        capabilities: capabilities
      )
    }
    .sorted { lhs, rhs in
      if lhs.startDate != rhs.startDate {
        return lhs.startDate < rhs.startDate
      }
      if lhs.endDate != rhs.endDate {
        return lhs.endDate < rhs.endDate
      }
      return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
  }
}

enum UnifiedScheduleEventStore {
  static func snapshot(
    workspaceTasks: [WorkspaceScheduleTaskDescriptor],
    calendarEvents: [ScheduleCalendarEvent],
    calendarSources: [ScheduleCalendarSource],
    accessDenied: Bool,
    calendar: Calendar = .autoupdatingCurrent
  ) -> ScheduleEventSnapshot {
    let workspaceTaskItems = WorkspaceTaskScheduleEventStore.items(
      from: workspaceTasks,
      calendar: calendar
    )
    let overlayItems = CalendarScheduleEventStore.items(from: calendarEvents)

    return ScheduleEventSnapshot(
      items: workspaceTaskItems + overlayItems,
      calendarSources: calendarSources,
      accessDenied: accessDenied
    )
  }
}
