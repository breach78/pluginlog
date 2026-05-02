import Foundation

struct ScheduleCalendarOverlayProjection: Equatable, Sendable {
  let calendarSources: [ScheduleCalendarSource]
  let foregroundEvents: [ScheduleCalendarEvent]
  let backgroundEvents: [ScheduleCalendarEvent]
  let calendarsSignature: Int
  let visibleEventsSignature: Int
  let accessDenied: Bool

  static let empty = ScheduleCalendarOverlayProjection(
    calendarSources: [],
    foregroundEvents: [],
    backgroundEvents: [],
    calendarsSignature: 0,
    visibleEventsSignature: 0,
    accessDenied: false
  )

  var events: [ScheduleCalendarEvent] {
    foregroundEvents + backgroundEvents
  }
}

struct WorkspaceProjectRuntimeRecord: Equatable, Sendable, Identifiable {
  let id: UUID
  let title: String
  let colorHex: String?
  let reminderListIdentifier: String?
  let reminderListExternalIdentifier: String?
  let projectNoteMarkdown: String
  let localStartDate: Date?
  let localDeadline: Date?
  let progressStageRaw: String?
  let boardOrder: Int?
  let createdAt: Date
  let updatedAt: Date
  let isArchived: Bool
}

struct ProjectSummaryRecord: Equatable, Sendable {
  let openRootTaskCount: Int
  let completedRootTaskCount: Int
  let undatedOpenRootTaskCount: Int
  let overdueOpenRootTaskCount: Int
  let todayTaskCount: Int
  let nextUpcomingDate: Date?
  let deadline: Date?
  let stageRaw: String
  let progress: Double
  let latestTaskUpdatedAt: Date?
  let title: String
  let colorHex: String?
  let isArchived: Bool
}

struct ScheduleSliceEntry: Identifiable, Equatable, Sendable {
  var id: UUID { taskID }
  let taskID: UUID
  let parentTaskID: UUID?
  let title: String
  let displayedDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let scheduleHasExplicitTime: Bool
  let scheduledDurationMinutes: Int?
  let isCompleted: Bool
  let completionDate: Date?
  let recurrenceRuleRaw: String?
  let attachmentCount: Int
  let reminderNoteText: String
  let requiredWorkDays: Int
  let completedWorkUnits: Int
  let completedWorkUnitDates: [Date]
  let preparationScheduleOverridesRaw: String
  let rowOrder: Int
  let priority: Int
  let isFlagged: Bool
  let isArchived: Bool
  let localUpdatedAt: Date
  let createdAt: Date

  var renderFingerprint: Int {
    var hasher = Hasher()
    hasher.combine(taskID)
    hasher.combine(title)
    hasher.combine(displayedDate)
    hasher.combine(isCompleted)
    hasher.combine(scheduledDurationMinutes)
    hasher.combine(attachmentCount)
    hasher.combine(reminderNoteText)
    hasher.combine(rowOrder)
    return hasher.finalize()
  }
}

struct ReminderWorkspaceSurfaceProjection: Equatable, Sendable {
  let projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord]
  let projectSummaries: [UUID: ProjectSummaryRecord]
  let scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]

  static let empty = ReminderWorkspaceSurfaceProjection(
    projectSnapshots: [:],
    projectSummaries: [:],
    scheduleEntriesByProjectID: [:]
  )
}

struct TaskRowSnapshot: Identifiable, Hashable, Sendable {
  let id: UUID
  let title: String
  let reminderDate: Date?
  let scheduleHasExplicitTime: Bool
  let scheduledDurationMinutes: Int?
  let isCompleted: Bool
  let completionDate: Date?
  let recurrenceRuleRaw: String?
  let attachmentCount: Int
  let reminderNoteText: String
  let requiredWorkDays: Int
  let completedWorkUnits: Int
  let completedWorkUnitDates: [Date]
  let preparationScheduleOverridesRaw: String
  let rowOrder: Int
  let createdAt: Date
  let isArchived: Bool
}

