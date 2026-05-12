import AppKit
import SwiftUI

extension ScheduleBoardView {
  func timeMinutes(for date: Date) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  func durationMinutes(for event: ScheduleCalendarEvent) -> Int {
    max(timedMinimumDuration, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
  }

  func scheduleDay(for task: TaskRowSnapshot) -> Date? {
    ScheduleBoardReadPath.scheduleDay(for: task, calendar: calendar)
  }

  func shouldDisplayScheduledWorkspaceTask(_ task: TaskRowSnapshot) -> Bool {
    ScheduleBoardReadPath.shouldDisplayWorkspaceTask(task, today: today, calendar: calendar)
  }

  func shouldRetainCompletedScheduleWorkspaceTask(_ task: TaskRowSnapshot) -> Bool {
    ScheduleBoardReadPath.shouldRetainCompletedWorkspaceTask(
      task,
      today: today,
      calendar: calendar
    )
  }

  var shouldSuppressHistoryRecording: Bool {
    appState.isUndoRedoInFlight || undoManager?.isUndoing == true || undoManager?.isRedoing == true
  }

  func scheduleTaskDescriptor(for taskID: UUID) -> WorkspaceScheduleTaskDescriptor? {
    if let cached = cachedWorkspaceScheduleTasksByID[taskID] {
      return scheduleTaskDescriptorApplyingOptimisticSchedule(cached)
    }
    guard let descriptor = resolvedScheduleTaskSnapshot(preferCached: true).workspaceTasksByID[taskID]
    else {
      return nil
    }
    return scheduleTaskDescriptorApplyingOptimisticSchedule(descriptor)
  }

  func effectiveScheduleTaskIsCompleted(_ taskRow: TaskRowSnapshot) -> Bool {
    optimisticScheduleTaskCompletionByID[taskRow.id] ?? taskRow.isCompleted
  }

  func optimisticScheduleTaskScheduleState(
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) -> OptimisticScheduleTaskScheduleState {
    let normalizedDay = day.map { calendar.startOfDay(for: $0) }
    return OptimisticScheduleTaskScheduleState(
      day: normalizedDay,
      timeMinutes: normalizedDay == nil ? nil : timeMinutes,
      durationMinutes: normalizedDay == nil || timeMinutes == nil ? nil : durationMinutes
    )
  }

  func scheduleTaskSourceSignatureApplyingOptimisticSchedule(baseSignature: Int) -> Int {
    guard !optimisticScheduleTaskScheduleByID.isEmpty else { return baseSignature }
    var hasher = Hasher()
    hasher.combine(baseSignature)
    for taskID in optimisticScheduleTaskScheduleByID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard let schedule = optimisticScheduleTaskScheduleByID[taskID] else { continue }
      hasher.combine(taskID)
      hasher.combine(schedule.day)
      hasher.combine(schedule.timeMinutes)
      hasher.combine(schedule.durationMinutes)
    }
    return hasher.finalize()
  }

  func scheduleTaskDescriptorsApplyingOptimisticSchedule(
    _ descriptors: [WorkspaceScheduleTaskDescriptor]
  ) -> [WorkspaceScheduleTaskDescriptor] {
    guard !optimisticScheduleTaskScheduleByID.isEmpty else { return descriptors }
    return descriptors.map(scheduleTaskDescriptorApplyingOptimisticSchedule)
  }

  func scheduleTaskDescriptorApplyingOptimisticSchedule(
    _ descriptor: WorkspaceScheduleTaskDescriptor
  ) -> WorkspaceScheduleTaskDescriptor {
    guard let schedule = optimisticScheduleTaskScheduleByID[descriptor.taskRow.id] else {
      return descriptor
    }
    return WorkspaceScheduleTaskDescriptor(
      projectID: descriptor.projectID,
      projectTitle: descriptor.projectTitle,
      projectColorHex: descriptor.projectColorHex,
      taskRow: taskRow(descriptor.taskRow, applying: schedule)
    )
  }

  func taskRow(
    _ taskRow: TaskRowSnapshot,
    applying schedule: OptimisticScheduleTaskScheduleState
  ) -> TaskRowSnapshot {
    TaskRowSnapshot(
      id: taskRow.id,
      title: taskRow.title,
      reminderDate: schedule.day.map { scheduleDate(day: $0, timeMinutes: schedule.timeMinutes) },
      scheduleHasExplicitTime: schedule.day != nil && schedule.timeMinutes != nil,
      scheduledDurationMinutes: schedule.timeMinutes == nil ? nil : schedule.durationMinutes,
      isCompleted: taskRow.isCompleted,
      completionDate: taskRow.completionDate,
      recurrenceRuleRaw: taskRow.recurrenceRuleRaw,
      isLocalCompletedRecurringOccurrence: taskRow.isLocalCompletedRecurringOccurrence,
      attachmentCount: taskRow.attachmentCount,
      hasReminderNoteContent: taskRow.hasReminderNoteContent,
      reminderNoteText: taskRow.reminderNoteText,
      requiredWorkDays: taskRow.requiredWorkDays,
      completedWorkUnits: taskRow.completedWorkUnits,
      completedWorkUnitDates: taskRow.completedWorkUnitDates,
      preparationScheduleOverridesRaw: taskRow.preparationScheduleOverridesRaw,
      rowOrder: taskRow.rowOrder,
      createdAt: taskRow.createdAt,
      isArchived: taskRow.isArchived
    )
  }

