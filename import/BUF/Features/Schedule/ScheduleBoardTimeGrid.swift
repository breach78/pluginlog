import AppKit
import SwiftUI


struct ScheduleCurrentTimeIndicator: View {
  private static let refreshIntervalSeconds: TimeInterval = 60

  let dayRange: ClosedRange<Int>
  let dayColumnWidth: CGFloat
  let totalWidth: CGFloat
  let totalHeight: CGFloat
  let hourHeight: CGFloat
  let calendar: Calendar

  var body: some View {
    TimelineView(.periodic(from: .now, by: Self.refreshIntervalSeconds)) { context in
      ZStack(alignment: .topLeading) {
        let currentDate = context.date
        let today = calendar.startOfDay(for: currentDate)
        let days = visibleDays(relativeTo: today)
        let dayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) })

        if let dayIndex {
          let components = calendar.dateComponents([.hour, .minute, .second], from: currentDate)
          let currentMinutes =
            CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + CGFloat(components.second ?? 0) / 60
          let y = currentMinutes / 60 * hourHeight
          let startX = CGFloat(dayIndex) * dayColumnWidth

          Rectangle()
            .fill(Color.red.opacity(ScheduleUITokens.Board.currentTimeLineOpacity))
            .frame(width: dayColumnWidth, height: ScheduleUITokens.Board.currentTimeLineHeight)
            .offset(x: startX, y: y - ScheduleUITokens.Board.currentTimeLineHeight / 2)

          Text(currentTimeChipLabel(from: currentDate))
            .font(.system(
              size: ScheduleUITokens.Board.currentTimeChipFontSize,
              weight: .semibold,
              design: .monospaced
            ))
            .foregroundStyle(Color.red.opacity(ScheduleUITokens.Board.currentTimeChipForegroundOpacity))
            .padding(.horizontal, ScheduleUITokens.Board.currentTimeChipHorizontalPadding)
            .padding(.vertical, ScheduleUITokens.Board.currentTimeChipVerticalPadding)
            .background(
              Capsule()
                .fill(Color(nsColor: .windowBackgroundColor))
            )
            .fixedSize()
            .offset(
              x: startX + ScheduleUITokens.Board.currentTimeChipXOffset,
              y: y - ScheduleUITokens.Board.currentTimeChipYOffset
            )
        }
      }
      .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
    }
  }

  func visibleDays(relativeTo today: Date) -> [Date] {
    Array(dayRange).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: today)
    }
  }

  func currentTimeChipLabel(from date: Date) -> String {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    return String(format: "%02d:%02d", hour, minute)
  }
}

struct SchedulePostponeAffordance: View {
  let compact: Bool
  let motionQuality: MotionQuality
  let isPinnedVisible: Bool
  let onTrigger: () -> Void

  @State var isHovering = false

  var zoneWidth: CGFloat {
    compact
      ? ScheduleUITokens.Board.postponeCompactZoneWidth
      : ScheduleUITokens.Board.postponeRegularZoneWidth
  }
  var buttonSize: CGFloat {
    compact
      ? ScheduleUITokens.Board.postponeCompactButtonSize
      : ScheduleUITokens.Board.postponeRegularButtonSize
  }
  var iconSize: CGFloat {
    compact
      ? ScheduleUITokens.Board.postponeCompactIconSize
      : ScheduleUITokens.Board.postponeRegularIconSize
  }
  var hoverAnimation: Animation? {
    MotionSystem.animation(for: .hoverFade, quality: motionQuality)
  }
  var shadowOpacity: Double {
    switch motionQuality {
    case .full:
      return ScheduleUITokens.Board.postponeShadowFullOpacity
    case .reduced:
      return ScheduleUITokens.Board.postponeShadowReducedOpacity
    case .minimal, .disabled:
      return 0
    }
  }

  var body: some View {
    ZStack {
      if isHovering || isPinnedVisible {
        Button(action: onTrigger) {
          ZStack {
            Circle()
              .fill(Color(nsColor: .windowBackgroundColor).opacity(
                ScheduleUITokens.Board.postponeBackgroundOpacity
              ))

            Image(systemName: "chevron.right")
              .font(.system(size: iconSize, weight: .bold))
              .foregroundStyle(.secondary)
              .offset(x: ScheduleUITokens.Board.postponeIconXOffset)
          }
          .frame(width: buttonSize, height: buttonSize)
          .shadow(
            color: .black.opacity(shadowOpacity),
            radius: ScheduleUITokens.Board.postponeShadowRadius,
            x: 0,
            y: ScheduleUITokens.Board.postponeShadowYOffset
          )
        }
        .buttonStyle(.plain)
        .help("하루 뒤 올데이로 미루기")
        .transition(.opacity)
      }
    }
    .frame(width: zoneWidth)
    .frame(maxHeight: .infinity)
    .contentShape(Rectangle())
    .onHover { hovering in
      if let hoverAnimation {
        withAnimation(hoverAnimation) {
          isHovering = hovering
        }
      } else {
        MotionTransaction.withoutAnimation {
          isHovering = hovering
        }
      }
    }
  }
}
