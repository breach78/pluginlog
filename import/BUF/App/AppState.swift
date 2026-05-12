import AppKit
@preconcurrency import Combine
@preconcurrency import EventKit
import Foundation
import SwiftData

enum AppRuntimeEnvironment {
  static var isRunningPreview: Bool {
    let value = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"]?.lowercased() ?? ""
    return value == "1" || value == "true" || value == "yes"
  }
}

@MainActor
final class AppState: ObservableObject {
  static let includeCompletedSyncEnabledKey = "sync.includeCompletedRemindersEnabled"
  static let initialSyncConsentGrantedKey = "sync.initialConsentGranted"
  static let initialSyncConsentDecidedKey = "sync.initialConsentDecided"
  static let obsidianVaultBookmarkDataKey = "obsidian.vault.bookmarkData"
  static let obsidianVaultRootPathKey = "obsidian.vault.path"
  static let timelineDayColumnWidthKey = "timeline.dayColumnWidth"
  static let calendarDayChangedNotification = Notification.Name("NSCalendarDayChanged")
  static let systemClockDidChangeNotification = Notification.Name("NSSystemClockDidChange")
  static let systemTimeZoneDidChangeNotification = Notification.Name("NSSystemTimeZoneDidChange")
  static let domainUndoLimit = 20

  @Published var modelContainer: ModelContainer?
  @Published var viewMode: ViewMode = .timeline
  @Published var isArchiveVisible = false
  @Published var selectedProjectID: UUID?
  @Published private(set) var workspaceTreeRevision = 0
  @Published var searchText = ""
  @Published var errorMessage: String?
  @Published var containerHealth: ContainerHealth = .unknown
  @Published var syncStatus = "Idle"
  @Published var isInitialSyncRunning = false
  @Published var syncStarted = false
  @Published var boardsLoaded = false
  @Published var isLaunching = true
  @Published var timelineJumpToTodayToken = 0
  @Published var scheduleJumpToTodayToken = 0
  @Published var scheduleJumpTargetDate: Date?
  @Published var scheduleJumpToDateToken = 0
  @Published var scheduleMonthDisplayedMonthStart: Date?
  @Published var currentDayStart: Date = Calendar.autoupdatingCurrent.startOfDay(for: .now)
  @Published var currentDayChangeToken = 0
  @Published var isHoveringTimelineTaskBadgeOverlay = false
  @Published var isHoveringTimelineDayHeaderOverlay = false
  @Published var workspaceNavigationRequest: WorkspaceNavigationRequest?
  @Published var includeCompletedSyncEnabled = true
  @Published var hasInitialSyncConsent = false
  @Published var hasSyncConsentDecision = false
  @Published var obsidianVaultRootURL: URL?
  @Published var containerRootURL: URL?
  @Published var timelineDayColumnWidth: CGFloat = 44
  @Published var isEditorActive = false
  @Published var isEditorMotionSuppressed = false
  @Published var scheduleCalendarOverlayProjection: ScheduleCalendarOverlayProjection = .empty
  @Published private(set) var timelineProjectListVisibleOrder: [UUID] = []

  let defaultTimelineDayColumnWidth: CGFloat = 44
  let minimumTimelineDayColumnWidth: CGFloat = 22
  let maximumTimelineDayColumnWidth: CGFloat = 88

  var didAutoBootstrapSync = false
  var cachedDefaultReminderCalendarIdentifier: String?
  var hasCachedDefaultReminderCalendarIdentifier = false
  var editorIdleTask: Task<Void, Never>?
  var editorMotionReleaseTask: Task<Void, Never>?
  var dayBoundaryTimer: Timer?
  var editorIdleDeadline: Date = .distantPast
  var activeExplicitEditorSessionIDs: Set<String> = []
  var editorStateChangeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
  var workspaceProjectDetailEscapeHandlers: [UUID: () -> Bool] = [:]
  var workspaceProjectDetailEscapeHandlerOrder: [UUID] = []
  var scheduleCalendarOverlayProjectionCancellable: AnyCancellable?
  var scheduleCalendarOwnedEventInvalidationCancellable: AnyCancellable?
  let editorMotionReleaseDelay: Duration = .milliseconds(260)
  var dayBoundaryObservers: [NSObjectProtocol] = []
  var workspaceDayBoundaryObservers: [NSObjectProtocol] = []
  var reminderSyncEditGate: ReminderSyncEditGate?
  var reminderSyncRecoveryJournal: ReminderSyncRecoveryJournalStore?
  var reminderSourceObserver: ReminderSourceObserver?
  var pendingReminderSourceRefreshReason: SyncReason?
  private var undoRedoDepth = 0
  let storageCoordinator: LocalStorageCoordinator
  let platformUIFoundation: PlatformUIFoundation
  let calendarServiceRegistry: AppStateCalendarServiceRegistry
  let reminderGateway: ReminderGateway
  let reminderProjectProvider: ReminderProjectProvider
  let reminderAuthorizationStatusProvider: () -> EKAuthorizationStatus
  let timelineService: TimelineService

