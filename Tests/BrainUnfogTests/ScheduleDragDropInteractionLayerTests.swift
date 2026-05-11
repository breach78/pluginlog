import CoreGraphics
import XCTest
@testable import BrainUnfog

final class ScheduleDragDropInteractionLayerTests: XCTestCase {
  private let metrics = ScheduleInteractionMetrics(
    dayColumnWidth: 120,
    hourHeight: 60,
    quarterHourHeight: 15,
    timeGridHeight: 24 * 60,
    timedMinimumDurationMinutes: WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
  )

  func testAllDayItemDraggedIntoTimedGridUsesDefaultScheduledDuration() {
    let preview = ScheduleDragDropInteractionLayer.preview(
      originalDay: Date(timeIntervalSince1970: 0),
      originalTimeMinutes: nil,
      originalDurationMinutes: nil,
      translation: CGSize(width: 0, height: 180),
      originalPointerScheduleY: -40,
      originalTopScheduleY: -60,
      currentPointerScheduleY: 180,
      currentTopScheduleY: 160,
      metrics: metrics,
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertNotNil(preview.timeMinutes)
    XCTAssertEqual(preview.durationMinutes, 30)
  }

  func testTimedItemDraggedIntoAllDayZonePresentsAsAllDay() {
    let preview = ScheduleDragDropInteractionLayer.preview(
      originalDay: Date(timeIntervalSince1970: 0),
      originalTimeMinutes: 10 * 60,
      originalDurationMinutes: 60,
      translation: CGSize(width: 120, height: -220),
      originalPointerScheduleY: 10 * 60,
      originalTopScheduleY: 10 * 60,
      currentPointerScheduleY: -20,
      currentTopScheduleY: -40,
      forceAllDay: true,
      metrics: metrics,
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertNil(preview.timeMinutes)
    XCTAssertNil(preview.durationMinutes)
  }

  func testDragPreviewCanDisableDateSnapping() {
    let calendar = Calendar(identifier: .gregorian)
    let originalDay = Date(timeIntervalSince1970: 0)

    let preview = ScheduleDragDropInteractionLayer.preview(
      originalDay: originalDay,
      originalTimeMinutes: 10 * 60,
      originalDurationMinutes: 60,
      translation: CGSize(width: 260, height: 0),
      originalPointerScheduleY: 10 * 60,
      originalTopScheduleY: 10 * 60,
      allowsDayChange: false,
      metrics: metrics,
      calendar: calendar
    )

    XCTAssertEqual(preview.day, originalDay)
  }

  func testDragPreviewSnapsDateWhenDateChangesAreAllowed() throws {
    let calendar = Calendar(identifier: .gregorian)
    let originalDay = Date(timeIntervalSince1970: 0)
    let expectedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: originalDay))

    let preview = ScheduleDragDropInteractionLayer.preview(
      originalDay: originalDay,
      originalTimeMinutes: 10 * 60,
      originalDurationMinutes: 60,
      translation: CGSize(width: 260, height: 0),
      originalPointerScheduleY: 10 * 60,
      originalTopScheduleY: 10 * 60,
      allowsDayChange: true,
      metrics: metrics,
      calendar: calendar
    )

    XCTAssertEqual(preview.day, expectedDay)
  }

