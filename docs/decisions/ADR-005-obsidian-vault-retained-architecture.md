# ADR-005: Use Obsidian vault as retained project store

## Status

Accepted

## Date

2026-04-25

## Context

The retained Brain Unfog product is a native Timeline/Schedule companion for
Apple Reminders and Apple Calendar context. The previous retained architecture
used Logseq as the project/outliner/detail surface.

In real use, Logseq has shown unreliable behavior for this product direction:

- disk writes can trigger disruptive "modified on disk" conflict modals while
  the user is actively typing
- Logseq UI can lag or fail to reflect Markdown changes written by the app
- the app has to account for both Logseq files and Logseq's internal state
- sync correctness work is being spent on Logseq-specific behavior instead of
  the actual Reminders/Schedule workflow

The user workflow is now clearer:

- Brain Unfog is the primary day-planning and schedule workspace.
- Apple Reminders remains the portable task/list source.
- Obsidian should replace Logseq as the editable Markdown project surface.
- Apple Calendar remains a read-only contextual overlay.

## Decision

Migrate the retained project store from Logseq graph pages to an Obsidian vault.

This is not a full app rewrite. Brain Unfog keeps:

- Timeline view
- Schedule view
- Reminders permission and EventKit Reminder gateway work
- Calendar read-only overlay work
- retained sync baseline and merge policy concepts
- build/test/runtime harness

Brain Unfog replaces:

- Logseq graph setup
- Logseq `pages/` store
- Logseq helper plugin
- Logseq page filename codec
- Logseq task/property parser and renderer
- Logseq-specific watcher/deep-link/config code

## Data Contract

### Project/List

An Obsidian Markdown note represents a Reminders list.

An Obsidian note is in sync scope only when it is under `raw/projects/` and
either condition is true:

- frontmatter `tags` contains `프로젝트`
- frontmatter contains `reminder_list_external_id`

Sync-scoped project notes must live under `raw/projects/` inside the selected
vault. If `raw/projects/` does not exist, Brain Unfog creates it before writing
synced project notes.

Notes outside `raw/projects/` are not automatically adopted into Reminders sync
even if they contain `프로젝트` tags. This keeps vault scanning narrow and avoids
unexpectedly claiming unrelated Obsidian notes.

Persisted note identity:

```yaml
---
tags:
  - 프로젝트
reminder_list_external_id: 79892F48-5DCF-44B4-AE10-085188B563F9
---
```

Rules:

- Reminder list title is the user-facing project title.
- Obsidian note filename under `raw/projects/` is the user-facing project note
  name.
- Title-only matching is not identity.
- Brain Unfog may derive runtime UUIDs from Reminder identifiers, but must not
  write `brain_unfog_project_id` into Markdown.

### Task/Reminder

An Obsidian Markdown task represents a Reminder item.

Task syntax:

```md
- [ ] Task title ^buf-46B721BC
  %% brain-unfog: {"reminder_external_id":"46B721BC-6454-46AC-BEB9-C77ABE619619","date":"2026-04-25","time":"14:00","duration":15,"repeat":null} %%
  - child note
  - [ ] child task
```

Rules:

- `- [ ]` means incomplete Reminder task.
- `- [x]` means completed Reminder task.
- `reminder_external_id` is the persisted task identity.
- `date` is stored as `yyyy-mm-dd` and syncs with Reminder due date.
- `time` is optional `HH:mm` local time and syncs with Reminder due time when
  present.
- `repeat` syncs with Reminder recurrence where supported.
- `duration` is Obsidian/app-owned Schedule block length.
- A task with `date` and `time` but no valid `duration` renders as a 15 minute
  Schedule block.
- Brain Unfog must not write `brain_unfog_task_id` into Markdown.
- The optional Obsidian block id (`^buf-...`) is for open/focus navigation,
  not sync identity.

### Task Subtrees and Reminder Notes

Reminder notes and Obsidian task subtrees remain part of the retained contract.
The Obsidian workflow assumes an outliner plugin, so Brain Unfog treats the
task's nested subtree as meaningful project detail, not incidental Markdown.

When a synced task has child bullets, child tasks, or nested prose, Brain Unfog
preserves that subtree in Obsidian and syncs the whole subtree into the Apple
Reminder note. The Reminder note is therefore the portable representation of the
task detail subtree.

If a child task needs stable tracking inside the Reminder note, the note uses
the existing `t:<reminder-external-id>` marker strategy so later Reminder-note
edits can be reconciled back to the correct child task position.

Brain Unfog must not collapse the subtree into a lossy summary during normal
sync. If a Reminder note edit cannot be parsed back into the subtree safely, the
task enters repair-needed state instead of overwriting the Obsidian subtree.

This rule survives the Logseq to Obsidian migration.

### Calendar

Reminder-backed task blocks are not Apple Calendar events.

Rules from `ADR-002` remain in force:

- `date` maps to a date-only Reminder due date.
- `date` plus `time` maps to a timed Reminder due date.
- `duration` controls Brain Unfog Schedule block length only.
- Brain Unfog must not create, update, or delete Apple Calendar events from
  Reminder-backed tasks.
- Apple Calendar events are read-only Schedule overlays.

## Obsidian Integration

Brain Unfog must work even when Obsidian is not open. The native app reads
`raw/projects/*.md` directly as the baseline source for Timeline/Schedule and
for sync decisions. The Obsidian helper plugin is an enhancement for open
Obsidian sessions, not a hard runtime dependency.

