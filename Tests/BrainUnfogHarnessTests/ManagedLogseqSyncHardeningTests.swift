import XCTest
@testable import BrainUnfogHarness

final class ManagedLogseqSyncHardeningTests: XCTestCase {
  func testDetectsAmbiguousManagedTaskIdentities() {
    XCTAssertTrue(
      ManagedLogseqSyncHardening.hasAmbiguousManagedTaskIdentities([
        .init(taskID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"), title: "A", isCompleted: false),
        .init(taskID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"), title: "B", isCompleted: false),
      ])
    )
    XCTAssertTrue(
      ManagedLogseqSyncHardening.hasAmbiguousManagedTaskIdentities([
        .init(title: "A", isCompleted: false, reminderExternalIdentifier: "reminder-1"),
        .init(title: "B", isCompleted: false, reminderExternalIdentifier: "reminder-1"),
      ])
    )
    XCTAssertTrue(
      ManagedLogseqSyncHardening.hasAmbiguousManagedTaskIdentities([
        .init(title: "A", isCompleted: false, calendarEventExternalIdentifier: "event-1"),
        .init(title: "B", isCompleted: false, calendarEventExternalIdentifier: "event-1"),
      ])
    )
  }

  func testAllowsManagedTaskCreationOnlyForSafeIdentityShapes() {
    XCTAssertTrue(
      ManagedLogseqSyncHardening.allowsManagedTaskCreation(
        .init(title: "Fresh task", isCompleted: false),
        remoteMatchCount: 0
      )
    )
    XCTAssertTrue(
      ManagedLogseqSyncHardening.allowsManagedTaskCreation(
        .init(title: "Claim remote", isCompleted: false, reminderExternalIdentifier: "reminder-1"),
        remoteMatchCount: 1
      )
    )
    XCTAssertFalse(
      ManagedLogseqSyncHardening.allowsManagedTaskCreation(
        .init(title: "Ambiguous remote", isCompleted: false, reminderExternalIdentifier: "reminder-1"),
        remoteMatchCount: 2
      )
    )
    XCTAssertFalse(
      ManagedLogseqSyncHardening.allowsManagedTaskCreation(
        .init(
          taskID: UUID(),
          title: "Damaged hidden task id",
          isCompleted: false,
          reminderExternalIdentifier: "reminder-1"
        ),
        remoteMatchCount: 1
      )
    )
    XCTAssertFalse(
      ManagedLogseqSyncHardening.allowsManagedTaskCreation(
        .init(
          title: "Calendar orphan",
          isCompleted: false,
          calendarEventExternalIdentifier: "event-1"
        ),
        remoteMatchCount: 0
      )
    )
  }

  func testProjectIdentityConsistencyRequiresMatchingDerivedProjectID() {
    let externalIdentifier = "reminder-list-1"
    let derivedProjectID = ReminderProjectionIdentity.projectID(for: externalIdentifier)

    XCTAssertTrue(
      ManagedLogseqSyncHardening.isConsistentProjectIdentity(
        pageProjectID: derivedProjectID,
        reminderListExternalIdentifier: externalIdentifier
      )
    )
    XCTAssertFalse(
      ManagedLogseqSyncHardening.isConsistentProjectIdentity(
        pageProjectID: UUID(),
        reminderListExternalIdentifier: externalIdentifier
      )
    )
  }

  func testAmbiguousOwnedCalendarEventIdentifiersRequireFailClosedBehavior() {
    let duplicateIdentifier = "event-1"
    let bindings: [AppState.RuntimeLogseqTaskBinding] = [
      .init(
        taskID: UUID(),
        reminderIdentifier: nil,
        reminderExternalIdentifier: "reminder-1",
        title: "A",
        isCompleted: false,
        dueDate: nil,
        hasExplicitTime: false,
        recurrenceRuleRaw: nil,
        durationMinutes: nil,
        calendarEventExternalIdentifier: duplicateIdentifier
      ),
      .init(
        taskID: UUID(),
        reminderIdentifier: nil,
        reminderExternalIdentifier: "reminder-2",
        title: "B",
        isCompleted: false,
        dueDate: nil,
        hasExplicitTime: false,
        recurrenceRuleRaw: nil,
        durationMinutes: nil,
        calendarEventExternalIdentifier: duplicateIdentifier
      ),
    ]

    XCTAssertEqual(
      ManagedLogseqSyncHardening.ambiguousOwnedCalendarEventIdentifiers(bindings),
      [duplicateIdentifier]
    )
  }
}
