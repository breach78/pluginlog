import XCTest
@testable import BrainUnfogHarness

@MainActor
final class RetainedCalendarEventKitBridgeTests: XCTestCase {
  func testCreateWritesCalendarIdentityBackToLogseqAndReturnsEchoMarker() async throws {
    let fixture = try await makeGraph(
      calendarEventExternalIdentifier: nil,
      date: "2026-04-25 14:30",
      duration: "45"
    )
    let writer = FakeRetainedCalendarEventWriter()
    writer.nextExternalIdentifier = "event-new"
    let decision = RetainedCalendarBridgeDecision.upsert(
      RetainedCalendarBridgeUpsertRequest(
        externalIdentifier: nil,
        title: "Prepare launch",
        startDate: try XCTUnwrap(LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date),
        durationMinutes: 45
      )
    )

    let result = try await RetainedCalendarEventKitBridge.apply(
      commandResult: commandResult(fixture: fixture, decision: decision),
      graphRootURL: fixture.graphRootURL,
      eventWriter: writer
    )

    let task = try await loadedTask(taskID: fixture.taskID, graphRootURL: fixture.graphRootURL)
    XCTAssertEqual(task.calendarEventExternalIdentifier, "event-new")
    XCTAssertEqual(writer.upserts.count, 1)
    XCTAssertEqual(result.calendarEventExternalIdentifier, "event-new")
    XCTAssertEqual(result.calendarWriteMarker?.externalIdentifier, "event-new")
    XCTAssertTrue(
      RetainedCalendarBridgeWriteLoopGuard.shouldSuppressEcho(
        marker: try XCTUnwrap(result.calendarWriteMarker),
        activeMarkers: [try XCTUnwrap(result.calendarWriteMarker)]
      )
    )
  }

  func testUpdateRequiresStableExistingCalendarIdentity() async throws {
    let fixture = try await makeGraph(
      calendarEventExternalIdentifier: "event-1",
      date: "2026-04-25 14:30",
      duration: "45"
    )
    let writer = FakeRetainedCalendarEventWriter()
    writer.existingExternalIdentifiers = ["event-1"]
    let decision = RetainedCalendarBridgeDecision.upsert(
      RetainedCalendarBridgeUpsertRequest(
        externalIdentifier: "event-1",
        title: "Prepare launch",
        startDate: try XCTUnwrap(LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date),
        durationMinutes: 45
      )
    )

    let result = try await RetainedCalendarEventKitBridge.apply(
      commandResult: commandResult(fixture: fixture, decision: decision),
      graphRootURL: fixture.graphRootURL,
      eventWriter: writer
    )

    let task = try await loadedTask(taskID: fixture.taskID, graphRootURL: fixture.graphRootURL)
    XCTAssertEqual(task.calendarEventExternalIdentifier, "event-1")
    XCTAssertEqual(writer.upserts.map(\.request.externalIdentifier), ["event-1"])
    XCTAssertEqual(result.calendarEventExternalIdentifier, "event-1")
  }

  func testStaleRetainedDecisionBlocksBeforeEventKitMutation() async throws {
    let fixture = try await makeGraph(
      calendarEventExternalIdentifier: "event-1",
      date: "2026-04-25 14:30",
      duration: "45"
    )
    let writer = FakeRetainedCalendarEventWriter()
    writer.existingExternalIdentifiers = ["event-1"]
    let staleDecision = RetainedCalendarBridgeDecision.removeOwnedEvent(externalIdentifier: "event-1")

    do {
      _ = try await RetainedCalendarEventKitBridge.apply(
        commandResult: commandResult(fixture: fixture, decision: staleDecision),
        graphRootURL: fixture.graphRootURL,
        eventWriter: writer
      )
      XCTFail("Expected stale decision to fail closed")
    } catch RetainedCalendarBridgeApplyError.staleCalendarDecision(let expected, let actual) {
      XCTAssertEqual(expected, staleDecision)
      guard case .upsert = actual else {
        XCTFail("Expected current retained decision to be upsert")
        return
      }
    }

    XCTAssertTrue(writer.upserts.isEmpty)
    XCTAssertTrue(writer.removals.isEmpty)
    let task = try await loadedTask(taskID: fixture.taskID, graphRootURL: fixture.graphRootURL)
    XCTAssertEqual(task.calendarEventExternalIdentifier, "event-1")
  }

