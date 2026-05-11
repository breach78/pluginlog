import XCTest
@testable import BrainUnfog

final class AppOwnedRetainedTaskCommandServiceTests: XCTestCase {
  @MainActor
  func testObsidianCommandCreateRoutesToAppOwnedStoreWhenEnabled() async throws {
    let fixture = try await makeEnabledStoreFixture()
    let provider = FakeAppOwnedReminderProjectProvider()
    provider.createdTaskMetadata = ReminderTaskRemoteMetadata(
      identifier: "created-identifier",
      externalIdentifier: "created-external",
      modifiedAt: Date(timeIntervalSinceReferenceDate: 500)
    )

    let result = try await RetainedTaskCommandFacade.createTask(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      title: "Created",
      day: nil,
      timeMinutes: nil,
      durationMinutes: nil,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let task = try XCTUnwrap(snapshot.projects.first?.tasks.first)

    XCTAssertEqual(provider.createdProjectIdentifier, "list-1")
    XCTAssertEqual(result.taskID, ReminderProjectionIdentity.taskID(for: "created-external"))
    XCTAssertEqual(task.title, "Created")
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "created-external")
  }

  @MainActor
  func testObsidianCommandUpdateRoutesToAppOwnedStoreWhenEnabled() async throws {
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      taskTitle: "Original"
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    provider.updateMetadata = ReminderTaskRemoteMetadata(
      identifier: "task-identifier",
      externalIdentifier: "task-1",
      modifiedAt: Date(timeIntervalSinceReferenceDate: 600)
    )
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")

    _ = try await RetainedTaskCommandFacade.updateTaskEditFields(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      fields: RetainedTaskEditFields(
        title: "Renamed",
        noteText: "new note",
        day: nil,
        timeMinutes: nil,
        durationMinutes: nil
      ),
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )
    let fields = try await RetainedTaskCommandFacade.taskEditFields(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      calendar: Self.calendar
    )

    XCTAssertEqual(provider.renamedTitle, "Renamed")
    XCTAssertEqual(provider.updatedNoteText, "new note")
    XCTAssertEqual(fields.title, "Renamed")
    XCTAssertEqual(fields.noteText, "new note")
  }

  @MainActor
  func testAppOwnedTaskEditDurationOnlyEditStaysLocalAndLoadsBack() async throws {
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      dueDate: start,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 30
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let day = Self.calendar.startOfDay(for: start)

    _ = try await RetainedTaskCommandFacade.updateTaskEditFields(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      fields: RetainedTaskEditFields(
        title: "Task",
        noteText: "",
        day: day,
        timeMinutes: 9 * 60 + 30,
        durationMinutes: 90
      ),
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )

    let fields = try await RetainedTaskCommandFacade.taskEditFields(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      calendar: Self.calendar
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let task = try XCTUnwrap(snapshot.projects.first?.tasks.first)

    XCTAssertNil(provider.scheduleUpdate)
    XCTAssertEqual(fields.durationMinutes, 90)
    XCTAssertEqual(task.schedule.durationMinutes, 90)
  }

  @MainActor
  func testUserFlowDurationEditSurvivesRelaunchAndReminderRefresh() async throws {
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      dueDate: start,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 30
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let day = Self.calendar.startOfDay(for: start)

    _ = try await RetainedTaskCommandFacade.updateTaskEditFields(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      fields: RetainedTaskEditFields(
        title: "Task",
        noteText: "",
        day: day,
        timeMinutes: 9 * 60 + 30,
        durationMinutes: 105
      ),
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )

    let reloadedStore = AppOwnedWorkspaceStore(
      containerRootURL: ObsidianVaultLayout(vaultRootURL: fixture.vaultRoot).sidecarRootURL
    )
    var snapshot = try await reloadedStore.loadRetainedWorkspaceSnapshot(
      projectIDs: [fixture.projectID]
    )
    XCTAssertEqual(snapshot.projects.first?.tasks.first?.schedule.durationMinutes, 105)

    try await reloadedStore.replaceReminderSnapshot(
      reminderImportBatch(
        item: reminderImportItem(
          identifier: "task-identifier",
          externalIdentifier: "task-1",
          title: "Task",
          dueDate: start,
          scheduleHasExplicitTime: true,
          scheduledDurationMinutes: nil,
          modifiedAt: Date(timeIntervalSinceReferenceDate: 402)
        )
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 402)
    )
    snapshot = try await reloadedStore.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])

