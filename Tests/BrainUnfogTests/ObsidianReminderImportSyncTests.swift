import XCTest
@testable import BrainUnfog

final class ObsidianReminderImportSyncTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func setUp() async throws {
    try await super.setUp()
    ReminderSyncBaselineStore.reset()
  }

  override func tearDown() async throws {
    ReminderSyncBaselineStore.reset()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testNewReminderListCreatesProjectNoteAndTask() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let store = ObsidianProjectMarkdownStore(vaultRootURL: try makeTemporaryVault())
    let dueDate = makeDate(year: 2026, month: 4, day: 25, hour: 9, minute: 30)
    let list = makeList(identifier: "list-1", title: "Inbox", colorHex: "#FF3B30")

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "task-1",
              listIdentifier: list.identifier,
              title: "Remote task",
              notes: "remote note",
              dueDate: dueDate,
              hasExplicitTime: true,
              recurrenceRuleRaw: "monthly|1"
            ),
          ],
        ]
      ),
      store: store,
      now: fixedNow
    )

    let snapshots = try await store.loadProjectNotesInScope()
    let note = try XCTUnwrap(snapshots.first?.note)
    let task = try XCTUnwrap(note.tasks.first)
    XCTAssertEqual(result.importedProjectCount, 1)
    XCTAssertEqual(result.importedTaskCount, 1)
    XCTAssertEqual(snapshots.first?.vaultRelativePath, "raw/projects/Inbox.md")
    XCTAssertEqual(note.reminderListExternalIdentifier, "list-1")
    XCTAssertEqual(note.frontmatter?.colorHex, "#FF3B30")
    XCTAssertEqual(task.title, "Remote task")
    XCTAssertEqual(task.metadata?.reminderExternalIdentifier, "task-1")
    XCTAssertEqual(task.metadata?.date, "2026-04-25")
    XCTAssertEqual(task.metadata?.time, "09:30")
    XCTAssertEqual(task.metadata?.repeatRule, "reminder")
    XCTAssertTrue(snapshots[0].rawMarkdown.contains("  - remote note"))
    XCTAssertTrue(
      snapshots[0].rawMarkdown.contains(##"%% brain-unfog: {"project_color_hex":"#FF3B30"} %%"##)
    )
    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-1")?.state.title, "Remote task")
  }

  func testNewReminderListExpandsReminderNoteTaskMarkersIntoNestedTaskBlocks() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let store = ObsidianProjectMarkdownStore(vaultRootURL: try makeTemporaryVault())
    let list = makeList(identifier: "list-1", title: "Nested")

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "parent",
              listIdentifier: list.identifier,
              title: "Parent",
              notes: "before\nt:child\nafter"
            ),
            makeItem(
              identifier: "child",
              listIdentifier: list.identifier,
              title: "Child",
              notes: "child detail"
            ),
          ],
        ]
      ),
      store: store,
      now: fixedNow
    )

    let snapshots = try await store.loadProjectNotesInScope()
    let raw = try XCTUnwrap(snapshots.first?.rawMarkdown)

    XCTAssertEqual(result.importedTaskCount, 2)
    XCTAssertTrue(raw.contains("  - before"))
    XCTAssertTrue(raw.contains("  - [ ] Child"))
    XCTAssertTrue(raw.contains(#""reminder_external_id":"child""#))
    XCTAssertTrue(raw.contains("    - child detail"))
    XCTAssertTrue(raw.contains("  - after"))
    XCTAssertFalse(raw.contains("t:child"))
    XCTAssertEqual(raw.components(separatedBy: "- [ ] Child").count - 1, 1)
  }

  func testNewReminderListRestoresNestedTasksFromOutlineStateWithoutReminderNoteMarkers() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    try ObsidianReminderOutlineStateStore(vaultRootURL: vault).upsertListOutline(
      ObsidianReminderOutlineState(
        roots: [.task("parent")],
        taskChildrenByReminderID: [
          "parent": [
            .bullet(text: "before", children: []),
            .task("child"),
            .bullet(text: "after", children: []),
          ],
          "child": [
            .bullet(text: "child detail", children: []),
          ],
        ]
      ),
      forListID: "list-1"
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)
    let list = makeList(identifier: "list-1", title: "Nested")

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "parent",
              listIdentifier: list.identifier,
              title: "Parent",
              notes: "before\nafter"
            ),
            makeItem(
              identifier: "child",
              listIdentifier: list.identifier,
              title: "Child",
              notes: "child detail"
            ),
          ],
        ]
      ),
      store: store,
      now: fixedNow
    )

    let snapshots = try await store.loadProjectNotesInScope()
    let raw = try XCTUnwrap(snapshots.first?.rawMarkdown)

    XCTAssertEqual(result.importedTaskCount, 2)
    XCTAssertLessThan(
      try XCTUnwrap(raw.range(of: "  - before")?.lowerBound),
      try XCTUnwrap(raw.range(of: "  - [ ] Child")?.lowerBound)
    )
    XCTAssertLessThan(
      try XCTUnwrap(raw.range(of: "  - [ ] Child")?.lowerBound),
      try XCTUnwrap(raw.range(of: "  - after")?.lowerBound)
    )
    XCTAssertFalse(raw.contains("t:child"))
    XCTAssertEqual(raw.components(separatedBy: "- [ ] Child").count - 1, 1)
  }

  func testNewReminderListFailsClosedForUnknownReminderNoteTaskMarker() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)
    let list = makeList(identifier: "list-1", title: "Nested")

    do {
      _ = try await ObsidianReminderImportSync.sync(
        batch: ReminderImportSnapshotBatch(
          lists: [list],
          itemsByListIdentifier: [
            list.identifier: [
              makeItem(
                identifier: "parent",
                listIdentifier: list.identifier,
                title: "Parent",
                notes: "before\nt:missing-child\nafter"
              ),
            ],
          ]
        ),
        store: store,
        now: fixedNow
      )
      XCTFail("Expected unresolved task marker to fail closed")
    } catch ObsidianReminderImportSync.SyncError.unresolvedReminderNoteTaskMarker(
      "missing-child"
    ) {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertTrue(try projectMarkdownFiles(in: vault).isEmpty)
  }

  func testExistingReminderListColorUpdatesHiddenObsidianPropertyWithoutTaskChanges() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      brain_unfog_color_hex: "#0A84FF"
      ---
      - [ ] Stable task
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      """
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-1",
      state: ReminderSyncTaskState(
        title: "Stable task",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
    let list = makeList(identifier: "list-1", title: "Project", colorHex: "#34C759")

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(identifier: "task-1", listIdentifier: list.identifier, title: "Stable task"),
          ],
        ]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vault)
      .loadProjectNotesInScope()
    let raw = try XCTUnwrap(snapshots.first?.rawMarkdown)
    XCTAssertEqual(result.updatedTaskCount, 0)
    XCTAssertTrue(raw.contains(##"%% brain-unfog: {"project_color_hex":"#34C759"} %%"##))
    XCTAssertFalse(raw.contains("brain_unfog_color_hex:"))
    XCTAssertFalse(raw.contains("project_color_hex\":\"#0A84FF"))
  }

  func testExistingReminderEditsMergeIntoObsidianAndPreserveDuration() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      Local prose remains.
      - [ ] Old title
        %% brain-unfog: {"reminder_external_id":"task-1","date":"2026-04-24","duration":45,"repeat":"weekly"} %%
        - old note
      """
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-1",
      state: ReminderSyncTaskState(
        title: "Old title",
        isCompleted: false,
        date: "2026-04-24",
        repeatRule: "weekly",
        noteText: "old note"
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )

    let list = makeList(identifier: "list-1", title: "Project")
    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "task-1",
              listIdentifier: list.identifier,
              title: "Remote title",
              notes: "remote note",
              isCompleted: true,
              dueDate: makeDate(year: 2026, month: 4, day: 25, hour: 10, minute: 15),
              hasExplicitTime: true,
              recurrenceRuleRaw: "monthly|1",
              modifiedAt: fixedRemoteDate.addingTimeInterval(10)
            ),
          ],
        ]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vault)
      .loadProjectNotesInScope()
    let raw = try XCTUnwrap(snapshots.first?.rawMarkdown)
    XCTAssertEqual(result.updatedTaskCount, 1)
    XCTAssertEqual(result.projectRecords.map(\.title), ["Project"])
    XCTAssertEqual(result.projectRecords.map(\.reminderListExternalIdentifier), ["list-1"])
    XCTAssertTrue(raw.contains("Local prose remains."))
    XCTAssertTrue(raw.contains("- [x] Remote title"))
    XCTAssertTrue(raw.contains(#""date":"2026-04-25","time":"10:15","duration":45,"repeat":"reminder""#))
    XCTAssertTrue(raw.contains("  - remote note"))
    XCTAssertFalse(raw.contains("old note"))
  }

  func testRemoteCleanNoteTextPreservesExistingChildTaskBlocks() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] Parent
        %% brain-unfog: {"reminder_external_id":"parent"} %%
        - stale note
        - [ ] Child one
          %% brain-unfog: {"reminder_external_id":"child-one"} %%
        - [ ] Child two
          %% brain-unfog: {"reminder_external_id":"child-two"} %%
      """
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "parent",
      state: ReminderSyncTaskState(
        title: "Parent",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: "stale note"
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "child-one",
      state: matchingChildState("Child one"),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "child-two",
      state: matchingChildState("Child two"),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
    let list = makeList(identifier: "list-1", title: "Project")

    _ = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "parent",
              listIdentifier: list.identifier,
              title: "Parent",
              notes: "remote note\nremote trailing",
              modifiedAt: fixedRemoteDate.addingTimeInterval(10)
            ),
            makeItem(identifier: "child-one", listIdentifier: list.identifier, title: "Child one"),
            makeItem(identifier: "child-two", listIdentifier: list.identifier, title: "Child two"),
          ],
        ]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    let raw = try String(
      contentsOf: vault
        .appendingPathComponent("raw", isDirectory: true)
        .appendingPathComponent("projects", isDirectory: true)
        .appendingPathComponent("Project.md"),
      encoding: .utf8
    )
    XCTAssertTrue(raw.contains("  - remote note"))
    XCTAssertTrue(raw.contains("  - remote trailing"))
    XCTAssertFalse(raw.contains("stale note"))
    XCTAssertFalse(raw.contains("t:child"))
    XCTAssertLessThan(
      try XCTUnwrap(raw.range(of: "  - [ ] Child one")?.lowerBound),
      try XCTUnwrap(raw.range(of: "  - [ ] Child two")?.lowerBound)
    )
  }

  func testMissingBaselineDoesNotOverwriteDifferingLocalTask() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] Local title
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      """
    )
    let list = makeList(identifier: "list-1", title: "Project")

    _ = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(identifier: "task-1", listIdentifier: list.identifier, title: "Remote title"),
          ],
        ]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    let raw = try String(
      contentsOf: vault
        .appendingPathComponent("raw", isDirectory: true)
        .appendingPathComponent("projects", isDirectory: true)
        .appendingPathComponent("Project.md"),
      encoding: .utf8
    )
    XCTAssertTrue(raw.contains("Local title"))
    XCTAssertFalse(raw.contains("Remote title"))
    XCTAssertTrue(
      ReminderSyncBaselineStore.baseline(for: "task-1")?.conflictedFields.contains(.title)
        ?? false
    )
  }

  func testUnknownReminderNoteTaskMarkerDoesNotRewriteSubtree() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] Parent
        %% brain-unfog: {"reminder_external_id":"parent"} %%
        - stable note
      """
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "parent",
      state: ReminderSyncTaskState(
        title: "Parent",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: "stable note"
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
    let list = makeList(identifier: "list-1", title: "Project")

    _ = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "parent",
              listIdentifier: list.identifier,
              title: "Parent",
              notes: "remote note\nt:missing-child",
              modifiedAt: fixedRemoteDate.addingTimeInterval(10)
            ),
          ],
        ]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    let raw = try String(
      contentsOf: vault
        .appendingPathComponent("raw", isDirectory: true)
        .appendingPathComponent("projects", isDirectory: true)
        .appendingPathComponent("Project.md"),
      encoding: .utf8
    )
    XCTAssertTrue(raw.contains("stable note"))
    XCTAssertFalse(raw.contains("missing-child"))
    XCTAssertTrue(
      ReminderSyncBaselineStore.baseline(for: "parent")?.conflictedFields.contains(.noteText)
        ?? false
    )
  }

  func testExistingLegacyTaskMarkerForKnownTaskDoesNotFailValidation() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] Parent
        %% brain-unfog: {"reminder_external_id":"parent"} %%
        - t:child
      - [ ] Child
        %% brain-unfog: {"reminder_external_id":"child"} %%
      """
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "parent",
      state: ReminderSyncTaskState(
        title: "Parent",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "child",
      state: matchingChildState("Child"),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
    let list = makeList(identifier: "list-1", title: "Project")

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(identifier: "parent", listIdentifier: list.identifier, title: "Parent"),
            makeItem(identifier: "child", listIdentifier: list.identifier, title: "Child"),
          ],
        ]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    XCTAssertEqual(result.updatedTaskCount, 0)
  }

  func testEmptyReminderBatchDoesNotDeleteLocalProjects() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianImportData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    try writeProjectNote(
      vault: vault,
      fileName: "Deleted.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] Removed task
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      """
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-1",
      state: ReminderSyncTaskState(
        title: "Removed task",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(lists: [], itemsByListIdentifier: [:]),
      store: store,
      now: fixedNow
    )
    let lifecycleRecord = try ProjectLifecycleStore(vaultRootURL: vault)
      .record(forListIdentifier: "list-1")

    XCTAssertEqual(result.deletedProjectCount, 0)
    XCTAssertEqual(result.deletedProjectIDs, [])
    XCTAssertEqual(try projectMarkdownFiles(in: vault).map(\.lastPathComponent), ["Deleted.md"])
    XCTAssertNotNil(ReminderSyncBaselineStore.baseline(for: "task-1"))
    XCTAssertNil(lifecycleRecord)
  }

  func testMissingReminderListDoesNotDeleteArchivedObsidianProject() async throws {
    let vault = try makeTemporaryVault()
    try writeProjectNote(
      vault: vault,
      fileName: "Archived.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      아카이브: true
      ---
      - [ ] Archived task
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      """
    )
    try ObsidianReminderArchiveStore(vaultRootURL: vault).save(
      ObsidianReminderArchiveSnapshot(
        archivedAt: fixedNow,
        sourceVaultRelativePath: "raw/projects/Archived.md",
        list: makeList(identifier: "list-1", title: "Archived"),
        items: []
      ),
      forListIdentifier: "list-1"
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(lists: [], itemsByListIdentifier: [:]),
      store: store,
      now: fixedNow
    )

    XCTAssertEqual(result.deletedProjectCount, 0)
    XCTAssertEqual(try projectMarkdownFiles(in: vault).map(\.lastPathComponent), ["Archived.md"])
  }

  func testReminderDeleteLifecycleRecordDoesNotBlockReimport() async throws {
    let vault = try makeTemporaryVault()
    let list = makeList(identifier: "list-1", title: "Restored")
    try ProjectLifecycleStore(vaultRootURL: vault).recordStarted(
      intent: .remindersDelete,
      projectID: RetainedProjectionBuilder.derivedProjectID(for: list.identifier),
      reminderListExternalIdentifier: list.identifier,
      noteVaultRelativePath: "raw/projects/Restored.md",
      at: fixedNow
    )

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(lists: [list], itemsByListIdentifier: [:]),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    XCTAssertEqual(result.importedProjectCount, 1)
    XCTAssertEqual(try projectMarkdownFiles(in: vault).map(\.lastPathComponent), ["Restored.md"])
  }

  func testDuplicateAndDamagedMetadataFailClosedWithoutWrites() async throws {
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] One
        %% brain-unfog: {"reminder_external_id":"dup"} %%
      - [ ] Two
        %% brain-unfog: {"reminder_external_id":"dup"} %%
      """
    )
    let list = makeList(identifier: "list-1", title: "Project")

    do {
      _ = try await ObsidianReminderImportSync.sync(
        batch: ReminderImportSnapshotBatch(lists: [list], itemsByListIdentifier: [:]),
        store: ObsidianProjectMarkdownStore(vaultRootURL: vault)
      )
      XCTFail("Expected duplicate failure")
    } catch ObsidianReminderImportSync.SyncError.duplicateReminderExternalIdentifier("dup") {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let damagedVault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: damagedVault,
      fileName: "Damaged.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] Broken
        %% brain-unfog: {"reminder_external_id":
      """
    )
    do {
      _ = try await ObsidianReminderImportSync.sync(
        batch: ReminderImportSnapshotBatch(lists: [list], itemsByListIdentifier: [:]),
        store: ObsidianProjectMarkdownStore(vaultRootURL: damagedVault)
      )
      XCTFail("Expected damaged metadata failure")
    } catch ObsidianReminderImportSync.SyncError.damagedTaskMetadata {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private var fixedNow: Date { Date(timeIntervalSince1970: 2_000) }
  private var fixedRemoteDate: Date { Date(timeIntervalSince1970: 1_000) }

  private func matchingChildState(_ title: String) -> ReminderSyncTaskState {
    ReminderSyncTaskState(
      title: title,
      isCompleted: false,
      date: nil,
      repeatRule: nil,
      noteText: nil
    )
  }

  private func makeList(
    identifier: String,
    title: String,
    colorHex: String? = nil
  ) -> ReminderListImportSnapshot {
    ReminderListImportSnapshot(
      identifier: identifier,
      externalIdentifier: identifier,
      title: title,
      colorHex: colorHex
    )
  }

  private func makeItem(
    identifier: String,
    listIdentifier: String,
    title: String,
    notes: String = "",
    isCompleted: Bool = false,
    dueDate: Date? = nil,
    hasExplicitTime: Bool = false,
    recurrenceRuleRaw: String? = nil,
    modifiedAt: Date? = nil
  ) -> ReminderItemImportSnapshot {
    ReminderItemImportSnapshot(
      identifier: identifier,
      externalIdentifier: identifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: listIdentifier,
      sourceListTitle: listIdentifier,
      title: title,
      notes: notes,
      attachmentCount: 0,
      isCompleted: isCompleted,
      completionDate: isCompleted ? modifiedAt ?? fixedRemoteDate : nil,
      startDate: nil,
      dueDate: dueDate,
      scheduleHasExplicitTime: hasExplicitTime,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: recurrenceRuleRaw,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: fixedRemoteDate,
      modifiedAt: modifiedAt ?? fixedRemoteDate
    )
  }

  private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0
  ) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = .autoupdatingCurrent
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
  }

  private func makeTemporaryVault() throws -> URL {
    try makeTemporaryDirectory(prefix: "ObsidianReminderImportSyncTests")
  }

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  private func projectMarkdownFiles(in vaultURL: URL) throws -> [URL] {
    let projects = vaultURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    guard FileManager.default.fileExists(atPath: projects.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: projects,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "md" }
  }

  @discardableResult
  private func writeProjectNote(
    vault: URL,
    fileName: String,
    body: String
  ) throws -> URL {
    let projects = vault
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let url = projects.appendingPathComponent(fileName, isDirectory: false)
    try body.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
