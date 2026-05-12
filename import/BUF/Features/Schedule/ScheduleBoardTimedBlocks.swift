import AppKit
import SwiftUI

extension ScheduleBoardView {
  func timedBlock(_ layout: ScheduleTimedBlockLayout) -> some View {
    let frame = timedFrame(for: layout)
    let blockHeight = max(quarterHourHeight, frame.height)
    let taskDescriptor = layout.entry.taskDescriptor
    let event = layout.entry.event
    let isDragging = activeTaskDrag?.entryID == layout.entry.id
    let isResizing = activeTaskResize?.entryID == layout.entry.id
    let isEventDragging = activeCalendarDrag?.eventID == event?.id
    let isEventResizing = activeCalendarResize?.eventID == event?.id
    let visibleDay = days[layout.entry.dayIndex]
    let xOffsetWithinDay = frame.minX - CGFloat(layout.entry.dayIndex) * dayColumnWidth
    let documentFrame = CGRect(
      x: frame.minX,
      y: frame.minY,
      width: frame.width,
      height: blockHeight
    )
    let viewportFrame = timedViewportFrame(forDocumentFrame: documentFrame)

    return Group {
      if layout.entry.isTask, let taskDescriptor {
        let taskRow = taskDescriptor.taskRow
        scheduleTaskBlock(
          taskDescriptor: taskDescriptor,
          entryID: layout.entry.id,
          day: visibleDay,
          title: layout.entry.title,
          subtitle: layout.entry.subtitle,
          color: layout.entry.color,
          isSelected: selectedScheduleTaskID == taskRow.id,
          isPreparationSlot: layout.entry.isPreparationSlot,
          targetCompletedWorkUnits: layout.entry.targetCompletedWorkUnits,
          startMinute: layout.entry.startMinute,
          durationMinutes: layout.entry.durationMinutes,
          sourceDay: layout.entry.sourceStartDay,
          sourceTimeMinutes: layout.entry.sourceStartMinute,
          sourceDurationMinutes: layout.entry.sourceDurationMinutes,
          documentFrame: documentFrame,
          xOffsetWithinDay: xOffsetWithinDay,
          allowsStartResize: layout.entry.isFirstSegment,
          allowsEndResize: layout.entry.isLastSegment,
          timeLabel: timeRangeLabel(
            startMinute: layout.entry.startMinute,
            durationMinutes: layout.entry.durationMinutes
          ),
          blockHeight: blockHeight,
          viewportFrame: viewportFrame,
          postponeAction: postponeScheduleAction(
            for: taskDescriptor,
            day: visibleDay,
            isPreparationSlot: layout.entry.isPreparationSlot,
            targetCompletedWorkUnits: layout.entry.targetCompletedWorkUnits
          )
        )
        .frame(width: frame.width, height: blockHeight, alignment: .topLeading)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(
          ScheduleResizePreviewStylePolicy.sourceBlockOpacity(
            isResizing: isResizing,
            isDragging: isDragging,
            dragPlaceholderOpacity: dragSourcePlaceholderOpacity
          )
        )
        .simultaneousGesture(
          taskDragGesture(
            for: taskDescriptor,
            entryID: layout.entry.id,
            originalDay: layout.entry.sourceStartDay,
            originalTimeMinutes: layout.entry.sourceStartMinute,
            originalDurationMinutes: layout.entry.sourceDurationMinutes,
            itemFrame: frame,
            originalTopScheduleYOverride: sourceTopScheduleY(for: layout.entry),
            isAllDay: false,
            isPreparationSlot: layout.entry.isPreparationSlot,
            targetCompletedWorkUnits: layout.entry.targetCompletedWorkUnits
          )
        )
        .zIndex(
          ScheduleTimedBlockHitPriorityPolicy.zIndex(
            isTask: true,
            taskID: taskRow.id,
            selectedTaskID: selectedScheduleTaskID,
            startMinute: layout.entry.startMinute,
            isBackgroundCalendar: false
          )
        )
      } else if let event {
        Group {
          if layout.entry.isBackgroundCalendar {
            scheduleEventBlock(
              event: event,
              title: layout.entry.title,
              subtitle: layout.entry.subtitle,
              color: layout.entry.color,
              timeLabel: timeRangeLabel(
                startMinute: layout.entry.startMinute,
                durationMinutes: layout.entry.durationMinutes
              ),
              visibleDay: visibleDay,
              blockHeight: blockHeight,
              startMinute: layout.entry.startMinute,
              durationMinutes: layout.entry.durationMinutes,
              viewportFrame: viewportFrame,
              contentTopOffset: layout.entry.contentTopOffset,
              isBackgroundCalendar: true
            )
          } else if event.canEditTiming {
            scheduleEventBlock(
              event: event,
              title: layout.entry.title,
              subtitle: layout.entry.subtitle,
              color: layout.entry.color,
              timeLabel: timeRangeLabel(
                startMinute: layout.entry.startMinute,
                durationMinutes: layout.entry.durationMinutes
              ),
              visibleDay: visibleDay,
              blockHeight: blockHeight,
              startMinute: layout.entry.startMinute,
              durationMinutes: layout.entry.durationMinutes,
              viewportFrame: viewportFrame,
              resizeSourceDay: layout.entry.sourceStartDay,
              resizeSourceTimeMinutes: layout.entry.sourceStartMinute,
              resizeSourceDurationMinutes: layout.entry.sourceDurationMinutes,
              documentFrame: documentFrame,
              xOffsetWithinDay: xOffsetWithinDay,
              allowsStartResize: layout.entry.isFirstSegment,
              allowsEndResize: layout.entry.isLastSegment
            )
            .gesture(
              eventDragGesture(
                for: event,
                itemFrame: frame,
                originalTopScheduleYOverride: sourceTopScheduleY(for: layout.entry),
                isAllDay: false
              )
            )
          } else {
            scheduleEventBlock(
              event: event,
              title: layout.entry.title,
              subtitle: layout.entry.subtitle,
              color: layout.entry.color,
              timeLabel: timeRangeLabel(
                startMinute: layout.entry.startMinute,
                durationMinutes: layout.entry.durationMinutes
              ),
              visibleDay: visibleDay,
              blockHeight: blockHeight,
              startMinute: layout.entry.startMinute,
              durationMinutes: layout.entry.durationMinutes,
              viewportFrame: viewportFrame
            )
          }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(
          ScheduleResizePreviewStylePolicy.sourceBlockOpacity(
            isResizing: isEventResizing,
            isDragging: isEventDragging,
            dragPlaceholderOpacity: dragSourcePlaceholderOpacity
          )
        )
        .zIndex(
          ScheduleTimedBlockHitPriorityPolicy.zIndex(
            isTask: false,
            taskID: nil,
            selectedTaskID: selectedScheduleTaskID,
            startMinute: layout.entry.startMinute,
            isBackgroundCalendar: layout.entry.isBackgroundCalendar
          )
        )
      }
    }
  }


  func scheduleTaskBlock(
    taskDescriptor: WorkspaceScheduleTaskDescriptor,
    entryID: String,
    day: Date,
    title: String,
    subtitle: String?,
    color: Color,
    isSelected: Bool,
    isPreparationSlot: Bool,
    targetCompletedWorkUnits: Int?,
    startMinute: Int,
    durationMinutes: Int,
    sourceDay: Date,
    sourceTimeMinutes: Int,
    sourceDurationMinutes: Int,
    documentFrame: CGRect,
    xOffsetWithinDay: CGFloat,
    allowsStartResize: Bool,
    allowsEndResize: Bool,
    timeLabel: String?,
    blockHeight: CGFloat,
    viewportFrame: CGRect,
    postponeAction: (() -> Void)? = nil
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
        recordedAt: day,
        isPreparationSlot: isPreparationSlot,
        targetCompletedWorkUnits: targetCompletedWorkUnits,
        timeLabel: timeLabel,
        density: density,
        postponeAction: postponeAction
      )
    }
    .clipped()
    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .onTapGesture(count: 2) {
      handleScheduleTaskDetailTap(taskDescriptor)
    }
    .simultaneousGesture(
      TapGesture()
        .onEnded {
          handleScheduleTaskPrimaryTap(taskDescriptor)
        }
    )
    .contextMenu {
      scheduleTaskContextMenu(taskDescriptor)
    }
    .overlay(alignment: .top) {
      if allowsStartResize {
        resizeHandle(
          for: taskDescriptor,
          entryID: entryID,
          day: sourceDay,
          originalTimeMinutes: sourceTimeMinutes,
          durationMinutes: sourceDurationMinutes,
          edge: .start,
          originalDocumentFrame: documentFrame,
          visibleDay: day,
          xOffsetWithinDay: xOffsetWithinDay,
          isPreparationSlot: isPreparationSlot,
          targetCompletedWorkUnits: targetCompletedWorkUnits
        )
      }
    }
    .overlay(alignment: .bottom) {
      if allowsEndResize {
        resizeHandle(
          for: taskDescriptor,
          entryID: entryID,
          day: sourceDay,
          originalTimeMinutes: sourceTimeMinutes,
          durationMinutes: sourceDurationMinutes,
          edge: .end,
          originalDocumentFrame: documentFrame,
          visibleDay: day,
          xOffsetWithinDay: xOffsetWithinDay,
          isPreparationSlot: isPreparationSlot,
          targetCompletedWorkUnits: targetCompletedWorkUnits
        )
      }
    }
  }

  func scheduleEventBlock(
    event: ScheduleCalendarEvent,
    title: String,
    subtitle: String?,
    color: Color,
    timeLabel: String?,
    visibleDay: Date,
    blockHeight: CGFloat,
    startMinute _: Int,
    durationMinutes: Int,
    viewportFrame: CGRect,
    resizeSourceDay: Date? = nil,
    resizeSourceTimeMinutes: Int? = nil,
    resizeSourceDurationMinutes: Int? = nil,
    documentFrame: CGRect? = nil,
    xOffsetWithinDay: CGFloat = 0,
    allowsStartResize: Bool = true,
    allowsEndResize: Bool = true,
    contentTopOffset: CGFloat = 0,
    isBackgroundCalendar: Bool = false
  ) -> some View {
    let density = timedBlockDensity(for: blockHeight)

    return ScheduleEventBlockSurface(color: color, isBackgroundCalendar: isBackgroundCalendar) {
      scheduleEventBlockContent(
        event: event,
        title: title,
        subtitle: subtitle,
        timeLabel: timeLabel,
        blockHeight: blockHeight,
        density: density,
        durationMinutes: durationMinutes,
        isBackgroundCalendar: isBackgroundCalendar,
        contentTopOffset: contentTopOffset
      )
    }
    .clipped()
    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(alignment: .topTrailing) {
      if event.isRecurring {
        recurrenceIndicator(fontSize: ScheduleUITokens.ScheduleItem.recurrenceIndicatorFontSize)
          .padding(.top, ScheduleUITokens.ScheduleItem.recurrenceIndicatorTopPadding)
          .padding(.trailing, ScheduleUITokens.ScheduleItem.recurrenceIndicatorTrailingPadding)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .allowsHitTesting(!isBackgroundCalendar)
    .onTapGesture {
      guard !isBackgroundCalendar else { return }
      showScheduleCalendarEventEditor(event)
    }
    .contextMenu {
      if !isBackgroundCalendar {
        scheduleEventContextMenu(event)
      }
    }
    .overlay(alignment: .top) {
      if event.canEditTiming && allowsStartResize && !isBackgroundCalendar,
        let resizeSourceDay,
        let resizeSourceTimeMinutes,
        let resizeSourceDurationMinutes,
        let documentFrame
      {
        eventResizeHandle(
          for: event,
          edge: .start,
          originalDay: resizeSourceDay,
          originalTimeMinutes: resizeSourceTimeMinutes,
          originalDurationMinutes: resizeSourceDurationMinutes,
          originalDocumentFrame: documentFrame,
          visibleDay: visibleDay,
          xOffsetWithinDay: xOffsetWithinDay
        )
      }
    }
    .overlay(alignment: .bottom) {
      if event.canEditTiming && allowsEndResize && !isBackgroundCalendar,
        let resizeSourceDay,
        let resizeSourceTimeMinutes,
        let resizeSourceDurationMinutes,
        let documentFrame
      {
        eventResizeHandle(
          for: event,
          edge: .end,
          originalDay: resizeSourceDay,
          originalTimeMinutes: resizeSourceTimeMinutes,
          originalDurationMinutes: resizeSourceDurationMinutes,
          originalDocumentFrame: documentFrame,
          visibleDay: visibleDay,
          xOffsetWithinDay: xOffsetWithinDay
        )
      }
    }
  }

  @ViewBuilder
  func scheduleTaskBlockContent(
    taskDescriptor: WorkspaceScheduleTaskDescriptor,
    title: String,
    subtitle: String?,
    color: Color,
    isSelected: Bool,
    isCompleted: Bool,
    blockHeight: CGFloat,
    recordedAt: Date,
    isPreparationSlot: Bool,
    targetCompletedWorkUnits: Int?,
    timeLabel: String?,
    density: ScheduleTimedBlockDensity,
    postponeAction: (() -> Void)? = nil
  ) -> some View {
    let primaryTextColor = scheduleTaskPrimaryTextColor(
      isSelected: isSelected,
      isCompleted: isCompleted
    )
    let secondaryTextColor = scheduleTaskSecondaryTextColor(isSelected: isSelected)
    let titleLineLimit = scheduleTimedTitleLineLimit(for: blockHeight, density: density)
    switch density {
    case .compact:
      HStack(alignment: .center, spacing: 6) {
        completionToggle(
          taskDescriptor: taskDescriptor,
          color: color,
          isSelected: isSelected,
          compact: true,
          recordedAt: recordedAt,
          isPreparationSlot: isPreparationSlot,
          targetCompletedWorkUnits: targetCompletedWorkUnits
        )

        scheduleTaskTitleRow(
          title,
          taskDescriptor: taskDescriptor,
          titleColor: primaryTextColor,
          metadataColor: secondaryTextColor,
          lineLimit: 1
        )

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(.horizontal, ScheduleUITokens.Spacing.scheduleItemHorizontalPadding)
      .padding(.vertical, ScheduleUITokens.Spacing.scheduleItemCompactVerticalPadding)
      .overlay(alignment: .trailing) {
        schedulePostponeAffordanceOverlay(
          compact: true,
          isSelected: isSelected,
          postponeAction: postponeAction
        )
      }

    case .standard:
      HStack(alignment: .top, spacing: 6) {
        completionToggle(
          taskDescriptor: taskDescriptor,
          color: color,
          isSelected: isSelected,
          compact: true,
          recordedAt: recordedAt,
          isPreparationSlot: isPreparationSlot,
          targetCompletedWorkUnits: targetCompletedWorkUnits
        )
        .padding(.top, 1)

        VStack(alignment: .leading, spacing: 2) {
          scheduleTaskTitleRow(
            title,
            taskDescriptor: taskDescriptor,
            titleColor: primaryTextColor,
            metadataColor: secondaryTextColor,
            lineLimit: titleLineLimit
          )

          scheduleTaskSupplementalRow(
            timeLabel: timeLabel,
            textColor: secondaryTextColor
          )

          Spacer(minLength: 0)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.horizontal, ScheduleUITokens.Spacing.scheduleItemHorizontalPadding)
      .padding(.vertical, ScheduleUITokens.Spacing.scheduleItemStandardVerticalPadding)
      .overlay(alignment: .trailing) {
        schedulePostponeAffordanceOverlay(
          compact: true,
          isSelected: isSelected,
          postponeAction: postponeAction
        )
        .padding(.top, 1)
      }

    case .expanded:
      HStack(alignment: .top, spacing: 6) {
        completionToggle(
          taskDescriptor: taskDescriptor,
          color: color,
          isSelected: isSelected,
          compact: false,
          recordedAt: recordedAt,
          isPreparationSlot: isPreparationSlot,
          targetCompletedWorkUnits: targetCompletedWorkUnits
        )

        VStack(alignment: .leading, spacing: 3) {
          scheduleTaskTitleRow(
            title,
            taskDescriptor: taskDescriptor,
            titleColor: primaryTextColor,
            metadataColor: secondaryTextColor,
            lineLimit: titleLineLimit
          )

          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(scheduleItemSupplementalFont(weight: .medium))
              .foregroundStyle(secondaryTextColor)
              .lineLimit(scheduleTimedSupplementalLineLimit(for: blockHeight))
          }

          scheduleTaskSupplementalRow(
            timeLabel: timeLabel,
            textColor: secondaryTextColor
          )

          Spacer(minLength: 0)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.horizontal, ScheduleUITokens.Spacing.scheduleItemHorizontalPadding)
      .padding(.vertical, ScheduleUITokens.Spacing.scheduleItemExpandedVerticalPadding)
      .overlay(alignment: .trailing) {
        schedulePostponeAffordanceOverlay(
          compact: false,
          isSelected: isSelected,
          postponeAction: postponeAction
        )
        .padding(.top, 1)
      }
    }
  }

  @ViewBuilder
  func scheduleEventBlockContent(
    event: ScheduleCalendarEvent,
    title: String,
    subtitle: String?,
    timeLabel: String?,
    blockHeight: CGFloat,
    density: ScheduleTimedBlockDensity,
    durationMinutes: Int,
    isBackgroundCalendar: Bool,
    contentTopOffset: CGFloat = 0
  ) -> some View {
    let titleColor: Color =
      isBackgroundCalendar
        ? .secondary.opacity(ScheduleUITokens.ScheduleItem.backgroundCalendarTitleOpacity)
        : .primary
    let subtitleColor = scheduleEventSecondaryTextColor(isBackgroundCalendar: isBackgroundCalendar)
    let titleLineLimit = scheduleTimedTitleLineLimit(for: blockHeight, density: density)
    switch density {
    case .compact:
      HStack(alignment: .center, spacing: 6) {
        scheduleEventTitleRow(
          title,
          event: event,
          titleColor: titleColor,
          metadataColor: subtitleColor,
          lineLimit: 1
        )

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(.leading, ScheduleUITokens.Spacing.scheduleEventLeadingPadding)
      .padding(.trailing, ScheduleUITokens.Spacing.scheduleEventTrailingPadding)
      .padding(.top, ScheduleUITokens.Spacing.scheduleItemCompactVerticalPadding + contentTopOffset)
      .padding(.bottom, ScheduleUITokens.Spacing.scheduleItemCompactVerticalPadding)

    case .standard:
      VStack(alignment: .leading, spacing: 2) {
        scheduleEventTitleRow(
          title,
          event: event,
          titleColor: titleColor,
          metadataColor: subtitleColor,
          lineLimit: max(durationMinutes >= 75 ? 2 : 1, titleLineLimit)
        )

        scheduleEventSupplementalRow(
          timeLabel: isBackgroundCalendar ? nil : timeLabel,
          textColor: subtitleColor
        )

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.leading, ScheduleUITokens.Spacing.scheduleEventLeadingPadding)
      .padding(.trailing, ScheduleUITokens.Spacing.scheduleEventTrailingPadding)
      .padding(.top, ScheduleUITokens.Spacing.scheduleItemStandardVerticalPadding + contentTopOffset)
      .padding(.bottom, ScheduleUITokens.Spacing.scheduleItemStandardVerticalPadding)

    case .expanded:
      VStack(alignment: .leading, spacing: 3) {
        scheduleEventTitleRow(
          title,
          event: event,
          titleColor: titleColor,
          metadataColor: subtitleColor,
          lineLimit: max(durationMinutes >= 90 ? 3 : 2, titleLineLimit)
        )

        if let subtitle, !subtitle.isEmpty, durationMinutes >= 60 {
          Text(subtitle)
            .font(scheduleItemSupplementalFont(weight: .medium))
            .foregroundStyle(subtitleColor)
            .lineLimit(scheduleTimedSupplementalLineLimit(for: blockHeight))
        }

        scheduleEventSupplementalRow(
          timeLabel: isBackgroundCalendar ? nil : timeLabel,
          textColor: subtitleColor
        )

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.leading, ScheduleUITokens.Spacing.scheduleEventLeadingPadding)
      .padding(.trailing, ScheduleUITokens.Spacing.scheduleEventTrailingPadding)
      .padding(.top, ScheduleUITokens.Spacing.scheduleItemExpandedVerticalPadding + contentTopOffset)
      .padding(.bottom, ScheduleUITokens.Spacing.scheduleItemExpandedVerticalPadding)
    }
  }

  func taskChip(
    _ taskDescriptor: WorkspaceScheduleTaskDescriptor,
    title: String,
    subtitle: String?,
    color: Color,
    compact: Bool,
    isSelected: Bool,
    recordedAt: Date? = nil,
    isPreparationSlot: Bool = false,
    targetCompletedWorkUnits: Int? = nil,
    trailingLabel: String? = nil,
    postponeAction: (() -> Void)? = nil
  ) -> some View {
    let taskRow = taskDescriptor.taskRow
    let isCompleted = effectiveScheduleTaskIsCompleted(taskRow)
    return ScheduleTaskChipSurface(
      color: color,
      isSelected: isSelected,
      isPreparationSlot: isPreparationSlot,
      selectionHighlightColor: selectionHighlightColor
    ) {
      HStack(spacing: 2) {
        completionToggle(
          taskDescriptor: taskDescriptor,
          color: color,
          isSelected: isSelected,
          compact: true,
          recordedAt: recordedAt,
          isPreparationSlot: isPreparationSlot,
          targetCompletedWorkUnits: targetCompletedWorkUnits
        )
        .offset(x: -3)

        scheduleTaskTitleRow(
          title,
          taskDescriptor: taskDescriptor,
          titleColor: scheduleTaskPrimaryTextColor(
            isSelected: isSelected,
            isCompleted: isCompleted
          ),
          metadataColor: scheduleTaskSecondaryTextColor(isSelected: isSelected),
          lineLimit: 1
        )

        if !compact, let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(scheduleItemSupplementalFont(weight: .medium))
            .foregroundStyle(scheduleTaskSecondaryTextColor(isSelected: isSelected))
            .lineLimit(1)
        }

        Spacer(minLength: 0)

        if let trailingLabel, !trailingLabel.isEmpty {
          Text(trailingLabel)
            .font(scheduleItemSupplementalFont(weight: .medium, design: .monospaced))
            .foregroundStyle(scheduleTaskSecondaryTextColor(isSelected: isSelected))
            .lineLimit(1)
        }
      }
      .padding(.leading, ScheduleUITokens.Spacing.scheduleItemChipLeadingPadding)
      .padding(.trailing, ScheduleUITokens.Spacing.scheduleItemChipTrailingPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .overlay(alignment: .trailing) {
      schedulePostponeAffordanceOverlay(
        compact: compact,
        isSelected: isSelected,
        postponeAction: postponeAction
      )
    }
    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .onTapGesture(count: 2) {
      handleScheduleTaskDetailTap(taskDescriptor)
    }
    .simultaneousGesture(
      TapGesture()
        .onEnded {
          handleScheduleTaskPrimaryTap(taskDescriptor)
        }
    )
    .contextMenu {
      scheduleTaskContextMenu(taskDescriptor)
    }
  }

  func eventChip(
    _ event: ScheduleCalendarEvent,
    title: String,
    subtitle: String?,
    color: Color,
    isBackgroundCalendar: Bool = false
  ) -> some View {
    ScheduleEventChipSurface(color: color, isBackgroundCalendar: isBackgroundCalendar) {
      let titleColor: Color =
        isBackgroundCalendar
          ? .secondary.opacity(ScheduleUITokens.ScheduleItem.backgroundCalendarTitleOpacity)
          : .primary
      let subtitleColor = scheduleEventSecondaryTextColor(isBackgroundCalendar: isBackgroundCalendar)
      HStack(spacing: 2) {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
          .frame(width: 18, height: 18, alignment: .center)
          .offset(x: -3)
        scheduleEventTitleRow(
          title,
          event: event,
          titleColor: titleColor,
          metadataColor: subtitleColor,
          lineLimit: 1
        )
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(scheduleItemSupplementalFont(weight: .medium))
            .foregroundStyle(subtitleColor)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        if event.isRecurring {
          recurrenceIndicator(fontSize: ScheduleUITokens.ScheduleItem.chipRecurrenceIndicatorFontSize)
        }
      }
      .padding(.leading, ScheduleUITokens.Spacing.scheduleItemChipLeadingPadding)
      .padding(.trailing, ScheduleUITokens.Spacing.scheduleItemChipTrailingPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .allowsHitTesting(!isBackgroundCalendar)
    .onTapGesture {
      guard !isBackgroundCalendar else { return }
      showScheduleCalendarEventEditor(event)
    }
    .contextMenu {
      if !isBackgroundCalendar {
        scheduleEventContextMenu(event)
      }
    }
  }
}
