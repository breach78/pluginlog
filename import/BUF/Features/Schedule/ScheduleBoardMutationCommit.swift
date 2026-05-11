import AppKit
import SwiftUI

extension ScheduleBoardView {
  func applyInteractionSession(
    _ session: ScheduleInteractionSession,
    to taskDescriptor: WorkspaceScheduleTaskDescriptor,
    actionName: String
  ) {
    let taskRow = taskDescriptor.taskRow
    guard let command = session.command else { return }
    let commandPreview = command.schedulePreview()
    let previousDay = WorkspaceTaskScheduleEventStore.scheduledDay(for: taskRow, calendar: calendar)
    let previousTime = WorkspaceTaskScheduleEventStore.scheduledTimeMinutes(for: taskRow, calendar: calendar)
    let previousDuration = WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(for: taskRow)

    guard previousDay != commandPreview.day
      || previousTime != commandPreview.timeMinutes
      || previousDuration != commandPreview.durationMinutes
    else {
      committedTaskDrop = nil
      return
    }

    _ = applyTaskInteractionCommand(command, actionName: actionName)
  }

  func applyPreparationPreview(
    _ preview: ScheduleInteractionPreview,
    to taskDescriptor: WorkspaceScheduleTaskDescriptor,
    targetCompletedWorkUnits: Int,
    actionName: String
  ) {
    let taskRow = taskDescriptor.taskRow
    guard let previousSchedule = WorkspaceTaskScheduleEventStore.resolvedPreparationSchedule(
      for: taskRow,
      targetCompletedUnits: targetCompletedWorkUnits
    ) else {
      return
    }

    let isAllDay = preview.timeMinutes == nil
    let timeMinutes = min(
      max(0, preview.timeMinutes ?? previousSchedule.timeMinutes),
      23 * 60 + 45
    )
    let durationMinutes: Int
    if previousSchedule.isAllDay,
      preview.timeMinutes != nil,
      preview.durationMinutes == interactionMetrics.timedMinimumDurationMinutes
    {
      durationMinutes = previousSchedule.durationMinutes
    } else {
      durationMinutes = max(5, preview.durationMinutes ?? previousSchedule.durationMinutes)
    }

    guard previousSchedule.isAllDay != isAllDay
      || previousSchedule.timeMinutes != timeMinutes
      || previousSchedule.durationMinutes != durationMinutes
    else {
      return
    }

    applyPreparationScheduleState(
      taskID: taskRow.id,
      projectID: taskDescriptor.projectID,
      targetCompletedWorkUnits: targetCompletedWorkUnits,
      isAllDay: isAllDay,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes,
      registerUndo: true,
      actionName: actionName
    )
  }

  func commitCalendarSession(
    _ session: ScheduleInteractionSession,
    for event: ScheduleCalendarEvent,
    actionName: String
  ) {
    guard let command = session.command else { return }
    _ = applyCalendarInteractionCommand(command, actionName: actionName)
  }

