import Foundation

enum WorkspaceTaskRowSemantics {
  static func rootRows(from taskRows: [TaskRowSnapshot]) -> [TaskRowSnapshot] {
    let rowIDs = Set(taskRows.map(\.id))
    return taskRows.filter { row in
      guard let parentTaskID = row.parentTaskID else { return true }
      return !rowIDs.contains(parentTaskID)
    }
  }

  static func rootTaskCounts(from taskRows: [TaskRowSnapshot]) -> (remaining: Int, completed: Int) {
    rootRows(from: taskRows).reduce(into: (0, 0)) { counts, row in
      if row.isCompleted {
        counts.1 += 1
      } else {
        counts.0 += 1
      }
    }
  }
}

struct TimelineTaskPreview: Identifiable {
  let id: String
  let taskID: UUID
  let title: String
  let isOverdue: Bool
}

struct TimelineWorkPreview: Identifiable {
  let id: String
  let taskID: UUID
  let title: String
  let targetCompletedUnits: Int
}

struct TimelineDayPreview {
  let totalCount: Int
  let tasks: [TimelineTaskPreview]
}

struct TimelineWorkDayPreview {
  let totalCount: Int
  let tasks: [TimelineWorkPreview]
}

struct TimelineProjectBar: Identifiable {
  let id: UUID
  let projectReference: WorkspaceProjectReference
  let reminderListIdentifier: String?
  let reminderListExternalIdentifier: String?
  let title: String
  let colorHex: String?
  let start: Date?
  let end: Date?
  let deadline: Date?
  let progress: Double
  let remainingTaskCount: Int
  let undatedRemainingTaskCount: Int
  let dailyTaskCounts: [Date: Int]
  let dailyTaskPreviews: [Date: TimelineDayPreview]
  let dailyPlannedWorkCounts: [Date: Int]
  let dailyPlannedWorkPreviews: [Date: TimelineWorkDayPreview]
  let dailyCompletedTaskCounts: [Date: Int]
  let dailyCompletedTaskPreviews: [Date: TimelineDayPreview]
  let nextUpcomingDate: Date?

  var projectID: UUID {
    projectReference.id
  }
}

struct TimelineTaskSource: Hashable {
  let id: UUID
  let title: String
  let isCompleted: Bool
  let completionDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let scheduleHasExplicitTime: Bool
  let scheduledDurationMinutes: Int?
  let priority: Int
  let recurrenceRuleRaw: String?
  let rowOrder: Int
  let requiredWorkDays: Int
  let completedWorkUnits: Int
  let completedWorkUnitDates: [Date]
  let localUpdatedAt: Date
  let createdAt: Date
}

struct TimelineProjectSource {
  let reference: WorkspaceProjectReference
  let reminderListIdentifier: String?
  let reminderListExternalIdentifier: String?
  let title: String
  let colorHex: String?
  let deadline: Date?
  let progress: Double
  let isArchived: Bool
  let summary: ProjectSummaryRecord?
  let tasks: [TimelineTaskSource]
}

protocol TimelineService: AnyObject {
  /// Builds the per-project timeline model consumed by the board view.
  func buildTimeline(projectDetails: [ProjectDetailSnapshot]) -> [TimelineProjectBar]
  func buildTimeline(
    projectDetails: [ProjectDetailSnapshot],
    projectSummariesByID: [UUID: ProjectSummaryRecord]
  ) -> [TimelineProjectBar]
  func buildTimeline(projectSources: [TimelineProjectSource]) -> [TimelineProjectBar]
}

final class DefaultTimelineService: TimelineService {
  private struct CacheEntry {
    let key: Int
    let bars: [TimelineProjectBar]
  }

  private let maxPreviewTasksPerDay = 6
  private let cacheLock = NSLock()
  private var cacheEntry: CacheEntry?

  func buildTimeline(projectDetails: [ProjectDetailSnapshot]) -> [TimelineProjectBar] {
    buildTimeline(projectDetails: projectDetails, projectSummariesByID: [:])
  }

  func buildTimeline(
    projectDetails: [ProjectDetailSnapshot],
    projectSummariesByID: [UUID: ProjectSummaryRecord]
  ) -> [TimelineProjectBar] {
    let sources = projectDetails.map { detail in
      let projectID = detail.node.projectID ?? detail.node.id
      return makeWorkspaceProjectSource(detail, summary: projectSummariesByID[projectID])
    }
    return buildTimeline(projectSources: sources)
  }

