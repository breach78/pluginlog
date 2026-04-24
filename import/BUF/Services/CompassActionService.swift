import Foundation
import SwiftData

enum CompassActionServiceError: LocalizedError {
  case priorityTaskUnavailable
  case projectUnavailable
  case taskCreationFailed
  case scheduleTargetUnavailable

  var errorDescription: String? {
    switch self {
    case .priorityTaskUnavailable:
      return "오늘 우선순위로 채택할 기존 할일을 찾지 못했다."
    case .projectUnavailable:
      return "추천을 반영할 프로젝트를 찾지 못했다."
    case .taskCreationFailed:
      return "추천된 할일을 실제 작업으로 만들지 못했다."
    case .scheduleTargetUnavailable:
      return "일정으로 반영할 기존 할일을 찾지 못했다."
    }
  }
}

struct CompassPriorityAdoptionResult: Hashable, Sendable {
  var taskID: UUID
  var projectID: UUID?
}

struct CompassMissingTaskCreationResult: Hashable, Sendable {
  var taskID: UUID
  var projectID: UUID
}

struct CompassScheduleApplicationResult: Hashable, Sendable {
  var taskIDs: [UUID]
  var projectIDs: [UUID]
}

@MainActor
final class CompassActionService {
  private let appState: AppState
  private let context: ModelContext
  private let calendar: Calendar

  init(
    appState: AppState,
    context: ModelContext,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.appState = appState
    self.context = context
    self.calendar = calendar
  }

  func adoptPriority(
    _ recommendation: CompassPriorityRecommendation,
    referenceDate: Date = .now
  ) async throws -> CompassPriorityAdoptionResult {
    guard
      let taskID = recommendation.taskID,
      let task = await resolvedProjectionTask(forTaskID: taskID),
      let projectID = try resolveProjectID(
        preferredProjectID: recommendation.projectID,
        fallbackTaskID: taskID
      )
    else {
      throw CompassActionServiceError.priorityTaskUnavailable
    }
    let targetDay = calendar.startOfDay(for: referenceDate)
    let shouldReschedule =
      task.dueDate == nil || !calendar.isDate(task.dueDate ?? targetDay, inSameDayAs: targetDay)
    let shouldPromote =
      task.boardStage != .now
      || task.importance != .important
      || !task.isFlagged

    if shouldPromote {
      let didWrite = await appState.saveProjectDetailTaskPresentation(
        taskID: taskID,
        boardStage: .now,
        importance: .important,
        priority: max(task.priority, 1),
        isFlagged: true,
        context: context
      )
      guard didWrite else {
        throw CompassActionServiceError.priorityTaskUnavailable
      }
    }

    if shouldReschedule {
      let didWrite = await appState.writeProjectDetailTaskSchedule(
        day: targetDay,
        hasExplicitTime: task.scheduleHasExplicitTime,
        timeMinutes: task.scheduleHasExplicitTime ? explicitTimeMinutes(from: task.dueDate) : nil,
        durationMinutes: recommendation.estimatedMinutes ?? task.scheduledDurationMinutes,
        taskID: taskID,
        context: context
      )
      guard didWrite else {
        throw CompassActionServiceError.priorityTaskUnavailable
      }
    }

    if shouldPromote || shouldReschedule {
      ProjectHistoryService.recordProjectUpdated(
        projectID: projectID,
        projectTitle: projectTitle(for: projectID),
        summary: "나침반 우선순위 채택: \(task.title)",
        in: context
      )
    }

    return CompassPriorityAdoptionResult(taskID: taskID, projectID: projectID)
  }

  func createMissingTask(
    from suggestion: CompassMissingTaskSuggestion,
    referenceDate: Date = .now
  ) async throws -> CompassMissingTaskCreationResult {
    guard
      let projectID = try resolveProjectID(preferredProjectID: suggestion.projectID),
      appState.projectDocumentStore(for: projectID) != nil
    else {
      throw CompassActionServiceError.projectUnavailable
    }

    let targetDay = calendar.startOfDay(for: referenceDate)
    guard
      let taskID = await appState.createTask(
        inProjectID: projectID,
        title: suggestion.suggestedTaskTitle,
        startDate: targetDay,
        durationMinutes: nil,
        context: context
      ),
      let task = await resolvedProjectionTask(forTaskID: taskID)
    else {
      throw CompassActionServiceError.taskCreationFailed
    }

    let didWrite = await appState.saveProjectDetailTaskPresentation(
      taskID: taskID,
      boardStage: .now,
      importance: .important,
      priority: max(task.priority, 1),
      isFlagged: true,
      context: context
    )
    guard didWrite else {
      throw CompassActionServiceError.taskCreationFailed
    }

    ProjectHistoryService.recordProjectUpdated(
      projectID: projectID,
      projectTitle: projectTitle(for: projectID),
      summary: "나침반 제안으로 할일 추가: \(task.title)",
      in: context
    )

    return CompassMissingTaskCreationResult(taskID: taskID, projectID: projectID)
  }