struct TimelineProjectTaskPreview: Identifiable, Equatable, Sendable {
  let id: String
  let taskID: UUID
  let title: String
  let isCompleted: Bool
  let isOverdue: Bool
  let targetCompletedWorkUnits: Int

  var targetCompletedUnits: Int { targetCompletedWorkUnits }
}

struct TimelineDayPreview: Equatable, Sendable {
  let totalCount: Int
  let tasks: [TimelineProjectTaskPreview]
}

struct TimelineWorkDayPreview: Equatable, Sendable {
  let totalCount: Int
  let tasks: [TimelineProjectTaskPreview]
}

struct TimelineProjectBar: Identifiable, Equatable, Sendable {
  var id: UUID { projectID }
  let projectID: UUID
  let title: String
  let colorHex: String?
  let start: Date?
  let end: Date?
  let deadline: Date?
  let nextUpcomingDate: Date?
  let progress: Double
  let remainingTaskCount: Int
  let undatedRemainingTaskCount: Int
  let dailyTaskCounts: [Date: Int]
  let dailyCompletedTaskCounts: [Date: Int]
  let dailyPlannedWorkCounts: [Date: Int]
  let dailyTaskPreviews: [Date: TimelineDayPreview]
  let dailyCompletedTaskPreviews: [Date: TimelineDayPreview]
  let dailyPlannedWorkPreviews: [Date: TimelineWorkDayPreview]
  let projectReference: WorkspaceProjectReference
}

protocol TimelineService: AnyObject {}

final class DefaultTimelineService: TimelineService {}

