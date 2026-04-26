import XCTest
@testable import BrainUnfogHarness

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
    let list = makeList(identifier: "list-1", title: "Inbox")

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
    XCTAssertEqual(task.title, "Remote task")
    XCTAssertEqual(task.metadata?.reminderExternalIdentifier, "task-1")
    XCTAssertEqual(task.metadata?.date, "2026-04-25")
    XCTAssertEqual(task.metadata?.time, "09:30")
    XCTAssertEqual(task.metadata?.repeatRule, "reminder")
    XCTAssertTrue(snapshots[0].rawMarkdown.contains("  - remote note"))
    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-1")?.state.title, "Remote task")
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

  func testReminderNoteTaskMarkersReorderPreservedChildTaskBlocks() async throws {
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
        noteText: "stale note\nt:child-one\nt:child-two"
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
              notes: "remote note\nt:child-two\nt:child-one\nremote trailing",
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
    XCTAssertLessThan(
      try XCTUnwrap(raw.range(of: "  - [ ] Child two")?.lowerBound),
      try XCTUnwrap(raw.range(of: "  - [ ] Child one")?.lowerBound)
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

  private func makeList(identifier: String, title: String) -> ReminderListImportSnapshot {
    ReminderListImportSnapshot(
      identifier: identifier,
      externalIdentifier: identifier,
      title: title,
      colorHex: nil
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
