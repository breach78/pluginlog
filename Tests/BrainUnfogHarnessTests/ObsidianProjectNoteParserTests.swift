import XCTest
@testable import BrainUnfogHarness

final class ObsidianProjectNoteParserTests: XCTestCase {
  func testParsesProjectFrontmatterTaskMetadataAndSubtree() throws {
    let note = ObsidianProjectNoteParser.parse(
      """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: LIST-1
      ---

      Intro prose.

      - [ ] Task title ^buf-TASK-1
        %% brain-unfog: {"reminder_external_id":"TASK-1","date":"2026-04-25","time":"14:00","duration":15,"repeat":"monthly"} %%
        - child note
        - [ ] child task t:TASK-CHILD
          %% brain-unfog: {"reminder_external_id":"TASK-CHILD"} %%
      """
    )

    XCTAssertEqual(note.tags, ["프로젝트"])
    XCTAssertEqual(note.reminderListExternalIdentifier, "LIST-1")
    XCTAssertEqual(note.frontmatter?.isArchived, false)
    XCTAssertTrue(note.isSyncScopeCandidate)
    XCTAssertTrue(
      ObsidianProjectNoteScope.isSyncScopeCandidate(
        note,
        vaultRelativePath: "raw/projects/Project.md"
      )
    )
    XCTAssertFalse(
      ObsidianProjectNoteScope.isSyncScopeCandidate(
        note,
        vaultRelativePath: "notes/Project.md"
      )
    )

    XCTAssertEqual(note.tasks.count, 2)
    let parent = try XCTUnwrap(note.tasks.first)
    XCTAssertEqual(parent.title, "Task title")
    XCTAssertFalse(parent.isCompleted)
    XCTAssertEqual(parent.blockIdentifier, "^buf-TASK-1")
    XCTAssertEqual(parent.metadata?.reminderExternalIdentifier, "TASK-1")
    XCTAssertEqual(parent.metadata?.date, "2026-04-25")
    XCTAssertEqual(parent.metadata?.time, "14:00")
    XCTAssertEqual(parent.metadata?.durationMinutes, 15)
    XCTAssertEqual(parent.metadata?.repeatRule, "monthly")
    XCTAssertTrue(parent.subtreeMarkdown.contains("- child note"))
    XCTAssertTrue(parent.subtreeMarkdown.contains("- [ ] child task t:TASK-CHILD"))

    let child = try XCTUnwrap(note.tasks.last)
    XCTAssertEqual(child.title, "child task t:TASK-CHILD")
    XCTAssertEqual(child.metadata?.reminderExternalIdentifier, "TASK-CHILD")
  }

  func testParsesArchivedProjectFrontmatterCheckbox() {
    let note = ObsidianProjectNoteParser.parse(
      """
      ---
      tags: [프로젝트]
      reminder_list_external_id: LIST-1
      아카이브: true
      ---

      - [ ] Archived task
      """
    )

    XCTAssertEqual(note.frontmatter?.isArchived, true)
  }

  func testParsesProjectTimelineFrontmatterProperties() throws {
    let note = ObsidianProjectNoteParser.parse(
      """
      ---
      tags: [프로젝트]
      reminder_list_external_id: LIST-1
      brain_unfog_color_hex: "#FF3B30"
      분류:
        - Area
      시작일: 2026-04-01
      마감일: 2026-04-30
      ---

      - [ ] Task
      """
    )

    let frontmatter = try XCTUnwrap(note.frontmatter)
    XCTAssertEqual(frontmatter.colorHex, "#FF3B30")
    XCTAssertEqual(frontmatter.projectStage, .area)
    XCTAssertEqual(frontmatter.startDate, "2026-04-01")
    XCTAssertEqual(frontmatter.deadline, "2026-04-30")
  }

  func testClassifiesTagOnlyIdOnlyAndOrdinaryNotesAtProjectBoundary() {
    let tagOnly = ObsidianProjectNoteParser.parse(
      """
      ---
      tags: [프로젝트]
      ---

      - [ ] Unbound
      """
    )
    let idOnly = ObsidianProjectNoteParser.parse(
      """
      ---
      reminder_list_external_id: LIST-2
      ---

      - [ ] Bound list
      """
    )
    let ordinary = ObsidianProjectNoteParser.parse(
      """
      ---
      tags: [journal]
      ---

      - [ ] Ordinary todo
      """
    )

    XCTAssertTrue(
      ObsidianProjectNoteScope.isSyncScopeCandidate(
        tagOnly,
        vaultRelativePath: "raw/projects/Tag.md"
      )
    )
    XCTAssertTrue(
      ObsidianProjectNoteScope.isSyncScopeCandidate(
        idOnly,
        vaultRelativePath: "raw/projects/List.md"
      )
    )
    XCTAssertFalse(
      ObsidianProjectNoteScope.isSyncScopeCandidate(
        ordinary,
        vaultRelativePath: "raw/projects/Ordinary.md"
      )
    )
    XCTAssertFalse(
      ObsidianProjectNoteScope.isSyncScopeCandidate(
        tagOnly,
        vaultRelativePath: "raw/Tag.md"
      )
    )
  }

