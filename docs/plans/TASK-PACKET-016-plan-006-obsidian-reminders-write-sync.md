# TASK-PACKET-016: Obsidian -> Reminders Create/Update Sync

## Context
- PLAN-006 Phase 5b/6a has Obsidian vault setup, Reminders-first bootstrap, retained read projection, and raw/projects watcher infrastructure.
- TASK-PACKET-015 detects `raw/projects/*.md` changes and refreshes retained projection without using Logseq fallback or writing Reminders.
- This slice connects the changed Obsidian project note path to Reminders create/update sync.

## Scope
- Read only direct `<vault>/raw/projects/*.md` notes through `ObsidianProjectMarkdownStore`.
- Create a Reminder list for a project-tagged note that has no `reminder_list_external_id`.
- Create a Reminder item for a task inside a synced project note that has no `reminder_external_id`.
- Write newly created canonical identities back to the same Obsidian note through `ObsidianProjectMarkdownStore` with a stale baseline.
- Push existing task title, TODO/DONE, date/time, and subtree note changes to Reminders when baseline proves the local field changed and the remote field did not.
- Do not push `repeat` metadata to Reminders. Recurrence is Reminders-owned and inbound-only.
- Keep `duration` Obsidian/BUF-only and never write it to Reminders.
- Update `ReminderSyncBaselineStore` after successful create/update pushes.

## Out Of Scope
- Reminder -> Obsidian import/merge changes.
- Reminder delete sync and Obsidian task delete sync.
- Project rename or Reminder list rename sync.
- Obsidian note auto-move.
- Helper auto-enable or helper sync logic.
- Calendar writes.
- Logseq fallback or new Logseq behavior.
- SwiftData/schema/runtime data deletion.

## Safety Rules
- Duplicate `reminder_list_external_id` or `reminder_external_id` fails closed before any write.
- Damaged task metadata fails closed before any write.
- Existing task update requires an existing sync baseline; without it, skip push rather than overwrite Reminders.
- Remote snapshot older than baseline does not accept a push.
- If both local and remote changed the same field from baseline, do not push that field.
- Markdown write-back requires an expected baseline for existing files.
- Pending create writes that cannot be committed must leave the already-created Reminder detectable by the next safe sync.
- All writes must use canonical `reminder_list_external_id` / `reminder_external_id`; never write `brain_unfog_project_id` or `brain_unfog_task_id`.

## Acceptance Criteria
- New project-tagged Obsidian note creates one Reminder list and writes `reminder_list_external_id`.
- New task in a synced Obsidian note creates one Reminder item and writes `reminder_external_id`.
- Re-running the same sync does not duplicate lists or tasks.
- Existing task title changes push to Reminders when baseline is safe.
- Existing TODO/DONE changes push completion to Reminders when baseline is safe.
- Existing date/time changes push Reminder due date/time when baseline is safe.
- Existing repeat changes do not call any Reminder recurrence write.
- Existing duration changes do not call any Reminder write.
- Existing subtree changes push Reminder note when baseline is safe.
- Duplicate identities fail closed without creating or updating Reminders.
- Damaged metadata fails closed without creating or updating Reminders.
- Stale Markdown baseline blocks identity write-back.
- Calendar write path remains unused.
- Logseq path remains unused.

## Tests
- `ObsidianReminderProvisioningSyncTests`
  - `testNewProjectNoteCreatesReminderListAndWritesCanonicalID`
  - `testNewTaskCreatesReminderItemAndWritesCanonicalID`
  - `testExistingTaskTitleCompletionDateTimeAndNotePushToReminderWithoutRecurrenceWrite`
  - `testDurationEditDoesNotWriteReminder`
  - `testDuplicateIDsFailClosedBeforeReminderWrites`
  - `testDamagedMetadataFailsClosedBeforeReminderWrites`
  - `testStaleBaselineBlocksMarkdownIdentityWriteBack`
- Existing focused tests:
  - `swift test --filter ObsidianProjectDirectoryWatcherTests`
  - `swift test --filter ObsidianChangedProjectProjectionRefreshTests`
  - `swift test --filter RetainedSetupFlowTests`

## Gates
- Focused tests pass.
- `swift build` passes.
- `swift test` passes.
- Existing app is terminated and `.build/BrainUnfogHarness.app` is relaunched after code changes.
