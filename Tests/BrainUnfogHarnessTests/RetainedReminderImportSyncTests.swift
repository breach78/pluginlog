import XCTest
@testable import BrainUnfogHarness

final class RetainedReminderImportSyncTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testSyncImportsReminderListsAndTasksIntoRetainedLogseqPages() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRoot.appendingPathComponent("pages", isDirectory: true)
    )
    let dueDate = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 9, minute: 30))
    )
    let batch = ReminderImportSnapshotBatch(
      lists: [
        .init(
          identifier: "list-local-1",
          externalIdentifier: "list-external-1",
          title: "Client Project",
          colorHex: nil
        )
      ],
      itemsByListIdentifier: [
        "list-local-1": [
          .init(
            identifier: "task-local-1",
            externalIdentifier: "task-external-1",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-local-1",
            sourceListTitle: "Client Project",
            title: "Prepare kickoff",
            notes: "",
            attachmentCount: 0,
            isCompleted: false,
            completionDate: nil,
            startDate: nil,
            dueDate: dueDate,
            scheduleHasExplicitTime: true,
            scheduledDurationMinutes: 45,
            priority: 0,
            recurrenceRuleRaw: "weekly",
            isFlagged: false,
            requiredWorkDays: 0,
            createdAt: dueDate,
            modifiedAt: dueDate
          )
        ],
      ]
    )

    let result = try await RetainedReminderImportSync.sync(batch: batch, store: store, now: dueDate)
    let secondResult = try await RetainedReminderImportSync.sync(batch: batch, store: store, now: dueDate)
    let pages = try await store.loadProjectPagesInScope()
    let snapshot = try RetainedProjectionBuilder.build(.init(pages: pages))
    let pageFile = try XCTUnwrap(pages.first?.fileURL)
    let pageMarkdown = try String(contentsOf: pageFile, encoding: .utf8)

    XCTAssertEqual(result.importedProjectCount, 1)
    XCTAssertEqual(result.importedTaskCount, 1)
    XCTAssertEqual(secondResult.importedProjectCount, 1)
    XCTAssertEqual(secondResult.importedTaskCount, 1)
    XCTAssertEqual(pages.count, 1)
    XCTAssertEqual(snapshot.projects.count, 1)
    XCTAssertEqual(snapshot.projects[0].title, "Client Project")
    XCTAssertEqual(
      snapshot.projects[0].identity.projectID,
      RetainedProjectionBuilder.derivedProjectID(for: "list-external-1")
    )
    XCTAssertEqual(snapshot.projects[0].tasks.count, 1)
    XCTAssertEqual(snapshot.projects[0].tasks[0].title, "Prepare kickoff")
    XCTAssertEqual(
      snapshot.projects[0].tasks[0].identity.taskID,
      ReminderProjectionIdentity.taskID(for: "task-external-1")
    )
    XCTAssertEqual(snapshot.projects[0].tasks[0].identity.reminderExternalIdentifier, "task-external-1")
    XCTAssertEqual(snapshot.projects[0].tasks[0].schedule.rawDate, "2026-04-24 09:30")
    XCTAssertNil(snapshot.projects[0].tasks[0].schedule.rawDuration)
    XCTAssertEqual(snapshot.projects[0].tasks[0].schedule.rawRepeatRule, "weekly")
    XCTAssertFalse(pageMarkdown.contains("brain_unfog_project_id::"))
    XCTAssertFalse(pageMarkdown.contains("brain_unfog_task_id::"))
    XCTAssertFalse(pageMarkdown.contains("## Brain Unfog Managed Tasks"))
    XCTAssertFalse(pageMarkdown.contains("<!-- generated-by: Brain Unfog -->"))
    XCTAssertEqual(pageMarkdown.components(separatedBy: "reminder_external_id:: task-external-1").count - 1, 1)
    XCTAssertEqual(pages.first?.managedTasks.count, 0)
    XCTAssertEqual(pages.first?.externalTasks.count, 1)
  }

  func testSyncAppendsNewReminderItemsToExistingRetainedPage() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRoot.appendingPathComponent("pages", isDirectory: true)
    )
    let now = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 10))
    )
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Client Project",
      colorHex: nil
    )
    let initialBatch = ReminderImportSnapshotBatch(
      lists: [list],
      itemsByListIdentifier: [
        list.identifier: [
          makeItem(
            identifier: "task-local-1",
            externalIdentifier: "task-external-1",
            title: "Existing external reminder",
            list: list,
            now: now
          )
        ],
      ]
    )
    let expandedBatch = ReminderImportSnapshotBatch(
      lists: [list],
      itemsByListIdentifier: [
        list.identifier: [
          makeItem(
            identifier: "task-local-1",
            externalIdentifier: "task-external-1",
            title: "Existing external reminder",
            list: list,
            now: now
          ),
          makeItem(
            identifier: "task-local-2",
            externalIdentifier: "task-external-2",
            title: "New external reminder",
            list: list,
            now: now.addingTimeInterval(60)
          ),
        ],
      ]
    )

    _ = try await RetainedReminderImportSync.sync(batch: initialBatch, store: store, now: now)
    _ = try await RetainedReminderImportSync.sync(batch: expandedBatch, store: store, now: now)
    _ = try await RetainedReminderImportSync.sync(batch: expandedBatch, store: store, now: now)
    let pages = try await store.loadProjectPagesInScope()
    let pageFile = try XCTUnwrap(pages.first?.fileURL)
    let pageMarkdown = try String(contentsOf: pageFile, encoding: .utf8)

    XCTAssertEqual(pages.count, 1)
    XCTAssertEqual(pages.first?.externalTasks.map(\.title), [
      "Existing external reminder",
      "New external reminder",
    ])
    XCTAssertEqual(pageMarkdown.components(separatedBy: "reminder_external_id:: task-external-1").count - 1, 1)
    XCTAssertEqual(pageMarkdown.components(separatedBy: "reminder_external_id:: task-external-2").count - 1, 1)
  }

  func testReminderProjectionIdentityMatchesRetainedProjectionProjectIdentity() {
    XCTAssertEqual(
      ReminderProjectionIdentity.projectID(for: "list-external-1"),
      RetainedProjectionBuilder.derivedProjectID(for: "list-external-1")
    )
  }

  private func makeItem(
    identifier: String,
    externalIdentifier: String,
    title: String,
    list: ReminderListImportSnapshot,
    now: Date
  ) -> ReminderItemImportSnapshot {
    ReminderItemImportSnapshot(
      identifier: identifier,
      externalIdentifier: externalIdentifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: list.identifier,
      sourceListTitle: list.title,
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
      createdAt: now,
      modifiedAt: now
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("RetainedReminderImportSyncTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }
}
