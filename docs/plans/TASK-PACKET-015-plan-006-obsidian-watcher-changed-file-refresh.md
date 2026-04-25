# TASK-PACKET-015: Obsidian Watcher And Changed-File Projection Refresh

Status: Draft for implementation

## Goal

Add the runtime infrastructure that watches `<vault>/raw/projects/*.md`, coalesces Obsidian edits with a 10 second idle debounce, and refreshes retained projection state from changed project notes without implementing Obsidian-to-Reminders write sync yet.

## Scope

- Add an Obsidian project directory watcher for direct markdown files in `<vault>/raw/projects/`.
- Add a changed-file retained projection refresh seam that uses `ObsidianProjectMarkdownStore.loadProjectNotesInScope(at:)`.
- Wire the watcher into `AppState` when an Obsidian vault is configured.
- Stop the Obsidian watcher when leaving Obsidian mode or setup is reset.
- Keep Logseq watcher behavior unchanged for Logseq mode.
- Treat Obsidian helper invalidation as an optional fast hint only; the file watcher must work without it.

## Required Behavior

- Only direct `raw/projects/*.md` changes are projection refresh candidates.
- Files outside `raw/projects/`, nested markdown files, symlink escapes, and non-markdown files are ignored.
- Repeated changes to the same file are coalesced by the 10 second idle debounce.
- Different project files changed during the same idle window are accumulated and delivered together.
- If a new change arrives before the debounce fires, the previous scheduled sync is cancelled and rescheduled.
- Fast invalidation may bump Timeline/Schedule projection revision before the debounced changed-file refresh.
- Debounced changed-file refresh loads only touched project note files.
- Debounced changed-file refresh must call the changed-file store path and must not call full `loadProjectNotesInScope()` for edit events.
- Debounced changed-file refresh performs no Reminders fetch/create/update/delete calls.
- Delete and rename events may invalidate projection state, but this slice must not create Reminder tombstones, delete Reminder items, or write files in response.
- Duplicate/damaged metadata never falls back to Logseq data.
- Obsidian watcher setup must not create `.obsidian`, enable helper plugins, delete files, or write Reminders.

## Out Of Scope

- Obsidian-to-Reminders create/update/delete sync.
- Reminder-backed Obsidian write-back.
- Delete sync.
- Helper plugin auto-enable.
- Obsidian note auto-move.
- Logseq source removal.
- SwiftData/schema/runtime data deletion.
- Calendar write policy changes.

## Review Lane

Review must check:

- Watcher cannot scan or report files outside `raw/projects/`.
- Debounce semantics are cancel-and-reschedule, not fixed-delay batching.
- Changed-file refresh does not perform Reminders writes.
- Logseq watcher behavior is not changed.
- AppState stops the inactive mode watcher when switching source modes.

## Test Lane

Focused tests:

- Watcher/change tracker ignores non-project files.
- Watcher coalesces repeated changes.
- Watcher accumulates multiple changed project files in one idle window.
- Delete events do not produce Reminder delete/tombstone work in this slice.
- Changed-file projection refresh only loads touched project notes.
- Changed-file projection refresh performs no Reminder create/update/delete calls.
- Changed-file projection refresh preserves no-op Calendar bridge decisions for timed tasks.
- Helper/fast invalidation hint does not consume the debounced sync change.
- Duplicate IDs fail closed.
- Damaged metadata fails closed for requested changed project coverage.
- AppState configures Obsidian watcher and stops Logseq watcher in Obsidian mode.

Full gates:

- `swift test --filter ObsidianProjectDirectoryWatcherTests`
- `swift test --filter ObsidianChangedProjectProjectionRefreshTests`
- `swift test --filter RetainedSetupFlowTests`
- `swift build`
- `swift test`
- Quit existing app and launch `.build/BrainUnfogHarness.app`.

## Acceptance

- Obsidian file watcher exists and is active after Obsidian setup/runtime prepare.
- A changed `raw/projects/*.md` file can trigger fast projection invalidation and a debounced changed-file refresh without Reminders write sync.
- The changed-file refresh path is bounded to touched raw project notes and never scans the full vault.
- All changes are non-destructive and do not alter Calendar write policy.
