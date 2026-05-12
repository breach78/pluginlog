import AppKit
import SwiftUI

extension ScheduleBoardView {
  func sourceTopScheduleY(for entry: ScheduleTimedEntry) -> CGFloat {
    let visibleDay = days[entry.dayIndex]
    let dayDelta = calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: entry.sourceStartDay),
      to: calendar.startOfDay(for: visibleDay)
    ).day ?? 0
    return CGFloat(entry.sourceStartMinute - dayDelta * 24 * 60) / 60 * hourHeight
  }

  func buildLayoutCache(
    filteredEvents: [ScheduleCalendarEvent],
    backgroundEvents: [ScheduleCalendarEvent],
    taskSnapshot: ScheduleTaskSnapshotCache
  ) -> ScheduleLayoutCache {
    let calendarOverlayProjection = appState.resolvedScheduleCalendarOverlayProjection()
    let snapshot = UnifiedScheduleEventStore.snapshot(
      workspaceTasks: taskSnapshot.taskDescriptors,
      calendarEvents: filteredEvents,
      calendarSources: calendarOverlayProjection.calendarSources,
      accessDenied: calendarOverlayProjection.accessDenied,
      calendar: calendar
    )
    let eventModelsByID = snapshot.itemsByID
    let workspaceTaskByID = taskSnapshot.workspaceTasksByID
    let eventByID = Dictionary(uniqueKeysWithValues: filteredEvents.map { ($0.id, $0) })
    let layout = layoutEngine.makeLayout(
      items: snapshot.items,
      dayIndexByDate: dayIndexByDate,
      calendar: calendar,
      metrics: ScheduleDayTimelineLayoutMetrics(minimumTimedDurationMinutes: timedMinimumDuration)
    )

    func timedLayouts(
      from layout: ScheduleDayTimelineLayout,
      eventModelsByID: [String: ScheduleEventModel],
      eventByID: [String: ScheduleCalendarEvent],
      isBackgroundCalendar: Bool
    ) -> [ScheduleTimedBlockLayout] {
      layout.timed.compactMap { placement -> ScheduleTimedBlockLayout? in
        guard let eventModel = eventModelsByID[placement.itemID] else { return nil }

        switch eventModel.source {
        case .workspaceTask(let taskID, _):
          guard let task = workspaceTaskByID[taskID] else { return nil }
          return ScheduleTimedBlockLayout(
            id: placement.id,
            entry: ScheduleTimedEntry(
              id: placement.id,
              dayIndex: placement.dayIndex,
              startMinute: placement.startMinute,
              durationMinutes: placement.durationMinutes,
              endMinute: placement.endMinute,
              sourceStartDay: placement.sourceStartDay,
              sourceStartMinute: placement.sourceStartMinute,
              sourceDurationMinutes: placement.sourceDurationMinutes,
              isFirstSegment: placement.isFirstSegment,
              isLastSegment: placement.isLastSegment,
              title: eventModel.title,
              subtitle: eventModel.subtitle,
              color: scheduleColor(for: eventModel.colorHex),
              isTask: true,
              isPreparationSlot: eventModel.isPreparationSlot,
              targetCompletedWorkUnits: eventModel.targetCompletedWorkUnits,
              taskDescriptor: task,
              event: nil,
              isBackgroundCalendar: false,
              contentTopOffset: 0
            ),
            column: placement.column,
            columnCount: placement.columnCount,
            columnSpan: placement.columnSpan
          )
        case .calendarEvent(let eventID):
          guard let event = eventByID[eventID] else { return nil }
          return ScheduleTimedBlockLayout(
            id: placement.id,
            entry: ScheduleTimedEntry(
              id: placement.id,
              dayIndex: placement.dayIndex,
              startMinute: placement.startMinute,
              durationMinutes: placement.durationMinutes,
              endMinute: placement.endMinute,
              sourceStartDay: placement.sourceStartDay,
              sourceStartMinute: placement.sourceStartMinute,
              sourceDurationMinutes: placement.sourceDurationMinutes,
              isFirstSegment: placement.isFirstSegment,
              isLastSegment: placement.isLastSegment,
              title: eventModel.title,
              subtitle: eventModel.subtitle,
              color: scheduleColor(for: eventModel.colorHex, fallback: .secondary),
              isTask: false,
              isPreparationSlot: false,
              targetCompletedWorkUnits: nil,
              taskDescriptor: nil,
              event: event,
              isBackgroundCalendar: isBackgroundCalendar,
              contentTopOffset: 0
            ),
            column: placement.column,
            columnCount: placement.columnCount,
            columnSpan: placement.columnSpan
          )
        }
      }
    }

    func allDayLayouts(
      from layout: ScheduleDayTimelineLayout,
      eventModelsByID: [String: ScheduleEventModel],
      eventByID: [String: ScheduleCalendarEvent],
      isBackgroundCalendar: Bool
    ) -> [ScheduleAllDayLayout] {
      layout.allDay.compactMap { placement -> ScheduleAllDayLayout? in
        guard let eventModel = eventModelsByID[placement.itemID] else { return nil }

        switch eventModel.source {
        case .workspaceTask(let taskID, _):
          guard let task = workspaceTaskByID[taskID] else { return nil }
          return ScheduleAllDayLayout(
            id: placement.id,
            dayIndex: placement.dayIndex,
            rowIndex: placement.rowIndex,
            title: eventModel.title,
            subtitle: eventModel.subtitle,
            color: scheduleColor(for: eventModel.colorHex),
            isTask: true,
            isPreparationSlot: eventModel.isPreparationSlot,
            targetCompletedWorkUnits: eventModel.targetCompletedWorkUnits,
            taskDescriptor: task,
            event: nil,
            isBackgroundCalendar: false
          )
        case .calendarEvent(let eventID):
          guard let event = eventByID[eventID] else { return nil }
          return ScheduleAllDayLayout(
            id: placement.id,
            dayIndex: placement.dayIndex,
            rowIndex: placement.rowIndex,
            title: eventModel.title,
            subtitle: eventModel.subtitle,
            color: scheduleColor(for: eventModel.colorHex, fallback: .secondary),
            isTask: false,
            isPreparationSlot: false,
            targetCompletedWorkUnits: nil,
            taskDescriptor: nil,
            event: event,
            isBackgroundCalendar: isBackgroundCalendar
          )
        }
      }
    }

    let timedEntries = timedLayouts(
      from: layout,
      eventModelsByID: eventModelsByID,
      eventByID: eventByID,
      isBackgroundCalendar: false
    )
    let allDayEntries = allDayLayouts(
      from: layout,
      eventModelsByID: eventModelsByID,
      eventByID: eventByID,
      isBackgroundCalendar: false
    )

    let backgroundItems = CalendarScheduleEventStore.items(from: backgroundEvents)
    let backgroundEventModelsByID = Dictionary(uniqueKeysWithValues: backgroundItems.map { ($0.id, $0) })
    let backgroundEventByID = Dictionary(uniqueKeysWithValues: backgroundEvents.map { ($0.id, $0) })
    let backgroundLayout = layoutEngine.makeLayout(
      items: backgroundItems,
      dayIndexByDate: dayIndexByDate,
      calendar: calendar,
      metrics: ScheduleDayTimelineLayoutMetrics(minimumTimedDurationMinutes: timedMinimumDuration)
    )
    let rawBackgroundTimedEntries = timedLayouts(
      from: backgroundLayout,
      eventModelsByID: backgroundEventModelsByID,
      eventByID: backgroundEventByID,
      isBackgroundCalendar: true
    )
    let foregroundBlocks = timedEntries.map { layout in
      ScheduleBackgroundLabelAvoidanceBlock(
        dayIndex: layout.entry.dayIndex,
        startMinute: layout.entry.startMinute,
        endMinute: layout.entry.endMinute
      )
    }
    let backgroundTimedEntries = rawBackgroundTimedEntries.map { layout in
      let block = ScheduleBackgroundLabelAvoidanceBlock(
        dayIndex: layout.entry.dayIndex,
        startMinute: layout.entry.startMinute,
        endMinute: layout.entry.endMinute
      )
      let offset = ScheduleBackgroundLabelAvoidancePolicy.topOffset(
        for: block,
        foregroundBlocks: foregroundBlocks,
        hourHeight: hourHeight
      )
      return layout.withContentTopOffset(offset)
    }
    let backgroundAllDayEntries = allDayLayouts(
      from: backgroundLayout,
      eventModelsByID: backgroundEventModelsByID,
      eventByID: backgroundEventByID,
      isBackgroundCalendar: true
    )

    return ScheduleLayoutCache(
      timedEntries: timedEntries,
      allDayEntries: allDayEntries,
      backgroundTimedEntries: backgroundTimedEntries,
      backgroundAllDayEntries: backgroundAllDayEntries
    )
  }

  func timedFrame(for layout: ScheduleTimedBlockLayout) -> CGRect {
    timedFrame(
      dayIndex: layout.entry.dayIndex,
      startMinute: layout.entry.startMinute,
      durationMinutes: layout.entry.durationMinutes,
      column: layout.column,
      columnCount: layout.columnCount,
      columnSpan: layout.columnSpan
    )
  }

  func timedFrame(
    dayIndex: Int,
    startMinute: Int,
    durationMinutes: Int,
    column: Int,
    columnCount: Int,
    columnSpan: Int
  ) -> CGRect {
    let columnCount = max(1, columnCount)
    let columnSpan = max(1, min(columnSpan, columnCount - column + 1))
    let totalSpacing = CGFloat(columnCount - 1) * timedBlockColumnSpacing + timedBlockInset * 2
    let blockWidth = max(44, (dayColumnWidth - totalSpacing) / CGFloat(columnCount))
    let x =
      CGFloat(dayIndex) * dayColumnWidth
      + timedBlockInset
      + CGFloat(column) * (blockWidth + timedBlockColumnSpacing)
    let width = blockWidth * CGFloat(columnSpan) + timedBlockColumnSpacing * CGFloat(columnSpan - 1)
    let y = CGFloat(startMinute) / 60 * hourHeight
    let height = max(quarterHourHeight, CGFloat(durationMinutes) / 60 * hourHeight)
    return CGRect(x: x, y: y, width: width, height: height)
  }

  func timedViewportFrame(
    dayIndex: Int,
    startMinute: Int,
    durationMinutes: Int,
    column: Int,
    columnCount: Int
  ) -> CGRect {
    let frame = timedFrame(
      dayIndex: dayIndex,
      startMinute: startMinute,
      durationMinutes: durationMinutes,
      column: column,
      columnCount: columnCount,
      columnSpan: 1
    )
    return CGRect(
      x: titleColumnWidth + frame.minX - currentScrollOffsetX,
      y: headerHeight + frame.minY - currentScrollOffsetY,
      width: frame.width,
      height: frame.height
    )
  }
}
