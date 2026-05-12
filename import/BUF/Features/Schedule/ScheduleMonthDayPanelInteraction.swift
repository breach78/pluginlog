import AppKit
import SwiftUI

extension ScheduleMonthDaySchedulePanel {
  func interactionIdentity(for item: ScheduleMonthItem) -> ScheduleInteractionItemIdentity? {
    switch item.source {
    case .workspaceTask(let taskID, _):
      return .task(taskID)
    case .calendarEvent(let eventID):
      return .calendarEvent(eventID)
    }
  }

  func updateMovePreview(
    for item: ScheduleMonthItem,
    drag: DragGesture.Value,
    originalTopScheduleY: CGFloat?,
    originalX: CGFloat?,
    originalWidth: CGFloat?
  ) {
    guard canUpdateSchedule(for: item) else { return }
    guard resizeBlockedMoveItemID != item.id, activeItemResizeState == nil else { return }
    onExternalMonthDragActiveChanged(true)
    let state = updatedDragState(
      for: item,
      drag: drag,
      originalTopScheduleY: originalTopScheduleY,
      originalX: originalX,
      originalWidth: originalWidth
    )
    let externalDrop = externalMonthDropContext(for: drag)
    if externalDrop.isExternal {
      activeMutationPreview = nil
      onExternalMonthDragTargetChanged(externalDrop.day)
      updateMoveCursor(isExternalDrop: true, externalDropDay: externalDrop.day)
      return
    }
    onExternalMonthDragTargetChanged(nil)
    updateMoveCursor(isExternalDrop: false, externalDropDay: nil)
    activeMutationPreview = moveMutationPreview(for: state)
  }

  func finishMovePreview(
    for item: ScheduleMonthItem,
    drag: DragGesture.Value,
    originalTopScheduleY: CGFloat?,
    originalX: CGFloat?,
    originalWidth: CGFloat?
  ) {
    guard canUpdateSchedule(for: item) else { return }
    defer { onExternalMonthDragActiveChanged(false) }
    guard resizeBlockedMoveItemID != item.id, activeItemResizeState == nil else {
      if resizeBlockedMoveItemID == item.id {
        resizeBlockedMoveItemID = nil
      }
      return
    }
    let state = updatedDragState(
      for: item,
      drag: drag,
      originalTopScheduleY: originalTopScheduleY,
      originalX: originalX,
      originalWidth: originalWidth
    )
    defer { NSCursor.arrow.set() }
    let externalDrop = externalMonthDropContext(for: drag)
    if externalDrop.isExternal {
      defer { onExternalMonthDragTargetChanged(nil) }
      guard let targetDay = externalDrop.day else {
        activeMutationPreview = nil
        activeItemDragState = nil
        return
      }
      guard let session = externalMonthDropSession(for: state, targetDay: targetDay) else {
        activeMutationPreview = nil
        activeItemDragState = nil
        return
      }
      commitMutationSession(session, item: state.originalItem, itemID: state.itemID)
      return
    }
    onExternalMonthDragTargetChanged(nil)
    guard let session = moveSession(for: state) else { return }
    commitMutationSession(session, item: state.originalItem, itemID: state.itemID)
  }

  func updateResizePreview(
    for layout: ScheduleMonthDayTimedItemLayout,
    edge: ScheduleResizeEdge,
    drag: DragGesture.Value
  ) {
    let item = layout.item
    guard canResizeSchedule(for: item) else { return }
    let state = resizeState(for: layout, edge: edge, drag: drag)
    activeMutationPreview = resizeMutationPreview(for: state, currentPointerPanelY: drag.location.y)
  }

  func finishResizePreview(
    for layout: ScheduleMonthDayTimedItemLayout,
    edge: ScheduleResizeEdge,
    drag: DragGesture.Value
  ) {
    let item = layout.item
    guard canResizeSchedule(for: item) else { return }
    let state = resizeState(for: layout, edge: edge, drag: drag)
    guard let session = resizeSession(for: state, currentPointerPanelY: drag.location.y) else { return }
    let blockedItemID = state.itemID
    commitMutationSession(session, item: state.originalItem, itemID: state.itemID)
    DispatchQueue.main.async {
      if resizeBlockedMoveItemID == blockedItemID {
        resizeBlockedMoveItemID = nil
      }
    }
  }

