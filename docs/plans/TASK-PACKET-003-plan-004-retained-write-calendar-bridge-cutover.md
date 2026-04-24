# TASK-PACKET-003: Retained Write Action And Calendar Bridge Cutover

## Context
- PLAN-004 retained read path is in place for Schedule and Timeline.
- Schedule/Timeline reload now prefers `RetainedWorkspaceSurfaceProjection`.
- Legacy fallback is allowed only when the Logseq graph is not configured or retained page loading fails.
- Identity ambiguity, missing/orphan/damaged identities, and partial retained coverage are blockers, not fallback reasons.
- Calendar write is not implemented yet; TASK-PACKET-001/002 only preserve `RetainedCalendarBridgePolicy` decisions.

## Slice Goal
Move the smallest safe Schedule/Timeline user action path away from legacy Outliner/Project Detail runtime writes and into retained Logseq/Reminder commands.

This slice creates the retained command seam and wires only the actions that already have enough retained identity:
- task completion
- task schedule edit
- task reveal/open

Calendar work is limited to lightweight orchestration seam state: policy decisions, owned-event write intent, and write-loop suppression markers. This slice must not write EventKit events.

## Timeline Action Path Cutover Scope
- `completeTimelineTask` / timeline completion undo-redo path calls a retained command that writes:
  - Logseq managed task `TODO`/`DONE`
  - Reminder item completion state
- This slice must not add legacy History writes. Undo may be omitted, or it must call the same retained command path without Project Detail/Outliner writes.
- `revealTimelineTaskDetail` remains project-page open behavior and must not restore Project Detail or Outliner entry points.
- After a retained completion write, Timeline reloads through the retained read path.
- Timeline planned work, project creation, project deletion, project reorder, color/stage edits, and task move remain blocked by the mutation gate or existing non-retained paths until a later packet explicitly covers them.

## Schedule Action Path Cutover Scope
- `updateScheduleTaskCompletion` calls the same retained completion command as Timeline.
- `applyScheduleState` calls a retained schedule command that writes:
  - Logseq managed task `date::`
  - Logseq managed task `duration::` only for explicit-time scheduled tasks
  - Reminder item due date and explicit-time flag
  - Existing `repeat::` is preserved but not converted into Calendar recurring series
- `revealScheduleTask` remains project-page open behavior and must not restore Project Detail or Outliner entry points.
- After a retained write, Schedule reloads through the retained read path.
- Schedule quick-add, task deletion, preparation schedule, planned work progress, and external calendar event drag/delete remain blocked by the mutation gate or existing out-of-scope behavior until later packets.

## Logseq/Reminder Write Command Scope
- Introduce a retained task command seam that operates from:
  - active Logseq graph root
  - retained project id
  - retained task id
  - `reminder_external_id::`
- Command must fail closed when:
  - graph root is missing
  - retained projection cannot be built
  - project/task cannot be found in the retained snapshot
  - task identity is damaged, duplicate, missing, orphaned, or ambiguous
  - target task is not in the BUF managed Logseq section
  - `reminder_external_id::` is missing for a command that must write Reminder
  - Logseq page cannot safely persist managed tasks
  - Reminder write fails after Logseq write and Logseq rollback fails
- Completion command writes Reminder and Logseq according to PLAN-001:
  - Logseq task = Reminder item
  - task completion is reflected in both systems
- Schedule command writes Reminder and Logseq according to PLAN-001:
  - `date::` is date-only when no explicit time exists
  - `date::` is explicit timestamp when time exists
  - `duration::` is stored only when explicit time exists and duration is positive
  - `repeat::` is preserved by schedule edits and not expanded into Calendar recurrence
- `repeat::` editing itself is out of scope for this slice. A later retained command must update both Logseq `repeat::` and Reminder recurrence when repeat editing is reintroduced.
- If Reminder write fails after Logseq write, rollback the Logseq managed task record to the pre-write state.

## Calendar Bridge Write Orchestration Scope
- Retain Calendar policy from TASK-PACKET-001:
  - external Calendar event = read-only overlay
  - only app-managed event candidates are writable
  - date-only task owns no Calendar event
  - explicit-time `date::` + `duration::` task is an app-managed event candidate
  - `repeat::` must not create recurring Calendar series
  - ambiguous Calendar ownership fails closed
