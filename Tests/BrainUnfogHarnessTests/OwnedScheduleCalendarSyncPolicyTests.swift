import XCTest
@testable import BrainUnfogHarness

final class OwnedScheduleCalendarSyncPolicyTests: XCTestCase {
  func testEligibleTaskProducesOwnedEventUpsertRequest() throws {
    let calendar = Calendar(identifier: .gregorian)
    let dueDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 14, minute: 30))
    )

    let request = OwnedScheduleCalendarSyncPolicy.upsertRequest(
      title: "Prepare launch",
      dueDate: dueDate,
      hasExplicitTime: true,
      durationMinutes: 45,
      existingExternalIdentifier: "event-1"
    )

    XCTAssertEqual(
      request,
      OwnedScheduleCalendarEventUpsertRequest(
        externalIdentifier: "event-1",
        title: "Prepare launch",
        startDate: dueDate,
        durationMinutes: 45
      )
    )
  }

  func testIneligibleTasksDoNotProduceOwnedEventUpsertRequest() throws {
    let calendar = Calendar(identifier: .gregorian)
    let dueDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 14, minute: 30))
    )

    XCTAssertNil(
      OwnedScheduleCalendarSyncPolicy.upsertRequest(
        title: "No explicit time",
        dueDate: dueDate,
        hasExplicitTime: false,
        durationMinutes: 45,
        existingExternalIdentifier: nil
      )
    )
    XCTAssertNil(
      OwnedScheduleCalendarSyncPolicy.upsertRequest(
        title: "No duration",
        dueDate: dueDate,
        hasExplicitTime: true,
        durationMinutes: nil,
        existingExternalIdentifier: nil
      )
    )
    XCTAssertNil(
      OwnedScheduleCalendarSyncPolicy.upsertRequest(
        title: "No date",
        dueDate: nil,
        hasExplicitTime: true,
        durationMinutes: 45,
        existingExternalIdentifier: nil
      )
    )
  }

  func testTaskScheduleValueMapsTimedEventBackToDateAndDuration() throws {
    let calendar = Calendar(identifier: .gregorian)
    let startDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 9, minute: 15))
    )
    let endDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 10, minute: 0))
    )
    let event = ScheduleCalendarEvent(
      id: "owned-1",
      eventIdentifier: "event-id",
      externalIdentifier: "event-external-id",
      occurrenceDate: nil,
      calendarIdentifier: "calendar-1",
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

    let scheduleValue = OwnedScheduleCalendarSyncPolicy.taskScheduleValue(for: event)

    XCTAssertEqual(
      scheduleValue,
      OwnedScheduleCalendarSyncPolicy.TaskScheduleValue(
        day: calendar.startOfDay(for: startDate),
        timeMinutes: 9 * 60 + 15,
        durationMinutes: 45
      )
    )
  }
}
