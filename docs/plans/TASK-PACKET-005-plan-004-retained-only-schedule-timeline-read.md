# TASK-PACKET-005: Retained-Only Schedule/Timeline Read Path

## Context
- TASK-PACKET-002 moved Schedule/Timeline reloads to retained-first with legacy fallback only for graph-not-configured or loader failure.
- TASK-PACKET-003 moved retained-capable task completion/schedule actions to retained Logseq/Reminder commands.
- TASK-PACKET-004 added lightweight retained Calendar EventKit bridge for schedule-derived app-managed events.

## Slice Goal
Remove Schedule/Timeline read fallback to legacy Outliner runtime projection.

After this slice, Schedule and Timeline must either render retained projection data or fail closed with an actionable retained-load blocker. They must not consult `cachedOutlinerRuntimeProjectionSnapshot` or `ReminderRuntimeProjectionReadModelService.workspaceSurfaceProjection` for Schedule/Timeline read reloads.

## Scope
- Add retained-only read resolution for `RetainedWorkspaceSurfaceProjectionLoadResult`.
- Treat graph-not-configured and retained page loader failure as blockers, not legacy fallback.
- Wire Schedule reload to retained-only resolution.
- Wire Timeline reload to retained-only resolution.
- Preserve retained Calendar bridge decisions and write markers.
- Keep existing legacy fallback function available for later checked removal; do not delete source files in this slice.

## Out Of Scope
- Source file deletion.
- SwiftData/schema/model removal.
- `.buf/attachments` or graph-local runtime data deletion.
- Removing old runtime projection services globally.
- Calendar external-change import.
- Schedule/Timeline action or write-path changes except keeping existing retained state compiling.
- Calendar EventKit write changes.
- UI redesign.

## Candidate Files
- Modify `import/BUF/Services/RetainedWorkspaceSurfaceProjection.swift`.
- Modify `import/BUF/Features/Schedule/ScheduleBoardActions.swift`.
- Modify `import/BUF/Features/Timeline/TimelineBoardRefresh.swift`.
- Modify `Tests/BrainUnfogHarnessTests/RetainedWorkspaceSurfaceProjectionTests.swift`.

## Acceptance Criteria
- Schedule reload does not reference legacy read fallback services.
- Timeline reload does not reference legacy read fallback services.
- Schedule/Timeline reload paths contain no references to `cachedOutlinerRuntimeProjectionSnapshot`.
- Schedule/Timeline reload paths contain no calls to `ReminderRuntimeProjectionReadModelService.workspaceSurfaceProjection`.
- Schedule/Timeline reload paths contain no branch that invokes the legacy fallback helper for retained read resolution.
- Graph-not-configured becomes a retained blocker with empty Schedule/Timeline data.
- Retained loader failure becomes a retained blocker with empty Schedule/Timeline data.
- Focused tests cover graph-not-configured and loader-failure retained blockers and prove no fallback data is returned.
- Identity ambiguity/missing/orphan/damaged/partial coverage remain blockers.
- Existing TASK-PACKET-001/002/003/004 tests still pass.

## Build/Test/Runtime Gate
- `swift test --filter RetainedWorkspaceSurfaceProjectionTests`
- `swift build`
- `swift test`
- After code changes and passing build/test, terminate the existing app.
- Relaunch `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app`.

## Stop Conditions
- Stop before source file deletion.
- Stop before SwiftData/schema/model removal.
- Stop before `.buf/attachments` or graph-local runtime data deletion.
- Stop if implementation requires broad out-of-scope edits.
- Stop if implementation requires Schedule/Timeline action-path changes or Calendar EventKit write changes.
- Stop if implementation requires adding a legacy runtime feature to compile.
- Stop if Schedule/Timeline cannot render retained projection without a new retained concept.
