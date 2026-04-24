# TASK-PACKET-002: PLAN-004 retained projection consumer cutover

## Status

Draft for the next implementation slice after `TASK-PACKET-001`.

## Why this slice exists

Schedule and Timeline still read their project/task surface from the legacy Outliner runtime snapshot. `PLAN-004` cannot safely delete that runtime until these consumers can read from the retained Logseq/Reminder projection instead.

This packet starts the cutover with the smallest buildable change:

- add a retained read-model adapter that projects `RetainedWorkspaceSnapshot` into a compatibility surface consumed by the existing Schedule/Timeline intermediate models
- wire Schedule and Timeline reload paths to use that retained projection when it can be built
- keep legacy runtime as an explicit temporary fallback only while retained loading is unavailable
- expose the lightweight Calendar bridge policy at the read-model boundary without performing EventKit writes

## Scope

### Schedule read path cutover

In scope:

- Build a retained-owned compatibility surface from `RetainedWorkspaceSnapshot`.
- The temporary compatibility surface may contain `WorkspaceProjectRuntimeRecord`, `ProjectSummaryRecord`, and `ScheduleSliceEntry` only to avoid rewriting Schedule/Timeline UI in this slice.
- Change Schedule workspace reload to prefer the retained projection read model.
- Keep existing Schedule UI layout, cache, drag, resize, and mutation handlers unchanged.
- Keep all-day rendering behavior for date-only tasks.
- Use explicit-time `date::` plus `duration::` only to mark Calendar bridge candidates, not to write Calendar events.

Out of scope:

- Replacing task completion, drag, resize, quick-add, or scheduling commands.
- Removing undo paths.
- Changing Schedule visual layout.
- Deleting or editing the legacy Schedule UI files beyond the reload/read-path seam needed for this packet.

### Timeline read path cutover

In scope:

- Build Timeline inputs from retained project/task records through the temporary compatibility surface used by the current Timeline projection.
- Change Timeline workspace reload to prefer the retained projection read model.
- Preserve project ordering from the incoming project ID list.
- Preserve root-task semantics by treating retained task records as root rows for now.

Out of scope:

- Replacing Timeline mutation commands.
- Rebuilding Timeline rows, overlays, or interactions.
- Adding task nesting support unless retained projection cannot represent the current required read model.

### Legacy runtime fallback

Fallback is allowed only as a temporary read-path bridge before retained identity evaluation can run.

Allowed fallback cases:

- Logseq graph root is not configured yet.
- Logseq pages directory cannot be opened or loaded before retained identity checks run.

Removal condition:

- Remove fallback only after Schedule and Timeline acceptance tests prove retained projection coverage for configured graphs and mutation paths no longer need legacy runtime state.

Fallback must not:

- silently reinterpret duplicate, missing, orphan, damaged, or conflicting retained identity failures as legacy truth
- silently reinterpret partial requested-project coverage as successful legacy truth
- write back through legacy runtime for newly added read-model code
- reintroduce Project Detail or Outliner entry points

Blocked retained cases:

- Any `RetainedProjectionBuilder.Error`.
- A configured graph whose retained projection does not cover all requested project IDs.
- Any retained projection value that cannot be expressed by the temporary compatibility surface.

Blocked cases must surface a diagnostic or empty retained result and must not display legacy runtime data as if the retained read path succeeded.

### Calendar bridge policy connection

In scope:

- Call `RetainedCalendarBridgePolicy.decision(for:)` while building retained schedule entries.
- Preserve decisions through `calendarBridgeDecisionsByTaskID` on the retained read-model surface.
- Do not write to EventKit.
- Do not create recurring Calendar series from `repeat::`.

Out of scope:

- Replacing `AppStateOwnedCalendarSync`.
- Editing `AppStateCalendarOwnerCommands`.
- Writing, updating, or deleting Calendar events.
- Changing foreign Calendar overlay behavior.

## Files in scope

New files:

- `import/BUF/Services/RetainedWorkspaceSurfaceProjection.swift`
- `Tests/BrainUnfogHarnessTests/RetainedWorkspaceSurfaceProjectionTests.swift`

Existing files:

- `import/BUF/Features/Schedule/ScheduleBoardActions.swift`
- `import/BUF/Features/Schedule/ScheduleBoardView.swift`
- `import/BUF/Features/Timeline/TimelineBoardRefresh.swift`
- `import/BUF/Features/Timeline/TimelineBoardView.swift`