  @discardableResult
  func applyTaskInteractionCommand(
    _ command: ScheduleInteractionCommand,
    actionName: String
  ) -> Bool {
    let taskID: UUID
    switch command {
    case .moveTask(let id, _, _, _), .resizeTask(let id, _, _, _):
      taskID = id
    case .moveCalendarEvent, .resizeCalendarEvent:
      return false
    }

    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return false }
    let preview = command.schedulePreview()
    applyScheduleState(
      taskID: taskID,
      projectID: taskDescriptor.projectID,
      day: preview.day,
      timeMinutes: preview.timeMinutes,
      durationMinutes: preview.durationMinutes,
      registerUndo: true,
      actionName: actionName
    )
    return true
  }

  @discardableResult
  func applyCalendarInteractionCommand(
    _ command: ScheduleInteractionCommand,
    actionName: String
  ) -> Bool {
    let eventID: String
    switch command {
    case .moveCalendarEvent(let id, _, _, _), .resizeCalendarEvent(let id, _, _, _):
      eventID = id
    case .moveTask, .resizeTask:
      return false
    }

    guard let event = appState.resolvedScheduleCalendarEvent(eventID: eventID),
      event.canEditTiming
    else {
      return false
    }

    let preview = command.schedulePreview()
    guard calendarPreviewDiffers(from: event, preview: preview) else {
      return false
    }

    if event.isRecurring {
      pendingCalendarEditAction = PendingScheduleCalendarEditAction(
        eventID: event.id,
        preview: preview,
        actionName: actionName
      )
      return true
    }

    applyCalendarPreview(
      preview,
      to: event,
      scope: .thisEvent,
      actionName: actionName
    )
    return true
  }

  func commitPendingCalendarEdit(scope: ScheduleCalendarRecurringEditScope) {
    guard let pendingAction = pendingCalendarEditAction,
      let event = appState.resolvedScheduleCalendarEvent(eventID: pendingAction.eventID)
    else {
      pendingCalendarEditAction = nil
      return
    }

    pendingCalendarEditAction = nil
    applyCalendarPreview(
      pendingAction.preview,
      to: event,
      scope: scope,
      actionName: pendingAction.actionName
    )
  }

  func applyCalendarPreview(
    _ preview: ScheduleInteractionPreview,
    to event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope,
    actionName: String,
    registerUndo: Bool = true
  ) {
    let previousPreview = schedulePreview(for: event)
    Task { @MainActor in
      do {
        let updatedEvent = try await appState.writeScheduleCalendarEventTiming(
          event,
          preview: preview,
          scope: scope
        )
        calendarEditError = nil

        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          self.applyCalendarPreview(
            previousPreview,
            to: updatedEvent,
            scope: scope,
            actionName: actionName,
            registerUndo: true
          )
        }
      } catch let error as ScheduleCalendarEditError {
        handleScheduleCalendarEditError(error, context: .applyPreview)
      } catch {
        handleScheduleCalendarEditFailure(
          error,
          context: .applyPreview,
          fallback: .saveFailed(error.localizedDescription)
        )
      }
    }
  }

  func calendarPreviewDiffers(
    from event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview
  ) -> Bool {
    let currentDay = calendar.startOfDay(for: event.startDate)
    let currentTimeMinutes = event.isAllDay ? nil : timeMinutes(for: event.startDate)
    let currentDurationMinutes = event.isAllDay ? nil : durationMinutes(for: event)
    return currentDay != preview.day
      || currentTimeMinutes != preview.timeMinutes
      || currentDurationMinutes != preview.durationMinutes
  }

  func schedulePreview(for event: ScheduleCalendarEvent) -> ScheduleInteractionPreview {
    ScheduleInteractionPreview(
      day: calendar.startOfDay(for: event.startDate),
      timeMinutes: event.isAllDay ? nil : timeMinutes(for: event.startDate),
      durationMinutes: event.isAllDay ? nil : durationMinutes(for: event)
    )
  }

  func applyScheduleState(
    taskID: UUID,
    projectID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    registerUndo: Bool,
    actionName: String
  ) {
    guard allowScheduleRetainedWrite("task-schedule") else { return }
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }

    let previousDay = WorkspaceTaskScheduleEventStore.scheduledDay(
      for: taskDescriptor.taskRow,
      calendar: calendar
    )
    let previousTime = WorkspaceTaskScheduleEventStore.scheduledTimeMinutes(
      for: taskDescriptor.taskRow,
      calendar: calendar
    )
    let previousDuration = WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(
      for: taskDescriptor.taskRow
    )
    let nextSchedule = optimisticScheduleTaskScheduleState(
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )

    guard previousDay != nextSchedule.day
      || previousTime != nextSchedule.timeMinutes
      || previousDuration != nextSchedule.durationMinutes
    else {
      return
    }
    selectedScheduleTaskID = taskID
    scheduleTaskWriteNotice = nil
    let previousOptimisticSchedule = optimisticScheduleTaskScheduleByID[taskID]
    optimisticScheduleTaskScheduleByID[taskID] = nextSchedule
    Task { @MainActor in
      do {
        let result = try await RetainedTaskCommandFacade.setTaskSchedule(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          day: nextSchedule.day,
          timeMinutes: nextSchedule.timeMinutes,
          durationMinutes: nextSchedule.durationMinutes,
          calendar: calendar,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
        retainedScheduleCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
        retainedScheduleCalendarBridgeWriteMarkersByTaskID[taskID] = nil
        refreshCalendarOverlayIfChanged(by: result)
        clearOptimisticScheduleTaskSchedule(taskID: taskID, expectedSchedule: nextSchedule)

        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          self.applyScheduleState(
            taskID: taskID,
            projectID: projectID,
            day: previousDay,
            timeMinutes: previousTime,
            durationMinutes: previousDuration,
            registerUndo: true,
            actionName: actionName
          )
        }
      } catch {
        restoreOptimisticScheduleTaskSchedule(
          taskID: taskID,
          expectedCurrentSchedule: nextSchedule,
          previousSchedule: previousOptimisticSchedule
        )
        if await handleRetainedScheduleWriteFailure(error) {
          return
        }
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func handleRetainedScheduleWriteFailure(_ error: Error) async -> Bool {
    guard let retainedError = error as? RetainedTaskCommandError else {
      return false
    }

    guard case .retainedProjectionFailed(let message) = retainedError,
      message.contains("reminder sync baseline")
    else {
      return false
    }

    AppLogger.ui.error(
      "schedule retained write stale baseline: \(message, privacy: .public)"
    )
    scheduleTaskWriteNotice = ScheduleBoardRuntimeNotice(
      id: "schedule_retained_write_stale_baseline",
      symbol: "arrow.clockwise.circle",
      title: "일정 저장 대기",
      message: "리마인더가 먼저 바뀌어 최신 상태를 다시 불러왔습니다. 같은 이동을 다시 시도해 주세요."
    )
    await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
    refreshCalendarOverlay(force: true)
    return true
  }

  func externalTaskDropPreview(at location: CGPoint) -> ScheduleInteractionPreview? {
    guard let target = externalTaskDropTarget(at: location) else { return nil }
    return ScheduleInteractionEngine.movePreview(
      originalTimeMinutes: nil,
      originalDurationMinutes: nil,
      target: target,
      metrics: interactionMetrics
    )
  }

  func externalTaskDropTarget(at location: CGPoint) -> ScheduleInteractionTarget? {
    ScheduleDragDropInteractionLayer.externalDropTarget(
      at: location,
      days: days,
      externalMetrics: ScheduleExternalDropMetrics(
        titleColumnWidth: titleColumnWidth,
        headerHeight: headerHeight,
        dayColumnsWidth: dayColumnsWidth,
        scrollOffsetX: currentScrollOffsetX,
        scrollOffsetY: currentScrollOffsetY
      ),
      interactionMetrics: interactionMetrics
    )
  }

  func applyExternalTaskDrop(taskID: UUID, target: ScheduleInteractionTarget) {
    guard let command = externalTaskDropCommand(taskID: taskID, target: target) else { return }

    releaseActiveTextResponderForUndo()
    suppressTaskTap(for: 0.2)

    _ = applyTaskInteractionCommand(command, actionName: "일정 배치")
  }

  func moveScheduleMonthItem(_ item: ScheduleMonthDragItem, to target: ScheduleInteractionTarget) {
    releaseActiveTextResponderForUndo()
    suppressTaskTap(for: 0.2)
    guard let command = monthMoveCommand(for: item, to: target) else { return }
    let commandPreview = command.schedulePreview()

    switch item {
    case .task(let taskID):
      guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
      guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return }

      _ = applyTaskInteractionCommand(command, actionName: "월간 일정 이동")
      if let updatedDescriptor = scheduleTaskDescriptor(for: taskID),
        let updatedItem = ScheduleMonthItemFactory.item(
          workspaceTask: updatedDescriptor,
          calendar: calendar
        )
      {
        onMonthItemScheduleChanged(updatedItem)
      }

    case .calendarEvent(let eventID):
      guard let event = appState.resolvedScheduleCalendarEvent(eventID: eventID),
        event.canEditTiming
      else {
        return
      }

      _ = applyCalendarInteractionCommand(command, actionName: "월간 일정 이동")
      if !event.isRecurring {
        onMonthItemScheduleChanged(
          ScheduleMonthItemFactory.item(
            calendarEvent: calendarEvent(applying: commandPreview, to: event),
            isBackgroundCalendar: false
          )
        )
      }
    }
  }

  func externalTaskDropCommand(
    taskID: UUID,
    target: ScheduleInteractionTarget
  ) -> ScheduleInteractionCommand? {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else {
      return nil
    }

    return ScheduleInteractionSession.move(
      identity: .task(taskID),
      originalTimeMinutes: WorkspaceTaskScheduleEventStore.scheduledTimeMinutes(
        for: taskDescriptor.taskRow,
        calendar: calendar
      ),
      originalDurationMinutes: WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(
        for: taskDescriptor.taskRow
      ),
      target: target,
      metrics: interactionMetrics
    )?.command
  }

  func monthMoveCommand(
    for item: ScheduleMonthDragItem,
    to target: ScheduleInteractionTarget
  ) -> ScheduleInteractionCommand? {
    switch item {
    case .task(let taskID):
      guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return nil }
      guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return nil }
      return ScheduleInteractionSession.move(
        identity: item.interactionIdentity,
        originalTimeMinutes: WorkspaceTaskScheduleEventStore.scheduledTimeMinutes(
          for: taskDescriptor.taskRow,
          calendar: calendar
        ),
        originalDurationMinutes: WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(
          for: taskDescriptor.taskRow
        ),
        target: target,
        metrics: interactionMetrics
      )?.command

    case .calendarEvent(let eventID):
      guard let event = appState.resolvedScheduleCalendarEvent(eventID: eventID),
        event.canEditTiming
      else {
        return nil
      }
      return ScheduleInteractionSession.move(
        identity: item.interactionIdentity,
        originalTimeMinutes: event.isAllDay ? nil : timeMinutes(for: event.startDate),
        originalDurationMinutes: event.isAllDay ? nil : durationMinutes(for: event),
        target: target,
        metrics: interactionMetrics
      )?.command
    }
  }

  private func calendarEvent(
    applying preview: ScheduleInteractionPreview,
    to event: ScheduleCalendarEvent
  ) -> ScheduleCalendarEvent {
    let startDate = previewStartDate(preview)
    let endDate = previewEndDate(preview, startDate: startDate)
    return ScheduleCalendarEvent(
      id: event.id,
      eventIdentifier: event.eventIdentifier,
      externalIdentifier: event.externalIdentifier,
      occurrenceDate: event.occurrenceDate,
      calendarIdentifier: event.calendarIdentifier,
      calendarTitle: event.calendarTitle,
      calendarColorHex: event.calendarColorHex,
      title: event.title,
      notes: event.notes,
      startDate: startDate,
      endDate: endDate,
      isAllDay: preview.timeMinutes == nil,
      isRecurring: event.isRecurring,
      isDetached: event.isDetached,
      canEditTiming: event.canEditTiming,
      editTimingRestrictionReason: event.editTimingRestrictionReason
    )
  }

  private func previewStartDate(_ preview: ScheduleInteractionPreview) -> Date {
    let day = calendar.startOfDay(for: preview.day ?? today)
    guard let timeMinutes = preview.timeMinutes else {
      return day
    }
    return calendar.date(byAdding: .minute, value: timeMinutes, to: day) ?? day
  }

  private func previewEndDate(
    _ preview: ScheduleInteractionPreview,
    startDate: Date
  ) -> Date {
    if preview.timeMinutes != nil {
      let duration = max(5, preview.durationMinutes ?? WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes)
      return calendar.date(byAdding: .minute, value: duration, to: startDate) ?? startDate
    }
    let day = calendar.startOfDay(for: preview.day ?? today)
    return calendar.date(byAdding: .day, value: 1, to: day) ?? day
  }

  func applyPreparationScheduleState(
    taskID: UUID,
    projectID: UUID,
    targetCompletedWorkUnits: Int,
    isAllDay: Bool,
    timeMinutes: Int,
    durationMinutes: Int,
    registerUndo: Bool,
    actionName: String
  ) {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
    guard let previousSchedule = WorkspaceTaskScheduleEventStore.resolvedPreparationSchedule(
      for: taskDescriptor.taskRow,
      targetCompletedUnits: targetCompletedWorkUnits
    ) else {
      return
    }

    let normalizedTime = min(max(0, timeMinutes), 23 * 60 + 45)
    let normalizedDuration = max(5, durationMinutes)
    guard previousSchedule.isAllDay != isAllDay
      || previousSchedule.timeMinutes != normalizedTime
      || previousSchedule.durationMinutes != normalizedDuration
    else {
      return
    }
    guard allowScheduleMutation("preparation-schedule") else { return }
  }
}
