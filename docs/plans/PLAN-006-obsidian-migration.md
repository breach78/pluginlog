# PLAN-006: Obsidian migration for retained Brain Unfog

## Status

Accepted and active on 2026-04-25.

This is the execution plan for the Obsidian migration unless a later plan
explicitly supersedes it.

## Related Decisions

- `docs/decisions/ADR-002-reminder-backed-schedule-blocks-no-calendar-event-mirroring.md`
- `docs/decisions/ADR-003-use-reminder-identifiers-as-retained-sync-identity.md`
- `docs/decisions/ADR-005-obsidian-vault-retained-architecture.md`

## Objective

Move the retained project/outliner/detail store from Logseq to Obsidian while
preserving the working native app surface:

- Timeline view
- Schedule view
- Apple Reminders list/task sync
- Apple Calendar read-only overlay
- task subtree and Reminder note sync

The migration should be a partial rewrite:

- Keep the app and views.
- Rebuild the Markdown storage/sync layer for Obsidian.
- Remove Logseq only after the Obsidian path is proven.

## Non-Goals

- Do not rewrite Timeline/Schedule from scratch.
- Do not create Apple Calendar events for Reminder-backed tasks.
- Do not migrate from Logseq files as the initial source of truth.
- Do not support Obsidian mobile in the first implementation.
- Do not hide metadata only in a sidecar store.

## Current Baseline

Useful pieces to keep:

- `ReminderGateway`
- `ReminderSourceObserver`
- `ReminderSyncBaseline`
- `RetainedProjectionBuilder` concepts
- `RetainedWorkspaceSurfaceProjection` concepts
- `RetainedTaskCommandService` concepts
- Timeline/Schedule UI
- build/test/runtime harness

Pieces to replace:

- `LogseqProjectPageStore`
- `LogseqPagesDirectoryWatcher`
- `LogseqPageFilenameCodec`
- `LogseqReminderPropertyCodec` naming and Logseq-specific syntax
- `LogseqHelperPluginInstaller`
- `Resources/LogseqHelperPlugin`
- `LogseqDeepLinking`
- Logseq graph setup UI and preferences

## Target Obsidian Markdown Contract

Project note:

```md
---
tags:
  - 프로젝트
reminder_list_external_id: 79892F48-5DCF-44B4-AE10-085188B563F9
---

- [ ] Task title ^buf-46B721BC
  %% brain-unfog: {"reminder_external_id":"46B721BC-6454-46AC-BEB9-C77ABE619619","date":"2026-04-25","time":"14:00","duration":15,"repeat":null} %%
  - child note
  - [ ] child task
```

Rules:

- Obsidian note = Reminders list.
- Synced project notes live under `raw/projects/`.
- Brain Unfog creates `raw/projects/` if the folder is missing.
- Project-tagged notes outside `raw/projects/` are not automatically synced.
- Obsidian task = Reminder item.
- `reminder_list_external_id` and `reminder_external_id` are the persisted
  sync identities.
- `date` is stored as `yyyy-mm-dd` and maps to Reminder due date.
- `time` is optional `HH:mm` local time and maps to Reminder due time when
  present.
- `repeat` maps to Reminder recurrence where supported.
- `duration` is app/Obsidian-only Schedule block length.
- The whole task subtree syncs with the Reminder note.
- Task subtree and Reminder note sync must preserve `t:<id>` child-task markers
  for nested child tasks.
- The optional `^buf-*` block id supports deep focus, not sync identity.

## Commands

Build:

```bash
swift build
```

Test:

```bash
swift test
```

Focused test examples:

```bash
swift test --filter ObsidianProjectNoteStoreTests
swift test --filter ObsidianMarkdownRendererTests
swift test --filter RetainedReminderImportSyncTests
```

Runtime gate:

```bash
swift run --skip-build BrainUnfogHarness launch
```

Helper plugin gate, once added:

```bash
npm install
npm run build
```

## Execution Orchestration

The implementation must be orchestrated by the main Codex agent.

Allowed execution resources:

- installed Codex subagents
- Codex harness
- installed `addyosmani/agent-skills` skills

No other agent framework or external automation layer is part of this plan.

### Main Orchestrator

The main agent owns:

