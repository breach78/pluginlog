# PLAN-005: Logseq, Reminders, Calendar sync completion

## Status

Superseded for current execution by `PLAN-006-obsidian-migration.md`.

Proposed on 2026-04-24. This plan remains sync-policy background, but the
active storage migration plan is Obsidian-based.

Related decisions:

- `docs/decisions/ADR-002-reminder-backed-schedule-blocks-no-calendar-event-mirroring.md`
- `docs/decisions/ADR-003-use-reminder-identifiers-as-retained-sync-identity.md`
- `docs/decisions/ADR-004-project-tag-auto-provisions-reminders-sync.md`

## Context

The retained app cleanup has removed most legacy BUF surfaces. The remaining product is:

- Logseq graph as the user-facing project/outliner/detail store.
- Brain Unfog as the native Timeline/Schedule bridge.
- Apple Reminders as list/task sync target.
- Apple Calendar as read-only Schedule context.

`PLAN-004` should not continue as the primary execution plan. It was a deletion/replacement plan. The next work must be a connection-completion plan.

The current runtime error:

> Retained task cannot be shown in Schedule/Timeline without a stable task id

means a Logseq project page contains TODO blocks that are in sync scope but do not yet have `brain_unfog_task_id::`. The app currently treats that as a projection blocker. That is too harsh for the retained product. It needs an adoption/repair path.

After ADR-003, this runtime error is also a legacy identity smell. Timeline/Schedule should not require persisted `brain_unfog_task_id::`; it should derive a stable app task ID from `reminder_external_id::`.

Important correction after review:

The first practical sync step is not Logseq task adoption. The app should assume the selected Logseq graph has not participated in Brain Unfog sync yet, or that any previous partial sync state is unreliable. Therefore the first implementation priority is Reminders-first bootstrap:

1. Read Apple Reminders lists and reminders.
2. Create or safely claim matching Logseq pages.
3. Write stable Reminder external identifiers into those imported pages/tasks.
4. Let Timeline/Schedule render that imported retained projection.

Existing user-authored Logseq TODO blocks without `reminder_external_id::` must not block the board during the Reminders-first import pass. If they are on a project-tagged or Reminders-backed page, the Logseq-to-Reminders provisioning pass must create or bind Apple Reminder items for them and write `reminder_external_id::`.

## Current Implementation Baseline

Working or partially working:

- Setup chooses one Logseq graph folder.
- `.buf` is created as hidden app support under the graph.
- `LogseqProjectPageStore` can read/write project pages and parse page/task properties.
- Schedule/Timeline read from retained projection.
- App-created projects/tasks write Logseq and Reminders.
- Basic Reminders import seam now exists through `RetainedReminderImportSync`.
- Calendar overlay pieces exist, but any task-to-Calendar event write path is now out of scope.

Known gaps:

- Existing Logseq TODO blocks without `reminder_external_id::` currently can block Timeline/Schedule through legacy `brain_unfog_task_id::` requirements. During Reminders-first import they should not block the board, and during Logseq project provisioning they should be turned into Reminder-backed tasks when they belong to a synced project page.
- The current managed-section model is temporary and too narrow for Logseq-as-outliner.
- Existing user-authored Logseq task blocks on project pages need in-place provisioning instead of being forced into a generated section.
- Reminders import/export needs full reconciliation and conflict policy.
- Legacy Calendar event write code must be disabled or removed from the retained task path.
- UI should show repair/sync status instead of fatal modal blockers for common recoverable states.

## Target Data Contract

### Page/List

- Logseq page = Reminders list.
- Page enters sync scope when it has `reminder_list_external_id::`, `tags:: 프로젝트`, or `tags:: [[프로젝트]]`.
- If a project-tagged page has no `reminder_list_external_id::`, the app creates a Reminders list and writes `reminder_list_external_id::`.
- Page title and Reminders list title are the same user-facing field.
- Internal properties:
  - `reminder_list_external_id::`
- Legacy tolerated, not newly written:
  - `brain_unfog_project_id::`

### Task/Reminder

- Logseq TODO/DONE block on a synced project page = Reminders item.
- TODO/DONE blocks on ordinary pages remain Logseq-only.
- Bullet order and nesting remain Logseq-only.
- User-editable properties:
  - `date::`
  - `duration::`
  - `repeat::`
- Internal properties:
  - `reminder_external_id::`
