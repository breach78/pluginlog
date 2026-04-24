import SwiftUI

struct ProjectDetailTaskSection<AnimationToken: Equatable, Rows: View, Overlay: View>: View {
  let orderingMode: BlockChildOrderingMode
  let showsCompletedTasks: Bool
  let rowSpacing: CGFloat
  let coordinateSpaceName: String
  let animationToken: AnimationToken
  let onCycleOrdering: () -> Void
  let onAppendTask: () -> Void
  let onToggleShowsCompletedTasks: (Bool) -> Void
  let onRowFramesChange: ([UUID: CGRect]) -> Void
  @ViewBuilder let rows: () -> Rows
  @ViewBuilder let overlay: () -> Overlay

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      headerRow

      VStack(alignment: .leading, spacing: rowSpacing) {
        rows()
      }
      .animation(.easeOut(duration: 0.14), value: animationToken)
      .coordinateSpace(name: coordinateSpaceName)
      .onPreferenceChange(ProjectDetailTaskRowFramePreferenceKey.self) { rowFrames in
        onRowFramesChange(rowFrames)
      }
      .overlay(alignment: .topLeading) {
        overlay()
      }
    }
  }

  private var headerRow: some View {
    HStack(spacing: 8) {
      Button(action: onCycleOrdering) {
        HStack(spacing: 6) {
          ProjectDetailTaskOrderingIndicator(mode: orderingMode)

          Text("진행")
            .font(sectionFont(size: 18, weight: .bold))
            .foregroundStyle(.primary)
        }
      }
      .buttonStyle(.plain)

      Button(action: onAppendTask) {
        Image(systemName: "plus")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary.opacity(0.92))
          .frame(width: 20, height: 20)
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(Color.secondary.opacity(0.08))
          )
      }
      .buttonStyle(.plain)

      Spacer(minLength: 0)

      HStack(spacing: 6) {
        Text("완료 항목")
          .font(sectionFont(size: 11, weight: .medium))
          .foregroundStyle(.secondary)

        Toggle(
          "",
          isOn: Binding(
            get: { showsCompletedTasks },
            set: onToggleShowsCompletedTasks
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
      }
    }
  }

  private func sectionFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    NoteTypography.font(size: size, weight: weight)
  }
}

private struct ProjectDetailTaskOrderingIndicator: View {
  let mode: BlockChildOrderingMode

  var body: some View {
    switch mode {
    case .manual:
      Circle()
        .fill(Color.secondary.opacity(0.82))
        .frame(width: 5, height: 5)
    case .dateAscending:
      Image(systemName: "arrow.down")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
    case .dateDescending:
      Image(systemName: "arrow.up")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
    }
  }
}

struct ProjectDetailTaskRowFramePreferenceKey: PreferenceKey {
  static let defaultValue: [UUID: CGRect] = [:]

  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}