- phase ordering
- task packet creation
- final architecture decisions
- sync policy interpretation
- merge/delete/repair safety decisions
- final review of worker output
- final build/test/runtime gate judgment

The main agent must not delegate a task if the next critical-path step depends
on the answer immediately. Blocking decisions stay local.

### Agent Lanes

Each implementation slice should use separate lanes when practical:

- implementation lane: writes the scoped code change
- review lane: performs adversarial code review against the task packet and
  this plan
- test lane: runs focused tests, full `swift test`, build, and runtime gates

Reviewer and tester lanes must be separate from the implementation lane. If a
reviewer or tester lane times out or is unavailable, record that fact in the
slice notes and use sequential fallback.

### 5.3 Codex Spark Usage

Use `gpt-5.3-codex-spark` only for narrow, low-risk, speed-sensitive work:

- `rg` inventory and stale reference lists
- fixture enumeration
- small test skeletons
- documentation/task-packet drafts
- simple mechanical renames after the contract is fixed
- focused verification summaries

Do not use Spark as the final authority for:

- Obsidian architecture decisions
- sync merge policy
- deletion/tombstone policy
- Reminder note subtree encoding changes
- Calendar write policy
- broad multi-file implementation
- final acceptance judgment

### Required Skills

Use only installed `addyosmani/agent-skills` skills for this plan. The default
skill set is:

- `spec-driven-development`
- `planning-and-task-breakdown`
- `api-and-interface-design`
- `source-driven-development`
- `incremental-implementation`
- `test-driven-development`
- `code-review-and-quality`
- `performance-optimization`
- `deprecation-and-migration`
- `security-and-hardening`
- `documentation-and-adrs`
- `git-workflow-and-versioning`

Apply `source-driven-development` whenever implementation depends on Obsidian
plugin APIs or current official behavior. Cite official Obsidian docs in the
task packet or implementation notes when plugin APIs are used.

### Task Packet Rule

Before each phase slice that changes code, create or update a task packet with:

- objective
- exact scope
- non-goals
- files likely touched
- implementation lane instructions
- review lane instructions
- test lane instructions
- build/test/runtime gates
- Ask First items
- rollback/fail-closed expectations

No code slice passes unless the task packet, implementation, review, and test
lanes all close or a documented sequential fallback closes the same gates.

## Boundaries

Always:

- Keep Reminders identifiers as the sync identity.
- Preserve task subtree and Reminder note sync behavior.
- Keep Calendar read-only for Reminder-backed tasks.
- Keep Timeline/Schedule functional from `raw/projects/*.md` even when
  Obsidian is closed or the helper plugin is disconnected.
- Store app-owned sidecar state under `<vault>/.buf/`.
- Keep helper plugin responsibilities limited to vault-side UI, safe writes,
  focus/highlight, and invalidation hints.
- Keep Reminders merge, delete, baseline, and repair decisions in the native
  BUF app.
- Debounce file-edit driven Reminders sync with a 10 second idle window.
- Add fixture tests before runtime cutover.
- Keep each new source file under 800 lines.
- Prefer small seams over large rewrites.
- Create/update a task packet before each code-changing phase slice.
- Split implementation, review, and test lanes where practical.

Ask First:

- Delete Logseq source files.
- Delete user data from a Logseq graph or Obsidian vault.
- Move existing Obsidian notes into `raw/projects/`.
- Modify Obsidian vault configuration to auto-enable the helper plugin.
- Change Reminder note encoding for child task markers.
- Add a third-party plugin dependency.
- Change Calendar write policy.

Never:

- Write `brain_unfog_project_id` or `brain_unfog_task_id` into new Obsidian
  Markdown.
- Treat title-only matching as identity.
- Create/update/delete Apple Calendar events from Reminder-backed tasks.
- Rewrite ordinary untagged Obsidian notes.
- Remove Logseq code before the Obsidian runtime gate passes.

## Migration Strategy

Use Reminders-first bootstrap.

The first reliable Obsidian vault state should come from Apple Reminders, not
from the current Logseq graph. Logseq can be offered later as an explicit import
source, but it should not be the initial source of truth because the current
problem is Logseq reliability.

After Reminders-first bootstrap works:

1. Obsidian project-tagged notes can create Reminders lists.
2. Obsidian tasks inside synced notes can create Reminder items.
3. Reminder changes can update Obsidian tasks.
4. Timeline/Schedule can use Obsidian projection.
5. Logseq code can be removed.

## Runtime Responsibility Model

BUF app owns:

- Reminders permission, import, update, delete, and recurrence operations
- Calendar read-only overlay loading
- Timeline/Schedule UI and projection state
- sync merge policy, deletion safety baseline, tombstones, and repair-needed
  decisions
- direct `raw/projects/*.md` reads when Obsidian is closed
- `.buf/` sidecar stores

Obsidian helper owns:

- date, time, and duration entry UI inside Obsidian
- hiding or rendering metadata comments as readable chips
- vault-side change hints after Obsidian layout is ready
- safe note patch application through Obsidian Vault APIs
- task focus/highlight from Brain Unfog clicks

The helper must not independently reconcile with Apple Reminders. It is a
vault-side execution helper, not a second sync engine.

## Performance Requirements

Normal typing in Obsidian must not trigger full-vault or full-sync work.

Rules:

- Watch and scan only `raw/projects/`.
- Parse only changed project files for Timeline/Schedule projection refresh.
- Use `.buf` hashes, mtimes, baselines, and repair state to skip unchanged
  files.
- Treat helper events as invalidation hints and coalesce them with file watcher
  events.
- Keep projection refresh separate from Reminders sync.
- Refresh local projection quickly enough for the app UI to feel current, but
  do not push to Reminders on every keystroke.
- Run file-edit driven Reminders sync only after a 10 second idle debounce.
- If edits keep arriving, cancel the pending sync and schedule a new one.
- Sync task subtrees to Reminder notes at task-subtree granularity where
  possible.
- Do not rewrite a whole project note for a single task metadata change unless
  the renderer proves that is the only safe operation.

## Phase 0: Contract and Gate Setup

Goal: freeze the Obsidian contract before implementation.

Tasks:

- Accept `ADR-005`.
- Treat `PLAN-006` as the active migration plan.
- Mark `PLAN-005` as superseded for execution after the Obsidian parser slice
  begins.
- Add fixture samples for project notes, task metadata comments, date-only
  tasks, date-plus-time tasks, duration, repeat, child notes, and child tasks.
- Add performance fixtures or counters for changed-file-only projection
  refresh.

Acceptance:

- Contract examples are present in docs.
- Fixtures describe both parse and render expectations.
- Performance policy is represented in task packets before runtime cutover.
- No runtime behavior changes yet.

Verification:

- `swift build`
- `swift test`

## Phase 1: Obsidian Parser and Renderer

Goal: build pure Obsidian Markdown parsing/rendering without touching runtime
sync.

Likely files:

- `import/BUF/Services/ObsidianProjectNoteModels.swift`
- `import/BUF/Services/ObsidianProjectNoteParser.swift`
- `import/BUF/Services/ObsidianProjectNoteRenderer.swift`
- `Tests/BrainUnfogHarnessTests/ObsidianProjectNoteParserTests.swift`
- `Tests/BrainUnfogHarnessTests/ObsidianProjectNoteRendererTests.swift`

Tasks:

- Parse YAML frontmatter needed for `tags` and `reminder_list_external_id`.
- Parse Markdown tasks `- [ ]` and `- [x]`.
- Parse adjacent `%% brain-unfog: {...} %%` metadata comments.
- Preserve child bullets and child tasks under parent tasks.
- Render notes without destroying unrelated prose.
- Round-trip task metadata, task completion, date, duration, repeat, and subtree.
- Expose stable file-level parse output that can be cached by content hash.

Acceptance:

- Parser handles project notes and ordinary notes.
- Renderer is idempotent on fixture round-trips.
- Duplicate Reminder identifiers are detected and reported, not silently merged.
- Damaged JSON metadata fails closed and preserves raw text.
- Unchanged file content can be skipped by hash/mtime without changing
  projection results.

Verification:

- `swift test --filter ObsidianProjectNoteParserTests`
- `swift test --filter ObsidianProjectNoteRendererTests`
- `swift build`
- `swift test`

