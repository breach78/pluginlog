import XCTest
@testable import BrainUnfog

final class RecurringCompletionUndoScheduleRestorePolicyTests: XCTestCase {
  func testRestoresTimedScheduleWhenUndoingCompletedRecurringTask() {
    let fields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: Date(timeIntervalSince1970: 0),
      timeMinutes: 9 * 60,
      durationMinutes: 45
    )

    XCTAssertTrue(
      RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
        previousIsCompleted: true,
        nextIsCompleted: false,
        isRecurring: true,
        fields: fields
      )
    )
  }

  func testRestoresAllDayScheduleWhenUndoingCompletedRecurringTask() {
    let fields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: Date(timeIntervalSince1970: 0),
      timeMinutes: nil,
      durationMinutes: nil
    )

    XCTAssertTrue(
      RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
        previousIsCompleted: true,
        nextIsCompleted: false,
        isRecurring: true,
        fields: fields
      )
    )
  }

  func testDoesNotRestoreWhenTargetHasNoDay() {
    let fields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: nil,
      timeMinutes: nil,
      durationMinutes: nil
    )

    XCTAssertFalse(
      RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
        previousIsCompleted: true,
        nextIsCompleted: false,
        isRecurring: true,
        fields: fields
      )
    )
  }

  func testRestoresWhenRecurringCompletionUndoMovesBackFromAdvancedNextOccurrence() {
    let currentFields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: Date(timeIntervalSince1970: 8 * 24 * 60 * 60),
      timeMinutes: nil,
      durationMinutes: nil
    )
    let targetFields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: Date(timeIntervalSince1970: 0),
      timeMinutes: 12 * 60,
      durationMinutes: 45
    )

    XCTAssertTrue(
      RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
        previousIsCompleted: false,
        nextIsCompleted: false,
        isRecurring: true,
        previousFields: currentFields,
        fields: targetFields
      )
    )
  }

  func testRecurringCompletionUndoSkipsCompletionWriteAndRestoresScheduleOnly() {
    let advancedNextOccurrenceFields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: Date(timeIntervalSince1970: 8 * 24 * 60 * 60),
      timeMinutes: nil,
      durationMinutes: nil
    )
    let originalOccurrenceFields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: Date(timeIntervalSince1970: 0),
      timeMinutes: 13 * 60,
      durationMinutes: 30
    )

    XCTAssertFalse(
      RecurringCompletionUndoScheduleRestorePolicy.shouldWriteCompletion(
        previousIsCompleted: false,
        nextIsCompleted: false,
        isRecurring: true,
        previousFields: advancedNextOccurrenceFields,
        fields: originalOccurrenceFields
      )
    )
    XCTAssertTrue(
      RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
        previousIsCompleted: false,
        nextIsCompleted: false,
        isRecurring: true,
        previousFields: advancedNextOccurrenceFields,
        fields: originalOccurrenceFields
      )
    )
  }

  func testRecurringCompletionRedoRestoresAdvancedAllDayOccurrence() {
    let originalOccurrenceFields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: Date(timeIntervalSince1970: 0),
      timeMinutes: 13 * 60,
      durationMinutes: 30
    )
    let advancedNextOccurrenceFields = RetainedTaskEditFields(
      title: "Task",
      noteText: "",
      day: Date(timeIntervalSince1970: 8 * 24 * 60 * 60),
      timeMinutes: nil,
      durationMinutes: nil
    )

    XCTAssertFalse(
      RecurringCompletionUndoScheduleRestorePolicy.shouldWriteCompletion(
        previousIsCompleted: false,
        nextIsCompleted: false,
        isRecurring: true,
        previousFields: originalOccurrenceFields,
        fields: advancedNextOccurrenceFields
      )
    )
    XCTAssertTrue(
      RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
        previousIsCompleted: false,
        nextIsCompleted: false,
        isRecurring: true,
        previousFields: originalOccurrenceFields,
        fields: advancedNextOccurrenceFields
      )
    )
  }

  func testCompletionMutationWithWorkBumpsWorkspaceRevision() {
    XCTAssertTrue(
      RetainedTaskCompletionWorkspaceInvalidationPolicy.shouldBumpWorkspaceRevision(
        after: RetainedTaskCompletionMutationPlan(writesCompletion: true, restoresSchedule: false)
      )
    )
    XCTAssertTrue(
      RetainedTaskCompletionWorkspaceInvalidationPolicy.shouldBumpWorkspaceRevision(
        after: RetainedTaskCompletionMutationPlan(writesCompletion: false, restoresSchedule: true)
      )
    )
  }

  func testNoOpCompletionMutationDoesNotBumpWorkspaceRevision() {
    XCTAssertFalse(
      RetainedTaskCompletionWorkspaceInvalidationPolicy.shouldBumpWorkspaceRevision(
        after: RetainedTaskCompletionMutationPlan(writesCompletion: false, restoresSchedule: false)
      )
    )
  }
}
