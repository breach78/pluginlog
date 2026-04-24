# ADR-001: Keep BUF as the native hub and sync Logseq graph with Apple Reminders and Calendar

## Status
Proposed

## Date
2026-04-23

## Context

The target product is no longer "a Logseq plugin that reimplements BUF inside Logseq."
The target product is:

- keep `BUF` as a standalone macOS app
- reuse the existing native schedule and timeline views
- remove the current in-app project detail dependency from the main flow
- open the matching Logseq page when a project is selected
- sync Logseq project pages with Apple Reminders
- sync the schedule view with Apple Calendar

The data models are not identical:

- Apple Reminders has `list -> reminder`
- Logseq has `page -> bullet -> task`

For reminders sync, BUF must treat the Logseq model as richer than the Reminders model.
Only the project page and task subset are synced to Reminders.
Non-task bullets remain Logseq-only content.

This direction matches the current codebase much better than a Logseq plugin rewrite.

Existing code already provides the expensive native pieces:

- Apple Reminders access via EventKit in `import/BUF/Services/ReminderGateway.swift`
- Apple Calendar access via EventKit in `import/BUF/Services/ScheduleCalendarStore.swift`
- reminder projection and sync coordination in `import/BUF/App/OutlinerReminderSyncCoordinator.swift`
- schedule and timeline UI in `import/BUF/Features/Schedule/ScheduleBoardView.swift` and `import/BUF/Features/Timeline/TimelineBoardView.swift`
- project selection currently routed through inspector callbacks in `import/BUF/Features/Workspace/MainWorkspacePanels.swift`, `import/BUF/Features/Workspace/MainWorkspaceActions.swift`, and `import/BUF/Features/Workspace/MainWorkspaceSidebar.swift`
- platform URL opening in `import/BUF/Utilities/PlatformUIFoundation.swift`

Local Logseq documentation already confirms the deep-link path we need:

- `logseq://graph/<graph>?page=<page>`
- `logseq://graph/<graph>?block-id=<block uuid>`

Reference: `logseq-plugin-materials/repos/official/logseq-docs/pages/Logseq Protocol.md`

Local Logseq documentation also confirms that page files are title-based and depend on graph filename rules rather than UUID filenames.

Reference: `logseq-plugin-materials/repos/official/logseq-docs/pages/Filename format.md`

This matters because the current `ObsidianProjectNoteStore` writes `UUID.md` files and therefore is not a valid final storage layer for Logseq pages.

## Decision

Adopt the following architecture:

- `BUF` remains the native application and orchestration hub.
- Logseq is treated as an external Markdown graph and page viewer/editor.
- Apple Reminders and Apple Calendar remain connected through EventKit.
- Project selection in BUF opens the corresponding Logseq page instead of opening the current inspector/detail surface.
- Sync is implemented as a bidirectional diff engine centered in BUF, not as a direct Logseq-to-Apple bridge.

In short:

`Logseq graph files <-> BUF sync engine <-> EventKit`

BUF is the sync arbiter and identity registry.
Logseq and Apple apps remain editable clients, but BUF owns reconciliation, conflict policy, and outbound fan-out.

## Why Not a Logseq Plugin

A plugin-first design would force a split architecture:

- Logseq plugin UI for timeline and schedule
- a separate macOS native helper for EventKit access
- a bridge between the two

That would discard much of the value already present in the existing SwiftUI and EventKit code.
The native app approach preserves the working parts and only changes navigation and file sync.

## Scope of V1

V1 includes:

- project click in BUF opens Logseq page
- Logseq graph folder is configured in BUF
- pages with explicit project-page properties participate in sync
- project page tasks sync with Apple Reminders
- explicitly scheduled tasks sync with a BUF-owned Apple Calendar
- non-BUF Apple Calendar events are shown in the schedule view as read-only overlays

V1 does not include:

- rewriting BUF into a Logseq plugin
- writing to arbitrary user calendars not owned by BUF
- full task-level deep-linking on day one
- support for Logseq DB graphs

## Source of Truth

This system is not single-writer.
It is a multi-writer sync system with one hub.

The rules are:

- BUF owns canonical stable identities and sync metadata.
- Logseq graph files are user-editable content sources.
- Apple Reminders and the BUF-owned Apple Calendar are remote editable sources.
- BUF resolves changes from all sides into its local model, then writes normalized updates back out.

Practical interpretation:

- project identity is anchored by `Project.id`
- task identity is anchored by `TaskItem.id`
- remote links are stored as external identifiers
- page and block mapping must be stored explicitly instead of inferred only from titles

