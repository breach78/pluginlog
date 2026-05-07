import XCTest
@testable import BrainUnfog

final class ScheduleTimedBlockHitPriorityPolicyTests: XCTestCase {
  func testSelectedTaskWinsResizeHitPriorityAtSharedEdge() {
    let upperTaskID = UUID()
    let lowerTaskID = UUID()
    let upperPriority = ScheduleTimedBlockHitPriorityPolicy.zIndex(
      isTask: true,
      taskID: upperTaskID,
      selectedTaskID: lowerTaskID,
      startMinute: 9 * 60,
      isBackgroundCalendar: false
    )
    let lowerPriority = ScheduleTimedBlockHitPriorityPolicy.zIndex(
      isTask: true,
      taskID: lowerTaskID,
      selectedTaskID: lowerTaskID,
      startMinute: 10 * 60,
      isBackgroundCalendar: false
    )

    XCTAssertGreaterThan(lowerPriority, upperPriority)
  }

  func testEarlierTaskWinsResizeHitPriorityWhenNoTaskIsSelected() {
    let upperPriority = ScheduleTimedBlockHitPriorityPolicy.zIndex(
      isTask: true,
      taskID: UUID(),
      selectedTaskID: nil,
      startMinute: 9 * 60,
      isBackgroundCalendar: false
    )
    let lowerPriority = ScheduleTimedBlockHitPriorityPolicy.zIndex(
      isTask: true,
      taskID: UUID(),
      selectedTaskID: nil,
      startMinute: 10 * 60,
      isBackgroundCalendar: false
    )

    XCTAssertGreaterThan(upperPriority, lowerPriority)
  }

  func testUnrelatedSelectionFallsBackToEarlierTaskPriority() {
    let unrelatedTaskID = UUID()
    let upperPriority = ScheduleTimedBlockHitPriorityPolicy.zIndex(
      isTask: true,
      taskID: UUID(),
      selectedTaskID: unrelatedTaskID,
      startMinute: 9 * 60,
      isBackgroundCalendar: false
    )
    let lowerPriority = ScheduleTimedBlockHitPriorityPolicy.zIndex(
      isTask: true,
      taskID: UUID(),
      selectedTaskID: unrelatedTaskID,
      startMinute: 10 * 60,
      isBackgroundCalendar: false
    )

    XCTAssertGreaterThan(upperPriority, lowerPriority)
  }
}
