import XCTest
@testable import BrainUnfogHarness

@MainActor
final class RetainedTaskCommandServiceTests: XCTestCase {
  func testCompletionUpdatesLogseqAndReminderWithoutLegacyCalendarWrite() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedCompletionGraph")
    let projectID = UUID()
    let taskID = UUID()
    let store = makeStore(graphRootURL: graphRootURL)
    try await store.upsertPage(
      .init(projectID: projectID, title: "Launch", reminderListExternalIdentifier: nil),
      noteMarkdown: "Launch note",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Prepare launch",
          isCompleted: false,
          date: "2026-04-25 14:30",
          duration: "45",
          repeatRule: nil,
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: "event-1"
        )
      ]
    )
    let provider = FakeReminderProjectProvider()
    let completionDate = try XCTUnwrap(Self.calendar.date(from: .init(year: 2026, month: 4, day: 24)))

    let result = try await RetainedTaskCommandService.setTaskCompletion(
      graphRootURL: graphRootURL,
      projectID: projectID,
      taskID: taskID,
      isCompleted: true,
      completionDate: completionDate,
      reminderProjectProvider: provider
    )

    let task = try await loadedTask(taskID: taskID, graphRootURL: graphRootURL)
    XCTAssertTrue(task.isCompleted)
    XCTAssertEqual(provider.completionWrites.count, 1)
    XCTAssertEqual(provider.completionWrites[0].reference.taskID, taskID)
    XCTAssertEqual(provider.completionWrites[0].reference.reminderExternalIdentifier, "reminder-1")
    XCTAssertTrue(provider.completionWrites[0].isCompleted)
    XCTAssertEqual(provider.scheduleWrites.count, 0)
    XCTAssertEqual(provider.recurrenceWrites.count, 0)
    XCTAssertEqual(
      result.calendarBridgeDecision,
      .upsert(
        RetainedCalendarBridgeUpsertRequest(
          externalIdentifier: "event-1",
          title: "Prepare launch",
          startDate: try XCTUnwrap(LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date),
          durationMinutes: 45
        )
      )
    )
  }

  func testDateOnlyScheduleReturnsRemoveIntentWithoutClearingCalendarIdentity() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedDateOnlyGraph")
    let projectID = UUID()
    let taskID = UUID()
    let store = makeStore(graphRootURL: graphRootURL)
    try await store.upsertPage(
      .init(projectID: projectID, title: "Launch", reminderListExternalIdentifier: nil),
      noteMarkdown: "",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Date only",
          isCompleted: false,
          date: "2026-04-25 14:30",
          duration: "45",
          repeatRule: "weekly",
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: "event-1"
        )
      ]
    )
    let provider = FakeReminderProjectProvider()
    let day = try XCTUnwrap(Self.calendar.date(from: .init(year: 2026, month: 4, day: 25)))

    let result = try await RetainedTaskCommandService.setTaskSchedule(
      graphRootURL: graphRootURL,
      projectID: projectID,
      taskID: taskID,
      day: day,
      timeMinutes: nil,
      durationMinutes: nil,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )

    let task = try await loadedTask(taskID: taskID, graphRootURL: graphRootURL)
    XCTAssertEqual(task.date, "2026-04-25")
    XCTAssertNil(task.duration)
    XCTAssertEqual(task.repeatRule, "weekly")
    XCTAssertEqual(task.calendarEventExternalIdentifier, "event-1")
    XCTAssertEqual(provider.scheduleWrites.count, 1)
    XCTAssertEqual(provider.scheduleWrites[0].reference.reminderExternalIdentifier, "reminder-1")
    XCTAssertEqual(provider.scheduleWrites[0].dueDate, day)
    XCTAssertFalse(provider.scheduleWrites[0].hasExplicitTime)
    XCTAssertEqual(result.calendarBridgeDecision, .removeOwnedEvent(externalIdentifier: "event-1"))
    XCTAssertEqual(result.calendarWriteMarker?.operation, .removeOwnedEvent)
    XCTAssertEqual(result.calendarWriteMarker?.externalIdentifier, "event-1")
  }

  func testExplicitTimeScheduleReturnsUpsertIntentAndDoesNotWriteRecurrence() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedTimedGraph")
    let projectID = UUID()
    let taskID = UUID()
    let store = makeStore(graphRootURL: graphRootURL)
    try await store.upsertPage(
      .init(projectID: projectID, title: "Launch", reminderListExternalIdentifier: nil),
      noteMarkdown: "",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Timed",
          isCompleted: false,
          date: nil,
          duration: nil,
          repeatRule: "daily",
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: nil
        )
      ]
    )
    let provider = FakeReminderProjectProvider()
    let day = try XCTUnwrap(Self.calendar.date(from: .init(year: 2026, month: 4, day: 25)))
    let expectedStart = try XCTUnwrap(
      Self.calendar.date(from: .init(year: 2026, month: 4, day: 25, hour: 14, minute: 30))
    )

    let result = try await RetainedTaskCommandService.setTaskSchedule(
      graphRootURL: graphRootURL,
      projectID: projectID,
      taskID: taskID,
      day: day,
      timeMinutes: 14 * 60 + 30,
      durationMinutes: 45,
      calendar: Self.calendar,
      reminderProjectProvider: provider
    )

    let task = try await loadedTask(taskID: taskID, graphRootURL: graphRootURL)
    XCTAssertEqual(task.date, "2026-04-25 14:30")
    XCTAssertEqual(task.duration, "45")
    XCTAssertEqual(task.repeatRule, "daily")
    XCTAssertEqual(provider.scheduleWrites.count, 1)
    XCTAssertEqual(provider.scheduleWrites[0].dueDate, expectedStart)
    XCTAssertTrue(provider.scheduleWrites[0].hasExplicitTime)
    XCTAssertEqual(provider.recurrenceWrites.count, 0)
    XCTAssertEqual(
      result.calendarBridgeDecision,
      .upsert(
        RetainedCalendarBridgeUpsertRequest(
          externalIdentifier: nil,
          title: "Timed",
          startDate: expectedStart,
          durationMinutes: 45
        )
      )
    )
    XCTAssertEqual(result.calendarWriteMarker?.operation, .upsertOwnedEvent)
  }

  func testMissingReminderIdentityBlocksWithoutMutatingLogseqOrReminder() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedMissingReminderGraph")
    let projectID = UUID()
    let taskID = UUID()
    let store = makeStore(graphRootURL: graphRootURL)
    try await store.upsertPage(
      .init(projectID: projectID, title: "Launch", reminderListExternalIdentifier: nil),
      noteMarkdown: "",
      managedTasks: [
        .init(taskID: taskID, title: "No reminder", isCompleted: false)
      ]
    )
    let provider = FakeReminderProjectProvider()

    do {
      _ = try await RetainedTaskCommandService.setTaskCompletion(
        graphRootURL: graphRootURL,
        projectID: projectID,
        taskID: taskID,
        isCompleted: true,
        completionDate: .now,
        reminderProjectProvider: provider
      )
      XCTFail("Expected missing reminder identity to block")
    } catch RetainedTaskCommandError.missingReminderExternalIdentifier(let blockedTaskID) {
      XCTAssertEqual(blockedTaskID, taskID)
    }

    let task = try await loadedTask(taskID: taskID, graphRootURL: graphRootURL)
    XCTAssertFalse(task.isCompleted)
    XCTAssertEqual(provider.completionWrites.count, 0)
    XCTAssertEqual(provider.scheduleWrites.count, 0)
  }

  func testExternalTaskBlocksWithoutLegacyFallback() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedExternalTaskGraph")
    let projectID = UUID()
    let taskID = UUID()
    let pagesURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesURL, withIntermediateDirectories: true)
    let pageURL = pagesURL.appendingPathComponent("External.md", isDirectory: false)
    try """
    tags:: 프로젝트
    brain_unfog_project_id:: \(projectID.uuidString.lowercased())

    - TODO External task
      brain_unfog_task_id:: \(taskID.uuidString.lowercased())
      reminder_external_id:: reminder-1

    ## Brain Unfog Managed Tasks
    <!-- generated-by: Brain Unfog -->
    """.write(to: pageURL, atomically: true, encoding: .utf8)
    let provider = FakeReminderProjectProvider()

    do {
      _ = try await RetainedTaskCommandService.setTaskCompletion(
        graphRootURL: graphRootURL,
        projectID: projectID,
        taskID: taskID,
        isCompleted: true,
        completionDate: .now,
        reminderProjectProvider: provider
      )
      XCTFail("Expected unmanaged task to block")
    } catch RetainedTaskCommandError.unmanagedTask(let blockedTaskID) {
      XCTAssertEqual(blockedTaskID, taskID)
    }

    XCTAssertEqual(provider.completionWrites.count, 0)
  }

  func testReminderFailureRollsBackLogseqManagedTaskMutation() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedRollbackGraph")
    let projectID = UUID()
    let taskID = UUID()
    let store = makeStore(graphRootURL: graphRootURL)
    try await store.upsertPage(
      .init(projectID: projectID, title: "Launch", reminderListExternalIdentifier: nil),
      noteMarkdown: "",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Rollback",
          isCompleted: false,
          reminderExternalIdentifier: "reminder-1"
        )
      ]
    )
    let provider = FakeReminderProjectProvider()
    provider.completionError = FakeReminderError.requestedFailure

    do {
      _ = try await RetainedTaskCommandService.setTaskCompletion(
        graphRootURL: graphRootURL,
        projectID: projectID,
        taskID: taskID,
        isCompleted: true,
        completionDate: .now,
        reminderProjectProvider: provider
      )
      XCTFail("Expected reminder failure")
    } catch FakeReminderError.requestedFailure {
    }

    let task = try await loadedTask(taskID: taskID, graphRootURL: graphRootURL)
    XCTAssertFalse(task.isCompleted)
    XCTAssertEqual(provider.completionWrites.count, 1)
  }

  func testManagedTaskUpdateFailsClosedWhenBaselineChanged() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedConcurrentWriteGraph")
    let projectID = UUID()
    let taskID = UUID()
    let store = makeStore(graphRootURL: graphRootURL)
    try await store.upsertPage(
      .init(projectID: projectID, title: "Launch", reminderListExternalIdentifier: nil),
      noteMarkdown: "",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Concurrent",
          isCompleted: false,
          reminderExternalIdentifier: "reminder-1"
        )
      ]
    )
    let pages = try await store.loadProjectPagesInScope()
    let page = try XCTUnwrap(pages.onlyValue)
    var firstWrite = page.managedTasks
    firstWrite[0].isCompleted = true
    try await store.updateManagedTasks(
      in: page,
      expectedManagedTasks: page.managedTasks,
      managedTasks: firstWrite
    )
    var staleWrite = page.managedTasks
    staleWrite[0].title = "Stale overwrite"

    do {
      try await store.updateManagedTasks(
        in: page,
        expectedManagedTasks: page.managedTasks,
        managedTasks: staleWrite
      )
      XCTFail("Expected baseline mismatch to fail closed")
    } catch LogseqProjectPageStore.StoreError.managedTasksChangedSinceLoad {
    }

    let task = try await loadedTask(taskID: taskID, graphRootURL: graphRootURL)
    XCTAssertEqual(task.title, "Concurrent")
    XCTAssertTrue(task.isCompleted)
  }

  func testCalendarWriteLoopGuardSuppressesOnlyMatchingRetainedWriteMarkers() throws {
    let taskID = UUID()
    let start = try XCTUnwrap(
      Self.calendar.date(from: .init(year: 2026, month: 4, day: 25, hour: 14, minute: 30))
    )
    let marker = try XCTUnwrap(
      RetainedCalendarBridgeWriteLoopGuard.marker(
        taskID: taskID,
        decision: .upsert(
          RetainedCalendarBridgeUpsertRequest(
            externalIdentifier: "event-1",
            title: "Timed",
            startDate: start,
            durationMinutes: 45
          )
        )
      )
    )
    let changedMarker = RetainedCalendarBridgeWriteMarker(
      taskID: taskID,
      operation: .upsertOwnedEvent,
      externalIdentifier: "event-1",
      title: "Timed",
      startDate: start,
      durationMinutes: 60
    )

    XCTAssertTrue(
      RetainedCalendarBridgeWriteLoopGuard.shouldSuppressEcho(
        marker: marker,
        activeMarkers: [marker]
      )
    )
    XCTAssertFalse(
      RetainedCalendarBridgeWriteLoopGuard.shouldSuppressEcho(
        marker: changedMarker,
        activeMarkers: [marker]
      )
    )
    XCTAssertNil(
      RetainedCalendarBridgeWriteLoopGuard.marker(taskID: taskID, decision: .noAction)
    )
    XCTAssertNil(
      RetainedCalendarBridgeWriteLoopGuard.marker(
        taskID: taskID,
        decision: .failClosed(.ambiguousOwnedEventIdentifier("event-1"))
      )
    )
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    return calendar
  }

  private func makeStore(graphRootURL: URL) -> LogseqProjectPageStore {
    LogseqProjectPageStore(
      pagesRootURL: graphRootURL.appendingPathComponent("pages", isDirectory: true)
    )
  }

  private func loadedTask(
    taskID: UUID,
    graphRootURL: URL
  ) async throws -> LogseqProjectPageStore.TaskRecord {
    let store = makeStore(graphRootURL: graphRootURL)
    let pages = try await store.loadProjectPagesInScope()
    let tasks = pages.flatMap(\.managedTasks) + pages.flatMap(\.externalTasks)
    return try XCTUnwrap(tasks.first { $0.taskID == taskID })
  }

  private func makeGraphRoot(named name: String) throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
  }
}

