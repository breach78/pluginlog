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

  func createTimelineProject(named rawTitle: String) {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    guard !isCreatingProject else { return }
    isCreatingProject = true
    Task { @MainActor in
      defer { isCreatingProject = false }
      guard let projectID = await appState.createProjectList(
        named: title,
        context: modelContext
      ) else {
        return
      }
      appendTimelineProjectManualOrderIfNeeded(projectID)
      isNewProjectSheetPresented = false
      selectTimelineProject(projectID, commitDelay: .zero)
    }
  }

  func seedTimelineProjectManualOrderFromRemindersIfNeeded(
    for projectIDs: [UUID]
  ) async {
    guard !projectIDs.isEmpty else { return }
    let reminderOrderedProjectIDs = await appState.reminderProjectIDsInCurrentListOrder()
    let nextOrder = TimelineProjectManualOrderStore.mergedOrder(
      existing: timelineProjectManualOrder,
      reminderOrderedProjectIDs: reminderOrderedProjectIDs,
      availableProjectIDs: projectIDs
    )
    applyTimelineProjectManualOrder(nextOrder)
  }

  func appendTimelineProjectManualOrderIfNeeded(_ projectID: UUID) {
    guard timelineProjectManualOrder[projectID] == nil else { return }
    var nextOrder = timelineProjectManualOrder
    nextOrder[projectID] = (nextOrder.values.max() ?? -1) + 1
    applyTimelineProjectManualOrder(nextOrder)
  }

  func applyTimelineProjectManualOrder(_ nextOrder: [UUID: Int64]) {
    guard nextOrder != timelineProjectManualOrder else { return }
    timelineProjectManualOrder = nextOrder
    TimelineProjectManualOrderStore.save(nextOrder)
    cachedTimelineBars = []
    cachedTimelineRowLayouts = []
    cachedTimelineBarsSourceSignature = nil
    cachedTimelineBarsPresentationSignature = nil
  }

  func openScheduleDay(for offset: Int) {
    cancelTimelineDayHeaderOverlay()
    appState.jumpSchedule(to: date(for: offset))
  }

  func openTimelineProjectListWindow(for bar: TimelineProjectBar) {
    selectTimelineProject(bar.projectID, commitDelay: .zero)
    activeTimelineProjectListPopoverProjectID = nil
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()

    let projectID = bar.projectID
    TimelineProjectListWindowPresenter.shared.present(
      snapshot: timelineProjectListWindowSnapshot(for: bar),
      onToggleTaskCompletion: { taskID, isCompleted in
        await self.toggleTimelineProjectListWindowTaskCompletion(
          taskID,
          projectID: projectID,
          isCompleted: isCompleted
        )
      },
      onEditTask: { taskID in
        self.editTimelineTaskFromProjectListWindow(taskID: taskID, projectID: projectID)
      },
      onReorderTasks: { projectID, orderedTaskIDs in
        self.saveTimelineProjectListWindowTaskOrder(
          projectID: projectID,
          orderedTaskIDs: orderedTaskIDs
        )
      },
      onCreateTask: { projectID, title in
        await self.createTimelineProjectListWindowTask(title, projectID: projectID)
      },
      onRenameTask: { projectID, taskID, title in
        await self.renameTimelineProjectListWindowTask(
          title,
          taskID: taskID,
          projectID: projectID
        )
      },
      onDeleteTask: { projectID, taskID in
        await self.deleteTimelineProjectListWindowTask(taskID, projectID: projectID)
      },
      onRenameProject: { projectID, title in
        self.requestRename(projectID: projectID, title: title)
      }
    )
  }

  func createTimelineProjectListWindowTask(
    _ rawTitle: String,
    projectID: UUID
  ) async -> TimelineProjectListWindowSnapshot.Task? {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }

    do {
      let result = try await ObsidianRetainedTaskCommandService.createTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        title: title,
        day: nil,
        timeMinutes: nil,
        durationMinutes: nil,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      await refreshTimelineProjectState(including: [projectID])
      retainedTimelineCalendarBridgeDecisionsByTaskID[result.taskID] = result.calendarBridgeDecision
      retainedTimelineCalendarBridgeWriteMarkersByTaskID[result.taskID] = result.calendarWriteMarker
      appState.bumpWorkspaceTreeRevision()
      return TimelineProjectListWindowSnapshot.Task(
        id: result.taskID,
        title: timelinePreviewTitle(for: title),
        dateText: nil,
        isCompleted: false,
        isOverdue: false
      )
    } catch {
      appState.reportError(error, logMessage: "timeline project list createTask failed")
      return nil
    }
  }

  func renameTimelineProjectListWindowTask(
    _ rawTitle: String,
    taskID: UUID,
    projectID: UUID
  ) async -> TimelineProjectListWindowSnapshot.Task? {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    guard let entry = scheduleEntry(taskID: taskID, projectID: projectID) else { return nil }
    var fields = timelineTaskEditFields(for: entry)
    fields.title = title

    do {
      let result = try await ObsidianRetainedTaskCommandService.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        fields: fields,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      await refreshTimelineProjectState(including: [projectID])
      retainedTimelineCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
      retainedTimelineCalendarBridgeWriteMarkersByTaskID[taskID] = result.calendarWriteMarker
      appState.bumpWorkspaceTreeRevision()
      return TimelineProjectListWindowSnapshot.Task(
        id: taskID,
        title: timelinePreviewTitle(for: title),
        dateText: timelineProjectListDateText(for: entry),
        isCompleted: entry.isCompleted,
        isOverdue: timelineProjectListEntryIsOverdue(entry)
      )
    } catch {
      appState.reportError(error, logMessage: "timeline project list renameTask failed")
      return nil
    }
  }

  func toggleTimelineProjectListWindowTaskCompletion(
    _ taskID: UUID,
    projectID: UUID,
    isCompleted: Bool
  ) async -> Bool {
    let nextIsCompleted = TimelineTaskCompletionTogglePolicy.nextIsCompleted(
      currentIsCompleted: isCompleted
    )
    return await updateTimelineTaskCompletionAndWait(
      taskID: taskID,
      projectID: projectID,
      isCompleted: nextIsCompleted,
      completionDate: TimelineTaskCompletionTogglePolicy.completionDate(
        nextIsCompleted: nextIsCompleted
      ),
      targetState: nil,
      registerUndo: true
    )
  }

  func deleteTimelineProjectListWindowTask(
    _ taskID: UUID,
    projectID: UUID
  ) async -> Bool {
    do {
      _ = try await ObsidianRetainedTaskCommandService.deleteTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      await refreshTimelineProjectState(including: [projectID])
      retainedTimelineCalendarBridgeDecisionsByTaskID.removeValue(forKey: taskID)
      retainedTimelineCalendarBridgeWriteMarkersByTaskID.removeValue(forKey: taskID)
      appState.bumpWorkspaceTreeRevision()
      return true
    } catch {
      appState.reportError(error, logMessage: "timeline project list deleteTask failed")
      return false
    }
  }

  func saveTimelineProjectListWindowTaskOrder(
    projectID: UUID,
    orderedTaskIDs: [UUID]
  ) {
    TimelineProjectTaskManualOrderStore.saveProjectOrder(orderedTaskIDs, for: projectID)
  }

  func editTimelineTaskFromProjectListWindow(taskID: UUID, projectID: UUID) {
    guard let entry = workspaceTimelineScheduleEntriesByProjectID[projectID]?.first(where: {
      $0.taskID == taskID
    }) else {
      return
    }
    onEditTask(
      WorkspaceTaskEditPanelTarget(
        projectID: projectID,
        taskID: taskID,
        initialFields: timelineTaskEditFields(for: entry)
      )
    )
  }

  func timelineProjectListWindowSnapshot(
    for bar: TimelineProjectBar
  ) -> TimelineProjectListWindowSnapshot {
    let entries = timelineProjectListWindowEntries(for: bar.projectID)
    return TimelineProjectListWindowSnapshot(
      projectID: bar.projectID,
      title: bar.title,
      colorHex: bar.colorHex,
      tasks: entries.map { entry in
        TimelineProjectListWindowSnapshot.Task(
          id: entry.taskID,
          title: timelinePreviewTitle(for: entry.title),
          dateText: timelineProjectListDateText(for: entry),
          isCompleted: entry.isCompleted,
          isOverdue: timelineProjectListEntryIsOverdue(entry)
        )
      }
    )
  }

  func refreshOpenTimelineProjectListWindow(using bars: [TimelineProjectBar]) {
    let presentedProjectIDs = Set(TimelineProjectListWindowPresenter.shared.presentedProjectIDs)
    guard !presentedProjectIDs.isEmpty else { return }

    for bar in bars where presentedProjectIDs.contains(bar.projectID) {
      TimelineProjectListWindowPresenter.shared.refresh(
        snapshot: timelineProjectListWindowSnapshot(for: bar)
      )
    }
  }

  func timelineProjectListWindowEntries(for projectID: UUID) -> [ScheduleSliceEntry] {
    let entries = TimelineBoardReadPath.projectListWindowEntries(
      from: workspaceTimelineScheduleEntriesByProjectID[projectID] ?? []
    )
    let orderedTaskIDs = TimelineProjectTaskManualOrderStore.orderedTaskIDs(
      entries.map(\.taskID),
      using: TimelineProjectTaskManualOrderStore.projectOrder(for: projectID)
    )
    let entriesByTaskID = Dictionary(uniqueKeysWithValues: entries.map { ($0.taskID, $0) })
    return orderedTaskIDs.compactMap { entriesByTaskID[$0] }
  }

  func revealTimelineTaskDetail(taskID: UUID, projectID: UUID) {
    selectTimelineProject(projectID, commitDelay: .zero)
    activeTimelineProjectListPopoverProjectID = nil
    activeTimelineTaskEditTarget = nil
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
    selectTimelineProject(projectID, commitDelay: .zero)
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

  func showTimelineTaskEditor(taskID: UUID, projectID: UUID) {
    activeTimelineTaskEditTarget = TimelineTaskEditTarget(
      projectID: projectID,
      taskID: taskID
    )
  }

  func timelineTaskEditorBinding(taskID: UUID, projectID: UUID) -> Binding<Bool> {
    Binding(
      get: {
        activeTimelineTaskEditTarget == TimelineTaskEditTarget(
          projectID: projectID,
          taskID: taskID
        )
      },
      set: { isPresented in
        if isPresented {
          showTimelineTaskEditor(taskID: taskID, projectID: projectID)
        } else if activeTimelineTaskEditTarget == TimelineTaskEditTarget(
          projectID: projectID,
          taskID: taskID
        ) {
          activeTimelineTaskEditTarget = nil
        }
      }
    )
  }

  func timelineTaskEditFields(for entry: ScheduleSliceEntry) -> RetainedTaskEditFields {
    let date = ReminderTaskDateCanonicalizer.unifiedDate(
      dueDate: entry.dueDate,
      startDate: entry.startDate,
      displayedDate: entry.displayedDate
    )
    return RetainedTaskEditFields(
      title: timelinePreviewTitle(for: entry.title),
      noteText: entry.reminderNoteText,
      day: date.map { calendar.startOfDay(for: $0) },
      timeMinutes: entry.scheduleHasExplicitTime ? date.map(timelineTaskEditTimeMinutes) : nil,
      durationMinutes: entry.scheduledDurationMinutes
    )
  }

  func loadTimelineTaskEditFields(
    projectID: UUID,
    taskID: UUID,
    fallback: RetainedTaskEditFields
  ) async -> RetainedTaskEditFields {
    do {
      return try await ObsidianRetainedTaskCommandService.taskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        calendar: calendar
      )
    } catch {
      appState.errorMessage = error.localizedDescription
      return fallback
    }
  }

  func selectTimelineProject(
    _ projectID: UUID,
    commitDelay: Duration = .milliseconds(140)
  ) {
    if immediateSelectedProjectID != projectID {
      immediateSelectedProjectID = projectID
    }

    selectionCommitTask?.cancel()
    guard selectedProjectID != projectID else {
      selectionCommitTask = nil
      return
    }

    selectionCommitTask = Task { @MainActor in
      if commitDelay > .zero {
        do {
          try await Task.sleep(for: commitDelay)
        } catch {
          return
        }
      }
      guard !Task.isCancelled, immediateSelectedProjectID == projectID else { return }
      onSelectProject(projectID)
    }
  }

  func saveTimelineTaskEditFields(
    _ fields: RetainedTaskEditFields,
    projectID: UUID,
    taskID: UUID
  ) async throws {
    do {
      let result = try await ObsidianRetainedTaskCommandService.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        fields: fields,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      await refreshTimelineProjectState(including: [projectID])
      retainedTimelineCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
      retainedTimelineCalendarBridgeWriteMarkersByTaskID[taskID] = result.calendarWriteMarker
      activeTimelineTaskEditTarget = nil
    } catch {
      appState.errorMessage = error.localizedDescription
      throw error
    }
  }

  private func timelineTaskEditTimeMinutes(for date: Date) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  func completeTimelineTask(_ taskID: UUID, projectID: UUID) {
    toggleTimelineTaskCompletion(taskID, projectID: projectID, isCompleted: false)
  }

  func toggleTimelineTaskCompletion(_ taskID: UUID, projectID: UUID, isCompleted: Bool) {
    let nextIsCompleted = TimelineTaskCompletionTogglePolicy.nextIsCompleted(
      currentIsCompleted: isCompleted
    )
    updateTimelineTaskCompletion(
      taskID: taskID,
      projectID: projectID,
      isCompleted: nextIsCompleted,
      completionDate: TimelineTaskCompletionTogglePolicy.completionDate(
        nextIsCompleted: nextIsCompleted
      ),
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
      await updateTimelineTaskCompletionAndWait(
        taskID: taskID,
        projectID: projectID,
        previousState: previousState,
        nextState: nextState,
        registerUndo: registerUndo
      )
    }
  }

  @discardableResult
  private func updateTimelineTaskCompletionAndWait(
    taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    targetState: TimelineTaskCompletionUndoSnapshot?,
    registerUndo: Bool
  ) async -> Bool {
    guard allowTimelineRetainedWrite("task-completion") else { return false }
    guard let previousState = timelineTaskCompletionState(taskID: taskID, projectID: projectID) else {
      return false
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
    guard previousState != nextState else { return true }
    return await updateTimelineTaskCompletionAndWait(
      taskID: taskID,
      projectID: projectID,
      previousState: previousState,
      nextState: nextState,
      registerUndo: registerUndo
    )
  }

  @discardableResult
  private func updateTimelineTaskCompletionAndWait(
    taskID: UUID,
    projectID: UUID,
    previousState: TimelineTaskCompletionUndoSnapshot,
    nextState: TimelineTaskCompletionUndoSnapshot,
    registerUndo: Bool
  ) async -> Bool {
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

      guard registerUndo else { return true }
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
      return true
    } catch {
      appState.errorMessage = error.localizedDescription
      return false
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

  func requestRename(for bar: TimelineProjectBar) {
    requestRename(projectID: bar.projectID, title: bar.title)
  }

  func requestRename(projectID: UUID, title: String) {
    guard allowTimelineRetainedWrite("rename-project") else { return }
    pendingRenameProject = TimelineProjectRenameRequest(id: projectID, title: title)
  }

  func submitTimelineProjectRename(projectID: UUID, title: String) {
    guard !isRenamingProject else { return }
    guard allowTimelineRetainedWrite("rename-project") else { return }
    isRenamingProject = true
    Task { @MainActor in
      let didRename = await appState.renameProject(
        projectID,
        to: title,
        context: modelContext
      )
      isRenamingProject = false
      if didRename {
        pendingRenameProject = nil
        await refreshTimelineProjectState(including: [projectID])
      }
    }
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
    applyTimelineProjectManualOrder(nextOrder)

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