    XCTAssertNil(provider.scheduleUpdate)
    XCTAssertEqual(snapshot.projects.first?.tasks.first?.schedule.parsedDate, start)
    XCTAssertEqual(snapshot.projects.first?.tasks.first?.schedule.durationMinutes, 105)
  }

  @MainActor
  func testObsidianProjectTitleRoutesToAppOwnedStoreWhenEnabled() async throws {
    let fixture = try await makeEnabledStoreFixture()
    let provider = FakeAppOwnedReminderProjectProvider()

    let result = try await RetainedProjectCommandFacade.setProjectTitle(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      title: "Renamed Project",
      reminderProjectProvider: provider
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(provider.projectTitleUpdate?.0, "list-1")
    XCTAssertEqual(provider.projectTitleUpdate?.1, "Renamed Project")
    XCTAssertEqual(result.reminderListExternalIdentifier, "list-1")
    XCTAssertEqual(project.title, "Renamed Project")
    assertRawProjectsDoesNotExist(in: fixture.vaultRoot)
  }

  @MainActor
  func testAppOwnedProjectTitleReturnsNeutralSnapshotWithoutRawProjects() async throws {
    let fixture = try await makeEnabledStoreFixture()
    let provider = FakeAppOwnedReminderProjectProvider()

    let result = try await AppOwnedRetainedProjectCommandService.setProjectTitle(
      store: fixture.store,
      projectID: fixture.projectID,
      title: "Renamed Project",
      reminderProjectProvider: provider
    )

    XCTAssertEqual(result.projectID, fixture.projectID)
    XCTAssertEqual(result.reminderListExternalIdentifier, "list-1")
    XCTAssertEqual(result.title, "Renamed Project")
    assertRawProjectsDoesNotExist(in: fixture.vaultRoot)
  }

  @MainActor
  func testObsidianProjectColorAndStageRouteToAppOwnedStoreWhenEnabled() async throws {
    let fixture = try await makeEnabledStoreFixture()
    let provider = FakeAppOwnedReminderProjectProvider()

    _ = try await RetainedProjectCommandFacade.setProjectColor(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      colorHex: "#112233",
      reminderProjectProvider: provider
    )
    _ = try await RetainedProjectCommandFacade.setProjectStage(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      stage: .later
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(provider.projectColorUpdate?.0, "list-1")
    XCTAssertEqual(provider.projectColorUpdate?.1, "#112233")
    XCTAssertEqual(project.colorHex, "#112233")
    XCTAssertEqual(project.progressStage, .later)
    assertRawProjectsDoesNotExist(in: fixture.vaultRoot)
  }

  @MainActor
  func testProjectNoteCreatesLowPriorityReminderAndStoresNote() async throws {
    let fixture = try await makeEnabledStoreFixture()
    let provider = FakeAppOwnedReminderProjectProvider()
    provider.createdTaskMetadata = ReminderTaskRemoteMetadata(
      identifier: "note-identifier",
      externalIdentifier: "note-external",
      modifiedAt: Date(timeIntervalSinceReferenceDate: 720)
    )

    let savedNote = try await RetainedProjectCommandFacade.setProjectNote(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      noteText: "목록 핵심",
      reminderProjectProvider: provider
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(savedNote, "목록 핵심")
    XCTAssertEqual(provider.createdProjectIdentifier, "list-1")
    XCTAssertEqual(provider.createdTaskTitle, "프로젝트 노트")
    XCTAssertEqual(provider.presentationUpdates, ["note-external": 9])
    XCTAssertEqual(project.noteMarkdown, "목록 핵심")
    XCTAssertTrue(project.tasks.isEmpty)
    assertRawProjectsDoesNotExist(in: fixture.vaultRoot)
  }

  @MainActor
  func testAppOwnedProjectAndTaskOrderingDoNotCreateRawProjects() async throws {
    let fixture = try await makeEnabledStoreFixture(taskExternalIdentifier: "task-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")

    try await fixture.store.updateProjectBoardOrders([fixture.projectID: 3])
    try await fixture.store.reorderOpenTasks(
      projectID: fixture.projectID,
      orderedTaskIDs: [taskID]
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(project.boardOrder, 3)
    XCTAssertEqual(project.tasks.map(\.identity.taskID), [taskID])
    assertRawProjectsDoesNotExist(in: fixture.vaultRoot)
  }

  @MainActor
  func testProjectNoteUpdateTreatsRenamedReminderAsBrokenAndCreatesNewNoteReminder() async throws {
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "note-old",
      taskTitle: "프로젝트 노트",
      taskNoteText: "old",
      taskPriority: 9
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    provider.remoteTaskSnapshot = ReminderTaskRemoteSnapshot(
      identifier: "old-identifier",
      externalIdentifier: "note-old",
      calendarIdentifier: "list-1",
      title: "Renamed",
      noteText: "old",
      dueDate: nil,
      hasExplicitTime: false,
      priority: 9,
      modifiedAt: Date(timeIntervalSinceReferenceDate: 730)
    )
    provider.createdTaskMetadata = ReminderTaskRemoteMetadata(
      identifier: "note-new-identifier",
      externalIdentifier: "note-new",
      modifiedAt: Date(timeIntervalSinceReferenceDate: 731)
    )

    _ = try await RetainedProjectCommandFacade.setProjectNote(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      noteText: "new",
      reminderProjectProvider: provider
    )

    XCTAssertNil(provider.updatedNoteText)
    XCTAssertEqual(provider.createdTaskTitle, "프로젝트 노트")
    XCTAssertEqual(provider.presentationUpdates["note-new"], 9)
  }

  @MainActor
  func testAppOwnedScheduleClampsOutOfRangeTimeMinutes() async throws {
    let fixture = try await makeEnabledStoreFixture(taskExternalIdentifier: "task-1")
    let provider = FakeAppOwnedReminderProjectProvider()
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let day = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))

    _ = try await RetainedTaskCommandFacade.setTaskSchedule(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      day: day,
      timeMinutes: 2_000,
      durationMinutes: nil,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let task = try XCTUnwrap(snapshot.projects.first?.tasks.first)
    let expected = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 23, minute: 59)))

    XCTAssertEqual(task.schedule.parsedDate, expected)
  }

  @MainActor
  func testAppOwnedDurationOnlyScheduleEditStaysLocalAcrossReminderImport() async throws {
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      dueDate: start,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 30
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let day = Self.calendar.startOfDay(for: start)

    _ = try await RetainedTaskCommandFacade.setTaskSchedule(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      day: day,
      timeMinutes: 9 * 60 + 30,
      durationMinutes: 90,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )

    XCTAssertNil(provider.scheduleUpdate)

    let reimportedItem = ReminderItemImportSnapshot(
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
      dueDate: start,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: Date(timeIntervalSinceReferenceDate: 401),
      modifiedAt: Date(timeIntervalSinceReferenceDate: 401)
    )
    try await fixture.store.replaceReminderSnapshot(
      ReminderImportSnapshotBatch(
        lists: [
          ReminderListImportSnapshot(
            identifier: "list-1",
            externalIdentifier: "list-1",
            title: "Project",
            colorHex: nil
          )
        ],
        itemsByListIdentifier: ["list-1": [reimportedItem]]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 401)
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let task = try XCTUnwrap(snapshot.projects.first?.tasks.first)

    XCTAssertEqual(task.schedule.parsedDate, start)
    XCTAssertTrue(task.schedule.hasExplicitTime)
    XCTAssertEqual(task.schedule.durationMinutes, 90)
  }

  @MainActor
  func testAppOwnedScheduleEditPreservesStoredDurationWhenCallerOmitsDuration() async throws {
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
    let expectedDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 10, minute: 30))
    )
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      dueDate: start,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 90
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")

    _ = try await RetainedTaskCommandFacade.setTaskSchedule(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      day: Self.calendar.startOfDay(for: start),
      timeMinutes: 10 * 60 + 30,
      durationMinutes: nil,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let task = try XCTUnwrap(snapshot.projects.first?.tasks.first)

    XCTAssertEqual(provider.scheduleUpdate?.0, expectedDate)
    XCTAssertEqual(provider.scheduleUpdate?.1, true)
    XCTAssertEqual(task.schedule.parsedDate, expectedDate)
    XCTAssertEqual(task.schedule.durationMinutes, 90)
  }

  @MainActor
  func testUserFlowRecurringTaskDateChangeSurvivesRelaunch() async throws {
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
    let moved = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 15, minute: 15))
    )
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      taskTitle: "Recurring",
      dueDate: start,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 45,
      recurrenceRuleRaw: "daily"
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")

    _ = try await RetainedTaskCommandFacade.setTaskSchedule(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      day: Self.calendar.startOfDay(for: moved),
      timeMinutes: 15 * 60 + 15,
      durationMinutes: 80,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )
    let reloadedStore = AppOwnedWorkspaceStore(
      containerRootURL: ObsidianVaultLayout(vaultRootURL: fixture.vaultRoot).sidecarRootURL
    )
    let snapshot = try await reloadedStore.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let task = try XCTUnwrap(snapshot.projects.first?.tasks.first)

    XCTAssertEqual(provider.scheduleUpdate?.0, moved)
    XCTAssertEqual(provider.scheduleUpdate?.1, true)
    XCTAssertEqual(task.schedule.parsedDate, moved)
    XCTAssertEqual(task.schedule.durationMinutes, 80)
    XCTAssertEqual(task.schedule.rawRepeatRule, "daily")
  }

  @MainActor
  func testAppOwnedScheduleEditRefreshesStaleReminderIdentifierAndRetries() async throws {
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
    let expectedDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 11, minute: 15))
    )
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      dueDate: start,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 90
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    provider.scheduleMetadataResults = [
      nil,
      ReminderTaskRemoteMetadata(
        identifier: "fresh-task-identifier",
        externalIdentifier: "task-1",
        modifiedAt: Date(timeIntervalSinceReferenceDate: 710)
      ),
    ]
    provider.fetchedImportSnapshotBatch = ReminderImportSnapshotBatch(
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
            identifier: "fresh-task-identifier",
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
            dueDate: start,
            scheduleHasExplicitTime: true,
            scheduledDurationMinutes: nil,
            priority: 0,
            recurrenceRuleRaw: nil,
            isFlagged: false,
            requiredWorkDays: 0,
            createdAt: Date(timeIntervalSinceReferenceDate: 700),
            modifiedAt: Date(timeIntervalSinceReferenceDate: 700)
          )
        ]
      ]
    )
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")

    _ = try await RetainedTaskCommandFacade.setTaskSchedule(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      day: Self.calendar.startOfDay(for: start),
      timeMinutes: 11 * 60 + 15,
      durationMinutes: nil,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )
    let task = try await fixture.store.taskReference(projectID: fixture.projectID, taskID: taskID)

    XCTAssertEqual(provider.scheduleTaskReferences.map(\.reminderIdentifier), [
      "task-identifier",
      "fresh-task-identifier",
    ])
    XCTAssertEqual(task.reminderIdentifier, "fresh-task-identifier")
    XCTAssertEqual(task.dueDate, expectedDate)
    XCTAssertEqual(task.durationMinutes, 90)
  }

  @MainActor
  func testAppOwnedPartialReminderRefreshPreservesOtherProjectStorageInvariants()
    async throws
  {
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30))
    )
    let expectedDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 11, minute: 15))
    )
    let recurringActiveDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 9))
    )
    let recurringCompletedDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 8))
    )
    let vaultRoot = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: vaultRoot.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    let store = AppOwnedWorkspaceStore.storeForVaultRootURL(vaultRoot)
    let firstProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    let secondProjectID = RetainedProjectionBuilder.derivedProjectID(for: "list-2")
    let firstTaskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let secondFirstTaskID = ReminderProjectionIdentity.taskID(for: "task-2-a")
    let secondSecondTaskID = ReminderProjectionIdentity.taskID(for: "task-2-b")
    let recurringTaskID = ReminderProjectionIdentity.taskID(for: "task-2-recurring")
    let importedAt = Date(timeIntervalSinceReferenceDate: 800)

    func item(
      identifier: String,
      externalIdentifier: String,
      listIdentifier: String,
      title: String,
      dueDate: Date? = nil,
      hasExplicitTime: Bool = false,
      durationMinutes: Int? = nil,
      recurrenceRuleRaw: String? = nil,
      modifiedAt: Date = importedAt
    ) -> ReminderItemImportSnapshot {
      ReminderItemImportSnapshot(
        identifier: identifier,
        externalIdentifier: externalIdentifier,
        parentExternalIdentifier: nil,
        sourceListIdentifier: listIdentifier,
        sourceListTitle: listIdentifier == "list-1" ? "Focus" : "Backlog",
        title: title,
        notes: "",
        attachmentCount: 0,
        isCompleted: false,
        completionDate: nil,
        startDate: nil,
        dueDate: dueDate,
        scheduleHasExplicitTime: hasExplicitTime,
        scheduledDurationMinutes: durationMinutes,
        priority: 0,
        recurrenceRuleRaw: recurrenceRuleRaw,
        isFlagged: false,
        requiredWorkDays: 0,
        createdAt: importedAt,
        modifiedAt: modifiedAt
      )
    }

    let initialBatch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Focus",
          colorHex: nil
        ),
        ReminderListImportSnapshot(
          identifier: "list-2",
          externalIdentifier: "list-2",
          title: "Backlog",
          colorHex: nil
        ),
      ],
      itemsByListIdentifier: [
        "list-1": [
          item(
            identifier: "task-1-identifier",
            externalIdentifier: "task-1",
            listIdentifier: "list-1",
            title: "Editable",
            dueDate: start,
            hasExplicitTime: true,
            durationMinutes: 90
          )
        ],
        "list-2": [
          item(
            identifier: "task-2-a-identifier",
            externalIdentifier: "task-2-a",
            listIdentifier: "list-2",
            title: "Second A",
            dueDate: start,
            hasExplicitTime: true
          ),
          item(
            identifier: "task-2-b-identifier",
            externalIdentifier: "task-2-b",
            listIdentifier: "list-2",
            title: "Second B"
          ),
          item(
            identifier: "task-2-recurring-identifier",
            externalIdentifier: "task-2-recurring",
            listIdentifier: "list-2",
            title: "Recurring",
            dueDate: recurringActiveDate,
            recurrenceRuleRaw: "daily"
          ),
        ],
      ]
    )
    try await store.replaceReminderSnapshot(initialBatch, importedAt: importedAt)
    try await store.setProjectionReadEnabled(true)
    try await store.updateProjectStage(
      projectID: secondProjectID,
      stage: .later,
      modifiedAt: importedAt.addingTimeInterval(1)
    )
    try await store.updateProjectBoardOrders([
      firstProjectID: 1,
      secondProjectID: 0,
    ])
    try await store.mergeTaskSupplements([
      AppOwnedWorkspaceStore.TaskSupplement(taskID: secondFirstTaskID, durationMinutes: 75)
    ])
    try await store.reorderOpenTasks(
      projectID: secondProjectID,
      orderedTaskIDs: [secondSecondTaskID, secondFirstTaskID, recurringTaskID]
    )
    let recurringTask = try await store.taskReference(
      projectID: secondProjectID,
      taskID: recurringTaskID
    )
    _ = try await store.upsertLocalCompletedRecurringOccurrence(
      projectID: secondProjectID,
      sourceTask: AppOwnedWorkspaceStore.TaskReference(
        projectID: secondProjectID,
        taskID: recurringTaskID,
        reminderIdentifier: recurringTask.reminderIdentifier,
        reminderExternalIdentifier: recurringTask.reminderExternalIdentifier,
        title: recurringTask.title,
        noteText: recurringTask.noteText,
        isCompleted: false,
        completionDate: nil,
        dueDate: recurringCompletedDate,
        hasExplicitTime: true,
        durationMinutes: 45,
        recurrenceRuleRaw: recurringTask.recurrenceRuleRaw,
        priority: recurringTask.priority
      ),
      completionDate: recurringCompletedDate,
      modifiedAt: importedAt.addingTimeInterval(2)
    )

    let provider = FakeAppOwnedReminderProjectProvider()
    provider.scheduleMetadataResults = [
      nil,
      ReminderTaskRemoteMetadata(
        identifier: "fresh-task-1-identifier",
        externalIdentifier: "task-1",
        modifiedAt: importedAt.addingTimeInterval(20)
      ),
    ]
    provider.fetchedImportSnapshotBatch = ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: "list-1",
          externalIdentifier: "list-1",
          title: "Focus",
          colorHex: nil
        )
      ],
      itemsByListIdentifier: [
        "list-1": [
          item(
            identifier: "fresh-task-1-identifier",
            externalIdentifier: "task-1",
            listIdentifier: "list-1",
            title: "Editable",
            dueDate: start,
            hasExplicitTime: true,
            durationMinutes: nil,
            modifiedAt: importedAt.addingTimeInterval(10)
          )
        ]
      ]
    )

    _ = try await RetainedTaskCommandFacade.setTaskSchedule(
      vaultRootURL: vaultRoot,
      projectID: firstProjectID,
      taskID: firstTaskID,
      day: Self.calendar.startOfDay(for: start),
      timeMinutes: 11 * 60 + 15,
      durationMinutes: nil,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )
    let reloadedStore = AppOwnedWorkspaceStore.storeForVaultRootURL(vaultRoot)
    let snapshot = try await reloadedStore.loadRetainedWorkspaceSnapshot(projectIDs: [])
    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map {
      ($0.identity.projectID, $0)
    })
    let refreshedTask = try await reloadedStore.taskReference(
      projectID: firstProjectID,
      taskID: firstTaskID
    )
    let secondProject = try XCTUnwrap(projectsByID[secondProjectID])
    let secondOpenTasks = secondProject.tasks.filter { !$0.isCompleted }
    let completedOccurrence = try XCTUnwrap(secondProject.tasks.first { $0.isCompleted })

    XCTAssertEqual(provider.scheduleTaskReferences.map(\.reminderIdentifier), [
      "task-1-identifier",
      "fresh-task-1-identifier",
    ])
    XCTAssertEqual(refreshedTask.dueDate, expectedDate)
    XCTAssertEqual(refreshedTask.durationMinutes, 90)
    XCTAssertEqual(secondProject.progressStage, .later)
    XCTAssertEqual(projectsByID[firstProjectID]?.boardOrder, 1)
    XCTAssertEqual(secondProject.boardOrder, 0)
    XCTAssertEqual(
      secondOpenTasks.map(\.identity.taskID),
      [secondSecondTaskID, secondFirstTaskID, recurringTaskID]
    )
    XCTAssertEqual(
      secondOpenTasks.first { $0.identity.taskID == secondFirstTaskID }?.schedule.durationMinutes,
      75
    )
    XCTAssertEqual(completedOccurrence.schedule.parsedDate, recurringCompletedDate)
    XCTAssertEqual(completedOccurrence.schedule.durationMinutes, 45)
  }

  @MainActor
  func testAppOwnedRecurringCompletionUsesAdvancedReminderSnapshotAndClearsTime() async throws {
    let dueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 2)))
    let nextDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 2)))
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      taskTitle: "Recurring",
      dueDate: dueDate,
      scheduleHasExplicitTime: true,
      scheduledDurationMinutes: 45,
      recurrenceRuleRaw: "daily"
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    provider.remoteTaskSnapshot = ReminderTaskRemoteSnapshot(
      identifier: "task-identifier",
      externalIdentifier: "task-1",
      calendarIdentifier: "list-1",
      title: "Recurring",
      noteText: "",
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: nextDueDate,
      hasExplicitTime: true,
      priority: 0,
      recurrenceRuleRaw: "daily",
      modifiedAt: Date(timeIntervalSinceReferenceDate: 700)
    )
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")

    _ = try await RetainedTaskCommandFacade.setTaskCompletion(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      isCompleted: true,
      completionDate: dueDate,
      reminderProjectProvider: provider
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let tasks = try XCTUnwrap(snapshot.projects.first?.tasks)
    let task = try XCTUnwrap(tasks.first { !$0.isCompleted })
    let completedOccurrence = try XCTUnwrap(tasks.first { $0.isCompleted })

    XCTAssertEqual(provider.completionUpdate?.0, taskID)
    XCTAssertEqual(provider.scheduleUpdate?.0, nextDueDate)
    XCTAssertEqual(provider.scheduleUpdate?.1, false)
    XCTAssertEqual(tasks.count, 2)
    XCTAssertFalse(task.isCompleted)
    XCTAssertEqual(task.schedule.parsedDate, nextDueDate)
    XCTAssertFalse(task.schedule.hasExplicitTime)
    XCTAssertNil(task.schedule.durationMinutes)
    XCTAssertEqual(task.schedule.rawRepeatRule, "daily")
    XCTAssertEqual(completedOccurrence.title, "Recurring")
    XCTAssertEqual(completedOccurrence.schedule.parsedDate, dueDate)
    XCTAssertTrue(completedOccurrence.schedule.hasExplicitTime)
    XCTAssertEqual(completedOccurrence.schedule.durationMinutes, 45)
    XCTAssertNil(completedOccurrence.schedule.rawRepeatRule)
    XCTAssertTrue(
      AppOwnedWorkspaceStore.isLocalCompletedRecurringExternalIdentifier(
        completedOccurrence.identity.reminderExternalIdentifier
      )
    )
  }

  @MainActor
  func testAppOwnedRecurringScheduleRestoreWithResetRecreatesReminderAnchor() async throws {
    let advancedDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 5)))
    let originalDueDate = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 11)))
    let fixture = try await makeEnabledStoreFixture(
      taskExternalIdentifier: "task-1",
      taskTitle: "Recurring",
      dueDate: advancedDueDate,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      recurrenceRuleRaw: "daily|3"
    )
    let provider = FakeAppOwnedReminderProjectProvider()
    provider.createdTaskMetadata = ReminderTaskRemoteMetadata(
      identifier: "recreated-identifier",
      externalIdentifier: "task-recreated",
      modifiedAt: Date(timeIntervalSinceReferenceDate: 900)
    )
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let sourceTask = try await fixture.store.taskReference(projectID: fixture.projectID, taskID: taskID)
    _ = try await fixture.store.upsertLocalCompletedRecurringOccurrence(
      projectID: fixture.projectID,
      sourceTask: AppOwnedWorkspaceStore.TaskReference(
        projectID: fixture.projectID,
        taskID: taskID,
        reminderIdentifier: sourceTask.reminderIdentifier,
        reminderExternalIdentifier: sourceTask.reminderExternalIdentifier,
        title: sourceTask.title,
        noteText: sourceTask.noteText,
        isCompleted: false,
        completionDate: nil,
        dueDate: originalDueDate,
        hasExplicitTime: true,
        durationMinutes: 45,
        recurrenceRuleRaw: sourceTask.recurrenceRuleRaw,
        priority: sourceTask.priority
      ),
      completionDate: originalDueDate,
      modifiedAt: Date(timeIntervalSinceReferenceDate: 850)
    )

    _ = try await RetainedTaskCommandFacade.setTaskSchedule(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      day: Self.calendar.startOfDay(for: originalDueDate),
      timeMinutes: 11 * 60,
      durationMinutes: 45,
      calendar: Self.calendar,
      reminderProjectProvider: provider,
      resetRecurringAnchor: true
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let tasks = try XCTUnwrap(snapshot.projects.first?.tasks)
    let task = try XCTUnwrap(tasks.first)

    XCTAssertEqual(provider.createdProjectIdentifier, "list-1")
    XCTAssertEqual(provider.createdTaskTitle, "Recurring")
    XCTAssertEqual(provider.createdTaskDueDate, originalDueDate)
    XCTAssertEqual(provider.createdTaskHasExplicitTime, true)
    XCTAssertEqual(provider.recurrenceUpdate?.0, "task-recreated")
    XCTAssertEqual(provider.recurrenceUpdate?.1, "daily|3")
    XCTAssertEqual(provider.removedTaskExternalIdentifiers, ["task-1"])
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "task-recreated")
    XCTAssertEqual(task.schedule.parsedDate, originalDueDate)
    XCTAssertTrue(task.schedule.hasExplicitTime)
    XCTAssertEqual(task.schedule.durationMinutes, 45)
    XCTAssertEqual(task.schedule.rawRepeatRule, "daily|3")
  }

  @MainActor
  func testObsidianCommandDoesNotFallbackToLegacyMarkdownWhenAppOwnedStoreIsUnavailable() async throws {
    let vaultRoot = try makeTemporaryDirectory()

    do {
      _ = try await RetainedTaskCommandFacade.taskEditFields(
        vaultRootURL: vaultRoot,
        projectID: UUID(),
        taskID: UUID(),
        calendar: Self.calendar
      )
      XCTFail("Expected disabled legacy Obsidian markdown storage to fail")
    } catch RetainedTaskCommandError.retainedProjectionFailed(let message) {
      XCTAssertTrue(message.contains("app-owned workspace storage is unavailable"))
    }
  }

  private struct StoreFixture {
    let vaultRoot: URL
    let store: AppOwnedWorkspaceStore
    let projectID: UUID
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private func reminderImportBatch(
    item: ReminderItemImportSnapshot,
    listIdentifier: String = "list-1",
    listExternalIdentifier: String = "list-1",
    listTitle: String = "Project"
  ) -> ReminderImportSnapshotBatch {
    ReminderImportSnapshotBatch(
      lists: [
        ReminderListImportSnapshot(
          identifier: listIdentifier,
          externalIdentifier: listExternalIdentifier,
          title: listTitle,
          colorHex: nil
        )
      ],
      itemsByListIdentifier: [listIdentifier: [item]]
    )
  }

  private func reminderImportItem(
    identifier: String,
    externalIdentifier: String,
    title: String,
    dueDate: Date?,
    scheduleHasExplicitTime: Bool,
    scheduledDurationMinutes: Int?,
    recurrenceRuleRaw: String? = nil,
    modifiedAt: Date
  ) -> ReminderItemImportSnapshot {
    ReminderItemImportSnapshot(
      identifier: identifier,
      externalIdentifier: externalIdentifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: "list-1",
      sourceListTitle: "Project",
      title: title,
      notes: "",
      attachmentCount: 0,
      isCompleted: false,
      completionDate: nil,
      startDate: nil,
      dueDate: dueDate,
      scheduleHasExplicitTime: scheduleHasExplicitTime,
      scheduledDurationMinutes: scheduledDurationMinutes,
      priority: 0,
      recurrenceRuleRaw: recurrenceRuleRaw,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: modifiedAt,
      modifiedAt: modifiedAt
    )
  }

  @MainActor
  private func makeEnabledStoreFixture(
    taskExternalIdentifier: String? = nil,
    taskTitle: String = "Task",
    taskNoteText: String = "",
    taskPriority: Int = 0,
    dueDate: Date? = nil,
    scheduleHasExplicitTime: Bool = false,
    scheduledDurationMinutes: Int? = nil,
    recurrenceRuleRaw: String? = nil
  ) async throws -> StoreFixture {
    let vaultRoot = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
      at: vaultRoot.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    let store = AppOwnedWorkspaceStore.storeForVaultRootURL(vaultRoot)
    let items: [ReminderItemImportSnapshot]
    if let taskExternalIdentifier {
      items = [
        ReminderItemImportSnapshot(
          identifier: "task-identifier",
          externalIdentifier: taskExternalIdentifier,
          parentExternalIdentifier: nil,
          sourceListIdentifier: "list-1",
          sourceListTitle: "Project",
          title: taskTitle,
          notes: taskNoteText,
          attachmentCount: 0,
	          isCompleted: false,
	          completionDate: nil,
	          startDate: nil,
	          dueDate: dueDate,
	          scheduleHasExplicitTime: scheduleHasExplicitTime,
	          scheduledDurationMinutes: scheduledDurationMinutes,
	          priority: taskPriority,
	          recurrenceRuleRaw: recurrenceRuleRaw,
          isFlagged: false,
          requiredWorkDays: 0,
          createdAt: Date(timeIntervalSinceReferenceDate: 400),
          modifiedAt: Date(timeIntervalSinceReferenceDate: 400)
        )
      ]
    } else {
      items = []
    }
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
        itemsByListIdentifier: ["list-1": items]
      ),
      importedAt: Date(timeIntervalSinceReferenceDate: 400)
    )
    try await store.setProjectionReadEnabled(true)
    return StoreFixture(
      vaultRoot: vaultRoot,
      store: store,
      projectID: RetainedProjectionBuilder.derivedProjectID(for: "list-1")
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppOwnedRetainedTaskCommandServiceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func assertRawProjectsDoesNotExist(
    in vaultRoot: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let rawProjectsURL = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: rawProjectsURL.path), file: file, line: line)
  }
}

