import Combine
@preconcurrency import EventKit
import XCTest
@testable import BrainUnfogHarness

@MainActor
final class RetainedSetupFlowTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func setUp() async throws {
    try await super.setUp()
    TaskIdentityBridgeStore.reset()
    clearRetainedSetupDefaults()
  }

  override func tearDown() async throws {
    clearRetainedSetupDefaults()
    TaskIdentityBridgeStore.reset()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testHarnessEntitlementsAllowVaultFolderSelectionAndPersistence() throws {
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

  func testConfigureObsidianVaultCreatesBufRawProjectsAndRunsReminderFirstBootstrap() async throws {
    let vaultRoot = try makeVaultRoot()
    let gateway = SetupReminderGateway()
    let calendarService = RecordingScheduleCalendarService()
    let appState = makeAppState(reminderGateway: gateway, calendarService: calendarService)

    await appState.configureObsidianVault(at: vaultRoot, activateWhenReady: true)

    let expectedContainerRoot = vaultRoot.appendingPathComponent(".buf", isDirectory: true)
    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    XCTAssertEqual(appState.obsidianVaultRootURL?.standardizedFileURL, vaultRoot.standardizedFileURL)
    XCTAssertEqual(appState.containerRootURL?.standardizedFileURL, expectedContainerRoot.standardizedFileURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: expectedContainerRoot.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: projectsRoot.path))
    let helperPluginRoot = vaultRoot
      .appendingPathComponent(".obsidian", isDirectory: true)
      .appendingPathComponent("plugins", isDirectory: true)
      .appendingPathComponent(ObsidianHelperPluginInstaller.pluginIdentifier, isDirectory: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: helperPluginRoot.path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: helperPluginRoot
          .appendingPathComponent("manifest.json", isDirectory: false)
          .path
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: vaultRoot
          .appendingPathComponent(".obsidian", isDirectory: true)
          .appendingPathComponent("community-plugins.json", isDirectory: false)
          .path
      )
    )
    XCTAssertNotNil(appState.reminderSourceObserver)
    XCTAssertNotNil(appState.obsidianProjectDirectoryWatcher)
    XCTAssertTrue(appState.hasCompletedInitialSetup)
    XCTAssertTrue(appState.syncStarted)
    XCTAssertEqual(calendarService.requestAccessCallCount, 1)
    XCTAssertEqual(gateway.writeCallCount, 0)
    XCTAssertEqual(UserDefaults.standard.string(forKey: AppState.obsidianVaultRootPathKey), vaultRoot.path)

    let projectFiles = try FileManager.default.contentsOfDirectory(
      at: projectsRoot,
      includingPropertiesForKeys: nil
    )
    let projectFile = try XCTUnwrap(projectFiles.first { $0.pathExtension == "md" })
    let markdown = try String(contentsOf: projectFile, encoding: .utf8)
    let taskIdentifier = try XCTUnwrap(
      gateway.reminder.calendarItemExternalIdentifier ?? gateway.reminder.calendarItemIdentifier
    )
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: gateway.calendar.calendarIdentifier)
    let taskID = ReminderProjectionIdentity.taskID(for: taskIdentifier)
    XCTAssertTrue(markdown.contains("reminder_list_external_id:"))
    XCTAssertTrue(markdown.contains("reminder_external_id"))
    XCTAssertTrue(markdown.contains("- [ ] Imported task"))
    XCTAssertTrue(markdown.contains("note line"))
    XCTAssertEqual(TaskIdentityBridgeStore.projectTitle(for: projectID), "Imported list")
    XCTAssertEqual(TaskIdentityBridgeStore.taskRecord(for: taskID)?.title, "Imported task")
  }

  func testConfigureObsidianVaultRejectsCandidateWithoutObsidianDirectoryWithoutDirtyingFolder()
    async throws
  {
    let vaultRoot = try makeTemporaryDirectory(named: "not-a-vault")
    let appState = makeAppState(reminderGateway: SetupReminderGateway())

    await appState.configureObsidianVault(at: vaultRoot, activateWhenReady: true)

    XCTAssertNil(appState.obsidianVaultRootURL)
    XCTAssertNil(appState.containerRootURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent(".obsidian").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent(".buf").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent("raw").path))
    XCTAssertNil(UserDefaults.standard.string(forKey: AppState.obsidianVaultRootPathKey))
    XCTAssertNil(UserDefaults.standard.string(forKey: "container.rootPath"))
    XCTAssertNotNil(appState.errorMessage)
  }

  func testConfigureObsidianVaultReconcilesExistingLocalOnlyProjectNoteWithoutBootstrapAlert()
    async throws
  {
    let vaultRoot = try makeVaultRoot()
    let gateway = SetupReminderGateway()
    let taskIdentifier = try XCTUnwrap(
      gateway.reminder.calendarItemExternalIdentifier ?? gateway.reminder.calendarItemIdentifier
    )
    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    let noteURL = projectsRoot.appendingPathComponent("Imported list.md", isDirectory: false)
    let originalMarkdown = """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: \(gateway.calendar.calendarIdentifier)
      ---
      Local prose that must stay.
      - [ ] Imported task
        %% brain-unfog: {"reminder_external_id":"\(taskIdentifier)"} %%
        - note line

      """
    try originalMarkdown.write(to: noteURL, atomically: true, encoding: .utf8)
    let appState = makeAppState(reminderGateway: gateway)

    await appState.configureObsidianVault(at: vaultRoot, activateWhenReady: true)

    let afterMarkdown = try String(contentsOf: noteURL, encoding: .utf8)
    XCTAssertEqual(
      afterMarkdown,
      """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: \(gateway.calendar.calendarIdentifier)
      완료 가리기: true
      ---
      Local prose that must stay.
      - [ ] Imported task
        %% brain-unfog: {"reminder_external_id":"\(taskIdentifier)"} %%
        - note line

      """
    )
    XCTAssertEqual(appState.obsidianVaultRootURL?.standardizedFileURL, vaultRoot.standardizedFileURL)
    XCTAssertTrue(appState.hasCompletedInitialSetup)
    XCTAssertNil(appState.errorMessage)
  }

  func testConfigureObsidianVaultDoesNotCompleteWhenBootstrapAccessDenied() async throws {
    let vaultRoot = try makeVaultRoot()
    let appState = makeAppState(reminderGateway: SetupReminderGateway(accessGranted: false))

    await appState.configureObsidianVault(at: vaultRoot, activateWhenReady: true)

    XCTAssertNil(appState.obsidianVaultRootURL)
    XCTAssertNil(appState.containerRootURL)
    XCTAssertFalse(appState.hasCompletedInitialSetup)
    XCTAssertNil(UserDefaults.standard.string(forKey: AppState.obsidianVaultRootPathKey))
    XCTAssertNil(UserDefaults.standard.string(forKey: "container.rootPath"))
    XCTAssertNotNil(appState.errorMessage)
  }

  func testConfigureObsidianVaultLeavesConflictingRawProjectNoteUnchanged() async throws {
    let vaultRoot = try makeVaultRoot()
    let projectsRoot = vaultRoot
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    let conflictingNoteURL = projectsRoot.appendingPathComponent("Imported list.md", isDirectory: false)
    let originalMarkdown = """
      ---
      tags:
        - 프로젝트
      reminder_list_external_id: other-list
      ---
      - [ ] Local task

      """
    try originalMarkdown.write(to: conflictingNoteURL, atomically: true, encoding: .utf8)
    let appState = makeAppState(reminderGateway: SetupReminderGateway())

    await appState.configureObsidianVault(at: vaultRoot, activateWhenReady: true)

    let afterMarkdown = try String(contentsOf: conflictingNoteURL, encoding: .utf8)
    XCTAssertEqual(afterMarkdown, originalMarkdown)
    XCTAssertNil(appState.obsidianVaultRootURL)
    XCTAssertNil(appState.containerRootURL)
    XCTAssertFalse(appState.hasCompletedInitialSetup)
    XCTAssertNil(UserDefaults.standard.string(forKey: "container.rootPath"))
    XCTAssertNotNil(appState.errorMessage)
  }

  func testLaunchRestoresObsidianVaultFromStoredPath() async throws {
    let vaultRoot = try makeVaultRoot()
    UserDefaults.standard.set(vaultRoot.path, forKey: AppState.obsidianVaultRootPathKey)
    UserDefaults.standard.set(true, forKey: AppState.initialSyncConsentGrantedKey)
    UserDefaults.standard.set(true, forKey: AppState.initialSyncConsentDecidedKey)
    let appState = makeAppState(reminderGateway: SetupReminderGateway())

    await appState.launch()
    try await Task.sleep(nanoseconds: 120_000_000)

    XCTAssertEqual(appState.obsidianVaultRootURL?.standardizedFileURL, vaultRoot.standardizedFileURL)
    XCTAssertEqual(
      appState.containerRootURL?.standardizedFileURL,
      vaultRoot.appendingPathComponent(".buf", isDirectory: true).standardizedFileURL
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: vaultRoot
          .appendingPathComponent("raw", isDirectory: true)
          .appendingPathComponent("projects", isDirectory: true)
          .path
      )
    )
    XCTAssertNotNil(appState.reminderSourceObserver)
  }

  func testDeniedInitialSyncConsentStopsReminderSourceObservation() async throws {
    let vaultRoot = try makeVaultRoot()
    UserDefaults.standard.set(vaultRoot.path, forKey: AppState.obsidianVaultRootPathKey)
    UserDefaults.standard.set(false, forKey: AppState.initialSyncConsentGrantedKey)
    UserDefaults.standard.set(true, forKey: AppState.initialSyncConsentDecidedKey)
    let appState = makeAppState(reminderGateway: SetupReminderGateway())

    await appState.launch()

    XCTAssertNil(appState.reminderSourceObserver)
    XCTAssertEqual(appState.syncStatus, "Refresh paused")
  }

  func testDeniedInitialSyncConsentBlocksStartupSync() async throws {
    let vaultRoot = try makeVaultRoot()
    let appState = makeAppState()

    await appState.configureObsidianVault(at: vaultRoot, activateWhenReady: true)
    appState.setInitialSyncConsentPreference(granted: false, activateWhenReady: false)

    appState.requestStartupSyncIfNeeded()

    XCTAssertTrue(appState.hasCompletedInitialSetup)
    XCTAssertFalse(appState.hasInitialSyncConsent)
    XCTAssertTrue(appState.syncStarted)
    XCTAssertFalse(appState.isInitialSyncRunning)
    XCTAssertEqual(appState.syncStatus, "Refresh paused")
  }

  func testStartupSyncRunsBootstrapReconciliation() async throws {
    let vaultRoot = try makeVaultRoot()
    let appState = makeAppState()

    await appState.configureObsidianVault(at: vaultRoot, activateWhenReady: true)
    appState.syncStatus = "Ready"
    appState.syncStarted = false

    appState.requestStartupSyncIfNeeded()
    try await Task.sleep(nanoseconds: 120_000_000)

    XCTAssertTrue(appState.syncStarted)
    XCTAssertEqual(appState.syncStatus, "Refreshed (\(SyncReason.bootstrap.rawValue))")
  }

  func testQueuedSyncRequestsCoalesceToHighestPriorityReason() {
    let appState = makeAppState()

    appState.queueReminderSourceRefresh(reason: .periodic)
    appState.queueReminderSourceRefresh(reason: .eventStoreChanged)
    appState.queueReminderSourceRefresh(reason: .manual)
    appState.queueReminderSourceRefresh(reason: .periodic)

    XCTAssertEqual(appState.pendingReminderSourceRefreshReason, .manual)
  }

  func testAppAuthoredReminderPushSuppressesImmediateEventStoreEchoOnly() {
    let appState = makeAppState()
    let now = Date(timeIntervalSince1970: 1_000)

    appState.recordAppAuthoredReminderPush(now: now)

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
    appState.appAuthoredReminderEchoRefreshTask?.cancel()
  }

  func testExternalReminderInvalidationRunsRetainedReconciliation() async throws {
    let vaultRoot = try makeVaultRoot()
    let appState = makeAppState()

    await appState.configureObsidianVault(at: vaultRoot, activateWhenReady: true)
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
    reminderGateway: ReminderGateway? = nil,
    calendarService: RecordingScheduleCalendarService = RecordingScheduleCalendarService()
  ) -> AppState {
    AppState(
      storageCoordinator: storageCoordinator,
      reminderGateway: reminderGateway ?? PreviewReminderGateway(),
      calendarServiceRegistry: .live(scheduleCalendarService: calendarService),
      reminderAuthorizationStatusProvider: { .fullAccess }
    )
  }

  private func makeVaultRoot() throws -> URL {
    let vaultRoot = try makeTemporaryDirectory(named: "obsidian-vault")
    try FileManager.default.createDirectory(
      at: vaultRoot.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    return vaultRoot
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
      AppState.obsidianVaultBookmarkDataKey,
      AppState.obsidianVaultRootPathKey,
      "container.bookmarkData",
      "container.rootPath",
    ].forEach(defaults.removeObject(forKey:))
  }
}

