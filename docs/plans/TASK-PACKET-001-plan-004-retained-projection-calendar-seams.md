# TASK-PACKET-001: PLAN-004 retained projection and lightweight Calendar bridge seams

## Status

Draft for the next implementation slice after the 2026-04-24 visible-entry-point rewiring pass.

## Why this slice exists

`PLAN-004` blocks destructive cleanup until Schedule/Timeline and Calendar sync stop depending on the oversized legacy runtime.

The next safe slice is not deletion.
The next safe slice is a pure seam:

- define retained projection types
- define retained Calendar bridge policy/types
- add fixture coverage for fail-closed identity cases
- keep current consumers and legacy runtime intact

This keeps the app buildable while creating the replacement surface needed by later cutover work.

## Required inputs

- `docs/plans/PLAN-004-checked-feature-deletion-and-retained-projection-replacement.md`
- `docs/plans/ARTIFACT-002-plan-004-phase-0-deletion-inventory.md`
- `docs/plans/PLAN-001-sync-policy-v1.md`
- `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`

## Objective

Add a retained, pure-data seam that can represent:

- Logseq-managed projects/pages
- Reminder-backed tasks and identity bindings
- task schedule metadata needed by Schedule/Timeline
- lightweight Calendar ownership decisions for app-managed events

without:

- deleting legacy files
- switching Schedule/Timeline consumers
- removing SwiftData/schema/runtime data
- keeping the old BUF-owned Calendar implementation as the long-term design

## Lane split

### Implementation lane

Single-writer.
No parallel worker split in this slice.

Reason:

- the seam is new, but the vocabulary must stay coherent
- the next slice will depend on exact naming and fail-closed rules

### Review lane

Separate adversarial review agent after the packet or code lands.
Primary review target:

- identity ambiguity handling
- accidental scope creep into consumer migration
- accidental preservation of old Calendar ownership semantics

### Test lane

Separate tester lane runs focused tests plus full `swift build` and `swift test`.

## Exact files in scope

Existing files:

- `import/BUF/Services/LogseqProjectPageStore.swift`
- `import/BUF/Services/LogseqReminderPropertyCodec.swift`
- `import/BUF/Services/ManagedLogseqSyncHardening.swift`
- `import/BUF/Services/ReminderTaskAdoptionPolicy.swift`

New files:

- `import/BUF/Services/RetainedProjectionModels.swift`
- `import/BUF/Services/RetainedProjectionBuilder.swift`
- `import/BUF/Services/RetainedCalendarBridgePolicy.swift`
- `Tests/BrainUnfogHarnessTests/RetainedProjectionBuilderTests.swift`
- `Tests/BrainUnfogHarnessTests/RetainedCalendarBridgePolicyTests.swift`

## Exact files out of scope

- `import/BUF/App/AppStateRuntimeProjectionRead.swift`
- `import/BUF/App/AppStateRuntimeProjectionPatch.swift`
- `import/BUF/App/AppStateScheduleProjectionRead.swift`
- `import/BUF/App/AppStateOwnedCalendarSync.swift`
- `import/BUF/App/AppStateCalendarOwnerCommands.swift`
- `import/BUF/Services/ScheduleProjectionService.swift`
- `import/BUF/Services/TimelineProjectionService.swift`
- `import/BUF/Services/OwnedScheduleCalendarInvalidationPolicy.swift`
- `import/BUF/Services/OwnedScheduleCalendarSupport.swift`
- `import/BUF/Services/OwnedScheduleCalendarSyncPolicy.swift`
- `import/BUF/Features/Schedule/ScheduleBoardActions.swift`
- `import/BUF/Features/Timeline/TimelineBoardActions.swift`
- every file listed under `Replacement-required before deletion` in `ARTIFACT-002`, unless only read for reference
- any source-file deletion
- any `.buf` runtime data deletion

## Work items

1. Add retained vocabulary types.
   Required minimum types:
   - `RetainedWorkspaceSnapshot`
   - `RetainedProject`
   - `RetainedTask`
   - `RetainedTaskIdentity`
   - `RetainedProjectIdentity`
   - `RetainedTaskSchedule`
   - `RetainedCalendarBridgeDecision`

2. Build a pure retained projection builder.
   Inputs must mirror real retained source shapes:
   - Logseq page snapshots
   - reminder/list identity bindings
   - retained task property payloads
   Fixture payloads are allowed, but they must match the loader shapes that later cutover work will consume.
   It must not read SwiftData or mutate app state in this slice.

3. Encode fail-closed rules in the builder.
   Required failures:
   - duplicate `brain_unfog_project_id::`
   - duplicate `reminder_list_external_id::`
   - duplicate `brain_unfog_task_id::`
   - duplicate `reminder_external_id::`
   - duplicate `calendar_event_external_id::`
   - conflicting project identity between page metadata and derived reminder identity
   - missing page for a retained project binding
   - orphan reminder binding with no safe page/task match
   - damaged hidden properties that cannot be deterministically repaired

4. Add a lightweight Calendar bridge policy surface.
   It should answer only:
   - should this retained task own an app-managed event
   - if yes, what upsert payload is needed
   - if no, should any existing owned binding be removed
   - when should ambiguous ownership fail closed
   It must inherit the V1 boundary from `PLAN-001`:
   - only explicit-time `date::` plus `duration::` tasks are calendar-owned candidates
   - date-only tasks remain reminders-only
   - `repeat::` does not imply recurring Calendar series ownership in this slice

5. Add focused tests and fixtures.
   Tests should be pure and deterministic.
   No EventKit write tests in this slice.

## Acceptance criteria

- `RetainedProjectionBuilder` can construct a retained snapshot from fixture input without touching `AppState`.
- The fixture input covers real loader-equivalent shapes, not ad hoc synthetic shortcuts.
- The builder preserves retained metadata:
  - `brain_unfog_project_id::`
  - `reminder_list_external_id::`
  - `brain_unfog_task_id::`
  - `reminder_external_id::`
  - `calendar_event_external_id::`
  - `date::`
  - `duration::`
  - `repeat::`
- Identity ambiguity and missing-page bindings fail closed with explicit test coverage.
- `RetainedCalendarBridgePolicy` emits decisions only for app-managed event cases and leaves foreign calendars out of scope.
- `RetainedCalendarBridgePolicy` keeps date-only tasks out of Calendar ownership and does not create recurring event-series semantics from `repeat::`.
- No Schedule/Timeline consumer is migrated yet.
- No legacy Calendar or runtime file is deleted.
- `swift build` and `swift test` pass.

## Verification commands

- `swift build`
- `swift test`
- `swift test --filter RetainedProjectionBuilderTests`
- `swift test --filter RetainedCalendarBridgePolicyTests`
- `pkill -x BrainUnfogHarness || true`
- `open -n "/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app"`

## Stop conditions

Stop and report before continuing if any step requires:

- deleting a source file
- deleting `.buf/attachments` or any other graph-local runtime path
- removing a SwiftData model or schema element
- editing any out-of-scope single-writer file to make the pure seam compile

If that happens, report the exact file list and stop at the gate.

## Handoff note for the following slice

Only after this packet passes should the next slice touch consumer cutover:

- move `ScheduleProjectionService` read paths to retained projection
- move `TimelineProjectionService` read paths to retained projection
- replace legacy BUF-owned Calendar write orchestration with the retained bridge

Deletion is explicitly not part of this packet.
