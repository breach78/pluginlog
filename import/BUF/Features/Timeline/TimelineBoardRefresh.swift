import Foundation
import SwiftData
import SwiftUI

enum TimelineBoardReadPath {
  static func orderedBars(
    _ bars: [TimelineProjectBar],
    by projectIDs: [UUID]
  ) -> [TimelineProjectBar] {
    guard !projectIDs.isEmpty else { return bars }

    let barsByProjectID = Dictionary(
      uniqueKeysWithValues: bars.map { ($0.projectID, $0) }
    )
    let coveredProjectIDs = Set(barsByProjectID.keys)
    guard Set(projectIDs).isSubset(of: coveredProjectIDs) else {
      return bars
    }

    return projectIDs.compactMap { barsByProjectID[$0] }
  }

  static func normalizedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    return projectIDs.filter { seen.insert($0).inserted }
  }

  static func hasCompleteWorkspaceCoverage(
    projectIDs: [UUID],
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> Bool {
    let normalizedProjectIDs = normalizedProjectIDs(projectIDs)
    guard !normalizedProjectIDs.isEmpty else { return false }
    return normalizedProjectIDs.allSatisfy {
      workspaceProjectSnapshots[$0] != nil && scheduleEntriesByProjectID[$0] != nil
    }
  }

  static func workspaceDetailSignature(
    projectIDs: [UUID],
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    workspaceProjectSummaries: [UUID: ProjectSummaryRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> Int {
    var hasher = Hasher()
    let normalizedProjectIDs = normalizedProjectIDs(projectIDs)
    hasher.combine(normalizedProjectIDs)
    for projectID in normalizedProjectIDs {
      guard let project = workspaceProjectSnapshots[projectID] else {
        hasher.combine(projectID)
        hasher.combine(0)
        continue
      }
      hasher.combine(project.id)
      hasher.combine(project.updatedAt.timeIntervalSinceReferenceDate)
      hasher.combine(project.localStartDate?.timeIntervalSinceReferenceDate)
      hasher.combine(project.localDeadline?.timeIntervalSinceReferenceDate)
      hasher.combine(project.title)
      hasher.combine(project.colorHex)
      hasher.combine(project.reminderListIdentifier)
      hasher.combine(project.reminderListExternalIdentifier)
      if let summary = workspaceProjectSummaries[projectID] {
        hasher.combine(summary.openRootTaskCount)
        hasher.combine(summary.completedRootTaskCount)
        hasher.combine(summary.undatedOpenRootTaskCount)
        hasher.combine(summary.overdueOpenRootTaskCount)
        hasher.combine(summary.todayTaskCount)
        hasher.combine(summary.nextUpcomingDate?.timeIntervalSinceReferenceDate)
        hasher.combine(summary.deadline?.timeIntervalSinceReferenceDate)
        hasher.combine(summary.stageRaw)
        hasher.combine(summary.progress)
        hasher.combine(summary.latestTaskUpdatedAt?.timeIntervalSinceReferenceDate)
      } else {
        hasher.combine(0)
        hasher.combine(0)
      }
      for entry in scheduleEntriesByProjectID[projectID] ?? [] {
        hasher.combine(entry.taskID)
        hasher.combine(entry.renderFingerprint)
      }
    }
    return hasher.finalize()
  }

  static func workspaceLoadSignature(
    projectIDs: [UUID],
    workspaceTreeRevision: Int
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(normalizedProjectIDs(projectIDs))
    hasher.combine(workspaceTreeRevision)
    return hasher.finalize()
  }

  static func resolvedBars(
    service: TimelineService,
    projectIDs: [UUID],
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    workspaceProjectSummaries: [UUID: ProjectSummaryRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> [TimelineProjectBar] {
    TimelineProjectionService.runtimeBars(
      service: service,
      projectIDs: projectIDs,
      projectSnapshots: workspaceProjectSnapshots,
      projectSummariesByID: workspaceProjectSummaries,
      scheduleEntriesByProjectID: scheduleEntriesByProjectID
    )
  }
}

extension TimelineBoardView {
  @MainActor
  func reloadWorkspaceTimelineProjectDetails(for projectIDs: [UUID]) async {
    let requestedProjectIDs = TimelineBoardReadPath.normalizedProjectIDs(projectIDs)
    guard !requestedProjectIDs.isEmpty else {
      workspaceTimelineProjectSnapshots = [:]
      workspaceTimelineProjectSummaries = [:]
      workspaceTimelineScheduleEntriesByProjectID = [:]
      retainedTimelineCalendarBridgeDecisionsByTaskID = [:]
      return
    }

    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      graphRootURL: appState.logseqGraphRootURL,
      projectIDs: requestedProjectIDs
    )
    let resolvedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolve(retainedResult) {
      ReminderRuntimeProjectionReadModelService.workspaceSurfaceProjection(
        projectIDs: requestedProjectIDs,
        runtimeSnapshot: appState.cachedOutlinerRuntimeProjectionSnapshot
      )
    }

    workspaceTimelineProjectSnapshots = resolvedRead.projectSnapshots
    workspaceTimelineProjectSummaries = resolvedRead.projectSummaries
    workspaceTimelineScheduleEntriesByProjectID = resolvedRead.scheduleEntriesByProjectID
    retainedTimelineCalendarBridgeDecisionsByTaskID =
      resolvedRead.calendarBridgeDecisionsByTaskID
    if case .blocked = resolvedRead.source {
      appState.errorMessage = resolvedRead.errorMessage
    }
  }

  func refreshAnchorDateIfNeeded(referenceDate: Date = .now) {
    let nextAnchorDate = calendar.startOfDay(for: referenceDate)
    guard nextAnchorDate != anchorDate else { return }
    anchorDate = nextAnchorDate
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()
  }

  func performTimelineDateRefresh(force: Bool) {
    refreshAnchorDateIfNeeded()
    let liveSourceSignature = timelineRefreshSignature(
      projectIDs: activeProjectIDs,
      workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
      workspaceProjectSummaries: workspaceTimelineProjectSummaries,
      scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID
    )
    let refreshedBars = refreshTimelineBarsIfNeeded(
      projectIDs: activeProjectIDs,
      workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
      workspaceProjectSummaries: workspaceTimelineProjectSummaries,
      scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID,
      sourceSignature: liveSourceSignature,
      force: force
    )
    refreshTimelineDayHeaderSectionsIfNeeded(
      from: refreshedBars,
      sourceSignature: liveSourceSignature,
      force: force
    )
    seedRangeIfNeeded(with: refreshedBars)
    prepareTimelineInitialViewportIfNeeded(with: refreshedBars)
  }

  func scheduleMidnightRefresh() {
    cancelMidnightRefresh()

    let nextRefreshDate = nextMidnight(after: .now)
    let interval = max(1, nextRefreshDate.timeIntervalSinceNow)
    let timer = Timer(timeInterval: interval, repeats: false) { _ in
      Task { @MainActor in
        performTimelineDateRefresh(force: true)
        scheduleMidnightRefresh()
      }
    }
    midnightRefreshTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func cancelMidnightRefresh() {
    midnightRefreshTimer?.invalidate()
    midnightRefreshTimer = nil
  }

  func nextMidnight(after date: Date) -> Date {
    let startOfDay = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: 1, to: startOfDay)
      ?? date.addingTimeInterval(24 * 60 * 60)
  }

  func coverageOffsets(for bar: TimelineProjectBar) -> (lower: Int, upper: Int)? {
    var offsets: [Int] = []
    if let start = bar.start {
      offsets.append(dayOffset(for: start))
    }
    if let end = bar.end {
      offsets.append(dayOffset(for: end))
    }
    if let deadline = bar.deadline {
      offsets.append(dayOffset(for: deadline))
    }

    guard let lower = offsets.min(), let upper = offsets.max() else {
      return nil
    }
    return (lower: lower, upper: upper)
  }

  enum OffscreenDirection {
    case left
    case right
  }

  func scrollToNearestBarEdge(
    for bar: TimelineProjectBar,
    direction: OffscreenDirection,
    visibleLowerOffset: Int,
    visibleUpperOffset: Int
  ) {
    guard let targetTaskOffset = firstRemainingTaskOffset(for: bar) else {
      return
    }
    let targetLeftOffset = targetTaskOffset - jumpLeftInsetDays

    requestHorizontalScroll(toLeftDayOffset: targetLeftOffset)
  }

  func requestHorizontalScroll(toLeftDayOffset dayOffset: Int) {
    let clampedOffset = min(max(dayOffset, dayRange.lowerBound), dayRange.upperBound)
    let x = CGFloat(clampedOffset - dayRange.lowerBound) * dayColumnWidth

    scrollRequestGeneration += 1
    requestedOffsetX = max(0, x)
  }

  func preserveLeftVisibleDayOnZoom(oldWidth: CGFloat, newWidth: CGFloat) {
    guard abs(oldWidth - newWidth) > 0.01 else { return }

    let safeOldWidth = max(1, oldWidth)
    let rawLeftOffset = dayRange.lowerBound + Int(floor(max(0, horizontalOffsetX) / safeOldWidth))
    let leftOffset = min(max(rawLeftOffset, dayRange.lowerBound), dayRange.upperBound)
    let targetX = CGFloat(leftOffset - dayRange.lowerBound) * newWidth

    horizontalOffsetX = max(0, targetX)
    scrollRequestGeneration += 1
    requestedOffsetX = max(0, targetX)
  }

  func offscreenDirection(
    for bar: TimelineProjectBar,
    visibleLowerOffset: Int,
    visibleUpperOffset: Int
  ) -> OffscreenDirection? {
    guard let targetTaskOffset = firstRemainingTaskOffset(for: bar) else {
      return nil
    }

    if targetTaskOffset < visibleLowerOffset {
      return .left
    }
    if targetTaskOffset > visibleUpperOffset {
      return .right
    }
    return nil
  }

  func firstRemainingTaskOffset(for bar: TimelineProjectBar) -> Int? {
    guard let firstRemainingTaskDate = bar.dailyTaskCounts.keys.min() else {
      return nil
    }
    return max(dayOffset(for: firstRemainingTaskDate), dayRange.lowerBound)
  }

  func prepareTimelineInitialViewportIfNeeded(with bars: [TimelineProjectBar]) {
    let hasRows = !bars.isEmpty
    scheduleInitialScrollPositionIfNeeded(hasRows: hasRows)
    scheduleTimelineScrollPrewarmIfNeeded(hasRows: hasRows)
  }

  func scheduleInitialScrollPositionIfNeeded(hasRows: Bool) {
    guard hasRows, !didSetInitialScrollPosition else { return }
    requestTodayScrollPosition(isExplicitRequest: false)
    didSetInitialScrollPosition = true
  }

  func scheduleTimelineScrollPrewarmIfNeeded(hasRows: Bool) {
    guard hasRows, isActive, !didPrewarmTimelineScrollMode, timelineScrollSession == nil else {
      return
    }

    didPrewarmTimelineScrollMode = true
    let prewarmSession = TimelineScrollSessionMetrics(
      startedAt: .now,
      offsetEvents: 0,
      preciseHoverOffsetEvents: 0,
      suppressedTaskBadgeHoverEvents: 0,
      suppressedDayHeaderHoverEvents: 0,
      lastHorizontalOffset: max(0, horizontalOffsetX),
      lastVerticalOffset: max(0, verticalOffsetY)
    )
    timelineScrollSession = prewarmSession
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()

    DispatchQueue.main.async {
      guard timelineScrollSession === prewarmSession else { return }
      finishTimelineScrollSession(reason: "prewarm")
    }
  }

  func requestTodayScrollPosition(isExplicitRequest: Bool) {
    let targetDayOffset = min(max(-2, dayRange.lowerBound), dayRange.upperBound)
    if isExplicitRequest {
      scrollRequestGeneration += 1
    }
    let x = CGFloat(targetDayOffset - dayRange.lowerBound) * dayColumnWidth
    requestedOffsetX = max(0, x)
  }

  func seedRangeIfNeeded(with bars: [TimelineProjectBar]) {
    guard let span = spanOffsets(for: bars) else {
      dayRange = -fallbackPastDays...max(dayRange.upperBound, minimumFutureDays)
      return
    }

    let lower = max(span.lower, -fallbackPastDays)
    let upper = max(span.upper + seedPaddingDays, minimumFutureDays)
    dayRange = lower...upper
  }

  func spanOffsets(for bars: [TimelineProjectBar]) -> (
    lower: Int, upper: Int, hasPastBeforeToday: Bool
  )? {
    var lower: Int?
    var upper: Int?
    var hasPastBeforeToday = false

    for bar in bars {
      guard let coverage = coverageOffsets(for: bar) else { continue }
      let localLower = coverage.lower
      let localUpper = coverage.upper

      if localLower < 0 {
        hasPastBeforeToday = true
      }
      lower = min(lower ?? localLower, localLower)
      upper = max(upper ?? localUpper, localUpper)
    }

    guard let lower, let upper else { return nil }
    return (lower, upper, hasPastBeforeToday)
  }

  func dayOffset(for date: Date) -> Int {
    let target = calendar.startOfDay(for: date)
    return calendar.dateComponents([.day], from: anchorDate, to: target).day ?? 0
  }

  func date(for offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: anchorDate) ?? anchorDate
  }

  var leadingVisibleDayOffset: Int {
    let scrolledDays = Int(floor(horizontalOffsetX / dayColumnWidth))
    let raw = dayRange.lowerBound + max(0, scrolledDays)
    return min(max(raw, dayRange.lowerBound), dayRange.upperBound)
  }

  var currentMonthText: String {
    date(for: leadingVisibleDayOffset)
      .formatted(.dateTime.locale(Locale(identifier: "ko_KR")).year().month(.wide))
  }

  func computedLiveBars(
    projectIDs: [UUID],
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    workspaceProjectSummaries: [UUID: ProjectSummaryRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> [TimelineProjectBar] {
    TimelineBoardReadPath.resolvedBars(
      service: appState.timelineService,
      projectIDs: projectIDs,
      workspaceProjectSnapshots: workspaceProjectSnapshots,
      workspaceProjectSummaries: workspaceProjectSummaries,
      scheduleEntriesByProjectID: scheduleEntriesByProjectID
    )
  }

  static func orderedTimelineBars(
    _ bars: [TimelineProjectBar],
    by projectIDs: [UUID]
  ) -> [TimelineProjectBar] {
    guard !projectIDs.isEmpty else { return bars }

    let barsByProjectID = Dictionary(
      uniqueKeysWithValues: bars.map { ($0.projectID, $0) }
    )
    let coveredProjectIDs = Set(barsByProjectID.keys)
    guard Set(projectIDs).isSubset(of: coveredProjectIDs) else {
      return bars
    }

    return projectIDs.compactMap { barsByProjectID[$0] }
  }

  func timelineRefreshSignature(
    projectIDs: [UUID],
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    workspaceProjectSummaries: [UUID: ProjectSummaryRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(projectIDs)
    hasher.combine(
      TimelineBoardReadPath.workspaceDetailSignature(
        projectIDs: projectIDs,
        workspaceProjectSnapshots: workspaceProjectSnapshots,
        workspaceProjectSummaries: workspaceProjectSummaries,
        scheduleEntriesByProjectID: scheduleEntriesByProjectID
      )
    )
    return hasher.finalize()
  }

  func refreshTimelineBarsIfNeeded(
    projectIDs: [UUID],
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    workspaceProjectSummaries: [UUID: ProjectSummaryRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]],
    sourceSignature: Int,
    force: Bool
  ) -> [TimelineProjectBar] {
    if !force,
      let cachedTimelineBarsSourceSignature,
      cachedTimelineBarsSourceSignature == sourceSignature
    {
      return cachedTimelineBars
    }

    let refreshed = computedLiveBars(
      projectIDs: projectIDs,
      workspaceProjectSnapshots: workspaceProjectSnapshots,
      workspaceProjectSummaries: workspaceProjectSummaries,
      scheduleEntriesByProjectID: scheduleEntriesByProjectID
    )
    cachedTimelineBars = refreshed
    cachedTimelineRowLayouts = buildRowLayouts(for: refreshed)
    cachedTimelineBarsSourceSignature = sourceSignature
    cachedTimelineBarsPresentationSignature = timelineSignature(for: refreshed)
    return refreshed
  }

  func timelineSignature(for bars: [TimelineProjectBar]) -> Int {
    var hasher = Hasher()
    hasher.combine(bars.count)
    for bar in bars {
      hasher.combine(bar.id)
      hasher.combine(bar.title)
      hasher.combine(bar.colorHex)
      hasher.combine(bar.start?.timeIntervalSinceReferenceDate)
      hasher.combine(bar.end?.timeIntervalSinceReferenceDate)
      hasher.combine(bar.deadline?.timeIntervalSinceReferenceDate)
      hasher.combine(bar.progress)
      hasher.combine(bar.remainingTaskCount)
      hasher.combine(bar.undatedRemainingTaskCount)
      hasher.combine(bar.dailyTaskCounts.count)
      hasher.combine(bar.dailyTaskCounts.values.reduce(0, +))
      hasher.combine(bar.dailyTaskPreviews.count)
      for day in bar.dailyTaskPreviews.keys.sorted() {
        hasher.combine(day.timeIntervalSinceReferenceDate)
        if let preview = bar.dailyTaskPreviews[day] {
          hasher.combine(preview.totalCount)
          hasher.combine(preview.tasks.count)
          for task in preview.tasks {
            hasher.combine(task.id)
            hasher.combine(task.taskID)
            hasher.combine(task.title)
          }
        }
      }
      hasher.combine(bar.dailyPlannedWorkCounts.count)
      hasher.combine(bar.dailyPlannedWorkCounts.values.reduce(0, +))
      hasher.combine(bar.dailyPlannedWorkPreviews.count)
      for day in bar.dailyPlannedWorkPreviews.keys.sorted() {
        hasher.combine(day.timeIntervalSinceReferenceDate)
        if let preview = bar.dailyPlannedWorkPreviews[day] {
          hasher.combine(preview.totalCount)
          hasher.combine(preview.tasks.count)
          for task in preview.tasks {
            hasher.combine(task.id)
            hasher.combine(task.taskID)
            hasher.combine(task.title)
            hasher.combine(task.targetCompletedUnits)
          }
        }
      }
      hasher.combine(bar.dailyCompletedTaskCounts.count)
      hasher.combine(bar.dailyCompletedTaskCounts.values.reduce(0, +))
      for day in bar.dailyCompletedTaskCounts.keys.sorted() {
        hasher.combine(day.timeIntervalSinceReferenceDate)
        hasher.combine(bar.dailyCompletedTaskCounts[day] ?? 0)
      }
      hasher.combine(bar.dailyCompletedTaskPreviews.count)
      for day in bar.dailyCompletedTaskPreviews.keys.sorted() {
        hasher.combine(day.timeIntervalSinceReferenceDate)
        if let preview = bar.dailyCompletedTaskPreviews[day] {
          hasher.combine(preview.totalCount)
          hasher.combine(preview.tasks.count)
          for task in preview.tasks {
            hasher.combine(task.id)
            hasher.combine(task.taskID)
            hasher.combine(task.title)
          }
        }
      }
      hasher.combine(bar.nextUpcomingDate?.timeIntervalSinceReferenceDate)
    }
    return hasher.finalize()
  }
}
