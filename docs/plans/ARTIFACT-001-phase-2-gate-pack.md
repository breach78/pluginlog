# ARTIFACT-001: Phase 2 gate pack for retained slice

## Status
In Progress

## Date
2026-04-23

## Related Docs

- `docs/plans/SPEC-001-buf-schedule-timeline-retained-slice.md`
- `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
- `docs/plans/PLAN-001-sync-policy-v1.md`

## Purpose

Close the missing Phase 2 artifacts required by `PLAN-002`:

- dependency inventory
- seam map
- file ownership map
- harness restoration path
- initial task packets

## Phase Gate Status

### Phase 1

- `SPEC-001` now exists
- `ADR-001`, `PLAN-001`, and `PLAN-002` already exist
- host-shell decision is closed for Phase 1:
  - recover the existing `BUFApp.swift` app entry through a SwiftPM harness candidate first
  - do not design a new narrow host before the harness slice finishes
  - decide any post-harness host narrowing only after Slice 2 produces a concrete build result

### Phase 2

Current outputs in this artifact:

- dependency inventory: complete enough for the retained slice
- seam map: complete enough for V1a/V1b
- file ownership map: complete enough for worker assignment
- harness restoration path: complete through SwiftPM harness recovery
- task packets: Slice 1 through Slice 7 written

Current slice state:

- Slice 2: complete
- Slice 3: complete
- Slice 4: complete
- Slice 5: complete
- Slice 6: code path complete, build/test/runtime green, deterministic EventKit fixture verification still open
- Slice 7: hardening path implemented, build/test/runtime green, final release gate still blocked by the same fixture-harness gap

## Dependency Inventory

### Keep First

- workspace routing edge:
  - `import/BUF/Features/Workspace/MainWorkspacePanels.swift`
  - `import/BUF/Features/Workspace/MainWorkspaceView.swift`
- timeline surface:
  - `import/BUF/Features/Timeline/TimelineBoardView.swift`
  - `import/BUF/Features/Timeline/TimelineBoardRows.swift`
  - `import/BUF/Features/Timeline/TimelineBoardOverlays.swift`
  - `import/BUF/Features/Timeline/TimelineBoardRefresh.swift`
  - `import/BUF/Features/Timeline/TimelineBoardSupport.swift`
- schedule surface:
  - `import/BUF/Features/Schedule/ScheduleBoardView.swift`
  - `import/BUF/Features/Schedule/ScheduleBoardChrome.swift`
  - `import/BUF/Features/Schedule/ScheduleBoardAllDayRail.swift`
  - `import/BUF/Features/Schedule/ScheduleBoardTimeGrid.swift`
  - `import/BUF/Features/Schedule/ScheduleDayTimelineLayoutEngine.swift`
  - `import/BUF/Features/Schedule/ScheduleCollisionDetector.swift`
  - `import/BUF/Features/Schedule/ScheduleEventModel.swift`
  - `import/BUF/Features/Schedule/ScheduleEventRenderingLayer.swift`
  - `import/BUF/Features/Schedule/ScheduleEventStores.swift`
  - `import/BUF/Features/Schedule/ScheduleInteractionLayers.swift`
- shared read-model floor:
  - `import/BUF/Services/ReminderRuntimeProjectionReadModelService.swift`
  - `import/BUF/Services/ScheduleProjectionService.swift`
  - `import/BUF/Services/TimelineProjectionService.swift`
  - `import/BUF/Services/TimelineService.swift`
- runtime/model floor currently dragged along:
  - `import/BUF/Services/ProjectDetailSnapshotModels.swift`
  - `import/BUF/Models/OutlinerCoreStorage.swift`
  - `import/BUF/Features/Outliner/OutlinerSessionSnapshot.swift`
  - `import/BUF/Features/Outliner/OutlinerModels.swift`
  - `import/BUF/Models/Project.swift`
  - `import/BUF/Persistence/NormalizedPersistence.swift`
  - `import/BUF/App/WorkspaceNavigation.swift`
- calendar overlay read path:
  - `import/BUF/Services/ScheduleCalendarStore.swift`
  - `import/BUF/App/AppStateScheduleProjectionRead.swift`
  - `import/BUF/App/AppStateCalendarServiceRegistry.swift`
  - `import/BUF/App/AppState.swift`
- project-open foundation:
  - `import/BUF/Utilities/PlatformUIFoundation.swift`

### Drop First

- `import/BUF/Features/ProjectWindow/*`
- `import/BUF/Features/Compass/*`
- `import/BUF/Features/Journal/*`
- `import/BUF/Features/Archive/*`
- `import/BUF/Features/Settings/*`
- `import/BUF/Features/Setup/*` once a retained shell is established

### Highest-Risk Couplings

- `ReminderRuntimeProjectionReadModelService.swift` still ties the boards to outliner runtime types instead of a slim board DTO.
- `MainWorkspaceOverlays.swift -> ProjectDetailHostView.swift -> ProjectDetailOutlinerView.swift -> OutlinerView.swift` is the main scope cliff.
- `ScheduleBoardActions.swift` and `TimelineBoardActions.swift` mix read helpers with mutation entry points.
- schedule calendar overlay still depends on `AppState` publisher wiring, not a narrow client.

## Seam Map

### Required Seams

- `ScheduleTimelineHostState`
  - isolate the schedule/timeline state consumed by the retained host
- `WorkspaceSurfaceProvider`
  - expose only the read projection needed by schedule/timeline
- `ScheduleTimelineCommands`
  - gate write paths so V1a can stay read-first
- `CalendarOverlayClient`
  - isolate read-only overlay refresh from owner-edit commands
- `LogseqProjectPageOpener`
  - replace embedded project detail routing with Logseq open behavior

### Immediate V1a Gates

- remove or gate all project-detail presentation from project selection
- keep `selectedProjectID` highlighting if possible
- block schedule/timeline write actions that still route into broad outliner mutation paths

## File Ownership Map

### Single-Writer Zones

- `import/BUF/App/AppState*.swift`
- `import/BUF/App/AppStateRuntimeProjectionPatch.swift`
- `import/BUF/App/AppStateProjectCommandDispatch.swift`
- `import/BUF/App/AppStateCalendarOwnerCommands.swift`
- `import/BUF/Features/Schedule/ScheduleBoardActions.swift`
- `import/BUF/Features/Timeline/TimelineBoardActions.swift`
- `import/BUF/Features/Timeline/TimelineBoardRefresh.swift`

### Planned Ownership

- orchestrator
  - docs, task packets, integration decisions, final acceptance
- worker A
  - harness recovery only
- worker B
  - dependency/seam extraction after harness exists
- reviewer lane
  - adversarial review only
- tester lane
  - build/runtime/fixture verification only

No parallel implementation is allowed until the harness exists and the first seam pass narrows ownership further.

## Harness Restoration Path

### Confirmed Current State

- no `.xcodeproj`
- no `.xcworkspace`
- no `Package.swift`
- `xcodebuild -list` fails in repo root and `import/BUF`
- `swift build` fails in `import/BUF` because no manifest exists

### Confirmed Recovery Path For Slice 2

1. Create a minimal Apple-native `Package.swift` harness.
2. Treat it as Slice 2 infrastructure-only work.
3. First goal is reproducible compile/run discovery, not full product behavior.
4. Do not mix schedule/timeline behavior changes into the harness slice.

Why this path is confirmed:

- no Xcode project or workspace exists in the checked-in workspace
- no existing SwiftPM manifest exists either
- a SwiftPM manifest is the smallest Apple-native harness addition available inside the allowed toolchain
- Slice 2 acceptance explicitly allows success or reduction to a smaller compile blocker

### Recovery Risks

- the current codebase includes wide feature surfaces not needed by the retained slice
- SwiftPM may force explicit exclusion or conditional compilation for out-of-scope feature files
- resources and app lifecycle wiring may need a narrow host before the package can build cleanly

## Initial Task Packets

### Slice 1 Task Packet: Dependency inventory and shell target

- objective:
  - freeze the retained/deferred file set and the V1a disable list
- files in scope:
  - `docs/plans/ARTIFACT-001-phase-2-gate-pack.md`
  - `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
- files out of scope:
  - all `import/BUF/*.swift`
- commands:
  - `rg --files import/BUF`
  - `rg -n 'TimelineBoard|ScheduleBoard|ProjectDetail|Outliner' import/BUF --glob '*.swift'`
- acceptance:
  - retained set and hot spots are written down
  - single-writer zones are named
- verification:
  - adversarial review confirms no missing Phase 2 blocker in the inventory itself
- ownership and merge boundaries:
  - orchestrator-only
  - no worker merge required
- required inputs:
  - `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
  - `docs/plans/PLAN-001-sync-policy-v1.md`
  - `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`

### Slice 2 Task Packet: Harness recovery

- objective:
  - establish a reproducible Apple-native build/run harness for BUF retained-slice work
- files in scope:
  - new `Package.swift`
  - any minimal companion files required only for the harness to resolve target layout
- files out of scope:
  - schedule/timeline behavior changes
  - sync policy changes
  - project-open flow changes
- commands:
  - `swift package describe`
  - `swift build`
  - `swift run`
- acceptance:
  - the repo contains a concrete build manifest
  - `swift build` reaches either a successful build or a smaller, more specific compile blocker than "no harness exists"
  - the run command path is concrete
- verification:
  - separate review lane checks that the harness slice does not smuggle product behavior
  - separate test lane runs the build and reports the first hard blocker or success
- ownership and merge boundaries:
  - worker A owns `Package.swift` and any minimal manifest-only companion files
  - reviewer lane must not edit worker-owned files
  - tester lane must not edit source files
  - no `import/BUF/**/*.swift` behavior edits are allowed in this slice
- required inputs:
  - `docs/plans/SPEC-001-buf-schedule-timeline-retained-slice.md`
  - `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
  - `docs/plans/ARTIFACT-001-phase-2-gate-pack.md`
  - current discovery result: there is no checked-in `.xcodeproj`, `.xcworkspace`, or `Package.swift`