  func testBridgeMarkerUsesNormalizedWriterOutput() async throws {
    let fixture = try await makeGraph(
      calendarEventExternalIdentifier: nil,
      date: "2026-04-25 14:30",
      duration: "1"
    )
    let writer = FakeRetainedCalendarEventWriter()
    writer.nextExternalIdentifier = "event-new"
    let decision = RetainedCalendarBridgeDecision.upsert(
      RetainedCalendarBridgeUpsertRequest(
        externalIdentifier: nil,
        title: "Prepare launch",
        startDate: try XCTUnwrap(LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date),
        durationMinutes: 1
      )
    )

    let result = try await RetainedCalendarEventKitBridge.apply(
      commandResult: commandResult(fixture: fixture, decision: decision),
      graphRootURL: fixture.graphRootURL,
      eventWriter: writer
    )

    XCTAssertEqual(result.calendarWriteMarker?.durationMinutes, 5)
    XCTAssertEqual(
      result.calendarBridgeDecision,
      .upsert(
        RetainedCalendarBridgeUpsertRequest(
          externalIdentifier: "event-new",
          title: "Prepare launch",
          startDate: try XCTUnwrap(LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date),
          durationMinutes: 5
        )
      )
    )
  }

  func testRemoveClearsCalendarIdentityOnlyAfterOwnedEventDeleteSucceeds() async throws {
    let fixture = try await makeGraph(
      calendarEventExternalIdentifier: "event-1",
      date: "2026-04-25",
      duration: nil
    )
    let writer = FakeRetainedCalendarEventWriter()
    writer.existingExternalIdentifiers = ["event-1"]
    let decision = RetainedCalendarBridgeDecision.removeOwnedEvent(externalIdentifier: "event-1")

    let result = try await RetainedCalendarEventKitBridge.apply(
      commandResult: commandResult(fixture: fixture, decision: decision),
      graphRootURL: fixture.graphRootURL,
      eventWriter: writer
    )

    let task = try await loadedTask(taskID: fixture.taskID, graphRootURL: fixture.graphRootURL)
    XCTAssertNil(task.calendarEventExternalIdentifier)
    XCTAssertEqual(writer.removals, ["event-1"])
    XCTAssertEqual(result.calendarBridgeDecision, .noAction)
  }

  func testMissingOwnedEventFailsClosedAndPreservesCalendarIdentity() async throws {
    let fixture = try await makeGraph(
      calendarEventExternalIdentifier: "event-missing",
      date: "2026-04-25",
      duration: nil
    )
    let writer = FakeRetainedCalendarEventWriter()
    let decision = RetainedCalendarBridgeDecision.removeOwnedEvent(externalIdentifier: "event-missing")

    do {
      _ = try await RetainedCalendarEventKitBridge.apply(
        commandResult: commandResult(fixture: fixture, decision: decision),
        graphRootURL: fixture.graphRootURL,
        eventWriter: writer
      )
      XCTFail("Expected missing owned event to fail closed")
    } catch RetainedCalendarBridgeApplyError.ownedEventMissing(let externalIdentifier) {
      XCTAssertEqual(externalIdentifier, "event-missing")
    }

    let task = try await loadedTask(taskID: fixture.taskID, graphRootURL: fixture.graphRootURL)
    XCTAssertEqual(task.calendarEventExternalIdentifier, "event-missing")
  }

