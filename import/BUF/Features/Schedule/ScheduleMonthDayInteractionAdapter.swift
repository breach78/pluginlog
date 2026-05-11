import CoreGraphics
import Foundation

enum ScheduleMonthDayInteractionAdapter {
  private static let externalDropMinimumHorizontalDistance: CGFloat = 24
  private static let externalDropLeftEscapeSlop: CGFloat = 8

  static func metrics(
    hourHeight: CGFloat,
    minimumDurationMinutes: Int
  ) -> ScheduleInteractionMetrics {
    ScheduleInteractionMetrics(
      dayColumnWidth: 1,
      hourHeight: hourHeight,
      quarterHourHeight: hourHeight / 4,
      timeGridHeight: hourHeight * 24,
      timedMinimumDurationMinutes: minimumDurationMinutes
    )
  }

  static func updatedDragState(
    _ state: ScheduleMonthDayItemDragState,
    drag: DragGestureProxy,
    allDayRowHeight: CGFloat,
    timeContentMinYInPanel: CGFloat
  ) -> ScheduleMonthDayItemDragState {
    var next = state
    next.timeContentMinYInPanel = timeContentMinYInPanel
    next.translation = drag.translation
    next.currentPointerPanelY = drag.locationY
    next.isInAllDayZone = isPointerInAllDayZone(
      pointerYInPanel: drag.locationY,
      boundaryYInPanel: state.allDayBoundaryYInPanel,
      wasInAllDayZone: state.isInAllDayZone,
      rowHeight: allDayRowHeight
    )
    return next
  }

  static func movePreview(
    for state: ScheduleMonthDayItemDragState,
    targetDay: Date,
    calendar: Calendar,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleMonthDayScheduleMutationPreview {
    let target = moveTarget(
      for: state,
      targetDay: targetDay,
      calendar: calendar,
      metrics: metrics
    )
    return (
      ScheduleInteractionEngine.movePreview(
        originalTimeMinutes: state.originalTimeMinutes,
        originalDurationMinutes: state.originalDurationMinutes,
        target: target,
        metrics: metrics
      ) ?? ScheduleInteractionPreview(day: targetDay, timeMinutes: nil, durationMinutes: nil)
    ).monthDayPreview(itemID: state.itemID, fallbackDay: targetDay)
  }

  static func moveTarget(
    for state: ScheduleMonthDayItemDragState,
    targetDay: Date,
    calendar: Calendar,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleInteractionTarget {
    if state.isInAllDayZone {
      return .allDay(targetDay)
    }

    let currentPointerScheduleY = currentPointerScheduleY(for: state)
    let projectedTopY = currentPointerScheduleY - (state.originalPointerScheduleY - state.originalTopScheduleY)
    return ScheduleInteractionEngine.timedTarget(
      visibleDay: targetDay,
      scheduleY: projectedTopY,
      metrics: metrics,
      calendar: calendar
    )
  }

  static func externalMonthDropPreview(
    for state: ScheduleMonthDayItemDragState,
    targetDay: Date,
    calendar: Calendar,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleMonthDayScheduleMutationPreview {
    let target = externalMonthDropTarget(
      targetDay: targetDay,
      calendar: calendar
    )
    return (
      ScheduleInteractionEngine.movePreview(
        originalTimeMinutes: state.originalTimeMinutes,
        originalDurationMinutes: state.originalDurationMinutes,
        target: target,
        metrics: metrics
      ) ?? ScheduleInteractionPreview(day: targetDay, timeMinutes: nil, durationMinutes: nil)
    ).monthDayPreview(itemID: state.itemID, fallbackDay: targetDay)
  }

  static func externalMonthDropTarget(
    targetDay: Date,
    calendar: Calendar
  ) -> ScheduleInteractionTarget {
    ScheduleMonthDragSessionState.external(
      targetDay: targetDay,
      calendar: calendar
    ).target
  }

  static func resizePreview(
    for state: ScheduleMonthDayItemResizeState,
    currentPointerPanelY: CGFloat,
    targetDay: Date,
    calendar: Calendar,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleMonthDayScheduleMutationPreview {
    let target = resizeTarget(
      for: state,
      currentPointerPanelY: currentPointerPanelY,
      targetDay: targetDay,
      calendar: calendar,
      metrics: metrics
    )
    let preview = ScheduleInteractionEngine.resizePreview(
      originalDay: calendar.startOfDay(for: state.originalItem.startDate),
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      isStartEdge: state.edge == .start,
      target: target,
      metrics: metrics,
      calendar: calendar
    ) ?? ScheduleInteractionPreview(
      day: calendar.startOfDay(for: state.originalItem.startDate),
      timeMinutes: state.originalTimeMinutes,
      durationMinutes: state.originalDurationMinutes
    )
    return preview.monthDayPreview(itemID: state.itemID, fallbackDay: targetDay)
  }

  static func resizeTarget(
    for state: ScheduleMonthDayItemResizeState,
    currentPointerPanelY: CGFloat,
    targetDay: Date,
    calendar: Calendar,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleInteractionTarget {
    let currentPointerScheduleY = currentPointerPanelY - state.timeContentMinYInPanel
    return ScheduleTimeResizingInteractionLayer.resizeTarget(
      isStartEdge: state.edge == .start,
      originalPointerScheduleY: state.originalPointerScheduleY,
      originalEdgeScheduleY: state.originalEdgeScheduleY,
      currentPointerScheduleY: currentPointerScheduleY,
      fallbackTranslationHeight: 0,
      targetDay: targetDay,
      calendar: calendar,
      metrics: metrics
    )
  }

  static func snappedTimeMinutes(
    for scheduleY: CGFloat,
    metrics: ScheduleInteractionMetrics
  ) -> Int {
    ScheduleDragDropInteractionLayer.snappedTimeMinutes(for: scheduleY, metrics: metrics)
  }

  static func clampedDuration(
    _ durationMinutes: Int,
    startMinute: Int,
    metrics: ScheduleInteractionMetrics
  ) -> Int {
    ScheduleDragDropInteractionLayer.clampedDuration(
      durationMinutes,
      for: startMinute,
      metrics: metrics
    )
  }

  static func isPointerInAllDayZone(
    pointerYInPanel: CGFloat,
    boundaryYInPanel: CGFloat,
    wasInAllDayZone: Bool,
    rowHeight: CGFloat
  ) -> Bool {
    let releaseSlop = max(4, min(8, rowHeight * 0.35))
    let bottom = wasInAllDayZone ? boundaryYInPanel + releaseSlop : boundaryYInPanel
    return pointerYInPanel < bottom
  }

  static func isExternalMonthDropLocation(
    locationXInPanel: CGFloat,
    translation: CGSize
  ) -> Bool {
    translation.width <= -externalDropMinimumHorizontalDistance
      && locationXInPanel <= -externalDropLeftEscapeSlop
  }

  private static func currentPointerScheduleY(for state: ScheduleMonthDayItemDragState) -> CGFloat {
    if let currentPointerPanelY = state.currentPointerPanelY {
      return currentPointerPanelY - state.timeContentMinYInPanel
    }
    return state.originalPointerScheduleY + state.translation.height
  }

}

struct DragGestureProxy {
  let locationY: CGFloat
  let translation: CGSize
}