## Phase 2: ProjectMarkdownStore Seam

Goal: separate retained sync from Logseq-specific storage.

Likely files:

- `import/BUF/Services/ProjectMarkdownStore.swift`
- `import/BUF/Services/LogseqProjectMarkdownStoreAdapter.swift`
- `import/BUF/Services/ObsidianProjectMarkdownStore.swift`
- tests for adapter behavior

Tasks:

- Define a store protocol for project notes and task records.
- Move retained sync call sites toward the protocol.
- Keep Logseq adapter behavior unchanged during this slice.
- Add Obsidian store implementation backed by parser/renderer fixtures.
- Add changed-file APIs so consumers do not need to reload all project notes for
  every edit.

Acceptance:

- Existing Logseq tests still pass.
- Obsidian store can load/save fixture project notes.
- Obsidian store can reload one changed note and preserve cached results for
  unchanged notes.
- No Timeline/Schedule runtime cutover yet.

Verification:

- focused store tests
- `swift build`
- `swift test`

## Phase 3: Obsidian Vault Setup

Goal: let the app choose and persist an Obsidian vault.

Likely files:

- `import/BUF/App/ObsidianVaultPreferenceResolver.swift`
- `import/BUF/App/AppStateObsidianLaunchAndSetup.swift`
- retained setup UI files

Tasks:

- Replace first-run Logseq graph selection with Obsidian vault selection.
- Create `<vault>/.buf` for Brain Unfog sidecar data.
- Store sync baselines, tombstones, repair state, and bridge tokens under
  `<vault>/.buf` when those stores need persistence.
- Create `<vault>/raw/projects` when Brain Unfog needs to create or sync
  project notes.
- Store a security-scoped bookmark for the selected vault.
- Detect `.obsidian` and offer to create it only when the folder is a valid
  vault candidate.
- Keep Logseq preference data untouched until deletion is approved.

Acceptance:

- First run asks for one Obsidian vault folder.
- Later runs restore the vault and continue directly.
- `.buf` is created under the vault.
- `raw/projects/` is created when missing.
- Brain Unfog-created project notes land under `raw/projects/`.
- Timeline/Schedule can load from `raw/projects/*.md` without Obsidian running.
- No attachment/history/archive storage is reintroduced.

Verification:

- setup tests
- `swift build`
- `swift test`
- app relaunch gate

## Phase 4: Obsidian Helper Plugin

Goal: install and use an Obsidian helper for coherent open-vault operations.

Likely files:

- `import/BUF/Services/ObsidianHelperPluginInstaller.swift`
- `import/BUF/Resources/ObsidianHelperPlugin/manifest.json`
- `import/BUF/Resources/ObsidianHelperPlugin/main.ts`
- `import/BUF/Resources/ObsidianHelperPlugin/styles.css`

Tasks:

- Install helper into `<vault>/.obsidian/plugins/brain-unfog-obsidian-helper`.
- Do not silently enable the helper by editing Obsidian config; expose this as
  a setup step unless explicit auto-enable approval exists.
- Observe vault changes only after Obsidian layout is ready.
- Treat helper events as faster/more coherent invalidation hints; the app still
  owns sync decisions and can read the Markdown files directly.
- Do not perform Reminders merge/delete/repair decisions inside the helper.
- Use Obsidian Vault APIs for safe note edits.
- Use `Vault.process()` for read-modify-write edits where possible.
- Support `focusTask(reminder_external_id)` to open the note and highlight the
  task line.
- Add a bridge transport spike before committing to the transport:
  - preferred: localhost desktop-only bridge with token
  - fallback: visible `Brain Unfog Bridge/` queue inside the vault
  - avoid hidden `.buf` for plugin-mediated Vault API queue operations unless
    Adapter API use is deliberately accepted

Acceptance:

- Plugin can be installed by the app.
- Plugin enablement state is visible in setup/status UI.
- Plugin can focus/highlight a known task.
- Plugin can apply a metadata update without creating an Obsidian conflict.
- Plugin change events are lightweight and do not include a full sync loop.
- If the plugin is not running, Timeline/Schedule still load from Markdown and
  sync can use guarded direct writes where explicitly allowed.
