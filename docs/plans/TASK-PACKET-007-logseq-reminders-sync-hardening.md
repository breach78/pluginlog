# TASK-PACKET-007: Logseq/Reminders Sync Hardening

## Goal

Keep Logseq, Reminders, and the app as editable sync peers while reducing avoidable Logseq
`file modified on disk` warnings and duplicate Reminder creation.

## Scope

- Add a normalized no-op guard to the single Markdown write path so unchanged page content is
  not replaced and does not emit app-authored write notifications.
- Read Reminder identity aliases as existing identities:
  - `reminder_external_id::`
  - `reminder-external-id::`
  - `reminder external id::`
  - `reminder_list_external_id::`
  - `reminder-list-external-id::`
  - `reminder list external id::`
- Keep writes canonical with underscore property names.
- Avoid canonicalizing aliases in background when no real content change is otherwise needed.
- Coalesce provisioning writes per page for identity writes only. Do not mix date/repeat/note
  reconciliation into provisioning unless a separate import conflict decision already produced
  those field edits.
- Add a small file-backed pending binding seam so a Reminder list/item created before a failed
  Markdown write is reused on the next sync instead of being created again.
- Keep startup/bootstrap Reminders-first. After import, use a distinct missing-bindings-only
  repair mode that reuses only verified pending list/item bindings and skips both existing task
  push updates and fresh Reminder creation.

## Out Of Scope

- Source file deletion.
- SwiftData/schema removal.
- Runtime data or `.buf/attachments` deletion.
- Disabling continuous sync or changing to manual batch-only sync.
- Calendar writes. Calendar remains read-only overlay for Reminder-backed tasks.
- Large Schedule/Timeline UI rewrites.

## Files Expected To Change

- `import/BUF/Services/LogseqProjectPageStore.swift`
- `import/BUF/Services/RetainedLogseqProjectProvisioningSync.swift`
- `import/BUF/App/AppStateSourceIO.swift`
- `import/BUF/App/AppState.swift`
- `import/BUF/App/AppStateLaunchAndSetup.swift`
- New small sidecar store under `import/BUF/Services/`
- Focused tests under `Tests/BrainUnfogHarnessTests/`

## Acceptance Criteria

- A no-op Logseq page write leaves file mtime unchanged and does not post
  `logseqProjectPageStoreDidWriteMarkdown`.
- Hyphen and space aliases are parsed as existing identities and do not create duplicate Reminder
  lists or items.
- Alias properties are canonicalized only when a real write is already needed.
- App-authored writes remain ignored by the Logseq watcher loop.
- Bootstrap import still runs Reminders-first, then repairs only verified pending bindings without
  pushing already-bound Logseq task edits or creating fresh Reminders from Logseq.
- A pending list/item binding from a prior Markdown write failure is reused on the next sync only
  when page path, list/page fingerprint, task title fingerprint, original task ordinal, and remote
  list membership still match.
- Conflicting identity aliases fail closed by not creating new Reminders for that ambiguous task or
  page in this slice.
- Ordinary page TODO blocks remain ignored.
- Calendar write path remains disabled/read-only.

## Build/Test/Runtime Gate

- Focused tests for `LogseqProjectPageStoreTests`.
- Focused tests for `RetainedLogseqProjectProvisioningSyncTests`.
- Existing focused tests for watcher loop and Calendar read-only policy.
- `swift build`.
- `swift test`.
- Quit the existing app and relaunch `.build/BrainUnfogHarness.app`.

## Main Risks To Review

- Pending binding keys must not bind the wrong Reminder to a different task after heavy page edits;
  never key only by task index.
- Bootstrap missing-binding provisioning must not reintroduce Logseq-over-Reminders overwrite loops.
- Alias support must prevent duplicate creation without causing constant background Markdown rewrites.
- No-op write guard must not hide real content changes caused by line-ending normalization.
