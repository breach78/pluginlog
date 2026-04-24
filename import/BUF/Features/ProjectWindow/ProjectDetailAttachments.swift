import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct ProjectDetailAttachmentDropDelegate: DropDelegate {
  let onValidate: ((DropInfo) -> Bool)?
  let onEntered: (() -> Void)?
  let onExited: (() -> Void)?
  let onPerformDrop: (DropInfo) -> Bool

  init(
    onValidate: ((DropInfo) -> Bool)? = nil,
    onEntered: (() -> Void)? = nil,
    onExited: (() -> Void)? = nil,
    onPerformDrop: @escaping (DropInfo) -> Bool = { _ in false }
  ) {
    self.onValidate = onValidate
    self.onEntered = onEntered
    self.onExited = onExited
    self.onPerformDrop = onPerformDrop
  }

  func validateDrop(info: DropInfo) -> Bool {
    onValidate?(info) ?? true
  }

  func dropEntered(info: DropInfo) {
    onEntered?()
  }

  func dropExited(info: DropInfo) {
    onExited?()
  }

  func performDrop(info: DropInfo) -> Bool {
    onPerformDrop(info)
  }
}

struct ProjectDetailAttachmentSection: View {
  let attachments: [BlockAttachmentPreviewSnapshot]
  let tint: Color
  let accentColor: Color
  let isCompactTaskAttachment: Bool
  let showsChrome: Bool
  let showsImportControl: Bool
  let showsDropHint: Bool
  let isDropTargeted: Bool
  let scrollAnchorID: String?
  let taskSurfacePosition: TaskExpandedSurfacePosition?
  let dropTypes: [String]
  let dropDelegate: ProjectDetailAttachmentDropDelegate
  let onImport: () -> Void
  let onOpen: (BlockAttachmentPreviewSnapshot) -> Void
  let onRevealInFinder: (BlockAttachmentPreviewSnapshot) -> Void
  let onDelete: (BlockAttachmentPreviewSnapshot) -> Void
  let dragItemProvider: (BlockAttachmentPreviewSnapshot) -> NSItemProvider?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if showsChrome {
        HStack(spacing: 8) {
          sectionTitle("첨부")

          countChip("\(attachments.count)")

          if showsImportControl {
            Button(action: onImport) {
              Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.9))
                .frame(width: 18, height: 18)
                .background(
                  RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
          }

          if isDropTargeted, showsDropHint {
            Text("파일을 놓아 추가")
              .font(sectionFont(size: 11.5, weight: .medium))
              .foregroundStyle(accentColor)
          }

          Spacer(minLength: 0)
        }
      }

      ProjectDetailAttachmentList(
        attachments: attachments,
        tint: tint,
        isCompactTaskAttachment: isCompactTaskAttachment,
        taskSurfacePosition: taskSurfacePosition,
        rowSpacing: nil,
        onOpen: onOpen,
        onRevealInFinder: onRevealInFinder,
        onDelete: onDelete,
        dragItemProvider: dragItemProvider
      )
    }
    .id(scrollAnchorID)
    .padding(.horizontal, isDropTargeted ? 10 : 0)
    .padding(.vertical, isDropTargeted ? 10 : 0)
    .background {
      if isDropTargeted {
        RoundedRectangle(cornerRadius: dropSurfaceCornerRadius, style: .circular)
          .fill(accentColor.opacity(0.06))
      }
    }
    .overlay {
      if isDropTargeted {
        RoundedRectangle(cornerRadius: dropSurfaceCornerRadius, style: .circular)
          .stroke(accentColor.opacity(0.24), lineWidth: 1)
      }
    }
    .onDrop(of: dropTypes, delegate: dropDelegate)
  }

  private var dropSurfaceCornerRadius: CGFloat {
    ProjectDetailSurfaceMetrics.subtleCornerRadius
  }

  private func sectionFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    NoteTypography.font(size: size, weight: weight)
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text)
      .font(sectionFont(size: 11.5, weight: .bold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .tracking(0.3)
  }

  private func countChip(_ text: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: "paperclip")
        .font(.system(size: 10.5, weight: .semibold))
      Text(text)
        .lineLimit(1)
    }
    .font(sectionFont(size: 11.5, weight: .medium))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Capsule(style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }
}

