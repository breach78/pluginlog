# TASK-PACKET-021: Phase 9 Logseq Removal And Final Release Gate

## Context
- PLAN-006 Phase 1-8 moved the retained workspace, Reminders sync, Schedule,
  Timeline, and task open/reveal paths to Obsidian `raw/projects/*.md`.
- User approval for Phase 9 is granted for source/resource/test/setup/runtime
  wiring code only.
- User data is out of scope and must not be deleted.

## Objective
Remove Logseq runtime/source/resource/test wiring now that Obsidian is the
source workspace, and close the final release gate.

## Delete Scope
Delete these Logseq-specific source files:

- `import/BUF/App/LogseqGraphRootPreferenceResolver.swift`
- `import/BUF/Services/LogseqGraphConfigStore.swift`
- `import/BUF/Services/LogseqHelperPluginInstaller.swift`
- `import/BUF/Services/LogseqPageFilenameCodec.swift`
- `import/BUF/Services/LogseqPagesDirectoryWatcher.swift`
- `import/BUF/Services/LogseqProjectMarkdownStoreAdapter.swift`
- `import/BUF/Services/LogseqProjectPageStore.swift`
- `import/BUF/Services/LogseqReminderPropertyCodec.swift`
- `import/BUF/Services/ManagedLogseqSyncHardening.swift`
- `import/BUF/Services/RetainedReminderImportSync.swift`
- Logseq-specific body of `import/BUF/Services/RetainedTaskCommandService.swift`,
  while preserving neutral command-result/write-loop marker types needed by
  Obsidian command tests/runtime.
- `import/BUF/Services/RetainedCalendarEventKitBridge.swift`
- `import/BUF/Services/RetainedLogseqProjectProvisioningSync.swift`
- `import/BUF/Utilities/LogseqDeepLinking.swift`

Delete these bundled Logseq helper resources:

- `import/BUF/Resources/LogseqHelperPlugin/icon.svg`
- `import/BUF/Resources/LogseqHelperPlugin/index.html`
- `import/BUF/Resources/LogseqHelperPlugin/index.js`
- `import/BUF/Resources/LogseqHelperPlugin/package.json`
- `import/BUF/Resources/LogseqHelperPlugin/styles.css`

Delete these Logseq-specific tests:

- `Tests/BrainUnfogHarnessTests/LogseqGraphConfigStoreTests.swift`
- `Tests/BrainUnfogHarnessTests/LogseqGraphRootPreferenceResolverTests.swift`
- `Tests/BrainUnfogHarnessTests/LogseqHelperPluginInstallerTests.swift`
- `Tests/BrainUnfogHarnessTests/LogseqPagesChangeTrackerTests.swift`
- `Tests/BrainUnfogHarnessTests/LogseqProjectMarkdownStoreAdapterTests.swift`
- `Tests/BrainUnfogHarnessTests/LogseqProjectPageStoreTests.swift`
- `Tests/BrainUnfogHarnessTests/LogseqReminderPropertyCodecTests.swift`
- `Tests/BrainUnfogHarnessTests/ManagedLogseqSyncHardeningTests.swift`
- `Tests/BrainUnfogHarnessTests/RetainedReminderImportSyncTests.swift`
- `Tests/BrainUnfogHarnessTests/RetainedTaskCommandServiceTests.swift`
- `Tests/BrainUnfogHarnessTests/RetainedCalendarEventKitBridgeTests.swift`
- `Tests/BrainUnfogHarnessTests/RetainedLogseqProjectProvisioningSyncTests.swift`
- legacy retained Logseq command/import/projection tests that still instantiate
  `LogseqProjectPageStore`, after confirming equivalent Obsidian tests exist.

## Modify Scope
- Stop reading/writing Logseq preference keys/state from `AppState`, but do not
  delete existing UserDefaults values, bookmarks, graph files, or `.buf` data.
- Rename the app-authored Reminder echo suppression from Logseq-specific naming
  to neutral naming.
- Make first-run/setup/settings Obsidian-only.
- Remove Logseq helper copy from `Package.swift`.
- Remove Logseq fallback from Timeline/Schedule read and command paths.
- Keep retained identity helpers only after removing Logseq-specific input
  types. Production must have no `LogseqProjectPageStore` references before
  deleting the Logseq store.