- Legacy tolerated, not newly written:
  - `brain_unfog_task_id::`

### Calendar

- The Schedule view is the Calendar replacement layer for Reminder tasks that need duration blocks.
- Brain Unfog must never create, update, or delete Apple Calendar events from Reminder-backed tasks in this product direction.
- `date:: YYYY-MM-DD` syncs with an Apple Reminder date-only due date and appears as day-level work in Schedule.
- `date:: YYYY-MM-DD HH:MM` syncs with an Apple Reminder timed due date and appears as a timed Schedule task block.
- `duration::` is Logseq/app-owned task planning metadata because Apple Reminders has no native duration field.
- If a task has a timed `date::` but no valid `duration::`, Schedule uses a 15 minute default block length.
- Apple Calendar events are read-only overlays for context only.

Important distinction:

- Reminder-backed task block = the primary project-management object shown in Timeline/Schedule.
- Apple Calendar event = read-only context.
- There is no app-owned task Calendar event in the retained design.

## Execution Order

### Phase 1: Reminders-First Bootstrap

Goal: Use Apple Reminders as the initial source of truth and create the first reliable retained Logseq projection.

Tasks:

- Request/verify Reminders permission before bootstrap.
- Fetch all visible Reminders lists and reminders.
- For each list, use `reminder_list_external_id::` as the persisted page identity.
- Derive any app runtime project ID from `reminder_list_external_id::` without writing it to Markdown.
- Create a Logseq page when no matching owned page exists.
- If a same-title unowned Logseq page exists, preserve existing content and only claim it when it is safe:
  - no conflicting `reminder_list_external_id::`
  - no ambiguous same-title candidates
- Write imported reminders as Reminder-backed TODO/DONE blocks with:
  - `reminder_external_id::`
  - `date::` when the reminder has a due date
  - `repeat::` when supported
- Derive any app runtime task ID from `reminder_external_id::` without writing it to Markdown.
- During this phase, do not treat existing Logseq TODO blocks without `reminder_external_id::` as sync tasks.
- Timeline/Schedule should render imported Reminders-backed tasks only.

Acceptance:

- First sync from Reminders creates Logseq pages under `pages`.
- Re-running bootstrap does not duplicate pages or tasks.
- Existing unowned Logseq content is preserved.
- Existing unowned Logseq TODOs do not trigger fatal Timeline/Schedule blockers.
- Timeline/Schedule show imported Reminders tasks after bootstrap.

### Phase 2: Logseq Project Auto-Provisioning

Goal: After Reminders-first import works, make Logseq project tags and project-page TODOs automatically create the missing Reminders side.

Tasks:

- Add a Logseq project provisioning seam.
- When a page has `tags:: 프로젝트` or `tags:: [[프로젝트]]` and no `reminder_list_external_id::`, create an Apple Reminders list using the page title and write `reminder_list_external_id::`.
- When a TODO/DONE block on a Reminders-backed page has no `reminder_external_id::`, create an Apple Reminder item in the linked list and write `reminder_external_id::`.
- Preserve the task at its existing location; do not move it into a generated section.
- If a task has a unique matching Reminder identity, bind it by writing `reminder_external_id::`.
- If matching is ambiguous, mark the task as repair-needed and exclude it from Timeline/Schedule without showing a fatal modal.

Acceptance:

- Adding `tags:: 프로젝트` to a Logseq page creates a Reminders list and records `reminder_list_external_id::`.
- Adding TODO/DONE to a Reminders-backed page creates a Reminder item and records `reminder_external_id::`.
- Existing TODO/DONE blocks on a newly synced project page are provisioned in place.
- Timeline/Schedule render after provisioning.
- No user prose or bullet nesting is destroyed.
- Ambiguous identities fail closed but do not blank the board.

### Phase 3: Replace Managed-Section Dependency

Goal: Logseq itself is the outliner/detail surface, so app writes must update task blocks in place.

Tasks:

- Split `LogseqProjectPageStore` into page-level and task-block update seams if needed.
- Support in-place updates for:
  - title
  - TODO/DONE state
  - `date::`
  - `duration::`
  - `repeat::`
  - `reminder_external_id::`
- Keep managed section readable for migration, but stop depending on it for normal operation.

Acceptance:

- App schedule/completion edits update the original Logseq task block.
- Existing managed-section fixtures still read.
- New imports do not require generated managed sections.

