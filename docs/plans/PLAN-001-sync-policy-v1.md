# PLAN-001: V1 sync policy and implementation plan

## Status
Draft

Superseded for current execution by `docs/plans/PLAN-005-logseq-reminders-calendar-sync-completion.md`.
This document remains policy background, but its older Logseq-first bootstrap wording, Brain-Unfog-owned Markdown identity wording, and task-to-Calendar event write wording must not override `PLAN-005`, ADR-002, or ADR-003.

## Date
2026-04-23

## Related Decision

- `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
- `docs/decisions/ADR-002-reminder-backed-schedule-blocks-no-calendar-event-mirroring.md`
- `docs/decisions/ADR-003-use-reminder-identifiers-as-retained-sync-identity.md`
- `docs/decisions/ADR-004-project-tag-auto-provisions-reminders-sync.md`

## Goal

Ship a controlled V1 sync system for:

- `BUF <-> Logseq file graph`
- `BUF <-> Apple Reminders`
- `Apple Calendar -> BUF read-only Schedule overlay`

without turning sync into a full mirror system.

## Audit Result

The sync design is viable only if V1 stays intentionally asymmetric and narrow.

The main risk points are:

- rename loops
- duplicate creation during first sync
- destructive delete propagation
- model mismatch between Logseq structure and Reminders flat lists
- user edits to hidden identity properties
- watcher misses and remote callback ordering

The policy below keeps those risks bounded by reducing symmetry and making BUF the only reconciliation hub.

## V1 Boundaries

### In Scope

- project page title syncs with BUF project title
- BUF project title syncs with Apple Reminders list title
- Logseq task blocks sync with Apple Reminders items
- Logseq `date::`, `duration::`, `repeat::` sync with BUF scheduling fields
- Reminder-backed tasks render in Schedule with Logseq/app-owned duration blocks
- Apple Calendar events render as read-only overlays in BUF
- project selection in BUF opens the corresponding Logseq page

### Out of Scope

- Logseq plugin implementation
- DB graph support
- mirroring Logseq bullet order to Reminders
- mirroring Logseq nesting to Reminders
- creating, updating, or deleting Apple Calendar events from Reminder-backed tasks
- automatic sync into arbitrary user calendars
- automatic destructive delete propagation across all sides
- exact task-block deep link on day one

## Canonical Mapping

### Project Layer

- `BUF Project.title`
- `Logseq project page title`
- `Apple Reminders list title`

These represent the same user-facing name and must converge.

### Task Layer

- `Logseq task block`
- `BUF TaskItem`
- `Apple reminder`

These represent the same actionable item.

### Structure Rule

The Logseq model is richer than the Reminders model.

- Logseq page = reminder list
- Logseq task = reminder item
- plain bullet = Logseq-only
- task nesting = Logseq-only
- task ordering = Logseq-only

BUF must flatten Logseq tasks when projecting to Reminders.

## Property Schema

### Visible User Properties

Page:

- `tags:: 프로젝트`

Task:

- `date:: <date-or-datetime>`
- `duration:: <minutes>`
- `repeat:: <repeat-rule>`

These are user-editable and must round-trip through Logseq.

### Hidden Internal Properties

Page:

- `reminder_list_external_id:: <string>`

Task:

- `reminder_external_id:: <string>`

- `brain_unfog_project_id::` and `brain_unfog_task_id::` may exist from earlier prototypes, but they are not part of the current retained sync contract.
- Current retained sync derives app runtime IDs from Reminder external identifiers instead of writing Brain Unfog IDs to Markdown.
- `calendar_event_external_id::` may exist from earlier prototypes, but it is not part of the current retained task sync contract.

These are linkage properties. They should be hidden in Logseq UI when the current client supports property hiding, but the system must remain correct even if they are visible.

### Canonical Property Grammar

V1 must treat shared user-facing properties as structured values, not free-form text.

- `date::`
  - allowed forms: `YYYY-MM-DD` or `YYYY-MM-DD HH:MM`
  - stored and interpreted in graph-local time
  - date-only means Reminder due date and day-level Schedule placement
  - datetime means Reminder due date with explicit time and exact Schedule placement
- `duration::`
  - allowed form: positive integer minutes
  - examples: `30`, `45`, `90`
  - used by the Schedule view as the task block length
  - remains in Logseq/app schedule state because Apple Reminders has no native duration field
- `repeat::`
  - V1 allowed values: `daily`, `weekly`, `monthly`, `yearly`
  - free-form recurrence strings are out of scope for V1

Invalid property values never sync through blindly.
They enter validation or repair flow inside BUF.

## Source of Truth Policy

This is a multi-writer system with one hub.

- BUF is the reconciliation hub
- Logseq is a user-editable content source
- Reminders is a user-editable task source
- Apple Calendar is a read-only schedule context source

Interpretation:

- identity is anchored in BUF IDs plus remote external IDs
- user-facing field edits may originate from any synced client
- conflict policy is applied only in BUF

## Detection Policy

V1 must combine three mechanisms:

- file-system watch for Logseq graph changes
- EventKit refresh and callbacks for Reminders and Calendar
- periodic repair scan

Reason:

- file watchers are not reliable enough on their own
- EventKit updates can arrive late or out of order
- periodic repair is required for eventual convergence

## Project Scope Ownership Policy

Project scope is controlled by both visible project tagging and stable internal identity.

Rules:

- a page enters project sync scope when it has `tags:: 프로젝트` or `tags:: [[프로젝트]]`
- a project-tagged page without `reminder_list_external_id::` automatically creates a Reminders list and records the new list identifier
- a page already carrying `reminder_list_external_id::` is treated as a managed page even if the tag is later removed
- removing the tag from a managed page does not silently unsync it
- tag removal from a managed page enters explicit repair or opt-out flow

Reason:

- otherwise a page can fall out of import scope while still carrying active remote linkage

## Bootstrap Policy

First sync is import-first, not merge-everything-first.

### Rules

1. Import existing Reminders lists into Logseq pages first.
2. Scan Logseq pages with `tags:: 프로젝트` or `tags:: [[프로젝트]]`.
3. Create missing Reminders lists for project-tagged Logseq pages without `reminder_list_external_id::`.
4. Create missing Reminder items for TODO/DONE blocks on Reminders-backed pages without `reminder_external_id::`.
5. Bind to existing reminders only when stable Reminder identifiers already match or deterministic repair criteria apply.
6. Load Apple Calendar overlay only after Reminders/Logseq task projection is stable.
7. Never delete unmatched remote objects during first sync.
8. Never rewrite ordinary untagged Logseq pages during first sync.

### Consequence

V1 seeds from existing Reminders first, then auto-provisions project-tagged Logseq pages into Reminders.
Ordinary Logseq pages and TODOs remain untouched.

## Rename Policy

### Project Rename

Project rename is a shared user-facing field.

If the project name changes in BUF or Reminders:

- BUF updates the project title
- BUF renames the Logseq page title
- BUF updates the Logseq filename as required by Logseq filename rules
- internal identity properties stay unchanged

### Loop Prevention

Every rename write must carry enough local sync context to suppress immediate echo handling.

Minimum requirement:

- perform rename as a transaction keyed by stable project identity, not by title alone
- remember both outbound title and outbound file target
- treat `old file disappeared + new file appeared` as the same managed rename when the stable project identity matches
- ignore the same rename when it comes back unchanged with the same linked identity

## Task Field Policy

### Shared Editable Fields

- title
- completion state
- `date::`
- `duration::`
- `repeat::`

Field fan-out in V1:

- `title` syncs across Logseq, BUF, and Reminders
- `completion state` syncs across Logseq, BUF, and Reminders
- `date::` is the shared task time field and syncs to Reminders due date/date-time
- `duration::` stays in Logseq/app state and controls Schedule task block length
- `repeat::` syncs to Reminders only in V1

### Logseq-Only Fields

- plain bullets
- nesting
- ordering
- surrounding prose structure

### Calendar Projection Rule

The Schedule view is a project-planning surface built from Reminder-backed task blocks.
Apple Calendar events are read-only context. Reminder-backed tasks must never be mirrored into Apple Calendar events.

V1 rule:

- show Reminder-backed tasks with `date::` and optional `duration::` in Schedule
- use `duration::` as the Schedule task block length
- use a 15 minute default Schedule block when a timed task has no valid `duration::`
- do not create, update, or delete Apple Calendar events from Reminder-backed tasks
- do not create recurring calendar series from `repeat::` in V1 unless recurrence support is designed explicitly

Due-date-only tasks remain Reminder-backed task blocks and can still appear in Schedule as day-level work.

## Conflict Policy

### Required Rules

- identity mismatch never merges by title alone when an internal ID exists
- title, date, duration, and repeat use last-writer-wins with conflict logging
- completion state prefers the latest authoritative change by modification time
- note body merges conservatively and records conflict excerpts when unsafe
- delete is never blindly propagated in V1

### Repair Cases

The engine must detect and handle:

- missing remote external IDs
- orphaned reminders
- orphaned calendar events
- duplicate reminders linked to one task
- duplicate Logseq pages carrying the same `reminder_list_external_id::`
- duplicate Logseq tasks carrying the same `reminder_external_id::`

Repair should prefer rebinding over creating new objects when identity can be recovered safely.

## Delete Policy

V1 uses soft handling.

- deleting a Logseq task does not immediately hard-delete a reminder unless identity and intent are unambiguous
- deleting a reminder does not immediately remove surrounding Logseq structure
- project deletion is never full hard-delete propagation in V1

Practical default:

- mark conflict or orphan state
- surface the mismatch for repair
- only hard-delete automatically for BUF-owned objects with clear lineage

## Hidden Property Policy

Hidden internal properties are not a safety boundary.

- hidden properties may still appear in some Logseq views
- raw Markdown always contains them
- a user can still edit or remove them

Therefore:

- hiding is for noise reduction only
- sync correctness must not depend on hiding
- missing or corrupted hidden properties must be repairable

## Echo Suppression Policy

Every outbound sync write must be tracked long enough to suppress its own echo.

V1 minimum:

- per-project outbound write fingerprint
- per-task outbound write fingerprint
- debounce writes by entity
- ignore unchanged round-trips for the same linked identity

Without this, rename and property-update loops will appear immediately.

## Verification Checklist

### Bootstrap

- importing an existing Logseq project graph does not create duplicate reminders
- importing an existing reminder list without IDs does not hijack unrelated Logseq pages
- adding `tags:: 프로젝트` to a Logseq page creates a Reminders list and writes `reminder_list_external_id::`
- adding TODO/DONE inside a Reminders-backed page creates a Reminder item and writes `reminder_external_id::`
- legacy body-level `#프로젝트` pages can be migrated into property-based scope before sync begins

