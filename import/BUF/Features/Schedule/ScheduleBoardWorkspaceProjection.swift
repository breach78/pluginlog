import AppKit
import SwiftUI

extension ScheduleBoardView {
  func reloadWorkspaceScheduleProjectDetails(
    for projectIDs: [UUID],
    force: Bool = false
  ) async {
    let requestedProjectIDs = Array(Set(projectIDs))
    let loadSignature = scheduleWorkspaceLoadSignature(
      projectIDs: requestedProjectIDs,
      workspaceTreeRevision: appState.workspaceTreeRevision
    )
    guard force || workspaceScheduleLastLoadSignature != loadSignature else { return }
    workspaceScheduleLoadGeneration += 1
    let loadGeneration = workspaceScheduleLoadGeneration
    guard !requestedProjectIDs.isEmpty else {
      await MainActor.run {
        let didChange = !workspaceScheduleProjectSnapshots.isEmpty
          || !workspaceScheduleSliceEntriesByProjectID.isEmpty
          || !retainedScheduleCalendarBridgeDecisionsByTaskID.isEmpty
          || !retainedScheduleCalendarBridgeWriteMarkersByTaskID.isEmpty
        if didChange {
          workspaceScheduleProjectSnapshots = [:]
          workspaceScheduleSliceEntriesByProjectID = [:]
          retainedScheduleCalendarBridgeDecisionsByTaskID = [:]
          retainedScheduleCalendarBridgeWriteMarkersByTaskID = [:]
          invalidateWorkspaceScheduleProjectionCaches()
        }
        workspaceScheduleLastLoadSignature = loadSignature
        recordWorkspaceLoadFallback(nil)
      }
      return
    }

    let obsidianVaultRootURL = await MainActor.run { appState.obsidianVaultRootURL }
    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: obsidianVaultRootURL,
      projectIDs: requestedProjectIDs
    )

    await MainActor.run {
      guard loadGeneration == workspaceScheduleLoadGeneration else { return }
      let resolvedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(retainedResult)
      let currentTaskIDs = Set(resolvedRead.calendarBridgeDecisionsByTaskID.keys)
      let nextWriteMarkers = retainedScheduleCalendarBridgeWriteMarkersByTaskID.filter {
        currentTaskIDs.contains($0.key)
      }
      let didChange = workspaceScheduleProjectSnapshots != resolvedRead.projectSnapshots
        || workspaceScheduleSliceEntriesByProjectID != resolvedRead.scheduleEntriesByProjectID
        || retainedScheduleCalendarBridgeDecisionsByTaskID != resolvedRead.calendarBridgeDecisionsByTaskID
        || retainedScheduleCalendarBridgeWriteMarkersByTaskID != nextWriteMarkers
      if didChange {
        workspaceScheduleProjectSnapshots = resolvedRead.projectSnapshots
        workspaceScheduleSliceEntriesByProjectID = resolvedRead.scheduleEntriesByProjectID
        retainedScheduleCalendarBridgeDecisionsByTaskID =
          resolvedRead.calendarBridgeDecisionsByTaskID
        retainedScheduleCalendarBridgeWriteMarkersByTaskID = nextWriteMarkers
        invalidateWorkspaceScheduleProjectionCaches()
      }
      workspaceScheduleLastLoadSignature = loadSignature

      committedTaskDrop = nil
      switch resolvedRead.source {
      case .retained:
        recordWorkspaceLoadFallback(nil)
      case .blocked:
        appState.errorMessage = resolvedRead.errorMessage
        recordWorkspaceLoadFallback(nil)
      }
    }
  }

  func reloadChangedWorkspaceScheduleProjectDetails(for projectIDs: [UUID]) async {
    let requestedProjectIDs = Set(projectIDs)
    guard !requestedProjectIDs.isEmpty else { return }
    workspaceScheduleLoadGeneration += 1
    let loadGeneration = workspaceScheduleLoadGeneration
    workspaceScheduleLastLoadSignature = scheduleWorkspaceLoadSignature(
      projectIDs: activeProjectIDs,
      workspaceTreeRevision: appState.workspaceTreeRevision
    )
    let obsidianVaultRootURL = await MainActor.run { appState.obsidianVaultRootURL }
    let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      obsidianVaultRootURL: obsidianVaultRootURL,
      projectIDs: Array(requestedProjectIDs)
    )

    guard case .loaded(let loadedProjection) = retainedResult else {
      let activeIDs = await MainActor.run { self.activeProjectIDs }
      await reloadWorkspaceScheduleProjectDetails(for: activeIDs, force: true)
      return
    }

    await MainActor.run {
      guard loadGeneration == workspaceScheduleLoadGeneration else { return }
      let existingProjection = RetainedWorkspaceSurfaceProjection(
        projectSnapshots: workspaceScheduleProjectSnapshots,
        projectSummaries: [:],
        scheduleEntriesByProjectID: workspaceScheduleSliceEntriesByProjectID,
        calendarBridgeDecisionsByTaskID: retainedScheduleCalendarBridgeDecisionsByTaskID
      )
      let mergedProjection = RetainedWorkspaceSurfaceProjectionMergePolicy.merge(
        existing: existingProjection,
        loaded: loadedProjection,
        replacingProjectIDs: requestedProjectIDs
      )
      let nextWriteMarkers = RetainedWorkspaceSurfaceProjectionMergePolicy.filteredWriteMarkers(
        existingMarkers: retainedScheduleCalendarBridgeWriteMarkersByTaskID,
        existing: existingProjection,
        loaded: loadedProjection,
        replacingProjectIDs: requestedProjectIDs
      )
      let didChange = workspaceScheduleProjectSnapshots != mergedProjection.projectSnapshots
        || workspaceScheduleSliceEntriesByProjectID != mergedProjection.scheduleEntriesByProjectID
        || retainedScheduleCalendarBridgeDecisionsByTaskID != mergedProjection.calendarBridgeDecisionsByTaskID
        || retainedScheduleCalendarBridgeWriteMarkersByTaskID != nextWriteMarkers
      if didChange {
        workspaceScheduleProjectSnapshots = mergedProjection.projectSnapshots
        workspaceScheduleSliceEntriesByProjectID = mergedProjection.scheduleEntriesByProjectID
        retainedScheduleCalendarBridgeDecisionsByTaskID =
          mergedProjection.calendarBridgeDecisionsByTaskID
        retainedScheduleCalendarBridgeWriteMarkersByTaskID = nextWriteMarkers
        invalidateWorkspaceScheduleProjectionCaches()
      }
      workspaceScheduleLastLoadSignature = scheduleWorkspaceLoadSignature(
        projectIDs: activeProjectIDs,
        workspaceTreeRevision: appState.workspaceTreeRevision
      )
      committedTaskDrop = nil
      recordWorkspaceLoadFallback(nil)
    }
  }

  func invalidateWorkspaceScheduleProjectionCaches() {
    cachedScheduledTaskSourceSignature = nil
    cachedScheduledTaskDescriptors = []
    cachedWorkspaceScheduleTasksByID = [:]
    cachedScheduleTaskSignature = 0
    cachedLayoutSourceSignature = nil
    cachedTimedEntries = []
    cachedAllDayEntries = []
    cachedBackgroundTimedEntries = []
    cachedBackgroundAllDayEntries = []
    cachedScheduleDayHeaderSections = [:]
    cachedScheduleDayHeaderSourceSignature = nil
  }
}
