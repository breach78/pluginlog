import AppKit
import SwiftUI

extension ScheduleBoardView {
  func calendarDisplayRange() -> ClosedRange<Date> {
    if displayMode == .month {
      return ScheduleMonthContinuousWindow.visibleDateRange(
        containing: monthAnchorDate,
        calendar: calendar
      )
    }
    let lowerDay = calendar.date(byAdding: .day, value: -pastDayBuffer, to: today) ?? today
    let upperDay = calendar.date(byAdding: .day, value: futureDayWindow + 1, to: today) ?? today
    return lowerDay...upperDay
  }

  func refreshCalendarOverlay(force: Bool = false) {
    guard isActive else {
      calendarOverlayRefreshTask?.cancel()
      calendarOverlayRefreshTask = nil
      return
    }
    let fetchRange = calendarDisplayRange()
    calendarOverlayRefreshTask?.cancel()
    calendarOverlayRefreshTask = Task { @MainActor in
      guard !Task.isCancelled else { return }
      await appState.refreshScheduleCalendarOverlay(visibleRange: fetchRange, force: force)
    }
  }

  func refreshCalendarOverlayIfChanged(by result: RetainedTaskCommandResult) {
    switch result.calendarBridgeDecision {
    case .upsert, .removeOwnedEvent:
      refreshCalendarOverlay(force: true)
    case .noAction, .failClosed:
      break
    }
  }

  func deleteScheduleCalendarEvent(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope,
    actionName: String = "캘린더 일정 삭제",
    registerUndo: Bool = true
  ) {
    Task { @MainActor in
      do {
        let snapshot = try await appState.deleteScheduleCalendarEvent(
          event,
          scope: scope,
          undoManager: undoManager
        )
        calendarEditError = nil
        refreshCalendarOverlay(force: true)

        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          self.restoreDeletedScheduleCalendarEvent(
            snapshot,
            actionName: actionName
          )
        }
      } catch let error as ScheduleCalendarEditError {
        handleScheduleCalendarEditError(error, context: .deleteEvent)
      } catch {
        handleScheduleCalendarEditFailure(
          error,
          context: .deleteEvent,
          fallback: .removeFailed(error.localizedDescription)
        )
      }
    }
  }

  func restoreDeletedScheduleCalendarEvent(
    _ snapshot: DeletedScheduleCalendarEventSnapshot,
    actionName: String
  ) {
    Task { @MainActor in
      do {
        let restoredEvent = try await appState.restoreDeletedScheduleCalendarEvent(
          snapshot,
          undoManager: undoManager
        )
        calendarEditError = nil
        refreshCalendarOverlay(force: true)
        appState.registerUndo(with: undoManager, actionName: actionName) {
          self.deleteScheduleCalendarEvent(
            restoredEvent,
            scope: snapshot.scope,
            actionName: actionName,
            registerUndo: true
          )
        }
      } catch let error as ScheduleCalendarEditError {
        handleScheduleCalendarEditError(error, context: .restoreDeletedEvent)
      } catch {
        handleScheduleCalendarEditFailure(
          error,
          context: .restoreDeletedEvent,
          fallback: .saveFailed(error.localizedDescription)
        )
      }
    }
  }
}