@MainActor
private final class FakeAppOwnedReminderProjectProvider: ReminderProjectProvider {
  var createdTaskMetadata: ReminderTaskRemoteMetadata?
  var createdTaskTitle: String?
  var createdTaskDueDate: Date?
  var createdTaskHasExplicitTime: Bool?
  var updateMetadata = ReminderTaskRemoteMetadata(
    identifier: "task-identifier",
    externalIdentifier: "task-1",
    modifiedAt: Date(timeIntervalSinceReferenceDate: 1)
  )
  var createdProjectIdentifier: String?
  var renamedTitle: String?
  var updatedNoteText: String?
  var projectTitleUpdate: (String, String)?
  var projectColorUpdate: (String, String?)?
  var completionUpdate: (UUID, Bool)?
  var scheduleUpdate: (Date?, Bool)?
  var scheduleTaskReferences: [ReminderTaskReference] = []
  var scheduleMetadataResults: [ReminderTaskRemoteMetadata?]?
  var recurrenceUpdate: (String?, String?)?
  var removedTaskExternalIdentifiers: [String?] = []
  var remoteTaskSnapshot: ReminderTaskRemoteSnapshot?
  var fetchedImportSnapshotBatch: ReminderImportSnapshotBatch?
  var presentationUpdates: [String: Int] = [:]

