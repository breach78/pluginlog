# TASK-PACKET-009: PLAN-006 Phase 2a ProjectMarkdownStore Seam

## Objective

Introduce a storage seam that lets retained sync code move away from
Logseq-specific page storage in later phases, while keeping current runtime
behavior unchanged in this slice.

## Scope

- Add a small `ProjectMarkdownStore` protocol with changed-file loading APIs.
- Add `LogseqProjectMarkdownStoreAdapter` as a thin wrapper over existing
  `LogseqProjectPageStore`.
- Add `ObsidianProjectMarkdownStore` backed by Phase 1 parser/renderer.
- Restrict Obsidian store scanning to `<vault>/raw/projects/*.md`.
- Create `<vault>/raw/projects/` only when the Obsidian store prepares or writes
  project notes in tests.
- Save Obsidian fixture project notes through a guarded write API:
  - new files may be created under `raw/projects/`
  - existing files may be returned without mutation when normalized content is
    unchanged
  - existing files require caller-supplied expected hash/mtime before mutation
  - existing files fail closed when the embedded `reminder_list_external_id`
    conflicts or is missing for a reminder-backed write
- Keep file-level deterministic hash/fingerprint in the loaded snapshot for
  later changed-file cache work.

## Non-Goals

- Do not wire Timeline/Schedule runtime to Obsidian.
- Do not change app setup or preferences.
- Do not replace Logseq runtime paths.
- Do not delete Logseq source files or resources.
- Do not create or write `<vault>/.buf` in this slice.
- Do not watch files or add debounce logic in this slice.
- Do not move existing Obsidian notes into `raw/projects/`.
- Do not add or auto-enable an Obsidian helper plugin.
- Do not touch Reminders sync or Calendar code.

## Likely Files

- `import/BUF/Services/ProjectMarkdownStore.swift`
- `import/BUF/Services/LogseqProjectMarkdownStoreAdapter.swift`
- `import/BUF/Services/ObsidianProjectMarkdownStore.swift`
- `Tests/BrainUnfogHarnessTests/ObsidianProjectMarkdownStoreTests.swift`
- `Tests/BrainUnfogHarnessTests/LogseqProjectMarkdownStoreAdapterTests.swift`

## Implementation Lane

- Keep the protocol small and source-agnostic.
- Use actor-backed stores to preserve current async call style.
- Obsidian store must only enumerate direct `.md` files in `raw/projects/`.
- `loadProjectNotesInScope(at:)` must ignore files outside `raw/projects/`,
  nested directories, `../` path escapes, and symlink escapes after canonical
  path resolution.
- Obsidian store may expose a simple write/upsert method for fixture tests; it
  must be guarded by hash/mtime for existing-file mutation and must not write
  `.buf` or perform sync decisions.
- No title-only identity matching is allowed beyond generating a safe filename
  for a caller-provided new project note write. If the generated file already
  exists, identity and baseline checks must pass before mutation.
- No Calendar/EventKit imports or bridge references.

## Fail-Closed / Rollback

- Parse/validation failure preserves raw Markdown and does not delete or
  overwrite files.
- Duplicate Reminder list/task identifiers are reported by parser validation
  and must not be merged by the store.
- Existing-file writes require matching expected normalized content hash and
  mtime unless normalized rendered content is already identical.
- Existing-file writes fail when the current file has a different or missing
  `reminder_list_external_id` for a reminder-backed write.
- Path escape or symlink escape returns no snapshot and performs no write.
- Partial write failures are surfaced as thrown errors; this slice performs no
  cleanup deletion.

## Review Lane

Review adversarially for:

- accidental runtime cutover
- whole-vault scans
- hidden `.buf` writes
- Logseq deletion or behavior changes
- data-loss write behavior
- title-only identity assumptions
- Calendar policy regression
- Ask First violations

## Test Lane

Add focused tests for:

- Obsidian store creates `raw/projects/` during prepare/write.
- Obsidian store scans only `raw/projects/*.md`, not ordinary vault notes.
- Changed-file load returns only changed files under `raw/projects/`.
- Changed-file load ignores nested files, `../` escapes, and symlink escapes.
- Obsidian store write is no-op when normalized content is unchanged.
- Obsidian store refuses to overwrite an existing file with conflicting or
  missing `reminder_list_external_id`.
- Obsidian store refuses real existing-file mutation when expected hash/mtime is
  stale or absent.
- Obsidian store round-trips a parser/renderer fixture.
- Logseq adapter delegates to existing `LogseqProjectPageStore` without changing
  behavior.
- Existing Calendar policy tests still pass, and new ProjectMarkdownStore files
  contain no Calendar/EventKit/bridge references.

## Build/Test/Runtime Gate

- `swift test --filter ObsidianProjectMarkdownStoreTests`
- `swift test --filter LogseqProjectMarkdownStoreAdapterTests`
- `rg -n "ObsidianProjectMarkdownStore" import/BUF/App import/BUF/Features import/BUF/Services/Retained import/BUF/Services/Reminder import/BUF/Services/Schedule` returns no runtime cutover references in this slice.
- `rg -n "EventKit|EKEvent|Calendar|calendar_event_external_id" import/BUF/Services/ProjectMarkdownStore.swift import/BUF/Services/LogseqProjectMarkdownStoreAdapter.swift import/BUF/Services/ObsidianProjectMarkdownStore.swift` returns no matches.
- `swift build`
- `swift test`
- Because this slice changes code, quit existing Brain Unfog app and relaunch
  `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app` after
  build/test pass.

## Ask First Items

Stop before:

- deleting Logseq source files
- deleting user data from any graph or vault
- moving existing Obsidian notes into `raw/projects/`
- adding `.buf` sidecar writes
- adding or auto-enabling a helper plugin
- changing Reminder note marker encoding
- adding a third-party dependency
- changing Calendar write policy

## Acceptance

- Phase 2a store seam tests pass.
- Existing Logseq behavior remains unchanged.
- Obsidian store can load and save fixture notes under `raw/projects/`.
- No runtime source is cut over to Obsidian yet.
- No `.buf` cache/watcher/setup/helper/runtime sync behavior is added.