  func testParsesUnboundTaskWithoutInventingIdentity() throws {
    let note = ObsidianProjectNoteParser.parse("- [ ] New task ^buf-X")

    XCTAssertEqual(note.tasks.count, 1)
    let task = try XCTUnwrap(note.tasks.first)
    XCTAssertEqual(task.title, "New task")
    XCTAssertEqual(task.blockIdentifier, "^buf-X")
    XCTAssertNil(task.reminderExternalIdentifier)
    XCTAssertNil(task.metadata)
  }

  func testDamagedMetadataIsReportedAndRawLineIsPreserved() throws {
    let note = ObsidianProjectNoteParser.parse(
      """
      - [ ] Broken
        %% brain-unfog: {"reminder_external_id": %%
      """
    )

    XCTAssertEqual(note.tasks.count, 1)
    let task = try XCTUnwrap(note.tasks.first)
    XCTAssertTrue(task.metadataIsDamaged)
    XCTAssertEqual(task.rawMetadataLine, "  %% brain-unfog: {\"reminder_external_id\": %%")
    XCTAssertEqual(
      note.diagnostics,
      [
        .damagedTaskMetadata(
          line: 1,
          rawLine: "  %% brain-unfog: {\"reminder_external_id\": %%"
        )
      ]
    )
  }

  func testUnterminatedBrainUnfogMetadataIsReportedAsDamaged() throws {
    let note = ObsidianProjectNoteParser.parse(
      """
      - [ ] Broken
        %% brain-unfog: {"reminder_external_id":"TASK-1"
      """
    )

    let task = try XCTUnwrap(note.tasks.first)
    XCTAssertTrue(task.metadataIsDamaged)
    XCTAssertEqual(
      note.diagnostics,
      [
        .damagedTaskMetadata(
          line: 1,
          rawLine: #"  %% brain-unfog: {"reminder_external_id":"TASK-1""#
        )
      ]
    )
  }

  func testTaskSubtreeStopsBeforeOutdentedProse() throws {
    let note = ObsidianProjectNoteParser.parse(
      """
      - [ ] Parent
        %% brain-unfog: {"reminder_external_id":"TASK-1"} %%
        - child note

      Comment after.
      - [ ] Next
      """
    )

    let parent = try XCTUnwrap(note.tasks.first)
    XCTAssertTrue(parent.subtreeMarkdown.contains("- child note"))
    XCTAssertFalse(parent.subtreeMarkdown.contains("Comment after."))
    XCTAssertFalse(parent.subtreeMarkdown.contains("- [ ] Next"))
  }

  func testNestedTaskSubtreeStopsBeforeSameLevelParentNoteLine() throws {
    let note = ObsidianProjectNoteParser.parse(
      """
      - [ ] Parent
        %% brain-unfog: {"reminder_external_id":"PARENT"} %%
        - before child
        - [ ] Child
          %% brain-unfog: {"reminder_external_id":"CHILD"} %%
          - child detail
        - after child
      """
    )

    let child = try XCTUnwrap(note.tasks.last)
    XCTAssertTrue(child.subtreeMarkdown.contains("- child detail"))
    XCTAssertFalse(child.subtreeMarkdown.contains("- after child"))
  }

  func testValidationReportsDuplicateListAndTaskReminderIdentifiers() {
    let first = ObsidianProjectNoteParser.parse(
      """
      ---
      reminder_list_external_id: LIST-DUP
      ---

      - [ ] A
        %% brain-unfog: {"reminder_external_id":"TASK-DUP"} %%
      """
    )
    let second = ObsidianProjectNoteParser.parse(
      """
      ---
      reminder_list_external_id: LIST-DUP
      ---

      - [ ] B
        %% brain-unfog: {"reminder_external_id":"TASK-DUP"} %%
      """
    )

    let issues = ObsidianProjectNoteValidation.issues(in: [first, second])

    XCTAssertTrue(issues.contains(.duplicateReminderListExternalIdentifier("LIST-DUP")))
    XCTAssertTrue(issues.contains(.duplicateReminderExternalIdentifier("TASK-DUP")))
  }

  func testNormalizedContentHashIsStableForLineEndingOnlyDiffs() {
    let lf = ObsidianProjectNoteParser.parse("- [ ] Task\n  note")
    let crlf = ObsidianProjectNoteParser.parse("- [ ] Task\r\n  note")
    let changed = ObsidianProjectNoteParser.parse("- [ ] Task changed\n  note")

    XCTAssertEqual(lf.normalizedContentHash, crlf.normalizedContentHash)
    XCTAssertNotEqual(lf.normalizedContentHash, changed.normalizedContentHash)
  }
}
