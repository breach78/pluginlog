import AppKit
import SwiftUI

struct ScheduleMonthDayCurrentTimeIndicator: View {
  private static let refreshIntervalSeconds: TimeInterval = 60

  let day: Date
  let width: CGFloat
  let height: CGFloat
  let hourHeight: CGFloat
  let calendar: Calendar

  var body: some View {
    TimelineView(.periodic(from: .now, by: Self.refreshIntervalSeconds)) { context in
      ZStack(alignment: .topLeading) {
        if calendar.isDate(day, inSameDayAs: context.date) {
          let y = currentTimeY(for: context.date)

          Rectangle()
            .fill(Color.red.opacity(ScheduleUITokens.MonthDayPanel.currentTimeLineOpacity))
            .frame(width: width, height: ScheduleUITokens.MonthDayPanel.currentTimeLineHeight)
            .offset(y: y - ScheduleUITokens.MonthDayPanel.currentTimeLineHeight / 2)

          Circle()
            .fill(Color.red.opacity(ScheduleUITokens.MonthDayPanel.currentTimeDotOpacity))
            .frame(
              width: ScheduleUITokens.MonthDayPanel.currentTimeDotSize,
              height: ScheduleUITokens.MonthDayPanel.currentTimeDotSize
            )
            .offset(
              x: ScheduleUITokens.MonthDayPanel.currentTimeDotXOffset,
              y: y - ScheduleUITokens.MonthDayPanel.currentTimeDotYOffset
            )
        }
      }
      .frame(width: width, height: height, alignment: .topLeading)
    }
    .allowsHitTesting(false)
  }

  private func currentTimeY(for date: Date) -> CGFloat {
    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
    let minutes =
      CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
      + CGFloat(components.second ?? 0) / 60
    return minutes / 60 * hourHeight
  }
}
