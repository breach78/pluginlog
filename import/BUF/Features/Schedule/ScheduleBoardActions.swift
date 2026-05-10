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

  func preview(for dragState: ScheduleTaskDragState) -> ScheduleInteractionPreview {
    let currentPointerScheduleY = dragState.currentPointerViewportLocation.map {
      $0.y - headerHeight + currentScrollOffsetY
    }
    let currentTopScheduleY: CGFloat? =
      dragState.originalTimeMinutes == nil
      ? dragState.originalTopScheduleY + dragState.translation.height + currentScrollOffsetY
      : nil

    let allowsDayChange = !dragState.isPreparationSlot
    let allowsTranslationDateSnap = allowsScheduleDragDateSnapping && allowsDayChange
    let preview = ScheduleDragDropInteractionLayer.preview(
      originalDay: dragState.originalDay,
      originalTimeMinutes: dragState.originalTimeMinutes,
      originalDurationMinutes: dragState.originalDurationMinutes,
      translation: dragState.translation,
      originalPointerScheduleY: dragState.originalPointerScheduleY,
      originalTopScheduleY: dragState.originalTopScheduleY,
      currentPointerScheduleY: currentPointerScheduleY,
      currentTopScheduleY: currentTopScheduleY,
      forceAllDay: dragState.isInAllDayZone,
      allowsDayChange: allowsTranslationDateSnap,
      allowsAllDay: true,
      metrics: interactionMetrics,
      calendar: calendar
    )
    return previewWithPointerDay(
      preview,
      pointerViewportLocation: dragState.currentPointerViewportLocation,
      allowsDayChange: allowsDayChange
    )
  }

  func preview(for dragState: ScheduleCalendarDragState) -> ScheduleInteractionPreview {
    let currentPointerScheduleY = dragState.currentPointerViewportLocation.map {
      $0.y - headerHeight + currentScrollOffsetY
    }
    let currentTopScheduleY: CGFloat? =
      dragState.originalTimeMinutes == nil
      ? dragState.originalTopScheduleY + dragState.translation.height + currentScrollOffsetY
      : nil

    let preview = ScheduleDragDropInteractionLayer.preview(
      originalDay: dragState.originalDay,
      originalTimeMinutes: dragState.originalTimeMinutes,
      originalDurationMinutes: dragState.originalDurationMinutes,
      translation: dragState.translation,
      originalPointerScheduleY: dragState.originalPointerScheduleY,
      originalTopScheduleY: dragState.originalTopScheduleY,
      currentPointerScheduleY: currentPointerScheduleY,
      currentTopScheduleY: currentTopScheduleY,
      forceAllDay: dragState.isInAllDayZone,
      allowsDayChange: true,
      metrics: interactionMetrics,
      calendar: calendar
    )
    guard let timeMinutes = preview.timeMinutes else {
      return preview
    }
    guard dragState.originalTimeMinutes != nil else {
      return ScheduleInteractionPreview(
        day: preview.day,
        timeMinutes: timeMinutes,
        durationMinutes: timedMinimumDuration
      )
    }
    return ScheduleInteractionPreview(
      day: preview.day,
      timeMinutes: timeMinutes,
      durationMinutes: dragState.originalDurationMinutes
    )
  }

  func previewWithPointerDay(
    _ preview: ScheduleInteractionPreview,
    pointerViewportLocation: CGPoint?,
    allowsDayChange: Bool
  ) -> ScheduleInteractionPreview {
    ScheduleDragDropInteractionLayer.previewByApplyingPointerDay(
      preview,
      pointerViewportLocation: pointerViewportLocation,
      allowsDayChange: allowsDayChange,
      titleColumnWidth: titleColumnWidth,
      scrollOffsetX: currentScrollOffsetX,
      days: days,
      metrics: interactionMetrics
    )
  }

  func taskDragPointerViewportLocation(
    for dragState: ScheduleTaskDragState,
    value: DragGesture.Value
  ) -> CGPoint {
    scrollViewportState.pointerViewportLocation()
      ?? CGPoint(
        x: dragState.originalPointerViewportX + value.translation.width,
        y: dragState.originalPointerViewportY + value.translation.height
      )
  }

  func preview(for resizeState: ScheduleTaskResizeState) -> ScheduleInteractionPreview {
    ScheduleTimeResizingInteractionLayer.preview(
      originalDay: resizeState.originalDay,
      originalTimeMinutes: resizeState.originalTimeMinutes,
      originalDurationMinutes: resizeState.originalDurationMinutes,
      isStartEdge: resizeState.edge == .start,
      translationHeight: resizeState.translationHeight,
      metrics: interactionMetrics
    )
  }

  func preview(for resizeState: ScheduleCalendarResizeState) -> ScheduleInteractionPreview {
    ScheduleTimeResizingInteractionLayer.preview(
      originalDay: resizeState.originalDay,
      originalTimeMinutes: resizeState.originalTimeMinutes,
      originalDurationMinutes: resizeState.originalDurationMinutes,
      isStartEdge: resizeState.edge == .start,
      translationHeight: resizeState.translationHeight,
      metrics: interactionMetrics
    )
  }

  func taskDragGesture(
    for taskDescriptor: WorkspaceScheduleTaskDescriptor,
    entryID: String,
    originalDay: Date,
    originalTimeMinutes: Int?,
    originalDurationMinutes: Int?,
    itemFrame: CGRect,
    originalTopScheduleYOverride: CGFloat? = nil,
    isAllDay: Bool,
    isPreparationSlot: Bool = false,
    targetCompletedWorkUnits: Int? = nil
  ) -> some Gesture {
    let taskID = taskDescriptor.taskRow.id
    return DragGesture(minimumDistance: 6)
      .onChanged { value in
        guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return }
        guard activeTaskResize == nil, activeCalendarDrag == nil, activeCalendarResize == nil else { return }
        var dragState = activeTaskDrag
        if dragState?.entryID != entryID {
          let visibleAllDayY = min(itemFrame.minY, allDayRailVisibleHeight - itemFrame.height)
          let originalScheduleY =
            originalTopScheduleYOverride
            ?? (isAllDay ? visibleAllDayY - allDayRailVisibleHeight : itemFrame.minY)
          let originalViewportFrame =
            isAllDay
            ? CGRect(
              x: titleColumnWidth + itemFrame.minX - currentScrollOffsetX,
              y: dateHeaderHeight + visibleAllDayY,
              width: itemFrame.width,
              height: itemFrame.height
            )
            : CGRect(
              x: titleColumnWidth + itemFrame.minX - currentScrollOffsetX,
              y: headerHeight + itemFrame.minY - currentScrollOffsetY,
              width: itemFrame.width,
              height: itemFrame.height
            )
          dragState = ScheduleTaskDragState(
            entryID: entryID,
            taskID: taskID,
            isPreparationSlot: isPreparationSlot,
            targetCompletedWorkUnits: targetCompletedWorkUnits,
            originalDay: originalDay,
            originalTimeMinutes: originalTimeMinutes,
            originalDurationMinutes: originalDurationMinutes,
            originalViewportFrame: originalViewportFrame,
            originalPointerViewportX: originalViewportFrame.minX + value.startLocation.x,
            originalPointerViewportY: originalViewportFrame.minY + value.startLocation.y,
            originalPointerScheduleY: originalScheduleY + value.startLocation.y,
            originalTopScheduleY: originalScheduleY
          )
        }
        suppressTaskTap()
        guard var dragState else { return }
        dragState.translation = value.translation
        let pointerViewportLocation = taskDragPointerViewportLocation(
          for: dragState,
          value: value
        )
        dragState.currentPointerViewportLocation = pointerViewportLocation
        dragState.isInAllDayZone = isPointerInAllDayZone(
          pointerViewportLocation: pointerViewportLocation,
          wasInAllDayZone: dragState.isInAllDayZone
        )
        activeTaskDrag = dragState
        onTaskDragProjectionChanged?(
          taskDragPointInGlobalSpace(for: dragState),
          taskDragProjectionFrameInCoordinateSpace(for: dragState)
        )
      }
      .onEnded { value in
        guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return }
        guard let dragState = activeTaskDrag, dragState.entryID == entryID else { return }
        suppressTaskTap()
        var resolvedDragState = dragState
        let pointerViewportLocation = taskDragPointerViewportLocation(
          for: dragState,
          value: value
        )
        resolvedDragState.currentPointerViewportLocation = pointerViewportLocation
        resolvedDragState.isInAllDayZone = isPointerInAllDayZone(
          pointerViewportLocation: pointerViewportLocation,
          wasInAllDayZone: dragState.isInAllDayZone
        )
        let dropPoint = taskDragPointInGlobalSpace(for: resolvedDragState)
        let projectionFrame = taskDragProjectionFrameInCoordinateSpace(for: resolvedDragState)
        if onTaskDragEndedAtPoint != nil, dropPoint == nil || projectionFrame == nil {
          logScheduleInvalidDrop(
            at: resolvedDragState.currentPointerViewportLocation ?? .zero,
            reason: .projectionUnavailable
          )
        }
        if onTaskDragEndedAtPoint?(dragState.taskID, dropPoint, projectionFrame) == true {
          activeTaskDrag = nil
          onTaskDragProjectionChanged?(nil, nil)
          return
        }
        let resolvedPreview = preview(for: resolvedDragState)
        if let dropFrame = dragDropTargetViewportFrame(for: resolvedDragState, preview: resolvedPreview) {
          committedTaskDrop = CommittedTaskDropState(
            originalFrame: dragState.originalViewportFrame,
            isOriginalAllDay: dragState.originalTimeMinutes == nil,
            dropFrame: dropFrame,
            color: scheduleColor(for: taskDescriptor.projectColorHex),
            isAllDay: resolvedPreview.timeMinutes == nil,
            label: resolvedPreview.timeMinutes == nil ? nil : scheduleDragPreviewLabel(for: resolvedPreview)
          )
        }
        activeTaskDrag = nil
        onTaskDragProjectionChanged?(nil, nil)
        if dragState.isPreparationSlot, let targetCompletedWorkUnits = dragState.targetCompletedWorkUnits {
          applyPreparationPreview(
            resolvedPreview,
            to: taskDescriptor,
            targetCompletedWorkUnits: targetCompletedWorkUnits,
            actionName: "예상 일정 이동"
          )
        } else {
          applyPreview(
            resolvedPreview,
            to: taskDescriptor,
            actionName: "일정 이동"
          )
        }
      }
  }

  func taskDragPointInGlobalSpace(for dragState: ScheduleTaskDragState) -> CGPoint? {
    guard !boardFrameInGlobal.isNull else {
      recordScheduleViewportDiagnostic(.dragProjectionFrameUnavailable)
      return nil
    }

    let viewportPoint =
      dragState.currentPointerViewportLocation
      ?? CGPoint(
        x: dragState.originalPointerViewportX + dragState.translation.width,
        y: dragState.originalPointerViewportY + dragState.translation.height
      )

    return CGPoint(
      x: boardFrameInGlobal.minX + viewportPoint.x,
      y: boardFrameInGlobal.minY + viewportPoint.y
    )
  }

  func taskDragProjectionFrameInCoordinateSpace(for dragState: ScheduleTaskDragState) -> CGRect? {
    guard !boardFrameInGlobal.isNull else {
      recordScheduleViewportDiagnostic(.dragProjectionFrameUnavailable)
      return nil
    }

    let rawFollowFrame = dragState.originalViewportFrame.offsetBy(
      dx: dragState.isPreparationSlot ? 0 : dragState.translation.width,
      dy: dragState.translation.height
    )

    return rawFollowFrame.offsetBy(dx: boardFrameInGlobal.minX, dy: boardFrameInGlobal.minY)
  }

  func eventDragGesture(
    for event: ScheduleCalendarEvent,
    itemFrame: CGRect,
    originalTopScheduleYOverride: CGFloat? = nil,
    isAllDay: Bool
  ) -> some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        guard event.canEditTiming,
          activeTaskDrag == nil, activeTaskResize == nil, activeCalendarResize == nil
        else { return }

        var dragState = activeCalendarDrag
        if dragState?.eventID != event.id {
          let visibleAllDayY = min(itemFrame.minY, allDayRailVisibleHeight - itemFrame.height)
          let originalScheduleY =
            originalTopScheduleYOverride
            ?? (isAllDay ? visibleAllDayY - allDayRailVisibleHeight : itemFrame.minY)
          let originalViewportFrame =
            isAllDay
            ? CGRect(
              x: titleColumnWidth + itemFrame.minX - currentScrollOffsetX,
              y: dateHeaderHeight + visibleAllDayY,
              width: itemFrame.width,
              height: itemFrame.height
            )
            : CGRect(
              x: titleColumnWidth + itemFrame.minX - currentScrollOffsetX,
              y: headerHeight + itemFrame.minY - currentScrollOffsetY,
              width: itemFrame.width,
              height: itemFrame.height
            )
          dragState = ScheduleCalendarDragState(
            eventID: event.id,
            originalDay: calendar.startOfDay(for: event.startDate),
            originalTimeMinutes: event.isAllDay ? nil : timeMinutes(for: event.startDate),
            originalDurationMinutes: durationMinutes(for: event),
            originalViewportFrame: originalViewportFrame,
            originalPointerViewportX: originalViewportFrame.minX + value.startLocation.x,
            originalPointerViewportY: originalViewportFrame.minY + value.startLocation.y,
            originalPointerScheduleY: originalScheduleY + value.startLocation.y,
            originalTopScheduleY: originalScheduleY
          )
        }

        suppressTaskTap()
        guard var dragState else { return }
        dragState.translation = value.translation
        let pointerViewportLocation =
          scrollViewportState.pointerViewportLocation()
          ?? CGPoint(
            x: dragState.originalPointerViewportX + value.translation.width,
            y: dragState.originalPointerViewportY + value.translation.height
          )
        dragState.currentPointerViewportLocation = pointerViewportLocation
        dragState.isInAllDayZone = isPointerInAllDayZone(
          pointerViewportLocation: pointerViewportLocation,
          wasInAllDayZone: dragState.isInAllDayZone
        )
        activeCalendarDrag = dragState
      }
      .onEnded { value in
        guard let dragState = activeCalendarDrag, dragState.eventID == event.id else { return }
        suppressTaskTap()
        activeCalendarDrag = nil
        var resolvedDragState = dragState
        let pointerViewportLocation =
          scrollViewportState.pointerViewportLocation()
          ?? CGPoint(
            x: dragState.originalPointerViewportX + value.translation.width,
            y: dragState.originalPointerViewportY + value.translation.height
          )
        resolvedDragState.currentPointerViewportLocation = pointerViewportLocation
        resolvedDragState.isInAllDayZone = isPointerInAllDayZone(
          pointerViewportLocation: pointerViewportLocation,
          wasInAllDayZone: dragState.isInAllDayZone
        )
        commitCalendarPreview(
          preview(for: resolvedDragState),
          for: event,
          actionName: "캘린더 일정 이동"
        )
      }
  }

  func isPointerInAllDayZone(
    pointerViewportLocation: CGPoint,
    wasInAllDayZone: Bool
  ) -> Bool {
    let releaseSlop = max(4, min(8, allDayRowHeight * 0.35))
    var zone = allDayDropZoneFrame
    if wasInAllDayZone {
      zone.size.height += releaseSlop
    }
    return zone.contains(pointerViewportLocation)
  }

  func taskResizeGesture(
    for taskDescriptor: WorkspaceScheduleTaskDescriptor,
    entryID: String,
    originalDay: Date,
    originalTimeMinutes: Int,
    originalDurationMinutes: Int,
    edge: ScheduleResizeEdge,
    originalViewportFrame: CGRect,
    isPreparationSlot: Bool = false,
    targetCompletedWorkUnits: Int? = nil
  ) -> some Gesture {
    let taskID = taskDescriptor.taskRow.id
    return DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return }
        guard activeTaskDrag == nil, activeCalendarDrag == nil, activeCalendarResize == nil else {
          return
        }

        if activeTaskResize?.entryID != entryID || activeTaskResize?.edge != edge {
          activeTaskResize = ScheduleTaskResizeState(
            entryID: entryID,
            taskID: taskID,
            isPreparationSlot: isPreparationSlot,
            targetCompletedWorkUnits: targetCompletedWorkUnits,
            originalDay: originalDay,
            originalTimeMinutes: originalTimeMinutes,
            originalDurationMinutes: originalDurationMinutes,
            edge: edge,
            originalViewportFrame: originalViewportFrame
          )
          selectedScheduleTaskID = taskID
        }
        suppressTaskTap()
        activeTaskResize?.translationHeight = value.translation.height
      }
      .onEnded { _ in
        guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return }
        guard let resizeState = activeTaskResize, resizeState.entryID == entryID else { return }
        suppressTaskTap()
        activeTaskResize = nil
        if resizeState.isPreparationSlot, let targetCompletedWorkUnits = resizeState.targetCompletedWorkUnits {
          applyPreparationPreview(
            preview(for: resizeState),
            to: taskDescriptor,
            targetCompletedWorkUnits: targetCompletedWorkUnits,
            actionName: "예상 일정 길이 조절"
          )
        } else {
          applyPreview(
            preview(for: resizeState),
            to: taskDescriptor,
            actionName: "일정 길이 조절"
          )
        }
      }
  }

  func eventResizeGesture(
    for event: ScheduleCalendarEvent,
    originalDay: Date,
    originalTimeMinutes: Int,
    originalDurationMinutes: Int,
    edge: ScheduleResizeEdge,
    originalViewportFrame: CGRect
  ) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard event.canEditTiming,
          activeTaskDrag == nil, activeTaskResize == nil, activeCalendarDrag == nil,
          !event.isAllDay
        else {
          return
        }

        if activeCalendarResize?.eventID != event.id || activeCalendarResize?.edge != edge {
          activeCalendarResize = ScheduleCalendarResizeState(
            eventID: event.id,
            originalDay: originalDay,
            originalTimeMinutes: originalTimeMinutes,
            originalDurationMinutes: originalDurationMinutes,
            edge: edge,
            originalViewportFrame: originalViewportFrame
          )
        }
        suppressTaskTap()
        activeCalendarResize?.translationHeight = value.translation.height
      }
      .onEnded { _ in
        guard let resizeState = activeCalendarResize, resizeState.eventID == event.id else { return }
        suppressTaskTap()
        activeCalendarResize = nil
        commitCalendarPreview(
          preview(for: resizeState),
          for: event,
          actionName: "캘린더 일정 길이 조절"
        )
      }
  }

  func applyPreview(
    _ preview: ScheduleInteractionPreview,
    to taskDescriptor: WorkspaceScheduleTaskDescriptor,
    actionName: String
  ) {
    let taskRow = taskDescriptor.taskRow
    let previousDay = WorkspaceTaskScheduleEventStore.scheduledDay(for: taskRow, calendar: calendar)
    let previousTime = WorkspaceTaskScheduleEventStore.scheduledTimeMinutes(for: taskRow, calendar: calendar)
    let previousDuration = WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(for: taskRow)

    guard previousDay != preview.day
      || previousTime != preview.timeMinutes
      || previousDuration != preview.durationMinutes
    else {
      committedTaskDrop = nil
      return
    }

    applyScheduleState(
      taskID: taskRow.id,
      projectID: taskDescriptor.projectID,
      day: preview.day,
      timeMinutes: preview.timeMinutes,
      durationMinutes: preview.durationMinutes,
      registerUndo: true,
      actionName: actionName
    )
  }

  func applyPreparationPreview(
    _ preview: ScheduleInteractionPreview,
    to taskDescriptor: WorkspaceScheduleTaskDescriptor,
    targetCompletedWorkUnits: Int,
    actionName: String
  ) {
    let taskRow = taskDescriptor.taskRow
    guard let previousSchedule = WorkspaceTaskScheduleEventStore.resolvedPreparationSchedule(
      for: taskRow,
      targetCompletedUnits: targetCompletedWorkUnits
    ) else {
      return
    }

    let isAllDay = preview.timeMinutes == nil
    let timeMinutes = min(
      max(0, preview.timeMinutes ?? previousSchedule.timeMinutes),
      23 * 60 + 45
    )
    let durationMinutes: Int
    if previousSchedule.isAllDay,
      preview.timeMinutes != nil,
      preview.durationMinutes == interactionMetrics.timedMinimumDurationMinutes
    {
      durationMinutes = previousSchedule.durationMinutes
    } else {
      durationMinutes = max(5, preview.durationMinutes ?? previousSchedule.durationMinutes)
    }

    guard previousSchedule.isAllDay != isAllDay
      || previousSchedule.timeMinutes != timeMinutes
      || previousSchedule.durationMinutes != durationMinutes
    else {
      return
    }

    applyPreparationScheduleState(
      taskID: taskRow.id,
      projectID: taskDescriptor.projectID,
      targetCompletedWorkUnits: targetCompletedWorkUnits,
      isAllDay: isAllDay,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes,
      registerUndo: true,
      actionName: actionName
    )
  }

  func commitCalendarPreview(
    _ preview: ScheduleInteractionPreview,
    for event: ScheduleCalendarEvent,
    actionName: String
  ) {
    guard calendarPreviewDiffers(from: event, preview: preview) else {
      return
    }

    if event.isRecurring {
      pendingCalendarEditAction = PendingScheduleCalendarEditAction(
        eventID: event.id,
        preview: preview,
        actionName: actionName
      )
      return
    }

    applyCalendarPreview(
      preview,
      to: event,
      scope: .thisEvent,
      actionName: actionName
    )
  }

  func commitPendingCalendarEdit(scope: ScheduleCalendarRecurringEditScope) {
    guard let pendingAction = pendingCalendarEditAction,
      let event = appState.resolvedScheduleCalendarEvent(eventID: pendingAction.eventID)
    else {
      pendingCalendarEditAction = nil
      return
    }

    pendingCalendarEditAction = nil
    applyCalendarPreview(
      pendingAction.preview,
      to: event,
      scope: scope,
      actionName: pendingAction.actionName
    )
  }

  func applyCalendarPreview(
    _ preview: ScheduleInteractionPreview,
    to event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope,
    actionName: String,
    registerUndo: Bool = true
  ) {
    let previousPreview = schedulePreview(for: event)
    Task { @MainActor in
      do {
        let updatedEvent = try await appState.writeScheduleCalendarEventTiming(
          event,
          preview: preview,
          scope: scope
        )
        calendarEditError = nil

        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          self.applyCalendarPreview(
            previousPreview,
            to: updatedEvent,
            scope: scope,
            actionName: actionName,
            registerUndo: true
          )
        }
      } catch let error as ScheduleCalendarEditError {
        handleScheduleCalendarEditError(error, context: .applyPreview)
      } catch {
        handleScheduleCalendarEditFailure(
          error,
          context: .applyPreview,
          fallback: .saveFailed(error.localizedDescription)
        )
      }
    }
  }

  func calendarPreviewDiffers(
    from event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview
  ) -> Bool {
    let currentDay = calendar.startOfDay(for: event.startDate)
    let currentTimeMinutes = event.isAllDay ? nil : timeMinutes(for: event.startDate)
    let currentDurationMinutes = event.isAllDay ? nil : durationMinutes(for: event)
    return currentDay != preview.day
      || currentTimeMinutes != preview.timeMinutes
      || currentDurationMinutes != preview.durationMinutes
  }

  func schedulePreview(for event: ScheduleCalendarEvent) -> ScheduleInteractionPreview {
    ScheduleInteractionPreview(
      day: calendar.startOfDay(for: event.startDate),
      timeMinutes: event.isAllDay ? nil : timeMinutes(for: event.startDate),
      durationMinutes: event.isAllDay ? nil : durationMinutes(for: event)
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
          (try? await ObsidianRetainedTaskCommandService.taskEditFields(
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
        _ = try await ObsidianRetainedTaskCommandService.deleteTask(
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

  func applyScheduleState(
    taskID: UUID,
    projectID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    registerUndo: Bool,
    actionName: String
  ) {
    guard allowScheduleRetainedWrite("task-schedule") else { return }
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }

    let previousDay = WorkspaceTaskScheduleEventStore.scheduledDay(
      for: taskDescriptor.taskRow,
      calendar: calendar
    )
    let previousTime = WorkspaceTaskScheduleEventStore.scheduledTimeMinutes(
      for: taskDescriptor.taskRow,
      calendar: calendar
    )
    let previousDuration = WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(
      for: taskDescriptor.taskRow
    )
    let nextSchedule = optimisticScheduleTaskScheduleState(
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )

    guard previousDay != nextSchedule.day
      || previousTime != nextSchedule.timeMinutes
      || previousDuration != nextSchedule.durationMinutes
    else {
      return
    }
    selectedScheduleTaskID = taskID
    scheduleTaskWriteNotice = nil
    let previousOptimisticSchedule = optimisticScheduleTaskScheduleByID[taskID]
    optimisticScheduleTaskScheduleByID[taskID] = nextSchedule
    Task { @MainActor in
      do {
        let result = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          day: nextSchedule.day,
          timeMinutes: nextSchedule.timeMinutes,
          durationMinutes: nextSchedule.durationMinutes,
          calendar: calendar,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        await reloadChangedWorkspaceScheduleProjectDetails(for: [projectID])
        retainedScheduleCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
        retainedScheduleCalendarBridgeWriteMarkersByTaskID[taskID] = nil
        refreshCalendarOverlayIfChanged(by: result)
        clearOptimisticScheduleTaskSchedule(taskID: taskID, expectedSchedule: nextSchedule)

        guard registerUndo else { return }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          self.applyScheduleState(
            taskID: taskID,
            projectID: projectID,
            day: previousDay,
            timeMinutes: previousTime,
            durationMinutes: previousDuration,
            registerUndo: true,
            actionName: actionName
          )
        }
      } catch {
        restoreOptimisticScheduleTaskSchedule(
          taskID: taskID,
          expectedCurrentSchedule: nextSchedule,
          previousSchedule: previousOptimisticSchedule
        )
        if await handleRetainedScheduleWriteFailure(error) {
          return
        }
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func handleRetainedScheduleWriteFailure(_ error: Error) async -> Bool {
    guard let retainedError = error as? RetainedTaskCommandError else {
      return false
    }

    guard case .retainedProjectionFailed(let message) = retainedError,
      message.contains("reminder sync baseline")
    else {
      return false
    }

    AppLogger.ui.error(
      "schedule retained write stale baseline: \(message, privacy: .public)"
    )
    scheduleTaskWriteNotice = ScheduleBoardRuntimeNotice(
      id: "schedule_retained_write_stale_baseline",
      symbol: "arrow.clockwise.circle",
      title: "일정 저장 대기",
      message: "리마인더가 먼저 바뀌어 최신 상태를 다시 불러왔습니다. 같은 이동을 다시 시도해 주세요."
    )
    await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
    refreshCalendarOverlay(force: true)
    return true
  }

  func externalTaskDropPreview(at location: CGPoint) -> ScheduleInteractionPreview? {
    ScheduleDragDropInteractionLayer.externalDropPreview(
      at: location,
      days: days,
      externalMetrics: ScheduleExternalDropMetrics(
        titleColumnWidth: titleColumnWidth,
        headerHeight: headerHeight,
        dayColumnsWidth: dayColumnsWidth,
        scrollOffsetX: currentScrollOffsetX,
        scrollOffsetY: currentScrollOffsetY
      ),
      interactionMetrics: interactionMetrics
    )
  }

  func applyExternalTaskDrop(taskID: UUID, preview: ScheduleInteractionPreview) {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }

    releaseActiveTextResponderForUndo()
    suppressTaskTap(for: 0.2)

    let durationMinutes: Int?
    if preview.timeMinutes != nil {
      durationMinutes = max(
        timedMinimumDuration,
        WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(for: taskDescriptor.taskRow)
          ?? timedMinimumDuration
      )
    } else {
      durationMinutes = nil
    }

    applyScheduleState(
      taskID: taskID,
      projectID: taskDescriptor.projectID,
      day: preview.day,
      timeMinutes: preview.timeMinutes,
      durationMinutes: durationMinutes,
      registerUndo: true,
      actionName: "일정 배치"
    )
  }

  func moveScheduleMonthItem(_ item: ScheduleMonthDragItem, to targetDay: Date) {
    let normalizedTargetDay = calendar.startOfDay(for: targetDay)
    releaseActiveTextResponderForUndo()
    suppressTaskTap(for: 0.2)

    switch item {
    case .task(let taskID):
      guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
      guard !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence else { return }

      let timeMinutes = WorkspaceTaskScheduleEventStore.scheduledTimeMinutes(
        for: taskDescriptor.taskRow,
        calendar: calendar
      )
      let durationMinutes = timeMinutes == nil
        ? nil
        : (
          WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(
            for: taskDescriptor.taskRow
          ) ?? WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
        )

      applyScheduleState(
        taskID: taskID,
        projectID: taskDescriptor.projectID,
        day: normalizedTargetDay,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes,
        registerUndo: true,
        actionName: "월간 일정 이동"
      )
      if let updatedDescriptor = scheduleTaskDescriptor(for: taskID),
        let updatedItem = ScheduleMonthItemFactory.item(
          workspaceTask: updatedDescriptor,
          calendar: calendar
        )
      {
        onMonthItemScheduleChanged(updatedItem)
      }

    case .calendarEvent(let eventID):
      guard let event = appState.resolvedScheduleCalendarEvent(eventID: eventID),
        event.canEditTiming
      else {
        return
      }

      let preview = ScheduleInteractionPreview(
        day: normalizedTargetDay,
        timeMinutes: event.isAllDay ? nil : timeMinutes(for: event.startDate),
        durationMinutes: event.isAllDay ? nil : durationMinutes(for: event)
      )
      commitCalendarPreview(
        preview,
        for: event,
        actionName: "월간 일정 이동"
      )
      if !event.isRecurring {
        onMonthItemScheduleChanged(
          ScheduleMonthItemFactory.item(
            calendarEvent: calendarEvent(applying: preview, to: event),
            isBackgroundCalendar: false
          )
        )
      }
    }
  }

  private func calendarEvent(
    applying preview: ScheduleInteractionPreview,
    to event: ScheduleCalendarEvent
  ) -> ScheduleCalendarEvent {
    let startDate = previewStartDate(preview)
    let endDate = previewEndDate(preview, startDate: startDate)
    return ScheduleCalendarEvent(
      id: event.id,
      eventIdentifier: event.eventIdentifier,
      externalIdentifier: event.externalIdentifier,
      occurrenceDate: event.occurrenceDate,
      calendarIdentifier: event.calendarIdentifier,
      calendarTitle: event.calendarTitle,
      calendarColorHex: event.calendarColorHex,
      title: event.title,
      notes: event.notes,
      startDate: startDate,
      endDate: endDate,
      isAllDay: preview.timeMinutes == nil,
      isRecurring: event.isRecurring,
      isDetached: event.isDetached,
      canEditTiming: event.canEditTiming,
      editTimingRestrictionReason: event.editTimingRestrictionReason
    )
  }

  private func previewStartDate(_ preview: ScheduleInteractionPreview) -> Date {
    let day = calendar.startOfDay(for: preview.day ?? today)
    guard let timeMinutes = preview.timeMinutes else {
      return day
    }
    return calendar.date(byAdding: .minute, value: timeMinutes, to: day) ?? day
  }

  private func previewEndDate(
    _ preview: ScheduleInteractionPreview,
    startDate: Date
  ) -> Date {
    if preview.timeMinutes != nil {
      let duration = max(5, preview.durationMinutes ?? WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes)
      return calendar.date(byAdding: .minute, value: duration, to: startDate) ?? startDate
    }
    let day = calendar.startOfDay(for: preview.day ?? today)
    return calendar.date(byAdding: .day, value: 1, to: day) ?? day
  }

  func applyPreparationScheduleState(
    taskID: UUID,
    projectID: UUID,
    targetCompletedWorkUnits: Int,
    isAllDay: Bool,
    timeMinutes: Int,
    durationMinutes: Int,
    registerUndo: Bool,
    actionName: String
  ) {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
    guard let previousSchedule = WorkspaceTaskScheduleEventStore.resolvedPreparationSchedule(
      for: taskDescriptor.taskRow,
      targetCompletedUnits: targetCompletedWorkUnits
    ) else {
      return
    }

    let normalizedTime = min(max(0, timeMinutes), 23 * 60 + 45)
    let normalizedDuration = max(5, durationMinutes)
    guard previousSchedule.isAllDay != isAllDay
      || previousSchedule.timeMinutes != normalizedTime
      || previousSchedule.durationMinutes != normalizedDuration
    else {
      return
    }
    guard allowScheduleMutation("preparation-schedule") else { return }
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
        let result = try await ObsidianRetainedTaskCommandService.createTask(
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
      let result = try await ObsidianRetainedTaskCommandService.createTask(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        title: snapshot.fields.title,
        day: snapshot.fields.day,
        timeMinutes: snapshot.fields.timeMinutes,
        durationMinutes: snapshot.fields.durationMinutes,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      _ = try await ObsidianRetainedTaskCommandService.updateTaskEditFields(
        vaultRootURL: appState.obsidianVaultRootURL,
        projectID: projectID,
        taskID: result.taskID,
        fields: snapshot.fields,
        calendar: calendar,
        reminderProjectProvider: appState.reminderProjectProvider
      )
      if snapshot.isCompleted {
        _ = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
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
          result = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
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
          result = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
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
