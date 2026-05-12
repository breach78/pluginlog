import AppKit
import SwiftUI

extension ScheduleBoardView {
  func dragPreviewChip(
    taskDescriptor: WorkspaceScheduleTaskDescriptor,
    title: String,
    subtitle: String?,
    color: Color,
    isSelected: Bool,
    isPreparationSlot: Bool
  ) -> some View {
    taskChip(
      taskDescriptor,
      title: title,
      subtitle: subtitle,
      color: color,
      compact: true,
      isSelected: isSelected,
      isPreparationSlot: isPreparationSlot,
      targetCompletedWorkUnits: nil,
      trailingLabel: nil
    )
  }

  func dragPreviewBlock(
    taskDescriptor: WorkspaceScheduleTaskDescriptor,
    title: String,
    subtitle: String?,
    color: Color,
    isSelected: Bool,
    isPreparationSlot: Bool,
    targetCompletedWorkUnits: Int?,
    timeLabel: String?,
    blockHeight: CGFloat
  ) -> some View {
    let taskRow = taskDescriptor.taskRow
    let isCompleted = effectiveScheduleTaskIsCompleted(taskRow)
    let density = timedBlockDensity(for: blockHeight)

    return ScheduleTaskBlockSurface(
      color: color,
      isSelected: isSelected,
      isCompleted: isCompleted,
      isPreparationSlot: isPreparationSlot,
      selectionHighlightColor: selectionHighlightColor
    ) {
      scheduleTaskBlockContent(
        taskDescriptor: taskDescriptor,
        title: title,
        subtitle: subtitle,
        color: color,
        isSelected: isSelected,
        isCompleted: isCompleted,
        blockHeight: blockHeight,
        recordedAt: WorkspaceTaskScheduleEventStore.scheduledDay(for: taskRow) ?? .now,
        isPreparationSlot: isPreparationSlot,
        targetCompletedWorkUnits: targetCompletedWorkUnits,
        timeLabel: timeLabel,
        density: density
      )
    }
  }

  func dragPreviewEventChip(
    event: ScheduleCalendarEvent,
    title: String,
    subtitle: String?,
    color: Color
  ) -> some View {
    eventChip(event, title: title, subtitle: subtitle, color: color)
  }

  func dragPreviewEventBlock(
    event: ScheduleCalendarEvent,
    title: String,
    subtitle: String?,
    color: Color,
    timeLabel: String?,
    blockHeight: CGFloat,
    durationMinutes: Int
  ) -> some View {
    let density = timedBlockDensity(for: blockHeight)

    return ScheduleEventBlockSurface(color: color) {
      scheduleEventBlockContent(
        event: event,
        title: title,
        subtitle: subtitle,
        timeLabel: timeLabel,
        blockHeight: blockHeight,
        density: density,
        durationMinutes: durationMinutes,
        isBackgroundCalendar: false
      )
    }
    .overlay(alignment: .topTrailing) {
      if event.isRecurring {
        recurrenceIndicator(fontSize: ScheduleUITokens.ScheduleItem.recurrenceIndicatorFontSize)
          .padding(.top, ScheduleUITokens.ScheduleItem.recurrenceIndicatorTopPadding)
          .padding(.trailing, ScheduleUITokens.ScheduleItem.recurrenceIndicatorTrailingPadding)
      }
    }
  }

  func liftedDragGhost<Content: View>(
    frame: CGRect,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(width: frame.width, height: frame.height, alignment: .topLeading)
      .offset(x: frame.minX, y: frame.minY)
      .scaleEffect(dragGhostScale, anchor: .center)
      .opacity(dragGhostOpacity)
      .shadow(
        color: Color.black.opacity(ScheduleUITokens.Shadow.liftedGhostOpacity),
        radius: dragGhostShadowRadius,
        x: 0,
        y: dragGhostShadowYOffset
      )
      .zIndex(2000)
  }