  func buildTimeline(projectSources sources: [TimelineProjectSource]) -> [TimelineProjectBar] {
    let cacheKey = timelineCacheKey(for: sources)
    if let cached = cachedBars(for: cacheKey) {
      return cached
    }

    var bars: [TimelineProjectBar] = []
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: .now)

    for project in sources where !project.isArchived {
      let summary = project.summary
      let activeTasks = project.tasks
        .filter { !$0.isCompleted }
        .sorted(by: taskPreviewSort)
      var undatedRemainingTaskCount = 0
      var candidateDates: [Date] = []
      candidateDates.reserveCapacity(activeTasks.count * 2)
      var dailyCounts: [Date: Int] = [:]
      var dailyPreviews: [Date: TimelineDayPreview] = [:]
      var dailyPlannedCounts: [Date: Int] = [:]
      var dailyPlannedPreviews: [Date: TimelineWorkDayPreview] = [:]
      var dailyCompletedCounts: [Date: Int] = [:]
      var dailyCompletedPreviews: [Date: TimelineDayPreview] = [:]
      var upcomingDates: [Date] = []

      for task in activeTasks {
        let displayDate = ReminderTaskDateCanonicalizer.unifiedDate(
          dueDate: task.dueDate,
          startDate: task.startDate
        )
        if let displayDate {
          let day = calendar.startOfDay(for: displayDate)
          let isOverdue = day < today
          candidateDates.append(day)
          if day >= today {
            upcomingDates.append(day)
          }
          dailyCounts[day, default: 0] += 1
          let existingPreview = dailyPreviews[day] ?? TimelineDayPreview(totalCount: 0, tasks: [])
          let previewTasks =
            existingPreview.tasks.count < maxPreviewTasksPerDay
            ? existingPreview.tasks + [
              TimelineTaskPreview(
                id: "task-\(task.id.uuidString)",
                taskID: task.id,
                title: task.title,
                isOverdue: isOverdue
              )
            ]
            : existingPreview.tasks
          dailyPreviews[day] = TimelineDayPreview(
            totalCount: existingPreview.totalCount + 1,
            tasks: previewTasks
          )
        } else {
          undatedRemainingTaskCount += 1
        }

        for slot in plannedWorkSlots(for: task, calendar: calendar) {
          candidateDates.append(slot.date)
          if slot.date >= today {
            upcomingDates.append(slot.date)
          }
          dailyPlannedCounts[slot.date, default: 0] += 1
          let existingPreview =
            dailyPlannedPreviews[slot.date] ?? TimelineWorkDayPreview(totalCount: 0, tasks: [])
          let previewTasks =
            existingPreview.tasks.count < maxPreviewTasksPerDay
            ? existingPreview.tasks + [
              TimelineWorkPreview(
                id: "\(task.id.uuidString)-\(slot.targetCompletedUnits)",
                taskID: task.id,
                title: task.title,
                targetCompletedUnits: slot.targetCompletedUnits
              )
            ]
            : existingPreview.tasks
          dailyPlannedPreviews[slot.date] = TimelineWorkDayPreview(
            totalCount: existingPreview.totalCount + 1,
            tasks: previewTasks
          )
        }
      }

      for task in project.tasks {
        for (index, completedDay) in plannedWorkCompletionDays(for: task, calendar: calendar).enumerated() {
          candidateDates.append(completedDay)
          dailyCompletedCounts[completedDay, default: 0] += 1
          let existingPreview = dailyCompletedPreviews[completedDay] ?? TimelineDayPreview(
            totalCount: 0,
            tasks: []
          )
          let previewTasks =
            existingPreview.tasks.count < maxPreviewTasksPerDay
            ? existingPreview.tasks + [
              TimelineTaskPreview(
                id: "planned-\(task.id.uuidString)-\(index)",
                taskID: task.id,
                title: task.title,
                isOverdue: false
              )
            ]
            : existingPreview.tasks
          dailyCompletedPreviews[completedDay] = TimelineDayPreview(
            totalCount: existingPreview.totalCount + 1,
            tasks: previewTasks
          )
        }

        guard shouldIncludeCompletedTask(task),
          let completedDay = completionDay(for: task, calendar: calendar)
        else {
          continue
        }

        candidateDates.append(completedDay)
        dailyCompletedCounts[completedDay, default: 0] += 1
        let existingPreview = dailyCompletedPreviews[completedDay] ?? TimelineDayPreview(
          totalCount: 0,
          tasks: []
        )
        let previewTasks =
          existingPreview.tasks.count < maxPreviewTasksPerDay
          ? existingPreview.tasks + [
            TimelineTaskPreview(
              id: "completed-\(task.id.uuidString)",
              taskID: task.id,
              title: task.title,
              isOverdue: false
            )
          ]
          : existingPreview.tasks
        dailyCompletedPreviews[completedDay] = TimelineDayPreview(
          totalCount: existingPreview.totalCount + 1,
          tasks: previewTasks
        )
      }

      let inferredStart = candidateDates.min()
      let inferredEnd = candidateDates.max()
      let normalizedDeadline = (summary?.deadline ?? project.deadline).map {
        calendar.startOfDay(for: $0)
      }
      let start: Date?
      let end: Date?
      if let normalizedDeadline {
        if let inferredStart {
          start = min(inferredStart, normalizedDeadline)
          if let inferredEnd {
            end = max(inferredEnd, normalizedDeadline)
          } else {
            end = normalizedDeadline
          }
        } else {
          start = normalizedDeadline
          end = normalizedDeadline
        }
      } else {
        start = inferredStart
        end = inferredEnd
      }

      bars.append(
        TimelineProjectBar(
          id: project.reference.id,
          projectReference: project.reference,
          reminderListIdentifier: project.reminderListIdentifier,
          reminderListExternalIdentifier: project.reminderListExternalIdentifier,
          title: project.title,
          colorHex: project.colorHex,
          start: start,
          end: end,
          deadline: normalizedDeadline,
          progress: summary?.progress ?? project.progress,
          remainingTaskCount: summary?.openRootTaskCount ?? activeTasks.count,
          undatedRemainingTaskCount:
            summary?.undatedOpenRootTaskCount ?? undatedRemainingTaskCount,
          dailyTaskCounts: dailyCounts,
          dailyTaskPreviews: dailyPreviews,
          dailyPlannedWorkCounts: dailyPlannedCounts,
          dailyPlannedWorkPreviews: dailyPlannedPreviews,
          dailyCompletedTaskCounts: dailyCompletedCounts,
          dailyCompletedTaskPreviews: dailyCompletedPreviews,
          nextUpcomingDate: summary?.nextUpcomingDate ?? upcomingDates.min()
        )
      )
    }

