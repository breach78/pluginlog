import XCTest
@testable import BrainUnfog

final class TimelineTaskEditReloadPolicyTests: XCTestCase {
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
