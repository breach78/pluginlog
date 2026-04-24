import AppKit
import SwiftUI

extension TimelineBoardView {
  func timelineBoardOverlaySurface(
    snapshot: TimelineBoardSnapshot,
    viewport: TimelineViewportSnapshot
  ) -> some View {
    GeometryReader { overlayProxy in
      let paddedFrame = overlayProxy.frame(in: .named(workspaceMainPaneCoordinateSpaceName))
      let containerOrigin = CGPoint(
        x: paddedFrame.minX + horizontalEdgePadding,
        y: paddedFrame.minY + topEdgePadding
      )
      Color.clear
        .preference(
          key: TimelineProjectTapPassthroughFramePreferenceKey.self,
          value: showsProjectPassthroughFrames && isActive
            ? timelineProjectBarPassthroughFrames(
              for: snapshot.bars,
              rowLayouts: snapshot.rowLayouts,
              containerOrigin: containerOrigin,
              viewportHeight: viewport.viewportHeight
            )
            : []
        )
        .preference(
          key: TimelineTaskBadgeOverlayPresentationPreferenceKey.self,
          value: isActive
            ? timelineTaskBadgeOverlayPresentation(
              from: snapshot.bars,
              rowLayouts: snapshot.rowLayouts,
              rowsHeight: viewport.rowsHeight,
              containerOrigin: containerOrigin
            )
            : nil
        )
        .preference(
          key: TimelineDayHeaderOverlayPresentationPreferenceKey.self,
          value: isActive
            ? timelineDayHeaderOverlayPresentation(containerOrigin: containerOrigin)
            : nil
        )
    }
  }

  @ViewBuilder
  func timelineTaskToggleMarker(isOverdue: Bool, opacity: Double = 1.0) -> some View {
    let markerSize: CGFloat = 13
    if isOverdue {
      Circle()
        .stroke(Color.red.opacity(opacity), lineWidth: 1.9)
        .frame(width: markerSize, height: markerSize)
    } else {
      Image(systemName: "circle")
        .font(.system(size: markerSize, weight: .regular))
        .foregroundStyle(.secondary.opacity(opacity))
    }
  }

