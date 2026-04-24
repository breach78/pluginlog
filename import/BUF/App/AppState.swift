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
  // Root state + assembly only.
  // Budget + split fence enforced by AppStateReductionMilestoneTests.swift.
  // Domain slices: AppStateLaunchAndSetup.swift, AppStateWorkspaceUI.swift,
  // AppStateEditorState.swift, AppStateProjectActions.swift, AppStateSourceIO.swift,
  // AppStateSyncAndPersistence.swift, AppStateDiagnostics.swift.
  static let includeCompletedSyncEnabledKey = "sync.includeCompletedRemindersEnabled"
  static let initialSyncConsentGrantedKey = "sync.initialConsentGranted"
  static let initialSyncConsentDecidedKey = "sync.initialConsentDecided"
  static let logseqGraphBookmarkDataKey = "logseq.graphRoot.bookmarkData"
  static let logseqGraphRootPathKey = "logseq.graphRoot.path"
  static let obsidianBookmarkDataKey = "obsidian.projectsFolder.bookmarkData"
  static let obsidianRootPathKey = "obsidian.projectsFolder.path"
  static let privateObsidianFeaturesEnabledKey = "features.privateObsidianEnabled"
  static let timelineDayColumnWidthKey = "timeline.dayColumnWidth"
  static let geminiSummaryModelNameKey = "journal.summary.gemini.modelName"
  private static let journalMinimumIncludedDayKey = "journal.minimumIncludedDay"
  private static let debugPhase0AutoExportAfterLaunchKey = "debug.phase0AutoExportAfterLaunch"
  static let calendarDayChangedNotification = Notification.Name("NSCalendarDayChanged")
  static let systemClockDidChangeNotification = Notification.Name("NSSystemClockDidChange")
  static let systemTimeZoneDidChangeNotification = Notification.Name("NSSystemTimeZoneDidChange")
#if DEBUG
  private static let debugTaskListPerfSeedArgument = "--debug-task-list-perf-1000"
  private static let debugTaskListPerfCompactSeedArgument = "--debug-task-list-perf-1000-compact"
  private static let debugTaskListPerfRichSeedArgument = "--debug-task-list-perf-1000-rich"
  private static let debugTaskListPerfTaskCount = 1000
