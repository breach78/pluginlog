import Foundation

enum TimelineProjectionService {
  static func runtimeBars(
    service: TimelineService,
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    projectSummariesByID: [UUID: ProjectSummaryRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> [TimelineProjectBar] {
    let normalizedProjectIDs = normalizedProjectIDs(projectIDs)
    guard !normalizedProjectIDs.isEmpty else { return [] }

    let sources = normalizedProjectIDs.compactMap { projectID -> TimelineProjectSource? in
      guard let project = projectSnapshots[projectID] else { return nil }
      let taskRows = (scheduleEntriesByProjectID[projectID] ?? []).map { $0.taskRowSnapshot(projectID: projectID) }
      let summary = projectSummariesByID[projectID]
      let defaultStage = project.progressStageRaw.flatMap(Int.init)
        .flatMap(ProjectProgressStage.init(rawValue:))
        ?? .do
      let progress = summary?.progress ?? defaultStage.progressValue
      return TimelineProjectSource(
        reference: .project(projectID),
        reminderListIdentifier: project.reminderListIdentifier,
        reminderListExternalIdentifier: project.reminderListExternalIdentifier,
        title: project.title,
        colorHex: project.colorHex,
        deadline: project.localDeadline,
        progress: progress,
        isArchived: project.isArchived,
        summary: summary,
        tasks: WorkspaceTaskRowSemantics.rootRows(from: taskRows).map {
          TimelineTaskSource(
            id: $0.id,
            title: $0.title,
            isCompleted: $0.isCompleted,
            completionDate: $0.completionDate,
            startDate: $0.startDate,
            dueDate: $0.dueDate,
            scheduleHasExplicitTime: $0.scheduleHasExplicitTime,
            scheduledDurationMinutes: $0.scheduledDurationMinutes,
            priority: $0.priority,
            recurrenceRuleRaw: $0.recurrenceRuleRaw,
            rowOrder: $0.rowOrder,
            requiredWorkDays: $0.requiredWorkDays,
            completedWorkUnits: $0.completedWorkUnits,
            completedWorkUnitDates: $0.completedWorkUnitDates,
            localUpdatedAt: $0.localUpdatedAt,
            createdAt: $0.createdAt
          )
        }
      )
    }
    guard sources.count == normalizedProjectIDs.count else { return [] }

    let bars = service.buildTimeline(projectSources: sources)
    let barsByProjectID = Dictionary(uniqueKeysWithValues: bars.map { ($0.projectID, $0) })
    return normalizedProjectIDs.compactMap { barsByProjectID[$0] }
  }

  private static func normalizedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return projectIDs.filter { seen.insert($0).inserted }
  }
}
