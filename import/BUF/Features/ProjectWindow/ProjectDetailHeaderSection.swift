import SwiftUI

@MainActor
final class ProjectDetailHeaderControlCoordinator: ObservableObject {
  enum Action {
    case archiveProject
    case deleteProject
    case detach
    case close
  }

  @Published private(set) var requestToken = UUID()
  private(set) var requestedAction: Action?

  func request(_ action: Action) {
    requestedAction = action
    requestToken = UUID()
  }

  func consumeRequestedAction() -> Action? {
    defer { requestedAction = nil }
    return requestedAction
  }
}

struct ProjectDetailHeaderSection<TitleContent: View, MetadataContent: View>: View {
  private let titleVerticalLift: CGFloat = 50
  private let metadataVerticalLift: CGFloat = 30

  let breadcrumbTitle: String
  let trailingReservedWidth: CGFloat
  @ViewBuilder let titleContent: () -> TitleContent
  @ViewBuilder let metadataContent: () -> MetadataContent

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if !breadcrumbTitle.isEmpty {
        Text(breadcrumbTitle)
          .font(sectionFont(size: 11.5, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      titleContent()
        .padding(.trailing, trailingReservedWidth)
        .offset(y: -titleVerticalLift)

      metadataContent()
        .offset(y: -metadataVerticalLift)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func sectionFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    NoteTypography.font(size: size, weight: weight)
  }
}

private enum ProjectDetailFloatingControlMetrics {
  static let controlScale: CGFloat = 0.77
  static let controlHitSize: CGFloat = 34
  static var controlFrameSize: CGFloat { 32 * controlScale }
  static var controlCornerRadius: CGFloat { 9 * controlScale }
}

struct ProjectDetailFloatingControlLabel: View {
  let systemName: String
  let isHovered: Bool

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 15 * ProjectDetailFloatingControlMetrics.controlScale, weight: .semibold))
      .foregroundStyle(.secondary.opacity(0.92))
      .frame(
        width: ProjectDetailFloatingControlMetrics.controlFrameSize,
        height: ProjectDetailFloatingControlMetrics.controlFrameSize
      )
      .frame(
        width: ProjectDetailFloatingControlMetrics.controlHitSize,
        height: ProjectDetailFloatingControlMetrics.controlHitSize
      )
      .background(
        RoundedRectangle(
          cornerRadius: ProjectDetailFloatingControlMetrics.controlCornerRadius,
          style: .continuous
        )
        .fill(Color.secondary.opacity(isHovered ? 0.14 : 0.08))
      )
      .contentShape(
        RoundedRectangle(
          cornerRadius: ProjectDetailFloatingControlMetrics.controlCornerRadius,
          style: .continuous
        )
      )
  }
}

struct ProjectDetailFloatingControlButton: View {
  @State private var isHovered = false

  let systemName: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ProjectDetailFloatingControlLabel(systemName: systemName, isHovered: isHovered)
    }
    .buttonStyle(.plain)
    .contentShape(
      RoundedRectangle(
        cornerRadius: ProjectDetailFloatingControlMetrics.controlCornerRadius,
        style: .continuous
      )
    )
    .onHover { isHovered = $0 }
  }
}

private struct ProjectDetailFloatingContextMenuButton: View {
  @State private var isHovered = false

  let systemName: String
  let onArchiveProject: (() -> Void)?
  let onDeleteProject: (() -> Void)?

  var body: some View {
    Menu {
      if let onArchiveProject {
        Button("이 프로젝트 아카이브", action: onArchiveProject)
      }

      if let onDeleteProject {
        if onArchiveProject != nil {
          Divider()
        }
        Button("삭제", role: .destructive, action: onDeleteProject)
      }
    } label: {
      ProjectDetailFloatingControlLabel(systemName: systemName, isHovered: isHovered)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { isHovered = $0 }
  }
}

struct ProjectDetailHeaderControlRail: View {

  let onArchiveProject: (() -> Void)?
  let onDeleteProject: (() -> Void)?
  let onDetach: (() -> Void)?
  let onClose: (() -> Void)?

  var body: some View {
    HStack(spacing: 8) {
      if showsOverflowMenu {
        ProjectDetailFloatingContextMenuButton(
          systemName: "ellipsis",
          onArchiveProject: onArchiveProject,
          onDeleteProject: onDeleteProject
        )
      }

      if let onDetach {
        ProjectDetailFloatingControlButton(systemName: "rectangle.on.rectangle", action: onDetach)
      }

      if let onClose {
        ProjectDetailFloatingControlButton(systemName: "xmark.circle", action: onClose)
      }
    }
    .fixedSize()
  }

  private var showsOverflowMenu: Bool {
    onArchiveProject != nil || onDeleteProject != nil
  }
}

struct ProjectDetailHeaderPropertyRow<Content: View>: View {
  private let metadataScale: CGFloat = 0.9

  let label: String
  let iconName: String
  let usesTint: Bool
  let titleTint: Color
  let propertyLabelWidth: CGFloat
  let leadingLabelInset: CGFloat
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 18) {
      leadingLabel
        .frame(width: propertyLabelWidth, alignment: .leading)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 0)
    }
  }

  private func rowFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    NoteTypography.font(size: size, weight: weight)
  }

  private var leadingLabel: some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: ProjectDetailSurfaceMetrics.subtleCornerRadius, style: .continuous)
        .fill((usesTint ? titleTint : Color.secondary).opacity(0.12))
        .frame(width: 22 * metadataScale, height: 22 * metadataScale)
        .overlay {
          Image(systemName: iconName)
            .font(.system(size: 11 * metadataScale, weight: .semibold))
            .foregroundStyle(usesTint ? titleTint : .secondary)
        }

      Text(label)
        .font(rowFont(size: 13.5 * metadataScale, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .padding(.leading, leadingLabelInset)
  }
}

struct ProjectDetailHeaderAttachmentRow<Content: View>: View {
  let label: String
  let iconName: String
  let propertyLabelWidth: CGFloat
  let metadataScale: CGFloat
  let leadingLabelInset: CGFloat
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(alignment: .top, spacing: 18) {
      leadingLabel
        .frame(width: propertyLabelWidth, alignment: .leading)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var leadingLabel: some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: ProjectDetailSurfaceMetrics.subtleCornerRadius, style: .continuous)
        .fill(Color.secondary.opacity(0.12))
        .frame(width: 22 * metadataScale, height: 22 * metadataScale)
        .overlay {
          Image(systemName: iconName)
            .font(.system(size: 11 * metadataScale, weight: .semibold))
            .foregroundStyle(.secondary)
        }

      Text(label)
        .font(NoteTypography.font(size: 13.5 * metadataScale, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .padding(.leading, leadingLabelInset)
  }
}
