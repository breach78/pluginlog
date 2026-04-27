import AppKit
import SwiftUI

struct WorkspaceOverdueTaskRolloverTarget: Equatable {
  let projectID: UUID
  let taskID: UUID
}

enum WorkspaceOverdueTaskRolloverPlanner {
  static func targets(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]],
    today: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> [WorkspaceOverdueTaskRolloverTarget] {
    let normalizedToday = calendar.startOfDay(for: today)
    var seenTaskIDs = Set<UUID>()
    var targets: [WorkspaceOverdueTaskRolloverTarget] = []

    for projectID in projectIDs {
      guard projectSnapshots[projectID]?.isArchived != true else { continue }

      for entry in scheduleEntriesByProjectID[projectID] ?? [] {
        guard !entry.isArchived, !entry.isCompleted else { continue }
        guard seenTaskIDs.insert(entry.taskID).inserted else { continue }
        guard let scheduledDate = entry.displayedDate ?? entry.dueDate ?? entry.startDate else {
          continue
        }
        guard calendar.startOfDay(for: scheduledDate) < normalizedToday else { continue }

        targets.append(WorkspaceOverdueTaskRolloverTarget(projectID: projectID, taskID: entry.taskID))
      }
    }

    return targets
  }
}

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

  func rollOverdueTasksToTodayAllDay() {
    guard !isRollingOverdueTasksToToday else { return }
    let projectIDs = WorkspaceProjectReadPath.timelineInputProjectIDsInOrder(
      timelineOrderedProjectIDs: sidebarRootProjectIDs,
      sidebarProjects: workspaceSidebarProjects
    )
    guard !projectIDs.isEmpty else { return }

    isRollingOverdueTasksToToday = true
    Task { @MainActor in
      defer { isRollingOverdueTasksToToday = false }

      let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
        obsidianVaultRootURL: appState.obsidianVaultRootURL,
        projectIDs: projectIDs
      )
      let resolvedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(retainedResult)
      if case .blocked(let blocker) = resolvedRead.source {
        appState.errorMessage = blocker.userMessage
        return
      }

      let today = Calendar.autoupdatingCurrent.startOfDay(for: appState.currentDayStart)
      let targets = WorkspaceOverdueTaskRolloverPlanner.targets(
        projectIDs: projectIDs,
        projectSnapshots: resolvedRead.projectSnapshots,
        scheduleEntriesByProjectID: resolvedRead.scheduleEntriesByProjectID,
        today: today
      )
      guard !targets.isEmpty else { return }

      var appliedCount = 0
      do {
        for target in targets {
          _ = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
            vaultRootURL: appState.obsidianVaultRootURL,
            projectID: target.projectID,
            taskID: target.taskID,
            day: today,
            timeMinutes: nil,
            durationMinutes: nil,
            reminderProjectProvider: appState.reminderProjectProvider
          )
          appliedCount += 1
        }

        appState.bumpWorkspaceTreeRevision()
      } catch {
        if appliedCount > 0 {
          appState.bumpWorkspaceTreeRevision()
        }
        appState.errorMessage = error.localizedDescription
      }
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
    openProjectTaskInSource(projectID: projectID, taskID: taskID)
  }

  func showTimelineTaskEditor(_ target: WorkspaceTaskEditPanelTarget) {
    showArchive = false
    inspectorSelection = nil
    activeWorkspaceCalendarEventEditPanelTarget = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
    activeWorkspaceTaskEditPanelTarget = target
    selectProjectContext(target.projectID)
  }

  func showTimelineTaskEditor(
    taskID: UUID,
    projectID: UUID,
    title: String,
    date: Date?,
    hasExplicitTime: Bool = false,
    durationMinutes: Int? = nil
  ) {
    let target = WorkspaceTaskEditPanelTarget(
      projectID: projectID,
      taskID: taskID,
      initialFields: timelineTaskEditFallbackFields(
        title: title,
        date: date,
        hasExplicitTime: hasExplicitTime,
        durationMinutes: durationMinutes
      )
    )
    showTimelineTaskEditor(target)
  }

  func showTimelineTaskEditor(taskID: UUID, projectID: UUID) {
    let target = WorkspaceTaskEditPanelTarget(
      projectID: projectID,
      taskID: taskID,
      initialFields: timelineTaskEditFallbackFields(
        title: "",
        date: nil
      )
    )
    showTimelineTaskEditor(target)
  }

  func dismissTimelineTaskEditor() {
    activeWorkspaceTaskEditPanelTarget = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
  }

  func showCalendarEventEditor(_ event: ScheduleCalendarEvent) {
    showArchive = false
    inspectorSelection = nil
    activeWorkspaceTaskEditPanelTarget = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
    appState.isHoveringTimelineDayHeaderOverlay = false
    activeWorkspaceCalendarEventEditPanelTarget = WorkspaceCalendarEventEditPanelTarget(
      eventID: event.id,
      event: event,
      initialFields: ScheduleCalendarEventEditPanelContent.editFields(for: event)
    )
  }

  func dismissCalendarEventEditor() {
    activeWorkspaceCalendarEventEditPanelTarget = nil
  }

  func loadCalendarEventEditFields(
    eventID: String,
    fallback: ScheduleCalendarEventEditFields
  ) async -> ScheduleCalendarEventEditFields {
    guard let event = appState.resolvedScheduleCalendarEvent(eventID: eventID) else {
      return fallback
    }
    return ScheduleCalendarEventEditPanelContent.editFields(for: event)
  }

  func saveCalendarEventEditFields(
    _ fields: ScheduleCalendarEventEditFields,
    eventID: String,
    fallbackEvent: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEventEditFields {
    let event = appState.resolvedScheduleCalendarEvent(eventID: eventID) ?? fallbackEvent
    do {
      let updatedEvent = try await appState.writeScheduleCalendarEventFields(
        event,
        fields: fields,
        scope: scope
      )
      let updatedFields = ScheduleCalendarEventEditPanelContent.editFields(for: updatedEvent)
      if activeWorkspaceCalendarEventEditPanelTarget?.eventID == eventID,
        updatedEvent.id != eventID
      {
        activeWorkspaceCalendarEventEditPanelTarget = WorkspaceCalendarEventEditPanelTarget(
          eventID: updatedEvent.id,
          event: updatedEvent,
          initialFields: updatedFields
        )
      }
      return updatedFields
    } catch {
      appState.errorMessage = error.localizedDescription
      throw error
    }
  }

  func timelineTaskEditFallbackFields(
    title: String,
    date: Date?,
    hasExplicitTime: Bool = false,
    durationMinutes: Int? = nil
  ) -> RetainedTaskEditFields {
    let calendar = Calendar.autoupdatingCurrent
    return RetainedTaskEditFields(
      title: title,
      noteText: "",
      day: date.map { calendar.startOfDay(for: $0) },
      timeMinutes: hasExplicitTime ? date.map(timelineTaskEditTimeMinutes) : nil,
      durationMinutes: durationMinutes
    )
  }

  func loadTimelineTaskEditFields(
    projectID: UUID,
    taskID: UUID,
    fallback: RetainedTaskEditFields
  ) async -> RetainedTaskEditFields {
    do {
      return try await ObsidianRetainedTaskCommandService.taskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        calendar: .autoupdatingCurrent
      )
    } catch {
      appState.errorMessage = error.localizedDescription
      return fallback
    }
  }

  func saveTimelineTaskEditFields(
    _ fields: RetainedTaskEditFields,
    projectID: UUID,
    taskID: UUID
  ) async throws {
    do {
      _ = try await ObsidianRetainedTaskCommandService.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        fields: fields,
        calendar: .autoupdatingCurrent,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      appState.bumpWorkspaceTreeRevision()
    } catch {
      appState.errorMessage = error.localizedDescription
      throw error
    }
  }

  private func timelineTaskEditTimeMinutes(for date: Date) -> Int {
    let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
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
    if localKeyMonitor == nil {
      localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        handleKeyDown(event)
      }
    }
    if localMouseDownMonitor == nil {
      localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
      ) { event in
        handleMouseDown(event)
      }
    }
  }

  func removeLocalKeyMonitor() {
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
    }
    localKeyMonitor = nil
    if let localMouseDownMonitor {
      NSEvent.removeMonitor(localMouseDownMonitor)
    }
    localMouseDownMonitor = nil
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if event.keyCode == 53 {
      if releaseActiveEditPanelTextResponder() {
        return nil
      }
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

  private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
    releaseActiveEditPanelTextResponder(for: event)
    return event
  }

  @discardableResult
  private func releaseActiveEditPanelTextResponder(for event: NSEvent? = nil) -> Bool {
    let hasActiveEditPanel =
      activeWorkspaceTaskEditPanelTarget != nil || activeWorkspaceCalendarEventEditPanelTarget != nil
    let window = event?.window ?? NSApp.keyWindow ?? NSApp.mainWindow
    guard let window else { return false }
    let hitView = event.flatMap { mouseHitView(for: $0, in: window) }
    guard
      WorkspaceTextResponderReleasePolicy.shouldReleaseTextResponder(
        hasActiveEditPanel: hasActiveEditPanel,
        firstResponder: window.firstResponder,
        mouseHitView: hitView
      )
    else {
      return false
    }
    window.endEditing(for: nil)
    window.makeFirstResponder(nil)
    return true
  }

  private func mouseHitView(for event: NSEvent, in window: NSWindow) -> NSView? {
    guard let contentView = window.contentView else { return nil }
    let point = contentView.convert(event.locationInWindow, from: nil)
    return contentView.hitTest(point)
  }

  func presentInitialSyncAlertIfNeeded() {
    guard appState.shouldPromptForInitialSyncConsent else { return }
    showInitialSyncAlert = true
  }
}