#endif

  @Published var modelContainer: ModelContainer?
  @Published var viewMode: ViewMode = .timeline
  @Published var isArchiveVisible: Bool = false
  @Published var selectedProjectID: UUID?
  @Published private(set) var workspaceTreeRevision: Int = 0
  @Published var searchText: String = ""
  @Published var errorMessage: String?
  @Published var containerHealth: ContainerHealth = .unknown
  @Published var syncStatus: String = "Idle"
  @Published var isInitialSyncRunning: Bool = false
  @Published var syncStarted: Bool = false
  @Published var boardsLoaded: Bool = false
  @Published var isLaunching: Bool = true
  @Published var timelineJumpToTodayToken: Int = 0
  @Published var scheduleJumpToTodayToken: Int = 0
  @Published var scheduleJumpTargetDate: Date?
  @Published var scheduleJumpToDateToken: Int = 0
  @Published var currentDayStart: Date =
    Calendar.autoupdatingCurrent.startOfDay(for: .now)
  @Published var currentDayChangeToken: Int = 0
  @Published var isHoveringTimelineTaskBadgeOverlay: Bool = false
  @Published var isHoveringTimelineDayHeaderOverlay: Bool = false
  @Published var workspaceNavigationRequest: WorkspaceNavigationRequest?
  @Published var includeCompletedSyncEnabled: Bool = false
  @Published var hasInitialSyncConsent: Bool = false
  @Published var hasSyncConsentDecision: Bool = false
  @Published var isPrivateObsidianFeaturesEnabled: Bool = false
  @Published var logseqGraphRootURL: URL?
  @Published var obsidianProjectsRootURL: URL?
  @Published var containerRootURL: URL?
  @Published var timelineDayColumnWidth: CGFloat = 44
  @Published var isEditorActive: Bool = false
  @Published var isEditorMotionSuppressed: Bool = false
  @Published var hasGeminiAPIKey: Bool = false
  @Published var hasOpenAIAPIKey: Bool = false
  @Published var documentReferenceChangeEvents: [UUID: DocumentReferenceChangeEvent] =
    [:]
  @Published var normalizedReminderImportStatus: String = "Idle"
  @Published var geminiSummaryModelName: String =
    GeminiGenerateContentSummaryService.defaultModelName
  @Published private(set) var journalMinimumIncludedDay: Date =
    Calendar.autoupdatingCurrent.startOfDay(for: .now)

  private var normalizedReminderStatus: String {
    syncStatus.lowercased()
  }

  var reminderStatusDisplayText: String {
    switch normalizedReminderStatus {
    case "idle":
      return "리마인더 메타데이터 대기"
    case "ready":
      return "리마인더 메타데이터 준비됨"
    case "preview":
      return "미리보기"
    case "refresh paused":
      return "리마인더 메타데이터 새로고침 일시중지"
    case "waiting for reminder preference":
      return "리마인더 메타데이터 새로고침 설정 대기"
    case "container open failed":
      return "컨테이너 열기 실패"
    case "container not opened":
      return "컨테이너 미열림"
    case "logseq graph not configured":
      return "Logseq 그래프 미설정"
    case "obsidian vault not configured":
      return "Obsidian 보관함 미설정"
    case "setup failed":
      return "설정 준비 실패"
    case "reminders access denied":
      return "리마인더 접근 권한 필요"
    default:
      break
    }

    if normalizedReminderStatus.contains("refreshing") {
      return "리마인더 메타데이터 새로고침 중"
    }
    if normalizedReminderStatus.hasPrefix("refreshed") {
      return "리마인더 메타데이터 새로고침 완료"
    }
    if syncStatus.hasPrefix("Refresh failed: ") {
      let message = String(syncStatus.dropFirst("Refresh failed: ".count))
      return "리마인더 메타데이터 준비 실패: \(message)"
    }

    return syncStatus
  }

  var isReminderStatusReady: Bool {
    normalizedReminderStatus == "ready"
      || normalizedReminderStatus == "preview"
      || normalizedReminderStatus.hasPrefix("synced")
  }

  var isReminderStatusRefreshing: Bool {
    isInitialSyncRunning
      || normalizedReminderStatus.contains("refreshing")
      || normalizedReminderStatus.hasPrefix("starting refresh")
  }

  var isReminderStatusDenied: Bool {
    normalizedReminderStatus.contains("denied")
  }

  var isReminderStatusFailed: Bool {
    normalizedReminderStatus.contains("failed")
      || normalizedReminderStatus.contains("error")
  }

  let defaultTimelineDayColumnWidth: CGFloat = 44
  let minimumTimelineDayColumnWidth: CGFloat = 22
  let maximumTimelineDayColumnWidth: CGFloat = 88

  var defaultReminderCalendarIdentifier: String? {
    if hasCachedDefaultReminderCalendarIdentifier {
      return cachedDefaultReminderCalendarIdentifier
    }

    let identifier = reminderProjectProvider.defaultCalendarIdentifierForNewReminders
    cachedDefaultReminderCalendarIdentifier = identifier
    hasCachedDefaultReminderCalendarIdentifier = true
    return identifier
  }

  var didAutoBootstrapSync = false
  var isOutlinerProjectionBootstrapPending = true
  var cachedDefaultReminderCalendarIdentifier: String?
  var hasCachedDefaultReminderCalendarIdentifier = false
  var pendingProjectDetailReorderPersistenceTask: Task<Void, Never>?
  var editorIdleTask: Task<Void, Never>?
  var editorMotionReleaseTask: Task<Void, Never>?
  var normalizedPersistenceTask: Task<Void, Never>?
  var documentReferenceObservationTask: Task<Void, Never>?
  var normalizedReminderImportTask: Task<Void, Never>?
  var outlinerCacheWarmupTask: Task<Void, Never>?
  var dayBoundaryTimer: Timer?
  var editorIdleDeadline: Date = .distantPast
  var activeExplicitEditorSessionIDs: Set<String> = []
  var editorStateChangeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
  var workspaceProjectDetailEscapeHandlers: [UUID: () -> Bool] = [:]
  var workspaceProjectDetailEscapeHandlerOrder: [UUID] = []
  var projectCommandDispatcherRegistry: [UUID: ProjectDocumentStore] = [:]
  var projectDocumentStoreChangeCancellables: [UUID: AnyCancellable] = [:]
  var scheduleCalendarOverlayProjectionCancellable: AnyCancellable?
  var scheduleCalendarOwnedEventInvalidationCancellable: AnyCancellable?
  lazy var projectIndexUpdateQueue = ProjectIndexUpdateQueue(
    storeProvider: { [weak self] projectID in
      self?.projectDocumentStore(for: projectID)
    },
    flushObserver: { [weak self] projectIDs in
      guard let self else { return }
      await self.invalidateWorkspaceProjectCaches(for: projectIDs)
      self.bumpWorkspaceTreeRevision()
    }
  )
  let editorMotionReleaseDelay: Duration = .milliseconds(260)
  var dayBoundaryObservers: [NSObjectProtocol] = []
  var workspaceDayBoundaryObservers: [NSObjectProtocol] = []
  var detachedProjectWindowRegistry: [UUID: DetachedProjectWindowController] = [:]
  var outlinerWindowController: OutlinerWindowController?
  var cachedOutlinerSessionSnapshot: OutlinerSessionSnapshot?
  @Published private(set) var runtimeProjectionRevision: UInt64 = 0
  @Published var cachedOutlinerRuntimeProjectionSnapshot: OutlineProjectionRuntimeSnapshot? {
    didSet {
      runtimeProjectionRevision &+= 1
    }
  }
  @Published var scheduleCalendarOverlayProjection: ScheduleCalendarOverlayProjection = .empty

  let storageCoordinator: LocalStorageCoordinator
  let platformUIFoundation: PlatformUIFoundation

  let timelineService: TimelineService
  let undoCoordinator: UndoCoordinator
  let openAISummaryModelName: String = OpenAIResponsesSummaryService.modelName
  let calendarServiceRegistry: AppStateCalendarServiceRegistry

  let reminderGateway: ReminderGateway
  let reminderProjectProvider: ReminderProjectProvider
  let geminiAPIKeyStore = GeminiAPIKeyStore.shared
  let openAIAPIKeyStore = OpenAIAPIKeyStore.shared
  var journalStore: ObsidianJournalStore?
  var logseqSecurityScopedURL: URL?
  var obsidianSecurityScopedURL: URL?

  var attachmentStore: LocalAttachmentStore?
  var archiveService: DefaultArchiveService?
  var reminderSyncEditGate: ReminderSyncEditGate?
  var reminderSyncRecoveryJournal: ReminderSyncRecoveryJournalStore?
  var reminderSourceObserver: ReminderSourceObserver?
  var documentReferenceRepository: NormalizedDocumentReferenceRepository?
  var documentReferenceImporter: SecurityScopedDocumentReferenceImporter?
  var documentReferenceAccessService: SecurityScopedDocumentReferenceAccessService?
  var documentReferencePresenterPool: DocumentReferencePresenterPool?
  var workspaceTreeRepository: WorkspaceTreeRepository?

  deinit {
    pendingProjectDetailReorderPersistenceTask?.cancel()
    editorIdleTask?.cancel()
    editorMotionReleaseTask?.cancel()
    normalizedPersistenceTask?.cancel()
    documentReferenceObservationTask?.cancel()
    normalizedReminderImportTask?.cancel()
    outlinerCacheWarmupTask?.cancel()
    scheduleCalendarOverlayProjectionCancellable?.cancel()
    scheduleCalendarOwnedEventInvalidationCancellable?.cancel()
    editorStateChangeContinuations.values.forEach { $0.finish() }
    logseqSecurityScopedURL?.stopAccessingSecurityScopedResource()
    obsidianSecurityScopedURL?.stopAccessingSecurityScopedResource()
  }

  func refreshDefaultReminderCalendarIdentifier() {
    cachedDefaultReminderCalendarIdentifier =
      reminderProjectProvider.defaultCalendarIdentifierForNewReminders
    hasCachedDefaultReminderCalendarIdentifier = true
  }

  init(
    storageCoordinator: LocalStorageCoordinator? = nil,
    reminderGateway: ReminderGateway? = nil,
    timelineService: TimelineService? = nil,
    undoCoordinator: UndoCoordinator? = nil,
    calendarServiceRegistry: AppStateCalendarServiceRegistry? = nil,
    isPreviewAppState: Bool = false
  ) {
    let usesPreviewRuntimeSetup = isPreviewAppState || AppRuntimeEnvironment.isRunningPreview
    self.storageCoordinator = storageCoordinator ?? LocalStorageCoordinator()
    TaskIdentityBridgeStore.install(dataDirectory: self.storageCoordinator.paths?.dataDirectory)
    self.platformUIFoundation = .shared
    let resolvedReminderGateway = reminderGateway ?? (
      usesPreviewRuntimeSetup
      ? PreviewReminderGateway()
      : EventKitReminderGateway()
    )
    self.reminderGateway = resolvedReminderGateway
    self.reminderProjectProvider = EventKitReminderProjectProvider(gateway: resolvedReminderGateway)
    self.timelineService = timelineService ?? DefaultTimelineService()
    self.undoCoordinator = undoCoordinator ?? UndoCoordinator()
    self.calendarServiceRegistry =
      calendarServiceRegistry ?? AppStateCalendarServiceRegistry.live()
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
          guard let self else { return }
          _ = await self.handleExternalCalendarEventInvalidation(
            ownerIDs: ownerIDs,
            changedFields: AppOwnerField.calendarEventExternalChangeFields,
            waitForEditorIdle: false
          )
        }
      }

    if !UserDefaults.standard.bool(forKey: Self.includeCompletedSyncEnabledKey) {
      // Completed reminders must always be cached locally so Reminders remains the source of truth.
      UserDefaults.standard.set(true, forKey: Self.includeCompletedSyncEnabledKey)
    }
    self.includeCompletedSyncEnabled = true
    self.hasInitialSyncConsent = UserDefaults.standard.bool(
      forKey: Self.initialSyncConsentGrantedKey)
    self.isPrivateObsidianFeaturesEnabled = false

    if let decided = UserDefaults.standard.object(forKey: Self.initialSyncConsentDecidedKey)
      as? Bool
    {
      self.hasSyncConsentDecision = decided
    } else {
      // Backward compatibility: if consent key existed in older builds, treat it as already decided.
      self.hasSyncConsentDecision =
        UserDefaults.standard.object(forKey: Self.initialSyncConsentGrantedKey) != nil
    }

    let storedWidth = UserDefaults.standard.double(forKey: Self.timelineDayColumnWidthKey)
    if storedWidth > 0 {
      self.timelineDayColumnWidth = min(
        max(CGFloat(storedWidth), minimumTimelineDayColumnWidth), maximumTimelineDayColumnWidth)
    }

    let storedGeminiModel = UserDefaults.standard.string(forKey: Self.geminiSummaryModelNameKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let storedGeminiModel, !storedGeminiModel.isEmpty {
      self.geminiSummaryModelName = storedGeminiModel
    } else {
      UserDefaults.standard.set(
        GeminiGenerateContentSummaryService.defaultModelName,
        forKey: Self.geminiSummaryModelNameKey
      )
    }

    self.journalMinimumIncludedDay = Self.resolvedJournalMinimumIncludedDay()

    guard !usesPreviewRuntimeSetup else { return }

    configureDayBoundaryObservation()
  }

  func exportPhase0RedLineBaseline() async {
    guard let modelContainer else {
      errorMessage = "컨테이너가 아직 준비되지 않았습니다."
      return
    }

    let exporter = Phase0RedLineBaselineExporter(
      storageCoordinator: storageCoordinator,
      modelContainer: modelContainer,
      runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
      currentViewMode: viewMode,
      selectedProjectID: selectedProjectID,
      timelineDayColumnWidth: timelineDayColumnWidth,
      includeCompletedSyncEnabled: includeCompletedSyncEnabled,
      hasInitialSyncConsent: hasInitialSyncConsent,
      hasSyncConsentDecision: hasSyncConsentDecision,
      obsidianProjectsRootURL: obsidianProjectsRootURL,
      containerRootURL: containerRootURL,
      userDefaults: .standard
    )

    do {
      let exportURL = try await exporter.export()
      AppLogger.app.info(
        "phase0 red line baseline exported: \(exportURL.path, privacy: .public)"
      )
      platformUIFoundation.documentOpener.revealInFiles([exportURL])
    } catch {
      reportError(error, logMessage: "exportPhase0RedLineBaseline failed")
    }
  }

  func scheduleDebugPhase0AutoExportIfNeeded() {
#if DEBUG
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: Self.debugPhase0AutoExportAfterLaunchKey) else { return }
    defaults.removeObject(forKey: Self.debugPhase0AutoExportAfterLaunchKey)

    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(10))
      guard let self, !Task.isCancelled else { return }
      await self.exportPhase0RedLineBaseline()
    }
