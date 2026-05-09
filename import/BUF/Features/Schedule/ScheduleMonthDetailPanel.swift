import SwiftUI

struct ScheduleMonthDetailPanelContent: View {
  let target: ScheduleMonthDetailPanelTarget
  let calendar: Calendar
  let onOpenItem: (ScheduleMonthItem) -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Divider()

      if target.items.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(target.items) { item in
              Button {
                onOpenItem(item)
              } label: {
                ScheduleMonthDetailItemRow(item: item)
              }
              .buttonStyle(.plain)

              Divider()
                .padding(.leading, 38)
            }
          }
          .padding(.vertical, 8)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(dateTitle)
          .font(.system(size: 18, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)

        Text(itemCountText)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      Button {
        onClose()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("닫기")
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("표시할 항목이 없습니다")
        .font(.system(size: 14, weight: .semibold))
      Text("월간 캘린더에서 다른 날짜를 선택할 수 있습니다.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var dateTitle: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy년 M월 d일 EEEE"
    return formatter.string(from: target.date)
  }

  private var itemCountText: String {
    "\(target.items.count)개 항목"
  }
}

private struct ScheduleMonthDetailItemRow: View {
  let item: ScheduleMonthItem

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      marker
        .frame(width: 18, height: 18)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(item.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(item.isCompleted ? .secondary : .primary)
            .lineLimit(2)

          Spacer(minLength: 0)

          if let timeText {
            Text(timeText)
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        if let subtitle = item.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .contentShape(Rectangle())
    .opacity(item.isCompleted || item.isBackgroundCalendar ? 0.55 : 1)
  }

  @ViewBuilder
  private var marker: some View {
    switch item.source {
    case .workspaceTask:
      Circle()
        .strokeBorder(itemColor, lineWidth: 1.6)
    case .calendarEvent:
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(itemColor.opacity(item.isAllDay ? 0.28 : 0.85))
        .overlay {
          if item.isAllDay {
            Image(systemName: "calendar")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(itemColor)
          }
        }
    }
  }

  private var itemColor: Color {
    ColorHexCodec.color(from: item.colorHex) ?? .accentColor
  }

  private var timeText: String? {
    guard !item.isAllDay else { return "종일" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "a h:mm"
    return formatter.string(from: item.startDate)
  }
}
