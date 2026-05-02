import XCTest
import SQLite3
@testable import BrainUnfog

final class AppOwnedWorkspaceStoreTests: XCTestCase {
  func testPrepareCreatesEmptySQLiteStore() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())

    try await store.prepare()

    let hasImportedWorkspace = try await store.hasImportedWorkspace()
    XCTAssertFalse(hasImportedWorkspace)
  }

  func testReplaceReminderSnapshotBuildsRetainedWorkspaceSnapshot() async throws {
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
    let createdAt = Date(timeIntervalSinceReferenceDate: 200)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Project",
          colorHex: "#2255aa"
        )
      ],
      itemsByListIdentifier: [
        "list-1": [
          ReminderItemImportSnapshot(
            identifier: "task-1",
            externalIdentifier: "task-1",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "Project",
            title: "Task",
            notes: "note",
            attachmentCount: 2,
            isCompleted: false,
            completionDate: nil,
            startDate: nil,
            dueDate: dueDate,
            scheduleHasExplicitTime: false,
            scheduledDurationMinutes: nil,
            priority: 1,
            recurrenceRuleRaw: "daily",
            isFlagged: true,
            requiredWorkDays: 3,
            createdAt: createdAt,
            modifiedAt: createdAt
          )
        ]
      ]
    )

    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    let project = try XCTUnwrap(snapshot.projects.first)
    let task = try XCTUnwrap(project.tasks.first)
    let hasImportedWorkspace = try await store.hasImportedWorkspace()
    XCTAssertTrue(hasImportedWorkspace)
    XCTAssertEqual(project.identity.projectID, RetainedProjectionBuilder.derivedProjectID(for: "list-1"))
    XCTAssertEqual(project.title, "Project")
    XCTAssertEqual(project.colorHex, "#2255aa")
    XCTAssertEqual(task.identity.taskID, ReminderProjectionIdentity.taskID(for: "task-1"))
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "task-1")
    XCTAssertEqual(task.title, "Task")
    XCTAssertEqual(task.noteText, "note")
    XCTAssertEqual(task.schedule.parsedDate, dueDate)
    XCTAssertEqual(task.schedule.rawRepeatRule, "daily")
  }

  func testMergeProjectSupplementsPreservesAppOwnedProjectFields() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let startDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
    let deadline = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Project",
            colorHex: "#111111"
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 250)
    )

    try await store.mergeProjectSupplements([
      AppOwnedWorkspaceStore.ProjectSupplement(
        projectID: projectID,
        noteMarkdown: "Project note",
        progressStageRaw: ProjectProgressStage.later.storageRawValue,
        startDate: startDate,
        deadline: deadline,
        isArchived: true,
        colorHex: "#222222"
      )
    ])
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(project.noteMarkdown, "Project note")
    XCTAssertEqual(project.progressStage, .later)
    XCTAssertEqual(project.localStartDate, startDate)
    XCTAssertEqual(project.localDeadline, deadline)
    XCTAssertTrue(project.isArchived)
    XCTAssertEqual(project.colorHex, "#222222")
  }

  func testReplaceReminderSnapshotKeepsAppOwnedProjectFieldsAcrossImports() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Original",
            colorHex: "#111111"
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 250)
    )
    try await store.mergeProjectSupplements([
      AppOwnedWorkspaceStore.ProjectSupplement(
        projectID: projectID,
        noteMarkdown: "App note",
        progressStageRaw: ProjectProgressStage.area.storageRawValue,
        startDate: nil,
        deadline: nil,
        isArchived: true,
        colorHex: "#222222"
      )
    ])

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Imported Update",
            colorHex: "#333333"
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 260)
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(project.title, "Imported Update")
    XCTAssertEqual(project.noteMarkdown, "App note")
    XCTAssertEqual(project.progressStage, .area)
    XCTAssertTrue(project.isArchived)
    XCTAssertEqual(project.colorHex, "#333333")
  }

  func testReplaceReminderSnapshotKeepsTaskDurationAcrossImports() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let createdAt = Date(timeIntervalSinceReferenceDate: 300)
    let item = ReminderItemImportSnapshot(
      identifier: "task-identifier",
      externalIdentifier: "task-1",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Task",
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
      createdAt: createdAt,
      modifiedAt: createdAt
    )
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Project",
          colorHex: nil
        )
      ],
      itemsByListIdentifier: ["list-1": [item]]
    )

    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: taskID, durationMinutes: 45)
    ])
    try await store.replaceReminderSnapshot(batch, importedAt: createdAt.addingTimeInterval(10))
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let task = try XCTUnwrap(snapshot.tasks.first)

    XCTAssertEqual(task.schedule.durationMinutes, 45)
  }

  func testRetainedSnapshotHidesCompletedRecurringOccurrenceWhenActiveOccurrenceIsRestored() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 11)))
    let rawDate = try XCTUnwrap(ReminderScheduleMetadataCodec.encodeDate(dueDate, hasExplicitTime: true))
    let createdAt = Date(timeIntervalSinceReferenceDate: 410)
    let active = ReminderItemImportSnapshot(
      identifier: "active-identifier",
      externalIdentifier: "task-1",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: "daily",
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )
    let completed = ReminderItemImportSnapshot(
      identifier: "completed-identifier",
      externalIdentifier: "task-1::completed::\(rawDate)",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "",
      attachmentCount: 0,
      isCompleted: true,
      completionDate: dueDate,
      startDate: nil,
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: "daily",
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: ["list-1": [active, completed]]
      ),
      importedAt: createdAt
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    XCTAssertEqual(snapshot.tasks.map(\.identity.reminderExternalIdentifier), ["task-1"])
  }

  func testRetainedSnapshotHidesCompletedRecurringOccurrencesEvenWhenCompletedDateIsAfterRestoredAnchor()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let activeDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 45)))
    let completedDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 12)))
    let completedAt = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 22, minute: 48)))
    let createdAt = Date(timeIntervalSinceReferenceDate: 420)
    let active = ReminderItemImportSnapshot(
      identifier: "active-identifier",
      externalIdentifier: "task-active",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: activeDueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: "daily|3",
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )
    let completed = ReminderItemImportSnapshot(
      identifier: "completed-identifier",
      externalIdentifier: "task-completed",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "",
      attachmentCount: 0,
      isCompleted: true,
      completionDate: completedAt,
      startDate: nil,
      dueDate: completedDueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: ["list-1": [active, completed]]
      ),
      importedAt: createdAt
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    XCTAssertEqual(snapshot.tasks.map(\.identity.reminderExternalIdentifier), ["task-active"])
  }

  func testRetainedSnapshotHidesCompletedOccurrenceThatLostRecurrenceRule() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let activeDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 8)))
    let completedDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
    let createdAt = Date(timeIntervalSinceReferenceDate: 415)
    let active = ReminderItemImportSnapshot(
      identifier: "active-identifier",
      externalIdentifier: "active-external",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "same note",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: activeDueDate,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: "daily|3",
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )
    let completed = ReminderItemImportSnapshot(
      identifier: "completed-identifier",
      externalIdentifier: "completed-external",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "same note",
      attachmentCount: 0,
      isCompleted: true,
      completionDate: completedDueDate,
      startDate: nil,
      dueDate: completedDueDate,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: ["list-1": [active, completed]]
      ),
      importedAt: createdAt
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    XCTAssertEqual(snapshot.tasks.map(\.identity.reminderExternalIdentifier), ["active-external"])
  }

  func testReplaceReminderSnapshotKeepsRecurringTaskIDWhenExternalIdentifierChanges()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let firstDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
    let nextDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 5)))
    let createdAt = Date(timeIntervalSinceReferenceDate: 418)
    let first = ReminderItemImportSnapshot(
      identifier: "first-identifier",
      externalIdentifier: "old-external",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "same note",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: firstDueDate,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: "daily|3",
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )
    let next = ReminderItemImportSnapshot(
      identifier: "next-identifier",
      externalIdentifier: "new-external",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "same note",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: nextDueDate,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: "daily|3",
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt.addingTimeInterval(10)
    )

    try await store.replaceReminderSnapshot(
      Self.batch(items: [first], createdAt: createdAt),
      importedAt: createdAt
    )
    try await store.replaceReminderSnapshot(
      Self.batch(items: [next], createdAt: createdAt.addingTimeInterval(10)),
      importedAt: createdAt.addingTimeInterval(10)
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let task = try XCTUnwrap(snapshot.tasks.first)

    XCTAssertEqual(task.identity.taskID, ReminderProjectionIdentity.taskID(for: "old-external"))
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "new-external")
  }

  func testReorderOpenTasksPersistsRetainedWorkspaceTaskOrder() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let createdAt = Date(timeIntervalSinceReferenceDate: 420)
    try await store.replaceReminderSnapshot(
      Self.batch(
        taskExternalIdentifiers: ["task-1", "task-2", "task-3"],
        createdAt: createdAt
      ),
      importedAt: createdAt
    )
    let firstID = ReminderProjectionIdentity.taskID(for: "task-1")
    let secondID = ReminderProjectionIdentity.taskID(for: "task-2")
    let thirdID = ReminderProjectionIdentity.taskID(for: "task-3")
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")

    try await store.reorderOpenTasks(
      projectID: projectID,
      orderedTaskIDs: [thirdID, firstID, secondID]
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])

    XCTAssertEqual(snapshot.tasks.map(\.identity.taskID), [thirdID, firstID, secondID])
  }

  func testReplaceReminderSnapshotKeepsManualTaskOrderAcrossImports() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let createdAt = Date(timeIntervalSinceReferenceDate: 430)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let firstID = ReminderProjectionIdentity.taskID(for: "task-1")
    let secondID = ReminderProjectionIdentity.taskID(for: "task-2")
    let thirdID = ReminderProjectionIdentity.taskID(for: "task-3")
    let batch = Self.batch(
      taskExternalIdentifiers: ["task-1", "task-2", "task-3"],
      createdAt: createdAt
    )

    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    try await store.reorderOpenTasks(
      projectID: projectID,
      orderedTaskIDs: [thirdID, firstID, secondID]
    )
    try await store.replaceReminderSnapshot(batch, importedAt: createdAt.addingTimeInterval(10))
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])

    XCTAssertEqual(snapshot.tasks.map(\.identity.taskID), [thirdID, firstID, secondID])
  }

  func testLoadPrefersAppOwnedStoreWhenSQLiteHasImportedRows() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: vaultRoot.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    let containerRoot = ObsidianVaultLayout(vaultRootURL: vaultRoot).sidecarRootURL
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let createdAt = Date(timeIntervalSinceReferenceDate: 300)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Stored Project",
          colorHex: nil
        )
      ],
      itemsByListIdentifier: [:]
    )
    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    try await store.setProjectionReadEnabled(true)

    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: vaultRoot,
      projectIDs: [],
      calendar: Self.calendar
    )
    let projection: RetainedWorkspaceSurfaceProjection
    switch result {
    case .loaded(let loadedProjection):
      projection = loadedProjection
    case .blocked(let blocker):
      return XCTFail("Expected app-owned projection, got \(blocker)")
    }

    XCTAssertEqual(
      projection.projectSnapshots[RetainedProjectionBuilder.derivedProjectID(for: "list-1")]?.title,
      "Stored Project"
    )
  }

  func testLoadFallsBackToLegacySourceUntilProjectionReadIsEnabled() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: vaultRoot.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    let store = AppOwnedWorkspaceStore(
      containerRootURL: ObsidianVaultLayout(vaultRootURL: vaultRoot).sidecarRootURL
    )
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Shadow Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 400)
    )

    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: vaultRoot,
      projectIDs: [],
      calendar: Self.calendar
    )

    switch result {
    case .loaded(let projection):
      XCTAssertNil(projection.projectSnapshots[RetainedProjectionBuilder.derivedProjectID(for: "list-1")])
    case .blocked:
      break
    }
  }

  func testProjectionReadDoesNotAttemptSchemaWritesWhileAnotherConnectionIsWriting() async throws {
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let createdAt = Date(timeIntervalSinceReferenceDate: 500)
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: createdAt
    )
    try await store.setProjectionReadEnabled(true)

    var writer: OpaquePointer?
    let sqliteURL = ContainerPaths(root: containerRoot).sqliteURL
    XCTAssertEqual(sqlite3_open(sqliteURL.path, &writer), SQLITE_OK)
    defer {
      sqlite3_exec(writer, "ROLLBACK;", nil, nil, nil)
      sqlite3_close(writer)
    }
    XCTAssertEqual(sqlite3_exec(writer, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil), SQLITE_OK)

    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    XCTAssertEqual(snapshot.projects.first?.title, "Project")
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private static func batch(
    taskExternalIdentifiers: [String],
    createdAt: Date
  ) -> ReminderImportSnapshotBatch {
    ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Project",
          colorHex: nil
        )
      ],
      itemsByListIdentifier: [
        "list-1": taskExternalIdentifiers.map { identifier in
          ReminderItemImportSnapshot(
            identifier: "\(identifier)-identifier",
            externalIdentifier: identifier,
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "Project",
            title: identifier,
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
            createdAt: createdAt,
            modifiedAt: createdAt
          )
        }
      ]
    )
  }

  private static func batch(
    items: [ReminderItemImportSnapshot],
    createdAt: Date
  ) -> ReminderImportSnapshotBatch {
    _ = createdAt
    return ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Project",
          colorHex: nil
        )
      ],
      itemsByListIdentifier: ["list-1": items]
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppOwnedWorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
