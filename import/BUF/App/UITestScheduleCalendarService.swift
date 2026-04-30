import Combine
import Foundation

@MainActor
final class UITestScheduleCalendarService: ScheduleCalendarServicing {
  private let overlaySubject = CurrentValueSubject<ScheduleCalendarOverlayProjection, Never>(.empty)
  private let invalidationSubject = PassthroughSubject<[String], Never>()

  var overlayProjection: ScheduleCalendarOverlayProjection { .empty }
  var overlayProjectionPublisher: AnyPublisher<ScheduleCalendarOverlayProjection, Never> {
    overlaySubject.eraseToAnyPublisher()
  }
  var ownedEventInvalidationPublisher: AnyPublisher<[String], Never> {
    invalidationSubject.eraseToAnyPublisher()
  }
  var calendars: [ScheduleCalendarSource] { [] }
  var events: [ScheduleCalendarEvent] { [] }
  var visibleEvents: [ScheduleCalendarEvent] { [] }
  var calendarsSignature: Int { 0 }
  var visibleEventsSignature: Int { 0 }
  var accessDenied: Bool { false }

  func requestCalendarAccessOnceIfNeeded() async -> Bool { true }
  func filteredEvents() -> [ScheduleCalendarEvent] { [] }
  func isCalendarVisible(_ calendarIdentifier: String) -> Bool { true }
  func isCalendarBackgroundOnly(_ calendarIdentifier: String) -> Bool { false }
  func toggleCalendarVisibility(_ calendarIdentifier: String) {}
  func toggleCalendarBackgroundOnly(_ calendarIdentifier: String) {}
  func foregroundVisibleEvents() -> [ScheduleCalendarEvent] { [] }
  func backgroundVisibleEvents() -> [ScheduleCalendarEvent] { [] }
  func refresh(visibleRange: ClosedRange<Date>) async {}
  func refresh(visibleRange: ClosedRange<Date>, force: Bool) async {}
  func reveal(_ event: ScheduleCalendarEvent) {}
  func applyFieldChange(
    to event: ScheduleCalendarEvent,
    fields: ScheduleCalendarEventEditFields,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    event
  }
  func applyTimingChange(
    to event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    event
  }
  func delete(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> DeletedScheduleCalendarEventSnapshot {
    throw ScheduleCalendarEditError.eventNotFound
  }
  func restoreDeletedEvent(_ snapshot: DeletedScheduleCalendarEventSnapshot) async throws
    -> ScheduleCalendarEvent
  {
    throw ScheduleCalendarEditError.eventNotFound
  }
  func applyOwnerFieldWrite(_ write: CalendarEventFieldsWrite) async throws -> ScheduleCalendarEvent {
    write.event
  }
  func ensureOwnedCalendar() async throws -> OwnedScheduleCalendarDescriptor {
    OwnedScheduleCalendarDescriptor(
      calendarIdentifier: "ui-test-owned-calendar",
      title: "UI Test Calendar",
      colorHex: nil
    )
  }
  func resolveOwnedEvent(externalIdentifier: String, calendarIdentifier: String?) async
    -> ScheduleCalendarEvent?
  {
    nil
  }
  func upsertOwnedEvent(
    _ request: OwnedScheduleCalendarEventUpsertRequest,
    calendarIdentifier: String
  ) async throws -> ScheduleCalendarEvent {
    throw ScheduleCalendarEditError.eventNotFound
  }
  func removeOwnedEvent(externalIdentifier: String, calendarIdentifier: String) async throws -> Bool {
    false
  }
  func resolveEvent(ownerID: String) async -> ScheduleCalendarEvent? {
    nil
  }
}