Relevant existing model anchors:

- `Project.id`, `Project.title`, and existing remote identifier fields in `import/BUF/Models/Project.swift`
- `TaskItem.id`, `reminderIdentifier`, `reminderExternalIdentifier`, `scheduleHasExplicitTime`, and `scheduledDurationMinutes` in `import/BUF/Models/TaskItem.swift`
- `SyncState` and `ConflictLog` in `import/BUF/Models/SyncMetadata.swift`

## Sync Topology

The sync engine runs in four directions:

1. Logseq file changes -> BUF
2. BUF local UI changes -> Logseq
3. Apple Reminders and Calendar changes -> BUF
4. BUF local changes -> Apple Reminders and Calendar

The pipeline is:

1. detect changed file or remote record
2. parse into normalized payload
3. resolve identity
4. compute field-level diff
5. apply conflict policy
6. persist BUF model
7. fan out normalized changes to the other targets

This is eventual consistency, not a direct live shared document model.
It should feel near-real-time, but reconciliation is still diff-based.

### Change Detection

The system must not rely on a single watcher.

V1 detection strategy:

- file-system watcher for low-latency graph updates
- EventKit-driven remote refresh for Reminders and Calendar changes
- periodic full reconciliation pass as a repair path

Reason:

- file watchers can miss bursts, renames, or external tool rewrites
- EventKit callbacks can arrive out of order
- a periodic repair scan is needed to converge after missed events

## Logseq Model

### Sync Target

Only Logseq file graphs are supported.

V1 project pages are pages that explicitly indicate project membership.
Supported detection should be narrow and deterministic.

Required rule for V1:

- sync only pages whose page properties contain `tags:: 프로젝트` or `tags:: [[프로젝트]]`
- free-text body mentions of `#프로젝트` do not make a page syncable by themselves

Reason:

- property-based matching is deterministic
- body-text matching is too easy to trigger accidentally
- sync scope must stay narrow in V1 to avoid touching unrelated pages

Migration note:

- if an existing graph only uses body-level `#프로젝트` markers, BUF should offer a one-time migration that writes page-level `tags:: 프로젝트` properties before enabling sync

### Stable Metadata

Each synced page must carry a stable project identity in the Markdown body or page properties.

There are two classes of properties:

- user-facing sync properties that should stay readable and editable in Logseq
- internal identity properties that should exist in Markdown but be hidden in the default UI when possible

### Page Property Contract

User-facing page properties:

- `tags:: 프로젝트`

Internal page properties:

- `brain_unfog_project_id`
- `reminder_list_external_id`
- optional `brain_unfog_page_name`
- optional `brain_unfog_page_uuid` once block/page UUID capture is implemented

### Task Property Contract

User-facing task properties:

- `date:: <date-or-datetime>`
- `duration:: <minutes>`
- `repeat:: <repeat-rule>`

Internal task properties:

- `brain_unfog_task_id`
- `reminder_external_id`
- `calendar_event_external_id` when applicable
- Logseq block UUID once captured

The practical rule is:

- if a user should be able to read and edit it in Logseq, keep it as a visible property
- if BUF only needs it for identity and sync linkage, keep it as an internal property

### Task Block Contract

V1 should not infer sync-critical schedule state from arbitrary prose.
Synced task blocks need an app-managed property contract.

Non-task bullets are not part of the reminders sync surface.

Required:

- TODO state from the Logseq task marker
- `brain_unfog_task_id:: <uuid>`

User-facing optional properties:

- `date:: <date-or-datetime>`
- `duration:: <int-minutes>`
- `repeat:: <repeat-rule>`

Internal optional properties:

- `reminder_external_id:: <string>`
- `calendar_event_external_id:: <string>`

Reason:

- prose parsing is too ambiguous for reliable round-trip sync
- explicit properties let BUF update only owned metadata while preserving user text
- deterministic properties make conflict resolution tractable

Why this is required:

- titles can change
- page names can be renamed
- task order can change
- a title-only match is not safe for bidirectional sync

### Property Visibility Strategy

Internal identity properties should be hidden in Logseq's default UI when the current client supports property-level hiding.

Examples:

- `brain_unfog_project_id`
- `reminder_list_external_id`
- `brain_unfog_task_id`
- `reminder_external_id`
- `calendar_event_external_id`

User-facing scheduling properties should remain visible:

- `date`
- `duration`
- `repeat`

Important limitation:

