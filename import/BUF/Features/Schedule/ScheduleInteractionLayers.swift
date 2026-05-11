import CoreGraphics
import Foundation

struct ScheduleInteractionPreview: Equatable, Sendable {
  let day: Date?
  let timeMinutes: Int?
  let durationMinutes: Int?
}

struct ScheduleInteractionMetrics {
  let dayColumnWidth: CGFloat
  let hourHeight: CGFloat
  let quarterHourHeight: CGFloat
  let timeGridHeight: CGFloat
  let timedMinimumDurationMinutes: Int
}

struct ScheduleExternalDropMetrics {
  let titleColumnWidth: CGFloat
  let headerHeight: CGFloat
  let dayColumnsWidth: CGFloat
  let scrollOffsetX: CGFloat
  let scrollOffsetY: CGFloat
}

enum ScheduleDragDropInteractionLayer {
  static func initialPointerViewportLocation(
    currentPointerViewportLocation: CGPoint?,
    translation: CGSize,
    originalViewportFrame: CGRect,
    gestureStartLocation: CGPoint
  ) -> CGPoint {
    if let currentPointerViewportLocation {
      return CGPoint(
        x: currentPointerViewportLocation.x - translation.width,
        y: currentPointerViewportLocation.y - translation.height
      )
    }

    if gestureStartLocation.x >= 0,
      gestureStartLocation.y >= 0,
      gestureStartLocation.x <= originalViewportFrame.width,
      gestureStartLocation.y <= originalViewportFrame.height
    {
      return CGPoint(
        x: originalViewportFrame.minX + gestureStartLocation.x,
        y: originalViewportFrame.minY + gestureStartLocation.y
      )
    }

    return gestureStartLocation
  }

  static func externalDropPreview(
    at location: CGPoint,
    days: [Date],
    externalMetrics: ScheduleExternalDropMetrics,
    interactionMetrics: ScheduleInteractionMetrics
  ) -> ScheduleInteractionPreview? {
    guard !days.isEmpty, location.y >= 0 else { return nil }

    guard
      let day = dayForPointerViewportX(
        location.x,
        titleColumnWidth: externalMetrics.titleColumnWidth,
        scrollOffsetX: externalMetrics.scrollOffsetX,
        days: days,
        metrics: interactionMetrics
      )
    else { return nil }

    if location.y < externalMetrics.headerHeight {
      return ScheduleInteractionPreview(day: day, timeMinutes: nil, durationMinutes: nil)
    }

    let scheduleY = location.y - externalMetrics.headerHeight + externalMetrics.scrollOffsetY
    let timeMinutes = snappedTimeMinutes(for: scheduleY, metrics: interactionMetrics)
    return ScheduleInteractionPreview(
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: interactionMetrics.timedMinimumDurationMinutes
    )
  }

  static func dayForPointerViewportX(
    _ pointerViewportX: CGFloat,
    titleColumnWidth: CGFloat,
    scrollOffsetX: CGFloat,
    days: [Date],
    metrics: ScheduleInteractionMetrics
  ) -> Date? {
    guard !days.isEmpty else { return nil }

    let scheduleX = pointerViewportX - titleColumnWidth + scrollOffsetX
    let dayColumnsWidth = CGFloat(days.count) * metrics.dayColumnWidth
    guard scheduleX >= 0, scheduleX < dayColumnsWidth else { return nil }

    let dayIndex = min(max(Int(scheduleX / metrics.dayColumnWidth), 0), days.count - 1)
    return days[dayIndex]
  }