  func updatedDragState(
    for item: ScheduleMonthItem,
    drag: DragGesture.Value,
    originalTopScheduleY: CGFloat?,
    originalX: CGFloat?,
    originalWidth: CGFloat?
  ) -> ScheduleMonthDayItemDragState {
    let state: ScheduleMonthDayItemDragState
    if let activeItemDragState, activeItemDragState.itemID == item.id {
      state = activeItemDragState
    } else {
      let originalPointerScheduleY = drag.startLocation.y - timeContentMinYInPanel
      state = ScheduleMonthDayItemDragState(
        itemID: item.id,
        originalItem: item,
        originalTimeMinutes: item.isAllDay ? nil : startMinute(for: item),
        originalDurationMinutes: item.isAllDay ? nil : durationMinutes(for: item),
        originalPointerScheduleY: originalPointerScheduleY,
        originalTopScheduleY: originalTopScheduleY ?? (originalPointerScheduleY - Self.allDayRowHeight / 2),
        originalX: originalX,
        originalWidth: originalWidth,
        allDayBoundaryYInPanel: allDaySectionHeight + Self.dividerHeight,
        timeContentMinYInPanel: timeContentMinYInPanel,
        isInAllDayZone: item.isAllDay
      )
      activeItemResizeState = nil
    }
    let next = ScheduleMonthDayInteractionAdapter.updatedDragState(
      state,
      drag: DragGestureProxy(
        locationY: drag.location.y,
        translation: drag.translation
      ),
      allDayRowHeight: Self.allDayRowHeight,
      timeContentMinYInPanel: timeContentMinYInPanel
    )
    activeItemDragState = next
    return next
  }