  var defaultCalendarIdentifierForNewReminders: String? { "list-1" }

  func requestAccess() async throws -> Bool { true }
  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch? {
    _ = identifiers
    return fetchedImportSnapshotBatch
  }

  func createProjectList(title: String) throws -> ReminderProjectListSnapshot {
    ReminderProjectListSnapshot(identifier: "list-1", externalIdentifier: "list-1", title: title, colorHex: nil)
  }
  func removeProjectList(identifier: String) throws {}
  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot? {
    projectTitleUpdate = (identifier, title)
    return ReminderProjectListSnapshot(identifier: identifier, externalIdentifier: identifier, title: title, colorHex: nil)
  }

  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot? {
    projectColorUpdate = (identifier, colorHex)
    return ReminderProjectListSnapshot(
      identifier: identifier,
      externalIdentifier: identifier,
      title: "Project",
      colorHex: colorHex
    )
  }

  func createTaskReminder(
    inProject identifier: String,
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    createdProjectIdentifier = identifier
    createdTaskTitle = title
    createdTaskDueDate = dueDate
    createdTaskHasExplicitTime = hasExplicitTime
    return createdTaskMetadata
  }

  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool {
    removedTaskExternalIdentifiers.append(task.reminderExternalIdentifier)
    return true
  }
  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot? {
    _ = task
    return remoteTaskSnapshot
  }

