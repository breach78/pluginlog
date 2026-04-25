# TASK-PACKET-010: PLAN-006 Phase 3a Obsidian Vault Setup Seams

## Objective

Add the non-destructive Obsidian vault setup seams needed before replacing the
Logseq graph setup UI.

## Scope

- Add `ObsidianVaultPreferenceResolver` for stored path plus security bookmark
  resolution, mirroring the existing Logseq resolver behavior.
- Add `ObsidianVaultLayout` to prepare app-owned directories:
  - `<vault>/.buf`
  - `<vault>/raw/projects`
- Add a lightweight vault candidate check:
  - existing `.obsidian` directory means valid Obsidian vault
  - `.obsidian` as a file or invalid node is not a valid vault
  - missing `.obsidian` is only a candidate; this slice must not create it
  - candidate detection is read-only and must not create `.buf` or `raw/projects`
- Keep setup/runtime unchanged; no UI cutover yet.

## Non-Goals

- Do not replace first-run Logseq graph setup.
- Do not write UserDefaults keys from runtime code.
- Do not create `.obsidian`.
- Do not install or auto-enable an Obsidian helper plugin.
- Do not move existing Obsidian notes into `raw/projects/`.
- Do not delete Logseq source, preferences, or user data.
- Do not delete, rename, move, or rewrite existing Obsidian vault contents.
- Do not add third-party dependencies.
- Do not change Reminders or Calendar sync behavior.

## Likely Files

- `import/BUF/App/ObsidianVaultPreferenceResolver.swift`
- `import/BUF/Services/ObsidianVaultLayout.swift`
- `Tests/BrainUnfogHarnessTests/ObsidianVaultPreferenceResolverTests.swift`
- `Tests/BrainUnfogHarnessTests/ObsidianVaultLayoutTests.swift`

## Implementation Lane

- Keep this as pure setup infrastructure.
- Do not reference the new resolver/layout from `AppState` yet.
- Directory creation is limited to `.buf` and `raw/projects`, and only after
  `.obsidian` is confirmed to be an existing directory.
- `.obsidian` detection is read-only.
- No Calendar/EventKit imports.

## Review Lane

Review adversarially for:

- accidental setup/runtime cutover
- `.obsidian` auto-creation
- helper plugin auto-enable
- user data deletion/move
- whole-vault scans
- Calendar policy regression
- Ask First violations

## Test Lane

Add focused tests for:

- resolver uses bookmark when stored path matches bookmark
- resolver prefers stored path when bookmark points elsewhere
- resolver falls back to stored path when bookmark fails
- layout prepares `.buf` and `raw/projects`
- layout does not create `.obsidian` for candidate folders
- layout detects existing `.obsidian`
- layout treats `.obsidian` regular file as candidate, not valid vault
- layout does not create `.buf` or `raw/projects` for candidate folders
- layout does not create legacy attachment/history/archive folders

## Build/Test/Runtime Gate

- `swift test --filter ObsidianVaultPreferenceResolverTests`
- `swift test --filter ObsidianVaultLayoutTests`
- `swift test --filter RetainedSetupFlowTests`
- `rg -n "ObsidianVaultPreferenceResolver|ObsidianVaultLayout" import/BUF/App/AppState* import/BUF/Features`
  must return no runtime cutover matches.
- `swift build`
- `swift test`
- Because this slice changes code, quit existing Brain Unfog app and relaunch
  `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app` after
  build/test pass.

## Ask First Items

Stop before:

- replacing setup UI
- creating `.obsidian`
- installing or auto-enabling helper plugin
- deleting Logseq source or user data
- deleting, renaming, moving, or rewriting existing Obsidian vault contents
- moving Obsidian notes into `raw/projects/`
- adding a third-party dependency
- changing Reminder note marker encoding
- changing Calendar write policy

## Fail-Closed / Rollback

- Resolver returns nil when neither stored path nor bookmark resolves.
- Layout creation failures throw and do not delete existing directories.
- Missing `.obsidian` is reported as candidate state only; no config is written.

## Acceptance

- Phase 3a setup seam tests pass.
- Existing setup/runtime behavior remains unchanged.
- No Obsidian helper/plugin/config is installed or enabled.
- No user data is deleted or moved.
