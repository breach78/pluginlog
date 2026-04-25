import XCTest
@testable import BrainUnfogHarness

@MainActor
final class RetainedLogseqProjectProvisioningSyncTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    ReminderPendingBindingStore.reset()
    ReminderSyncBaselineStore.reset()
    ReminderDeletedTaskTombstoneStore.reset()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testProjectTagCreatesReminderListAndWritesListIdentifier() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let pageURL = pagesRoot.appendingPathComponent("Client Project.md", isDirectory: false)
    try """
    tags:: [[프로젝트]]

    Existing project notes
    """.write(to: pageURL, atomically: true, encoding: .utf8)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()

    let result = try await RetainedLogseqProjectProvisioningSync.sync(
      store: store,
      reminderProjectProvider: provider
    )
    let secondResult = try await RetainedLogseqProjectProvisioningSync.sync(
      store: store,
      reminderProjectProvider: provider
    )
    let markdown = try String(contentsOf: pageURL, encoding: .utf8)

    XCTAssertEqual(result.createdProjectCount, 1)
    XCTAssertEqual(result.createdTaskCount, 0)
    XCTAssertEqual(secondResult.createdProjectCount, 0)
    XCTAssertEqual(secondResult.createdTaskCount, 0)
    XCTAssertEqual(provider.createdLists.map(\.title), ["Client Project"])
    XCTAssertEqual(markdown.components(separatedBy: "reminder_list_external_id:: list-ext-1").count - 1, 1)
    XCTAssertFalse(markdown.contains("brain_unfog_project_id::"))
    XCTAssertFalse(markdown.contains("brain_unfog_task_id::"))
  }

  func testProjectPageTasksCreateReminderItemsInPlaceAndOrdinaryPageIsIgnored() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    let ordinaryPageURL = pagesRoot.appendingPathComponent("Inbox.md", isDirectory: false)
    try """
    tags:: 프로젝트

    Intro
    - TODO Prepare kickoff
      date:: 2026-04-25 14:30
      duration:: 45
      repeat:: weekly
      - child note remains Logseq-only
    - DONE Close loop
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    try """
    Ordinary notes
    - TODO Do not sync
    """.write(to: ordinaryPageURL, atomically: true, encoding: .utf8)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()

    let result = try await RetainedLogseqProjectProvisioningSync.sync(
      store: store,
      reminderProjectProvider: provider
    )
    let secondResult = try await RetainedLogseqProjectProvisioningSync.sync(
      store: store,
      reminderProjectProvider: provider
    )
    let projectMarkdown = try String(contentsOf: projectPageURL, encoding: .utf8)
    let ordinaryMarkdown = try String(contentsOf: ordinaryPageURL, encoding: .utf8)
    let pages = try await store.loadProjectPagesInScope()
    let snapshot = try RetainedProjectionBuilder.build(.init(pages: pages))
    let project = try XCTUnwrap(snapshot.projects.onlyValue)

    XCTAssertEqual(result.createdProjectCount, 1)
    XCTAssertEqual(result.createdTaskCount, 2)
    XCTAssertEqual(secondResult.createdProjectCount, 0)
    XCTAssertEqual(secondResult.createdTaskCount, 0)
    XCTAssertEqual(provider.createdTasks.map(\.title), ["Prepare kickoff", "Close loop"])
    XCTAssertEqual(provider.createdTasks.first?.inProject, "list-ext-1")
    XCTAssertEqual(provider.createdTasks.first?.hasExplicitTime, true)
    XCTAssertEqual(
      provider.createdTasks.first?.dueDate,
      LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date
    )
    XCTAssertEqual(provider.completionWrites.map(\.reference.reminderExternalIdentifier), ["task-ext-2"])
    XCTAssertEqual(provider.recurrenceWrites.map(\.recurrenceRuleRaw), ["weekly|1|"])
    XCTAssertEqual(project.tasks.map(\.identity.reminderExternalIdentifier), ["task-ext-1", "task-ext-2"])
    XCTAssertEqual(project.tasks.first?.schedule.rawDuration, "45")
    XCTAssertEqual(projectMarkdown.components(separatedBy: "reminder_external_id:: task-ext-1").count - 1, 1)
    XCTAssertEqual(projectMarkdown.components(separatedBy: "reminder_external_id:: task-ext-2").count - 1, 1)
    XCTAssertTrue(projectMarkdown.contains("duration:: 45"))
    XCTAssertTrue(projectMarkdown.contains("- child note remains Logseq-only"))
    XCTAssertFalse(projectMarkdown.contains("brain_unfog_task_id::"))
    XCTAssertFalse(ordinaryMarkdown.contains("reminder_external_id::"))
    XCTAssertEqual(provider.createdLists.count, 1)
    XCTAssertEqual(provider.createdTasks.count, 2)
  }

  func testReminderIdentityAliasesDoNotCreateDuplicateReminderItemsOrCanonicalizeWithoutRealWrite() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let projectPageURL = pagesRoot.appendingPathComponent("Aliases.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder list external id:: list-ext-1

    - TODO Existing aliased task
      reminder-external-id:: task-ext-1
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let beforeMTime = try XCTUnwrap(
      projectPageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    )
    let noNotification = expectation(description: "alias-only sync does not rewrite")
    noNotification.isInverted = true
    let token = NotificationCenter.default.addObserver(
      forName: .logseqProjectPageStoreDidWriteMarkdown,
      object: nil,
      queue: nil
    ) { notification in
      guard let fileURL = notification.userInfo?[LogseqProjectPageStoreWriteNotification.fileURLKey] as? URL,
        fileURL.standardizedFileURL == projectPageURL.standardizedFileURL
      else {
        return
      }
      noNotification.fulfill()
    }
    defer { NotificationCenter.default.removeObserver(token) }
    let provider = ProvisioningFakeReminderProjectProvider()

    let result = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )
    await fulfillment(of: [noNotification], timeout: 0.1)
    let afterMTime = try XCTUnwrap(
      projectPageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    )
    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)

    XCTAssertEqual(result.createdTaskCount, 0)
    XCTAssertEqual(provider.createdTasks.count, 0)
    XCTAssertEqual(afterMTime, beforeMTime)
    XCTAssertTrue(markdown.contains("reminder list external id:: list-ext-1"))
    XCTAssertTrue(markdown.contains("reminder-external-id:: task-ext-1"))
  }

  func testConflictingReminderIdentityAliasesFailClosedWithoutCreatingDuplicates() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let ambiguousPageURL = pagesRoot.appendingPathComponent("Ambiguous List.md", isDirectory: false)
    let ambiguousTaskURL = pagesRoot.appendingPathComponent("Ambiguous Task.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1
    reminder-list-external-id:: list-ext-2

    - TODO Should not create list
    """.write(to: ambiguousPageURL, atomically: true, encoding: .utf8)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Should not create task
      reminder_external_id:: task-ext-1
      reminder-external-id:: task-ext-2
    """.write(to: ambiguousTaskURL, atomically: true, encoding: .utf8)
    let provider = ProvisioningFakeReminderProjectProvider()

    let result = try await RetainedLogseqProjectProvisioningSync.sync(
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )

    XCTAssertEqual(result.createdProjectCount, 0)
    XCTAssertEqual(result.createdTaskCount, 0)
    XCTAssertEqual(provider.createdLists.count, 0)
    XCTAssertEqual(provider.createdTasks.count, 0)
  }

  func testPendingReminderTaskBindingPreventsDuplicateCreationOnNextSync() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Pending task
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let now = Date(timeIntervalSince1970: 2_000)
    let pendingTask = LogseqProjectPageStore.TaskRecord(
      title: "Pending task",
      isCompleted: false
    )
    ReminderPendingBindingStore.upsertTaskBinding(
      pageFileURL: projectPageURL,
      listExternalIdentifier: "list-ext-1",
      taskIndex: 0,
      task: pendingTask,
      reminderExternalIdentifier: "task-ext-pending",
      now: now
    )
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.importBatch = ReminderImportSnapshotBatch(
      lists: [
        .init(
          identifier: "list-ext-1",
          externalIdentifier: "list-ext-1",
          title: "Launch",
          colorHex: nil
        ),
      ],
      itemsByListIdentifier: [
        "list-ext-1": [
          ReminderItemImportSnapshot(
            identifier: "task-local-pending",
            externalIdentifier: "task-ext-pending",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-ext-1",
            sourceListTitle: "Launch",
            title: "Pending task",
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
            createdAt: now,
            modifiedAt: now
          ),
        ],
      ]
    )

    let result = try await RetainedLogseqProjectProvisioningSync.sync(
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider,
      now: now.addingTimeInterval(1)
    )
    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)

    XCTAssertEqual(result.createdTaskCount, 0)
    XCTAssertEqual(provider.createdTasks.count, 0)
    XCTAssertTrue(markdown.contains("reminder_external_id:: task-ext-pending"))
  }

  func testChangedPendingTaskBindingFailsClosedInsteadOfCreatingDuplicateReminder() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Edited pending task
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let now = Date(timeIntervalSince1970: 2_000)
    ReminderPendingBindingStore.upsertTaskBinding(
      pageFileURL: projectPageURL,
      listExternalIdentifier: "list-ext-1",
      taskIndex: 0,
      task: LogseqProjectPageStore.TaskRecord(title: "Original pending task", isCompleted: false),
      reminderExternalIdentifier: "task-ext-pending",
      now: now
    )
    let provider = ProvisioningFakeReminderProjectProvider()

    let result = try await RetainedLogseqProjectProvisioningSync.sync(
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider,
      now: now.addingTimeInterval(1)
    )
    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)

    XCTAssertEqual(result.createdTaskCount, 0)
    XCTAssertEqual(provider.createdTasks.count, 0)
    XCTAssertFalse(markdown.contains("reminder_external_id::"))
  }

  func testPendingReminderListBindingPreventsDuplicateListCreationOnNextSync() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderPendingBindingStore.install(dataDirectory: dataRoot)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트

    Project notes
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let now = Date(timeIntervalSince1970: 2_000)
    ReminderPendingBindingStore.upsertProjectBinding(
      pageFileURL: projectPageURL,
      pageTitle: "Launch",
      reminderListExternalIdentifier: "list-ext-pending",
      now: now
    )
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.importBatch = ReminderImportSnapshotBatch(
      lists: [
        .init(
          identifier: "list-ext-pending",
          externalIdentifier: "list-ext-pending",
          title: "Launch",
          colorHex: nil
        ),
      ],
      itemsByListIdentifier: ["list-ext-pending": []]
    )

    let result = try await RetainedLogseqProjectProvisioningSync.sync(
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider,
      now: now.addingTimeInterval(1)
    )
    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)

    XCTAssertEqual(result.createdProjectCount, 0)
    XCTAssertEqual(provider.createdLists.count, 0)
    XCTAssertTrue(markdown.contains("reminder_list_external_id:: list-ext-pending"))
  }

  func testBootstrapMissingBindingsOnlyDoesNotPushExistingLogseqTaskEditsOrCreateFreshReminders() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Edited local title
      reminder_external_id:: task-ext-1
    - TODO Missing binding task
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-1",
      state: ReminderSyncTaskState(
        title: "Remote title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Remote title",
      noteText: "",
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      modifiedAt: remoteModifiedAt
    )

    let result = try await RetainedLogseqProjectProvisioningSync.sync(
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider,
      mode: .missingBindingsOnly
    )
    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)

    XCTAssertEqual(result.createdTaskCount, 0)
    XCTAssertEqual(provider.titleWrites.count, 0)
    XCTAssertEqual(provider.createdTasks.count, 0)
    XCTAssertTrue(markdown.contains("reminder_external_id:: task-ext-1"))
    XCTAssertFalse(markdown.contains("reminder_external_id:: task-ext-2"))
  }

  func testNestedLogseqTaskMarkersCreateFlatReminderItems() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let projectPageURL = pagesRoot.appendingPathComponent("2026.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - Parent note
    \t- LATER Nested child task
    \t\tdate:: 2026-04-30
    \t- NOW Another nested child task
    - DONE Root completed task
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()

    let result = try await RetainedLogseqProjectProvisioningSync.sync(
      store: store,
      reminderProjectProvider: provider
    )
    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)

    XCTAssertEqual(result.createdTaskCount, 3)
    XCTAssertEqual(
      provider.createdTasks.map(\.title),
      ["Nested child task", "Another nested child task", "Root completed task"]
    )
    XCTAssertEqual(provider.completionWrites.map(\.reference.reminderExternalIdentifier), ["task-ext-3"])
    XCTAssertEqual(markdown.components(separatedBy: "reminder_external_id::").count - 1, 3)
    XCTAssertTrue(markdown.contains("\t- LATER Nested child task"))
    XCTAssertTrue(markdown.contains("\t- NOW Another nested child task"))
  }

  func testLogseqTaskSubtreeUpdatesReminderNoteText() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Parent task
      reminder_external_id:: parent-ext
    \t- direct note
    \t\t- nested note
    \t- TODO Child task
    \t  reminder_external_id:: child-ext
    \t\t- child private note
    \t- trailing note
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "parent-ext",
      state: ReminderSyncTaskState(
        title: "Parent task",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "child-ext",
      state: ReminderSyncTaskState(
        title: "Child task",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["parent-ext"] = .init(
      identifier: "parent-local",
      externalIdentifier: "parent-ext",
      calendarIdentifier: "list-ext-1",
      title: "Parent task",
      noteText: "",
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      modifiedAt: remoteModifiedAt
    )
    provider.taskSnapshotsByExternalIdentifier["child-ext"] = .init(
      identifier: "child-local",
      externalIdentifier: "child-ext",
      calendarIdentifier: "list-ext-1",
      title: "Child task",
      noteText: "",
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      modifiedAt: remoteModifiedAt
    )

    _ = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: store,
      reminderProjectProvider: provider
    )

    XCTAssertEqual(provider.noteWrites.map(\.reference.reminderExternalIdentifier), ["parent-ext", "child-ext"])
    XCTAssertEqual(provider.noteWrites.map(\.noteText), [
      "direct note\n nested note\nt:child-ext\ntrailing note",
      "child private note",
    ])
  }

  func testEmptyLogseqSubtreeDoesNotClearExistingReminderNoteText() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Parent task
      reminder_external_id:: parent-ext
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["parent-ext"] = .init(
      identifier: "parent-local",
      externalIdentifier: "parent-ext",
      calendarIdentifier: "list-ext-1",
      title: "Parent task",
      noteText: "important remote note",
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      modifiedAt: .now
    )

    _ = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: store,
      reminderProjectProvider: provider
    )

    XCTAssertEqual(provider.noteWrites.count, 0)
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["parent-ext"]?.noteText, "important remote note")
  }

  func testBaselineTrackedEmptyLogseqSubtreeClearsReminderNoteText() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Parent task
      reminder_external_id:: parent-ext
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "parent-ext",
      state: ReminderSyncTaskState(
        title: "Parent task",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: "important remote note"
      ),
      remoteModifiedAt: Date(timeIntervalSince1970: 1_000),
      now: Date(timeIntervalSince1970: 1_000)
    )

    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["parent-ext"] = .init(
      identifier: "parent-local",
      externalIdentifier: "parent-ext",
      calendarIdentifier: "list-ext-1",
      title: "Parent task",
      noteText: "important remote note",
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      modifiedAt: Date(timeIntervalSince1970: 1_000)
    )

    _ = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )

    XCTAssertEqual(provider.noteWrites.map(\.noteText), [""])
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["parent-ext"]?.noteText, "")
    XCTAssertNil(ReminderSyncBaselineStore.baseline(for: "parent-ext")?.state.noteText)
  }

  func testExistingReminderBackedTaskTitleChangeUpdatesReminderInPlace() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Edited title
      reminder_external_id:: task-ext-1
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-1",
      state: ReminderSyncTaskState(
        title: "Original title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Original title",
      noteText: "",
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      modifiedAt: remoteModifiedAt
    )

    let result = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: store,
      reminderProjectProvider: provider
    )
    let secondResult = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: store,
      reminderProjectProvider: provider
    )

    XCTAssertEqual(result.createdTaskCount, 0)
    XCTAssertEqual(secondResult.createdTaskCount, 0)
    XCTAssertEqual(provider.createdTasks.count, 0)
    XCTAssertEqual(provider.titleWrites.map(\.title), ["Edited title"])
    XCTAssertEqual(provider.titleWrites.first?.reference.reminderExternalIdentifier, "task-ext-1")
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.title, "Edited title")
  }

  func testExistingReminderBackedTaskTitleChangeUsesPrefetchedLocalIdentifierWhenExternalLookupMisses() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    let projectPageURL = pagesRoot.appendingPathComponent("2026.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Edited Logseq title
      reminder_external_id:: task-ext-1
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-1",
      state: ReminderSyncTaskState(
        title: "Original title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.importBatch = ReminderImportSnapshotBatch(
      lists: [
        .init(
          identifier: "list-ext-1",
          externalIdentifier: "list-ext-1",
          title: "2026",
          colorHex: nil
        ),
      ],
      itemsByListIdentifier: [
        "list-ext-1": [
          ReminderItemImportSnapshot(
            identifier: "task-local-1",
            externalIdentifier: "task-ext-1",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-ext-1",
            sourceListTitle: "2026",
            title: "Original title",
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
            createdAt: remoteModifiedAt,
            modifiedAt: remoteModifiedAt
          ),
        ],
      ]
    )

    _ = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )

    XCTAssertEqual(provider.titleWrites.map(\.title), ["Edited Logseq title"])
    XCTAssertEqual(provider.titleWrites.first?.reference.reminderIdentifier, "task-local-1")
    XCTAssertEqual(provider.titleWrites.first?.reference.reminderExternalIdentifier, "task-ext-1")
  }

  func testExistingReminderBackedTaskChangesUpdateReminderInPlace() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - DONE Existing task
      reminder_external_id:: task-ext-1
      date:: 2026-04-25 14:30
      repeat:: weekly
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-1",
      state: ReminderSyncTaskState(
        title: "Existing task",
        isCompleted: false,
        date: "2026-04-23",
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Existing task",
      noteText: "",
      isCompleted: false,
      dueDate: LogseqReminderPropertyCodec.decodeDate("2026-04-23")?.date,
      hasExplicitTime: false,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: remoteModifiedAt
    )

    let result = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: store,
      reminderProjectProvider: provider
    )
    let secondResult = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: store,
      reminderProjectProvider: provider
    )

    XCTAssertEqual(result.createdTaskCount, 0)
    XCTAssertEqual(secondResult.createdTaskCount, 0)
    XCTAssertEqual(provider.createdTasks.count, 0)
    XCTAssertEqual(provider.completionWrites.map(\.isCompleted), [true])
    XCTAssertEqual(provider.scheduleWrites.map(\.dueDate), [
      LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date
    ])
    XCTAssertEqual(provider.scheduleWrites.map(\.hasExplicitTime), [true])
    XCTAssertEqual(provider.recurrenceWrites.map(\.recurrenceRuleRaw), ["weekly|1|"])
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.isCompleted, true)
    XCTAssertEqual(
      LogseqReminderPropertyCodec.encodeDate(
        provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.dueDate,
        hasExplicitTime: provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.hasExplicitTime ?? false
      ),
      "2026-04-25 14:30"
    )
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.recurrenceRuleRaw, "weekly|1|")
  }

  func testNoBaselineExistingReminderUpdateFailsClosedInsteadOfPushingLocalDiff() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Stale local title
      reminder_external_id:: task-ext-1
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 2_000)
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Remote title",
      noteText: "",
      isCompleted: false,
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: remoteModifiedAt
    )

    _ = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )

    XCTAssertEqual(provider.titleWrites.count, 0)
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.title, "Remote title")
  }

  func testDuplicateLocalReminderIdentifiersDoNotWriteSameReminder() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO First local title
      reminder_external_id:: task-ext-1
    - TODO Second local title
      reminder_external_id:: task-ext-1
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-1",
      state: ReminderSyncTaskState(
        title: "Remote title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Remote title",
      noteText: "",
      isCompleted: false,
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: remoteModifiedAt
    )

    _ = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )

    XCTAssertEqual(provider.titleWrites.count, 0)
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.title, "Remote title")
  }

  func testReminderImportUpdatesLogseqTitleBeforeProvisioningCanOverwriteRemoteChange() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Old Logseq title
      reminder_external_id:: task-ext-1
      - keep Logseq-only child note
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let remoteModifiedAt = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 10))
    )
    let localModifiedAt = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 9))
    )
    try FileManager.default.setAttributes(
      [.modificationDate: localModifiedAt],
      ofItemAtPath: projectPageURL.path
    )
    let remoteTask = ReminderItemImportSnapshot(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-local-1",
      sourceListTitle: "Launch",
      title: "Remote Reminder title",
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
      createdAt: remoteModifiedAt,
      modifiedAt: remoteModifiedAt
    )
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Remote Reminder title",
      noteText: "",
      isCompleted: false,
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: remoteModifiedAt
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [
          .init(
            identifier: "list-local-1",
            externalIdentifier: "list-ext-1",
            title: "Launch",
            colorHex: nil
          ),
        ],
        itemsByListIdentifier: ["list-local-1": [remoteTask]]
      ),
      store: store,
      now: remoteModifiedAt
    )
    _ = try await RetainedLogseqProjectProvisioningSync.sync(
      store: store,
      reminderProjectProvider: provider,
      now: remoteModifiedAt
    )

    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)
    XCTAssertTrue(markdown.contains("- TODO Remote Reminder title"))
    XCTAssertTrue(markdown.contains("- keep Logseq-only child note"))
    XCTAssertEqual(provider.titleWrites.count, 0)
  }

  func testNoBaselineMergeUsesReminderAsInitialBaselineBeforeProvisioning() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Stale local title
      reminder_external_id:: task-ext-1
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 2_000)
    let remoteTask = ReminderItemImportSnapshot(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-local-1",
      sourceListTitle: "Launch",
      title: "Remote Reminder title",
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
      createdAt: remoteModifiedAt,
      modifiedAt: remoteModifiedAt
    )
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Remote Reminder title",
      noteText: "",
      isCompleted: false,
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: remoteModifiedAt
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [
          .init(
            identifier: "list-local-1",
            externalIdentifier: "list-ext-1",
            title: "Launch",
            colorHex: nil
          ),
        ],
        itemsByListIdentifier: ["list-local-1": [remoteTask]]
      ),
      store: store,
      conflictPolicy: .mergeWithBaseline,
      now: remoteModifiedAt
    )
    _ = try await RetainedLogseqProjectProvisioningSync.sync(
      store: store,
      reminderProjectProvider: provider,
      now: remoteModifiedAt
    )

    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)
    XCTAssertTrue(markdown.contains("- TODO Remote Reminder title"))
    XCTAssertFalse(markdown.contains("Stale local title"))
    XCTAssertEqual(provider.titleWrites.count, 0)
    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-ext-1")?.state.title, "Remote Reminder title")
  }

  func testNewerLogseqChangeSurvivesStaleReminderImportAndPushesToReminder() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Local Logseq title
      reminder_external_id:: task-ext-1
      - keep Logseq-only child note
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let remoteModifiedAt = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 9))
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-1",
      state: ReminderSyncTaskState(
        title: "Stale Reminder title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    let localModifiedAt = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 10))
    )
    try FileManager.default.setAttributes(
      [.modificationDate: localModifiedAt],
      ofItemAtPath: projectPageURL.path
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [
          .init(
            identifier: "list-local-1",
            externalIdentifier: "list-ext-1",
            title: "Launch",
            colorHex: nil
          ),
        ],
        itemsByListIdentifier: [
          "list-local-1": [
            ReminderItemImportSnapshot(
              identifier: "task-local-1",
              externalIdentifier: "task-ext-1",
              parentExternalIdentifier: nil,
              sourceListIdentifier: "list-local-1",
              sourceListTitle: "Launch",
              title: "Stale Reminder title",
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
              createdAt: remoteModifiedAt,
              modifiedAt: remoteModifiedAt
            ),
          ],
        ]
      ),
      store: store,
      now: remoteModifiedAt
    )
    let importedMarkdown = try String(contentsOf: projectPageURL, encoding: .utf8)
    let importedModificationDate = try XCTUnwrap(
      projectPageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    )
    XCTAssertTrue(importedMarkdown.contains("- TODO Local Logseq title"))
    XCTAssertFalse(importedMarkdown.contains("Stale Reminder title"))
    XCTAssertLessThan(abs(importedModificationDate.timeIntervalSince(localModifiedAt)), 0.5)

    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Stale Reminder title",
      noteText: "",
      isCompleted: false,
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: remoteModifiedAt
    )
    _ = try await RetainedLogseqProjectProvisioningSync.sync(
      store: store,
      reminderProjectProvider: provider,
      now: localModifiedAt
    )

    XCTAssertEqual(provider.titleWrites.map(\.title), ["Local Logseq title"])
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.title, "Local Logseq title")
  }

  func testChangedPageDoesNotOverwriteRemoteFieldChangedSinceBaseline() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Base title
      reminder_external_id:: task-ext-1
      - Local note changed
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)

    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-1",
      state: ReminderSyncTaskState(
        title: "Base title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: Date(timeIntervalSince1970: 1_000),
      now: Date(timeIntervalSince1970: 1_000)
    )

    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Remote title",
      noteText: "",
      isCompleted: false,
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: Date(timeIntervalSince1970: 2_000)
    )

    _ = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: store,
      reminderProjectProvider: provider
    )

    XCTAssertEqual(provider.titleWrites.count, 0)
    XCTAssertEqual(provider.noteWrites.map(\.noteText), ["Local note changed"])
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.title, "Remote title")
  }

  func testChangedPageDoesNotPushSameFieldConflictOverRemoteChange() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Local title
      reminder_external_id:: task-ext-1
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-1",
      state: ReminderSyncTaskState(
        title: "Base title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: Date(timeIntervalSince1970: 1_000),
      now: Date(timeIntervalSince1970: 1_000)
    )

    let provider = ProvisioningFakeReminderProjectProvider()
    provider.taskSnapshotsByExternalIdentifier["task-ext-1"] = .init(
      identifier: "task-local-1",
      externalIdentifier: "task-ext-1",
      calendarIdentifier: "list-ext-1",
      title: "Remote title",
      noteText: "",
      isCompleted: false,
      dueDate: nil,
      hasExplicitTime: false,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: Date(timeIntervalSince1970: 2_000)
    )

    _ = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )

    XCTAssertEqual(provider.titleWrites.count, 0)
    XCTAssertEqual(provider.taskSnapshotsByExternalIdentifier["task-ext-1"]?.title, "Remote title")
  }

  func testDeletedLogseqTaskRemovesMatchingReminderWhenBaselineIsStable() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    ReminderDeletedTaskTombstoneStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    defer { ReminderDeletedTaskTombstoneStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Kept task
      reminder_external_id:: task-ext-kept
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-kept",
      state: ReminderSyncTaskState(
        title: "Kept task",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-ext-deleted",
      state: ReminderSyncTaskState(
        title: "Deleted task",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: remoteModifiedAt,
      now: remoteModifiedAt
    )
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.importBatch = ReminderImportSnapshotBatch(
      lists: [
        .init(
          identifier: "list-ext-1",
          externalIdentifier: "list-ext-1",
          title: "Launch",
          colorHex: nil
        ),
      ],
      itemsByListIdentifier: [
        "list-ext-1": [
          makeImportItem(
            identifier: "task-local-kept",
            externalIdentifier: "task-ext-kept",
            title: "Kept task",
            listIdentifier: "list-ext-1",
            listTitle: "Launch",
            modifiedAt: remoteModifiedAt
          ),
          makeImportItem(
            identifier: "task-local-deleted",
            externalIdentifier: "task-ext-deleted",
            title: "Deleted task",
            listIdentifier: "list-ext-1",
            listTitle: "Launch",
            modifiedAt: remoteModifiedAt
          ),
        ],
      ]
    )

    let result = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )

    XCTAssertEqual(result.deletedTaskCount, 1)
    XCTAssertEqual(provider.removedTaskReferences.map(\.reminderExternalIdentifier), ["task-ext-deleted"])
    XCTAssertNotNil(ReminderSyncBaselineStore.baseline(for: "task-ext-kept"))
    XCTAssertNil(ReminderSyncBaselineStore.baseline(for: "task-ext-deleted"))
    XCTAssertTrue(
      ReminderDeletedTaskTombstoneStore.shouldSuppressImport(
        reminderExternalIdentifier: "task-ext-deleted",
        remoteModifiedAt: remoteModifiedAt,
        now: remoteModifiedAt.addingTimeInterval(1)
      )
    )
  }

  func testDeletedLogseqTaskWithoutBaselineFailsClosed() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    ReminderDeletedTaskTombstoneStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    defer { ReminderDeletedTaskTombstoneStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    Project notes only
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    let provider = ProvisioningFakeReminderProjectProvider()
    provider.importBatch = ReminderImportSnapshotBatch(
      lists: [
        .init(
          identifier: "list-ext-1",
          externalIdentifier: "list-ext-1",
          title: "Launch",
          colorHex: nil
        ),
      ],
      itemsByListIdentifier: [
        "list-ext-1": [
          makeImportItem(
            identifier: "task-local-1",
            externalIdentifier: "task-ext-1",
            title: "Remote-only task",
            listIdentifier: "list-ext-1",
            listTitle: "Launch",
            modifiedAt: remoteModifiedAt
          ),
        ],
      ]
    )

    let result = try await RetainedLogseqProjectProvisioningSync.syncChangedPages(
      fileURLs: [projectPageURL],
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      reminderProjectProvider: provider
    )

    XCTAssertEqual(result.deletedTaskCount, 0)
    XCTAssertEqual(provider.removedTaskReferences.count, 0)
  }

  func testDeletedLogseqTaskTombstoneSuppressesStaleReminderImport() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    ReminderDeletedTaskTombstoneStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    defer { ReminderDeletedTaskTombstoneStore.reset() }

    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    Project notes only
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
    let deletedAt = Date(timeIntervalSince1970: 2_000)
    let staleRemoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    ReminderDeletedTaskTombstoneStore.upsertTaskDeletion(
      reminderExternalIdentifier: "task-ext-deleted",
      deletedAt: deletedAt
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [
          .init(
            identifier: "list-ext-1",
            externalIdentifier: "list-ext-1",
            title: "Launch",
            colorHex: nil
          ),
        ],
        itemsByListIdentifier: [
          "list-ext-1": [
            makeImportItem(
              identifier: "task-local-deleted",
              externalIdentifier: "task-ext-deleted",
              title: "Deleted task",
              listIdentifier: "list-ext-1",
              listTitle: "Launch",
              modifiedAt: staleRemoteModifiedAt
            ),
          ],
        ]
      ),
      store: LogseqProjectPageStore(pagesRootURL: pagesRoot),
      conflictPolicy: .mergeWithBaseline,
      now: deletedAt.addingTimeInterval(1)
    )

    let markdown = try String(contentsOf: projectPageURL, encoding: .utf8)
    XCTAssertFalse(markdown.contains("Deleted task"))
    XCTAssertFalse(markdown.contains("task-ext-deleted"))
  }

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("RetainedLogseqProjectProvisioningSyncTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  private func makeImportItem(
    identifier: String,
    externalIdentifier: String,
    title: String,
    listIdentifier: String,
    listTitle: String,
    modifiedAt: Date
  ) -> ReminderItemImportSnapshot {
    ReminderItemImportSnapshot(
      identifier: identifier,
      externalIdentifier: externalIdentifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: listIdentifier,
      sourceListTitle: listTitle,
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
      createdAt: modifiedAt,
      modifiedAt: modifiedAt
    )
  }
}

@MainActor
private final class ProvisioningFakeReminderProjectProvider: ReminderProjectProvider {
  struct CreatedList {
    let title: String
  }

  struct CreatedTask {
    let inProject: String
    let title: String
    let dueDate: Date?
    let hasExplicitTime: Bool
    let noteText: String
  }

  struct CompletionWrite {
    let reference: ReminderTaskReference
    let isCompleted: Bool
  }

  struct RecurrenceWrite {
    let reference: ReminderTaskReference
    let recurrenceRuleRaw: String?
  }

  struct ScheduleWrite {
    let reference: ReminderTaskReference
    let dueDate: Date?
    let hasExplicitTime: Bool
  }

  struct TitleWrite {
    let reference: ReminderTaskReference
    let title: String
  }

  struct NoteWrite {
    let reference: ReminderTaskReference
    let noteText: String
  }

  var createdLists: [CreatedList] = []
  var createdTasks: [CreatedTask] = []
  var completionWrites: [CompletionWrite] = []
  var recurrenceWrites: [RecurrenceWrite] = []
  var scheduleWrites: [ScheduleWrite] = []
  var titleWrites: [TitleWrite] = []
  var noteWrites: [NoteWrite] = []
  var removedTaskReferences: [ReminderTaskReference] = []
  var taskSnapshotsByExternalIdentifier: [String: ReminderTaskRemoteSnapshot] = [:]
  var importBatch: ReminderImportSnapshotBatch?
  var nextCreatedTaskNumber = 1

  var reminderGateway: ReminderGateway? { nil }
  var defaultCalendarIdentifierForNewReminders: String? { nil }

  func requestAccess() async throws -> Bool { true }

  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch? {
    guard let importBatch else { return nil }
    let requestedIdentifiers = Set(identifiers)
    let lists = importBatch.lists.filter { requestedIdentifiers.contains($0.identifier) }
    let itemsByListIdentifier = importBatch.itemsByListIdentifier.filter {
      requestedIdentifiers.contains($0.key)
    }
    return ReminderImportSnapshotBatch(
      lists: lists,
      itemsByListIdentifier: itemsByListIdentifier
    )
  }

  func createProjectList(title: String) throws -> ReminderProjectListSnapshot {
    createdLists.append(CreatedList(title: title))
    return ReminderProjectListSnapshot(
      identifier: "list-local-\(createdLists.count)",
      externalIdentifier: "list-ext-\(createdLists.count)",
      title: title,
      colorHex: nil
    )
  }

  func removeProjectList(identifier: String) throws { _ = identifier }
  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot? { nil }
  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot? { nil }

  func createTaskReminder(
    inProject identifier: String,
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    let createdTaskNumber = nextCreatedTaskNumber
    nextCreatedTaskNumber += 1
    createdTasks.append(
      CreatedTask(
        inProject: identifier,
        title: title,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime,
        noteText: noteText
      )
    )
    return ReminderTaskRemoteMetadata(
      identifier: "task-local-\(createdTaskNumber)",
      externalIdentifier: "task-ext-\(createdTaskNumber)",
      modifiedAt: .now
    )
  }

  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool {
    removedTaskReferences.append(task)
    guard let reminderExternalIdentifier = task.reminderExternalIdentifier else {
      return false
    }
    taskSnapshotsByExternalIdentifier.removeValue(forKey: reminderExternalIdentifier)
    return true
  }

  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot? {
    guard let reminderExternalIdentifier = task.reminderExternalIdentifier else {
      return nil
    }
    return taskSnapshotsByExternalIdentifier[reminderExternalIdentifier]
  }

  func setTaskTitle(for task: ReminderTaskReference, title: String) throws -> ReminderTaskRemoteMetadata? {
    titleWrites.append(TitleWrite(reference: task, title: title))
    if let reminderExternalIdentifier = task.reminderExternalIdentifier,
      let snapshot = taskSnapshotsByExternalIdentifier[reminderExternalIdentifier]
    {
      taskSnapshotsByExternalIdentifier[reminderExternalIdentifier] = ReminderTaskRemoteSnapshot(
        identifier: snapshot.identifier,
        externalIdentifier: snapshot.externalIdentifier,
        calendarIdentifier: snapshot.calendarIdentifier,
        title: title,
        noteText: snapshot.noteText,
        isCompleted: snapshot.isCompleted,
        completionDate: snapshot.completionDate,
        startDate: snapshot.startDate,
        dueDate: snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime,
        priority: snapshot.priority,
        recurrenceRuleRaw: snapshot.recurrenceRuleRaw,
        modifiedAt: .now
      )
    }
    return ReminderTaskRemoteMetadata(
      identifier: task.reminderIdentifier ?? "",
      externalIdentifier: task.reminderExternalIdentifier,
      modifiedAt: .now
    )
  }

  func setTaskCompletion(
    for task: ReminderTaskReference,
    isCompleted: Bool,
    completionDate: Date?
  ) throws -> ReminderTaskRemoteMetadata? {
    completionWrites.append(CompletionWrite(reference: task, isCompleted: isCompleted))
    updateSnapshot(task) { snapshot in
      ReminderTaskRemoteSnapshot(
        identifier: snapshot.identifier,
        externalIdentifier: snapshot.externalIdentifier,
        calendarIdentifier: snapshot.calendarIdentifier,
        title: snapshot.title,
        noteText: snapshot.noteText,
        isCompleted: isCompleted,
        completionDate: completionDate,
        startDate: snapshot.startDate,
        dueDate: snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime,
        priority: snapshot.priority,
        recurrenceRuleRaw: snapshot.recurrenceRuleRaw,
        modifiedAt: .now
      )
    }
    return ReminderTaskRemoteMetadata(
      identifier: task.reminderIdentifier ?? "",
      externalIdentifier: task.reminderExternalIdentifier,
      modifiedAt: .now
    )
  }

  func setTaskReminderNote(for task: ReminderTaskReference, noteText: String) throws -> ReminderTaskRemoteMetadata? {
    noteWrites.append(NoteWrite(reference: task, noteText: noteText))
    updateSnapshot(task) { snapshot in
      ReminderTaskRemoteSnapshot(
        identifier: snapshot.identifier,
        externalIdentifier: snapshot.externalIdentifier,
        calendarIdentifier: snapshot.calendarIdentifier,
        title: snapshot.title,
        noteText: noteText,
        isCompleted: snapshot.isCompleted,
        completionDate: snapshot.completionDate,
        startDate: snapshot.startDate,
        dueDate: snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime,
        priority: snapshot.priority,
        recurrenceRuleRaw: snapshot.recurrenceRuleRaw,
        modifiedAt: .now
      )
    }
    return ReminderTaskRemoteMetadata(
      identifier: task.reminderIdentifier ?? "",
      externalIdentifier: task.reminderExternalIdentifier,
      modifiedAt: .now
    )
  }

  func setTaskSchedule(
    for task: ReminderTaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws -> ReminderTaskRemoteMetadata? {
    scheduleWrites.append(ScheduleWrite(
      reference: task,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime
    ))
    updateSnapshot(task) { snapshot in
      ReminderTaskRemoteSnapshot(
        identifier: snapshot.identifier,
        externalIdentifier: snapshot.externalIdentifier,
        calendarIdentifier: snapshot.calendarIdentifier,
        title: snapshot.title,
        noteText: snapshot.noteText,
        isCompleted: snapshot.isCompleted,
        completionDate: snapshot.completionDate,
        startDate: snapshot.startDate,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime,
        priority: snapshot.priority,
        recurrenceRuleRaw: snapshot.recurrenceRuleRaw,
        modifiedAt: .now
      )
    }
    return ReminderTaskRemoteMetadata(
      identifier: task.reminderIdentifier ?? "",
      externalIdentifier: task.reminderExternalIdentifier,
      modifiedAt: .now
    )
  }

  func setTaskRecurrence(
    for task: ReminderTaskReference,
    recurrenceRuleRaw: String?
  ) throws -> ReminderTaskRemoteMetadata? {
    recurrenceWrites.append(RecurrenceWrite(reference: task, recurrenceRuleRaw: recurrenceRuleRaw))
    updateSnapshot(task) { snapshot in
      ReminderTaskRemoteSnapshot(
        identifier: snapshot.identifier,
        externalIdentifier: snapshot.externalIdentifier,
        calendarIdentifier: snapshot.calendarIdentifier,
        title: snapshot.title,
        noteText: snapshot.noteText,
        isCompleted: snapshot.isCompleted,
        completionDate: snapshot.completionDate,
        startDate: snapshot.startDate,
        dueDate: snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime,
        priority: snapshot.priority,
        recurrenceRuleRaw: recurrenceRuleRaw,
        modifiedAt: .now
      )
    }
    return ReminderTaskRemoteMetadata(
      identifier: task.reminderIdentifier ?? "",
      externalIdentifier: task.reminderExternalIdentifier,
      modifiedAt: .now
    )
  }

  func setTaskPresentation(for task: ReminderTaskReference, priority: Int) throws -> ReminderTaskRemoteMetadata? {
    _ = task
    _ = priority
    return nil
  }

  func moveTaskReminder(
    for task: ReminderTaskReference,
    toProject identifier: String
  ) throws -> ReminderTaskRemoteMetadata? {
    _ = task
    _ = identifier
    return nil
  }

  func restoreArchivedProject(
    _ project: ReminderArchivedProjectSnapshot
  ) throws -> ReminderProjectRestoreResult {
    _ = project
    return ReminderProjectRestoreResult(
      list: ReminderProjectListSnapshot(
        identifier: "unused-list",
        externalIdentifier: "unused-list",
        title: "Unused",
        colorHex: nil
      ),
      taskMetadataByTaskID: [:]
    )
  }

  func removeArchivedProjectLists(
    _ projects: [ReminderProjectListReference]
  ) -> ReminderProjectCleanupResult {
    _ = projects
    return ReminderProjectCleanupResult(removedCount: 0, failedProjectIDs: [])
  }

  private func updateSnapshot(
    _ task: ReminderTaskReference,
    transform: (ReminderTaskRemoteSnapshot) -> ReminderTaskRemoteSnapshot
  ) {
    guard let reminderExternalIdentifier = task.reminderExternalIdentifier,
      let snapshot = taskSnapshotsByExternalIdentifier[reminderExternalIdentifier]
    else { return }
    taskSnapshotsByExternalIdentifier[reminderExternalIdentifier] = transform(snapshot)
  }
}

private extension Array {
  var onlyValue: Element? {
    count == 1 ? self[0] : nil
  }
}
