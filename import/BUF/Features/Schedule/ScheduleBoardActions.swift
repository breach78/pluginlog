import AppKit
import SwiftUI

enum ScheduleBoardReadPath {
  struct QuickAddState: Equatable {
    let options: [ScheduleQuickAddProjectOption]
    let defaultProjectID: UUID?
  }

  static func deduplicatedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return projectIDs.filter { seen.insert($0).inserted }
  }

  static func normalizedProjectIDs(
    projectIDs: [UUID]
  ) -> [UUID] {
    deduplicatedProjectIDs(projectIDs)
  }

  static func orderedProjectDetails(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord]
  ) -> [WorkspaceProjectRuntimeRecord] {
    deduplicatedProjectIDs(projectIDs)
      .compactMap { projectSnapshots[$0] }
      .filter { !$0.isArchived }
  }

  static func workspaceTaskDescriptors(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> [WorkspaceScheduleTaskDescriptor] {
    ScheduleProjectionService.taskDescriptors(
      projectIDs: projectIDs,
      projectSnapshots: projectSnapshots,
      scheduleEntriesByProjectID: scheduleEntriesByProjectID
    )
  }

  static func scheduleDay(
    for task: TaskRowSnapshot,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Date? {
    guard let anchorDate = task.reminderDate else { return nil }
    return calendar.startOfDay(for: anchorDate)
  }

  static func shouldRetainCompletedWorkspaceTask(
    _ task: TaskRowSnapshot,
    today: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Bool {
    guard let scheduledDay = scheduleDay(for: task, calendar: calendar) else { return false }
    return scheduledDay >= today
  }

  static func shouldDisplayWorkspaceTask(
    _ task: TaskRowSnapshot,
    today: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Bool {
    guard !task.isArchived, scheduleDay(for: task, calendar: calendar) != nil else {
      return false
    }
    guard task.isCompleted else { return true }
    return shouldRetainCompletedWorkspaceTask(task, today: today, calendar: calendar)
  }

  static func quickAddState(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    selectedProjectID: UUID?,
    appSelectedProjectID: UUID?,
    defaultReminderCalendarIdentifier: String?
  ) -> QuickAddState {
    let projects = orderedProjectDetails(projectIDs: projectIDs, projectSnapshots: projectSnapshots)
    let options = projects.map { project in
      ScheduleQuickAddProjectOption(
        id: project.id,
        title: project.title
      )
    }

    let defaultProjectID: UUID?
    if let defaultReminderCalendarIdentifier,
      let matchingDefault = projects.first(where: {
        $0.reminderListIdentifier == defaultReminderCalendarIdentifier
      })
    {
      defaultProjectID = matchingDefault.id
    } else if let selectedProjectID,
      options.contains(where: { $0.id == selectedProjectID })
    {
      defaultProjectID = selectedProjectID
    } else if let appSelectedProjectID,
      options.contains(where: { $0.id == appSelectedProjectID })
    {
      defaultProjectID = appSelectedProjectID
    } else {
      defaultProjectID = options.first?.id
    }

    return QuickAddState(options: options, defaultProjectID: defaultProjectID)
  }

  static func sourceSignature(
    today: Date,
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(today.timeIntervalSinceReferenceDate)
    for project in orderedProjectDetails(projectIDs: projectIDs, projectSnapshots: projectSnapshots) {
      hasher.combine(project.id)
      hasher.combine(project.updatedAt.timeIntervalSinceReferenceDate)
      hasher.combine(project.title)
      hasher.combine(project.colorHex)
      hasher.combine(project.reminderListIdentifier)
      hasher.combine(project.reminderListExternalIdentifier)
      let scheduleEntries = scheduleEntriesByProjectID[project.id] ?? []
      hasher.combine(scheduleEntries.count)
      for entry in scheduleEntries {
        hasher.combine(entry.taskID)
        hasher.combine(entry.scheduleRenderFingerprint)
      }
    }
    return hasher.finalize()
  }
}

struct ScheduleTaskCompletionState: Equatable {
  let isCompleted: Bool
  let completionDate: Date?
  let isRecurring: Bool
  let occurrenceDate: Date?
  let editFields: RetainedTaskEditFields
}

extension ScheduleBoardView {
  var allowsScheduleDragDateSnapping: Bool {
    false
  }

  func allowScheduleMutation(_ feature: String) -> Bool {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.schedule, feature: feature)
    return false
  }

  func allowScheduleRetainedWrite(_ feature: String) -> Bool {
    _ = feature
    return true
  }

  func recordWorkspaceLoadFallback(_ fallback: ScheduleWorkspaceLoadFallback?) {
    if workspaceLoadFallback != fallback {
      workspaceLoadFallback = fallback
    }
  }

  func recordScheduleViewportDiagnostic(_ diagnostic: ScheduleViewportSyncDiagnostic) {
    guard viewportSyncDiagnostic != diagnostic else { return }
    viewportSyncDiagnostic = diagnostic
    AppLogger.ui.error(
      "schedule viewport diagnostic [\(diagnostic.rawValue, privacy: .public)]"
    )
  }

  func clearScheduleViewportDiagnostic(_ diagnostic: ScheduleViewportSyncDiagnostic? = nil) {
    guard let current = viewportSyncDiagnostic else { return }
    guard diagnostic == nil || current == diagnostic else { return }
    viewportSyncDiagnostic = nil
  }

  func handleScheduleCalendarEditError(
    _ error: ScheduleCalendarEditError,
    context: ScheduleCalendarFailureContext
  ) {
    AppLogger.ui.error(
      "schedule calendar failure [\(context.rawValue, privacy: .public)]: \(error.localizedDescription, privacy: .public)"
    )
    calendarEditError = error
  }

  func handleScheduleCalendarEditFailure(
    _ error: Error,
    context: ScheduleCalendarFailureContext,
    fallback: ScheduleCalendarEditError
  ) {
    AppLogger.ui.error(
      "schedule calendar failure [\(context.rawValue, privacy: .public)]: \(error.localizedDescription, privacy: .public)"
    )
    calendarEditError = fallback
  }

  func logScheduleInvalidDrop(at location: CGPoint, reason: ScheduleInvalidDropReason) {
    AppLogger.ui.error(
      "schedule invalid drop [\(reason.rawValue, privacy: .public)] at x=\(location.x, privacy: .public) y=\(location.y, privacy: .public)"
    )
    if reason == .projectionUnavailable {
      recordScheduleViewportDiagnostic(.dragProjectionFrameUnavailable)
    }
  }

  func scheduleWorkspaceLoadSignature(
    projectIDs: [UUID],
    workspaceTreeRevision: Int
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(projectIDs.map(\.uuidString).sorted())
    hasher.combine(workspaceTreeRevision)
    return hasher.finalize()
  }

  func reloadWorkspaceScheduleProjectDetails(
    for projectIDs: [UUID],
    force: Bool = false
  ) async {
    let requestedProjectIDs = Array(Set(projectIDs))
    let loadSignature = scheduleWorkspaceLoadSignature(
      projectIDs: requestedProjectIDs,
      workspaceTreeRevision: appState.workspaceTreeRevision
    )
    guard force || workspaceScheduleLastLoadSignature != loadSignature else { return }
    workspaceScheduleLoadGeneration += 1
    let loadGeneration = workspaceScheduleLoadGeneration
    guard !requestedProjectIDs.isEmpty else {
      await MainActor.run {
        let didChange = !workspaceScheduleProjectSnapshots.isEmpty
          || !workspaceScheduleSliceEntriesByProjectID.isEmpty
          || !retainedScheduleCalendarBridgeDecisionsByTaskID.isEmpty
          || !retainedScheduleCalendarBridgeWriteMarkersByTaskID.isEmpty
        if didChange {
          workspaceScheduleProjectSnapshots = [:]
          workspaceScheduleSliceEntriesByProjectID = [:]
          retainedScheduleCalendarBridgeDecisionsByTaskID = [:]
          retainedScheduleCalendarBridgeWriteMarkersByTaskID = [:]
          invalidateWorkspaceScheduleProjectionCaches()
        }
        workspaceScheduleLastLoadSignature = loadSignature
        recordWorkspaceLoadFallback(nil)
      }
      return
    }

    let obsidianVaultRootURL = await MainActor.run { appState.obsidianVaultRootURL }
    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: obsidianVaultRootURL,
      projectIDs: requestedProjectIDs
    )

    await MainActor.run {
      guard loadGeneration == workspaceScheduleLoadGeneration else { return }
      let resolvedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(retainedResult)
      let currentTaskIDs = Set(resolvedRead.calendarBridgeDecisionsByTaskID.keys)
      let nextWriteMarkers = retainedScheduleCalendarBridgeWriteMarkersByTaskID.filter {
        currentTaskIDs.contains($0.key)
      }
      let didChange = workspaceScheduleProjectSnapshots != resolvedRead.projectSnapshots
        || workspaceScheduleSliceEntriesByProjectID != resolvedRead.scheduleEntriesByProjectID
        || retainedScheduleCalendarBridgeDecisionsByTaskID != resolvedRead.calendarBridgeDecisionsByTaskID
        || retainedScheduleCalendarBridgeWriteMarkersByTaskID != nextWriteMarkers
      if didChange {
        workspaceScheduleProjectSnapshots = resolvedRead.projectSnapshots
        workspaceScheduleSliceEntriesByProjectID = resolvedRead.scheduleEntriesByProjectID
        retainedScheduleCalendarBridgeDecisionsByTaskID =
          resolvedRead.calendarBridgeDecisionsByTaskID
        retainedScheduleCalendarBridgeWriteMarkersByTaskID = nextWriteMarkers
        invalidateWorkspaceScheduleProjectionCaches()
      }
      workspaceScheduleLastLoadSignature = loadSignature

      committedTaskDrop = nil
      switch resolvedRead.source {
      case .retained:
        recordWorkspaceLoadFallback(nil)
      case .blocked:
        appState.errorMessage = resolvedRead.errorMessage
        recordWorkspaceLoadFallback(nil)
      }
    }
  }

  func reloadChangedWorkspaceScheduleProjectDetails(for projectIDs: [UUID]) async {
    let requestedProjectIDs = Set(projectIDs)
    guard !requestedProjectIDs.isEmpty else { return }
    workspaceScheduleLoadGeneration += 1
    let loadGeneration = workspaceScheduleLoadGeneration
    workspaceScheduleLastLoadSignature = scheduleWorkspaceLoadSignature(
      projectIDs: activeProjectIDs,
      workspaceTreeRevision: appState.workspaceTreeRevision
    )
    let obsidianVaultRootURL = await MainActor.run { appState.obsidianVaultRootURL }
    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: obsidianVaultRootURL,
      projectIDs: Array(requestedProjectIDs)
    )

    guard case .loaded(let loadedProjection) = retainedResult else {
      let activeIDs = await MainActor.run { self.activeProjectIDs }
      await reloadWorkspaceScheduleProjectDetails(for: activeIDs, force: true)
      return
    }

    await MainActor.run {
      guard loadGeneration == workspaceScheduleLoadGeneration else { return }
      let existingProjection = RetainedWorkspaceSurfaceProjection(
        projectSnapshots: workspaceScheduleProjectSnapshots,
        projectSummaries: [:],
        scheduleEntriesByProjectID: workspaceScheduleSliceEntriesByProjectID,
        calendarBridgeDecisionsByTaskID: retainedScheduleCalendarBridgeDecisionsByTaskID
      )
      let mergedProjection = RetainedWorkspaceSurfaceProjectionMergePolicy.merge(
        existing: existingProjection,
        loaded: loadedProjection,
        replacingProjectIDs: requestedProjectIDs
      )
      let nextWriteMarkers = RetainedWorkspaceSurfaceProjectionMergePolicy.filteredWriteMarkers(
        existingMarkers: retainedScheduleCalendarBridgeWriteMarkersByTaskID,
        existing: existingProjection,
        loaded: loadedProjection,
        replacingProjectIDs: requestedProjectIDs
      )
      let didChange = workspaceScheduleProjectSnapshots != mergedProjection.projectSnapshots
        || workspaceScheduleSliceEntriesByProjectID != mergedProjection.scheduleEntriesByProjectID
        || retainedScheduleCalendarBridgeDecisionsByTaskID != mergedProjection.calendarBridgeDecisionsByTaskID
        || retainedScheduleCalendarBridgeWriteMarkersByTaskID != nextWriteMarkers
      if didChange {
        workspaceScheduleProjectSnapshots = mergedProjection.projectSnapshots
        workspaceScheduleSliceEntriesByProjectID = mergedProjection.scheduleEntriesByProjectID
        retainedScheduleCalendarBridgeDecisionsByTaskID =
          mergedProjection.calendarBridgeDecisionsByTaskID
        retainedScheduleCalendarBridgeWriteMarkersByTaskID = nextWriteMarkers
        invalidateWorkspaceScheduleProjectionCaches()
      }
      workspaceScheduleLastLoadSignature = scheduleWorkspaceLoadSignature(
        projectIDs: activeProjectIDs,
        workspaceTreeRevision: appState.workspaceTreeRevision
      )
      committedTaskDrop = nil
      recordWorkspaceLoadFallback(nil)
    }
  }

  func invalidateWorkspaceScheduleProjectionCaches() {
    cachedScheduledTaskSourceSignature = nil
    cachedScheduledTaskDescriptors = []
    cachedWorkspaceScheduleTasksByID = [:]
    cachedScheduleTaskSignature = 0
    cachedLayoutSourceSignature = nil
    cachedTimedEntries = []
    cachedAllDayEntries = []
    cachedBackgroundTimedEntries = []
    cachedBackgroundAllDayEntries = []
    cachedScheduleDayHeaderSections = [:]
    cachedScheduleDayHeaderSourceSignature = nil
  }

  func calendarDisplayRange() -> ClosedRange<Date> {
    if displayMode == .month {
      return ScheduleMonthContinuousWindow.visibleDateRange(
        containing: monthAnchorDate,
        calendar: calendar
      )
    }
    let lowerDay = calendar.date(byAdding: .day, value: -pastDayBuffer, to: today) ?? today
    let upperDay = calendar.date(byAdding: .day, value: futureDayWindow + 1, to: today) ?? today
    return lowerDay...upperDay
  }

  func refreshCalendarOverlay(force: Bool = false) {
    guard isActive else {
      calendarOverlayRefreshTask?.cancel()
      calendarOverlayRefreshTask = nil
      return
    }
    let fetchRange = calendarDisplayRange()
    calendarOverlayRefreshTask?.cancel()
    calendarOverlayRefreshTask = Task { @MainActor in
      guard !Task.isCancelled else { return }
      await appState.refreshScheduleCalendarOverlay(visibleRange: fetchRange, force: force)
    }
  }

  func refreshCalendarOverlayIfChanged(by result: RetainedTaskCommandResult) {
    switch result.calendarBridgeDecision {
    case .upsert, .removeOwnedEvent:
      refreshCalendarOverlay(force: true)
    case .noAction, .failClosed:
      break
    }
  }

  func updateTimedQuickCreateSelection(
    startLocation: CGPoint,
    currentLocation: CGPoint
  ) {
    pendingTimedQuickCreateSelection = nil
    activeTimedQuickCreateSelection = timedQuickCreateSelection(
      startLocation: startLocation,
      currentLocation: currentLocation
    )
  }

  func commitTimedQuickCreateSelection(
    startLocation: CGPoint,
    currentLocation: CGPoint
  ) {
    activeTimedQuickCreateSelection = nil
    guard scheduleQuickAddProjectID != nil else {
      handleUnavailableScheduleQuickAdd(reason: .noAvailableProject)
      return
    }
    pendingTimedQuickCreateSelection = timedQuickCreateSelection(
      startLocation: startLocation,
      currentLocation: currentLocation
    )
  }

  func cancelTimedQuickCreateSelection() {
    activeTimedQuickCreateSelection = nil
  }

  func timedQuickCreateSelection(
    startLocation: CGPoint,
    currentLocation: CGPoint
  ) -> ScheduleTimedQuickCreateSelection? {
    guard !days.isEmpty else { return nil }

    let clampedDayIndex = min(max(Int(startLocation.x / dayColumnWidth), 0), days.count - 1)
    let topY = max(0, min(startLocation.y, currentLocation.y))
    let bottomY = min(timeGridHeight, max(startLocation.y, currentLocation.y))
    let snappedStart = ScheduleDragDropInteractionLayer.snappedTimeMinutes(
      for: topY,
      metrics: interactionMetrics
    )
    let snappedEnd = ScheduleDragDropInteractionLayer.snappedTimeMinutes(
      for: max(topY + quarterHourHeight, bottomY),
      metrics: interactionMetrics
    )
    let unclampedDuration = max(timedMinimumDuration, snappedEnd - snappedStart)
    let durationMinutes = ScheduleDragDropInteractionLayer.clampedDuration(
      unclampedDuration,
      for: snappedStart,
      metrics: interactionMetrics
    )

    return ScheduleTimedQuickCreateSelection(
      dayIndex: clampedDayIndex,
      day: days[clampedDayIndex],
      startMinutes: snappedStart,
      durationMinutes: durationMinutes
    )
  }

  func timedQuickCreateViewportFrame(
    for selection: ScheduleTimedQuickCreateSelection
  ) -> CGRect {
    timedViewportFrame(
      dayIndex: selection.dayIndex,
      startMinute: selection.startMinutes,
      durationMinutes: selection.durationMinutes,
      column: 0,
      columnCount: 1
    )
  }

  func revealScheduleTask(taskID: UUID, projectID: UUID) {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else {
      selectedScheduleTaskID = taskID
      appState.selectedProjectID = projectID
      onEditTask(
        WorkspaceTaskEditPanelTarget(
          projectID: projectID,
          taskID: taskID,
          initialFields: RetainedTaskEditFields(
            title: "",
            noteText: "",
            day: nil,
            timeMinutes: nil,
            durationMinutes: nil
          ),
          initialFocus: .note
        )
      )
      return
    }
    showScheduleTaskEditor(taskDescriptor)
  }

  func handleScheduleTaskPrimaryTap(_ taskDescriptor: WorkspaceScheduleTaskDescriptor) {
    DispatchQueue.main.async {
      guard shouldHandleTaskTap() else { return }
      guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return }
      showScheduleTaskEditor(taskDescriptor)
    }
  }

  func handleScheduleTaskDetailTap(_ taskDescriptor: WorkspaceScheduleTaskDescriptor) {
    DispatchQueue.main.async {
      let taskRow = taskDescriptor.taskRow
      guard shouldHandleTaskTap() else { return }
      guard !taskRow.isLocalCompletedRecurringOccurrence else { return }
      revealScheduleTask(taskID: taskRow.id, projectID: taskDescriptor.projectID)
    }
  }

  func showScheduleTaskEditor(_ taskDescriptor: WorkspaceScheduleTaskDescriptor) {
    let taskRow = taskDescriptor.taskRow
    selectedScheduleTaskID = taskRow.id
    appState.selectedProjectID = taskDescriptor.projectID
    onEditTask(
      WorkspaceTaskEditPanelTarget(
        projectID: taskDescriptor.projectID,
        taskID: taskRow.id,
        initialFields: scheduleTaskEditFields(for: taskRow),
        initialFocus: .note
      )
    )
  }

  func showScheduleCalendarEventEditor(_ event: ScheduleCalendarEvent) {
    selectedScheduleTaskID = nil
    onEditCalendarEvent(event)
  }

  func scheduleTaskEditFields(for taskRow: TaskRowSnapshot) -> RetainedTaskEditFields {
    RetainedTaskEditFields(
      title: taskRow.title,
      noteText: "",
      day: taskRow.reminderDate.map { calendar.startOfDay(for: $0) },
      timeMinutes: taskRow.scheduleHasExplicitTime ? taskRow.reminderDate.map(timeMinutes) : nil,
      durationMinutes: taskRow.scheduledDurationMinutes
    )
  }

  func taskUndoSnapshot(for taskRow: TaskRowSnapshot) -> RetainedTaskUndoSnapshot {
    RetainedTaskUndoSnapshot(
      fields: scheduleTaskEditFields(for: taskRow),
      isCompleted: taskRow.isCompleted,
      completionDate: taskRow.completionDate
    )
  }

  func selectScheduleTask(_ taskID: UUID) {
    MotionTransaction.withoutAnimation {
      selectedScheduleTaskID = taskID
    }
  }

  func handleScheduleBackgroundTap() {
    MotionTransaction.withoutAnimation {
      selectedScheduleTaskID = nil
    }
    onTapEmptyArea()
  }

  func deleteScheduleTask(
    _ taskID: UUID,
    actionName: String = "할일 삭제",
    registerUndo: Bool = true
  ) {
    if selectedScheduleTaskID == taskID {
      selectedScheduleTaskID = nil
    }
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
    let undoSnapshot = taskUndoSnapshot(for: taskDescriptor.taskRow)
    scheduleTaskWriteNotice = nil
    Task { @MainActor in
      do {
        let fullUndoFields =
          (try? await RetainedTaskCommandFacade.taskEditFields(
            vaultRootURL: appState.obsidianVaultRootURL,
            projectID: taskDescriptor.projectID,
            taskID: taskID,
            calendar: calendar
          )) ?? undoSnapshot.fields
        let fullUndoSnapshot = RetainedTaskUndoSnapshot(
          fields: fullUndoFields,
          isCompleted: undoSnapshot.isCompleted,
          completionDate: undoSnapshot.completionDate
        )
        _ = try await RetainedTaskCommandFacade.deleteTask(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: taskDescriptor.projectID,
          taskID: taskID,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        appState.bumpWorkspaceTreeRevision()
        await reloadChangedWorkspaceScheduleProjectDetails(for: [taskDescriptor.projectID])
        retainedScheduleCalendarBridgeDecisionsByTaskID.removeValue(forKey: taskID)
        retainedScheduleCalendarBridgeWriteMarkersByTaskID.removeValue(forKey: taskID)
        refreshCalendarOverlay(force: true)
        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          Task { @MainActor in
            _ = await self.recreateScheduleTask(
              fullUndoSnapshot,
              projectID: taskDescriptor.projectID,
              registerUndo: false
            )
          }
        }
      } catch {
        if await handleRetainedScheduleWriteFailure(error) {
          return
        }
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func deleteScheduleCalendarEvent(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope,
    actionName: String = "캘린더 일정 삭제",
    registerUndo: Bool = true
  ) {
    Task { @MainActor in
      do {
        let snapshot = try await appState.deleteScheduleCalendarEvent(
          event,
          scope: scope,
          undoManager: undoManager
        )
        calendarEditError = nil
        refreshCalendarOverlay(force: true)

        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          self.restoreDeletedScheduleCalendarEvent(
            snapshot,
            actionName: actionName
          )
        }
      } catch let error as ScheduleCalendarEditError {
        handleScheduleCalendarEditError(error, context: .deleteEvent)
      } catch {
        handleScheduleCalendarEditFailure(
          error,
          context: .deleteEvent,
          fallback: .removeFailed(error.localizedDescription)
        )
      }
    }
  }

  func restoreDeletedScheduleCalendarEvent(
    _ snapshot: DeletedScheduleCalendarEventSnapshot,
    actionName: String
  ) {
    Task { @MainActor in
      do {
        let restoredEvent = try await appState.restoreDeletedScheduleCalendarEvent(
          snapshot,
          undoManager: undoManager
        )
        calendarEditError = nil
        refreshCalendarOverlay(force: true)
        appState.registerUndo(with: undoManager, actionName: actionName) {
          self.deleteScheduleCalendarEvent(
            restoredEvent,
            scope: snapshot.scope,
            actionName: actionName,
            registerUndo: true
          )
        }
      } catch let error as ScheduleCalendarEditError {
        handleScheduleCalendarEditError(error, context: .restoreDeletedEvent)
      } catch {
        handleScheduleCalendarEditFailure(
          error,
          context: .restoreDeletedEvent,
          fallback: .saveFailed(error.localizedDescription)
        )
      }
    }
  }

  func suppressTaskTap(for duration: TimeInterval = 0.35) {
    suppressedTaskTapUntil = TaskTapSuppressionPolicy.suppressedUntil(
      now: Date(),
      duration: duration
    )
  }

  func shouldHandleTaskTap() -> Bool {
    TaskTapSuppressionPolicy.shouldHandleTaskTap(
      now: Date(),
      suppressedUntil: suppressedTaskTapUntil
    )
  }

  func postponeScheduleAction(
    for taskDescriptor: WorkspaceScheduleTaskDescriptor,
    day: Date,
    isPreparationSlot: Bool,
    targetCompletedWorkUnits _: Int?
  ) -> (() -> Void)? {
    guard !taskDescriptor.taskRow.isCompleted, !isPreparationSlot else { return nil }
    let normalizedDay = calendar.startOfDay(for: day)
    return {
      self.postponeScheduledTaskToNextDayAllDay(
        taskID: taskDescriptor.taskRow.id,
        projectID: taskDescriptor.projectID,
        from: normalizedDay
      )
    }
  }

  func postponeScheduledTaskToNextDayAllDay(taskID: UUID, projectID: UUID, from day: Date) {
    guard calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) != nil else { return }
    guard allowScheduleMutation("postpone-task") else { return }
  }

  func releaseActiveTextResponderForUndo() {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
    if let responder = window.firstResponder, responder is NSTextView || responder is NSTextField {
      window.endEditing(for: nil)
      window.makeFirstResponder(nil)
    }
  }

  func createScheduleTask(
    _ title: String,
    projectID: UUID,
    location: CGPoint,
    isAllDayRegion: Bool
  ) {
    guard !days.isEmpty else {
      handleUnavailableScheduleQuickAdd(reason: .noVisibleDay)
      return
    }

    let clampedDayIndex = min(max(Int(location.x / dayColumnWidth), 0), days.count - 1)
    let day = days[clampedDayIndex]
    if isAllDayRegion {
      createScheduleTask(title, projectID: projectID, day: day, timeMinutes: nil, durationMinutes: nil)
    } else {
      let snappedMinutes = ScheduleDragDropInteractionLayer.snappedTimeMinutes(
        for: location.y,
        metrics: interactionMetrics
      )
      createScheduleTask(
        title,
        projectID: projectID,
        day: day,
        timeMinutes: snappedMinutes,
        durationMinutes: timedMinimumDuration
      )
    }
  }

  func createScheduleTask(
    _ title: String,
    projectID: UUID,
    day: Date,
    timeMinutes: Int?,
    durationMinutes: Int?,
    registerUndo: Bool = true
  ) {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTitle.isEmpty else { return }
    scheduleTaskWriteNotice = nil
    Task { @MainActor in
      do {
        let result = try await RetainedTaskCommandFacade.createTask(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          title: normalizedTitle,
          day: day,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes,
          calendar: calendar,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        selectedScheduleTaskID = result.taskID
        appState.bumpWorkspaceTreeRevision()
        await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
        retainedScheduleCalendarBridgeDecisionsByTaskID[result.taskID] = result.calendarBridgeDecision
        retainedScheduleCalendarBridgeWriteMarkersByTaskID[result.taskID] = result.calendarWriteMarker
        refreshCalendarOverlayIfChanged(by: result)
        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: "할일 추가") {
          self.deleteScheduleTask(result.taskID, actionName: "할일 추가", registerUndo: false)
        }
      } catch {
        appState.reportError(error, logMessage: "schedule createTask failed")
      }
    }
  }

  func recreateScheduleTask(
    _ snapshot: RetainedTaskUndoSnapshot,
    projectID: UUID,
    registerUndo: Bool = true
  ) async -> UUID? {
    do {
      let result = try await RetainedTaskCommandFacade.createTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        title: snapshot.fields.title,
        day: snapshot.fields.day,
        timeMinutes: snapshot.fields.timeMinutes,
        durationMinutes: snapshot.fields.durationMinutes,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      _ = try await RetainedTaskCommandFacade.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: result.taskID,
        fields: snapshot.fields,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      if snapshot.isCompleted {
        _ = try await RetainedTaskCommandFacade.setTaskCompletion(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: result.taskID,
          isCompleted: true,
          completionDate: snapshot.completionDate,
          reminderProjectProvider: appState.reminderProjectProvider
        )
      }
      selectedScheduleTaskID = result.taskID
      appState.bumpWorkspaceTreeRevision()
      await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
      retainedScheduleCalendarBridgeDecisionsByTaskID[result.taskID] = result.calendarBridgeDecision
      retainedScheduleCalendarBridgeWriteMarkersByTaskID[result.taskID] = result.calendarWriteMarker
      refreshCalendarOverlayIfChanged(by: result)
      if registerUndo {
        appState.registerUndo(with: undoManager, actionName: "할일 삭제 취소") {
          self.deleteScheduleTask(result.taskID, actionName: "할일 삭제 취소", registerUndo: false)
        }
      }
      return result.taskID
    } catch {
      appState.reportError(error, logMessage: "schedule recreateTask failed")
      return nil
    }
  }

  func handleUnavailableScheduleQuickAdd(reason: ScheduleQuickAddFailureReason = .noAvailableProject) {
    AppLogger.ui.error(
      "schedule quick add failure [\(reason.rawValue, privacy: .public)]"
    )
    appState.errorMessage = reason.userMessage
  }

  func timeMinutes(for date: Date) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  func durationMinutes(for event: ScheduleCalendarEvent) -> Int {
    max(timedMinimumDuration, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
  }

  func scheduleDay(for task: TaskRowSnapshot) -> Date? {
    ScheduleBoardReadPath.scheduleDay(for: task, calendar: calendar)
  }

  func shouldDisplayScheduledWorkspaceTask(_ task: TaskRowSnapshot) -> Bool {
    ScheduleBoardReadPath.shouldDisplayWorkspaceTask(task, today: today, calendar: calendar)
  }

  func shouldRetainCompletedScheduleWorkspaceTask(_ task: TaskRowSnapshot) -> Bool {
    ScheduleBoardReadPath.shouldRetainCompletedWorkspaceTask(
      task,
      today: today,
      calendar: calendar
    )
  }

  var shouldSuppressHistoryRecording: Bool {
    appState.isUndoRedoInFlight || undoManager?.isUndoing == true || undoManager?.isRedoing == true
  }

  func scheduleTaskDescriptor(for taskID: UUID) -> WorkspaceScheduleTaskDescriptor? {
    if let cached = cachedWorkspaceScheduleTasksByID[taskID] {
      return scheduleTaskDescriptorApplyingOptimisticSchedule(cached)
    }
    guard let descriptor = resolvedScheduleTaskSnapshot(preferCached: true).workspaceTasksByID[taskID]
    else {
      return nil
    }
    return scheduleTaskDescriptorApplyingOptimisticSchedule(descriptor)
  }

  func effectiveScheduleTaskIsCompleted(_ taskRow: TaskRowSnapshot) -> Bool {
    optimisticScheduleTaskCompletionByID[taskRow.id] ?? taskRow.isCompleted
  }

  func optimisticScheduleTaskScheduleState(
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) -> OptimisticScheduleTaskScheduleState {
    let normalizedDay = day.map { calendar.startOfDay(for: $0) }
    return OptimisticScheduleTaskScheduleState(
      day: normalizedDay,
      timeMinutes: normalizedDay == nil ? nil : timeMinutes,
      durationMinutes: normalizedDay == nil || timeMinutes == nil ? nil : durationMinutes
    )
  }

  func scheduleTaskSourceSignatureApplyingOptimisticSchedule(baseSignature: Int) -> Int {
    guard !optimisticScheduleTaskScheduleByID.isEmpty else { return baseSignature }
    var hasher = Hasher()
    hasher.combine(baseSignature)
    for taskID in optimisticScheduleTaskScheduleByID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard let schedule = optimisticScheduleTaskScheduleByID[taskID] else { continue }
      hasher.combine(taskID)
      hasher.combine(schedule.day)
      hasher.combine(schedule.timeMinutes)
      hasher.combine(schedule.durationMinutes)
    }
    return hasher.finalize()
  }

  func scheduleTaskDescriptorsApplyingOptimisticSchedule(
    _ descriptors: [WorkspaceScheduleTaskDescriptor]
  ) -> [WorkspaceScheduleTaskDescriptor] {
    guard !optimisticScheduleTaskScheduleByID.isEmpty else { return descriptors }
    return descriptors.map(scheduleTaskDescriptorApplyingOptimisticSchedule)
  }

  func scheduleTaskDescriptorApplyingOptimisticSchedule(
    _ descriptor: WorkspaceScheduleTaskDescriptor
  ) -> WorkspaceScheduleTaskDescriptor {
    guard let schedule = optimisticScheduleTaskScheduleByID[descriptor.taskRow.id] else {
      return descriptor
    }
    return WorkspaceScheduleTaskDescriptor(
      projectID: descriptor.projectID,
      projectTitle: descriptor.projectTitle,
      projectColorHex: descriptor.projectColorHex,
      taskRow: taskRow(descriptor.taskRow, applying: schedule)
    )
  }

  func taskRow(
    _ taskRow: TaskRowSnapshot,
    applying schedule: OptimisticScheduleTaskScheduleState
  ) -> TaskRowSnapshot {
    TaskRowSnapshot(
      id: taskRow.id,
      title: taskRow.title,
      reminderDate: schedule.day.map { scheduleDate(day: $0, timeMinutes: schedule.timeMinutes) },
      scheduleHasExplicitTime: schedule.day != nil && schedule.timeMinutes != nil,
      scheduledDurationMinutes: schedule.timeMinutes == nil ? nil : schedule.durationMinutes,
      isCompleted: taskRow.isCompleted,
      completionDate: taskRow.completionDate,
      recurrenceRuleRaw: taskRow.recurrenceRuleRaw,
      isLocalCompletedRecurringOccurrence: taskRow.isLocalCompletedRecurringOccurrence,
      attachmentCount: taskRow.attachmentCount,
      hasReminderNoteContent: taskRow.hasReminderNoteContent,
      reminderNoteText: taskRow.reminderNoteText,
      requiredWorkDays: taskRow.requiredWorkDays,
      completedWorkUnits: taskRow.completedWorkUnits,
      completedWorkUnitDates: taskRow.completedWorkUnitDates,
      preparationScheduleOverridesRaw: taskRow.preparationScheduleOverridesRaw,
      rowOrder: taskRow.rowOrder,
      createdAt: taskRow.createdAt,
      isArchived: taskRow.isArchived
    )
  }

  func clearOptimisticScheduleTaskSchedule(
    taskID: UUID,
    expectedSchedule: OptimisticScheduleTaskScheduleState
  ) {
    guard optimisticScheduleTaskScheduleByID[taskID] == expectedSchedule else { return }
    optimisticScheduleTaskScheduleByID.removeValue(forKey: taskID)
  }

  func restoreOptimisticScheduleTaskSchedule(
    taskID: UUID,
    expectedCurrentSchedule: OptimisticScheduleTaskScheduleState,
    previousSchedule: OptimisticScheduleTaskScheduleState?
  ) {
    guard optimisticScheduleTaskScheduleByID[taskID] == expectedCurrentSchedule else { return }
    if let previousSchedule {
      optimisticScheduleTaskScheduleByID[taskID] = previousSchedule
    } else {
      optimisticScheduleTaskScheduleByID.removeValue(forKey: taskID)
    }
  }

  func scheduleMonthItemsApplyingOptimisticTaskCompletion(
    _ items: [ScheduleMonthItem]
  ) -> [ScheduleMonthItem] {
    guard !optimisticScheduleTaskCompletionByID.isEmpty else { return items }
    return items.map { item in
      guard case .workspaceTask(let taskID, _) = item.source,
        let isCompleted = optimisticScheduleTaskCompletionByID[taskID],
        item.isCompleted != isCompleted
      else {
        return item
      }
      return ScheduleMonthItem(
        id: item.id,
        source: item.source,
        title: item.title,
        subtitle: item.subtitle,
        startDate: item.startDate,
        endDate: item.endDate,
        isAllDay: item.isAllDay,
        colorHex: item.colorHex,
        isCompleted: isCompleted,
        isPreparationSlot: item.isPreparationSlot,
        isBackgroundCalendar: item.isBackgroundCalendar,
        calendarEvent: item.calendarEvent
      )
    }
  }

  func scheduleMonthItemsSignature(
    baseSignature: Int,
    items: [ScheduleMonthItem]
  ) -> Int {
    guard !optimisticScheduleTaskCompletionByID.isEmpty else { return baseSignature }
    var hasher = Hasher()
    hasher.combine(baseSignature)
    var didIncludeOptimisticValue = false
    for item in items {
      guard case .workspaceTask(let taskID, _) = item.source,
        let isCompleted = optimisticScheduleTaskCompletionByID[taskID]
      else {
        continue
      }
      didIncludeOptimisticValue = true
      hasher.combine(taskID)
      hasher.combine(isCompleted)
    }
    guard didIncludeOptimisticValue else { return baseSignature }
    return hasher.finalize()
  }

  func clearOptimisticScheduleTaskCompletion(taskID: UUID, expectedIsCompleted: Bool) {
    guard optimisticScheduleTaskCompletionByID[taskID] == expectedIsCompleted else { return }
    optimisticScheduleTaskCompletionByID.removeValue(forKey: taskID)
  }

  func restoreOptimisticScheduleTaskCompletion(
    taskID: UUID,
    expectedCurrentValue: Bool,
    previousValue: Bool?
  ) {
    guard optimisticScheduleTaskCompletionByID[taskID] == expectedCurrentValue else { return }
    if let previousValue {
      optimisticScheduleTaskCompletionByID[taskID] = previousValue
    } else {
      optimisticScheduleTaskCompletionByID.removeValue(forKey: taskID)
    }
  }

  func scheduleCompletionState(for taskRow: TaskRowSnapshot) -> ScheduleTaskCompletionState {
    ScheduleTaskCompletionState(
      isCompleted: taskRow.isCompleted,
      completionDate: taskRow.completionDate,
      isRecurring: WorkspaceTaskScheduleEventStore.isRecurring(taskRow),
      occurrenceDate: taskRow.reminderDate,
      editFields: scheduleTaskEditFields(for: taskRow)
    )
  }

  func updateScheduleTaskCompletion(
    taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    targetState: ScheduleTaskCompletionState? = nil,
    undoTargetState: ScheduleTaskCompletionState? = nil,
    registerUndo: Bool
  ) {
    guard allowScheduleRetainedWrite("task-completion") else { return }
    let optimisticIsCompleted = targetState?.isCompleted ?? isCompleted
    let previousOptimisticValue = optimisticScheduleTaskCompletionByID[taskID]
    optimisticScheduleTaskCompletionByID[taskID] = optimisticIsCompleted
    Task { @MainActor in
      guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else {
        restoreOptimisticScheduleTaskCompletion(
          taskID: taskID,
          expectedCurrentValue: optimisticIsCompleted,
          previousValue: previousOptimisticValue
        )
        return
      }
      let previousState = scheduleCompletionState(for: taskDescriptor.taskRow)
      let nextState =
        targetState
        ?? ScheduleTaskCompletionState(
          isCompleted: isCompleted,
          completionDate: isCompleted ? (completionDate ?? .now) : nil,
          isRecurring: previousState.isRecurring,
          occurrenceDate: previousState.occurrenceDate,
          editFields: previousState.editFields
        )
      guard previousState != nextState else {
        clearOptimisticScheduleTaskCompletion(
          taskID: taskID,
          expectedIsCompleted: optimisticIsCompleted
        )
        return
      }
      do {
        let mutationPlan = RecurringCompletionUndoScheduleRestorePolicy.mutationPlan(
          previousIsCompleted: previousState.isCompleted,
          nextIsCompleted: nextState.isCompleted,
          isRecurring: nextState.isRecurring,
          previousFields: previousState.editFields,
          fields: nextState.editFields
        )
        var result: RetainedTaskCommandResult?
        if mutationPlan.writesCompletion {
          result = try await RetainedTaskCommandFacade.setTaskCompletion(
            vaultRootURL: appState.obsidianVaultRootURL,
            projectID: projectID,
            taskID: taskID,
            isCompleted: nextState.isCompleted,
            completionDate: nextState.isCompleted && nextState.isRecurring
              ? (nextState.occurrenceDate ?? nextState.completionDate)
              : nextState.completionDate,
            reminderProjectProvider: appState.reminderProjectProvider
          )
        }
        if mutationPlan.restoresSchedule {
          result = try await RetainedTaskCommandFacade.setTaskSchedule(
            vaultRootURL: appState.obsidianVaultRootURL,
            projectID: projectID,
            taskID: taskID,
            day: nextState.editFields.day,
            timeMinutes: nextState.editFields.timeMinutes,
            durationMinutes: nextState.editFields.durationMinutes,
            calendar: calendar,
            reminderProjectProvider: appState.reminderProjectProvider,
            resetRecurringAnchor: nextState.isRecurring
          )
        }
        if RetainedTaskCompletionWorkspaceInvalidationPolicy.shouldBumpWorkspaceRevision(after: mutationPlan) {
          appState.bumpWorkspaceTreeRevision()
        }
        guard let result else {
          await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
          clearOptimisticScheduleTaskCompletion(
            taskID: taskID,
            expectedIsCompleted: nextState.isCompleted
          )
          return
        }
        await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
        retainedScheduleCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
        retainedScheduleCalendarBridgeWriteMarkersByTaskID[taskID] = result.calendarWriteMarker
        clearOptimisticScheduleTaskCompletion(
          taskID: taskID,
          expectedIsCompleted: nextState.isCompleted
        )

        guard registerUndo else { return }
        let registeredUndoState = undoTargetState ?? previousState
        appState.registerUndo(
          with: undoManager,
          actionName: nextState.isCompleted ? "할일 완료" : "할일 완료 취소"
        ) {
          self.updateScheduleTaskCompletion(
            taskID: taskID,
            projectID: projectID,
            isCompleted: registeredUndoState.isCompleted,
            completionDate: registeredUndoState.completionDate,
            targetState: registeredUndoState,
            undoTargetState: nextState,
            registerUndo: true
          )
        }
      } catch {
        restoreOptimisticScheduleTaskCompletion(
          taskID: taskID,
          expectedCurrentValue: nextState.isCompleted,
          previousValue: previousOptimisticValue
        )
        if await handleRetainedScheduleWriteFailure(error) {
          return
        }
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func updateSchedulePlannedWorkProgress(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date,
    registerUndo: Bool
  ) {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
    let previousCompletedUnits = taskDescriptor.taskRow.completedWorkUnits
    guard previousCompletedUnits != targetCompletedUnits else {
      return
    }
    guard allowScheduleMutation("planned-work-progress") else { return }
  }

  func scheduleDate(day: Date, timeMinutes: Int?) -> Date {
    let normalizedDay = calendar.startOfDay(for: day)
    guard let timeMinutes else { return normalizedDay }
    let boundedMinutes = min(max(0, timeMinutes), 23 * 60 + 59)
    let hours = boundedMinutes / 60
    let minutes = boundedMinutes % 60
    return calendar.date(bySettingHour: hours, minute: minutes, second: 0, of: normalizedDay)
      ?? normalizedDay
  }
}