  func clearOptimisticScheduleTaskSchedule(
    taskID: UUID,
    expectedSchedule: OptimisticScheduleTaskScheduleState
  ) {
    guard optimisticScheduleTaskScheduleByID[taskID] == expectedSchedule else { return }
    optimisticScheduleTaskScheduleByID.removeValue(forKey: taskID)
  }

  func restoreOptimisticScheduleTaskSchedule(
    taskID: UUID,
    expectedCurrentSchedule: OptimisticScheduleTaskScheduleState,
    previousSchedule: OptimisticScheduleTaskScheduleState?
  ) {
    guard optimisticScheduleTaskScheduleByID[taskID] == expectedCurrentSchedule else { return }
    if let previousSchedule {
      optimisticScheduleTaskScheduleByID[taskID] = previousSchedule
    } else {
      optimisticScheduleTaskScheduleByID.removeValue(forKey: taskID)
    }
  }

  func scheduleMonthItemsApplyingOptimisticTaskCompletion(
    _ items: [ScheduleMonthItem]
  ) -> [ScheduleMonthItem] {
    guard !optimisticScheduleTaskCompletionByID.isEmpty else { return items }
    return items.map { item in
      guard case .workspaceTask(let taskID, _) = item.source,
        let isCompleted = optimisticScheduleTaskCompletionByID[taskID],
        item.isCompleted != isCompleted
      else {
        return item
      }
      return ScheduleMonthItem(
        id: item.id,
        source: item.source,
        title: item.title,
        subtitle: item.subtitle,
        startDate: item.startDate,
        endDate: item.endDate,
        isAllDay: item.isAllDay,
        colorHex: item.colorHex,
        isCompleted: isCompleted,
        isPreparationSlot: item.isPreparationSlot,
        isBackgroundCalendar: item.isBackgroundCalendar,
        calendarEvent: item.calendarEvent
      )
    }
  }

  func scheduleMonthItemsSignature(
    baseSignature: Int,
    items: [ScheduleMonthItem]
  ) -> Int {
    guard !optimisticScheduleTaskCompletionByID.isEmpty else { return baseSignature }
    var hasher = Hasher()
    hasher.combine(baseSignature)
    var didIncludeOptimisticValue = false
    for item in items {
      guard case .workspaceTask(let taskID, _) = item.source,
        let isCompleted = optimisticScheduleTaskCompletionByID[taskID]
      else {
        continue
      }
      didIncludeOptimisticValue = true
      hasher.combine(taskID)
      hasher.combine(isCompleted)
    }
    guard didIncludeOptimisticValue else { return baseSignature }
    return hasher.finalize()
  }

  func clearOptimisticScheduleTaskCompletion(taskID: UUID, expectedIsCompleted: Bool) {
    guard optimisticScheduleTaskCompletionByID[taskID] == expectedIsCompleted else { return }
    optimisticScheduleTaskCompletionByID.removeValue(forKey: taskID)
  }

  func restoreOptimisticScheduleTaskCompletion(
    taskID: UUID,
    expectedCurrentValue: Bool,
    previousValue: Bool?
  ) {
    guard optimisticScheduleTaskCompletionByID[taskID] == expectedCurrentValue else { return }
    if let previousValue {
      optimisticScheduleTaskCompletionByID[taskID] = previousValue
    } else {
      optimisticScheduleTaskCompletionByID.removeValue(forKey: taskID)
    }
  }

  func scheduleCompletionState(for taskRow: TaskRowSnapshot) -> ScheduleTaskCompletionState {
    ScheduleTaskCompletionState(
      isCompleted: taskRow.isCompleted,
      completionDate: taskRow.completionDate,
      isRecurring: WorkspaceTaskScheduleEventStore.isRecurring(taskRow),
      occurrenceDate: taskRow.reminderDate,
      editFields: scheduleTaskEditFields(for: taskRow)
    )
  }

  func scheduleDate(day: Date, timeMinutes: Int?) -> Date {
    let normalizedDay = calendar.startOfDay(for: day)
    guard let timeMinutes else { return normalizedDay }
    let boundedMinutes = min(max(0, timeMinutes), 23 * 60 + 59)
    let hours = boundedMinutes / 60
    let minutes = boundedMinutes % 60
    return calendar.date(bySettingHour: hours, minute: minutes, second: 0, of: normalizedDay)
      ?? normalizedDay
  }
}
