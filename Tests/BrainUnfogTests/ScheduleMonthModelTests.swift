import XCTest
@testable import BrainUnfog

final class ScheduleMonthModelTests: XCTestCase {
  func testVisibleDaysAlwaysCoversSixWeeksStartingAtCalendarWeekStart() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))

    let days = ScheduleMonthCalendar.visibleDays(containing: anchor, calendar: calendar)

    XCTAssertEqual(days.count, 42)
    XCTAssertEqual(calendar.component(.month, from: days[0]), 5)
    XCTAssertEqual(calendar.component(.day, from: days[0]), 3)
    XCTAssertEqual(calendar.component(.month, from: days[41]), 6)
    XCTAssertEqual(calendar.component(.day, from: days[41]), 13)
  }

  func testAllDayEventEndDateIsTreatedAsExclusiveWhenGroupingDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let may9 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let may10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
    let item = ScheduleMonthItem(
      id: "calendar-test",
      source: .calendarEvent(eventID: "test"),
      title: "하루 일정",
      subtitle: nil,
      startDate: may9,
      endDate: may10,
      isAllDay: true,
      colorHex: nil,
      isCompleted: false,
      isPreparationSlot: false,
      isBackgroundCalendar: false,
      calendarEvent: nil
    )

    let grouped = ScheduleMonthCalendar.itemsByDay(
      items: [item],
      visibleDays: ScheduleMonthCalendar.visibleDays(containing: may9, calendar: calendar),
      calendar: calendar
    )

    XCTAssertEqual(grouped[may9]?.map(\.id), ["calendar-test"])
    XCTAssertNil(grouped[may10])
  }

  func testAllDayEventLateEndDateStillUsesExclusiveEndDayForGroupingDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let lateMay8 = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 23, minute: 59))
    )
    let item = ScheduleMonthItem(
      id: "calendar-late-end",
      source: .calendarEvent(eventID: "late-end"),
      title: "종일 일정",
      subtitle: nil,
      startDate: may7,
      endDate: lateMay8,
      isAllDay: true,
      colorHex: nil,
      isCompleted: false,
      isPreparationSlot: false,
      isBackgroundCalendar: false,
      calendarEvent: nil
    )

    let grouped = ScheduleMonthCalendar.itemsByDay(
      items: [item],
      visibleDays: ScheduleMonthCalendar.visibleDays(containing: may7, calendar: calendar),
      calendar: calendar
    )

    XCTAssertEqual(grouped[may7]?.map(\.id), ["calendar-late-end"])
    let may8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    XCTAssertNil(grouped[may8])
  }

  func testOverflowLimitShrinksAsCellHeightShrinks() {
    XCTAssertEqual(ScheduleMonthOverflowPolicy.visibleItemLimit(cellHeight: 150), 6)
    XCTAssertEqual(ScheduleMonthOverflowPolicy.visibleItemLimit(cellHeight: 92), 3)
    XCTAssertEqual(ScheduleMonthOverflowPolicy.visibleItemLimit(cellHeight: 48), 1)
  }

  func testAllDayCalendarEventsBecomeConnectedWeekSegments() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let may3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let may10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
    let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: may3) }
    let item = makeMonthItem(
      id: "calendar-span",
      source: .calendarEvent(eventID: "span"),
      startDate: may7,
      endDate: may10,
      isAllDay: true
    )

    let segments = ScheduleMonthSpanLayout.allDayCalendarSegments(
      for: weekDays,
      items: [item],
      calendar: calendar
    )

    XCTAssertEqual(segments.count, 1)
    XCTAssertEqual(segments[0].startDayIndex, 4)
    XCTAssertEqual(segments[0].endDayIndex, 6)
    XCTAssertEqual(segments[0].rowIndex, 0)
  }

  func testOverlappingAllDayCalendarSegmentsUseSeparateRows() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let may3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
    let may4 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
    let may6 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6)))
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: may3) }
    let first = makeMonthItem(
      id: "first",
      source: .calendarEvent(eventID: "first"),
      startDate: may4,
      endDate: may7,
      isAllDay: true
    )
    let second = makeMonthItem(
      id: "second",
      source: .calendarEvent(eventID: "second"),
      startDate: may6,
      endDate: may7,
      isAllDay: true
    )

    let segments = ScheduleMonthSpanLayout.allDayCalendarSegments(
      for: weekDays,
      items: [first, second],
      calendar: calendar
    )

    XCTAssertEqual(segments.map(\.rowIndex), [0, 1])
  }

  func testAllDayWorkspaceTasksStayInInlineMonthItems() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let may3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
    let may4 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
    let may5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5)))
    let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: may3) }
    let task = makeMonthItem(
      id: "task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: may4,
      endDate: may5,
      isAllDay: true
    )

    let segments = ScheduleMonthSpanLayout.allDayCalendarSegments(
      for: weekDays,
      items: [task],
      calendar: calendar
    )

    XCTAssertTrue(segments.isEmpty)
    XCTAssertEqual(ScheduleMonthSpanLayout.inlineItems(from: [task]).map(\.id), ["task"])
  }

  func testAllDayReservationOnlyAppliesToDaysCoveredByVisibleSegments() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let may3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
    let may5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5)))
    let may6 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6)))
    let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: may3) }
    let item = makeMonthItem(
      id: "calendar-span",
      source: .calendarEvent(eventID: "span"),
      startDate: may5,
      endDate: may6,
      isAllDay: true
    )
    let segments = ScheduleMonthSpanLayout.allDayCalendarSegments(
      for: weekDays,
      items: [item],
      calendar: calendar
    )

    XCTAssertEqual(
      ScheduleMonthSpanLayout.visibleAllDayRowCount(
        on: 0,
        segments: segments,
        visibleRowLimit: 2
      ),
      0
    )
    XCTAssertEqual(
      ScheduleMonthSpanLayout.visibleAllDayRowCount(
        on: 2,
        segments: segments,
        visibleRowLimit: 2
      ),
      1
    )
  }

  func testInlineMonthItemsSortCalendarEventsBeforeTasks() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 9)))
    let may5Later = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 10)))
    let task = makeMonthItem(
      id: "task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: may5,
      endDate: may5Later,
      isAllDay: false
    )
    let event = makeMonthItem(
      id: "event",
      source: .calendarEvent(eventID: "event"),
      startDate: may5Later,
      endDate: may5Later.addingTimeInterval(1800),
      isAllDay: false
    )

    let inlineItems = ScheduleMonthSpanLayout.inlineItems(from: [task, event])

    XCTAssertEqual(inlineItems.map(\.id), ["event", "task"])
  }

  func testContinuousWindowProvidesUniqueFullWeeksAroundAnchor() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))

    let days = ScheduleMonthContinuousWindow.visibleDays(
      containing: anchor,
      monthRadius: 1,
      calendar: calendar
    )

    XCTAssertEqual(days.count % 7, 0)
    XCTAssertEqual(Set(days).count, days.count)
    XCTAssertTrue(days.contains(ScheduleMonthContinuousWindow.weekStart(containing: anchor, calendar: calendar)))
    XCTAssertTrue(days.contains(anchor))
  }

  func testContinuousWindowMonthStartWeekTargetsWeekContainingFirstDayOfMonth() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))

    let target = ScheduleMonthContinuousWindow.monthStartWeek(containing: anchor, calendar: calendar)

    XCTAssertEqual(calendar.component(.month, from: target), 4)
    XCTAssertEqual(calendar.component(.day, from: target), 26)
  }

  func testMonthDragGeometryMapsPointerLocationToWeekGridDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let weekStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
    let rowSize = CGSize(width: 700, height: 100)

    let sameWeekDay = try XCTUnwrap(
      ScheduleMonthDragGeometry.day(
        at: CGPoint(x: 350, y: 50),
        weekStart: weekStart,
        rowSize: rowSize,
        calendar: calendar
      )
    )
    let nextWeekDay = try XCTUnwrap(
      ScheduleMonthDragGeometry.day(
        at: CGPoint(x: 350, y: 150),
        weekStart: weekStart,
        rowSize: rowSize,
        calendar: calendar
      )
    )

    XCTAssertEqual(calendar.component(.day, from: sameWeekDay), 6)
    XCTAssertEqual(calendar.component(.day, from: nextWeekDay), 13)
  }

  func testMonthDragGeometryPreservesClickedOffsetWithinMultiDayItem() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let originalStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let clickedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let currentPointerDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16)))

    let movedStart = try XCTUnwrap(
      ScheduleMonthDragGeometry.movedStartDay(
        originalStartDay: originalStart,
        startPointerDay: clickedDay,
        currentPointerDay: currentPointerDay,
        calendar: calendar
      )
    )

    XCTAssertEqual(calendar.component(.day, from: movedStart), 14)
  }

  func testScheduleMonthDragPayloadRoundTripsTaskAndCalendarEventItems() {
    let taskID = UUID()
    let calendarEventID = "calendar/event:2026-05-10"

    XCTAssertEqual(
      ScheduleMonthDragPayload.parseItem(
        from: ScheduleMonthDragPayload.payloadString(for: .task(taskID))
      ),
      .task(taskID)
    )
    XCTAssertEqual(
      ScheduleMonthDragPayload.parseItem(
        from: ScheduleMonthDragPayload.payloadString(for: .calendarEvent(calendarEventID))
      ),
      .calendarEvent(calendarEventID)
    )
    XCTAssertNil(ScheduleMonthDragPayload.parseItem(from: "buf-project:\(UUID().uuidString)"))
  }

  private func makeMonthItem(
    id: String,
    source: ScheduleMonthItemSource,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool
  ) -> ScheduleMonthItem {
    ScheduleMonthItem(
      id: id,
      source: source,
      title: id,
      subtitle: nil,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      colorHex: nil,
      isCompleted: false,
      isPreparationSlot: false,
      isBackgroundCalendar: false,
      calendarEvent: nil
    )
  }
}
