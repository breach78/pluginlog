# TASK-PACKET-011: PLAN-006 Phase 4a Obsidian Helper Installer Seam

## Objective

Add the Obsidian helper plugin bundle and installer seam without making it a
runtime dependency.

## Source Basis

- Obsidian plugin folders should match the manifest `id`.
- Obsidian plugin release assets include `manifest.json`, `main.js`, and
  optional `styles.css`.
- Vault event registration should happen after layout ready.
- Future safe writes should prefer Obsidian `Vault.process()`, but this slice
  does not expose a write bridge.

## Scope

- Add bundled helper resource:
  - `import/BUF/Resources/ObsidianHelperPlugin/manifest.json`
  - `import/BUF/Resources/ObsidianHelperPlugin/main.js`
  - `import/BUF/Resources/ObsidianHelperPlugin/styles.css`
- Add `ObsidianHelperPluginInstaller`.
- Install into `<vault>/.obsidian/plugins/brain-unfog-helper`.
- Use plugin id `brain-unfog-helper`; official Obsidian manifest rules do not
  allow `obsidian` in the id, and the local folder should match the id.
- Require an existing `.obsidian` directory before installing.
- Copy/replace the plugin folder atomically under `.obsidian/plugins`.
- Replace an existing helper folder only when it has the Brain Unfog ownership
  marker. Refuse to overwrite unowned folders.
- Validate bundled source has `manifest.json`, `main.js`, and `styles.css`.
- Add focused tests for bundled resource and installer behavior.

## Non-Goals

- Do not auto-enable the plugin.
- Do not edit `.obsidian/community-plugins.json` or any Obsidian settings file.
- Do not create `.obsidian`.
- Do not add a third-party dependency or Node build step.
- Do not add helper bridge transport.
- Do not call the helper from runtime app code.
- Do not perform Reminders merge/delete/repair decisions in helper JavaScript.
- Do not change Calendar policy.

## Likely Files

- `Package.swift`
- `import/BUF/Services/ObsidianHelperPluginInstaller.swift`
- `import/BUF/Resources/ObsidianHelperPlugin/manifest.json`
- `import/BUF/Resources/ObsidianHelperPlugin/main.js`
- `import/BUF/Resources/ObsidianHelperPlugin/styles.css`
- `Tests/BrainUnfogHarnessTests/ObsidianHelperPluginInstallerTests.swift`

## Implementation Lane

- Keep installer API explicit and test-only for now.
- Use `ObsidianVaultLayout` for `.obsidian` and plugin path derivation.
- Fail closed when `.obsidian` is missing or is not a directory.
- Do not reference installer from `AppState` or setup UI yet.
- Helper JavaScript may observe `raw/projects/` modifications as an
  invalidation hint stub only; it must not write files or call Reminders.
- Helper JavaScript must not contain vault write operations, network calls,
  Reminders logic, or Calendar logic in this slice.

## Review Lane

Review adversarially for:

- silent helper auto-enable
- accidental `.obsidian` creation
- runtime dependency or setup cutover
- helper becoming a second sync brain
- plugin id/folder mismatch
- user data deletion/move
- third-party dependency introduction
- Calendar/EventKit regression

## Test Lane

Add focused tests for:

- bundled helper contains `manifest.json`, `main.js`, `styles.css`
- manifest id equals installer plugin identifier
- manifest has required plugin metadata and `isDesktopOnly`
- install copies plugin into existing `.obsidian/plugins`
- install replaces stale plugin folder
- install refuses to replace unowned existing plugin folder
- install fails when `.obsidian` is missing and does not create it
- install does not create or modify `community-plugins.json`
- install does not modify existing Obsidian settings files
- helper JavaScript contains invalidation stubs only, with no vault writes,
  network calls, Reminders, or Calendar operations

## Build/Test/Runtime Gate

- `swift test --filter ObsidianHelperPluginInstallerTests`
- `rg -n "ObsidianHelperPluginInstaller" import/BUF/App import/BUF/Features`
  must return no runtime cutover matches.
- `rg -n "ObsidianHelperPlugin|brain-unfog-helper|\\.obsidian/plugins" import/BUF/App import/BUF/Features import/BUF/Services --glob '!ObsidianHelperPluginInstaller.swift'`
  must return no indirect runtime wiring matches.
- `rg -n "community-plugins|setConfig|enablePlugin" import/BUF/Services import/BUF/Resources/ObsidianHelperPlugin`
  must return no auto-enable matches.
- Inspect `Package.swift`/`Package.resolved`: this slice may only add bundled
  resources, not package/npm dependencies.
- `swift build`
- `swift test`
- Because this slice changes code, quit existing Brain Unfog app and relaunch
  `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app` after
  build/test pass.

## Ask First Items

Stop before:

- auto-enabling the Obsidian helper
- editing any Obsidian settings/config file
- adding helper bridge transport as runtime dependency
- creating `.obsidian`
- deleting, renaming, moving, or rewriting Obsidian vault contents
- adding a third-party dependency
- changing Reminder note marker encoding
- changing Calendar write policy

## Acceptance

- The app can install the helper into an already initialized Obsidian vault.
- Installing the helper is explicit API only; runtime behavior is unchanged.
- No Obsidian settings file is created or modified.
- The helper bundle cannot perform Reminders sync or Calendar writes.
