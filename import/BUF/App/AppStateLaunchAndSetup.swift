import AppKit
import Foundation
import SwiftData

extension AppState {
  func launch() async {
    isLaunching = true
    defer { isLaunching = false }

    applySetupPendingState()
    restoreLogseqGraphRootIfPossible()
    if let logseqGraphRootURL {
      do {
        try await prepareGraphLocalContainer(for: logseqGraphRootURL)
      } catch {
        storageCoordinator.clearActiveContainer()
        refreshContainerRootURL()
        errorMessage = error.localizedDescription
        syncStatus = "Graph storage failed"
      }
    }
    await requestRetainedExternalAccess()
    refreshContainerRootURL()
    await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true)
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
        await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true, startStartupSync: false)
      }
    } catch {
      storageCoordinator.clearActiveContainer()
      refreshContainerRootURL()
      reportError(error, logMessage: "configureLogseqGraphRoot failed")
    }
  }

  private func prepareGraphLocalContainer(for graphRootURL: URL) async throws {
    let containerRootURL = graphRootURL.appendingPathComponent(".buf", isDirectory: true)
    try await storageCoordinator.openOrInitializeContainer(at: containerRootURL)
    do {
      try LogseqGraphConfigStore(graphRootURL: graphRootURL).ensureInternalIdentityPropertiesHidden()
    } catch {
      AppLogger.sync.error(
        "logseq hidden property config update failed: \(error.localizedDescription, privacy: .public)"
      )
    }
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
    TaskIdentityBridgeStore.install(dataDirectory: storageCoordinator.paths?.dataDirectory)
  }

  func applySetupPendingState() {
    refreshContainerRootURL()
    reminderSourceObserver?.stop()
    reminderSourceObserver = nil
    stopLogseqPagesDirectoryWatcher()
    modelContainer = nil
    scheduleCalendarOverlayProjection = .empty
    isInitialSyncRunning = false
    syncStarted = false
    boardsLoaded = false
    syncStatus = isLogseqGraphConfigured ? "Container not opened" : "Logseq graph not configured"
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
        applyLogseqGraphRoot(resolvedURL)
        return
      } catch {
        AppLogger.storage.error(
          "restoreLogseqGraphRoot bookmark failed: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    if let path = UserDefaults.standard.string(forKey: Self.logseqGraphRootPathKey), !path.isEmpty {
      applyLogseqGraphRoot(URL(fileURLWithPath: path, isDirectory: true))
    }
  }

  private func applyLogseqGraphRoot(_ rootURL: URL) {
    _ = rootURL.startAccessingSecurityScopedResource()
    logseqGraphRootURL = rootURL
  }

  private func prepareWorkspaceIfSetupComplete(
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
      configureReminderSourceObservation()
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