  var defaultReminderCalendarIdentifier: String? {
    if hasCachedDefaultReminderCalendarIdentifier {
      return cachedDefaultReminderCalendarIdentifier
    }
    let identifier = reminderProjectProvider.defaultCalendarIdentifierForNewReminders
    cachedDefaultReminderCalendarIdentifier = identifier
    hasCachedDefaultReminderCalendarIdentifier = true
    return identifier
  }

  private var normalizedReminderStatus: String {
    syncStatus.lowercased()
  }

  var reminderStatusDisplayText: String {
    switch normalizedReminderStatus {
    case "idle": "리마인더 대기"
    case "ready", "preview": "리마인더 준비됨"
    case "refresh paused": "리마인더 새로고침 일시중지"
    case "obsidian vault not configured": "Obsidian vault 미설정"
    case "container not opened": "컨테이너 미열림"
    case "reminders access denied": "리마인더 접근 권한 필요"
    default: syncStatus
    }
  }

  var isReminderStatusReady: Bool {
    normalizedReminderStatus == "ready"
      || normalizedReminderStatus == "preview"
      || normalizedReminderStatus.hasPrefix("synced")
      || normalizedReminderStatus.hasPrefix("refreshed")
  }

  var isReminderStatusRefreshing: Bool {
    isInitialSyncRunning || normalizedReminderStatus.contains("refreshing")
  }

  var isReminderStatusDenied: Bool {
    normalizedReminderStatus.contains("denied")
  }

  var isReminderStatusFailed: Bool {
    normalizedReminderStatus.contains("failed") || normalizedReminderStatus.contains("error")
  }

  init(
    storageCoordinator: LocalStorageCoordinator? = nil,
    reminderGateway: ReminderGateway? = nil,
    timelineService: TimelineService? = nil,
    calendarServiceRegistry: AppStateCalendarServiceRegistry? = nil,
    reminderAuthorizationStatusProvider: @escaping () -> EKAuthorizationStatus = {
      EKEventStore.authorizationStatus(for: .reminder)
    },
    isPreviewAppState: Bool = false
  ) {
    let uiTestConfiguration = AppUITestRuntime.Configuration()
    let usesPreviewRuntimeSetup = isPreviewAppState || AppRuntimeEnvironment.isRunningPreview
    self.storageCoordinator =
      storageCoordinator ?? LocalStorageCoordinator(
        userDefaults: uiTestConfiguration?.userDefaults ?? .standard
      )
    TaskIdentityBridgeStore.install(dataDirectory: self.storageCoordinator.paths?.dataDirectory)
    ReminderPendingBindingStore.install(dataDirectory: self.storageCoordinator.paths?.dataDirectory)
    ReminderDeletedTaskTombstoneStore.install(dataDirectory: self.storageCoordinator.paths?.dataDirectory)
    self.platformUIFoundation = .shared
    let resolvedReminderGateway = reminderGateway ?? (
      (usesPreviewRuntimeSetup || uiTestConfiguration != nil)
        ? PreviewReminderGateway()
        : EventKitReminderGateway()
    )
    self.reminderGateway = resolvedReminderGateway
    if let uiTestConfiguration, reminderGateway == nil {
      self.reminderProjectProvider = UITestReminderProjectProvider(seed: uiTestConfiguration.seed)
    } else {
      self.reminderProjectProvider = EventKitReminderProjectProvider(gateway: resolvedReminderGateway)
    }
    self.reminderAuthorizationStatusProvider = reminderAuthorizationStatusProvider
    self.timelineService = timelineService ?? DefaultTimelineService()
    self.calendarServiceRegistry =
      calendarServiceRegistry ?? AppStateCalendarServiceRegistry.live(
        scheduleCalendarService: uiTestConfiguration == nil
          ? nil
          : UITestScheduleCalendarService()
      )
    self.scheduleCalendarOverlayProjection =
      self.calendarServiceRegistry.scheduleCalendarService.overlayProjection
    self.scheduleCalendarOverlayProjectionCancellable =
      self.calendarServiceRegistry.scheduleCalendarService.overlayProjectionPublisher
      .sink { [weak self] projection in
        self?.scheduleCalendarOverlayProjection = projection
      }
    self.scheduleCalendarOwnedEventInvalidationCancellable =
      self.calendarServiceRegistry.scheduleCalendarService.ownedEventInvalidationPublisher
      .sink { [weak self] ownerIDs in
        guard let self, !ownerIDs.isEmpty else { return }
        Task { @MainActor [weak self] in
          _ = await self?.handleExternalCalendarEventInvalidation(
            ownerIDs: ownerIDs,
            changedFields: AppOwnerField.calendarEventExternalChangeFields,
            waitForEditorIdle: false
          )
        }
      }

    UserDefaults.standard.set(true, forKey: Self.includeCompletedSyncEnabledKey)
    includeCompletedSyncEnabled = true
    hasInitialSyncConsent = UserDefaults.standard.bool(forKey: Self.initialSyncConsentGrantedKey)
    hasSyncConsentDecision =
      UserDefaults.standard.object(forKey: Self.initialSyncConsentDecidedKey) as? Bool
      ?? (UserDefaults.standard.object(forKey: Self.initialSyncConsentGrantedKey) != nil)

    let storedWidth = UserDefaults.standard.double(forKey: Self.timelineDayColumnWidthKey)
    if storedWidth > 0 {
      timelineDayColumnWidth = min(
        max(CGFloat(storedWidth), minimumTimelineDayColumnWidth),
        maximumTimelineDayColumnWidth
      )
    }

    guard !usesPreviewRuntimeSetup else { return }
    configureDayBoundaryObservation()
  }