  func testDuplicateRetainedCalendarIdentityBlocksBeforeEventKitMutation() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedCalendarDuplicateGraph")
    let projectID = UUID()
    let taskID = UUID()
    let duplicateTaskID = UUID()
    let store = makeStore(graphRootURL: graphRootURL)
    try await store.upsertPage(
      .init(projectID: projectID, title: "Launch", reminderListExternalIdentifier: nil),
      noteMarkdown: "",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "A",
          isCompleted: false,
          date: "2026-04-25",
          duration: nil,
          repeatRule: nil,
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: "event-1"
        ),
        .init(
          taskID: duplicateTaskID,
          title: "B",
          isCompleted: false,
          date: "2026-04-26",
          duration: nil,
          repeatRule: nil,
          reminderExternalIdentifier: "reminder-2",
          calendarEventExternalIdentifier: "event-1"
        ),
      ]
    )
    let writer = FakeRetainedCalendarEventWriter()
    writer.existingExternalIdentifiers = ["event-1"]

    do {
      _ = try await RetainedCalendarEventKitBridge.apply(
        commandResult: RetainedTaskCommandResult(
          projectID: projectID,
          taskID: taskID,
          calendarBridgeDecision: .removeOwnedEvent(externalIdentifier: "event-1"),
          calendarWriteMarker: RetainedCalendarBridgeWriteLoopGuard.marker(
            taskID: taskID,
            decision: .removeOwnedEvent(externalIdentifier: "event-1")
          )
        ),
        graphRootURL: graphRootURL,
        eventWriter: writer
      )
      XCTFail("Expected duplicate retained event identity to fail closed")
    } catch RetainedCalendarBridgeApplyError.retainedProjectionFailed {
    }

    XCTAssertTrue(writer.upserts.isEmpty)
    XCTAssertTrue(writer.removals.isEmpty)
  }

  func testForeignOrAmbiguousWriterErrorPreservesCalendarIdentity() async throws {
    let fixture = try await makeGraph(
      calendarEventExternalIdentifier: "event-foreign",
      date: "2026-04-25 14:30",
      duration: "45"
    )
    let writer = FakeRetainedCalendarEventWriter()
    writer.upsertError = RetainedCalendarEventWriterError.foreignEvent("event-foreign")
    let decision = RetainedCalendarBridgeDecision.upsert(
      RetainedCalendarBridgeUpsertRequest(
        externalIdentifier: "event-foreign",
        title: "Prepare launch",
        startDate: try XCTUnwrap(LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date),
        durationMinutes: 45
      )
    )

    do {
      _ = try await RetainedCalendarEventKitBridge.apply(
        commandResult: commandResult(fixture: fixture, decision: decision),
        graphRootURL: fixture.graphRootURL,
        eventWriter: writer
      )
      XCTFail("Expected foreign event to fail closed")
    } catch RetainedCalendarEventWriterError.foreignEvent(let externalIdentifier) {
      XCTAssertEqual(externalIdentifier, "event-foreign")
    }

    let task = try await loadedTask(taskID: fixture.taskID, graphRootURL: fixture.graphRootURL)
    XCTAssertEqual(task.calendarEventExternalIdentifier, "event-foreign")
  }

  func testCreatedEventRollsBackWhenLogseqIdentityPersistenceFails() async throws {
    let fixture = try await makeGraph(
      calendarEventExternalIdentifier: nil,
      date: "2026-04-25 14:30",
      duration: "45"
    )
    let writer = FakeRetainedCalendarEventWriter()
    writer.nextExternalIdentifier = "event-new"
    writer.onUpsert = {
      let store = self.makeStore(graphRootURL: fixture.graphRootURL)
      let pages = try await store.loadProjectPagesInScope()
      let page = try XCTUnwrap(pages.onlyValue)
      var managedTasks = page.managedTasks
      managedTasks[0].title = "Concurrent edit"
      try await store.updateManagedTasks(
        in: page,
        expectedManagedTasks: page.managedTasks,
        managedTasks: managedTasks
      )
    }
    let decision = RetainedCalendarBridgeDecision.upsert(
      RetainedCalendarBridgeUpsertRequest(
        externalIdentifier: nil,
        title: "Prepare launch",
        startDate: try XCTUnwrap(LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date),
        durationMinutes: 45
      )
    )

    do {
      _ = try await RetainedCalendarEventKitBridge.apply(
        commandResult: commandResult(fixture: fixture, decision: decision),
        graphRootURL: fixture.graphRootURL,
        eventWriter: writer
      )
      XCTFail("Expected Logseq baseline failure")
    } catch LogseqProjectPageStore.StoreError.managedTasksChangedSinceLoad {
    }

    XCTAssertEqual(writer.removals, ["event-new"])
    let task = try await loadedTask(taskID: fixture.taskID, graphRootURL: fixture.graphRootURL)
    XCTAssertNil(task.calendarEventExternalIdentifier)
    XCTAssertEqual(task.title, "Concurrent edit")
  }

  func testBridgeMarkerSuppressesMatchingEchoOnly() throws {
    let taskID = UUID()
    let start = try XCTUnwrap(LogseqReminderPropertyCodec.decodeDate("2026-04-25 14:30")?.date)
    let decision = RetainedCalendarBridgeDecision.upsert(
      RetainedCalendarBridgeUpsertRequest(
        externalIdentifier: "event-1",
        title: "Prepare launch",
        startDate: start,
        durationMinutes: 45
      )
    )
    let marker = try XCTUnwrap(
      RetainedCalendarBridgeWriteLoopGuard.marker(taskID: taskID, decision: decision)
    )
    let changedMarker = RetainedCalendarBridgeWriteMarker(
      taskID: taskID,
      operation: .upsertOwnedEvent,
      externalIdentifier: "event-1",
      title: "Prepare launch",
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
  }

  private struct Fixture {
    let graphRootURL: URL
    let projectID: UUID
    let taskID: UUID
  }

  private func makeGraph(
    calendarEventExternalIdentifier: String?,
    date: String?,
    duration: String?
  ) async throws -> Fixture {
    let graphRootURL = try makeGraphRoot(named: "RetainedCalendarBridgeGraph")
    let projectID = UUID()
    let taskID = UUID()
    let store = makeStore(graphRootURL: graphRootURL)
    try await store.upsertPage(
      .init(projectID: projectID, title: "Launch", reminderListExternalIdentifier: nil),
      noteMarkdown: "",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Prepare launch",
          isCompleted: false,
          date: date,
          duration: duration,
          repeatRule: "weekly",
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: calendarEventExternalIdentifier
        )
      ]
    )
    return Fixture(graphRootURL: graphRootURL, projectID: projectID, taskID: taskID)
  }

  private func commandResult(
    fixture: Fixture,
    decision: RetainedCalendarBridgeDecision
  ) -> RetainedTaskCommandResult {
    RetainedTaskCommandResult(
      projectID: fixture.projectID,
      taskID: fixture.taskID,
      calendarBridgeDecision: decision,
      calendarWriteMarker: RetainedCalendarBridgeWriteLoopGuard.marker(
        taskID: fixture.taskID,
        decision: decision
      )
    )
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
    let tasks = pages.flatMap(\.managedTasks)
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
private final class FakeRetainedCalendarEventWriter: RetainedCalendarEventWriting {
  var existingExternalIdentifiers: Set<String> = []
  var nextExternalIdentifier = "event-new"
  var upsertError: Error?
  var removeError: Error?
  var onUpsert: (() async throws -> Void)?
  var upserts: [(request: RetainedCalendarBridgeUpsertRequest, marker: RetainedCalendarBridgeWriteMarker?)] = []
  var removals: [String] = []

  func upsertOwnedEvent(
    _ request: RetainedCalendarBridgeUpsertRequest,
    marker: RetainedCalendarBridgeWriteMarker?
  ) async throws -> RetainedCalendarEventWriteResult {
    upserts.append((request, marker))
    if let upsertError {
      throw upsertError
    }
    let externalIdentifier: String
    if let existing = request.externalIdentifier {
      guard existingExternalIdentifiers.contains(existing) else {
        throw RetainedCalendarEventWriterError.ownedEventMissing(existing)
      }
      externalIdentifier = existing
    } else {
      externalIdentifier = nextExternalIdentifier
      existingExternalIdentifiers.insert(externalIdentifier)
    }
    try await onUpsert?()
    let trimmedTitle = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return RetainedCalendarEventWriteResult(
      externalIdentifier: externalIdentifier,
      title: trimmedTitle.isEmpty ? "Untitled Event" : trimmedTitle,
      startDate: request.startDate,
      durationMinutes: max(5, request.durationMinutes)
    )
  }

  func removeOwnedEvent(
    externalIdentifier: String,
    marker _: RetainedCalendarBridgeWriteMarker?
  ) async throws -> Bool {
    if let removeError {
      throw removeError
    }
    guard existingExternalIdentifiers.remove(externalIdentifier) != nil else {
      return false
    }
    removals.append(externalIdentifier)
    return true
  }
}

private extension Array {
  var onlyValue: Element? {
    count == 1 ? self[0] : nil
  }
}
