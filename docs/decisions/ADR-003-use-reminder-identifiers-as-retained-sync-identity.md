# ADR-003: Use Reminder identifiers as retained sync identity

## Status

Accepted

## Date

2026-04-24

## Context

The retained app is now centered on Apple Reminders as the task source:

- Apple Reminders list = Logseq page.
- Apple Reminder item = Logseq TODO/DONE task block.
- Brain Unfog provides Timeline/Schedule views and sync orchestration.

Earlier plans stored separate Brain Unfog identifiers in Markdown:

- `brain_unfog_project_id::`
- `brain_unfog_task_id::`

Those identifiers came from the older BUF-owned model. In the retained product, they duplicate the stable identifiers already available from Apple Reminders and make first sync, repair, and user-visible Markdown noisier than necessary.

## Decision

Use Apple Reminders identifiers as the persisted retained sync identity.

Persisted Logseq page identity:

- `reminder_list_external_id::`

Persisted Logseq task identity:

- `reminder_external_id::`

User-editable task scheduling properties:

- `date::`
- `duration::`
- `repeat::`

Brain Unfog may derive internal runtime UUIDs from Reminder external identifiers for SwiftUI selection, dictionaries, tests, and view models. Those derived IDs are implementation details and must not be written to Logseq Markdown as sync identity.

## Rules

- A Reminder-backed page is identified by `reminder_list_external_id::`.
- A Reminder-backed task is identified by `reminder_external_id::`.
- `brain_unfog_project_id::` and `brain_unfog_task_id::` are legacy properties, not part of the current retained sync contract.
- Existing legacy `brain_unfog_*` properties may be tolerated during migration, but new imports and normal writes should not create them.
- Logseq TODO/DONE blocks without `reminder_external_id::` on ordinary pages are Logseq-only.
- Logseq TODO/DONE blocks without `reminder_external_id::` on Reminders-backed project pages automatically create or bind Apple Reminder items, then receive `reminder_external_id::`.
- `ADR-004` defines when a project-tagged Logseq page becomes Reminders-backed.
- Title-only matching is not identity.

## Consequences

- First sync from Reminders creates cleaner Logseq Markdown.
- Duplicate identity repair focuses on duplicate Reminder external identifiers.
- Timeline/Schedule can derive stable app IDs from Reminder IDs without persisting separate app IDs.
- Existing code that requires `brain_unfog_task_id::` before rendering Timeline/Schedule must be changed.
- Existing code that writes `brain_unfog_*` properties should be treated as legacy compatibility and removed or narrowed after the Reminder-first bootstrap path is stable.

## Supersedes

This ADR supersedes the Brain-Unfog-owned Markdown identity parts of `ADR-001`, `PLAN-001`, `PLAN-002`, `PLAN-004`, and related task packets.
