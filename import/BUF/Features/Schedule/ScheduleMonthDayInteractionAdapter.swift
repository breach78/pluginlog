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
    if state.isInAllDayZone {
      return (
        ScheduleInteractionEngine.movePreview(
          originalTimeMinutes: state.originalTimeMinutes,
          originalDurationMinutes: state.originalDurationMinutes,
          target: .allDay(targetDay),
          metrics: metrics
        ) ?? ScheduleInteractionPreview(day: targetDay, timeMinutes: nil, durationMinutes: nil)
      ).monthDayPreview(itemID: state.itemID, fallbackDay: targetDay)
    }

    let currentPointerScheduleY = currentPointerScheduleY(for: state)
    let projectedTopY = currentPointerScheduleY - (state.originalPointerScheduleY - state.originalTopScheduleY)
    let preview = ScheduleInteractionEngine.movePreview(
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      target: ScheduleInteractionEngine.timedTarget(
        visibleDay: targetDay,
        scheduleY: projectedTopY,
        metrics: metrics,
        calendar: calendar
      ),
      metrics: metrics
    ) ?? ScheduleInteractionPreview(day: targetDay, timeMinutes: nil, durationMinutes: nil)
    return preview.monthDayPreview(itemID: state.itemID, fallbackDay: targetDay)
  }

  static func resizePreview(
    for state: ScheduleMonthDayItemResizeState,
    currentPointerPanelY: CGFloat,
    targetDay: Date,
    calendar: Calendar,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleMonthDayScheduleMutationPreview {
    let currentPointerScheduleY = currentPointerPanelY - state.timeContentMinYInPanel
    let edgeY = currentPointerScheduleY - (state.originalPointerScheduleY - state.originalEdgeScheduleY)
    let preview = ScheduleInteractionEngine.resizePreview(
      originalDay: calendar.startOfDay(for: state.originalItem.startDate),
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      isStartEdge: state.edge == .start,
      edgeScheduleY: edgeY,
      targetDay: targetDay,
      metrics: metrics,
      calendar: calendar
    )
    return preview.monthDayPreview(itemID: state.itemID, fallbackDay: targetDay)
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
