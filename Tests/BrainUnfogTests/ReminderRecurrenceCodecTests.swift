@preconcurrency import EventKit
import XCTest
@testable import BrainUnfog

final class ReminderRecurrenceCodecTests: XCTestCase {
  func testMonthlyDayOfMonthRoundTripsThroughEventKitRule() throws {
    let rawValue = "monthly|2|days=15"

    let rule = try XCTUnwrap(ReminderRecurrenceCodec.recurrenceRules(fromRawValue: rawValue)?.first)

    XCTAssertEqual(rule.frequency, .monthly)
    XCTAssertEqual(rule.interval, 2)
    XCTAssertEqual(rule.daysOfTheMonth?.map(\.intValue), [15])
    XCTAssertEqual(ReminderRecurrenceCodec.rawValue(from: [rule]), rawValue)
  }

  func testMonthlyWeekdayOrdinalRoundTripsThroughEventKitRule() throws {
    let rawValue = "monthly|1|weekdays=3:2"

    let rule = try XCTUnwrap(ReminderRecurrenceCodec.recurrenceRules(fromRawValue: rawValue)?.first)
    let weekday = try XCTUnwrap(rule.daysOfTheWeek?.first)

    XCTAssertEqual(rule.frequency, .monthly)
    XCTAssertEqual(rule.interval, 1)
    XCTAssertEqual(weekday.dayOfTheWeek, .tuesday)
    XCTAssertEqual(weekday.weekNumber, 2)
    XCTAssertEqual(ReminderRecurrenceCodec.rawValue(from: [rule]), rawValue)
  }

  func testLegacyWeeklyRawValueStillDecodes() throws {
    let rawValue = "weekly|3|2,4"

    let rule = try XCTUnwrap(ReminderRecurrenceCodec.recurrenceRules(fromRawValue: rawValue)?.first)

    XCTAssertEqual(rule.frequency, .weekly)
    XCTAssertEqual(rule.interval, 3)
    XCTAssertEqual(rule.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue).sorted(), [2, 4])
    XCTAssertEqual(ReminderRecurrenceCodec.rawValue(from: [rule]), rawValue)
  }
}
