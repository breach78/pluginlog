import XCTest
@testable import BrainUnfogHarness

@MainActor
final class ObsidianReminderProvisioningSyncTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func setUp() async throws {
    try await super.setUp()
    ReminderSyncBaselineStore.reset()
    ReminderPendingBindingStore.reset()
  }

  override func tearDown() async throws {
    ReminderSyncBaselineStore.reset()
    ReminderPendingBindingStore.reset()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testNewProjectNoteCreatesReminderListAndWritesCanonicalID() async throws {
    let vault = try makeTemporaryVault()
    let dataRoot = try makeTemporaryDirectory()
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Fresh.md",
      body: """
      ---
      tags:
        - 프로젝트
      ---
      """
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)
    let provider = FakeObsidianReminderProjectProvider()

    let result = try await ObsidianReminderProvisioningSync.syncChangedNotes(
      fileURLs: [noteURL],
      store: store,
      reminderProjectProvider: provider,
      now: fixedNow
    )

    XCTAssertEqual(result.createdProjectCount, 1)
    XCTAssertEqual(provider.createdLists.map(\.title), ["Fresh"])
    let snapshots = try await store.loadProjectNotesInScope()
    let snapshot = try XCTUnwrap(snapshots.first)
    XCTAssertEqual(snapshot.note.reminderListExternalIdentifier, "list-1")
    XCTAssertFalse(snapshot.rawMarkdown.contains("brain_unfog_" + "project_id"))
  }

  func testNewTaskCreatesReminderItemAndWritesCanonicalID() async throws {
    let vault = try makeTemporaryVault()
    let dataRoot = try makeTemporaryDirectory()
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] Task one
        - child note
      """
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)
    let provider = FakeObsidianReminderProjectProvider()
    provider.lists["list-1"] = ReminderProjectListSnapshot(
      identifier: "list-1",
      externalIdentifier: "list-1",
      title: "Project",
      colorHex: nil
    )

    let result = try await ObsidianReminderProvisioningSync.syncChangedNotes(
      fileURLs: [noteURL],
      store: store,
      reminderProjectProvider: provider,
      now: fixedNow
    )

    XCTAssertEqual(result.createdTaskCount, 1)
    XCTAssertEqual(provider.createdTasks.map(\.title), ["Task one"])
    XCTAssertEqual(provider.createdTasks.first?.noteText, "child note")
    let snapshots = try await store.loadProjectNotesInScope()
    let task = try XCTUnwrap(snapshots.first?.note.tasks.first)
    XCTAssertEqual(task.reminderExternalIdentifier, "task-1")
    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-1")?.state.title, "Task one")
  }

  func testExistingTaskTitleCompletionDateTimeRepeatAndNotePushToReminder() async throws {
    let vault = try makeTemporaryVault()
    let dataRoot = try makeTemporaryDirectory()
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [x] New title
        %% brain-unfog: {"reminder_external_id":"task-1","date":"2026-04-25","time":"09:30","repeat":"monthly"} %%
        - updated note
      """
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)
    let provider = FakeObsidianReminderProjectProvider()
    provider.snapshots["task-1"] = makeRemoteTask(
      externalID: "task-1",
      listID: "list-1",
      title: "Old title",
      note: "old note",
      isCompleted: false,
      dueDate: makeDate(year: 2026, month: 4, day: 24),
      hasExplicitTime: false,
      recurrenceRuleRaw: "weekly|1|",
      modifiedAt: fixedRemoteDate
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

    let result = try await ObsidianReminderProvisioningSync.syncChangedNotes(
      fileURLs: [noteURL],
      store: store,
      reminderProjectProvider: provider,
      now: fixedNow
    )

    XCTAssertEqual(result.updatedTaskCount, 1)
    XCTAssertEqual(provider.updatedTitles, ["task-1": "New title"])
    XCTAssertEqual(provider.updatedCompletions, ["task-1": true])
    XCTAssertEqual(provider.updatedNotes, ["task-1": "updated note"])
    XCTAssertEqual(provider.updatedSchedules["task-1"]?.hasExplicitTime, true)
    XCTAssertEqual(
      provider.updatedSchedules["task-1"]?.date.map {
        dateTimeString($0)
      },
      "2026-04-25 09:30"
    )
    XCTAssertEqual(provider.updatedRecurrences, ["task-1": "monthly|1"])
  }

  func testDurationEditDoesNotWriteReminder() async throws {
    let vault = try makeTemporaryVault()
    let dataRoot = try makeTemporaryDirectory()
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] Same title
        %% brain-unfog: {"reminder_external_id":"task-1","duration":90} %%
      """
    )
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)
    let provider = FakeObsidianReminderProjectProvider()
    provider.snapshots["task-1"] = makeRemoteTask(
      externalID: "task-1",
      listID: "list-1",
      title: "Same title",
      note: "",
      isCompleted: false,
      dueDate: nil,
      hasExplicitTime: false,
      recurrenceRuleRaw: nil,
      modifiedAt: fixedRemoteDate
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-1",
      state: ReminderSyncTaskState(
        title: "Same title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )

    let result = try await ObsidianReminderProvisioningSync.syncChangedNotes(
      fileURLs: [noteURL],
      store: store,
      reminderProjectProvider: provider,
      now: fixedNow
    )

    XCTAssertEqual(result.updatedTaskCount, 0)
    XCTAssertTrue(provider.allTaskUpdateCalls.isEmpty)
  }

  func testDuplicateIDsFailClosedBeforeReminderWrites() async throws {
    let vault = try makeTemporaryVault()
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] One
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      - [ ] Two
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      """
    )
    let provider = FakeObsidianReminderProjectProvider()

    do {
      _ = try await ObsidianReminderProvisioningSync.syncChangedNotes(
        fileURLs: [noteURL],
        store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
        reminderProjectProvider: provider
      )
      XCTFail("Expected duplicate id failure")
    } catch ObsidianReminderProvisioningSync.SyncError
      .duplicateReminderExternalIdentifier("task-1") {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(provider.allTaskUpdateCalls.isEmpty)
    XCTAssertTrue(provider.createdTasks.isEmpty)
  }

  func testDuplicateIDInUnchangedProjectFailsClosedBeforeReminderWrites() async throws {
    let vault = try makeTemporaryVault()
    let changedURL = try writeProjectNote(
      vault: vault,
      fileName: "Changed.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] One
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      """
    )
    _ = try writeProjectNote(
      vault: vault,
      fileName: "Unchanged.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-2
      ---
      - [ ] Two
        %% brain-unfog: {"reminder_external_id":"task-1"} %%
      """
    )
    let provider = FakeObsidianReminderProjectProvider()

    do {
      _ = try await ObsidianReminderProvisioningSync.syncChangedNotes(
        fileURLs: [changedURL],
        store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
        reminderProjectProvider: provider
      )
      XCTFail("Expected duplicate id failure")
    } catch ObsidianReminderProvisioningSync.SyncError
      .duplicateReminderExternalIdentifier("task-1") {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(provider.allTaskUpdateCalls.isEmpty)
  }

  func testDamagedMetadataFailsClosedBeforeReminderWrites() async throws {
    let vault = try makeTemporaryVault()
    let noteURL = try writeProjectNote(
      vault: vault,
      fileName: "Project.md",
      body: """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: list-1
      ---
      - [ ] One
        %% brain-unfog: {"reminder_external_id":
      """
    )
    let provider = FakeObsidianReminderProjectProvider()

    do {
      _ = try await ObsidianReminderProvisioningSync.syncChangedNotes(
        fileURLs: [noteURL],
        store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
        reminderProjectProvider: provider
      )
      XCTFail("Expected damaged metadata failure")
    } catch ObsidianReminderProvisioningSync.SyncError.damagedTaskMetadata {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(provider.createdTasks.isEmpty)
    XCTAssertTrue(provider.allTaskUpdateCalls.isEmpty)
  }

  func testStaleBaselineBlocksMarkdownIdentityWriteBack() async throws {
    let vault = try makeTemporaryVault()
    let dataRoot = try makeTemporaryDirectory()
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let rawNote = """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: list-1
    ---
    - [ ] Task one
    """
    let noteURL = try writeProjectNote(vault: vault, fileName: "Project.md", body: rawNote)
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vault)
    let staleSnapshots = try await store.loadProjectNotesInScope()
    let provider = FakeObsidianReminderProjectProvider()
    try await Task.sleep(nanoseconds: 10_000_000)
    try rawNote.write(to: noteURL, atomically: true, encoding: .utf8)

    do {
      _ = try await ObsidianReminderProvisioningSync.syncLoadedSnapshots(
        snapshots: staleSnapshots,
        store: store,
        reminderProjectProvider: provider,
        now: fixedNow
      )
      XCTFail("Expected stale baseline to fail")
    } catch ObsidianProjectMarkdownStore.StoreError.staleExpectedBaseline {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(provider.createdTasks.count, 1)

    let result = try await ObsidianReminderProvisioningSync.syncChangedNotes(
      fileURLs: [noteURL],
      store: ObsidianProjectMarkdownStore(vaultRootURL: vault),
      reminderProjectProvider: provider,
      now: fixedNow.addingTimeInterval(1)
    )
    XCTAssertEqual(result.createdTaskCount, 1)
    XCTAssertEqual(provider.createdTasks.count, 1)
    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vault)
      .loadProjectNotesInScope()
    let task = try XCTUnwrap(snapshots.first?.note.tasks.first)
    XCTAssertEqual(task.reminderExternalIdentifier, "task-1")
  }

  private var fixedNow: Date { Date(timeIntervalSince1970: 2_000) }
  private var fixedRemoteDate: Date { Date(timeIntervalSince1970: 1_000) }

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ObsidianProvisioning-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  private func makeTemporaryVault() throws -> URL {
    try makeTemporaryDirectory()
  }

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

  private func dateTimeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
  }

  private func makeRemoteTask(
    externalID: String,
    listID: String,
    title: String,
    note: String,
    isCompleted: Bool,
    dueDate: Date?,
    hasExplicitTime: Bool,
    recurrenceRuleRaw: String?,
    modifiedAt: Date
  ) -> ReminderTaskRemoteSnapshot {
    ReminderTaskRemoteSnapshot(
      identifier: externalID,
      externalIdentifier: externalID,
      calendarIdentifier: listID,
      title: title,
      noteText: note,
      isCompleted: isCompleted,
      completionDate: nil,
      startDate: nil,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      priority: 0,
      recurrenceRuleRaw: recurrenceRuleRaw,
      modifiedAt: modifiedAt
    )
  }
}

