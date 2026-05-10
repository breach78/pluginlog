import SwiftUI

struct ScheduleMonthDetailPanelContent: View {
  let target: ScheduleMonthDetailPanelTarget
  let calendar: Calendar
  let quickAddProjects: [ScheduleQuickAddProjectOption]
  let defaultQuickAddProjectID: UUID?
  let onOpenItem: (ScheduleMonthItem) -> Void
  let onToggleTaskCompletion: (ScheduleMonthItem, Bool) async -> ScheduleMonthItem?
  let onUpdateItemSchedule: (ScheduleMonthItem, Date, Int?, Int?) async -> ScheduleMonthItem?
  let onCreateTask: (String, UUID, Date, Int?, Int?) async -> ScheduleMonthItem?
  let onDeleteItem: (ScheduleMonthItem, ScheduleCalendarRecurringEditScope?) async -> Bool
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Divider()

      ScheduleMonthDaySchedulePanel(
        target: target,
        calendar: calendar,
        quickAddProjects: quickAddProjects,
        defaultQuickAddProjectID: defaultQuickAddProjectID,
        onOpenItem: onOpenItem,
        onToggleTaskCompletion: onToggleTaskCompletion,
        onUpdateItemSchedule: onUpdateItemSchedule,
        onCreateTask: onCreateTask,
        onDeleteItem: onDeleteItem
      )
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
