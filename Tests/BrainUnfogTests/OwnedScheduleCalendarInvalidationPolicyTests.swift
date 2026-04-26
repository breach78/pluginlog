import XCTest
@testable import BrainUnfog

final class OwnedScheduleCalendarInvalidationPolicyTests: XCTestCase {
  func testChangedOwnerIDsDetectMovedOwnedEvent() throws {
    let previous = try makeEvent(
      externalIdentifier: "event-1",
      calendarIdentifier: "owned-calendar",
      startHour: 9,
      startMinute: 0,
      endHour: 10,
      endMinute: 0
    )
    let current = try makeEvent(
      externalIdentifier: "event-1",
      calendarIdentifier: "owned-calendar",
      startHour: 11,
      startMinute: 0,
      endHour: 12,
      endMinute: 0
    )

    let ownerIDs = OwnedScheduleCalendarInvalidationPolicy.changedOwnerIDs(
      previousEvents: [previous],
      currentEvents: [current],
      ownedCalendarIdentifier: "owned-calendar"
    )

    XCTAssertEqual(ownerIDs, [ScheduleCalendarOwnerIDCodec.ownerID(for: previous)])
  }

  func testChangedOwnerIDsIgnoreForeignCalendarEvents() throws {
    let previous = try makeEvent(
      externalIdentifier: "event-1",
      calendarIdentifier: "foreign-calendar",
      startHour: 9,
      startMinute: 0,
      endHour: 10,
      endMinute: 0
    )
    let current = try makeEvent(
      externalIdentifier: "event-1",
      calendarIdentifier: "foreign-calendar",
      startHour: 11,
      startMinute: 0,
      endHour: 12,
      endMinute: 0
    )

    let ownerIDs = OwnedScheduleCalendarInvalidationPolicy.changedOwnerIDs(
      previousEvents: [previous],
      currentEvents: [current],
      ownedCalendarIdentifier: "owned-calendar"
    )

    XCTAssertTrue(ownerIDs.isEmpty)
  }

  func testChangedOwnerIDsFailClosedOnDuplicateOwnedIdentifiers() throws {
    let duplicateA = try makeEvent(
      externalIdentifier: "event-1",
      calendarIdentifier: "owned-calendar",
      startHour: 9,
      startMinute: 0,
      endHour: 10,
      endMinute: 0
    )
    let duplicateB = try makeEvent(
      externalIdentifier: "event-1",
      calendarIdentifier: "owned-calendar",
      startHour: 13,
      startMinute: 0,
      endHour: 14,
      endMinute: 0
    )

    let ownerIDs = OwnedScheduleCalendarInvalidationPolicy.changedOwnerIDs(
      previousEvents: [duplicateA, duplicateB],
      currentEvents: [],
      ownedCalendarIdentifier: "owned-calendar"
    )

    XCTAssertEqual(
      Set(ownerIDs),
      Set([
        ScheduleCalendarOwnerIDCodec.ownerID(for: duplicateA),
        ScheduleCalendarOwnerIDCodec.ownerID(for: duplicateB),
      ])
    )
  }

  private func makeEvent(
    externalIdentifier: String,
    calendarIdentifier: String,
    startHour: Int,
    startMinute: Int,
    endHour: Int,
    endMinute: Int
  ) throws -> ScheduleCalendarEvent {
    let calendar = Calendar(identifier: .gregorian)
    let startDate = try XCTUnwrap(
      calendar.date(
        from: DateComponents(year: 2026, month: 4, day: 25, hour: startHour, minute: startMinute)
      )
    )
    let endDate = try XCTUnwrap(
      calendar.date(
        from: DateComponents(year: 2026, month: 4, day: 25, hour: endHour, minute: endMinute)
      )
    )

    return ScheduleCalendarEvent(
      id: "\(externalIdentifier)-\(startHour)",
      eventIdentifier: nil,
      externalIdentifier: externalIdentifier,
      occurrenceDate: nil,
      calendarIdentifier: calendarIdentifier,
      calendarTitle: "BUF",
      calendarColorHex: nil,
      title: "Prepare launch",
      startDate: startDate,
      endDate: endDate,
      isAllDay: false,
      isRecurring: false,
      isDetached: false,
      canEditTiming: true,
      editTimingRestrictionReason: nil
    )
  }
}
