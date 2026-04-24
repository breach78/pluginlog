import AppKit
import Foundation
import SwiftData

enum OutlinerCacheWarmupPolicy {
  static let maxWarmupProjectCount = 4

  static func visibleProjectIDs(
    selectedProjectID: UUID?,
    detachedProjectIDs: some Sequence<UUID>
  ) -> [UUID] {
    var seen: Set<UUID> = []
    var ordered: [UUID] = []

    if let selectedProjectID, seen.insert(selectedProjectID).inserted {
      ordered.append(selectedProjectID)
    }

    for projectID in detachedProjectIDs where seen.insert(projectID).inserted {
      ordered.append(projectID)
    }

    return Array(ordered.prefix(maxWarmupProjectCount))
  }

  static func shouldScheduleWarmup(
    hasModelContainer: Bool,
    hasWarmupTask: Bool,
    visibleProjectIDs: [UUID]
  ) -> Bool {
    hasModelContainer && !hasWarmupTask && !visibleProjectIDs.isEmpty
  }
}

extension AppState {
  /// Boots storage, restores persisted setup, and prepares the workspace for first render.
  func launch() async {
    isLaunching = true
    defer { isLaunching = false }

    applySetupPendingState()
    isInitialSyncRunning = false
    syncStarted = false
    resetWorkspaceBoardLoading()

    restoreLogseqGraphRootIfPossible()
    if let logseqGraphRootURL {
      do {
        try await prepareGraphLocalContainer(for: logseqGraphRootURL)
      } catch {
        storageCoordinator.clearActiveContainer()
        refreshContainerRootURL()
        errorMessage = error.localizedDescription
        syncStatus = "Graph storage failed"
        AppLogger.storage.error(
          "graph-local container open failed: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
    await requestRetainedExternalAccess()
    refreshContainerRootURL()

    await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true)
  }

  /// Creates the on-disk app container and optionally continues directly into workspace startup.
  func initializeContainer(at rootURL: URL, activateWhenReady: Bool = true) async {
    do {
      try await storageCoordinator.initializeContainer(at: rootURL)
      refreshContainerRootURL()
      if activateWhenReady {
        await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: false)
      } else {
        applySetupPendingState()
      }
    } catch {
      errorMessage = error.localizedDescription
      AppLogger.storage.error(
        "initializeContainer failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Moves the existing container to a new root and refreshes dependent resources.
  func relocateContainer(to url: URL) async {
    do {
      try await storageCoordinator.relocateContainer(to: url)
      refreshContainerRootURL()
      await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: false)
    } catch {
      errorMessage = error.localizedDescription
      AppLogger.storage.error(
        "relocateContainer failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Stores the security-scoped Obsidian folder bookmark used for project note sync.
  func configureObsidianProjectsFolder(at rootURL: URL, activateWhenReady: Bool = true) async {
    do {
      let bookmarkData = try rootURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmarkData, forKey: Self.obsidianBookmarkDataKey)
      UserDefaults.standard.set(rootURL.path, forKey: Self.obsidianRootPathKey)
      applyObsidianProjectsFolder(rootURL)
      if activateWhenReady {
        await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true)
      } else {
        applySetupPendingState()
      }
    } catch {
      errorMessage = error.localizedDescription
      AppLogger.storage.error(
        "configureObsidianProjectsFolder failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Stores the security-scoped Logseq graph root bookmark used for project page deep links.
  func configureLogseqGraphRoot(at rootURL: URL, activateWhenReady: Bool = true) async {
    do {
      let bookmarkData = try rootURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmarkData, forKey: Self.logseqGraphBookmarkDataKey)
      UserDefaults.standard.set(rootURL.path, forKey: Self.logseqGraphRootPathKey)
      applyLogseqGraphRoot(rootURL)
      try await prepareGraphLocalContainer(for: rootURL)
      enableRetainedSyncConsent()
      await requestRetainedExternalAccess()
      if activateWhenReady {
        await prepareWorkspaceIfSetupComplete(
          shouldRefreshHealth: true,
          startStartupSync: false
        )
      } else {
        applySetupPendingState()
      }
    } catch {
      storageCoordinator.clearActiveContainer()
      refreshContainerRootURL()
      errorMessage = error.localizedDescription
      AppLogger.storage.error(
        "configureLogseqGraphRoot failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func prepareGraphLocalContainer(for graphRootURL: URL) async throws {
    let containerRootURL = graphRootURL.appendingPathComponent(".buf", isDirectory: true)
    try await storageCoordinator.openOrInitializeContainer(at: containerRootURL)
    refreshContainerRootURL()
    enableRetainedSyncConsent()
  }

  private func enableRetainedSyncConsent() {
    hasInitialSyncConsent = true
    hasSyncConsentDecision = true
    UserDefaults.standard.set(true, forKey: Self.initialSyncConsentGrantedKey)
    UserDefaults.standard.set(true, forKey: Self.initialSyncConsentDecidedKey)
  }

  func requestRetainedExternalAccess() async {
    _ = await calendarServiceRegistry.scheduleCalendarService.requestCalendarAccessOnceIfNeeded()
    do {
      _ = try await reminderProjectProvider.requestAccess()
    } catch {
      AppLogger.sync.error(
        "reminders access request failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  func setInitialSyncConsentPreference(granted: Bool, activateWhenReady: Bool = true) {
    hasInitialSyncConsent = granted
    hasSyncConsentDecision = true
    UserDefaults.standard.set(granted, forKey: Self.initialSyncConsentGrantedKey)
    UserDefaults.standard.set(true, forKey: Self.initialSyncConsentDecidedKey)

    if !granted {
      syncStatus = "Refresh paused"
    }

    guard activateWhenReady else {
      applySetupPendingState()
      return
    }

    if modelContainer == nil {
      Task { @MainActor [weak self] in
        await self?.prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true)
      }
      return
    }

    if granted && !syncStarted && !isInitialSyncRunning {
      refreshReminderSourceNow()
    }
  }

  func requestStartupSyncIfNeeded() {
#if DEBUG
    guard !Self.isDebugTaskListPerfLaunchRequested else { return }
#endif
    guard modelContainer != nil else { return }
    guard reminderSourceObserver != nil else { return }
    guard hasSyncConsentDecision else { return }
    guard hasInitialSyncConsent else {
      syncStatus = "Refresh paused"
      return
    }
    guard !syncStarted else { return }
    guard !isInitialSyncRunning else { return }
    refreshReminderSourceNow()
  }

  func refreshHealth() async {
    containerHealth = await storageCoordinator.healthStatus()
  }

  func completeInitialSetupAndLaunch() async {
    await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true)
  }

  private func refreshContainerRootURL() {
    containerRootURL = storageCoordinator.paths?.root
  }

  func applySetupPendingState() {
    refreshContainerRootURL()
    reminderSourceObserver?.stop()
    outlinerCacheWarmupTask?.cancel()
    outlinerCacheWarmupTask = nil
    modelContainer = nil
    cachedOutlinerSessionSnapshot = nil
    cachedOutlinerRuntimeProjectionSnapshot = nil
    scheduleCalendarOverlayProjection = .empty
    isOutlinerProjectionBootstrapPending = true
    TaskIdentityBridgeStore.reset()
    ArchivedProjectBundleOwner.reset()
    attachmentStore = nil
    archiveService = nil
    reminderSyncEditGate = nil
    reminderSyncRecoveryJournal = nil
    reminderSourceObserver = nil
    isInitialSyncRunning = false
    syncStarted = false
    resetWorkspaceBoardLoading()
    refreshPrivateObsidianStores()

    if !isLogseqGraphConfigured {
      syncStatus = "Logseq graph not configured"
    } else if requiresObsidianVaultSetup && !isObsidianFolderConfigured {
      syncStatus = "Obsidian vault not configured"
    } else if !isContainerConfigured {
      syncStatus = "Container not opened"
    } else if !hasSyncConsentDecision {
      syncStatus = "Waiting for reminder preference"
    } else if !hasInitialSyncConsent {
      syncStatus = "Refresh paused"
    } else {
      syncStatus = "Ready"
    }
  }

  func prepareWorkspaceIfSetupComplete(
    shouldRefreshHealth: Bool,
    startStartupSync: Bool = true
  ) async {
    guard hasCompletedInitialSetup else {
      applySetupPendingState()
      if shouldRefreshHealth {
        await refreshHealth()
      }
      return
    }

    do {
      try await prepareContainerDependentResources(
        shouldRefreshHealth: shouldRefreshHealth,
        startStartupSync: startStartupSync
      )
    } catch {
      errorMessage = error.localizedDescription
      syncStatus = "Setup failed"
      AppLogger.storage.error(
        "prepareWorkspaceIfSetupComplete failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func restoreLogseqGraphRootIfPossible() {
    if let bookmarkData = UserDefaults.standard.data(forKey: Self.logseqGraphBookmarkDataKey) {
      do {
        var isStale = false
        let resolvedURL = try URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )

        if isStale {
          let refreshedBookmark = try resolvedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          )
          UserDefaults.standard.set(refreshedBookmark, forKey: Self.logseqGraphBookmarkDataKey)
        }

        UserDefaults.standard.set(resolvedURL.path, forKey: Self.logseqGraphRootPathKey)
        applyLogseqGraphRoot(resolvedURL)
        return
      } catch {
        AppLogger.storage.error(
          "restoreLogseqGraphRoot bookmark failed: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    if let path = UserDefaults.standard.string(forKey: Self.logseqGraphRootPathKey), !path.isEmpty {
      let url = URL(fileURLWithPath: path, isDirectory: true)
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        applyLogseqGraphRoot(url)
        return
      }
    }

    clearLogseqGraphRoot()
  }

  private func restoreObsidianProjectsFolderIfPossible() {
    if let bookmarkData = UserDefaults.standard.data(forKey: Self.obsidianBookmarkDataKey) {
      do {
        var isStale = false
        let resolvedURL = try URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )

        if isStale {
          let refreshedBookmark = try resolvedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          )
          UserDefaults.standard.set(refreshedBookmark, forKey: Self.obsidianBookmarkDataKey)
        }

        UserDefaults.standard.set(resolvedURL.path, forKey: Self.obsidianRootPathKey)
        applyObsidianProjectsFolder(resolvedURL)
        return
      } catch {
        AppLogger.storage.error(
          "restoreObsidianProjectsFolder bookmark failed: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    if let path = UserDefaults.standard.string(forKey: Self.obsidianRootPathKey), !path.isEmpty {
      let url = URL(fileURLWithPath: path, isDirectory: true)
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        applyObsidianProjectsFolder(url)
        return
      }
    }

    clearObsidianProjectsFolder()
  }

  func applyLogseqGraphRoot(_ rootURL: URL) {
    if logseqSecurityScopedURL?.path != rootURL.path {
      logseqSecurityScopedURL?.stopAccessingSecurityScopedResource()
      logseqSecurityScopedURL = nil

      if rootURL.startAccessingSecurityScopedResource() {
        logseqSecurityScopedURL = rootURL
      }
    }

    logseqGraphRootURL = rootURL
  }

  private func clearLogseqGraphRoot() {
    logseqSecurityScopedURL?.stopAccessingSecurityScopedResource()
    logseqSecurityScopedURL = nil
    logseqGraphRootURL = nil
  }

  func applyObsidianProjectsFolder(_ rootURL: URL) {
    if isPrivateObsidianFeaturesEnabled {
      if obsidianSecurityScopedURL?.path != rootURL.path {
        obsidianSecurityScopedURL?.stopAccessingSecurityScopedResource()
        obsidianSecurityScopedURL = nil

        if rootURL.startAccessingSecurityScopedResource() {
          obsidianSecurityScopedURL = rootURL
        }
      }
    } else {
      obsidianSecurityScopedURL?.stopAccessingSecurityScopedResource()
      obsidianSecurityScopedURL = nil
    }

    obsidianProjectsRootURL = rootURL
    refreshPrivateObsidianStores()
  }

  private func clearObsidianProjectsFolder() {
    obsidianSecurityScopedURL?.stopAccessingSecurityScopedResource()
    obsidianSecurityScopedURL = nil
    obsidianProjectsRootURL = nil
    refreshPrivateObsidianStores()
  }

  private func startDataStackIfPossible() async throws {
    guard let paths = storageCoordinator.paths else {
      TaskIdentityBridgeStore.reset()
      ArchivedProjectBundleOwner.reset()
      return
    }

    try storageCoordinator.validateStructure()
    try RuntimeSidecarSQLiteBootstrap.ensureInstalled(
      databaseURL: paths.normalizedSQLiteURL,
      ensureWorkspaceRoot: true
    )
    reminderSourceObserver?.stop()
    reminderSourceObserver = nil
    TaskIdentityBridgeStore.install(dataDirectory: paths.dataDirectory)
    ArchivedProjectBundleOwner.install(dataDirectory: paths.dataDirectory)

    outlinerCacheWarmupTask?.cancel()
    outlinerCacheWarmupTask = nil
    cachedOutlinerSessionSnapshot = nil
    cachedOutlinerRuntimeProjectionSnapshot = nil
    isOutlinerProjectionBootstrapPending = true
    let attachmentStore = LocalAttachmentStore(
      storage: storageCoordinator,
      runtimeSnapshotProvider: { [weak self] in
        self?.cachedOutlinerRuntimeProjectionSnapshot
      }
    )
    self.attachmentStore = attachmentStore
    let documentReferenceRepository = NormalizedDocumentReferenceRepository(
      databaseURL: paths.normalizedSQLiteURL
    )
    self.documentReferenceRepository = documentReferenceRepository
    self.workspaceTreeRepository = WorkspaceTreeRepository(databaseURL: paths.normalizedSQLiteURL)
    self.documentReferenceImporter = SecurityScopedDocumentReferenceImporter(
      repository: documentReferenceRepository
    )
    self.documentReferenceAccessService = SecurityScopedDocumentReferenceAccessService(
      repository: documentReferenceRepository
    )
    let presenterPool = DocumentReferencePresenterPool()
    self.documentReferencePresenterPool = presenterPool
    startDocumentReferenceObservationIfNeeded(presenterPool: presenterPool)

    let archiveService = DefaultArchiveService()
    self.archiveService = archiveService
    let reminderSyncEditGate = ReminderSyncEditGate(
      fileURL: paths.dataDirectory.appendingPathComponent("reminder-sync-edit-gate.json")
    )
    self.reminderSyncEditGate = reminderSyncEditGate
    sweepReminderSyncEditSessionsIfNeeded()
    let reminderSyncRecoveryJournal = ReminderSyncRecoveryJournalStore(
      fileURL: paths.dataDirectory.appendingPathComponent("reminder-sync-recovery-journal.json")
    )
    self.reminderSyncRecoveryJournal = reminderSyncRecoveryJournal

    let stack = try DataStack(sqliteURL: paths.sqliteURL)
    modelContainer = stack.modelContainer
    let reminderSourceObserver = ReminderSourceObserver(
      gateway: reminderGateway,
      invalidateSource: { [weak self] reason in
        guard let self else { return false }
        return await self.handleReminderSourceInvalidation(reason: reason)
      },
      handleExternalOwnerChange: { [weak self] command in
        guard let self else { return false }
        return await self.send(command)
      }
    )
    self.reminderSourceObserver = reminderSourceObserver

    isInitialSyncRunning = false
    syncStarted = false
    loadWorkspaceBoardsIfNeeded()
    didAutoBootstrapSync = false
  }

  // Shared post-container setup to keep launch/init/relocate behavior aligned.
  private func prepareContainerDependentResources(
    shouldRefreshHealth: Bool,
    startStartupSync: Bool
  ) async throws {
    try await startDataStackIfPossible()
#if DEBUG
    try seedDebugTaskListPerfProjectIfRequested()
#endif
    refreshPrivateObsidianStores()
    if isPrivateObsidianFeaturesEnabled {
      await prepareJournalStore()
    }
    if startStartupSync {
      requestStartupSyncIfNeeded()
    }
    if shouldRefreshHealth {
      await refreshHealth()
    }
    scheduleOutlinerCacheWarmupIfNeeded()
  }

  func scheduleOutlinerCacheWarmupIfNeeded(delay: Duration = .milliseconds(250)) {
    guard modelContainer != nil else { return }
    guard outlinerCacheWarmupTask == nil else { return }
    guard hasInitialSyncConsent else { return }

    outlinerCacheWarmupTask = Task { @MainActor [weak self] in
      defer {
        self?.outlinerCacheWarmupTask = nil
      }

      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      guard let self, !Task.isCancelled, self.modelContainer != nil else { return }
      guard !Task.isCancelled else { return }
      guard self.hasInitialSyncConsent, let runtimeSnapshot = self.cachedOutlinerRuntimeProjectionSnapshot else {
        return
      }
      _ = await self.recomputeCachedRuntimeProjectionProjects(
        Set(runtimeSnapshot.projects.map(\.id))
      )
    }
  }
}
