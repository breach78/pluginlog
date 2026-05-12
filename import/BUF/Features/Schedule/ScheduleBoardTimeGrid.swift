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
            .fill(Color.red.opacity(0.78))
            .frame(width: dayColumnWidth, height: 2)
            .offset(x: startX, y: y - 1)

          Text(currentTimeChipLabel(from: currentDate))
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.red.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
              Capsule()
                .fill(Color(nsColor: .windowBackgroundColor))
            )
            .fixedSize()
            .offset(x: startX + 2, y: y - 14)
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

  var zoneWidth: CGFloat { compact ? 24 : 26 }
  var buttonSize: CGFloat { compact ? 18 : 20 }
  var iconSize: CGFloat { compact ? 9 : 10 }
  var hoverAnimation: Animation? {
    MotionSystem.animation(for: .hoverFade, quality: motionQuality)
  }
  var shadowOpacity: Double {
    switch motionQuality {
    case .full:
      return 0.08
    case .reduced:
      return 0.04
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
              .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))

            Image(systemName: "chevron.right")
              .font(.system(size: iconSize, weight: .bold))
              .foregroundStyle(.secondary)
              .offset(x: 0.5)
          }
          .frame(width: buttonSize, height: buttonSize)
          .shadow(color: .black.opacity(shadowOpacity), radius: 3, x: 0, y: 1)
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
