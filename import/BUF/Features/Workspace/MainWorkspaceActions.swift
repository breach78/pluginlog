import AppKit
import SwiftUI

struct WorkspaceOverdueTaskRolloverTarget: Equatable {
  let projectID: UUID
  let taskID: UUID
}

enum WorkspaceOverdueTaskRolloverPlanner {
  static func targets(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]],
    today: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> [WorkspaceOverdueTaskRolloverTarget] {
    let normalizedToday = calendar.startOfDay(for: today)
    var seenTaskIDs = Set<UUID>()
    var targets: [WorkspaceOverdueTaskRolloverTarget] = []

    for projectID in projectIDs {
      guard projectSnapshots[projectID]?.isArchived != true else { continue }

      for entry in scheduleEntriesByProjectID[projectID] ?? [] {
        guard !entry.isArchived, !entry.isCompleted else { continue }
        guard seenTaskIDs.insert(entry.taskID).inserted else { continue }
        guard let scheduledDate = entry.displayedDate ?? entry.dueDate ?? entry.startDate else {
          continue
        }
        guard calendar.startOfDay(for: scheduledDate) < normalizedToday else { continue }

        targets.append(WorkspaceOverdueTaskRolloverTarget(projectID: projectID, taskID: entry.taskID))
      }
    }

    return targets
  }
}

enum WorkspaceEscapeKeyAction: Equatable {
  case clearSearch
  case dismissInspector
  case dismissEditPanel
  case passThrough
}

enum WorkspaceEscapeKeyPolicy {
  static func action(
    hasActiveEditPanelTextResponder: Bool,
    hasSearchQuery: Bool,
    hasInspectorSelection: Bool,
    hasEditPanel: Bool
  ) -> WorkspaceEscapeKeyAction {
    if hasActiveEditPanelTextResponder {
      return .passThrough
    }
    if hasSearchQuery {
      return .clearSearch
    }
    if hasInspectorSelection {
      return .dismissInspector
    }
    if hasEditPanel {
      return .dismissEditPanel
    }
    return .passThrough
  }
}

extension MainWorkspaceView {
  func toggleSyncQuickAddPopover() {
    guard !syncQuickAddProjects.isEmpty else {
      appState.errorMessage = "할일을 추가할 기본 목록이 없습니다."
      return
    }
    chromeState.toggleSyncQuickAddPopover()
  }

  func dismissSyncQuickAddPopover() {
    chromeState.dismissSyncQuickAddPopover()
    NSApp.keyWindow?.endEditing(for: nil)
  }

  func createSyncQuickAddTask(_ title: String, projectID: UUID) {
    Task { @MainActor in
      let taskID = await appState.createTask(
        inProjectID: projectID,
        title: title,
        startDate: Calendar.autoupdatingCurrent.startOfDay(for: .now),
        durationMinutes: nil,
        context: modelContext
      )
      if let taskID {
        appState.registerUndo(with: undoManager, actionName: "할일 추가") {
          Task { @MainActor in
            do {
              _ = try await RetainedTaskCommandFacade.deleteTask(
                vaultRootURL: appState.obsidianVaultRootURL,
                projectID: projectID,
                taskID: taskID,
                reminderProjectProvider: appState.reminderProjectProvider
              )
              appState.bumpWorkspaceTreeRevision()
            } catch {
              appState.reportError(error, logMessage: "quick add undo deleteTask failed")
            }
          }
        }
      }
      selectProjectContext(projectID)
      dismissSyncQuickAddPopover()
    }
  }

