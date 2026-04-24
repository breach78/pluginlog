import XCTest
@testable import BrainUnfogHarness

final class LogseqReminderPropertyCodecTests: XCTestCase {
  func testDecodeDateParsesDayAndDateTimeForms() {
    let dayOnly = LogseqReminderPropertyCodec.decodeDate("2026-04-25")
    XCTAssertNotNil(dayOnly)
    XCTAssertEqual(dayOnly?.hasExplicitTime, false)

    let dateTime = LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")
    XCTAssertNotNil(dateTime)
    XCTAssertEqual(dateTime?.hasExplicitTime, true)
  }

  func testEncodeDateUsesExpectedForms() {
    let calendar = Calendar(identifier: .gregorian)
    let dayOnly = calendar.date(from: DateComponents(year: 2026, month: 4, day: 25))
    let dateTime = calendar.date(from: DateComponents(
      year: 2026,
      month: 4,
      day: 25,
      hour: 14,
      minute: 30
    ))

    XCTAssertEqual(
      LogseqReminderPropertyCodec.encodeDate(dayOnly, hasExplicitTime: false),
      "2026-04-25"
    )
    XCTAssertEqual(
      LogseqReminderPropertyCodec.encodeDate(dateTime, hasExplicitTime: true),
      "2026-04-25 14:30"
    )
  }

  func testRepeatRoundTripsV1Values() {
    XCTAssertEqual(
      LogseqReminderPropertyCodec.decodeRepeat("daily"),
      "daily|1"
    )
    XCTAssertEqual(
      LogseqReminderPropertyCodec.decodeRepeat("weekly"),
      "weekly|1|"
    )
    XCTAssertEqual(
      LogseqReminderPropertyCodec.encodeRepeat("monthly|1"),
      "monthly"
    )
    XCTAssertEqual(
      LogseqReminderPropertyCodec.encodeRepeat("yearly|1"),
      "yearly"
    )
    XCTAssertNil(LogseqReminderPropertyCodec.decodeRepeat("every weekday"))
  }
}