@MainActor
private final class SetupReminderGateway: ReminderGateway {
  let eventStore = EKEventStore()
  let calendar: EKCalendar
  let reminder: EKReminder
  private let accessGranted: Bool
  private(set) var writeCallCount = 0

  init(accessGranted: Bool = true) {
    self.accessGranted = accessGranted
    calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = "Imported list"

    reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = calendar
    reminder.title = "Imported task"
    reminder.notes = "note line"
  }

  func requestAccess() async throws -> Bool { accessGranted }
  func fetchAllCalendars() async throws -> [EKCalendar] { [calendar] }
  func fetchReminders(in calendar: EKCalendar, scope: ReminderFetchScope) async throws -> [EKReminder] {
    _ = scope
    return calendar.calendarIdentifier == self.calendar.calendarIdentifier ? [reminder] : []
  }
  func fetchReminders(in calendars: [EKCalendar], scope: ReminderFetchScope) async throws -> [EKReminder] {
    _ = scope
    return calendars.contains { $0.calendarIdentifier == calendar.calendarIdentifier } ? [reminder] : []
  }
  func defaultCalendarIdentifierForNewReminders() -> String? { calendar.calendarIdentifier }
  func calendar(withIdentifier identifier: String) -> EKCalendar? {
    identifier == calendar.calendarIdentifier ? calendar : nil
  }
  func reminder(withIdentifier identifier: String) -> EKReminder? {
    identifier == reminder.calendarItemIdentifier ? reminder : nil
  }
  func reminders(withExternalIdentifier externalIdentifier: String) -> [EKReminder] {
    _ = externalIdentifier
    return []
  }
  func lastModifiedDate(for reminder: EKReminder) -> Date? {
    _ = reminder
    return Date(timeIntervalSince1970: 1_700_000_000)
  }
  func makeReminder(in calendar: EKCalendar) -> EKReminder {
    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = calendar
    return reminder
  }
  func createCalendar(title: String) throws -> EKCalendar {
    _ = title
    writeCallCount += 1
    throw SetupReminderGatewayError.unexpectedWrite
  }
  func save(_ reminder: EKReminder) throws {
    _ = reminder
    writeCallCount += 1
    throw SetupReminderGatewayError.unexpectedWrite
  }
  func remove(_ reminder: EKReminder) throws {
    _ = reminder
    writeCallCount += 1
    throw SetupReminderGatewayError.unexpectedWrite
  }
  func save(_ calendar: EKCalendar) throws {
    _ = calendar
    writeCallCount += 1
    throw SetupReminderGatewayError.unexpectedWrite
  }
  func remove(_ calendar: EKCalendar) throws {
    _ = calendar
    writeCallCount += 1
    throw SetupReminderGatewayError.unexpectedWrite
  }
}

