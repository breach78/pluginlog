import AppKit
import Foundation
import SwiftData

extension AppState {
  func launch() async {
    isLaunching = true
    defer { isLaunching = false }

    if let uiTestConfiguration = AppUITestRuntime.Configuration() {
      await launchUITestRuntime(configuration: uiTestConfiguration)
      return
    }

    applySetupPendingState()
    restoreObsidianVaultIfPossible()
    if let obsidianVaultRootURL {
      do {
        try await prepareObsidianLocalContainer(for: obsidianVaultRootURL)
      } catch {
        storageCoordinator.clearActiveContainer()
        refreshContainerRootURL()
        errorMessage = error.localizedDescription
        syncStatus = "Vault storage failed"
      }
    }
    refreshContainerRootURL()
    await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true, startStartupSync: false)
    await requestRetainedExternalAccess()
    requestStartupSyncIfNeeded()
  }

  func initializeContainer(at rootURL: URL, activateWhenReady: Bool = true) async {
    do {
      try await storageCoordinator.initializeContainer(at: rootURL)
      refreshContainerRootURL()
      if activateWhenReady {
        await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: false)
      }
    } catch {
      reportError(error, logMessage: "initializeContainer failed")
    }
  }

  func relocateContainer(to url: URL) async {
    await initializeContainer(at: url)
  }

  func chooseObsidianVaultWithPicker(activateWhenReady: Bool = true) async {
    do {
      let urls = try await platformUIFoundation.pathPicker.pick(
        request: PlatformPathPickerRequest(
          kind: .directory,
          message: "Vault 루트를 선택해 주세요."
        )
      )
      guard let rootURL = urls.first else { return }
      await configureObsidianVault(at: rootURL, activateWhenReady: activateWhenReady)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func configureObsidianVault(at rootURL: URL, activateWhenReady: Bool = true) async {
    let previousContainerRootURL = containerRootURL
      let previousContainerPreferenceSnapshot = ContainerPreferenceSnapshot.capture()
    do {
      didAutoBootstrapSync = false
      reminderSourceObserver?.stop()
      reminderSourceObserver = nil
      _ = rootURL.startAccessingSecurityScopedResource()
      try await prepareObsidianLocalContainer(for: rootURL)
      let bookmarkData = try rootURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmarkData, forKey: Self.obsidianVaultBookmarkDataKey)
      UserDefaults.standard.set(rootURL.path, forKey: Self.obsidianVaultRootPathKey)
      applyObsidianVault(rootURL)
      enableRetainedSyncConsent()
      await requestRetainedExternalAccess()
      guard await performReminderSourceRefresh(reason: .bootstrap) else {
        throw ObsidianVaultSetupError.bootstrapFailed(syncStatus)
      }
      didAutoBootstrapSync = true
      if activateWhenReady {
        await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true, startStartupSync: false)
      }
    } catch {
      obsidianVaultRootURL = nil
      UserDefaults.standard.removeObject(forKey: Self.obsidianVaultBookmarkDataKey)
      UserDefaults.standard.removeObject(forKey: Self.obsidianVaultRootPathKey)
      previousContainerPreferenceSnapshot.restore()
      if let previousContainerRootURL {
        try? await storageCoordinator.openOrInitializeContainer(at: previousContainerRootURL)
      } else {
        storageCoordinator.clearActiveContainer()
      }
      refreshContainerRootURL()
      reportError(error, logMessage: "configureObsidianVault failed")
    }
  }

  private func prepareObsidianLocalContainer(for vaultRootURL: URL) async throws {
    let layout = ObsidianVaultLayout(vaultRootURL: vaultRootURL)
    try layout.prepareAppDirectories()
    try await storageCoordinator.openOrInitializeContainer(at: layout.sidecarRootURL)
    refreshContainerRootURL()
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
    syncStatus = granted ? "Ready" : "Refresh paused"
    guard activateWhenReady else { return }
    Task { @MainActor [weak self] in
      await self?.prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true)
    }
  }

  func requestStartupSyncIfNeeded() {
    guard hasCompletedInitialSetup else { return }
    guard hasInitialSyncConsent else {
      syncStatus = "Refresh paused"
      return
    }
    guard !didAutoBootstrapSync else { return }
    didAutoBootstrapSync = true
    refreshReminderSourceNow(reason: .bootstrap)
  }

  func refreshHealth() async {
    containerHealth = await storageCoordinator.healthStatus()
  }

  func completeInitialSetupAndLaunch() async {
    await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true)
  }

  func refreshContainerRootURL() {
    containerRootURL = storageCoordinator.paths?.root
    TaskIdentityBridgeStore.install(dataDirectory: storageCoordinator.paths?.dataDirectory)
    ReminderPendingBindingStore.install(dataDirectory: storageCoordinator.paths?.dataDirectory)
    ReminderDeletedTaskTombstoneStore.install(dataDirectory: storageCoordinator.paths?.dataDirectory)
    ReminderSyncBaselineStore.install(dataDirectory: storageCoordinator.paths?.dataDirectory)
  }

  func applySetupPendingState() {
    refreshContainerRootURL()
    reminderSourceObserver?.stop()
    reminderSourceObserver = nil
    modelContainer = nil
    scheduleCalendarOverlayProjection = .empty
    isInitialSyncRunning = false
    syncStarted = false
    didAutoBootstrapSync = false
    boardsLoaded = false
    syncStatus = isObsidianVaultConfigured
      ? "Container not opened"
      : "Project store not configured"
  }

  private func restoreObsidianVaultIfPossible() {
    let bookmarkData = UserDefaults.standard.data(forKey: Self.obsidianVaultBookmarkDataKey)
    let resolution = ObsidianVaultPreferenceResolver.resolve(
      storedPath: UserDefaults.standard.string(forKey: Self.obsidianVaultRootPathKey),
      bookmarkData: bookmarkData,
      resolveBookmark: { bookmarkData in
        var isStale = false
        return try URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
      }
    )

    guard let resolution else {
      if bookmarkData != nil {
        AppLogger.storage.error("restoreObsidianVault bookmark failed and no stored path exists")
      }
      return
    }

    if resolution.didPreferStoredPathOverBookmark {
      AppLogger.storage.error(
        "restoreObsidianVault preferred stored path over mismatched bookmark path=\(resolution.url.path, privacy: .public)"
      )
    }
    applyObsidianVault(resolution.url)
  }

  private func applyObsidianVault(_ rootURL: URL) {
    _ = rootURL.startAccessingSecurityScopedResource()
    obsidianVaultRootURL = rootURL
  }

  func prepareWorkspaceIfSetupComplete(
    shouldRefreshHealth: Bool,
    startStartupSync: Bool = true
  ) async {
    guard hasCompletedInitialSetup else {
      if shouldRefreshHealth { await refreshHealth() }
      return
    }

    do {
      modelContainer = try ModelContainer(for: Schema([]), configurations: [])
      if shouldRefreshHealth { await refreshHealth() }
      await prepareProjectNoteStore()
      reminderSourceObserver?.stop()
      reminderSourceObserver = nil
      if hasInitialSyncConsent {
        configureReminderSourceObservation()
      }
      boardsLoaded = true
      syncStatus = "Ready"
      if startStartupSync {
        requestStartupSyncIfNeeded()
      }
    } catch {
      reportError(error, logMessage: "prepareWorkspaceIfSetupComplete failed")
      syncStatus = "Setup failed"
    }
  }
}

private enum ObsidianVaultSetupError: LocalizedError {
  case bootstrapFailed(String)

  var errorDescription: String? {
    switch self {
    case .bootstrapFailed(let status):
      "Vault bootstrap failed before setup could complete: \(status)"
    }
  }
}

private struct ContainerPreferenceSnapshot {
  private static let bookmarkDataKey = "container.bookmarkData"
  private static let rootPathKey = "container.rootPath"

  let bookmarkData: Data?
  let rootPath: String?

  static func capture(defaults: UserDefaults = .standard) -> ContainerPreferenceSnapshot {
    ContainerPreferenceSnapshot(
      bookmarkData: defaults.data(forKey: bookmarkDataKey),
      rootPath: defaults.string(forKey: rootPathKey)
    )
  }

  func restore(defaults: UserDefaults = .standard) {
    if let bookmarkData {
      defaults.set(bookmarkData, forKey: Self.bookmarkDataKey)
    } else {
      defaults.removeObject(forKey: Self.bookmarkDataKey)
    }

    if let rootPath {
      defaults.set(rootPath, forKey: Self.rootPathKey)
    } else {
      defaults.removeObject(forKey: Self.rootPathKey)
    }
  }
}
