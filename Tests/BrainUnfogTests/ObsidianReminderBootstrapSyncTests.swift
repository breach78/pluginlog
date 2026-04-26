import XCTest
@testable import BrainUnfog

final class ObsidianReminderBootstrapSyncTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testEmptyVaultBootstrapCreatesReminderProjectNotesAndTasks() async throws {
    let store = ObsidianProjectMarkdownStore(vaultRootURL: try makeTemporaryDirectory())
    let dueDate = makeDate(year: 2026, month: 4, day: 25, hour: 9, minute: 30)
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "2026")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(
            identifier: "task-1",
            listIdentifier: "list-1",
            title: "Pay tax",
            notes: "sub one\n sub two",
            dueDate: dueDate,
            hasExplicitTime: true,
            recurrenceRuleRaw: "monthly|1"
          ),
        ],
      ]
    )

    let result = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
    let snapshots = try await store.loadProjectNotesInScope()

    XCTAssertEqual(result.importedProjectCount, 1)
    XCTAssertEqual(result.importedTaskCount, 1)
    XCTAssertEqual(result.projectRecords.map(\.title), ["2026"])
    XCTAssertEqual(result.projectRecords.map(\.reminderListExternalIdentifier), ["list-1"])
    XCTAssertEqual(result.taskRecords.map(\.title), ["Pay tax"])
    XCTAssertEqual(result.taskRecords.map(\.reminderExternalIdentifier), ["task-1"])
    XCTAssertEqual(snapshots.count, 1)
    XCTAssertEqual(snapshots[0].vaultRelativePath, "raw/projects/2026.md")
    XCTAssertEqual(snapshots[0].note.reminderListExternalIdentifier, "list-1")
    XCTAssertEqual(snapshots[0].note.tasks.first?.title, "Pay tax")
    XCTAssertEqual(snapshots[0].note.tasks.first?.metadata?.reminderExternalIdentifier, "task-1")
    XCTAssertEqual(snapshots[0].note.tasks.first?.metadata?.date, "2026-04-25")
    XCTAssertEqual(snapshots[0].note.tasks.first?.metadata?.time, "09:30")
    XCTAssertEqual(snapshots[0].note.tasks.first?.metadata?.repeatRule, "reminder")
    XCTAssertTrue(snapshots[0].rawMarkdown.contains("  - sub one"))
    XCTAssertTrue(snapshots[0].rawMarkdown.contains("    - sub two"))
    XCTAssertFalse(snapshots[0].rawMarkdown.contains("brain_unfog_" + "project_id"))
    XCTAssertFalse(snapshots[0].rawMarkdown.contains("brain_unfog_" + "task_id"))
  }

  func testDateOnlyDueDateWritesDateWithoutTime() async throws {
    let store = ObsidianProjectMarkdownStore(vaultRootURL: try makeTemporaryDirectory())
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Dates")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(
            identifier: "task-1",
            listIdentifier: "list-1",
            title: "Date only",
            dueDate: makeDate(year: 2026, month: 7, day: 15),
            hasExplicitTime: false
          ),
        ],
      ]
    )

    _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
    let snapshots = try await store.loadProjectNotesInScope()
    let task = try XCTUnwrap(snapshots.first?.note.tasks.first)

    XCTAssertEqual(task.metadata?.date, "2026-07-15")
    XCTAssertNil(task.metadata?.time)
  }

  func testBootstrapExpandsReminderNoteTaskMarkersIntoNestedTaskBlocks() async throws {
    let store = ObsidianProjectMarkdownStore(vaultRootURL: try makeTemporaryDirectory())
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Nested")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(
            identifier: "parent",
            listIdentifier: "list-1",
            title: "Parent",
            notes: "before\nt:child\nafter"
          ),
          makeItem(
            identifier: "child",
            listIdentifier: "list-1",
            title: "Child",
            notes: "child detail"
          ),
        ],
      ]
    )

    let result = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
    let snapshots = try await store.loadProjectNotesInScope()
    let raw = try XCTUnwrap(snapshots.first?.rawMarkdown)

    XCTAssertEqual(result.importedTaskCount, 2)
    XCTAssertTrue(raw.contains("  - before"))
    XCTAssertTrue(raw.contains("  - [ ] Child"))
    XCTAssertTrue(raw.contains(#""reminder_external_id":"child""#))
    XCTAssertTrue(raw.contains("    - child detail"))
    XCTAssertTrue(raw.contains("  - after"))
    XCTAssertFalse(raw.contains("t:child"))
    XCTAssertLessThan(
      try XCTUnwrap(raw.range(of: "  - before")?.lowerBound),
      try XCTUnwrap(raw.range(of: "  - [ ] Child")?.lowerBound)
    )
    XCTAssertLessThan(
      try XCTUnwrap(raw.range(of: "  - [ ] Child")?.lowerBound),
      try XCTUnwrap(raw.range(of: "  - after")?.lowerBound)
    )
    XCTAssertEqual(raw.components(separatedBy: "- [ ] Child").count - 1, 1)
  }

  func testRerunIsIdempotentAndDoesNotDuplicateNotesOrTasks() async throws {
    let store = ObsidianProjectMarkdownStore(vaultRootURL: try makeTemporaryDirectory())
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Stable")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(identifier: "task-1", listIdentifier: "list-1", title: "Stable task"),
        ],
      ]
    )

    _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
    let firstSnapshots = try await store.loadProjectNotesInScope()
    let firstRaw = try XCTUnwrap(firstSnapshots.first?.rawMarkdown)
    _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
    let snapshots = try await store.loadProjectNotesInScope()

    XCTAssertEqual(snapshots.count, 1)
    XCTAssertEqual(snapshots[0].note.tasks.count, 1)
    XCTAssertEqual(snapshots[0].rawMarkdown, firstRaw)
  }

  func testExistingOwnedNoteUpdatesThroughBaselineWithoutDuplicatingTasks() async throws {
    let store = ObsidianProjectMarkdownStore(vaultRootURL: try makeTemporaryDirectory())
    let firstBatch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Owned")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(identifier: "task-1", listIdentifier: "list-1", title: "Old title"),
        ],
      ]
    )
    let secondBatch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Owned")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(identifier: "task-1", listIdentifier: "list-1", title: "New title"),
        ],
      ]
    )

    _ = try await ObsidianReminderBootstrapSync.sync(batch: firstBatch, store: store)
    _ = try await ObsidianReminderBootstrapSync.sync(batch: secondBatch, store: store)
    let snapshots = try await store.loadProjectNotesInScope()
    let note = try XCTUnwrap(snapshots.first?.note)

    XCTAssertEqual(note.tasks.map(\.title), ["New title"])
    XCTAssertEqual(note.tasks.map(\.reminderExternalIdentifier), ["task-1"])
  }

  func testDamagedExistingNoteIsNotOverwritten() async throws {
    let vaultURL = try makeTemporaryDirectory()
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let projectsURL = vaultURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    let noteURL = projectsURL.appendingPathComponent("Damaged.md", isDirectory: false)
    let damaged = """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: list-1
    ---
    - [ ] Existing
      %% brain-unfog: {"reminder_external_id":
    """
    try damaged.write(to: noteURL, atomically: true, encoding: .utf8)
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Damaged")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(identifier: "task-1", listIdentifier: "list-1", title: "Remote"),
        ],
      ]
    )

    do {
      _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
      XCTFail("Expected damaged note bootstrap to fail closed")
    } catch {
      XCTAssertTrue(error is ObsidianReminderBootstrapSync.BootstrapError)
    }
    XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), damaged)
  }

  func testDuplicateReminderListTitlesProduceDistinctFiles() async throws {
    let store = ObsidianProjectMarkdownStore(vaultRootURL: try makeTemporaryDirectory())
    let batch = ReminderImportSnapshotBatch(
      lists: [
        makeList(identifier: "list-alpha-123", title: "Inbox"),
        makeList(identifier: "list-beta-456", title: "Inbox"),
      ],
      itemsByListIdentifier: [:]
    )

    _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
    let paths = try await store.loadProjectNotesInScope().map(\.vaultRelativePath).sorted()

    XCTAssertEqual(
      paths,
      [
        "raw/projects/Inbox - list-alp.md",
        "raw/projects/Inbox - list-bet.md",
      ]
    )
  }

  func testDuplicateTaskIdentifiersFailClosedWithoutWrites() async throws {
    let vaultURL = try makeTemporaryDirectory()
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Dupes")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(identifier: "task-1", listIdentifier: "list-1", title: "One"),
          makeItem(identifier: "task-1", listIdentifier: "list-1", title: "Two"),
        ],
      ]
    )

    do {
      _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
      XCTFail("Expected duplicate task identity to fail closed")
    } catch ObsidianReminderBootstrapSync.BootstrapError.duplicateReminderExternalIdentifier("task-1") {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(try projectMarkdownFiles(in: vaultURL).isEmpty)
  }

  func testMissingTaskIdentifierFailsClosedWithoutWrites() async throws {
    let vaultURL = try makeTemporaryDirectory()
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Missing")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(identifier: "", listIdentifier: "list-1", title: "No identity"),
        ],
      ]
    )

    do {
      _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
      XCTFail("Expected missing task identity to fail closed")
    } catch ObsidianReminderBootstrapSync.BootstrapError.missingReminderExternalIdentifier("No identity") {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(try projectMarkdownFiles(in: vaultURL).isEmpty)
  }

  func testExistingUnownedFilenameCollisionRemainsUnchanged() async throws {
    let vaultURL = try makeTemporaryDirectory()
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let projectsURL = vaultURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    let noteURL = projectsURL.appendingPathComponent("Collision.md", isDirectory: false)
    let local = """
    ---
    tags:
      - 프로젝트
    ---
    - [ ] Local only
    """
    try local.write(to: noteURL, atomically: true, encoding: .utf8)
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Collision")],
      itemsByListIdentifier: ["list-1": []]
    )

    do {
      _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
      XCTFail("Expected unowned filename collision to fail closed")
    } catch ObsidianProjectMarkdownStore.StoreError.conflictingReminderListIdentity(
      existing: nil,
      requested: "list-1"
    ) {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), local)
  }

  func testExistingOwnedLocalOnlyContentRemainsUnchanged() async throws {
    let vaultURL = try makeTemporaryDirectory()
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultURL)
    let projectsURL = vaultURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    let noteURL = projectsURL.appendingPathComponent("Owned.md", isDirectory: false)
    let local = """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: list-1
    ---
    Local prose that bootstrap must not delete.
    - [ ] Existing
      %% brain-unfog: {"reminder_external_id":"task-1"} %%
    """
    try local.write(to: noteURL, atomically: true, encoding: .utf8)
    let batch = ReminderImportSnapshotBatch(
      lists: [makeList(identifier: "list-1", title: "Owned")],
      itemsByListIdentifier: [
        "list-1": [
          makeItem(identifier: "task-1", listIdentifier: "list-1", title: "Remote"),
        ],
      ]
    )

    do {
      _ = try await ObsidianReminderBootstrapSync.sync(batch: batch, store: store)
      XCTFail("Expected local-only content to fail closed")
    } catch ObsidianReminderBootstrapSync.BootstrapError.unsafeExistingNoteContent("raw/projects/Owned.md") {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), local)
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
    dueDate: Date? = nil,
    hasExplicitTime: Bool = false,
    recurrenceRuleRaw: String? = nil
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
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: dueDate,
      scheduleHasExplicitTime: hasExplicitTime,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: recurrenceRuleRaw,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: makeDate(year: 2026, month: 1, day: 1),
      modifiedAt: makeDate(year: 2026, month: 1, day: 1)
    )
  }

  private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0
  ) -> Date {
    DateComponents(
      calendar: Calendar.autoupdatingCurrent,
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute
    ).date!
  }

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ObsidianReminderBootstrapSyncTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  private func projectMarkdownFiles(in vaultURL: URL) throws -> [URL] {
    let projectsURL = vaultURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    guard FileManager.default.fileExists(atPath: projectsURL.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: projectsURL,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension.lowercased() == "md" }
  }
}
