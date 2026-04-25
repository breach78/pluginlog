# TASK-PACKET-008: PLAN-006 Phase 1 Obsidian Parser/Renderer

## Objective

Build the pure Obsidian Markdown parser/renderer seam required by PLAN-006
Phase 1 without changing runtime sync, setup, Timeline, Schedule, Reminders, or
Calendar behavior.

This packet also closes the Phase 0 gap by fixing concrete parser/renderer
fixture expectations before implementation.

## Scope

- Add pure Obsidian project note models.
- Parse only Markdown project notes under the PLAN-006 contract:
  - YAML frontmatter `tags`
  - YAML frontmatter `reminder_list_external_id`
  - Markdown tasks `- [ ]` and `- [x]`
  - adjacent `%% brain-unfog: {...} %%` JSON metadata comments
  - task metadata fields `reminder_external_id`, `date`, `time`, `duration`,
    `repeat`
  - nested child bullets/tasks as raw task subtree lines
- Render project notes from parsed models using the canonical Obsidian contract:
  - `reminder_list_external_id` in frontmatter
  - `reminder_external_id` only in metadata comments
  - `date` as `yyyy-mm-dd`
  - optional `time` as `HH:mm`
  - optional `duration` as integer minutes
  - optional `repeat`
  - no `brain_unfog_project_id`
  - no `brain_unfog_task_id`
- Detect duplicate project/task Reminder identifiers in parse output.
- Detect damaged JSON metadata and keep raw Markdown available for repair.
- Preserve unrelated prose and task subtree text in round-trip fixture tests.
- Expose stable file-level information suitable for later hash/mtime caching.
  Phase 1 may expose deterministic normalized content hash/fingerprint and
  source ranges only; it must not read/write `.buf`, install watchers, or
  persist cache state.
- Preserve `t:<id>` child-task marker text verbatim; do not replace the marker
  contract with metadata-only or `^buf-*`.

## Non-Goals

- Do not wire Obsidian parser output into runtime Timeline/Schedule.
- Do not replace Logseq setup or preferences.
- Do not delete Logseq source files or resources.
- Do not move existing Obsidian notes into `raw/projects/`.
- Do not add or auto-enable an Obsidian helper plugin.
- Do not add third-party dependencies.
- Do not change Reminder note child marker policy.
- Do not create, update, or delete Apple Calendar events.
- Do not change Reminders sync behavior in this slice.

## Likely Files

- `import/BUF/Services/ObsidianProjectNoteModels.swift`
- `import/BUF/Services/ObsidianProjectNoteParser.swift`
- `import/BUF/Services/ObsidianProjectNoteRenderer.swift`
- `Tests/BrainUnfogHarnessTests/ObsidianProjectNoteParserTests.swift`
- `Tests/BrainUnfogHarnessTests/ObsidianProjectNoteRendererTests.swift`

If a shared helper is needed, keep it in the same small files unless a file
would exceed 800 lines.

## Fixture Expectations

### Project Note

Input:

```md
---
tags:
  - 프로젝트
reminder_list_external_id: LIST-1
---

Intro prose.

- [ ] Task title ^buf-TASK-1
  %% brain-unfog: {"reminder_external_id":"TASK-1","date":"2026-04-25","time":"14:00","duration":15,"repeat":"monthly"} %%
  - child note
  - [ ] child task
    %% brain-unfog: {"reminder_external_id":"TASK-CHILD"} %%
```

Expected parse:

- later store phases classify a note as sync-scoped only when its vault-relative
  path is under `raw/projects/` and either frontmatter contains `프로젝트` or
  frontmatter contains `reminder_list_external_id`
- project identity is `LIST-1`
- parent task identity is `TASK-1`
- parent task is incomplete
- parent `date` is `2026-04-25`
- parent `time` is `14:00`
- parent `duration` is `15`
- parent `repeat` is `monthly`
- parent subtree preserves `child note`, the nested child task lines, and any
  existing `t:<id>` marker text verbatim
- child task identity remains parseable as its own task when the parser walks
  all Markdown tasks

Additional scope fixtures:

- tag-only note under `raw/projects/` is a project candidate with no list
  identity yet
