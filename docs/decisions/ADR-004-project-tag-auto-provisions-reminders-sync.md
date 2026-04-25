# ADR-004: Auto-provision Reminders sync from Logseq project pages

## Status

Superseded for current execution by
`ADR-005-obsidian-vault-retained-architecture.md`.

This ADR remains historical background for project-tag auto-provisioning, but
the active user-facing Markdown surface is now Obsidian, not Logseq.

## Date

2026-04-24

## Context

The retained product must let Logseq remain the project/outliner surface.
When a user marks a Logseq page as a project, the app should connect that page to Apple Reminders without requiring a separate manual adoption step.

Ordinary Logseq pages and TODOs should remain untouched.
The automatic behavior only applies to project pages.

## Decision

`tags:: 프로젝트` or `tags:: [[프로젝트]]` on a Logseq page is an automatic sync trigger.

When a tagged page does not have `reminder_list_external_id::`, Brain Unfog creates an Apple Reminders list using the page title and writes the created list identifier back to the page as `reminder_list_external_id::`.

When a TODO/DONE block exists inside a Reminders-backed page and does not have `reminder_external_id::`, Brain Unfog creates an Apple Reminder item in that page's linked list and writes the created reminder identifier back to the task block as `reminder_external_id::`.

Pages without project tag and without `reminder_list_external_id::` remain Logseq-only.
TODO/DONE blocks on those ordinary pages remain Logseq-only.

## Rules

- Page title is the Reminders list title.
- Task text is the Reminders item title.
- TODO/DONE state syncs with Reminder completion.
- `date::` syncs with Reminder due date or due date-time.
- `repeat::` syncs with Reminder recurrence where supported.
- `duration::` stays in Logseq/app state for Schedule block length.
- Bullet order, nesting, and non-task bullets remain Logseq-only.
- If creating the Reminders list or item fails, the Logseq page/task remains unlinked and is reported as sync-needed or repair-needed.
- Title-only matching to an existing Reminders list/item is not identity. Existing remote objects are bound only through explicit identifiers or deterministic repair rules.

## Consequences

- Adding `tags:: 프로젝트` is enough to create the matching Reminders list.
- Adding a TODO inside a synced project page is enough to create the matching Reminder item.
- The app must watch Logseq page changes, Reminders changes, and run periodic repair because either side can be edited.
- The first implementation must add tests for project-tag auto-provisioning and task auto-provisioning before enabling broad delete cleanup.

## Related

- `ADR-003-use-reminder-identifiers-as-retained-sync-identity.md`
- `ADR-002-reminder-backed-schedule-blocks-no-calendar-event-mirroring.md`
