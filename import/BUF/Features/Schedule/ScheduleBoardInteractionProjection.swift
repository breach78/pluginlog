import AppKit
import SwiftUI

extension ScheduleBoardView {
  func resizePreviewViewportFrame(
    for resizeState: ScheduleTaskResizeState,
    preview: ScheduleInteractionPreview
  ) -> CGRect {
    resizePreviewViewportFrame(
      originalDay: resizeState.originalDay,
      visibleDay: resizeState.visibleDay,
      originalViewportFrame: resizeState.originalViewportFrame,
      xOffsetWithinDay: resizeState.xOffsetWithinDay,
      preview: preview
    )
  }

  func resizePreviewViewportFrame(
    for resizeState: ScheduleCalendarResizeState,
    preview: ScheduleInteractionPreview
  ) -> CGRect {
    resizePreviewViewportFrame(
      originalDay: resizeState.originalDay,
      visibleDay: resizeState.visibleDay,
      originalViewportFrame: resizeState.originalViewportFrame,
      xOffsetWithinDay: resizeState.xOffsetWithinDay,
      preview: preview
    )
  }

  func resizePreviewViewportFrame(
    originalDay: Date,
    visibleDay: Date,
    originalViewportFrame: CGRect,
    xOffsetWithinDay: CGFloat,
    preview: ScheduleInteractionPreview
  ) -> CGRect {
    guard let timeMinutes = preview.timeMinutes else {
      return originalViewportFrame
    }
    let day = ScheduleInteractionViewportProjection.resizeDisplayDay(
      originalDay: originalDay,
      visibleDay: visibleDay,
      preview: preview,
      calendar: calendar
    )

    return ScheduleInteractionViewportProjection.resizeFrame(
      for: ScheduleInteractionPreview(
        day: preview.day,
        timeMinutes: timeMinutes,
        durationMinutes: preview.durationMinutes
      ),
      displayDay: day,
      sourceViewportFrame: originalViewportFrame,
      dayIndexByDate: dayIndexByDate,
      metrics: interactionViewportProjectionMetrics,
      xOffsetWithinDay: xOffsetWithinDay
    ) ?? originalViewportFrame
  }

  var interactionViewportProjectionMetrics: ScheduleInteractionViewportProjectionMetrics {
    ScheduleInteractionViewportProjectionMetrics(
      titleColumnWidth: titleColumnWidth,
      dayColumnWidth: dayColumnWidth,
      hourHeight: hourHeight,
      quarterHourHeight: quarterHourHeight,
      currentScrollOffsetX: currentScrollOffsetX,
      currentScrollOffsetY: currentScrollOffsetY,
      dateHeaderHeight: dateHeaderHeight,
      allDayRailPadding: allDayRailPadding,
      allDayRailVisibleHeight: allDayRailVisibleHeight,
      allDayRowHeight: allDayRowHeight,
      allDayChipHorizontalInset: allDayChipHorizontalInset,
      timedBlockInset: timedBlockInset,
      timedMinimumDurationMinutes: timedMinimumDuration
    )
  }

  func dragDropTargetViewportFrame(
    for dragState: ScheduleTaskDragState,
    preview: ScheduleInteractionPreview
  ) -> CGRect? {
    if isTaskDragOverExternalTarget || isTaskDragOutsideBoardBounds(dragState) {
      return nil
    }
    return dragDropTargetViewportFrame(
      for: preview,
      allDayViewportY: allDayPreviewViewportY(for: dragState, preview: preview)
    )
  }

  func dragDropTargetViewportFrame(
    for dragState: ScheduleCalendarDragState,
    preview: ScheduleInteractionPreview
  ) -> CGRect? {
    return dragDropTargetViewportFrame(
      for: preview,
      allDayViewportY: allDayPreviewViewportY(for: dragState, preview: preview)
    )
  }

  func dragDropTargetViewportFrame(
    for preview: ScheduleInteractionPreview,
    allDayViewportY: CGFloat? = nil
  ) -> CGRect? {
    SyncPerformanceCounter.measure(.dragFrameUpdate) {
      ScheduleInteractionViewportProjection.dragDropFrame(
        for: preview,
        dayIndexByDate: dayIndexByDate,
        metrics: interactionViewportProjectionMetrics,
        allDayViewportY: allDayViewportY
      )
    }
  }

  func allDayPreviewViewportY(
    for dragState: ScheduleTaskDragState,
    preview: ScheduleInteractionPreview
  ) -> CGFloat? {
    allDayPreviewViewportY(
      preview: preview,
      pointerViewportY: dragState.currentPointerViewportLocation?.y,
      originalPointerViewportY: dragState.originalPointerViewportY,
      originalViewportMinY: dragState.originalViewportFrame.minY,
      translationHeight: dragState.translation.height
    )
  }

  func allDayPreviewViewportY(
    for dragState: ScheduleCalendarDragState,
    preview: ScheduleInteractionPreview
  ) -> CGFloat? {
    allDayPreviewViewportY(
      preview: preview,
      pointerViewportY: dragState.currentPointerViewportLocation?.y,
      originalPointerViewportY: dragState.originalPointerViewportY,
      originalViewportMinY: dragState.originalViewportFrame.minY,
      translationHeight: dragState.translation.height
    )
  }

