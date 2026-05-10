import AppKit
import SwiftUI

private enum ScheduleItemVisualStyle {
  static let titleFontSize: CGFloat = 11.5
  static let supplementalFontSize = titleFontSize * 0.8
  static let secondaryTextOpacityMultiplier: Double = 0.6
  static let attachmentLinkRegex = try? NSRegularExpression(
    pattern: #"!?\[[^\]]+\]\(raw/assets/[^)]+\)"#
  )
}

struct ScheduleCurrentTimeIndicator: View {
  private static let refreshIntervalSeconds: TimeInterval = 60

  let dayRange: ClosedRange<Int>
  let dayColumnWidth: CGFloat
  let totalWidth: CGFloat
  let totalHeight: CGFloat
  let hourHeight: CGFloat
  let calendar: Calendar

  var body: some View {
    TimelineView(.periodic(from: .now, by: Self.refreshIntervalSeconds)) { context in
      ZStack(alignment: .topLeading) {
        let currentDate = context.date
        let today = calendar.startOfDay(for: currentDate)
        let days = visibleDays(relativeTo: today)
        let dayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) })

        if let dayIndex {
          let components = calendar.dateComponents([.hour, .minute, .second], from: currentDate)
          let currentMinutes =
            CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + CGFloat(components.second ?? 0) / 60
          let y = currentMinutes / 60 * hourHeight
          let startX = CGFloat(dayIndex) * dayColumnWidth

          Rectangle()
            .fill(Color.red.opacity(0.78))
            .frame(width: dayColumnWidth, height: 2)
            .offset(x: startX, y: y - 1)

          Text(currentTimeChipLabel(from: currentDate))
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.red.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
              Capsule()
                .fill(Color(nsColor: .windowBackgroundColor))
            )
            .fixedSize()
            .offset(x: startX + 2, y: y - 14)
        }
      }
      .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
    }
  }

  func visibleDays(relativeTo today: Date) -> [Date] {
    Array(dayRange).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: today)
    }
  }

  func currentTimeChipLabel(from date: Date) -> String {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    return String(format: "%02d:%02d", hour, minute)
  }
}

struct SchedulePostponeAffordance: View {
  let compact: Bool
  let motionQuality: MotionQuality
  let isPinnedVisible: Bool
  let onTrigger: () -> Void

  @State var isHovering = false

  var zoneWidth: CGFloat { compact ? 24 : 26 }
  var buttonSize: CGFloat { compact ? 18 : 20 }
  var iconSize: CGFloat { compact ? 9 : 10 }
  var hoverAnimation: Animation? {
    MotionSystem.animation(for: .hoverFade, quality: motionQuality)
  }
  var shadowOpacity: Double {
    switch motionQuality {
    case .full:
      return 0.08
    case .reduced:
      return 0.04
    case .minimal, .disabled:
      return 0
    }
  }

  var body: some View {
    ZStack {
      if isHovering || isPinnedVisible {
        Button(action: onTrigger) {
          ZStack {
            Circle()
              .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))

            Image(systemName: "chevron.right")
              .font(.system(size: iconSize, weight: .bold))
              .foregroundStyle(.secondary)
              .offset(x: 0.5)
          }
          .frame(width: buttonSize, height: buttonSize)
          .shadow(color: .black.opacity(shadowOpacity), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .help("하루 뒤 올데이로 미루기")
        .transition(.opacity)
      }
    }
    .frame(width: zoneWidth)
    .frame(maxHeight: .infinity)
    .contentShape(Rectangle())
    .onHover { hovering in
      if let hoverAnimation {
        withAnimation(hoverAnimation) {
          isHovering = hovering
        }
      } else {
        MotionTransaction.withoutAnimation {
          isHovering = hovering
        }
      }
    }
  }
}

struct ScheduleTimedEntry: Identifiable {
  let id: String
  let dayIndex: Int
  let startMinute: Int
  let durationMinutes: Int
  let endMinute: Int
  let title: String
  let subtitle: String?
  let color: Color
  let isTask: Bool
  let isPreparationSlot: Bool
  let targetCompletedWorkUnits: Int?
  let taskDescriptor: WorkspaceScheduleTaskDescriptor?
  let event: ScheduleCalendarEvent?
  let isBackgroundCalendar: Bool
  let contentTopOffset: CGFloat
}