@MainActor
private final class FakeReminderProjectProvider: ReminderProjectProvider {
  var completionWrites: [CompletionWrite] = []
  var scheduleWrites: [ScheduleWrite] = []
  var recurrenceWrites: [RecurrenceWrite] = []
  var completionError: Error?
  var scheduleError: Error?
  var resolvesTask = true

  var reminderGateway: ReminderGateway? { nil }
  var defaultCalendarIdentifierForNewReminders: String? { nil }

  func requestAccess() async throws -> Bool {
    true
  }

  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch? {
    _ = identifiers
    return nil
  }

  func createProjectList(title: String) throws -> ReminderProjectListSnapshot {
    throw FakeReminderError.unexpectedCall("createProjectList")
  }

  func removeProjectList(identifier: String) throws {
    throw FakeReminderError.unexpectedCall("removeProjectList")
  }

  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot? {
    throw FakeReminderError.unexpectedCall("setProjectTitle")
  }

  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot? {
    throw FakeReminderError.unexpectedCall("setProjectColor")
  }

  func createTaskReminder(
    inProject identifier: String,
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    throw FakeReminderError.unexpectedCall("createTaskReminder")
  }

  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool {
    throw FakeReminderError.unexpectedCall("removeTaskReminder")
  }

  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot? {
    throw FakeReminderError.unexpectedCall("taskSnapshot")
  }