  func dragDropTargetIndicator(
    frame: CGRect,
    color: Color,
    isAllDay: Bool,
    label: String?
  ) -> some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: isAllDay ? 8 : 6, style: .continuous)
        .fill(color.opacity(
          isAllDay
            ? ScheduleUITokens.Interaction.dropTargetAllDayFillOpacity
            : ScheduleUITokens.Interaction.dropTargetTimedFillOpacity
        ))

      ScheduleRoundedRectangleStrokeOverlay(
        cornerRadius: isAllDay ? 8 : 6,
        color: color.opacity(ScheduleUITokens.Interaction.dropTargetStrokeOpacity),
        lineWidth: 1.2,
        lineCap: .round,
        dash: [5, 4]
      )

      if let label {
        Text(label)
          .font(.system(size: ScheduleUITokens.Interaction.dropTargetLabelFontSize, weight: .semibold))
          .foregroundStyle(color.opacity(ScheduleUITokens.Interaction.dropTargetLabelForegroundOpacity))
          .lineLimit(1)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
      }
    }
    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    .offset(x: frame.minX, y: frame.minY)
    .allowsHitTesting(false)
    .zIndex(1998)
  }

  func dragSourcePlaceholder(frame: CGRect, isAllDay: Bool) -> some View {
    RoundedRectangle(cornerRadius: isAllDay ? 8 : 6, style: .continuous)
      .fill(Color(nsColor: .windowBackgroundColor).opacity(
        ScheduleUITokens.Interaction.dragSourcePlaceholderFillOpacity
      ))
      .overlay {
        ScheduleRoundedRectangleStrokeOverlay(
          cornerRadius: isAllDay ? 8 : 6,
          color: Color.primary.opacity(ScheduleUITokens.Interaction.dragSourcePlaceholderStrokeOpacity),
          lineWidth: 1
        )
      }
      .frame(width: frame.width, height: frame.height, alignment: .topLeading)
      .offset(x: frame.minX, y: frame.minY)
      .allowsHitTesting(false)
      .zIndex(1997)
  }

  func resizePreviewTaskBlock(
    taskDescriptor: WorkspaceScheduleTaskDescriptor,
    day: Date,
    color: Color,
    timeLabel: String?,
    frame: CGRect,
    isPreparationSlot: Bool,
    targetCompletedWorkUnits: Int?
  ) -> some View {
    let taskRow = taskDescriptor.taskRow
    let isCompleted = effectiveScheduleTaskIsCompleted(taskRow)
    let density = timedBlockDensity(for: frame.height)

    return ScheduleTaskBlockSurface(
      color: color,
      isSelected: true,
      isCompleted: isCompleted,
      isPreparationSlot: isPreparationSlot,
      selectionHighlightColor: selectionHighlightColor
    ) {
      scheduleTaskBlockContent(
        taskDescriptor: taskDescriptor,
        title: taskRow.title,
        subtitle: taskDescriptor.projectTitle,
        color: color,
        isSelected: true,
        isCompleted: isCompleted,
        blockHeight: frame.height,
        recordedAt: day,
        isPreparationSlot: isPreparationSlot,
        targetCompletedWorkUnits: targetCompletedWorkUnits,
        timeLabel: timeLabel,
        density: density,
        postponeAction: nil
      )
    }
    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    .offset(x: frame.minX, y: frame.minY)
    .opacity(ScheduleResizePreviewStylePolicy.targetBlockOpacity)
    .shadow(
      color: Color.black.opacity(ScheduleUITokens.Shadow.resizePreviewTaskOpacity),
      radius: ScheduleUITokens.Shadow.resizePreviewTaskRadius,
      x: 0,
      y: ScheduleUITokens.Shadow.dragPreviewYOffset
    )
    .allowsHitTesting(false)
  }

  func resizePreviewEventBlock(
    event: ScheduleCalendarEvent,
    color: Color,
    timeLabel: String?,
    durationMinutes: Int,
    frame: CGRect
  ) -> some View {
    let density = timedBlockDensity(for: frame.height)

    return ScheduleEventBlockSurface(color: color) {
      scheduleEventBlockContent(
        event: event,
        title: event.title,
        subtitle: event.calendarTitle,
        timeLabel: timeLabel,
        blockHeight: frame.height,
        density: density,
        durationMinutes: durationMinutes,
        isBackgroundCalendar: false
      )
    }
    .overlay(alignment: .topTrailing) {
      if event.isRecurring {
        recurrenceIndicator(fontSize: ScheduleUITokens.ScheduleItem.recurrenceIndicatorFontSize)
          .padding(.top, ScheduleUITokens.ScheduleItem.recurrenceIndicatorTopPadding)
          .padding(.trailing, ScheduleUITokens.ScheduleItem.recurrenceIndicatorTrailingPadding)
      }
    }
    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    .offset(x: frame.minX, y: frame.minY)
    .opacity(ScheduleResizePreviewStylePolicy.targetBlockOpacity)
    .overlay {
      ScheduleRoundedRectangleStrokeOverlay(
        cornerRadius: 6,
        color: color.opacity(ScheduleUITokens.Interaction.dropTargetStrokeOpacity),
        lineWidth: 1
      )
    }
    .shadow(
      color: Color.black.opacity(ScheduleUITokens.Shadow.resizePreviewEventOpacity),
      radius: ScheduleUITokens.Shadow.resizePreviewEventRadius,
      x: 0,
      y: ScheduleUITokens.Shadow.dragPreviewYOffset
    )
    .allowsHitTesting(false)
  }

  func recurrenceIndicator(fontSize: CGFloat) -> some View {
    Image(systemName: "repeat")
      .font(.system(size: fontSize, weight: .semibold))
      .foregroundStyle(.secondary)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  func resizeHandle(
    for taskDescriptor: WorkspaceScheduleTaskDescriptor,
    entryID: String,
    day: Date,
    originalTimeMinutes: Int,
    durationMinutes: Int,
    edge: ScheduleResizeEdge,
    originalViewportFrame: CGRect,
    visibleDay: Date,
    xOffsetWithinDay: CGFloat,
    isPreparationSlot: Bool = false,
    targetCompletedWorkUnits: Int? = nil
  ) -> some View {
    let hitZoneHeight = min(10, max(7, originalViewportFrame.height * 0.24))
    let edgeOffset = min(5, max(4, hitZoneHeight * 0.35 + 2))
    let leadingExclusionWidth: CGFloat = isPreparationSlot ? 28 : 0

    HStack(spacing: 0) {
      if leadingExclusionWidth > 0 {
        Color.clear
          .frame(width: leadingExclusionWidth)
      }

      Rectangle()
        .fill(Color.clear)
        .frame(maxWidth: .infinity)
        .overlay {
          if isActive {
            ScheduleCursorRegion(cursor: .resizeUpDown)
          }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
          taskResizeGesture(
            for: taskDescriptor,
            entryID: entryID,
            originalDay: day,
            originalTimeMinutes: originalTimeMinutes,
            originalDurationMinutes: durationMinutes,
            edge: edge,
            originalViewportFrame: originalViewportFrame,
            visibleDay: visibleDay,
            xOffsetWithinDay: xOffsetWithinDay,
            isPreparationSlot: isPreparationSlot,
            targetCompletedWorkUnits: targetCompletedWorkUnits
          )
        )
        .help(edge == .start ? "시작 시간 조절" : "종료 시간 조절")
    }
    .frame(maxWidth: .infinity)
    .frame(height: hitZoneHeight)
    .offset(y: edge == .start ? -edgeOffset : edgeOffset)
  }

  @ViewBuilder
  func eventResizeHandle(
    for event: ScheduleCalendarEvent,
    edge: ScheduleResizeEdge,
    originalDay: Date,
    originalTimeMinutes: Int,
    originalDurationMinutes: Int,
    originalViewportFrame: CGRect,
    visibleDay: Date,
    xOffsetWithinDay: CGFloat
  ) -> some View {
    let hitZoneHeight = min(10, max(7, originalViewportFrame.height * 0.24))
    let edgeOffset = min(5, max(4, hitZoneHeight * 0.35 + 2))

    Rectangle()
      .fill(Color.clear)
      .frame(maxWidth: .infinity)
      .frame(height: hitZoneHeight)
      .offset(y: edge == .start ? -edgeOffset : edgeOffset)
      .overlay {
        if isActive {
          ScheduleCursorRegion(cursor: .resizeUpDown)
        }
      }
      .contentShape(Rectangle())
      .highPriorityGesture(
        eventResizeGesture(
          for: event,
          originalDay: originalDay,
          originalTimeMinutes: originalTimeMinutes,
          originalDurationMinutes: originalDurationMinutes,
          edge: edge,
          originalViewportFrame: originalViewportFrame,
          visibleDay: visibleDay,
          xOffsetWithinDay: xOffsetWithinDay
        )
      )
      .help(edge == .start ? "시작 시간 조절" : "종료 시간 조절")
  }

  func floatingInteractionOverlay() -> some View {
    ZStack(alignment: .topLeading) {
      ZStack(alignment: .topLeading) {
        if let selection = activeTimedQuickCreateSelection ?? pendingTimedQuickCreateSelection {
          let frame = timedQuickCreateViewportFrame(for: selection)

          timedQuickCreatePreviewBlock(
            selection: selection,
            frame: frame
          )
          .frame(width: frame.width, height: frame.height, alignment: .topLeading)
          .offset(x: frame.minX, y: frame.minY)
          .zIndex(1999)
        }

        if let dragState = activeTaskDrag,
          let taskDescriptor = scheduleTaskDescriptor(for: dragState.taskID)
        {
          let preview = preview(for: dragState)
          let dropFrame = dragDropTargetViewportFrame(for: dragState, preview: preview)
          let ghostFrame = dragGhostViewportFrame(for: dragState, dropFrame: dropFrame)
          let ghostPresentsAsAllDay = dragState.originalTimeMinutes == nil
          let color = scheduleColor(for: taskDescriptor.projectColorHex)
          let taskRow = taskDescriptor.taskRow

          dragSourcePlaceholder(
            frame: dragState.originalViewportFrame,
            isAllDay: ghostPresentsAsAllDay
          )

          if let dropFrame {
            dragDropTargetIndicator(
              frame: dropFrame,
              color: color,
              isAllDay: preview.timeMinutes == nil,
              label: preview.timeMinutes == nil ? nil : scheduleDragPreviewLabel(for: preview)
            )
          }

          liftedDragGhost(frame: ghostFrame) {
            if ghostPresentsAsAllDay {
              dragPreviewChip(
                taskDescriptor: taskDescriptor,
                title: taskRow.title,
                subtitle: taskDescriptor.projectTitle,
                color: color,
                isSelected: false,
                isPreparationSlot: dragState.isPreparationSlot
              )
            } else {
              dragPreviewBlock(
                taskDescriptor: taskDescriptor,
                title: taskRow.title,
                subtitle: taskDescriptor.projectTitle,
                color: color,
                isSelected: false,
                isPreparationSlot: dragState.isPreparationSlot,
                targetCompletedWorkUnits: dragState.targetCompletedWorkUnits,
                timeLabel: taskDragTimeLabel(for: dragState, preview: preview, dropFrame: dropFrame),
                blockHeight: ghostFrame.height
              )
            }
          }
        }

        if activeTaskDrag == nil, let committed = committedTaskDrop {
          dragSourcePlaceholder(frame: committed.originalFrame, isAllDay: committed.isOriginalAllDay)
          dragDropTargetIndicator(
            frame: committed.dropFrame,
            color: committed.color,
            isAllDay: committed.isAllDay,
            label: committed.label
          )
        }

        if let dragState = activeCalendarDrag,
          let event = appState.resolvedScheduleCalendarEvent(eventID: dragState.eventID)
        {
          let preview = preview(for: dragState)
          let dropFrame = dragDropTargetViewportFrame(for: dragState, preview: preview)
          let ghostFrame = dragGhostViewportFrame(for: dragState, dropFrame: dropFrame)
          let ghostPresentsAsAllDay = dragState.originalTimeMinutes == nil
          let color = scheduleColor(for: event.calendarColorHex, fallback: .secondary)

          dragSourcePlaceholder(
            frame: dragState.originalViewportFrame,
            isAllDay: ghostPresentsAsAllDay
          )

          if let dropFrame {
            dragDropTargetIndicator(
              frame: dropFrame,
              color: color,
              isAllDay: preview.timeMinutes == nil,
              label: preview.timeMinutes == nil ? nil : scheduleDragPreviewLabel(for: preview)
            )
          }

          liftedDragGhost(frame: ghostFrame) {
            if ghostPresentsAsAllDay {
              dragPreviewEventChip(
                event: event,
                title: event.title,
                subtitle: event.calendarTitle,
                color: color
              )
            } else {
              dragPreviewEventBlock(
                event: event,
                title: event.title,
                subtitle: event.calendarTitle,
                color: color,
                timeLabel: calendarDragTimeLabel(for: dragState, preview: preview, dropFrame: dropFrame),
                blockHeight: ghostFrame.height,
                durationMinutes: dragState.originalDurationMinutes ?? timedMinimumDuration
              )
            }
          }
        }

        if let resizeState = activeTaskResize,
          let taskDescriptor = scheduleTaskDescriptor(for: resizeState.taskID)
        {
          let preview = preview(for: resizeState)
          let frame = resizePreviewViewportFrame(for: resizeState, preview: preview)
          let color = scheduleColor(for: taskDescriptor.projectColorHex)

          resizePreviewTaskBlock(
            taskDescriptor: taskDescriptor,
            day: preview.day ?? resizeState.originalDay,
            color: color,
            timeLabel: scheduleDragPreviewLabel(for: preview),
            frame: frame,
            isPreparationSlot: resizeState.isPreparationSlot,
            targetCompletedWorkUnits: resizeState.targetCompletedWorkUnits
          )
          .zIndex(2001)
        }

        if let resizeState = activeCalendarResize,
          let event = appState.resolvedScheduleCalendarEvent(eventID: resizeState.eventID)
        {
          let preview = preview(for: resizeState)
          let frame = resizePreviewViewportFrame(for: resizeState, preview: preview)
          let color = scheduleColor(for: event.calendarColorHex, fallback: .secondary)

          resizePreviewEventBlock(
            event: event,
            color: color,
            timeLabel: scheduleDragPreviewLabel(for: preview),
            durationMinutes: preview.durationMinutes ?? timedMinimumDuration,
            frame: frame
          )
          .zIndex(2002)
        }

      }
      .allowsHitTesting(false)

      if let selection = pendingTimedQuickCreateSelection {
        timedQuickCreatePopover(selection: selection)
          .zIndex(2100)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .animation(scheduleOverlayPresentationAnimation, value: overlayPresentationSignature)
  }

  func timedQuickCreatePreviewBlock(
    selection: ScheduleTimedQuickCreateSelection,
    frame: CGRect
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("새 할일")
        .font(.system(size: ScheduleUITokens.Interaction.quickCreateTitleFontSize, weight: .semibold))
        .foregroundStyle(.primary.opacity(ScheduleUITokens.Interaction.quickCreateTitleForegroundOpacity))
      Text(timeRangeLabel(startMinute: selection.startMinutes, durationMinutes: selection.durationMinutes))
        .font(.system(size: ScheduleUITokens.Interaction.quickCreateTimeFontSize, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, ScheduleUITokens.Interaction.quickCreateHorizontalPadding)
    .padding(.vertical, ScheduleUITokens.Interaction.quickCreateVerticalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.accentColor.opacity(ScheduleUITokens.Interaction.quickCreateFillOpacity))
    )
    .overlay {
      ScheduleRoundedRectangleStrokeOverlay(
        cornerRadius: 12,
        color: Color.accentColor.opacity(ScheduleUITokens.Interaction.quickCreateStrokeOpacity),
        lineWidth: 1.1,
        dash: [5, 4]
      )
    }
  }

  func timedQuickCreatePopover(selection: ScheduleTimedQuickCreateSelection) -> some View {
    let previewFrame = timedQuickCreateViewportFrame(for: selection)
    let viewportSize = scheduleViewportSize
    let popoverSize = CGSize(width: 260, height: 150)
    let x = min(
      max(titleColumnWidth + 8, previewFrame.minX + 12),
      max(titleColumnWidth + 8, viewportSize.width - popoverSize.width - 12)
    )
    let y = min(
      max(8, previewFrame.minY + 12),
      max(8, viewportSize.height - popoverSize.height - 12)
    )

    return ScheduleQuickAddPopoverContent(
      projects: scheduleQuickAddProjects,
      defaultProjectID: scheduleQuickAddProjectID,
      onSubmit: { title, projectID in
        createScheduleTask(
          title,
          projectID: projectID,
          day: selection.day,
          timeMinutes: selection.startMinutes,
          durationMinutes: selection.durationMinutes
        )
        pendingTimedQuickCreateSelection = nil
      },
      onCancel: {
        pendingTimedQuickCreateSelection = nil
      }
    )
    .overlaySurface(
      cornerRadius: 12,
      strokeColor: .primary,
      style: scheduleOverlayCardStyle
    )
    .frame(width: popoverSize.width)
    .offset(x: x, y: y)
  }
}
