import XCTest
@testable import BrainUnfogHarness

@MainActor
final class RetainedLogseqProjectProvisioningSyncTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
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

  func testExistingReminderBackedTaskTitleChangeUpdatesReminderInPlace() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - TODO Edited title
      reminder_external_id:: task-ext-1
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
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
      modifiedAt: .now
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

  func testExistingReminderBackedTaskChangesUpdateReminderInPlace() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let projectPageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-ext-1

    - DONE Existing task
      reminder_external_id:: task-ext-1
      date:: 2026-04-25 14:30
      repeat:: weekly
    """.write(to: projectPageURL, atomically: true, encoding: .utf8)
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
      modifiedAt: .now
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

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("RetainedLogseqProjectProvisioningSyncTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
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

  var createdLists: [CreatedList] = []
  var createdTasks: [CreatedTask] = []
  var completionWrites: [CompletionWrite] = []
  var recurrenceWrites: [RecurrenceWrite] = []
  var scheduleWrites: [ScheduleWrite] = []
  var titleWrites: [TitleWrite] = []
  var taskSnapshotsByExternalIdentifier: [String: ReminderTaskRemoteSnapshot] = [:]

  var reminderGateway: ReminderGateway? { nil }
  var defaultCalendarIdentifierForNewReminders: String? { nil }

  func requestAccess() async throws -> Bool { true }

  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch? {
    _ = identifiers
    return nil
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
    _ = noteText
    createdTasks.append(
      CreatedTask(
        inProject: identifier,
        title: title,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime
      )
    )
    return ReminderTaskRemoteMetadata(
      identifier: "task-local-\(createdTasks.count)",
      externalIdentifier: "task-ext-\(createdTasks.count)",
      modifiedAt: .now
    )
  }

  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool {
    _ = task
    return false
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
    _ = task
    _ = noteText
    return nil
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