struct ScheduleTimedBlockLayout: Identifiable {
  let id: String
  let entry: ScheduleTimedEntry
  let column: Int
  let columnCount: Int
  let columnSpan: Int

  func withContentTopOffset(_ offset: CGFloat) -> ScheduleTimedBlockLayout {
    ScheduleTimedBlockLayout(
      id: id,
      entry: ScheduleTimedEntry(
        id: entry.id,
        dayIndex: entry.dayIndex,
        startMinute: entry.startMinute,
        durationMinutes: entry.durationMinutes,
        endMinute: entry.endMinute,
        title: entry.title,
        subtitle: entry.subtitle,
        color: entry.color,
        isTask: entry.isTask,
        isPreparationSlot: entry.isPreparationSlot,
        targetCompletedWorkUnits: entry.targetCompletedWorkUnits,
        taskDescriptor: entry.taskDescriptor,
        event: entry.event,
        isBackgroundCalendar: entry.isBackgroundCalendar,
        contentTopOffset: offset
      ),
      column: column,
      columnCount: columnCount,
      columnSpan: columnSpan
    )
  }
}

struct ScheduleBackgroundLabelAvoidanceBlock: Hashable {
  let dayIndex: Int
  let startMinute: Int
  let endMinute: Int
}

enum ScheduleBackgroundLabelAvoidancePolicy {
  static let estimatedLabelHeight: CGFloat = 44
  static let labelGap: CGFloat = 6

  static func topOffset(
    for background: ScheduleBackgroundLabelAvoidanceBlock,
    foregroundBlocks: [ScheduleBackgroundLabelAvoidanceBlock],
    hourHeight: CGFloat,
    labelHeight: CGFloat = estimatedLabelHeight,
    gap: CGFloat = labelGap
  ) -> CGFloat {
    guard hourHeight > 0, labelHeight > 0 else { return 0 }

    let backgroundStart = min(max(0, background.startMinute), 24 * 60)
    let backgroundEnd = min(max(backgroundStart, background.endMinute), 24 * 60)
    guard backgroundEnd > backgroundStart else { return 0 }

    let labelDurationMinutes = max(1, Int(ceil(labelHeight / hourHeight * 60)))
    let gapMinutes = max(0, Int(ceil(gap / hourHeight * 60)))
    let latestLabelStart = max(backgroundStart, backgroundEnd - labelDurationMinutes)
    guard latestLabelStart > backgroundStart else { return 0 }

    var candidateStart = backgroundStart
    let obstacles = foregroundBlocks
      .filter { block in
        block.dayIndex == background.dayIndex
          && block.startMinute < backgroundEnd
          && block.endMinute > backgroundStart
      }
      .sorted { lhs, rhs in
        if lhs.startMinute != rhs.startMinute {
          return lhs.startMinute < rhs.startMinute
        }
        return lhs.endMinute < rhs.endMinute
      }

    for obstacle in obstacles {
      if candidateStart + labelDurationMinutes <= obstacle.startMinute {
        break
      }
      if candidateStart < obstacle.endMinute {
        candidateStart = obstacle.endMinute + gapMinutes
      }
      if candidateStart > latestLabelStart {
        candidateStart = latestLabelStart
        break
      }
    }

    guard candidateStart > backgroundStart else { return 0 }
    return CGFloat(candidateStart - backgroundStart) / 60 * hourHeight
  }
}

enum ScheduleTimedBlockHitPriorityPolicy {
  private static let backgroundCalendarPriority = 1.0
  private static let calendarPriority = 2.0
  private static let taskPriority = 3.0
  private static let selectedTaskPriority = 4.0