  func applyScheduleSuggestion(
    _ suggestion: CompassScheduleSuggestion,
    referenceDate: Date = .now
  ) async throws -> CompassScheduleApplicationResult {
    var resolvedTasks: [(ProjectIdentityTaskRecord, UUID)] = []
    for taskID in suggestion.taskIDs {
      guard
        let task = await resolvedProjectionTask(forTaskID: taskID),
        let projectID = try resolveProjectID(fallbackTaskID: taskID)
      else {
        continue
      }
      resolvedTasks.append((task, projectID))
    }
    guard !resolvedTasks.isEmpty else {
      throw CompassActionServiceError.scheduleTargetUnavailable
    }

    let targetDay = calendar.startOfDay(for: referenceDate)
    let explicitStartMinutes = normalizedTimeMinutes(
      hour: suggestion.startHour,
      minute: suggestion.startMinute
    )
    let scheduledDuration: Int
    if explicitStartMinutes != nil {
      scheduledDuration = max(15, suggestion.durationMinutes / max(resolvedTasks.count, 1))
    } else {
      scheduledDuration = max(15, suggestion.durationMinutes)
    }

    var cursorMinutes = explicitStartMinutes
    var touchedProjectIDs: Set<UUID> = []

    for (task, projectID) in resolvedTasks {
      let didWrite = await appState.writeProjectDetailTaskSchedule(
        day: targetDay,
        hasExplicitTime: cursorMinutes != nil,
        timeMinutes: cursorMinutes,
        durationMinutes: scheduledDuration,
        taskID: task.id,
        context: context
      )
      guard didWrite else {
        throw CompassActionServiceError.scheduleTargetUnavailable
      }
      if task.boardStage != .now {
        let didWrite = await appState.saveProjectDetailTaskPresentation(
          taskID: task.id,
          boardStage: .now,
          importance: task.importance,
          priority: task.priority,
          isFlagged: task.isFlagged,
          context: context
        )
        guard didWrite else {
          throw CompassActionServiceError.scheduleTargetUnavailable
        }
      }

      touchedProjectIDs.insert(projectID)
      if let currentCursorMinutes = cursorMinutes {
        cursorMinutes = min(currentCursorMinutes + scheduledDuration, 23 * 60 + 59)
      }
    }

    for projectID in touchedProjectIDs {
      ProjectHistoryService.recordProjectUpdated(
        projectID: projectID,
        projectTitle: projectTitle(for: projectID),
        summary: "나침반 일정 반영: \(suggestion.title)",
        in: context
      )
    }

    return CompassScheduleApplicationResult(
      taskIDs: resolvedTasks.map { $0.0.id },
      projectIDs: Array(touchedProjectIDs).sorted { $0.uuidString < $1.uuidString }
    )
  }

  private func resolveProjectID(
    preferredProjectID: UUID? = nil,
    fallbackTaskID: UUID? = nil
  ) throws -> UUID? {
    if let preferredProjectID, appState.isActiveProjectIdentity(preferredProjectID, context: context) {
      return preferredProjectID
    }

    if let fallbackTaskID,
      let projectID = appState.resolvedOwnerProjectID(forTaskID: fallbackTaskID, context: context)
    {
      return projectID
    }

    if let selectedProjectID = appState.selectedProjectID,
      appState.isActiveProjectIdentity(selectedProjectID, context: context)
    {
      return selectedProjectID
    }

    let runtimeSnapshot = appState.cachedOutlinerRuntimeProjectionSnapshot
    let projectIDs = runtimeSnapshot?.projects.map(\.id) ?? []
    return WorkspaceProjectRuntimeRecordBuilder.records(
      from: runtimeSnapshot,
      projectIDs: projectIDs
    )
    .values
    .filter { !$0.isArchived }
    .sorted { lhs, rhs in
      if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
      }
      return lhs.createdAt < rhs.createdAt
    }
    .first?.id
  }

  private func projectTitle(for projectID: UUID) -> String {
    appState.resolvedProjectTitle(forProjectID: projectID, context: context)
  }

  private func resolvedProjectionTask(forTaskID taskID: UUID) async -> ProjectIdentityTaskRecord? {
    if let task = appState.resolvedTaskRecord(forTaskID: taskID, context: context) {
      return task
    }
    if let runtimeSnapshot = appState.cachedOutlinerRuntimeProjectionSnapshot {
      let projectIDs = Set(runtimeSnapshot.projects.map(\.id))
      if !projectIDs.isEmpty {
        _ = await appState.recomputeCachedRuntimeProjectionProjects(projectIDs)
      }
    }
    return appState.resolvedTaskRecord(forTaskID: taskID, context: context)
  }
  private func explicitTimeMinutes(from date: Date?) -> Int? {
    guard let date else { return nil }
    let components = calendar.dateComponents([.hour, .minute], from: date)
    guard let hour = components.hour, let minute = components.minute else { return nil }
    return hour * 60 + minute
  }

  private func normalizedTimeMinutes(hour: Int?, minute: Int?) -> Int? {
    guard let hour, let minute else { return nil }
    let boundedHour = min(max(hour, 0), 23)
    let boundedMinute = min(max(minute, 0), 59)
    return boundedHour * 60 + boundedMinute
  }
}