  func rollOverdueTasksToTodayAllDay() {
    guard !isRollingOverdueTasksToToday else { return }
    let projectIDs = WorkspaceProjectReadPath.timelineInputProjectIDsInOrder(
      timelineOrderedProjectIDs: sidebarRootProjectIDs,
      sidebarProjects: workspaceSidebarProjects
    )
    guard !projectIDs.isEmpty else { return }

    isRollingOverdueTasksToToday = true
    Task { @MainActor in
      defer { isRollingOverdueTasksToToday = false }

      let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
        obsidianVaultRootURL: appState.obsidianVaultRootURL,
        projectIDs: projectIDs
      )
      let resolvedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(retainedResult)
      if case .blocked(let blocker) = resolvedRead.source {
        appState.errorMessage = blocker.userMessage
        return
      }

      let today = Calendar.autoupdatingCurrent.startOfDay(for: appState.currentDayStart)
      let targets = WorkspaceOverdueTaskRolloverPlanner.targets(
        projectIDs: projectIDs,
        projectSnapshots: resolvedRead.projectSnapshots,
        scheduleEntriesByProjectID: resolvedRead.scheduleEntriesByProjectID,
        today: today
      )
      guard !targets.isEmpty else { return }

      var appliedCount = 0
      do {
        for target in targets {
          _ = try await RetainedTaskCommandFacade.setTaskSchedule(
            vaultRootURL: appState.obsidianVaultRootURL,
            projectID: target.projectID,
            taskID: target.taskID,
            day: today,
            timeMinutes: nil,
            durationMinutes: nil,
            reminderProjectProvider: appState.reminderProjectProvider
          )
          appliedCount += 1
        }

        appState.bumpWorkspaceTreeRevision()
      } catch {
        if appliedCount > 0 {
          appState.bumpWorkspaceTreeRevision()
        }
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func submitSidebarNewProject(_ rawTitle: String) {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isCreatingSidebarProject else { return }
    isCreatingSidebarProject = true
    Task { @MainActor in
      let createdProjectID = await appState.createProjectList(named: title, context: modelContext)
      isCreatingSidebarProject = false
      showSidebarAddProjectPopover = false
      if let createdProjectID {
        selectProjectContext(createdProjectID)
      }
    }
  }

  func dismissInspectorSelection() {
    inspectorSelection = nil
    selectProjectContext(nil)
  }

  func revealTimelineTaskDetail(taskID: UUID, projectID: UUID) {
    openProjectTaskInSource(projectID: projectID, taskID: taskID)
  }

  func showTimelineTaskEditor(_ target: WorkspaceTaskEditPanelTarget) {
    guard shouldOpenWorkspaceTaskEditor() else { return }
    showArchive = false
    inspectorSelection = nil
    activeWorkspaceProjectListPanelProjectID = nil
    activeWorkspaceCalendarEventEditPanelTarget = nil
    activeWorkspaceScheduleMonthDetailTarget = nil
    previousWorkspaceScheduleMonthDetailTarget = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
    activeWorkspaceTaskEditPanelTarget = target
    selectProjectContext(target.projectID)
  }

  func openDailyJournalWindow() {
    DailyJournalWindowPresenter.shared.present(vaultRootURL: appState.obsidianVaultRootURL)
  }

  func suppressWorkspaceTaskEditorOpen(
    for duration: TimeInterval = TaskTapSuppressionPolicy.completionControlDuration
  ) {
    suppressedWorkspaceTaskEditorOpenUntil = TaskTapSuppressionPolicy.suppressedUntil(
      now: Date(),
      duration: duration
    )
  }

  func shouldOpenWorkspaceTaskEditor() -> Bool {
    TaskTapSuppressionPolicy.shouldHandleTaskTap(
      now: Date(),
      suppressedUntil: suppressedWorkspaceTaskEditorOpenUntil
    )
  }

  func showTimelineProjectListPanel(projectID: UUID) {
    showArchive = false
    inspectorSelection = nil
    activeWorkspaceTaskEditPanelTarget = nil
    activeWorkspaceCalendarEventEditPanelTarget = nil
    activeWorkspaceScheduleMonthDetailTarget = nil
    previousWorkspaceScheduleMonthDetailTarget = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
    activeWorkspaceProjectListPanelProjectID = projectID
    selectProjectContext(projectID)
  }

  func openWorkspaceTaskProjectListWindow(for target: WorkspaceTaskEditPanelTarget) {
    openWorkspaceProjectListWindow(projectID: target.projectID)
  }

  func workspaceProjectListActions(projectID: UUID) -> TimelineProjectListActions {
    TimelineProjectListActions(
      onToggleTaskCompletion: { taskID, isCompleted in
        await self.toggleWorkspaceProjectListWindowTaskCompletion(
          taskID,
          projectID: projectID,
          isCompleted: isCompleted
        )
      },
      onEditTask: { taskID in
        self.showTimelineTaskEditor(taskID: taskID, projectID: projectID)
      },
      onReorderTasks: { projectID, orderedTaskIDs, registerUndo in
        self.saveWorkspaceProjectListWindowTaskOrder(
          projectID: projectID,
          orderedTaskIDs: orderedTaskIDs,
          registerUndo: registerUndo
        )
      },
      onCreateTask: { projectID, title in
        await self.createWorkspaceProjectListWindowTask(title, projectID: projectID)
      },
      onRenameTask: { projectID, taskID, title in
        await self.renameWorkspaceProjectListWindowTask(
          title,
          taskID: taskID,
          projectID: projectID
        )
      },
      onDeleteTask: { projectID, taskID in
        await self.deleteWorkspaceProjectListWindowTask(taskID, projectID: projectID)
      },
      onRenameProject: { projectID, title in
        self.pendingRenameProject = .init(id: projectID, title: title)
      },
      onSaveProjectNote: { projectID, noteText in
        await self.saveWorkspaceProjectListWindowProjectNote(
          noteText,
          projectID: projectID
        )
      },
      moveOptions: {
        self.activeQuickAddProjects.map {
          TimelineProjectMoveOption(id: $0.id, title: $0.title)
        }
      },
      onMoveTask: { sourceProjectID, taskID, targetProjectID in
        await self.moveWorkspaceProjectListWindowTask(
          taskID,
          sourceProjectID: sourceProjectID,
          targetProjectID: targetProjectID
        )
      }
    )
  }

  func openWorkspaceProjectListWindow(projectID: UUID) {
    selectProjectContext(projectID)
    guard !TimelineProjectListWindowPresenter.shared.presentedProjectIDs.contains(projectID) else {
      return
    }

    Task { @MainActor in
      guard !TimelineProjectListWindowPresenter.shared.presentedProjectIDs.contains(projectID) else {
        return
      }
      guard let snapshot = await workspaceProjectListWindowSnapshot(projectID: projectID) else {
        return
      }

      TimelineProjectListWindowPresenter.shared.present(
        snapshot: snapshot,
        actions: workspaceProjectListActions(projectID: projectID)
      )
    }
  }

  func showTimelineTaskEditor(
    taskID: UUID,
    projectID: UUID,
    title: String,
    date: Date?,
    hasExplicitTime: Bool = false,
    durationMinutes: Int? = nil
  ) {
    let target = WorkspaceTaskEditPanelTarget(
      projectID: projectID,
      taskID: taskID,
      initialFields: timelineTaskEditFallbackFields(
        title: title,
        date: date,
        hasExplicitTime: hasExplicitTime,
        durationMinutes: durationMinutes
      )
    )
    showTimelineTaskEditor(target)
  }

  func showTimelineTaskEditor(taskID: UUID, projectID: UUID) {
    let target = WorkspaceTaskEditPanelTarget(
      projectID: projectID,
      taskID: taskID,
      initialFields: timelineTaskEditFallbackFields(
        title: "",
        date: nil
      )
    )
    showTimelineTaskEditor(target)
  }

  func dismissTimelineTaskEditor() {
    activeWorkspaceTaskEditPanelTarget = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
  }

  func dismissWorkspaceProjectListPanel() {
    activeWorkspaceProjectListPanelProjectID = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
  }

  func saveWorkspaceProjectListWindowProjectNote(
    _ noteText: String,
    projectID: UUID
  ) async -> String? {
    do {
      let savedNote = try await RetainedProjectCommandFacade.setProjectNote(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        noteText: noteText,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      appState.bumpWorkspaceTreeRevision()
      await refreshWorkspaceProjectListWindow(projectID: projectID)
      return savedNote
    } catch {
      appState.reportError(error, logMessage: "saveWorkspaceProjectListWindowProjectNote failed")
      return nil
    }
  }

  func createWorkspaceProjectListWindowTask(
    _ rawTitle: String,
    projectID: UUID,
    registerUndo: Bool = true
  ) async -> TimelineProjectListWindowSnapshot.Task? {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }

    do {
      let result = try await RetainedTaskCommandFacade.createTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        title: title,
        day: nil,
        timeMinutes: nil,
        durationMinutes: nil,
        calendar: .autoupdatingCurrent,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      appState.bumpWorkspaceTreeRevision()
      await refreshWorkspaceProjectListWindow(projectID: projectID)
      if registerUndo {
        appState.registerUndo(with: undoManager, actionName: "할일 추가") {
          Task { @MainActor in
            _ = await self.deleteWorkspaceProjectListWindowTask(
              result.taskID,
              projectID: projectID,
              registerUndo: false
            )
          }
        }
      }
      return await workspaceProjectListWindowTaskSnapshot(
        projectID: projectID,
        taskID: result.taskID
      )
    } catch {
      appState.reportError(error, logMessage: "workspace project list createTask failed")
      return nil
    }
  }

  func renameWorkspaceProjectListWindowTask(
    _ rawTitle: String,
    taskID: UUID,
    projectID: UUID,
    registerUndo: Bool = true,
    undoTitle: String? = nil
  ) async -> TimelineProjectListWindowSnapshot.Task? {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    guard let entry = await workspaceProjectListWindowEntry(projectID: projectID, taskID: taskID)
    else {
      return nil
    }
    var fields = workspaceTaskEditFields(for: entry)
    fields.title = title

    do {
      _ = try await RetainedTaskCommandFacade.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        fields: fields,
        calendar: .autoupdatingCurrent,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      appState.bumpWorkspaceTreeRevision()
      await refreshWorkspaceProjectListWindow(projectID: projectID)
      let previousTitle = undoTitle ?? entry.title
      if registerUndo, previousTitle != title {
        appState.registerUndo(with: undoManager, actionName: "할일 이름 변경") {
          Task { @MainActor in
            _ = await self.renameWorkspaceProjectListWindowTask(
              previousTitle,
              taskID: taskID,
              projectID: projectID,
              registerUndo: true,
              undoTitle: title
            )
          }
        }
      }
      return await workspaceProjectListWindowTaskSnapshot(projectID: projectID, taskID: taskID)
    } catch {
      appState.reportError(error, logMessage: "workspace project list renameTask failed")
      return nil
    }
  }

  func toggleWorkspaceProjectListWindowTaskCompletion(
    _ taskID: UUID,
    projectID: UUID,
    isCompleted: Bool
  ) async -> Bool {
    let nextIsCompleted = TimelineTaskCompletionTogglePolicy.nextIsCompleted(
      currentIsCompleted: isCompleted
    )
    return await setWorkspaceProjectListWindowTaskCompletion(
      taskID,
      projectID: projectID,
      isCompleted: nextIsCompleted,
      registerUndo: true
    )
  }

  func setWorkspaceProjectListWindowTaskCompletion(
    _ taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    completionDate: Date? = nil,
    registerUndo: Bool = true,
    restoreScheduleFields: RetainedTaskEditFields? = nil,
    undoTargetSnapshot: RetainedTaskUndoSnapshot? = nil
  ) async -> Bool {
    guard let entry = await workspaceProjectListWindowEntry(projectID: projectID, taskID: taskID)
    else {
      return false
    }
    let isRecurring = !(entry.recurrenceRuleRaw?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty ?? true)
    let nextCompletionDate =
      isCompleted
      ? (completionDate ?? .now)
      : nil
    let currentSnapshot = workspaceTaskUndoSnapshot(for: entry)
    let targetFields = restoreScheduleFields ?? currentSnapshot.fields
    let targetSnapshot = RetainedTaskUndoSnapshot(
      fields: targetFields,
      isCompleted: isCompleted,
      completionDate: nextCompletionDate
    )
    let shouldRestoreSchedule = RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
      previousIsCompleted: currentSnapshot.isCompleted,
      nextIsCompleted: targetSnapshot.isCompleted,
      isRecurring: isRecurring,
      previousFields: currentSnapshot.fields,
      fields: targetSnapshot.fields
    )
    let shouldWriteCompletion = RecurringCompletionUndoScheduleRestorePolicy.shouldWriteCompletion(
      previousIsCompleted: currentSnapshot.isCompleted,
      nextIsCompleted: targetSnapshot.isCompleted,
      isRecurring: isRecurring,
      previousFields: currentSnapshot.fields,
      fields: targetSnapshot.fields
    )
    guard shouldWriteCompletion || shouldRestoreSchedule else { return true }

    do {
      if shouldWriteCompletion {
        _ = try await RetainedTaskCommandFacade.setTaskCompletion(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          isCompleted: targetSnapshot.isCompleted,
          completionDate: targetSnapshot.completionDate,
          reminderProjectProvider: appState.reminderProjectProvider
        )
      }
      if shouldRestoreSchedule {
        _ = try await RetainedTaskCommandFacade.setTaskSchedule(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          day: targetSnapshot.fields.day,
          timeMinutes: targetSnapshot.fields.timeMinutes,
          durationMinutes: targetSnapshot.fields.durationMinutes,
          calendar: .autoupdatingCurrent,
          reminderProjectProvider: appState.reminderProjectProvider,
          resetRecurringAnchor: isRecurring
        )
      }
      appState.bumpWorkspaceTreeRevision()
      await refreshWorkspaceProjectListWindow(projectID: projectID)
      if registerUndo {
        let registeredUndoSnapshot = undoTargetSnapshot ?? currentSnapshot
        appState.registerUndo(
          with: undoManager,
          actionName: isCompleted ? "할일 완료" : "할일 완료 취소"
        ) {
          Task { @MainActor in
            _ = await self.setWorkspaceProjectListWindowTaskCompletion(
              taskID,
              projectID: projectID,
              isCompleted: registeredUndoSnapshot.isCompleted,
              completionDate: registeredUndoSnapshot.completionDate,
              registerUndo: true,
              restoreScheduleFields: registeredUndoSnapshot.fields,
              undoTargetSnapshot: targetSnapshot
            )
          }
        }
      }
      return true
    } catch {
      appState.reportError(error, logMessage: "workspace project list completion failed")
      return false
    }
  }

  func deleteWorkspaceProjectListWindowTask(
    _ taskID: UUID,
    projectID: UUID,
    registerUndo: Bool = true
  ) async -> Bool {
    let undoSnapshot = await workspaceProjectListWindowEntry(
      projectID: projectID,
      taskID: taskID
    ).map(workspaceTaskUndoSnapshot)
    do {
      _ = try await RetainedTaskCommandFacade.deleteTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      handleTimelineTaskDeleted(projectID: projectID, taskID: taskID)
      appState.bumpWorkspaceTreeRevision()
      await refreshWorkspaceProjectListWindow(projectID: projectID)
      if registerUndo, let undoSnapshot {
        appState.registerUndo(with: undoManager, actionName: "할일 삭제") {
          Task { @MainActor in
            _ = await self.recreateWorkspaceProjectListWindowTask(
              undoSnapshot,
              projectID: projectID,
              registerUndo: false
            )
          }
        }
      }
      return true
    } catch {
      appState.reportError(error, logMessage: "workspace project list deleteTask failed")
      return false
    }
  }

  func moveWorkspaceProjectListWindowTask(
    _ taskID: UUID,
    sourceProjectID: UUID,
    targetProjectID: UUID
  ) async -> Bool {
    guard sourceProjectID != targetProjectID else { return false }

    do {
      _ = try await RetainedTaskCommandFacade.moveTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        taskID: taskID,
        sourceProjectID: sourceProjectID,
        targetProjectID: targetProjectID,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      if let activeTarget = activeWorkspaceTaskEditPanelTarget,
        activeTarget.projectID == sourceProjectID,
        activeTarget.taskID == taskID
      {
        activeWorkspaceTaskEditPanelTarget = WorkspaceTaskEditPanelTarget(
          projectID: targetProjectID,
          taskID: taskID,
          initialFields: activeTarget.initialFields,
          initialFocus: activeTarget.initialFocus
        )
      }
      appState.bumpWorkspaceTreeRevision()
      await refreshWorkspaceProjectListWindow(projectID: sourceProjectID)
      await refreshWorkspaceProjectListWindow(projectID: targetProjectID)
      return true
    } catch {
      appState.reportError(error, logMessage: "workspace project list moveTask failed")
      return false
    }
  }

  func recreateWorkspaceProjectListWindowTask(
    _ snapshot: RetainedTaskUndoSnapshot,
    projectID: UUID,
    registerUndo: Bool = true
  ) async -> TimelineProjectListWindowSnapshot.Task? {
    guard let created = await createWorkspaceProjectListWindowTask(
      snapshot.fields.title,
      projectID: projectID,
      registerUndo: false
    ) else {
      return nil
    }

    do {
      _ = try await RetainedTaskCommandFacade.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: created.id,
        fields: snapshot.fields,
        calendar: .autoupdatingCurrent,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      if snapshot.isCompleted {
        _ = await setWorkspaceProjectListWindowTaskCompletion(
          created.id,
          projectID: projectID,
          isCompleted: true,
          completionDate: snapshot.completionDate,
          registerUndo: false
        )
      }
      appState.bumpWorkspaceTreeRevision()
      await refreshWorkspaceProjectListWindow(projectID: projectID)
      if registerUndo {
        appState.registerUndo(with: undoManager, actionName: "할일 삭제 취소") {
          Task { @MainActor in
            _ = await self.deleteWorkspaceProjectListWindowTask(
              created.id,
              projectID: projectID,
              registerUndo: false
            )
          }
        }
      }
      return await workspaceProjectListWindowTaskSnapshot(
        projectID: projectID,
        taskID: created.id
      )
    } catch {
      appState.reportError(error, logMessage: "workspace project list recreateTask failed")
      return nil
    }
  }

  func saveWorkspaceProjectListWindowTaskOrder(
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
      self.saveWorkspaceProjectListWindowTaskOrder(
        projectID: projectID,
        orderedTaskIDs: previousOrder,
        registerUndo: true
      )
    }
  }

