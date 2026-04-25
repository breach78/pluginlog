# TASK-PACKET-020: Obsidian Task Focus/Open

## Context
- TASK-PACKET-014 moved Timeline/Schedule read projection to Obsidian when a
  vault is configured.
- TASK-PACKET-019 moved retained completion and schedule commands to Obsidian
  markdown writes in Obsidian mode.
- Timeline/Schedule task reveal still routes through project selection paths
  that were originally Logseq-first.

## Objective
Open the matching Obsidian project note, and focus the matching task when a
stable Obsidian block identifier is available, from Timeline/Schedule reveal
actions.

## Scope
- Add a small Obsidian source-opening seam.
- Build Obsidian `open` URIs for project notes and task block identifiers using
  official Obsidian URI behavior; use structured URL construction and
  single-pass percent encoding, not raw string concatenation. Source:
  https://obsidian.md/help/uri
- Resolve the current project note/task from `<vault>/raw/projects/*.md` by
  `reminder_list_external_id` and `reminder_external_id`.
- Fall back to opening the note file when an Obsidian URI open fails.
- Route Timeline task reveal and Schedule task reveal through this seam when an
  Obsidian vault is configured.
- Keep the existing Logseq project-page route only when no Obsidian vault is
  configured.

## Out Of Scope
- Helper auto-enable.
- Helper write-through or helper as sync brain.
- Creating missing block ids.
- Writing markdown, Reminders, Calendar, or sidecar state.
- Installing/enabling helper plugins or writing `.obsidian` config.
- Logseq source/resource deletion.
- Adding third-party dependencies.

## Safety Rules
- No sync write is allowed from reveal/open actions.
- Reveal/open must not create `raw/projects`, `.obsidian`, or `.buf`; if the
  current project directory is missing, fail closed.
- No Reminder or Calendar write is allowed.
- Obsidian mode must not fall back to Logseq if task open fails.
- Duplicate list/task ids or damaged metadata fail closed before task focus.
- Missing current raw/projects identity match fails closed; title-only matches
  are not allowed.
- If a task has no block identifier, open the project note only.
- If Obsidian is unavailable or closed, try a safe file-open fallback.
- Obsidian block open should prefer exact file path targeting over ambiguous
  vault-name targeting.
- Any helper interaction, if added later, must be focus/open-only and must not
  install, auto-enable, write markdown, trigger sync, or touch `.buf`.

## Implementation Lane
- Prefer a pure URL builder plus a small async opener service over UI-specific
  parsing logic.
- Touch Schedule/Timeline/MainWorkspace only at reveal/open dispatch points.
- Keep each new/modified file under 800 lines.

## Review Lane
- Check Logseq fallback leakage, accidental writes, helper becoming sync brain,
  duplicate/damaged metadata handling, and Obsidian URI encoding.

## Test Lane
- Add focused tests for URL building, URI encoding edge cases, note fallback,
  task block focus, missing identity, duplicate fail-closed, damaged metadata
  fail-closed, and no mutation of `raw/projects`, `.obsidian`, or `.buf`.
- Add dispatch or negative-grep coverage proving Obsidian mode does not route
  through Logseq open paths.

## Acceptance Criteria
- Timeline task reveal opens the Obsidian project note in Obsidian mode.
- Schedule task reveal opens the Obsidian project note in Obsidian mode.
- If a task block id exists, the opener attempts an Obsidian block URI.
- If helper/Obsidian URI open is unavailable, the opener falls back to the note
  file.
- If Obsidian is closed, the URI/file open path remains safe.
- Reveal/open does not modify markdown, Reminders, Calendar, or sidecar state.
- Obsidian mode does not use Logseq open paths.
- Logseq open path remains available only when no Obsidian vault is configured.
- Vault/file/block parameters with spaces, Korean text, reserved characters,
  slashes, and leading `^` are encoded once.
- Missing/stale project or task identity opens nothing and does not fall back to
  title matching.

## Gates
- `swift test --filter ObsidianTaskOpenServiceTests`
- `swift test --filter TimelineBoardReadPathTests`
- `swift test --filter Schedule`
- Negative grep for Reminder/Calendar writes, helper install/enable/write, and
  Logseq fallback in the new Obsidian opener plus touched dispatch files.
- `swift build`
- `swift test`
- Terminate existing app and relaunch `.build/BrainUnfogHarness.app`.
