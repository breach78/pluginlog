import XCTest
@testable import BrainUnfog

final class ReminderTaskAdoptionPolicyTests: XCTestCase {
  func testAllowsAdoptionOnlyWhenReminderBelongsToTargetList() {
    XCTAssertTrue(
      ReminderTaskAdoptionPolicy.allowsExternalReminderAdoption(
        candidateCalendarIdentifier: "list-1",
        targetReminderListIdentifier: "list-1"
      )
    )
    XCTAssertFalse(
      ReminderTaskAdoptionPolicy.allowsExternalReminderAdoption(
        candidateCalendarIdentifier: "list-2",
        targetReminderListIdentifier: "list-1"
      )
    )
  }

  func testRejectsAdoptionWhenEitherIdentifierIsMissing() {
    XCTAssertFalse(
      ReminderTaskAdoptionPolicy.allowsExternalReminderAdoption(
        candidateCalendarIdentifier: nil,
        targetReminderListIdentifier: "list-1"
      )
    )
    XCTAssertFalse(
      ReminderTaskAdoptionPolicy.allowsExternalReminderAdoption(
        candidateCalendarIdentifier: "list-1",
        targetReminderListIdentifier: nil
      )
    )
  }

  func testTrimsIdentifiersBeforeComparing() {
    XCTAssertTrue(
      ReminderTaskAdoptionPolicy.allowsExternalReminderAdoption(
        candidateCalendarIdentifier: " list-1 ",
        targetReminderListIdentifier: "list-1"
      )
    )
  }

  func testUniqueMatchRejectsAmbiguousExternalIdentifierMatches() {
    XCTAssertNil(ReminderTaskAdoptionPolicy.uniqueMatch(from: [1, 2]))
    XCTAssertEqual(ReminderTaskAdoptionPolicy.uniqueMatch(from: [7]), 7)
  }
}
