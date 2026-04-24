# TASK-PACKET-004: Lightweight Retained Calendar EventKit Bridge

## Context
- TASK-PACKET-001 added retained projection and Calendar bridge policy seams.
- TASK-PACKET-002 moved Schedule/Timeline read reload paths to retained projection first.
- TASK-PACKET-003 moved retained-capable task completion and schedule edit actions to Logseq/Reminder retained commands.
- TASK-PACKET-003 preserved Calendar bridge decisions and write-loop markers but did not write EventKit.

## Slice Goal
Implement the smallest lightweight Calendar EventKit write bridge for retained task schedule edits.

This slice must write only app-managed Calendar events derived from retained Logseq/Reminder task schedules. It must not use legacy Outliner runtime, Project Detail runtime, `AppStateOwnedCalendarSync`, `AppStateCalendarOwnerCommands`, or old `OwnedScheduleCalendar*` policy/support types.

## Calendar Bridge Scope
- Add a retained Calendar write service that consumes `RetainedCalendarBridgeDecision`.
- Support:
  - `upsert` for explicit-time `date::` + positive `duration::`
  - `removeOwnedEvent` for date-only, unscheduled, or durationless tasks that already have `calendar_event_external_id::`
  - `noAction` as no-op
  - `failClosed` as an error
- Write created/updated EventKit event external identity back to Logseq `calendar_event_external_id::`.
- Resolve or create the dedicated retained app-owned Calendar first.
- Existing `calendar_event_external_id::` update/delete must resolve the app-owned Calendar by stable stored Calendar identifier only.
- If the stable app-owned Calendar identifier is absent/stale, update/delete fails closed before creating or title-adopting any Calendar.
- Calendar creation must fail closed if any existing Calendar already uses the retained app-owned Calendar title without the stable stored identifier.
- Update/delete only events that resolve inside that retained app-owned Calendar.
- Fail closed if an existing `calendar_event_external_id::` resolves to any foreign Calendar event.
- Clear `calendar_event_external_id::` only after retained app-owned Calendar delete succeeds.
- If EventKit cannot resolve an existing `calendar_event_external_id::`, preserve the Logseq identity and fail closed for repair.
- Preserve `repeat::`; never create recurring Calendar series in this slice.
- Keep external Calendar overlay read-only. This service must not attach retained task identity to foreign events.

## Ownership And Fail-Closed Rules
- Update/delete is allowed only when `calendar_event_external_id::` resolves to one retained task in the retained graph.
- Duplicate retained event identities block before EventKit writes.
- Missing/orphan/damaged retained identities block before EventKit writes.
- Ambiguous EventKit matches for an existing external identifier block before mutation.
- Missing EventKit object for an existing retained Calendar binding blocks before Logseq identity clearing.
- Existing Calendar events are adopted or updated only through a stable unique `calendar_event_external_id::`; never by title/time fuzzy matching.
- A created event whose external identity cannot be persisted to Logseq must be removed as rollback when possible.
- Logseq `calendar_event_external_id::` updates must use the existing managed-task baseline and fail closed if the managed section changed since command load.

## Schedule/Timeline Wiring Scope
- Wire Schedule task schedule edits to apply the retained Calendar bridge after the retained Logseq/Reminder schedule command.
- After bridge apply, reload Schedule retained read path and refresh Calendar overlay.
- Preserve the returned write-loop marker in Schedule state.
- Timeline completion remains retained Logseq/Reminder only; it does not trigger Calendar writes because completion does not change Calendar projection.
- Calendar event drag/delete from overlay remains out of scope and stays blocked until a retained external-change packet exists.

## Write Loop Policy
- Calendar writes must return or preserve `RetainedCalendarBridgeWriteMarker`.
- Echo suppression is proven at seam level by marker comparison tests.
- Create/update/delete bridge results must expose a marker containing EventKit identity and normalized timing fingerprint where applicable.
- Tests must prove a simulated matching EventKit echo is suppressed and a non-matching external change is not.
- Consumer state must keep the marker long enough for a later retained external-change observer to suppress matching EventKit echoes.

## Out Of Scope
- Source file deletion.
- `.buf/attachments` or graph-local runtime data deletion.
- SwiftData/schema/model removal.
- Legacy runtime/reference removal.
- Calendar.app external change import from retained owned events back into Logseq.
- Calendar event drag/delete UI cutover.
- Timeline Calendar write trigger beyond schedule-derived retained tasks.
- Recurring Calendar series for `repeat::`.
- Replacing Calendar overlay read path.
- Editing external Calendar events.

## Candidate Files
- Add `import/BUF/Services/RetainedCalendarEventKitBridge.swift`.
- Add `Tests/BrainUnfogHarnessTests/RetainedCalendarEventKitBridgeTests.swift`.
- Modify `import/BUF/Features/Schedule/ScheduleBoardActions.swift` only to call retained bridge after retained schedule command.

## Acceptance Criteria
- Explicit-time `date::` + positive `duration::` creates an app-managed Calendar event and writes `calendar_event_external_id::`.
- Existing unique `calendar_event_external_id::` updates the matching app-managed Calendar event.
- Date-only or unscheduled retained task removes the existing app-managed Calendar event and then clears `calendar_event_external_id::`.
- Missing EventKit object for an existing `calendar_event_external_id::` fails closed and preserves `calendar_event_external_id::`.
- Existing Calendar events are never matched by title/time alone.
- Foreign Calendar matches fail closed and preserve `calendar_event_external_id::`.
- Duplicate retained event identities fail closed without EventKit mutation.
- Ambiguous EventKit matches fail closed without mutation.
- Created event rollback removes the new EventKit event if Logseq identity persistence fails.
- `repeat::` is preserved and does not create recurring Calendar series.
- Schedule action path does not call legacy Calendar owner/sync services.
- Focused tests cover create/update/delete/fail-closed/rollback/write-loop behavior.

## Build/Test/Runtime Gate
- `swift test --filter RetainedCalendarEventKitBridgeTests`
- `swift build`
- `swift test`
- After code changes and passing build/test, terminate the existing app.
- Relaunch `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app`.

## Stop Conditions
- Stop and report exact file/path list before source file deletion.
- Stop and report exact schema/model list before SwiftData/schema/model removal.
- Stop before deleting `.buf/attachments` or graph-local runtime data.
- Stop if Calendar authorization/TCC packaging blocks runtime launch or automated bridge verification.
- Stop if retained concepts cannot safely represent Calendar ownership.
