# SPEC-001: BUF schedule/timeline retained slice

## Status
Draft

## Date
2026-04-23

## Related Docs

- `docs/decisions/ADR-001-buf-logseq-eventkit-architecture.md`
- `docs/plans/PLAN-001-sync-policy-v1.md`
- `docs/plans/PLAN-002-schedule-timeline-extraction-spec-driven.md`

## Objective

Build a macOS-native retained product slice that keeps only BUF's schedule and timeline views, then connects that slice to:

- Logseq file graph pages
- Apple Reminders
- a BUF-owned Apple Calendar

Success means:

- schedule and timeline can run without the full legacy BUF product surface
- selecting a project in BUF opens the matching Logseq page instead of the embedded project detail flow
- reminders sync follows `page=list`, `task=reminder`, with plain bullets, ordering, and nesting staying Logseq-only
- calendar editing is limited to BUF-owned events while foreign calendar events stay read-only overlays

Temporary host-shell decision for Phase 1:

- recover the existing `BUFApp.swift` app entry through a SwiftPM harness candidate first
- do not design a new narrow host before the harness slice finishes
- reevaluate host narrowing only after the harness exists and the retained slice can actually build

## Commands

Current workspace discovery commands:

- build-harness discovery: `find . -maxdepth 4 \( -name '*.xcodeproj' -o -name '*.xcworkspace' -o -name 'Package.swift' \)`
- xcode project discovery check: `cd "/Users/three/app_build/logseq plugin/import/BUF" && xcodebuild -list`
- SwiftPM discovery check: `cd "/Users/three/app_build/logseq plugin/import/BUF" && swift build`

Current result:

- no `.xcodeproj`
- no `.xcworkspace`
- no `Package.swift`
- no executable build command exists yet for `BUF`

Target commands after Slice 2 harness recovery:

- build: `swift build`
- run: `swift run`
- verification build discovery: `swift package describe`

If the recovered harness ends up using a different Apple-native command, the spec must be updated before behavior slices begin.

## Project Structure

Relevant current structure:

- `import/BUF/BUFApp.swift`
  app entry point
- `import/BUF/App/`
  `AppState`, launch/setup, workspace routing, calendar/reminder owner commands
- `import/BUF/Features/Schedule/`
  schedule board views, layout, overlays, interaction helpers
- `import/BUF/Features/Timeline/`
  timeline board views, overlays, actions, refresh support
- `import/BUF/Features/Workspace/`
  current workspace shell, panel routing, overlays, inspector flow
- `import/BUF/Features/ProjectWindow/`
  project detail host that must leave the retained slice
- `import/BUF/Features/Outliner/`
  currently required runtime model floor feeding the board projections
- `import/BUF/Services/`
  projection readers, Logseq/Obsidian stores, Reminders/Calendar services
- `import/BUF/Persistence/`
  local storage and workspace sidecar persistence
- `docs/decisions/`
  ADRs
- `docs/plans/`
  spec, plans, task packets, phase artifacts

## Code Style

Project style is narrow and composition-first:

```swift
struct RootSceneView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    Group {
      if let modelContainer = appState.modelContainer {
        MainWorkspaceView()
          .modelContainer(modelContainer)
      } else if appState.isLaunching {
        StartupPlaceholderView()
      } else {
        SetupContainerView()
      }
    }
  }
}
```

Required style rules for this effort:

- keep changes minimal and scope-bound
- prefer explicit adapters over broad refactors
- preserve existing Korean user-facing strings unless the slice requires new copy
- do not introduce new files over 800 lines
- prefer extracting a seam over copying large bodies of logic
- keep write-path changes out of V1a unless a plan slice explicitly allows them

## Testing Strategy

Phase-gated verification applies:

- static verification
  - spec/plan alignment
  - adversarial review by a separate Codex sub-agent session
- build verification
  - requires Slice 2 harness recovery first
  - build command must be reproducible from the repo root or the recovered harness root
- runtime verification
  - the retained shell launches
  - schedule/timeline smoke flow works
  - project selection opens the expected Logseq page
- sync verification
  - allowed only after fixture harness rules exist
  - EventKit fixture runs must use isolated reminder/calendar containers
  - authorization preflight must pass before fixture setup begins

Until the harness exists, only documentation, dependency inventory, and harness-recovery work are valid.

## Boundaries

### Always

- keep scope limited to the schedule/timeline retained slice and the sync plumbing required by that slice
- use BUF as the only sync reconciliation hub
- follow PLAN-001 sync policy as written
- keep implementation, review, and test ownership separated
- preserve stable IDs and avoid title-only identity logic

### Ask First

- broad stored-data model renames
- scope expansion beyond schedule/timeline plus required Logseq/Reminders/BUF-owned Calendar sync
- dependency additions outside the current Apple/native toolchain
- automatic destructive delete propagation across sync targets

### Never

- rebuild the whole legacy BUF product surface
- mirror Logseq bullet ordering or nesting into Reminders
- make foreign calendars writable in V1
- depend on hidden Logseq properties as a correctness boundary
- skip harness, review, or test gates

## Success Criteria

- `SPEC-001`, `PLAN-001`, `PLAN-002`, and the phase artifacts agree on retained scope
- a concrete Apple-native build harness exists
- the retained shell reaches schedule and timeline without requiring the embedded project detail host
- project selection opens a Logseq page through the defined opener path
- Reminders sync keeps `page=list`, `task=reminder`, `bullet/order/nesting=Logseq-only`
- BUF-owned Calendar sync is the only writable calendar path in V1
- each implementation slice has an explicit task packet, separate review lane, and separate test lane

## Open Questions

- whether the SwiftPM harness remains sufficient after the first successful build, or whether a narrower host must replace it immediately after Slice 2
- how much of the existing workspace shell can be reused before a narrower host must exist
- whether V1a can avoid compiling Compass and Journal code paths entirely during harness recovery
