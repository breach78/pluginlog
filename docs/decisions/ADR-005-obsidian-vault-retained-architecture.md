# ADR-005: Use app-owned storage for retained project state

## Status

Accepted. This decision supersedes the earlier Obsidian project-markdown runtime
storage design.

## Date

2026-04-25, revised 2026-05-11

## Context

Brain Unfog is a native Timeline/Schedule companion for Apple Reminders and
Apple Calendar context. Earlier retained architecture work used Obsidian project
Markdown files as the runtime project/task store after moving away from Logseq.
In practice, that kept the app dependent on filesystem sync behavior and made
local app-owned values such as duration, project stage, project order, and task
order too easy to lose during Reminders refresh or app relaunch.

The current product contract is clearer:

- Apple Reminders is the portable source for list/task identity and Reminder-owned
  fields.
- Brain Unfog owns the retained workspace state that Reminders cannot store.
- Apple Calendar remains a contextual schedule source.
- The selected vault is still useful for journals, attachments, and app-local
  container placement, but it is not the project/task runtime database.

## Decision

Project/task runtime state is stored in app-owned SQLite under the selected
vault's `.buf/` sidecar container. Runtime commands, projections, and refreshes
must use Reminders plus app-owned SQLite as the source of truth.

The vault may be used only for:

- selecting the workspace root and calculating the app container location
- `.buf/` app-owned SQLite and sidecar files
- `raw/journals` journal Markdown files
- allowed attachment/assets paths, such as `raw/assets`
- opening an existing vault file in Obsidian when explicitly requested

The vault must not be used at runtime for:

- project/task storage through project Markdown files
- project/task projection reads from legacy project Markdown files
- project/task command writes to legacy project Markdown files
- project Markdown directory watching
- Obsidian Markdown task-line to Reminders two-way sync
- archive, outline, or baseline logic that treats project Markdown as the
  runtime store

Legacy project Markdown migration is allowed only as a one-shot migration path.
It must be metadata-gated before reading legacy project files, and it must not be
called from normal Reminders import/refresh persistence.

## Data Ownership

### Reminder-owned fields

These values may be imported from, or written back to, Apple Reminders:

- title
- note text
- due date
- explicit due time
- completion state and completion date
- priority
- recurrence
- attachment count or equivalent Reminder metadata

### App-owned fields

These values must be preserved in app-owned storage and must not be cleared by a
Reminders refresh/import:

- task duration
- project stage
- project order
- task order
- project note storage metadata
- completed recurring occurrence records
- local bridge, tombstone, repair, and sync-baseline records

## Runtime Responsibility Split

Brain Unfog native app owns:

- Apple Reminders read/write through the Reminder gateway
- Apple Calendar contextual overlay loading
- Timeline, Schedule, Month, and detail-pane projections
- project/task mutation commands
- app-owned SQLite state under `.buf/`
- journal files under `raw/journals`
- attachment files under allowed asset paths

Obsidian is not a runtime sync engine for project/task state. If an Obsidian
helper or file-opening flow exists, it may help the user open or inspect allowed
vault files, but it must not perform project/task merge, delete, repair, or sync
decisions independently from the native app.

## Migration Policy

Legacy project Markdown migration code may exist only behind explicit
`LegacyObsidian...Migration` entry points. The migration runner must check
app-owned completion metadata before enumerating legacy project files. Once the
metadata says migration is complete, normal app launch, setup, refresh, and
manual import must not enumerate or write legacy project files.

Migration is a compatibility bridge, not a runtime storage strategy.

## Performance Policy

Normal app use must avoid filesystem work proportional to the vault contents.
Project/task views should be rebuilt from Reminders snapshots plus app-owned
SQLite data. Journal and attachment operations should touch only their explicit
paths.

This keeps app launch, Reminders refresh, and view projection independent from
Obsidian project Markdown file counts and iCloud file availability.

## Consequences

This decision removes the ambiguity that caused app-owned values to be restored
from the wrong place or overwritten by incomplete imports. It also makes future
runtime boundary tests straightforward: App and Feature code must not call
legacy Obsidian project Markdown stores, and command facades must expose
app-owned neutral types rather than Markdown snapshot types.
