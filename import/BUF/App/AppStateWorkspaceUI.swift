import AppKit
import Foundation
import SwiftUI

extension AppState {
  var availableViewModes: [ViewMode] { ViewMode.coreWorkspaceModes }

  func registerWorkspaceProjectDetailEscapeHandler(
    id: UUID,
    handler: @escaping () -> Bool
  ) {
    workspaceProjectDetailEscapeHandlers[id] = handler
    workspaceProjectDetailEscapeHandlerOrder.append(id)
  }

  func unregisterWorkspaceProjectDetailEscapeHandler(id: UUID) {
    workspaceProjectDetailEscapeHandlers[id] = nil
    workspaceProjectDetailEscapeHandlerOrder.removeAll { $0 == id }
  }

  func consumeWorkspaceProjectDetailEscape() -> Bool {
    for id in workspaceProjectDetailEscapeHandlerOrder.reversed() {
      if workspaceProjectDetailEscapeHandlers[id]?() == true { return true }
    }
    return false
  }

  func isViewModeAvailable(_ mode: ViewMode) -> Bool {
    availableViewModes.contains(mode)
  }

  func selectViewMode(_ mode: ViewMode) {
    guard isViewModeAvailable(mode) else { return }
    viewMode = mode
    isArchiveVisible = false
  }

  func setShowsCompletedTasks(_ showsCompleted: Bool) {
    guard showsCompletedTasks != showsCompleted else { return }
    showsCompletedTasks = showsCompleted
    UserDefaults.standard.set(showsCompleted, forKey: Self.showCompletedTasksKey)
  }

  func handleViewMenuSelection(_ mode: ViewMode) {
    selectViewMode(mode)
  }

  func setArchiveVisibility(_ isVisible: Bool) {
    isArchiveVisible = false
    _ = isVisible
  }

  func handleWorkspaceSearchMenuCommand() {
    platformUIFoundation.windowManager.makeMainWindowKeyAndFront()
    NotificationCenter.default.post(name: .reminderAppFocusWorkspaceSearchRequested, object: nil)
  }

  func updateSearchText(_ text: String) {
    searchText = text
  }

  func clearSearchText() {
    searchText = ""
  }

  func openDetachedProjectWindow(projectID: UUID) {
    requestWorkspaceNavigation(.projectTop(projectID: projectID))
  }

  @discardableResult
  func focusDetachedProjectWindow(projectID: UUID) -> Bool {
    _ = projectID
    return false
  }

  func closeDetachedProjectWindow(projectID: UUID) {
    _ = projectID
  }

  func isProjectDetached(_ projectID: UUID) -> Bool {
    _ = projectID
    return false
  }

  func loadWorkspaceBoardsIfNeeded() {
    guard !boardsLoaded else { return }
    boardsLoaded = true
  }

  func jumpTimelineToToday() {
    timelineJumpToTodayToken &+= 1
  }

  func jumpScheduleToToday() {
    scheduleJumpToTodayToken &+= 1
  }

  func jumpSchedule(to date: Date) {
    scheduleJumpTargetDate = date
    scheduleJumpToDateToken &+= 1
    selectViewMode(.schedule)
  }

  func requestWorkspaceNavigation(_ target: WorkspaceNavigationTarget) {
    workspaceNavigationRequest = WorkspaceNavigationRequest(target: target)
  }

  func zoomOutTimelineDayColumn() {
    setTimelineDayColumnWidth(timelineDayColumnWidth - 6)
  }

  func zoomInTimelineDayColumn() {
    setTimelineDayColumnWidth(timelineDayColumnWidth + 6)
  }

  func canZoomOutTimelineDayColumn() -> Bool {
    timelineDayColumnWidth > minimumTimelineDayColumnWidth
  }

  func canZoomInTimelineDayColumn() -> Bool {
    timelineDayColumnWidth < maximumTimelineDayColumnWidth
  }

  func resetWorkspaceBoardLoading() {
    boardsLoaded = false
  }

  private func setTimelineDayColumnWidth(_ width: CGFloat) {
    timelineDayColumnWidth = min(max(width, minimumTimelineDayColumnWidth), maximumTimelineDayColumnWidth)
    UserDefaults.standard.set(Double(timelineDayColumnWidth), forKey: Self.timelineDayColumnWidthKey)
  }
}
