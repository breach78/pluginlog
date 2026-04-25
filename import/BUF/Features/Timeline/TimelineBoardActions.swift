import AppKit
import SwiftUI

extension TimelineBoardView {
  func allowTimelineMutation(_ feature: String) -> Bool {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: feature)
    return false
  }

  func allowTimelineRetainedWrite(_ feature: String) -> Bool {
    _ = feature
    return true
  }

  func submitNewProject(_ rawTitle: String) {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    guard !isCreatingProject else { return }
    guard allowTimelineMutation("create-project") else { return }
  }

  func openScheduleDay(for offset: Int) {
    cancelTimelineDayHeaderOverlay()
    appState.jumpSchedule(to: date(for: offset))
  }

  func revealTimelineTaskDetail(taskID: UUID, projectID: UUID) {
    appState.selectedProjectID = projectID
    Task { @MainActor in
      do {
        try await ObsidianTaskOpenService.openTask(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          documentOpener: appState.platformUIFoundation.documentOpener
        )
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()
  }

  func completeTimelineTask(_ taskID: UUID, projectID: UUID) {
    updateTimelineTaskCompletion(
      taskID: taskID,
      projectID: projectID,
      isCompleted: true,
      completionDate: .now,
      targetState: nil,
      registerUndo: true
    )
  }

  private func updateTimelineTaskCompletion(
    taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    targetState: TimelineTaskCompletionUndoSnapshot?,
    registerUndo: Bool
  ) {
    guard allowTimelineRetainedWrite("task-completion") else { return }
    guard let previousState = timelineTaskCompletionState(taskID: taskID, projectID: projectID) else {
      return
    }

    let nextState =
      targetState
      ?? TimelineTaskCompletionUndoSnapshot(
        taskID: taskID,
        projectID: projectID,
        isCompleted: isCompleted,
        completionDate: isCompleted ? (completionDate ?? .now) : nil,
        isRecurring: previousState.isRecurring,
        occurrenceDate: previousState.occurrenceDate
      )
    guard previousState != nextState else { return }
    Task { @MainActor in
      do {
        let result = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          isCompleted: nextState.isCompleted,
          completionDate: nextState.isCompleted && nextState.isRecurring
            ? (nextState.occurrenceDate ?? nextState.completionDate)
            : nextState.completionDate,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        await refreshTimelineProjectState(including: [projectID])
        retainedTimelineCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
        retainedTimelineCalendarBridgeWriteMarkersByTaskID[taskID] = result.calendarWriteMarker

        guard registerUndo else { return }
        appState.registerUndo(
          with: undoManager,
          actionName: nextState.isCompleted ? "할일 완료" : "할일 완료 취소"
        ) {
          self.updateTimelineTaskCompletion(
            taskID: taskID,
            projectID: projectID,
            isCompleted: previousState.isCompleted,
            completionDate: previousState.completionDate,
            targetState: previousState,
            registerUndo: true
          )
        }
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func completeTimelinePlannedWork(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date
  ) {
    updateTimelinePlannedWorkProgress(
      taskID: taskID,
      projectID: projectID,
      targetCompletedUnits: targetCompletedUnits,
      completedOn: completedOn,
      targetState: nil,
      registerUndo: true
    )
  }

  private func updateTimelinePlannedWorkProgress(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date,
    targetState: TimelinePlannedWorkUndoSnapshot?,
    registerUndo: Bool
  ) {
    guard let currentEntry = scheduleEntry(taskID: taskID, projectID: projectID) else {
      return
    }

    let previousState = TimelinePlannedWorkUndoSnapshot(
      taskID: taskID,
      projectID: projectID,
      completedUnits: currentEntry.completedWorkUnits,
      completedOn: completedOn
    )
    let normalizedTarget = max(0, min(targetCompletedUnits, currentEntry.requiredWorkDays))
    let nextState =
      targetState
      ?? TimelinePlannedWorkUndoSnapshot(
        taskID: taskID,
        projectID: projectID,
        completedUnits: normalizedTarget,
        completedOn: completedOn
    )
    guard previousState != nextState else { return }
    guard allowTimelineMutation("planned-work-progress") else { return }
  }

  func archiveProjectFromTimeline(_ projectID: UUID) {
    guard allowTimelineMutation("archive-project") else { return }
  }

  func updateTimelineProjectColor(projectID: UUID, hex: String) {
    guard allowTimelineMutation("project-color") else { return }
  }

  func updateTimelineProjectStage(
    projectID: UUID,
    stage: ProjectProgressStage,
    registerUndo: Bool = true
  ) {
    let currentStage = timelineProjectStage(for: projectID)
    guard currentStage != stage else { return }
    guard allowTimelineMutation("project-stage") else { return }
  }

  func colorSwatchMenuImage(hex: String, selected: Bool) -> NSImage {
    let size = NSSize(width: 12, height: 12)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let color = ColorHexCodec.nsColor(from: hex) ?? .gray
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
    let path = NSBezierPath(ovalIn: rect)
    color.setFill()
    path.fill()

    let strokeColor = selected ? NSColor.white : NSColor.black.withAlphaComponent(0.22)
    strokeColor.setStroke()
    path.lineWidth = selected ? 1.8 : 1
    path.stroke()

    image.isTemplate = false
    return image
  }

  func requestPermanentDelete(for bar: TimelineProjectBar) {
    guard allowTimelineMutation("delete-project") else { return }

    pendingDeleteProjectID = bar.projectID
    pendingDeleteProjectTitle = bar.title
  }

  func performPermanentDelete(_ projectID: UUID) {
    guard allowTimelineMutation("delete-project") else { return }
  }

  func moveTaskToProjectTop(taskID: UUID, targetProjectID: UUID) {
    guard taskProjectID(for: taskID) != nil else { return }
    guard allowTimelineMutation("move-task") else { return }
  }

  var pendingTimelineDeleteDialogBinding: Binding<Bool> {
    Binding(
      get: { pendingDeleteProjectID != nil },
      set: { isPresented in
        if !isPresented {
          pendingDeleteProjectID = nil
          pendingDeleteProjectTitle = ""
        }
      }
    )
  }

  func reorderProjects(
    draggedID: UUID,
    targetID: UUID,
    placement: TimelineProjectDropPlacement
  ) {
    defer { clearProjectDragFeedback() }
    guard projectListSortMode.allowsInteractiveReordering else { return }
    guard draggedID != targetID else { return }
    guard allowTimelineMutation("reorder-projects") else { return }
  }

  private func clearProjectDragFeedback() {
    draggingProjectID = nil
    projectDropIndicator = nil
    taskDropTargetProjectID = nil
  }

  private func refreshTimelineProjectState(
    including additionalProjectIDs: [UUID] = [],
    excluding excludedProjectIDs: [UUID] = []
  ) async {
    let excluded = Set(excludedProjectIDs)
    let requestedProjectIDs = TimelineBoardReadPath.normalizedProjectIDs(
      (activeProjectIDs + additionalProjectIDs).filter { !excluded.contains($0) }
    )
    await reloadWorkspaceTimelineProjectDetails(for: requestedProjectIDs)
  }

  private func timelineTaskCompletionState(
    taskID: UUID,
    projectID: UUID
  ) -> TimelineTaskCompletionUndoSnapshot? {
    guard let entry = scheduleEntry(taskID: taskID, projectID: projectID) else { return nil }
    return TimelineTaskCompletionUndoSnapshot(
      taskID: taskID,
      projectID: projectID,
      isCompleted: entry.isCompleted,
      completionDate: entry.completionDate,
      isRecurring: !(entry.recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
      occurrenceDate: ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: entry.dueDate,
        startDate: entry.startDate,
        displayedDate: entry.displayedDate
      )
    )
  }

  private func scheduleEntry(taskID: UUID, projectID: UUID) -> ScheduleSliceEntry? {
    workspaceTimelineScheduleEntriesByProjectID[projectID]?.first(where: { $0.taskID == taskID })
  }

  private func timelineProjectStage(for projectID: UUID) -> ProjectProgressStage {
    if
      let stageRaw = workspaceTimelineProjectSummaries[projectID]?.stageRaw,
      let stageValue = Int(stageRaw),
      let stage = ProjectProgressStage(rawValue: stageValue)
    {
      return stage
    }

    if
      let stageRaw = workspaceTimelineProjectSnapshots[projectID]?.progressStageRaw,
      let stageValue = Int(stageRaw),
      let stage = ProjectProgressStage(rawValue: stageValue)
    {
      return stage
    }

    if let bar = timelineBoardSnapshot.bars.first(where: { $0.projectID == projectID }) {
      return ProjectProgressStage.from(progress: bar.progress)
    }

    return .do
  }

  private func taskProjectID(for taskID: UUID) -> UUID? {
    for (projectID, entries) in workspaceTimelineScheduleEntriesByProjectID {
      if entries.contains(where: { $0.taskID == taskID }) {
        return projectID
      }
    }
    return nil
  }

}