### Slice 3 Task Packet: Project-open flow and inspector bypass

- objective:
  - route project selection in the retained shell to Logseq page opening instead of the embedded inspector flow
  - gate the V1a-forbidden schedule/timeline mutation actions that still depend on the broad legacy mutation stack
  - introduce a dedicated Logseq graph-root configuration path so project opening does not depend on the legacy Obsidian root setting
- files in scope:
  - new `import/BUF/Utilities/LogseqDeepLinking.swift`
  - `import/BUF/App/AppState.swift`
  - `import/BUF/App/AppStateLaunchAndSetup.swift`
  - `import/BUF/Features/Workspace/MainWorkspaceView.swift`
  - `import/BUF/Features/Workspace/MainWorkspacePanels.swift`
  - `import/BUF/Features/Workspace/MainWorkspaceActions.swift`
  - `import/BUF/Features/Workspace/MainWorkspaceSearch.swift`
  - `import/BUF/Features/Timeline/TimelineBoardActions.swift`
  - `import/BUF/Features/Schedule/ScheduleBoardActions.swift`
  - `import/BUF/Features/Setup/SetupContainerView.swift`
- files out of scope:
  - reminder sync files
  - calendar sync files
  - project-detail host implementation files
  - outliner mutation internals
- commands:
  - `swift build`
  - `swift run BrainUnfogHarness`