- id-only note under `raw/projects/` is a project candidate
- tagged or id-only notes outside `raw/projects/` parse normally but later
  stores must not auto-sync them
- unbound task `- [ ] New task ^buf-X` parses with no Reminder identity,
  preserves title/block id, renders without inventing `reminder_external_id`,
  and never treats title or `^buf-*` as sync identity

### Ordinary Note

An Obsidian note without `프로젝트` tag and without
`reminder_list_external_id` parses as ordinary and must not be considered a
synced project note by later stores.

### Damaged Metadata

Malformed `%% brain-unfog: ... %%` metadata must not be silently discarded or
rewritten. The parser marks the task as repair-needed/damaged and preserves the
raw metadata line for later UI/reporting.

Rendering a note containing damaged metadata must either reproduce the raw
damaged line unchanged or refuse with repair-needed. It must not canonicalize,
drop, or overwrite damaged metadata. Unsupported frontmatter, prose, and
comments before, between, and after tasks must be preserved in renderer
fixtures.

### Duplicate Identities

Duplicate `reminder_list_external_id` or duplicate `reminder_external_id`
within a parse batch must be reported by validation helpers and must not merge
unrelated projects/tasks.

### Renderer

Renderer round-trip on valid fixtures is idempotent after line-ending
normalization. Rendering must not emit legacy `brain_unfog_*` keys.

## Implementation Lane

- Keep the slice pure and deterministic.
- Prefer simple line-oriented parsing over a large Markdown AST dependency.
- Treat unsupported YAML as preserved raw frontmatter plus extracted known
  fields; do not attempt a complete YAML implementation.
- Parse only enough frontmatter for `tags` and `reminder_list_external_id`.
- Preserve line endings by normalizing to `\n` internally and rendering `\n`.
- Do not import EventKit or touch ReminderGateway.
- Parser/renderer files should import `Foundation` only; do not reference
  `EventKit`, `EKEvent`, `calendar_event_external_id`, Calendar bridge types, or
  Calendar runtime files.
- Do not modify existing Logseq runtime code unless compilation requires a
  narrow type visibility change. If that happens, stop and report first.

## Review Lane

Review adversarially for:

- accidental runtime behavior changes
- any write of `brain_unfog_project_id` or `brain_unfog_task_id`
- title-only identity assumptions
- lossy subtree parsing or rendering
- damaged metadata being overwritten instead of fail-closed
- Calendar write policy regression
- parser scope creep beyond `raw/projects/` contract
- any Ask First violation

## Test Lane

Add focused tests for:

- project frontmatter tag/list id parsing
- tag-only, id-only, and outside-`raw/projects/` classification fixtures at the
  parser/store-boundary model level
- unbound task parsing without invented identity
- ordinary note classification
- task metadata parsing for date/time/duration/repeat
- renderer emits canonical metadata and no legacy IDs
- valid fixture round-trip idempotence
- damaged metadata is preserved and marked damaged
- duplicate task Reminder IDs are reported
- duplicate project Reminder list IDs across a parse batch are reported and must
  not merge project notes
- child subtree lines are preserved
- `t:<id>` marker text in child task subtrees is preserved verbatim
- deterministic normalized content hash/fingerprint is stable for line-ending
  equivalent content and changes when meaningful content changes
- timed task without duration remains parseable; Schedule 15-minute default is
  not implemented here and remains a later projection concern
- Calendar write path remains untouched by this pure slice

## Build/Test/Runtime Gate

- `swift test --filter ObsidianProjectNoteParserTests`
- `swift test --filter ObsidianProjectNoteRendererTests`
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
- changing Reminder note child marker encoding
- adding a third-party dependency
- changing Calendar write policy
- auto-enabling an Obsidian helper plugin

## Acceptance

- Phase 1 parser/renderer tests pass.
- Existing Logseq tests still pass.
- No runtime source is cut over to Obsidian yet.
- No Calendar write path is introduced.
- No legacy Brain Unfog IDs are rendered into new Obsidian Markdown.
- No `.buf` cache, watcher, setup, helper plugin, or runtime store is added in
  this slice.
