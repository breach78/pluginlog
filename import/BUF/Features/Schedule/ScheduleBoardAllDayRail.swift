import SwiftUI

struct ScheduleAllDayLayout: Identifiable {
  let id: String
  let dayIndex: Int
  let rowIndex: Int
  let title: String
  let subtitle: String?
  let color: Color
  let isTask: Bool
  let isPreparationSlot: Bool
  let targetCompletedWorkUnits: Int?
  let taskDescriptor: WorkspaceScheduleTaskDescriptor?
  let event: ScheduleCalendarEvent?
  let isBackgroundCalendar: Bool
}

extension ScheduleBoardView {
  var scheduleAllDayQuickAddSection: some View {
    ScheduleQuickAddContextMenuRegion(
      isAllDayRegion: true,
      canCreateTask: scheduleQuickAddProjectID != nil,
      projects: scheduleQuickAddProjects,
      defaultProjectID: scheduleQuickAddProjectID,
      onCreateTask: createScheduleTask,
      onUnavailable: { handleUnavailableScheduleQuickAdd() },
      onBackgroundTap: handleScheduleBackgroundTap,
      allowsTimedDragCreation: false,
      onTimedDragPreview: nil,
      onTimedDragCommit: nil,
      onTimedDragCancel: nil
    )
  }

  func allDayRail(
    _ entries: [ScheduleAllDayLayout],
    backgroundEntries: [ScheduleAllDayLayout]
  ) -> some View {
    let foregroundRowCount = (entries.map(\.rowIndex).max() ?? -1) + 1
    let backgroundRowCount = (backgroundEntries.map(\.rowIndex).max() ?? -1) + 1
    let totalRowCount = max(max(foregroundRowCount, backgroundRowCount), allDayVisibleRowCount)
    let contentHeight = CGFloat(totalRowCount) * allDayRowHeight + allDayRailPadding * 2

    return ScheduleVerticalRailScrollView(
      contentSize: CGSize(width: dayColumnsWidth, height: contentHeight),
      visibleHeight: allDayRailVisibleHeight,
      isScrollEnabled: contentHeight > allDayRailVisibleHeight,
      viewportState: scrollViewportState
    ) {
      ZStack(alignment: .topLeading) {
        scheduleAllDayQuickAddSection
          .frame(width: dayColumnsWidth, height: contentHeight)

        ZStack(alignment: .topLeading) {
          ForEach(Array(days.enumerated()), id: \.offset) { index, day in
            Rectangle()
              .fill(dayColumnBackgroundColor(for: day, section: .allDayRail))
              .frame(width: dayColumnWidth, height: contentHeight)
              .offset(x: CGFloat(index) * dayColumnWidth)

            Rectangle()
              .fill(Color.primary.opacity(0.07))
              .frame(width: 1, height: contentHeight)
              .offset(x: CGFloat(index + 1) * dayColumnWidth - 0.5)
          }
        }
        .allowsHitTesting(false)

        ForEach(backgroundEntries) { entry in
          allDayChip(entry)
        }

        ForEach(entries) { entry in
          allDayChip(entry)
        }
      }
      .frame(width: dayColumnsWidth, height: contentHeight, alignment: .topLeading)
    }
    .frame(width: dayColumnsWidth, height: allDayRailVisibleHeight, alignment: .topLeading)
    .clipped()
  }

  func allDayChip(_ entry: ScheduleAllDayLayout) -> some View {
    let frame = allDayFrame(for: entry)
    let isTaskDragging = activeTaskDrag?.entryID == entry.id
    let isEventDragging = activeCalendarDrag?.eventID == entry.event?.id

    return Group {
      if entry.isTask, let taskDescriptor = entry.taskDescriptor {
        let taskRow = taskDescriptor.taskRow
        taskChip(
          taskDescriptor,
          title: entry.title,
          subtitle: entry.subtitle,
          color: entry.color,
          compact: true,
          isSelected: selectedScheduleTaskID == taskRow.id,
          recordedAt: days[entry.dayIndex],
          isPreparationSlot: entry.isPreparationSlot,
          targetCompletedWorkUnits: entry.targetCompletedWorkUnits,
          trailingLabel: nil,
          postponeAction: postponeScheduleAction(
            for: taskDescriptor,
            day: days[entry.dayIndex],
            isPreparationSlot: entry.isPreparationSlot,
            targetCompletedWorkUnits: entry.targetCompletedWorkUnits
          )
        )
        .gesture(
          taskDragGesture(
            for: taskDescriptor,
            entryID: entry.id,
            originalDay: days[entry.dayIndex],
            originalTimeMinutes: nil,
            originalDurationMinutes: nil,
            itemFrame: frame,
            isAllDay: true,
            isPreparationSlot: entry.isPreparationSlot,
            targetCompletedWorkUnits: entry.targetCompletedWorkUnits
          )
        )
        .opacity(isTaskDragging ? dragSourcePlaceholderOpacity : 1)
        .offset(x: frame.minX, y: frame.minY)
        .zIndex(2)
      } else if let event = entry.event {
        Group {
          if entry.isBackgroundCalendar {
            eventChip(
              event,
              title: entry.title,
              subtitle: nil,
              color: entry.color,
              isBackgroundCalendar: true
            )
          } else if event.canEditTiming {
            eventChip(event, title: entry.title, subtitle: nil, color: entry.color)
              .gesture(
                eventDragGesture(
                  for: event,
                  itemFrame: frame,
                  isAllDay: true
                )
              )
          } else {
            eventChip(event, title: entry.title, subtitle: nil, color: entry.color)
          }
        }
        .opacity(isEventDragging ? dragSourcePlaceholderOpacity : 1)
        .offset(x: frame.minX, y: frame.minY)
        .zIndex(1)
      }
    }
    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    .zIndex((isTaskDragging || isEventDragging) ? 1000 : 0)
  }

  func allDayFrame(for entry: ScheduleAllDayLayout) -> CGRect {
    allDayFrame(dayIndex: entry.dayIndex, rowIndex: entry.rowIndex)
  }

  func allDayFrame(dayIndex: Int, rowIndex: Int) -> CGRect {
    CGRect(
      x: CGFloat(dayIndex) * dayColumnWidth + allDayChipHorizontalInset,
      y: CGFloat(rowIndex) * allDayRowHeight + allDayRailPadding,
      width: dayColumnWidth - allDayChipHorizontalInset * 2,
      height: allDayRowHeight - 4
    )
  }

  func allDayViewportFrame(dayIndex: Int, rowIndex: Int) -> CGRect {
    let frame = allDayFrame(dayIndex: dayIndex, rowIndex: rowIndex)
    return CGRect(
      x: titleColumnWidth + frame.minX - currentScrollOffsetX,
      y: dateHeaderHeight + min(frame.minY, allDayRailVisibleHeight - frame.height),
      width: frame.width,
      height: frame.height
    )
  }

}
