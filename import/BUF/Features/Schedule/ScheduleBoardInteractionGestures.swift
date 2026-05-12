import AppKit
import SwiftUI

extension ScheduleBoardView {
  func preview(for dragState: ScheduleTaskDragState) -> ScheduleInteractionPreview {
    moveSession(for: dragState)?.preview ?? ScheduleInteractionPreview(
      day: dragState.originalDay,
      timeMinutes: dragState.originalTimeMinutes,
      durationMinutes: dragState.originalDurationMinutes
    )
  }

  func moveTarget(for dragState: ScheduleTaskDragState) -> ScheduleInteractionTarget {
    let currentPointerScheduleY = dragState.currentPointerViewportLocation.map {
      $0.y - headerHeight + currentScrollOffsetY
    }
    let currentTopScheduleY = ScheduleDragDropInteractionLayer.dragTopScheduleY(
      currentPointerScheduleY: currentPointerScheduleY,
      originalPointerScheduleY: dragState.originalPointerScheduleY,
      originalTopScheduleY: dragState.originalTopScheduleY,
      fallbackTopScheduleY: dragState.originalTimeMinutes == nil
        ? dragState.originalTopScheduleY + dragState.translation.height + currentScrollOffsetY
        : nil
    )

    let allowsDayChange = !dragState.isPreparationSlot
    let allowsTranslationDateSnap = allowsScheduleDragDateSnapping && allowsDayChange
    return ScheduleDragDropInteractionLayer.moveTarget(
      originalDay: dragState.originalDay,
      originalTimeMinutes: dragState.originalTimeMinutes,
      translation: dragState.translation,
      originalPointerScheduleY: dragState.originalPointerScheduleY,
      originalTopScheduleY: dragState.originalTopScheduleY,
      currentPointerScheduleY: currentPointerScheduleY,
      currentTopScheduleY: currentTopScheduleY,
      forceAllDay: dragState.isInAllDayZone,
      allowsDayChange: allowsTranslationDateSnap,
      allowsAllDay: true,
      targetDay: interactionTargetDay(
        pointerViewportLocation: dragState.currentPointerViewportLocation,
        allowsDayChange: allowsDayChange
      ),
      metrics: interactionMetrics,
      calendar: calendar
    )
  }

  func preview(for dragState: ScheduleCalendarDragState) -> ScheduleInteractionPreview {
    moveSession(for: dragState)?.preview ?? ScheduleInteractionPreview(
      day: dragState.originalDay,
      timeMinutes: dragState.originalTimeMinutes,
      durationMinutes: dragState.originalDurationMinutes
    )
  }

  func moveTarget(for dragState: ScheduleCalendarDragState) -> ScheduleInteractionTarget {
    let currentPointerScheduleY = dragState.currentPointerViewportLocation.map {
      $0.y - headerHeight + currentScrollOffsetY
    }
    let currentTopScheduleY = ScheduleDragDropInteractionLayer.dragTopScheduleY(
      currentPointerScheduleY: currentPointerScheduleY,
      originalPointerScheduleY: dragState.originalPointerScheduleY,
      originalTopScheduleY: dragState.originalTopScheduleY,
      fallbackTopScheduleY: dragState.originalTimeMinutes == nil
        ? dragState.originalTopScheduleY + dragState.translation.height + currentScrollOffsetY
        : nil
    )

    return ScheduleDragDropInteractionLayer.moveTarget(
      originalDay: dragState.originalDay,
      originalTimeMinutes: dragState.originalTimeMinutes,
      translation: dragState.translation,
      originalPointerScheduleY: dragState.originalPointerScheduleY,
      originalTopScheduleY: dragState.originalTopScheduleY,
      currentPointerScheduleY: currentPointerScheduleY,
      currentTopScheduleY: currentTopScheduleY,
      forceAllDay: dragState.isInAllDayZone,
      allowsDayChange: true,
      targetDay: interactionTargetDay(
        pointerViewportLocation: dragState.currentPointerViewportLocation,
        allowsDayChange: true
      ),
      metrics: interactionMetrics,
      calendar: calendar
    )
  }

  private func calendarDragDurationForTimedPreview(
    _ dragState: ScheduleCalendarDragState
  ) -> Int? {
    dragState.originalTimeMinutes == nil ? nil : dragState.originalDurationMinutes
  }

