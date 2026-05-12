import AppKit
import SwiftUI

extension ScheduleBoardView {
  var scheduleViewportSize: CGSize {
    scrollViewportState.scrollView?.contentView.bounds.size
      ?? CGSize(width: boardWidth, height: boardHeight)
  }

  func scheduleTaskCompletionGlyph(
    isCompleted: Bool,
    isRecurring: Bool,
    color: Color,
    isSelected: Bool,
    compact: Bool,
    isPreparationSlot: Bool = false
  ) -> some View {
    let frameSize: CGFloat =
      compact
        ? ScheduleUITokens.ScheduleItem.compactCompletionGlyphSize
        : ScheduleUITokens.ScheduleItem.regularCompletionGlyphSize
    let strokeWidth: CGFloat =
      compact
        ? ScheduleUITokens.ScheduleItem.compactCompletionStrokeWidth
        : ScheduleUITokens.ScheduleItem.regularCompletionStrokeWidth
    let arrowFontSize: CGFloat =
      compact
        ? ScheduleUITokens.ScheduleItem.compactRecurringArrowFontSize
        : ScheduleUITokens.ScheduleItem.regularRecurringArrowFontSize
    let glyphColor: Color = isSelected ? .white : color

    return ZStack {
      if isCompleted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(
            size: compact
              ? ScheduleUITokens.ScheduleItem.compactCompletionIconFontSize
              : ScheduleUITokens.ScheduleItem.regularCompletionIconFontSize,
            weight: .semibold
          ))
          .foregroundStyle(glyphColor)
      } else {
        taskOutlineGlyph(
          color: glyphColor,
          strokeWidth: strokeWidth,
          showsPreparationIndicator: isPreparationSlot
        )

        if isRecurring {
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: arrowFontSize, weight: .bold))
            .foregroundStyle(glyphColor)
        }
      }
    }
    .frame(width: frameSize, height: frameSize)
  }

  func taskOutlineGlyph(
    color: Color,
    strokeWidth: CGFloat,
    showsPreparationIndicator: Bool
  ) -> some View {
    Group {
      if showsPreparationIndicator {
        ScheduleCircleStrokeOverlay(
          color: color.opacity(ScheduleUITokens.ScheduleItem.preparationOutlineOpacity),
          lineWidth: strokeWidth,
          lineCap: .round,
          dash: [0.1, 3.15]
        )
      } else {
        ScheduleCircleStrokeOverlay(
          color: color.opacity(ScheduleUITokens.ScheduleItem.outlineOpacity),
          lineWidth: strokeWidth
        )
      }
    }
  }

  @ViewBuilder
  func scheduleTaskContextMenu(_ taskDescriptor: WorkspaceScheduleTaskDescriptor) -> some View {
    if !taskDescriptor.taskRow.isLocalCompletedRecurringOccurrence {
      Button(role: .destructive) {
        deleteScheduleTask(taskDescriptor.taskRow.id)
      } label: {
        Label("삭제", systemImage: "trash")
      }
    }
  }

  @ViewBuilder
  func scheduleEventContextMenu(_ event: ScheduleCalendarEvent) -> some View {
    if event.canEditTiming {
      if event.isRecurring {
        Button(role: .destructive) {
          deleteScheduleCalendarEvent(event, scope: .thisEvent)
        } label: {
          Label("이 일정만 삭제", systemImage: "trash")
        }

        Button(role: .destructive) {
          deleteScheduleCalendarEvent(event, scope: .futureEvents)
        } label: {
          Label("이후 반복 일정 삭제", systemImage: "trash")
        }
      } else {
        Button(role: .destructive) {
          deleteScheduleCalendarEvent(event, scope: .thisEvent)
        } label: {
          Label("삭제", systemImage: "trash")
        }
      }
    }
  }

  func completionToggle(
    taskDescriptor: WorkspaceScheduleTaskDescriptor,
    color: Color,
    isSelected: Bool,
    compact: Bool,
    recordedAt: Date? = nil,
    isPreparationSlot: Bool = false,
    targetCompletedWorkUnits: Int? = nil
  ) -> some View {
    let taskRow = taskDescriptor.taskRow
    let isCompleted = effectiveScheduleTaskIsCompleted(taskRow)
    return Button {
      suppressTaskTap(for: TaskTapSuppressionPolicy.completionControlDuration)
      if let targetCompletedWorkUnits {
        updateSchedulePlannedWorkProgress(
          taskID: taskRow.id,
          projectID: taskDescriptor.projectID,
          targetCompletedUnits: targetCompletedWorkUnits,
          completedOn: recordedAt ?? .now,
          registerUndo: true
        )
      } else {
        updateScheduleTaskCompletion(
          taskID: taskRow.id,
          projectID: taskDescriptor.projectID,
          isCompleted: !isCompleted,
          completionDate: isCompleted ? nil : .now,
          registerUndo: true
        )
      }
    } label: {
      scheduleTaskCompletionGlyph(
        isCompleted: isCompleted,
        isRecurring: WorkspaceTaskScheduleEventStore.isRecurring(taskRow),
        color: color,
        isSelected: isSelected,
        compact: compact,
        isPreparationSlot: isPreparationSlot
      )
      .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .simultaneousGesture(
      taskCompletionPressGesture {
        suppressTaskTap(for: TaskTapSuppressionPolicy.completionControlDuration)
      }
    )
    .allowsHitTesting(!taskRow.isLocalCompletedRecurringOccurrence)
    .help(
      targetCompletedWorkUnits == nil
        ? (isCompleted ? "완료 취소" : "완료")
        : "예상 작업 체크"
    )
  }

  func timeRangeLabel(startMinute: Int, durationMinutes: Int) -> String {
    let endMinute = min(24 * 60, startMinute + durationMinutes)
    return "\(timeLabel(minute: startMinute))–\(timeLabel(minute: endMinute))"
  }

  func scheduleDragPreviewLabel(for preview: ScheduleInteractionPreview) -> String {
    guard let timeMinutes = preview.timeMinutes else { return "올데이" }
    let durationMinutes = preview.durationMinutes ?? timedMinimumDuration
    return timeRangeLabel(startMinute: timeMinutes, durationMinutes: durationMinutes)
  }

  func scheduleItemTitleFont(weight: Font.Weight = .semibold) -> Font {
    scheduleItemFont(ScheduleItemVisualStyle.titleFontSize, weight: weight)
  }

  func scheduleItemSupplementalFont(weight: Font.Weight = .medium) -> Font {
    scheduleItemFont(ScheduleItemVisualStyle.supplementalFontSize, weight: weight)
  }

  func scheduleItemSupplementalFont(
    weight: Font.Weight,
    design: Font.Design
  ) -> Font {
    scheduleItemFont(ScheduleItemVisualStyle.supplementalFontSize, weight: weight, design: design)
  }

  func scheduleTaskPrimaryTextColor(isSelected: Bool, isCompleted: Bool) -> Color {
    if isSelected {
      return isCompleted
        ? Color.white.opacity(ScheduleUITokens.ScheduleItem.selectedCompletedTitleOpacity)
        : .white
    }
    return isCompleted ? .secondary : .primary
  }

  func scheduleTaskSecondaryTextColor(isSelected: Bool) -> Color {
    isSelected
      ? Color.white.opacity(
        ScheduleUITokens.ScheduleItem.selectedSecondaryTextBaseOpacity
          * ScheduleItemVisualStyle.secondaryTextOpacityMultiplier
      )
      : Color.secondary.opacity(ScheduleItemVisualStyle.secondaryTextOpacityMultiplier)
  }

  func scheduleEventSecondaryTextColor(isBackgroundCalendar: Bool) -> Color {
    let baseOpacity =
      isBackgroundCalendar
        ? ScheduleUITokens.ScheduleItem.backgroundCalendarSecondaryTextBaseOpacity
        : 1.0
    return Color.secondary.opacity(
      baseOpacity * ScheduleItemVisualStyle.secondaryTextOpacityMultiplier
    )
  }

  @ViewBuilder
  func scheduleTaskTitleRow(
    _ title: String,
    taskDescriptor: WorkspaceScheduleTaskDescriptor,
    titleColor: Color,
    metadataColor: Color,
    lineLimit: Int
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(title)
        .font(scheduleItemTitleFont())
        .foregroundStyle(titleColor)
        .lineLimit(lineLimit)

      scheduleTaskMetadataIndicators(for: taskDescriptor, color: metadataColor)
    }
  }

  @ViewBuilder
  func scheduleEventTitleRow(
    _ title: String,
    event: ScheduleCalendarEvent,
    titleColor: Color,
    metadataColor: Color,
    lineLimit: Int
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(title)
        .font(scheduleItemTitleFont())
        .foregroundStyle(titleColor)
        .lineLimit(lineLimit)

      scheduleEventMetadataIndicators(for: event, color: metadataColor)
    }
  }

  @ViewBuilder
  func scheduleTaskMetadataIndicators(
    for taskDescriptor: WorkspaceScheduleTaskDescriptor,
    color: Color
  ) -> some View {
    scheduleMetadataIndicators(
      hasNote: taskDescriptor.taskRow.hasReminderNoteContent,
      attachmentCount: max(0, taskDescriptor.taskRow.attachmentCount),
      color: color
    )
  }

  @ViewBuilder
  func scheduleEventMetadataIndicators(
    for event: ScheduleCalendarEvent,
    color: Color
  ) -> some View {
    scheduleMetadataIndicators(
      hasNote: hasScheduleNote(event.notes),
      attachmentCount: scheduleAttachmentLinkCount(in: event.notes),
      color: color
    )
  }

  @ViewBuilder
  private func scheduleMetadataIndicators(
    hasNote: Bool,
    attachmentCount: Int,
    color: Color
  ) -> some View {
    if hasNote || attachmentCount > 0 {
      HStack(spacing: 3) {
        if hasNote {
          Image(systemName: "note.text")
            .help("노트 있음")
        }
        if attachmentCount > 0 {
          Image(systemName: "paperclip")
            .help(attachmentCount > 1 ? "첨부파일 \(attachmentCount)개" : "첨부파일 있음")
        }
      }
      .font(scheduleItemSupplementalFont(weight: .semibold))
      .foregroundStyle(color)
      .imageScale(.small)
      .lineLimit(1)
    }
  }

  @ViewBuilder
  func scheduleTaskSupplementalRow(
    timeLabel: String?,
    textColor: Color
  ) -> some View {
    if let timeLabel {
      Text(timeLabel)
        .font(scheduleItemSupplementalFont(weight: .semibold, design: .monospaced))
        .foregroundStyle(textColor)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  func scheduleEventSupplementalRow(
    timeLabel: String?,
    textColor: Color
  ) -> some View {
    if let timeLabel {
      Text(timeLabel)
        .font(scheduleItemSupplementalFont(weight: .semibold, design: .monospaced))
        .foregroundStyle(textColor)
        .lineLimit(1)
    }
  }

  private func hasScheduleNote(_ noteText: String) -> Bool {
    !TaskEditAttachmentService.noteTextByRemovingAttachmentLinks(from: noteText)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
  }

  private func scheduleAttachmentLinkCount(in noteText: String) -> Int {
    TaskEditAttachmentService.attachmentLinkCount(in: noteText)
  }

  func scheduleTimedTitleLineLimit(
    for blockHeight: CGFloat,
    density: ScheduleTimedBlockDensity
  ) -> Int {
    switch density {
    case .compact:
      return 1
    case .standard:
      return max(1, min(6, Int(floor((blockHeight - 16) / 17))))
    case .expanded:
      return max(2, min(8, Int(floor((blockHeight - 20) / 16))))
    }
  }

  func scheduleTimedSupplementalLineLimit(for blockHeight: CGFloat) -> Int {
    max(1, min(3, Int(floor((blockHeight - 44) / 22))))
  }

  @ViewBuilder
  func schedulePostponeAffordanceOverlay(
    compact: Bool,
    isSelected: Bool,
    postponeAction: (() -> Void)?
  ) -> some View {
    EmptyView()
  }

  func scheduleColor(for colorHex: String?, fallback: Color = .accentColor) -> Color {
    ColorHexCodec.color(from: colorHex) ?? fallback
  }

  func dayColumnBackgroundColor(
    for day: Date,
    section: ScheduleDayBackgroundSection
  ) -> Color {
    let isToday = calendar.isDate(day, inSameDayAs: today)
    let isWeekend = calendar.isDateInWeekend(day)

    switch section {
    case .header:
      if isToday {
        return Color.accentColor.opacity(ScheduleUITokens.ScheduleItem.todayHeaderBackgroundOpacity)
      }
      if isWeekend {
        return Color.primary.opacity(ScheduleUITokens.ScheduleItem.weekendHeaderBackgroundOpacity)
      }
      return Color(nsColor: .windowBackgroundColor)
    case .allDayRail:
      return Color(nsColor: .windowBackgroundColor)
    case .timeline:
      if isToday {
        return Color.accentColor.opacity(ScheduleUITokens.ScheduleItem.todayTimelineBackgroundOpacity)
      }
      if isWeekend {
        return Color.primary.opacity(ScheduleUITokens.ScheduleItem.weekendTimelineBackgroundOpacity)
      }
      return .clear
    }
  }

  func timedBlockDensity(for blockHeight: CGFloat) -> ScheduleTimedBlockDensity {
    if blockHeight < 46 {
      return .compact
    }
    if blockHeight < 92 {
      return .standard
    }
    return .expanded
  }

  func timeLabel(minute: Int) -> String {
    let boundedMinute = max(0, min(24 * 60, minute))
    let hour = boundedMinute / 60
    let minuteValue = boundedMinute % 60
    return String(format: "%02d:%02d", hour, minuteValue)
  }
}
