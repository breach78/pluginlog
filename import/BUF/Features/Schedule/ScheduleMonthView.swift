import AppKit
import SwiftUI

private enum ScheduleMonthLayoutMetrics {
  static let dayNumberHeight: CGFloat = 24
  static let dayCellTopPadding: CGFloat = 5
  static let dayCellHorizontalPadding: CGFloat = 6
  static let itemRowHeight: CGFloat = 18
  static let itemRowSpacing: CGFloat = 3
  static let allDaySpanHeight: CGFloat = 18
  static let allDaySpanRowHeight: CGFloat = 20
  static let allDaySpanTopOffset: CGFloat = dayCellTopPadding + dayNumberHeight + itemRowSpacing
}

struct ScheduleMonthView: View {
  @Binding var anchorDate: Date

  let today: Date
  let items: [ScheduleMonthItem]
  let selectedDate: Date?
  let calendar: Calendar
  let onSelectDay: (Date, [ScheduleMonthItem]) -> Void

  private let weekdayHeaderHeight: CGFloat = 28
  private let monthHeaderHeight: CGFloat = 58
  private let cellMinHeight: CGFloat = 72
  private let gridLineColor = Color.primary.opacity(0.10)

  var visibleDays: [Date] {
    ScheduleMonthCalendar.visibleDays(containing: anchorDate, calendar: calendar)
  }

  var monthStart: Date {
    ScheduleMonthCalendar.monthStart(containing: anchorDate, calendar: calendar)
  }

  var itemsByDay: [Date: [ScheduleMonthItem]] {
    ScheduleMonthCalendar.itemsByDay(
      items: items,
      visibleDays: visibleDays,
      calendar: calendar
    )
  }

  var body: some View {
    GeometryReader { proxy in
      let availableGridHeight = max(
        cellMinHeight * 6,
        proxy.size.height - monthHeaderHeight - weekdayHeaderHeight
      )
      let cellHeight = availableGridHeight / 6
      let visibleItemLimit = ScheduleMonthOverflowPolicy.visibleItemLimit(
        cellHeight: cellHeight
      )

      VStack(spacing: 0) {
        monthHeader
          .frame(height: monthHeaderHeight)

        weekdayHeader
          .frame(height: weekdayHeaderHeight)

        monthGrid(cellHeight: cellHeight, visibleItemLimit: visibleItemLimit)
          .frame(height: availableGridHeight)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Color(nsColor: .windowBackgroundColor))
      .background {
        ScheduleMonthScrollEventMonitor { monthDelta in
          moveMonth(by: monthDelta)
        }
      }
    }
  }

