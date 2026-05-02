import XCTest
@testable import BrainUnfog

final class ScheduleCalendarEventEditPanelTests: XCTestCase {
  @MainActor
  func testAllDayMultiDayEventUsesVisibleEndDayInEditFields() throws {
    let calendar = Calendar.autoupdatingCurrent
    let startDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 2))
    )
    let exclusiveEndDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))
    )

    let fields = ScheduleCalendarEventEditPanelContent.editFields(
      for: makeEvent(startDate: startDate, endDate: exclusiveEndDate, isAllDay: true)
    )

    XCTAssertEqual(fields.day, calendar.startOfDay(for: startDate))
    XCTAssertEqual(
      fields.endDay,
      try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
    )
    XCTAssertTrue(fields.isAllDay)
  }

  @MainActor
  func testTimedMultiDayEventKeepsEndDayAndEndTimeInEditFields() throws {
    let calendar = Calendar.autoupdatingCurrent
    let startDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 22, minute: 30))
    )
    let endDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 0, minute: 15))
    )

    let fields = ScheduleCalendarEventEditPanelContent.editFields(
      for: makeEvent(startDate: startDate, endDate: endDate, isAllDay: false)
    )

    XCTAssertEqual(fields.day, calendar.startOfDay(for: startDate))
    XCTAssertEqual(fields.endDay, calendar.startOfDay(for: endDate))
    XCTAssertFalse(fields.isAllDay)
    XCTAssertEqual(fields.startMinutes, 22 * 60 + 30)
    XCTAssertEqual(fields.endMinutes, 15)
  }

  func testCalendarEventDetectsMultiDaySpans() throws {
    let calendar = Calendar.autoupdatingCurrent
    let startDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9))
    )
    let endDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 9))
    )

    XCTAssertTrue(makeEvent(startDate: startDate, endDate: endDate, isAllDay: false).spansMultipleDays)
  }

  private func makeEvent(
    startDate: Date,
    endDate: Date,
    isAllDay: Bool
  ) -> ScheduleCalendarEvent {
    ScheduleCalendarEvent(
      id: UUID().uuidString,
      eventIdentifier: "event-id",
      externalIdentifier: "external-id",
      occurrenceDate: nil,
      calendarIdentifier: "calendar-id",
      calendarTitle: "Calendar",
      calendarColorHex: nil,
      title: "Event",
      notes: "Notes",
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      isRecurring: false,
      isDetached: false,
      canEditTiming: true,
      editTimingRestrictionReason: nil
    )
  }
}
