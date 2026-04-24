# TASK-PACKET-006: Blocked legacy action reference removal

## Status

Drafted during PLAN-004 orchestration on 2026-04-24. No source files or runtime data are deleted by this packet.

## Goal

Remove direct Schedule/Timeline references to legacy Outliner/Project Detail/SwiftData action code that is already unreachable behind retained mutation gates.

This is a non-destructive reference-removal slice before file deletion inventory approval.

## Implementation Scope

- Replace blocked Schedule action bodies with gate-only no-ops where the action is not yet represented by retained commands:
  - task create/delete/restore
  - planned work progress
  - preparation/postpone helpers
  - legacy BUF-owned Calendar event drag/delete handlers that are already blocked
- Replace blocked Timeline action bodies with gate-only no-ops where the action is not yet represented by retained commands:
  - project create/delete/archive/color/stage/reorder
  - task move
  - planned work progress
- Remove Schedule/Timeline `SwiftData` imports and `modelContext` environment usage when no longer needed.
- Remove Schedule/Timeline references to `ReminderRuntimeProjectionReadModelService.createdProjectUndoTemplate` and `cachedOutlinerRuntimeProjectionSnapshot`.

## Retained Paths Preserved

- Schedule/Timeline retained read reload path remains retained-only.
- Task completion stays on `RetainedTaskCommandService`.
- Task schedule edit stays on `RetainedTaskCommandService`.
- Lightweight Calendar EventKit bridge remains task-schedule driven through `RetainedCalendarEventKitBridge`.
- Project/task reveal still routes to Logseq page selection.
- Foreign Calendar overlay actions remain read-only.
- Retained app-managed event writes from task schedule edits must keep `RetainedCalendarEventKitBridge`.

## Legacy Fallback Policy

- No legacy action fallback is allowed in Schedule/Timeline.
- Unsupported actions remain blocked through `RetainedSurfaceMutationGate`.
- If a blocked legacy action must be retained for the product, stop and define a new retained command concept first.

## Out Of Scope

- Source file deletion.
- SwiftData schema/model removal.
- `.buf`, `.buf/attachments`, or graph-local runtime data deletion.
- Implementing new retained create/delete/project-order commands.
- Rewriting Schedule/Timeline UI.
- Re-enabling Project Detail or Outliner entry points.
- Implementing inbound Calendar overlay edit semantics.

## Acceptance Criteria

- `import/BUF/Features/Schedule/*` and `import/BUF/Features/Timeline/*` contain no references to:
  - `modelContext`
  - `ReminderRuntimeProjectionReadModelService`
  - `cachedOutlinerRuntimeProjectionSnapshot`
  - `appState.createProjectList`
  - `appState.deleteProjectPermanently`
  - `appState.saveProjectDetail`
  - `appState.writeProjectDetail`
  - `appState.archiveProject`
  - `appState.updateProjectColor`
- Retained completion/schedule/reveal actions still compile and remain connected.
- Unsupported actions still report a retained mutation gate error instead of calling legacy code.
- Every converted action must still call `RetainedSurfaceMutationGate` through
  `allowScheduleMutation` or `allowTimelineMutation` before returning.
- Calendar edits are split explicitly:
  - External Calendar overlay events stay read-only.
  - App-managed schedule-derived Calendar writes stay task-schedule driven through
    `RetainedCalendarEventKitBridge`.
  - Only already-blocked legacy BUF-owned Calendar command handlers are no-oped.
- No source files, schemas, or runtime data are deleted.

## Verification Gate

- Focused grep acceptance checks for the exact legacy symbols above.
- Broad Schedule/Timeline grep for legacy action-path symbols:
  - `appState.saveProjectDetail`
  - `appState.writeProjectDetail`
  - `Outliner`
  - `SwiftData`
  - `ModelContext`
  - `AppStateOwnedCalendarSync`
  - `AppStateCalendarOwnerCommands`
  - `OwnedScheduleCalendar`
  - `saveProjectDetailTaskPlannedWorkProgress`
  - `saveProjectDetailTaskCompletion`
  - `writeProjectDetailTaskSchedule`
  - `moveTaskSequence`
- Focused grep retained-path checks:
  - retained read reload still calls `resolveRetainedOnly`
  - completion still calls `RetainedTaskCommandService.setTaskCompletion`
  - schedule edit still calls `RetainedTaskCommandService.setTaskSchedule`
  - task-schedule Calendar bridge still calls `RetainedCalendarEventKitBridge.apply`
  - reveal paths still call `onSelectProject(projectID)`
- `swift build`
- `swift test`
- Terminate the existing app.
- Relaunch `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app`.

## Stop Conditions

- Stop before deleting any source file.
- Stop before removing SwiftData schema/model definitions.
- Stop before deleting `.buf` or graph-local runtime data.
- Stop if Schedule/Timeline requires a currently missing retained command to preserve active user-facing behavior.
- Stop if the required edit expands beyond Schedule/Timeline action/view reference removal.