  deinit {
    editorIdleTask?.cancel()
    editorMotionReleaseTask?.cancel()
    scheduleCalendarOverlayProjectionCancellable?.cancel()
    scheduleCalendarOwnedEventInvalidationCancellable?.cancel()
    editorStateChangeContinuations.values.forEach { $0.finish() }
  }

  func refreshDefaultReminderCalendarIdentifier() {
    cachedDefaultReminderCalendarIdentifier =
      reminderProjectProvider.defaultCalendarIdentifierForNewReminders
    hasCachedDefaultReminderCalendarIdentifier = true
  }

  var isContainerConfigured: Bool { containerRootURL != nil }
  var isObsidianVaultConfigured: Bool { obsidianVaultRootURL != nil }
  var hasCompletedInitialSetup: Bool {
    isContainerConfigured && isObsidianVaultConfigured && hasSyncConsentDecision
  }

  var isUndoRedoInFlight: Bool { undoRedoDepth > 0 }

  func registerUndo(
    with undoManager: UndoManager?,
    actionName: String,
    handler: @escaping @MainActor () -> Void
  ) {
    guard let undoManager else { return }
    undoManager.levelsOfUndo = Self.domainUndoLimit
    undoManager.registerUndo(withTarget: self) { target in
      let runHandler = {
        target.undoRedoDepth += 1
        defer { target.undoRedoDepth -= 1 }
        handler()
      }
      if Thread.isMainThread {
        MainActor.assumeIsolated {
          runHandler()
        }
      } else {
        Task { @MainActor in
          runHandler()
        }
      }
    }
    undoManager.setActionName(actionName)
  }

  func reportError(_ error: Error, logMessage: String? = nil) {
    errorMessage = error.localizedDescription
    if let logMessage {
      AppLogger.app.error(
        "\(logMessage, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  func bumpWorkspaceTreeRevision() {
    workspaceTreeRevision &+= 1
  }

  func updateTimelineProjectListVisibleOrder(_ projectIDs: [UUID]) {
    guard timelineProjectListVisibleOrder != projectIDs else { return }
    timelineProjectListVisibleOrder = projectIDs
  }

  @discardableResult
  func saveContext(
    _ context: ModelContext,
    logMessage: String? = nil
  ) -> Bool {
    do {
      try context.save()
      return true
    } catch {
      reportError(error, logMessage: logMessage)
      return false
    }
  }
}
