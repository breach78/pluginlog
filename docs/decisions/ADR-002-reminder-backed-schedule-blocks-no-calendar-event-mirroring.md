# ADR-002: Use Reminder-backed Schedule blocks without Calendar event mirroring

## Status

Accepted

## Date

2026-04-24

## Context

The retained product is a project-management companion for Logseq and Apple Reminders.
Its Schedule view exists because Apple Reminders can store due dates and due times, but cannot store task duration or render tasks as planning blocks.

Earlier planning described a BUF-owned Apple Calendar that would mirror exact timed tasks into Calendar events.
That direction is rejected for the retained product because it turns task planning into Calendar event management and adds unnecessary sync loops.

## Decision

Reminder-backed task blocks are the primary Schedule objects.

The mapping is:

- Apple Reminders list = Logseq page.
- Apple Reminder item = Logseq TODO/DONE task block.
- `date:: YYYY-MM-DD` = date-only Reminder due date and day-level Schedule work.
- `date:: YYYY-MM-DD HH:MM` = timed Reminder due date and timed Schedule task block.
- `duration:: <minutes>` = Logseq/app-owned Schedule block length.
- Missing `duration::` on a timed task uses a 15 minute default in Schedule.
- `repeat::` syncs with Apple Reminders recurrence where supported.

Brain Unfog must not create, update, or delete Apple Calendar events from Reminder-backed tasks.
Apple Calendar events are read-only Schedule overlays for context.

## Consequences

- Reminder identity is defined separately in `ADR-003-use-reminder-identifiers-as-retained-sync-identity.md`.
- `calendar_event_external_id::` is not part of the current retained task sync contract.
- Existing task-to-Calendar bridge code is legacy and should be disabled or removed from retained task actions.
- Calendar permission is still useful for read-only overlays, but Calendar write permission is not required for Reminder task scheduling.
- Schedule edits update Logseq and Apple Reminders, not Apple Calendar events.
- Duration survives because it is stored in Logseq/app state, not in Apple Reminders.

## Supersedes

This ADR supersedes the task-to-BUF-owned-Calendar-event parts of `ADR-001`, `PLAN-001`, `PLAN-002`, `PLAN-004`, and related task packets.
