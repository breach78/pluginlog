import SwiftUI

struct CalendarPickerRow: View {
  let source: ScheduleCalendarSource
  let onCycle: () -> Void

  @State private var isHovering = false

  private var calendarColor: Color {
    ColorHexCodec.color(from: source.colorHex) ?? Color.secondary
  }

  var body: some View {
    Button(action: onCycle) {
      HStack(spacing: 10) {
        stateIcon
          .frame(width: 14, height: 14)

        Text(source.title)
          .font(.system(size: 13))
          .foregroundStyle(source.isVisible ? Color.primary : Color.primary.opacity(0.3))
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(stateHelp)
  }

  @ViewBuilder
  private var stateIcon: some View {
    if !source.isVisible {
      Image(systemName: "xmark")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(0.25))
    } else if source.isBackgroundOnly {
      Image(systemName: "triangle.fill")
        .font(.system(size: 9))
        .foregroundStyle(calendarColor.opacity(0.55))
    } else {
      Image(systemName: "circle.fill")
        .font(.system(size: 9))
        .foregroundStyle(calendarColor)
    }
  }

  private var stateHelp: String {
    if !source.isVisible { return "숨김 → 클릭하면 활성으로" }
    if source.isBackgroundOnly { return "표시만 함 → 클릭하면 숨김으로" }
    return "활성 → 클릭하면 표시만으로"
  }
}

struct ScheduleHiddenTimedItemsIndicatorRow: View {
  let dayCount: Int
  let dayColumnWidth: CGFloat
  let hourHeight: CGFloat
  let timedEntries: [ScheduleTimedBlockLayout]
  let backgroundTimedEntries: [ScheduleTimedBlockLayout]
  let viewportState: ScheduleScrollViewportState
  let onRevealDay: (Int, Int, [ScheduleTimedBlockLayout]) -> Void

  @State private var visibleStartMinute = 0
  @State private var viewportListenerID: UUID?

  private var allTimedEntries: [ScheduleTimedBlockLayout] {
    timedEntries + backgroundTimedEntries
  }

  var body: some View {
    let layouts = allTimedEntries
    let hiddenDayIndexes = ScheduleHiddenTimedItemIndicatorPolicy.hiddenDayIndexes(
      layouts: layouts,
      visibleStartMinute: visibleStartMinute
    )

    HStack(spacing: 0) {
      ForEach(0..<dayCount, id: \.self) { dayIndex in
        ZStack {
          if hiddenDayIndexes.contains(dayIndex) {
            Button {
              onRevealDay(dayIndex, visibleStartMinute, layouts)
            } label: {
              Image(systemName: "arrowtriangle.up.fill")
                .font(
                  .system(size: ScheduleUITokens.MonthDayPanel.hiddenIndicatorFontSize, weight: .bold)
                )
                .foregroundStyle(
                  Color.secondary.opacity(ScheduleUITokens.MonthDayPanel.hiddenIndicatorOpacity)
                )
                .frame(
                  width: ScheduleUITokens.MonthDayPanel.hiddenIndicatorWidth,
                  height: ScheduleUITokens.MonthDayPanel.hiddenIndicatorHeight
                )
            }
            .buttonStyle(.plain)
            .help("위쪽 숨겨진 시간대에 항목 있음")
          }
        }
        .frame(width: dayColumnWidth, height: 12, alignment: .center)
      }
    }
    .frame(width: CGFloat(dayCount) * dayColumnWidth, height: 12, alignment: .topLeading)
    .onAppear {
      updateVisibleStartMinute()
      if viewportListenerID == nil {
        viewportListenerID = viewportState.addViewportChangeListener {
          updateVisibleStartMinute()
        }
      }
    }
    .onDisappear {
      if let viewportListenerID {
        viewportState.removeViewportChangeListener(viewportListenerID)
        self.viewportListenerID = nil
      }
    }
  }

  private func updateVisibleStartMinute() {
    let nextMinute = ScheduleHiddenTimedItemIndicatorPolicy.visibleStartMinute(
      scrollOffsetY: viewportState.liveOffsetY,
      hourHeight: hourHeight
    )
    if visibleStartMinute != nextMinute {
      visibleStartMinute = nextMinute
    }
  }
}
