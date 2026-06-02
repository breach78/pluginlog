import SwiftUI

struct ProjectOutlineScheduleFallbackMenu: View {
  let task: TimelineProjectListWindowSnapshot.Task
  let recurringCompletionCount: Int
  let projectColor: Color
  let onSelect: (TaskEditAuxiliarySection) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        onSelect(.schedule)
      } label: {
        menuRow(
          systemImage: "calendar.badge.clock",
          title: "날짜와 시간",
          detail: task.dateText
        )
      }
      .buttonStyle(.plain)

      Button {
        onSelect(.recurrence)
      } label: {
        menuRow(
          systemImage: "repeat",
          title: "반복",
          detail: recurrenceDetail
        )
      }
      .buttonStyle(.plain)
    }
    .padding(8)
    .frame(width: 176, alignment: .leading)
    .font(projectOutlinerChipFont)
  }

  private var recurrenceDetail: String? {
    if recurringCompletionCount > 0 {
      return "\(recurringCompletionCount)"
    }
    return task.metadataIndicators.isRecurring ? "설정됨" : nil
  }

  private func menuRow(systemImage: String, title: String, detail: String?) -> some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(projectColor.opacity(0.9))
        .frame(width: 18)
      Text(title)
        .foregroundStyle(Color.primary)
      Spacer(minLength: 8)
      if let detail {
        Text(detail)
          .lineLimit(1)
          .foregroundStyle(Color.secondary)
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 5)
    .contentShape(Rectangle())
  }
}