  func setTaskTitle(
    for task: ReminderTaskReference,
    title: String
  ) throws -> ReminderTaskRemoteMetadata? {
    throw FakeReminderError.unexpectedCall("setTaskTitle")
  }

  func setTaskCompletion(
    for task: ReminderTaskReference,
    isCompleted: Bool,
    completionDate: Date?
  ) throws -> ReminderTaskRemoteMetadata? {
    completionWrites.append(
      CompletionWrite(reference: task, isCompleted: isCompleted, completionDate: completionDate)
    )
    if let completionError {
      throw completionError
    }
    return metadata(for: task)
  }

  func setTaskReminderNote(
    for task: ReminderTaskReference,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    throw FakeReminderError.unexpectedCall("setTaskReminderNote")
  }

  func setTaskSchedule(
    for task: ReminderTaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws -> ReminderTaskRemoteMetadata? {
    scheduleWrites.append(
      ScheduleWrite(reference: task, dueDate: dueDate, hasExplicitTime: hasExplicitTime)
    )
    if let scheduleError {
      throw scheduleError
    }
    return metadata(for: task)
  }

  func setTaskRecurrence(
    for task: ReminderTaskReference,
    recurrenceRuleRaw: String?
  ) throws -> ReminderTaskRemoteMetadata? {
    recurrenceWrites.append(RecurrenceWrite(reference: task, recurrenceRuleRaw: recurrenceRuleRaw))
    return metadata(for: task)
  }

  func setTaskPresentation(
    for task: ReminderTaskReference,
    priority: Int
  ) throws -> ReminderTaskRemoteMetadata? {
    throw FakeReminderError.unexpectedCall("setTaskPresentation")
  }

  func moveTaskReminder(
    for task: ReminderTaskReference,
    toProject identifier: String
  ) throws -> ReminderTaskRemoteMetadata? {
    throw FakeReminderError.unexpectedCall("moveTaskReminder")
  }

  func restoreArchivedProject(
    _ project: ReminderArchivedProjectSnapshot
  ) throws -> ReminderProjectRestoreResult {
    throw FakeReminderError.unexpectedCall("restoreArchivedProject")
  }

  func removeArchivedProjectLists(
    _ projects: [ReminderProjectListReference]
  ) -> ReminderProjectCleanupResult {
    _ = projects
    return ReminderProjectCleanupResult(removedCount: 0, failedProjectIDs: [])
  }

  private func metadata(for task: ReminderTaskReference) -> ReminderTaskRemoteMetadata? {
    guard resolvesTask else { return nil }
    return ReminderTaskRemoteMetadata(
      identifier: task.reminderIdentifier ?? "reminder-\(task.taskID.uuidString)",
      externalIdentifier: task.reminderExternalIdentifier,
      modifiedAt: .now
    )
  }
}

private struct CompletionWrite {
  let reference: ReminderTaskReference
  let isCompleted: Bool
  let completionDate: Date?
}

private struct ScheduleWrite {
  let reference: ReminderTaskReference
  let dueDate: Date?
  let hasExplicitTime: Bool
}

private struct RecurrenceWrite {
  let reference: ReminderTaskReference
  let recurrenceRuleRaw: String?
}

private enum FakeReminderError: LocalizedError, Equatable {
  case unexpectedCall(String)
  case requestedFailure

  var errorDescription: String? {
    switch self {
    case .unexpectedCall(let function):
      return "Unexpected fake reminder call: \(function)"
    case .requestedFailure:
      return "Requested fake reminder failure"
    }
  }
}

private extension Array {
  var onlyValue: Element? {
    count == 1 ? self[0] : nil
  }
}