Brain Unfog should use the Obsidian helper plugin for operations that need the
Obsidian app to stay coherent while it is open.

The helper plugin owns:

- vault change observation after Obsidian layout is ready
- safe file edits through Obsidian Vault APIs
- task focus/highlight from Brain Unfog task clicks
- date/time/duration task UI chips or popovers, if implemented

When the helper plugin is available, native app writes should go through the
helper so Obsidian sees the edit as an Obsidian edit. The plugin should prefer
`Vault.process()` for read-modify-write operations.

When the helper plugin is unavailable, the native app may use direct Markdown
file reads and writes against `raw/projects/` and must still render
Timeline/Schedule from the vault files. Direct writes require parser/renderer
and conflict guards. Direct writes are the expected path when Obsidian is
closed. If Obsidian may be open but the helper is unavailable, writes must use
hash/mtime baseline checks and fail closed when the file changed since the
command was prepared.

The helper plugin is desktop-focused for this app. Mobile support is not a
requirement for the native macOS app workflow.

The app may copy the helper plugin into the vault, but enabling it changes
Obsidian vault configuration and must be presented as an explicit setup action.

## Runtime Responsibility Split

Brain Unfog native app is the sync brain:

- owns Apple Reminders read/write
- owns Apple Calendar read-only overlay loading
- owns Timeline/Schedule state
- owns merge, delete, baseline, and repair decisions
- owns direct `raw/projects/*.md` reads when Obsidian is closed
- owns `.buf/` sidecar state

The Obsidian helper plugin is the vault-side agent:

- provides date, time, and duration input UI in Obsidian
- hides or renders Brain Unfog metadata comments as chips when possible
- observes Obsidian vault changes and sends lightweight invalidation hints
- applies app-computed patches through Obsidian Vault APIs when Obsidian is open
- opens, focuses, and highlights a task selected from Brain Unfog

The helper plugin must not become a second sync engine. It must not make
Reminders merge, delete, or repair decisions independently from the native app.

## Performance Policy

Brain Unfog must avoid work proportional to the whole vault during normal
typing.

Rules:

- Watch and scan `raw/projects/`, not the whole Obsidian vault.
- Treat helper events and file watcher events as invalidation hints, not as an
  instruction to run full sync immediately.
- Re-parse only changed project files when updating Timeline/Schedule.
- Keep hashes, mtimes, baselines, and repair state in `.buf/` so unchanged
  project files are skipped.
- Separate projection refresh from Reminders sync.
- Projection refresh may be fast and local, but Reminders writes should be
  coalesced behind an idle debounce.
- File-edit driven Reminders sync uses a 10 second idle debounce: repeated edits
  cancel the pending sync, and sync runs once after edits are quiet.
- Subtree note sync operates at task-subtree granularity and should not rewrite
  the whole project note unless a whole-note operation is explicitly required.

## App Sidecar Storage

Brain Unfog stores app-owned sidecar data under `<vault>/.buf/`, matching the
previous graph-local hidden-folder approach used with Logseq.

`.buf/` may contain sync baselines, deletion tombstones, bridge tokens, repair
state, and app runtime metadata. It must not be used as the only copy of
Reminder list/task identity; those identities must remain recoverable from the
Markdown project notes.

## Alternatives Considered

### Keep Logseq and keep patching sync behavior

Rejected. The current failures are not only bugs in Brain Unfog; they are also
friction from Logseq's file/UI/internal-state model. Continuing to patch this
keeps the project centered on Logseq-specific repair work.

### Rewrite the entire app

Rejected. Timeline, Schedule, permissions, Reminders gateway, and test harness
remain valuable. Rewriting everything would throw away working product surface
and slow the migration.

### Direct file writes only, no Obsidian helper plugin

Rejected as the primary architecture. Obsidian is file-first, so direct writes
are more viable than with Logseq, but task focus/highlight and lower-conflict
edits require a plugin path.

### Store all task metadata only in `.buf`

Rejected. A sidecar-only identity store makes recovery and portability worse.
Reminder identifiers must remain recoverable from the Markdown note itself.

## Consequences

- `ADR-003` remains valid, but "Logseq page/task" should be read as the
  retained Markdown page/task abstraction during migration.
- `ADR-004` is superseded for the user-facing project surface by this ADR:
  project-tag auto-provisioning applies to Obsidian notes, not Logseq pages.
- `PLAN-005` becomes historical background for sync policy, not the main
  execution plan.
- Obsidian parser/renderer fixtures must be implemented before runtime cutover.
- Logseq code must not be deleted until the Obsidian path passes build, test,
  fixture, and runtime gates.
- The helper plugin bridge transport must be proven in a spike before sync
  runtime depends on it.

## Sources

- Obsidian Vault API: `https://docs.obsidian.md/Plugins/Vault`
- Obsidian events: `https://docs.obsidian.md/Plugins/Events`
- Obsidian plugin load timing: `https://docs.obsidian.md/plugins/guides/load-time`
- Obsidian URI open note/block: `https://help.obsidian.md/uri`
- Obsidian block references: `https://help.obsidian.md/Linking%20notes%20and%20files/Internal%20links`
- Obsidian properties: `https://help.obsidian.md/properties`
- Obsidian comments and tasks: `https://help.obsidian.md/syntax`
