import Foundation

struct ScheduleCalendarOverlayProjection: Equatable {
  let calendarSources: [ScheduleCalendarSource]
  let foregroundEvents: [ScheduleCalendarEvent]
  let backgroundEvents: [ScheduleCalendarEvent]
  let calendarsSignature: Int
  let visibleEventsSignature: Int
  let accessDenied: Bool

  static let empty = ScheduleCalendarOverlayProjection(
    calendarSources: [],
    foregroundEvents: [],
    backgroundEvents: [],
    calendarsSignature: 0,
    visibleEventsSignature: 0,
    accessDenied: false
  )

  var visibleEvents: [ScheduleCalendarEvent] {
    foregroundEvents + backgroundEvents
  }

  var visibleEventsByID: [String: ScheduleCalendarEvent] {
    Dictionary(uniqueKeysWithValues: visibleEvents.map { ($0.id, $0) })
  }
}

@MainActor
extension AppState {
  func refreshScheduleCalendarOverlay(
    visibleRange: ClosedRange<Date>,
    force: Bool = false
  ) async {
    await calendarServiceRegistry.scheduleCalendarService.refresh(
      visibleRange: visibleRange,
      force: force
    )
  }

  func toggleScheduleCalendarVisibility(_ calendarIdentifier: String) {
    calendarServiceRegistry.scheduleCalendarService.toggleCalendarVisibility(calendarIdentifier)
  }

  func toggleScheduleCalendarBackgroundOnly(_ calendarIdentifier: String) {
    calendarServiceRegistry.scheduleCalendarService.toggleCalendarBackgroundOnly(calendarIdentifier)
  }

  func resolvedScheduleCalendarOverlayProjection() -> ScheduleCalendarOverlayProjection {
    scheduleCalendarOverlayProjection
  }

  func resolvedScheduleCalendarEvent(eventID: String) -> ScheduleCalendarEvent? {
    scheduleCalendarOverlayProjection.visibleEventsByID[eventID]
  }
}
