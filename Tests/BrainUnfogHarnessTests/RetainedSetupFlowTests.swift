import Combine
import XCTest
@testable import BrainUnfogHarness

@MainActor
final class RetainedSetupFlowTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func setUp() async throws {
    try await super.setUp()
    clearRetainedSetupDefaults()
  }

  override func tearDown() async throws {
    clearRetainedSetupDefaults()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testLaunchDoesNotFallbackToOldContainerWhenGraphLocalBufIsDamaged() async throws {
    let storageCoordinator = LocalStorageCoordinator()
    let oldContainerRoot = try makeTemporaryDirectory(named: "old-container")
    try await storageCoordinator.initializeContainer(at: oldContainerRoot)

    let graphRoot = try makeTemporaryDirectory(named: "graph")
    let damagedBufRoot = graphRoot.appendingPathComponent(".buf", isDirectory: true)
    try FileManager.default.createDirectory(
      at: damagedBufRoot.appendingPathComponent("data", isDirectory: true),
      withIntermediateDirectories: true
    )
    FileManager.default.createFile(
      atPath: damagedBufRoot.appendingPathComponent("data/main.sqlite").path,
      contents: nil
    )
    UserDefaults.standard.set(graphRoot.path, forKey: AppState.logseqGraphRootPathKey)

    let appState = makeAppState(storageCoordinator: storageCoordinator)

    await appState.launch()

    XCTAssertNil(appState.containerRootURL)
    XCTAssertNil(appState.modelContainer)
    XCTAssertNotEqual(appState.containerRootURL?.standardizedFileURL, oldContainerRoot.standardizedFileURL)
    XCTAssertEqual(appState.logseqGraphRootURL?.standardizedFileURL, graphRoot.standardizedFileURL)
    XCTAssertNotNil(appState.errorMessage)
  }

  func testConfigureGraphCreatesBufButDoesNotStartStartupSync() async throws {
    let graphRoot = try makeTemporaryDirectory(named: "graph")
    let calendarService = RecordingScheduleCalendarService()
    let appState = makeAppState(calendarService: calendarService)

    await appState.configureLogseqGraphRoot(at: graphRoot, activateWhenReady: true)

    let expectedContainerRoot = graphRoot.appendingPathComponent(".buf", isDirectory: true)
    XCTAssertEqual(appState.containerRootURL?.standardizedFileURL, expectedContainerRoot.standardizedFileURL)
    for legacyDirectoryName in ["attachments", "notes", "cache", "exports"] {
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: expectedContainerRoot.appendingPathComponent(legacyDirectoryName).path
        ),
        "Retained setup must not create legacy \(legacyDirectoryName) storage."
      )
    }
    XCTAssertNotNil(appState.modelContainer)
    XCTAssertTrue(appState.hasInitialSyncConsent)
    XCTAssertTrue(appState.hasSyncConsentDecision)
    XCTAssertFalse(appState.syncStarted)
    XCTAssertFalse(appState.isInitialSyncRunning)
    XCTAssertEqual(calendarService.requestAccessCallCount, 1)
  }

  private func makeAppState(
    storageCoordinator: LocalStorageCoordinator = LocalStorageCoordinator(),
    calendarService: RecordingScheduleCalendarService = RecordingScheduleCalendarService()
  ) -> AppState {
    AppState(
      storageCoordinator: storageCoordinator,
      reminderGateway: PreviewReminderGateway(),
      calendarServiceRegistry: .live(scheduleCalendarService: calendarService)
    )
  }

  private func makeTemporaryDirectory(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("RetainedSetupFlowTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root.deletingLastPathComponent())
    return root
  }

  private func clearRetainedSetupDefaults() {
    let defaults = UserDefaults.standard
    [
      AppState.initialSyncConsentGrantedKey,
      AppState.initialSyncConsentDecidedKey,
      AppState.logseqGraphBookmarkDataKey,
      AppState.logseqGraphRootPathKey,
      "container.bookmarkData",
      "container.rootPath",
    ].forEach(defaults.removeObject(forKey:))
  }
}

@MainActor
private final class RecordingScheduleCalendarService: ScheduleCalendarServicing {
  private let overlaySubject = CurrentValueSubject<ScheduleCalendarOverlayProjection, Never>(.empty)
  private let invalidationSubject = PassthroughSubject<[String], Never>()

  private(set) var requestAccessCallCount = 0

  var overlayProjection: ScheduleCalendarOverlayProjection { .empty }
  var overlayProjectionPublisher: AnyPublisher<ScheduleCalendarOverlayProjection, Never> {
    overlaySubject.eraseToAnyPublisher()
  }
  var ownedEventInvalidationPublisher: AnyPublisher<[String], Never> {
    invalidationSubject.eraseToAnyPublisher()
  }
  var calendars: [ScheduleCalendarSource] { [] }
  var events: [ScheduleCalendarEvent] { [] }
  var visibleEvents: [ScheduleCalendarEvent] { [] }
  var calendarsSignature: Int { 0 }
  var visibleEventsSignature: Int { 0 }
  var accessDenied: Bool { false }

  func requestCalendarAccessOnceIfNeeded() async -> Bool {
    requestAccessCallCount += 1
    return true
  }

  func filteredEvents() -> [ScheduleCalendarEvent] { [] }
  func isCalendarVisible(_ calendarIdentifier: String) -> Bool { true }
  func isCalendarBackgroundOnly(_ calendarIdentifier: String) -> Bool { false }
  func toggleCalendarVisibility(_ calendarIdentifier: String) {}
  func toggleCalendarBackgroundOnly(_ calendarIdentifier: String) {}
  func foregroundVisibleEvents() -> [ScheduleCalendarEvent] { [] }
  func backgroundVisibleEvents() -> [ScheduleCalendarEvent] { [] }
  func refresh(visibleRange: ClosedRange<Date>) async {}
  func refresh(visibleRange: ClosedRange<Date>, force: Bool) async {}
  func reveal(_ event: ScheduleCalendarEvent) {}

  func applyTimingChange(
    to event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    event
  }

  func delete(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> DeletedScheduleCalendarEventSnapshot {
    throw ScheduleCalendarEditError.eventNotFound
  }

  func restoreDeletedEvent(_ snapshot: DeletedScheduleCalendarEventSnapshot) async throws
    -> ScheduleCalendarEvent
  {
    throw ScheduleCalendarEditError.eventNotFound
  }

  func applyOwnerFieldWrite(_ write: CalendarEventFieldsWrite) async throws -> ScheduleCalendarEvent {
    write.event
  }

  func ensureOwnedCalendar() async throws -> OwnedScheduleCalendarDescriptor {
    OwnedScheduleCalendarDescriptor(calendarIdentifier: "owned", title: "Owned", colorHex: nil)
  }

  func resolveOwnedEvent(
    externalIdentifier: String,
    calendarIdentifier: String?
  ) async -> ScheduleCalendarEvent? {
    nil
  }

  func upsertOwnedEvent(
    _ request: OwnedScheduleCalendarEventUpsertRequest,
    calendarIdentifier: String
  ) async throws -> ScheduleCalendarEvent {
    throw ScheduleCalendarEditError.eventNotFound
  }

  func removeOwnedEvent(
    externalIdentifier: String,
    calendarIdentifier: String
  ) async throws -> Bool {
    false
  }

  func resolveEvent(ownerID: String) async -> ScheduleCalendarEvent? {
    nil
  }
}