    storeCachedBars(bars, for: cacheKey)
    return bars
  }

  private func makeWorkspaceProjectSource(
    _ detail: ProjectDetailSnapshot,
    summary: ProjectSummaryRecord? = nil
  ) -> TimelineProjectSource {
    return TimelineProjectSource(
      reference: .project(detail.node.projectID ?? detail.node.id),
      reminderListIdentifier: detail.node.reminderListIdentifier,
      reminderListExternalIdentifier: detail.node.reminderListExternalIdentifier,
      title: detail.node.title,
      colorHex: detail.node.colorHex,
      deadline: detail.projectDeadline,
      progress: summary?.progress ?? ProjectProgressStage.do.progressValue,
      isArchived: detail.node.isArchived,
      summary: summary,
      tasks: WorkspaceTaskRowSemantics.rootRows(from: detail.taskRows).map(makeWorkspaceTaskSource)
    )
  }

  private func makeWorkspaceTaskSource(_ task: TaskRowSnapshot) -> TimelineTaskSource {
    TimelineTaskSource(
      id: task.id,
      title: task.title,
      isCompleted: task.isCompleted,
      completionDate: task.completionDate,
      startDate: task.startDate,
      dueDate: task.dueDate,
      scheduleHasExplicitTime: task.scheduleHasExplicitTime,
      scheduledDurationMinutes: task.scheduledDurationMinutes,
      priority: task.priority,
      recurrenceRuleRaw: task.recurrenceRuleRaw,
      rowOrder: task.rowOrder,
      requiredWorkDays: task.requiredWorkDays,
      completedWorkUnits: task.completedWorkUnits,
      completedWorkUnitDates: task.completedWorkUnitDates,
      localUpdatedAt: task.localUpdatedAt,
      createdAt: task.createdAt
    )
  }

  private func cachedBars(for key: Int) -> [TimelineProjectBar]? {
    cacheLock.lock()
    defer { cacheLock.unlock() }
    guard let cacheEntry, cacheEntry.key == key else { return nil }
    return cacheEntry.bars
  }

  private func storeCachedBars(_ bars: [TimelineProjectBar], for key: Int) {
    cacheLock.lock()
    cacheEntry = CacheEntry(key: key, bars: bars)
    cacheLock.unlock()
  }

  private func timelineCacheKey(for projects: [TimelineProjectSource]) -> Int {
    var hasher = Hasher()
    hasher.combine(projects.count)

    for project in projects {
      hasher.combine(project.reference)
      hasher.combine(project.title)
      hasher.combine(project.colorHex)
      hasher.combine(project.isArchived)
      hasher.combine(project.deadline?.timeIntervalSinceReferenceDate)
      hasher.combine(project.progress)
      hasher.combine(project.summary?.openRootTaskCount)
      hasher.combine(project.summary?.completedRootTaskCount)
      hasher.combine(project.summary?.undatedOpenRootTaskCount)
      hasher.combine(project.summary?.overdueOpenRootTaskCount)
      hasher.combine(project.summary?.todayTaskCount)
      hasher.combine(project.summary?.nextUpcomingDate?.timeIntervalSinceReferenceDate)
      hasher.combine(project.summary?.deadline?.timeIntervalSinceReferenceDate)
      hasher.combine(project.summary?.stageRaw)
      hasher.combine(project.summary?.progress)
      hasher.combine(project.summary?.latestTaskUpdatedAt?.timeIntervalSinceReferenceDate)

      let orderedTasks = tasksForCacheSignature(project.tasks)
      hasher.combine(orderedTasks.count)

      for task in orderedTasks {
        hasher.combine(task.id)
        hasher.combine(task.title)
        hasher.combine(task.rowOrder)
        hasher.combine(task.priority)
        hasher.combine(task.isCompleted)
        hasher.combine(task.completionDate?.timeIntervalSinceReferenceDate)
        hasher.combine(task.startDate?.timeIntervalSinceReferenceDate)
        hasher.combine(task.dueDate?.timeIntervalSinceReferenceDate)
        hasher.combine(task.scheduleHasExplicitTime)
        hasher.combine(task.scheduledDurationMinutes)
        hasher.combine(task.requiredWorkDays)
        hasher.combine(task.completedWorkUnits)
        hasher.combine(task.completedWorkUnitDates.map(\.timeIntervalSinceReferenceDate))
        hasher.combine(task.recurrenceRuleRaw)
        hasher.combine(task.localUpdatedAt.timeIntervalSinceReferenceDate)
        hasher.combine(task.createdAt.timeIntervalSinceReferenceDate)
      }
    }

    return hasher.finalize()
  }

  private func tasksForCacheSignature(_ tasks: [TimelineTaskSource]) -> [TimelineTaskSource] {
    tasks.sorted { lhs, rhs in
      if lhs.rowOrder != rhs.rowOrder {
        return lhs.rowOrder < rhs.rowOrder
      }
      if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private func plannedWorkSlots(
    for task: TimelineTaskSource,
    calendar: Calendar
  ) -> [(date: Date, targetCompletedUnits: Int)] {
    let requiredWorkDays = max(0, task.requiredWorkDays)
    let completedWorkUnits = max(0, task.completedWorkUnits)
    guard requiredWorkDays > 0,
      let dueDate = task.dueDate.map({ calendar.startOfDay(for: $0) })
    else {
      return []
    }

    var slots: [(date: Date, targetCompletedUnits: Int)] = []
    slots.reserveCapacity(requiredWorkDays)

    for index in completedWorkUnits..<requiredWorkDays {
      let daysBeforeDue = requiredWorkDays - index - 1
      guard let slotDate = calendar.date(byAdding: .day, value: -daysBeforeDue, to: dueDate) else {
        continue
      }
      guard slotDate != dueDate else { continue }
      slots.append((date: slotDate, targetCompletedUnits: index + 1))
    }

    return slots
  }

  private func taskPreviewSort(lhs: TimelineTaskSource, rhs: TimelineTaskSource) -> Bool {
    if lhs.rowOrder != rhs.rowOrder {
      return lhs.rowOrder < rhs.rowOrder
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }

  private func shouldIncludeCompletedTask(_ task: TimelineTaskSource) -> Bool {
    guard task.isCompleted else { return false }
    return task.recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
  }

  private func plannedWorkCompletionDays(for task: TimelineTaskSource, calendar: Calendar) -> [Date] {
    guard shouldIncludeCompletedHistory(for: task) else { return [] }
    return task.completedWorkUnitDates.map { calendar.startOfDay(for: $0) }
  }

  private func shouldIncludeCompletedHistory(for task: TimelineTaskSource) -> Bool {
    guard task.completedWorkUnits > 0 else { return false }
    return task.recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
  }

  private func completionDay(for task: TimelineTaskSource, calendar: Calendar) -> Date? {
    let completionAnchor = task.completionDate ?? (task.isCompleted ? task.localUpdatedAt : nil)
    guard let completionAnchor else { return nil }
    return calendar.startOfDay(for: completionAnchor)
  }
}