- acceptance:
  - the slice introduces and uses a dedicated Logseq graph-root configuration path, separate from the legacy Obsidian root setting
  - selecting a project from timeline, schedule, sidebar, or workspace search opens the matching Logseq page
  - selection highlight uses app-level selected project state, not inspector visibility
  - retained shell no longer depends on inspector being opened to select a project
  - V1a-forbidden actions in `TimelineBoardActions.swift` and `ScheduleBoardActions.swift` are gated so they no longer perform legacy mutation writes from schedule/timeline surfaces
  - no new product behavior outside project-open flow is introduced
- verification:
  - review lane checks that the slice does not expand into sync or detail-host refactors
  - test lane verifies build, launch, one project-open smoke path, and that at least one gated V1a action no longer mutates state
- ownership and merge boundaries:
  - worker B owns the in-scope files above only
  - reviewer lane must not edit worker-owned files
  - tester lane must not edit source files
  - no `ProjectWindow/*` or `Outliner/*` edits are allowed in this slice
- required inputs:
  - `docs/plans/SPEC-001-buf-schedule-timeline-retained-slice.md`
  - `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
  - `docs/plans/PLAN-001-sync-policy-v1.md`
- `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
- `logseq-plugin-materials/repos/official/logseq-docs/pages/Logseq Protocol.md`
- current review finding: using `obsidianProjectsRootURL` as the Logseq graph source is not correct enough for slice acceptance

