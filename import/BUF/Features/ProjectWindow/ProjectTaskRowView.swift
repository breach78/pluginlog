import SwiftUI

struct ProjectTaskRowView: View, Equatable {
  let taskID: UUID
  let renderSignature: Int
  let baseBackgroundColor: Color
  let selectionBackgroundColor: Color
  let scrollAnchorID: String
  let cellVerticalInset: CGFloat
  let checkColumnWidth: CGFloat
  let checkToTitleSpacing: CGFloat
  let rowBaseHeight: CGFloat
  let rowHorizontalPadding: CGFloat
  let rowVerticalPadding: CGFloat
  let onTap: () -> Void
  let statusControl: () -> AnyView
  let leadingAccessory: () -> AnyView
  let titleCell: (Bool) -> AnyView
  let dateCell: () -> AnyView
  let blockCell: () -> AnyView

  @State private var isHovered = false

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.taskID == rhs.taskID && lhs.renderSignature == rhs.renderSignature
  }

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      statusControl()
        .padding(.vertical, cellVerticalInset)
        .frame(
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: Alignment(horizontal: .center, vertical: .center)
        )
        .frame(width: checkColumnWidth, alignment: .center)
        .frame(
          minHeight: rowBaseHeight,
          maxHeight: .infinity,
          alignment: .center
        )

      leadingAccessory()
        .frame(width: checkToTitleSpacing, alignment: .center)
        .frame(
          minHeight: rowBaseHeight,
          maxHeight: .infinity,
          alignment: .center
        )

      titleCell(isHovered)
    }
    .padding(.horizontal, rowHorizontalPadding)
    .padding(.vertical, rowVerticalPadding)
    .contentShape(Rectangle())
    .background {
      ZStack {
        Rectangle().fill(baseBackgroundColor)
        Rectangle().fill(selectionBackgroundColor)
      }
    }
    .onTapGesture(perform: onTap)
    .onHover { hovering in
      isHovered = hovering
    }
    .anchorPreference(key: TaskRowBoundsPreferenceKey.self, value: .bounds) {
      [taskID: $0]
    }
    .id(scrollAnchorID)
  }
}
