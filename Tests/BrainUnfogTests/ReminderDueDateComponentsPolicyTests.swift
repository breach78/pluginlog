import XCTest
@testable import BrainUnfog

final class ReminderDueDateComponentsPolicyTests: XCTestCase {
  func testClearsExistingDueDateWhenSameDayAllDayBecomesTimed() {
    let existing = DateComponents(year: 2026, month: 4, day: 25)
    let next = DateComponents(year: 2026, month: 4, day: 25, hour: 9, minute: 30)

    XCTAssertTrue(
      ReminderDueDateComponentsPolicy.shouldClearExistingDueDateBeforeAssigning(
        existing: existing,
        next: next
      )
    )
    XCTAssertEqual(
      ReminderDueDateComponentsPolicy.assignmentSteps(existing: existing, next: next).count,
      2
    )
    XCTAssertNil(ReminderDueDateComponentsPolicy.assignmentSteps(existing: existing, next: next)[0])
  }

  func testClearsExistingDueDateWhenSameDayTimedBecomesAllDay() {
    let existing = DateComponents(year: 2026, month: 4, day: 25, hour: 9, minute: 30)
    let next = DateComponents(year: 2026, month: 4, day: 25)

    XCTAssertTrue(
      ReminderDueDateComponentsPolicy.shouldClearExistingDueDateBeforeAssigning(
        existing: existing,
        next: next
      )
    )
    XCTAssertEqual(
      ReminderDueDateComponentsPolicy.assignmentSteps(existing: existing, next: next).count,
      2
    )
    XCTAssertNil(ReminderDueDateComponentsPolicy.assignmentSteps(existing: existing, next: next)[0])
  }

  func testDoesNotTemporarilyClearDueDateWhenIntermediateNilIsDisallowed() {
    let existing = DateComponents(year: 2026, month: 4, day: 25, hour: 9, minute: 30)
    let next = DateComponents(year: 2026, month: 4, day: 25)

    XCTAssertEqual(
      ReminderDueDateComponentsPolicy.assignmentSteps(
        existing: existing,
        next: next,
        allowsIntermediateNil: false
      ),
      [next]
    )
  }

  func testDoesNotClearExistingDueDateWhenDateChanges() {
    let existing = DateComponents(year: 2026, month: 4, day: 25)
    let next = DateComponents(year: 2026, month: 4, day: 26, hour: 9, minute: 30)

    XCTAssertFalse(
      ReminderDueDateComponentsPolicy.shouldClearExistingDueDateBeforeAssigning(
        existing: existing,
        next: next
      )
    )
    XCTAssertEqual(
      ReminderDueDateComponentsPolicy.assignmentSteps(existing: existing, next: next).count,
      1
    )
  }

  func testDateOnlyComponentsKeepCalendarButNoTimeZone() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
    let date = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 9, minute: 30))
    )

    let components = try XCTUnwrap(
      ReminderDueDateComponentsPolicy.components(
        from: date,
        existing: nil,
        hasExplicitTime: false,
        calendar: calendar
      )
    )

    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 4)
    XCTAssertEqual(components.day, 25)
    XCTAssertNil(components.hour)
    XCTAssertNil(components.minute)
    XCTAssertNotNil(components.calendar)
    XCTAssertNil(components.timeZone)
  }
}
