import SwiftUI
import XCTest
@testable import BrainUnfog

final class ScheduleHiddenTimedItemIndicatorPolicyTests: XCTestCase {
  func testVisibleStartMinuteUsesPinnedHeaderCoveredTimelineStart() {
    let minute = ScheduleHiddenTimedItemIndicatorPolicy.visibleStartMinute(
      scrollOffsetY: 6 * 60,
      hourHeight: 60
    )

    XCTAssertEqual(minute, 6 * 60)
  }

  func testHiddenDayIndexesIncludesOnlyFullyHiddenTimedItems() {
    let layouts = [
      makeLayout(dayIndex: 0, startMinute: 5 * 60, endMinute: 6 * 60),
      makeLayout(dayIndex: 1, startMinute: 5 * 60 + 30, endMinute: 6 * 60 + 30),
      makeLayout(dayIndex: 2, startMinute: 9 * 60, endMinute: 10 * 60)
    ]

    let hiddenDayIndexes = ScheduleHiddenTimedItemIndicatorPolicy.hiddenDayIndexes(
      layouts: layouts,
      visibleStartMinute: 6 * 60
    )

    XCTAssertEqual(hiddenDayIndexes, [0])
  }

  func testEarliestHiddenStartMinuteFindsTargetDayOnly() {
    let layouts = [
      makeLayout(dayIndex: 0, startMinute: 4 * 60, endMinute: 5 * 60),
      makeLayout(dayIndex: 1, startMinute: 3 * 60, endMinute: 4 * 60),
      makeLayout(dayIndex: 0, startMinute: 2 * 60, endMinute: 3 * 60)
    ]

    let startMinute = ScheduleHiddenTimedItemIndicatorPolicy.earliestHiddenStartMinute(
      dayIndex: 0,
      layouts: layouts,
      visibleStartMinute: 6 * 60
    )

    XCTAssertEqual(startMinute, 2 * 60)
  }

  private func makeLayout(
    dayIndex: Int,
    startMinute: Int,
    endMinute: Int
  ) -> ScheduleTimedBlockLayout {
    let id = "\(dayIndex)-\(startMinute)-\(endMinute)"
    return ScheduleTimedBlockLayout(
      id: id,
      entry: ScheduleTimedEntry(
        id: id,
        dayIndex: dayIndex,
        startMinute: startMinute,
        durationMinutes: endMinute - startMinute,
        endMinute: endMinute,
        sourceStartDay: Date(timeIntervalSince1970: 0),
        sourceStartMinute: startMinute,
        sourceDurationMinutes: endMinute - startMinute,
        isFirstSegment: true,
        isLastSegment: true,
        title: "item",
        subtitle: nil,
        color: .blue,
        isTask: true,
        isPreparationSlot: false,
        targetCompletedWorkUnits: nil,
        taskDescriptor: nil,
        event: nil,
        isBackgroundCalendar: false,
        contentTopOffset: 0
      ),
      column: 0,
      columnCount: 1,
      columnSpan: 1
    )
  }
}