### Phase 4: Reminders Reconciliation

Goal: Logseq and Reminders converge through Brain Unfog.

Tasks:

- Implement list reconciliation:
  - create Logseq page for Reminders list without page
  - create Reminders list for project-tagged Logseq page without list
  - rename in either side updates the other through stable identity
- Implement task reconciliation:
  - create Reminder for Logseq task without remote
  - create Logseq task for Reminder without page task
  - update title/completion/date/repeat both directions
  - keep `duration::` in Logseq/app schedule state because Apple Reminders does not provide a native duration field
- Add loop markers for outbound writes.
- Add repair scan after launch and after EventKit/file events.

Acceptance:

- First sync imports existing Reminders into Logseq `pages`.
- Existing Logseq project tasks appear in Reminders.
- Re-running sync does not duplicate pages, lists, tasks, or reminders.
- Rename loops are suppressed.

### Phase 5: Calendar Reconciliation

Goal: Schedule view overlays Apple Calendar context while keeping Reminder-backed task blocks inside Brain Unfog only.

Tasks:

- Request/verify Calendar permission only for reading overlay events.
- Keep `duration::` as the Schedule task block length for Reminder-backed tasks.
- Use a 15 minute default Schedule block when a timed Reminder-backed task has no valid `duration::`.
- Keep all Apple Calendar events read-only.
- Remove retained task-to-Calendar event write calls from Schedule actions.
- Ignore legacy `calendar_event_external_id::` for new retained sync and add cleanup/repair handling before deleting old metadata.

Acceptance:

- Reminder-backed tasks with `duration::` render as task blocks in Schedule.
- Timed Reminder-backed tasks without `duration::` render as 15 minute task blocks.
- Editing task time in Schedule updates Logseq `date::` and Apple Reminders due date/time.
- Editing task duration in Schedule updates Logseq `duration::` only.
- No Schedule task action creates, updates, or deletes an Apple Calendar event.
- Apple Calendar event drag/edit remains blocked or read-only from Brain Unfog.

### Phase 6: UX and Diagnostics

Goal: Sync state must be understandable and recoverable.

Tasks:

- Replace fatal projection modals for repairable cases with board-level status.
- Add visible sync status:
  - graph configured
  - Reminders permission
  - Calendar permission
  - last sync result
  - repair-needed count
- Add manual actions:
  - refresh/sync now
  - repair project pages or tasks that could not auto-provision
  - open Logseq page

Acceptance:

- Empty Timeline explains whether there are no tasks, no permission, or repair blockers.
- Common repair states do not block the entire app.
- User can trigger sync without restarting.

### Phase 7: Hardening and Cleanup

Goal: Remove temporary compatibility once the real sync path is stable.

Tasks:

- Remove or narrow generated managed-section assumptions.
- Delete obsolete compatibility types only after tests no longer use them.
- Add regression fixtures for damaged legacy properties, duplicate Reminder identifiers, orphan reminders, and renamed pages.
- Update ADR/PLAN docs with final sync policy.

Acceptance:

- `swift build` passes.
- `swift test` passes.
- Runtime app relaunches.
- No legacy Detail/Outliner/Journal/Compass/Attachment dependency returns.

## First Task Packet To Execute

Start with Phase 1.

Task Packet:

- Name: `TASK-PACKET-008-plan-005-reminders-first-bootstrap`
- Scope:
- Reminders-first import into Logseq pages
- deterministic runtime page/task identity derivation from Reminder IDs
- safe page claim/create behavior
- projection ignores unowned Logseq TODOs during bootstrap
  - create tests using Reminder snapshot and Logseq page fixtures
- Files likely touched:
  - `import/BUF/Services/LogseqProjectPageStore.swift`
  - `import/BUF/Services/RetainedReminderImportSync.swift`
  - `import/BUF/Services/RetainedWorkspaceSurfaceProjection.swift`
  - `import/BUF/App/AppStateSourceIO.swift`
  - tests under `Tests/BrainUnfogHarnessTests/`
- Verification:
  - focused Reminders bootstrap tests
  - retained projection tests
  - `swift build`
  - `swift test`
  - relaunch app

## Decision

Do not blindly continue `PLAN-004`.

Use `PLAN-005` as the new primary implementation plan. `PLAN-004` remains historical cleanup context only.
