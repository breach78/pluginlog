import EventKit
import XCTest
@testable import BrainUnfog

final class ScheduleCalendarAccessPromptPolicyTests: XCTestCase {
  func testRequestsWhenAuthorizationIsNotDetermined() {
    XCTAssertTrue(
      ScheduleCalendarAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .notDetermined,
        promptAttempted: false
      )
    )
  }

  func testDoesNotRequestAgainWhenAuthorizationRemainsNotDeterminedAfterPromptAttempt() {
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

  func testLegacyPromptAttemptDoesNotSuppressDifferentExecutableIdentity() {
    XCTAssertFalse(
      ScheduleCalendarAccessPromptPolicy.promptAttemptedForCurrentIdentity(
        storedIdentity: nil,
        currentIdentity: "build-2",
        legacyPromptAttempted: true
      )
    )
    XCTAssertFalse(
      ScheduleCalendarAccessPromptPolicy.promptAttemptedForCurrentIdentity(
        storedIdentity: "build-1",
        currentIdentity: "build-2",
        legacyPromptAttempted: true
      )
    )
    XCTAssertTrue(
      ScheduleCalendarAccessPromptPolicy.promptAttemptedForCurrentIdentity(
        storedIdentity: "build-2",
        currentIdentity: "build-2",
        legacyPromptAttempted: false
      )
    )
  }
}