  private var monthHeader: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(monthTitle(for: monthStart))
        .font(.system(size: 32, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      Spacer(minLength: 0)

      HStack(spacing: 8) {
        Button {
          moveMonth(by: -1)
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 12, weight: .bold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help("이전 달")

        Button("오늘") {
          anchorDate = today
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Button {
          moveMonth(by: 1)
        } label: {
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help("다음 달")
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 4)
  }

  private var weekdayHeader: some View {
    HStack(spacing: 0) {
      ForEach(weekdaySymbols, id: \.self) { symbol in
        Text(symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(gridLineColor)
        .frame(height: 1)
    }
  }

  private func monthGrid(cellHeight: CGFloat, visibleItemLimit: Int) -> some View {
    VStack(spacing: 0) {
      ForEach(0..<6, id: \.self) { weekIndex in
        let weekDays = (0..<7).map { visibleDays[weekIndex * 7 + $0] }
        ScheduleMonthWeekRow(
          weekDays: weekDays,
          monthStart: monthStart,
          today: today,
          itemsByDay: itemsByDay,
          visibleItemLimit: visibleItemLimit,
          selectedDate: selectedDate,
          calendar: calendar,
          gridLineColor: gridLineColor,
          onSelectDay: select(day:)
        )
        .frame(height: cellHeight)
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(weekIndex == 5 ? Color.clear : gridLineColor)
            .frame(height: 1)
        }
      }
    }
  }

  private var weekdaySymbols: [String] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    let symbols = formatter.shortStandaloneWeekdaySymbols ?? ["일", "월", "화", "수", "목", "금", "토"]
    let first = max(0, min(calendar.firstWeekday - 1, symbols.count - 1))
    return Array(symbols[first..<symbols.count] + symbols[0..<first])
  }

  private func select(day: Date) {
    let normalizedDay = calendar.startOfDay(for: day)
    onSelectDay(normalizedDay, itemsByDay[normalizedDay] ?? [])
  }

  private func moveMonth(by value: Int) {
    if let next = calendar.date(byAdding: .month, value: value, to: anchorDate) {
      anchorDate = next
    }
  }

  private func monthTitle(for date: Date) -> String {
    let components = calendar.dateComponents([.year, .month], from: date)
    return "\(components.year ?? 0)년 \(components.month ?? 1)월"
  }
}

private struct ScheduleMonthWeekRow: View {
  let weekDays: [Date]
  let monthStart: Date
  let today: Date
  let itemsByDay: [Date: [ScheduleMonthItem]]
  let visibleItemLimit: Int
  let selectedDate: Date?
  let calendar: Calendar
  let gridLineColor: Color
  let onSelectDay: (Date) -> Void

  private var allDaySegments: [ScheduleMonthAllDaySpanSegment] {
    ScheduleMonthSpanLayout.allDayCalendarSegments(
      for: weekDays,
      items: weekItems,
      calendar: calendar
    )
  }

  private var visibleAllDaySegments: [ScheduleMonthAllDaySpanSegment] {
    allDaySegments.filter { $0.rowIndex < visibleAllDayRowLimit }
  }

  private var visibleAllDayRowLimit: Int {
    max(0, visibleItemLimit)
  }

  private var weekItems: [ScheduleMonthItem] {
    var seen: Set<String> = []
    var result: [ScheduleMonthItem] = []
    for day in weekDays {
      let normalized = calendar.startOfDay(for: day)
      for item in itemsByDay[normalized] ?? [] where seen.insert(item.id).inserted {
        result.append(item)
      }
    }
    return result
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      HStack(spacing: 0) {
        ForEach(0..<7, id: \.self) { dayIndex in
          let day = weekDays[dayIndex]
          let normalizedDay = calendar.startOfDay(for: day)
          let dayItems = itemsByDay[normalizedDay] ?? []

          ScheduleMonthDayCell(
            day: day,
            monthStart: monthStart,
            today: today,
            items: ScheduleMonthSpanLayout.inlineItems(from: dayItems),
            visibleItemLimit: inlineVisibleItemLimit(on: dayIndex),
            hiddenAllDayItemCount: hiddenAllDayItemCount(on: dayIndex),
            reservedAllDayRowCount: visibleAllDayRowCount(on: dayIndex),
            isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false,
            calendar: calendar,
            onSelect: {
              onSelectDay(day)
            }
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .overlay(alignment: .trailing) {
            Rectangle()
              .fill(dayIndex == 6 ? Color.clear : gridLineColor)
              .frame(width: 1)
          }
        }
      }

      GeometryReader { proxy in
        let columnWidth = proxy.size.width / 7
        ForEach(visibleAllDaySegments) { segment in
          let width = max(0, columnWidth * CGFloat(segment.daySpanCount) - 4)
          let x = columnWidth * CGFloat(segment.startDayIndex) + width / 2 + 2
          let y = ScheduleMonthLayoutMetrics.allDaySpanTopOffset
            + CGFloat(segment.rowIndex) * ScheduleMonthLayoutMetrics.allDaySpanRowHeight
            + ScheduleMonthLayoutMetrics.allDaySpanHeight / 2

          ScheduleMonthAllDaySpanRow(segment: segment)
            .frame(width: width, height: ScheduleMonthLayoutMetrics.allDaySpanHeight)
            .position(x: x, y: y)
        }
      }
      .allowsHitTesting(false)
    }
  }

  private func inlineVisibleItemLimit(on dayIndex: Int) -> Int {
    max(0, visibleItemLimit - visibleAllDayRowCount(on: dayIndex))
  }

  private func visibleAllDayRowCount(on dayIndex: Int) -> Int {
    ScheduleMonthSpanLayout.visibleAllDayRowCount(
      on: dayIndex,
      segments: allDaySegments,
      visibleRowLimit: visibleAllDayRowLimit
    )
  }

  private func hiddenAllDayItemCount(on dayIndex: Int) -> Int {
    ScheduleMonthSpanLayout.hiddenAllDayItemCount(
      on: dayIndex,
      segments: allDaySegments,
      visibleRowLimit: visibleAllDayRowLimit
    )
  }
}

private struct ScheduleMonthScrollEventMonitor: NSViewRepresentable {
  let onMonthScroll: (Int) -> Void

  func makeNSView(context: Context) -> ScheduleMonthScrollMonitorNSView {
    let view = ScheduleMonthScrollMonitorNSView()
    view.onMonthScroll = onMonthScroll
    return view
  }

  func updateNSView(_ nsView: ScheduleMonthScrollMonitorNSView, context: Context) {
    nsView.onMonthScroll = onMonthScroll
  }
}

private final class ScheduleMonthScrollMonitorNSView: NSView {
  var onMonthScroll: ((Int) -> Void)?

  private var eventMonitor: Any?
  private var accumulatedVerticalDelta: CGFloat = 0
  private var lastNavigationTimestamp: TimeInterval = 0

  override var isOpaque: Bool { false }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    refreshEventMonitor()
  }

  private func refreshEventMonitor() {
    removeEventMonitor()
    guard window != nil else { return }
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      self?.handleScrollEvent(event) ?? event
    }
  }

  private func removeEventMonitor() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
  }

  private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
    guard let window, event.window === window else { return event }
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }

    let horizontalMagnitude = abs(event.scrollingDeltaX)
    let verticalMagnitude = abs(event.scrollingDeltaY)
    guard verticalMagnitude > horizontalMagnitude, verticalMagnitude > 0.2 else {
      return event
    }

