import XCTest
@testable import BrainUnfogHarness

final class ObsidianProjectNoteRendererTests: XCTestCase {
  func testRendersCanonicalMetadataWithoutLegacyBrainUnfogIdentifiers() {
    let note = ObsidianProjectNoteParser.parse(
      """
      ---
      tags:
        - 프로젝트
      brain_unfog_project_id: legacy-project
      reminder_list_external_id: LIST-1
      owner: kept
      ---

      Comment before.

      - [ ] Task title ^buf-TASK-1
        %% brain-unfog: {"repeat":"monthly","duration":15,"time":"14:00","date":"2026-04-25","reminder_external_id":"TASK-1"} %%
        - child note
        - [ ] child task t:TASK-CHILD
          %% brain-unfog: {"reminder_external_id":"TASK-CHILD"} %%

      Comment after.
      """
    )

    let rendered = ObsidianProjectNoteRenderer.render(note)

    XCTAssertTrue(rendered.contains("tags:\n  - 프로젝트"))
    XCTAssertTrue(rendered.contains("reminder_list_external_id: LIST-1"))
    XCTAssertTrue(rendered.contains("완료 가리기: true"))
    XCTAssertTrue(rendered.contains("owner: kept"))
    XCTAssertFalse(rendered.contains("brain_unfog_project_id"))
    XCTAssertFalse(rendered.contains("brain_unfog_task_id"))
    XCTAssertTrue(
      rendered.contains(
        #"%% brain-unfog: {"reminder_external_id":"TASK-1","date":"2026-04-25","time":"14:00","duration":15,"repeat":"monthly"} %%"#
      )
    )
    XCTAssertTrue(rendered.contains("- [ ] child task t:TASK-CHILD"))

    let renderedAgain = ObsidianProjectNoteRenderer.render(
      ObsidianProjectNoteParser.parse(rendered)
    )
    XCTAssertEqual(renderedAgain, rendered)
  }

  func testRenderingDamagedMetadataPreservesRawLine() {
    let markdown = """
    - [ ] Broken
      %% brain-unfog: {"reminder_external_id": %%
      - child note
    """
    let note = ObsidianProjectNoteParser.parse(markdown)

    let rendered = ObsidianProjectNoteRenderer.render(note)

    XCTAssertEqual(rendered, markdown)
  }

  func testRenderingUnboundTaskDoesNotInventReminderIdentity() {
    let note = ObsidianProjectNoteParser.parse("- [ ] New task ^buf-X")

    let rendered = ObsidianProjectNoteRenderer.render(note)

    XCTAssertEqual(rendered, "- [ ] New task ^buf-X")
    XCTAssertFalse(rendered.contains("reminder_external_id"))
  }

  func testTimedTaskWithoutDurationRemainsParseableAndRendererDoesNotInferDuration() throws {
    let note = ObsidianProjectNoteParser.parse(
      """
      - [ ] Timed without duration
        %% brain-unfog: {"reminder_external_id":"TASK-1","date":"2026-04-25","time":"14:00"} %%
      """
    )

    XCTAssertEqual(note.tasks.count, 1)
    let task = try XCTUnwrap(note.tasks.first)
    XCTAssertEqual(task.metadata?.date, "2026-04-25")
    XCTAssertEqual(task.metadata?.time, "14:00")
    XCTAssertNil(task.metadata?.durationMinutes)

    let rendered = ObsidianProjectNoteRenderer.render(note)
    XCTAssertFalse(rendered.contains(#""duration":"#))
    XCTAssertFalse(rendered.contains(#""calendar_event_external_id""#))
  }

  func testRendererPreservesUnsupportedFrontmatterLists() {
    let note = ObsidianProjectNoteParser.parse(
      """
      ---
      tags:
        - 프로젝트
      aliases:
        - Alpha
        - Beta
      reminder_list_external_id: LIST-1
      ---

      - [ ] Task
      """
    )

    let rendered = ObsidianProjectNoteRenderer.render(note)

    XCTAssertTrue(rendered.contains("aliases:\n  - Alpha\n  - Beta"))
    XCTAssertTrue(rendered.contains("tags:\n  - 프로젝트"))
    XCTAssertTrue(rendered.contains("reminder_list_external_id: LIST-1"))
    XCTAssertTrue(rendered.contains("완료 가리기: true"))
  }

  func testRendererPreservesCompletedVisibilityCheckboxForReminderSyncedProject() {
    let note = ObsidianProjectNoteParser.parse(
      """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      완료 가리기: true
      ---

      - [x] Done
      """
    )

    let rendered = ObsidianProjectNoteRenderer.render(note)

    XCTAssertTrue(rendered.contains("완료 가리기: true"))
    XCTAssertEqual(rendered.components(separatedBy: "완료 가리기:").count - 1, 1)
  }

  func testRendererDoesNotAddCompletedVisibilityCheckboxWithoutReminderBinding() {
    let note = ObsidianProjectNoteParser.parse(
      """
      ---
      tags:
        - 프로젝트
      ---

      - [ ] Local project
      """
    )

    let rendered = ObsidianProjectNoteRenderer.render(note)

    XCTAssertFalse(rendered.contains("완료 가리기:"))
  }
}
