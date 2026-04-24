# PLAN-004: Checked feature deletion and retained projection replacement

## Status

Decisions updated from user direction on 2026-04-24. Do not execute destructive deletion until the Phase 0 inventory gate is approved.

## Source

- Checklist: `docs/plans/FEATURE-CLEANUP-CHECKLIST-001.md`
- Architecture baseline: `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
- Sync policy: `docs/plans/PLAN-001-sync-policy-v1.md`
- Retained app cleanup: `docs/plans/PLAN-003-retained-app-cleanup.md`
- Phase 0 inventory: `docs/plans/ARTIFACT-002-plan-004-phase-0-deletion-inventory.md`

## Goal

Remove all checked legacy features from the current app while preserving the retained product:

- Logseq graph folder as the user-facing data store.
- Reminders sync where page equals list and task equals reminder.
- Schedule view.
- Timeline view.
- Foreign calendar read-only overlay.
- Lightweight Logseq/Reminders/Calendar bridge behavior required by PLAN-001.

Unchecked items in `FEATURE-CLEANUP-CHECKLIST-001.md` are not deletion targets for this plan.

## Non-goals

- Do not remove Logseq, Reminders, Schedule, Timeline, setup, permission, graph-local `.buf`, or security-scoped bookmark flows.
- Do not remove foreign calendar read-only overlay.
- Do not keep legacy BUF app concepts just because current Schedule/Timeline still depend on them.
- Do not migrate old `.buf` SQLite domain data. If a retained runtime need appears, design a new minimal cache/store and ask before adding it.

## User decisions

- The app is now a lightweight Logseq-based bridge: Logseq is the detail/outliner base, Reminders supplies lists/tasks, and Calendar supplies events.
- Keep only code needed for Logseq, Reminders, Calendar, Schedule, and Timeline.
- If existing Schedule/Timeline dependencies are larger than that bridge, replace them with smaller retained concepts.
- Delete `.buf/attachments` contents and remove attachment management.
- Do not migrate old `.buf` SQLite data. Logseq, Reminders, and Calendar are the retained sources of truth.

## Current blocker

The checked list includes runtime foundations currently used by Schedule and Timeline. Direct deletion is not safe.

High-risk checked items:

- `Persistence and derived read models`
- `Outliner core storage models`
- `Normalized SQLite persistence`
- `Workspace tree repository`
- `Runtime projection patch/read services`
- `Schedule/timeline read model services`
- `Project lifecycle/order/task order services`
- `BUF-owned calendar creation and writes`

Observed dependency examples:

- `ScheduleBoardActions` and `ScheduleBoardView` still call `ScheduleProjectionService` and use `cachedOutlinerRuntimeProjectionSnapshot`.
- `TimelineBoardRefresh` still calls `TimelineProjectionService` and uses `cachedOutlinerRuntimeProjectionSnapshot`.
- `AppStateRuntimeProjectionRead`, `AppStateRuntimeProjectionPatch`, `AppStateSourceIO`, reminder owner commands, sidecar owner commands, and calendar owner commands still depend on `OutlineProjectionRuntimeSnapshot`.
- `ProjectIdentityResolver` and Reminder sync still use runtime snapshot identity maps.
- Legacy BUF-owned Calendar writes provide the current `calendar_event_external_id::` creation/update/remove path.

Therefore direct deletion would break build, Schedule, Timeline, and Calendar sync.

## Replacement concept

Introduce a smaller retained projection that is not an Outliner, Project Detail, Archive, Journal, Compass, Attachment, History, or Undo system.

New retained bridge vocabulary:

- `RetainedWorkspaceSnapshot`
- `RetainedProject`
- `RetainedTask`
- `RetainedTaskSchedule`
- `RetainedTaskIdentity`
- `RetainedProjectIdentity`
- `RetainedCalendarBridge`

Rules:

- Source of truth for visible project/task content is Logseq pages and Reminders.
- Logseq page title maps to Reminder list title.
- Logseq task maps to Reminder item.
- Logseq bullet nesting/order remains Logseq-only.
- Internal identity remains hidden metadata in Logseq task/page properties.
- Schedule and Timeline consume retained projection only, not Outliner runtime types.
- Foreign Calendar events are read-only overlays in Schedule.
- Calendar events created from Logseq/Reminder task schedules are writable by the app and tracked through `calendar_event_external_id::`.
- The old BUF-owned Calendar implementation is deletion-target code; the retained behavior should be rebuilt as a smaller bridge, not preserved as a legacy subsystem.
- `.buf` may remain only as hidden app support storage for setup/cache if needed; it must not be the source of truth for projects, notes, task structure, attachments, history, or old SQLite domain data.

## Deletion strategy

Use strangler migration. Do not delete a legacy foundation until all retained consumers have moved to the replacement.

### Phase 0: Deletion inventory gate

Before any file deletion or SwiftData/schema removal:

- Produce the exact file list to delete.
- Produce the exact type/model/schema list to remove.
- Classify each item as safe-delete, replacement-required, or hold.
- Stop for user confirmation.

Acceptance:

- No code is deleted in Phase 0.
- The file list maps back to checked checklist items only.
- Any retained dependency is marked replacement-required or hold.

### Phase 1: Safe visible cleanup

Remove checked low-risk visible leftovers that do not define retained data:

- Note font menu.
- Remaining Journal visible entry points.
- Remaining Compass visible entry points.
- Remaining Archive visible entry points.
- Remaining OpenAI/Gemini visible settings and API-key status surfaces.

Acceptance:

- App launches.
- Main workspace still shows retained navigation.
- Timeline and Schedule still open.
- `swift build` and `swift test` pass.

### Phase 2: Disconnect Project Detail and Outliner UI

Remove checked UI paths without deleting shared runtime types yet:

- Embedded project detail host.
- Detached project window.
- Project note editor.
- Project task list UI.
- Project detail attachments UI.
- Outliner window/menu/entry points.

Replacement behavior:

- Selecting a project from Timeline or workspace opens the matching Logseq page.
- No in-app project detail editor remains.

Acceptance:

- Project selection opens Logseq page or is a safe no-op when the page cannot be resolved.
- No Project Detail or Outliner window can be opened from app UI.
- Schedule/Timeline still render from the existing runtime snapshot during this phase.
- `swift build` and `swift test` pass.

### Phase 3: Build retained projection seam

Add a retained projection adapter while leaving legacy runtime in place:

- Load projects and tasks from Logseq managed pages plus reminder bindings.
- Preserve `brain_unfog_task_id::`, `reminder_external_id::`, and `calendar_event_external_id::`.
- Preserve `date::`, `duration::`, and `repeat::`.
- Expose project/task descriptors required by Timeline and Schedule.
- Add fixtures for duplicate IDs, orphan bindings, damaged hidden properties, and missing pages.

Acceptance:

- Retained projection tests pass from fixture pages.
- Identity ambiguity fails closed.
- Existing runtime consumers remain unchanged until Phase 4.

### Phase 4: Move Timeline and Schedule to retained projection

Replace existing Schedule/Timeline dependency on Outliner runtime:

- Replace `ScheduleProjectionService` consumption with a retained schedule projection.
- Replace `TimelineProjectionService` consumption with a retained timeline projection.
- Replace task completion/scheduling actions with retained Logseq/Reminder-backed commands.
- Remove Undo registrations or replace them with explicit non-undo behavior.

Acceptance:

- Timeline renders projects/tasks from retained projection.
- Schedule renders scheduled tasks and foreign calendar overlay.
- Task completion writes to Reminders/Logseq according to PLAN-001.
- Task schedule edits update `date::`, `duration::`, `repeat::` as applicable.
- `swift build` and `swift test` pass.

### Phase 5: Rebuild lightweight Calendar bridge

Replace legacy BUF-owned Calendar code with the retained bridge:

- Scheduled Logseq/Reminder task creates or updates one app-managed Calendar event.
- Removing task schedule removes the owned event binding according to fail-closed rules.
- Calendar event timing changes can update the corresponding Logseq task schedule only when `calendar_event_external_id::` identifies a single retained task.
- Foreign calendar events remain read-only.
- No sync loop is introduced.
- Calendar authorization prompt-once policy remains intact.
- Old `OwnedScheduleCalendar*` and `AppStateOwnedCalendarSync` code is removed after the retained bridge passes tests.

### Phase 6: Delete legacy foundations

Only after Phases 3-5 pass:

- Delete Outliner runtime snapshot types.
- Delete Project Detail source files.
- Delete Outliner source files.
- Delete Attachment source files and `.buf/attachments` management code.
- Delete `.buf/attachments` directory contents during destructive cleanup after the exact path list is approved.
- Delete Journal source files.
- Delete Compass source files.
- Delete Obsidian legacy source files.
- Delete Archive source files and soft-delete semantics.
- Delete History and Undo source files.
- Delete AI/API-key source files.
- Delete SwiftData app stack and legacy SwiftData models if no retained schema needs them.
- Delete old normalized persistence and old SQLite domain data without migration after the retained projection no longer depends on it.

Before this phase starts, run the Phase 0 inventory gate again with the final post-migration source tree.

Acceptance:

- No references remain to deleted feature names in compiled Swift sources except migration notes/tests explicitly allowed by this plan.
- `swift build` and `swift test` pass.
- App launches and opens directly after graph/permission setup.

## Risk register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Schedule/Timeline currently depend on Outliner runtime snapshot | High | Build retained projection first, then migrate consumers |
| Removing normalized persistence removes identity and sidecar storage | High | Move retained identity to Logseq properties/EventKit IDs before deletion; do not migrate old SQLite domain data |
| Removing legacy BUF-owned calendar writes conflicts with PLAN-001 | High | Rebuild only the lightweight retained Calendar bridge behavior |
| Removing Project lifecycle services can break create/rename/delete flows | High | Replace with Logseq page plus Reminder list commands before removal |
| Removing Undo changes user behavior | Medium | Explicitly accept no undo for retained schedule/timeline commands |
| Removing attachment directories deletes user files | Medium | User explicitly chose deletion; require exact path list approval before destructive cleanup |
| Removing history can break Journal/Compass consumers | Low after those features are deleted | Delete Journal/Compass first, then history |

## Ask First decisions

- Closed: Calendar sync remains, but only as a lightweight Logseq/Reminders/Calendar bridge.
- Closed: `.buf/attachments` contents should be deleted.
- Closed: old `.buf` SQLite domain data should not be migrated.
- Still required before deletion: exact file/type/schema/path deletion inventory and user approval.

## Execution gate

Implementation must proceed slice by slice:

- Implement or delete one slice.
- Run review.
- Run `swift build`.
- Run `swift test`.
- Relaunch the app after non-document changes.
- Do not start the next destructive slice until the retained app passes the current gate.
