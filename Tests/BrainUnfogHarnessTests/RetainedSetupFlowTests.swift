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

  func testHarnessEntitlementsAllowGraphFolderSelectionAndPersistence() throws {
    let entitlementsURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("import/BUF/BrainUnfogHarness.entitlements", isDirectory: false)
    let data = try Data(contentsOf: entitlementsURL)
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Bool]
    )

    XCTAssertEqual(plist["com.apple.security.app-sandbox"], true)
    XCTAssertEqual(plist["com.apple.security.files.user-selected.read-write"], true)
    XCTAssertEqual(plist["com.apple.security.files.bookmarks.app-scope"], true)
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

  func testConfigureGraphCreatesBufAndRunsReminderFirstBootstrap() async throws {
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
    XCTAssertTrue(appState.syncStarted)
    XCTAssertFalse(appState.isInitialSyncRunning)
    XCTAssertNotNil(appState.reminderSourceObserver)
    XCTAssertEqual(calendarService.requestAccessCallCount, 1)
    XCTAssertEqual(appState.syncStatus, "Refreshed (\(SyncReason.bootstrap.rawValue))")

    let configURL = graphRoot.appendingPathComponent("logseq/config.edn", isDirectory: false)
    let configContents = try String(contentsOf: configURL, encoding: .utf8)
    XCTAssertTrue(configContents.contains(":reminder_list_external_id"))
    XCTAssertTrue(configContents.contains(":reminder_external_id"))

    let cssURL = graphRoot.appendingPathComponent("logseq/custom.css", isDirectory: false)
    let cssContents = try String(contentsOf: cssURL, encoding: .utf8)
    XCTAssertTrue(cssContents.contains("a[data-ref=\"reminder_list_external_id\" i]"))
    XCTAssertTrue(cssContents.contains("a[data-ref=\"reminder_external_id\" i]"))
    XCTAssertTrue(cssContents.contains("Brain Unfog completed task filter"))
    XCTAssertFalse(appState.showsCompletedLogseqTasks)

    appState.setShowsCompletedLogseqTasks(true)
    let visibleCompletedCSS = try String(contentsOf: cssURL, encoding: .utf8)
    XCTAssertFalse(visibleCompletedCSS.contains("Brain Unfog completed task filter"))
  }

  func testConfigureGraphCanSwitchRootWithoutDeletingPreviousGraphData() async throws {
    let oldGraphRoot = try makeTemporaryDirectory(named: "old-graph")
    let newGraphRoot = try makeTemporaryDirectory(named: "new-graph")
    let oldPageURL = oldGraphRoot
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("Keep.md", isDirectory: false)
    try FileManager.default.createDirectory(
      at: oldPageURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "tags:: 프로젝트\n".write(to: oldPageURL, atomically: true, encoding: .utf8)

    let appState = makeAppState()

    await appState.configureLogseqGraphRoot(at: oldGraphRoot, activateWhenReady: true)
    await appState.configureLogseqGraphRoot(at: newGraphRoot, activateWhenReady: true)

    let expectedContainerRoot = newGraphRoot.appendingPathComponent(".buf", isDirectory: true)
    XCTAssertEqual(appState.logseqGraphRootURL?.standardizedFileURL, newGraphRoot.standardizedFileURL)
    XCTAssertEqual(appState.containerRootURL?.standardizedFileURL, expectedContainerRoot.standardizedFileURL)
    XCTAssertEqual(UserDefaults.standard.string(forKey: AppState.logseqGraphRootPathKey), newGraphRoot.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: oldPageURL.path))
  }

  func testDeniedInitialSyncConsentBlocksStartupSync() async throws {
    let graphRoot = try makeTemporaryDirectory(named: "graph")
    let appState = makeAppState()

    await appState.configureLogseqGraphRoot(at: graphRoot, activateWhenReady: true)
    appState.setInitialSyncConsentPreference(granted: false, activateWhenReady: false)

    appState.requestStartupSyncIfNeeded()

    XCTAssertTrue(appState.hasCompletedInitialSetup)
    XCTAssertFalse(appState.hasInitialSyncConsent)
    XCTAssertTrue(appState.syncStarted)
    XCTAssertFalse(appState.isInitialSyncRunning)
    XCTAssertEqual(appState.syncStatus, "Refresh paused")
  }

  func testStartupSyncUsesReminderFirstBootstrapPolicy() async throws {
    let graphRoot = try makeTemporaryDirectory(named: "graph")
    let appState = makeAppState()

    await appState.configureLogseqGraphRoot(at: graphRoot, activateWhenReady: true)
    appState.syncStatus = "Ready"
    appState.syncStarted = false

    appState.requestStartupSyncIfNeeded()
    try await Task.sleep(nanoseconds: 120_000_000)

    XCTAssertTrue(appState.syncStarted)
    XCTAssertEqual(appState.syncStatus, "Refreshed (\(SyncReason.bootstrap.rawValue))")
  }

  func testBootstrapSyncPolicyIsReminderAuthoritativeButEventSyncUsesBaselineMerge() {
    let appState = makeAppState()

    XCTAssertEqual(
      appState.reminderImportConflictPolicy(for: .bootstrap),
      .remindersAuthoritative
    )
    XCTAssertEqual(
      appState.reminderImportConflictPolicy(for: .eventStoreChanged),
      .mergeWithBaseline
    )
    XCTAssertEqual(
      appState.reminderImportConflictPolicy(for: .manual),
      .mergeWithBaseline
    )
    XCTAssertFalse(appState.shouldProvisionFromLogseqAfterImport(reason: .bootstrap))
    XCTAssertFalse(appState.shouldProvisionFromLogseqAfterImport(reason: .eventStoreChanged))
    XCTAssertTrue(appState.shouldProvisionFromLogseqAfterImport(reason: .manual))
    XCTAssertFalse(appState.shouldProvisionFromLogseqAfterImport(reason: .periodic))
  }

  func testQueuedSyncRequestsCoalesceToHighestPriorityReason() {
    let appState = makeAppState()

    appState.queueReminderSourceRefresh(reason: .periodic)
    appState.queueReminderSourceRefresh(reason: .eventStoreChanged)
    appState.queueReminderSourceRefresh(reason: .manual)
    appState.queueReminderSourceRefresh(reason: .periodic)

    XCTAssertEqual(appState.pendingReminderSourceRefreshReason, .manual)
  }

  func testLogseqAuthoredReminderPushSuppressesImmediateEventStoreEchoOnly() {
    let appState = makeAppState()
    let now = Date(timeIntervalSince1970: 1_000)

    appState.recordLogseqAuthoredReminderPush(now: now)

    XCTAssertTrue(
      appState.shouldSuppressReminderSourceRefresh(
        reason: .eventStoreChanged,
        now: now.addingTimeInterval(1)
      )
    )
    XCTAssertFalse(
      appState.shouldSuppressReminderSourceRefresh(
        reason: .manual,
        now: now.addingTimeInterval(1)
      )
    )
    XCTAssertFalse(
      appState.shouldSuppressReminderSourceRefresh(
        reason: .eventStoreChanged,
        now: now.addingTimeInterval(30)
      )
    )
    appState.logseqAuthoredReminderEchoRefreshTask?.cancel()
  }

  func testExternalReminderInvalidationRunsRetainedReconciliation() async throws {
    let graphRoot = try makeTemporaryDirectory(named: "graph")
    let appState = makeAppState()

    await appState.configureLogseqGraphRoot(at: graphRoot, activateWhenReady: true)
    let didRefresh = await appState.handleExternalReminderTaskInvalidation(
      ownerIDs: ["task-ext-1"],
      changedFields: [.title],
      waitForEditorIdle: false
    )

    XCTAssertTrue(didRefresh)
    XCTAssertTrue(appState.syncStarted)
    XCTAssertEqual(appState.syncStatus, "Refreshed (\(SyncReason.eventStoreChanged.rawValue))")
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
      AppState.showCompletedLogseqTasksKey,
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
