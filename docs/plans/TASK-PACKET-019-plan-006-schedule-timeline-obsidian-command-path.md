# TASK-PACKET-019: Schedule/Timeline Obsidian Command Path

## Context
- TASK-PACKET-014 moved Timeline/Schedule read projection to Obsidian when a vault is configured.
- TASK-PACKET-016/017/018 added Obsidian <-> Reminders create/update/import/delete sync.
- Schedule/Timeline direct user actions still block in Obsidian mode with "not connected" errors.

## Objective
Route retained task completion and schedule edits from Schedule/Timeline to Obsidian `raw/projects/*.md` when an Obsidian vault is configured.

## Scope
- Add an Obsidian retained task command service for:
  - task completion toggle
  - task date/time/duration edit
- Preserve existing Logseq command path when no Obsidian vault is configured.
- Update Schedule and Timeline action dispatch to choose Obsidian command path in Obsidian mode.
- Write only the matched task line/metadata in the matched project note, guarded by Obsidian store baseline.
- Resolve the project note and task from the current `raw/projects` snapshot by `reminder_list_external_id` / `reminder_external_id` immediately before each write.
- Update Reminders for completion and due date/time changes.
- Do not write Reminders when only `duration` changes.
- Update sync baseline after successful Reminder writes.
- Before a Reminder write, require an existing sync baseline and a current Reminder snapshot that is not newer than that baseline.
- Roll back the Obsidian markdown edit if a required Reminder write fails, only when the file still equals the just-written post-command content.

## Out Of Scope
- Creating new tasks from Schedule quick-add.
- Moving tasks between projects.
- Project reorder, archive, delete, or color/stage commands.
- Obsidian helper write-through; direct store writes are used in this slice.
- Logseq source deletion or Logseq command rewrite.
- Calendar event create/update/delete.

## Safety Rules
- Obsidian vault mode never falls back to Logseq to hide command failures.
- Duplicate list/task ids or damaged metadata fail closed before writes.
- Missing Reminder identity fails closed.
- Missing or stale Obsidian file baseline fails closed.
- Missing or stale Reminder sync baseline fails closed before Reminder writes.
- Reminder failure after markdown write must attempt rollback before surfacing the error.
- Rollback never overwrites a file that changed after the command write.
- `duration` is Obsidian/BUF-only and never sent to Reminders.
- Calendar bridge decision for Reminder-backed tasks remains `.noAction`.

## Implementation Lane
- Keep a small new service seam instead of expanding the existing Logseq-specific command service.
- Reuse `ObsidianProjectMarkdownStore`, `ObsidianRetainedProjectionAdapter`, `ObsidianReminderImportFormatting`, and `ReminderSyncBaselineStore`.
- Touch Schedule/Timeline action files only where they dispatch commands.

## Review Lane
- Check data-loss risk, stale write guard, rollback behavior, Logseq fallback leakage, Calendar write leakage, and duration-to-Reminder leakage.

## Test Lane
- Add focused tests for Obsidian completion, schedule, duration-only, missing identity, stale baseline/rollback, and Calendar no-write policy.

## Acceptance Criteria
- Schedule completion in Obsidian mode writes `- [x]` / `- [ ]` in the project note and updates Reminder completion.
- Timeline completion in Obsidian mode uses the same command path.
- Schedule date/time edit writes Obsidian `date`/`time` metadata and updates Reminder due date/time.
- Schedule duration-only edit writes Obsidian `duration` and does not call Reminder schedule write.
- Duration-only edit leaves Reminder sync baseline unchanged.
- Missing identity, duplicate ids, damaged metadata, and stale baseline fail closed.
- Remote Reminder edits after the last baseline block completion/date commands.
- Reminder write failure rolls back the Obsidian markdown edit.
- Calendar write remains disabled/read-only.
- Logseq command path is still used only when no Obsidian vault is configured.

## Gates
- `swift test --filter ObsidianRetainedTaskCommandServiceTests`
- `swift test --filter RetainedTaskCommandServiceTests`
- `swift test --filter TimelineBoardReadPathTests`
- `swift test --filter Schedule`
- Negative implementation grep for Calendar write APIs in the new command service and Schedule/Timeline dispatch.
- `swift build`
- `swift test`
- Terminate existing app and relaunch `.build/BrainUnfogHarness.app`.
