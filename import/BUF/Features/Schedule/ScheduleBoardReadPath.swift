import AppKit
import SwiftUI

enum ScheduleBoardReadPath {
  struct QuickAddState: Equatable {
    let options: [ScheduleQuickAddProjectOption]
    let defaultProjectID: UUID?
  }

  static func deduplicatedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return projectIDs.filter { seen.insert($0).inserted }
  }

  static func normalizedProjectIDs(
    projectIDs: [UUID]
  ) -> [UUID] {
    deduplicatedProjectIDs(projectIDs)
  }

  static func orderedProjectDetails(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord]
  ) -> [WorkspaceProjectRuntimeRecord] {
    deduplicatedProjectIDs(projectIDs)
      .compactMap { projectSnapshots[$0] }
      .filter { !$0.isArchived }
  }

  static func workspaceTaskDescriptors(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> [WorkspaceScheduleTaskDescriptor] {
    ScheduleProjectionService.taskDescriptors(
      projectIDs: projectIDs,
      projectSnapshots: projectSnapshots,
      scheduleEntriesByProjectID: scheduleEntriesByProjectID
    )
  }

  static func scheduleDay(
    for task: TaskRowSnapshot,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Date? {
    guard let anchorDate = task.reminderDate else { return nil }
    return calendar.startOfDay(for: anchorDate)
  }

  static func shouldRetainCompletedWorkspaceTask(
    _ task: TaskRowSnapshot,
    today: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Bool {
    guard let scheduledDay = scheduleDay(for: task, calendar: calendar) else { return false }
    return scheduledDay >= today
  }

  static func shouldDisplayWorkspaceTask(
    _ task: TaskRowSnapshot,
    today: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Bool {
    guard !task.isArchived, scheduleDay(for: task, calendar: calendar) != nil else {
      return false
    }
    guard task.isCompleted else { return true }
    return shouldRetainCompletedWorkspaceTask(task, today: today, calendar: calendar)
  }

  static func quickAddState(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    selectedProjectID: UUID?,
    appSelectedProjectID: UUID?,
    defaultReminderCalendarIdentifier: String?
  ) -> QuickAddState {
    let projects = orderedProjectDetails(projectIDs: projectIDs, projectSnapshots: projectSnapshots)
    let options = projects.map { project in
      ScheduleQuickAddProjectOption(
        id: project.id,
        title: project.title
      )
    }

    let defaultProjectID: UUID?
    if let defaultReminderCalendarIdentifier,
      let matchingDefault = projects.first(where: {
        $0.reminderListIdentifier == defaultReminderCalendarIdentifier
      })
    {
      defaultProjectID = matchingDefault.id
    } else if let selectedProjectID,
      options.contains(where: { $0.id == selectedProjectID })
    {
      defaultProjectID = selectedProjectID
    } else if let appSelectedProjectID,
      options.contains(where: { $0.id == appSelectedProjectID })
    {
      defaultProjectID = appSelectedProjectID
    } else {
      defaultProjectID = options.first?.id
    }

    return QuickAddState(options: options, defaultProjectID: defaultProjectID)
  }

  static func sourceSignature(
    today: Date,
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(today.timeIntervalSinceReferenceDate)
    for project in orderedProjectDetails(projectIDs: projectIDs, projectSnapshots: projectSnapshots) {
      hasher.combine(project.id)
      hasher.combine(project.updatedAt.timeIntervalSinceReferenceDate)
      hasher.combine(project.title)
      hasher.combine(project.colorHex)
      hasher.combine(project.reminderListIdentifier)
      hasher.combine(project.reminderListExternalIdentifier)
      let scheduleEntries = scheduleEntriesByProjectID[project.id] ?? []
      hasher.combine(scheduleEntries.count)
      for entry in scheduleEntries {
        hasher.combine(entry.taskID)
        hasher.combine(entry.scheduleRenderFingerprint)
      }
    }
    return hasher.finalize()
  }
}

struct ScheduleTaskCompletionState: Equatable {
  let isCompleted: Bool
  let completionDate: Date?
  let isRecurring: Bool
  let occurrenceDate: Date?
  let editFields: RetainedTaskEditFields
}