### Slice 4 Task Packet: Logseq page store and property schema

- objective:
  - add a dedicated Logseq page store that round-trips BUF project pages through `pages/*.md`
  - preserve unrelated user-authored page content while giving BUF an app-managed task section for synced tasks
  - wire the page store into source IO only far enough to prepare the directory, load managed page state, and persist managed page state
- files in scope:
  - new `import/BUF/Services/LogseqPageFilenameCodec.swift`
  - new `import/BUF/Services/LogseqProjectPageStore.swift`
  - `import/BUF/App/AppStateSourceIO.swift`
  - `Package.swift`
  - new `Tests/BrainUnfogHarnessTests/LogseqProjectPageStoreTests.swift`
- files out of scope:
  - reminder sync coordinators
  - calendar sync files
  - workspace routing files
  - project detail host files
  - broad model schema changes
- commands:
  - `swift test --filter LogseqProjectPageStoreTests`
  - `swift build`
  - `swift run BrainUnfogHarness`
- acceptance:
  - the slice introduces a dedicated Logseq page store rooted at the configured graph `pages` directory
  - file resolution is title-based and no longer relies on the legacy UUID-note-store assumption
  - the page store recognizes both supported project-scope tag forms: `tags:: 프로젝트` and `tags:: [[프로젝트]]`
  - the page store manages page properties for project tag scope, `brain_unfog_project_id::`, and `reminder_list_external_id::`
  - the page store uses a dedicated app-managed task section only for BUF-created pages or pages that already carry that managed section; existing synced task blocks outside the managed section must still be readable during Slice 4 and must not be relocated silently
  - non-task page content outside the managed section is preserved byte-stably enough for V1a
  - the managed task section round-trips `brain_unfog_task_id`, completion marker, task title, `date::`, `duration::`, `repeat::`, `reminder_external_id`, and `calendar_event_external_id`
  - the page store writes only to pages already carrying BUF-owned page identity metadata or to pages explicitly created by BUF in this slice
  - `AppStateSourceIO.swift` prepares and uses the page store without opening reminder or calendar fan-out behavior in this slice
- verification:
  - review lane checks that the slice does not smuggle reminder or calendar sync behavior into the page-store slice
  - test lane verifies store parse/render round-trip with preserved non-managed content, graph filename-format coverage, build success, and harness launch success
  - test lane verifies that an existing tagged page with synced tasks outside the managed section is imported read-only in Slice 4 and not rewritten unless BUF ownership is already established
- ownership and merge boundaries:
  - worker B owns the in-scope files above only
  - reviewer lane must not edit worker-owned files
  - tester lane must not edit source files
  - no `import/BUF/Features/Workspace/*`, `ReminderGateway.swift`, or `ScheduleCalendarStore.swift` edits are allowed in this slice
