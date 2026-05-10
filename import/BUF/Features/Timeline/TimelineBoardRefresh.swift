import Foundation
import SwiftUI

enum TimelineBoardReadPath {
  static let pastIncompleteContextDays = 7
  static let visibleDayRange: ClosedRange<Int> = -pastIncompleteContextDays...61

  static func resolvedVisibleDayRange(
    for bars: [TimelineProjectBar],
    anchorDate: Date,
    calendar: Calendar
  ) -> ClosedRange<Int> {
    let anchorDay = calendar.startOfDay(for: anchorDate)
    let oldestPastIncompleteOffset = bars
      .flatMap(\.dailyTaskCounts.keys)
      .compactMap { day in
        calendar.dateComponents([.day], from: anchorDay, to: calendar.startOfDay(for: day)).day
      }
      .filter { $0 < 0 }
      .min()
    let contextLowerBound = (oldestPastIncompleteOffset ?? 0) - pastIncompleteContextDays
    let lowerBound = min(visibleDayRange.lowerBound, contextLowerBound)

    return lowerBound...visibleDayRange.upperBound
  }

  static func pinnedTopSignature(
    anchorDate: Date,
    dayRange: ClosedRange<Int>,
    dayColumnWidth: CGFloat,
    localeIdentifier: String,
    isTimelineScrolling: Bool
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(anchorDate.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(Int((dayColumnWidth * 100).rounded()))
    hasher.combine(localeIdentifier)
    hasher.combine(isTimelineScrolling)
    return hasher.finalize()
  }

  static func reorderedProjectIDsAfterDrop(
    _ projectIDs: [UUID],
    draggedID: UUID,
    targetID: UUID,
    placement: TimelineProjectDropPlacement
  ) -> [UUID]? {
    guard projectIDs.contains(targetID), draggedID != targetID else {
      return nil
    }

    var reordered = projectIDs.filter { $0 != draggedID }
    guard let adjustedTargetIndex = reordered.firstIndex(of: targetID) else { return nil }
    let insertionIndex: Int
    switch placement {
    case .before:
      insertionIndex = adjustedTargetIndex
    case .after:
      insertionIndex = adjustedTargetIndex + 1
    }
    reordered.insert(draggedID, at: min(insertionIndex, reordered.count))
    return reordered == projectIDs ? nil : reordered
  }

  static func reorderedProjectIDsAfterProjectListDrop(
    bars: [TimelineProjectBar],
    mode: ProjectListSortMode,
    draggedID: UUID,
    targetID: UUID,
    placement: TimelineProjectDropPlacement,
    stageForBar: (TimelineProjectBar) -> ProjectProgressStage
  ) -> [UUID]? {
    let scopedProjectIDs: [UUID]
    switch mode {
    case .manual:
      scopedProjectIDs = bars.map(\.projectID)
    case .priority, .bucketGrouped:
      guard let targetBar = bars.first(where: { $0.projectID == targetID }) else {
        return nil
      }
      let targetStage = stageForBar(targetBar)
      scopedProjectIDs = bars
        .filter { stageForBar($0) == targetStage }
        .map(\.projectID)
    case .recent, .title:
      return nil
    }

    return reorderedProjectIDsAfterDrop(
      scopedProjectIDs,
      draggedID: draggedID,
      targetID: targetID,
      placement: placement
    )
  }

  static func reorderedTaskIDsAfterDrop(
    _ taskIDs: [UUID],
    draggedID: UUID,
    targetID: UUID,
    placement: TimelineProjectDropPlacement
  ) -> [UUID]? {
    reorderedProjectIDsAfterDrop(
      taskIDs,
      draggedID: draggedID,
      targetID: targetID,
      placement: placement
    )
  }

  static func dayHeaderHoverOffset(
    locationX: CGFloat,
    dayRange: ClosedRange<Int>,
    dayColumnWidth: CGFloat
  ) -> Int? {
    guard dayColumnWidth > 0, locationX >= 0 else { return nil }
    let offset = dayRange.lowerBound + Int(floor(locationX / dayColumnWidth))
    guard dayRange.contains(offset) else { return nil }
    return offset
  }

  static func dayHeaderHoverOffset(
    contentLocation: CGPoint,
    visibleBoundsOrigin: CGPoint,
    titleColumnWidth: CGFloat,
    headerHeight: CGFloat,
    dayRange: ClosedRange<Int>,
    dayColumnWidth: CGFloat
  ) -> Int? {
    let visibleX = contentLocation.x - visibleBoundsOrigin.x
    let visibleY = contentLocation.y - visibleBoundsOrigin.y
    guard visibleX >= titleColumnWidth, visibleY >= 0, visibleY < headerHeight else {
      return nil
    }
    return dayHeaderHoverOffset(
      locationX: contentLocation.x - titleColumnWidth,
      dayRange: dayRange,
      dayColumnWidth: dayColumnWidth
    )
  }

  static func taskBadgeHoverID(
    contentLocation: CGPoint,
    visibleBoundsOrigin: CGPoint,
    titleColumnWidth: CGFloat,
    headerHeight: CGFloat,
    targets: [TimelineTaskBadgeHitTarget]
  ) -> String? {
    let visibleX = contentLocation.x - visibleBoundsOrigin.x
    let visibleY = contentLocation.y - visibleBoundsOrigin.y
    guard visibleX >= titleColumnWidth, visibleY >= headerHeight else {
      return nil
    }
    return targets.first { target in
      target.rect.contains(contentLocation)
    }?.badgeID
  }

  static func didScrollOriginChange(
    from previous: CGPoint?,
    to next: CGPoint,
    tolerance: CGFloat = 0.5
  ) -> Bool {
    guard let previous else { return false }
    return abs(previous.x - next.x) > tolerance || abs(previous.y - next.y) > tolerance
  }

  static func projectColorHex(
    forProjectReference reference: WorkspaceProjectReference,
    in bars: [TimelineProjectBar]
  ) -> String? {
    bars.first { $0.projectReference.id == reference.id }?.colorHex
  }

  static func timelinePreviewTitle(for title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "제목 없음" : trimmed
  }

  static func projectListPopoverEntries(from entries: [ScheduleSliceEntry])
    -> [ScheduleSliceEntry]
  {
    entries
      .filter { !$0.isArchived && !$0.isCompleted }
      .sorted(by: projectListEntrySort)
  }

  static func projectListWindowEntries(from entries: [ScheduleSliceEntry])
    -> [ScheduleSliceEntry]
  {
    entries
      .filter { !$0.isArchived }
      .sorted(by: projectListEntrySort)
  }

  private static func projectListEntrySort(
    _ lhs: ScheduleSliceEntry,
    _ rhs: ScheduleSliceEntry
  ) -> Bool {
    if lhs.isCompleted != rhs.isCompleted {
      return !lhs.isCompleted
    }

    if lhs.rowOrder != rhs.rowOrder {
      return lhs.rowOrder < rhs.rowOrder
    }

    let titleComparison = timelinePreviewTitle(for: lhs.title)
      .localizedStandardCompare(timelinePreviewTitle(for: rhs.title))
    if titleComparison != .orderedSame {
      return titleComparison == .orderedAscending
    }

    return lhs.taskID.uuidString < rhs.taskID.uuidString
  }

  static func dayHeaderSectionsByDay(
    from bars: [TimelineProjectBar],
    today: Date
  ) -> [Date: [TimelineDayHeaderOverlayProjectSection]] {
    var sectionsByDay: [Date: [TimelineDayHeaderOverlayProjectSection]] = [:]

    for bar in bars {
      var tasksByDay: [Date: [TimelineDayHeaderOverlayTaskItem]] = [:]
      for day in bar.dailyTaskPreviews.keys.sorted() {
        guard let preview = bar.dailyTaskPreviews[day] else { continue }
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

      for day in bar.dailyCompletedTaskPreviews.keys.sorted() {
        guard let preview = bar.dailyCompletedTaskPreviews[day] else { continue }
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

      for day in tasksByDay.keys.sorted() {
        guard let items = tasksByDay[day] else { continue }
        sectionsByDay[day, default: []].append(
          TimelineDayHeaderOverlayProjectSection(
            id: bar.projectID,
            projectReference: bar.projectReference,
            projectColorHex: bar.colorHex,
            projectTitle: bar.title,
            tasks: items
          )
        )
      }
    }

    return sectionsByDay
  }

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

  static func orderedBars(
    _ bars: [TimelineProjectBar],
    mode: ProjectListSortMode,
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    workspaceProjectSummaries: [UUID: ProjectSummaryRecord],
    manualOrderByProjectID: [UUID: Int64]
  ) -> [TimelineProjectBar] {
    switch mode {
    case .recent:
      return bars.sorted {
        let lhsDate = latestActivityDate(
          for: $0,
          workspaceProjectSnapshots: workspaceProjectSnapshots,
          workspaceProjectSummaries: workspaceProjectSummaries
        )
        let rhsDate = latestActivityDate(
          for: $1,
          workspaceProjectSnapshots: workspaceProjectSnapshots,
          workspaceProjectSummaries: workspaceProjectSummaries
        )
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return titleSort($0, $1)
      }
    case .title:
      return bars.sorted(by: titleSort)
    case .priority, .bucketGrouped:
      return bars.sorted {
        let lhsStage = stage(for: $0, workspaceProjectSnapshots: workspaceProjectSnapshots)
        let rhsStage = stage(for: $1, workspaceProjectSnapshots: workspaceProjectSnapshots)
        if lhsStage.rawValue != rhsStage.rawValue { return lhsStage.rawValue < rhsStage.rawValue }
        let lhsOrder = manualOrderByProjectID[$0.projectID] ?? Int64.max
        let rhsOrder = manualOrderByProjectID[$1.projectID] ?? Int64.max
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
        return titleSort($0, $1)
      }
    case .manual:
      return bars.sorted {
        let lhsOrder = manualOrderByProjectID[$0.projectID] ?? Int64.max
        let rhsOrder = manualOrderByProjectID[$1.projectID] ?? Int64.max
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
        return titleSort($0, $1)
      }
    }
  }

  static func normalizedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    return projectIDs.filter { seen.insert($0).inserted }
  }

  static func visibleProjectIDs(
    _ projectIDs: [UUID],
    hiddenProjectIDs: Set<UUID>
  ) -> [UUID] {
    normalizedProjectIDs(projectIDs).filter { !hiddenProjectIDs.contains($0) }
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

  static func shouldShowLoadingState(
    projectIDs: [UUID],
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]],
    readBlocker: RetainedWorkspaceSurfaceProjectionBlocker?
  ) -> Bool {
    guard readBlocker == nil else { return false }
    return !normalizedProjectIDs(projectIDs).isEmpty
      && !hasCompleteWorkspaceCoverage(
        projectIDs: projectIDs,
        workspaceProjectSnapshots: workspaceProjectSnapshots,
        scheduleEntriesByProjectID: scheduleEntriesByProjectID
      )
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
      hasher.combine(project.isArchived)
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
        hasher.combine(summary.isArchived)
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

  private static func latestActivityDate(
    for bar: TimelineProjectBar,
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    workspaceProjectSummaries: [UUID: ProjectSummaryRecord]
  ) -> Date {
    let projectDate = workspaceProjectSnapshots[bar.projectID]?.updatedAt ?? .distantPast
    guard let taskDate = workspaceProjectSummaries[bar.projectID]?.latestTaskUpdatedAt else {
      return projectDate
    }
    return max(projectDate, taskDate)
  }

  private static func stage(
    for bar: TimelineProjectBar,
    workspaceProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord]
  ) -> ProjectProgressStage {
    if let rawValue = workspaceProjectSnapshots[bar.projectID]?.progressStageRaw,
      let stage = ProjectProgressStage.fromStorageValue(rawValue)
    {
      return stage
    }
    return ProjectProgressStage.from(progress: bar.progress)
  }

  private static func titleSort(_ lhs: TimelineProjectBar, _ rhs: TimelineProjectBar) -> Bool {
    lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }
}

extension TimelineBoardView {
  @MainActor
  func reloadWorkspaceTimelineProjectDetails(
    for projectIDs: [UUID],
    force: Bool = false
  ) async {
    let requestedProjectIDs = TimelineBoardReadPath.normalizedProjectIDs(projectIDs)
    let loadSignature = TimelineBoardReadPath.workspaceLoadSignature(
      projectIDs: requestedProjectIDs,
      workspaceTreeRevision: appState.workspaceTreeRevision
    )
    guard force || workspaceTimelineLastLoadSignature != loadSignature else { return }
    workspaceTimelineLoadGeneration += 1
    let loadGeneration = workspaceTimelineLoadGeneration
    guard !requestedProjectIDs.isEmpty else {
      let didChange = !workspaceTimelineProjectSnapshots.isEmpty
        || !workspaceTimelineProjectSummaries.isEmpty
        || !workspaceTimelineScheduleEntriesByProjectID.isEmpty
        || retainedTimelineReadBlocker != nil
        || !retainedTimelineCalendarBridgeDecisionsByTaskID.isEmpty
        || !retainedTimelineCalendarBridgeWriteMarkersByTaskID.isEmpty
      if didChange {
        workspaceTimelineProjectSnapshots = [:]
        workspaceTimelineProjectSummaries = [:]
        workspaceTimelineScheduleEntriesByProjectID = [:]
        retainedTimelineReadBlocker = nil
        retainedTimelineCalendarBridgeDecisionsByTaskID = [:]
        retainedTimelineCalendarBridgeWriteMarkersByTaskID = [:]
        invalidateWorkspaceTimelineProjectionCaches()
      }
      workspaceTimelineLastLoadSignature = loadSignature
      return
    }

    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: appState.obsidianVaultRootURL,
      projectIDs: requestedProjectIDs
    )
    guard loadGeneration == workspaceTimelineLoadGeneration else { return }
    let resolvedRead = RetainedWorkspaceProjectStageOverridePolicy.apply(
      pendingTimelineProjectStageOverrides,
      to: RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(retainedResult)
    )
    let nextReadBlocker: RetainedWorkspaceSurfaceProjectionBlocker?
    if case .blocked(let blocker) = resolvedRead.source {
      nextReadBlocker = blocker
    } else {
      nextReadBlocker = nil
    }
    let currentTaskIDs = Set(resolvedRead.calendarBridgeDecisionsByTaskID.keys)
    let nextWriteMarkers = retainedTimelineCalendarBridgeWriteMarkersByTaskID.filter {
      currentTaskIDs.contains($0.key)
    }
    let didChange = workspaceTimelineProjectSnapshots != resolvedRead.projectSnapshots
      || workspaceTimelineProjectSummaries != resolvedRead.projectSummaries
      || workspaceTimelineScheduleEntriesByProjectID != resolvedRead.scheduleEntriesByProjectID
      || retainedTimelineReadBlocker != nextReadBlocker
      || retainedTimelineCalendarBridgeDecisionsByTaskID != resolvedRead.calendarBridgeDecisionsByTaskID
      || retainedTimelineCalendarBridgeWriteMarkersByTaskID != nextWriteMarkers
    if didChange {
      retainedTimelineReadBlocker = nextReadBlocker
      workspaceTimelineProjectSnapshots = resolvedRead.projectSnapshots
      workspaceTimelineProjectSummaries = resolvedRead.projectSummaries
      workspaceTimelineScheduleEntriesByProjectID = resolvedRead.scheduleEntriesByProjectID
      retainedTimelineCalendarBridgeDecisionsByTaskID =
        resolvedRead.calendarBridgeDecisionsByTaskID
      retainedTimelineCalendarBridgeWriteMarkersByTaskID = nextWriteMarkers
      invalidateWorkspaceTimelineProjectionCaches()
      rebuildWorkspaceTimelineProjectionCachesAfterMutation()
    }
    workspaceTimelineLastLoadSignature = loadSignature
    if case .blocked = resolvedRead.source {
      appState.errorMessage = resolvedRead.errorMessage
    }
  }