    if event.phase.contains(.began) {
      accumulatedVerticalDelta = 0
    }

    accumulatedVerticalDelta += event.scrollingDeltaY
    let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 80 : 3
    let now = event.timestamp

    if abs(accumulatedVerticalDelta) >= threshold,
       now - lastNavigationTimestamp > 0.18 {
      onMonthScroll?(accumulatedVerticalDelta < 0 ? 1 : -1)
      accumulatedVerticalDelta = 0
      lastNavigationTimestamp = now
    }

    let gestureEnded = event.phase.contains(.ended) || event.phase.contains(.cancelled)
    let momentumEnded =
      event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
    if gestureEnded || momentumEnded {
      accumulatedVerticalDelta = 0
    }

    return nil
  }
}

private struct ScheduleMonthDayCell: View {
  let day: Date
  let monthStart: Date
  let today: Date
  let items: [ScheduleMonthItem]
  let visibleItemLimit: Int
  let hiddenAllDayItemCount: Int
  let reservedAllDayRowCount: Int
  let isSelected: Bool
  let calendar: Calendar
  let onSelect: () -> Void

  var visibleItems: [ScheduleMonthItem] {
    guard visibleItemLimit > 0 else { return [] }
    return Array(items.prefix(visibleItemLimit))
  }

  var hiddenItemCount: Int {
    hiddenAllDayItemCount + max(0, items.count - visibleItems.count)
  }

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: 3) {
        dayNumber
          .frame(height: ScheduleMonthLayoutMetrics.dayNumberHeight)
          .frame(maxWidth: .infinity, alignment: .trailing)

        if reservedAllDayRowCount > 0 {
          Color.clear
            .frame(height: CGFloat(reservedAllDayRowCount) * ScheduleMonthLayoutMetrics.allDaySpanRowHeight)
        }

        ForEach(visibleItems) { item in
          ScheduleMonthCompactItemRow(item: item)
        }

        if hiddenItemCount > 0 {
          Text("+\(hiddenItemCount)개")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, 5)
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, ScheduleMonthLayoutMetrics.dayCellHorizontalPadding)
      .padding(.vertical, ScheduleMonthLayoutMetrics.dayCellTopPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .contentShape(Rectangle())
      .background(selectionBackground)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var dayNumber: some View {
    let number = "\(calendar.component(.day, from: day))일"
    if calendar.isDate(day, inSameDayAs: today) {
      Text("\(calendar.component(.day, from: day))")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Color.white)
        .frame(width: 24, height: 24)
        .background(Circle().fill(Color.red.opacity(0.88)))
        .accessibilityLabel(number)
    } else {
      Text(number)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(dayNumberColor)
        .lineLimit(1)
    }
  }

  private var dayNumberColor: Color {
    calendar.isDate(day, equalTo: monthStart, toGranularity: .month)
      ? .primary
      : .secondary.opacity(0.55)
  }

  @ViewBuilder
  private var selectionBackground: some View {
    if isSelected {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color.accentColor.opacity(0.08))
        .padding(2)
    }
  }
}

private struct ScheduleMonthAllDaySpanRow: View {
  let segment: ScheduleMonthAllDaySpanSegment

  private var item: ScheduleMonthItem {
    segment.item
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "calendar")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(itemColor)

      Text(item.title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(itemColor.opacity(item.isBackgroundCalendar ? 0.22 : 0.20))
    }
    .opacity(item.isBackgroundCalendar ? 0.50 : 1)
  }

  private var itemColor: Color {
    ColorHexCodec.color(from: item.colorHex) ?? .accentColor
  }
}

private struct ScheduleMonthCompactItemRow: View {
  let item: ScheduleMonthItem

  var body: some View {
    HStack(spacing: 4) {
      marker

      Text(item.title)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(textColor)
        .lineLimit(1)
        .truncationMode(.tail)

      if let timeText {
        Spacer(minLength: 2)
        Text(timeText)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(height: ScheduleMonthLayoutMetrics.itemRowHeight)
    .opacity(item.isCompleted || item.isBackgroundCalendar ? 0.48 : 1)
  }

  @ViewBuilder
  private var marker: some View {
    switch item.source {
    case .workspaceTask:
      Circle()
        .strokeBorder(itemColor, lineWidth: 1.4)
        .frame(width: 10, height: 10)
    case .calendarEvent:
      if item.isAllDay {
        Image(systemName: "calendar")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(itemColor)
      } else {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(itemColor)
          .frame(width: 3, height: 14)
      }
    }
  }

  private var itemColor: Color {
    ColorHexCodec.color(from: item.colorHex) ?? .accentColor
  }

  private var textColor: Color {
    item.isCompleted ? .secondary : .primary
  }

  private var timeText: String? {
    guard case .calendarEvent = item.source, !item.isAllDay else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "a h:mm"
    return formatter.string(from: item.startDate)
  }
}
