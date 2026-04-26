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

  func createTimelineProject() {
    guard !isCreatingProject else { return }
    isCreatingProject = true
    Task { @MainActor in
      defer { isCreatingProject = false }
      guard let snapshot = await appState.createProjectStub(context: modelContext) else { return }
      do {
        try ObsidianTaskOpenService.openProjectNoteFile(
          fileURL: snapshot.fileURL,
          documentOpener: appState.platformUIFoundation.documentOpener
        )
      } catch {
        appState.errorMessage = error.localizedDescription
      }
      await appState.handleObsidianProjectDirectoryChange([snapshot.fileURL])
    }
  }

  func openScheduleDay(for offset: Int) {
    cancelTimelineDayHeaderOverlay()
    appState.jumpSchedule(to: date(for: offset))
  }

  func revealTimelineTaskDetail(taskID: UUID, projectID: UUID) {
    appState.selectedProjectID = projectID
    activeTimelineProjectListPopoverProjectID = nil
    Task { @MainActor in
      do {
        try await RemindersAppOpenService.openTask(taskID: taskID)
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()
  }

  func showTimelineProjectListPopover(_ projectID: UUID) {
    onSelectProject(projectID)
    appState.selectedProjectID = projectID
    activeTimelineProjectListPopoverProjectID = nil
    DispatchQueue.main.async {
      activeTimelineProjectListPopoverProjectID = projectID
    }
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()
  }

  func timelineProjectListPopoverBinding(for projectID: UUID) -> Binding<Bool> {
    Binding(
      get: { activeTimelineProjectListPopoverProjectID == projectID },
      set: { isPresented in
        if isPresented {
          showTimelineProjectListPopover(projectID)
        } else if activeTimelineProjectListPopoverProjectID == projectID {
          activeTimelineProjectListPopoverProjectID = nil
        }
      }
    )
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
    guard allowTimelineRetainedWrite("project-color") else { return }
    Task { @MainActor in
      do {
        _ = try await ObsidianRetainedProjectCommandService.setProjectColor(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          colorHex: hex,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        appState.recordAppAuthoredReminderPush()
        await refreshTimelineProjectState(including: [projectID])
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func updateTimelineProjectStage(
    projectID: UUID,
    stage: ProjectProgressStage,
    registerUndo: Bool = true
  ) {
    let currentStage = timelineProjectStage(for: projectID)
    guard currentStage != stage else { return }
    guard allowTimelineRetainedWrite("project-stage") else { return }
    Task { @MainActor in
      do {
        _ = try await ObsidianRetainedProjectCommandService.setProjectStage(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          stage: stage
        )
        await refreshTimelineProjectState(including: [projectID])

        guard registerUndo else { return }
        appState.registerUndo(
          with: undoManager,
          actionName: "분류 변경"
        ) {
          self.updateTimelineProjectStage(
            projectID: projectID,
            stage: currentStage,
            registerUndo: true
          )
        }
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
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
    guard allowTimelineRetainedWrite("delete-project") else { return }

    pendingDeleteProjectID = bar.projectID
    pendingDeleteProjectTitle = bar.title
  }

  func hideProjectFromTimeline(_ projectID: UUID) {
    var nextHiddenProjectIDs = hiddenTimelineProjectIDs
    guard nextHiddenProjectIDs.insert(projectID).inserted else { return }
    hiddenTimelineProjectIDs = nextHiddenProjectIDs
    TimelineHiddenProjectStore.save(nextHiddenProjectIDs)

    cachedTimelineBars.removeAll { $0.projectID == projectID }
    cachedTimelineRowLayouts = buildRowLayouts(for: cachedTimelineBars)
    cachedTimelineBarsSourceSignature = nil
    cachedTimelineBarsPresentationSignature = timelineSignature(for: cachedTimelineBars)
    if activeTimelineProjectListPopoverProjectID == projectID {
      activeTimelineProjectListPopoverProjectID = nil
    }
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()
  }

  func performPermanentDelete(_ projectID: UUID) {
    guard allowTimelineRetainedWrite("delete-project") else { return }
    Task { @MainActor in
      _ = await appState.deleteProjectPermanently(projectID, context: modelContext)
    }
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
    guard projectListSortMode == .priority || projectListSortMode == .bucketGrouped else { return }
    guard draggedID != targetID else { return }
    let bars = timelineBoardSnapshot.bars
    guard let draggedBar = bars.first(where: { $0.projectID == draggedID }),
      let targetBar = bars.first(where: { $0.projectID == targetID })
    else {
      return
    }
    let draggedStage = priorityStage(for: draggedBar)
    let targetStage = priorityStage(for: targetBar)
    let stageProjectIDs = bars
      .filter { priorityStage(for: $0) == targetStage }
      .map(\.projectID)
    guard let reordered = TimelineBoardReadPath.reorderedProjectIDsAfterDrop(
      stageProjectIDs,
      draggedID: draggedID,
      targetID: targetID,
      placement: placement
    ) else {
      return
    }

    var nextOrder = timelineProjectManualOrder
    for (index, projectID) in reordered.enumerated() {
      nextOrder[projectID] = Int64(index)
    }
    timelineProjectManualOrder = nextOrder
    TimelineProjectManualOrderStore.save(nextOrder)

    if draggedStage != targetStage {
      updateTimelineProjectStage(projectID: draggedID, stage: targetStage)
    }
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
      let stage = ProjectProgressStage.fromStorageValue(stageRaw)
    {
      return stage
    }

    if
      let stageRaw = workspaceTimelineProjectSnapshots[projectID]?.progressStageRaw,
      let stage = ProjectProgressStage.fromStorageValue(stageRaw)
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
