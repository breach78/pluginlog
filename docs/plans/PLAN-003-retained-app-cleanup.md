# PLAN-003: Retained app cleanup and Logseq-owned storage

## Status
Draft for implementation

## Date
2026-04-24

## Source of Truth

- `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
- `docs/plans/PLAN-001-sync-policy-v1.md`
- `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
- `docs/plans/SPEC-001-buf-schedule-timeline-retained-slice.md`
- `docs/plans/ARTIFACT-001-phase-2-gate-pack.md`

## Objective

Reduce the recovered BUF app to the retained Logseq companion scope:

- first launch asks for one Logseq graph folder
- app storage is automatically created inside that graph at `.buf`
- Reminders and Calendar permissions are requested once and reused
- schedule and timeline remain as the primary app surfaces
- Logseq remains responsible for markdown pages and attachments
- old Obsidian, Journal, Compass, attachment repository, archive/history UI, and undo/redo affordances are removed from the visible app

## Non-Negotiable Sync Policy

- Logseq page equals Reminders list.
- Logseq task equals Reminders item.
- Logseq bullet order and nesting remain Logseq-only.
- `date::`, `duration::`, `repeat::`, `brain_unfog_task_id::`, `reminder_external_id::`, and `calendar_event_external_id::` remain the task sync contract.
- Only BUF-owned calendar events are writable.
- Foreign calendar events remain read-only overlay.
- Deletion and damaged identity states fail closed until deterministic fixture gates prove safety.

## Commands

- Build: `swift build`
- Test: `swift test`
- Runtime smoke: `swift run --skip-build BrainUnfogHarness`
- Focused policy test: `swift test --filter ScheduleCalendarAccessPromptPolicyTests`

After non-document code changes, the currently running app must be terminated and the rebuilt app relaunched.

## Target Architecture

### Setup

Selecting a Logseq graph root performs three actions in one user step:

1. Store a security-scoped bookmark for the graph root.
2. Create or open `<graph>/.buf` as the app container.
3. Mark sync consent as enabled because this retained app has no non-sync mode.

The setup screen should only show:

- Logseq graph folder selection
- permission status/actions for Reminders and Calendar
- setup progress/errors

There is no separate app storage picker, Obsidian picker, Journal/Compass toggle, or sync opt-out.

### Storage

`ContainerPaths.root` becomes the hidden `.buf` folder inside the selected graph.

Final retained directories should be reduced to what retained sync needs:

- `.buf/container.json`
- `.buf/data/main.sqlite`
- `.buf/data/normalized.sqlite`
- `.buf/cache`
- `.buf/exports` only while diagnostics/export code remains compiled

Attachment directories should not be created for new retained installs after attachment code is removed.

Important sequencing rule: Slice 1 may move the container root to `.buf`, but it must not reduce
`ContainerPaths.requiredDirectories` yet. Existing compiled services still reference attachment,
notes, cache, and export paths, so directory reduction is deferred until those services are removed.

### Retained Surfaces

- Timeline view
- Schedule view
- Logseq page opening from project selection
- Reminder sync
- BUF-owned calendar sync
- Read-only foreign calendar overlay
- Settings only if still needed for sync/runtime diagnostics

### Removed Surfaces

- Journal UI and Obsidian journal store
- Compass UI, services, model stores, and model settings
- Attachment UI, drag/drop, local file repository, thumbnails, and markdown attachment tokens
- Archive view and visible archive toggle
- History UI and behavior logs not required by retained sync
- App-level undo/redo registration and UI affordances

## Cleanup Strategy

This is a dependency-cutting cleanup, not a blind delete. The safe order is:

1. Hide and disconnect legacy UI entry points.
2. Collapse first-run setup to Logseq graph plus `.buf` storage.
3. Remove no-longer-reachable Journal/Compass/Archive surfaces.
4. Remove attachment UI and local file-storage paths.
5. Remove undo/redo registration from schedule/timeline actions.
6. Remove history models/services only after schedule/timeline/read-model tests prove no retained sync dependency.
7. Delete dead files only after an explicit local file deletion confirmation.

## Task Packets

### Slice 1: Setup and storage collapse

Acceptance:

- Selecting a Logseq graph creates or opens `<graph>/.buf`.
- Setup no longer exposes a separate storage folder picker.
- Setup no longer exposes Obsidian or Journal/Compass controls.
- Sync consent is automatically enabled for retained mode.
- Existing separate BUF container is not moved or deleted silently; this slice starts using the graph-local `.buf` container and leaves old data untouched.
- Existing graph with existing `.buf/container.json` reopens without rewriting Logseq pages, Reminders, or Calendar objects during setup.
- Missing or corrupt `.buf/container.json` fails with a recoverable setup error unless `.buf` is truly new.
- Reminders or Calendar denied state does not crash and does not trigger partial destructive sync.
- Existing saved Logseq graph reopens `.buf` on launch.
- Build/test/runtime smoke pass.

Files likely touched:

- `import/BUF/App/AppStateLaunchAndSetup.swift`
- `import/BUF/App/AppState.swift`
- `import/BUF/Features/Setup/SetupContainerView.swift`
- `import/BUF/Persistence/StorageCoordinator.swift`
- `import/BUF/Persistence/ContainerPaths.swift`
- `import/BUF/App/AppStateSyncAndPersistence.swift`
- `import/BUF/Services/ReminderSourceObserver.swift`

Slice 1 constraints:

- No source-file deletion.
- No SwiftData schema/model removal.
- No `ContainerPaths.requiredDirectories` reduction.
- No attachment/history/archive/undo source edits except hiding setup UI controls if needed.
- No delete propagation or first-sync rewrite behavior beyond the existing PLAN-001 fail-closed policy.

### Slice 2: Remove visible legacy navigation

Acceptance:

- View mode picker only shows Timeline and Schedule.
- App menu only exposes Timeline and Schedule shortcuts.
- Journal, Compass, Archive, Obsidian, and attachment quick-add UI are not reachable.
- Build/test/runtime smoke pass.

Files likely touched:

- `import/BUF/Models/Enums.swift`
- `import/BUF/BUFApp.swift`
- `import/BUF/Features/Workspace/MainWorkspaceChrome.swift`
- `import/BUF/Features/Workspace/MainWorkspacePanels.swift`
- `import/BUF/App/AppStateWorkspaceUI.swift`

### Slice 3: Attachment UI and local repository removal

Acceptance:

- No retained view can import, display, drag, reveal, or delete local attachments.
- New `.buf` containers do not create attachment directories.
- Attachment deletion does not affect Logseq markdown attachments.
- Source-file deletion happens only after user confirms exact files.
- Build/test/runtime smoke pass.

Ask First:

- Delete attachment source files.
- Drop attachment database model/table or migrate existing data.

### Slice 4: Journal and Compass source removal

Acceptance:

- Journal/Compass code is unreachable and then removed.
- Gemini/OpenAI keychain status is not read at startup unless another retained feature needs it.
- Obsidian bookmark state is unused and removed from setup.
- Source-file deletion happens only after user confirms exact files.
- Build/test/runtime smoke pass.

Ask First:

- Delete Journal/Compass source files.
- Delete persisted Obsidian bookmark defaults.

### Slice 5: Archive/history/undo cleanup

Acceptance:

- Visible archive toggle and Archive view are removed.
- App-level undo/redo registration is removed from retained schedule/timeline actions.
- Project history recording is removed only where it is not used for retained sync safety.
- Timeline completed-history rendering is either explicitly retained as schedule context or removed with tests.
- Build/test/runtime smoke pass.

Ask First:

- Delete history model/service files.
- Remove `ProjectHistoryEvent` from SwiftData schema.
- Change archive semantics from soft-delete to any new behavior.

## Review Gates

- Critical review lane must review each slice before deletion.
- Tester lane or sequential fallback must run `swift test` and `swift build`.
- Runtime gate must relaunch `BrainUnfogHarness` after code changes.
- Sync-sensitive changes must not weaken PLAN-001 identity and fail-closed policies.

## Current Blockers

- Deterministic EventKit fixture harness is still not fully closed, so sync deletion behavior must remain conservative.
- Full removal of `AttachmentEntity` and `ProjectHistoryEvent` may require SwiftData/schema migration work and cannot be done as a blind file delete.
- Calendar permission behavior may require app-bundle/runtime packaging follow-up; retained setup should still expose one permission request path.
