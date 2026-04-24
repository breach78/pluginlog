import AppKit
import Foundation

extension AppState {
  func registerWorkspaceProjectDetailEscapeHandler(
    id: UUID,
    handler: @escaping () -> Bool
  ) {
    workspaceProjectDetailEscapeHandlers[id] = handler
    workspaceProjectDetailEscapeHandlerOrder.removeAll { $0 == id }
    workspaceProjectDetailEscapeHandlerOrder.append(id)
  }

  func unregisterWorkspaceProjectDetailEscapeHandler(id: UUID) {
    workspaceProjectDetailEscapeHandlers.removeValue(forKey: id)
    workspaceProjectDetailEscapeHandlerOrder.removeAll { $0 == id }
  }

  func consumeWorkspaceProjectDetailEscape() -> Bool {
    for id in workspaceProjectDetailEscapeHandlerOrder.reversed() {
      guard let handler = workspaceProjectDetailEscapeHandlers[id] else { continue }
      if handler() {
        return true
      }
    }
    return false
  }

  var availableViewModes: [ViewMode] {
    ViewMode.coreWorkspaceModes
  }

  func isViewModeAvailable(_ mode: ViewMode) -> Bool {
    availableViewModes.contains(mode)
  }

  func saveGeminiAPIKey(_ rawValue: String) {
    do {
      try geminiAPIKeyStore.saveAPIKey(rawValue)
      refreshGeminiAPIKeyStatus()
    } catch {
      reportError(error, logMessage: "saveGeminiAPIKey failed")
    }
  }

  func clearGeminiAPIKey() {
    do {
      try geminiAPIKeyStore.deleteAPIKey()
      refreshGeminiAPIKeyStatus()
    } catch {
      reportError(error, logMessage: "clearGeminiAPIKey failed")
    }
  }

  func saveGeminiSummaryModelName(_ rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolved =
      trimmed.isEmpty ? GeminiGenerateContentSummaryService.defaultModelName : trimmed
    geminiSummaryModelName = resolved
    UserDefaults.standard.set(resolved, forKey: Self.geminiSummaryModelNameKey)
  }

  func selectViewMode(_ mode: ViewMode) {
    guard isViewModeAvailable(mode) else {
      guard viewMode != .timeline else { return }
      viewMode = .timeline
      return
    }
    guard viewMode != mode else { return }
    viewMode = mode
  }

  func handleViewMenuSelection(_ mode: ViewMode) {
    platformUIFoundation.windowManager.makeMainWindowKeyAndFront()
    selectViewMode(mode)
  }

  func setArchiveVisibility(_ isVisible: Bool) {
    platformUIFoundation.windowManager.makeMainWindowKeyAndFront()
    guard isArchiveVisible != isVisible else { return }
    isArchiveVisible = isVisible
  }

  func setPrivateObsidianFeaturesEnabled(_ enabled: Bool) {
    guard isPrivateObsidianFeaturesEnabled != enabled else { return }
    isPrivateObsidianFeaturesEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: Self.privateObsidianFeaturesEnabledKey)
    if let obsidianProjectsRootURL {
      applyObsidianProjectsFolder(obsidianProjectsRootURL)
    } else {
      refreshPrivateObsidianStores()
    }

    if !isViewModeAvailable(viewMode) {
      viewMode = .timeline
    }

