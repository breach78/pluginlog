# TASK-PACKET-018: Safe Deletion Sync

## Context
- TASK-PACKET-016 pushes Obsidian create/update changes to Reminders.
- TASK-PACKET-017 imports Reminders create/update changes to Obsidian.
- Deletion is still absent. PLAN-006 requires deletion only when identity and baseline rules are unambiguous.

## Objective
Add safe task deletion propagation in both directions without project/list hard delete and without Calendar or Logseq writes.

## Scope
- Obsidian -> Reminders task deletion:
  - If a task disappears from a still-present, readable, synced project note, delete the matching Reminder item only when the Reminder item still matches the full stored baseline.
  - Whole note absence, note move, unreadable note, missing `reminder_list_external_id`, or lost sync scope never means "delete all tasks"; it is repair-needed/fail-closed.
  - Record a deleted-task tombstone and remove the active baseline only after successful Reminder deletion.
- Reminders -> Obsidian task deletion:
  - If a Reminder item is absent from a fresh complete fetched list, remove the matching Obsidian task block only when the local task still matches the full stored baseline and has no conflict fields.
  - Remove the active baseline only after successful Markdown write.
- Preserve all unrelated Obsidian prose and task blocks.
- Continue to validate all existing Obsidian notes before any delete/write.

## Out Of Scope
- Reminder list deletion.
- Obsidian project note deletion.
- Deleting `.md` files or sidecar data.
- SwiftData/schema/runtime data deletion.
- Calendar writes.
- Logseq fallback or new Logseq behavior.

## Safety Rules
- Missing baseline means no hard delete.
- Any conflicted baseline field means no hard delete.
- Baseline equality means all canonical synced fields match: title, completion, date/time, repeat, and normalized note/subtree text.
- Remote task newer than baseline or different from baseline blocks Obsidian -> Reminders delete.
- Local task different from baseline blocks Reminders -> Obsidian delete.
- Duplicate ids or damaged metadata fail closed before any delete/write.
- Deletes never run if remote snapshots are unavailable, stale, partial, permission-denied, or missing list identity.
- Tombstones suppress immediate re-import of app-deleted Reminder tasks only while scoped to the same reminder id and not superseded by a newer remote modified timestamp.
- Batch preflight must complete before any Reminder delete or Markdown write in that batch.

## Implementation Lane
- Extend existing Obsidian sync services instead of adding a broad new engine.
- Reuse `ReminderDeletedTaskTombstoneStore` and `ReminderSyncBaselineStore`.
- Keep each new/modified file under 800 lines.

## Review Lane
- Check data-loss risk, missing baseline cases, stale baseline cases, duplicate/damaged preflight, and Logseq/Calendar leakage.

## Test Lane
- Add focused tests for both deletion directions and all fail-closed cases.

## Acceptance Criteria
- Obsidian task deletion removes the Reminder only when baseline and remote state are unchanged.
- Obsidian task deletion does not remove the Reminder when remote changed after baseline.
- Reminders task deletion removes the Obsidian task block only when local state still equals baseline.
- Reminders task deletion preserves the Obsidian task when local changed after baseline.
- Missing/moved/unreadable project notes or missing list identity never delete project tasks.
- One damaged note in the batch blocks all deletes and writes.
- Duplicate/damaged metadata blocks deletes before writes.
- Project/list deletes are not propagated.
- Calendar write path remains unused.
- Logseq path remains unused.

## Gates
- `swift test --filter ObsidianReminderProvisioningSyncTests`
- `swift test --filter ObsidianReminderImportSyncTests`
- Negative implementation grep for `Logseq`, `EventKit`, `EKEvent`, `calendar_event`, `brain_unfog_project_id`, and `brain_unfog_task_id` in new deletion code/tests.
- `swift build`
- `swift test`
- Terminate existing app and relaunch `.build/BrainUnfogHarness.app`.
