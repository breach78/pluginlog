import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension TimelineBoardView {
  func boardContent(
    bars: [TimelineProjectBar],
    rowLayouts: [TimelineRowLayout],
    rowsHeight: CGFloat,
    visibleLowerOffset: Int,
    visibleUpperOffset: Int
  ) -> some View {
    HStack(spacing: 0) {
      Color.clear
        .frame(width: titleColumnWidth, height: headerHeight + rowsHeight)

      VStack(spacing: 0) {
        Color.clear
          .frame(width: timelineWidth, height: headerHeight)
        timelineRowsCanvas(
          bars: bars,
          rowLayouts: rowLayouts,
          rowsHeight: rowsHeight,
          visibleLowerOffset: visibleLowerOffset,
          visibleUpperOffset: visibleUpperOffset
        )
      }
      .frame(width: timelineWidth, height: headerHeight + rowsHeight, alignment: .topLeading)
    }
    .frame(
      width: titleColumnWidth + timelineWidth, height: headerHeight + rowsHeight,
      alignment: .topLeading)
  }

  func leftColumnContent(
    bars: [TimelineProjectBar],
    rowLayouts: [TimelineRowLayout],
    rowsHeight: CGFloat,
    visibleLowerOffset: Int,
    visibleUpperOffset: Int
  ) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        WorkspaceProjectSortButton(
          sortMode: Binding(
            get: { projectListSortMode },
            set: { projectListSortMode = $0 }
          ),
          context: .timeline
        )

        Button {
          createTimelineProject()
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.plain)
        .disabled(isCreatingProject)
        .help("새 프로젝트 생성")

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .frame(width: titleColumnWidth, height: headerHeight, alignment: .leading)
      .background(Color(nsColor: .windowBackgroundColor))

      VStack(alignment: .leading, spacing: 0) {
        ZStack(alignment: .topLeading) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
              leftProjectRow(
                for: bar,
                rowLayout: rowLayouts[index],
                showsPriorityBoundary: showsPriorityBoundary(before: index, in: bars),
                index: index,
                totalCount: bars.count,
                visibleLowerOffset: visibleLowerOffset,
                visibleUpperOffset: visibleUpperOffset
              )
            }
          }
        }
      }
      .frame(width: titleColumnWidth, height: rowsHeight, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
      .onDrop(
        of: [UTType.text.identifier],
        delegate: TimelineProjectListDropDelegate(
          targets: projectDropTargets(for: bars, rowLayouts: rowLayouts),
          draggingProjectID: $draggingProjectID,
          dropIndicator: $projectDropIndicator,
          taskDropTargetProjectID: $taskDropTargetProjectID,
          onPerformDrop: { draggedID, targetID, placement in
            reorderProjects(draggedID: draggedID, targetID: targetID, placement: placement)
          },
          onPerformTaskDrop: { taskID, targetID in
            moveTaskToProjectTop(taskID: taskID, targetProjectID: targetID)
          }
        )
      )
    }
    .frame(width: titleColumnWidth, height: headerHeight + rowsHeight, alignment: .topLeading)
    .overlay(alignment: .leading) {
      if projectListSortMode == .priority {
        VStack(spacing: 0) {
          Color.clear
            .frame(height: headerHeight)
          priorityStageRail(
            for: bars,
            rowLayouts: rowLayouts,
            width: priorityStageRailWidth
          )
          .frame(width: priorityStageRailWidth, height: rowsHeight, alignment: .top)
        }
        .offset(x: priorityStageRailLeadingOffset)
        .allowsHitTesting(false)
      }
    }
    .onHover { isHovering in
      isHoveringPinnedLeftColumn = isHovering
      if isHovering {
        cancelTimelineTaskBadgeOverlay()
        cancelTimelineDayHeaderOverlay()
      }
    }
  }

  var priorityStageRailLeadingOffset: CGFloat {
    let titleAreaMaxX = titleColumnWidth - timelineTitleColumnHorizontalPadding
      - priorityCountLaneReserve
    return titleAreaMaxX - (priorityStageRailWidth * 0.5) + 5
  }

  var timelineHeaderStripSection: some View {
    HStack(spacing: 0) {
      ForEach(dayOffsets, id: \.self) { offset in
        dayHeaderCell(offset: offset)
      }
    }
    .frame(width: timelineWidth, height: headerHeight, alignment: .leading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  func dayHeaderCell(offset: Int) -> some View {
    let date = date(for: offset)
    let day = calendar.component(.day, from: date)
    let isToday = offset == 0
    let isSunday = calendar.component(.weekday, from: date) == 1
    let isSaturday = calendar.component(.weekday, from: date) == 7
    let dateTextColor: Color =
      isSunday ? .red : (isSaturday ? .orange : (isToday ? .blue : .primary))
    let weekdayTextColor: Color = isSunday ? .red : (isSaturday ? .orange : .secondary)

    return VStack(spacing: 0) {
      Color.clear
        .frame(height: monthHeaderReservedHeight)

      VStack(spacing: 2) {
        Text(date, format: .dateTime.locale(Locale(identifier: "ko_KR")).weekday(.narrow))
          .font(.caption2)
          .foregroundStyle(weekdayTextColor)

        Text("\(day)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(dateTextColor)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: dayColumnWidth, height: headerHeight)
    .background(alignment: .bottom) {
      if isToday {
        Color.blue.opacity(0.12)
          .frame(height: max(0, headerHeight - monthHeaderReservedHeight))
      }
    }
    .overlay(alignment: .trailing) {
      Rectangle()
        .fill(Color.secondary.opacity(0.12))
        .frame(width: 1)
    }
    .allowsHitTesting(!isTimelineScrolling)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      openScheduleDay(for: offset)
    }
  }

  func timelineRowsCanvas(
    bars: [TimelineProjectBar],
    rowLayouts: [TimelineRowLayout],
    rowsHeight: CGFloat,
    visibleLowerOffset: Int,
    visibleUpperOffset: Int
  ) -> some View {
    let occupiedRowsHeight = totalRowsHeight(for: rowLayouts)

    return ZStack(alignment: .topLeading) {
      Canvas { context, _ in
        var gridPath = Path()
        for index in dayOffsets.indices {
          let x = CGFloat(index) * dayColumnWidth
          gridPath.addRect(CGRect(x: x, y: 0, width: 1, height: rowsHeight))
        }
        context.fill(gridPath, with: .color(Color.secondary.opacity(0.10)))
      }
      .frame(width: timelineWidth, height: rowsHeight, alignment: .topLeading)

      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
          timelineRow(
            for: bar,
            rowLayout: rowLayouts[index],
            showsPriorityBoundary: showsPriorityBoundary(before: index, in: bars),
            index: index,
            totalCount: bars.count,
            visibleLowerOffset: visibleLowerOffset,
            visibleUpperOffset: visibleUpperOffset
          )
        }
      }
      .frame(width: timelineWidth, alignment: .topLeading)

      if dayRange.contains(0) {
        Rectangle()
          .fill(Color.blue.opacity(0.62))
          .frame(width: 2, height: occupiedRowsHeight)
          .offset(x: CGFloat(-dayRange.lowerBound) * dayColumnWidth)
          .allowsHitTesting(false)
      }

    }
    .frame(width: timelineWidth, height: rowsHeight, alignment: .topLeading)
  }

  func timelineRow(
    for bar: TimelineProjectBar,
    rowLayout: TimelineRowLayout,
    showsPriorityBoundary: Bool,
    index: Int,
    totalCount: Int,
    visibleLowerOffset: Int,
    visibleUpperOffset: Int
  ) -> some View {
    let isSelected = projectIsSelected(bar.projectID)
    let interactiveProjectID = bar.projectID
    let isProjectDropTarget =
      projectDropIndicator?.targetProjectID == interactiveProjectID
    let isTaskDropTarget =
      taskDropTargetProjectID == interactiveProjectID
    let projectColor = timelineColor(for: bar)
    let mutedProjectColor = timelineMutedColor(for: bar)

    return ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: 6)
        .fill(
          rowBackgroundFill(
            for: bar,
            isSelected: isSelected,
            isProjectDropTarget: isProjectDropTarget,
            isTaskDropTarget: isTaskDropTarget,
            inLeftColumn: false
          )
        )
        .frame(width: timelineWidth, height: rowLayout.metrics.height)

      if let segment = segmentFrame(for: bar) {
        RoundedRectangle(cornerRadius: 6)
          .fill(mutedProjectColor.opacity(isSelected ? 0.74 : 0.52))
          .frame(width: segment.width, height: rowLayout.metrics.contentHeight)
          .offset(x: segment.x)
      }

      if let activeSegment = activeSegmentFrame(for: bar) {
        RoundedRectangle(cornerRadius: 6)
          .fill(projectColor.opacity(isSelected ? 0.62 : 0.38))
          .frame(width: activeSegment.width, height: rowLayout.metrics.contentHeight)
          .offset(x: activeSegment.x)
      }

      if let deadlineMarker = deadlineMarkerFrame(for: bar) {
        RoundedRectangle(cornerRadius: 6)
          .fill(projectColor.opacity(isSelected ? 0.96 : 0.82))
          .frame(width: deadlineMarker.width, height: rowLayout.metrics.contentHeight)
          .offset(x: deadlineMarker.x)
      }

      taskCountBadges(
        for: bar,
        rowLayout: rowLayout,
        rowIndex: index,
        projectColor: projectColor
      )
    }
    .padding(.top, interRowTopPadding(for: index, rowLayout: rowLayout))
    .padding(.bottom, interRowBottomPadding(for: index, totalCount: totalCount, rowLayout: rowLayout))
    .contentShape(Rectangle())
    .modifier(TimelineProjectDragModifier(bar: bar, draggingProjectID: $draggingProjectID))
    .onTapGesture {
      onSelectProject(bar.projectID)
    }
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        onToggleProjectSelection(bar.projectID)
      }
    )
    .overlay(alignment: .top) {
      if showsPriorityBoundary {
        priorityBoundaryLine
      }
    }
    .overlay(alignment: projectDropIndicatorAlignment(for: interactiveProjectID)) {
      if projectDropIndicator?.targetProjectID == interactiveProjectID {
        Rectangle()
          .fill(Color.accentColor.opacity(0.9))
          .frame(height: 2)
      }
    }
    .contextMenu { projectContextMenu(for: bar) }
  }

  func leftProjectRow(
    for bar: TimelineProjectBar,
    rowLayout: TimelineRowLayout,
    showsPriorityBoundary: Bool,
    index: Int,
    totalCount: Int,
    visibleLowerOffset: Int,
    visibleUpperOffset: Int
  ) -> some View {
    let direction = offscreenDirection(
      for: bar,
      visibleLowerOffset: visibleLowerOffset,
      visibleUpperOffset: visibleUpperOffset
    )
    let remainingTaskCount = bar.remainingTaskCount
    let undatedRemainingTaskCount = bar.undatedRemainingTaskCount
    let interactiveProjectID = bar.projectID
    let inlineControlHeight = rowLayout.metrics.height

    return HStack(spacing: 8) {
      progressStageMenu(for: bar, rowHeight: inlineControlHeight)

      HStack(spacing: 8) {
        Text(bar.title)
          .lineLimit(1)
          .fontWeight(projectIsSelected(bar.projectID) ? .semibold : .regular)
        Spacer(minLength: 0)
        if remainingTaskCount > 0 {
          taskCountLabel(
            undatedRemainingTaskCount: undatedRemainingTaskCount,
            remainingTaskCount: remainingTaskCount
          )
          .frame(minWidth: 20, alignment: .trailing)
        }
        if direction == .left {
          Button {
            scrollToNearestBarEdge(
              for: bar,
              direction: .left,
              visibleLowerOffset: visibleLowerOffset,
              visibleUpperOffset: visibleUpperOffset
            )
          } label: {
            Image(systemName: "arrowtriangle.left.fill")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.secondary)
              .frame(width: 18, height: inlineControlHeight, alignment: .center)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        } else if direction == .right {
          Button {
            scrollToNearestBarEdge(
              for: bar,
              direction: .right,
              visibleLowerOffset: visibleLowerOffset,
              visibleUpperOffset: visibleUpperOffset
            )
          } label: {
            Image(systemName: "arrowtriangle.right.fill")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.secondary)
              .frame(width: 18, height: inlineControlHeight, alignment: .center)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.horizontal, 12)
    .frame(width: titleColumnWidth, height: rowLayout.metrics.height, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(
          rowBackgroundFill(
            for: bar,
            isSelected: projectIsSelected(bar.projectID),
            isProjectDropTarget:
              projectDropIndicator?.targetProjectID == interactiveProjectID,
            isTaskDropTarget:
              taskDropTargetProjectID == interactiveProjectID,
            inLeftColumn: true
          )
        )
    )
    .padding(.top, interRowTopPadding(for: index, rowLayout: rowLayout))
    .padding(
      .bottom,
      interRowBottomPadding(for: index, totalCount: totalCount, rowLayout: rowLayout)
    )
    .contentShape(Rectangle())
    .modifier(TimelineProjectDragModifier(bar: bar, draggingProjectID: $draggingProjectID))
    .gesture(
      TapGesture(count: 2)
        .onEnded {
          showTimelineProjectListPopover(bar.projectID)
        }
        .exclusively(
          before: TapGesture()
            .onEnded {
              onSelectProject(bar.projectID)
            }
        )
    )
    .popover(isPresented: timelineProjectListPopoverBinding(for: bar.projectID)) {
      timelineProjectListPopover(for: bar)
    }
    .overlay(alignment: .top) {
      if showsPriorityBoundary {
        priorityBoundaryLine
      }
    }
    .overlay(alignment: projectDropIndicatorAlignment(for: interactiveProjectID)) {
      if projectDropIndicator?.targetProjectID == interactiveProjectID {
        Rectangle()
          .fill(Color.accentColor.opacity(0.9))
          .frame(height: 2)
      }
    }
    .contextMenu { projectContextMenu(for: bar) }
  }

  func timelineProjectListPopover(for bar: TimelineProjectBar) -> some View {
    let entries = timelineProjectListPopoverEntries(for: bar.projectID)
    let projectColor = timelineColor(for: bar)

    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Circle()
          .fill(projectColor)
          .frame(width: 7, height: 7)

        Text(timelinePreviewTitle(for: bar.title))
          .font(.caption.weight(.semibold))
          .foregroundStyle(projectColor)
          .lineLimit(1)

        Spacer(minLength: 0)

        Text("\(entries.count)")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      if entries.isEmpty {
        Text("할일 없음")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 7) {
            ForEach(entries) { entry in
              timelineProjectListPopoverTaskRow(
                entry,
                projectID: bar.projectID,
                projectColor: projectColor
              )
            }
          }
          .padding(.vertical, 1)
        }
        .frame(maxHeight: 360)
      }
    }
    .padding(10)
    .frame(width: timelineProjectListPopoverWidth, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(nsColor: NSColor(calibratedWhite: 0.985, alpha: 1)))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.8)
    }
    .compositingGroup()
    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
  }

  func timelineProjectListPopoverTaskRow(
    _ entry: ScheduleSliceEntry,
    projectID: UUID,
    projectColor: Color
  ) -> some View {
    let isOverdue = timelineProjectListEntryIsOverdue(entry)

    return HStack(alignment: .top, spacing: 8) {
      if entry.isCompleted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(projectColor.opacity(0.9))
          .frame(width: 14, height: 18, alignment: .top)
      } else {
        Button {
          completeTimelineTask(entry.taskID, projectID: projectID)
        } label: {
          timelineTaskToggleMarker(isOverdue: isOverdue)
            .frame(width: 14, height: 18, alignment: .top)
        }
        .buttonStyle(.plain)
      }

      Button {
        onEditTask(
          WorkspaceTaskEditPanelTarget(
            projectID: projectID,
            taskID: entry.taskID,
            initialFields: timelineTaskEditFields(for: entry)
          )
        )
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(timelinePreviewTitle(for: entry.title))
            .font(.system(size: 12))
            .foregroundStyle(entry.isCompleted ? Color.secondary : Color.primary)
            .strikethrough(entry.isCompleted, color: Color.secondary.opacity(0.55))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let dateText = timelineProjectListDateText(for: entry) {
            Text(dateText)
              .font(.caption2)
              .foregroundStyle(isOverdue ? Color.red : Color.secondary.opacity(0.9))
              .lineLimit(1)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  func timelineProjectListPopoverEntries(for projectID: UUID) -> [ScheduleSliceEntry] {
    TimelineBoardReadPath.projectListPopoverEntries(
      from: workspaceTimelineScheduleEntriesByProjectID[projectID] ?? []
    )
  }

  func timelineProjectListDateText(for entry: ScheduleSliceEntry) -> String? {
    guard
      let date = ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: entry.dueDate,
        startDate: entry.startDate,
        displayedDate: entry.displayedDate
      )
    else {
      return nil
    }

    let locale = Locale(identifier: "ko_KR")
    if entry.scheduleHasExplicitTime {
      return date.formatted(
        .dateTime
          .locale(locale)
          .month(.abbreviated)
          .day()
          .hour(.twoDigits(amPM: .omitted))
          .minute(.twoDigits)
      )
    }

    return date.formatted(.dateTime.locale(locale).month(.abbreviated).day())
  }

  func timelineProjectListEntryIsOverdue(_ entry: ScheduleSliceEntry) -> Bool {
    guard !entry.isCompleted else { return false }
    guard
      let date = ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: entry.dueDate,
        startDate: entry.startDate,
        displayedDate: entry.displayedDate
      )
    else {
      return false
    }
    return calendar.startOfDay(for: date) < calendar.startOfDay(for: .now)
  }

  @ViewBuilder
  func projectContextMenu(for bar: TimelineProjectBar) -> some View {
    Menu("색상") {
      ForEach(reminderColorPalette, id: \.hex) { item in
        let selected = (bar.colorHex?.uppercased() == item.hex.uppercased())
        Button {
          updateTimelineProjectColor(projectID: bar.projectID, hex: item.hex)
        } label: {
          Label {
            Text(item.name)
          } icon: {
            Image(nsImage: colorSwatchMenuImage(hex: item.hex, selected: selected))
          }
        }
      }
    }

    Divider()

    Button {
      hideProjectFromTimeline(bar.projectID)
    } label: {
      Label("숨김", systemImage: "eye.slash")
    }

    Divider()

    Button(role: .destructive) {
      requestPermanentDelete(for: bar)
    } label: {
      Label("삭제", systemImage: "trash")
    }
  }

  func interRowTopPadding(for index: Int, rowLayout: TimelineRowLayout) -> CGFloat {
    rowLayout.metrics.topPadding(for: index)
  }

  func interRowBottomPadding(
    for index: Int,
    totalCount: Int,
    rowLayout: TimelineRowLayout
  ) -> CGFloat {
    rowLayout.metrics.bottomPadding(for: index, totalCount: totalCount)
  }

  var priorityBoundaryLine: some View {
    Rectangle()
      .fill(Color.secondary.opacity(0.20))
      .frame(height: 1)
      .allowsHitTesting(false)
  }

  func totalRowsHeight(for rowLayouts: [TimelineRowLayout]) -> CGFloat {
    guard let lastRowLayout = rowLayouts.last else {
      return 1
    }
    return lastRowLayout.topY + lastRowLayout.metrics.height
  }

  @ViewBuilder
  func taskCountBadges(
    for bar: TimelineProjectBar,
    rowLayout: TimelineRowLayout,
    rowIndex: Int,
    projectColor: Color
  ) -> some View {
    let badges = timelineTaskBadges(for: bar, rowIndex: rowIndex)
    let completedCounts = timelineCompletedCountLayouts(
      for: bar,
      suppressOnDatesWithPendingWork: true
    )

    ZStack(alignment: .topLeading) {
      ForEach(badges, id: \.id) { badge in
        timelineTaskCountBadge(badge, projectColor: projectColor)
          .position(x: badge.x, y: rowLayout.metrics.midpointY)
      }

      ForEach(completedCounts, id: \.id) { completedCount in
        timelineCompletedCountLabel(completedCount, projectColor: projectColor)
          .position(x: completedCount.x, y: rowLayout.metrics.midpointY)
      }
    }
    .frame(width: timelineWidth, height: rowLayout.metrics.height, alignment: .topLeading)
    .clipped()
    .allowsHitTesting(
      !appState.isEditorMotionSuppressed
        && !isInteractionObscured
        && activeTimelineDayHeaderOffset == nil
        && !appState.isHoveringTimelineDayHeaderOverlay
    )
  }

  func timelineTaskCountBadge(_ badge: TimelineTaskBadgeLayout, projectColor: Color)
    -> some View
  {
    let isLightOnly = badge.visualStyle == .light
    let isOverdue = badge.visualStyle == .overdue
    let overdueBadgeDiameter = timelineOverdueBadgeDiameter(for: badge.count)
    return Text("\(badge.count)")
      .font(.system(size: 10, weight: .semibold, design: .rounded))
      .foregroundStyle(isOverdue ? Color.red : (isLightOnly ? .secondary : .primary))
      .frame(
        width: isOverdue ? overdueBadgeDiameter : nil,
        height: isOverdue ? overdueBadgeDiameter : nil
      )
      .minimumScaleFactor(isOverdue ? 0.7 : 1.0)
      .lineLimit(1)
      .padding(.horizontal, isOverdue ? 0 : 5)
      .padding(.vertical, isOverdue ? 0 : 1.5)
      .background(
        Group {
          if isOverdue {
            Circle()
              .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
          } else {
            Capsule()
              .fill(
                isLightOnly
                  ? projectColor.opacity(0.18)
                  : Color(nsColor: .windowBackgroundColor).opacity(0.92)
              )
          }
        }
      )
      .overlay {
        Group {
          if isOverdue {
            Circle()
              .stroke(Color.red.opacity(0.95), lineWidth: 1.8)
          } else {
            Capsule()
              .stroke(
                isLightOnly ? projectColor.opacity(0.28) : Color.secondary.opacity(0.25),
                lineWidth: 0.6
              )
          }
        }
      }
      .allowsHitTesting(!isTimelineScrolling && !isInteractionObscured)
      .contentShape(Rectangle())
      .onHover { isHovering in
        updateTimelineTaskBadgeHover(badge.id, isHovering: isHovering)
      }
  }

  func timelineCompletedCountLabel(
    _ layout: TimelineCompletedCountLayout,
    projectColor: Color
  ) -> some View {
    Text("\(layout.count)")
      .font(.system(size: 10, weight: .regular, design: .rounded))
      .foregroundStyle(projectColor)
      .allowsHitTesting(!isTimelineScrolling && !isInteractionObscured)
      .contentShape(Rectangle())
      .onHover { isHovering in
        updateTimelineTaskBadgeHover(layout.hoverTargetID, isHovering: isHovering)
      }
  }

  func timelineTaskBadgeWidth(for count: Int) -> CGFloat {
    let digitCount = max(1, String(count).count)
    return max(24, CGFloat(14 + digitCount * 8))
  }

  func timelineOverdueBadgeDiameter(for count: Int) -> CGFloat {
    let digitCount = max(1, String(count).count)
    return digitCount > 1 ? 18 : 16
  }

  func timelineTaskBadgeID(for projectID: UUID, date: Date) -> String {
    let normalized = calendar.startOfDay(for: date)
    return "\(projectID.uuidString)-\(Int(normalized.timeIntervalSinceReferenceDate))"
  }

  func timelineTaskBadges(
    for bar: TimelineProjectBar,
    rowIndex: Int,
    suppressOnDatesWithCompletedWork: Bool = false
  )
    -> [TimelineTaskBadgeLayout]
  {
    let dates = Set(bar.dailyTaskCounts.keys).union(bar.dailyPlannedWorkCounts.keys)
    return dates.compactMap { date -> TimelineTaskBadgeLayout? in
      let strongCount = bar.dailyTaskCounts[date] ?? 0
      let lightCount = bar.dailyPlannedWorkCounts[date] ?? 0
      let totalCount = strongCount + lightCount
      guard totalCount > 0 else { return nil }
      if suppressOnDatesWithCompletedWork, (bar.dailyCompletedTaskCounts[date] ?? 0) > 0 {
        return nil
      }
      let offset = dayOffset(for: date)
      guard dayRange.contains(offset) else { return nil }
      let x = CGFloat(offset - dayRange.lowerBound) * dayColumnWidth + (dayColumnWidth * 0.5)
      let visualStyle = timelineTaskBadgeVisualStyle(
        date: date,
        strongCount: strongCount,
        lightCount: lightCount
      )
      return TimelineTaskBadgeLayout(
        id: timelineTaskBadgeID(for: bar.projectID, date: date),
        projectReference: bar.projectReference,
        date: date,
        rowIndex: rowIndex,
        x: x,
        badgeWidth: visualStyle == .overdue
          ? timelineOverdueBadgeDiameter(for: totalCount)
          : timelineTaskBadgeWidth(for: totalCount),
        count: totalCount,
        strongPreview: bar.dailyTaskPreviews[date],
        lightPreview: bar.dailyPlannedWorkPreviews[date],
        visualStyle: visualStyle
      )
    }
    .sorted { $0.date < $1.date }
  }

  func timelineTaskBadgeVisualStyle(
    date: Date,
    strongCount: Int,
    lightCount: Int
  ) -> TimelineTaskBadgeVisualStyle {
    if strongCount > 0, calendar.startOfDay(for: date) < calendar.startOfDay(for: .now) {
      return .overdue
    }
    return strongCount > 0 ? .strong : .light
  }

  func timelineCompletedCountLayouts(for bar: TimelineProjectBar)
    -> [TimelineCompletedCountLayout]
  {
    timelineCompletedCountLayouts(for: bar, suppressOnDatesWithPendingWork: false)
  }

  func timelineCompletedCountLayouts(
    for bar: TimelineProjectBar,
    suppressOnDatesWithPendingWork: Bool
  ) -> [TimelineCompletedCountLayout] {
    bar.dailyCompletedTaskCounts.compactMap { date, count in
      guard count > 0 else { return nil }
      if suppressOnDatesWithPendingWork,
        ((bar.dailyTaskCounts[date] ?? 0) + (bar.dailyPlannedWorkCounts[date] ?? 0)) > 0
      {
        return nil
      }
      let offset = dayOffset(for: date)
      guard offset >= -completedHistoryVisiblePastDays else { return nil }
      guard dayRange.contains(offset) else { return nil }
      let x = CGFloat(offset - dayRange.lowerBound) * dayColumnWidth + (dayColumnWidth * 0.5)
      let hoverTargetID =
        ((bar.dailyTaskCounts[date] ?? 0) + (bar.dailyPlannedWorkCounts[date] ?? 0)) > 0
        ? timelineTaskBadgeID(for: bar.projectID, date: date)
        : "completed-\(bar.projectID.uuidString)-\(offset)"
      return TimelineCompletedCountLayout(
        id: "completed-\(bar.projectID.uuidString)-\(offset)",
        date: date,
        x: x,
        count: count,
        badgeWidth: timelineTaskBadgeWidth(for: count),
        hoverTargetID: hoverTargetID
      )
    }
    .sorted { $0.date < $1.date }
  }

  func buildRowLayouts(for bars: [TimelineProjectBar]) -> [TimelineRowLayout] {
    var nextTopY: CGFloat = 0
    return bars.map { bar in
      let metrics = rowMetrics(for: bar)
      defer {
        nextTopY += metrics.height + metrics.spacing
      }
      return TimelineRowLayout(topY: nextTopY, metrics: metrics)
    }
  }

  func priorityStage(for bar: TimelineProjectBar) -> ProjectProgressStage {
    ProjectProgressStage.from(progress: bar.progress)
  }

  func showsPriorityBoundary(before rowIndex: Int, in bars: [TimelineProjectBar]) -> Bool {
    guard projectListSortMode == .priority, rowIndex > 0, bars.indices.contains(rowIndex) else {
      return false
    }

    return priorityStage(for: bars[rowIndex - 1]) != priorityStage(for: bars[rowIndex])
  }

  func rowBackgroundFill(
    for bar: TimelineProjectBar,
    isSelected: Bool,
    isProjectDropTarget: Bool,
    isTaskDropTarget: Bool,
    inLeftColumn: Bool
  ) -> Color {
    if isTaskDropTarget {
      return Color.accentColor.opacity(0.16)
    }

    if isSelected {
      return selectionHighlightColor
    }

    return Color.gray.opacity(inLeftColumn ? 0.05 : 0.08)
  }

  func priorityStageRailColor(for stage: ProjectProgressStage) -> Color {
    switch stage {
    case .do:
      return Color.red.opacity(0.5)
    case .decide:
      return Color.yellow.opacity(0.5)
    case .area:
      return Color.green.opacity(0.5)
    case .later:
      return Color.secondary.opacity(0.35)
    }
  }

  @ViewBuilder
  func priorityStageRail(
    for bars: [TimelineProjectBar],
    rowLayouts: [TimelineRowLayout],
    width: CGFloat
  ) -> some View {
    if projectListSortMode == .priority {
      ZStack(alignment: .topLeading) {
        ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
          if rowLayouts.indices.contains(index) {
            let rowLayout = rowLayouts[index]
            let stage = priorityStage(for: bar)
            Rectangle()
              .fill(priorityStageRailColor(for: stage))
              .frame(
                width: width,
                height: rowSlotHeight(
                  for: rowLayout,
                  index: index,
                  totalCount: bars.count
                )
              )
              .offset(
                x: 0,
                y: rowSlotMinY(for: rowLayout, index: index)
              )
          }
        }
      }
      .allowsHitTesting(false)
    }
  }

  func rowSlotMinY(for rowLayout: TimelineRowLayout, index: Int) -> CGFloat {
    rowLayout.topY - rowLayout.metrics.topPadding(for: index)
  }

  func rowSlotHeight(
    for rowLayout: TimelineRowLayout,
    index: Int,
    totalCount: Int
  ) -> CGFloat {
    rowLayout.metrics.topPadding(for: index)
      + rowLayout.metrics.height
      + rowLayout.metrics.bottomPadding(for: index, totalCount: totalCount)
  }

  func rowMetrics(for bar: TimelineProjectBar) -> TimelineRowMetrics {
    guard projectListSortMode == .priority,
      priorityStage(for: bar) == .do
    else {
      return rowMetrics
    }

    return TimelineRowMetrics(
      height: rowMetrics.height * priorityDoRowHeightMultiplier,
      spacing: rowMetrics.spacing,
      contentInsetY: rowMetrics.contentInsetY
    )
  }

  func projectDropTargets(
    for bars: [TimelineProjectBar],
    rowLayouts: [TimelineRowLayout]
  ) -> [TimelineProjectDropTarget] {
    bars.enumerated().compactMap { index, bar in
      guard rowLayouts.indices.contains(index) else {
        return nil
      }
      let rowLayout = rowLayouts[index]
      let minY = rowSlotMinY(for: rowLayout, index: index)
      let height = rowSlotHeight(for: rowLayout, index: index, totalCount: bars.count)
      return TimelineProjectDropTarget(
        projectID: bar.projectID,
        minY: minY,
        midY: minY + height / 2,
        maxY: minY + height
      )
    }
  }

  func visibleTimelineRowRange(
    rowLayouts: [TimelineRowLayout],
    viewportHeight: CGFloat
  ) -> ClosedRange<Int>? {
    guard !rowLayouts.isEmpty else { return nil }
    let visibleMinY = max(0, verticalOffsetY)
    let visibleMaxY = visibleMinY + max(viewportHeight, rowMetrics.height)

    var lower: Int?
    var upper: Int?

    for (index, rowLayout) in rowLayouts.enumerated() {
      let rowMinY = rowLayout.topY
      let rowMaxY = rowLayout.topY + rowLayout.metrics.height
      let buffer = rowLayout.metrics.spacing

      if rowMaxY < visibleMinY - buffer {
        continue
      }

      if rowMinY > visibleMaxY + buffer {
        break
      }

      if lower == nil {
        lower = max(0, index - 1)
      }
      upper = index
    }

    guard let resolvedLower = lower, let resolvedUpper = upper else {
      return nil
    }

    let upperWithBuffer = min(rowLayouts.count - 1, resolvedUpper + 1)
    let lowerClamped = max(0, resolvedLower)
    guard lowerClamped <= upperWithBuffer else { return nil }
    return lowerClamped...upperWithBuffer
  }

  func timelineProjectBarPassthroughFrames(
    for bars: [TimelineProjectBar],
    rowLayouts: [TimelineRowLayout],
    containerOrigin: CGPoint,
    viewportHeight: CGFloat
  ) -> [CGRect] {
    guard let visibleRange = visibleTimelineRowRange(
      rowLayouts: rowLayouts,
      viewportHeight: viewportHeight
    ) else {
      return []
    }

    return visibleRange.compactMap { index in
      let bar = bars[index]
      let segment = segmentFrame(for: bar)
      let deadline = deadlineMarkerFrame(for: bar)

      guard segment != nil || deadline != nil else { return nil }

      var rects: [CGRect] = []
      let rowLayout = rowLayouts[index]
      let rowOriginY = containerOrigin.y + headerHeight + rowLayout.topY - verticalOffsetY

      if let segment {
        rects.append(
          CGRect(
            x: containerOrigin.x + titleColumnWidth + segment.x - horizontalOffsetX,
            y: rowOriginY + rowLayout.metrics.contentInsetY,
            width: segment.width,
            height: rowLayout.metrics.contentHeight
          )
        )
      }

      if let deadline {
        rects.append(
          CGRect(
            x: containerOrigin.x + titleColumnWidth + deadline.x - horizontalOffsetX,
            y: rowOriginY + rowLayout.metrics.contentInsetY,
            width: deadline.width,
            height: rowLayout.metrics.contentHeight
          )
        )
      }

      guard let firstRect = rects.first else { return nil }
      return rects.dropFirst().reduce(firstRect) { partial, rect in
        partial.union(rect)
      }
    }
  }

  func segmentFrame(for bar: TimelineProjectBar) -> (x: CGFloat, width: CGFloat)? {
    guard let start = bar.start, let end = bar.end else {
      return nil
    }

    return segmentFrame(start: start, end: end)
  }

  func activeSegmentFrame(for bar: TimelineProjectBar) -> (x: CGFloat, width: CGFloat)? {
    guard
      let end = bar.end,
      let nextUpcomingDate = bar.nextUpcomingDate
    else {
      return nil
    }

    let segmentStart = max(bar.start ?? nextUpcomingDate, nextUpcomingDate)
    guard segmentStart <= end else {
      return nil
    }

    return segmentFrame(start: segmentStart, end: end)
  }

  func segmentFrame(start: Date, end: Date) -> (x: CGFloat, width: CGFloat)? {
    let startOffset = dayOffset(for: start)
    let endOffset = dayOffset(for: end)
    let lower = min(startOffset, endOffset)
    let upper = max(startOffset, endOffset)
    let visibleLower = max(lower, dayRange.lowerBound)
    let visibleUpper = min(upper, dayRange.upperBound)

    guard visibleLower <= visibleUpper else {
      return nil
    }

    let x = CGFloat(visibleLower - dayRange.lowerBound) * dayColumnWidth
    let width = CGFloat(visibleUpper - visibleLower + 1) * dayColumnWidth
    return (x: x, width: max(8, width))
  }

  func deadlineMarkerFrame(for bar: TimelineProjectBar) -> (x: CGFloat, width: CGFloat)? {
    guard let deadline = bar.deadline else {
      return nil
    }

    let offset = dayOffset(for: deadline)
    guard dayRange.contains(offset) else {
      return nil
    }

    let edgeX = CGFloat(offset - dayRange.lowerBound + 1) * dayColumnWidth
    let width = min(deadlineMarkerWidth, max(6, dayColumnWidth - 2))
    return (x: max(0, edgeX - width), width: width)
  }

  @ViewBuilder
  func taskCountLabel(
    undatedRemainingTaskCount: Int,
    remainingTaskCount: Int
  ) -> some View {
    if undatedRemainingTaskCount > 0 {
      HStack(spacing: 4) {
        Text("\(undatedRemainingTaskCount)")
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(Color(red: 0.62, green: 0.30, blue: 0.30))

        Text("/\(remainingTaskCount)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
    } else {
      Text("\(remainingTaskCount)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }

  func projectDropIndicatorAlignment(for projectID: UUID) -> Alignment {
    guard let projectDropIndicator, projectDropIndicator.targetProjectID == projectID else {
      return .top
    }
    return projectDropIndicator.placement == .before ? .top : .bottom
  }

  func projectIsSelected(_ projectID: UUID) -> Bool {
    selectedProjectID == projectID
  }

  @ViewBuilder
  func progressMarker(for bar: TimelineProjectBar) -> some View {
    let projectColor = timelineColor(for: bar)
    let stage = ProjectProgressStage.from(progress: bar.progress)

    progressMarker(stage: stage, projectColor: projectColor)
  }

  @ViewBuilder
  func progressMarker(stage: ProjectProgressStage, projectColor: Color) -> some View {
    Image(systemName: stage.iconName)
      .font(.system(size: progressMarkerSize, weight: stage == .do ? .semibold : .bold))
      .foregroundStyle(projectColor)
      .frame(width: progressMarkerSize, height: progressMarkerSize)
  }

  func progressStageMenu(for bar: TimelineProjectBar, rowHeight: CGFloat) -> some View {
    let projectColor = timelineColor(for: bar)
    let selectedStage = ProjectProgressStage.from(progress: bar.progress)

    return Group {
      LeftClickMenuButton(
        selectedStage: selectedStage,
        onSelect: { stage in
          updateTimelineProjectStage(projectID: bar.projectID, stage: stage)
        }
      ) {
        progressMarker(stage: selectedStage, projectColor: projectColor)
          .frame(width: 18, height: rowHeight, alignment: .center)
          .contentShape(Rectangle())
      }
      .help("분류")
    }
  }

  func timelineColor(for bar: TimelineProjectBar) -> Color {
    ColorHexCodec.color(from: bar.colorHex) ?? .blue
  }

  func timelineColor(forProjectID projectID: UUID) -> Color {
    guard let colorHex = workspaceTimelineProjectSnapshots[projectID]?.colorHex else { return .blue }
    return ColorHexCodec.color(from: colorHex) ?? .blue
  }

  func timelineMutedColor(for bar: TimelineProjectBar) -> Color {
    let nsColor = ColorHexCodec.nsColor(from: bar.colorHex) ?? .systemBlue
    guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
      return timelineColor(for: bar)
    }

    return Color(
      nsColor: NSColor(
        hue: rgbColor.hueComponent,
        saturation: rgbColor.saturationComponent * 0.15,
        brightness: rgbColor.brightnessComponent,
        alpha: rgbColor.alphaComponent
      )
    )
  }
}
