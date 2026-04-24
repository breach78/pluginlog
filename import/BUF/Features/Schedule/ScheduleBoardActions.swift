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
        hasher.combine(entry.renderFingerprint)
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
}

extension ScheduleBoardView {
  func allowScheduleMutation(_ feature: String) -> Bool {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.schedule, feature: feature)
    return false
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
    hasher.combine(projectIDs)
    hasher.combine(workspaceTreeRevision)
    return hasher.finalize()
  }

  func reloadWorkspaceScheduleProjectDetails(for projectIDs: [UUID]) async {
    let requestedProjectIDs = Array(Set(projectIDs))
    guard !requestedProjectIDs.isEmpty else {
      await MainActor.run {
        workspaceScheduleProjectSnapshots = [:]
        workspaceScheduleSliceEntriesByProjectID = [:]
        retainedScheduleCalendarBridgeDecisionsByTaskID = [:]
        retainedScheduleCalendarBridgeWriteMarkersByTaskID = [:]
        invalidateWorkspaceScheduleProjectionCaches()
        recordWorkspaceLoadFallback(nil)
      }
      return
    }

    let graphRootURL = await MainActor.run {
      appState.logseqGraphRootURL
    }
    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      graphRootURL: graphRootURL,
      projectIDs: requestedProjectIDs
    )

    await MainActor.run {
      let resolvedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(retainedResult)
      workspaceScheduleProjectSnapshots = resolvedRead.projectSnapshots
      workspaceScheduleSliceEntriesByProjectID = resolvedRead.scheduleEntriesByProjectID
      retainedScheduleCalendarBridgeDecisionsByTaskID =
        resolvedRead.calendarBridgeDecisionsByTaskID
      let currentTaskIDs = Set(resolvedRead.calendarBridgeDecisionsByTaskID.keys)
      retainedScheduleCalendarBridgeWriteMarkersByTaskID =
        retainedScheduleCalendarBridgeWriteMarkersByTaskID.filter { currentTaskIDs.contains($0.key) }
      if RetainedWorkspaceSurfaceProjectionBuilder.shouldInvalidateConsumerCaches(
        for: resolvedRead.source
      ) {
        invalidateWorkspaceScheduleProjectionCaches()
      }

      switch resolvedRead.source {
      case .retained:
        recordWorkspaceLoadFallback(nil)
      case .legacyFallback:
        assertionFailure("Schedule retained-only read must not resolve legacy fallback.")
        recordWorkspaceLoadFallback(nil)
      case .blocked:
        appState.errorMessage = resolvedRead.errorMessage
        recordWorkspaceLoadFallback(nil)
      }
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

    return ScheduleDragDropInteractionLayer.preview(
      originalDay: dragState.originalDay,
      originalTimeMinutes: dragState.originalTimeMinutes,
      originalDurationMinutes: dragState.originalDurationMinutes,
      translation: dragState.translation,
      originalPointerScheduleY: dragState.originalPointerScheduleY,
      originalTopScheduleY: dragState.originalTopScheduleY,
      currentPointerScheduleY: currentPointerScheduleY,
      currentTopScheduleY: currentTopScheduleY,
      forceAllDay: dragState.isInAllDayZone,
      allowsDayChange: !dragState.isPreparationSlot,
      allowsAllDay: true,
      metrics: interactionMetrics,
      calendar: calendar
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

    return ScheduleDragDropInteractionLayer.preview(
      originalDay: dragState.originalDay,
      originalTimeMinutes: dragState.originalTimeMinutes,
      originalDurationMinutes: dragState.originalDurationMinutes,
      translation: dragState.translation,
      originalPointerScheduleY: dragState.originalPointerScheduleY,
      originalTopScheduleY: dragState.originalTopScheduleY,
      currentPointerScheduleY: currentPointerScheduleY,
      currentTopScheduleY: currentTopScheduleY,
      forceAllDay: dragState.isInAllDayZone,
      metrics: interactionMetrics,
      calendar: calendar
    )
  }

  func taskDragPointerViewportLocation(
    for dragState: ScheduleTaskDragState,
    value: DragGesture.Value
  ) -> CGPoint {
    scrollViewportState.pointerViewportLocation()
      ?? CGPoint(
        x: dragState.originalViewportFrame.midX + value.translation.width,
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
    isAllDay: Bool,
    isPreparationSlot: Bool = false,
    targetCompletedWorkUnits: Int? = nil
  ) -> some Gesture {
    let taskID = taskDescriptor.taskRow.id
    return DragGesture(minimumDistance: 6)
      .onChanged { value in
        guard activeTaskResize == nil, activeCalendarDrag == nil, activeCalendarResize == nil else { return }
        var dragState = activeTaskDrag
        if dragState?.entryID != entryID {
          let visibleAllDayY = min(itemFrame.minY, allDayRailVisibleHeight - itemFrame.height)
          let originalScheduleY = isAllDay ? visibleAllDayY - allDayRailVisibleHeight : itemFrame.minY
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
            originalPointerViewportY: originalViewportFrame.minY + value.startLocation.y,
            originalPointerScheduleY: originalScheduleY + value.startLocation.y,
            originalTopScheduleY: originalScheduleY
          )
          selectedScheduleTaskID = taskID
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
        guard let dragState = activeTaskDrag, dragState.entryID == entryID else { return }
        suppressTaskTap()
        activeTaskDrag = nil
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
          onTaskDragProjectionChanged?(nil, nil)
          return
        }
        onTaskDragProjectionChanged?(nil, nil)
        if dragState.isPreparationSlot, let targetCompletedWorkUnits = dragState.targetCompletedWorkUnits {
          applyPreparationPreview(
            preview(for: resolvedDragState),
            to: taskDescriptor,
            targetCompletedWorkUnits: targetCompletedWorkUnits,
            actionName: "예상 일정 이동"
          )
        } else {
          applyPreview(
            preview(for: resolvedDragState),
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
        x: dragState.originalViewportFrame.midX + dragState.translation.width,
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
          let originalScheduleY = isAllDay ? visibleAllDayY - allDayRailVisibleHeight : itemFrame.minY
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
            x: dragState.originalViewportFrame.midX + value.translation.width,
            y: dragState.originalPointerViewportY + value.translation.height
          )
        dragState.currentPointerViewportLocation = pointerViewportLocation
        dragState.isInAllDayZone = isPointerInAllDayZone(
          pointerViewportLocation: pointerViewportLocation,
          wasInAllDayZone: dragState.isInAllDayZone
        )
        activeCalendarDrag = dragState
      }
      .onEnded { _ in
        guard let dragState = activeCalendarDrag, dragState.eventID == event.id else { return }
        suppressTaskTap()
        activeCalendarDrag = nil
        commitCalendarPreview(
          preview(for: dragState),
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
            originalDay: calendar.startOfDay(for: event.startDate),
            originalTimeMinutes: timeMinutes(for: event.startDate),
            originalDurationMinutes: durationMinutes(for: event),
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
    guard allowScheduleMutation("calendar-timing") else { return }
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
    _ = taskID
    selectedScheduleTaskID = taskID
    appState.selectedProjectID = projectID
    onSelectProject(projectID)
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

  func deleteScheduleTask(_ taskID: UUID, actionName: String = "할일 삭제") {
    if selectedScheduleTaskID == taskID {
      selectedScheduleTaskID = nil
    }
    guard allowScheduleMutation("delete-task") else { return }
  }

  func deleteScheduleCalendarEvent(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) {
    guard allowScheduleMutation("delete-calendar-event") else { return }
  }

  func suppressTaskTap(for duration: TimeInterval = 0.35) {
    suppressedTaskTapUntil = Date().addingTimeInterval(duration)
  }

  func shouldHandleTaskTap() -> Bool {
    Date() >= suppressedTaskTapUntil
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

    guard previousDay != day || previousTime != timeMinutes || previousDuration != durationMinutes else {
      return
    }
    selectedScheduleTaskID = taskID
    Task { @MainActor in
      do {
        let result = try await RetainedTaskCommandService.setTaskSchedule(
          graphRootURL: appState.logseqGraphRootURL,
          projectID: projectID,
          taskID: taskID,
          day: day,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes,
          calendar: calendar,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        let bridgeResult: RetainedCalendarBridgeApplyResult?
        do {
          bridgeResult = try await RetainedCalendarEventKitBridge.apply(
            commandResult: result,
            graphRootURL: appState.logseqGraphRootURL
          )
        } catch {
          bridgeResult = nil
          appState.errorMessage = error.localizedDescription
        }
        await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
        if let bridgeResult {
          retainedScheduleCalendarBridgeDecisionsByTaskID[taskID] =
            bridgeResult.calendarBridgeDecision
          retainedScheduleCalendarBridgeWriteMarkersByTaskID[taskID] =
            bridgeResult.calendarWriteMarker
        } else {
          retainedScheduleCalendarBridgeDecisionsByTaskID[taskID] =
            result.calendarBridgeDecision
          retainedScheduleCalendarBridgeWriteMarkersByTaskID[taskID] = nil
        }
        refreshCalendarOverlay(force: true)

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
        appState.errorMessage = error.localizedDescription
      }
    }
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
    if let timeMinutes = preview.timeMinutes {
      let requestedDuration = max(
        timedMinimumDuration,
        WorkspaceTaskScheduleEventStore.normalizedScheduledDurationMinutes(for: taskDescriptor.taskRow)
          ?? timedMinimumDuration
      )
      durationMinutes = ScheduleDragDropInteractionLayer.clampedDuration(
        requestedDuration,
        for: timeMinutes,
        metrics: interactionMetrics
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
    durationMinutes: Int?
  ) {
    guard allowScheduleMutation("create-task") else { return }
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
      return cached
    }
    return resolvedScheduleTaskSnapshot(preferCached: true).workspaceTasksByID[taskID]
  }

  func scheduleCompletionState(for taskRow: TaskRowSnapshot) -> ScheduleTaskCompletionState {
    ScheduleTaskCompletionState(
      isCompleted: taskRow.isCompleted,
      completionDate: taskRow.completionDate,
      isRecurring: WorkspaceTaskScheduleEventStore.isRecurring(taskRow),
      occurrenceDate: taskRow.reminderDate
    )
  }

  func updateScheduleTaskCompletion(
    taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    registerUndo: Bool
  ) {
    guard let taskDescriptor = scheduleTaskDescriptor(for: taskID) else { return }
    let previousState = scheduleCompletionState(for: taskDescriptor.taskRow)
    let nextState = ScheduleTaskCompletionState(
      isCompleted: isCompleted,
      completionDate: isCompleted ? (completionDate ?? .now) : nil,
      isRecurring: previousState.isRecurring,
      occurrenceDate: previousState.occurrenceDate
    )
    guard previousState != nextState else {
      return
    }
    Task { @MainActor in
      do {
        let result = try await RetainedTaskCommandService.setTaskCompletion(
          graphRootURL: appState.logseqGraphRootURL,
          projectID: projectID,
          taskID: taskID,
          isCompleted: nextState.isCompleted,
          completionDate: nextState.isCompleted && nextState.isRecurring
            ? (nextState.occurrenceDate ?? nextState.completionDate)
            : nextState.completionDate,
          reminderProjectProvider: appState.reminderProjectProvider
        )
        await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
        retainedScheduleCalendarBridgeDecisionsByTaskID[taskID] = result.calendarBridgeDecision
        retainedScheduleCalendarBridgeWriteMarkersByTaskID[taskID] = result.calendarWriteMarker

        guard registerUndo else { return }
        appState.registerUndo(
          with: undoManager,
          actionName: nextState.isCompleted ? "할일 완료" : "할일 완료 취소"
        ) {
          self.updateScheduleTaskCompletion(
            taskID: taskID,
            projectID: projectID,
            isCompleted: previousState.isCompleted,
            completionDate: previousState.completionDate,
            registerUndo: true
          )
        }
      } catch {
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
