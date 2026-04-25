# TASK-PACKET-017: Reminders -> Obsidian Reconciliation

## Context
- TASK-PACKET-014 cut Timeline/Schedule read projection over to Obsidian notes.
- TASK-PACKET-015 added `raw/projects/*.md` watching, changed-file refresh, and 10 second idle debounce.
- TASK-PACKET-016 added Obsidian -> Reminders create/update sync.
- The remaining Phase 7 gap is inbound Reminders edits creating/updating Obsidian project notes/tasks without falling back to Logseq.

## Objective
Safely merge Reminders list/item changes into `<vault>/raw/projects/*.md` while preserving Obsidian-only fields and avoiding destructive deletes.

## Scope
- Read only direct `<vault>/raw/projects/*.md` notes through `ObsidianProjectMarkdownStore`.
- Fetch Reminders snapshots through `ReminderImportSnapshotBatch`.
- Create a project note when a Reminder list has no matching `reminder_list_external_id`.
- Add a task when a Reminder item has no matching `reminder_external_id` in its project note.
- Update existing task title, TODO/DONE, date/time, repeat marker, and subtree
  from Reminder note when baseline rules allow.
- Store only `repeat:"reminder"` when Reminders reports any recurrence; never
  import recurrence details that could later be written back as simplified rules.
- Preserve Obsidian-only `duration`.
- Preserve existing untracked note body lines and existing task order byte-for-byte outside targeted safe field/subtree edits.
- Write back through `ObsidianProjectMarkdownStore` with expected baselines.
- Update `ReminderSyncBaselineStore` after successful inbound writes.

## Out Of Scope
- Hard delete propagation in either direction.
- Project note rename/move or Obsidian note auto-move.
- Helper auto-enable or helper sync logic.
- Calendar writes.
- Logseq fallback or new Logseq behavior.
- SwiftData/schema/runtime data deletion.

## Safety Rules
- Duplicate `reminder_list_external_id` or `reminder_external_id` fails closed before any write.
- Damaged metadata fails closed before any write.
- If a field changed both locally and remotely from baseline to different values, keep local Markdown, mark the baseline conflict, and do not overwrite that field.
- Missing baseline for an existing linked task seeds baseline without writing unless the current local task state exactly matches the Reminders state or the task was newly imported from the inbound batch.
- Reminder note `t:<id>` markers must resolve to an existing preserved descendant task block before subtree write. Unknown or ambiguous markers fail closed for that task.
- Full existing-note validation and remote batch identity validation must complete before any file write.
- New project note creation must fail closed when the target filename already exists without the same Reminder list identity; do not auto-adopt or overwrite unrelated notes.
- Markdown write-back requires an expected baseline for existing files.
- Deletions are not propagated in this slice; missing remote/local objects are preserved unless a new object is being imported.
- All writes use canonical `reminder_list_external_id` / `reminder_external_id`; never write `brain_unfog_project_id` or `brain_unfog_task_id`.

## Implementation Lane
- Add an `ObsidianReminderImportSync` service rather than expanding the already-large Obsidian push service.
- Keep helpers local/private unless reused by a later packet.
- Reuse `ReminderSyncTaskState` and `ReminderSyncBaselineStore`.
- Keep the new source file under 800 lines.

## Review Lane
- Adversarially check data-loss risk, duplicate creation, baseline conflict handling, Logseq leakage, and Calendar write leakage.
- Confirm no whole-vault scan or `raw/projects` escape is introduced.

## Test Lane
- Add focused tests for inbound create/update, subtree note merge, duration preservation, conflict fail-closed behavior, duplicate/damaged metadata, and stale baseline blocking.
- Run focused tests, `swift build`, `swift test`, and runtime relaunch after code changes.

## Acceptance Criteria
- New Reminders list creates one Obsidian project note under `raw/projects/`.
- New Reminder item creates one Obsidian markdown task with canonical metadata.
- Existing Reminder title/completion/date/time/repeat updates merge into Obsidian when baseline is safe.
- Existing Reminder note updates the Obsidian task subtree when baseline is safe.
- Existing Obsidian `duration` survives inbound updates and is not sourced from Reminders.
- Existing prose before/after task blocks survives inbound updates.
- Reminder note subtree update with unknown `t:<id>` marker fails closed without rewriting the task subtree.
- Duplicate IDs and damaged metadata fail closed without writing files.
- Stale Markdown baseline blocks write-back.
- Delete propagation is absent in this slice.
- Calendar write path remains unused.
- Logseq path remains unused.

## Gates
- `swift test --filter ObsidianReminderImportSyncTests`
- `swift test --filter ObsidianReminderProvisioningSyncTests`
- `swift test --filter ObsidianProjectMarkdownStoreTests`
- `rg -n "Logseq|logseq|EventKit|EKEvent|calendar_event" import/BUF/Services/ObsidianReminderImportSync.swift import/BUF/Services/ObsidianReminderImportFormatting.swift`
- `swift build`
- `swift test`
- Terminate existing app and relaunch `.build/BrainUnfogHarness.app`.