- If Obsidian may be open but the helper is unavailable, direct writes require
  hash/mtime baseline checks and fail closed on changed content.

Verification:

- plugin build
- installer tests
- manual focus-task test in a test vault
- `swift build`
- `swift test`

## Phase 5: Reminders-First Obsidian Bootstrap

Goal: create the first reliable Obsidian retained projection from Reminders.

Tasks:

- Request/verify Reminders permission.
- Fetch Reminders lists and items.
- Create one Obsidian project note per Reminders list under `raw/projects/`.
- If an existing owned note with the same list identity exists outside
  `raw/projects/`, report repair-needed and do not auto-move it without
  approval.
- Write each Reminder item as an Obsidian task with metadata comment.
- Store date, repeat, and the whole Reminder note as the initial task subtree
  where it can be parsed safely.
- Do not import from Logseq.
- Re-running bootstrap must not duplicate notes or tasks.

Acceptance:

- Empty test vault becomes usable from Reminders.
- Existing Reminders lists appear as Obsidian notes.
- Existing Reminder items appear as tasks.
- Timeline/Schedule can render bootstrapped tasks without Obsidian running.

Verification:

- bootstrap fixture tests
- `swift build`
- `swift test`
- app relaunch gate

## Phase 6: Obsidian-to-Reminders Sync

Goal: Obsidian edits create/update/delete Reminder objects through the retained
sync policy.

Tasks:

- Project-tagged Obsidian note under `raw/projects/` without
  `reminder_list_external_id` creates a Reminders list.
- Task inside a synced note without `reminder_external_id` creates a Reminder.
- Task title/completion/date/repeat updates push to Reminders.
- Task deletion deletes or tombstones the Reminder only when identity and
  baseline rules are unambiguous.
- Duration updates remain Obsidian/app only.
- The whole Obsidian task subtree writes to the Reminder note.
- Child task markers in Reminder notes remain compatible with `t:<id>`.
- File-edit driven pushes to Reminders are delayed until the 10 second idle
  debounce fires.

Acceptance:

- Adding a project note creates a Reminders list.
- Adding a task creates a Reminder item.
- Editing title/completion/date/repeat converges.
- Editing duration affects Schedule only.
- Editing a task subtree updates the linked Reminder note.
- Continuous typing does not push intermediate states to Reminders.
- Deleting a task follows existing safe-delete policy.

Verification:

- provisioning tests
- deletion/tombstone tests
- subtree note sync tests
- `swift build`
- `swift test`
- app relaunch gate

## Phase 7: Reminders-to-Obsidian Reconciliation

Goal: Reminders changes update Obsidian notes and tasks.

Tasks:

- New Reminders list creates a project note.
- New Reminder item creates a task.
- Reminder title/completion/date/repeat updates modify metadata/task state.
- Reminder note changes update the associated whole task subtree where markers
  and parser safety allow.
- Ambiguous states fail closed and report repair-needed.

Acceptance:

- Reminders app changes appear in Obsidian and Brain Unfog.
- Reminder note changes round-trip to the Obsidian task subtree when safe.
- Duplicate IDs do not merge unrelated tasks.
- Damaged metadata is preserved and reported.
- Board does not disappear because one task needs repair.

Verification:

- import/reconcile tests
- damaged metadata tests
- `swift build`
- `swift test`
- app relaunch gate

## Phase 8: Timeline/Schedule Cutover

Goal: use Obsidian projection as the retained runtime source.

Tasks:

- Load Timeline/Schedule from Obsidian store.
- App task clicks call Obsidian task focus.
- Schedule edits update Obsidian task metadata and Reminders due date/time.
- Duration edits update Obsidian metadata only.
- Calendar overlay stays read-only.
- Remove Logseq fallback from the retained runtime only after Obsidian projection
  tests pass; do not hide Obsidian projection errors by falling back to Logseq.
- Update projection from changed files instead of reloading all project notes on
  every edit.

Acceptance:

- Timeline shows Obsidian/Reminders tasks.
- Schedule shows timed tasks with duration or 15 minute default.
- Clicking a task opens/highlights the Obsidian task.
- Calendar writes are absent from Reminder-backed task paths.
- Obsidian typing in one project note does not cause whole-vault scans or
  immediate Reminders writes.

