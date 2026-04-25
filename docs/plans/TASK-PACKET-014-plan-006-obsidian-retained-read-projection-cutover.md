# TASK-PACKET-014: Obsidian Retained Read Projection Cutover

Status: Draft for implementation

## Goal

Make Timeline/Schedule read from Obsidian project notes when an Obsidian vault is configured, without requiring Obsidian to be running and without implementing Obsidian-to-Reminders write sync in this slice.

## Scope

- Add an adapter that converts `ObsidianProjectMarkdownStore.Snapshot` values from `<vault>/raw/projects/*.md` into `RetainedWorkspaceSnapshot`.
- Keep `RetainedProjectionBuilder.Source` Logseq-specific for now; do not force Obsidian notes through Logseq page snapshots.
- Do not depend on Logseq page store models or Logseq property codecs in the Obsidian projection adapter.
- Add a retained surface load path that prefers Obsidian when `obsidianVaultRootURL` is configured.
- Update Schedule/Timeline reload paths to call the source-aware retained projection loader.
- Preserve Logseq read loading when no Obsidian vault is configured.

## Required Behavior

- Only `raw/projects/` direct markdown files are loaded for Obsidian projection.
- Obsidian mode must not use Logseq fallback to hide Obsidian projection errors.
- Project identity derives from `reminder_list_external_id`.
- Task identity derives from `reminder_external_id`.
- Obsidian metadata maps to retained schedule fields:
  - `date` as `yyyy-mm-dd`
  - optional `time` as `HH:mm`
  - `duration` as app-only schedule length
  - `repeat` as retained recurrence display value
- Tasks without stable Reminder identity are not shown in Schedule/Timeline in this slice.
- Duplicate identities block projection instead of generating fallback data.
- Damaged task metadata excludes the affected project from retained read output; if that project was requested, the retained read returns partial coverage instead of Logseq fallback data.
- Project-tagged Obsidian notes without `reminder_list_external_id` are not auto-provisioned in this slice; if a requested project cannot be represented from Obsidian metadata, the retained read returns a blocker instead of Logseq fallback data.
- Reminder-backed tasks must not create Calendar write candidates.

## Out Of Scope

- Obsidian-to-Reminders push/write sync.
- Changed-file projection cache.
- 10 second idle debounce.
- Obsidian note auto-move.
- Helper auto-enable.
- Logseq source deletion.
- SwiftData/schema/runtime data deletion.
- Calendar write policy changes.
- Third-party dependency additions.

## Review Lane

Review must check:

- Obsidian projection cannot scan outside `raw/projects/`.
- Obsidian load errors cannot fall back to Logseq in Obsidian mode.
- Duplicate/damaged identities fail closed.
- New Obsidian markdown does not introduce `brain_unfog_project_id` or `brain_unfog_task_id`.
- Calendar remains read-only for Reminder-backed tasks.

## Test Lane

Focused tests:

- Obsidian retained projection adapter maps list/task identities and schedule metadata.
- Duplicate Obsidian Reminder task IDs block projection.
- Duplicate Obsidian Reminder list IDs block projection.
- Damaged Obsidian task metadata excludes only the affected project when unrelated valid notes exist.
- Retained read from Obsidian does not rewrite note bytes or mtimes.
- Requested Obsidian projects missing from retained metadata block projection without global fatal UI.
- Surface projection loads from Obsidian vault when configured.
- Legacy `brain_unfog_project_id` / `brain_unfog_task_id` fields do not create Obsidian projection identities.
- Obsidian mode does not use Logseq fallback to hide missing/invalid Obsidian projection.
- Existing Logseq surface load remains unchanged.

Full gates:

- Existing Obsidian focused tests.
- `swift build`
- `swift test`
- Quit existing app and launch `.build/BrainUnfogHarness.app`.

## Acceptance

- With `obsidianVaultRootURL` configured, Timeline/Schedule can build retained project/task surfaces from `raw/projects/*.md` alone.
- With only Logseq configured, existing retained Logseq read behavior still works.
- No file deletion, schema deletion, runtime data deletion, Obsidian note move, or helper auto-enable occurs.