  func refreshWorkspaceProjectListWindow(projectID: UUID) async {
    guard let snapshot = await workspaceProjectListWindowSnapshot(projectID: projectID) else {
      return
    }
    TimelineProjectListWindowPresenter.shared.refresh(snapshot: snapshot)
  }

  func handleTimelineTaskDeleted(projectID: UUID, taskID: UUID) {
    guard activeWorkspaceTaskEditPanelTarget?.projectID == projectID,
      activeWorkspaceTaskEditPanelTarget?.taskID == taskID
    else {
      return
    }
    dismissTimelineTaskEditor()
  }

  func showCalendarEventEditor(_ event: ScheduleCalendarEvent) {
    showArchive = false
    inspectorSelection = nil
    activeWorkspaceTaskEditPanelTarget = nil
    activeWorkspaceProjectListPanelProjectID = nil
    activeWorkspaceScheduleMonthDetailTarget = nil
    previousWorkspaceScheduleMonthDetailTarget = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
    activeWorkspaceCalendarEventEditPanelTarget = WorkspaceCalendarEventEditPanelTarget(
      eventID: event.id,
      event: event,
      initialFields: ScheduleCalendarEventEditPanelContent.editFields(for: event)
    )
  }

  func dismissCalendarEventEditor() {
    activeWorkspaceCalendarEventEditPanelTarget = nil
  }

