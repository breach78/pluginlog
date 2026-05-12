import AppKit
import SwiftUI

extension ScheduleBoardView {
  func updateScheduleTaskCompletion(
    taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    targetState: ScheduleTaskCompletionState? = nil,
    undoTargetState: ScheduleTaskCompletionState? = nil,
    registerUndo: Bool
  ) {
    guard allowScheduleRetainedWrite("task-completion") else { return }
    let optimisticIsCompleted = targetState?.isCompleted ?? isCompleted
    let previousOptimisticValue = optimisticScheduleTaskCompletionByID[taskID]
    optimisticScheduleTaskCompletionByID[taskID] = optimisticIsCompleted
    Task { @MainActor in
      guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else {
        restoreOptimisticScheduleTaskCompletion(
          taskID: taskID,
          expectedCurrentValue: optimisticIsCompleted,
          previousValue: previousOptimisticValue
        )
        return
      }
      let previousState = scheduleCompletionState(for: taskDescriptor.taskRow)
      let nextState =
        targetState
        ?? ScheduleTaskCompletionState(
          isCompleted: isCompleted,
          completionDate: isCompleted ? (completionDate ?? .now) : nil,
          isRecurring: previousState.isRecurring,
          occurrenceDate: previousState.occurrenceDate,
          editFields: previousState.editFields
        )
      guard previousState != nextState else {
        clearOptimisticScheduleTaskCompletion(
          taskID: taskID,
          expectedIsCompleted: optimisticIsCompleted
        )
        return
      }
      do {
        let mutationPlan = RecurringCompletionUndoScheduleRestorePolicy.mutationPlan(
          previousIsCompleted: previousState.isCompleted,
          nextIsCompleted: nextState.isCompleted,
          isRecurring: nextState.isRecurring,
          previousFields: previousState.editFields,
          fields: nextState.editFields
        )
        var result: RetainedTaskCommandResult?
        if mutationPlan.writesCompletion {
          result = try await RetainedTaskCommandFacade.setTaskCompletion(
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
        if mutationPlan.restoresSchedule {
          result = try await RetainedTaskCommandFacade.setTaskSchedule(
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
        if RetainedTaskCompletionWorkspaceInvalidationPolicy.shouldBumpWorkspaceRevision(after: mutationPlan) {
          appState.bumpWorkspaceTreeRevision()
        }
        guard let result else {
          await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
          clearOptimisticScheduleTaskCompletion(
            taskID: taskID,
            expectedIsCompleted: nextState.isCompleted
          )
          return
        }
        await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
        retainedScheduleCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
        retainedScheduleCalendarBridgeWriteMarkersByTaskID[taskID] = result.calendarWriteMarker
        clearOptimisticScheduleTaskCompletion(
          taskID: taskID,
          expectedIsCompleted: nextState.isCompleted
        )

        guard registerUndo else { return }
        let registeredUndoState = undoTargetState ?? previousState
        appState.registerUndo(
          with: undoManager,
          actionName: nextState.isCompleted ? "할일 완료" : "할일 완료 취소"
        ) {
          self.updateScheduleTaskCompletion(
            taskID: taskID,
            projectID: projectID,
            isCompleted: registeredUndoState.isCompleted,
            completionDate: registeredUndoState.completionDate,
            targetState: registeredUndoState,
            undoTargetState: nextState,
            registerUndo: true
          )
        }
      } catch {
        restoreOptimisticScheduleTaskCompletion(
          taskID: taskID,
          expectedCurrentValue: nextState.isCompleted,
          previousValue: previousOptimisticValue
        )
        if await handleRetainedScheduleWriteFailure(error) {
          return
        }
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func updateSchedulePlannedWorkProgress(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date,
    registerUndo: Bool
  ) {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
    let previousCompletedUnits = taskDescriptor.taskRow.completedWorkUnits
    guard previousCompletedUnits != targetCompletedUnits else {
      return
    }
    guard allowScheduleMutation("planned-work-progress") else { return }
  }
}