private enum SetupReminderGatewayError: Error {
  case unexpectedWrite
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
  func isCalendarVisible(_ calendarIdentifier: String) -> Bool { _ = calendarIdentifier; return true }
  func isCalendarBackgroundOnly(_ calendarIdentifier: String) -> Bool { _ = calendarIdentifier; return false }
  func toggleCalendarVisibility(_ calendarIdentifier: String) { _ = calendarIdentifier }
  func toggleCalendarBackgroundOnly(_ calendarIdentifier: String) { _ = calendarIdentifier }
  func foregroundVisibleEvents() -> [ScheduleCalendarEvent] { [] }
  func backgroundVisibleEvents() -> [ScheduleCalendarEvent] { [] }
  func refresh(visibleRange: ClosedRange<Date>) async { _ = visibleRange }
  func refresh(visibleRange: ClosedRange<Date>, force: Bool) async { _ = visibleRange; _ = force }
  func reveal(_ event: ScheduleCalendarEvent) { _ = event }
  func applyTimingChange(
    to event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    _ = preview
    _ = scope
    return event
  }
  func delete(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> DeletedScheduleCalendarEventSnapshot {
    _ = event
    _ = scope
    throw ScheduleCalendarEditError.eventNotFound
  }
  func restoreDeletedEvent(_ snapshot: DeletedScheduleCalendarEventSnapshot) async throws
    -> ScheduleCalendarEvent
  {
    _ = snapshot
    throw ScheduleCalendarEditError.eventNotFound
  }
  func applyOwnerFieldWrite(_ write: CalendarEventFieldsWrite) async throws -> ScheduleCalendarEvent {
    write.event
  }
  func ensureOwnedCalendar() async throws -> OwnedScheduleCalendarDescriptor {
    OwnedScheduleCalendarDescriptor(calendarIdentifier: "owned", title: "Owned", colorHex: nil)
  }
  func resolveOwnedEvent(externalIdentifier: String, calendarIdentifier: String?) async -> ScheduleCalendarEvent? {
    _ = externalIdentifier
    _ = calendarIdentifier
    return nil
  }
  func upsertOwnedEvent(
    _ request: OwnedScheduleCalendarEventUpsertRequest,
    calendarIdentifier: String
  ) async throws -> ScheduleCalendarEvent {
    _ = request
    _ = calendarIdentifier
    throw ScheduleCalendarEditError.eventNotFound
  }
  func removeOwnedEvent(externalIdentifier: String, calendarIdentifier: String) async throws -> Bool {
    _ = externalIdentifier
    _ = calendarIdentifier
    return false
  }
  func resolveEvent(ownerID: String) async -> ScheduleCalendarEvent? {
    _ = ownerID
    return nil
  }
}