- This slice returns a Calendar bridge decision after retained task command mutation.
- This slice may create pure write-intent/loop-prevention marker types.
- This slice must not call EventKit event write APIs.
- Date-only or unscheduled tasks with an existing `calendar_event_external_id::` return a `removeOwnedEvent` intent only. They must not clear `calendar_event_external_id::` until a retained Calendar delete path exists.
- This slice must not call `AppStateOwnedCalendarSync`, `AppStateCalendarOwnerCommands`, or old `OwnedScheduleCalendar*` services.

## Action Fallback Policy
- Retained-capable completion/schedule actions must not call legacy Project Detail/Outliner writes once graph root is configured.
- Existing read fallback remains only for graph-not-configured or page-loader failure as defined in TASK-PACKET-002.
- Legacy Outliner/Project Detail runtime must not hide retained command identity failures.
- Old BUF-owned Calendar sync must not preserve previous Calendar write semantics.
- Removal condition:
  - after retained commands cover create/delete/move/planned-work/preparation and Calendar EventKit writes have a retained bridge, remove the remaining legacy action fallback code under a checked deletion packet.

## Out Of Scope
- Source file deletion.
- `.buf/attachments` or runtime data deletion.
- SwiftData/schema removal.
- Project Detail or Outliner visible entry point restoration.
- Large Schedule/Timeline UI rewrite.
- EventKit Calendar event create/update/delete.
- Legacy BUF-owned Calendar sync replacement beyond pure retained write intent.
- Schedule quick-add, task deletion, preparation schedule, planned work progress.
- Timeline project create/delete/reorder/stage/color and task move.
- AppState-owned Calendar sync internals.

## Candidate Files
- Add `import/BUF/Services/RetainedTaskCommandService.swift`.
- Add `Tests/BrainUnfogHarnessTests/RetainedTaskCommandServiceTests.swift`.
- Modify `import/BUF/Services/LogseqProjectPageStore.swift` only to add a non-renaming managed-task update method for existing owned pages.
- Modify `import/BUF/Features/Schedule/ScheduleBoardView.swift` only to store retained Calendar write-loop markers.
- Modify `import/BUF/Features/Schedule/ScheduleBoardActions.swift` only for completion/schedule retained command routing.
- Modify `import/BUF/Features/Timeline/TimelineBoardView.swift` only to store retained Calendar write-loop markers.
- Modify `import/BUF/Features/Timeline/TimelineBoardRefresh.swift` only to prune retained Calendar write-loop markers on reload.
- Modify `import/BUF/Features/Timeline/TimelineBoardActions.swift` only for completion retained command routing.

## Acceptance Criteria
- Retained completion command updates Logseq managed task completion and Reminder completion.
- Retained schedule command updates Logseq `date::`/`duration::` and Reminder schedule.
- Date-only schedule returns `removeOwnedEvent` intent when an existing app-managed Calendar event id exists, but does not clear `calendar_event_external_id::` and does not mutate EventKit.
- Explicit-time date + positive duration returns an upsert Calendar bridge decision.
- `repeat::` survives schedule edits but does not create recurring Calendar write intent.
- `repeat::` editing is not exposed in this slice.
- Missing/duplicate/damaged/orphan identity blocks the command and does not call legacy write paths.
- Non-managed Logseq tasks block the command.
- Retained commands update the existing Logseq page in place and do not rename/remove graph page files in this slice.
- Retained Logseq writes fail closed when the managed task section changed after the command loaded its baseline.
- Reminder failure rolls back Logseq managed task mutation.
- Schedule/Timeline consumer state preserves the retained Calendar write-loop marker returned by user-initiated retained commands.
- Calendar write-loop prevention is test-covered at the pure seam level.
- No EventKit Calendar event write occurs in this slice.
- No `AppStateOwnedCalendarSync`, `AppStateCalendarOwnerCommands`, or old `OwnedScheduleCalendar*` service is called.
- No source files, SwiftData/schema, `.buf/attachments`, or runtime data are deleted.

## Build/Test/Runtime Gate
- `swift test --filter RetainedTaskCommandServiceTests`
- `swift build`
- `swift test`
- After code changes and passing build/test, terminate the existing app.
- Relaunch `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app`.

## Stop Conditions
- Stop and report exact file/path list if deletion becomes necessary.
- Stop and report exact file list and reason if out-of-scope files must be modified to compile.
- Stop and propose a new retained concept if a Schedule/Timeline action cannot be safely represented as a retained command.
