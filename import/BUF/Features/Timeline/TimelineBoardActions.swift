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
    let nextOrder = TimelineProjectManualOrderStore.mergedStoredOrder(
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

  func restoreTimelineProjectManualOrder(
    _ nextOrder: [UUID: Int64],
    actionName: String = "프로젝트 순서 변경",
    registerUndo: Bool = true
  ) {
    let previousOrder = timelineProjectManualOrder
    guard previousOrder != nextOrder else { return }
    applyTimelineProjectManualOrder(nextOrder)
    guard registerUndo else { return }
    appState.registerUndo(with: undoManager, actionName: actionName) {
      self.restoreTimelineProjectManualOrder(
        previousOrder,
        actionName: actionName,
        registerUndo: true
      )
    }
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
      onReorderTasks: { projectID, orderedTaskIDs, registerUndo in
        self.saveTimelineProjectListWindowTaskOrder(
          projectID: projectID,
          orderedTaskIDs: orderedTaskIDs,
          registerUndo: registerUndo
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
      },
      onSaveProjectNote: { projectID, noteText in
        await self.saveTimelineProjectListWindowProjectNote(
          noteText,
          projectID: projectID
        )
      }
    )
  }

  func openTimelineProjectListPanel(for bar: TimelineProjectBar) {
    selectTimelineProject(bar.projectID, commitDelay: .zero)
    activeTimelineProjectListPopoverProjectID = nil
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()

    onOpenProjectListPanel(bar.projectID)
  }

  func createTimelineProjectListWindowTask(
    _ rawTitle: String,
    projectID: UUID,
    registerUndo: Bool = true
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
      appState.bumpWorkspaceTreeRevision()
      await refreshTimelineProjectState(including: [projectID])
      retainedTimelineCalendarBridgeDecisionsByTaskID[result.taskID] = result.calendarBridgeDecision
      retainedTimelineCalendarBridgeWriteMarkersByTaskID[result.taskID] = result.calendarWriteMarker
      if registerUndo {
        appState.registerUndo(with: undoManager, actionName: "할일 추가") {
          Task { @MainActor in
            _ = await self.deleteTimelineProjectListWindowTask(
              result.taskID,
              projectID: projectID,
              registerUndo: false
            )
          }
        }
      }
      return TimelineProjectListWindowSnapshot.Task(
        id: result.taskID,
        title: timelinePreviewTitle(for: title),
        dateText: nil,
        notePreviewText: nil,
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
    projectID: UUID,
    registerUndo: Bool = true,
    undoTitle: String? = nil
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
      appState.bumpWorkspaceTreeRevision()
      await refreshTimelineProjectState(including: [projectID])
      retainedTimelineCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
      retainedTimelineCalendarBridgeWriteMarkersByTaskID[taskID] = result.calendarWriteMarker
      let previousTitle = undoTitle ?? entry.title
      if registerUndo, previousTitle != title {
        appState.registerUndo(with: undoManager, actionName: "할일 이름 변경") {
          Task { @MainActor in
            _ = await self.renameTimelineProjectListWindowTask(
              previousTitle,
              taskID: taskID,
              projectID: projectID,
              registerUndo: true,
              undoTitle: title
            )
          }
        }
      }
      return TimelineProjectListWindowSnapshot.Task(
        id: taskID,
        title: timelinePreviewTitle(for: title),
        dateText: timelineProjectListDateText(for: entry),
        notePreviewText: TimelineProjectListWindowSnapshotFactory.notePreviewText(for: entry),
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
    projectID: UUID,
    registerUndo: Bool = true
  ) async -> Bool {
    let undoSnapshot = scheduleEntry(taskID: taskID, projectID: projectID).map(taskUndoSnapshot)
    do {
      _ = try await ObsidianRetainedTaskCommandService.deleteTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      appState.bumpWorkspaceTreeRevision()
      await refreshTimelineProjectState(including: [projectID])
      retainedTimelineCalendarBridgeDecisionsByTaskID.removeValue(forKey: taskID)
      retainedTimelineCalendarBridgeWriteMarkersByTaskID.removeValue(forKey: taskID)
      if activeTimelineTaskEditTarget == TimelineTaskEditTarget(projectID: projectID, taskID: taskID) {
        activeTimelineTaskEditTarget = nil
      }
      onTaskDeleted(projectID, taskID)
      if registerUndo, let undoSnapshot {
        appState.registerUndo(with: undoManager, actionName: "할일 삭제") {
          Task { @MainActor in
            _ = await self.recreateTimelineProjectListWindowTask(
              undoSnapshot,
              projectID: projectID,
              registerUndo: false
            )
          }
        }
      }
      return true
    } catch {
      appState.reportError(error, logMessage: "timeline project list deleteTask failed")
      return false
    }
  }

  func saveTimelineProjectListWindowTaskOrder(
    projectID: UUID,
    orderedTaskIDs: [UUID],
    registerUndo: Bool = true
  ) {
    let currentStoredOrder = TimelineProjectTaskManualOrderStore.projectOrder(for: projectID)
    let previousOrder = TimelineProjectTaskManualOrderStore.orderedTaskIDs(
      orderedTaskIDs,
      using: currentStoredOrder
    )
    guard TimelineProjectTaskManualOrderStore.shouldSaveProjectOrder(
      orderedTaskIDs,
      currentStoredOrder: currentStoredOrder
    ) else {
      return
    }
    TimelineProjectTaskManualOrderStore.saveProjectOrder(orderedTaskIDs, for: projectID)
    Task { @MainActor in
      await appState.persistAppOwnedProjectTaskOrder(
        projectID: projectID,
        orderedTaskIDs: orderedTaskIDs
      )
    }
    guard registerUndo, previousOrder != orderedTaskIDs else { return }
    appState.registerUndo(with: undoManager, actionName: "목록 순서 변경") {
      self.saveTimelineProjectListWindowTaskOrder(
        projectID: projectID,
        orderedTaskIDs: previousOrder,
        registerUndo: true
      )
    }
  }

  func recreateTimelineProjectListWindowTask(
    _ snapshot: RetainedTaskUndoSnapshot,
    projectID: UUID,
    registerUndo: Bool = true
  ) async -> TimelineProjectListWindowSnapshot.Task? {
    guard let created = await createTimelineProjectListWindowTask(
      snapshot.fields.title,
      projectID: projectID,
      registerUndo: false
    ) else {
      return nil
    }

    do {
      let result = try await ObsidianRetainedTaskCommandService.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: created.id,
        fields: snapshot.fields,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      retainedTimelineCalendarBridgeDecisionsByTaskID[created.id] = result.calendarBridgeDecision
      retainedTimelineCalendarBridgeWriteMarkersByTaskID[created.id] = result.calendarWriteMarker
      if snapshot.isCompleted {
        _ = await updateTimelineTaskCompletionAndWait(
          taskID: created.id,
          projectID: projectID,
          isCompleted: true,
          completionDate: snapshot.completionDate,
          targetState: nil,
          registerUndo: false
        )
      } else {
        appState.bumpWorkspaceTreeRevision()
        await refreshTimelineProjectState(including: [projectID])
      }
      if registerUndo {
        appState.registerUndo(with: undoManager, actionName: "할일 삭제 취소") {
          Task { @MainActor in
            _ = await self.deleteTimelineProjectListWindowTask(
              created.id,
              projectID: projectID,
              registerUndo: false
            )
          }
        }
      }
      return TimelineProjectListWindowSnapshot.Task(
        id: created.id,
        title: timelinePreviewTitle(for: snapshot.fields.title),
        dateText: nil,
        notePreviewText: TimelineProjectListWindowSnapshotFactory.notePreviewText(
          for: snapshot.fields.noteText
        ),
        isCompleted: snapshot.isCompleted,
        isOverdue: false
      )
    } catch {
      appState.reportError(error, logMessage: "timeline project list recreateTask failed")
      return nil
    }
  }

  func editTimelineTaskFromProjectListWindow(taskID: UUID, projectID: UUID) {
    guard let entry = workspaceTimelineScheduleEntriesByProjectID[projectID]?.first(where: {
      $0.taskID == taskID
    }) else {
      return
    }
    openTimelineTaskEditor(
      WorkspaceTaskEditPanelTarget(
        projectID: projectID,
        taskID: taskID,
        initialFields: timelineTaskEditFields(for: entry)
      )
    )
  }

  func suppressTimelineTaskTap(
    for duration: TimeInterval = TaskTapSuppressionPolicy.completionControlDuration
  ) {
    suppressedTimelineTaskTapUntil = TaskTapSuppressionPolicy.suppressedUntil(
      now: Date(),
      duration: duration
    )
  }

  func shouldHandleTimelineTaskTap() -> Bool {
    TaskTapSuppressionPolicy.shouldHandleTaskTap(
      now: Date(),
      suppressedUntil: suppressedTimelineTaskTapUntil
    )
  }

  func openTimelineTaskEditor(_ target: WorkspaceTaskEditPanelTarget) {
    DispatchQueue.main.async {
      guard shouldHandleTimelineTaskTap() else { return }
      onEditTask(target)
    }
  }

  func timelineProjectListWindowSnapshot(
    for bar: TimelineProjectBar
  ) -> TimelineProjectListWindowSnapshot {
    TimelineProjectListWindowSnapshotFactory.snapshot(
      projectID: bar.projectID,
      title: bar.title,
      colorHex: bar.colorHex,
      projectNoteText: workspaceTimelineProjectSnapshots[bar.projectID]?.projectNoteMarkdown ?? "",
      entries: workspaceTimelineScheduleEntriesByProjectID[bar.projectID] ?? [],
      calendar: calendar
    )
  }

  func saveTimelineProjectListWindowProjectNote(
    _ noteText: String,
    projectID: UUID
  ) async -> String? {
    do {
      let savedNote = try await ObsidianRetainedProjectCommandService.setProjectNote(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        noteText: noteText,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      appState.bumpWorkspaceTreeRevision()
      await refreshTimelineProjectState(including: [projectID])
      return savedNote
    } catch {
      appState.reportError(error, logMessage: "saveTimelineProjectListWindowProjectNote failed")
      return nil
    }
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
    TimelineProjectListWindowSnapshotFactory.orderedEntries(
      projectID: projectID,
      entries: workspaceTimelineScheduleEntriesByProjectID[projectID] ?? []
    )
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

  func taskUndoSnapshot(for entry: ScheduleSliceEntry) -> RetainedTaskUndoSnapshot {
    RetainedTaskUndoSnapshot(
      fields: timelineTaskEditFields(for: entry),
      isCompleted: entry.isCompleted,
      completionDate: entry.completionDate
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
      if RetainedTaskCommandErrorPolicy.isTaskNotFound(error, taskID: taskID) {
        activeTimelineTaskEditTarget = nil
        return fallback
      }
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
    taskID: UUID,
    registerUndo: Bool = true,
    undoFields: RetainedTaskEditFields? = nil
  ) async throws {
    let previousFields: RetainedTaskEditFields?
    if let undoFields {
      previousFields = undoFields
    } else {
      previousFields = try? await ObsidianRetainedTaskCommandService.taskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        calendar: calendar
      )
    }
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
      if registerUndo, let previousFields, previousFields != fields {
        appState.registerUndo(with: undoManager, actionName: "할일 편집") {
          Task { @MainActor in
            try? await self.saveTimelineTaskEditFields(
              previousFields,
              projectID: projectID,
              taskID: taskID,
              registerUndo: true,
              undoFields: fields
            )
          }
        }
      }
    } catch {
      if RetainedTaskCommandErrorPolicy.isTaskNotFound(error, taskID: taskID) {
        activeTimelineTaskEditTarget = nil
        return
      }
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
    undoTargetState: TimelineTaskCompletionUndoSnapshot? = nil,
    registerUndo: Bool
  ) {
    guard allowTimelineRetainedWrite("task-completion") else { return }
    Task { @MainActor in
      _ = await updateTimelineTaskCompletionAndWait(
        taskID: taskID,
        projectID: projectID,
        isCompleted: isCompleted,
        completionDate: completionDate,
        targetState: targetState,
        undoTargetState: undoTargetState,
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
    undoTargetState: TimelineTaskCompletionUndoSnapshot? = nil,
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
        occurrenceDate: previousState.occurrenceDate,
        editFields: previousState.editFields
      )
    guard previousState != nextState else { return true }
    return await updateTimelineTaskCompletionAndWait(
      taskID: taskID,
      projectID: projectID,
      previousState: previousState,
      nextState: nextState,
      undoTargetState: undoTargetState,
      registerUndo: registerUndo
    )
  }

  @discardableResult
  private func updateTimelineTaskCompletionAndWait(
    taskID: UUID,
    projectID: UUID,
    previousState: TimelineTaskCompletionUndoSnapshot,
    nextState: TimelineTaskCompletionUndoSnapshot,
    undoTargetState: TimelineTaskCompletionUndoSnapshot? = nil,
    registerUndo: Bool
  ) async -> Bool {
    do {
      let shouldRestoreSchedule = RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
        previousIsCompleted: previousState.isCompleted,
        nextIsCompleted: nextState.isCompleted,
        isRecurring: nextState.isRecurring,
        previousFields: previousState.editFields,
        fields: nextState.editFields
      )
      let shouldWriteCompletion = RecurringCompletionUndoScheduleRestorePolicy.shouldWriteCompletion(
        previousIsCompleted: previousState.isCompleted,
        nextIsCompleted: nextState.isCompleted,
        isRecurring: nextState.isRecurring,
        previousFields: previousState.editFields,
        fields: nextState.editFields
      )
      var result: RetainedTaskCommandResult?
      if shouldWriteCompletion {
        result = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          isCompleted: nextState.isCompleted,
          completionDate: nextState.isCompleted && nextState.isRecurring
            ? (nextState.occurrenceDate ?? nextState.completionDate)
            : nextState.completionDate,
          reminderProjectProvider: appState.reminderProjectProvider
        )
      }
      if shouldRestoreSchedule {
        result = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          day: nextState.editFields.day,
          timeMinutes: nextState.editFields.timeMinutes,
          durationMinutes: nextState.editFields.durationMinutes,
          calendar: calendar,
          reminderProjectProvider: appState.reminderProjectProvider,
          resetRecurringAnchor: nextState.isRecurring
        )
      }
      guard let result else {
        await refreshTimelineProjectState(including: [projectID])
        return true
      }
      await refreshTimelineProjectState(including: [projectID])
      retainedTimelineCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
      retainedTimelineCalendarBridgeWriteMarkersByTaskID[taskID] = result.calendarWriteMarker

      guard registerUndo else { return true }
      let registeredUndoState = undoTargetState ?? previousState
      appState.registerUndo(
        with: undoManager,
        actionName: nextState.isCompleted ? "할일 완료" : "할일 완료 취소"
      ) {
        self.updateTimelineTaskCompletion(
          taskID: taskID,
          projectID: projectID,
          isCompleted: registeredUndoState.isCompleted,
          completionDate: registeredUndoState.completionDate,
          targetState: registeredUndoState,
          undoTargetState: nextState,
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
    restoreTimelineProjectManualOrder(nextOrder)

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
    let changedProjectIDs = TimelineBoardReadPath.normalizedProjectIDs(
      additionalProjectIDs.filter { !excluded.contains($0) }
    )
    if changedProjectIDs.isEmpty {
      let requestedProjectIDs = TimelineBoardReadPath.normalizedProjectIDs(
        activeProjectIDs.filter { !excluded.contains($0) }
      )
      await reloadWorkspaceTimelineProjectDetails(for: requestedProjectIDs)
    } else {
      await reloadChangedWorkspaceTimelineProjectDetails(for: changedProjectIDs)
    }
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
      ),
      editFields: timelineTaskEditFields(for: entry)
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