  static func zIndex(
    isTask: Bool,
    taskID: UUID?,
    selectedTaskID: UUID?,
    startMinute: Int,
    isBackgroundCalendar: Bool
  ) -> Double {
    if isBackgroundCalendar {
      return backgroundCalendarPriority
    }
    if isTask {
      if let taskID, taskID == selectedTaskID {
        return selectedTaskPriority + earlierStartTieBreaker(startMinute)
      }
      return taskPriority + earlierStartTieBreaker(startMinute)
    }
    return calendarPriority + earlierStartTieBreaker(startMinute)
  }

  private static func earlierStartTieBreaker(_ startMinute: Int) -> Double {
    let boundedStartMinute = min(max(0, startMinute), 24 * 60)
    return Double((24 * 60) - boundedStartMinute) / 10_000
  }
}

enum ScheduleResizePreviewStylePolicy {
  static let targetBlockOpacity = 0.96

  static func sourceBlockOpacity(
    isResizing: Bool,
    isDragging: Bool,
    dragPlaceholderOpacity: Double = 0.34
  ) -> Double {
    if isResizing {
      return 0
    }
    return isDragging ? dragPlaceholderOpacity : 1
  }
}

struct ScheduleLayoutCache {
  let timedEntries: [ScheduleTimedBlockLayout]
  let allDayEntries: [ScheduleAllDayLayout]
  let backgroundTimedEntries: [ScheduleTimedBlockLayout]
  let backgroundAllDayEntries: [ScheduleAllDayLayout]
}

enum ScheduleDayBackgroundSection {
  case header
  case allDayRail
  case timeline
}

enum ScheduleTimedBlockDensity {
  case compact
  case standard
  case expanded
}

extension ScheduleBoardView {
  var scheduleBoardLeftAxisSection: some View {
    leftAxisContent
  }

  var scheduleBoardInteractionOverlaySection: some View {
    floatingInteractionOverlay()
  }

  func scheduleTimedGridSection(
    timedEntries: [ScheduleTimedBlockLayout],
    backgroundTimedEntries: [ScheduleTimedBlockLayout]
  ) -> some View {
    boardContent(
      timedEntries: timedEntries,
      backgroundTimedEntries: backgroundTimedEntries
    )
  }

  func boardContent(
    timedEntries: [ScheduleTimedBlockLayout],
    backgroundTimedEntries: [ScheduleTimedBlockLayout]
  ) -> some View {
    HStack(spacing: 0) {
      Color.clear
        .frame(width: titleColumnWidth, height: boardHeight)

      VStack(spacing: 0) {
        Color.clear
          .frame(width: dayColumnsWidth, height: headerHeight)

        ZStack(alignment: .topLeading) {
          gridBackground

          ForEach(backgroundTimedEntries) { layout in
            timedBlock(layout)
              .allowsHitTesting(false)
          }

          currentTimeIndicator
            .allowsHitTesting(false)

          ForEach(timedEntries) { layout in
            timedBlock(layout)
          }
        }
        .frame(width: dayColumnsWidth, height: timeGridHeight, alignment: .topLeading)
        .clipped()
      }
      .frame(width: dayColumnsWidth, height: boardHeight, alignment: .topLeading)
    }
    .frame(width: boardWidth, height: boardHeight, alignment: .topLeading)
  }

  var leftAxisContent: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        Color.clear
          .frame(height: dateHeaderHeight)

