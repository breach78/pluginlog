import CoreGraphics
import XCTest
@testable import BrainUnfogHarness

final class ScheduleDragDropInteractionLayerTests: XCTestCase {
  func testAllDayItemDraggedIntoTimedGridUsesDefaultScheduledDuration() {
    let metrics = ScheduleInteractionMetrics(
      dayColumnWidth: 120,
      hourHeight: 60,
      quarterHourHeight: 15,
      timeGridHeight: 24 * 60,
      timedMinimumDurationMinutes: WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
    )

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
    let metrics = ScheduleInteractionMetrics(
      dayColumnWidth: 120,
      hourHeight: 60,
      quarterHourHeight: 15,
      timeGridHeight: 24 * 60,
      timedMinimumDurationMinutes: WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
    )

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
}