- hidden does not mean protected
- hidden properties can still be revealed in some views and actions
- raw Markdown still contains the values
- a user can still delete or edit them and break linkage

Therefore BUF must treat hidden properties as convenience only, not as an integrity boundary.
The sync engine must be able to detect missing or corrupted internal identifiers and repair or rebind them during reconciliation.

Configuration note:

- do not depend on legacy graph-wide hide settings for correctness
- use per-property UI hiding where available
- keep the sync engine correct even when no hiding support exists

### File Naming

Do not reuse `ObsidianProjectNoteStore` as the final Logseq page store.

Reason:

- `ObsidianProjectNoteStore` canonicalizes to `UUID.md`
- Logseq stores pages by title-derived filenames and graph filename format

Instead:

- create a dedicated `LogseqProjectPageStore`
- keep only the atomic write, temp file, backup, and recovery patterns if they are reusable
- write only to pages already marked with BUF-owned metadata or pages explicitly created by BUF
- preserve user-authored text and minimize reformatting outside app-managed properties

## Navigation Model

Project selection in BUF should stop opening the inspector as the primary workflow.

New primary behavior:

- timeline project click -> open project page in Logseq
- schedule project click -> open project page in Logseq
- sidebar project click -> open project page in Logseq
- task reveal actions open the owning project page first

Implementation anchor points:

- `import/BUF/Features/Workspace/MainWorkspacePanels.swift`
- `import/BUF/Features/Workspace/MainWorkspaceActions.swift`
- `import/BUF/Features/Workspace/MainWorkspaceSidebar.swift`
- `import/BUF/Features/Timeline/TimelineBoardActions.swift`

Keep `selectedProjectID` for local selection state and visual highlight.
Do not rely on `inspectorSelection` for the main flow.

V1 navigation target:

- open page by page name using `logseq://graph/<graph>?page=<page>`

V2 navigation target:

- open exact task block using `?block-id=<uuid>`

## Reminders Sync Design

### Mapping

The reminders mapping is:

- one Logseq project page = one BUF project = one Apple Reminders list
- one Logseq task block under that page = one BUF task = one `EKReminder`
- non-task bullets under that page have no Apple Reminders counterpart

Expected field mapping:

- page title <-> project title
- task text <-> reminder title
- `TODO` or open state <-> incomplete reminder
- `DONE` state <-> completed reminder
- due date <-> reminder due date
- recurrence property <-> reminder recurrence rule
- note body or block body <-> reminder notes
- priority if present <-> reminder priority where practical

### Structure Rule

Logseq task order and nesting are not projected into Apple Reminders.
For reminders sync, a project page is flattened into a list of task items.

That means:

- Logseq page title syncs with the Reminders list title
- Logseq task blocks sync with reminder items
- plain bullets stay only in Logseq
- task nesting stays only in Logseq
- task order stays only in Logseq

This is intentional, not a temporary limitation.
The Reminders side is a flat operational projection of the richer Logseq page.

### Direction

Reminders sync is bidirectional.

Examples:

- create task in Logseq -> create reminder in Apple Reminders
- complete reminder in Apple Reminders -> mark Logseq task as done
- rename task in Logseq -> update reminder title
- change due date in Apple Reminders -> update BUF task and write back to Logseq

If a nested Logseq task is synced, it still becomes a flat reminder item in the owning list.
Its original nesting context remains only in Logseq.

### Identity

The primary remote key is the reminder external identifier already modeled on `TaskItem`.
Task title matching must not be used as the main identity rule.

### Conflict Policy

Use field-level policy, not whole-object overwrite.

V1 rules:

- completion state prefers the latest authoritative change by modification time
- title and due date use last-writer-wins with conflict logging
- note body should preserve a conflict excerpt if automatic merge is unsafe
- deletes should be soft and require explicit matching rules, not immediate blind propagation

Existing alignment points already exist in:

- `import/BUF/Services/ReminderSyncHardening.swift`
- `import/BUF/Services/ReminderConflictPolicy.swift`
- `import/BUF/App/OutlinerReminderSyncCoordinator.swift`

## Calendar Sync Design

### Core Rule

Calendar sync is not the same as reminders sync.
V1 must separate owned events from foreign events.

### Owned Calendar

BUF should create and manage one dedicated Apple Calendar for schedule writeback.

Example:

- `BUF Schedule`

Only events in this owned calendar participate in full bidirectional write sync.

### Foreign Calendars

User calendars that BUF does not own are read-only overlays in the schedule view.

That means:

- show them in schedule projection
- do not rewrite them
- do not attach BUF task identity to them by default

This reduces the risk of damaging existing personal or work calendar data.

### Event Creation Rule

Not every task should become a calendar event.

V1 event creation should be limited to tasks that have:

- explicit scheduled time
- explicit duration

This matches existing fields already present on `TaskItem`:

- `scheduleHasExplicitTime`
- `scheduledDurationMinutes`

Implication:

- due-date-only tasks remain reminders-first items
- they can still appear as schedule hints inside BUF
- they do not automatically create editable Calendar events in V1

### Direction

Owned calendar events sync bidirectionally.

Examples:

- drag a scheduled task in BUF -> update `EKEvent` and write normalized time back to Logseq
- move the owned event in Calendar.app -> update BUF task timing and write back to Logseq

### Identity

Calendar event identity must be stored explicitly on the BUF side and in Logseq metadata when a task is calendar-backed.

Required key:

- `calendar_event_external_id`

## Write Ordering

To reduce loops and duplicate churn, writes should be ordered:

1. apply incoming delta into BUF model
2. stamp sync metadata and debounce fan-out
3. write only the normalized diff to other targets
4. ignore echo events that carry the same known external identifier and modification stamp

BUF should avoid naive full-export-on-every-change behavior.
Per-project and per-task diff fan-out is required.

## Bootstrap Policy

First connection is the highest-risk sync moment because it can create duplicates.

V1 bootstrap rules:

1. import project pages from Logseq into BUF first
2. bind to existing Reminder and Calendar objects only when stable BUF metadata already exists
3. create missing Reminder lists, Reminder items, and owned Calendar events only after import completes
4. never delete unmatched remote objects during first sync
5. never rewrite unowned Logseq pages during first sync

Implications:

- Logseq acts as the seeding source for project scope
- existing Apple data is only linked if identity markers match
- ambiguous remote items stay untouched until explicitly claimed
- Reminders import creates or updates only synced task items, not free-form Logseq bullets or structure

## Conflict and Recovery

Conflicts are expected.
The system should record them instead of hiding them.

Minimum V1 behavior:

- record last sync time
- record last error
- record conflict log entries for field collisions
- preserve local data if remote merge is unsafe
- avoid destructive delete propagation without identity confirmation

Existing persistence anchors for this already exist in `SyncState` and `ConflictLog`.

## Implementation Phases

### Phase 1: Replace Inspector-First Navigation

- add `LogseqDeepLinkService`
- route project selection to Logseq page opening
- keep inspector code present but no longer primary

### Phase 2: Add Logseq Graph Configuration

- configure graph root path in BUF
- store graph name for deep links
- detect graph filename format requirements

### Phase 3: Build Logseq Page Store

- add `LogseqProjectPageStore`
- support page read, page write, atomic replace, and metadata extraction
- support project page detection and stable ID extraction

### Phase 4: Reminders Sync

- connect Logseq project page parsing into existing reminder sync pipeline
- support page create, task create, rename, complete, due date, and recurrence flows
- persist `brain_unfog_project_id` and `brain_unfog_task_id`

### Phase 5: Calendar Sync

- create BUF-owned calendar
- project explicit-time tasks into owned `EKEvent`s
- import owned event edits back into BUF and Logseq
- render foreign calendars as read-only overlays

### Phase 6: Exact Task Deep Links

- capture Logseq block UUIDs
- switch task reveal actions from page-only deep link to block deep link where available

## Consequences

Positive:

- preserves the valuable native BUF UI and EventKit work
- avoids building a macOS helper plus Logseq plugin bridge
- keeps Apple integrations in the platform that already supports them
- allows Logseq to stay the user's visible graph and Markdown editor

Negative:

- sync complexity moves into BUF
- Logseq file semantics must be handled carefully
- rename, block UUID, and filename format edge cases must be solved explicitly
- this only supports file graphs, not DB graphs

## Open Questions

- where to persist Logseq graph name and graph path in app settings
- whether the current `Project.calendarIdentifier` naming should be split to avoid reminder-list versus event-calendar ambiguity
- how aggressively to propagate deletes across Logseq, Reminders, and Calendar
- whether all-day scheduled tasks should ever create owned calendar events in V1

## Rejected Alternative

Rewrite BUF as a Logseq plugin.

Rejected because:

- native EventKit access would still require a helper
- SwiftUI schedule and timeline UI would need a second implementation in web tech
- current code reuse would drop sharply
- the user's real requirement is synced data and page navigation, not plugin packaging