### Rename

- renaming a project in BUF renames the Logseq page once
- the rename does not loop back and trigger a second rename

### Reminder Fields

- editing `date::` in Logseq updates the linked reminder task
- editing `repeat::` in Logseq updates the linked reminder task
- completing a reminder updates the Logseq task marker

### Calendar

- timed Reminder-backed tasks render as Schedule blocks with Logseq/app-owned duration
- Calendar events remain read-only overlays
- Reminder-backed tasks never create, update, or delete Calendar events

### Repair

- removing `reminder_external_id::` from a task does not crash sync
- duplicate remote reminder detection enters repair flow instead of duplicating again
- duplicate local `reminder_external_id::` detection enters repair flow before writeback
- removing `tags:: 프로젝트` from a managed page enters repair or opt-out flow instead of silently dropping scope

## Implementation Order

### Slice 1: Sync plumbing guardrails

- add outbound write fingerprints
- add periodic repair pass
- add sync logging for project and task entities

Exit criteria:

- echo suppression exists before any title or property sync is enabled

### Slice 2: Logseq project scope and page open

- detect project pages by page property
- add one-time migration path for legacy body-level `#프로젝트` pages
- configure graph root and graph name
- open pages from BUF with deep links

Exit criteria:

- project click opens the right Logseq page