Verification:

- projection tests
- command service tests
- `swift build`
- `swift test`
- app relaunch gate

## Phase 9: Logseq Deprecation and Removal

Goal: remove Logseq code after Obsidian passes gates.

Ask before this phase.

Deletion candidates:

- `import/BUF/Services/LogseqProjectPageStore.swift`
- `import/BUF/Services/LogseqPagesDirectoryWatcher.swift`
- `import/BUF/Services/LogseqPageFilenameCodec.swift`
- `import/BUF/Services/LogseqGraphConfigStore.swift`
- `import/BUF/Services/LogseqHelperPluginInstaller.swift`
- `import/BUF/Resources/LogseqHelperPlugin`
- `import/BUF/Utilities/LogseqDeepLinking.swift`
- Logseq-specific tests after Obsidian replacements exist
- Logseq-specific setup UI and preferences

Acceptance:

- No runtime references to Logseq remain.
- Build/test pass after deletion.
- Obsidian retained path remains functional.
- User data is not deleted automatically.

Verification:

- `rg -n "Logseq|logseq" import/BUF Tests`
- `swift build`
- `swift test`
- app relaunch gate

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---:|---|
| Helper plugin bridge transport is harder than expected | High | Do a transport spike in Phase 4 before runtime dependency |
| Metadata comments become visible in Source mode | Medium | Use comments plus rendered chips; keep metadata recoverable |
| Direct file writes still cause conflicts | High | Prefer helper plugin `Vault.process()` when Obsidian is open |
| Obsidian parser damages user prose | High | Fixture-first parser/renderer and idempotence tests |
| Logseq code removal breaks retained views | High | Remove only after Obsidian cutover gate passes |
| Reminder note subtree sync regresses | High | Dedicated whole-subtree and `t:<id>` tests before cutover |
| Date/time metadata becomes ambiguous | Medium | Store `date` as `yyyy-mm-dd` and optional `time` as `HH:mm` |
| Plugin install succeeds but plugin is not enabled | Medium | Surface enablement status and require explicit setup action |
| Project notes appear outside `raw/projects/` | Medium | Treat as repair-needed; do not auto-adopt or auto-move |
| Helper unavailable during normal app use | Medium | App reads `raw/projects/*.md` directly and uses `.buf` sidecar state |
| Typing in Obsidian causes sync jank | High | Changed-file projection plus 10 second idle debounce before Reminders writes |
| Helper becomes a second sync engine | High | Keep helper limited to UI, safe writes, focus, and invalidation hints |

## Adversarial Review Amendments

The first review pass added these constraints before implementation:

- Helper bridge transport must be proven in Phase 4 before runtime sync depends
  on it.
- Brain Unfog-created and sync-scoped project notes live under `raw/projects/`;
  tagged notes elsewhere are ignored unless explicitly moved/adopted.
- Date metadata is always `yyyy-mm-dd`; optional local task time is stored in
  a separate `time` field.
- Obsidian plugin auto-enable is not silent; it is a visible setup action unless
  explicitly approved.
- The outliner-plugin workflow means Reminder notes sync the whole task subtree,
  not a lossy summary.
- Obsidian being closed is a first-class runtime state: Timeline/Schedule and
  sync decisions still use `raw/projects/*.md`, with `<vault>/.buf/` as the
  hidden app sidecar store.
- Performance policy is part of the plan: changed-file projection refresh,
  `.buf` cache state, and 10 second idle debounce for Reminders writes.
- Helper role is fixed as vault-side UI/write/focus/invalidation helper, not a
  Reminders sync engine.

## Completion Criteria

- Obsidian vault setup replaces Logseq graph setup.
- Reminders-first bootstrap creates Obsidian project notes and tasks.
- Obsidian edits and Reminders edits converge under the retained sync policy.
- Timeline/Schedule use Obsidian projection.
- Task click opens/highlights the Obsidian task.
- Calendar remains read-only for Reminder-backed tasks.
- Normal Obsidian typing does not trigger full-vault scans or immediate
  Reminders writes.
- Logseq source and resources are removed after explicit deletion approval.
- `swift build`, `swift test`, and runtime app relaunch pass.