        HStack {
          Text("All-day")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.trailing, 6)
        }
        .frame(
          maxWidth: .infinity,
          minHeight: allDayRailVisibleHeight,
          maxHeight: allDayRailVisibleHeight,
          alignment: .trailing
        )
        .background(Color.clear)
      }
      .background(
        Rectangle()
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
      )

      VStack(spacing: 0) {
        ForEach(0..<hourCount, id: \.self) { hour in
          HStack {
            Text(hourLabel(hour))
              .font(.system(size: 10, weight: .medium, design: .monospaced))
              .foregroundStyle(.secondary)
              .padding(.top, 2)
              .padding(.trailing, 8)
          }
          .frame(
            maxWidth: .infinity,
            minHeight: hourHeight,
            maxHeight: hourHeight,
            alignment: .topTrailing
          )
        }
      }
      .background(
        Rectangle()
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
      )
    }
    .frame(width: titleColumnWidth, height: boardHeight, alignment: .top)
  }

  var scheduleTimedQuickAddSection: some View {
    ScheduleQuickAddContextMenuRegion(
      isAllDayRegion: false,
      canCreateTask: scheduleQuickAddProjectID != nil,
      projects: scheduleQuickAddProjects,
      defaultProjectID: scheduleQuickAddProjectID,
      onCreateTask: createScheduleTask,
      onUnavailable: { handleUnavailableScheduleQuickAdd() },
      onBackgroundTap: handleScheduleBackgroundTap,
      allowsTimedDragCreation: true,
      onTimedDragPreview: updateTimedQuickCreateSelection,
      onTimedDragCommit: commitTimedQuickCreateSelection,
      onTimedDragCancel: cancelTimedQuickCreateSelection
    )
  }

  var gridBackground: some View {
    ZStack(alignment: .topLeading) {
      scheduleTimedQuickAddSection
        .frame(width: dayColumnsWidth, height: timeGridHeight)

      ZStack(alignment: .topLeading) {
        Rectangle()
          .fill(Color(nsColor: .windowBackgroundColor))

        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
          Rectangle()
            .fill(dayColumnBackgroundColor(for: day, section: .timeline))
            .frame(width: dayColumnWidth, height: timeGridHeight)
            .offset(x: CGFloat(index) * dayColumnWidth)

          Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: timeGridHeight)
            .offset(x: CGFloat(index) * dayColumnWidth)
        }

        Rectangle()
          .fill(Color.primary.opacity(0.08))
          .frame(width: 1, height: timeGridHeight)
          .offset(x: dayColumnsWidth - 1)

        ForEach(0...hourCount, id: \.self) { hour in
          Rectangle()
            .fill(Color.primary.opacity(hour == 0 ? 0 : 0.08))
            .frame(width: dayColumnsWidth, height: 1)
            .offset(y: CGFloat(hour) * hourHeight)
        }

        ForEach(0..<hourCount, id: \.self) { hour in
          Rectangle()
            .fill(Color.primary.opacity(0.02))
            .frame(width: dayColumnsWidth, height: 1)
            .offset(y: CGFloat(hour) * hourHeight + hourHeight / 2)
        }
      }
      .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  var currentTimeIndicator: some View {
    if isActive {
      ScheduleCurrentTimeIndicator(
        dayRange: dayRange,
        dayColumnWidth: dayColumnWidth,
        totalWidth: dayColumnsWidth,
        totalHeight: timeGridHeight,
        hourHeight: hourHeight,
        calendar: calendar
      )
    }
  }

  func timedBlock(_ layout: ScheduleTimedBlockLayout) -> some View {
    let frame = timedFrame(for: layout)
    let blockHeight = max(quarterHourHeight, frame.height)
    let taskDescriptor = layout.entry.taskDescriptor
    let event = layout.entry.event
    let isDragging = activeTaskDrag?.entryID == layout.entry.id
    let isResizing = activeTaskResize?.entryID == layout.entry.id
    let isEventDragging = activeCalendarDrag?.eventID == event?.id
    let isEventResizing = activeCalendarResize?.eventID == event?.id
    let viewportFrame = CGRect(
      x: titleColumnWidth + frame.minX - currentScrollOffsetX,
      y: headerHeight + frame.minY - currentScrollOffsetY,
      width: frame.width,
      height: blockHeight
    )

    return Group {
      if layout.entry.isTask, let taskDescriptor {
        let taskRow = taskDescriptor.taskRow
        scheduleTaskBlock(
          taskDescriptor: taskDescriptor,
          entryID: layout.entry.id,
          day: days[layout.entry.dayIndex],
          title: layout.entry.title,
          subtitle: layout.entry.subtitle,
          color: layout.entry.color,
          isSelected: selectedScheduleTaskID == taskRow.id,
          isPreparationSlot: layout.entry.isPreparationSlot,
          targetCompletedWorkUnits: layout.entry.targetCompletedWorkUnits,
          startMinute: layout.entry.startMinute,
          durationMinutes: layout.entry.durationMinutes,
          timeLabel: timeRangeLabel(
            startMinute: layout.entry.startMinute,
            durationMinutes: layout.entry.durationMinutes
          ),
          blockHeight: blockHeight,
          viewportFrame: viewportFrame,
          postponeAction: postponeScheduleAction(
            for: taskDescriptor,
            day: days[layout.entry.dayIndex],
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
            originalDay: days[layout.entry.dayIndex],
            originalTimeMinutes: layout.entry.startMinute,
            originalDurationMinutes: layout.entry.durationMinutes,
            itemFrame: frame,
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
              blockHeight: blockHeight,
              startMinute: layout.entry.startMinute,
              durationMinutes: layout.entry.durationMinutes,
              viewportFrame: viewportFrame
            )
            .gesture(
              eventDragGesture(
                for: event,
                itemFrame: frame,
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
      resizeHandle(
        for: taskDescriptor,
        entryID: entryID,
        day: day,
        originalTimeMinutes: startMinute,
        durationMinutes: durationMinutes,
        edge: .start,
        originalViewportFrame: viewportFrame,
        isPreparationSlot: isPreparationSlot,
        targetCompletedWorkUnits: targetCompletedWorkUnits
      )
    }
    .overlay(alignment: .bottom) {
      resizeHandle(
        for: taskDescriptor,
        entryID: entryID,
        day: day,
        originalTimeMinutes: startMinute,
        durationMinutes: durationMinutes,
        edge: .end,
        originalViewportFrame: viewportFrame,
        isPreparationSlot: isPreparationSlot,
        targetCompletedWorkUnits: targetCompletedWorkUnits
      )
    }
  }

  func scheduleEventBlock(
    event: ScheduleCalendarEvent,
    title: String,
    subtitle: String?,
    color: Color,
    timeLabel: String?,
    blockHeight: CGFloat,
    startMinute _: Int,
    durationMinutes: Int,
    viewportFrame: CGRect,
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
        recurrenceIndicator(fontSize: 9.5)
          .padding(.top, 6)
          .padding(.trailing, 8)
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
      if event.canEditTiming && !event.spansMultipleDays && !isBackgroundCalendar {
        eventResizeHandle(
          for: event,
          edge: .start,
          originalViewportFrame: viewportFrame
        )
      }
    }
    .overlay(alignment: .bottom) {
      if event.canEditTiming && !event.spansMultipleDays && !isBackgroundCalendar {
        eventResizeHandle(
          for: event,
          edge: .end,
          originalViewportFrame: viewportFrame
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
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
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
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
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
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
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
    let titleColor: Color = isBackgroundCalendar ? .secondary.opacity(0.78) : .primary
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
      .padding(.leading, 10)
      .padding(.trailing, 8)
      .padding(.top, 5 + contentTopOffset)
      .padding(.bottom, 5)

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
      .padding(.leading, 10)
      .padding(.trailing, 8)
      .padding(.top, 6 + contentTopOffset)
      .padding(.bottom, 6)

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
      .padding(.leading, 10)
      .padding(.trailing, 8)
      .padding(.top, 7 + contentTopOffset)
      .padding(.bottom, 7)
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
      .padding(.leading, 5)
      .padding(.trailing, 9)
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
      let titleColor: Color = isBackgroundCalendar ? .secondary.opacity(0.78) : .primary
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
          recurrenceIndicator(fontSize: 9)
        }
      }
      .padding(.leading, 5)
      .padding(.trailing, 9)
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
        recurrenceIndicator(fontSize: 9.5)
          .padding(.top, 6)
          .padding(.trailing, 8)
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
        color: Color.black.opacity(0.18),
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
        .fill(color.opacity(isAllDay ? 0.08 : 0.1))

      ScheduleRoundedRectangleStrokeOverlay(
        cornerRadius: isAllDay ? 8 : 6,
        color: color.opacity(0.72),
        lineWidth: 1.2,
        lineCap: .round,
        dash: [5, 4]
      )

      if let label {
        Text(label)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(color.opacity(0.92))
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
      .fill(Color(nsColor: .windowBackgroundColor).opacity(0.58))
      .overlay {
        ScheduleRoundedRectangleStrokeOverlay(
          cornerRadius: isAllDay ? 8 : 6,
          color: Color.primary.opacity(0.08),
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
    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
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
        recurrenceIndicator(fontSize: 9.5)
          .padding(.top, 6)
          .padding(.trailing, 8)
      }
    }
    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    .offset(x: frame.minX, y: frame.minY)
    .opacity(ScheduleResizePreviewStylePolicy.targetBlockOpacity)
    .overlay {
      ScheduleRoundedRectangleStrokeOverlay(
        cornerRadius: 6,
        color: color.opacity(0.72),
        lineWidth: 1
      )
    }
    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
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
    originalViewportFrame: CGRect
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
        eventResizeGesture(for: event, edge: edge, originalViewportFrame: originalViewportFrame)
      )
      .help(edge == .start ? "시작 시간 조절" : "종료 시간 조절")
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
          let taskDescriptor = cachedWorkspaceScheduleTasksByID[dragState.taskID]
        {
          let preview = preview(for: dragState)
          let dropFrame = dragDropTargetViewportFrame(for: dragState, preview: preview)
          let ghostFrame = dragGhostViewportFrame(for: dragState)
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
                timeLabel: originalTaskDragTimeLabel(for: dragState),
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
          let ghostFrame = dragGhostViewportFrame(for: dragState)
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
                timeLabel: originalCalendarDragTimeLabel(for: dragState),
                blockHeight: ghostFrame.height,
                durationMinutes: dragState.originalDurationMinutes ?? timedMinimumDuration
              )
            }
          }
        }

        if let resizeState = activeTaskResize,
          let taskDescriptor = cachedWorkspaceScheduleTasksByID[resizeState.taskID]
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
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary.opacity(0.88))
      Text(timeRangeLabel(startMinute: selection.startMinutes, durationMinutes: selection.durationMinutes))
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.accentColor.opacity(0.14))
    )
    .overlay {
      ScheduleRoundedRectangleStrokeOverlay(
        cornerRadius: 12,
        color: Color.accentColor.opacity(0.6),
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
    let frameSize: CGFloat = compact ? 14 : 16
    let strokeWidth: CGFloat = compact ? 1.55 : 1.75
    let arrowFontSize: CGFloat = CGFloat(compact ? 9 : 10) * 0.9215
    let glyphColor: Color = isSelected ? .white : color

    return ZStack {
      if isCompleted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: compact ? 13 : 14, weight: .semibold))
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
          color: color.opacity(0.95),
          lineWidth: strokeWidth,
          lineCap: .round,
          dash: [0.1, 3.15]
        )
      } else {
        ScheduleCircleStrokeOverlay(
          color: color.opacity(0.9),
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
      return isCompleted ? Color.white.opacity(0.84) : .white
    }
    return isCompleted ? .secondary : .primary
  }

  func scheduleTaskSecondaryTextColor(isSelected: Bool) -> Color {
    isSelected
      ? Color.white.opacity(0.78 * ScheduleItemVisualStyle.secondaryTextOpacityMultiplier)
      : Color.secondary.opacity(ScheduleItemVisualStyle.secondaryTextOpacityMultiplier)
  }

  func scheduleEventSecondaryTextColor(isBackgroundCalendar: Bool) -> Color {
    let baseOpacity = isBackgroundCalendar ? 0.68 : 1.0
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
    guard let regex = ScheduleItemVisualStyle.attachmentLinkRegex else { return 0 }
    return regex.numberOfMatches(
      in: noteText,
      range: NSRange(noteText.startIndex..<noteText.endIndex, in: noteText)
    )
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
        return Color.accentColor.opacity(0.08)
      }
      if isWeekend {
        return Color.primary.opacity(0.02)
      }
      return Color(nsColor: .windowBackgroundColor)
    case .allDayRail:
      return Color(nsColor: .windowBackgroundColor)
    case .timeline:
      if isToday {
        return Color.accentColor.opacity(0.045)
      }
      if isWeekend {
        return Color.primary.opacity(0.018)
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

  func resizePreviewViewportFrame(
    for resizeState: ScheduleTaskResizeState,
    preview: ScheduleInteractionPreview
  ) -> CGRect {
    guard let timeMinutes = preview.timeMinutes else {
      return resizeState.originalViewportFrame
    }

    let durationMinutes = preview.durationMinutes ?? timedMinimumDuration
    return CGRect(
      x: resizeState.originalViewportFrame.minX,
      y: headerHeight + CGFloat(timeMinutes) / 60 * hourHeight - currentScrollOffsetY,
      width: resizeState.originalViewportFrame.width,
      height: max(quarterHourHeight, CGFloat(durationMinutes) / 60 * hourHeight)
    )
  }

  func resizePreviewViewportFrame(
    for resizeState: ScheduleCalendarResizeState,
    preview: ScheduleInteractionPreview
  ) -> CGRect {
    guard let timeMinutes = preview.timeMinutes else {
      return resizeState.originalViewportFrame
    }

    let durationMinutes = preview.durationMinutes ?? timedMinimumDuration
    return CGRect(
      x: resizeState.originalViewportFrame.minX,
      y: headerHeight + CGFloat(timeMinutes) / 60 * hourHeight - currentScrollOffsetY,
      width: resizeState.originalViewportFrame.width,
      height: max(quarterHourHeight, CGFloat(durationMinutes) / 60 * hourHeight)
    )
  }

  func dragDropTargetViewportFrame(
    for dragState: ScheduleTaskDragState,
    preview: ScheduleInteractionPreview
  ) -> CGRect? {
    if isTaskDragOverExternalTarget || isTaskDragOutsideBoardBounds(dragState) {
      return nil
    }
    return dragDropTargetViewportFrame(
      for: preview,
      allDayViewportY: allDayPreviewViewportY(for: dragState, preview: preview)
    )
  }

  func dragDropTargetViewportFrame(
    for dragState: ScheduleCalendarDragState,
    preview: ScheduleInteractionPreview
  ) -> CGRect? {
    let visualPreview: ScheduleInteractionPreview
    if let timeMinutes = preview.timeMinutes, let durationMinutes = preview.durationMinutes {
      visualPreview = ScheduleInteractionPreview(
        day: preview.day,
        timeMinutes: timeMinutes,
        durationMinutes: min(durationMinutes, max(timedMinimumDuration, (24 * 60) - timeMinutes))
      )
    } else {
      visualPreview = preview
    }
    return dragDropTargetViewportFrame(
      for: visualPreview,
      allDayViewportY: allDayPreviewViewportY(for: dragState, preview: preview)
    )
  }

  func dragDropTargetViewportFrame(
    for preview: ScheduleInteractionPreview,
    allDayViewportY: CGFloat? = nil
  ) -> CGRect? {
    guard let day = preview.day,
      let dayIndex = dayIndexByDate[day]
    else {
      return nil
    }

    if let timeMinutes = preview.timeMinutes {
      let durationMinutes = preview.durationMinutes ?? timedMinimumDuration
      return snappedTimedDragPreviewFrame(
        dayIndex: dayIndex,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes
      )
    }

    return snappedAllDayDragPreviewFrame(dayIndex: dayIndex, viewportY: allDayViewportY)
  }

  func allDayPreviewViewportY(
    for dragState: ScheduleTaskDragState,
    preview: ScheduleInteractionPreview
  ) -> CGFloat? {
    allDayPreviewViewportY(
      preview: preview,
      pointerViewportY: dragState.currentPointerViewportLocation?.y,
      originalPointerViewportY: dragState.originalPointerViewportY,
      originalViewportMinY: dragState.originalViewportFrame.minY,
      translationHeight: dragState.translation.height
    )
  }

  func allDayPreviewViewportY(
    for dragState: ScheduleCalendarDragState,
    preview: ScheduleInteractionPreview
  ) -> CGFloat? {
    allDayPreviewViewportY(
      preview: preview,
      pointerViewportY: dragState.currentPointerViewportLocation?.y,
      originalPointerViewportY: dragState.originalPointerViewportY,
      originalViewportMinY: dragState.originalViewportFrame.minY,
      translationHeight: dragState.translation.height
    )
  }

  func allDayPreviewViewportY(
    preview: ScheduleInteractionPreview,
    pointerViewportY: CGFloat?,
    originalPointerViewportY: CGFloat,
    originalViewportMinY: CGFloat,
    translationHeight: CGFloat
  ) -> CGFloat? {
    guard preview.timeMinutes == nil else { return nil }
    return ScheduleDragDropInteractionLayer.allDayPreviewViewportY(
      pointerViewportY: pointerViewportY,
      originalPointerViewportY: originalPointerViewportY,
      originalViewportMinY: originalViewportMinY,
      translationHeight: translationHeight,
      dateHeaderHeight: dateHeaderHeight,
      allDayRailPadding: allDayRailPadding,
      allDayRailVisibleHeight: allDayRailVisibleHeight,
      previewHeight: allDayRowHeight - 4
    )
  }

  func isTaskDragOutsideBoardBounds(_ dragState: ScheduleTaskDragState) -> Bool {
    guard let pointerX = dragState.currentPointerViewportLocation?.x else {
      return false
    }
    return pointerX < 0
  }

  func dragGhostViewportFrame(for dragState: ScheduleTaskDragState) -> CGRect {
    dragState.originalViewportFrame.offsetBy(
      dx: dragState.isPreparationSlot ? 0 : dragState.translation.width,
      dy: dragState.translation.height
    )
  }

  func dragGhostViewportFrame(for dragState: ScheduleCalendarDragState) -> CGRect {
    dragState.originalViewportFrame.offsetBy(
      dx: dragState.translation.width,
      dy: dragState.translation.height
    )
  }

  func originalTaskDragTimeLabel(for dragState: ScheduleTaskDragState) -> String? {
    guard let startMinute = dragState.originalTimeMinutes else { return nil }
    let durationMinutes = dragState.originalDurationMinutes ?? timedMinimumDuration
    return timeRangeLabel(startMinute: startMinute, durationMinutes: durationMinutes)
  }

  func originalCalendarDragTimeLabel(for dragState: ScheduleCalendarDragState) -> String? {
    guard let startMinute = dragState.originalTimeMinutes else { return nil }
    let durationMinutes = dragState.originalDurationMinutes ?? timedMinimumDuration
    return timeRangeLabel(startMinute: startMinute, durationMinutes: durationMinutes)
  }

  func snappedAllDayDragPreviewFrame(dayIndex: Int, viewportY: CGFloat? = nil) -> CGRect {
    CGRect(
      x: titleColumnWidth + CGFloat(dayIndex) * dayColumnWidth - currentScrollOffsetX
        + allDayChipHorizontalInset,
      y: viewportY ?? dateHeaderHeight + allDayRailPadding,
      width: dayColumnWidth - allDayChipHorizontalInset * 2,
      height: allDayRowHeight - 4
    )
  }

  func snappedTimedDragPreviewFrame(
    dayIndex: Int,
    timeMinutes: Int,
    durationMinutes: Int
  ) -> CGRect {
    CGRect(
      x: titleColumnWidth + CGFloat(dayIndex) * dayColumnWidth - currentScrollOffsetX
        + timedBlockInset,
      y: headerHeight + CGFloat(timeMinutes) / 60 * hourHeight - currentScrollOffsetY,
      width: dayColumnWidth - timedBlockInset * 2,
      height: max(quarterHourHeight, CGFloat(durationMinutes) / 60 * hourHeight)
    )
  }

  func hourLabel(_ hour: Int) -> String {
    let normalizedHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    let suffix = hour < 12 ? "AM" : "PM"
    return "\(normalizedHour) \(suffix)"
  }
}
