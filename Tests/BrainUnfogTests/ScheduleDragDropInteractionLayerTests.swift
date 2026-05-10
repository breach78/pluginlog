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

  func testDragGhostUsesResolvedDropFrameWhenAvailable() {
    let originalFrame = CGRect(x: 180, y: 420, width: 160, height: 240)
    let dropFrame = CGRect(x: 760, y: 180, width: 150, height: 120)

    let ghostFrame = ScheduleDragDropInteractionLayer.dragGhostViewportFrame(
      resolvedDropFrame: dropFrame,
      originalViewportFrame: originalFrame,
      translation: CGSize(width: -280, height: 90),
      allowsHorizontalMovement: true
    )

    XCTAssertEqual(ghostFrame, dropFrame)
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
}