  func setTaskTitle(
    for task: ReminderTaskReference,
    title: String
  ) throws -> ReminderTaskRemoteMetadata? {
    renamedTitle = title
    return updateMetadata
  }

  func setTaskCompletion(
    for task: ReminderTaskReference,
    isCompleted: Bool,
    completionDate: Date?
  ) throws -> ReminderTaskRemoteMetadata? {
    completionUpdate = (task.taskID, isCompleted)
    return updateMetadata
  }

  func setTaskReminderNote(
    for task: ReminderTaskReference,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    updatedNoteText = noteText
    return updateMetadata
  }

  func setTaskSchedule(
    for task: ReminderTaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws -> ReminderTaskRemoteMetadata? {
    scheduleTaskReferences.append(task)
    scheduleUpdate = (dueDate, hasExplicitTime)
    let metadata: ReminderTaskRemoteMetadata?
    if var scheduleMetadataResults {
      metadata = scheduleMetadataResults.removeFirst()
      self.scheduleMetadataResults = scheduleMetadataResults
    } else {
      metadata = updateMetadata
    }
    if let snapshot = remoteTaskSnapshot {
      remoteTaskSnapshot = ReminderTaskRemoteSnapshot(
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
        modifiedAt: metadata?.modifiedAt ?? updateMetadata.modifiedAt
      )
    }
    return metadata
  }

  func setTaskRecurrence(
    for task: ReminderTaskReference,
    recurrenceRuleRaw: String?
  ) throws -> ReminderTaskRemoteMetadata? {
    recurrenceUpdate = (task.reminderExternalIdentifier, recurrenceRuleRaw)
    return updateMetadata
  }

  func setTaskPresentation(
    for task: ReminderTaskReference,
    priority: Int
  ) throws -> ReminderTaskRemoteMetadata? {
    if let externalIdentifier = task.reminderExternalIdentifier {
      presentationUpdates[externalIdentifier] = priority
    }
    return updateMetadata
  }

  func moveTaskReminder(
    for task: ReminderTaskReference,
    toProject identifier: String
  ) throws -> ReminderTaskRemoteMetadata? {
    updateMetadata
  }

  func restoreArchivedProject(
    _ project: ReminderArchivedProjectSnapshot
  ) throws -> ReminderProjectRestoreResult {
    throw RetainedTaskCommandError.retainedProjectionFailed("unused")
  }

  func removeArchivedProjectLists(
    _ projects: [ReminderProjectListReference]
  ) -> ReminderProjectCleanupResult {
    ReminderProjectCleanupResult(removedCount: 0, failedProjectIDs: [])
  }
}