  static func previewByApplyingPointerDay(
    _ preview: ScheduleInteractionPreview,
    pointerViewportLocation: CGPoint?,
    allowsDayChange: Bool,
    titleColumnWidth: CGFloat,
    scrollOffsetX: CGFloat,
    days: [Date],
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleInteractionPreview {
    guard allowsDayChange,
      let pointerViewportLocation,
      let day = dayForPointerViewportX(
        pointerViewportLocation.x,
        titleColumnWidth: titleColumnWidth,
        scrollOffsetX: scrollOffsetX,
        days: days,
        metrics: metrics
      )
    else {
      return preview
    }

    return ScheduleInteractionPreview(
      day: day,
      timeMinutes: preview.timeMinutes,
      durationMinutes: preview.durationMinutes
    )
  }

  static func allDayPreviewViewportY(
    pointerViewportY: CGFloat?,
    originalPointerViewportY: CGFloat,
    originalViewportMinY: CGFloat,
    translationHeight: CGFloat,
    dateHeaderHeight: CGFloat,
    allDayRailPadding: CGFloat,
    allDayRailVisibleHeight: CGFloat,
    previewHeight: CGFloat
  ) -> CGFloat {
    let pointerY = pointerViewportY ?? (originalPointerViewportY + translationHeight)
    let grabOffsetY = originalPointerViewportY - originalViewportMinY
    let projectedY = pointerY - grabOffsetY
    let minY = dateHeaderHeight + allDayRailPadding
    let maxY = dateHeaderHeight + max(allDayRailPadding, allDayRailVisibleHeight - previewHeight)
    return min(max(projectedY, minY), maxY)
  }

  static func dragGhostViewportFrame(
    resolvedDropFrame: CGRect?,
    originalViewportFrame: CGRect,
    translation: CGSize,
    currentPointerViewportLocation: CGPoint? = nil,
    originalPointerViewportX: CGFloat? = nil,
    originalPointerViewportY: CGFloat? = nil,
    allowsHorizontalMovement: Bool
  ) -> CGRect {
    _ = resolvedDropFrame
    if let currentPointerViewportLocation,
      let originalPointerViewportX,
      let originalPointerViewportY
    {
      let grabOffsetX = originalPointerViewportX - originalViewportFrame.minX
      let grabOffsetY = originalPointerViewportY - originalViewportFrame.minY
      return CGRect(
        x: allowsHorizontalMovement
          ? currentPointerViewportLocation.x - grabOffsetX
          : originalViewportFrame.minX,
        y: currentPointerViewportLocation.y - grabOffsetY,
        width: originalViewportFrame.width,
        height: originalViewportFrame.height
      )
    }

    return originalViewportFrame.offsetBy(
      dx: allowsHorizontalMovement ? translation.width : 0,
      dy: translation.height
    )
  }

  static func dragTopScheduleY(
    currentPointerScheduleY: CGFloat?,
    originalPointerScheduleY: CGFloat,
    originalTopScheduleY: CGFloat,
    fallbackTopScheduleY: CGFloat?
  ) -> CGFloat? {
    guard let currentPointerScheduleY else {
      return fallbackTopScheduleY
    }

    let grabOffsetY = originalPointerScheduleY - originalTopScheduleY
    return currentPointerScheduleY - grabOffsetY
  }

  static func preview(
    originalDay: Date,
    originalTimeMinutes: Int?,
    originalDurationMinutes: Int?,
    translation: CGSize,
    originalPointerScheduleY: CGFloat,
    originalTopScheduleY: CGFloat,
    currentPointerScheduleY: CGFloat? = nil,
    currentTopScheduleY: CGFloat? = nil,
    forceAllDay: Bool = false,
    allowsDayChange: Bool = true,
    allowsAllDay: Bool = true,
    targetDay: Date? = nil,
    metrics: ScheduleInteractionMetrics,
    calendar: Calendar = .autoupdatingCurrent
  ) -> ScheduleInteractionPreview {
    let dayDelta = allowsDayChange ? Int((translation.width / metrics.dayColumnWidth).rounded()) : 0
    let day =
      calendar.date(byAdding: .day, value: dayDelta, to: originalDay)
      ?? originalDay
    let visibleTargetDay = targetDay ?? day
    let pointerScheduleY = currentPointerScheduleY ?? (originalPointerScheduleY + translation.height)
    let topScheduleY = currentTopScheduleY ?? (originalTopScheduleY + translation.height)
    if allowsAllDay && forceAllDay {
      return ScheduleInteractionEngine.movePreview(
        originalTimeMinutes: originalTimeMinutes,
        originalDurationMinutes: originalDurationMinutes,
        target: .allDay(visibleTargetDay),
        metrics: metrics
      ) ?? ScheduleInteractionPreview(day: visibleTargetDay, timeMinutes: nil, durationMinutes: nil)
    }

    if originalTimeMinutes != nil {
      return ScheduleInteractionEngine.movePreview(
        originalTimeMinutes: originalTimeMinutes,
        originalDurationMinutes: originalDurationMinutes,
        target: ScheduleInteractionEngine.timedTarget(
          visibleDay: visibleTargetDay,
          scheduleY: topScheduleY,
          metrics: metrics,
          calendar: calendar
        ),
        metrics: metrics
      ) ?? ScheduleInteractionPreview(day: day, timeMinutes: originalTimeMinutes, durationMinutes: originalDurationMinutes)
    }

    let allDayOriginTimedY = max(0, pointerScheduleY)
    if pointerScheduleY >= 0 || topScheduleY >= 0 {
      return ScheduleInteractionEngine.movePreview(
        originalTimeMinutes: originalTimeMinutes,
        originalDurationMinutes: originalDurationMinutes,
        target: ScheduleInteractionEngine.timedTarget(
          visibleDay: visibleTargetDay,
          scheduleY: allDayOriginTimedY,
          metrics: metrics,
          calendar: calendar
        ),
        metrics: metrics
      ) ?? ScheduleInteractionPreview(
        day: visibleTargetDay,
        timeMinutes: nil,
        durationMinutes: nil
      )
    }

    return ScheduleInteractionPreview(day: visibleTargetDay, timeMinutes: nil, durationMinutes: nil)
  }

  static func snappedTimeMinutes(
    for scheduleY: CGFloat,
    metrics: ScheduleInteractionMetrics
  ) -> Int {
    let boundedY = max(0, min(metrics.timeGridHeight - metrics.quarterHourHeight, scheduleY))
    let quarterHours = Int((boundedY / metrics.quarterHourHeight).rounded())
    return max(0, min(23 * 60 + 45, quarterHours * 15))
  }

  static func snappedMinuteDelta(
    for translationHeight: CGFloat,
    metrics: ScheduleInteractionMetrics
  ) -> Int {
    Int((translationHeight / metrics.quarterHourHeight).rounded()) * 15
  }

  static func clampedDuration(
    _ durationMinutes: Int,
    for timeMinutes: Int,
    metrics: ScheduleInteractionMetrics
  ) -> Int {
    let remainingMinutes = max(metrics.timedMinimumDurationMinutes, (24 * 60) - timeMinutes)
    return max(metrics.timedMinimumDurationMinutes, min(durationMinutes, remainingMinutes))
  }
}

enum ScheduleTimeResizingInteractionLayer {
  static func preview(
    originalDay: Date,
    originalTimeMinutes: Int,
    originalDurationMinutes: Int,
    isStartEdge: Bool,
    originalPointerScheduleY: CGFloat,
    originalEdgeScheduleY: CGFloat,
    currentPointerScheduleY: CGFloat?,
    fallbackTranslationHeight: CGFloat,
    targetDay: Date? = nil,
    calendar: Calendar = .autoupdatingCurrent,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleInteractionPreview {
    let edgeScheduleY: CGFloat
    if let currentPointerScheduleY {
      edgeScheduleY = currentPointerScheduleY - (originalPointerScheduleY - originalEdgeScheduleY)
    } else {
      edgeScheduleY = originalEdgeScheduleY + fallbackTranslationHeight
    }

    return preview(
      originalDay: originalDay,
      originalTimeMinutes: originalTimeMinutes,
      originalDurationMinutes: originalDurationMinutes,
      isStartEdge: isStartEdge,
      edgeScheduleY: edgeScheduleY,
      targetDay: targetDay ?? originalDay,
      calendar: calendar,
      metrics: metrics
    )
  }

  static func preview(
    originalDay: Date,
    originalTimeMinutes: Int,
    originalDurationMinutes: Int,
    isStartEdge: Bool,
    translationHeight: CGFloat,
    targetDay: Date? = nil,
    calendar: Calendar = .autoupdatingCurrent,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleInteractionPreview {
    let edgeScheduleY: CGFloat
    if isStartEdge {
      edgeScheduleY = CGFloat(originalTimeMinutes) / 15 * metrics.quarterHourHeight + translationHeight
    } else {
      edgeScheduleY = CGFloat(originalTimeMinutes + originalDurationMinutes) / 15
        * metrics.quarterHourHeight + translationHeight
    }

    return preview(
      originalDay: originalDay,
      originalTimeMinutes: originalTimeMinutes,
      originalDurationMinutes: originalDurationMinutes,
      isStartEdge: isStartEdge,
      edgeScheduleY: edgeScheduleY,
      targetDay: targetDay ?? originalDay,
      calendar: calendar,
      metrics: metrics
    )
  }

  private static func preview(
    originalDay: Date,
    originalTimeMinutes: Int,
    originalDurationMinutes: Int,
    isStartEdge: Bool,
    edgeScheduleY: CGFloat,
    targetDay: Date,
    calendar: Calendar,
    metrics: ScheduleInteractionMetrics
  ) -> ScheduleInteractionPreview {
    ScheduleInteractionEngine.resizePreview(
      originalDay: originalDay,
      originalTimeMinutes: originalTimeMinutes,
      originalDurationMinutes: originalDurationMinutes,
      isStartEdge: isStartEdge,
      edgeScheduleY: edgeScheduleY,
      targetDay: targetDay,
      metrics: metrics,
      calendar: calendar
    )
  }

}