  func showScheduleMonthDetail(_ target: ScheduleMonthDetailPanelTarget) {
    showArchive = false
    inspectorSelection = nil
    activeWorkspaceTaskEditPanelTarget = nil
    activeWorkspaceCalendarEventEditPanelTarget = nil
    activeWorkspaceProjectListPanelProjectID = nil
    previousWorkspaceScheduleMonthDetailTarget = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
    activeWorkspaceScheduleMonthDetailTarget = target
  }

  func dismissScheduleMonthDetail() {
    activeWorkspaceScheduleMonthDetailTarget = nil
    previousWorkspaceScheduleMonthDetailTarget = nil
    activeScheduleMonthExternalDropDay = nil
    scheduleMonthDetailDropTarget = nil
  }

  func scheduleMonthDropDay(at globalPoint: CGPoint) -> Date? {
    ScheduleMonthDropTargetResolver.day(
      at: globalPoint,
      targets: scheduleMonthDropTargets,
      calendar: .autoupdatingCurrent
    )
  }

  func updateScheduleMonthDetailAfterMovedItem(_ item: ScheduleMonthItem) {
    guard let target = activeWorkspaceScheduleMonthDetailTarget else { return }
    activeWorkspaceScheduleMonthDetailTarget =
      ScheduleMonthDetailTargetUpdater.applyingMovedItem(
        item,
        to: target,
        calendar: .autoupdatingCurrent
      )
  }

  func openScheduleMonthDetailItem(_ item: ScheduleMonthItem) {
    let backTarget = activeWorkspaceScheduleMonthDetailTarget
    switch item.source {
    case .workspaceTask(let taskID, let projectID):
      showTimelineTaskEditor(
        taskID: taskID,
        projectID: projectID,
        title: item.title,
        date: item.startDate,
        hasExplicitTime: item.hasExplicitTime,
        durationMinutes: item.durationMinutes
      )
      previousWorkspaceScheduleMonthDetailTarget = backTarget
    case .calendarEvent:
      guard let event = item.calendarEvent else { return }
      showCalendarEventEditor(event)
      previousWorkspaceScheduleMonthDetailTarget = backTarget
    }
  }

  func toggleScheduleMonthDetailTaskCompletion(
    _ item: ScheduleMonthItem,
    isCompleted: Bool
  ) async -> ScheduleMonthItem? {
    guard case .workspaceTask(let taskID, let projectID) = item.source else { return nil }
    let didSave = await setWorkspaceProjectListWindowTaskCompletion(
      taskID,
      projectID: projectID,
      isCompleted: isCompleted,
      registerUndo: true
    )
    guard didSave else { return nil }
    return scheduleMonthDetailItem(item, isCompleted: isCompleted)
  }

