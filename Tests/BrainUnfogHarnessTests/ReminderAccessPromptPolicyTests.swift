import EventKit
import XCTest
@testable import BrainUnfogHarness

final class ReminderAccessPromptPolicyTests: XCTestCase {
  func testRequestsOnlyWhenAuthorizationIsNotDeterminedAndPromptWasNotAttempted() {
    XCTAssertTrue(
      ReminderAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .notDetermined,
        promptAttempted: false
      )
    )
  }

  func testRequestsAgainWhenAuthorizationIsStillNotDeterminedAfterPromptWasAttempted() {
    XCTAssertTrue(
      ReminderAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .notDetermined,
        promptAttempted: true
      )
    )
  }

  func testDoesNotRequestWhenAuthorizationIsAlreadyResolved() {
    XCTAssertFalse(
      ReminderAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .fullAccess,
        promptAttempted: false
      )
    )
    XCTAssertFalse(
      ReminderAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .denied,
        promptAttempted: false
      )
    )
  }
}