- Replace date/repeat parsing that used `LogseqReminderPropertyCodec` with an
  Obsidian-neutral Reminder schedule metadata codec before deleting the
  Logseq-named codec.
- Keep history docs and user data untouched.

## Out Of Scope
- User Logseq graph deletion.
- Obsidian vault or `.buf` data deletion.
- Reminders or Calendar data deletion.
- SwiftData schema/runtime data deletion.
- Obsidian sync policy changes.
- Calendar write enablement.
- Helper auto-enable.

## Replacement Seams
- Obsidian setup is the only first-run project store path.
- Obsidian `raw/projects/*.md` is the only retained read/write source.
- `ObsidianRetainedProjectionAdapter` replaces Logseq projection input.
- `ObsidianRetainedTaskCommandService` replaces Logseq task commands.
- `ObsidianTaskOpenService` replaces Logseq deep linking.
- `ObsidianProjectDirectoryWatcher` replaces Logseq page watching.
- `ReminderScheduleMetadataCodec` replaces the Logseq-named date/repeat codec.
- Obsidian and neutral coverage replaces deleted legacy retained coverage:
  projection adapter, changed-file refresh, provisioning/import/deletion sync,
  task command rollback/stale-baseline tests, task open tests, Calendar policy
  tests, and setup/vault/helper tests.

## Review Lane
Adversarially check:

- Any remaining Logseq fallback that can hide Obsidian projection errors.
- Any accidental user data deletion or source graph mutation.
- Any Calendar/EventKit write introduced for Reminder-backed tasks.
- Any removal of a still-needed neutral retained type.
- Any loss of Obsidian setup/bootstrap/runtime path.

## Test Lane
Run focused tests that cover Obsidian replacement behavior:

- `swift test --filter ObsidianRetainedProjectionAdapterTests`
- `swift test --filter ObsidianChangedProjectProjectionRefreshTests`
- `swift test --filter ObsidianReminderProvisioningSyncTests`
- `swift test --filter ObsidianReminderImportSyncTests`
- `swift test --filter ObsidianReminderDeletionSyncTests`
- `swift test --filter ObsidianRetainedTaskCommandServiceTests`
- `swift test --filter ObsidianTaskOpenServiceTests`
- `swift test --filter ObsidianVaultPreferenceResolverTests`
- `swift test --filter ObsidianVaultLayoutTests`
- `swift test --filter ObsidianHelperPluginInstallerTests`
- `swift test --filter RetainedWorkspaceSurfaceProjectionTests`
- `swift test --filter RetainedCalendarBridgePolicyTests`
- `swift test --filter RetainedSetupFlowTests`
- `swift test --filter TimelineBoardReadPathTests`
- `swift test --filter Schedule`

Then run:

- `rg -n "Logseq|logseq" import/BUF Tests Package.swift`
- `rg -n "EKEvent|calendar_event_external_id|save\\(|remove\\(" import/BUF/Services import/BUF/Features`
  and confirm any remaining hits are Calendar read-only overlay, Reminder
  gateway saves, or retained no-write marker/policy code rather than
  Reminder-backed Calendar event writes.
- `swift build`
- `swift test`
- terminate existing `BrainUnfogHarness`
- relaunch `.build/BrainUnfogHarness.app`

## Acceptance Criteria
- `import/BUF`, `Tests`, and `Package.swift` have no Logseq runtime/source/test
  references.
- Build and full test suite pass.
- Obsidian setup remains available and Logseq setup is gone.
- Timeline/Schedule read, write, and open paths use Obsidian only.
- Calendar remains read-only for Reminder-backed tasks.
- User data is not deleted or mutated as part of the removal.

## Rollback Risk
- High: deleting Logseq source exposes any remaining hidden runtime dependency.
  Mitigation: negative grep and build failures drive minimal rewiring.
- Medium: test deletion can mask lost coverage. Mitigation: keep equivalent
  Obsidian focused tests and full suite.
- Low: old Logseq preferences may remain in user defaults. They are inert and
  should not be actively deleted in this slice.
