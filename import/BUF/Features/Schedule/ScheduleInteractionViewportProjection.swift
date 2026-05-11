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
      x: metrics.titleColumnWidth
        + CGFloat(dayIndex) * metrics.dayColumnWidth
        - metrics.currentScrollOffsetX
        + xOffsetWithinDay,
      y: metrics.headerHeight
        + CGFloat(timeMinutes) / 60 * metrics.hourHeight
        - metrics.currentScrollOffsetY,
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

  static func xOffsetWithinDay(
    for frame: CGRect,
    day: Date,
    dayIndexByDate: [Date: Int],
    metrics: ScheduleInteractionViewportProjectionMetrics
  ) -> CGFloat? {
    guard let dayIndex = dayIndexByDate[day] else { return nil }
    let dayViewportMinX = metrics.titleColumnWidth
      + CGFloat(dayIndex) * metrics.dayColumnWidth
      - metrics.currentScrollOffsetX
    return frame.minX - dayViewportMinX
  }
}