  func interactionTargetDay(
    pointerViewportLocation: CGPoint?,
    allowsDayChange: Bool
  ) -> Date? {
    guard allowsDayChange, let pointerViewportLocation else { return nil }
    return ScheduleDragDropInteractionLayer.dayForPointerViewportX(
      pointerViewportLocation.x,
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
    ScheduleDragDropInteractionLayer.pointerViewportLocation(
      originalPointerViewportX: dragState.originalPointerViewportX,
      originalPointerViewportY: dragState.originalPointerViewportY,
      translation: value.translation
    )
  }

  func resizePointerViewportLocation(
    originalViewportFrame: CGRect,
    edge: ScheduleResizeEdge,
    value: DragGesture.Value
  ) -> CGPoint {
    ScheduleDragDropInteractionLayer.resizePointerViewportLocation(
      originalViewportFrame: originalViewportFrame,
      edge: edge,
      translation: value.translation
    )
  }

  func resizeOriginalPointerScheduleY(
    currentPointerViewportLocation: CGPoint,
    value: DragGesture.Value
  ) -> CGFloat {
    currentPointerViewportLocation.y - value.translation.height - headerHeight + currentScrollOffsetY
  }

  func resizeCurrentPointerScheduleY(_ pointerViewportLocation: CGPoint?) -> CGFloat? {
    pointerViewportLocation.map { $0.y - headerHeight + currentScrollOffsetY }
  }

  func preview(for resizeState: ScheduleTaskResizeState) -> ScheduleInteractionPreview {
    resizeSession(for: resizeState)?.preview ?? ScheduleInteractionPreview(
      day: resizeState.originalDay,
      timeMinutes: resizeState.originalTimeMinutes,
      durationMinutes: resizeState.originalDurationMinutes
    )
  }

  func preview(for resizeState: ScheduleCalendarResizeState) -> ScheduleInteractionPreview {
    resizeSession(for: resizeState)?.preview ?? ScheduleInteractionPreview(
      day: resizeState.originalDay,
      timeMinutes: resizeState.originalTimeMinutes,
      durationMinutes: resizeState.originalDurationMinutes
    )
  }

  func resizeTarget(for resizeState: ScheduleTaskResizeState) -> ScheduleInteractionTarget {
    ScheduleTimeResizingInteractionLayer.resizeTarget(
      isStartEdge: resizeState.edge == .start,
      originalPointerScheduleY: resizeState.originalPointerScheduleY,
      originalEdgeScheduleY: resizeState.originalEdgeScheduleY,
      currentPointerScheduleY: resizeCurrentPointerScheduleY(
        resizeState.currentPointerViewportLocation
      ),
      fallbackTranslationHeight: resizeState.translationHeight,
      targetDay: interactionTargetDay(
        pointerViewportLocation: resizeState.currentPointerViewportLocation,
        allowsDayChange: true
      ) ?? resizeState.originalDay,
      calendar: calendar,
      metrics: interactionMetrics
    )
  }

  func resizeTarget(for resizeState: ScheduleCalendarResizeState) -> ScheduleInteractionTarget {
    ScheduleTimeResizingInteractionLayer.resizeTarget(
      isStartEdge: resizeState.edge == .start,
      originalPointerScheduleY: resizeState.originalPointerScheduleY,
      originalEdgeScheduleY: resizeState.originalEdgeScheduleY,
      currentPointerScheduleY: resizeCurrentPointerScheduleY(
        resizeState.currentPointerViewportLocation
      ),
      fallbackTranslationHeight: resizeState.translationHeight,
      targetDay: interactionTargetDay(
        pointerViewportLocation: resizeState.currentPointerViewportLocation,
        allowsDayChange: true
      ) ?? resizeState.originalDay,
      calendar: calendar,
      metrics: interactionMetrics
    )
  }

  func moveSession(for dragState: ScheduleTaskDragState) -> ScheduleInteractionSession? {
    ScheduleInteractionSession.move(
      identity: .task(dragState.taskID),
      originalTimeMinutes: dragState.originalTimeMinutes,
      originalDurationMinutes: dragState.originalDurationMinutes,
      target: moveTarget(for: dragState),
      metrics: interactionMetrics
    )
  }

  func moveSession(for dragState: ScheduleCalendarDragState) -> ScheduleInteractionSession? {
    ScheduleInteractionSession.move(
      identity: .calendarEvent(dragState.eventID),
      originalTimeMinutes: dragState.originalTimeMinutes,
      originalDurationMinutes: calendarDragDurationForTimedPreview(dragState),
      target: moveTarget(for: dragState),
      metrics: interactionMetrics
    )
  }

  func resizeSession(for resizeState: ScheduleTaskResizeState) -> ScheduleInteractionSession? {
    ScheduleInteractionSession.resize(
      identity: .task(resizeState.taskID),
      originalDay: resizeState.originalDay,
      originalTimeMinutes: resizeState.originalTimeMinutes,
      originalDurationMinutes: resizeState.originalDurationMinutes,
      isStartEdge: resizeState.edge == .start,
      target: resizeTarget(for: resizeState),
      metrics: interactionMetrics,
      calendar: calendar
    )
  }

  func resizeSession(for resizeState: ScheduleCalendarResizeState) -> ScheduleInteractionSession? {
    ScheduleInteractionSession.resize(
      identity: .calendarEvent(resizeState.eventID),
      originalDay: resizeState.originalDay,
      originalTimeMinutes: resizeState.originalTimeMinutes,
      originalDurationMinutes: resizeState.originalDurationMinutes,
      isStartEdge: resizeState.edge == .start,
      target: resizeTarget(for: resizeState),
      metrics: interactionMetrics,
      calendar: calendar
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
          let originalPointerViewportLocation = ScheduleDragDropInteractionLayer
            .initialPointerViewportLocation(
              currentPointerViewportLocation: scrollViewportState.pointerViewportLocation(),
              translation: value.translation,
              originalViewportFrame: originalViewportFrame,
              gestureStartLocation: value.startLocation
            )
          let originalPointerGrabOffsetY =
            originalPointerViewportLocation.y - originalViewportFrame.minY
          dragState = ScheduleTaskDragState(
            entryID: entryID,
            taskID: taskID,
            isPreparationSlot: isPreparationSlot,
            targetCompletedWorkUnits: targetCompletedWorkUnits,
            originalDay: originalDay,
            originalTimeMinutes: originalTimeMinutes,
            originalDurationMinutes: originalDurationMinutes,
            originalViewportFrame: originalViewportFrame,
            originalPointerViewportX: originalPointerViewportLocation.x,
            originalPointerViewportY: originalPointerViewportLocation.y,
            originalPointerScheduleY: originalScheduleY + originalPointerGrabOffsetY,
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
        let resolvedSession = moveSession(for: resolvedDragState)
        let resolvedPreview = resolvedSession?.preview ?? preview(for: resolvedDragState)
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
          guard let resolvedSession else { return }
          applyInteractionSession(
            resolvedSession,
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

    let resolvedPreview = preview(for: dragState)
    let dropFrame = dragDropTargetViewportFrame(for: dragState, preview: resolvedPreview)
    let rawFollowFrame = dragGhostViewportFrame(for: dragState, dropFrame: dropFrame)

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
          let originalPointerViewportLocation = ScheduleDragDropInteractionLayer
            .initialPointerViewportLocation(
              currentPointerViewportLocation: scrollViewportState.pointerViewportLocation(),
              translation: value.translation,
              originalViewportFrame: originalViewportFrame,
              gestureStartLocation: value.startLocation
            )
          let originalPointerGrabOffsetY =
            originalPointerViewportLocation.y - originalViewportFrame.minY
          dragState = ScheduleCalendarDragState(
            eventID: event.id,
            originalDay: calendar.startOfDay(for: event.startDate),
            originalTimeMinutes: event.isAllDay ? nil : timeMinutes(for: event.startDate),
            originalDurationMinutes: durationMinutes(for: event),
            originalViewportFrame: originalViewportFrame,
            originalPointerViewportX: originalPointerViewportLocation.x,
            originalPointerViewportY: originalPointerViewportLocation.y,
            originalPointerScheduleY: originalScheduleY + originalPointerGrabOffsetY,
            originalTopScheduleY: originalScheduleY
          )
        }

        suppressTaskTap()
        guard var dragState else { return }
        dragState.translation = value.translation
        let pointerViewportLocation = ScheduleDragDropInteractionLayer.pointerViewportLocation(
          originalPointerViewportX: dragState.originalPointerViewportX,
          originalPointerViewportY: dragState.originalPointerViewportY,
          translation: value.translation
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
        let pointerViewportLocation = ScheduleDragDropInteractionLayer.pointerViewportLocation(
          originalPointerViewportX: dragState.originalPointerViewportX,
          originalPointerViewportY: dragState.originalPointerViewportY,
          translation: value.translation
        )
        resolvedDragState.currentPointerViewportLocation = pointerViewportLocation
        resolvedDragState.isInAllDayZone = isPointerInAllDayZone(
          pointerViewportLocation: pointerViewportLocation,
          wasInAllDayZone: dragState.isInAllDayZone
        )
        guard let session = moveSession(for: resolvedDragState) else { return }
        commitCalendarSession(
          session,
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
    visibleDay: Date,
    xOffsetWithinDay: CGFloat,
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
          let pointerViewportLocation = resizePointerViewportLocation(
            originalViewportFrame: originalViewportFrame,
            edge: edge,
            value: value
          )
          let originalEdgeScheduleY = resizeOriginalPointerScheduleY(
            currentPointerViewportLocation: pointerViewportLocation,
            value: value
          )
          activeTaskResize = ScheduleTaskResizeState(
            entryID: entryID,
            taskID: taskID,
            isPreparationSlot: isPreparationSlot,
            targetCompletedWorkUnits: targetCompletedWorkUnits,
            originalDay: originalDay,
            visibleDay: visibleDay,
            originalTimeMinutes: originalTimeMinutes,
            originalDurationMinutes: originalDurationMinutes,
            edge: edge,
            originalViewportFrame: originalViewportFrame,
            xOffsetWithinDay: xOffsetWithinDay,
            originalPointerScheduleY: resizeOriginalPointerScheduleY(
              currentPointerViewportLocation: pointerViewportLocation,
              value: value
            ),
            originalEdgeScheduleY: originalEdgeScheduleY,
            currentPointerViewportLocation: pointerViewportLocation
          )
          selectedScheduleTaskID = taskID
        }
        suppressTaskTap()
        activeTaskResize?.currentPointerViewportLocation = resizePointerViewportLocation(
          originalViewportFrame: originalViewportFrame,
          edge: edge,
          value: value
        )
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
          guard let session = resizeSession(for: resizeState) else { return }
          applyInteractionSession(
            session,
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
    originalViewportFrame: CGRect,
    visibleDay: Date,
    xOffsetWithinDay: CGFloat
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
          let pointerViewportLocation = resizePointerViewportLocation(
            originalViewportFrame: originalViewportFrame,
            edge: edge,
            value: value
          )
          let originalEdgeScheduleY = resizeOriginalPointerScheduleY(
            currentPointerViewportLocation: pointerViewportLocation,
            value: value
          )
          activeCalendarResize = ScheduleCalendarResizeState(
            eventID: event.id,
            originalDay: originalDay,
            visibleDay: visibleDay,
            originalTimeMinutes: originalTimeMinutes,
            originalDurationMinutes: originalDurationMinutes,
            edge: edge,
            originalViewportFrame: originalViewportFrame,
            xOffsetWithinDay: xOffsetWithinDay,
            originalPointerScheduleY: resizeOriginalPointerScheduleY(
              currentPointerViewportLocation: pointerViewportLocation,
              value: value
            ),
            originalEdgeScheduleY: originalEdgeScheduleY,
            currentPointerViewportLocation: pointerViewportLocation
          )
        }
        suppressTaskTap()
        activeCalendarResize?.currentPointerViewportLocation = resizePointerViewportLocation(
          originalViewportFrame: originalViewportFrame,
          edge: edge,
          value: value
        )
        activeCalendarResize?.translationHeight = value.translation.height
      }
      .onEnded { _ in
        guard let resizeState = activeCalendarResize, resizeState.eventID == event.id else { return }
        suppressTaskTap()
        activeCalendarResize = nil
        guard let session = resizeSession(for: resizeState) else { return }
        commitCalendarSession(
          session,
          for: event,
          actionName: "캘린더 일정 길이 조절"
        )
      }
  }
}
