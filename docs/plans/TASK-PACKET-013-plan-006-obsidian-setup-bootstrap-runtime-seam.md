# TASK-PACKET-013: PLAN-006 Phase 5b/6a Obsidian Setup Bootstrap Runtime Seam

## Objective

Connect Obsidian vault selection and the Reminders-first bootstrap seam to the
actual app setup path, without cutting Timeline/Schedule over to Obsidian yet.

## Scope

- Persist an Obsidian vault bookmark and stored path.
- Restore the Obsidian vault on launch.
- Add app setup/settings UI for selecting an Obsidian vault.
- Require the selected folder to already contain an `.obsidian` directory.
- Prepare only app-owned directories:
  - `<vault>/.buf`
  - `<vault>/raw/projects`
- Run first sync as Reminders -> Obsidian bootstrap only when `raw/projects`
  has no project notes. If project notes already exist, run safe
  Reminders -> Obsidian reconciliation instead of bootstrap overwrite.
- Use `ReminderGatewayImportSnapshotProvider` to fetch Reminders snapshots and
  `ObsidianReminderBootstrapSync` to write project notes.
- Do not run Logseq import/provisioning when Obsidian mode is configured.
- Treat bootstrap success as part of Obsidian setup completion. If bootstrap
  fails, do not remember the vault as active setup state.

## Non-Goals

- Do not cut Timeline/Schedule projection to Obsidian in this slice.
- Do not implement Obsidian-to-Reminders file edit push.
- Do not implement Reminders-to-Obsidian incremental reconciliation beyond the
  bootstrap trigger.
- Do not scan or move Obsidian notes outside `raw/projects/`.
- Do not create `.obsidian`.
- Do not auto-enable the helper plugin.
- Do not delete Logseq source, preferences, or user data.
- Do not change Reminder note marker encoding.
- Do not change Calendar write policy.
- Do not add third-party dependencies.

## Likely Files

- `import/BUF/App/AppState.swift`
- `import/BUF/App/AppStateLaunchAndSetup.swift`
- `import/BUF/App/AppStateSourceIO.swift`
- `import/BUF/Features/Setup/SetupContainerView.swift`
- `import/BUF/Features/Setup/AppSettingsView.swift`
- `Tests/BrainUnfogHarnessTests/RetainedSetupFlowTests.swift`
- `docs/plans/TASK-PACKET-013-plan-006-obsidian-setup-bootstrap-runtime-seam.md`

## Implementation Lane

- Keep Logseq runtime code present and unchanged for existing paths.
- Add Obsidian runtime state alongside Logseq state.
- `hasCompletedInitialSetup` may be true when either Logseq or Obsidian setup
  is configured, but Obsidian setup must only persist active state after
  Reminders-first bootstrap succeeds.
- Obsidian bootstrap/reconciliation must fetch Reminders and write only under
  `raw/projects`.
- Obsidian setup must call `ObsidianVaultLayout.prepareAppDirectories()` and
  therefore fail if `.obsidian` is missing.
- Obsidian helper install/update is automatic for the selected vault, but helper
  auto-enable remains out of scope.
- When both legacy Logseq preferences and Obsidian preferences exist, Obsidian
  mode wins for setup/bootstrap. This slice does not delete Logseq preferences.

## Review Lane

Review adversarially for:

- first sync accidentally going Obsidian -> Reminders
- Logseq import/provisioning running in Obsidian mode
- `.obsidian` auto-creation
- outside-`raw/projects` writes or note auto-move
- helper auto-enable
- Calendar/EventKit write policy regression
- duplicate note/task creation
- setup marking complete before bootstrap safety gates
- Reminder create/update/delete calls during Obsidian setup
- `.obsidian/plugins` or `.obsidian` config writes during setup

## Test Lane

Add focused tests for:

- configuring Obsidian vault creates `.buf` and `raw/projects` only when
  `.obsidian` already exists
- configuring candidate folder without `.obsidian` fails without creating
  `.buf`, `raw/projects`, or `.obsidian`
- Obsidian configuration persists and restores from UserDefaults path/bookmark
- Obsidian bootstrap writes Reminder lists/items to `raw/projects`
- Obsidian mode does not create Logseq `pages` or `logseq` config folders
- Obsidian mode does not run Logseq provisioning after import
- Obsidian setup failure during bootstrap leaves setup incomplete and retryable
- Obsidian setup failure does not leave the failed `.buf` as the remembered
  app container
- Obsidian setup uses Reminders reads only and performs zero Reminder writes
- damaged/conflicting existing `raw/projects` note content remains unchanged
- Obsidian setup does not create helper plugin folders or `.obsidian` config
- when both Logseq and Obsidian preferences exist, Obsidian bootstrap wins
- existing Logseq setup tests continue to pass

## Build/Test/Runtime Gate

- `swift test --filter RetainedSetupFlowTests`
- `rg -n "installBundled\\(|enablePlugin|community-plugins" import/BUF/App import/BUF/Features`
  must show no Obsidian helper auto-enable/config writes.
- `rg -n "calendar_event_external_id|EKEvent|RetainedCalendarEventKitBridge" import/BUF/App/AppStateSourceIO.swift import/BUF/App/AppStateLaunchAndSetup.swift`
  must return no new Calendar write wiring for this slice.
- `swift build`
- `swift test`
- Because this slice changes code, quit existing Brain Unfog app and relaunch
  `/Users/three/app_build/logseq plugin/.build/BrainUnfogHarness.app` after
  build/test pass.

## Ask First Items

Stop before:

- scanning the whole vault to find owned notes outside `raw/projects/`
- moving, deleting, renaming, or rewriting existing Obsidian notes outside
  `raw/projects/`
- creating `.obsidian`
- auto-enabling the helper plugin
- changing Reminder note marker encoding
- changing Calendar write policy
- adding a third-party dependency

## Review Result

Adversarial review flagged these accepted hardening changes:

- bootstrap success is now a setup-completion gate
- setup tests assert zero Reminder writes during Obsidian bootstrap
- setup tests assert no helper auto-enable or `.obsidian` config writes
- setup tests assert conflicting existing `raw/projects` notes are unchanged
- setup tests assert Obsidian wins when both Logseq and Obsidian preferences exist

The reviewer also flagged potential duplicate owned notes outside `raw/projects`.
PLAN-006 forbids scanning/moving notes outside `raw/projects` without user
approval, so this remains an Ask First item for a later policy decision rather
than an automatic fix in this slice.

## Acceptance

- A user can select an existing Obsidian vault and trigger Reminders-first
  bootstrap into `raw/projects`.
- The app can be relaunched and remember the selected Obsidian vault.
- Timeline/Schedule are not yet considered migrated to Obsidian.
- No Logseq source deletion or data migration occurs.
