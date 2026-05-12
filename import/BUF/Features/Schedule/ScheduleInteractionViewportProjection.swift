import CoreGraphics
import Foundation

struct ScheduleInteractionViewportProjectionMetrics: Equatable, Sendable {
  let titleColumnWidth: CGFloat
  let dayColumnWidth: CGFloat
  let hourHeight: CGFloat
  let quarterHourHeight: CGFloat
  let currentScrollOffsetX: CGFloat
  let currentScrollOffsetY: CGFloat
  let dateHeaderHeight: CGFloat
  let allDayRailPadding: CGFloat
  let allDayRailVisibleHeight: CGFloat
  let allDayRowHeight: CGFloat
  let allDayChipHorizontalInset: CGFloat
  let timedBlockInset: CGFloat
  let timedMinimumDurationMinutes: Int

  var headerHeight: CGFloat {
    dateHeaderHeight + allDayRailVisibleHeight
  }
}

enum ScheduleInteractionViewportProjection {
  static func dragDropFrame(
    for preview: ScheduleInteractionPreview,
    dayIndexByDate: [Date: Int],
    metrics: ScheduleInteractionViewportProjectionMetrics,
    allDayViewportY: CGFloat? = nil
  ) -> CGRect? {
    if preview.timeMinutes != nil {
      return timedFrame(
        for: preview,
        dayIndexByDate: dayIndexByDate,
        metrics: metrics,
        xOffsetWithinDay: metrics.timedBlockInset,
        width: metrics.dayColumnWidth - metrics.timedBlockInset * 2
      )
    }

    return allDayFrame(
      for: preview,
      dayIndexByDate: dayIndexByDate,
      metrics: metrics,
      viewportY: allDayViewportY
    )
  }

  static func timedFrame(
    for preview: ScheduleInteractionPreview,
    dayIndexByDate: [Date: Int],
    metrics: ScheduleInteractionViewportProjectionMetrics,
    xOffsetWithinDay: CGFloat,
    width: CGFloat
  ) -> CGRect? {
    guard let documentFrame = timedDocumentFrame(
      for: preview,
      dayIndexByDate: dayIndexByDate,
      metrics: metrics,
      xOffsetWithinDay: xOffsetWithinDay,
      width: width
    ) else {
      return nil
    }

    return CGRect(
      x: metrics.titleColumnWidth + documentFrame.minX - metrics.currentScrollOffsetX,
      y: metrics.headerHeight + documentFrame.minY - metrics.currentScrollOffsetY,
      width: documentFrame.width,
      height: documentFrame.height
    )
  }

  static func resizeFrame(
    for preview: ScheduleInteractionPreview,
    displayDay: Date,
    sourceViewportFrame: CGRect,
    dayIndexByDate: [Date: Int],
    metrics: ScheduleInteractionViewportProjectionMetrics,
    xOffsetWithinDay: CGFloat
  ) -> CGRect? {
    guard let timeMinutes = preview.timeMinutes else { return nil }
    guard
      let projectedFrame = timedFrame(
        for: ScheduleInteractionPreview(
          day: displayDay,
          timeMinutes: timeMinutes,
          durationMinutes: preview.durationMinutes
        ),
        dayIndexByDate: dayIndexByDate,
        metrics: metrics,
        xOffsetWithinDay: xOffsetWithinDay,
        width: sourceViewportFrame.width
      )
    else {
      return nil
    }

    return CGRect(
      x: sourceViewportFrame.minX,
      y: projectedFrame.minY,
      width: sourceViewportFrame.width,
      height: projectedFrame.height
    )
  }

  static func timedDocumentFrame(
    for preview: ScheduleInteractionPreview,
    dayIndexByDate: [Date: Int],
    metrics: ScheduleInteractionViewportProjectionMetrics,
    xOffsetWithinDay: CGFloat,
    width: CGFloat
  ) -> CGRect? {
    guard
      let day = preview.day,
      let dayIndex = dayIndexByDate[day],
      let timeMinutes = preview.timeMinutes
    else {
      return nil
    }

    let durationMinutes = preview.durationMinutes
      ?? metrics.timedMinimumDurationMinutes
    return CGRect(
      x: CGFloat(dayIndex) * metrics.dayColumnWidth + xOffsetWithinDay,
      y: CGFloat(timeMinutes) / 60 * metrics.hourHeight,
      width: width,
      height: max(metrics.quarterHourHeight, CGFloat(durationMinutes) / 60 * metrics.hourHeight)
    )
  }

  static func allDayFrame(
    for preview: ScheduleInteractionPreview,
    dayIndexByDate: [Date: Int],
    metrics: ScheduleInteractionViewportProjectionMetrics,
    viewportY: CGFloat? = nil
  ) -> CGRect? {
    guard let day = preview.day, let dayIndex = dayIndexByDate[day] else { return nil }
    return CGRect(
      x: metrics.titleColumnWidth
        + CGFloat(dayIndex) * metrics.dayColumnWidth
        - metrics.currentScrollOffsetX
        + metrics.allDayChipHorizontalInset,
      y: viewportY ?? metrics.dateHeaderHeight + metrics.allDayRailPadding,
      width: metrics.dayColumnWidth - metrics.allDayChipHorizontalInset * 2,
      height: metrics.allDayRowHeight - 4
    )
  }

  static func resizeDisplayDay(
    originalDay: Date,
    visibleDay: Date,
    preview: ScheduleInteractionPreview,
    calendar: Calendar
  ) -> Date {
    let previewDay = preview.day.map { calendar.startOfDay(for: $0) } ?? originalDay
    if !calendar.isDate(previewDay, inSameDayAs: originalDay) {
      return previewDay
    }
    return calendar.startOfDay(for: visibleDay)
  }
}