Read-only reference files:

- `import/BUF/Services/RetainedProjectionModels.swift`
- `import/BUF/Services/RetainedProjectionBuilder.swift`
- `import/BUF/Services/RetainedCalendarBridgePolicy.swift`
- `import/BUF/Services/ReminderRuntimeProjectionReadModelService.swift`
- `import/BUF/Services/ScheduleProjectionService.swift`
- `import/BUF/Services/TimelineProjectionService.swift`
- `import/BUF/Services/LogseqProjectPageStore.swift`
- `import/BUF/Services/LogseqReminderPropertyCodec.swift`

## Out-of-scope files

- source file deletion
- `.buf/attachments` or any runtime data deletion
- SwiftData/schema removal
- `import/BUF/App/AppState.swift`
- `import/BUF/App/AppStateRuntimeProjectionRead.swift`
- `import/BUF/App/AppStateRuntimeProjectionPatch.swift`
- `import/BUF/App/AppStateOwnedCalendarSync.swift`
- `import/BUF/App/AppStateCalendarOwnerCommands.swift`
- `import/BUF/Services/OwnedScheduleCalendarInvalidationPolicy.swift`
- `import/BUF/Services/OwnedScheduleCalendarSupport.swift`
- `import/BUF/Services/OwnedScheduleCalendarSyncPolicy.swift`
- `import/BUF/Services/ScheduleProjectionService.swift`
- `import/BUF/Services/TimelineProjectionService.swift`
- Schedule/Timeline UI layout rewrites
- Project Detail or Outliner visible entry-point restoration

## Smallest implementation slice

1. Add `RetainedWorkspaceSurfaceProjection`.
2. Add a pure `RetainedWorkspaceSurfaceProjectionLoadResult` classification for retained success, fallback-allowed unavailable state, and blocked retained state.
3. Add pure tests that prove retained projects/tasks map into Schedule/Timeline intermediate records and fallback classification is narrow.
4. Wire Schedule and Timeline reload functions to prefer the retained read-model adapter from Logseq page snapshots.
5. Fall back to the existing runtime projection only for graph/loader unavailable cases.
6. Leave all mutation and Calendar write orchestration unchanged.

## Acceptance criteria

- Schedule reload no longer directly depends only on `cachedOutlinerRuntimeProjectionSnapshot`; it first attempts retained projection from Logseq pages.
- Timeline reload no longer directly depends only on `cachedOutlinerRuntimeProjectionSnapshot`; it first attempts retained projection from Logseq pages.
- Date-only retained tasks remain visible to Schedule as all-day workspace tasks.
- Explicit-time retained tasks with positive `duration::` are surfaced through `calendarBridgeDecisionsByTaskID` as `RetainedCalendarBridgePolicy.upsert` decisions.
- `repeat::` is preserved for Timeline/Reminder semantics but does not create Calendar recurrence behavior.
- Identity failures from `RetainedProjectionBuilder` fail closed as blocked retained reads and do not trigger legacy fallback.
- Partial requested-project coverage is blocked and does not trigger legacy fallback.
- No source files, SwiftData schema, or runtime data are deleted.
- Project Detail and Outliner visible entry points are not restored.

## Verification commands

- `swift test --filter RetainedWorkspaceSurfaceProjectionTests`
- `swift test --filter RetainedProjectionBuilderTests`
- `swift test --filter RetainedCalendarBridgePolicyTests`
- `swift build`
- `swift test`
- `pkill -x BrainUnfogHarness || true`
- `open -n "/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app"`

## Review lane

Adversarial review must check:

- retained read path does not mask identity ambiguity as successful legacy data
- Schedule/Timeline are not rebuilt beyond the read path
- legacy fallback is narrow, pre-identity-evaluation only, and explicitly removable
- Calendar bridge policy is called without preserving old broad Calendar write semantics
- no out-of-scope files or destructive changes are included

## Test lane

Tester must run focused retained projection tests, full build, full tests, and app relaunch.

If the tester lane does not respond, the implementation lane may run the verification commands sequentially and record the fallback.

## Stop conditions

Stop and report exact files/paths if implementation requires:

- deleting any source file
- deleting `.buf/attachments` or any graph-local runtime path
- removing SwiftData models or schema
- editing any out-of-scope file to make the build pass
- representing Schedule/Timeline data that cannot be expressed by retained projection without a new retained concept
