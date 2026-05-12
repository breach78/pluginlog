import AppKit
import SwiftUI

extension ScheduleBoardView {
  func updateTimedQuickCreateSelection(
    startLocation: CGPoint,
    currentLocation: CGPoint
  ) {
    pendingTimedQuickCreateSelection = nil
    activeTimedQuickCreateSelection = timedQuickCreateSelection(
      startLocation: startLocation,
      currentLocation: currentLocation
    )
  }

  func commitTimedQuickCreateSelection(
    startLocation: CGPoint,
    currentLocation: CGPoint
  ) {
    activeTimedQuickCreateSelection = nil
    guard scheduleQuickAddProjectID != nil else {
      handleUnavailableScheduleQuickAdd(reason: .noAvailableProject)
      return
    }
    pendingTimedQuickCreateSelection = timedQuickCreateSelection(
      startLocation: startLocation,
      currentLocation: currentLocation
    )
  }

  func cancelTimedQuickCreateSelection() {
    activeTimedQuickCreateSelection = nil
  }

  func timedQuickCreateSelection(
    startLocation: CGPoint,
    currentLocation: CGPoint
  ) -> ScheduleTimedQuickCreateSelection? {
    guard !days.isEmpty else { return nil }

    let clampedDayIndex = min(max(Int(startLocation.x / dayColumnWidth), 0), days.count - 1)
    let topY = max(0, min(startLocation.y, currentLocation.y))
    let bottomY = min(timeGridHeight, max(startLocation.y, currentLocation.y))
    let snappedStart = ScheduleDragDropInteractionLayer.snappedTimeMinutes(
      for: topY,
      metrics: interactionMetrics
    )
    let snappedEnd = ScheduleDragDropInteractionLayer.snappedTimeMinutes(
      for: max(topY + quarterHourHeight, bottomY),
      metrics: interactionMetrics
    )
    let unclampedDuration = max(timedMinimumDuration, snappedEnd - snappedStart)
    let durationMinutes = ScheduleDragDropInteractionLayer.clampedDuration(
      unclampedDuration,
      for: snappedStart,
      metrics: interactionMetrics
    )

    return ScheduleTimedQuickCreateSelection(
      dayIndex: clampedDayIndex,
      day: days[clampedDayIndex],
      startMinutes: snappedStart,
      durationMinutes: durationMinutes
    )
  }

  func timedQuickCreateViewportFrame(
    for selection: ScheduleTimedQuickCreateSelection
  ) -> CGRect {
    timedViewportFrame(
      dayIndex: selection.dayIndex,
      startMinute: selection.startMinutes,
      durationMinutes: selection.durationMinutes,
      column: 0,
      columnCount: 1
    )
  }

  func createScheduleTask(
    _ title: String,
    projectID: UUID,
    location: CGPoint,
    isAllDayRegion: Bool
  ) {
    guard !days.isEmpty else {
      handleUnavailableScheduleQuickAdd(reason: .noVisibleDay)
      return
    }

    let clampedDayIndex = min(max(Int(location.x / dayColumnWidth), 0), days.count - 1)
    let day = days[clampedDayIndex]
    if isAllDayRegion {
      createScheduleTask(title, projectID: projectID, day: day, timeMinutes: nil, durationMinutes: nil)
    } else {
      let snappedMinutes = ScheduleDragDropInteractionLayer.snappedTimeMinutes(
        for: location.y,
        metrics: interactionMetrics
      )
      createScheduleTask(
        title,
        projectID: projectID,
        day: day,
        timeMinutes: snappedMinutes,
        durationMinutes: timedMinimumDuration
      )
    }
  }

  func createScheduleTask(
    _ title: String,
    projectID: UUID,
    day: Date,
    timeMinutes: Int?,
    durationMinutes: Int?,
    registerUndo: Bool = true
  ) {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTitle.isEmpty else { return }
    scheduleTaskWriteNotice = nil
    Task { @MainActor in
      do {
        let result = try await RetainedTaskCommandFacade.createTask(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          title: normalizedTitle,
          day: day,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes,
          calendar: calendar,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        selectedScheduleTaskID = result.taskID
        appState.bumpWorkspaceTreeRevision()
        await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
        retainedScheduleCalendarBridgeDecisionsByTaskID[result.taskID] = result.calendarBridgeDecision
        retainedScheduleCalendarBridgeWriteMarkersByTaskID[result.taskID] = result.calendarWriteMarker
        refreshCalendarOverlayIfChanged(by: result)
        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: "할일 추가") {
          self.deleteScheduleTask(result.taskID, actionName: "할일 추가", registerUndo: false)
        }
      } catch {
        appState.reportError(error, logMessage: "schedule createTask failed")
      }
    }
  }

  func recreateScheduleTask(
    _ snapshot: RetainedTaskUndoSnapshot,
    projectID: UUID,
    registerUndo: Bool = true
  ) async -> UUID? {
    do {
      let result = try await RetainedTaskCommandFacade.createTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        title: snapshot.fields.title,
        day: snapshot.fields.day,
        timeMinutes: snapshot.fields.timeMinutes,
        durationMinutes: snapshot.fields.durationMinutes,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      _ = try await RetainedTaskCommandFacade.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: result.taskID,
        fields: snapshot.fields,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      if snapshot.isCompleted {
        _ = try await RetainedTaskCommandFacade.setTaskCompletion(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: result.taskID,
          isCompleted: true,
          completionDate: snapshot.completionDate,
          reminderProjectProvider: appState.reminderProjectProvider
        )
      }
      selectedScheduleTaskID = result.taskID
      appState.bumpWorkspaceTreeRevision()
      await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
      retainedScheduleCalendarBridgeDecisionsByTaskID[result.taskID] = result.calendarBridgeDecision
      retainedScheduleCalendarBridgeWriteMarkersByTaskID[result.taskID] = result.calendarWriteMarker
      refreshCalendarOverlayIfChanged(by: result)
      if registerUndo {
        appState.registerUndo(with: undoManager, actionName: "할일 삭제 취소") {
          self.deleteScheduleTask(result.taskID, actionName: "할일 삭제 취소", registerUndo: false)
        }
      }
      return result.taskID
    } catch {
      appState.reportError(error, logMessage: "schedule recreateTask failed")
      return nil
    }
  }

  func handleUnavailableScheduleQuickAdd(reason: ScheduleQuickAddFailureReason = .noAvailableProject) {
    AppLogger.ui.error(
      "schedule quick add failure [\(reason.rawValue, privacy: .public)]"
    )
    appState.errorMessage = reason.userMessage
  }
}