- required inputs:
  - `docs/plans/SPEC-001-buf-schedule-timeline-retained-slice.md`
  - `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
  - `docs/plans/PLAN-001-sync-policy-v1.md`
  - `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
  - `logseq-plugin-materials/repos/official/logseq-docs/pages/Filename format.md`
  - current implementation seam: `ObsidianJournalStore.swift` already uses a user-content-plus-managed-section pattern that Slice 4 may reuse conservatively

### Slice 5 Task Packet: Reminders sync for managed Logseq pages

- objective:
  - close V1 reminder sync for Logseq project pages and their managed task section without reopening the legacy outliner sync surface
  - bootstrap from in-scope Logseq project pages, creating and binding reminder lists or reminder items when no safe existing binding exists yet
  - import shared reminder fields from managed Logseq pages during bootstrap or repair through bounded owner-command paths
  - fan out local or remote reminder field changes back into the Logseq page store after scoped recompute
  - add an explicit reminder recurrence write path so `repeat::` no longer dead-ends locally
- files in scope:
  - `docs/plans/ARTIFACT-001-phase-2-gate-pack.md`
  - `import/BUF/App/AppCommand.swift`
  - `import/BUF/App/AppStateReminderOwnerCommands.swift`
  - `import/BUF/App/AppStateSourceIO.swift`
  - `import/BUF/App/AppStateSyncAndPersistence.swift`
  - `import/BUF/Services/ReminderGateway.swift`
  - `import/BUF/Services/LogseqProjectPageStore.swift`
  - new small Logseq/reminder sync helper if needed
  - new `Tests/BrainUnfogHarnessTests/*` coverage for the Slice 5 helper path
- files out of scope:
  - calendar owner commands and calendar event mutation files
  - workspace routing files
  - project detail host files
  - file watcher infrastructure beyond bootstrap or explicit repair entry
  - fuzzy or title-only claim of unmatched reminder lists or tasks
  - relocating or rewriting unmanaged external task blocks outside the managed section
- commands:
  - `swift test --filter LogseqReminder`
  - `swift test --filter ReminderOwner`
  - `swift build`
  - `swift run BrainUnfogHarness`
- acceptance:
  - bootstrap scans Logseq pages that are already BUF-owned or that are deterministically in project scope by the agreed project tag rule
  - bootstrap creates and binds reminder lists for in-scope Logseq pages when no safe existing list binding exists yet
  - bootstrap creates and binds reminder items for in-scope managed task blocks when no safe existing task binding exists yet
  - bootstrap or repair import reads shared fields from the managed Logseq task section and applies them through reminder-owner mutations or existing bounded command paths instead of raw storage rewrites
  - shared project or task field convergence covers project title, task title, completion, `date::`, and `repeat::`
  - `duration::` stays Logseq plus BUF-local only in Slice 5 and does not expand into calendar writes here
  - explicit reminder recurrence writes are supported end-to-end for V1 `repeat::` values
  - reminder owner writes and reminder external changes both fan out the normalized result back into the Logseq page store for the affected managed projects
  - unmatched reminder adoption exists in this slice but stays deterministic and conservative: internal-ID match, external-ID match, or other packet-defined safe criteria only; title-only binding is never allowed
  - pages with unmanaged external task blocks outside the managed section remain readable but read-only in this slice and must not be claimed, relocated, or duplicated
  - first-sync behavior for unmatched remote reminder objects remains conservative: no hijack and no duplicate remote object creation from title-only matching
- verification:
  - review lane checks that the slice stays inside managed-page reminder sync and does not smuggle calendar or broad watcher work
  - test lane verifies deterministic EventKit fixture preflight, isolated run-ID container setup, execution, and teardown before calling the slice accepted
  - test lane verifies one bootstrap scenario creates the missing reminder list and missing reminder items once from an in-scope Logseq page, one reminder external change round-trips back to the page store once, recurrence writes pass through the new reminder mutation path, build succeeds, and the harness still launches
  - test lane verifies an unclaimed reminder adoption case succeeds only on the defined safe criteria and does not hijack an unrelated reminder by title alone
