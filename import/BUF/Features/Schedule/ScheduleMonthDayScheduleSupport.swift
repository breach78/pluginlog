import CoreGraphics
import Foundation
import AppKit
import SwiftUI

struct ScheduleMonthDayTimedInterval {
  let item: ScheduleMonthItem
  let startMinute: Int
  let durationMinutes: Int
  let sourceStartDay: Date
  let sourceStartMinute: Int
  let sourceDurationMinutes: Int
  let isFirstSegment: Bool
  let isLastSegment: Bool

  var endMinute: Int {
    startMinute + durationMinutes
  }
}

struct ScheduleMonthDayTimedItemLayout: Identifiable {
  let item: ScheduleMonthItem
  let startMinute: Int
  let durationMinutes: Int
  let sourceStartDay: Date
  let sourceStartMinute: Int
  let sourceDurationMinutes: Int
  let isFirstSegment: Bool
  let isLastSegment: Bool
  let column: Int
  let columnCount: Int
  let containerWidth: CGFloat
  let hourHeight: CGFloat

  var id: String { item.id }

  var x: CGFloat {
    let columnWidth = containerWidth / CGFloat(max(1, columnCount))
    return CGFloat(column) * columnWidth + 6
  }

  var y: CGFloat {
    CGFloat(startMinute) / 60 * hourHeight
  }

  var height: CGFloat {
    max(28, CGFloat(durationMinutes) / 60 * hourHeight)
  }

  var width: CGFloat {
    max(42, containerWidth / CGFloat(max(1, columnCount)) - 12)
  }
}

enum ScheduleMonthDayTimedLayoutBuilder {
  static func layouts(
    intervals: [ScheduleMonthDayTimedInterval],
    width: CGFloat,
    hourHeight: CGFloat
  ) -> [ScheduleMonthDayTimedItemLayout] {
    let sorted = intervals.sorted {
      if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
      if $0.durationMinutes != $1.durationMinutes { return $0.durationMinutes > $1.durationMinutes }
      return $0.item.title < $1.item.title
    }
    var groups: [[ScheduleMonthDayTimedInterval]] = []
    var current: [ScheduleMonthDayTimedInterval] = []
    var currentEnd = 0

    for interval in sorted {
      if current.isEmpty || interval.startMinute < currentEnd {
        current.append(interval)
        currentEnd = max(currentEnd, interval.endMinute)
      } else {
        groups.append(current)
        current = [interval]
        currentEnd = interval.endMinute
      }
    }
    if !current.isEmpty {
      groups.append(current)
    }

    return groups.flatMap { group in
      layouts(forGroup: group, width: width, hourHeight: hourHeight)
    }
  }

  private static func layouts(
    forGroup group: [ScheduleMonthDayTimedInterval],
    width: CGFloat,
    hourHeight: CGFloat
  ) -> [ScheduleMonthDayTimedItemLayout] {
    var active: [(column: Int, endMinute: Int)] = []
    var assigned: [(interval: ScheduleMonthDayTimedInterval, column: Int)] = []
    var maxColumn = 0

    for interval in group {
      active.removeAll { $0.endMinute <= interval.startMinute }
      let usedColumns = Set(active.map(\.column))
      var column = 0
      while usedColumns.contains(column) {
        column += 1
      }
      active.append((column, interval.endMinute))
      maxColumn = max(maxColumn, column)
      assigned.append((interval, column))
    }

    let columnCount = maxColumn + 1
    return assigned.map { entry in
      ScheduleMonthDayTimedItemLayout(
        item: entry.interval.item,
        startMinute: entry.interval.startMinute,
        durationMinutes: entry.interval.durationMinutes,
        sourceStartDay: entry.interval.sourceStartDay,
        sourceStartMinute: entry.interval.sourceStartMinute,
        sourceDurationMinutes: entry.interval.sourceDurationMinutes,
        isFirstSegment: entry.interval.isFirstSegment,
        isLastSegment: entry.interval.isLastSegment,
        column: entry.column,
        columnCount: columnCount,
        containerWidth: width,
        hourHeight: hourHeight
      )
    }
  }
}

struct ScheduleMonthDayScheduleMutationPreview: Equatable {
  let itemID: String
  let day: Date
  let timeMinutes: Int?
  let durationMinutes: Int?

  var interactionPreview: ScheduleInteractionPreview {
    ScheduleInteractionPreview(
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )
  }
}

struct ScheduleMonthDayScheduleCreatePreview: Equatable {
  let timeMinutes: Int
  let durationMinutes: Int
}

struct ScheduleMonthDayItemDragState: Equatable {
  let itemID: String
  let originalItem: ScheduleMonthItem
  let originalTimeMinutes: Int?
  let originalDurationMinutes: Int?
  let originalPointerScheduleY: CGFloat
  let originalTopScheduleY: CGFloat
  let originalX: CGFloat?
  let originalWidth: CGFloat?
  let allDayBoundaryYInPanel: CGFloat
  var timeContentMinYInPanel: CGFloat
  var translation: CGSize = .zero
  var currentPointerPanelY: CGFloat?
  var isInAllDayZone: Bool
}

struct ScheduleMonthDayItemResizeState: Equatable {
  let itemID: String
  let originalItem: ScheduleMonthItem
  let originalTimeMinutes: Int
  let originalDurationMinutes: Int
  let originalPointerScheduleY: CGFloat
  let originalEdgeScheduleY: CGFloat
  let originalX: CGFloat
  let originalWidth: CGFloat
  let timeContentMinYInPanel: CGFloat
  let edge: ScheduleResizeEdge
}

