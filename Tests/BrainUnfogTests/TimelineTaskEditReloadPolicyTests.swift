import XCTest
@testable import BrainUnfog

final class TimelineTaskEditReloadPolicyTests: XCTestCase {
  func testDurationPolicySavesDefaultDurationForTimedTasks() {
    XCTAssertEqual(
      TimelineTaskEditDurationPolicy.savedDuration(
        hasDate: true,
        hasTime: true,
        durationMinutes: nil
      ),
      WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
    )
  }

  func testDurationPolicyDoesNotSaveDurationForAllDayTasks() {
    XCTAssertNil(
      TimelineTaskEditDurationPolicy.savedDuration(
        hasDate: true,
        hasTime: false,
        durationMinutes: 90
      )
    )
  }

  func testDurationPolicyFormatsDurationForDisplay() {
    XCTAssertEqual(TimelineTaskEditDurationPolicy.displayText(90), "1시간 30분")
    XCTAssertEqual(TimelineTaskEditDurationPolicy.displayText(60), "1시간")
    XCTAssertEqual(TimelineTaskEditDurationPolicy.displayText(15), "15분")
  }

  func testPreservesEditorWhenReloadOnlyDropsTrailingBlankLine() {
    let current = fields(noteText: "First line\n")
    let loaded = fields(noteText: "First line")

    XCTAssertTrue(
      TimelineTaskEditReloadPolicy.shouldPreserveCurrentEditorFields(
        current: current,
        loaded: loaded
      )
    )
  }

  func testPreservesEditorWhenReloadOnlyDropsTrailingWhitespaceBlankLine() {
    let current = fields(noteText: "First line\n  ")
    let loaded = fields(noteText: "First line")

    XCTAssertTrue(
      TimelineTaskEditReloadPolicy.shouldPreserveCurrentEditorFields(
        current: current,
        loaded: loaded
      )
    )
  }

  func testDoesNotPreserveEditorWhenInteriorBlankLineChanges() {
    let current = fields(noteText: "First line\n\nSecond line")
    let loaded = fields(noteText: "First line\nSecond line")

    XCTAssertFalse(
      TimelineTaskEditReloadPolicy.shouldPreserveCurrentEditorFields(
        current: current,
        loaded: loaded
      )
    )
  }

  func testDoesNotPreserveEditorWhenNonNoteFieldChanges() {
    let current = fields(title: "Task", noteText: "First line\n")
    let loaded = fields(title: "Renamed", noteText: "First line")

    XCTAssertFalse(
      TimelineTaskEditReloadPolicy.shouldPreserveCurrentEditorFields(
        current: current,
        loaded: loaded
      )
    )
  }

  func testSkipsCleanReloadImmediatelyAfterLocalSave() {
    let now = Date(timeIntervalSince1970: 1_000)
    let current = fields(noteText: "Saved")

    XCTAssertTrue(
      TimelineTaskEditReloadPolicy.shouldSkipCleanReloadAfterLocalSave(
        current: current,
        lastCommitted: current,
        skipUntil: now.addingTimeInterval(2),
        now: now
      )
    )
  }

  func testDoesNotSkipReloadAfterLocalSaveWindowExpires() {
    let now = Date(timeIntervalSince1970: 1_000)
    let current = fields(noteText: "Saved")

    XCTAssertFalse(
      TimelineTaskEditReloadPolicy.shouldSkipCleanReloadAfterLocalSave(
        current: current,
        lastCommitted: current,
        skipUntil: now.addingTimeInterval(-1),
        now: now
      )
    )
  }

  func testDoesNotSkipReloadWhenEditorHasDirtyChanges() {
    let now = Date(timeIntervalSince1970: 1_000)

    XCTAssertFalse(
      TimelineTaskEditReloadPolicy.shouldSkipCleanReloadAfterLocalSave(
        current: fields(noteText: "Typing"),
        lastCommitted: fields(noteText: "Saved"),
        skipUntil: now.addingTimeInterval(2),
        now: now
      )
    )
  }

  private func fields(
    title: String = "Task",
    noteText: String
  ) -> RetainedTaskEditFields {
    RetainedTaskEditFields(
      title: title,
      noteText: noteText,
      day: nil,
      timeMinutes: nil,
      durationMinutes: nil
    )
  }
}