@MainActor
private final class FakeObsidianReminderProjectProvider: ReminderProjectProvider {
  var defaultCalendarIdentifierForNewReminders: String? { nil }
  var lists: [String: ReminderProjectListSnapshot] = [:]
  var snapshots: [String: ReminderTaskRemoteSnapshot] = [:]
  var createdLists: [ReminderProjectListSnapshot] = []
  var createdTasks: [(listID: String, title: String, dueDate: Date?, hasExplicitTime: Bool, noteText: String)] = []
  var updatedTitles: [String: String] = [:]
  var updatedCompletions: [String: Bool] = [:]
  var updatedNotes: [String: String] = [:]
  var updatedSchedules: [String: (date: Date?, hasExplicitTime: Bool)] = [:]
  var updatedRecurrences: [String: String?] = [:]

  var allTaskUpdateCalls: [String] {
    Array(updatedTitles.keys)
      + Array(updatedCompletions.keys)
      + Array(updatedNotes.keys)
      + Array(updatedSchedules.keys)
      + Array(updatedRecurrences.keys)
  }

  func requestAccess() async throws -> Bool { true }

  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch? {
    ReminderImportSnapshotBatch(
      lists: identifiers.compactMap { listID in
        lists[listID] ?? ReminderProjectListSnapshot(
          identifier: listID,
          externalIdentifier: listID,
          title: listID,
          colorHex: nil
        )
      }.map {
        ReminderListImportSnapshot(
          identifier: $0.identifier,
          externalIdentifier: $0.externalIdentifier,
          title: $0.title,
          colorHex: $0.colorHex
        )
      },
      itemsByListIdentifier: Dictionary(
        uniqueKeysWithValues: identifiers.map { listID in
          (
            listID,
            snapshots.values
              .filter { $0.calendarIdentifier == listID }
              .map { item(from: $0) }
          )
        }
      )
    )
  }