  func testTimedDragPreservesDurationWhenMovedPastMidnight() {
    let preview = ScheduleDragDropInteractionLayer.preview(
      originalDay: Date(timeIntervalSince1970: 0),
      originalTimeMinutes: 20 * 60,
      originalDurationMinutes: 6 * 60,
      translation: CGSize(width: 0, height: 2 * 60),
      originalPointerScheduleY: 20 * 60,
      originalTopScheduleY: 20 * 60,
      metrics: metrics,
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertEqual(preview.timeMinutes, 22 * 60)
    XCTAssertEqual(preview.durationMinutes, 6 * 60)
  }

  func testTimedDragOnLaterVisibleSegmentUsesVisibleTargetDayForSourceStart() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let may8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8)))

    let preview = ScheduleDragDropInteractionLayer.preview(
      originalDay: may7,
      originalTimeMinutes: 22 * 60,
      originalDurationMinutes: 6 * 60,
      translation: CGSize(width: 0, height: 60),
      originalPointerScheduleY: 0,
      originalTopScheduleY: -2 * 60,
      currentPointerScheduleY: 60,
      currentTopScheduleY: -60,
      targetDay: may8,
      metrics: metrics,
      calendar: calendar
    )

    XCTAssertEqual(preview.day, may7)
    XCTAssertEqual(preview.timeMinutes, 23 * 60)
    XCTAssertEqual(preview.durationMinutes, 6 * 60)
  }

  func testEndResizePreservesDurationPastMidnight() {
    let preview = ScheduleTimeResizingInteractionLayer.preview(
      originalDay: Date(timeIntervalSince1970: 0),
      originalTimeMinutes: 22 * 60,
      originalDurationMinutes: 3 * 60,
      isStartEdge: false,
      translationHeight: 60,
      metrics: metrics
    )

    XCTAssertEqual(preview.timeMinutes, 22 * 60)
    XCTAssertEqual(preview.durationMinutes, 4 * 60)
  }

  func testStartResizePreservesOvernightEndInsteadOfClampingToSameDay() {
    let preview = ScheduleTimeResizingInteractionLayer.preview(
      originalDay: Date(timeIntervalSince1970: 0),
      originalTimeMinutes: 22 * 60,
      originalDurationMinutes: 4 * 60,
      isStartEdge: true,
      translationHeight: 60,
      metrics: metrics
    )

    XCTAssertEqual(preview.timeMinutes, 23 * 60)
    XCTAssertEqual(preview.durationMinutes, 3 * 60)
  }

  func testEndResizeOnLaterVisibleSegmentUsesVisibleTargetDayForSourceStart() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)))
    let may8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8)))

    let preview = ScheduleTimeResizingInteractionLayer.preview(
      originalDay: may7,
      originalTimeMinutes: 22 * 60,
      originalDurationMinutes: 6 * 60,
      isStartEdge: false,
      originalPointerScheduleY: 4 * 60,
      originalEdgeScheduleY: 4 * 60,
      currentPointerScheduleY: 5 * 60,
      fallbackTranslationHeight: 0,
      targetDay: may8,
      calendar: calendar,
      metrics: metrics
    )

    XCTAssertEqual(preview.day, may7)
    XCTAssertEqual(preview.timeMinutes, 22 * 60)
    XCTAssertEqual(preview.durationMinutes, 7 * 60)
  }

  func testMoveTaskCommandUsesScheduleInteractionPreviewValues() {
    let taskID = UUID()
    let day = Date(timeIntervalSince1970: 0)
    let preview = ScheduleInteractionPreview(
      day: day,
      timeMinutes: 9 * 60,
      durationMinutes: 75
    )

    let command = ScheduleInteractionEngine.command(
      for: .task(taskID),
      operation: .move,
      preview: preview
    )

    XCTAssertEqual(
      command,
      .moveTask(
        taskID: taskID,
        day: day,
        timeMinutes: 9 * 60,
        durationMinutes: 75
      )
    )
  }

  func testInteractionSessionBuildsMovePreviewAndCommandFromSameTarget() throws {
    let taskID = UUID()
    let day = Date(timeIntervalSince1970: 0)
    let session = try XCTUnwrap(ScheduleInteractionSession.move(
      identity: .task(taskID),
      originalTimeMinutes: 8 * 60,
      originalDurationMinutes: 75,
      target: .timed(day: day, minute: 11 * 60),
      metrics: metrics
    ))

    XCTAssertEqual(
      session.preview,
      ScheduleInteractionPreview(
        day: day,
        timeMinutes: 11 * 60,
        durationMinutes: 75
      )
    )
    XCTAssertEqual(
      session.command,
      .moveTask(
        taskID: taskID,
        day: day,
        timeMinutes: 11 * 60,
        durationMinutes: 75
      )
    )
  }

  func testInteractionSessionBuildsResizePreviewAndCommandFromSameGeometry() throws {
    let taskID = UUID()
    let day = Date(timeIntervalSince1970: 0)
    let target = ScheduleInteractionEngine.timedTarget(
      visibleDay: day,
      scheduleY: 9 * 60,
      metrics: metrics,
      calendar: Calendar(identifier: .gregorian)
    )
    let session = try XCTUnwrap(ScheduleInteractionSession.resize(
      identity: .task(taskID),
      originalDay: day,
      originalTimeMinutes: 10 * 60,
      originalDurationMinutes: 120,
      isStartEdge: true,
      target: target,
      metrics: metrics,
      calendar: Calendar(identifier: .gregorian)
    ))

    XCTAssertEqual(
      session.preview,
      ScheduleInteractionPreview(
        day: day,
        timeMinutes: 9 * 60,
        durationMinutes: 180
      )
    )
    XCTAssertEqual(
      session.command,
      .resizeTask(
        taskID: taskID,
        day: day,
        timeMinutes: 9 * 60,
        durationMinutes: 180
      )
    )
  }

  func testResizeSessionBuildsPreviewAndCommandFromCommonTarget() throws {
    let taskID = UUID()
    let day = Date(timeIntervalSince1970: 0)
    let target = ScheduleInteractionEngine.timedTarget(
      visibleDay: day,
      scheduleY: 9 * 60,
      metrics: metrics,
      calendar: Calendar(identifier: .gregorian)
    )

    let session = try XCTUnwrap(ScheduleInteractionSession.resize(
      identity: .task(taskID),
      originalDay: day,
      originalTimeMinutes: 10 * 60,
      originalDurationMinutes: 120,
      isStartEdge: true,
      target: target,
      metrics: metrics,
      calendar: Calendar(identifier: .gregorian)
    ))

    XCTAssertEqual(
      session.preview,
      ScheduleInteractionPreview(
        day: day,
        timeMinutes: 9 * 60,
        durationMinutes: 180
      )
    )
    XCTAssertEqual(
      session.command,
      .resizeTask(
        taskID: taskID,
        day: day,
        timeMinutes: 9 * 60,
        durationMinutes: 180
      )
    )
  }

  func testViewportProjectionUsesCommittedPreviewDayForResizeFrame() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may12 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
    let may13 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13)))
    let preview = ScheduleInteractionPreview(
      day: may13,
      timeMinutes: 11 * 60,
      durationMinutes: 90
    )
    let projectionMetrics = ScheduleInteractionViewportProjectionMetrics(
      titleColumnWidth: 76,
      dayColumnWidth: 120,
      hourHeight: 60,
      quarterHourHeight: 15,
      currentScrollOffsetX: 0,
      currentScrollOffsetY: 0,
      dateHeaderHeight: 32,
      allDayRailPadding: 6,
      allDayRailVisibleHeight: 48,
      allDayRowHeight: 24,
      allDayChipHorizontalInset: 5,
      timedBlockInset: 4,
      timedMinimumDurationMinutes: 30
    )
    let dayIndexByDate = [may12: 0, may13: 1]

    let frame = ScheduleInteractionViewportProjection.timedFrame(
      for: preview,
      dayIndexByDate: dayIndexByDate,
      metrics: projectionMetrics,
      xOffsetWithinDay: 10,
      width: 84
    )

    XCTAssertEqual(
      frame,
      CGRect(x: 76 + 120 + 10, y: 32 + 48 + 11 * 60, width: 84, height: 90)
    )
  }

  func testViewportProjectionKeepsCommittedDurationPastMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may12 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
    let preview = ScheduleInteractionPreview(
      day: may12,
      timeMinutes: 23 * 60,
      durationMinutes: 6 * 60
    )
    let projectionMetrics = ScheduleInteractionViewportProjectionMetrics(
      titleColumnWidth: 76,
      dayColumnWidth: 120,
      hourHeight: 60,
      quarterHourHeight: 15,
      currentScrollOffsetX: 0,
      currentScrollOffsetY: 0,
      dateHeaderHeight: 32,
      allDayRailPadding: 6,
      allDayRailVisibleHeight: 48,
      allDayRowHeight: 24,
      allDayChipHorizontalInset: 5,
      timedBlockInset: 4,
      timedMinimumDurationMinutes: 30
    )

    let frame = ScheduleInteractionViewportProjection.dragDropFrame(
      for: preview,
      dayIndexByDate: [may12: 0],
      metrics: projectionMetrics
    )

    XCTAssertEqual(
      frame,
      CGRect(x: 76 + 4, y: 32 + 48 + 23 * 60, width: 120 - 8, height: 6 * 60)
    )
  }

  func testMoveTaskCommandFromTimedTargetPreservesExistingDuration() {
    let taskID = UUID()
    let day = Date(timeIntervalSince1970: 0)

    let command = ScheduleInteractionEngine.moveCommand(
      for: .task(taskID),
      originalTimeMinutes: 9 * 60,
      originalDurationMinutes: 95,
      target: .timed(day: day, minute: 13 * 60),
      metrics: metrics
    )

    XCTAssertEqual(
      command,
      .moveTask(
        taskID: taskID,
        day: day,
        timeMinutes: 13 * 60,
        durationMinutes: 95
      )
    )
  }

  func testMoveCalendarCommandFromMonthTargetPreservesExistingTimedShape() {
    let day = Date(timeIntervalSince1970: 0)

    let command = ScheduleInteractionEngine.moveCommand(
      for: .calendarEvent("event-1"),
      originalTimeMinutes: 15 * 60,
      originalDurationMinutes: 180,
      target: .monthDay(day),
      metrics: metrics
    )

    XCTAssertEqual(
      command,
      .moveCalendarEvent(
        eventID: "event-1",
        day: day,
        timeMinutes: 15 * 60,
        durationMinutes: 180
      )
    )
  }

  func testPointerViewportXMapsToVisibleDayColumn() {
    let calendar = Calendar(identifier: .gregorian)
    let firstDay = Date(timeIntervalSince1970: 0)
    let days = (0..<3).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }

    let pointerDay = ScheduleDragDropInteractionLayer.dayForPointerViewportX(
      76 + 120 + 40,
      titleColumnWidth: 76,
      scrollOffsetX: 0,
      days: days,
      metrics: metrics
    )

    XCTAssertEqual(pointerDay, days[1])
  }

  func testPointerViewportXMappingAccountsForHorizontalScroll() {
    let calendar = Calendar(identifier: .gregorian)
    let firstDay = Date(timeIntervalSince1970: 0)
    let days = (0..<4).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }

    let pointerDay = ScheduleDragDropInteractionLayer.dayForPointerViewportX(
      76 + 30,
      titleColumnWidth: 76,
      scrollOffsetX: 240,
      days: days,
      metrics: metrics
    )

    XCTAssertEqual(pointerDay, days[2])
  }

  func testPointerDayCanChangeWhenTranslationDateSnappingIsDisabled() {
    let calendar = Calendar(identifier: .gregorian)
    let firstDay = Date(timeIntervalSince1970: 0)
    let days = (0..<4).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }
    let preview = ScheduleInteractionPreview(
      day: firstDay,
      timeMinutes: 10 * 60,
      durationMinutes: 60
    )

    let resolvedPreview = ScheduleDragDropInteractionLayer.previewByApplyingPointerDay(
      preview,
      pointerViewportLocation: CGPoint(x: 76 + 120 + 40, y: 300),
      allowsDayChange: true,
      titleColumnWidth: 76,
      scrollOffsetX: 0,
      days: days,
      metrics: metrics
    )

    XCTAssertEqual(resolvedPreview.day, days[1])
    XCTAssertEqual(resolvedPreview.timeMinutes, preview.timeMinutes)
    XCTAssertEqual(resolvedPreview.durationMinutes, preview.durationMinutes)
  }

  func testDateBoundarySnapPolicySkipsTargetWhenDisabled() {
    XCTAssertNil(
      ScheduleDateBoundarySnapPolicy.targetX(
        isEnabled: false,
        originX: 82,
        dayColumnWidth: 44,
        documentWidth: 500,
        viewportWidth: 160
      )
    )
  }

  func testDateBoundarySnapPolicyRoundsToNearestDayColumnWhenEnabled() {
    XCTAssertEqual(
      ScheduleDateBoundarySnapPolicy.targetX(
        isEnabled: true,
        originX: 82,
        dayColumnWidth: 44,
        documentWidth: 500,
        viewportWidth: 160
      ),
      88
    )
  }

  func testAllDayPreviewViewportYPreservesGrabOffset() {
    let y = ScheduleDragDropInteractionLayer.allDayPreviewViewportY(
      pointerViewportY: 210,
      originalPointerViewportY: 130,
      originalViewportMinY: 120,
      translationHeight: 80,
      dateHeaderHeight: 48,
      allDayRailPadding: 6,
      allDayRailVisibleHeight: 240,
      previewHeight: 32
    )

    XCTAssertEqual(y, 200)
  }

  func testAllDayPreviewViewportYClampsToVisibleRail() {
    let y = ScheduleDragDropInteractionLayer.allDayPreviewViewportY(
      pointerViewportY: 400,
      originalPointerViewportY: 130,
      originalViewportMinY: 120,
      translationHeight: 270,
      dateHeaderHeight: 48,
      allDayRailPadding: 6,
      allDayRailVisibleHeight: 120,
      previewHeight: 32
    )

    XCTAssertEqual(y, 136)
  }

  func testDragGhostFollowsPointerInsteadOfResolvedDropFrame() {
    let originalFrame = CGRect(x: 180, y: 420, width: 160, height: 240)
    let dropFrame = CGRect(x: 760, y: 180, width: 150, height: 120)

    let ghostFrame = ScheduleDragDropInteractionLayer.dragGhostViewportFrame(
      resolvedDropFrame: dropFrame,
      originalViewportFrame: originalFrame,
      translation: CGSize(width: -280, height: 90),
      allowsHorizontalMovement: true
    )

    XCTAssertEqual(ghostFrame, originalFrame.offsetBy(dx: -280, dy: 90))
  }

  func testDragGhostFallsBackToTranslationWithoutResolvedDropFrame() {
    let originalFrame = CGRect(x: 180, y: 420, width: 160, height: 240)

    let ghostFrame = ScheduleDragDropInteractionLayer.dragGhostViewportFrame(
      resolvedDropFrame: nil,
      originalViewportFrame: originalFrame,
      translation: CGSize(width: -80, height: 90),
      allowsHorizontalMovement: true
    )

    XCTAssertEqual(ghostFrame, originalFrame.offsetBy(dx: -80, dy: 90))
  }

  func testDragGhostUsesCurrentPointerWhenAvailable() {
    let originalFrame = CGRect(x: 180, y: 420, width: 160, height: 240)

    let ghostFrame = ScheduleDragDropInteractionLayer.dragGhostViewportFrame(
      resolvedDropFrame: nil,
      originalViewportFrame: originalFrame,
      translation: CGSize(width: -80, height: 90),
      currentPointerViewportLocation: CGPoint(x: 310, y: 700),
      originalPointerViewportX: 220,
      originalPointerViewportY: 500,
      allowsHorizontalMovement: true
    )

    XCTAssertEqual(ghostFrame, CGRect(x: 270, y: 620, width: 160, height: 240))
  }

  func testInitialPointerViewportLocationUsesCurrentPointerMinusTranslation() {
    let originalFrame = CGRect(x: 180, y: 420, width: 160, height: 240)

    let point = ScheduleDragDropInteractionLayer.initialPointerViewportLocation(
      currentPointerViewportLocation: CGPoint(x: 310, y: 700),
      translation: CGSize(width: 90, height: 200),
      originalViewportFrame: originalFrame,
      gestureStartLocation: CGPoint(x: 40, y: 80)
    )

    XCTAssertEqual(point, CGPoint(x: 220, y: 500))
  }

  func testInitialPointerViewportLocationKeepsOffsetGestureCoordinatesFromDoubleAdding() {
    let originalFrame = CGRect(x: 180, y: 420, width: 160, height: 240)

    let point = ScheduleDragDropInteractionLayer.initialPointerViewportLocation(
      currentPointerViewportLocation: nil,
      translation: .zero,
      originalViewportFrame: originalFrame,
      gestureStartLocation: CGPoint(x: 220, y: 500)
    )

    XCTAssertEqual(point, CGPoint(x: 220, y: 500))
  }

  func testInitialPointerViewportLocationSupportsLocalGestureCoordinates() {
    let originalFrame = CGRect(x: 180, y: 420, width: 160, height: 240)

    let point = ScheduleDragDropInteractionLayer.initialPointerViewportLocation(
      currentPointerViewportLocation: nil,
      translation: .zero,
      originalViewportFrame: originalFrame,
      gestureStartLocation: CGPoint(x: 40, y: 80)
    )

    XCTAssertEqual(point, CGPoint(x: 220, y: 500))
  }

  func testDragTopScheduleYUsesCurrentPointerAndGrabOffset() {
    let topY = ScheduleDragDropInteractionLayer.dragTopScheduleY(
      currentPointerScheduleY: 620,
      originalPointerScheduleY: 515,
      originalTopScheduleY: 480,
      fallbackTopScheduleY: 700
    )

    XCTAssertEqual(topY, 585)
  }

  func testDragTopScheduleYUsesFallbackWhenPointerIsUnavailable() {
    let topY = ScheduleDragDropInteractionLayer.dragTopScheduleY(
      currentPointerScheduleY: nil,
      originalPointerScheduleY: 515,
      originalTopScheduleY: 480,
      fallbackTopScheduleY: 700
    )

    XCTAssertEqual(topY, 700)
  }

  func testEndResizeUsesCurrentPointerAndGrabOffset() {
    let preview = ScheduleTimeResizingInteractionLayer.preview(
      originalDay: Date(timeIntervalSince1970: 0),
      originalTimeMinutes: 9 * 60,
      originalDurationMinutes: 120,
      isStartEdge: false,
      originalPointerScheduleY: 665,
      originalEdgeScheduleY: 660,
      currentPointerScheduleY: 725,
      fallbackTranslationHeight: 0,
      metrics: metrics
    )

    XCTAssertEqual(preview.timeMinutes, 9 * 60)
    XCTAssertEqual(preview.durationMinutes, 180)
  }

  func testStartResizeUsesCurrentPointerAndGrabOffset() {
    let preview = ScheduleTimeResizingInteractionLayer.preview(
      originalDay: Date(timeIntervalSince1970: 0),
      originalTimeMinutes: 9 * 60,
      originalDurationMinutes: 120,
      isStartEdge: true,
      originalPointerScheduleY: 545,
      originalEdgeScheduleY: 540,
      currentPointerScheduleY: 605,
      fallbackTranslationHeight: 0,
      metrics: metrics
    )

    XCTAssertEqual(preview.timeMinutes, 10 * 60)
    XCTAssertEqual(preview.durationMinutes, 60)
  }
}