#endif
  }

  var isContainerConfigured: Bool {
    containerRootURL != nil
  }

  var isLogseqGraphConfigured: Bool {
    logseqGraphRootURL != nil
  }

  var isObsidianFolderConfigured: Bool {
    obsidianProjectsRootURL != nil
  }

  var requiresObsidianVaultSetup: Bool {
    false
  }

  var hasCompletedInitialSetup: Bool {
    isContainerConfigured
      && isLogseqGraphConfigured
      && hasSyncConsentDecision
  }

  private static func resolvedJournalMinimumIncludedDay() -> Date {
    let defaults = UserDefaults.standard
    if
      let stored = defaults.string(forKey: Self.journalMinimumIncludedDayKey),
      let parsed = journalDayFormatter.date(from: stored)
    {
      return parsed
    }

    let fallback: Date
    if defaults.object(forKey: Self.obsidianRootPathKey) != nil
      || defaults.object(forKey: Self.obsidianBookmarkDataKey) != nil
    {
      fallback = journalDayFormatter.date(from: "2026-02-01")
        ?? Calendar.autoupdatingCurrent.startOfDay(for: .now)
    } else {
      fallback = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    }

    defaults.set(journalDayFormatter.string(from: fallback), forKey: Self.journalMinimumIncludedDayKey)
    return fallback
  }

  private static let journalDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static func initialPrivateObsidianFeaturesEnabled() -> Bool {
    false
  }

  var isUndoRedoInFlight: Bool {
    undoCoordinator.isPerformingUndoRedo
  }

  func registerUndo(
    with undoManager: UndoManager?,
    actionName: String,
    handler: @escaping @MainActor () -> Void
  ) {
    undoCoordinator.register(with: undoManager, actionName: actionName, handler: handler)
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

#if DEBUG
@MainActor
extension AppState {
  static var debugTaskListPerfSeedProfile: DebugTaskListPerfSeedProfile? {
    if CommandLine.arguments.contains(debugTaskListPerfCompactSeedArgument) {
      return .compact
    }
    if CommandLine.arguments.contains(debugTaskListPerfRichSeedArgument) {
      return .rich
    }
    if CommandLine.arguments.contains(debugTaskListPerfSeedArgument) {
      return .mixed
    }
    return nil
  }

  static var isDebugTaskListPerfLaunchRequested: Bool {
    debugTaskListPerfSeedProfile != nil
  }

  func seedDebugTaskListPerfProjectIfRequested() throws {
    guard let profile = Self.debugTaskListPerfSeedProfile else { return }

    let runtimeSnapshot = makeDebugTaskListPerfRuntimeSnapshot(profile: profile)
    installCachedRuntimeProjectionSnapshot(runtimeSnapshot)
    isOutlinerProjectionBootstrapPending = false
    selectedProjectID = runtimeSnapshot.currentProjectID
    loadWorkspaceBoardsIfNeeded()

    for entry in runtimeSnapshot.projects.first?.document.flatten() ?? [] where entry.node.type.isTask {
      UserDefaults.standard.set(
        profile != .rich,
        forKey: "project.taskReminderNoteCollapsed.\(entry.node.canonicalID.uuidString)"
      )
    }

    let projectID = runtimeSnapshot.currentProjectID
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(900))
      guard let self, !Task.isCancelled else { return }
      guard self.modelContainer != nil else { return }
      self.platformUIFoundation.windowManager.makeMainWindowKeyAndFront()
      self.openDetachedProjectWindow(projectID: projectID)
    }
  }

  private func makeDebugTaskListPerfRuntimeSnapshot(
    profile: DebugTaskListPerfSeedProfile
  ) -> OutlineProjectionRuntimeSnapshot {
    let now = Date()
    let calendar = Calendar.autoupdatingCurrent
    let startOfToday = calendar.startOfDay(for: now)
    let projectID = UUID()
    let reminderListIdentifier = profile.calendarIdentifier
    let reminderListExternalIdentifier = profile.calendarIdentifier
    let projectNote =
      "Seeded \(profile.rawValue) debug project for project detail task list performance with \(Self.debugTaskListPerfTaskCount) tasks."

    var rootNodes: [OutlineNode] = []
    rootNodes.reserveCapacity(Self.debugTaskListPerfTaskCount)
    var reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot] = [:]
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot] = [:]
    var featureSidecarByReminderIdentifier: [String: OutlinerTaskSidecarMetadata] = [:]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata] = [:]
    var reminderModifiedAtByReminderExternalIdentifier: [String: Date] = [:]
    var taskFeatureSidecars: [String: ReminderTaskFeatureSidecarRecord] = [:]
    var taskRuntimeStates: [String: ReminderTaskSourceRuntimeState] = [:]
    var orderedReminderExternalIdentifiers: [String] = []
    orderedReminderExternalIdentifiers.reserveCapacity(Self.debugTaskListPerfTaskCount)

    for index in 0..<Self.debugTaskListPerfTaskCount {
      let taskID = UUID()
      let reminderIdentifier = "debug-task-\(index)"
      let reminderExternalIdentifier = "debug-task-ext-\(index)"
      let dueDate = seededPerfTaskDueDate(
        index: index,
        profile: profile,
        calendar: calendar,
        startOfToday: startOfToday
      )
      let hasExplicitTime = seededPerfTaskHasExplicitTime(index: index, profile: profile)
      let scheduledDurationMinutes = hasExplicitTime ? 30 + ((index % 4) * 15) : nil
      let requiredWorkDays = seededPerfTaskRequiredWorkDays(index: index, profile: profile)
      let taskNote = seededPerfTaskReminderNote(index: index, profile: profile)
      let metadata = ReminderMetadataSnapshot(
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime,
        priority: index.isMultiple(of: 9) ? 1 : 0
      )
      let featureSidecar = OutlinerTaskSidecarMetadata(
        requiredWorkDays: requiredWorkDays,
        scheduledDurationMinutes: scheduledDurationMinutes
      )

      let node = OutlineNode(
        id: taskID,
        canonicalID: taskID,
        text: seededPerfTaskTitle(index: index, profile: profile),
        type: .task(completed: false),
        reminderIdentifier: reminderIdentifier,
        reminderExternalIdentifier: reminderExternalIdentifier
      )
      rootNodes.append(node)
      orderedReminderExternalIdentifiers.append(reminderExternalIdentifier)
      reminderMetadataByReminderIdentifier[reminderIdentifier] = metadata
      reminderMetadataByNodeID[node.id] = metadata
      featureSidecarByReminderIdentifier[reminderIdentifier] = featureSidecar
      featureSidecarByNodeID[node.id] = featureSidecar
      reminderModifiedAtByReminderExternalIdentifier[reminderExternalIdentifier] = now
      taskFeatureSidecars[reminderExternalIdentifier] = ReminderTaskFeatureSidecarRecord(
        reminderExternalIdentifier: reminderExternalIdentifier,
        attachmentManifestRaw: "",
        scheduledDurationMinutes: scheduledDurationMinutes,
        ownedCalendarEventExternalIdentifier: nil,
        boardStageRaw: BoardStage.now.rawValue,
        importanceRaw: index.isMultiple(of: 6) ? ImportanceLevel.important.rawValue : ImportanceLevel.minor.rawValue,
        isFlagged: false,
        requiredWorkDays: requiredWorkDays,
        completedWorkUnits: 0,
        completedWorkUnitDatesRaw: "",
        preparationScheduleOverridesRaw: "",
        createdAt: now,
        updatedAt: now
      )
      taskRuntimeStates[reminderExternalIdentifier] = ReminderTaskSourceRuntimeState(
        reminderExternalIdentifier: reminderExternalIdentifier,
        lastImportedNormalizedNoteHash: taskNote.isEmpty
          ? nil
          : ReminderNoteSourceMutationService.hash(
            for: ReminderNoteSourceCodec.parseReminderRawNote(taskNote).normalizedText
          ),
        lastExportedNormalizedNoteHash: nil,
        lastObservedReminderModifiedAt: now,
        lastObservedReminderRawPayloadRaw: nil,
        noteConflictStateRaw: nil
      )
    }

    let projectFeature = ReminderProjectFeatureSidecarRecord(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      projectNoteMarkdown: projectNote,
      localStartDate: nil,
      localDeadline: nil,
      progressStageRaw: ProjectProgressStage.do.storageRawValue,
      boardOrder: 0,
      attachmentManifestRaw: "",
      createdAt: now,
      updatedAt: now
    )
    let project = OutlinerProject(
      id: projectID,
      title: profile.title,
      document: OutlineDocument(rootNodes: rootNodes)
    )

    return OutlineProjectionRuntimeSnapshot(
      projects: [project],
      currentProjectID: projectID,
      featureSidecarByReminderIdentifier: featureSidecarByReminderIdentifier,
      featureSidecarByNodeID: featureSidecarByNodeID,
      reminderMetadataByReminderIdentifier: reminderMetadataByReminderIdentifier,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      projectReminderListIdentifierByProjectID: [projectID: reminderListIdentifier],
      projectReminderListExternalIdentifierByProjectID: [projectID: reminderListExternalIdentifier],
      projectColorHexByProjectID: [projectID: profile.colorHex],
      reminderModifiedAtByReminderExternalIdentifier: reminderModifiedAtByReminderExternalIdentifier,
      workspaceStructureRecord: ReminderWorkspaceStructureRecord(
        orderedReminderListExternalIdentifiers: [reminderListExternalIdentifier],
        createdAt: now,
        updatedAt: now
      ),
      projectTaskOrderByReminderListExternalIdentifier: [
        reminderListExternalIdentifier: ReminderProjectTaskOrderRecord(
          reminderListExternalIdentifier: reminderListExternalIdentifier,
          orderedTopLevelReminderExternalIdentifiers: orderedReminderExternalIdentifiers,
          createdAt: now,
          updatedAt: now
        )
      ],
      projectRootStructureByReminderListExternalIdentifier: [:],
      projectFeatureSidecarByProjectID: [projectID: projectFeature],
      projectFeatureSidecarByReminderListExternalIdentifier: [
        reminderListExternalIdentifier: projectFeature
      ],
      taskFeatureSidecarByReminderExternalIdentifier: taskFeatureSidecars,
      taskSourceRuntimeStateByReminderExternalIdentifier: taskRuntimeStates,
      projectionEngine: .appSidecar
    )
  }

  func seededPerfTaskTitle(index: Int, profile: DebugTaskListPerfSeedProfile) -> String {
    if profile == .compact {
      switch index % 4 {
      case 0:
        return "Compact row \(index + 1) baseline"
      case 1:
        return "Compact row \(index + 1) date only"
      case 2:
        return "Compact row \(index + 1) truncation candidate for single-line fast path verification"
      default:
        return "Compact row \(index + 1) https://brainunfog.app/perf/compact/\(index)"
      }
    }
    switch index % 10 {
    case 0:
      return "Perf row \(index + 1) short title"
    case 1:
      return "Perf row \(index + 1) due date and trailing metadata coverage"
    case 2:
      return "Perf row \(index + 1) long title for truncation and stable right-aligned metadata behavior in the project detail list"
    case 3:
      return "Perf row \(index + 1) https://brainunfog.app/debug/perf/\(index)"
    case 4:
      return "Perf row \(index + 1) block reason candidate waiting on upstream reply"
    case 5:
      return "Perf row \(index + 1) note heavy row with multiline content"
    case 6:
      return "Perf row \(index + 1) timed reminder layout check"
    case 7:
      return "Perf row \(index + 1) required work days progress shell"
    case 8:
      return "Perf row \(index + 1) mixed metadata stress case"
    default:
      return "Perf row \(index + 1) baseline"
    }
  }

  func seededPerfTaskBlockReason(index: Int, profile: DebugTaskListPerfSeedProfile) -> String {
    switch profile {
    case .compact:
      return ""
    case .mixed:
      guard !index.isMultiple(of: 4) else { return "" }
    case .rich:
      break
    }
    switch index % 5 {
    case 0:
      return "Waiting"
    case 1:
      return "Need reply"
    case 2:
      return "Need file"
    case 3:
      return "Need decision"
    default:
      return ""
    }
  }

  func seededPerfTaskReminderNote(index: Int, profile: DebugTaskListPerfSeedProfile) -> String {
    switch profile {
    case .compact:
      return ""
    case .mixed:
      guard index.isMultiple(of: 7) else { return "" }
    case .rich:
      guard !index.isMultiple(of: 2) else { return "" }
    }
    return """
    Debug perf note \(index + 1)
    - verify inline detail reuse
    - verify read-only note rendering
    - linked reference: https://brainunfog.app/perf-note/\(index)
    """
  }

  func seededPerfTaskAppNote(index: Int, profile: DebugTaskListPerfSeedProfile) -> String {
    switch profile {
    case .compact:
      return ""
    case .mixed:
      return index.isMultiple(of: 23) ? "Note mirror \(index)" : ""
    case .rich:
      return index.isMultiple(of: 5) ? "Rich mirror note \(index)" : ""
    }
  }

  func seededPerfTaskRequiredWorkDays(index: Int, profile: DebugTaskListPerfSeedProfile) -> Int {
    switch profile {
    case .compact:
      return 0
    case .mixed:
      return index.isMultiple(of: 17) ? 2 + (index % 3) : 0
    case .rich:
      return index.isMultiple(of: 6) ? 2 + (index % 4) : 0
    }
  }

  func seededPerfTaskHasExplicitTime(index: Int, profile: DebugTaskListPerfSeedProfile) -> Bool {
    switch profile {
    case .compact:
      return index.isMultiple(of: 8)
    case .mixed:
      return index.isMultiple(of: 6)
    case .rich:
      return index.isMultiple(of: 3)
    }
  }

  func seededPerfTaskDueDate(
    index: Int,
    profile: DebugTaskListPerfSeedProfile,
    calendar: Calendar,
    startOfToday: Date
  ) -> Date? {
    guard !index.isMultiple(of: 3) else { return nil }
    let dayOffset = index % 31
    guard var dueDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
      return nil
    }
    if seededPerfTaskHasExplicitTime(index: index, profile: profile) {
      dueDate =
        calendar.date(
          bySettingHour: 9 + (index % 7),
          minute: (index % 4) * 15,
          second: 0,
          of: dueDate
        ) ?? dueDate
    }
    return dueDate
  }

  func seededPerfTaskStartDate(
    index: Int,
    dueDate: Date?,
    calendar: Calendar,
    startOfToday: Date
  ) -> Date? {
    guard index.isMultiple(of: 9) else { return nil }
    if let dueDate {
      return calendar.date(byAdding: .day, value: -2, to: dueDate)
    }
    return calendar.date(byAdding: .day, value: index % 14, to: startOfToday)
  }
}
#endif