  func createProjectList(title: String) throws -> ReminderProjectListSnapshot {
    let list = ReminderProjectListSnapshot(
      identifier: "list-\(createdLists.count + 1)",
      externalIdentifier: "list-\(createdLists.count + 1)",
      title: title,
      colorHex: nil
    )
    lists[list.identifier] = list
    createdLists.append(list)
    return list
  }

  func createTaskReminder(
    inProject identifier: String,
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    let taskID = "task-\(createdTasks.count + 1)"
    createdTasks.append((identifier, title, dueDate, hasExplicitTime, noteText))
    snapshots[taskID] = ReminderTaskRemoteSnapshot(
      identifier: taskID,
      externalIdentifier: taskID,
      calendarIdentifier: identifier,
      title: title,
      noteText: noteText,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: Date(timeIntervalSince1970: 2_000)
    )
    return ReminderTaskRemoteMetadata(
      identifier: taskID,
      externalIdentifier: taskID,
      modifiedAt: Date(timeIntervalSince1970: 2_000)
    )
  }

  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot? {
    guard let id = task.reminderExternalIdentifier else { return nil }
    return snapshots[id]
  }

  func setTaskTitle(
    for task: ReminderTaskReference,
    title: String
  ) throws -> ReminderTaskRemoteMetadata? {
    updatedTitles[taskKey(task)] = title
    return updateSnapshot(task, title: title)
  }

