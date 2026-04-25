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

  func testReminderNoteUpdatesLogseqTaskSubtreeAndPreservesNestedTaskPosition() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let pageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-external-1

    - TODO Parent task
      reminder_external_id:: parent-ext
      - stale note
      - TODO Child one
        reminder_external_id:: child-one-ext
        - stale child one note
      - TODO Child two
        reminder_external_id:: child-two-ext
        - stale child two note
      - stale trailing
    """.write(to: pageURL, atomically: true, encoding: .utf8)
    let localModifiedAt = Date(timeIntervalSince1970: 1_000)
    let remoteModifiedAt = Date(timeIntervalSince1970: 2_000)
    try FileManager.default.setAttributes(
      [.modificationDate: localModifiedAt],
      ofItemAtPath: pageURL.path
    )
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Launch",
      colorHex: nil
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "parent-local",
              externalIdentifier: "parent-ext",
              title: "Parent task",
              notes: "remote note\nt:child-two-ext\nt:child-one-ext\nremote trailing",
              list: list,
              now: remoteModifiedAt
            ),
            makeItem(
              identifier: "child-one-local",
              externalIdentifier: "child-one-ext",
              title: "Child one",
              notes: "child one remote note",
              list: list,
              now: remoteModifiedAt
            ),
            makeItem(
              identifier: "child-two-local",
              externalIdentifier: "child-two-ext",
              title: "Child two",
              notes: "child two remote note",
              list: list,
              now: remoteModifiedAt
            ),
          ],
        ]
      ),
      store: store,
      now: remoteModifiedAt
    )

    let markdown = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertTrue(markdown.contains("  - remote note"))
    XCTAssertTrue(markdown.contains("  - TODO Child two"))
    XCTAssertTrue(markdown.contains("    - child two remote note"))
    XCTAssertTrue(markdown.contains("  - TODO Child one"))
    XCTAssertTrue(markdown.contains("    - child one remote note"))
    XCTAssertTrue(markdown.contains("  - remote trailing"))
    XCTAssertLessThan(
      try XCTUnwrap(markdown.range(of: "  - TODO Child two")?.lowerBound),
      try XCTUnwrap(markdown.range(of: "  - TODO Child one")?.lowerBound)
    )
    XCTAssertFalse(markdown.contains("stale note"))
    XCTAssertFalse(markdown.contains("stale child one note"))
    XCTAssertFalse(markdown.contains("stale child two note"))
    XCTAssertFalse(markdown.contains("stale trailing"))
  }

  func testImportUpdatesManyExistingTasksWithoutLosingLinePositions() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let pageURL = pagesRoot.appendingPathComponent("Bulk.md", isDirectory: false)
    let taskCount = 80
    var markdownLines = [
      "tags:: 프로젝트",
      "reminder_list_external_id:: list-external-1",
      "",
    ]
    for index in 0..<taskCount {
      markdownLines.append("- TODO Local task \(index)")
      markdownLines.append("  reminder_external_id:: task-external-\(index)")
      markdownLines.append("  - local note \(index)")
    }
    try markdownLines.joined(separator: "\n").write(to: pageURL, atomically: true, encoding: .utf8)

    let now = Date(timeIntervalSince1970: 3_000)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Bulk",
      colorHex: nil
    )
    let importedItems = (0..<taskCount).map { index in
      makeItem(
        identifier: "task-local-\(index)",
        externalIdentifier: "task-external-\(index)",
        title: "Remote task \(index)",
        notes: remoteBulkNote(for: index),
        list: list,
        now: now
      )
    }

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [list.identifier: importedItems]
      ),
      store: store,
      conflictPolicy: .remindersAuthoritative,
      now: now
    )

    let markdown = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertEqual(markdown.components(separatedBy: "reminder_external_id::").count - 1, taskCount)
    for index in 0..<taskCount {
      XCTAssertTrue(markdown.contains("- TODO Remote task \(index)"))
      XCTAssertTrue(
        markdown.contains("reminder_external_id:: task-external-\(index)"),
        "missing reminder id for task \(index)"
      )
      if index % 3 != 0 {
        XCTAssertTrue(markdown.contains("  - remote note \(index)"))
      }
      if index % 3 == 2 {
        XCTAssertTrue(markdown.contains("  - remote note \(index)-extra"))
        XCTAssertTrue(markdown.contains("  - remote note \(index)-tail"))
      }
    }
    XCTAssertFalse(markdown.contains("Local task"))
    XCTAssertFalse(markdown.contains("local note"))
  }

  func testReminderProjectionIdentityMatchesRetainedProjectionProjectIdentity() {
    XCTAssertEqual(
      ReminderProjectionIdentity.projectID(for: "list-external-1"),
      RetainedProjectionBuilder.derivedProjectID(for: "list-external-1")
    )
  }

  func testBootstrapImportOverwritesNewerLocalTaskWithReminderValue() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    let pageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-external-1

    - TODO Local stale title
      reminder_external_id:: task-external-1
      - stale local note
    """.write(to: pageURL, atomically: true, encoding: .utf8)
    let localModifiedAt = Date(timeIntervalSince1970: 2_000)
    let remoteModifiedAt = Date(timeIntervalSince1970: 1_000)
    try FileManager.default.setAttributes(
      [.modificationDate: localModifiedAt],
      ofItemAtPath: pageURL.path
    )
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Launch",
      colorHex: nil
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "task-local-1",
              externalIdentifier: "task-external-1",
              title: "Reminder source title",
              notes: "remote note",
              list: list,
              now: remoteModifiedAt
            )
          ],
        ]
      ),
      store: store,
      conflictPolicy: .remindersAuthoritative,
      now: remoteModifiedAt
    )

    let markdown = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertTrue(markdown.contains("- TODO Reminder source title"))
    XCTAssertTrue(markdown.contains("  - remote note"))
    XCTAssertFalse(markdown.contains("Local stale title"))
    XCTAssertFalse(markdown.contains("stale local note"))
  }

  func testFieldLevelMergeKeepsLocalTitleAndImportsRemoteSchedule() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let pageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-external-1

    - TODO Local title
      reminder_external_id:: task-external-1
    """.write(to: pageURL, atomically: true, encoding: .utf8)

    let baseline = ReminderSyncTaskState(
      title: "Base title",
      isCompleted: false,
      date: nil,
      repeatRule: nil,
      noteText: nil
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-external-1",
      state: baseline,
      remoteModifiedAt: Date(timeIntervalSince1970: 1_000),
      now: Date(timeIntervalSince1970: 1_000)
    )

    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Launch",
      colorHex: nil
    )
    let remoteModifiedAt = Date(timeIntervalSince1970: 2_000)
    let dueDate = try XCTUnwrap(
      Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 9))
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            ReminderItemImportSnapshot(
              identifier: "task-local-1",
              externalIdentifier: "task-external-1",
              parentExternalIdentifier: nil,
              sourceListIdentifier: list.identifier,
              sourceListTitle: list.title,
              title: "Base title",
              notes: "",
              attachmentCount: 0,
              isCompleted: false,
              completionDate: nil,
              startDate: nil,
              dueDate: dueDate,
              scheduleHasExplicitTime: true,
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
      conflictPolicy: .mergeWithBaseline,
      now: remoteModifiedAt
    )

    let markdown = try String(contentsOf: pageURL, encoding: .utf8)
    let mergedBaseline = try XCTUnwrap(
      ReminderSyncBaselineStore.baseline(for: "task-external-1")
    )
    XCTAssertTrue(markdown.contains("- TODO Local title"))
    XCTAssertTrue(markdown.contains("date:: 2026-05-01 09:00"))
    XCTAssertEqual(mergedBaseline.state.title, "Base title")
    XCTAssertEqual(mergedBaseline.state.date, "2026-05-01 09:00")
  }

  func testEventMergeDoesNotOverwriteLocalTitleWithStaleReminderTitle() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let pageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-external-1

    - TODO Local title
      reminder_external_id:: task-external-1
    """.write(to: pageURL, atomically: true, encoding: .utf8)

    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-external-1",
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
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Launch",
      colorHex: nil
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "task-local-1",
              externalIdentifier: "task-external-1",
              title: "Base title",
              list: list,
              now: Date(timeIntervalSince1970: 1_500)
            ),
          ],
        ]
      ),
      store: store,
      conflictPolicy: .mergeWithBaseline,
      now: Date(timeIntervalSince1970: 1_500)
    )

    let markdown = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertTrue(markdown.contains("- TODO Local title"))
    XCTAssertFalse(markdown.contains("- TODO Base title"))
  }

  func testStaleReminderSnapshotOlderThanBaselineDoesNotOverwriteLogseqOrBaseline() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let pageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-external-1

    - TODO Already pushed Logseq title
      reminder_external_id:: task-external-1
    """.write(to: pageURL, atomically: true, encoding: .utf8)

    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-external-1",
      state: ReminderSyncTaskState(
        title: "Already pushed Logseq title",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: Date(timeIntervalSince1970: 2_000),
      now: Date(timeIntervalSince1970: 2_000)
    )

    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Launch",
      colorHex: nil
    )
    let staleRemoteModifiedAt = Date(timeIntervalSince1970: 1_500)

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "task-local-1",
              externalIdentifier: "task-external-1",
              title: "Stale Reminder title",
              list: list,
              now: staleRemoteModifiedAt
            ),
          ],
        ]
      ),
      store: store,
      conflictPolicy: .mergeWithBaseline,
      now: staleRemoteModifiedAt
    )

    let markdown = try String(contentsOf: pageURL, encoding: .utf8)
    let baseline = try XCTUnwrap(ReminderSyncBaselineStore.baseline(for: "task-external-1"))
    XCTAssertTrue(markdown.contains("- TODO Already pushed Logseq title"))
    XCTAssertFalse(markdown.contains("Stale Reminder title"))
    XCTAssertEqual(baseline.state.title, "Already pushed Logseq title")
    XCTAssertEqual(baseline.remoteModifiedAt, Date(timeIntervalSince1970: 2_000))
  }

  func testDuplicateLocalReminderIdentifiersAreNotImportedOver() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let pageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-external-1

    - TODO First ambiguous local task
      reminder_external_id:: task-external-1
    - TODO Second ambiguous local task
      reminder_external_id:: task-external-1
    """.write(to: pageURL, atomically: true, encoding: .utf8)

    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Launch",
      colorHex: nil
    )
    let remoteModifiedAt = Date(timeIntervalSince1970: 2_000)

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "task-local-1",
              externalIdentifier: "task-external-1",
              title: "Remote title",
              list: list,
              now: remoteModifiedAt
            ),
          ],
        ]
      ),
      store: store,
      conflictPolicy: .remindersAuthoritative,
      now: remoteModifiedAt
    )

    let markdown = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertTrue(markdown.contains("- TODO First ambiguous local task"))
    XCTAssertTrue(markdown.contains("- TODO Second ambiguous local task"))
    XCTAssertFalse(markdown.contains("Remote title"))
    XCTAssertNil(ReminderSyncBaselineStore.baseline(for: "task-external-1"))
  }

  func testImportedReminderNoteRendersIntoNewLogseqTaskSubtree() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRoot.appendingPathComponent("pages", isDirectory: true)
    )
    let now = Date(timeIntervalSince1970: 2_000)
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Client Project",
      colorHex: nil
    )

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "task-local-1",
              externalIdentifier: "task-external-1",
              title: "Reminder task",
              notes: "first line\n nested line",
              list: list,
              now: now
            )
          ],
        ]
      ),
      store: store,
      conflictPolicy: .remindersAuthoritative,
      now: now
    )

    let pages = try await store.loadProjectPagesInScope()
    let pageFile = try XCTUnwrap(pages.first?.fileURL)
    let markdown = try String(contentsOf: pageFile, encoding: .utf8)
    XCTAssertTrue(markdown.contains("- TODO Reminder task"))
    XCTAssertTrue(markdown.contains("  - first line"))
    XCTAssertTrue(markdown.contains("    - nested line"))
    XCTAssertEqual(
      ReminderSyncBaselineStore.baseline(for: "task-external-1")?.state.noteText,
      "first line\n nested line"
    )
  }

  func testRemoteReminderNoteDeletionClearsLogseqSubtreeWithoutPushingStaleNoteBack() async throws {
    let graphRoot = try makeTemporaryDirectory()
    let pagesRoot = graphRoot.appendingPathComponent("pages", isDirectory: true)
    let dataRoot = graphRoot.appendingPathComponent(".buf/data", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRoot, withIntermediateDirectories: true)
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    defer { ReminderSyncBaselineStore.reset() }

    let pageURL = pagesRoot.appendingPathComponent("Launch.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: list-external-1

    - TODO Parent task
      reminder_external_id:: parent-ext
      - stale note
    """.write(to: pageURL, atomically: true, encoding: .utf8)
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "parent-ext",
      state: ReminderSyncTaskState(
        title: "Parent task",
        isCompleted: false,
        date: nil,
        repeatRule: nil,
        noteText: "stale note"
      ),
      remoteModifiedAt: Date(timeIntervalSince1970: 1_000),
      now: Date(timeIntervalSince1970: 1_000)
    )
    let list = ReminderListImportSnapshot(
      identifier: "list-local-1",
      externalIdentifier: "list-external-1",
      title: "Launch",
      colorHex: nil
    )
    let store = LogseqProjectPageStore(pagesRootURL: pagesRoot)

    _ = try await RetainedReminderImportSync.sync(
      batch: ReminderImportSnapshotBatch(
        lists: [list],
        itemsByListIdentifier: [
          list.identifier: [
            makeItem(
              identifier: "parent-local",
              externalIdentifier: "parent-ext",
              title: "Parent task",
              notes: "",
              list: list,
              now: Date(timeIntervalSince1970: 2_000)
            )
          ],
        ]
      ),
      store: store,
      conflictPolicy: .mergeWithBaseline,
      now: Date(timeIntervalSince1970: 2_000)
    )

    let markdown = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertTrue(markdown.contains("- TODO Parent task"))
    XCTAssertFalse(markdown.contains("stale note"))
    XCTAssertNil(ReminderSyncBaselineStore.baseline(for: "parent-ext")?.state.noteText)
  }

  private func makeItem(
    identifier: String,
    externalIdentifier: String,
    title: String,
    notes: String = "",
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
      notes: notes,
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

  private func remoteBulkNote(for index: Int) -> String {
    switch index % 3 {
    case 0:
      return ""
    case 1:
      return "remote note \(index)"
    default:
      return "remote note \(index)\nremote note \(index)-extra\nremote note \(index)-tail"
    }
  }

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("RetainedReminderImportSyncTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }
}
