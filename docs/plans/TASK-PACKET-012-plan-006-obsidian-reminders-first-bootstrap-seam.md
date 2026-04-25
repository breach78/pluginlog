# TASK-PACKET-012: PLAN-006 Phase 5a Obsidian Reminders-First Bootstrap Seam

## Objective

Create the first pure Reminders-to-Obsidian bootstrap seam so an empty
Obsidian vault can be populated from a `ReminderImportSnapshotBatch`.

## Scope

- Add a service that maps Reminders lists/items into Obsidian project notes.
- Create project notes under `<vault>/raw/projects/`.
- Store list identity as frontmatter `reminder_list_external_id`.
- Store tasks as Markdown tasks with adjacent canonical `brain-unfog` metadata.
- Store task identity as `reminder_external_id`.
- Store `date` as `yyyy-mm-dd`, optional `time` as `HH:mm`, and repeat as the
  existing canonical repeat token.
- Render Reminder notes as task subtree bullets under the parent task.
- Re-running against already-owned notes must not create duplicate notes/tasks.
- Existing damaged/ambiguous Obsidian notes fail closed as repair-needed.
- Reminders lists with duplicate titles must not collide on one Markdown file.

## Non-Goals

- Do not request Reminders permission in this slice.
- Do not fetch EventKit directly; consume fixture/import snapshots only.
- Do not import from Logseq.
- Do not move Obsidian notes into `raw/projects/`.
- Do not modify notes outside `raw/projects/`.
- Do not add runtime AppState/setup UI cutover.
- Do not change Calendar policy.
- Do not add helper plugin runtime dependency.

## Likely Files

- `import/BUF/Services/ObsidianReminderBootstrapSync.swift`
- `Tests/BrainUnfogHarnessTests/ObsidianReminderBootstrapSyncTests.swift`
- `docs/plans/TASK-PACKET-012-plan-006-obsidian-reminders-first-bootstrap-seam.md`

## Implementation Lane

- Use existing `ReminderImportSnapshotBatch` models.
- Use existing `ObsidianProjectMarkdownStore` and parser/renderer.
- For existing owned notes, update through the store with `WriteBaseline`.
- Existing note identity conflicts must fail closed through store validation.
- Existing note diagnostics or duplicate identities must fail closed before
  writing.
- Existing local-only content or local-only tasks must fail closed before
  bootstrap overwrite.
- Snapshot list/task identities must be present and unique.
- Ordinary notes outside `raw/projects/` are not scanned or moved.
- Do not write `brain_unfog_project_id` or `brain_unfog_task_id`.
- Do not reference Logseq stores/codecs.

## Review Lane

Review adversarially for:

- duplicate project/task creation
- overwriting damaged or ambiguous notes
- Logseq import leakage
- writing legacy `brain_unfog_*` IDs
- whole-vault scans or outside-path writes
- Calendar/EventKit write policy regression
- runtime cutover before acceptance

## Test Lane

Add focused tests for:

- empty vault bootstrap creates one note per Reminder list
- Reminder items render as tasks with canonical metadata
- date-only due date writes `date` only
- timed due date writes `date` plus `time`
- Reminder note text renders as subtree bullets
- rerun is idempotent and does not duplicate notes/tasks
- existing owned note updates through baseline without duplicating tasks
- damaged existing note is not overwritten
- duplicate Reminder list titles produce distinct files
- duplicate or missing snapshot identities fail closed
- existing unowned filename collisions and local-only content stay unchanged
- legacy `brain_unfog_*` IDs are never written
- Calendar write path remains absent

## Build/Test/Runtime Gate

- `swift test --filter ObsidianReminderBootstrapSyncTests`
- `rg -n "brain_unfog_project_id|brain_unfog_task_id" import/BUF/Services/ObsidianReminderBootstrapSync.swift Tests/BrainUnfogHarnessTests/ObsidianReminderBootstrapSyncTests.swift`
  must return no matches.
- `rg -n "EventKit|EKEvent|Calendar|calendar_event_external_id" import/BUF/Services/ObsidianReminderBootstrapSync.swift`
  must return no matches.
- `rg -n "ReminderGateway|ReminderGatewayImportSnapshotProvider" import/BUF/Services/ObsidianReminderBootstrapSync.swift`
  must return no matches.
- `rg -n "Logseq|logseq" import/BUF/Services/ObsidianReminderBootstrapSync.swift Tests/BrainUnfogHarnessTests/ObsidianReminderBootstrapSyncTests.swift`
  must return no matches.
- `rg -n "ObsidianReminderBootstrapSync" import/BUF/App import/BUF/Features`
  must return no runtime cutover matches.
- `swift build`
- `swift test`
- Because this slice changes code, quit existing Brain Unfog app and relaunch
  `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app` after
  build/test pass.

## Ask First Items

Stop before:

- moving any existing Obsidian note into `raw/projects/`
- deleting or renaming Obsidian files
- making this bootstrap run automatically from app launch/setup
- changing Reminder note marker encoding
- changing Calendar write policy
- adding a third-party dependency

## Acceptance

- An empty test vault becomes usable from Reminder snapshots.
- Re-running bootstrap does not duplicate notes or tasks.
- No Logseq files, Calendar writes, helper runtime bridge, or user data moves
  are introduced.
