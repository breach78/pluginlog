import SwiftUI

struct ScheduleMonthView: View {
  @Environment(\.displayScale) private var displayScale
  @Binding var anchorDate: Date
  @State private var layoutCache = ScheduleMonthLayoutCache()
  @State private var dropTargetsByWeekStart: [Date: [ScheduleMonthDropTarget]] = [:]
  @State private var visibleMonthStart: Date?

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

  private var displayedMonthStart: Date {
    visibleMonthStart ?? monthStart
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
      Text(monthTitle(for: displayedMonthStart))
        .font(.system(size: ScheduleUITokens.Month.headerTitleFontSize, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      Spacer(minLength: 0)

      HStack(spacing: 8) {
        Button {
          moveMonth(by: -1)
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: ScheduleUITokens.Month.headerNavigationIconFontSize, weight: .bold))
            .frame(
              width: ScheduleUITokens.Month.headerNavigationButtonSize,
              height: ScheduleUITokens.Month.headerNavigationButtonSize
            )
        }
        .buttonStyle(.borderless)
        .help("이전 달")

        Button("오늘") {
          visibleMonthStart = ScheduleMonthCalendar.monthStart(containing: today, calendar: calendar)
          anchorDate = today
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Button {
          moveMonth(by: 1)
        } label: {
          Image(systemName: "chevron.right")
            .font(.system(size: ScheduleUITokens.Month.headerNavigationIconFontSize, weight: .bold))
            .frame(
              width: ScheduleUITokens.Month.headerNavigationButtonSize,
              height: ScheduleUITokens.Month.headerNavigationButtonSize
            )
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
          .font(.system(size: ScheduleUITokens.Month.weekdayFontSize, weight: .semibold))
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
              displayedMonthStart: displayedMonthStart,
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
            .background(
              GeometryReader { rowProxy in
                Color.clear.preference(
                  key: ScheduleMonthWeekFramePreferenceKey.self,
                  value: [
                    weekLayout.weekStart: rowProxy.frame(
                      in: .named(ScheduleMonthScrollCoordinateSpace.name)
                    )
                  ]
                )
              }
            )
          }
        }
      }
      .coordinateSpace(name: ScheduleMonthScrollCoordinateSpace.name)
      .scrollIndicators(.never)
      .onAppear {
        visibleMonthStart = monthStart
        scrollToAnchorWeek(using: proxy, animated: false)
      }
      .onChange(of: anchorDate) { _, _ in
        visibleMonthStart = monthStart
        scrollToAnchorWeek(using: proxy, animated: true)
      }
      .onPreferenceChange(ScheduleMonthWeekFramePreferenceKey.self) { weekFrames in
        updateVisibleMonthStart(
          from: weekFrames,
          weeks: layout.weeks,
          viewportHeight: cellHeight * 6
        )
      }
      .onDisappear {
        dropTargetsByWeekStart = [:]
        onDropTargetsChanged([])
      }
    }
  }

  private func updateVisibleMonthStart(
    from weekFrames: [Date: CGRect],
    weeks: [ScheduleMonthWeekLayout],
    viewportHeight: CGFloat
  ) {
    let weekMonthStarts = Dictionary(uniqueKeysWithValues: weeks.map { ($0.weekStart, $0.monthStart) })
    guard let nextMonthStart = ScheduleMonthVisibleMonthPolicy.displayedMonthStart(
      weekFrames: weekFrames,
      weekMonthStarts: weekMonthStarts,
      viewportHeight: viewportHeight,
      calendar: calendar
    ) else { return }

    let currentMonthStart = visibleMonthStart ?? monthStart
    guard !calendar.isDate(currentMonthStart, equalTo: nextMonthStart, toGranularity: .month) else {
      return
    }
    visibleMonthStart = nextMonthStart
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
    if let next = calendar.date(byAdding: .month, value: value, to: displayedMonthStart) {
      visibleMonthStart = ScheduleMonthCalendar.monthStart(containing: next, calendar: calendar)
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

private enum ScheduleMonthScrollCoordinateSpace {
  static let name = "schedule-month-scroll"
}

private struct ScheduleMonthWeekFramePreferenceKey: PreferenceKey {
  static let defaultValue: [Date: CGRect] = [:]

  static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}
