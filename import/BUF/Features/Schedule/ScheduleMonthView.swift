import AppKit
import SwiftUI

private enum ScheduleMonthLayoutMetrics {
  static let dayNumberHeight: CGFloat = ScheduleUITokens.Month.dayNumberHeight
  static let dayCellTopPadding: CGFloat = ScheduleUITokens.Month.dayCellTopPadding
  static let dayCellHorizontalPadding: CGFloat = ScheduleUITokens.Month.dayCellHorizontalPadding
  static let itemRowHeight: CGFloat = ScheduleUITokens.Month.itemRowHeight
  static let itemRowSpacing: CGFloat = ScheduleUITokens.Month.itemRowSpacing
  static let allDaySpanHeight: CGFloat = ScheduleUITokens.Month.allDaySpanHeight
  static let allDaySpanRowHeight: CGFloat = ScheduleUITokens.Month.allDaySpanRowHeight
  static let allDaySpanTopOffset: CGFloat = dayCellTopPadding + dayNumberHeight + itemRowSpacing
}

struct ScheduleMonthView: View {
  @Environment(\.displayScale) private var displayScale
  @Binding var anchorDate: Date
  @State private var layoutCache = ScheduleMonthLayoutCache()
  @State private var dropTargetsByWeekStart: [Date: [ScheduleMonthDropTarget]] = [:]

  let today: Date
  let items: [ScheduleMonthItem]
  let itemsSignature: Int
  let selectedDate: Date?
  let calendar: Calendar
  let onSelectDay: (Date, [ScheduleMonthItem]) -> Void
  let onToggleTaskCompletion: (UUID, UUID, Bool) -> Void
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void
  let externalDragTargetDate: Date?
  let externalDayDropTarget: ScheduleMonthDropTarget?
  let onDropTargetsChanged: ([ScheduleMonthDropTarget]) -> Void

  private let weekdayHeaderHeight: CGFloat = ScheduleUITokens.Month.weekdayHeaderHeight
  private let monthHeaderHeight: CGFloat = ScheduleUITokens.Month.monthHeaderHeight
  private let cellMinHeight: CGFloat = ScheduleUITokens.Month.cellMinHeight
  private let gridLineColor = Color.primary.opacity(ScheduleUITokens.Month.gridLineOpacity)

  private var gridLineWidth: CGFloat {
    1 / max(displayScale, 1)
  }

  var monthStart: Date {
    ScheduleMonthCalendar.monthStart(containing: anchorDate, calendar: calendar)
  }

  var monthLayout: ScheduleMonthLayout {
    layoutCache.layout(
      containing: anchorDate,
      items: items,
      itemsSignature: itemsSignature,
      calendar: calendar
    )
  }

  var body: some View {
    GeometryReader { proxy in
      let layout = monthLayout
      let availableGridHeight = max(
        cellMinHeight * 6,
        proxy.size.height - monthHeaderHeight - weekdayHeaderHeight
      )
      let cellHeight = pixelFloored(availableGridHeight / 6)
      let gridHeight = cellHeight * 6
      let visibleItemLimit = ScheduleMonthOverflowPolicy.visibleItemLimit(
        cellHeight: cellHeight
      )

      VStack(spacing: 0) {
        monthHeader
          .frame(height: monthHeaderHeight)

        weekdayHeader
          .frame(height: weekdayHeaderHeight)

        monthWeekScroller(
          layout: layout,
          cellHeight: cellHeight,
          visibleItemLimit: visibleItemLimit
        )
          .frame(height: gridHeight)
          .clipped()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Color(nsColor: .windowBackgroundColor))
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
      ScheduleMonthHorizontalGridLine(
        color: gridLineColor,
        lineWidth: gridLineWidth
      )
    }
  }