    if hasCompletedInitialSetup {
      if modelContainer == nil {
        Task { @MainActor in
          await prepareWorkspaceIfSetupComplete(shouldRefreshHealth: true)
        }
      } else if enabled {
        Task { @MainActor in
          await prepareJournalStore()
        }
      }
    } else {
      applySetupPendingState()
    }
  }

  func handleWorkspaceSearchMenuCommand() {
    platformUIFoundation.windowManager.makeMainWindowKeyAndFront()
    NotificationCenter.default.post(
      name: .reminderAppFocusWorkspaceSearchRequested,
      object: nil
    )
  }

  func updateSearchText(_ text: String) {
    guard searchText != text else { return }
    searchText = text
  }

  func clearSearchText() {
    updateSearchText("")
  }

  func openDetachedProjectWindow(projectID: UUID) {
    guard let modelContainer else { return }

    if focusDetachedProjectWindow(projectID: projectID) {
      return
    }

    let controller = DetachedProjectWindowController(
      projectID: projectID,
      appState: self,
      modelContainer: modelContainer
    )
    controller.onWillClose = { [weak self, weak controller] closedController in
      guard let self, let controller else { return }
      if self.detachedProjectWindowRegistry[controller.projectID] === controller
        && controller === closedController
      {
        self.detachedProjectWindowRegistry.removeValue(forKey: controller.projectID)
      }
    }
    detachedProjectWindowRegistry[projectID] = controller
    controller.present(appState: self, modelContainer: modelContainer)
  }

  @discardableResult
  func focusDetachedProjectWindow(projectID: UUID) -> Bool {
    guard let controller = detachedProjectWindowRegistry[projectID], let modelContainer else { return false }
    controller.present(appState: self, modelContainer: modelContainer)
    return true
  }

  func closeDetachedProjectWindow(projectID: UUID) {
    guard let controller = detachedProjectWindowRegistry[projectID] else { return }
    detachedProjectWindowRegistry.removeValue(forKey: projectID)
    controller.close()
  }

  func isProjectDetached(_ projectID: UUID) -> Bool {
    detachedProjectWindowRegistry[projectID] != nil
  }

  func loadWorkspaceBoardsIfNeeded() {
    setBoardsLoaded(true)
  }

  func jumpTimelineToToday() {
    loadWorkspaceBoardsIfNeeded()
    selectViewMode(.timeline)
    timelineJumpToTodayToken += 1
  }

  func saveOpenAIAPIKey(_ rawValue: String) {
    do {
      try openAIAPIKeyStore.saveAPIKey(rawValue)
      refreshOpenAIAPIKeyStatus()
    } catch {
      reportError(error, logMessage: "saveOpenAIAPIKey failed")
    }
  }

  func clearOpenAIAPIKey() {
    do {
      try openAIAPIKeyStore.deleteAPIKey()
      refreshOpenAIAPIKeyStatus()
    } catch {
      reportError(error, logMessage: "clearOpenAIAPIKey failed")
    }
  }

  func jumpScheduleToToday() {
    loadWorkspaceBoardsIfNeeded()
    selectViewMode(.schedule)
    scheduleJumpTargetDate = nil
    scheduleJumpToTodayToken += 1
  }

  func jumpSchedule(to date: Date) {
    loadWorkspaceBoardsIfNeeded()
    selectViewMode(.schedule)
    scheduleJumpTargetDate = Calendar.autoupdatingCurrent.startOfDay(for: date)
    scheduleJumpToDateToken += 1
  }

  func requestWorkspaceNavigation(_ target: WorkspaceNavigationTarget) {
    workspaceNavigationRequest = WorkspaceNavigationRequest(target: target)
  }

  func zoomOutTimelineDayColumn() {
    setTimelineDayColumnWidth(minimumTimelineDayColumnWidth)
  }

  func zoomInTimelineDayColumn() {
    setTimelineDayColumnWidth(defaultTimelineDayColumnWidth)
  }

  func canZoomOutTimelineDayColumn() -> Bool {
    timelineDayColumnWidth > minimumTimelineDayColumnWidth + 0.5
  }

  func canZoomInTimelineDayColumn() -> Bool {
    abs(timelineDayColumnWidth - defaultTimelineDayColumnWidth) > 0.5
  }

  func resetWorkspaceBoardLoading() {
    setBoardsLoaded(false)
  }

  private func setTimelineDayColumnWidth(_ width: CGFloat) {
    guard abs(timelineDayColumnWidth - width) > 0.01 else { return }
    timelineDayColumnWidth = width
    UserDefaults.standard.set(Double(width), forKey: Self.timelineDayColumnWidthKey)
  }

  private func setBoardsLoaded(_ isLoaded: Bool) {
    guard boardsLoaded != isLoaded else { return }
    boardsLoaded = isLoaded
  }

  func refreshAPIKeyStatusesInBackground() {
    let geminiAPIKeyStore = geminiAPIKeyStore
    let openAIAPIKeyStore = openAIAPIKeyStore

    Task.detached(priority: .utility) {
      func loadStatus(_ loadAPIKey: () throws -> String?) -> (hasKey: Bool, errorMessage: String?) {
        do {
          let storedKey = try loadAPIKey()
          return (
            storedKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            nil
          )
        } catch {
          return (false, error.localizedDescription)
        }
      }

      let geminiStatus = loadStatus(geminiAPIKeyStore.loadAPIKey)
      let openAIStatus = loadStatus(openAIAPIKeyStore.loadAPIKey)

      await MainActor.run { [weak self] in
        guard let self else { return }
        hasGeminiAPIKey = geminiStatus.hasKey
        hasOpenAIAPIKey = openAIStatus.hasKey

        if let errorMessage = geminiStatus.errorMessage {
          AppLogger.app.error("refreshGeminiAPIKeyStatus failed: \(errorMessage, privacy: .public)")
        }
        if let errorMessage = openAIStatus.errorMessage {
          AppLogger.app.error("refreshOpenAIAPIKeyStatus failed: \(errorMessage, privacy: .public)")
        }
      }
    }
  }

  func refreshOpenAIAPIKeyStatus() {
    do {
      let storedKey = try openAIAPIKeyStore.loadAPIKey()
      hasOpenAIAPIKey = storedKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    } catch {
      hasOpenAIAPIKey = false
      AppLogger.app.error(
        "refreshOpenAIAPIKeyStatus failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  func refreshGeminiAPIKeyStatus() {
    do {
      let storedKey = try geminiAPIKeyStore.loadAPIKey()
      hasGeminiAPIKey = storedKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    } catch {
      hasGeminiAPIKey = false
      AppLogger.app.error(
        "refreshGeminiAPIKeyStatus failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