  @ViewBuilder
  func timelineTaskBadgeOverlayCard(
    context: TimelineTaskBadgeOverlayContext
  ) -> some View {
    let projectID = context.projectReference.id
    VStack(alignment: .leading, spacing: 8) {
      let canInteractWithProject = activeProjectIDSet.contains(projectID)
      VStack(alignment: .leading, spacing: 8) {
        if let strongPreview = context.strongPreview,
          strongPreview.totalCount > 0
        {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(strongPreview.tasks, id: \.id) { task in
              HStack(spacing: 8) {
                Button {
                  completeTimelineTask(task.taskID, projectID: projectID)
                } label: {
                  timelineTaskToggleMarker(isOverdue: task.isOverdue)
                }
                .buttonStyle(.plain)
                .disabled(!canInteractWithProject)

                Button {
                  revealTimelineTaskDetail(taskID: task.taskID, projectID: projectID)
                } label: {
                  HStack(spacing: 0) {
                    Text(timelinePreviewTitle(for: task.title))
                      .font(.system(size: 12))
                      .foregroundStyle(.primary)
                      .lineLimit(1)

                    Spacer(minLength: 0)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }

            if context.hiddenStrongCount > 0 {
              Text("+\(context.hiddenStrongCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 21)
            }
          }
        }

        if let lightPreview = context.lightPreview,
          lightPreview.totalCount > 0
        {
          if (context.strongPreview?.totalCount ?? 0) > 0 {
            Divider()
          }

          VStack(alignment: .leading, spacing: 6) {
            ForEach(lightPreview.tasks, id: \.id) { task in
              HStack(spacing: 8) {
                Button {
                  completeTimelinePlannedWork(
                    taskID: task.taskID,
                    projectID: projectID,
                    targetCompletedUnits: task.targetCompletedUnits,
                    completedOn: context.date
                  )
                } label: {
                  timelineTaskToggleMarker(isOverdue: false, opacity: 0.75)
                }
                .buttonStyle(.plain)
                .disabled(!canInteractWithProject)

                Button {
                  revealTimelineTaskDetail(taskID: task.taskID, projectID: projectID)
                } label: {
                  HStack(spacing: 0) {
                    Text(timelinePreviewTitle(for: task.title))
                      .font(.system(size: 12))
                      .foregroundStyle(.primary.opacity(0.58))
                      .lineLimit(1)

                    Spacer(minLength: 0)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }

            if context.hiddenLightCount > 0 {
              Text("+\(context.hiddenLightCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 21)
            }
          }
        }

        if let completedPreview = context.completedPreview,
          completedPreview.totalCount > 0
        {
          let completedMarkerColor = timelineColor(forProjectID: projectID)
          if (context.strongPreview?.totalCount ?? 0) > 0
            || (context.lightPreview?.totalCount ?? 0) > 0
          {
            Divider()
          }

          VStack(alignment: .leading, spacing: 6) {
            ForEach(completedPreview.tasks, id: \.id) { task in
              Button {
                revealTimelineTaskDetail(taskID: task.taskID, projectID: projectID)
              } label: {
                HStack(spacing: 8) {
                  Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(completedMarkerColor.opacity(0.9))

                  Text(timelinePreviewTitle(for: task.title))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                  Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }

            if context.hiddenCompletedCount > 0 {
              Text("+\(context.hiddenCompletedCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 21)
            }
          }
        }
      }
    }
    .padding(10)
    .frame(width: timelineTaskBadgeOverlayWidth, alignment: .leading)
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
    .onHover { isHovering in
      if isHovering {
        appState.isHoveringTimelineTaskBadgeOverlay = true
        timelineTaskBadgeHideWorkItem?.cancel()
      } else {
        appState.isHoveringTimelineTaskBadgeOverlay = false
        scheduleTimelineTaskBadgeOverlayHideIfNeeded()
      }
    }
  }

  func timelineTaskBadgeOverlayLayout(
    badgeMinX: CGFloat,
    badgeMaxX: CGFloat,
    badgeMidY: CGFloat,
    overlayHeight: CGFloat,
    viewportWidth: CGFloat,
    viewportHeight: CGFloat
  ) -> TimelineTaskBadgeOverlayLayout {
    let minInset: CGFloat = 8
    let verticalGap: CGFloat = 2
    let maxX = max(minInset, viewportWidth - timelineTaskBadgeOverlayWidth - minInset)
    let maxY = max(minInset, viewportHeight - overlayHeight - minInset)
    let badgeMidX = (badgeMinX + badgeMaxX) * 0.5
    let x = min(maxX, max(minInset, badgeMidX - 18))

    let badgeHalfHeight = timelineTaskBadgeHeight * 0.5
    let spaceAbove = badgeMidY - badgeHalfHeight - minInset
    let spaceBelow = viewportHeight - (badgeMidY + badgeHalfHeight) - minInset
    let preferredAboveY = badgeMidY - badgeHalfHeight - overlayHeight - verticalGap
    let preferredBelowY = badgeMidY + badgeHalfHeight + verticalGap
    let y: CGFloat
    let placement: TimelineTaskBadgeOverlayPlacement
    if spaceAbove >= overlayHeight + verticalGap {
      y = max(minInset, preferredAboveY)
      placement = .above
    } else if spaceBelow >= overlayHeight + verticalGap {
      y = min(maxY, preferredBelowY)
      placement = .below
    } else if spaceAbove >= spaceBelow {
      y = max(minInset, min(preferredAboveY, maxY))
      placement = .above
    } else {
      y = min(maxY, max(minInset, preferredBelowY))
      placement = .below
    }

    return TimelineTaskBadgeOverlayLayout(
      position: CGPoint(x: x, y: y),
      placement: placement
    )
  }

  func timelineTaskBadgeOverlayEstimatedHeight(for context: TimelineTaskBadgeOverlayContext)
    -> CGFloat
  {
    func sectionHeight(visibleCount: Int, hiddenCount: Int) -> CGFloat {
      let extraLineCount = hiddenCount > 0 ? 1 : 0
      let itemCount = visibleCount + extraLineCount
      guard itemCount > 0 else { return 0 }

      let rowHeights = CGFloat(visibleCount) * 18
      let hiddenLineHeight = CGFloat(extraLineCount) * 14
      let interItemSpacing = CGFloat(max(0, itemCount - 1)) * 6
      return rowHeights + hiddenLineHeight + interItemSpacing
    }

    let sections = [
      sectionHeight(
        visibleCount: context.strongPreview?.tasks.count ?? 0,
        hiddenCount: context.hiddenStrongCount
      ),
      sectionHeight(
        visibleCount: context.lightPreview?.tasks.count ?? 0,
        hiddenCount: context.hiddenLightCount
      ),
      sectionHeight(
        visibleCount: context.completedPreview?.tasks.count ?? 0,
        hiddenCount: context.hiddenCompletedCount
      )
    ].filter { $0 > 0 }

    let dividerBlocks = CGFloat(max(0, sections.count - 1)) * 17
    let verticalPadding: CGFloat = 20
    return verticalPadding + sections.reduce(0, +) + dividerBlocks + 6
  }

  func timelineTaskBadgeOverlayPresentation(
    from bars: [TimelineProjectBar],
    rowLayouts: [TimelineRowLayout],
    rowsHeight: CGFloat,
    containerOrigin: CGPoint
  ) -> TimelineTaskBadgeOverlayPresentation? {
    guard !appState.isEditorMotionSuppressed,
      let overlayContext = activeTimelineTaskBadgeOverlayContext(from: bars, rowLayouts: rowLayouts)
    else {
      return nil
    }

    let overlayHeight = overlayMetricsCache.taskBadgeHeight(for: overlayContext) {
      timelineTaskBadgeOverlayEstimatedHeight(for: overlayContext)
    }
    let overlayLayout = timelineTaskBadgeOverlayLayout(
      badgeMinX: overlayContext.badgeMinX,
      badgeMaxX: overlayContext.badgeMaxX,
      badgeMidY: overlayContext.badgeMidY,
      overlayHeight: overlayHeight,
      viewportWidth: timelineWidth,
      viewportHeight: rowsHeight
    )
    let placementYOffset =
      overlayLayout.placement == .above
      ? timelineTaskBadgeOverlayAboveOffset
      : timelineTaskBadgeOverlayBelowOffset
    let frame = CGRect(
      x: containerOrigin.x + titleColumnWidth + overlayLayout.position.x - horizontalOffsetX,
      y: containerOrigin.y + headerHeight + overlayLayout.position.y + placementYOffset
        - verticalOffsetY,
      width: timelineTaskBadgeOverlayWidth,
      height: overlayHeight
    )

    return TimelineTaskBadgeOverlayPresentation(
      frame: frame,
      projectReference: overlayContext.projectReference,
      date: overlayContext.date,
      totalCount: overlayContext.totalCount,
      strongTasks: overlayContext.strongPreview?.tasks.map {
        TimelineTaskBadgeOverlayTaskItem(
          id: $0.id,
          taskID: $0.taskID,
          title: timelinePreviewTitle(for: $0.title),
          isOverdue: $0.isOverdue
        )
      } ?? [],
      lightTasks: overlayContext.lightPreview?.tasks.map {
        TimelineTaskBadgeOverlayPlannedItem(
          id: $0.id,
          taskID: $0.taskID,
          title: timelinePreviewTitle(for: $0.title),
          targetCompletedUnits: $0.targetCompletedUnits
        )
      } ?? [],
      completedTasks: overlayContext.completedPreview?.tasks.map {
        TimelineTaskBadgeOverlayTaskItem(
          id: $0.id,
          taskID: $0.taskID,
          title: timelinePreviewTitle(for: $0.title),
          isOverdue: false
        )
      } ?? [],
      hiddenStrongCount: overlayContext.hiddenStrongCount,
      hiddenLightCount: overlayContext.hiddenLightCount,
      hiddenCompletedCount: overlayContext.hiddenCompletedCount
    )
  }

  func activeTimelineTaskBadgeOverlayContext(
    from bars: [TimelineProjectBar],
    rowLayouts: [TimelineRowLayout]
  )
    -> TimelineTaskBadgeOverlayContext?
  {
    guard let activeTimelineTaskBadgeID else {
      return nil
    }

    for (rowIndex, bar) in bars.enumerated() {
      for badge in timelineTaskBadges(for: bar, rowIndex: rowIndex) {
        if badge.id == activeTimelineTaskBadgeID {
          let badgeMidX = badge.x
          let badgeMinX = badgeMidX - (badge.badgeWidth * 0.5)
          let badgeMaxX = badgeMidX + (badge.badgeWidth * 0.5)
          guard rowLayouts.indices.contains(badge.rowIndex) else { continue }
          let rowLayout = rowLayouts[badge.rowIndex]
          let badgeMidY = rowLayout.topY + rowLayout.metrics.midpointY

          return TimelineTaskBadgeOverlayContext(
            badgeID: activeTimelineTaskBadgeID,
            projectReference: bar.projectReference,
            date: badge.date,
            badgeMinX: badgeMinX,
            badgeMaxX: badgeMaxX,
            badgeMidY: badgeMidY,
            strongPreview: badge.strongPreview,
            lightPreview: badge.lightPreview,
            completedPreview: nil
          )
        }
      }

      for completedLayout in timelineCompletedCountLayouts(for: bar) {
        if completedLayout.id == activeTimelineTaskBadgeID {
          let badgeMidX = completedLayout.x
          let badgeMinX = badgeMidX - (completedLayout.badgeWidth * 0.5)
          let badgeMaxX = badgeMidX + (completedLayout.badgeWidth * 0.5)
          guard rowLayouts.indices.contains(rowIndex) else { continue }
          let rowLayout = rowLayouts[rowIndex]
          let badgeMidY = rowLayout.topY + rowLayout.metrics.midpointY

          return TimelineTaskBadgeOverlayContext(
            badgeID: activeTimelineTaskBadgeID,
            projectReference: bar.projectReference,
            date: completedLayout.date,
            badgeMinX: badgeMinX,
            badgeMaxX: badgeMaxX,
            badgeMidY: badgeMidY,
            strongPreview: nil,
            lightPreview: nil,
            completedPreview: bar.dailyCompletedTaskPreviews[completedLayout.date]
          )
        }
      }
    }

    return nil
  }

  func updateTimelineTaskBadgeHover(_ badgeID: String, isHovering: Bool) {
    if isTimelineScrolling {
      if isHovering {
        recordSuppressedTimelineTaskBadgeHover()
      }
      cancelTimelineTaskBadgeOverlay()
      return
    }

    if isHoveringPinnedLeftColumn {
      if isHovering {
        cancelTimelineTaskBadgeOverlay()
      }
      return
    }

    if activeTimelineDayHeaderOffset != nil || appState.isHoveringTimelineDayHeaderOverlay {
      if isHovering {
        timelineTaskBadgeShowWorkItem?.cancel()
      }
      return
    }

    if isHovering,
      appState.isHoveringTimelineTaskBadgeOverlay,
      let activeTimelineTaskBadgeID,
      activeTimelineTaskBadgeID != badgeID
    {
      timelineTaskBadgeShowWorkItem?.cancel()
      return
    }

    if isHovering {
      hoveredTimelineTaskBadgeID = badgeID
      timelineTaskBadgeHideWorkItem?.cancel()

      if activeTimelineTaskBadgeID == badgeID {
        return
      }

      timelineTaskBadgeShowWorkItem?.cancel()
      let workItem = DispatchWorkItem {
        guard hoveredTimelineTaskBadgeID == badgeID else { return }
        activeTimelineTaskBadgeID = badgeID
      }
      timelineTaskBadgeShowWorkItem = workItem
      DispatchQueue.main.asyncAfter(
        deadline: .now() + timelineTaskBadgeShowDelay, execute: workItem)
      return
    }

    if hoveredTimelineTaskBadgeID == badgeID {
      hoveredTimelineTaskBadgeID = nil
    }
    timelineTaskBadgeShowWorkItem?.cancel()
    scheduleTimelineTaskBadgeOverlayHideIfNeeded()
  }

  func scheduleTimelineTaskBadgeOverlayHideIfNeeded() {
    guard hoveredTimelineTaskBadgeID == nil, !appState.isHoveringTimelineTaskBadgeOverlay else {
      return
    }

    timelineTaskBadgeHideWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      guard hoveredTimelineTaskBadgeID == nil, !appState.isHoveringTimelineTaskBadgeOverlay else {
        return
      }
      activeTimelineTaskBadgeID = nil
    }
    timelineTaskBadgeHideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + timelineTaskBadgeHideDelay, execute: workItem)
  }

  func cancelTimelineTaskBadgeOverlay() {
    timelineTaskBadgeShowWorkItem?.cancel()
    timelineTaskBadgeHideWorkItem?.cancel()
    timelineTaskBadgeShowWorkItem = nil
    timelineTaskBadgeHideWorkItem = nil
    hoveredTimelineTaskBadgeID = nil
    activeTimelineTaskBadgeID = nil
    appState.isHoveringTimelineTaskBadgeOverlay = false
  }

  func timelinePreviewTitle(for title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "제목 없음" : trimmed
  }

  func refreshTimelineDayHeaderSectionsIfNeeded(
    from bars: [TimelineProjectBar],
    sourceSignature: Int,
    force: Bool
  ) {
    if !force,
      let cachedTimelineDayHeaderSourceSignature,
      cachedTimelineDayHeaderSourceSignature == sourceSignature
    {
      return
    }

    let today = calendar.startOfDay(for: .now)
    var sectionsByDay: [Date: [TimelineDayHeaderOverlayProjectSection]] = [:]

    for bar in bars {
      var tasksByDay: [Date: [TimelineDayHeaderOverlayTaskItem]] = [:]
      for (day, preview) in bar.dailyTaskPreviews {
        for task in preview.tasks {
          tasksByDay[day, default: []].append(
            TimelineDayHeaderOverlayTaskItem(
              id: "\(bar.projectID.uuidString)-\(task.id)-display",
              projectReference: bar.projectReference,
              taskID: task.taskID,
              title: timelinePreviewTitle(for: task.title),
              isCompleted: false,
              isOverdue: task.isOverdue
            )
          )

          if task.isOverdue {
            tasksByDay[today, default: []].append(
              TimelineDayHeaderOverlayTaskItem(
                id: "\(bar.projectID.uuidString)-\(task.id)-overdue-today",
                projectReference: bar.projectReference,
                taskID: task.taskID,
                title: timelinePreviewTitle(for: task.title),
                isCompleted: false,
                isOverdue: true
              )
            )
          }
        }
      }

      for (day, preview) in bar.dailyCompletedTaskPreviews {
        for task in preview.tasks {
          tasksByDay[day, default: []].append(
            TimelineDayHeaderOverlayTaskItem(
              id: "\(bar.projectID.uuidString)-\(task.id)-completed",
              projectReference: bar.projectReference,
              taskID: task.taskID,
              title: timelinePreviewTitle(for: task.title),
              isCompleted: true,
              isOverdue: false
            )
          )
        }
      }

      guard !tasksByDay.isEmpty else { continue }

      for (day, items) in tasksByDay {
        sectionsByDay[day, default: []].append(
          TimelineDayHeaderOverlayProjectSection(
            id: bar.projectID,
            projectReference: bar.projectReference,
            projectTitle: bar.title,
            tasks: items
          )
        )
      }
    }

    cachedTimelineDayHeaderSections = sectionsByDay
    cachedTimelineDayHeaderSourceSignature = sourceSignature
  }

  func timelineDayHeaderOverlayPresentation(containerOrigin: CGPoint)
    -> TimelineDayHeaderOverlayPresentation?
  {
    guard !appState.isEditorMotionSuppressed,
      let activeTimelineDayHeaderOffset,
      isTimelineDayHeaderInteractable(activeTimelineDayHeaderOffset)
    else {
      return nil
    }

    let activeDate = calendar.startOfDay(for: date(for: activeTimelineDayHeaderOffset))
    guard
      let sections = cachedTimelineDayHeaderSections[activeDate],
      !sections.isEmpty
    else {
      return nil
    }

    let overlayHeight = overlayMetricsCache.dayHeaderHeight(for: sections) {
      timelineDayHeaderOverlayEstimatedHeight(for: sections)
    }
    let overlayX = timelineDayHeaderOverlayX(for: activeTimelineDayHeaderOffset)
    let frame = CGRect(
      x: containerOrigin.x + titleColumnWidth + overlayX - horizontalOffsetX,
      y: containerOrigin.y + headerHeight,
      width: timelineDayHeaderOverlayWidth,
      height: overlayHeight
    )

    return TimelineDayHeaderOverlayPresentation(
      frame: frame,
      date: activeDate,
      sections: sections
    )
  }

  func timelineDayHeaderOverlayX(for offset: Int) -> CGFloat {
    let minInset: CGFloat = 8
    let maxX = max(minInset, timelineWidth - timelineDayHeaderOverlayWidth - minInset)
    let cellMidX =
      CGFloat(offset - dayRange.lowerBound) * dayColumnWidth + (dayColumnWidth * 0.5)
    return min(maxX, max(minInset, cellMidX - 32))
  }

  func timelineDayHeaderOverlayEstimatedHeight(
    for sections: [TimelineDayHeaderOverlayProjectSection]
  ) -> CGFloat {
    let verticalPadding: CGFloat = 24
    let sectionHeaderHeight: CGFloat = 18
    let rowHeightEstimate: CGFloat = 22
    let rowSpacing: CGFloat = 8
    let dividerBlockHeight: CGFloat = 19

    var total: CGFloat = verticalPadding
    for (index, section) in sections.enumerated() {
      total += sectionHeaderHeight
      total += CGFloat(section.tasks.count) * rowHeightEstimate
      total += CGFloat(max(0, section.tasks.count - 1)) * rowSpacing
      if index < sections.count - 1 {
        total += dividerBlockHeight
      }
    }
    return total
  }

  func updateTimelineDayHeaderHover(_ offset: Int, isHovering: Bool) {
    if isTimelineScrolling {
      if isHovering {
        recordSuppressedTimelineDayHeaderHover()
      }
      cancelTimelineDayHeaderOverlay()
      return
    }

    if isHoveringPinnedLeftColumn || !isTimelineDayHeaderInteractable(offset) {
      if isHovering {
        cancelTimelineDayHeaderOverlay()
      }
      return
    }

    if isHovering {
      cancelTimelineTaskBadgeOverlay()
      hoveredTimelineDayHeaderOffset = offset
      timelineDayHeaderHideWorkItem?.cancel()

      if activeTimelineDayHeaderOffset == offset {
        return
      }

      timelineDayHeaderShowWorkItem?.cancel()
      let workItem = DispatchWorkItem {
        guard hoveredTimelineDayHeaderOffset == offset else { return }
        activeTimelineDayHeaderOffset = offset
      }
      timelineDayHeaderShowWorkItem = workItem
      DispatchQueue.main.asyncAfter(
        deadline: .now() + timelineDayHeaderShowDelay,
        execute: workItem
      )
      return
    }

    if hoveredTimelineDayHeaderOffset == offset {
      hoveredTimelineDayHeaderOffset = nil
    }
    timelineDayHeaderShowWorkItem?.cancel()
    scheduleTimelineDayHeaderOverlayHideIfNeeded()
  }

  func scheduleTimelineDayHeaderOverlayHideIfNeeded() {
    guard hoveredTimelineDayHeaderOffset == nil, !appState.isHoveringTimelineDayHeaderOverlay else {
      return
    }

    timelineDayHeaderHideWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      guard
        hoveredTimelineDayHeaderOffset == nil,
        !appState.isHoveringTimelineDayHeaderOverlay
      else {
        return
      }
      activeTimelineDayHeaderOffset = nil
    }
    timelineDayHeaderHideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + timelineDayHeaderHideDelay, execute: workItem)
  }

  func dismissTimelineDayHeaderHoverIfObscured() {
    if let hoveredTimelineDayHeaderOffset,
      !isTimelineDayHeaderInteractable(hoveredTimelineDayHeaderOffset)
    {
      cancelTimelineDayHeaderOverlay()
      return
    }

    if let activeTimelineDayHeaderOffset,
      !isTimelineDayHeaderInteractable(activeTimelineDayHeaderOffset)
    {
      cancelTimelineDayHeaderOverlay()
    }
  }

  func isTimelineDayHeaderInteractable(_ offset: Int) -> Bool {
    offset >= currentVisibleLowerTimelineOffset()
  }

  func currentVisibleLowerTimelineOffset() -> Int {
    let rawVisibleLowerOffset =
      dayRange.lowerBound + Int(floor(max(0, horizontalOffsetX) / dayColumnWidth))
    return min(max(rawVisibleLowerOffset, dayRange.lowerBound), dayRange.upperBound)
  }

  func cancelTimelineDayHeaderOverlay() {
    timelineDayHeaderShowWorkItem?.cancel()
    timelineDayHeaderHideWorkItem?.cancel()
    timelineDayHeaderShowWorkItem = nil
    timelineDayHeaderHideWorkItem = nil
    hoveredTimelineDayHeaderOffset = nil
    activeTimelineDayHeaderOffset = nil
    appState.isHoveringTimelineDayHeaderOverlay = false
  }
}