  func setTaskCompletion(
    for task: ReminderTaskReference,
    isCompleted: Bool,
    completionDate: Date?
  ) throws -> ReminderTaskRemoteMetadata? {
    updatedCompletions[taskKey(task)] = isCompleted
    return updateSnapshot(task, isCompleted: isCompleted, completionDate: completionDate)
  }

  func setTaskReminderNote(
    for task: ReminderTaskReference,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    updatedNotes[taskKey(task)] = noteText
    return updateSnapshot(task, noteText: noteText)
  }

  func setTaskSchedule(
    for task: ReminderTaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws -> ReminderTaskRemoteMetadata? {
    updatedSchedules[taskKey(task)] = (dueDate, hasExplicitTime)
    return updateSnapshot(task, dueDate: dueDate, hasExplicitTime: hasExplicitTime)
  }

  func setTaskRecurrence(
    for task: ReminderTaskReference,
    recurrenceRuleRaw: String?
  ) throws -> ReminderTaskRemoteMetadata? {
    updatedRecurrences[taskKey(task)] = recurrenceRuleRaw
    return updateSnapshot(task, recurrenceRuleRaw: recurrenceRuleRaw)
  }

  func removeProjectList(identifier: String) throws {}
  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot? { nil }
  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot? { nil }
  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool { false }
  func setTaskPresentation(for task: ReminderTaskReference, priority: Int) throws -> ReminderTaskRemoteMetadata? { nil }
  func moveTaskReminder(for task: ReminderTaskReference, toProject identifier: String) throws -> ReminderTaskRemoteMetadata? { nil }
  func restoreArchivedProject(_ project: ReminderArchivedProjectSnapshot) throws -> ReminderProjectRestoreResult {
    throw NSError(domain: "unused", code: 1)
  }
  func removeArchivedProjectLists(_ projects: [ReminderProjectListReference]) -> ReminderProjectCleanupResult {
    ReminderProjectCleanupResult(removedCount: 0, failedProjectIDs: [])
  }

  private func taskKey(_ task: ReminderTaskReference) -> String {
    task.reminderExternalIdentifier ?? task.reminderIdentifier ?? task.taskID.uuidString
  }

  private func updateSnapshot(
    _ task: ReminderTaskReference,
    title: String? = nil,
    isCompleted: Bool? = nil,
    completionDate: Date? = nil,
    noteText: String? = nil,
    dueDate: Date? = nil,
    hasExplicitTime: Bool? = nil,
    recurrenceRuleRaw: String? = nil
  ) -> ReminderTaskRemoteMetadata? {
    let key = taskKey(task)
    guard let snapshot = snapshots[key] else { return nil }
    let next = ReminderTaskRemoteSnapshot(
      identifier: snapshot.identifier,
      externalIdentifier: snapshot.externalIdentifier,
      calendarIdentifier: snapshot.calendarIdentifier,
      title: title ?? snapshot.title,
      noteText: noteText ?? snapshot.noteText,
      isCompleted: isCompleted ?? snapshot.isCompleted,
      completionDate: completionDate ?? snapshot.completionDate,
      startDate: snapshot.startDate,
      dueDate: dueDate ?? snapshot.dueDate,
      hasExplicitTime: hasExplicitTime ?? snapshot.hasExplicitTime,
      priority: snapshot.priority,
      recurrenceRuleRaw: recurrenceRuleRaw ?? snapshot.recurrenceRuleRaw,
      modifiedAt: Date(timeIntervalSince1970: 3_000)
    )
    snapshots[key] = next
    return ReminderTaskRemoteMetadata(
      identifier: next.identifier,
      externalIdentifier: next.externalIdentifier,
      modifiedAt: next.modifiedAt
    )
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
