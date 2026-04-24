import XCTest
@testable import BrainUnfogHarness

@MainActor
final class RetainedCalendarEventKitBridgeTests: XCTestCase {
  func testApplyIsNoOpForLegacyUpsertDecision() async throws {
    let fixture = makeFixture()
    let writer = FakeRetainedCalendarEventWriter()
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
      graphRootURL: URL(fileURLWithPath: "/tmp/unused", isDirectory: true),
      eventWriter: writer
    )

    XCTAssertEqual(result.projectID, fixture.projectID)
    XCTAssertEqual(result.taskID, fixture.taskID)
    XCTAssertNil(result.calendarEventExternalIdentifier)
    XCTAssertEqual(result.calendarBridgeDecision, .noAction)
    XCTAssertNil(result.calendarWriteMarker)
    XCTAssertTrue(writer.upserts.isEmpty)
    XCTAssertTrue(writer.removals.isEmpty)
  }

  func testApplyIsNoOpForLegacyRemoveDecision() async throws {
    let fixture = makeFixture()
    let writer = FakeRetainedCalendarEventWriter()
    let decision = RetainedCalendarBridgeDecision.removeOwnedEvent(externalIdentifier: "event-1")

    let result = try await RetainedCalendarEventKitBridge.apply(
      commandResult: commandResult(fixture: fixture, decision: decision),
      graphRootURL: nil,
      eventWriter: writer
    )

    XCTAssertEqual(result.calendarBridgeDecision, .noAction)
    XCTAssertNil(result.calendarWriteMarker)
    XCTAssertTrue(writer.upserts.isEmpty)
    XCTAssertTrue(writer.removals.isEmpty)
  }

  func testApplyIsNoOpForLegacyFailClosedDecision() async throws {
    let fixture = makeFixture()
    let writer = FakeRetainedCalendarEventWriter()
    let decision = RetainedCalendarBridgeDecision.failClosed(.unmanagedTaskIdentity)

    let result = try await RetainedCalendarEventKitBridge.apply(
      commandResult: commandResult(fixture: fixture, decision: decision),
      graphRootURL: nil,
      eventWriter: writer
    )

    XCTAssertEqual(result.calendarBridgeDecision, .noAction)
    XCTAssertNil(result.calendarWriteMarker)
    XCTAssertTrue(writer.upserts.isEmpty)
    XCTAssertTrue(writer.removals.isEmpty)
  }

  func testBridgeMarkerSuppressesMatchingEchoOnlyForLegacyMarkers() throws {
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
    let projectID: UUID
    let taskID: UUID
  }

  private func makeFixture() -> Fixture {
    Fixture(projectID: UUID(), taskID: UUID())
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
}

@MainActor
private final class FakeRetainedCalendarEventWriter: RetainedCalendarEventWriting {
  var upserts: [(request: RetainedCalendarBridgeUpsertRequest, marker: RetainedCalendarBridgeWriteMarker?)] = []
  var removals: [String] = []

  func upsertOwnedEvent(
    _ request: RetainedCalendarBridgeUpsertRequest,
    marker: RetainedCalendarBridgeWriteMarker?
  ) async throws -> RetainedCalendarEventWriteResult {
    upserts.append((request, marker))
    return RetainedCalendarEventWriteResult(externalIdentifier: "unexpected")
  }

  func removeOwnedEvent(
    externalIdentifier: String,
    marker _: RetainedCalendarBridgeWriteMarker?
  ) async throws -> Bool {
    removals.append(externalIdentifier)
    return true
  }
}