  private func monthWeekScroller(
    layout: ScheduleMonthLayout,
    cellHeight: CGFloat,
    visibleItemLimit: Int
  ) -> some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(spacing: 0) {
          ForEach(layout.weeks) { weekLayout in
            ScheduleMonthWeekRow(
              layout: weekLayout,
              today: today,
              visibleItemLimit: visibleItemLimit,
              selectedDate: selectedDate,
              calendar: calendar,
              gridLineColor: gridLineColor,
              gridLineWidth: gridLineWidth,
              externalDragTargetDate: externalDragTargetDate,
              onSelectDay: onSelectDay,
              onToggleTaskCompletion: onToggleTaskCompletion,
              onMoveItem: onMoveItem,
              externalDayDropTarget: externalDayDropTarget,
              onRowDropTargetsChanged: updateDropTargets
            )
            .id(weekLayout.weekStart)
            .frame(height: cellHeight)
          }
        }
      }
      .scrollIndicators(.never)
      .onAppear {
        scrollToAnchorWeek(using: proxy, animated: false)
      }
      .onChange(of: anchorDate) { _, _ in
        scrollToAnchorWeek(using: proxy, animated: true)
      }
      .onDisappear {
        dropTargetsByWeekStart = [:]
        onDropTargetsChanged([])
      }
    }
  }

  private func updateDropTargets(
    weekStart: Date,
    targets: [ScheduleMonthDropTarget]
  ) {
    let key = calendar.startOfDay(for: weekStart)
    if targets.isEmpty {
      dropTargetsByWeekStart.removeValue(forKey: key)
    } else {
      dropTargetsByWeekStart[key] = targets
    }

    let allTargets = dropTargetsByWeekStart
      .keys
      .sorted()
      .flatMap { dropTargetsByWeekStart[$0] ?? [] }
    onDropTargetsChanged(allTargets)
  }

  private var weekdaySymbols: [String] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    let symbols = formatter.shortStandaloneWeekdaySymbols ?? ["일", "월", "화", "수", "목", "금", "토"]
    let first = max(0, min(calendar.firstWeekday - 1, symbols.count - 1))
    return Array(symbols[first..<symbols.count] + symbols[0..<first])
  }

  private func moveMonth(by value: Int) {
    if let next = calendar.date(byAdding: .month, value: value, to: anchorDate) {
      anchorDate = next
    }
  }

  private func scrollToAnchorWeek(using proxy: ScrollViewProxy, animated: Bool) {
    let target = ScheduleMonthContinuousWindow.monthStartWeek(containing: anchorDate, calendar: calendar)
    let action = {
      proxy.scrollTo(target, anchor: .top)
    }
    if animated {
      withAnimation(.easeOut(duration: 0.18), action)
    } else {
      action()
    }
  }

  private func monthTitle(for date: Date) -> String {
    let components = calendar.dateComponents([.year, .month], from: date)
    return "\(components.year ?? 0)년 \(components.month ?? 1)월"
  }

  private func pixelFloored(_ value: CGFloat) -> CGFloat {
    floor(value * max(displayScale, 1)) / max(displayScale, 1)
  }
}

private struct ScheduleMonthWeekRow: View {
  let layout: ScheduleMonthWeekLayout
  let today: Date
  let visibleItemLimit: Int
  let selectedDate: Date?
  @State private var activeDragDate: Date?
  @State private var activeDragFeedback: ScheduleMonthDragFeedback?
  let calendar: Calendar
  let gridLineColor: Color
  let gridLineWidth: CGFloat
  let externalDragTargetDate: Date?
  let onSelectDay: (Date, [ScheduleMonthItem]) -> Void
  let onToggleTaskCompletion: (UUID, UUID, Bool) -> Void
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void
  let externalDayDropTarget: ScheduleMonthDropTarget?
  let onRowDropTargetsChanged: (Date, [ScheduleMonthDropTarget]) -> Void
  @State private var rowFrameInScreen: CGRect = .null

  private var visibleAllDaySegments: [ScheduleMonthAllDaySpanSegment] {
    layout.allDaySegments.filter { $0.rowIndex < visibleAllDayRowLimit }
  }

  private var visibleAllDayRowLimit: Int {
    max(0, visibleItemLimit)
  }

  private var rowCoordinateSpaceName: String {
    "schedule-month-week-\(layout.weekStart.timeIntervalSinceReferenceDate)"
  }

