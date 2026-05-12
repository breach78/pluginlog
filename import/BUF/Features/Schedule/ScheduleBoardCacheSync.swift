import AppKit
import SwiftUI

extension ScheduleBoardView {
  func requestTodayScroll() {
    requestScroll(to: today)
  }

  func requestScroll(to targetDate: Date) {
    if scrollViewportState.scrollView == nil {
      recordScheduleViewportDiagnostic(.scrollRequestQueuedWithoutViewport)
    } else {
      clearScheduleViewportDiagnostic(.scrollRequestQueuedWithoutViewport)
    }
    let targetDay = calendar.startOfDay(for: targetDate)
    let targetOffset = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0
    let targetRange = (targetOffset - pastDayBuffer)...(targetOffset + futureDayWindow)
    if dayRange != targetRange {
      dayRange = targetRange
    }
    let targetIndex = max(0, targetOffset - targetRange.lowerBound)
    requestedOffsetX = CGFloat(targetIndex) * dayColumnWidth
    requestedOffsetY = headerHeight + CGFloat(defaultVisibleStartHour) * hourHeight
    scrollRequestGeneration += 1
  }

  func scheduleLayoutSourceSignature(filteredEventHash: Int, taskSignature: Int) -> Int {
    var hasher = Hasher()
    hasher.combine(today.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(taskSignature)
    hasher.combine(filteredEventHash)
    return hasher.finalize()
  }

  func resolvedScheduleLayoutSourceSignature(
    filteredEventHash: Int,
    taskSignature: Int,
    preferCached: Bool
  ) -> Int {
    if preferCached, let cachedLayoutSourceSignature {
      return cachedLayoutSourceSignature
    }
    return scheduleLayoutSourceSignature(
      filteredEventHash: filteredEventHash,
      taskSignature: taskSignature
    )
  }

  func syncScheduleBoardCaches(
    filteredEvents: [ScheduleCalendarEvent],
    backgroundEvents: [ScheduleCalendarEvent],
    taskSnapshot: ScheduleTaskSnapshotCache,
    layoutCache: ScheduleLayoutCache,
    layoutSourceSignature: Int,
    force: Bool
  ) {
    refreshScheduledTaskSnapshotIfNeeded(force: force, snapshot: taskSnapshot)
    refreshScheduleDayHeaderSectionsIfNeeded(
      sourceSignature: refreshedScheduleDayHeaderSourceSignature(
        taskSignature: taskSnapshot.signature
      ),
      force: force
    )
    refreshLayoutCacheIfNeeded(
      filteredEvents: filteredEvents,
      backgroundEvents: backgroundEvents,
      taskSnapshot: taskSnapshot,
      sourceSignature: layoutSourceSignature,
      force: force,
      layoutCache: layoutCache
    )
  }

  func applyLayoutCache(
    _ layoutCache: ScheduleLayoutCache,
    sourceSignature: Int
  ) {
    cachedTimedEntries = layoutCache.timedEntries
    cachedAllDayEntries = layoutCache.allDayEntries
    cachedBackgroundTimedEntries = layoutCache.backgroundTimedEntries
    cachedBackgroundAllDayEntries = layoutCache.backgroundAllDayEntries
    cachedLayoutSourceSignature = sourceSignature
  }

  func refreshLayoutCacheIfNeeded(
    filteredEvents: [ScheduleCalendarEvent],
    backgroundEvents: [ScheduleCalendarEvent],
    taskSnapshot: ScheduleTaskSnapshotCache,
    sourceSignature: Int,
    force: Bool,
    layoutCache: ScheduleLayoutCache? = nil
  ) {
    guard force || cachedLayoutSourceSignature != sourceSignature else { return }
    let layoutCache =
      layoutCache
      ?? buildLayoutCache(
        filteredEvents: filteredEvents,
        backgroundEvents: backgroundEvents,
        taskSnapshot: taskSnapshot
      )
    applyLayoutCache(layoutCache, sourceSignature: sourceSignature)
  }

  func resolvedScheduleTaskSnapshot(preferCached: Bool) -> ScheduleTaskSnapshotCache {
    let sourceSignature = scheduleTaskSourceSignature
    if preferCached, let cachedScheduledTaskSourceSignature {
      return ScheduleTaskSnapshotCache(
        sourceSignature: cachedScheduledTaskSourceSignature,
        taskDescriptors: cachedScheduledTaskDescriptors,
        workspaceTasksByID: cachedWorkspaceScheduleTasksByID,
        signature: cachedScheduleTaskSignature
      )
    }
    if cachedScheduledTaskSourceSignature == sourceSignature {
      return ScheduleTaskSnapshotCache(
        sourceSignature: cachedScheduledTaskSourceSignature ?? sourceSignature,
        taskDescriptors: cachedScheduledTaskDescriptors,
        workspaceTasksByID: cachedWorkspaceScheduleTasksByID,
        signature: cachedScheduleTaskSignature
      )
    }
    return buildScheduledTaskSnapshot(sourceSignature: sourceSignature)
  }

  func buildScheduledTaskSnapshot(sourceSignature: Int? = nil) -> ScheduleTaskSnapshotCache {
    let sourceSignature = sourceSignature ?? scheduleTaskSourceSignature
    return ScheduleProjectionService.buildTaskSnapshot(
      taskDescriptors: workspaceScheduleTasks,
      sourceSignature: sourceSignature
    )
  }

  func applyScheduledTaskSnapshot(_ snapshot: ScheduleTaskSnapshotCache) {
    cachedScheduledTaskSourceSignature = snapshot.sourceSignature
    cachedScheduledTaskDescriptors = snapshot.taskDescriptors
    cachedWorkspaceScheduleTasksByID = snapshot.workspaceTasksByID
    cachedScheduleTaskSignature = snapshot.signature
  }

  func refreshScheduledTaskSnapshotIfNeeded(
    force: Bool,
    snapshot: ScheduleTaskSnapshotCache? = nil
  ) {
    let snapshot = snapshot ?? buildScheduledTaskSnapshot(sourceSignature: scheduleTaskSourceSignature)
    guard force || cachedScheduledTaskSourceSignature != snapshot.sourceSignature else { return }
    applyScheduledTaskSnapshot(snapshot)
  }
}