struct ScheduleScreenFrameReporter: NSViewRepresentable {
  let onFrameChange: (CGRect) -> Void

  func makeNSView(context: Context) -> FrameView {
    let view = FrameView(frame: .zero)
    view.onFrameChange = onFrameChange
    return view
  }

  func updateNSView(_ view: FrameView, context: Context) {
    view.onFrameChange = onFrameChange
    view.scheduleReport()
  }

  final class FrameView: NSView {
    var onFrameChange: ((CGRect) -> Void)?
    private var lastReportedFrame: CGRect = .null
    private weak var observedClipView: NSClipView?

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      updateScrollObserver()
      scheduleReport()
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      updateScrollObserver()
      scheduleReport()
    }

    override func layout() {
      super.layout()
      updateScrollObserver()
      scheduleReport()
    }

    override func viewDidChangeBackingProperties() {
      super.viewDidChangeBackingProperties()
      scheduleReport()
    }

    func scheduleReport() {
      DispatchQueue.main.async { [weak self] in
        self?.report()
      }
    }

    private func report() {
      guard let window else {
        reportFrame(.null)
        return
      }
      let rectInWindow = convert(bounds, to: nil)
      reportFrame(window.convertToScreen(rectInWindow))
    }

    private func reportFrame(_ frame: CGRect) {
      guard frame != lastReportedFrame else { return }
      lastReportedFrame = frame
      onFrameChange?(frame)
    }

    private func updateScrollObserver() {
      let clipView = enclosingScrollView?.contentView
      guard clipView !== observedClipView else { return }
      removeScrollObserver()
      observedClipView = clipView
      clipView?.postsBoundsChangedNotifications = true
      if let clipView {
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(scrollBoundsChanged),
          name: NSView.boundsDidChangeNotification,
          object: clipView
        )
      }
    }

    private func removeScrollObserver() {
      guard let observedClipView else { return }
      NotificationCenter.default.removeObserver(
        self,
        name: NSView.boundsDidChangeNotification,
        object: observedClipView
      )
      self.observedClipView = nil
    }

    @objc private func scrollBoundsChanged() {
      scheduleReport()
    }
  }
}

enum ScheduleMonthDayTimeFormatter {
  static func timeText(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "a h:mm"
    return formatter.string(from: date)
  }
}

func itemSortKey(_ item: ScheduleMonthItem, calendar: Calendar) -> String {
  let dayPrefix = item.isAllDay ? "0" : "1"
  let completionPrefix = item.isCompleted ? "1" : "0"
  let time = calendar.dateComponents([.hour, .minute], from: item.startDate)
  let minutes = (time.hour ?? 0) * 60 + (time.minute ?? 0)
  let sourcePrefix: String
  switch item.source {
  case .calendarEvent:
    sourcePrefix = item.isAllDay ? "0" : "1"
  case .workspaceTask:
    sourcePrefix = item.isAllDay ? "1" : "0"
  }
  return "\(dayPrefix)-\(completionPrefix)-\(sourcePrefix)-\(String(format: "%04d", minutes))-\(item.title)"
}

extension ScheduleInteractionPreview {
  func monthDayPreview(
    itemID: String,
    fallbackDay: Date
  ) -> ScheduleMonthDayScheduleMutationPreview {
    ScheduleMonthDayScheduleMutationPreview(
      itemID: itemID,
      day: day ?? fallbackDay,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )
  }
}

extension ScheduleMonthItem {
  func applyingSchedulePreview(
    _ preview: ScheduleMonthDayScheduleMutationPreview,
    calendar: Calendar
  ) -> ScheduleMonthItem {
    replacing(
      startDate: startDate(for: preview, calendar: calendar),
      endDate: endDate(for: preview, calendar: calendar),
      isAllDay: preview.timeMinutes == nil
    )
  }

  func replacing(
    startDate: Date? = nil,
    endDate: Date? = nil,
    isAllDay: Bool? = nil,
    isCompleted: Bool? = nil,
    calendarEvent: ScheduleCalendarEvent? = nil
  ) -> ScheduleMonthItem {
    ScheduleMonthItem(
      id: id,
      source: source,
      title: title,
      subtitle: subtitle,
      startDate: startDate ?? self.startDate,
      endDate: endDate ?? self.endDate,
      isAllDay: isAllDay ?? self.isAllDay,
      colorHex: colorHex,
      isCompleted: isCompleted ?? self.isCompleted,
      isPreparationSlot: isPreparationSlot,
      isBackgroundCalendar: isBackgroundCalendar,
      calendarEvent: calendarEvent ?? self.calendarEvent
    )
  }

  private func startDate(
    for preview: ScheduleMonthDayScheduleMutationPreview,
    calendar: Calendar
  ) -> Date {
    guard let timeMinutes = preview.timeMinutes else {
      return calendar.startOfDay(for: preview.day)
    }
    return calendar.date(
      byAdding: .minute,
      value: timeMinutes,
      to: calendar.startOfDay(for: preview.day)
    ) ?? calendar.startOfDay(for: preview.day)
  }

  private func endDate(
    for preview: ScheduleMonthDayScheduleMutationPreview,
    calendar: Calendar
  ) -> Date {
    let start = startDate(for: preview, calendar: calendar)
    guard preview.timeMinutes != nil else {
      return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: preview.day)) ?? start
    }
    let duration = max(5, preview.durationMinutes ?? 30)
    return calendar.date(byAdding: .minute, value: duration, to: start) ?? start
  }
}
