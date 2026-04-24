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

  func testRequestsAgainWhenAuthorizationIsStillNotDeterminedAfterPromptWasAttempted() {
    XCTAssertTrue(
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

  func testDoesNotTreatStoredPromptAttemptAsStaleWhenAuthorizationIsStillNotDetermined() {
    XCTAssertFalse(
      ScheduleCalendarAccessPromptPolicy.hasStalePromptAttempt(
        authorizationStatus: .notDetermined,
        promptAttempted: true
      )
    )
  }

  func testPersistsPromptAttemptForNotDeterminedAndResolvedAuthorization() {
    XCTAssertTrue(
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