  func allDayPreviewViewportY(
    preview: ScheduleInteractionPreview,
    pointerViewportY: CGFloat?,
    originalPointerViewportY: CGFloat,
    originalViewportMinY: CGFloat,
    translationHeight: CGFloat
  ) -> CGFloat? {
    guard preview.timeMinutes == nil else { return nil }
    return ScheduleDragDropInteractionLayer.allDayPreviewViewportY(
      pointerViewportY: pointerViewportY,
      originalPointerViewportY: originalPointerViewportY,
      originalViewportMinY: originalViewportMinY,
      translationHeight: translationHeight,
      dateHeaderHeight: dateHeaderHeight,
      allDayRailPadding: allDayRailPadding,
      allDayRailVisibleHeight: allDayRailVisibleHeight,
      previewHeight: allDayRowHeight - 4
    )
  }

  func isTaskDragOutsideBoardBounds(_ dragState: ScheduleTaskDragState) -> Bool {
    guard let pointerX = dragState.currentPointerViewportLocation?.x else {
      return false
    }
    return pointerX < 0
  }

  func dragGhostViewportFrame(
    for dragState: ScheduleTaskDragState,
    dropFrame: CGRect?
  ) -> CGRect {
    ScheduleDragDropInteractionLayer.dragGhostViewportFrame(
      resolvedDropFrame: dropFrame,
      originalViewportFrame: dragState.originalViewportFrame,
      translation: dragState.translation,
      currentPointerViewportLocation: dragState.currentPointerViewportLocation,
      originalPointerViewportX: dragState.originalPointerViewportX,
      originalPointerViewportY: dragState.originalPointerViewportY,
      allowsHorizontalMovement: !dragState.isPreparationSlot
    )
  }

  func dragGhostViewportFrame(
    for dragState: ScheduleCalendarDragState,
    dropFrame: CGRect?
  ) -> CGRect {
    ScheduleDragDropInteractionLayer.dragGhostViewportFrame(
      resolvedDropFrame: dropFrame,
      originalViewportFrame: dragState.originalViewportFrame,
      translation: dragState.translation,
      currentPointerViewportLocation: dragState.currentPointerViewportLocation,
      originalPointerViewportX: dragState.originalPointerViewportX,
      originalPointerViewportY: dragState.originalPointerViewportY,
      allowsHorizontalMovement: true
    )
  }

  func taskDragTimeLabel(
    for dragState: ScheduleTaskDragState,
    preview: ScheduleInteractionPreview,
    dropFrame: CGRect?
  ) -> String? {
    guard dropFrame != nil else {
      return originalTaskDragTimeLabel(for: dragState)
    }
    return scheduleDragPreviewLabel(for: preview)
  }

  func calendarDragTimeLabel(
    for dragState: ScheduleCalendarDragState,
    preview: ScheduleInteractionPreview,
    dropFrame: CGRect?
  ) -> String? {
    guard dropFrame != nil else {
      return originalCalendarDragTimeLabel(for: dragState)
    }
    return scheduleDragPreviewLabel(for: preview)
  }

  func originalTaskDragTimeLabel(for dragState: ScheduleTaskDragState) -> String? {
    guard let startMinute = dragState.originalTimeMinutes else { return nil }
    let durationMinutes = dragState.originalDurationMinutes ?? timedMinimumDuration
    return timeRangeLabel(startMinute: startMinute, durationMinutes: durationMinutes)
  }

  func originalCalendarDragTimeLabel(for dragState: ScheduleCalendarDragState) -> String? {
    guard let startMinute = dragState.originalTimeMinutes else { return nil }
    let durationMinutes = dragState.originalDurationMinutes ?? timedMinimumDuration
    return timeRangeLabel(startMinute: startMinute, durationMinutes: durationMinutes)
  }

  func snappedAllDayDragPreviewFrame(dayIndex: Int, viewportY: CGFloat? = nil) -> CGRect {
    CGRect(
      x: titleColumnWidth + CGFloat(dayIndex) * dayColumnWidth - currentScrollOffsetX
        + allDayChipHorizontalInset,
      y: viewportY ?? dateHeaderHeight + allDayRailPadding,
      width: dayColumnWidth - allDayChipHorizontalInset * 2,
      height: allDayRowHeight - 4
    )
  }

  func snappedTimedDragPreviewFrame(
    dayIndex: Int,
    timeMinutes: Int,
    durationMinutes: Int
  ) -> CGRect {
    CGRect(
      x: titleColumnWidth + CGFloat(dayIndex) * dayColumnWidth - currentScrollOffsetX
        + timedBlockInset,
      y: headerHeight + CGFloat(timeMinutes) / 60 * hourHeight - currentScrollOffsetY,
      width: dayColumnWidth - timedBlockInset * 2,
      height: max(quarterHourHeight, CGFloat(durationMinutes) / 60 * hourHeight)
    )
  }

  func hourLabel(_ hour: Int) -> String {
    let normalizedHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    let suffix = hour < 12 ? "AM" : "PM"
    return "\(normalizedHour) \(suffix)"
  }
}
