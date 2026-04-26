import XCTest
@testable import BrainUnfog

@MainActor
final class ObsidianReminderDeletionSyncTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func setUp() async throws {
    try await super.setUp()
    ReminderSyncBaselineStore.reset()
    ReminderPendingBindingStore.reset()
    ReminderDeletedTaskTombstoneStore.reset()
    TaskIdentityBridgeStore.reset()
  }

  override func tearDown() async throws {
    ReminderSyncBaselineStore.reset()
    ReminderPendingBindingStore.reset()
    ReminderDeletedTaskTombstoneStore.reset()
    TaskIdentityBridgeStore.reset()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testMissingObsidianTaskDeletesReminderOnlyWhenBaselineAndRemoteMatch() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianDeletionData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    ReminderDeletedTaskTombstoneStore.install(dataDirectory: dataRoot)
    TaskIdentityBridgeStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: projectNote(body: "No tasks remain.")
    )
    let provider = FakeDeletionReminderProjectProvider()
    provider.snapshots["task-1"] = makeRemoteTask(title: "Task one")
    upsertBaseline(identifier: "task-1", title: "Task one", noteText: nil)

    let result = try await ObsidianReminderProvisioningSync.syncChangedNotes(
      fileURLs: [noteURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      reminderProjectProvider: provider,
      now: fixedNow
    )

    XCTAssertEqual(result.deletedTaskCount, 1)
    XCTAssertEqual(provider.removedReminderExternalIdentifiers, ["task-1"])
    XCTAssertNil(ReminderSyncBaselineStore.baseline(for: "task-1"))
  }

  func testMissingObsidianTaskDoesNotDeleteReminderWhenRemoteChanged() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianDeletionData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    ReminderDeletedTaskTombstoneStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: projectNote(body: "No tasks remain.")
    )
    let provider = FakeDeletionReminderProjectProvider()
    provider.snapshots["task-1"] = makeRemoteTask(
      title: "Remote edit",
      modifiedAt: fixedRemoteDate.addingTimeInterval(10)
    )
    upsertBaseline(identifier: "task-1", title: "Task one", noteText: nil)

    let result = try await ObsidianReminderProvisioningSync.syncChangedNotes(
      fileURLs: [noteURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      reminderProjectProvider: provider,
      now: fixedNow
    )

    XCTAssertEqual(result.deletedTaskCount, 0)
    XCTAssertTrue(provider.removedReminderExternalIdentifiers.isEmpty)
    XCTAssertNotNil(ReminderSyncBaselineStore.baseline(for: "task-1"))
  }

  func testLostListIdentityDoesNotCreateDuplicateListForBoundTasks() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianDeletionData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      ---
      - [ ] Task one
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      """
    )
    let provider = FakeDeletionReminderProjectProvider()

    let result = try await ObsidianReminderProvisioningSync.syncChangedNotes(
      fileURLs: [noteURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      reminderProjectProvider: provider,
      now: fixedNow
    )

    XCTAssertEqual(result.createdProjectCount, 0)
    XCTAssertTrue(provider.createdListTitles.isEmpty)
  }

  func testMissingReminderItemDeletesObsidianTaskOnlyWhenLocalEqualsBaseline() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianDeletionData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: projectNote(
        body: """
        - [ ] Task one
          %% brain-unfog: {"reminder_external_id":"task-1"} %%
        Unrelated prose.
        """
      )
    )
    upsertBaseline(identifier: "task-1", title: "Task one", noteText: nil)

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [makeList()],
        itemsByListIdentifier: ["list-1": []]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vault)
      .loadProjectNotesInScope()
    let raw = try XCTUnwrap(snapshots.first?.rawMarkdown)
    XCTAssertEqual(result.deletedTaskCount, 1)
    XCTAssertFalse(raw.contains("Task one"))
    XCTAssertTrue(raw.contains("Unrelated prose."))
    XCTAssertNil(ReminderSyncBaselineStore.baseline(for: "task-1"))
  }

  func testMissingReminderItemPreservesObsidianTaskWhenLocalChanged() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianDeletionData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: projectNote(
        body: """
        - [ ] Local edit
          %% brain-unfog: {"reminder_external_id":"task-1"} %%
        """
      )
    )
    upsertBaseline(identifier: "task-1", title: "Task one", noteText: nil)

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [makeList()],
        itemsByListIdentifier: ["list-1": []]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vault)
      .loadProjectNotesInScope()
    let raw = try XCTUnwrap(snapshots.first?.rawMarkdown)
    XCTAssertEqual(result.deletedTaskCount, 0)
    XCTAssertTrue(raw.contains("Local edit"))
    XCTAssertNotNil(ReminderSyncBaselineStore.baseline(for: "task-1"))
  }

  func testMissingParentReminderDoesNotDeleteExistingRemoteChildTask() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianDeletionData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: projectNote(
        body: """
        - [ ] Parent
          %% brain-unfog: {"reminder_external_id":"parent"} %%
          - [ ] Child
            %% brain-unfog: {"reminder_external_id":"child"} %%
        """
      )
    )
    upsertBaseline(identifier: "parent", title: "Parent", noteText: "Child")
    upsertBaseline(identifier: "child", title: "Child", noteText: nil)

    let result = try await ObsidianReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [makeList()],
        itemsByListIdentifier: [
          "list-1": [
            makeItem(identifier: "child", title: "Child"),
          ],
        ]
      ),
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      now: fixedNow
    )

    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vault)
      .loadProjectNotesInScope()
    let raw = try XCTUnwrap(snapshots.first?.rawMarkdown)
    XCTAssertEqual(result.deletedTaskCount, 0)
    XCTAssertTrue(raw.contains("Parent"))
    XCTAssertTrue(raw.contains("Child"))
  }

  func testDamagedNoteBlocksDeletionBeforeAnyWrite() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianDeletionData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Clean.md",
      body: projectNote(
        body: """
        - [ ] Task one
          %% brain-unfog: {"reminder_external_id":"task-1"} %%
        """
      )
    )
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Damaged.md",
      body: projectNote(
        body: """
        - [ ] Broken
          %% brain-unfog: {"reminder_external_id":
        """
      )
    )
    upsertBaseline(identifier: "task-1", title: "Task one", noteText: nil)

    do {
      _ = try await ObsidianReminderImportSync.sync(
        batch: ReminderImportSnapshotBatch(
          lists: [makeList()],
          itemsByListIdentifier: ["list-1": []]
        ),
        store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
        now: fixedNow
      )
      XCTFail("Expected damaged metadata failure")
    } catch ObsidianReminderImportSync.SyncError.damagedTaskMetadata {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vault)
      .loadProjectNotesInScope()
    let raw = try XCTUnwrap(
      snapshots.first { $0.fileURL.lastPathComponent == "Clean.md" }?.rawMarkdown
    )
    XCTAssertTrue(raw.contains("Task one"))
    XCTAssertNotNil(ReminderSyncBaselineStore.baseline(for: "task-1"))
  }

  private var fixedNow: Date { Date(timeIntervalSince1970: 2_000) }
  private var fixedRemoteDate: Date { Date(timeIntervalSince1970: 1_000) }

  private func projectNote(body: String) -> String {
    """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: list-1
    ---
    \(body)
    """
  }

  private func makeList() -> ReminderListImportSnapshot {
    ReminderListImportSnapshot(
      identifier: "list-1",
      externalIdentifier: "list-1",
      title: "Project",
      colorHex: nil
    )
  }

  private func makeItem(identifier: String, title: String) -> ReminderItemImportSnapshot {
    ReminderItemImportSnapshot(
      identifier: identifier,
      externalIdentifier: identifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: title,
      notes: "",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: nil,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: fixedRemoteDate,
      modifiedAt: fixedRemoteDate
    )
  }

  private func makeRemoteTask(
    title: String,
    modifiedAt: Date? = nil
  ) -> ReminderTaskRemoteSnapshot {
    ReminderTaskRemoteSnapshot(
      identifier: "task-1",
      externalIdentifier: "task-1",
      calendarIdentifier: "list-1",
      title: title,
      noteText: "",
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      modifiedAt: modifiedAt ?? fixedRemoteDate
    )
  }

  private func upsertBaseline(
    identifier: String,
    title: String,
    noteText: String?
  ) {
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: identifier,
      state: ReminderSyncTaskState(
        title: title,
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: noteText
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
  }

  private func makeTemporaryVault() throws -> URL {
    try makeTemporaryDirectory(prefix: "ObsidianDeletionVault")
  }

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  @discardableResult
  private func writeProjectNote(vault: URL, fileName: String, body: String) throws -> URL {
    let projects = vault
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let url = projects.appendingPathComponent(fileName, isDirectory: false)
    try body.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}

@MainActor
private final class FakeDeletionReminderProjectProvider: ReminderProjectProvider {
  var lists: [String: ReminderProjectListSnapshot] = [
    "list-1": ReminderProjectListSnapshot(
      identifier: "list-1",
      externalIdentifier: "list-1",
      title: "Project",
      colorHex: nil
    ),
  ]
  var snapshots: [String: ReminderTaskRemoteSnapshot] = [:]
  var createdListTitles: [String] = []
  var removedReminderExternalIdentifiers: [String] = []

  var reminderGateway: ReminderGateway? { nil }
  var defaultCalendarIdentifierForNewReminders: String? { nil }

  func requestAccess() async throws -> Bool { true }

  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch? {
    let lists = identifiers.compactMap { self.lists[$0] }.map {
      ReminderListImportSnapshot(
        identifier: $0.identifier,
        externalIdentifier: $0.externalIdentifier,
        title: $0.title,
        colorHex: $0.colorHex
      )
    }
    let itemsByListIdentifier = Dictionary(
      uniqueKeysWithValues: identifiers.map { listID in
        (
          listID,
          snapshots.values
            .filter { $0.calendarIdentifier == listID }
            .map(item)
        )
      }
    )
    return ReminderImportSnapshotBatch(
      lists: lists,
      itemsByListIdentifier: itemsByListIdentifier
    )
  }

  func createProjectList(title: String) throws -> ReminderProjectListSnapshot {
    createdListTitles.append(title)
    let identifier = "created-\(createdListTitles.count)"
    let list = ReminderProjectListSnapshot(
      identifier: identifier,
      externalIdentifier: identifier,
      title: title,
      colorHex: nil
    )
    lists[identifier] = list
    return list
  }

  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool {
    guard let identifier = task.reminderExternalIdentifier,
      snapshots.removeValue(forKey: identifier) != nil
    else {
      return false
    }
    removedReminderExternalIdentifiers.append(identifier)
    return true
  }

  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot? {
    guard let identifier = task.reminderExternalIdentifier else { return nil }
    return snapshots[identifier]
  }

  func createTaskReminder(
    inProject identifier: String,
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? { nil }

  func removeProjectList(identifier: String) throws {}
  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot? { nil }
  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot? { nil }
  func setTaskTitle(for task: ReminderTaskReference, title: String) throws -> ReminderTaskRemoteMetadata? { nil }
  func setTaskCompletion(for task: ReminderTaskReference, isCompleted: Bool, completionDate: Date?) throws -> ReminderTaskRemoteMetadata? { nil }
  func setTaskReminderNote(for task: ReminderTaskReference, noteText: String) throws -> ReminderTaskRemoteMetadata? { nil }
  func setTaskSchedule(for task: ReminderTaskReference, dueDate: Date?, hasExplicitTime: Bool) throws -> ReminderTaskRemoteMetadata? { nil }
  func setTaskRecurrence(for task: ReminderTaskReference, recurrenceRuleRaw: String?) throws -> ReminderTaskRemoteMetadata? { nil }
  func setTaskPresentation(for task: ReminderTaskReference, priority: Int) throws -> ReminderTaskRemoteMetadata? { nil }
  func moveTaskReminder(for task: ReminderTaskReference, toProject identifier: String) throws -> ReminderTaskRemoteMetadata? { nil }
  func restoreArchivedProject(_ project: ReminderArchivedProjectSnapshot) throws -> ReminderProjectRestoreResult {
    throw NSError(domain: "unused", code: 1)
  }
  func removeArchivedProjectLists(_ projects: [ReminderProjectListReference]) -> ReminderProjectCleanupResult {
    ReminderProjectCleanupResult(removedCount: 0, failedProjectIDs: [])
  }

  private func item(from snapshot: ReminderTaskRemoteSnapshot) -> ReminderItemImportSnapshot {
    ReminderItemImportSnapshot(
      identifier: snapshot.identifier,
      externalIdentifier: snapshot.externalIdentifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: snapshot.calendarIdentifier,
      sourceListTitle: snapshot.calendarIdentifier,
      title: snapshot.title,
      notes: snapshot.noteText,
      attachmentCount: 0,
      isCompleted: snapshot.isCompleted,
      completionDate: snapshot.completionDate,
      startDate: snapshot.startDate,
      dueDate: snapshot.dueDate,
      scheduleHasExplicitTime: snapshot.hasExplicitTime,
      scheduledDurationMinutes: nil,
      priority: snapshot.priority,
      recurrenceRuleRaw: snapshot.recurrenceRuleRaw,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: Date(timeIntervalSince1970: 1_000),
      modifiedAt: snapshot.modifiedAt
    )
  }
}
