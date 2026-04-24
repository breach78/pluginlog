import EventKit
import XCTest
@testable import BrainUnfogHarness

final class ScheduleCalendarAccessPromptPolicyTests: XCTestCase {
  func testRequestsOnlyWhenAuthorizationIsNotDeterminedAndPromptWasNotAttempted() {
    XCTAssertTrue(
      ScheduleCalendarAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .notDetermined,
        promptAttempted: false
      )
    )
  }

  func testDoesNotRequestAgainAfterPromptWasAttempted() {
    XCTAssertFalse(
      ScheduleCalendarAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .notDetermined,
        promptAttempted: true
      )
    )
  }

  func testDoesNotRequestWhenAuthorizationIsAlreadyResolved() {
    XCTAssertFalse(
      ScheduleCalendarAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .fullAccess,
        promptAttempted: false
      )
    )
    XCTAssertFalse(
      ScheduleCalendarAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .denied,
        promptAttempted: false
      )
    )
  }

  func testDetectsStalePromptAttemptWhenAuthorizationIsStillNotDetermined() {
    XCTAssertTrue(
      ScheduleCalendarAccessPromptPolicy.hasStalePromptAttempt(
        authorizationStatus: .notDetermined,
        promptAttempted: true
      )
    )
  }

  func testPersistsPromptAttemptOnlyAfterAuthorizationIsResolved() {
    XCTAssertFalse(
      ScheduleCalendarAccessPromptPolicy.shouldPersistPromptAttempt(after: .notDetermined)
    )
    XCTAssertTrue(
      ScheduleCalendarAccessPromptPolicy.shouldPersistPromptAttempt(after: .fullAccess)
    )
    XCTAssertTrue(
      ScheduleCalendarAccessPromptPolicy.shouldPersistPromptAttempt(after: .denied)
    )
  }
}