struct ProjectDetailAttachmentList: View {
  let attachments: [BlockAttachmentPreviewSnapshot]
  let tint: Color
  let isCompactTaskAttachment: Bool
  let taskSurfacePosition: TaskExpandedSurfacePosition?
  let rowSpacing: CGFloat?
  let onOpen: (BlockAttachmentPreviewSnapshot) -> Void
  let onRevealInFinder: (BlockAttachmentPreviewSnapshot) -> Void
  let onDelete: (BlockAttachmentPreviewSnapshot) -> Void
  let dragItemProvider: (BlockAttachmentPreviewSnapshot) -> NSItemProvider?

  var body: some View {
    VStack(alignment: .leading, spacing: resolvedRowSpacing) {
      ForEach(attachments) { attachment in
        attachmentChip(for: attachment)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(taskAttachmentBackground)
  }

  private var resolvedRowSpacing: CGFloat {
    rowSpacing ?? (isCompactTaskAttachment ? 0 : 8)
  }

  @ViewBuilder
  private func attachmentChip(for attachment: BlockAttachmentPreviewSnapshot) -> some View {
    let chip = attachmentChipBody(for: attachment)
      .contextMenu {
        Button("열기") {
          onOpen(attachment)
        }
        Button("Finder에서 보기") {
          onRevealInFinder(attachment)
        }
        Button("삭제", role: .destructive) {
          onDelete(attachment)
        }
      }

    chip.onDrag {
      dragItemProvider(attachment) ?? NSItemProvider()
    }
  }

  private func attachmentChipBody(for attachment: BlockAttachmentPreviewSnapshot) -> some View {
    HStack(spacing: isCompactTaskAttachment ? 8 : 10) {
      Button {
        onOpen(attachment)
      } label: {
        HStack(spacing: isCompactTaskAttachment ? 6 : 8) {
          Image(systemName: attachmentIconName(mimeType: attachment.mimeType))
            .font(.system(size: isCompactTaskAttachment ? 10 : 11, weight: .semibold))
            .foregroundStyle(tint.opacity(0.95))
            .frame(
              width: isCompactTaskAttachment ? 14 : 16,
              height: isCompactTaskAttachment ? 14 : 16
            )
            .background(
              RoundedRectangle(
                cornerRadius: ProjectDetailSurfaceMetrics.subtleCornerRadius,
                style: .continuous
              )
              .fill(tint.opacity(0.12))
            )

          attachmentSummaryText(attachment)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .buttonStyle(.plain)

      Button {
        onDelete(attachment)
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(.secondary.opacity(0.82))
          .frame(width: 12, height: 12)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("첨부 삭제")
    }
    .frame(
      maxWidth: .infinity,
      minHeight: isCompactTaskAttachment ? 26 : 0,
      alignment: .leading
    )
    .padding(.horizontal, isCompactTaskAttachment ? 8 : 10)
    .padding(.vertical, isCompactTaskAttachment ? 4.5 : 4)
    .background(chipBackground)
  }

  @ViewBuilder
  private var taskAttachmentBackground: some View {
    if isCompactTaskAttachment, let taskSurfacePosition {
      UnevenRoundedRectangle(
        cornerRadii: taskSurfacePosition.cornerRadii,
        style: .continuous
      )
      .fill(Color.secondary.opacity(0.05))
    }
  }

  @ViewBuilder
  private var chipBackground: some View {
    if !isCompactTaskAttachment {
      RoundedRectangle(
        cornerRadius: ProjectDetailSurfaceMetrics.subtleCornerRadius,
        style: .continuous
      )
      .fill(Color.secondary.opacity(0.05))
    }
  }

  private func attachmentSummaryText(_ attachment: BlockAttachmentPreviewSnapshot) -> some View {
    (
      Text(attachment.originalFilename)
        .foregroundStyle(.primary)
      + Text(" · \(attachmentMetadataText(attachment))")
        .foregroundStyle(.secondary)
    )
    .font(sectionFont(size: isCompactTaskAttachment ? 10 : 11, weight: .medium))
    .lineLimit(1)
  }

  private func attachmentIconName(mimeType: String) -> String {
    if mimeType.hasPrefix("image/") {
      return "photo"
    }
    if mimeType == "application/pdf" {
      return "doc.richtext"
    }
    return "paperclip"
  }

  private func attachmentMetadataText(_ attachment: BlockAttachmentPreviewSnapshot) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    let byteSize = formatter.string(fromByteCount: attachment.byteSize)

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ko_KR")
    dateFormatter.setLocalizedDateFormatFromTemplate("M.d")
    let updatedAt = dateFormatter.string(from: attachment.updatedAt)
    return "\(byteSize) · \(updatedAt)"
  }

  private func sectionFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    NoteTypography.font(size: size, weight: weight)
  }
}
