import AppKit
import SwiftUI

extension MainWorkspaceView {
  func toggleSyncQuickAddPopover() {
    guard !syncQuickAddProjects.isEmpty else {
      appState.errorMessage = "할일을 추가할 기본 목록이 없습니다."
      return
    }
    chromeState.toggleSyncQuickAddPopover()
  }

  func dismissSyncQuickAddPopover() {
    chromeState.dismissSyncQuickAddPopover()
    NSApp.keyWindow?.endEditing(for: nil)
  }

  func createSyncQuickAddTask(_ title: String, projectID: UUID) {
    Task { @MainActor in
      _ = await appState.createTask(
        inProjectID: projectID,
        title: title,
        startDate: Calendar.autoupdatingCurrent.startOfDay(for: .now),
        durationMinutes: nil,
        context: modelContext
      )
      selectProjectContext(projectID)
      dismissSyncQuickAddPopover()
    }
  }

  func submitSidebarNewProject(_ rawTitle: String) {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isCreatingSidebarProject else { return }
    isCreatingSidebarProject = true
    Task { @MainActor in
      let createdProjectID = await appState.createProjectList(named: title, context: modelContext)
      isCreatingSidebarProject = false
      showSidebarAddProjectPopover = false
      if let createdProjectID {
        selectProjectContext(createdProjectID)
      }
    }
  }

  func dismissInspectorSelection() {
    inspectorSelection = nil
    selectProjectContext(nil)
  }

  func revealTimelineTaskDetail(taskID: UUID, projectID: UUID) {
    _ = taskID
    openProjectPage(for: projectID)
  }

  func completeTimelineTask(_ taskID: UUID, projectID: UUID) {
    Task { @MainActor in
      _ = await appState.saveProjectDetailTaskCompletion(
        taskID: taskID,
        isCompleted: true,
        completionDate: .now,
        context: modelContext
      )
      selectProjectContext(projectID)
    }
  }

  func completeTimelinePlannedWork(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date? = nil
  ) {
    _ = taskID
    _ = targetCompletedUnits
    _ = projectID
    _ = completedOn
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "planned-work-progress")
  }

  func nonInspectorPassthroughRects(viewModePickerFrame: CGRect?) -> [CGRect] {
    viewModePickerFrame.map { [$0] } ?? []
  }

  func nonInspectorVisualExclusionRects(viewModePickerFrame: CGRect?) -> [CGRect] {
    nonInspectorPassthroughRects(viewModePickerFrame: viewModePickerFrame)
  }

  @ViewBuilder
  func nonInspectorDimOverlay(
    viewModePickerFrame: CGRect?,
    isVisible: Bool
  ) -> some View {
    if isVisible {
      Color.black.opacity(0.08)
        .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  func nonInspectorDimOverlay(
    visualExclusions: [CGRect],
    passthroughRects: [CGRect]
  ) -> some View {
    Color.black.opacity(0.08)
  }

  func archiveProjectFromList(_ projectID: UUID) {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "archive")
    _ = projectID
  }

  func performPermanentDelete(_ projectID: UUID) {
    Task { @MainActor in
      _ = await appState.deleteProjectPermanently(projectID, context: modelContext)
    }
  }

  var pendingProjectDeleteDialogBinding: Binding<Bool> {
    Binding(
      get: { pendingPermanentDeleteProject != nil },
      set: { isPresented in
        if !isPresented {
          pendingPermanentDeleteProject = nil
        }
      }
    )
  }

  func moveProjects(from source: IndexSet, to destination: Int) {
    _ = source
    _ = destination
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "project-ordering")
  }

  func moveTaskToProjectFromSidebar(_ taskID: UUID, targetProjectID: UUID) {
    _ = taskID
    _ = targetProjectID
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "task-move")
  }

  func installLocalKeyMonitor() {
    guard localKeyMonitor == nil else { return }
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handleKeyDown(event)
    }
  }

  func removeLocalKeyMonitor() {
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
    }
    localKeyMonitor = nil
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if event.keyCode == 53 {
      if !chromeState.workspaceSearchQuery.isEmpty {
        clearWorkspaceSearch()
        return nil
      }
      if inspectorSelection != nil {
        dismissInspectorSelection()
        return nil
      }
    }
    return event
  }

  func presentInitialSyncAlertIfNeeded() {
    guard appState.shouldPromptForInitialSyncConsent else { return }
    showInitialSyncAlert = true
  }
}
