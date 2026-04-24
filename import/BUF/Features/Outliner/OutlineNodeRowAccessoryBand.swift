import SwiftUI

enum OutlineNodeReminderConflictAction: Equatable {
  case keepLocal
  case adoptRemote
  case openDiff
}

struct OutlineNodeReminderConflictSurface: Equatable {
  let ownerLabel: String
  let excerpt: String
  let diffPreview: String?
  let isDiffExpanded: Bool
  let actionsEnabled: Bool
  let isBusy: Bool
}

struct OutlineNodeRowAccessoryBand: View {
  let leadingAccessoryX: CGFloat
  let isFocused: Bool
  let isTask: Bool
  let reminderMetadata: ReminderMetadataSnapshot
  let reminderReadOnlySurface: ReminderSyncReadOnlySurface?
  let reminderConflictSurface: OutlineNodeReminderConflictSurface?
  let isReminderDrawerOpen: Bool
  let referenceSuggestions: [OutlineBlockReferenceSuggestion]
  let attachments: [OutlineNodeAttachment]
  let onToggleReminderDrawer: () -> Void
  let onReminderAction: (OutlinerReminderEditorAction) -> Void
  let onResolveReminderConflict: (OutlineNodeReminderConflictAction) -> Void
  let onInsertReferenceSuggestion: (OutlineBlockReferenceSuggestion) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let reminderConflictSurface, isTask {
        HStack(spacing: 0) {
          Spacer()
            .frame(width: leadingAccessoryX)
          OutlineNodeReminderConflictCard(
            surface: reminderConflictSurface,
            onResolve: onResolveReminderConflict
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 6)
      }

      if isFocused && isTask {
        HStack(spacing: 0) {
          Spacer()
            .frame(width: leadingAccessoryX)
          OutlineNodeReminderInlineEditor(
            metadata: reminderMetadata,
            isDrawerOpen: isReminderDrawerOpen,
            onToggleDrawer: onToggleReminderDrawer,
            onApplyDuePreset: { preset in
              onReminderAction(.applyDuePreset(preset))
            },
            onClearDue: {
              onReminderAction(.clearDue)
            },
            onSetDueDate: { date, hasExplicitTime in
              onReminderAction(.setDue(date, hasExplicitTime: hasExplicitTime))
            },
            onSetRecurrence: { recurrence in
              onReminderAction(.setRecurrence(recurrence))
            },
            onCycleRecurrence: {
              onReminderAction(.cycleRecurrence)
            },
            onSetPriority: { priority in
              onReminderAction(.setPriority(priority))
            },
            onCyclePriority: {
              onReminderAction(.cyclePriority)
            }
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 6)

        if let reminderReadOnlySurface {
          HStack(spacing: 0) {
            Spacer()
              .frame(width: leadingAccessoryX)
            OutlineNodeReminderReadOnlyCard(surface: reminderReadOnlySurface)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.bottom, 6)
        }

      }

      if isFocused && !referenceSuggestions.isEmpty {
        HStack(spacing: 0) {
          Spacer()
            .frame(width: leadingAccessoryX)
          VStack(alignment: .leading, spacing: 0) {
            ForEach(referenceSuggestions) { suggestion in
              Button(action: {
                onInsertReferenceSuggestion(suggestion)
              }) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(suggestion.displayTitle)
                    .font(.sandoll(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                  Text(suggestion.contextText)
                    .font(.sandoll(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
              }
              .buttonStyle(.plain)
              if suggestion.id != referenceSuggestions.last?.id {
                Divider()
              }
            }
          }
          .background(Color(NSColor.windowBackgroundColor))
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.bottom, 6)
      }

      if !attachments.isEmpty {
        HStack(spacing: 4) {
          Spacer()
            .frame(width: leadingAccessoryX)
          ForEach(attachments) { attachment in
            HStack(spacing: 2) {
              Image(systemName: "paperclip")
                .font(.system(size: 9))
              Text(attachment.fileName)
                .font(.sandoll(size: 10))
                .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(3)
          }
        }
        .padding(.bottom, 2)
      }
    }
  }
}

private struct OutlineNodeReminderConflictCard: View {
  let surface: OutlineNodeReminderConflictSurface
  let onResolve: (OutlineNodeReminderConflictAction) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color(red: 0.76, green: 0.35, blue: 0.12))

        VStack(alignment: .leading, spacing: 4) {
          Text("리마인더 conflict")
            .font(.sandoll(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
          Text(surface.excerpt)
            .font(.sandoll(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)

        Text("owner: \(surface.ownerLabel)")
          .font(.sandoll(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.secondary.opacity(0.08))
          .clipShape(Capsule())
      }

      HStack(spacing: 8) {
        conflictActionButton(
          title: "로컬 유지",
          action: .keepLocal,
          fill: Color(red: 0.84, green: 0.92, blue: 0.85),
          isEnabled: surface.actionsEnabled
        )
        conflictActionButton(
          title: "원격 채택",
          action: .adoptRemote,
          fill: Color(red: 0.88, green: 0.92, blue: 0.99),
          isEnabled: surface.actionsEnabled
        )
        conflictActionButton(
          title: surface.isDiffExpanded ? "변경 닫기" : "변경 보기",
          action: .openDiff,
          fill: Color.secondary.opacity(0.12),
          isEnabled: true
        )
      }

      if surface.isDiffExpanded, let diffPreview = surface.diffPreview {
        Text(diffPreview)
          .font(.system(size: 11, weight: .regular, design: .monospaced))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.white.opacity(0.55))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      if !surface.actionsEnabled {
        Text("owner project에서만 conflict를 해제할 수 있습니다.")
          .font(.sandoll(size: 10))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(red: 0.99, green: 0.95, blue: 0.90))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color(red: 0.84, green: 0.62, blue: 0.42).opacity(0.55), lineWidth: 1)
    )
  }

  @ViewBuilder
  private func conflictActionButton(
    title: String,
    action: OutlineNodeReminderConflictAction,
    fill: Color,
    isEnabled: Bool
  ) -> some View {
    Button(title) {
      onResolve(action)
    }
    .buttonStyle(.plain)
    .font(.sandoll(size: 11, weight: .semibold))
    .foregroundStyle(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(fill)
    )
    .opacity(isEnabled ? 1 : 0.55)
    .disabled(!isEnabled || surface.isBusy)
  }
}

private struct OutlineNodeReminderReadOnlyCard: View {
  let surface: ReminderSyncReadOnlySurface

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("리마인더 read-only")
        .font(.sandoll(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 6) {
        readOnlyRow(icon: "location", label: "위치", value: surface.locationSummary)
        readOnlyRow(icon: "person.2", label: "공유", value: surface.sharingSummary)
        readOnlyRow(icon: "person.crop.circle", label: "담당자", value: surface.assigneeSummary)
        readOnlyRow(icon: "tag", label: "태그", value: surface.tagSummary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.secondary.opacity(0.07))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
    )
  }

  @ViewBuilder
  private func readOnlyRow(icon: String, label: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 14)
      Text(label)
        .font(.sandoll(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .leading)
      Text(value)
        .font(.sandoll(size: 11))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
