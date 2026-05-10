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
      return ScheduleMonthDayScheduleMutationPreview(
        itemID: state.itemID,
        day: targetDay,
        timeMinutes: nil,
        durationMinutes: nil
      )
    }

    let currentPointerScheduleY = currentPointerScheduleY(for: state)
    let projectedTopY = currentPointerScheduleY - (state.originalPointerScheduleY - state.originalTopScheduleY)
    let durationMinutes = max(
      metrics.timedMinimumDurationMinutes,
      state.originalDurationMinutes ?? metrics.timedMinimumDurationMinutes,
    )
    let resolvedStart = resolvedDateAndMinute(
      relativeMinute: snappedRelativeMinutes(for: projectedTopY, metrics: metrics),
      targetDay: targetDay,
      calendar: calendar
    )
    return ScheduleMonthDayScheduleMutationPreview(
      itemID: state.itemID,
      day: resolvedStart.day,
      timeMinutes: resolvedStart.timeMinutes,
      durationMinutes: durationMinutes
    )
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
    let edgeMinute = snappedRelativeMinutes(for: edgeY, metrics: metrics)
    let originalStartMinute = relativeMinute(
      from: targetDay,
      to: state.originalItem.startDate,
      calendar: calendar
    )
    let originalEndMinute = originalStartMinute + state.originalDurationMinutes
    let preview: ScheduleInteractionPreview
    if state.edge == .start {
      let start = min(
        edgeMinute,
        originalEndMinute - metrics.timedMinimumDurationMinutes
      )
      let resolvedStart = resolvedDateAndMinute(
        relativeMinute: start,
        targetDay: targetDay,
        calendar: calendar
      )
      preview = ScheduleInteractionPreview(
        day: resolvedStart.day,
        timeMinutes: resolvedStart.timeMinutes,
        durationMinutes: originalEndMinute - start
      )
    } else {
      let end = max(originalStartMinute + metrics.timedMinimumDurationMinutes, edgeMinute)
      let resolvedStart = resolvedDateAndMinute(
        relativeMinute: originalStartMinute,
        targetDay: targetDay,
        calendar: calendar
      )
      preview = ScheduleInteractionPreview(
        day: resolvedStart.day,
        timeMinutes: resolvedStart.timeMinutes,
        durationMinutes: end - originalStartMinute
      )
    }
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

  private static func snappedRelativeMinutes(
    for scheduleY: CGFloat,
    metrics: ScheduleInteractionMetrics
  ) -> Int {
    Int((scheduleY / metrics.quarterHourHeight).rounded()) * 15
  }

  private static func relativeMinute(
    from day: Date,
    to date: Date,
    calendar: Calendar
  ) -> Int {
    calendar.dateComponents([.minute], from: calendar.startOfDay(for: day), to: date).minute ?? 0
  }

  private static func resolvedDateAndMinute(
    relativeMinute: Int,
    targetDay: Date,
    calendar: Calendar
  ) -> (day: Date, timeMinutes: Int) {
    let date = calendar.date(
      byAdding: .minute,
      value: relativeMinute,
      to: calendar.startOfDay(for: targetDay)
    ) ?? targetDay
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (
      calendar.startOfDay(for: date),
      (components.hour ?? 0) * 60 + (components.minute ?? 0)
    )
  }
}

struct DragGestureProxy {
  let locationY: CGFloat
  let translation: CGSize
}