  func updateScheduleMonthDetailItemSchedule(
    _ item: ScheduleMonthItem,
    day: Date,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) async -> ScheduleMonthItem? {
    switch item.source {
    case .workspaceTask(let taskID, let projectID):
      return await updateScheduleMonthDetailTaskSchedule(
        item,
        taskID: taskID,
        projectID: projectID,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    case .calendarEvent:
      return await updateScheduleMonthDetailCalendarEventSchedule(
        item,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    }
  }

  func createScheduleMonthDetailTask(
    title: String,
    projectID: UUID,
    day: Date,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) async -> ScheduleMonthItem? {
    let calendar = Calendar.autoupdatingCurrent
    let normalizedDay = calendar.startOfDay(for: day)
    let startDate = scheduleMonthDetailStartDate(
      day: normalizedDay,
      timeMinutes: timeMinutes,
      calendar: calendar
    )
    let taskID = await appState.createTask(
      inProjectID: projectID,
      title: title,
      startDate: startDate,
      durationMinutes: timeMinutes == nil ? nil : durationMinutes,
      context: modelContext
    )
    guard let taskID else { return nil }

    appState.registerUndo(with: undoManager, actionName: "할일 추가") {
      Task { @MainActor in
        do {
          _ = try await RetainedTaskCommandFacade.deleteTask(
            vaultRootURL: appState.obsidianVaultRootURL,
            projectID: projectID,
            taskID: taskID,
            reminderProjectProvider: appState.reminderProjectProvider
          )
          appState.bumpWorkspaceTreeRevision()
        } catch {
          appState.reportError(error, logMessage: "schedule month detail quick add undo failed")
        }
      }
    }

    let descriptor = workspaceProjectDescriptorsByID[projectID]
    return ScheduleMonthItem(
      id: "workspace-task-\(taskID.uuidString)",
      source: .workspaceTask(taskID: taskID, projectID: projectID),
      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
      subtitle: descriptor?.title,
      startDate: startDate,
      endDate: scheduleMonthDetailEndDate(
        day: normalizedDay,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes,
        calendar: calendar
      ),
      isAllDay: timeMinutes == nil,
      colorHex: descriptor?.colorHex,
      isCompleted: false,
      isPreparationSlot: false,
      isBackgroundCalendar: false,
      calendarEvent: nil
    )
  }

  func deleteScheduleMonthDetailItem(
    _ item: ScheduleMonthItem,
    scope: ScheduleCalendarRecurringEditScope?
  ) async -> Bool {
    switch item.source {
    case .workspaceTask(let taskID, let projectID):
      return await deleteScheduleMonthDetailTask(taskID: taskID, projectID: projectID)
    case .calendarEvent:
      return await deleteScheduleMonthDetailCalendarEvent(item, scope: scope ?? .thisEvent)
    }
  }

  private func deleteScheduleMonthDetailTask(taskID: UUID, projectID: UUID) async -> Bool {
    await deleteWorkspaceProjectListWindowTask(taskID, projectID: projectID)
  }

  private func deleteScheduleMonthDetailCalendarEvent(
    _ item: ScheduleMonthItem,
    scope: ScheduleCalendarRecurringEditScope
  ) async -> Bool {
    guard let event = item.calendarEvent, event.canEditTiming else { return false }
    do {
      let snapshot = try await appState.deleteScheduleCalendarEvent(
        event,
        scope: scope,
        undoManager: undoManager
      )
      appState.registerUndo(with: undoManager, actionName: "캘린더 일정 삭제") {
        Task { @MainActor in
          do {
            _ = try await appState.restoreDeletedScheduleCalendarEvent(
              snapshot,
              undoManager: undoManager
            )
          } catch {
            appState.reportError(
              error,
              logMessage: "schedule month detail calendar restore failed"
            )
          }
        }
      }
      return true
    } catch {
      appState.reportError(error, logMessage: "schedule month detail calendar delete failed")
      return false
    }
  }

  private func updateScheduleMonthDetailTaskSchedule(
    _ item: ScheduleMonthItem,
    taskID: UUID,
    projectID: UUID,
    day: Date,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) async -> ScheduleMonthItem? {
    let calendar = Calendar.autoupdatingCurrent
    let normalizedDay = calendar.startOfDay(for: day)
    let previousDay = calendar.startOfDay(for: item.startDate)
    let previousTimeMinutes = item.isAllDay ? nil : scheduleMonthDetailTimeMinutes(item.startDate, calendar: calendar)
    let previousDuration = item.durationMinutes

    do {
      _ = try await RetainedTaskCommandFacade.setTaskSchedule(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        day: normalizedDay,
        timeMinutes: timeMinutes,
        durationMinutes: timeMinutes == nil ? nil : durationMinutes,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      appState.bumpWorkspaceTreeRevision()
      appState.registerUndo(with: undoManager, actionName: "일정 변경") {
        Task { @MainActor in
          do {
            _ = try await RetainedTaskCommandFacade.setTaskSchedule(
              vaultRootURL: appState.obsidianVaultRootURL,
              projectID: projectID,
              taskID: taskID,
              day: previousDay,
              timeMinutes: previousTimeMinutes,
              durationMinutes: previousDuration,
              calendar: calendar,
              reminderProjectProvider: appState.reminderProjectProvider
            )
            appState.bumpWorkspaceTreeRevision()
          } catch {
            appState.reportError(error, logMessage: "schedule month detail task schedule undo failed")
          }
        }
      }
      return scheduleMonthDetailItem(
        item,
        startDate: scheduleMonthDetailStartDate(
          day: normalizedDay,
          timeMinutes: timeMinutes,
          calendar: calendar
        ),
        endDate: scheduleMonthDetailEndDate(
          day: normalizedDay,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes,
          calendar: calendar
        ),
        isAllDay: timeMinutes == nil
      )
    } catch {
      appState.reportError(error, logMessage: "schedule month detail task schedule failed")
      return nil
    }
  }

  private func updateScheduleMonthDetailCalendarEventSchedule(
    _ item: ScheduleMonthItem,
    day: Date,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) async -> ScheduleMonthItem? {
    guard let event = item.calendarEvent, event.canEditTiming else { return nil }
    let calendar = Calendar.autoupdatingCurrent
    let normalizedDay = calendar.startOfDay(for: day)
    let previousPreview = ScheduleInteractionPreview(
      day: calendar.startOfDay(for: event.startDate),
      timeMinutes: event.isAllDay ? nil : scheduleMonthDetailTimeMinutes(event.startDate, calendar: calendar),
      durationMinutes: event.isAllDay
        ? nil
        : max(5, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
    )
    let preview = ScheduleInteractionPreview(
      day: normalizedDay,
      timeMinutes: timeMinutes,
      durationMinutes: timeMinutes == nil ? nil : durationMinutes
    )

    do {
      let updatedEvent = try await appState.writeScheduleCalendarEventTiming(
        event,
        preview: preview,
        scope: .thisEvent
      )
      appState.registerUndo(with: undoManager, actionName: "일정 변경") {
        Task { @MainActor in
          do {
            _ = try await appState.writeScheduleCalendarEventTiming(
              updatedEvent,
              preview: previousPreview,
              scope: .thisEvent
            )
          } catch {
            appState.reportError(error, logMessage: "schedule month detail calendar undo failed")
          }
        }
      }
      return ScheduleMonthItem(
        id: "calendar-\(updatedEvent.id)",
        source: .calendarEvent(eventID: updatedEvent.id),
        title: updatedEvent.title,
        subtitle: updatedEvent.calendarTitle,
        startDate: updatedEvent.startDate,
        endDate: updatedEvent.endDate,
        isAllDay: updatedEvent.isAllDay,
        colorHex: updatedEvent.calendarColorHex,
        isCompleted: false,
        isPreparationSlot: false,
        isBackgroundCalendar: item.isBackgroundCalendar,
        calendarEvent: updatedEvent
      )
    } catch {
      appState.reportError(error, logMessage: "schedule month detail calendar schedule failed")
      return nil
    }
  }

  private func scheduleMonthDetailItem(
    _ item: ScheduleMonthItem,
    startDate: Date? = nil,
    endDate: Date? = nil,
    isAllDay: Bool? = nil,
    isCompleted: Bool? = nil
  ) -> ScheduleMonthItem {
    ScheduleMonthItem(
      id: item.id,
      source: item.source,
      title: item.title,
      subtitle: item.subtitle,
      startDate: startDate ?? item.startDate,
      endDate: endDate ?? item.endDate,
      isAllDay: isAllDay ?? item.isAllDay,
      colorHex: item.colorHex,
      isCompleted: isCompleted ?? item.isCompleted,
      isPreparationSlot: item.isPreparationSlot,
      isBackgroundCalendar: item.isBackgroundCalendar,
      calendarEvent: item.calendarEvent
    )
  }

  private func scheduleMonthDetailStartDate(
    day: Date,
    timeMinutes: Int?,
    calendar: Calendar
  ) -> Date {
    let normalizedDay = calendar.startOfDay(for: day)
    guard let timeMinutes else { return normalizedDay }
    return calendar.date(byAdding: .minute, value: timeMinutes, to: normalizedDay) ?? normalizedDay
  }

  private func scheduleMonthDetailEndDate(
    day: Date,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar
  ) -> Date {
    let start = scheduleMonthDetailStartDate(day: day, timeMinutes: timeMinutes, calendar: calendar)
    guard timeMinutes != nil else {
      return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? start
    }
    return calendar.date(byAdding: .minute, value: durationMinutes ?? 30, to: start) ?? start
  }

  private func scheduleMonthDetailTimeMinutes(_ date: Date, calendar: Calendar) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  func loadCalendarEventEditFields(
    eventID: String,
    fallback: ScheduleCalendarEventEditFields
  ) async -> ScheduleCalendarEventEditFields {
    guard let event = appState.resolvedScheduleCalendarEvent(eventID: eventID) else {
      return fallback
    }
    return ScheduleCalendarEventEditPanelContent.editFields(for: event)
  }

  func saveCalendarEventEditFields(
    _ fields: ScheduleCalendarEventEditFields,
    eventID: String,
    fallbackEvent: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEventEditFields {
    let event = appState.resolvedScheduleCalendarEvent(eventID: eventID) ?? fallbackEvent
    do {
      let updatedEvent = try await appState.writeScheduleCalendarEventFields(
        event,
        fields: fields,
        scope: scope
      )
      let updatedFields = ScheduleCalendarEventEditPanelContent.editFields(for: updatedEvent)
      if activeWorkspaceCalendarEventEditPanelTarget?.eventID == eventID,
        updatedEvent.id != eventID
      {
        activeWorkspaceCalendarEventEditPanelTarget = WorkspaceCalendarEventEditPanelTarget(
          eventID: updatedEvent.id,
          event: updatedEvent,
          initialFields: updatedFields
        )
      }
      return updatedFields
    } catch {
      appState.errorMessage = error.localizedDescription
      throw error
    }
  }

  func timelineTaskEditFallbackFields(
    title: String,
    date: Date?,
    hasExplicitTime: Bool = false,
    durationMinutes: Int? = nil
  ) -> RetainedTaskEditFields {
    let calendar = Calendar.autoupdatingCurrent
    return RetainedTaskEditFields(
      title: title,
      noteText: "",
      day: date.map { calendar.startOfDay(for: $0) },
      timeMinutes: hasExplicitTime ? date.map(timelineTaskEditTimeMinutes) : nil,
      durationMinutes: durationMinutes
    )
  }

  func loadTimelineTaskEditFields(
    projectID: UUID,
    taskID: UUID,
    fallback: RetainedTaskEditFields
  ) async -> RetainedTaskEditFields {
    do {
      return try await RetainedTaskCommandFacade.taskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        calendar: .autoupdatingCurrent
      )
    } catch {
      if RetainedTaskCommandErrorPolicy.isTaskNotFound(error, taskID: taskID) {
        handleTimelineTaskDeleted(projectID: projectID, taskID: taskID)
        return fallback
      }
      appState.errorMessage = error.localizedDescription
      return fallback
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
      previousFields = try? await RetainedTaskCommandFacade.taskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        calendar: .autoupdatingCurrent
      )
    }
    do {
      _ = try await RetainedTaskCommandFacade.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        fields: fields,
        calendar: .autoupdatingCurrent,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      appState.bumpWorkspaceTreeRevision()
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
        handleTimelineTaskDeleted(projectID: projectID, taskID: taskID)
        return
      }
      appState.errorMessage = error.localizedDescription
      throw error
    }
  }

  func workspaceProjectListWindowSnapshot(
    projectID: UUID
  ) async -> TimelineProjectListWindowSnapshot? {
    guard let resolvedRead = await workspaceProjectListWindowResolvedRead(projectID: projectID) else {
      return nil
    }
    let descriptor = workspaceProjectDescriptorsByID[projectID]
    let project = resolvedRead.projectSnapshots[projectID]
    let title = project?.title ?? descriptor?.title ?? "프로젝트"
    let colorHex = project?.colorHex ?? descriptor?.colorHex
    let projectNoteText = project?.projectNoteMarkdown ?? ""
    return TimelineProjectListWindowSnapshotFactory.snapshot(
      projectID: projectID,
      title: title,
      colorHex: colorHex,
      projectNoteText: projectNoteText,
      entries: resolvedRead.scheduleEntriesByProjectID[projectID] ?? []
    )
  }

  private func workspaceProjectListWindowTaskSnapshot(
    projectID: UUID,
    taskID: UUID
  ) async -> TimelineProjectListWindowSnapshot.Task? {
    let snapshot = await workspaceProjectListWindowSnapshot(projectID: projectID)
    return snapshot?.tasks.first { $0.id == taskID }
  }

  private func workspaceProjectListWindowEntry(
    projectID: UUID,
    taskID: UUID
  ) async -> ScheduleSliceEntry? {
    let resolvedRead = await workspaceProjectListWindowResolvedRead(projectID: projectID)
    return resolvedRead?.scheduleEntriesByProjectID[projectID]?.first { $0.taskID == taskID }
  }

  private func workspaceProjectListWindowResolvedRead(
    projectID: UUID
  ) async -> RetainedWorkspaceSurfaceProjectionResolvedRead? {
    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: appState.obsidianVaultRootURL,
      projectIDs: [projectID]
    )
    let resolvedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(retainedResult)
    if case .blocked(let blocker) = resolvedRead.source {
      appState.errorMessage = blocker.userMessage
      return nil
    }
    return resolvedRead
  }

  private func workspaceTaskEditFields(for entry: ScheduleSliceEntry) -> RetainedTaskEditFields {
    let date = ReminderTaskDateCanonicalizer.unifiedDate(
      dueDate: entry.dueDate,
      startDate: entry.startDate,
      displayedDate: entry.displayedDate
    )
    let calendar = Calendar.autoupdatingCurrent
    return RetainedTaskEditFields(
      title: TimelineBoardReadPath.timelinePreviewTitle(for: entry.title),
      noteText: entry.reminderNoteText,
      day: date.map { calendar.startOfDay(for: $0) },
      timeMinutes: entry.scheduleHasExplicitTime ? date.map(timelineTaskEditTimeMinutes) : nil,
      durationMinutes: entry.scheduledDurationMinutes,
      recurrenceRuleRaw: entry.recurrenceRuleRaw,
      updatesRecurrence: true
    )
  }

  private func workspaceTaskUndoSnapshot(for entry: ScheduleSliceEntry)
    -> RetainedTaskUndoSnapshot
  {
    RetainedTaskUndoSnapshot(
      fields: workspaceTaskEditFields(for: entry),
      isCompleted: entry.isCompleted,
      completionDate: entry.completionDate
    )
  }

  private func timelineTaskEditTimeMinutes(for date: Date) -> Int {
    let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  func completeTimelineTask(_ taskID: UUID, projectID: UUID) {
    toggleTimelineTaskCompletion(taskID, projectID: projectID, isCompleted: false)
  }

  func toggleTimelineTaskCompletion(
    _ taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    targetSnapshot: RetainedTaskUndoSnapshot? = nil,
    undoTargetSnapshot: RetainedTaskUndoSnapshot? = nil
  ) {
    let nextIsCompleted =
      targetSnapshot?.isCompleted
      ?? TimelineTaskCompletionTogglePolicy.nextIsCompleted(currentIsCompleted: isCompleted)
    Task { @MainActor in
      guard let entry = await workspaceProjectListWindowEntry(projectID: projectID, taskID: taskID)
      else { return }
      let currentSnapshot = workspaceTaskUndoSnapshot(for: entry)
      let targetState =
        targetSnapshot
        ?? RetainedTaskUndoSnapshot(
          fields: currentSnapshot.fields,
          isCompleted: nextIsCompleted,
          completionDate: nil
        )
      let isRecurring = !(entry.recurrenceRuleRaw?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty ?? true)
      let occurrenceDate =
        ReminderTaskDateCanonicalizer.unifiedDate(
          dueDate: entry.dueDate,
          startDate: entry.startDate,
          displayedDate: entry.displayedDate
        )
      let completionDate = TimelineTaskCompletionTogglePolicy.completionDate(
        nextIsCompleted: nextIsCompleted
      )
      let targetCompletionDate =
        targetState.isCompleted
        ? (targetState.completionDate
          ?? (isRecurring ? occurrenceDate : nil)
          ?? completionDate)
        : nil
      let didSave = await appState.saveProjectDetailTaskCompletion(
        taskID: taskID,
        isCompleted: targetState.isCompleted,
        completionDate: targetCompletionDate,
        context: modelContext,
        restoreScheduleFields: isRecurring ? targetState.fields : nil,
        currentIsCompleted: currentSnapshot.isCompleted,
        currentScheduleFields: currentSnapshot.fields,
        isRecurring: isRecurring
      )
      if didSave {
        let registeredUndoSnapshot = undoTargetSnapshot ?? currentSnapshot
        appState.registerUndo(
          with: undoManager,
          actionName: targetState.isCompleted ? "할일 완료" : "할일 완료 취소"
        ) {
          self.toggleTimelineTaskCompletion(
            taskID,
            projectID: projectID,
            isCompleted: targetState.isCompleted,
            targetSnapshot: registeredUndoSnapshot,
            undoTargetSnapshot: targetState
          )
        }
      }
    }
  }

  func completeTimelinePlannedWork(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date? = nil
  ) {
    _ = taskID
    _ = targetCompletedUnits
    _ = projectID
    _ = completedOn
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "planned-work-progress")
  }

  func nonInspectorPassthroughRects(viewModePickerFrame: CGRect?) -> [CGRect] {
    viewModePickerFrame.map { [$0] } ?? []
  }

  func nonInspectorVisualExclusionRects(viewModePickerFrame: CGRect?) -> [CGRect] {
    nonInspectorPassthroughRects(viewModePickerFrame: viewModePickerFrame)
  }

  @ViewBuilder
  func nonInspectorDimOverlay(
    viewModePickerFrame: CGRect?,
    isVisible: Bool
  ) -> some View {
    if isVisible {
      Color.black.opacity(0.08)
        .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  func nonInspectorDimOverlay(
    visualExclusions: [CGRect],
    passthroughRects: [CGRect]
  ) -> some View {
    Color.black.opacity(0.08)
  }

  func archiveProjectFromList(_ projectID: UUID) {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "archive")
    _ = projectID
  }

  func performPermanentDelete(_ projectID: UUID) {
    Task { @MainActor in
      _ = await appState.deleteProjectPermanently(projectID, context: modelContext)
    }
  }

  var pendingProjectDeleteDialogBinding: Binding<Bool> {
    Binding(
      get: { pendingPermanentDeleteProject != nil },
      set: { isPresented in
        if !isPresented {
          pendingPermanentDeleteProject = nil
        }
      }
    )
  }

  func moveProjects(from source: IndexSet, to destination: Int) {
    guard canInteractivelyReorderSidebarProjects else { return }
    var reorderedProjects = filteredSidebarProjects
    reorderedProjects.move(fromOffsets: source, toOffset: destination)
    let orderedProjectIDs = reorderedProjects.compactMap(\.projectID)
    guard orderedProjectIDs.count == reorderedProjects.count else { return }

    workspaceSidebarProjects = reorderedProjects

    let boardOrders = Dictionary(
      uniqueKeysWithValues: orderedProjectIDs.enumerated().map { index, projectID in
        (projectID, Optional(index))
      }
    )
    Task { @MainActor in
      _ = await appState.writeProjectBoardOrders(boardOrders)
    }
  }

  func moveTaskToProjectFromSidebar(_ taskID: UUID, targetProjectID: UUID) {
    _ = taskID
    _ = targetProjectID
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "task-move")
  }

  func installLocalKeyMonitor() {
    if localKeyMonitor == nil {
      localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        handleKeyDown(event)
      }
    }
    if localMouseDownMonitor == nil {
      localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
      ) { event in
        handleMouseDown(event)
      }
    }
  }

  func removeLocalKeyMonitor() {
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
    }
    localKeyMonitor = nil
    if let localMouseDownMonitor {
      NSEvent.removeMonitor(localMouseDownMonitor)
    }
    localMouseDownMonitor = nil
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if isCommandTShortcut(event) {
      jumpCurrentWorkspaceBoardToToday()
      return nil
    }

    if isCommandLeftBracketShortcut(event), returnToPreviousScheduleMonthDetailIfAvailable() {
      return nil
    }

    if event.keyCode == 53 {
      let action = WorkspaceEscapeKeyPolicy.action(
        hasActiveEditPanelTextResponder: hasActiveEditPanelTextResponder(),
        hasSearchQuery: !chromeState.workspaceSearchQuery.isEmpty,
        hasInspectorSelection: inspectorSelection != nil,
        hasEditPanel: hasActiveWorkspaceEditPanel
      )
      switch action {
      case .clearSearch:
        clearWorkspaceSearch()
        return nil
      case .dismissInspector:
        dismissInspectorSelection()
        return nil
      case .dismissEditPanel:
        dismissActiveWorkspaceEditPanel()
        return nil
      case .passThrough:
        break
      }
    }
    return event
  }

  private func isCommandTShortcut(_ event: NSEvent) -> Bool {
    let shortcutModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
    return event.keyCode == 17 && shortcutModifiers == .command
  }

  private func isCommandLeftBracketShortcut(_ event: NSEvent) -> Bool {
    let shortcutModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
    guard shortcutModifiers == .command else { return false }
    return event.keyCode == 33 || event.charactersIgnoringModifiers == "["
  }

  private func returnToPreviousScheduleMonthDetailIfAvailable() -> Bool {
    guard let target = previousWorkspaceScheduleMonthDetailTarget else { return false }
    guard activeWorkspaceTaskEditPanelTarget != nil || activeWorkspaceCalendarEventEditPanelTarget != nil else {
      return false
    }
    activeWorkspaceTaskEditPanelTarget = nil
    activeWorkspaceCalendarEventEditPanelTarget = nil
    activeWorkspaceProjectListPanelProjectID = nil
    inspectorSelection = nil
    activeWorkspaceScheduleMonthDetailTarget = target
    previousWorkspaceScheduleMonthDetailTarget = nil
    return true
  }

  private func jumpCurrentWorkspaceBoardToToday() {
    showArchive = false
    switch appState.viewMode {
    case .timeline:
      appState.jumpTimelineToToday()
    case .schedule:
      appState.jumpScheduleToToday()
    }
  }

  private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
    releaseActiveEditPanelTextResponder(for: event)
    return event
  }

  private var hasActiveWorkspaceEditPanel: Bool {
    activeWorkspaceTaskEditPanelTarget != nil
      || activeWorkspaceCalendarEventEditPanelTarget != nil
      || activeWorkspaceProjectListPanelProjectID != nil
      || activeWorkspaceScheduleMonthDetailTarget != nil
  }

  @discardableResult
  private func dismissActiveWorkspaceEditPanel() -> Bool {
    if activeWorkspaceTaskEditPanelTarget != nil {
      dismissTimelineTaskEditor()
      return true
    }
    if activeWorkspaceCalendarEventEditPanelTarget != nil {
      dismissCalendarEventEditor()
      return true
    }
    if activeWorkspaceProjectListPanelProjectID != nil {
      dismissWorkspaceProjectListPanel()
      return true
    }
    if activeWorkspaceScheduleMonthDetailTarget != nil {
      dismissScheduleMonthDetail()
      return true
    }
    return false
  }

  @discardableResult
  private func releaseActiveEditPanelTextResponder(for event: NSEvent? = nil) -> Bool {
    let window = event?.window ?? NSApp.keyWindow ?? NSApp.mainWindow
    guard let window else { return false }
    guard window.identifier != .timelineProjectListWindow else { return false }
    let hitView = event.flatMap { mouseHitView(for: $0, in: window) }
    guard
      WorkspaceTextResponderReleasePolicy.shouldReleaseTextResponder(
        hasActiveEditPanel: hasActiveWorkspaceEditPanel,
        firstResponder: window.firstResponder,
        mouseHitView: hitView
      )
    else {
      return false
    }
    window.endEditing(for: nil)
    window.makeFirstResponder(nil)
    return true
  }

  private func hasActiveEditPanelTextResponder(for event: NSEvent? = nil) -> Bool {
    let window = event?.window ?? NSApp.keyWindow ?? NSApp.mainWindow
    guard let window else { return false }
    guard window.identifier != .timelineProjectListWindow else { return false }
    return WorkspaceTextResponderReleasePolicy.shouldReleaseTextResponder(
      hasActiveEditPanel: hasActiveWorkspaceEditPanel,
      firstResponder: window.firstResponder,
      mouseHitView: nil
    )
  }

  private func mouseHitView(for event: NSEvent, in window: NSWindow) -> NSView? {
    guard let contentView = window.contentView else { return nil }
    let point = contentView.convert(event.locationInWindow, from: nil)
    return contentView.hitTest(point)
  }

  func presentInitialSyncAlertIfNeeded() {
    guard appState.shouldPromptForInitialSyncConsent else { return }
    showInitialSyncAlert = true
  }
}