  var body: some View {
    GeometryReader { rowProxy in
      let rowSize = rowProxy.size
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
          ForEach(0..<layout.days.count, id: \.self) { dayIndex in
            let dayLayout = layout.days[dayIndex]

            ScheduleMonthDayCell(
              day: dayLayout.day,
              monthStart: layout.monthStart,
              today: today,
              items: dayLayout.inlineItems,
              visibleItemLimit: inlineVisibleItemLimit(on: dayIndex),
              hiddenAllDayItemCount: hiddenAllDayItemCount(on: dayIndex),
              reservedAllDayRowCount: visibleAllDayRowCount(on: dayIndex),
              isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: dayLayout.day) } ?? false,
              isDragTarget: isDragTarget(dayLayout.day),
              weekStart: layout.weekStart,
              rowSize: rowSize,
              rowCoordinateSpaceName: rowCoordinateSpaceName,
              rowFrameInScreen: rowFrameInScreen,
              activeDragDate: $activeDragDate,
              activeDragFeedback: $activeDragFeedback,
              calendar: calendar,
              onSelect: {
                onSelectDay(dayLayout.normalizedDay, dayLayout.allItems)
              },
              onToggleTaskCompletion: onToggleTaskCompletion,
              onMoveItem: onMoveItem,
              externalDayDropTarget: externalDayDropTarget
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }

        let columnWidth = rowSize.width / 7
        ForEach(visibleAllDaySegments) { segment in
          if segment.startDayIndex < layout.days.count {
            let segmentDay = layout.days[segment.startDayIndex]
            let width = max(0, columnWidth * CGFloat(segment.daySpanCount) - 4)
            let x = columnWidth * CGFloat(segment.startDayIndex) + width / 2 + 2
            let y = ScheduleMonthLayoutMetrics.allDaySpanTopOffset
              + CGFloat(segment.rowIndex) * ScheduleMonthLayoutMetrics.allDaySpanRowHeight
              + ScheduleMonthLayoutMetrics.allDaySpanHeight / 2

            ScheduleMonthAllDaySpanRow(segment: segment)
              .modifier(
                ScheduleMonthLocalDragModifier(
                  item: segment.item,
                  weekStart: layout.weekStart,
                  rowSize: rowSize,
                  rowCoordinateSpaceName: rowCoordinateSpaceName,
                  rowFrameInScreen: rowFrameInScreen,
                  activeDragDate: $activeDragDate,
                  activeDragFeedback: $activeDragFeedback,
                  calendar: calendar,
                  onMoveItem: onMoveItem,
                  externalDayDropTarget: externalDayDropTarget
                )
              )
              .simultaneousGesture(
                TapGesture().onEnded {
                  onSelectDay(segmentDay.normalizedDay, segmentDay.allItems)
                }
              )
              .frame(width: width, height: ScheduleMonthLayoutMetrics.allDaySpanHeight)
              .position(x: x, y: y)
          }
        }

        ScheduleMonthWeekGridLines(
          color: gridLineColor,
          lineWidth: gridLineWidth
        )
        .allowsHitTesting(false)

        if let feedback = activeDragFeedback, feedback.weekStart == layout.weekStart {
          ScheduleMonthDragFeedbackMarker(feedback: feedback)
            .position(x: feedback.location.x, y: feedback.location.y)
            .allowsHitTesting(false)
        }
      }
      .coordinateSpace(name: rowCoordinateSpaceName)
      .background(
        ScheduleScreenFrameReporter { frame in
          rowFrameInScreen = frame
          onRowDropTargetsChanged(layout.weekStart, dropTargets(rowFrame: frame))
        }
      )
    }
    .onDisappear {
      onRowDropTargetsChanged(layout.weekStart, [])
    }
    .zIndex(activeDragFeedback == nil ? 0 : 1)
  }

  private func dropTargets(rowFrame: CGRect) -> [ScheduleMonthDropTarget] {
    guard !rowFrame.isNull, rowFrame.width > 0, rowFrame.height > 0 else { return [] }
    let columnWidth = rowFrame.width / CGFloat(max(1, layout.days.count))
    return layout.days.enumerated().map { dayIndex, dayLayout in
      ScheduleMonthDropTarget(
        day: calendar.startOfDay(for: dayLayout.day),
        frame: CGRect(
          x: rowFrame.minX + columnWidth * CGFloat(dayIndex),
          y: rowFrame.minY,
          width: columnWidth,
          height: rowFrame.height
        )
      )
    }
  }

  private func inlineVisibleItemLimit(on dayIndex: Int) -> Int {
    max(0, visibleItemLimit - visibleAllDayRowCount(on: dayIndex))
  }

  private func isDragTarget(_ day: Date) -> Bool {
    activeDragDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
      || externalDragTargetDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
  }

  private func visibleAllDayRowCount(on dayIndex: Int) -> Int {
    ScheduleMonthSpanLayout.visibleAllDayRowCount(
      on: dayIndex,
      segments: layout.allDaySegments,
      visibleRowLimit: visibleAllDayRowLimit
    )
  }

  private func hiddenAllDayItemCount(on dayIndex: Int) -> Int {
    ScheduleMonthSpanLayout.hiddenAllDayItemCount(
      on: dayIndex,
      segments: layout.allDaySegments,
      visibleRowLimit: visibleAllDayRowLimit
    )
  }
}

