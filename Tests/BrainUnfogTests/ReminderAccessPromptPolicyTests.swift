import EventKit
import XCTest
@testable import BrainUnfog

final class ReminderAccessPromptPolicyTests: XCTestCase {
  func testRequestsWhenAuthorizationIsNotDetermined() {
    XCTAssertTrue(
      ReminderAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: .notDetermined,
        promptAttempted: false
      )
    )
  }

  func testDoesNotRequestAgainWhenAuthorizationRemainsNotDeterminedAfterPromptAttempt() {
    XCTAssertFalse(
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

  func testLegacyPromptAttemptDoesNotSuppressDifferentExecutableIdentity() {
    XCTAssertFalse(
      ReminderAccessPromptPolicy.promptAttemptedForCurrentIdentity(
        storedIdentity: nil,
        currentIdentity: "build-2",
        legacyPromptAttempted: true
      )
    )
    XCTAssertFalse(
      ReminderAccessPromptPolicy.promptAttemptedForCurrentIdentity(
        storedIdentity: "build-1",
        currentIdentity: "build-2",
        legacyPromptAttempted: true
      )
    )
    XCTAssertTrue(
      ReminderAccessPromptPolicy.promptAttemptedForCurrentIdentity(
        storedIdentity: "build-2",
        currentIdentity: "build-2",
        legacyPromptAttempted: false
      )
    )
  }
}
