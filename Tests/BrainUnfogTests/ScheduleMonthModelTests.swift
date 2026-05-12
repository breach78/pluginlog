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

  func testDayPanelTimedBlockHeightTracksActualDuration() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 18))
    )
    let end = try XCTUnwrap(calendar.date(byAdding: .minute, value: 30, to: start))
    let item = makeMonthItem(
      id: "laundry",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: start,
      endDate: end,
      isAllDay: false
    )
    let hourHeight = ScheduleUITokens.MonthDayPanel.hourHeight
    let layout = ScheduleMonthDayTimedItemLayout(
      item: item,
      startMinute: 18 * 60,
      durationMinutes: 30,
      sourceStartDay: calendar.startOfDay(for: start),
      sourceStartMinute: 18 * 60,
      sourceDurationMinutes: 30,
      isFirstSegment: true,
      isLastSegment: true,
      column: 0,
      columnCount: 1,
      containerWidth: 320,
      hourHeight: hourHeight
    )

    XCTAssertEqual(layout.y, 18 * hourHeight, accuracy: 0.001)
    XCTAssertEqual(layout.height, hourHeight / 2, accuracy: 0.001)
    let markerFootprint =
      ScheduleMonthDayTimedBlockMetrics.contentVerticalPadding(forBlockHeight: layout.height) * 2
      + ScheduleUITokens.DayPanelRow.markerTopPadding
      + ScheduleMonthDayTimedBlockMetrics.markerHitHeight(forBlockHeight: layout.height)
    XCTAssertLessThanOrEqual(markerFootprint, layout.height + 0.001)
    XCTAssertEqual(
      ScheduleMonthDayTimedBlockMetrics.titleLineLimit(forBlockHeight: layout.height),
      1
    )
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

  func testMonthDragGeometryTreatsHorizontalOutsideAsNoTargetDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let weekStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
    let rowSize = CGSize(width: 700, height: 100)

    XCTAssertNil(
      ScheduleMonthDragGeometry.day(
        at: CGPoint(x: -1, y: 50),
        weekStart: weekStart,
        rowSize: rowSize,
        calendar: calendar
      )
    )
    XCTAssertNil(
      ScheduleMonthDragGeometry.day(
        at: CGPoint(x: 701, y: 50),
        weekStart: weekStart,
        rowSize: rowSize,
        calendar: calendar
      )
    )
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

  func testMonthDragTargetResolutionReturnsMonthDayInteractionTarget() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let originalStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let clickedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let currentPointerDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16)))

    let resolution = try XCTUnwrap(
      ScheduleMonthDragTargetResolution.localMonthTarget(
        originalStartDay: originalStart,
        startPointerDay: clickedDay,
        currentPointerDay: currentPointerDay,
        calendar: calendar
      )
    )

    let expectedDay = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 14))
    )
    XCTAssertEqual(resolution.target, .monthDay(expectedDay))
    XCTAssertEqual(resolution.highlightDay, currentPointerDay)
  }

  func testMonthLocalDragSessionCarriesCommonTargetAndPointerAnchor() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let originalStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let clickedDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let currentPointerDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16)))

    let session = try XCTUnwrap(
      ScheduleMonthDragSessionState.local(
        originalStartDay: originalStart,
        startPointerDay: clickedDay,
        currentPointerDay: currentPointerDay,
        calendar: calendar
      )
    )

    let expectedDay = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 14))
    )
    XCTAssertEqual(session.startPointerDay, clickedDay)
    XCTAssertEqual(session.target, .monthDay(expectedDay))
    XCTAssertEqual(session.highlightDay, currentPointerDay)
  }

  func testMonthExternalDragSessionUsesCommonMonthTargetWithoutHighlight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let targetDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))

    let session = ScheduleMonthDragSessionState.external(
      targetDay: targetDay,
      calendar: calendar
    )

    XCTAssertNil(session.startPointerDay)
    XCTAssertNil(session.highlightDay)
    XCTAssertEqual(session.target, .monthDay(targetDay))
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
    XCTAssertEqual(
      ScheduleMonthDragPayload.parseItem(
        from: ScheduleMonthDragPayload.payloadString(for: .task(taskID)) as NSString
      ),
      .task(taskID)
    )
    XCTAssertNil(ScheduleMonthDragPayload.parseItem(from: "buf-project:\(UUID().uuidString)"))
  }

  func testScheduleMonthDragItemMapsToInteractionIdentity() {
    let taskID = UUID()

    XCTAssertEqual(
      ScheduleMonthDragItem.task(taskID).interactionIdentity,
      .task(taskID)
    )
    XCTAssertEqual(
      ScheduleMonthDragItem.calendarEvent("event-1").interactionIdentity,
      .calendarEvent("event-1")
    )
  }

  func testScreenPointMapperConvertsTopLeftLocalPointToScreenPoint() {
    let frame = CGRect(x: 100, y: 200, width: 300, height: 500)

    XCTAssertEqual(
      ScheduleScreenPointMapper.screenPoint(
        localLocation: CGPoint(x: 40, y: 80),
        in: frame
      ),
      CGPoint(x: 140, y: 620)
    )
  }

  func testScheduleMonthDropAcceptsCustomAndTextPayloads() {
    XCTAssertEqual(
      ScheduleMonthDragPayload.dropTypeIdentifiers,
      [
        ScheduleMonthDragPayload.typeIdentifier,
        ScheduleMonthDragPayload.utf8PlainTextTypeIdentifier,
        ScheduleMonthDragPayload.plainTextTypeIdentifier,
        ScheduleMonthDragPayload.textTypeIdentifier,
      ]
    )
  }

  func testDayPanelExternalMonthDropUsesEscapedPointerLocation() {
    XCTAssertTrue(
      ScheduleMonthDayInteractionAdapter.isExternalMonthDropLocation(
        locationXInPanel: -18,
        translation: CGSize(width: -90, height: 8)
      )
    )
    XCTAssertTrue(
      ScheduleMonthDayInteractionAdapter.isExternalMonthDropLocation(
        locationXInPanel: -18,
        translation: CGSize(width: -90, height: 120)
      )
    )
    XCTAssertFalse(
      ScheduleMonthDayInteractionAdapter.isExternalMonthDropLocation(
        locationXInPanel: -4,
        translation: CGSize(width: -90, height: 8)
      )
    )
    XCTAssertFalse(
      ScheduleMonthDayInteractionAdapter.isExternalMonthDropLocation(
        locationXInPanel: 80,
        translation: CGSize(width: -90, height: 8)
      )
    )
  }

  func testDayPanelDragUsesCurrentTimeContentOffsetWhenLeavingAllDayRail() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let targetDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
    let item = makeMonthItem(
      id: "all-day-task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: targetDay,
      endDate: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: targetDay)),
      isAllDay: true
    )
    let initialState = ScheduleMonthDayItemDragState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: nil,
      originalDurationMinutes: nil,
      originalPointerScheduleY: 120,
      originalTopScheduleY: 105,
      originalX: nil,
      originalWidth: nil,
      allDayBoundaryYInPanel: 160,
      timeContentMinYInPanel: 0,
      isInAllDayZone: true
    )

    let updatedState = ScheduleMonthDayInteractionAdapter.updatedDragState(
      initialState,
      drag: DragGestureProxy(
        locationY: 700,
        translation: CGSize(width: 0, height: 580)
      ),
      allDayRowHeight: 30,
      timeContentMinYInPanel: -180
    )
    let preview = ScheduleMonthDayInteractionAdapter.movePreview(
      for: updatedState,
      targetDay: targetDay,
      calendar: calendar,
      metrics: ScheduleMonthDayInteractionAdapter.metrics(
        hourHeight: 60,
        minimumDurationMinutes: 30
      )
    )

    XCTAssertEqual(updatedState.timeContentMinYInPanel, -180)
    XCTAssertEqual(preview.timeMinutes, 14 * 60 + 30)
    XCTAssertEqual(preview.durationMinutes, 30)
  }

  func testDayPanelMoveTargetUsesCommonInteractionTarget() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let targetDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
    let item = makeMonthItem(
      id: "timed-task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 9))),
      endDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 10))),
      isAllDay: false
    )
    var state = ScheduleMonthDayItemDragState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: 9 * 60,
      originalDurationMinutes: 60,
      originalPointerScheduleY: 9 * 60,
      originalTopScheduleY: 9 * 60,
      originalX: nil,
      originalWidth: nil,
      allDayBoundaryYInPanel: 120,
      timeContentMinYInPanel: 0,
      isInAllDayZone: false
    )
    state.currentPointerPanelY = 11 * 60 + 6

    let metrics = ScheduleMonthDayInteractionAdapter.metrics(
      hourHeight: 60,
      minimumDurationMinutes: 30
    )
    let target = ScheduleMonthDayInteractionAdapter.moveTarget(
      for: state,
      targetDay: targetDay,
      calendar: calendar,
      metrics: metrics
    )

    XCTAssertEqual(
      ScheduleInteractionEngine.movePreview(
        originalTimeMinutes: state.originalTimeMinutes,
        originalDurationMinutes: state.originalDurationMinutes,
        target: target,
        metrics: metrics
      ),
      ScheduleMonthDayInteractionAdapter.movePreview(
        for: state,
        targetDay: targetDay,
        calendar: calendar,
        metrics: metrics
      ).interactionPreview
    )
  }

  func testDayPanelMoveTargetReturnsAllDayTargetInAllDayZone() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let targetDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
    let item = makeMonthItem(
      id: "timed-task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 9))),
      endDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 10))),
      isAllDay: false
    )
    let state = ScheduleMonthDayItemDragState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: 9 * 60,
      originalDurationMinutes: 60,
      originalPointerScheduleY: 9 * 60,
      originalTopScheduleY: 9 * 60,
      originalX: nil,
      originalWidth: nil,
      allDayBoundaryYInPanel: 120,
      timeContentMinYInPanel: 0,
      isInAllDayZone: true
    )

    let target = ScheduleMonthDayInteractionAdapter.moveTarget(
      for: state,
      targetDay: targetDay,
      calendar: calendar,
      metrics: ScheduleMonthDayInteractionAdapter.metrics(
        hourHeight: 60,
        minimumDurationMinutes: 30
      )
    )

    XCTAssertEqual(target, .allDay(targetDay))
  }

  func testDayPanelExternalMonthDropPreviewUsesCommonMonthTarget() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let targetDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 14)))
    let item = makeMonthItem(
      id: "timed-task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 9))),
      endDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 10, minute: 30))),
      isAllDay: false
    )
    let state = ScheduleMonthDayItemDragState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: 9 * 60,
      originalDurationMinutes: 90,
      originalPointerScheduleY: 9 * 60,
      originalTopScheduleY: 9 * 60,
      originalX: nil,
      originalWidth: nil,
      allDayBoundaryYInPanel: 120,
      timeContentMinYInPanel: 0,
      isInAllDayZone: false
    )
    let metrics = ScheduleMonthDayInteractionAdapter.metrics(
      hourHeight: 60,
      minimumDurationMinutes: 30
    )
    let target = ScheduleMonthDragSessionState.external(
      targetDay: targetDay,
      calendar: calendar
    ).target

    XCTAssertEqual(
      ScheduleMonthDayInteractionAdapter.externalMonthDropPreview(
        for: state,
        targetDay: targetDay,
        calendar: calendar,
        metrics: metrics
      ).interactionPreview,
      ScheduleInteractionEngine.movePreview(
        originalTimeMinutes: state.originalTimeMinutes,
        originalDurationMinutes: state.originalDurationMinutes,
        target: target,
        metrics: metrics
      )
    )
  }

  func testUserFlowMonthToDayPanelMoveUsesSamePreviewAndCommit() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let taskID = UUID()
    let projectID = UUID()
    let sourceStart = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 9))
    )
    let sourceEnd = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 10, minute: 30))
    )
    let targetDay = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 14))
    )
    let item = makeMonthItem(
      id: "timed-task",
      source: .workspaceTask(taskID: taskID, projectID: projectID),
      startDate: sourceStart,
      endDate: sourceEnd,
      isAllDay: false
    )
    let state = ScheduleMonthDayItemDragState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: 9 * 60,
      originalDurationMinutes: 90,
      originalPointerScheduleY: 9 * 60,
      originalTopScheduleY: 9 * 60,
      originalX: nil,
      originalWidth: nil,
      allDayBoundaryYInPanel: 120,
      timeContentMinYInPanel: 0,
      isInAllDayZone: false
    )
    let metrics = ScheduleMonthDayInteractionAdapter.metrics(
      hourHeight: 60,
      minimumDurationMinutes: 30
    )
    let target = ScheduleMonthDragSessionState.external(
      targetDay: targetDay,
      calendar: calendar
    ).target
    let preview = ScheduleMonthDayInteractionAdapter.externalMonthDropPreview(
      for: state,
      targetDay: targetDay,
      calendar: calendar,
      metrics: metrics
    ).interactionPreview
    let session = try XCTUnwrap(
      ScheduleInteractionSession.move(
        identity: .task(taskID),
        originalTimeMinutes: state.originalTimeMinutes,
        originalDurationMinutes: state.originalDurationMinutes,
        target: target,
        metrics: metrics
      )
    )

    XCTAssertEqual(session.preview, preview)
    XCTAssertEqual(
      session.command,
      .moveTask(
        taskID: taskID,
        day: calendar.startOfDay(for: targetDay),
        timeMinutes: 9 * 60,
        durationMinutes: 90
      )
    )
  }

  func testScheduleMonthDropTargetResolverMapsGlobalPointToDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let may8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let targets = [
      ScheduleMonthDropTarget(day: may7, frame: CGRect(x: 10, y: 20, width: 90, height: 80)),
      ScheduleMonthDropTarget(day: may8, frame: CGRect(x: 100, y: 20, width: 90, height: 80)),
    ]

    let resolved = try XCTUnwrap(
      ScheduleMonthDropTargetResolver.day(
        at: CGPoint(x: 125, y: 45),
        targets: targets,
        calendar: calendar
      )
    )

    XCTAssertEqual(calendar.component(.day, from: resolved), 8)
    XCTAssertNil(
      ScheduleMonthDropTargetResolver.day(
        at: CGPoint(x: 220, y: 45),
        targets: targets,
        calendar: calendar
      )
    )
  }

  func testScheduleMonthDropTargetResolverMapsSingleExternalPanelTarget() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may9 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let target = ScheduleMonthDropTarget(day: may9, frame: CGRect(x: 300, y: 100, width: 180, height: 500))

    let resolved = try XCTUnwrap(
      ScheduleMonthDropTargetResolver.day(
        at: CGPoint(x: 420, y: 320),
        target: target,
        calendar: calendar
      )
    )

    XCTAssertEqual(calendar.component(.day, from: resolved), 9)
    XCTAssertNil(
      ScheduleMonthDropTargetResolver.day(
        at: CGPoint(x: 260, y: 320),
        target: target,
        calendar: calendar
      )
    )
    XCTAssertNil(
      ScheduleMonthDropTargetResolver.day(
        at: CGPoint(x: 420, y: 320),
        target: nil,
        calendar: calendar
      )
    )
  }

  func testScheduleMonthDetailTargetUpdaterAddsMovedItemForOpenDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may9 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let movedItem = ScheduleMonthItem(
      id: "workspace-task-\(UUID().uuidString)",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      title: "옮긴 할일",
      subtitle: "프로젝트",
      startDate: may9,
      endDate: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: may9)),
      isAllDay: true,
      colorHex: nil,
      isCompleted: false,
      isPreparationSlot: false,
      isBackgroundCalendar: false,
      calendarEvent: nil
    )
    let target = ScheduleMonthDetailPanelTarget(date: may9, items: [])

    let updated = ScheduleMonthDetailTargetUpdater.applyingMovedItem(
      movedItem,
      to: target,
      calendar: calendar
    )

    XCTAssertEqual(updated.items.map(\.id), [movedItem.id])
  }

  func testScheduleMonthDetailTargetUpdaterRemovesMovedItemOutsideOpenDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may9 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let may10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
    let movedItem = ScheduleMonthItem(
      id: "workspace-task-\(UUID().uuidString)",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      title: "옮긴 할일",
      subtitle: "프로젝트",
      startDate: may10,
      endDate: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: may10)),
      isAllDay: true,
      colorHex: nil,
      isCompleted: false,
      isPreparationSlot: false,
      isBackgroundCalendar: false,
      calendarEvent: nil
    )
    let target = ScheduleMonthDetailPanelTarget(date: may9, items: [movedItem])

    let updated = ScheduleMonthDetailTargetUpdater.applyingMovedItem(
      movedItem,
      to: target,
      calendar: calendar
    )

    XCTAssertTrue(updated.items.isEmpty)
  }

  func testScheduleMonthItemAppliesDateOnlyPreviewWithoutDroppingTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 9, minute: 30)))
    let may7End = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 10, minute: 45)))
    let may11 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
    let item = makeMonthItem(
      id: "timed",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: may7,
      endDate: may7End,
      isAllDay: false
    )

    let moved = item.applyingSchedulePreview(
      ScheduleMonthDayScheduleMutationPreview(
        itemID: item.id,
        day: may11,
        timeMinutes: 9 * 60 + 30,
        durationMinutes: 75
      ),
      calendar: calendar
    )

    XCTAssertFalse(moved.isAllDay)
    XCTAssertEqual(calendar.component(.day, from: moved.startDate), 11)
    XCTAssertEqual(calendar.component(.hour, from: moved.startDate), 9)
    XCTAssertEqual(calendar.component(.minute, from: moved.startDate), 30)
    XCTAssertEqual(Int(moved.endDate.timeIntervalSince(moved.startDate) / 60), 75)
  }

  func testScheduleMonthItemAppliesOvernightTimedPreviewWithoutTruncatingDuration() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 20)))
    let may8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 2)))
    let item = makeMonthItem(
      id: "overnight-task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: may7,
      endDate: may8,
      isAllDay: false
    )

    let moved = item.applyingSchedulePreview(
      ScheduleMonthDayScheduleMutationPreview(
        itemID: item.id,
        day: may7,
        timeMinutes: 22 * 60,
        durationMinutes: 6 * 60
      ),
      calendar: calendar
    )

    XCTAssertFalse(moved.isAllDay)
    XCTAssertEqual(calendar.component(.hour, from: moved.startDate), 22)
    XCTAssertEqual(Int(moved.endDate.timeIntervalSince(moved.startDate) / 60), 6 * 60)
    XCTAssertEqual(calendar.component(.day, from: moved.endDate), 8)
    XCTAssertEqual(calendar.component(.hour, from: moved.endDate), 4)
  }

  func testMonthLayoutShowsOvernightTimedItemOnlyOnStartDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 22)))
    let may8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 4)))
    let may7Day = calendar.startOfDay(for: may7)
    let may8Day = calendar.startOfDay(for: may8)
    let item = makeMonthItem(
      id: "overnight-task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: may7,
      endDate: may8,
      isAllDay: false
    )

    let itemsByDay = ScheduleMonthCalendar.itemsByDay(
      items: [item],
      visibleDays: [may7Day, may8Day],
      calendar: calendar
    )

    XCTAssertEqual(itemsByDay[may7Day]?.map(\.id), ["overnight-task"])
    XCTAssertNil(itemsByDay[may8Day])
  }

  func testDayPanelDraggingSecondDaySegmentPreservesOriginalOvernightOffset() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 22)))
    let may8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let may8Four = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 4)))
    let item = makeMonthItem(
      id: "overnight-task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: may7,
      endDate: may8Four,
      isAllDay: false
    )
    var state = ScheduleMonthDayItemDragState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: 22 * 60,
      originalDurationMinutes: 6 * 60,
      originalPointerScheduleY: 0,
      originalTopScheduleY: -2 * 60,
      originalX: nil,
      originalWidth: nil,
      allDayBoundaryYInPanel: 120,
      timeContentMinYInPanel: 0,
      isInAllDayZone: false
    )
    state.translation = CGSize(width: 0, height: 60)

    let preview = ScheduleMonthDayInteractionAdapter.movePreview(
      for: state,
      targetDay: may8,
      calendar: calendar,
      metrics: ScheduleMonthDayInteractionAdapter.metrics(
        hourHeight: 60,
        minimumDurationMinutes: 30
      )
    )

    XCTAssertEqual(preview.day, calendar.startOfDay(for: may7))
    XCTAssertEqual(preview.timeMinutes, 23 * 60)
    XCTAssertEqual(preview.durationMinutes, 6 * 60)
  }

  func testDayPanelEndResizeOnSecondDaySegmentPreservesPreviousDayStart() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 22)))
    let may8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let may8Four = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 4)))
    let item = makeMonthItem(
      id: "overnight-task",
      source: .workspaceTask(taskID: UUID(), projectID: UUID()),
      startDate: may7,
      endDate: may8Four,
      isAllDay: false
    )
    let state = ScheduleMonthDayItemResizeState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: 22 * 60,
      originalDurationMinutes: 6 * 60,
      originalPointerScheduleY: 4 * 60,
      originalEdgeScheduleY: 4 * 60,
      originalX: 0,
      originalWidth: 100,
      timeContentMinYInPanel: 0,
      edge: .end
    )

    let preview = ScheduleMonthDayInteractionAdapter.resizePreview(
      for: state,
      currentPointerPanelY: 5 * 60,
      targetDay: may8,
      calendar: calendar,
      metrics: ScheduleMonthDayInteractionAdapter.metrics(
        hourHeight: 60,
        minimumDurationMinutes: 30
      )
    )

    XCTAssertEqual(preview.day, calendar.startOfDay(for: may7))
    XCTAssertEqual(preview.timeMinutes, 22 * 60)
    XCTAssertEqual(preview.durationMinutes, 7 * 60)
  }

  func testDayPanelResizeTargetFeedsCommonSessionPreviewAndCommand() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let taskID = UUID()
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 10)))
    let may7Noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 12)))
    let item = makeMonthItem(
      id: "resized-task",
      source: .workspaceTask(taskID: taskID, projectID: UUID()),
      startDate: may7,
      endDate: may7Noon,
      isAllDay: false
    )
    let state = ScheduleMonthDayItemResizeState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: 10 * 60,
      originalDurationMinutes: 120,
      originalPointerScheduleY: 10 * 60,
      originalEdgeScheduleY: 10 * 60,
      originalX: 0,
      originalWidth: 100,
      timeContentMinYInPanel: 0,
      edge: .start
    )
    let metrics = ScheduleMonthDayInteractionAdapter.metrics(
      hourHeight: 60,
      minimumDurationMinutes: 30
    )
    let targetDay = calendar.startOfDay(for: may7)
    let target = ScheduleMonthDayInteractionAdapter.resizeTarget(
      for: state,
      currentPointerPanelY: 9 * 60,
      targetDay: targetDay,
      calendar: calendar,
      metrics: metrics
    )
    let session = try XCTUnwrap(ScheduleInteractionSession.resize(
      identity: .task(taskID),
      originalDay: targetDay,
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      isStartEdge: true,
      target: target,
      metrics: metrics,
      calendar: calendar
    ))

    XCTAssertEqual(
      session.preview,
      ScheduleMonthDayInteractionAdapter.resizePreview(
        for: state,
        currentPointerPanelY: 9 * 60,
        targetDay: targetDay,
        calendar: calendar,
        metrics: metrics
      ).interactionPreview
    )
    XCTAssertEqual(
      session.command,
      .resizeTask(
        taskID: taskID,
        day: targetDay,
        timeMinutes: 9 * 60,
        durationMinutes: 180
      )
    )
  }

  @MainActor
  func testMonthLayoutPerformanceCounterRecordsCacheMissOnly() throws {
    SyncPerformanceCounter.reset()
    defer { SyncPerformanceCounter.reset() }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let cache = ScheduleMonthLayoutCache()

    _ = cache.layout(containing: anchor, items: [], itemsSignature: 0, calendar: calendar)
    _ = cache.layout(containing: anchor, items: [], itemsSignature: 0, calendar: calendar)

    let snapshot = SyncPerformanceCounter.operationSnapshot()
    XCTAssertEqual(snapshot[SyncPerformanceOperation.monthLayout.rawValue]?.count, 1)
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