- ownership and merge boundaries:
  - worker lane owns the in-scope files above only
  - reviewer lane must not edit worker-owned files
  - tester lane must not edit source files
  - no `import/BUF/App/AppStateCalendarOwnerCommands.swift`, `import/BUF/Services/ScheduleCalendarStore.swift`, or `import/BUF/Features/Workspace/*` edits are allowed in this slice
- required inputs:
  - `docs/plans/SPEC-001-buf-schedule-timeline-retained-slice.md`
  - `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
  - `docs/plans/PLAN-001-sync-policy-v1.md`
  - `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
  - current implementation seams:
    - `handleReminderOwnerFieldWrite` already provides bounded title, schedule, completion, and scoped recompute behavior
    - `LogseqProjectPageStore` already round-trips managed task properties and preserves external user content
    - Slice 5 must extend those seams instead of introducing a second reminder-sync engine

### Slice 6 Task Packet: BUF-owned calendar sync for managed schedule fields

- objective:
  - project eligible managed Logseq tasks into one BUF-owned Apple Calendar without making foreign calendars writable
  - round-trip `date::` and `duration::` between Logseq, BUF runtime state, and owned `EKEvent` records
  - fan out owned-calendar changes back into the Logseq page store after scoped recompute
- files in scope:
  - `docs/plans/ARTIFACT-001-phase-2-gate-pack.md`
  - `import/BUF/App/AppStateCalendarOwnerCommands.swift`
  - `import/BUF/App/AppStateProjectActions.swift`
  - `import/BUF/App/AppStateSourceIO.swift`
  - `import/BUF/App/AppStateSyncAndPersistence.swift`
  - `import/BUF/App/AppStateRuntimeProjectionPatch.swift`
  - `import/BUF/App/AppStateSidecarOwnerCommands.swift`
  - `import/BUF/Features/Outliner/OutlinerSessionSnapshot.swift`
  - `import/BUF/Services/ScheduleCalendarStore.swift`
  - new small owned-calendar sync helper if needed
  - new `Tests/BrainUnfogHarnessTests/*` coverage for the owned-calendar path
- files out of scope:
  - reminder list or reminder item bootstrap rules already closed in Slice 5
  - workspace routing files
  - project detail host files
  - foreign calendar mutation
  - recurring series expansion beyond the existing schedule-calendar edit scope
- commands:
  - `swift test --filter Calendar`
  - `swift test`
  - `swift build`
  - `swift run BrainUnfogHarness`
- acceptance:
  - only tasks with explicit scheduled time and explicit duration become owned calendar events
  - BUF creates or reuses one dedicated owned Apple Calendar and writes only there
  - owned event identity is stored in exactly one BUF runtime seam and round-trips to `calendar_event_external_id::` in the managed Logseq task section
  - foreign calendar events remain read-only overlays in the schedule view
  - local task schedule edits converge through BUF into the owned event and back into Logseq once
  - external owned-calendar edits converge through scoped recompute and back into Logseq once
  - Slice 6 must not introduce a second parallel schedule sync engine; it must extend the existing sidecar/runtime projection seams
- verification:
  - review lane checks that the slice chooses one owned-event identity seam only and does not make foreign calendars writable
  - test lane verifies deterministic EventKit fixture setup for the owned calendar, one eligible task creates exactly one owned event, moving that event updates the linked task once, and build plus harness launch still pass
  - test lane verifies a due-date-only task does not create an owned event
- ownership and merge boundaries:
  - worker lane owns the in-scope files above only
  - reviewer lane must not edit worker-owned files
  - tester lane must not edit source files
  - no `import/BUF/App/AppStateReminderOwnerCommands.swift` or Logseq page-parser format changes are allowed in this slice unless required for the `calendar_event_external_id::` round-trip itself