private struct ScheduleMonthHorizontalGridLine: View {
  let color: Color
  let lineWidth: CGFloat

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color(nsColor: .windowBackgroundColor))
      Rectangle()
        .fill(color)
    }
    .frame(height: lineWidth)
  }
}

private struct ScheduleMonthWeekGridLines: View {
  let color: Color
  let lineWidth: CGFloat

  var body: some View {
    Canvas { context, size in
      let y = lineWidth / 2
      let columnWidth = size.width / 7
      var path = Path()

      for columnIndex in 1..<7 {
        let x = columnWidth * CGFloat(columnIndex)
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
      }

      path.move(to: CGPoint(x: 0, y: y))
      path.addLine(to: CGPoint(x: size.width, y: y))

      context.stroke(
        path,
        with: .color(Color(nsColor: .windowBackgroundColor)),
        lineWidth: lineWidth
      )
      context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }
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
  let isDragTarget: Bool
  let weekStart: Date
  let rowSize: CGSize
  let rowCoordinateSpaceName: String
  let rowFrameInScreen: CGRect
  @Binding var activeDragDate: Date?
  @Binding var activeDragFeedback: ScheduleMonthDragFeedback?
  let calendar: Calendar
  let onSelect: () -> Void
  let onToggleTaskCompletion: (UUID, UUID, Bool) -> Void
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void
  let externalDayDropTarget: ScheduleMonthDropTarget?

  @State private var suppressedSelectUntil: Date = .distantPast

  private var visibleRowCapacity: Int {
    max(0, visibleItemLimit)
  }

  private var shouldShowOverflowRow: Bool {
    visibleRowCapacity > 0 && (hiddenAllDayItemCount > 0 || items.count > visibleRowCapacity)
  }

  var visibleItems: [ScheduleMonthItem] {
    let itemLimit = shouldShowOverflowRow
      ? max(0, visibleRowCapacity - 1)
      : visibleRowCapacity
    return Array(items.prefix(itemLimit))
  }

  var hiddenItemCount: Int {
    guard shouldShowOverflowRow else { return 0 }
    return hiddenAllDayItemCount + max(0, items.count - visibleItems.count)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      cellBackground
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      cellContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .contentShape(Rectangle())
    .onTapGesture(perform: selectIfNotSuppressed)
    .onDrop(
      of: ScheduleMonthDragPayload.dropTypeIdentifiers,
      delegate: ScheduleMonthExternalItemDropDelegate(
        targetDay: day,
        activeDragDate: $activeDragDate,
        calendar: calendar,
        onMoveItem: onMoveItem
      )
    )
    .clipped()
  }

  private var cellContent: some View {
    VStack(alignment: .leading, spacing: ScheduleMonthLayoutMetrics.itemRowSpacing) {
      dayNumber
        .frame(height: ScheduleMonthLayoutMetrics.dayNumberHeight)
        .frame(maxWidth: .infinity, alignment: .trailing)

      if reservedAllDayRowCount > 0 {
        Color.clear
          .frame(height: CGFloat(reservedAllDayRowCount) * ScheduleMonthLayoutMetrics.allDaySpanRowHeight)
      }

      ForEach(visibleItems) { item in
        ScheduleMonthCompactItemRow(
          item: item,
          isCompletedTask: isCompletedTask(item),
          onToggleCompletion: completionToggleAction(for: item),
          onPressCompletionControl: completionPressAction(for: item)
        )
        .modifier(
          ScheduleMonthLocalDragModifier(
            item: item,
            weekStart: weekStart,
            rowSize: rowSize,
            rowCoordinateSpaceName: rowCoordinateSpaceName,
            rowFrameInScreen: rowFrameInScreen,
            activeDragDate: $activeDragDate,
            activeDragFeedback: $activeDragFeedback,
            calendar: calendar,
            onMoveItem: onMoveItem,
            externalDayDropTarget: externalDayDropTarget
          )
        )
        .simultaneousGesture(
          TapGesture().onEnded(selectIfNotSuppressed)
        )
      }

      if hiddenItemCount > 0 {
        Text("+\(hiddenItemCount)개")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.leading, 5)
          .frame(height: ScheduleMonthLayoutMetrics.itemRowHeight, alignment: .leading)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, ScheduleMonthLayoutMetrics.dayCellHorizontalPadding)
    .padding(.vertical, ScheduleMonthLayoutMetrics.dayCellTopPadding)
  }

  @ViewBuilder
  private var dayNumber: some View {
    let number = "\(calendar.component(.day, from: day))일"
    if calendar.isDate(day, inSameDayAs: today) {
      Text("\(calendar.component(.day, from: day))")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Color.white)
        .frame(width: 24, height: 24)
        .background(Circle().fill(Color.red.opacity(ScheduleUITokens.Month.todayBadgeFillOpacity)))
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

  private func isCompletedTask(_ item: ScheduleMonthItem) -> Bool {
    guard item.isCompleted else { return false }
    guard case .workspaceTask = item.source else { return false }
    return true
  }

  private func completionToggleAction(for item: ScheduleMonthItem) -> (() -> Void)? {
    guard !item.isPreparationSlot else { return nil }
    guard case .workspaceTask(let taskID, let projectID) = item.source else { return nil }
    return {
      suppressSelectionAfterCompletionPress()
      onToggleTaskCompletion(taskID, projectID, item.isCompleted)
    }
  }

  private func completionPressAction(for item: ScheduleMonthItem) -> (() -> Void)? {
    guard !item.isPreparationSlot else { return nil }
    guard case .workspaceTask = item.source else { return nil }
    return {
      suppressSelectionAfterCompletionPress()
    }
  }

  private func suppressSelectionAfterCompletionPress() {
    suppressedSelectUntil = TaskTapSuppressionPolicy.suppressedUntil(
      now: Date(),
      duration: TaskTapSuppressionPolicy.completionControlDuration
    )
  }

  private func selectIfNotSuppressed() {
    guard TaskTapSuppressionPolicy.shouldHandleTaskTap(
      now: Date(),
      suppressedUntil: suppressedSelectUntil
    ) else {
      return
    }
    onSelect()
  }

  @ViewBuilder
  private var cellBackground: some View {
    if isDragTarget {
      Rectangle()
        .fill(Color.accentColor.opacity(0.09))
    } else if isSelected {
      Rectangle()
        .fill(Color.accentColor.opacity(0.066))
    } else if calendar.isDate(day, inSameDayAs: today) {
      Rectangle()
        .fill(Color.accentColor.opacity(0.055))
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
        .font(.system(size: 13, weight: .medium))
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
  let isCompletedTask: Bool
  let onToggleCompletion: (() -> Void)?
  let onPressCompletionControl: (() -> Void)?

  private static let timeFormatStyle = Date.FormatStyle(
    date: .omitted,
    time: .shortened
  )
  .locale(Locale(identifier: "ko_KR"))

  private var rowOpacity: Double {
    if isCompletedTask { return 0.384 }
    if item.isBackgroundCalendar { return 0.48 }
    return 1
  }

  var body: some View {
    HStack(spacing: 4) {
      markerControl

      Text(item.title)
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(textColor)
        .lineLimit(1)
        .truncationMode(.tail)

      if let timeText {
        Spacer(minLength: 2)
        Text(timeText)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(height: ScheduleMonthLayoutMetrics.itemRowHeight)
    .opacity(rowOpacity)
  }

  @ViewBuilder
  private var markerControl: some View {
    if let onToggleCompletion {
      Button(action: onToggleCompletion) {
        marker
          .frame(width: 16, height: ScheduleMonthLayoutMetrics.itemRowHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .simultaneousGesture(
        taskCompletionPressGesture {
          onPressCompletionControl?()
        }
      )
      .help(item.isCompleted ? "완료 취소" : "완료")
    } else {
      marker
        .frame(width: 16, height: ScheduleMonthLayoutMetrics.itemRowHeight)
    }
  }

  @ViewBuilder
  private var marker: some View {
    switch item.source {
    case .workspaceTask:
      if isCompletedTask {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(itemColor)
      } else {
        Circle()
          .strokeBorder(itemColor, lineWidth: 1.4)
          .frame(width: 10, height: 10)
      }
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
    isCompletedTask ? .secondary : .primary
  }

  private var timeText: String? {
    guard case .calendarEvent = item.source, !item.isAllDay else {
      return nil
    }
    return item.startDate.formatted(Self.timeFormatStyle)
  }
}

private struct ScheduleMonthDragFeedbackMarker: View {
  let feedback: ScheduleMonthDragFeedback

  var body: some View {
    ZStack {
      Circle()
        .fill(Color(nsColor: .windowBackgroundColor))
        .overlay {
          Circle()
            .strokeBorder(itemColor.opacity(0.75), lineWidth: 1.2)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 2)

      marker
    }
    .frame(width: 24, height: 24)
  }

  @ViewBuilder
  private var marker: some View {
    switch feedback.source {
    case .workspaceTask:
      if feedback.isCompleted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(itemColor)
      } else {
        Circle()
          .strokeBorder(itemColor, lineWidth: 1.8)
          .frame(width: 12, height: 12)
      }
    case .calendarEvent:
      if feedback.isAllDay {
        Image(systemName: "calendar")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(itemColor)
      } else {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(itemColor)
          .frame(width: 4, height: 14)
      }
    }
  }

  private var itemColor: Color {
    ColorHexCodec.color(from: feedback.colorHex) ?? .accentColor
  }
}

private struct ScheduleMonthLocalDragModifier: ViewModifier {
  let item: ScheduleMonthItem
  let weekStart: Date
  let rowSize: CGSize
  let rowCoordinateSpaceName: String
  let rowFrameInScreen: CGRect
  @Binding var activeDragDate: Date?
  @Binding var activeDragFeedback: ScheduleMonthDragFeedback?
  let calendar: Calendar
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void
  let externalDayDropTarget: ScheduleMonthDropTarget?

  @State private var dragSession: ScheduleMonthDragSessionState?

  func body(content: Content) -> some View {
    if let dragItem = ScheduleMonthDragSupport.dragItem(for: item) {
      content
        .contentShape(Rectangle())
        .highPriorityGesture(
          DragGesture(minimumDistance: 6, coordinateSpace: .named(rowCoordinateSpaceName))
            .onChanged { value in
              updateDrag(value, dragItem: dragItem)
            }
            .onEnded { value in
              finishDrag(value, dragItem: dragItem)
            }
        )
    } else {
      content
    }
  }

  private func updateDrag(_ value: DragGesture.Value, dragItem _: ScheduleMonthDragItem) {
    let originalStartDay = calendar.startOfDay(for: item.startDate)
    if let externalTargetDay = externalDayPanelTargetDay(for: value) {
      let session = ScheduleMonthDragSessionState.external(
        targetDay: externalTargetDay,
        calendar: calendar
      )
      activeDragDate = session.highlightDay
      activeDragFeedback = ScheduleMonthDragFeedback(
        item: item,
        weekStart: weekStart,
        location: value.location
      )
      dragSession = session
      NSCursor.dragCopy.set()
      return
    }

    let resolvedStartPointerDay =
      dragSession?.startPointerDay
      ?? ScheduleMonthDragGeometry.day(
        at: value.startLocation,
        weekStart: weekStart,
        rowSize: rowSize,
        calendar: calendar
      )
    guard let resolvedStartPointerDay,
      let currentPointerDay = ScheduleMonthDragGeometry.day(
        at: value.location,
        weekStart: weekStart,
        rowSize: rowSize,
        calendar: calendar
      )
    else {
      return
    }

    guard let session = ScheduleMonthDragSessionState.local(
      originalStartDay: originalStartDay,
      startPointerDay: resolvedStartPointerDay,
      currentPointerDay: currentPointerDay,
      calendar: calendar
    ) else { return }

    dragSession = session
    activeDragDate = session.highlightDay
    NSCursor.closedHand.set()
    activeDragFeedback = ScheduleMonthDragFeedback(
      item: item,
      weekStart: weekStart,
      location: value.location
    )
  }

  private func finishDrag(_ value: DragGesture.Value, dragItem: ScheduleMonthDragItem) {
    defer { NSCursor.arrow.set() }
    updateDrag(value, dragItem: dragItem)
    let target = dragSession?.target

    dragSession = nil
    activeDragDate = nil
    activeDragFeedback = nil

    guard let target else { return }
    onMoveItem(dragItem, target)
  }

  private func externalDayPanelTargetDay(for value: DragGesture.Value) -> Date? {
    guard
      let screenPoint = ScheduleScreenPointMapper.screenPoint(
        localLocation: value.location,
        in: rowFrameInScreen
      )
    else {
      return nil
    }
    return ScheduleMonthDropTargetResolver.day(
      at: screenPoint,
      target: externalDayDropTarget,
      calendar: calendar
    )
  }
}

private struct ScheduleMonthExternalItemDropDelegate: DropDelegate {
  let targetDay: Date
  @Binding var activeDragDate: Date?
  let calendar: Calendar
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    dropProvider(in: info) != nil
  }

  func dropEntered(info _: DropInfo) {
    activeDragDate = calendar.startOfDay(for: targetDay)
  }

  func dropExited(info _: DropInfo) {
    if let activeDragDate,
      calendar.isDate(activeDragDate, inSameDayAs: targetDay)
    {
      self.activeDragDate = nil
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    validateDrop(info: info) ? DropProposal(operation: .move) : nil
  }

  func performDrop(info: DropInfo) -> Bool {
    activeDragDate = nil
    guard let provider = dropProvider(in: info) else {
      return false
    }
    let target = ScheduleMonthDragSessionState.external(
      targetDay: targetDay,
      calendar: calendar
    ).target
    loadDragItem(from: provider) { dragItem in
      guard let dragItem else { return }
      onMoveItem(dragItem, target)
    }
    return true
  }

  private func dropProvider(in info: DropInfo) -> NSItemProvider? {
    ScheduleMonthDragPayload.dropTypeIdentifiers.lazy.compactMap { typeIdentifier in
      info.itemProviders(for: [typeIdentifier]).first
    }.first
  }

  private func loadDragItem(
    from provider: NSItemProvider,
    completion: @escaping @MainActor (ScheduleMonthDragItem?) -> Void
  ) {
    let preferredType =
      ScheduleMonthDragPayload.dropTypeIdentifiers.first {
        provider.hasItemConformingToTypeIdentifier($0)
      } ?? ScheduleMonthDragPayload.textTypeIdentifier

    provider.loadItem(forTypeIdentifier: preferredType, options: nil) { item, _ in
      let dragItem = ScheduleMonthDragPayload.parseItem(from: item)
      Task { @MainActor in
        completion(dragItem)
      }
    }
  }
}