  func resizeState(
    for layout: ScheduleMonthDayTimedItemLayout,
    edge: ScheduleResizeEdge,
    drag: DragGesture.Value
  ) -> ScheduleMonthDayItemResizeState {
    let item = layout.item
    if let activeItemResizeState,
      activeItemResizeState.itemID == item.id,
      activeItemResizeState.edge == edge
    {
      return activeItemResizeState
    }

    let state = ScheduleMonthDayItemResizeState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: layout.sourceStartMinute,
      originalDurationMinutes: layout.sourceDurationMinutes,
      originalPointerScheduleY: drag.startLocation.y - timeContentMinYInPanel,
      originalEdgeScheduleY: edge == .start
        ? sourceTopScheduleY(for: layout)
        : sourceTopScheduleY(for: layout)
          + CGFloat(layout.sourceDurationMinutes) / 60 * Self.hourHeight,
      originalX: layout.x,
      originalWidth: layout.width,
      timeContentMinYInPanel: timeContentMinYInPanel,
      edge: edge
    )
    activeItemResizeState = state
    activeItemDragState = nil
    resizeBlockedMoveItemID = item.id
    return state
  }

  func createTask(
    title: String,
    projectID: UUID,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) {
    pendingCreatePreview = nil
    activeCreatePreview = nil
    Task { @MainActor in
      guard
        let created = await onCreateTask(
          title,
          projectID,
          calendar.startOfDay(for: target.date),
          timeMinutes,
          durationMinutes
        )
      else { return }
      replaceItem(created)
    }
  }

  func replaceItem(_ item: ScheduleMonthItem) {
    if let index = items.firstIndex(where: { $0.id == item.id }) {
      items[index] = item
    } else {
      items.append(item)
    }
    items = Self.sortedItems(items, calendar: calendar)
  }

  func replaceOrRemoveForCurrentDay(_ item: ScheduleMonthItem) {
    if itemBelongsToCurrentDay(item) {
      replaceItem(item)
    } else {
      removeItem(item.id)
    }
  }

  func removeItem(_ itemID: String) {
    items.removeAll { $0.id == itemID }
  }

  func itemBelongsToCurrentDay(_ item: ScheduleMonthItem) -> Bool {
    let day = calendar.startOfDay(for: target.date)
    if item.isAllDay {
      let start = calendar.startOfDay(for: item.startDate)
      let end = calendar.startOfDay(for: item.endDate)
      return start <= day && day < end
    }
    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
      return calendar.isDate(item.startDate, inSameDayAs: day)
    }
    return item.startDate < nextDay && item.endDate > day
  }

  func moveMutationPreview(
    for state: ScheduleMonthDayItemDragState
  ) -> ScheduleMonthDayScheduleMutationPreview? {
    moveSession(for: state)?.preview.monthDayPreview(
      itemID: state.itemID,
      fallbackDay: calendar.startOfDay(for: target.date)
    )
  }

  func moveSession(
    for state: ScheduleMonthDayItemDragState
  ) -> ScheduleInteractionSession? {
    guard let identity = interactionIdentity(for: state.originalItem) else { return nil }
    let targetDay = calendar.startOfDay(for: target.date)
    return ScheduleInteractionSession.move(
      identity: identity,
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      target: ScheduleMonthDayInteractionAdapter.moveTarget(
        for: state,
        targetDay: targetDay,
        calendar: calendar,
        metrics: interactionMetrics
      ),
      metrics: interactionMetrics
    )
  }

  func externalMonthDropSession(
    for state: ScheduleMonthDayItemDragState,
    targetDay: Date
  ) -> ScheduleInteractionSession? {
    guard let identity = interactionIdentity(for: state.originalItem) else { return nil }
    return ScheduleInteractionSession.move(
      identity: identity,
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      target: ScheduleMonthDayInteractionAdapter.externalMonthDropTarget(
        targetDay: targetDay,
        calendar: calendar
      ),
      metrics: interactionMetrics
    )
  }

  func externalMonthDropContext(for drag: DragGesture.Value) -> (
    isExternal: Bool,
    day: Date?
  ) {
    guard
      let screenPoint = ScheduleScreenPointMapper.screenPoint(
        localLocation: drag.location,
        in: panelFrameInScreen
      )
    else {
      return (false, nil)
    }
    let targetDay = externalMonthDropDay(at: screenPoint)
    let leftPanel = ScheduleMonthDayInteractionAdapter.isExternalMonthDropLocation(
      locationXInPanel: drag.location.x,
      translation: drag.translation
    )
    return (targetDay != nil || leftPanel, targetDay)
  }

  func externalMonthDropDay(at screenPoint: CGPoint) -> Date? {
    guard !panelFrameInScreen.isNull else { return nil }
    return resolveExternalMonthDropDay(screenPoint)
  }

  func updateMoveCursor(isExternalDrop: Bool, externalDropDay day: Date?) {
    if day != nil {
      NSCursor.dragCopy.set()
    } else if isExternalDrop {
      NSCursor.operationNotAllowed.set()
    } else if activeItemDragState != nil {
      NSCursor.closedHand.set()
    }
  }

  func resizeMutationPreview(
    for state: ScheduleMonthDayItemResizeState,
    currentPointerPanelY: CGFloat
  ) -> ScheduleMonthDayScheduleMutationPreview? {
    resizeSession(for: state, currentPointerPanelY: currentPointerPanelY)?.preview.monthDayPreview(
      itemID: state.itemID,
      fallbackDay: calendar.startOfDay(for: target.date)
    )
  }

  func resizeSession(
    for state: ScheduleMonthDayItemResizeState,
    currentPointerPanelY: CGFloat
  ) -> ScheduleInteractionSession? {
    guard let identity = interactionIdentity(for: state.originalItem) else { return nil }
    let targetDay = calendar.startOfDay(for: target.date)
    return ScheduleInteractionSession.resize(
      identity: identity,
      originalDay: calendar.startOfDay(for: state.originalItem.startDate),
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      isStartEdge: state.edge == .start,
      target: ScheduleMonthDayInteractionAdapter.resizeTarget(
        for: state,
        currentPointerPanelY: currentPointerPanelY,
        targetDay: targetDay,
        calendar: calendar,
        metrics: interactionMetrics
      ),
      metrics: interactionMetrics,
      calendar: calendar
    )
  }
}
