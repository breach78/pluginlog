import XCTest
@testable import BrainUnfogHarness

final class RetainedCalendarBridgePolicyTests: XCTestCase {
  func testExplicitTimeTaskWithDurationDoesNotProduceCalendarEventWrite() throws {
    let startDate = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: 25, hour: 14, minute: 30)
      )
    )
    let task = makeTask(
      title: "Prepare launch",
      rawDate: "2026-04-25 14:30",
      parsedDate: startDate,
      hasExplicitTime: true,
      rawDuration: "45",
      durationMinutes: 45,
      rawRepeatRule: "weekly",
      canonicalRepeatRule: "weekly|1|",
      calendarEventExternalIdentifier: "event-1"
    )

    let decision = RetainedCalendarBridgePolicy.decision(for: task)

    XCTAssertEqual(decision, .noAction)
  }

  func testDateOnlyTaskDoesNotOwnCalendarEvent() throws {
    let day = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: 25)
      )
    )
    let task = makeTask(
      title: "Reminder-only task",
      rawDate: "2026-04-25",
      parsedDate: day,
      hasExplicitTime: false,
      rawDuration: "45",
      durationMinutes: 45
    )

    let decision = RetainedCalendarBridgePolicy.decision(for: task)

    XCTAssertEqual(decision, .noAction)
  }

  func testLegacyCalendarIdentityDoesNotProduceRemovalWrite() throws {
    let day = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: 25)
      )
    )

    let dateOnlyTask = makeTask(
      title: "Date only",
      rawDate: "2026-04-25",
      parsedDate: day,
      hasExplicitTime: false,
      rawDuration: "45",
      durationMinutes: 45,
      calendarEventExternalIdentifier: "event-date-only"
    )
    XCTAssertEqual(
      RetainedCalendarBridgePolicy.decision(for: dateOnlyTask),
      .noAction
    )

    let noDateTask = makeTask(
      title: "Unschedule",
      rawDate: nil,
      parsedDate: nil,
      hasExplicitTime: false,
      rawDuration: nil,
      durationMinutes: nil,
      calendarEventExternalIdentifier: "event-no-date"
    )
    XCTAssertEqual(
      RetainedCalendarBridgePolicy.decision(for: noDateTask),
      .noAction
    )
  }

  func testAmbiguousLegacyCalendarIdentifierDoesNotProduceCalendarWrite() throws {
    let startDate = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: 25, hour: 14, minute: 30)
      )
    )
    let task = makeTask(
      title: "Prepare launch",
      rawDate: "2026-04-25 14:30",
      parsedDate: startDate,
      hasExplicitTime: true,
      rawDuration: "45",
      durationMinutes: 45,
      calendarEventExternalIdentifier: "event-1"
    )

    let decision = RetainedCalendarBridgePolicy.decision(
      for: task,
      ambiguousOwnedEventIdentifiers: ["event-1"]
    )

    XCTAssertEqual(decision, .noAction)
  }

  func testLegacyCalendarIdentityWithDamagedScheduleDoesNotProduceCalendarWrite() {
    let validDate = Calendar(identifier: .gregorian).date(
      from: DateComponents(year: 2026, month: 4, day: 25, hour: 14, minute: 30)
    )
    let damagedDateTask = makeTask(
      title: "Broken date",
      rawDate: "not-a-date",
      parsedDate: nil,
      hasExplicitTime: false,
      rawDuration: "45",
      durationMinutes: 45,
      calendarEventExternalIdentifier: "event-broken-date"
    )
    XCTAssertEqual(
      RetainedCalendarBridgePolicy.decision(for: damagedDateTask),
      .noAction
    )

    let damagedDurationTask = makeTask(
      title: "Broken duration",
      rawDate: "2026-04-25 14:30",
      parsedDate: validDate,
      hasExplicitTime: true,
      rawDuration: "NaN",
      durationMinutes: nil,
      calendarEventExternalIdentifier: "event-broken-duration"
    )
    XCTAssertEqual(
      RetainedCalendarBridgePolicy.decision(for: damagedDurationTask),
      .noAction
    )
  }

  func testIdentitylessExplicitTimeTaskDoesNotOwnCalendarEvent() throws {
    let startDate = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: 25, hour: 14, minute: 30)
      )
    )
    let task = RetainedTask(
      identity: RetainedTaskIdentity(
        taskID: nil,
        reminderExternalIdentifier: nil,
        calendarEventExternalIdentifier: nil
      ),
      title: "Plain Logseq task",
      isCompleted: false,
      schedule: RetainedTaskSchedule(
        rawDate: "2026-04-25 14:30",
        parsedDate: startDate,
        hasExplicitTime: true,
        rawDuration: "45",
        durationMinutes: 45,
        rawRepeatRule: nil,
        canonicalRepeatRule: nil
      ),
      isManagedTask: false
    )

    XCTAssertEqual(RetainedCalendarBridgePolicy.decision(for: task), .noAction)
  }

  private func makeTask(
    title: String,
    rawDate: String?,
    parsedDate: Date?,
    hasExplicitTime: Bool,
    rawDuration: String?,
    durationMinutes: Int?,
    rawRepeatRule: String? = nil,
    canonicalRepeatRule: String? = nil,
    calendarEventExternalIdentifier: String? = nil
  ) -> RetainedTask {
    RetainedTask(
      identity: RetainedTaskIdentity(
        taskID: UUID(),
        reminderExternalIdentifier: "reminder-\(UUID().uuidString)",
        calendarEventExternalIdentifier: calendarEventExternalIdentifier
      ),
      title: title,
      isCompleted: false,
      schedule: RetainedTaskSchedule(
        rawDate: rawDate,
        parsedDate: parsedDate,
        hasExplicitTime: hasExplicitTime,
        rawDuration: rawDuration,
        durationMinutes: durationMinutes,
        rawRepeatRule: rawRepeatRule,
        canonicalRepeatRule: canonicalRepeatRule
      ),
      isManagedTask: true
    )
  }
}
