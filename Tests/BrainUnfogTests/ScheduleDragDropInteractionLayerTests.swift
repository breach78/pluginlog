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
}