enum TimelineProjectionService {
  static func runtimeBars(
    service: TimelineService,
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    projectSummariesByID: [UUID: ProjectSummaryRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> [TimelineProjectBar] {
    _ = service
    var bars: [TimelineProjectBar] = []
    let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    for projectID in projectIDs {
      guard let project = projectSnapshots[projectID] else { continue }
      guard !project.isArchived else { continue }
      let summary = projectSummariesByID[projectID]
      let entries = scheduleEntriesByProjectID[projectID] ?? []
      let datedEntries = entries.compactMap { entry -> (ScheduleSliceEntry, Date)? in
        guard let date = entry.displayedDate ?? entry.dueDate ?? entry.startDate else { return nil }
        return (entry, Calendar.autoupdatingCurrent.startOfDay(for: date))
      }
      let datedDays = datedEntries.map(\.1)
      let explicitStart = project.localStartDate.map {
        Calendar.autoupdatingCurrent.startOfDay(for: $0)
      }
      let explicitDeadline = project.localDeadline.map {
        Calendar.autoupdatingCurrent.startOfDay(for: $0)
      }
      let barStart = explicitStart ?? datedDays.min()
      let lastDatedDay = datedDays.max()
      let barEnd = [lastDatedDay, explicitDeadline].compactMap { $0 }.max()
      let stage = ProjectProgressStage.fromStorageValue(project.progressStageRaw)
        ?? ProjectProgressStage.do
      var dailyTaskCounts: [Date: Int] = [:]
      var dailyCompletedTaskCounts: [Date: Int] = [:]
      var taskPreviews: [Date: [TimelineProjectTaskPreview]] = [:]
      var completedPreviews: [Date: [TimelineProjectTaskPreview]] = [:]
      for (entry, day) in datedEntries {
        let preview = TimelineProjectTaskPreview(
          id: "\(entry.taskID.uuidString)-\(day.timeIntervalSinceReferenceDate)",
          taskID: entry.taskID,
          title: entry.title,
          isCompleted: entry.isCompleted,
          isOverdue: !entry.isCompleted && day < today,
          targetCompletedWorkUnits: 0
        )
        if entry.isCompleted {
          dailyCompletedTaskCounts[day, default: 0] += 1
          completedPreviews[day, default: []].append(preview)
        } else {
          dailyTaskCounts[day, default: 0] += 1
          taskPreviews[day, default: []].append(preview)
        }
      }
      let normalizedTaskPreviews = taskPreviews.mapValues {
        TimelineDayPreview(totalCount: $0.count, tasks: $0)
      }
      let normalizedCompletedPreviews = completedPreviews.mapValues {
        TimelineDayPreview(totalCount: $0.count, tasks: $0)
      }
      bars.append(TimelineProjectBar(
        projectID: projectID,
        title: project.title,
        colorHex: project.colorHex,
        start: barStart,
        end: barEnd,
        deadline: explicitDeadline ?? summary?.deadline,
        nextUpcomingDate: summary?.nextUpcomingDate,
        progress: summary?.progress ?? stage.progressValue,
        remainingTaskCount: summary?.openRootTaskCount ?? entries.filter { !$0.isCompleted }.count,
        undatedRemainingTaskCount: summary?.undatedOpenRootTaskCount ?? 0,
        dailyTaskCounts: dailyTaskCounts,
        dailyCompletedTaskCounts: dailyCompletedTaskCounts,
        dailyPlannedWorkCounts: [:],
        dailyTaskPreviews: normalizedTaskPreviews,
        dailyCompletedTaskPreviews: normalizedCompletedPreviews,
        dailyPlannedWorkPreviews: [:],
        projectReference: .project(projectID)
      ))
    }
    return bars
  }
}

enum ScheduleProjectionService {
  static func taskDescriptors(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> [WorkspaceScheduleTaskDescriptor] {
    projectIDs.flatMap { projectID -> [WorkspaceScheduleTaskDescriptor] in
      guard let project = projectSnapshots[projectID] else { return [] }
      guard !project.isArchived else { return [] }
      return (scheduleEntriesByProjectID[projectID] ?? []).map { entry in
        WorkspaceScheduleTaskDescriptor(
          projectID: projectID,
          projectTitle: project.title,
          projectColorHex: project.colorHex,
          taskRow: TaskRowSnapshot(
            id: entry.taskID,
            title: entry.title,
            reminderDate: entry.displayedDate ?? entry.dueDate ?? entry.startDate,
            scheduleHasExplicitTime: entry.scheduleHasExplicitTime,
            scheduledDurationMinutes: entry.scheduledDurationMinutes,
            isCompleted: entry.isCompleted,
            completionDate: entry.completionDate,
            recurrenceRuleRaw: entry.recurrenceRuleRaw,
            attachmentCount: entry.attachmentCount,
            reminderNoteText: entry.reminderNoteText,
            requiredWorkDays: entry.requiredWorkDays,
            completedWorkUnits: entry.completedWorkUnits,
            completedWorkUnitDates: entry.completedWorkUnitDates,
            preparationScheduleOverridesRaw: entry.preparationScheduleOverridesRaw,
            rowOrder: entry.rowOrder,
            createdAt: entry.createdAt,
            isArchived: entry.isArchived
          )
        )
      }
    }
  }

  static func buildTaskSnapshot(
    taskDescriptors: [WorkspaceScheduleTaskDescriptor],
    sourceSignature: Int
  ) -> ScheduleTaskSnapshotCache {
    var hasher = Hasher()
    hasher.combine(sourceSignature)
    hasher.combine(taskDescriptors.count)
    for descriptor in taskDescriptors {
      hasher.combine(descriptor.projectID)
      hasher.combine(descriptor.taskRow)
    }
    return ScheduleTaskSnapshotCache(
      sourceSignature: sourceSignature,
      taskDescriptors: taskDescriptors,
      workspaceTasksByID: Dictionary(uniqueKeysWithValues: taskDescriptors.map {
        ($0.taskRow.id, $0)
      }),
      signature: hasher.finalize()
    )
  }
}
