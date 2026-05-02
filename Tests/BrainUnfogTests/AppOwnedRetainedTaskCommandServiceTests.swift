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

    let result = try await ObsidianRetainedTaskCommandService.createTask(
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

    _ = try await ObsidianRetainedTaskCommandService.updateTaskEditFields(
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
    let fields = try await ObsidianRetainedTaskCommandService.taskEditFields(
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
  func testObsidianProjectTitleRoutesToAppOwnedStoreWhenEnabled() async throws {
    let fixture = try await makeEnabledStoreFixture()
    let provider = FakeAppOwnedReminderProjectProvider()

    let result = try await ObsidianRetainedProjectCommandService.setProjectTitle(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      title: "Renamed Project",
      reminderProjectProvider: provider
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let project = try XCTUnwrap(snapshot.projects.first)

    XCTAssertEqual(provider.projectTitleUpdate?.0, "list-1")
    XCTAssertEqual(provider.projectTitleUpdate?.1, "Renamed Project")
    XCTAssertEqual(result.note.reminderListExternalIdentifier, "list-1")
    XCTAssertEqual(project.title, "Renamed Project")
  }

  @MainActor
  func testObsidianProjectColorAndStageRouteToAppOwnedStoreWhenEnabled() async throws {
    let fixture = try await makeEnabledStoreFixture()
    let provider = FakeAppOwnedReminderProjectProvider()

    _ = try await ObsidianRetainedProjectCommandService.setProjectColor(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      colorHex: "#112233",
      reminderProjectProvider: provider
    )
    _ = try await ObsidianRetainedProjectCommandService.setProjectStage(
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
  }

  @MainActor
  func testAppOwnedScheduleClampsOutOfRangeTimeMinutes() async throws {
    let fixture = try await makeEnabledStoreFixture(taskExternalIdentifier: "task-1")
    let provider = FakeAppOwnedReminderProjectProvider()
    let taskID = ReminderProjectionIdentity.taskID(for: "task-1")
    let day = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))

    _ = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
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

    _ = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
      vaultRootURL: fixture.vaultRoot,
      projectID: fixture.projectID,
      taskID: taskID,
      isCompleted: true,
      completionDate: dueDate,
      reminderProjectProvider: provider
    )
    let snapshot = try await fixture.store.loadRetainedWorkspaceSnapshot(projectIDs: [fixture.projectID])
    let task = try XCTUnwrap(snapshot.projects.first?.tasks.first)

    XCTAssertEqual(provider.completionUpdate?.0, taskID)
    XCTAssertEqual(provider.scheduleUpdate?.0, nextDueDate)
    XCTAssertEqual(provider.scheduleUpdate?.1, false)
    XCTAssertFalse(task.isCompleted)
    XCTAssertEqual(task.schedule.parsedDate, nextDueDate)
    XCTAssertFalse(task.schedule.hasExplicitTime)
    XCTAssertNil(task.schedule.durationMinutes)
    XCTAssertEqual(task.schedule.rawRepeatRule, "daily")
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

  @MainActor
  private func makeEnabledStoreFixture(
    taskExternalIdentifier: String? = nil,
    taskTitle: String = "Task",
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
}

@MainActor
private final class FakeAppOwnedReminderProjectProvider: ReminderProjectProvider {
  var createdTaskMetadata: ReminderTaskRemoteMetadata?
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
  var remoteTaskSnapshot: ReminderTaskRemoteSnapshot?

  var defaultCalendarIdentifierForNewReminders: String? { "list-1" }

  func requestAccess() async throws -> Bool { true }
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
    return createdTaskMetadata
  }

  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool { true }
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
    _ = task
    scheduleUpdate = (dueDate, hasExplicitTime)
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
        modifiedAt: updateMetadata.modifiedAt
      )
    }
    return updateMetadata
  }

  func setTaskRecurrence(
    for task: ReminderTaskReference,
    recurrenceRuleRaw: String?
  ) throws -> ReminderTaskRemoteMetadata? {
    updateMetadata
  }

  func setTaskPresentation(
    for task: ReminderTaskReference,
    priority: Int
  ) throws -> ReminderTaskRemoteMetadata? {
    updateMetadata
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