### Slice 3: Property schema and page store

- create `LogseqProjectPageStore`
- persist visible and hidden properties separately by role
- preserve user-authored text outside managed properties

Exit criteria:

- BUF can read and write a project page without reformatting unrelated content

### Slice 4: Reminder sync

- bootstrap from Logseq pages
- create and bind reminder lists
- create and bind reminder items from task blocks
- auto-provision project-tagged pages and project-page tasks
- round-trip title, completion, `date::`, and `repeat::`

Exit criteria:

- page title and task fields converge between Logseq and Reminders without duplicate creation

### Slice 5: Calendar sync

- read Apple Calendar events as Schedule overlays
- keep Reminder-backed task blocks separate from Calendar events
- never project tasks into Calendar events
- keep overlay calendar interactions read-only

Exit criteria:

- Schedule shows Reminder-backed task blocks and Calendar overlays without any task-to-Calendar writes

### Slice 6: Repair and hardening

- orphan detection
- duplicate detection
- repair UI or repair command path

Exit criteria:

- common linkage damage can be recovered without manual database surgery

## Risks to Recheck Before Implementation

- whether `Project.calendarIdentifier` should be split into reminder-list and calendar-event ownership concepts
- whether page rename should be blocked while a project is under active repair
- how aggressive the periodic repair pass should be on large graphs

## Definition of Done for V1

V1 is done when:

- project pages are the only Logseq sync surface
- reminders round-trip for title, completion, `date::`, and `repeat::`
- Reminder-backed task blocks use `date::` and `duration::` in Schedule without creating Calendar events
- no duplicate creation occurs in the tested bootstrap paths
- rename loops are suppressed
- damage to hidden IDs is recoverable
