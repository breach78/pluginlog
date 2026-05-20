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

  func testReplaceReminderSnapshotStoresImportedTimedDurationInCorrectColumns() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let dueDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
    let createdAt = Date(timeIntervalSinceReferenceDate: 200)
    let item = ReminderItemImportSnapshot(
      identifier: "task-1",
      externalIdentifier: "task-1",
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: "Task",
      notes: "note",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 125,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )

    try await store.replaceReminderSnapshot(
      Self.batch(items: [item], createdAt: createdAt),
      importedAt: createdAt
    )

    let task = try await store.taskReference(projectID: projectID, taskID: taskID)
    XCTAssertEqual(task.dueDate, dueDate)
    XCTAssertTrue(task.hasExplicitTime)
    XCTAssertEqual(task.durationMinutes, 125)
    XCTAssertEqual(task.priority, 0)
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
      importedAt: importedAt,
      coverage: .full
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

  func testReplaceReminderSnapshotRemovesRowsMissingFromFullReminderSnapshot()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let importedAt = Date(timeIntervalSinceReferenceDate: 203)
    let firstProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let secondProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-2")
    let firstTaskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let removedTaskID = ReminderProjectionIdentity.taskID(for: "task-2")

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
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
              identifier: "task-1-identifier",
              externalIdentifier: "task-1",
              parentExternalIdentifier: nil,
              sourceListIdentifier: "list-1",
              sourceListTitle: "First Project",
              title: "Kept Task",
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
              createdAt: importedAt,
              modifiedAt: importedAt
            ),
            ReminderItemImportSnapshot(
              identifier: "task-2-identifier",
              externalIdentifier: "task-2",
              parentExternalIdentifier: nil,
              sourceListIdentifier: "list-1",
              sourceListTitle: "First Project",
              title: "Removed Task",
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
              createdAt: importedAt,
              modifiedAt: importedAt
            ),
          ],
          "list-2": [],
        ]
      ),
      importedAt: importedAt
    )

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "First Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [
          "list-1": [
            ReminderItemImportSnapshot(
              identifier: "task-1-identifier",
              externalIdentifier: "task-1",
              parentExternalIdentifier: nil,
              sourceListIdentifier: "list-1",
              sourceListTitle: "First Project",
              title: "Kept Task",
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
              createdAt: importedAt,
              modifiedAt: importedAt.addingTimeInterval(10)
            )
          ]
        ]
      ),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map {
      ($0.identity.projectID, $0)
    })

    XCTAssertNotNil(projectsByID[firstProjectID])
    XCTAssertNil(projectsByID[secondProjectID])
    XCTAssertEqual(snapshot.tasks.map(\.identity.taskID), [firstTaskID])
    XCTAssertFalse(snapshot.tasks.contains { $0.identity.taskID == removedTaskID })

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "First Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: ["list-1": []]
      ),
      importedAt: importedAt.addingTimeInterval(20),
      coverage: .full
    )
    let emptyListSnapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    XCTAssertEqual(emptyListSnapshot.projects.map(\.identity.projectID), [firstProjectID])
    XCTAssertTrue(emptyListSnapshot.tasks.isEmpty)
  }

  func testEmptyFullReminderSnapshotDoesNotDeleteExistingAppOwnedStore() async throws {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let importedAt = Date(timeIntervalSinceReferenceDate: 203)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")

    try await store.replaceReminderSnapshot(
      Self.batch(taskExternalIdentifiers: ["task-1"], createdAt: importedAt),
      importedAt: importedAt,
      coverage: .full
    )

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(lists: [], itemsByListIdentifier: [:]),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )

    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let project = try XCTUnwrap(snapshot.projects.first)
    XCTAssertEqual(project.identity.projectID, projectID)
    XCTAssertEqual(project.tasks.map(\.identity.taskID), [taskID])
  }

  func testNonDestructiveReminderImportPreservesExistingRowsAndAppOwnedMetadata()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let importedAt = Date(timeIntervalSinceReferenceDate: 204)
    let firstProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let secondProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-2")
    let firstTaskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let secondTaskID = ReminderProjectionIdentity.taskID(for: "task-2")
    let initialBatch = ReminderImportSnapshotBatch(
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
            identifier: "task-1-identifier",
            externalIdentifier: "task-1",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "First Project",
            title: "Task 1",
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
            createdAt: importedAt,
            modifiedAt: importedAt
          )
        ],
        "list-2": [
          ReminderItemImportSnapshot(
            identifier: "task-2-identifier",
            externalIdentifier: "task-2",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-2",
            sourceListTitle: "Second Project",
            title: "Task 2",
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
            createdAt: importedAt,
            modifiedAt: importedAt
          )
        ],
      ]
    )

    try await store.replaceReminderSnapshot(initialBatch, importedAt: importedAt, coverage: .full)
    try await store.updateProjectStage(
      projectID: secondProjectID,
      stage: .area,
      modifiedAt: importedAt.addingTimeInterval(1)
    )
    try await store.updateProjectBoardOrders([
      firstProjectID: 1,
      secondProjectID: 0,
    ])
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: firstTaskID, durationMinutes: 90),
      AppOwnedWorkspaceStore.TaskSupplement(taskID: secondTaskID, durationMinutes: 120),
    ])
    try await store.reorderOpenTasks(projectID: firstProjectID, orderedTaskIDs: [firstTaskID])
    try await store.reorderOpenTasks(projectID: secondProjectID, orderedTaskIDs: [secondTaskID])

    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(lists: [], itemsByListIdentifier: [:]),
      importedAt: importedAt.addingTimeInterval(10)
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map {
      ($0.identity.projectID, $0)
    })

    XCTAssertEqual(Set(projectsByID.keys), [firstProjectID, secondProjectID])
    XCTAssertEqual(projectsByID[firstProjectID]?.boardOrder, 1)
    XCTAssertEqual(projectsByID[secondProjectID]?.boardOrder, 0)
    XCTAssertEqual(projectsByID[secondProjectID]?.progressStage, .area)
    XCTAssertEqual(
      projectsByID[firstProjectID]?.tasks.first { $0.identity.taskID == firstTaskID }?.schedule.durationMinutes,
      90
    )
    XCTAssertEqual(
      projectsByID[secondProjectID]?.tasks.first { $0.identity.taskID == secondTaskID }?.schedule.durationMinutes,
      120
    )
  }

  func testListedProjectReminderImportDeletesOnlyListedProjectMissingTasks()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let importedAt = Date(timeIntervalSinceReferenceDate: 205)
    let firstProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let secondProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-2")
    let firstTaskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let removedTaskID = ReminderProjectionIdentity.taskID(for: "task-removed")
    let secondTaskID = ReminderProjectionIdentity.taskID(for: "task-2")
    let initialBatch = ReminderImportSnapshotBatch(
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
            identifier: "task-1-identifier",
            externalIdentifier: "task-1",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "First Project",
            title: "Task 1",
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
            createdAt: importedAt,
            modifiedAt: importedAt
          ),
          ReminderItemImportSnapshot(
            identifier: "task-removed-identifier",
            externalIdentifier: "task-removed",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-1",
            sourceListTitle: "First Project",
            title: "Removed Task",
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
            createdAt: importedAt,
            modifiedAt: importedAt
          ),
        ],
        "list-2": [
          ReminderItemImportSnapshot(
            identifier: "task-2-identifier",
            externalIdentifier: "task-2",
            parentExternalIdentifier: nil,
            sourceListIdentifier: "list-2",
            sourceListTitle: "Second Project",
            title: "Task 2",
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
            createdAt: importedAt,
            modifiedAt: importedAt
          )
        ],
      ]
    )

    try await store.replaceReminderSnapshot(initialBatch, importedAt: importedAt, coverage: .full)
    try await store.updateProjectStage(
      projectID: secondProjectID,
      stage: .later,
      modifiedAt: importedAt.addingTimeInterval(1)
    )
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: secondTaskID, durationMinutes: 75)
    ])
    try await store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "First Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: [
          "list-1": [
            ReminderItemImportSnapshot(
              identifier: "task-1-identifier",
              externalIdentifier: "task-1",
              parentExternalIdentifier: nil,
              sourceListIdentifier: "list-1",
              sourceListTitle: "First Project",
              title: "Task 1",
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
              createdAt: importedAt,
              modifiedAt: importedAt.addingTimeInterval(10)
            )
          ]
        ]
      ),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .listedProjectsOnly
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map {
      ($0.identity.projectID, $0)
    })

    XCTAssertNotNil(projectsByID[firstProjectID])
    XCTAssertNotNil(projectsByID[secondProjectID])
    XCTAssertTrue(projectsByID[firstProjectID]?.tasks.contains { $0.identity.taskID == firstTaskID } ?? false)
    XCTAssertFalse(projectsByID[firstProjectID]?.tasks.contains { $0.identity.taskID == removedTaskID } ?? true)
    XCTAssertEqual(projectsByID[secondProjectID]?.progressStage, .later)
    XCTAssertEqual(projectsByID[secondProjectID]?.tasks.first?.identity.taskID, secondTaskID)
    XCTAssertEqual(projectsByID[secondProjectID]?.tasks.first?.schedule.durationMinutes, 75)
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

  func testReplaceReminderSnapshotRestoresProjectStageFromPersistentSupplementStore() async throws {
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let importedAt = Date(timeIntervalSinceReferenceDate: 270)
    let batch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Project",
          colorHex: "#111111"
        )
      ],
      itemsByListIdentifier: [:]
    )
    try await store.replaceReminderSnapshot(batch, importedAt: importedAt)
    try await store.updateProjectStage(
      projectID: projectID,
      stage: .area,
      modifiedAt: importedAt.addingTimeInterval(1)
    )
    try clearStoredProjectStages(containerRoot: containerRoot)

    try await store.replaceReminderSnapshot(
      batch,
      importedAt: importedAt.addingTimeInterval(2)
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(project.progressStage, .area)
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

  func testReplaceReminderSnapshotRestoresDurationFromPersistentSupplementStore() async throws {
    let containerRoot = try makeTemporaryDirectory()
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let createdAt = Date(timeIntervalSinceReferenceDate: 304)
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

    try await store.replaceReminderSnapshot(
      Self.batch(items: [item], createdAt: createdAt),
      importedAt: createdAt
    )
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: taskID, durationMinutes: 90)
    ])
    try clearStoredTaskDurations(containerRoot: containerRoot)

    try await store.replaceReminderSnapshot(
      Self.batch(items: [item], createdAt: createdAt.addingTimeInterval(10)),
      importedAt: createdAt.addingTimeInterval(10)
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let task = try XCTUnwrap(snapshot.tasks.first)

    XCTAssertEqual(task.schedule.durationMinutes, 90)
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

  func testAppOwnedStorageInvariantsSurviveStoreRecreationAndReminderImport()
    async throws
  {
    let containerRoot = try makeTemporaryDirectory()
    let importedAt = Date(timeIntervalSinceReferenceDate: 620)
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let firstTaskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let secondTaskID = ReminderProjectionIdentity.taskID(for: "task-2")
    let batch = Self.batch(taskExternalIdentifiers: ["task-1", "task-2"], createdAt: importedAt)
    var store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)

    try await store.replaceReminderSnapshot(batch, importedAt: importedAt, coverage: .full)
    try await store.updateProjectStage(
      projectID: projectID,
      stage: .area,
      modifiedAt: importedAt.addingTimeInterval(1)
    )
    try await store.updateProjectBoardOrders([projectID: 7])
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: firstTaskID, durationMinutes: 95)
    ])
    try await store.reorderOpenTasks(projectID: projectID, orderedTaskIDs: [secondTaskID, firstTaskID])

    store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    try await store.replaceReminderSnapshot(
      batch,
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(project.progressStage, .area)
    XCTAssertEqual(project.boardOrder, 7)
    XCTAssertEqual(project.tasks.map(\.identity.taskID), [secondTaskID, firstTaskID])
    XCTAssertEqual(
      project.tasks.first { $0.identity.taskID == firstTaskID }?.schedule.durationMinutes,
      95
    )
  }

  func testUserFlowProjectStageOrderAndTaskOrderSurviveRelaunch() async throws {
    let containerRoot = try makeTemporaryDirectory()
    let importedAt = Date(timeIntervalSinceReferenceDate: 621)
    let firstProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let secondProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-2")
    let firstTaskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let secondTaskID = ReminderProjectionIdentity.taskID(for: "task-2")
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
      itemsByListIdentifier: [
        "list-1": [
          Self.reminderItem(
            identifier: "task-1",
            title: "First task",
            createdAt: importedAt
          ),
          Self.reminderItem(
            identifier: "task-2",
            title: "Second task",
            createdAt: importedAt
          ),
        ]
      ]
    )
    var store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)

    try await store.replaceReminderSnapshot(batch, importedAt: importedAt, coverage: .full)
    try await store.updateProjectStage(
      projectID: firstProjectID,
      stage: .area,
      modifiedAt: importedAt.addingTimeInterval(1)
    )
    try await store.updateProjectBoardOrders([
      firstProjectID: 2,
      secondProjectID: 1,
    ])
    try await store.reorderOpenTasks(
      projectID: firstProjectID,
      orderedTaskIDs: [secondTaskID, firstTaskID]
    )

    store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map {
      ($0.identity.projectID, $0)
    })

    XCTAssertEqual(projectsByID[firstProjectID]?.progressStage, .area)
    XCTAssertEqual(projectsByID[firstProjectID]?.boardOrder, 2)
    XCTAssertEqual(projectsByID[secondProjectID]?.boardOrder, 1)
    XCTAssertEqual(projectsByID[firstProjectID]?.tasks.map(\.identity.taskID), [
      secondTaskID,
      firstTaskID,
    ])
  }

  func testLocalCompletedRecurringOccurrenceSurvivesStoreRecreationAndReminderImport()
    async throws
  {
    let containerRoot = try makeTemporaryDirectory()
    let importedAt = Date(timeIntervalSinceReferenceDate: 630)
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 9)))
    let completedAt = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 16, minute: 45))
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "recurring-task")
    let active = Self.reminderItem(
      identifier: "recurring-task",
      title: "Recurring",
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      recurrenceRuleRaw: "daily",
      createdAt: importedAt
    )
    let batch = Self.batch(items: [active], createdAt: importedAt)
    var store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)

    try await store.replaceReminderSnapshot(batch, importedAt: importedAt, coverage: .full)
    let sourceTask = try await store.taskReference(projectID: projectID, taskID: taskID)
    _ = try await store.upsertLocalCompletedRecurringOccurrence(
      projectID: projectID,
      sourceTask: sourceTask,
      completionDate: completedAt,
      modifiedAt: importedAt.addingTimeInterval(1)
    )
    try overwriteLocalCompletedRecurringDueDate(
      containerRoot: containerRoot,
      dueDate: completedAt,
      hasExplicitTime: true
    )
    let initialSnapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let initialCompletedOccurrence = try XCTUnwrap(initialSnapshot.tasks.first { $0.isCompleted })
    let initialCompletedTaskID = initialCompletedOccurrence.identity.taskID
    let initialCompletedExternalIdentifier =
      initialCompletedOccurrence.identity.reminderExternalIdentifier
    XCTAssertEqual(initialCompletedOccurrence.schedule.parsedDate, dueDate)

    store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)
    try await store.replaceReminderSnapshot(
      batch,
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let completedOccurrence = try XCTUnwrap(snapshot.tasks.first { $0.isCompleted })

    XCTAssertEqual(snapshot.tasks.count, 2)
    XCTAssertEqual(completedOccurrence.identity.taskID, initialCompletedTaskID)
    XCTAssertEqual(
      completedOccurrence.identity.reminderExternalIdentifier,
      initialCompletedExternalIdentifier
    )
    XCTAssertEqual(completedOccurrence.schedule.parsedDate, dueDate)
    XCTAssertTrue(completedOccurrence.schedule.hasExplicitTime)
    XCTAssertTrue(
      AppOwnedWorkspaceStore.isLocalCompletedRecurringExternalIdentifier(
        completedOccurrence.identity.reminderExternalIdentifier
      )
    )
  }

  func testRecurringExternalIdentifierChangePreservesDurationAndLocalCompletedOccurrence()
    async throws
  {
    let containerRoot = try makeTemporaryDirectory()
    let importedAt = Date(timeIntervalSinceReferenceDate: 640)
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 9)))
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "recurring-old")
    let initial = Self.reminderItem(
      identifier: "recurring-old",
      title: "Recurring",
      notes: "same note",
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      recurrenceRuleRaw: "daily",
      createdAt: importedAt
    )
    let changed = Self.reminderItem(
      identifier: "recurring-new",
      title: "Recurring",
      notes: "same note",
      dueDate: dueDate.addingTimeInterval(86_400),
      scheduleHasExplicitTime: true,
      recurrenceRuleRaw: "daily",
      createdAt: importedAt.addingTimeInterval(10)
    )
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)

    try await store.replaceReminderSnapshot(
      Self.batch(items: [initial], createdAt: importedAt),
      importedAt: importedAt,
      coverage: .full
    )
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: taskID, durationMinutes: 80)
    ])
    let sourceTask = try await store.taskReference(projectID: projectID, taskID: taskID)
    _ = try await store.upsertLocalCompletedRecurringOccurrence(
      projectID: projectID,
      sourceTask: sourceTask,
      completionDate: dueDate,
      modifiedAt: importedAt.addingTimeInterval(1)
    )

    try await store.replaceReminderSnapshot(
      Self.batch(items: [changed], createdAt: importedAt.addingTimeInterval(10)),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    let activeTask = try XCTUnwrap(snapshot.tasks.first { !$0.isCompleted })

    XCTAssertEqual(activeTask.identity.taskID, taskID)
    XCTAssertEqual(activeTask.identity.reminderExternalIdentifier, "recurring-new")
    XCTAssertEqual(activeTask.schedule.durationMinutes, 80)
    XCTAssertTrue(
      snapshot.tasks.contains {
        $0.isCompleted
          && AppOwnedWorkspaceStore.isLocalCompletedRecurringExternalIdentifier(
            $0.identity.reminderExternalIdentifier
          )
      }
    )
  }

  func testRecurringExternalIdentifierChangeRekeysLocalCompletedOccurrence()
    async throws
  {
    let containerRoot = try makeTemporaryDirectory()
    let importedAt = Date(timeIntervalSinceReferenceDate: 645)
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 9)))
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let activeTaskID = ReminderProjectionIdentity.taskID(for: "recurring-old")
    let initial = Self.reminderItem(
      identifier: "recurring-old",
      title: "Recurring",
      notes: "same note",
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      recurrenceRuleRaw: "daily",
      createdAt: importedAt
    )
    let changed = Self.reminderItem(
      identifier: "recurring-new",
      title: "Recurring",
      notes: "same note",
      dueDate: dueDate.addingTimeInterval(86_400),
      scheduleHasExplicitTime: true,
      recurrenceRuleRaw: "daily",
      createdAt: importedAt.addingTimeInterval(10)
    )
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)

    try await store.replaceReminderSnapshot(
      Self.batch(items: [initial], createdAt: importedAt),
      importedAt: importedAt,
      coverage: .full
    )
    let sourceTask = try await store.taskReference(projectID: projectID, taskID: activeTaskID)
    _ = try await store.upsertLocalCompletedRecurringOccurrence(
      projectID: projectID,
      sourceTask: sourceTask,
      completionDate: dueDate,
      modifiedAt: importedAt.addingTimeInterval(1)
    )

    try await store.replaceReminderSnapshot(
      Self.batch(items: [changed], createdAt: importedAt.addingTimeInterval(10)),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let completedRows = try localCompletedRecurringRows(containerRoot: containerRoot)

    XCTAssertEqual(completedRows.count, 1)
    let completedRow = try XCTUnwrap(completedRows.first)
    XCTAssertTrue(completedRow.externalIdentifier.hasPrefix("recurring-new::app-completed::"))
    XCTAssertEqual(completedRow.taskID, ReminderProjectionIdentity.taskID(for: completedRow.externalIdentifier))
    XCTAssertEqual(completedRow.recurrenceRuleRaw, "daily")
  }

  func testLegacyLocalCompletedOccurrenceBackfillsSignatureBeforeExternalIdentifierChange()
    async throws
  {
    let containerRoot = try makeTemporaryDirectory()
    let importedAt = Date(timeIntervalSinceReferenceDate: 646)
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 9)))
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let activeTaskID = ReminderProjectionIdentity.taskID(for: "recurring-old")
    let initial = Self.reminderItem(
      identifier: "recurring-old",
      title: "Recurring",
      notes: "same note",
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      recurrenceRuleRaw: "daily",
      createdAt: importedAt
    )
    let changed = Self.reminderItem(
      identifier: "recurring-new",
      title: "Recurring",
      notes: "same note",
      dueDate: dueDate.addingTimeInterval(86_400),
      scheduleHasExplicitTime: true,
      recurrenceRuleRaw: "daily",
      createdAt: importedAt.addingTimeInterval(20)
    )
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)

    try await store.replaceReminderSnapshot(
      Self.batch(items: [initial], createdAt: importedAt),
      importedAt: importedAt,
      coverage: .full
    )
    let sourceTask = try await store.taskReference(projectID: projectID, taskID: activeTaskID)
    _ = try await store.upsertLocalCompletedRecurringOccurrence(
      projectID: projectID,
      sourceTask: sourceTask,
      completionDate: dueDate,
      modifiedAt: importedAt.addingTimeInterval(1)
    )
    try clearLocalCompletedRecurringSignatureRules(containerRoot: containerRoot)

    try await store.replaceReminderSnapshot(
      Self.batch(items: [initial], createdAt: importedAt.addingTimeInterval(10)),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    try await store.replaceReminderSnapshot(
      Self.batch(items: [changed], createdAt: importedAt.addingTimeInterval(20)),
      importedAt: importedAt.addingTimeInterval(20),
      coverage: .full
    )
    let completedRows = try localCompletedRecurringRows(containerRoot: containerRoot)

    XCTAssertEqual(completedRows.count, 1)
    let completedRow = try XCTUnwrap(completedRows.first)
    XCTAssertTrue(completedRow.externalIdentifier.hasPrefix("recurring-new::app-completed::"))
    XCTAssertEqual(completedRow.recurrenceRuleRaw, "daily")
  }

  func testRecurringIdentityResolverUsesAnchorPhaseWhenExternalIdentifiersChange()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let importedAt = Date(timeIntervalSinceReferenceDate: 647)
    let firstDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9)))
    let secondDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 9)))
    let firstTaskID = ReminderProjectionIdentity.taskID(for: "first-old")
    let secondTaskID = ReminderProjectionIdentity.taskID(for: "second-old")
    let initial = [
      Self.reminderItem(
        identifier: "first-old",
        title: "Recurring",
        notes: "same note",
        dueDate: firstDate,
        scheduleHasExplicitTime: true,
        recurrenceRuleRaw: "daily|3",
        createdAt: importedAt
      ),
      Self.reminderItem(
        identifier: "second-old",
        title: "Recurring",
        notes: "same note",
        dueDate: secondDate,
        scheduleHasExplicitTime: true,
        recurrenceRuleRaw: "daily|3",
        createdAt: importedAt
      ),
    ]
    let changed = [
      Self.reminderItem(
        identifier: "first-new",
        title: "Recurring",
        notes: "same note",
        dueDate: firstDate.addingTimeInterval(3 * 86_400),
        scheduleHasExplicitTime: true,
        recurrenceRuleRaw: "daily|3",
        createdAt: importedAt.addingTimeInterval(10)
      ),
      Self.reminderItem(
        identifier: "second-new",
        title: "Recurring",
        notes: "same note",
        dueDate: secondDate.addingTimeInterval(3 * 86_400),
        scheduleHasExplicitTime: true,
        recurrenceRuleRaw: "daily|3",
        createdAt: importedAt.addingTimeInterval(10)
      ),
    ]

    try await store.replaceReminderSnapshot(Self.batch(items: initial, createdAt: importedAt), importedAt: importedAt, coverage: .full)
    try await store.replaceReminderSnapshot(
      Self.batch(items: changed, createdAt: importedAt.addingTimeInterval(10)),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let tasksByExternalIdentifier = Dictionary(uniqueKeysWithValues: snapshot.tasks.compactMap { task in
      task.identity.reminderExternalIdentifier.map { ($0, task) }
    })

    XCTAssertEqual(tasksByExternalIdentifier["first-new"]?.identity.taskID, firstTaskID)
    XCTAssertEqual(tasksByExternalIdentifier["second-new"]?.identity.taskID, secondTaskID)
  }

  func testCompletedRecurringRestoreDoesNotRekeyToDifferentAnchorPhase()
    async throws
  {
    let containerRoot = try makeTemporaryDirectory()
    let importedAt = Date(timeIntervalSinceReferenceDate: 648)
    let firstDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9)))
    let secondDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 9)))
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let firstTaskID = ReminderProjectionIdentity.taskID(for: "first-old")
    let initial = [
      Self.reminderItem(
        identifier: "first-old",
        title: "Recurring",
        notes: "same note",
        dueDate: firstDate,
        scheduleHasExplicitTime: true,
        recurrenceRuleRaw: "daily|3",
        createdAt: importedAt
      ),
      Self.reminderItem(
        identifier: "second-old",
        title: "Recurring",
        notes: "same note",
        dueDate: secondDate,
        scheduleHasExplicitTime: true,
        recurrenceRuleRaw: "daily|3",
        createdAt: importedAt
      ),
    ]
    let remainingDifferentPhase = Self.reminderItem(
      identifier: "second-new",
      title: "Recurring",
      notes: "same note",
      dueDate: secondDate.addingTimeInterval(3 * 86_400),
      scheduleHasExplicitTime: true,
      recurrenceRuleRaw: "daily|3",
      createdAt: importedAt.addingTimeInterval(10)
    )
    let store = AppOwnedWorkspaceStore(containerRootURL: containerRoot)

    try await store.replaceReminderSnapshot(Self.batch(items: initial, createdAt: importedAt), importedAt: importedAt, coverage: .full)
    let sourceTask = try await store.taskReference(projectID: projectID, taskID: firstTaskID)
    _ = try await store.upsertLocalCompletedRecurringOccurrence(
      projectID: projectID,
      sourceTask: sourceTask,
      completionDate: firstDate,
      modifiedAt: importedAt.addingTimeInterval(1)
    )

    try await store.replaceReminderSnapshot(
      Self.batch(items: [remainingDifferentPhase], createdAt: importedAt.addingTimeInterval(10)),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let completedRows = try localCompletedRecurringRows(containerRoot: containerRoot)

    XCTAssertEqual(completedRows.count, 1)
    let completedRow = try XCTUnwrap(completedRows.first)
    XCTAssertTrue(completedRow.externalIdentifier.hasPrefix("first-old::app-completed::"))
    XCTAssertFalse(completedRow.externalIdentifier.hasPrefix("second-new::app-completed::"))
  }

  func testRecurringIdentityResolverDoesNotMergeDuplicateTitleRecurringTasks()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let importedAt = Date(timeIntervalSinceReferenceDate: 650)
    let initial = [
      Self.reminderItem(identifier: "first-old", title: "Recurring", recurrenceRuleRaw: "daily", createdAt: importedAt),
      Self.reminderItem(identifier: "second-old", title: "Recurring", recurrenceRuleRaw: "daily", createdAt: importedAt),
    ]
    let changed = [
      Self.reminderItem(identifier: "first-new", title: "Recurring", recurrenceRuleRaw: "daily", createdAt: importedAt.addingTimeInterval(10)),
      Self.reminderItem(identifier: "second-new", title: "Recurring", recurrenceRuleRaw: "daily", createdAt: importedAt.addingTimeInterval(10)),
    ]

    try await store.replaceReminderSnapshot(Self.batch(items: initial, createdAt: importedAt), importedAt: importedAt, coverage: .full)
    try await store.replaceReminderSnapshot(
      Self.batch(items: changed, createdAt: importedAt.addingTimeInterval(10)),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    XCTAssertEqual(snapshot.tasks.count, 2)
    XCTAssertEqual(
      Set(snapshot.tasks.compactMap(\.identity.reminderExternalIdentifier)),
      ["first-new", "second-new"]
    )
  }

  func testRecurringSignatureFallbackRequiresMatchingRecurrenceRule()
    async throws
  {
    let store = AppOwnedWorkspaceStore(containerRootURL: try makeTemporaryDirectory())
    let importedAt = Date(timeIntervalSinceReferenceDate: 660)
    let initial = Self.reminderItem(
      identifier: "recurring-old",
      title: "Recurring",
      recurrenceRuleRaw: "daily",
      createdAt: importedAt
    )
    let changedRule = Self.reminderItem(
      identifier: "recurring-new",
      title: "Recurring",
      recurrenceRuleRaw: "weekly",
      createdAt: importedAt.addingTimeInterval(10)
    )

    try await store.replaceReminderSnapshot(Self.batch(items: [initial], createdAt: importedAt), importedAt: importedAt, coverage: .full)
    try await store.replaceReminderSnapshot(
      Self.batch(items: [changedRule], createdAt: importedAt.addingTimeInterval(10)),
      importedAt: importedAt.addingTimeInterval(10),
      coverage: .full
    )
    let snapshot = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [])

    XCTAssertEqual(snapshot.tasks.first?.identity.taskID, ReminderProjectionIdentity.taskID(for: "recurring-new"))
    XCTAssertEqual(snapshot.tasks.first?.identity.reminderExternalIdentifier, "recurring-new")
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private static func reminderItem(
    identifier: String,
    externalIdentifier: String? = nil,
    title: String? = nil,
    notes: String = "",
    isCompleted: Bool = false,
    completionDate: Date? = nil,
    dueDate: Date? = nil,
    scheduleHasExplicitTime: Bool = false,
    scheduledDurationMinutes: Int? = nil,
    recurrenceRuleRaw: String? = nil,
    createdAt: Date
  ) -> ReminderItemImportSnapshot {
    ReminderItemImportSnapshot(
      identifier: "\(identifier)-identifier",
      externalIdentifier: externalIdentifier ?? identifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: title ?? identifier,
      notes: notes,
      attachmentCount: 0,
      isCompleted: isCompleted,
      completionDate: completionDate,
      startDate: nil,
      dueDate: dueDate,
      scheduleHasExplicitTime: scheduleHasExplicitTime,
      scheduledDurationMinutes: scheduledDurationMinutes,
      priority: 0,
      recurrenceRuleRaw: recurrenceRuleRaw,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: createdAt,
      modifiedAt: createdAt
    )
  }

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

  private func clearStoredTaskDurations(containerRoot: URL) throws {
    let sqliteURL = ContainerPaths(root: containerRoot).sqliteURL
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(sqliteURL.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    XCTAssertEqual(
      sqlite3_exec(db, "UPDATE app_tasks SET scheduled_duration_minutes = NULL;", nil, nil, nil),
      SQLITE_OK
    )
  }

  private func clearStoredProjectStages(containerRoot: URL) throws {
    let sqliteURL = ContainerPaths(root: containerRoot).sqliteURL
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(sqliteURL.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    XCTAssertEqual(
      sqlite3_exec(db, "UPDATE app_projects SET progress_stage = 'do';", nil, nil, nil),
      SQLITE_OK
    )
  }

  private func localCompletedRecurringRows(containerRoot: URL) throws -> [
    (taskID: UUID, externalIdentifier: String, recurrenceRuleRaw: String?)
  ] {
    let sqliteURL = ContainerPaths(root: containerRoot).sqliteURL
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(sqliteURL.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    XCTAssertEqual(
      sqlite3_prepare_v2(
        db,
        """
        SELECT id, reminder_external_identifier, completed_recurring_signature_rule_raw
        FROM app_tasks
        WHERE is_completed = 1
          AND reminder_external_identifier LIKE '%::app-completed::%'
        ORDER BY reminder_external_identifier;
        """,
        -1,
        &statement,
        nil
      ),
      SQLITE_OK
    )
    defer { sqlite3_finalize(statement) }
    var rows: [(taskID: UUID, externalIdentifier: String, recurrenceRuleRaw: String?)] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let taskIDText = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
        let taskID = UUID(uuidString: taskIDText),
        let externalIdentifier = sqlite3_column_text(statement, 1).map({ String(cString: $0) })
      else {
        XCTFail("invalid local completed recurring row")
        continue
      }
      let recurrenceRuleRaw = sqlite3_column_text(statement, 2).map { String(cString: $0) }
      rows.append((taskID: taskID, externalIdentifier: externalIdentifier, recurrenceRuleRaw: recurrenceRuleRaw))
    }
    return rows
  }

  private func clearLocalCompletedRecurringSignatureRules(containerRoot: URL) throws {
    let sqliteURL = ContainerPaths(root: containerRoot).sqliteURL
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(sqliteURL.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    XCTAssertEqual(
      sqlite3_exec(
        db,
        """
        UPDATE app_tasks
        SET completed_recurring_signature_rule_raw = NULL
        WHERE is_completed = 1
          AND reminder_external_identifier LIKE '%::app-completed::%';
        """,
        nil,
        nil,
        nil
      ),
      SQLITE_OK
    )
  }

  private func overwriteLocalCompletedRecurringDueDate(
    containerRoot: URL,
    dueDate: Date,
    hasExplicitTime: Bool
  ) throws {
    let sqliteURL = ContainerPaths(root: containerRoot).sqliteURL
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(sqliteURL.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    let sql = """
      UPDATE app_tasks
      SET due_date = \(dueDate.timeIntervalSinceReferenceDate),
          schedule_has_explicit_time = \(hasExplicitTime ? 1 : 0)
      WHERE is_completed = 1
        AND reminder_external_identifier LIKE '%::app-completed::%';
      """
    XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
  }
}
