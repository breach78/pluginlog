import XCTest
@testable import BrainUnfog

final class ScheduleDayTimelineLayoutEngineTests: XCTestCase {
  func testMultiDayAllDayItemStaysAtTopAcrossCoveredDays() throws {
    let calendar = testCalendar()
    let day0 = try testDate(year: 2026, month: 4, day: 24, calendar: calendar)
    let day1 = try testDate(year: 2026, month: 4, day: 25, calendar: calendar)
    let day2 = try testDate(year: 2026, month: 4, day: 26, calendar: calendar)
    let day3 = try testDate(year: 2026, month: 4, day: 27, calendar: calendar)
    let dayIndexByDate = [day0: 0, day1: 1, day2: 2]
    let multiDay = event(
      id: "multi",
      title: "ZZZ multi-day",
      startDate: day0,
      endDate: day3,
      isAllDay: true
    )
    let singleDay = event(
      id: "single",
      title: "AAA single-day",
      startDate: day1,
      endDate: day2,
      isAllDay: true
    )

    let layout = ScheduleDayTimelineLayoutEngine().makeLayout(
      items: [singleDay, multiDay],
      dayIndexByDate: dayIndexByDate,
      calendar: calendar,
      metrics: ScheduleDayTimelineLayoutMetrics(minimumTimedDurationMinutes: 15)
    )

    let multiDayRows = Dictionary(
      uniqueKeysWithValues: layout.allDay
        .filter { $0.itemID == multiDay.id }
        .map { ($0.dayIndex, $0.rowIndex) }
    )
    XCTAssertEqual(multiDayRows, [0: 0, 1: 0, 2: 0])
    XCTAssertEqual(
      layout.allDay.first { $0.itemID == singleDay.id && $0.dayIndex == 1 }?.rowIndex,
      1
    )
  }

  func testOvernightTimedSegmentsCarrySourceTiming() throws {
    let calendar = testCalendar()
    let day1 = try testDate(year: 2026, month: 5, day: 1, calendar: calendar)
    let day2 = try testDate(year: 2026, month: 5, day: 2, calendar: calendar)
    let startDate = try XCTUnwrap(
      calendar.date(byAdding: .hour, value: 22, to: day1)
    )
    let endDate = try XCTUnwrap(
      calendar.date(byAdding: .hour, value: 4, to: day2)
    )
    let item = event(
      id: "overnight",
      title: "Overnight",
      startDate: startDate,
      endDate: endDate,
      isAllDay: false
    )

    let layout = ScheduleDayTimelineLayoutEngine().makeLayout(
      items: [item],
      dayIndexByDate: [day1: 0, day2: 1],
      calendar: calendar,
      metrics: ScheduleDayTimelineLayoutMetrics(minimumTimedDurationMinutes: 15)
    )

    let segments = layout.timed.sorted { $0.dayIndex < $1.dayIndex }
    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments[0].startMinute, 22 * 60)
    XCTAssertEqual(segments[0].durationMinutes, 2 * 60)
    XCTAssertEqual(segments[1].startMinute, 0)
    XCTAssertEqual(segments[1].durationMinutes, 4 * 60)
    XCTAssertEqual(segments.map(\.sourceStartDay), [day1, day1])
    XCTAssertEqual(segments.map(\.sourceStartMinute), [22 * 60, 22 * 60])
    XCTAssertEqual(segments.map(\.sourceDurationMinutes), [6 * 60, 6 * 60])
    XCTAssertEqual(segments.map(\.isFirstSegment), [true, false])
    XCTAssertEqual(segments.map(\.isLastSegment), [false, true])
  }

  private func event(
    id: String,
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool
  ) -> ScheduleEventModel {
    ScheduleEventModel(
      id: id,
      source: .calendarEvent(eventID: id),
      title: title,
      subtitle: nil,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      colorHex: nil,
      isCompleted: false,
      isPreparationSlot: false,
      targetCompletedWorkUnits: nil,
      capabilities: []
    )
  }

  private func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func testDate(
    year: Int,
    month: Int,
    day: Int,
    calendar: Calendar
  ) throws -> Date {
    try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
  }
}
