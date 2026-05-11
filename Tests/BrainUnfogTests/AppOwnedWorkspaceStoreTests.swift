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

  func testProjectBoardOrderPersistsAcrossReminderImports() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let importedAt = Date(timeIntervalSinceReferenceDate: 201)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "First",
          colorHex: nil
        ),
        ReminderListImportSnapshot(
          identifier: "list-2",
          externalIdentifier: "list-2",
          title: "Second",
          colorHex: nil
        ),
      ],
      itemsByListIdentifier: [:]
    )
    let firstProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let secondProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-2")

    try await store.replaceReminderSnapshot(batch, importedAt: importedAt)
    try await store.updateProjectBoardOrders(
      [
        firstProjectID: 1,
        secondProjectID: 0,
      ]
    )
    try await store.replaceReminderSnapshot(batch, importedAt: importedAt.addingTimeInterval(20))

    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map {
      ($0.identity.projectID, $0)
    })
    XCTAssertEqual(projectsByID[firstProjectID]?.boardOrder, 1)
    XCTAssertEqual(projectsByID[secondProjectID]?.boardOrder, 0)
  }

  func testAppOwnedProjectionCanLoadProjectInsertedAfterInitialImport() async throws {
    let vaultRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore.storeForVaultRootURL(vaultRoot)
    let importedAt = Date(timeIntervalSinceReferenceDate: 202)
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Existing Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [:]
      ),
      importedAt: importedAt
    )
    try await store.setProjectionReadEnabled(true)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "new-list-external")

    try await store.upsertProject(
      projectID: projectID,
      reminderListIdentifier: "new-list-id",
      reminderListExternalIdentifier: "new-list-external",
      title: "새 프로젝트",
      colorHex: nil,
      modifiedAt: importedAt.addingTimeInterval(5)
    )
    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: vaultRoot,
      projectIDs: [projectID],
      calendar: Self.calendar,
      now: importedAt
    )

    guard case .loaded(let projection) = result else {
      XCTFail("Expected app-owned retained projection to load the inserted project.")
      return
    }
    XCTAssertEqual(projection.projectSnapshots[projectID]?.title, "새 프로젝트")
  }

  func testScopedRetainedWorkspaceSnapshotIgnoresUnrequestedProjectTaskRows() async throws {
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let createdAt = Date(timeIntervalSinceReferenceDate: 205)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "First Project",
          colorHex: nil
        ),
        ReminderListImportSnapshot(
          identifier: "list-2",
          externalIdentifier: "list-2",
          title: "Second Project",
          colorHex: nil
        ),
      ],
      itemsByListIdentifier: [
        "list-1": [
          ReminderItemImportSnapshot(
            identifier: "task-1",
            externalIdentifier: "task-1",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "First Project",
            title: "Requested Task",
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
        ],
        "list-2": [
          ReminderItemImportSnapshot(
            identifier: "task-2",
            externalIdentifier: "task-2",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-2",
            sourceListTitle: "Second Project",
            title: "Unrequested Task",
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
        ],
      ]
    )

    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    let secondProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-2")
    var db: OpaquePointer?
    let sqliteURL = ContainerPaths(root: containerRoot).sqliteURL
    XCTAssertEqual(sqlite3_open(sqliteURL.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    XCTAssertEqual(
      sqlite3_exec(
        db,
        "UPDATE app_tasks SET id = 'not-a-uuid' WHERE project_id = '\(secondProjectID.uuidString)';",
        nil,
        nil,
        nil
      ),
      SQLITE_OK
    )

    let firstProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [firstProjectID])

    XCTAssertEqual(snapshot.projects.map(\.identity.projectID), [firstProjectID])
    XCTAssertEqual(snapshot.tasks.map(\.title), ["Requested Task"])
  }

  func testProjectNoteReminderBecomesProjectNoteAndIsHiddenFromTasks() async throws {
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let createdAt = Date(timeIntervalSinceReferenceDate: 215)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Project",
          colorHex: nil
        )
      ],
      itemsByListIdentifier: [
        "list-1": [
          ReminderItemImportSnapshot(
            identifier: "note-task",
            externalIdentifier: "note-task",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "Project",
            title: "프로젝트 노트",
            notes: "핵심 사항",
            attachmentCount: 0,
            isCompleted: false,
            completionDate: nil,
            startDate: nil,
            dueDate: nil,
            scheduleHasExplicitTime: false,
            scheduledDurationMinutes: nil,
            priority: 9,
            recurrenceRuleRaw: nil,
            isFlagged: false,
            requiredWorkDays: 0,
            createdAt: createdAt,
            modifiedAt: createdAt
          ),
          ReminderItemImportSnapshot(
            identifier: "task-1",
            externalIdentifier: "task-1",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "Project",
            title: "Visible Task",
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
          ),
        ]
      ]
    )

    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(project.noteMarkdown, "핵심 사항")
    XCTAssertEqual(project.tasks.map(\.title), ["Visible Task"])
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

  func testReplaceReminderSnapshotKeepsLocalTaskDurationWhenImportHasDefaultDuration() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let createdAt = Date(timeIntervalSinceReferenceDate: 305)
    let dueDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
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
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )
    let itemWithDefaultDuration = ReminderItemImportSnapshot(
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
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 30,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt.addingTimeInterval(10)
    )

    try await store.replaceReminderSnapshot(
      Self.batch(items: [item], createdAt: createdAt),
      importedAt: createdAt
    )
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: taskID, durationMinutes: 90)
    ])
    try await store.replaceReminderSnapshot(
      Self.batch(items: [itemWithDefaultDuration], createdAt: createdAt.addingTimeInterval(10)),
      importedAt: createdAt.addingTimeInterval(10)
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let task = try XCTUnwrap(snapshot.tasks.first)

    XCTAssertEqual(task.schedule.durationMinutes, 90)
  }

  func testFillMissingTaskDurationsDoesNotOverwriteExistingDuration() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let createdAt = Date(timeIntervalSinceReferenceDate: 307)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let existingTaskID = ReminderProjectionIdentity.taskID(for: "existing-task")
    let missingTaskID = ReminderProjectionIdentity.taskID(for: "missing-task")

    try await store.replaceReminderSnapshot(
      Self.batch(taskExternalIdentifiers: ["existing-task", "missing-task"], createdAt: createdAt),
      importedAt: createdAt
    )
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: existingTaskID, durationMinutes: 90)
    ])
    try await store.fillMissingTaskDurations([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: existingTaskID, durationMinutes: 120),
      AppOwnedWorkspaceStore.TaskSupplement(taskID: missingTaskID, durationMinutes: 60),
    ])

    let existingTask = try await store.taskReference(projectID: projectID, taskID: existingTaskID)
    let missingTask = try await store.taskReference(projectID: projectID, taskID: missingTaskID)

    XCTAssertEqual(existingTask.durationMinutes, 90)
    XCTAssertEqual(missingTask.durationMinutes, 60)
  }

  func testReplaceReminderSnapshotKeepsTaskDurationWhenExternalIdentifierChanges() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let createdAt = Date(timeIntervalSinceReferenceDate: 310)
    let firstDueDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9))
    )
    let first = ReminderItemImportSnapshot(
      identifier: "task-identifier",
      externalIdentifier: "old-external",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Task",
      notes: "",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: firstDueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )
    let changed = ReminderItemImportSnapshot(
      identifier: "task-identifier",
      externalIdentifier: "new-external",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Task",
      notes: "",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: firstDueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt.addingTimeInterval(10)
    )
    let originalTaskID = ReminderProjectionIdentity.taskID(for: "old-external")

    try await store.replaceReminderSnapshot(
      Self.batch(items: [first], createdAt: createdAt),
      importedAt: createdAt
    )
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: originalTaskID, durationMinutes: 75)
    ])
    try await store.replaceReminderSnapshot(
      Self.batch(items: [changed], createdAt: createdAt.addingTimeInterval(10)),
      importedAt: createdAt.addingTimeInterval(10)
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let task = try XCTUnwrap(snapshot.tasks.first)

    XCTAssertEqual(task.identity.taskID, originalTaskID)
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "new-external")
    XCTAssertEqual(task.schedule.durationMinutes, 75)
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

  func testRetainedSnapshotHidesCompletedRecurringOccurrenceWhenActiveNoteChanged()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let activeDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 5)))
    let completedDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 11)))
    let createdAt = Date(timeIntervalSinceReferenceDate: 412)
    let active = ReminderItemImportSnapshot(
      identifier: "active-identifier",
      externalIdentifier: "task-1",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "Edited active note",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: activeDueDate,
      scheduleHasExplicitTime: false,
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
      externalIdentifier: "completed-task-1",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Recurring",
      notes: "",
      attachmentCount: 0,
      isCompleted: true,
      completionDate: completedDueDate,
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

    XCTAssertEqual(snapshot.tasks.map(\.identity.reminderExternalIdentifier), ["task-1"])
  }

  func testRetainedSnapshotKeepsLocalCompletedRecurringOccurrenceWithActiveOccurrence()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 11)))
    let nextDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 5)))
    let createdAt = Date(timeIntervalSinceReferenceDate: 415)
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
      dueDate: nextDueDate,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: "daily",
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
      itemsByListIdentifier: ["list-1": [active]]
    )
    try await store.replaceReminderSnapshot(batch, importedAt: createdAt)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let sourceTask = try await store.taskReference(projectID: projectID, taskID: taskID)
    try await store.upsertTask(
      projectID: projectID,
      taskID: taskID,
      reminderIdentifier: sourceTask.reminderIdentifier,
      reminderExternalIdentifier: sourceTask.reminderExternalIdentifier,
      title: sourceTask.title,
      noteText: sourceTask.noteText,
      isCompleted: sourceTask.isCompleted,
      completionDate: sourceTask.completionDate,
      dueDate: nextDueDate,
      hasExplicitTime: false,
      durationMinutes: nil,
      recurrenceRuleRaw: sourceTask.recurrenceRuleRaw,
      modifiedAt: createdAt,
      appendIfMissing: false
    )
    _ = try await store.upsertLocalCompletedRecurringOccurrence(
      projectID: projectID,
      sourceTask: AppOwnedWorkspaceStore.TaskReference(
        projectID: projectID,
        taskID: taskID,
        reminderIdentifier: sourceTask.reminderIdentifier,
        reminderExternalIdentifier: sourceTask.reminderExternalIdentifier,
        title: sourceTask.title,
        noteText: sourceTask.noteText,
        isCompleted: false,
        completionDate: nil,
        dueDate: dueDate,
        hasExplicitTime: true,
        durationMinutes: 30,
        recurrenceRuleRaw: sourceTask.recurrenceRuleRaw,
        priority: sourceTask.priority
      ),
      completionDate: dueDate,
      modifiedAt: createdAt
    )

    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let tasks = snapshot.tasks

    XCTAssertEqual(tasks.count, 2)
    XCTAssertEqual(tasks.filter(\.isCompleted).first?.schedule.parsedDate, dueDate)
    XCTAssertTrue(
      AppOwnedWorkspaceStore.isLocalCompletedRecurringExternalIdentifier(
        tasks.filter(\.isCompleted).first?.identity.reminderExternalIdentifier
      )
    )

    try await store.replaceReminderSnapshot(batch, importedAt: createdAt.addingTimeInterval(10))
    let reloadedSnapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])

    XCTAssertEqual(reloadedSnapshot.tasks.count, 2)
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
