import AppKit
import SwiftUI

extension ScheduleBoardView {
  func revealScheduleTask(taskID: UUID, projectID: UUID) {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else {
      selectedScheduleTaskID = taskID
      appState.selectedProjectID = projectID
      onEditTask(
        WorkspaceTaskEditPanelTarget(
          projectID: projectID,
          taskID: taskID,
          initialFields: RetainedTaskEditFields(
            title: "",
            noteText: "",
            day: nil,
            timeMinutes: nil,
            durationMinutes: nil
          ),
          initialFocus: .note
        )
      )
      return
    }
    showScheduleTaskEditor(taskDescriptor)
  }

  func handleScheduleTaskPrimaryTap(_ taskDescriptor: WorkspaceScheduleTaskDescriptor) {
    DispatchQueue.main.async {
      guard shouldHandleTaskTap() else { return }
      guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return }
      showScheduleTaskEditor(taskDescriptor)
    }
  }

  func handleScheduleTaskDetailTap(_ taskDescriptor: WorkspaceScheduleTaskDescriptor) {
    DispatchQueue.main.async {
      let taskRow = taskDescriptor.taskRow
      guard shouldHandleTaskTap() else { return }
      guard !taskRow.isLocalCompletedRecurringOccurrence else { return }
      revealScheduleTask(taskID: taskRow.id, projectID: taskDescriptor.projectID)
    }
  }

  func showScheduleTaskEditor(_ taskDescriptor: WorkspaceScheduleTaskDescriptor) {
    let taskRow = taskDescriptor.taskRow
    selectedScheduleTaskID = taskRow.id
    appState.selectedProjectID = taskDescriptor.projectID
    onEditTask(
      WorkspaceTaskEditPanelTarget(
        projectID: taskDescriptor.projectID,
        taskID: taskRow.id,
        initialFields: scheduleTaskEditFields(for: taskRow),
        initialFocus: .note
      )
    )
  }

  func showScheduleCalendarEventEditor(_ event: ScheduleCalendarEvent) {
    selectedScheduleTaskID = nil
    onEditCalendarEvent(event)
  }

  func scheduleTaskEditFields(for taskRow: TaskRowSnapshot) -> RetainedTaskEditFields {
    RetainedTaskEditFields(
      title: taskRow.title,
      noteText: "",
      day: taskRow.reminderDate.map { calendar.startOfDay(for: $0) },
      timeMinutes: taskRow.scheduleHasExplicitTime ? taskRow.reminderDate.map(timeMinutes) : nil,
      durationMinutes: taskRow.scheduledDurationMinutes
    )
  }

  func taskUndoSnapshot(for taskRow: TaskRowSnapshot) -> RetainedTaskUndoSnapshot {
    RetainedTaskUndoSnapshot(
      fields: scheduleTaskEditFields(for: taskRow),
      isCompleted: taskRow.isCompleted,
      completionDate: taskRow.completionDate
    )
  }

  func selectScheduleTask(_ taskID: UUID) {
    MotionTransaction.withoutAnimation {
      selectedScheduleTaskID = taskID
    }
  }

  func handleScheduleBackgroundTap() {
    MotionTransaction.withoutAnimation {
      selectedScheduleTaskID = nil
    }
    onTapEmptyArea()
  }

  func deleteScheduleTask(
    _ taskID: UUID,
    actionName: String = "할일 삭제",
    registerUndo: Bool = true
  ) {
    if selectedScheduleTaskID == taskID {
      selectedScheduleTaskID = nil
    }
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
    let undoSnapshot = taskUndoSnapshot(for: taskDescriptor.taskRow)
    scheduleTaskWriteNotice = nil
    Task { @MainActor in
      do {
        let fullUndoFields =
          (try? await RetainedTaskCommandFacade.taskEditFields(
            vaultRootURL: appState.obsidianVaultRootURL,
            projectID: taskDescriptor.projectID,
            taskID: taskID,
            calendar: calendar
          )) ?? undoSnapshot.fields
        let fullUndoSnapshot = RetainedTaskUndoSnapshot(
          fields: fullUndoFields,
          isCompleted: undoSnapshot.isCompleted,
          completionDate: undoSnapshot.completionDate
        )
        _ = try await RetainedTaskCommandFacade.deleteTask(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: taskDescriptor.projectID,
          taskID: taskID,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        appState.bumpWorkspaceTreeRevision()
        await reloadChangedWorkspaceScheduleProjectDetails(for: [taskDescriptor.projectID])
        retainedScheduleCalendarBridgeDecisionsByTaskID.removeValue(forKey: taskID)
        retainedScheduleCalendarBridgeWriteMarkersByTaskID.removeValue(forKey: taskID)
        refreshCalendarOverlay(force: true)
        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          Task { @MainActor in
            _ = await self.recreateScheduleTask(
              fullUndoSnapshot,
              projectID: taskDescriptor.projectID,
              registerUndo: false
            )
          }
        }
      } catch {
        if await handleRetainedScheduleWriteFailure(error) {
          return
        }
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func suppressTaskTap(for duration: TimeInterval = 0.35) {
    suppressedTaskTapUntil = TaskTapSuppressionPolicy.suppressedUntil(
      now: Date(),
      duration: duration
    )
  }

  func shouldHandleTaskTap() -> Bool {
    TaskTapSuppressionPolicy.shouldHandleTaskTap(
      now: Date(),
      suppressedUntil: suppressedTaskTapUntil
    )
  }

  func postponeScheduleAction(
    for taskDescriptor: WorkspaceScheduleTaskDescriptor,
    day: Date,
    isPreparationSlot: Bool,
    targetCompletedWorkUnits _: Int?
  ) -> (() -> Void)? {
    guard !taskDescriptor.taskRow.isCompleted, !isPreparationSlot else { return nil }
    let normalizedDay = calendar.startOfDay(for: day)
    return {
      self.postponeScheduledTaskToNextDayAllDay(
        taskID: taskDescriptor.taskRow.id,
        projectID: taskDescriptor.projectID,
        from: normalizedDay
      )
    }
  }

  func postponeScheduledTaskToNextDayAllDay(taskID: UUID, projectID: UUID, from day: Date) {
    guard calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) != nil else { return }
    guard allowScheduleMutation("postpone-task") else { return }
  }

  func releaseActiveTextResponderForUndo() {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
    if let responder = window.firstResponder, responder is NSTextView || responder is NSTextField {
      window.endEditing(for: nil)
      window.makeFirstResponder(nil)
    }
  }
}