- required inputs:
  - `docs/plans/SPEC-001-buf-schedule-timeline-retained-slice.md`
  - `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
  - `docs/plans/PLAN-001-sync-policy-v1.md`
  - `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
  - current implementation discovery:
    - `ScheduleCalendarStore` already provides owned-event timing mutation for existing `EKEvent` records but does not create BUF-owned events from tasks today
    - `LogseqProjectPageStore` already round-trips `calendar_event_external_id::`
    - `ReminderTaskFeatureSidecarRecord` is the narrowest live per-task seam currently carrying `scheduledDurationMinutes`
    - `CalendarEventMirrorRecord` exists in normalized persistence but is not wired into the retained slice; Slice 6 must either activate that dormant seam or explicitly stay on the task-feature sidecar path, not both

### Slice 7 Task Packet: Hardening and repair-safe paths

- objective:
  - move duplicate IDs, orphan bindings, damaged hidden properties, and rename-loop cases into repair-safe paths
  - keep Slice 5 and Slice 6 from writing through ambiguous identity states
- files in scope:
  - `docs/plans/ARTIFACT-001-phase-2-gate-pack.md`
  - `import/BUF/App/AppStateSourceIO.swift`
  - `import/BUF/App/AppStateReminderOwnerCommands.swift`
  - `import/BUF/App/AppStateCalendarOwnerCommands.swift`
  - `import/BUF/App/AppStateSyncAndPersistence.swift`
  - `import/BUF/Services/LogseqProjectPageStore.swift`
  - new small sync-hardening helper if needed
  - new `Tests/BrainUnfogHarnessTests/*` coverage for repair-safe paths
- files out of scope:
  - new user-facing repair UI
  - broad watcher infrastructure beyond the existing bootstrap or explicit invalidation entry points
  - schedule or timeline rendering changes
- commands:
  - `swift test --filter Logseq`
  - `swift test --filter Reminder`
  - `swift test`
  - `swift build`
  - `swift run BrainUnfogHarness`
- acceptance:
  - duplicate local page or task identities block writeback instead of selecting an arbitrary winner
  - damaged hidden ID combinations enter conservative skip or repair paths instead of silent rebind
  - reminder and calendar external duplicates do not mutate arbitrary remote objects
  - rename-related echo paths no longer duplicate or bounce through Logseq writeback
  - periodic or explicit repair entry recomputes only bounded scope and does not crash when ambiguity remains unresolved
- verification:
  - review lane checks that ambiguity paths fail closed instead of silently choosing one object
  - test lane verifies duplicate local identity cases, damaged hidden-property cases, and remote duplicate cases all skip writeback without crashing or duplicating data
  - test lane verifies build plus harness launch still pass after the hardening slice
- ownership and merge boundaries:
  - worker lane owns the in-scope files above only
  - reviewer lane must not edit worker-owned files
  - tester lane must not edit source files
  - no workspace navigation or board UI edits are allowed in this slice
- required inputs:
  - `docs/plans/SPEC-001-buf-schedule-timeline-retained-slice.md`
  - `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`
  - `docs/plans/PLAN-001-sync-policy-v1.md`
  - `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
  - current implementation discovery:
    - Slice 5 already closed conservative reminder adoption and claim paths for the managed Logseq page store
    - duplicate local identity and orphan repair behavior is still incomplete and must be completed before the slice is accepted

## Next Action

Current next action is no longer another behavior slice.

The remaining gate is the fixture harness:

- add deterministic EventKit fixture setup/reset/teardown for the owned calendar path
- prove authorization preflight for Calendar and Reminders before fixture creation
- verify one eligible managed task creates exactly one owned event, moving that event updates the linked task once, due-date-only tasks do not create owned events, and orphan/duplicate repair-safe paths stay fail-closed

Until that fixture harness passes, release acceptance remains blocked even though Slices 2 through 7 pass build/test/runtime gates.
