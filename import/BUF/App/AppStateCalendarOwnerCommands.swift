import Foundation

@MainActor
extension AppState {
  func resolvedScheduleCalendarOverlayProjection() -> ScheduleCalendarOverlayProjection {
    scheduleCalendarOverlayProjection
  }

  func resolvedScheduleCalendarEvent(eventID: String) -> ScheduleCalendarEvent? {
    scheduleCalendarOverlayProjection.events.first { $0.id == eventID }
  }

  func toggleScheduleCalendarVisibility(_ sourceID: String) {
    calendarServiceRegistry.scheduleCalendarService.toggleCalendarVisibility(sourceID)
    scheduleCalendarOverlayProjection =
      calendarServiceRegistry.scheduleCalendarService.overlayProjection
  }

  func toggleScheduleCalendarBackgroundOnly(_ sourceID: String) {
    calendarServiceRegistry.scheduleCalendarService.toggleCalendarBackgroundOnly(sourceID)
    scheduleCalendarOverlayProjection =
      calendarServiceRegistry.scheduleCalendarService.overlayProjection
  }

  func refreshScheduleCalendarOverlay(
    visibleRange: DateInterval,
    force: Bool = false
  ) async {
    await calendarServiceRegistry.scheduleCalendarService.refresh(
      visibleRange: visibleRange.start...visibleRange.end,
      force: force
    )
    scheduleCalendarOverlayProjection =
      calendarServiceRegistry.scheduleCalendarService.overlayProjection
  }

  func refreshScheduleCalendarOverlay(
    visibleRange: ClosedRange<Date>,
    force: Bool = false
  ) async {
    await refreshScheduleCalendarOverlay(
      visibleRange: DateInterval(start: visibleRange.lowerBound, end: visibleRange.upperBound),
      force: force
    )
  }

  func writeScheduleCalendarEventTiming(
    _ event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    let updatedEvent = try await calendarServiceRegistry.scheduleCalendarService.applyTimingChange(
      to: event,
      preview: preview,
      scope: scope
    )
    scheduleCalendarOverlayProjection =
      calendarServiceRegistry.scheduleCalendarService.overlayProjection
    return updatedEvent
  }

  func writeScheduleCalendarEventFields(
    _ event: ScheduleCalendarEvent,
    fields: ScheduleCalendarEventEditFields,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    let updatedEvent = try await calendarServiceRegistry.scheduleCalendarService.applyFieldChange(
      to: event,
      fields: fields,
      scope: scope
    )
    scheduleCalendarOverlayProjection =
      calendarServiceRegistry.scheduleCalendarService.overlayProjection
    return updatedEvent
  }

  func deleteScheduleCalendarEvent(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope,
    undoManager: UndoManager? = nil
  ) async throws -> DeletedScheduleCalendarEventSnapshot {
    _ = undoManager
    return try await calendarServiceRegistry.scheduleCalendarService.delete(event, scope: scope)
  }

  func restoreDeletedScheduleCalendarEvent(
    _ snapshot: DeletedScheduleCalendarEventSnapshot,
    undoManager: UndoManager? = nil
  ) async throws -> ScheduleCalendarEvent {
    _ = undoManager
    return try await calendarServiceRegistry.scheduleCalendarService.restoreDeletedEvent(snapshot)
  }
}
