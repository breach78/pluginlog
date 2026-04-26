import Foundation
import XCTest
@testable import BrainUnfog

final class ScheduleBoardHostingInvalidationPolicyTests: XCTestCase {
  func testHostedContentVersionIgnoresTransientInteractionSignature() {
    let selectedTaskID = UUID()
    let firstBoardVersion = ScheduleBoardHostingInvalidationPolicy.boardContentVersion(
      today: Date(timeIntervalSinceReferenceDate: 1_234),
      dayRange: -2...30,
      layoutSourceSignature: 100,
      selectedScheduleTaskID: selectedTaskID,
      transientInteractionSignature: 1
    )
    let secondBoardVersion = ScheduleBoardHostingInvalidationPolicy.boardContentVersion(
      today: Date(timeIntervalSinceReferenceDate: 1_234),
      dayRange: -2...30,
      layoutSourceSignature: 100,
      selectedScheduleTaskID: selectedTaskID,
      transientInteractionSignature: 99
    )

    XCTAssertEqual(firstBoardVersion, secondBoardVersion)

    let firstPinnedTopVersion = ScheduleBoardHostingInvalidationPolicy.pinnedTopVersion(
      today: Date(timeIntervalSinceReferenceDate: 1_234),
      dayRange: -2...30,
      layoutSourceSignature: 100,
      calendarSourcesSignature: 200,
      selectedScheduleTaskID: selectedTaskID,
      transientInteractionSignature: 1
    )
    let secondPinnedTopVersion = ScheduleBoardHostingInvalidationPolicy.pinnedTopVersion(
      today: Date(timeIntervalSinceReferenceDate: 1_234),
      dayRange: -2...30,
      layoutSourceSignature: 100,
      calendarSourcesSignature: 200,
      selectedScheduleTaskID: selectedTaskID,
      transientInteractionSignature: 99
    )

    XCTAssertEqual(firstPinnedTopVersion, secondPinnedTopVersion)
  }

  func testHostedContentVersionStillTracksDurableInputs() {
    let selectedTaskID = UUID()
    let baseVersion = ScheduleBoardHostingInvalidationPolicy.boardContentVersion(
      today: Date(timeIntervalSinceReferenceDate: 1_234),
      dayRange: -2...30,
      layoutSourceSignature: 100,
      selectedScheduleTaskID: selectedTaskID,
      transientInteractionSignature: 1
    )
    let changedLayoutVersion = ScheduleBoardHostingInvalidationPolicy.boardContentVersion(
      today: Date(timeIntervalSinceReferenceDate: 1_234),
      dayRange: -2...30,
      layoutSourceSignature: 101,
      selectedScheduleTaskID: selectedTaskID,
      transientInteractionSignature: 1
    )
    let changedSelectionVersion = ScheduleBoardHostingInvalidationPolicy.boardContentVersion(
      today: Date(timeIntervalSinceReferenceDate: 1_234),
      dayRange: -2...30,
      layoutSourceSignature: 100,
      selectedScheduleTaskID: UUID(),
      transientInteractionSignature: 1
    )

    XCTAssertNotEqual(baseVersion, changedLayoutVersion)
    XCTAssertNotEqual(baseVersion, changedSelectionVersion)
  }
}
