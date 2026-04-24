# PLAN-002: Extract BUF schedule and timeline as the only retained product slice

## Status
In Progress

## Date
2026-04-23

## Related Docs

- `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
- `docs/plans/PLAN-001-sync-policy-v1.md`

## Objective

Build a new product slice that keeps only the BUF schedule view and timeline view, then connects that slice to:

- Logseq file graph pages
- Apple Reminders
- a BUF-owned Apple Calendar

The rest of BUF is not the product target.

Success means:

- schedule and timeline are reusable without carrying the whole legacy app
- project selection opens the matching Logseq page
- Reminders sync follows `page=list`, `task=reminder`, `bullet/order/nesting=Logseq-only`
- the implementation path is spec-driven and agent-orchestrated

## Delivery Strategy

The retained slice will not start as a full editable clone of current BUF behavior.

V1 extraction strategy:

- `V1a`: read-first extraction
  - retain schedule and timeline rendering
  - retain project selection and Logseq page opening
  - retain foreign calendar overlays
  - disable non-essential task mutation actions until seams exist
- `V1b`: re-enable bounded writes
  - task completion
  - explicit schedule/date writes
  - owned calendar event writes

This avoids dragging the whole legacy mutation stack into the first extraction cut.

## Assumptions

These are the assumptions this plan is making now:

1. The target platform is macOS, not a Logseq plugin.
2. The retained UI surface is only schedule and timeline.
3. Inspector/detail window, detached project window, and unrelated BUF feature surfaces are not required for V1.
4. Only installed addyosmani `agent-skills` workflows are allowed for planning and execution.
5. The workspace now has a SwiftPM harness (`Package.swift`) and reproducible `swift build` / `swift test` / `swift run --skip-build BrainUnfogHarness` commands.
6. The current Codex session already has sub-agents, harness tooling, and the installed [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills) skills available, so orchestration must stay inside that installed toolchain.

## Boundaries

### Always

- keep scope limited to schedule/timeline extraction and sync plumbing needed by that slice
- keep decisions grounded in the written spec and plan docs
- use BUF as the only sync reconciliation hub
- preserve stable IDs when moving data between Logseq, Reminders, and Calendar
- use agent-orchestrated review and test delegation for every implementation slice

### Ask First

- broad model renames that affect stored data
- any expansion beyond schedule/timeline retained product scope
- dependency additions outside the current Apple/native toolchain
- automatic destructive delete propagation across sync targets

### Never

- rebuild the whole BUF app as the shipped product
- mirror Logseq bullet order or nesting into Reminders
- make foreign user calendars writable in V1
- rely on hidden Logseq properties as an integrity boundary
- let an implementation slice proceed without a verification harness

## Execution Toolchain Contract

This effort is constrained to the installed Codex toolchain only.

Allowed execution building blocks:

- Codex main agent as orchestrator
- Codex sub-agent sessions as the concrete delegation primitive for explorer, worker, reviewer, and tester roles
- Codex harness stages defined in this plan
- installed addyosmani [`agent-skills`](https://github.com/addyosmani/agent-skills) workflows already available in Codex

Disallowed process additions:

- external orchestration frameworks
- ad hoc process that bypasses the written harness gates
- non-`agent-skills` workflow as the governing delivery method

Interpretation:

- the main agent owns orchestration
- spawned Codex sub-agent sessions execute bounded delegated work packets
- harness stages are the only acceptance path
- `agent-skills` define the phase workflow and quality gates
- if a separate sub-agent lane is temporarily unavailable, the main agent must record that fallback explicitly and run the equivalent review or test skill sequentially instead of silently collapsing the lane

## Commands and Harness Status

Current workspace observation:

- no `.xcodeproj`
- no `.xcworkspace`
- `Package.swift` exists and builds the retained harness target `BrainUnfogHarness`

Current harness state:

- stage 0 `intake harness`: complete
- stage 1 `spec harness`: complete
- stage 2 `code harness`: complete
- stage 3 `runtime harness`: complete
- stage 4 `fixture harness`: not complete

Planned harness stages:

0. `intake harness`
   - task packet
   - scope freeze
   - target file and command list
1. `spec harness`
   - document review
   - dependency inventory
   - extraction seam checklist
2. `code harness`
   - host app or project restoration
   - reproducible build command
   - reproducible test command
3. `runtime harness`
   - app launch
   - schedule/timeline smoke flow
   - sync scenario checks
4. `fixture harness`
   - deterministic Logseq graph fixtures
   - deterministic owned/unowned reminder fixtures
   - deterministic owned/unowned calendar fixtures
   - rename, bootstrap, duplicate-ID, and repair scenarios

Until stage 4 exists, sync safety is not considered verified.

Current release-gate note:

- Slices 2 through 7 have landed in code and pass local build/test/runtime checks.
- The remaining blocker is deterministic EventKit fixture coverage for the owned-calendar path and the repair-safe sync paths.

Fixture harness operating rules:

- fixture setup begins only after explicit authorization preflight for both Reminders and Calendar passes
- if either permission is missing, denied, restricted, or otherwise not writable enough for the slice, the run fails closed before creating any fixture container
- every run uses an isolated run ID
- every EventKit fixture object must be created inside a test-only container whose name carries that run ID
- owned reminder lists and owned calendars created for tests must be tagged as BUF test fixtures and never reuse user containers
- the tester records created fixture identifiers before exercising the slice
- teardown deletes only containers and objects created for that run ID
- a run is not deterministic unless setup, execution, and teardown all complete cleanly

## Product Slice Definition

### Keep

- schedule rendering and interaction surface
- timeline rendering and interaction surface
- read models and projection services that feed schedule and timeline
- Apple Calendar overlay read support required by schedule
- task/project selection state needed by those two views

### Drop From V1 Product Scope

- project detail host
- detached project window
- unrelated boards and feature surfaces
- any workflow that requires keeping the full multi-app shell concept from BUF

### Disable First In V1a

- timeline task move and root-structure mutation actions
- schedule task deletion actions
- project create/delete/archive actions from schedule/timeline surfaces
- any action that still requires the full project-detail/outliner mutation loop

### Replace With New Adapters

- Logseq project page opener
- Logseq graph page/task store
- Reminders sync adapter
- Calendar ownership adapter
- narrowed workspace shell that hosts only schedule/timeline

## Spec-Driven Delivery Model

Only the installed addyosmani `agent-skills` workflows are used.

Planned workflow sequence:

1. `agent-skills:using-agent-skills`
   - choose the active workflow and confirm the phase gate
2. `agent-skills:context-engineering`
   - narrow the working set to the exact file and contract surface
3. `agent-skills:spec-driven-development`
   - create and maintain the living spec
4. `agent-skills:source-driven-development`
   - confirm Logseq and Apple contract details against source material
5. `agent-skills:documentation-and-adrs`
   - keep ADR and plan docs in sync with decisions
6. `agent-skills:planning-and-task-breakdown`
   - derive ordered work slices
7. `agent-skills:incremental-implementation`
   - implement each slice with narrow file ownership
8. `agent-skills:test-driven-development`
   - define and run verification before behavior changes are accepted
9. `agent-skills:code-review-and-quality`
   - adversarial review before merge of each slice

No non-`agent-skills` process should be used as the governing workflow for this effort.

The installed skill source for this workflow is:

- [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)

## Orchestration Model

Codex main agent is the orchestrator.

### Main Agent Responsibilities

- keep the spec and plan authoritative
- decide implementation order
- assign work to sub-agents with disjoint ownership
- integrate results
- enforce review and test gates before moving to the next slice
- keep a per-slice `Task Packet` with files, commands, out-of-scope, and acceptance

### Task Packet Contract

Every delegated slice must carry a concrete packet with:

- objective
- exact files in scope
- exact files out of scope
- commands to run
- acceptance criteria
- verification steps
- ownership and merge boundaries
- required inputs from spec and plan

Delegation is incomplete if any of those fields are missing.

### Explorer Agents

Use explorer agents for:

- dependency inventory
- extraction seam analysis
- adversarial plan review
- verification result interpretation

Current planning-round role split:

- explorer lane: dependency inventory and coupling-risk discovery
- adversarial review lane: attack plan gaps before implementation
- process lane: validate harness shape, task packets, and delegation boundaries
- main lane: integrate findings and keep the docs authoritative

### Worker Agents

Use worker agents for:

- bounded code changes in disjoint file sets
- adapter creation
- harness additions
- test additions

Worker rule:

- each worker gets explicit file ownership
- workers are told other agents may also edit the repo
- workers must not revert unrelated changes

### Review Agents

Every completed slice gets an adversarial review pass by a separate agent before acceptance.

### Test Agents

Verification is delegated separately from implementation when possible:

- one agent implements
- one agent runs the relevant harness and reports results
- the main agent resolves mismatches and decides whether the slice passes

Review and test are never satisfied by the implementing worker alone.

Concrete delegation rule:

- each role lane uses a distinct spawned Codex sub-agent session when delegation is available
- reviewer and tester lanes must not reuse the implementing worker session
- if delegation is blocked by tool availability in a given turn, the main agent must log the fallback and run the corresponding installed `agent-skills` workflow sequentially

### Parallelism Rule

- `SPEC`, `ADR`, and `PLAN` are always sequential and single-agent owned
- only after the plan is approved can implementation parallelize
- implementation parallelism is capped at two worker agents at once
- review and test stay independent from the implementing worker
- no parallel worker split is allowed before seam creation makes file ownership genuinely disjoint

### Single-Writer Zones

These areas are treated as single-writer zones:

- `import/BUF/App/AppState*.swift`
- shared sync model and runtime projection patching
- shared service files that define write contracts
- `import/BUF/Features/Schedule/ScheduleBoardActions.swift`
- `import/BUF/Features/Timeline/TimelineBoardActions.swift`
- `import/BUF/Features/Timeline/TimelineBoardRefresh.swift`

No two worker agents should own the same single-writer zone in the same round.

## Current Extraction Inventory

### Keep First

- board UI surfaces: `import/BUF/Features/Schedule/*`, `import/BUF/Features/Timeline/*`
- projection and layout services: `ScheduleProjectionService.swift`, `TimelineProjectionService.swift`, `TimelineService.swift`
- schedule rendering helpers: `ScheduleEventStores.swift`, `ScheduleInteractionLayers.swift`, `ScheduleDayTimelineLayoutEngine.swift`, `ScheduleCollisionDetector.swift`, `ScheduleEventRenderingLayer.swift`
- shared ordering and navigation types: `ProjectOrdering.swift`, `WorkspaceNavigation.swift`
- read-path core: `ReminderRuntimeProjectionReadModelService.swift`
- calendar ownership path needed for schedule editing: `ScheduleCalendarStore.swift`, `AppStateCalendarServiceRegistry.swift`, `AppStateCalendarOwnerCommands.swift`

### Drop First

- `import/BUF/Features/Compass/*`
- `import/BUF/Features/Journal/*`
- `import/BUF/Features/Setup/*`
- `import/BUF/Features/Settings/*`
- `import/BUF/Features/Archive/*`
- `import/BUF/Features/ProjectWindow/*`
- detached project window controllers
- most of `import/BUF/Features/Workspace/*` once a narrow host exists

### Seams To Add

- `ScheduleTimelineHostState`
  - replaces direct broad `AppState` reads with a narrow state interface
- `WorkspaceSurfaceProvider`
  - exposes only the workspace surface projection needed by schedule/timeline
- `ScheduleTimelineCommands`
  - wraps complete, schedule, reorder, create, archive, and navigation writes
- `CalendarOverlayClient`
  - wraps overlay refresh and owned-event actions
- shared overlay support extraction
  - split shared overlay types out of timeline-only files where schedule currently reaches across
- write-capability gates
  - explicit flags or adapters that keep V1a read-first and only reopen writes after verification

### Biggest Coupling Risks

- read-path coupling
  - schedule/timeline currently depend on `ReminderRuntimeProjectionReadModelService.swift`
- write-path coupling
  - editing flows route through `AppStateProjectCommandDispatch.swift` and `AppStateRuntimeProjectionPatch.swift`
- calendar coupling
  - `AppStateCalendarOwnerCommands.swift` recomputes projection state after event edits
- UI support leakage
  - schedule currently reuses timeline support types
- outliner type gravity
  - outliner runtime and DTO types are still mixed into large files, so careless extraction can pull half the outliner along

## Phase Gates

### Phase 1: Specify

Artifact:

- `SPEC-001` saved under `docs/plans/`
- ADR and sync policy are aligned with the retained product slice
- this extraction plan is written and reviewed
- host-shell decision is explicit

Gate:

- extraction boundaries are explicit
- sync model remains narrow and asymmetric
- V1a disabled actions are explicit

### Phase 2: Plan

Artifact:

- dependency inventory
- seam map
- file ownership map
- implementation slices
- test and review delegation map

Gate:

- each slice is small enough to verify independently
- no slice requires moving more than one major risk at once

### Phase 3: Tasks

Artifact:

- ordered task list with acceptance and verification per slice
- per-slice task packet ready for delegation

Gate:

- each task has a clear owner, file set, and harness step
- review and test ownership are assigned before implementation starts

### Phase 4: Implement

Artifact:

- verified code slices landed one at a time

Gate:

- build/test/runtime verification passes for each completed slice
- harness-recovery slices are allowed before product-behavior slices only to establish stage 2

## Workstreams

### Workstream A: Extraction and Narrow Shell

Goal:

- host only schedule/timeline in a narrowed application shell

Needs:

- remove inspector-first assumptions from retained flow
- replace project-open behavior with Logseq page opening
- choose temporary host strategy before creating a new shell

Host decision:

- reuse the existing app entry flow as the temporary harness if the missing project shell can be restored
- only create a new narrow host after schedule/timeline seams exist
- do not design a brand-new shell and extraction seams at the same time

### Workstream B: Logseq Graph Adapters

Goal:

- read/write only the project page and synced task subset

Needs:

- page detection by `tags:: 프로젝트` or `tags:: [[프로젝트]]`
- managed-page handling when internal IDs exist even after visible tag changes
- visible user properties
- hidden internal linkage properties

### Workstream C: Reminders Sync

Goal:

- sync `page=list`, `task=reminder`

Needs:

- flatten Logseq tasks
- ignore plain bullets, nesting, and order on the Reminders side
- preserve linkage IDs

### Workstream D: Calendar Sync

Goal:

- sync only eligible scheduled tasks into a BUF-owned calendar

Needs:

- `date::` and `duration::`
- owned-event identity tracking
- foreign calendar overlay remains read-only

### Workstream E: Harness and Verification

Goal:

- restore or create build/test/runtime harness needed to prove each slice works

Needs:

- host project or app shell restoration
- executable build command
- executable test command
- smoke scenario checklist
- deterministic sync fixtures
- fixture setup/reset/teardown rules for EventKit-backed verification

## Implementation Slices

### Slice 1: Dependency Inventory and Shell Target

Acceptance:

- we know exactly which modules stay, which drop, and which become adapters
- the single-writer zones are named before worker delegation begins
- the V1a disable list is fixed before code changes begin

Verify:

- reviewed dependency map saved to docs

### Slice 2: Host Harness Recovery

Acceptance:

- there is a runnable host project or equivalent build harness
- the temporary host decision is explicit: reused existing shell or replacement shell

Verify:

- reproducible build command exists
- app can launch
- harness-recovery slice is documented as infrastructure-only and not counted as product behavior delivery

### Slice 3: Narrow Shell and Project Open Flow

Acceptance:

- retained shell hosts only schedule/timeline path
- project selection opens Logseq page instead of project detail surface
- V1a disabled actions are removed or gated

Verify:

- app launch smoke flow reaches schedule and timeline
- project click opens the expected Logseq page

### Slice 4: Logseq Page Store and Property Schema

Acceptance:

- project pages and synced tasks round-trip through the agreed property schema

Verify:

- page read/write smoke scenario preserves unrelated user content

### Slice 5: Reminders Sync

Acceptance:

- project title, task title, completion, `date::`, and `repeat::` converge between Logseq and Reminders

Verify:

- first-sync scenario does not duplicate reminders
- task edits round-trip once
- unclaimed reminder adoption does not hijack unrelated reminders

### Slice 6: Calendar Sync

Acceptance:

- eligible tasks create one owned event each
- `date::` and `duration::` round-trip between Logseq, BUF, and owned Calendar events

Verify:

- moving one owned event updates the linked task once
- foreign events remain read-only

### Slice 7: Hardening

Acceptance:

- rename loops, ID damage, orphan cases, and duplicate cases enter repair-safe paths

Verify:

- repair scenarios execute without crashes or silent duplication
- duplicate local ID scenarios enter repair instead of writeback

## Task Ownership Model

Planned ownership split for implementation:

- worker A: shell narrowing and navigation replacement
- worker B: Logseq page store and property schema
- worker C: reminders adapter and bootstrap policy
- worker D: calendar adapter and owned-event policy
- worker E: harness recovery and verification fixtures
- reviewer agent: adversarial review of each merged slice
- tester agent: build/test/runtime verification after each slice

The main agent owns integration and conflict resolution.

Delegation rule:

- no worker self-approves
- no reviewer validates their own implementation
- no tester validates a slice they implemented
- the main agent is the only role allowed to accept or reject a slice after review and harness output
- each delegated lane must reference the spawned sub-agent session or the documented sequential fallback

## Verification Policy

Each slice must have all three where possible:

- static verification
  - spec compliance
  - code review
- build verification
  - project builds cleanly
- runtime verification
  - the app launches
  - schedule/timeline smoke flows work
  - sync scenario relevant to that slice works once without loops

No later slice should begin while the prior slice lacks a passing verification story.

EventKit fixture rule:

- testers must prove authorization preflight passed before fixture setup begins
- test runs must use isolated reminder-list and calendar containers created for that run
- testers must prove cleanup completed, or the run is not considered trustworthy

## Risks

- the current source snapshot may be missing the executable project shell
- schedule/timeline may depend on wider AppState surfaces than expected
- page rename plus file rename can cause watcher echo loops
- user edits to hidden IDs can still break linkage
- repeat semantics may diverge between Logseq and Reminders if not constrained tightly

## Immediate Next Step

Do not start implementation yet.

Next action:

- derive the dependency inventory and seam map for schedule/timeline extraction
- confirm the build harness restoration path
- then split into worker-owned implementation slices
- issue the first concrete task packets only after those three artifacts exist