  @MainActor
  func reloadChangedWorkspaceTimelineProjectDetails(for projectIDs: [UUID]) async {
    let requestedProjectIDs = Set(TimelineBoardReadPath.normalizedProjectIDs(projectIDs))
    guard !requestedProjectIDs.isEmpty else { return }
    workspaceTimelineLoadGeneration += 1
    let loadGeneration = workspaceTimelineLoadGeneration
    workspaceTimelineLastLoadSignature = TimelineBoardReadPath.workspaceLoadSignature(
      projectIDs: activeProjectIDs,
      workspaceTreeRevision: appState.workspaceTreeRevision
    )
    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: appState.obsidianVaultRootURL,
      projectIDs: Array(requestedProjectIDs)
    )
    guard loadGeneration == workspaceTimelineLoadGeneration else { return }

    guard case .loaded(let loadedProjection) = retainedResult else {
      await reloadWorkspaceTimelineProjectDetails(for: activeProjectIDs, force: true)
      return
    }

    let existingProjection = RetainedWorkspaceSurfaceProjection(
      projectSnapshots: workspaceTimelineProjectSnapshots,
      projectSummaries: workspaceTimelineProjectSummaries,
      scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID,
      calendarBridgeDecisionsByTaskID: retainedTimelineCalendarBridgeDecisionsByTaskID
    )
    let mergedProjection = RetainedWorkspaceSurfaceProjectionMergePolicy.merge(
      existing: existingProjection,
      loaded: loadedProjection,
      replacingProjectIDs: requestedProjectIDs
    )
    let visibleProjection = RetainedWorkspaceProjectStageOverridePolicy.apply(
      pendingTimelineProjectStageOverrides,
      to: mergedProjection
    )
    let nextWriteMarkers = RetainedWorkspaceSurfaceProjectionMergePolicy.filteredWriteMarkers(
      existingMarkers: retainedTimelineCalendarBridgeWriteMarkersByTaskID,
      existing: existingProjection,
      loaded: loadedProjection,
      replacingProjectIDs: requestedProjectIDs
    )
    let didChange = workspaceTimelineProjectSnapshots != visibleProjection.projectSnapshots
      || workspaceTimelineProjectSummaries != visibleProjection.projectSummaries
      || workspaceTimelineScheduleEntriesByProjectID != visibleProjection.scheduleEntriesByProjectID
      || retainedTimelineReadBlocker != nil
      || retainedTimelineCalendarBridgeDecisionsByTaskID != visibleProjection.calendarBridgeDecisionsByTaskID
      || retainedTimelineCalendarBridgeWriteMarkersByTaskID != nextWriteMarkers
    if didChange {
      retainedTimelineReadBlocker = nil
      workspaceTimelineProjectSnapshots = visibleProjection.projectSnapshots
      workspaceTimelineProjectSummaries = visibleProjection.projectSummaries
      workspaceTimelineScheduleEntriesByProjectID = visibleProjection.scheduleEntriesByProjectID
      retainedTimelineCalendarBridgeDecisionsByTaskID =
        visibleProjection.calendarBridgeDecisionsByTaskID
      retainedTimelineCalendarBridgeWriteMarkersByTaskID = nextWriteMarkers
      invalidateWorkspaceTimelineProjectionCaches()
      rebuildWorkspaceTimelineProjectionCachesAfterMutation()
    }
    workspaceTimelineLastLoadSignature = TimelineBoardReadPath.workspaceLoadSignature(
      projectIDs: activeProjectIDs,
      workspaceTreeRevision: appState.workspaceTreeRevision
    )
  }

  func invalidateWorkspaceTimelineProjectionCaches() {
    cachedTimelineBars = []
    cachedTimelineRowLayouts = []
    cachedTimelineBarsSourceSignature = nil
    cachedTimelineBarsPresentationSignature = nil
    cachedTimelineDayHeaderSections = [:]
    cachedTimelineDayHeaderSourceSignature = nil
  }

  @discardableResult
  func rebuildWorkspaceTimelineProjectionCachesAfterMutation() -> [TimelineProjectBar] {
    guard !activeProjectIDs.isEmpty else { return [] }
    let sourceSignature = timelineRefreshSignature(
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
      sourceSignature: sourceSignature,
      force: true
    )
    appState.updateTimelineProjectListVisibleOrder(refreshedBars.map(\.projectID))
    refreshTimelineDayHeaderSectionsIfNeeded(
      from: refreshedBars,
      sourceSignature: sourceSignature,
      force: true
    )
    return refreshedBars
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
    let nextRange = TimelineBoardReadPath.resolvedVisibleDayRange(
      for: bars,
      anchorDate: anchorDate,
      calendar: calendar
    )
    guard nextRange != dayRange else { return }

    let previousLeadingOffset = leadingVisibleDayOffset
    dayRange = nextRange

    let preservedLeadingOffset = min(
      max(previousLeadingOffset, nextRange.lowerBound),
      nextRange.upperBound
    )
    let preservedX = CGFloat(preservedLeadingOffset - nextRange.lowerBound) * dayColumnWidth
    horizontalOffsetX = max(0, preservedX)
    scrollRequestGeneration += 1
    requestedOffsetX = max(0, preservedX)
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
    let bars = TimelineBoardReadPath.resolvedBars(
      service: appState.timelineService,
      projectIDs: projectIDs,
      workspaceProjectSnapshots: workspaceProjectSnapshots,
      workspaceProjectSummaries: workspaceProjectSummaries,
      scheduleEntriesByProjectID: scheduleEntriesByProjectID
    )
    return TimelineBoardReadPath.orderedBars(
      bars,
      mode: projectListSortMode,
      workspaceProjectSnapshots: workspaceProjectSnapshots,
      workspaceProjectSummaries: workspaceProjectSummaries,
      manualOrderByProjectID: timelineProjectManualOrder
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
    hasher.combine(projectListSortMode)
    for projectID in projectIDs {
      hasher.combine(timelineProjectManualOrder[projectID])
    }
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
    refreshOpenTimelineProjectListWindow(using: refreshed)
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
