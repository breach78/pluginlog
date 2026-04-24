import AppKit
import Foundation
import SwiftData
import SwiftUI

extension OutlinerView {
  private var shouldWriteGlobalOutlinerCaches: Bool {
    preferredProjectID == nil
  }

  func restorePersistedStateIfNeeded() {
    guard !isPreviewMode else {
      hasRestoredPersistedState = true
      return
    }
    guard !hasRestoredPersistedState else { return }
    isRestoringPersistedState = true
    defer {
      isRestoringPersistedState = false
      hasRestoredPersistedState = true
    }

    let persistedProjectionSidecars = appState.resolvedRuntimeProjectionSidecarPayload()
    guard let runtimeLoaded = cachedRuntimeProjectionSnapshot() else {
      return
    }
    applyRuntimeProjectionSnapshot(
      runtimeLoaded,
      firstSyncCompletedValue: !runtimeLoaded.projects.isEmpty,
      persistedProjectionSidecars: persistedProjectionSidecars,
      installProjectFeatureOwner: shouldWriteGlobalOutlinerCaches
    )
  }

  func cachedRuntimeProjectionSnapshot() -> OutlineProjectionRuntimeSnapshot? {
    guard let snapshot = appState.cachedOutlinerRuntimeProjectionSnapshot else {
      return nil
    }
    guard let preferredProjectID else {
      return snapshot
    }
    let scopedProjects = snapshot.projects.filter { $0.id == preferredProjectID }
    guard !scopedProjects.isEmpty else { return nil }
    return OutlineProjectionRuntimeSnapshot(
      projects: scopedProjects,
      currentProjectID: preferredProjectID,
      featureSidecarByReminderIdentifier: snapshot.featureSidecarByReminderIdentifier,
      featureSidecarByNodeID: snapshot.featureSidecarByNodeID,
      reminderMetadataByReminderIdentifier: snapshot.reminderMetadataByReminderIdentifier,
      reminderMetadataByNodeID: snapshot.reminderMetadataByNodeID,
      projectReminderListIdentifierByProjectID: snapshot.projectReminderListIdentifierByProjectID,
      projectReminderListExternalIdentifierByProjectID:
        snapshot.projectReminderListExternalIdentifierByProjectID,
      projectColorHexByProjectID: snapshot.projectColorHexByProjectID,
      reminderModifiedAtByReminderExternalIdentifier:
        snapshot.reminderModifiedAtByReminderExternalIdentifier,
      workspaceStructureRecord: snapshot.workspaceStructureRecord,
      projectTaskOrderByReminderListExternalIdentifier:
        snapshot.projectTaskOrderByReminderListExternalIdentifier,
      projectRootStructureByReminderListExternalIdentifier:
        snapshot.projectRootStructureByReminderListExternalIdentifier,
      projectFeatureSidecarByProjectID: snapshot.projectFeatureSidecarByProjectID,
      projectFeatureSidecarByReminderListExternalIdentifier:
        snapshot.projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarByReminderExternalIdentifier:
        snapshot.taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStateByReminderExternalIdentifier:
        snapshot.taskSourceRuntimeStateByReminderExternalIdentifier,
      projectionEngine: snapshot.projectionEngine
    )
  }
  func currentSessionSnapshot() -> OutlinerSessionSnapshot {
    let sidecarPayload = currentProjectionSidecarPayload()
    return OutlinerSessionSnapshot(
      projects: syncedProjects,
      currentProjectID: currentProjectID,
      reminderLinks: sidecarReminderLinks(),
      featureSidecarByReminderIdentifier: sidecarMetadataByReminderIdentifier,
      featureSidecarByNodeID: sidecarMetadataByNodeID,
      reminderMetadataByReminderIdentifier: reminderMetadataByReminderIdentifier,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      workspaceStructureRecord: sidecarPayload.workspaceStructureRecord,
      projectTaskOrderByReminderListExternalIdentifier:
        sidecarPayload.projectTaskOrderByReminderListExternalIdentifier,
      projectRootStructureByReminderListExternalIdentifier:
        sidecarPayload.projectRootStructureByReminderListExternalIdentifier,
      projectFeatureSidecarByReminderListExternalIdentifier:
        sidecarPayload.projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarByReminderExternalIdentifier:
        sidecarPayload.taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStateByReminderExternalIdentifier:
        taskSourceRuntimeStateByReminderExternalIdentifier,
      firstSyncCompleted: firstSyncCompleted
    )
  }
  func updateOutlineSessionCaches(includeIntegratedSnapshot: Bool) {
    let sessionSnapshot = currentSessionSnapshot()
    let sidecarPayload = ReminderProjectionSidecarPayload(
      workspaceStructureRecord: sessionSnapshot.workspaceStructureRecord,
      projectConnectionSidecarByReminderListExternalIdentifier:
        appState.resolvedRuntimeProjectionProjectConnections(),
      projectTaskOrderByReminderListExternalIdentifier:
        sessionSnapshot.projectTaskOrderByReminderListExternalIdentifier,
      projectRootStructureByReminderListExternalIdentifier:
        sessionSnapshot.projectRootStructureByReminderListExternalIdentifier,
      projectFeatureSidecarByReminderListExternalIdentifier:
        sessionSnapshot.projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarByReminderExternalIdentifier:
        sessionSnapshot.taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStateByReminderExternalIdentifier: [:]
    )
    persistProjectionSidecarPayloadIfAvailable(sidecarPayload)
    guard shouldWriteGlobalOutlinerCaches else { return }
    let mergedSessionSnapshot = sessionSnapshot.mergedForAppCache(
      existing: appState.cachedOutlinerSessionSnapshot,
      preferredProjectID: preferredProjectID
    )
    appState.installCachedOutlinerSessionSnapshot(mergedSessionSnapshot)
    let runtimeProjectionSnapshot = currentRuntimeProjectionSnapshot().mergedForAppCache(
      existing: appState.cachedOutlinerRuntimeProjectionSnapshot,
      preferredProjectID: preferredProjectID
    )
    appState.installCachedRuntimeProjectionSnapshot(runtimeProjectionSnapshot)
  }

  func projectionSidecarStore() -> ReminderProjectionSidecarStore? {
    appState.runtimeProjectionSidecarStore()
  }

  func persistProjectionSidecarPayloadIfAvailable(_ payload: ReminderProjectionSidecarPayload) {
    appState.persistRuntimeProjectionSidecarPayload(payload)
  }

  func currentProjectionSidecarPayload() -> ReminderProjectionSidecarPayload {
    let existing = appState.resolvedRuntimeProjectionSidecarPayload()
    let visibleProjectMappings = visibleReminderListExternalIdentifiersByProjectID()
    var workspaceStructureRecord = existing.workspaceStructureRecord
    var projectTaskOrders = existing.projectTaskOrderByReminderListExternalIdentifier
    var projectRootStructures = existing.projectRootStructureByReminderListExternalIdentifier
    var projectFeatureSidecars = existing.projectFeatureSidecarByReminderListExternalIdentifier
    var taskFeatureSidecars = existing.taskFeatureSidecarByReminderExternalIdentifier

    if preferredProjectID == nil {
      let orderedReminderListExternalIdentifiers = syncedProjects.compactMap { project in
        visibleProjectMappings[project.id]
      }
      if !orderedReminderListExternalIdentifiers.isEmpty {
        workspaceStructureRecord = ReminderWorkspaceStructureMutationService.record(
          orderedReminderListExternalIdentifiers: orderedReminderListExternalIdentifiers,
          existing: existing.workspaceStructureRecord
        )
      }
    }

    for project in syncedProjects {
      guard let reminderListExternalIdentifier = visibleProjectMappings[project.id] else { continue }
      let orderedTopLevelReminderExternalIdentifiers: [String] = project.document.rootNodes.compactMap {
        node -> String? in
        guard node.type.isTask else { return nil }
        return normalizedNonEmptyString(node.reminderExternalIdentifier)
      }
      projectTaskOrders[reminderListExternalIdentifier] =
        ReminderProjectTaskOrderMutationService.record(
          reminderListExternalIdentifier: reminderListExternalIdentifier,
          orderedTopLevelReminderExternalIdentifiers: orderedTopLevelReminderExternalIdentifiers,
          existing: projectTaskOrders[reminderListExternalIdentifier]
        )
      projectRootStructures[reminderListExternalIdentifier] =
        ReminderProjectRootStructureMutationService.record(
          reminderListExternalIdentifier: reminderListExternalIdentifier,
          rootNodes: ReminderProjectRootStructureCodec.rootNodes(from: project.document.rootNodes),
          existing: projectRootStructures[reminderListExternalIdentifier]
        )

      if let reminderListExternalIdentifier = visibleProjectMappings[project.id],
         let projectFeatureRecord = existing.projectFeatureSidecarByReminderListExternalIdentifier[
           reminderListExternalIdentifier]
         ?? appState.cachedOutlinerRuntimeProjectionSnapshot?
           .projectFeatureSidecarByProjectID[project.id]
      {
        projectFeatureSidecars[reminderListExternalIdentifier] =
          ReminderProjectFeatureMutationService.projectFeatureRecord(
            reminderListExternalIdentifier: reminderListExternalIdentifier,
            projectNoteMarkdown: projectFeatureRecord.projectNoteMarkdown,
            localStartDate: projectFeatureRecord.localStartDate,
            localDeadline: projectFeatureRecord.localDeadline,
            progressStageRaw: projectFeatureRecord.progressStageRaw,
            boardOrder: projectFeatureRecord.boardOrder,
            existing: projectFeatureSidecars[reminderListExternalIdentifier]
          )
      }
    }

    taskFeatureSidecars.merge(
      taskFeatureSidecarByReminderExternalIdentifier,
      uniquingKeysWith: { _, rhs in rhs }
    )

    projectFeatureSidecars = projectFeatureSidecars.filter { $0.value.hasMeaningfulContent }
    taskFeatureSidecars = taskFeatureSidecars.filter { $0.value.hasMeaningfulContent }

    return ReminderProjectionSidecarPayload(
      workspaceStructureRecord: workspaceStructureRecord,
      projectConnectionSidecarByReminderListExternalIdentifier:
        existing.projectConnectionSidecarByReminderListExternalIdentifier,
      projectTaskOrderByReminderListExternalIdentifier: projectTaskOrders,
      projectRootStructureByReminderListExternalIdentifier: projectRootStructures,
      projectFeatureSidecarByReminderListExternalIdentifier: projectFeatureSidecars,
      taskFeatureSidecarByReminderExternalIdentifier: taskFeatureSidecars,
      taskSourceRuntimeStateByReminderExternalIdentifier: [:]
    )
  }

  func currentRuntimeProjectionSnapshot() -> OutlineProjectionRuntimeSnapshot {
    let sidecarPayload = currentProjectionSidecarPayload()
    let existingRuntimeSnapshot = appState.cachedOutlinerRuntimeProjectionSnapshot
    let existingProjectFeatureSidecars = existingRuntimeSnapshot?.projectFeatureSidecarByProjectID ?? [:]
    let existingReminderListIdentifiers =
      existingRuntimeSnapshot?.projectReminderListIdentifierByProjectID ?? [:]
    let existingReminderListExternalIdentifiers =
      existingRuntimeSnapshot?.projectReminderListExternalIdentifierByProjectID ?? [:]
    let existingProjectColorHexByProjectID = existingRuntimeSnapshot?.projectColorHexByProjectID ?? [:]
    let existingReminderModifiedAtByReminderExternalIdentifier =
      existingRuntimeSnapshot?.reminderModifiedAtByReminderExternalIdentifier ?? [:]

    var projectFeatureSidecarByProjectID: [UUID: ReminderProjectFeatureSidecarRecord] = [:]
    var projectReminderListIdentifierByProjectID: [UUID: String] = [:]
    var projectReminderListExternalIdentifierByProjectID: [UUID: String] = [:]
    var projectColorHexByProjectID: [UUID: String] = [:]
    var reminderModifiedAtByReminderExternalIdentifier: [String: Date] = [:]

    for project in syncedProjects {
      if let reminderListIdentifier =
        existingReminderListIdentifiers[project.id]
        ?? appState.cachedOutlinerRuntimeProjectionSnapshot?
          .projectReminderListIdentifierByProjectID[project.id]
      {
        projectReminderListIdentifierByProjectID[project.id] = reminderListIdentifier
      }

      if let reminderListExternalIdentifier = resolvedReminderListExternalIdentifier(for: project.id),
         let featureSidecar = sidecarPayload.projectFeatureSidecarByReminderListExternalIdentifier[
           reminderListExternalIdentifier]
      {
        projectReminderListExternalIdentifierByProjectID[project.id] = reminderListExternalIdentifier
        projectFeatureSidecarByProjectID[project.id] = featureSidecar
      } else if let existing = existingProjectFeatureSidecars[project.id] {
        projectFeatureSidecarByProjectID[project.id] = existing
        if let reminderListExternalIdentifier = existingReminderListExternalIdentifiers[project.id] {
          projectReminderListExternalIdentifierByProjectID[project.id] = reminderListExternalIdentifier
        }
      } else if let reminderListExternalIdentifier = existingReminderListExternalIdentifiers[project.id] {
        projectReminderListExternalIdentifierByProjectID[project.id] = reminderListExternalIdentifier
      }

      if let colorHex =
        existingProjectColorHexByProjectID[project.id]
        ?? appState.cachedOutlinerRuntimeProjectionSnapshot?.projectColorHexByProjectID[project.id]
      {
        projectColorHexByProjectID[project.id] = colorHex
      }

      for entry in project.document.flatten() where entry.node.type.isTask {
        guard let reminderExternalIdentifier = normalizedNonEmptyString(
          entry.node.reminderExternalIdentifier
        ),
        let modifiedAt = existingReminderModifiedAtByReminderExternalIdentifier[
          reminderExternalIdentifier]
        else {
          continue
        }
        reminderModifiedAtByReminderExternalIdentifier[reminderExternalIdentifier] = modifiedAt
      }
    }

    return OutlineProjectionRuntimeSnapshot(
      projects: syncedProjects,
      currentProjectID: syncedProjects.contains(where: { $0.id == currentProjectID })
        ? currentProjectID
        : (syncedProjects.first?.id ?? currentProjectID),
      featureSidecarByReminderIdentifier: sidecarMetadataByReminderIdentifier,
      featureSidecarByNodeID: sidecarMetadataByNodeID,
      reminderMetadataByReminderIdentifier: reminderMetadataByReminderIdentifier,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      projectReminderListIdentifierByProjectID: projectReminderListIdentifierByProjectID,
      projectReminderListExternalIdentifierByProjectID:
        projectReminderListExternalIdentifierByProjectID,
      projectColorHexByProjectID: projectColorHexByProjectID,
      reminderModifiedAtByReminderExternalIdentifier: reminderModifiedAtByReminderExternalIdentifier,
      workspaceStructureRecord: sidecarPayload.workspaceStructureRecord,
      projectTaskOrderByReminderListExternalIdentifier:
        sidecarPayload.projectTaskOrderByReminderListExternalIdentifier,
      projectRootStructureByReminderListExternalIdentifier:
        sidecarPayload.projectRootStructureByReminderListExternalIdentifier,
      projectFeatureSidecarByProjectID: projectFeatureSidecarByProjectID,
      projectFeatureSidecarByReminderListExternalIdentifier:
        sidecarPayload.projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarByReminderExternalIdentifier:
        sidecarPayload.taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStateByReminderExternalIdentifier:
        taskSourceRuntimeStateByReminderExternalIdentifier,
      projectionEngine: .combined
    )
  }

  func applyRuntimeProjectionSnapshot(
    _ snapshot: OutlineProjectionRuntimeSnapshot,
    firstSyncCompletedValue: Bool,
    persistedProjectionSidecars: ReminderProjectionSidecarPayload,
    installProjectFeatureOwner: Bool = true,
    persistProjectOwner: Bool = true
  ) {
    let nextProjects = snapshot.projects
    let resolvedCurrentProjectID =
      nextProjects.contains(where: { $0.id == currentProjectID }) ? currentProjectID
      : nextProjects.contains(where: { $0.id == snapshot.currentProjectID }) ? snapshot.currentProjectID
      : nextProjects.first?.id ?? preferredProjectID ?? currentProjectID

    replaceProjectedProjects(nextProjects, persistToAppState: persistProjectOwner)
    currentProjectID = resolvedCurrentProjectID
    installCurrentDocumentTreeIndex(
      nextProjects.first(where: { $0.id == resolvedCurrentProjectID })?.document
        ?? nextProjects.first?.document
        ?? OutlineDocument(rootNodes: [])
    )
    integratedTaskStatesByContentID = [:]
    firstSyncCompleted = firstSyncCompletedValue
    if installProjectFeatureOwner {
      replaceSidecarMetadataByReminderIdentifier(snapshot.featureSidecarByReminderIdentifier)
      replaceSidecarMetadataByNodeID(snapshot.featureSidecarByNodeID)
      replaceReminderMetadataByReminderIdentifier(snapshot.reminderMetadataByReminderIdentifier)
      replaceReminderMetadataByNodeID(snapshot.reminderMetadataByNodeID)
    }
    replaceTaskFeatureSidecarByReminderExternalIdentifier(
      snapshot.taskFeatureSidecarByReminderExternalIdentifier.isEmpty
      ? persistedProjectionSidecars.taskFeatureSidecarByReminderExternalIdentifier
      : snapshot.taskFeatureSidecarByReminderExternalIdentifier
    )
    replaceTaskSourceRuntimeStateByReminderExternalIdentifier(
      snapshot.taskSourceRuntimeStateByReminderExternalIdentifier
    )
    refreshCanonicalInstanceCounts(for: syncedProjects)
    synchronizeMirrorAuxiliaryState(in: syncedProjects)
  }

  func reminderLinksByContentID(from snapshot: OutlineProjectionRuntimeSnapshot) -> [UUID: String] {
    var links: [UUID: String] = [:]
    for project in snapshot.projects {
      for entry in project.document.flatten() where entry.node.type.isTask {
        if let reminderIdentifier = normalizedNonEmptyString(entry.node.reminderIdentifier) {
          links[entry.node.canonicalID] = reminderIdentifier
        }
      }
    }
    return links
  }

  func visibleReminderListExternalIdentifiersByProjectID() -> [UUID: String] {
    syncedProjects.reduce(into: [:]) { partialResult, project in
      if let reminderListExternalIdentifier = normalizedNonEmptyString(
        appState.cachedOutlinerRuntimeProjectionSnapshot?
          .projectReminderListExternalIdentifierByProjectID[project.id]
      ) {
        partialResult[project.id] = reminderListExternalIdentifier
      }
    }
  }

  func resolvedReminderListExternalIdentifier(for projectID: UUID) -> String? {
    normalizedNonEmptyString(
      appState.cachedOutlinerRuntimeProjectionSnapshot?
        .projectReminderListExternalIdentifierByProjectID[projectID]
    )
  }

  func derivedMetadataEntries(
    from taskStatesByContentID: [UUID: OutlinerTaskSessionOverlayState],
    projects: [OutlinerProject]
  ) -> (
    featureSidecarByReminderIdentifier: [String: OutlinerTaskSidecarMetadata],
    featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata],
    reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot],
    reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot]
  ) {
    var featureSidecarByReminderIdentifier: [String: OutlinerTaskSidecarMetadata] = [:]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata] = [:]
    var reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot] = [:]
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot] = [:]
    _ = taskStatesByContentID
    _ = projects

    return (
      featureSidecarByReminderIdentifier,
      featureSidecarByNodeID,
      reminderMetadataByReminderIdentifier,
      reminderMetadataByNodeID
    )
  }
  func migratedNodeFeatureSidecarEntries(
    _ loadedNodeMetadataEntries: [UUID: OutlinerTaskSidecarMetadata],
    featureSidecarEntries: [String: OutlinerTaskSidecarMetadata],
    reminderLinks: [UUID: String],
    projects: [OutlinerProject]
  ) -> [UUID: OutlinerTaskSidecarMetadata] {
    guard loadedNodeMetadataEntries.isEmpty else {
      var migrated: [UUID: OutlinerTaskSidecarMetadata] = [:]
      for (persistedID, metadata) in loadedNodeMetadataEntries {
        guard let resolvedNodeID = restoredNodeID(forPersistedID: persistedID, in: projects) else { continue }
        migrated[resolvedNodeID] = metadata
      }
      return migrated
    }

    var migrated: [UUID: OutlinerTaskSidecarMetadata] = [:]
    for (persistedID, reminderIdentifier) in reminderLinks {
      guard let nodeID = restoredNodeID(forPersistedID: persistedID, in: projects) else { continue }
      guard let metadata = featureSidecarEntries[reminderIdentifier] else { continue }
      migrated[nodeID] = metadata
    }
    return migrated
  }
  func migratedNodeReminderMetadataEntries(
    _ loadedNodeMetadataEntries: [UUID: ReminderMetadataSnapshot],
    reminderMetadataEntries: [String: ReminderMetadataSnapshot],
    reminderLinks: [UUID: String],
    projects: [OutlinerProject]
  ) -> [UUID: ReminderMetadataSnapshot] {
    guard loadedNodeMetadataEntries.isEmpty else {
      var migrated: [UUID: ReminderMetadataSnapshot] = [:]
      for (persistedID, metadata) in loadedNodeMetadataEntries {
        guard let resolvedNodeID = restoredNodeID(forPersistedID: persistedID, in: projects) else { continue }
        migrated[resolvedNodeID] = metadata
      }
      return migrated
    }

    var migrated: [UUID: ReminderMetadataSnapshot] = [:]
    for (persistedID, reminderIdentifier) in reminderLinks {
      guard let nodeID = restoredNodeID(forPersistedID: persistedID, in: projects) else { continue }
      guard let metadata = reminderMetadataEntries[reminderIdentifier] else { continue }
      migrated[nodeID] = metadata
    }
    return migrated
  }
  func restoredNodeID(
    forPersistedID persistedID: UUID,
    in projects: [OutlinerProject]
  ) -> UUID? {
    if resolvedNode(id: persistedID, in: projects) != nil {
      return persistedID
    }

    for project in projects {
      if let nodeID = project.document.flatten()
        .first(where: { $0.node.canonicalID == persistedID })?.id
      {
        return nodeID
      }
    }
    return nil
  }
  func reminderLinksByContentID(
    from persistedLinks: [UUID: String],
    projects: [OutlinerProject]
  ) -> [UUID: String] {
    var converted: [UUID: String] = [:]
    for (persistedID, reminderIdentifier) in persistedLinks {
      if let node = resolvedNode(id: persistedID, in: projects) {
        converted[node.canonicalID] = reminderIdentifier
        continue
      }

      let hasCanonicalMatch = projects.contains { project in
        project.document.flatten().contains { $0.node.canonicalID == persistedID }
      }
      if hasCanonicalMatch {
        converted[persistedID] = reminderIdentifier
      }
    }
    return converted
  }
  func projectScopedTaskStates(
    for project: OutlinerProject,
    in taskStatesByContentID: [UUID: OutlinerTaskSessionOverlayState]
  ) -> [UUID: OutlinerTaskSessionOverlayState] {
    let projectContentIDs = Set(project.document.flatten().map(\.node.canonicalID))
    if projectContentIDs.isEmpty {
      return [:]
    }
    return taskStatesByContentID.filter { projectContentIDs.contains($0.key) }
  }
  func sidecarReminderLinks() -> [UUID: String] {
    let linkedByContentID = resolvedReminderLinksByContentID()
    guard !linkedByContentID.isEmpty else { return [:] }

    var reminderLinks: [UUID: String] = [:]
    var chosenNodeIDsByContentID: [UUID: UUID] = [:]
    for project in syncedProjects {
      for entry in project.document.flatten() {
        chosenNodeIDsByContentID[entry.node.canonicalID] = chosenNodeIDsByContentID[entry.node.canonicalID] ?? entry.id
      }
    }

    for (contentID, reminderIdentifier) in linkedByContentID {
      guard let nodeID = chosenNodeIDsByContentID[contentID] else { continue }
      reminderLinks[nodeID] = reminderIdentifier
    }
    return reminderLinks
  }

  func resolvedReminderLinksByContentID() -> [UUID: String] {
    reminderLinksByContentID(from: currentRuntimeProjectionSnapshot())
  }

  /// Keep local session/runtime caches in sync after direct writes without going
  /// through canonical document persistence or full source reloads.
  func syncEditorSessionState(triggerAutoPush: Bool = true) {
    guard !isPreviewMode else { return }
    guard hasRestoredPersistedState, !isRestoringPersistedState else { return }
    updateOutlineSessionCaches(includeIntegratedSnapshot: true)
    if triggerAutoPush {
      scheduleAutoPush()
    }
  }
  func persistReminderMetadata(
    _ metadata: ReminderMetadataSnapshot,
    for nodeID: UUID,
    reminderIdentifier: String? = nil,
    triggerAutoPush: Bool = true,
    persistState: Bool = true,
    queueReminderPush: Bool = true
  ) {
    guard let contentID = resolvedContentID(for: nodeID) else { return }
    var normalized = metadata
    normalized.priority = max(0, min(9, normalized.priority))
    if queueReminderPush {
      enqueueReminderPushContentIDs([contentID])
    }

    let peerNodeIDs = canonicalPeerNodeIDs(for: nodeID, in: syncedProjects)

    if normalized.hasMeaningfulContent {
      for peerNodeID in peerNodeIDs {
        replaceReminderMetadataByNodeID(for: peerNodeID, metadata: normalized)
      }
    } else {
      for peerNodeID in peerNodeIDs {
        removeReminderMetadataByNodeID(for: peerNodeID)
      }
    }

    if let reminderIdentifier {
      if normalized.hasMeaningfulContent {
        replaceReminderMetadataByReminderIdentifier(for: reminderIdentifier, metadata: normalized)
      } else {
        removeReminderMetadataByReminderIdentifier(for: reminderIdentifier)
      }
    }

    if persistState {
      syncEditorSessionState(triggerAutoPush: triggerAutoPush)
    }
  }
  func persistFeatureSidecarMetadata(
    _ metadata: OutlinerTaskSidecarMetadata,
    for nodeID: UUID,
    reminderIdentifier: String? = nil,
    triggerAutoPush: Bool = true,
    persistState: Bool = true
  ) {
    guard let contentID = resolvedContentID(for: nodeID) else { return }
    var normalized = metadata
    normalized.requiredWorkDays = max(0, normalized.requiredWorkDays)
    enqueueReminderPushContentIDs([contentID])

    let peerNodeIDs = canonicalPeerNodeIDs(for: nodeID, in: syncedProjects)
    if normalized.hasMeaningfulContent {
      for peerNodeID in peerNodeIDs {
        replaceSidecarMetadataByNodeID(for: peerNodeID, with: normalized)
      }
    } else {
      for peerNodeID in peerNodeIDs {
        removeSidecarMetadataByNodeID(for: peerNodeID)
      }
    }

    if let reminderIdentifier {
      if normalized.hasMeaningfulContent {
        replaceSidecarMetadataByReminderIdentifier(with: reminderIdentifier, metadata: normalized)
      } else {
        removeSidecarMetadataByReminderIdentifier(for: reminderIdentifier)
      }
    }

    let reminderExternalIdentifier =
      normalizedNonEmptyString(
        resolvedTaskState(
          for: contentID,
          defaultTitle: resolvedNode(id: nodeID, in: syncedProjects)?.text ?? ""
        ).reminderExternalIdentifier
      )
      ?? normalizedNonEmptyString(resolvedNode(id: nodeID, in: syncedProjects)?.reminderExternalIdentifier)
    if let reminderExternalIdentifier {
      replaceTaskFeatureSidecarByReminderExternalIdentifier(
        for: reminderExternalIdentifier,
        AppFeatureMutationService.taskFeatureRecord(
          reminderExternalIdentifier: reminderExternalIdentifier,
          featureSidecar: normalized,
          existing: taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier]
        )
      )
    }

    if persistState {
      syncEditorSessionState(triggerAutoPush: triggerAutoPush)
    }
  }
  func removeReminderMetadata(
    for reminderIdentifier: String,
    nodeID: UUID? = nil,
    triggerAutoPush: Bool = true
  ) {
    removeReminderMetadataByReminderIdentifier(for: reminderIdentifier)
    if let nodeID {
      if let contentID = resolvedContentID(for: nodeID) {
        let reminderExternalIdentifier = resolvedTaskState(
          for: contentID,
          defaultTitle: resolvedNode(id: nodeID, in: syncedProjects)?.text ?? ""
        ).reminderExternalIdentifier
        appState.clearRuntimeProjectionReminderIdentity(
          for: contentID,
          reminderIdentifier: reminderIdentifier,
          reminderExternalIdentifier: reminderExternalIdentifier
        )
        clearTaskSessionOverlay(for: contentID)
        enqueueReminderPushContentIDs([contentID])
      }
      for peerNodeID in canonicalPeerNodeIDs(for: nodeID, in: syncedProjects) {
        removeReminderMetadataByNodeID(for: peerNodeID)
      }
    }
    syncEditorSessionState(triggerAutoPush: triggerAutoPush)
  }
  func updateReminderMetadata(
    for nodeID: UUID,
    saveDirectly: Bool = true,
    mutate: (inout ReminderMetadataSnapshot) -> Void
  ) {
    var metadata = resolvedReminderMetadata(for: nodeID)
    mutate(&metadata)
    let reminderIdentifier = projection(for: nodeID)?.reminderIdentifier
    if saveDirectly {
      commitReminderMetadataDirectSave(
        for: nodeID,
        overrideMetadata: metadata,
        reminderIdentifierOverride: reminderIdentifier
      )
    } else {
      stageReminderMetadataForPendingCommit(
        metadata,
        for: nodeID,
        reminderIdentifier: reminderIdentifier
      )
    }
  }
  func normalizedNonEmptyString(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private func replaceSidecarMetadataByReminderIdentifier(
    _ value: [String: OutlinerTaskSidecarMetadata]
  ) {
    appState.replaceRuntimeProjectionSidecarMetadataByReminderIdentifier(value)
  }

  private func replaceSidecarMetadataByReminderIdentifier(
    with reminderIdentifier: String,
    metadata: OutlinerTaskSidecarMetadata
  ) {
    appState.replaceRuntimeProjectionSidecarMetadataByReminderIdentifier(
      for: reminderIdentifier,
      metadata: metadata
    )
  }

  private func removeSidecarMetadataByReminderIdentifier(for reminderIdentifier: String) {
    appState.removeRuntimeProjectionSidecarMetadataByReminderIdentifier(for: reminderIdentifier)
  }

  func replaceSidecarMetadataByNodeID(_ value: [UUID: OutlinerTaskSidecarMetadata]) {
    appState.replaceRuntimeProjectionSidecarMetadataByNodeID(value)
  }

  func replaceSidecarMetadataByNodeID(for nodeID: UUID, with metadata: OutlinerTaskSidecarMetadata) {
    appState.replaceRuntimeProjectionSidecarMetadataByNodeID(for: nodeID, metadata: metadata)
  }

  func removeSidecarMetadataByNodeID(for nodeID: UUID) {
    appState.removeRuntimeProjectionSidecarMetadataByNodeID(for: nodeID)
  }

  func replaceReminderMetadataByReminderIdentifier(_ value: [String: ReminderMetadataSnapshot]) {
    appState.replaceRuntimeProjectionReminderMetadataByReminderIdentifier(value)
  }

  func replaceReminderMetadataByReminderIdentifier(
    for reminderIdentifier: String,
    metadata: ReminderMetadataSnapshot
  ) {
    appState.replaceRuntimeProjectionReminderMetadataByReminderIdentifier(
      for: reminderIdentifier,
      metadata: metadata
    )
  }

  func removeReminderMetadataByReminderIdentifier(for reminderIdentifier: String) {
    appState.removeRuntimeProjectionReminderMetadataByReminderIdentifier(for: reminderIdentifier)
  }

  func replaceReminderMetadataByNodeID(_ value: [UUID: ReminderMetadataSnapshot]) {
    appState.replaceRuntimeProjectionReminderMetadataByNodeID(value)
  }

  func replaceReminderMetadataByNodeID(for nodeID: UUID, metadata: ReminderMetadataSnapshot) {
    appState.replaceRuntimeProjectionReminderMetadataByNodeID(
      for: nodeID,
      metadata: metadata
    )
  }

  func removeReminderMetadataByNodeID(for nodeID: UUID) {
    appState.removeRuntimeProjectionReminderMetadataByNodeID(for: nodeID)
  }

  func replaceTaskFeatureSidecarByReminderExternalIdentifier(
    _ value: [String: ReminderTaskFeatureSidecarRecord]
  ) {
    appState.replaceRuntimeProjectionTaskFeatureSidecars(value)
  }

  func replaceTaskFeatureSidecarByReminderExternalIdentifier(
    for reminderExternalIdentifier: String,
    _ metadata: ReminderTaskFeatureSidecarRecord
  ) {
    appState.replaceRuntimeProjectionTaskFeatureSidecar(
      for: reminderExternalIdentifier,
      metadata: metadata
    )
  }

  func removeTaskFeatureSidecarByReminderExternalIdentifier(for reminderExternalIdentifier: String) {
    appState.removeRuntimeProjectionTaskFeatureSidecar(for: reminderExternalIdentifier)
  }

  func replaceTaskSourceRuntimeStateByReminderExternalIdentifier(
    _ value: [String: ReminderTaskSourceRuntimeState]
  ) {
    appState.replaceRuntimeProjectionTaskSourceRuntimeStates(value)
  }

  func replaceTaskSourceRuntimeStateByReminderExternalIdentifier(
    for reminderExternalIdentifier: String,
    runtimeState: ReminderTaskSourceRuntimeState
  ) {
    appState.replaceRuntimeProjectionTaskSourceRuntimeState(
      for: reminderExternalIdentifier,
      runtimeState: runtimeState
    )
  }

  func removeTaskSourceRuntimeStateByReminderExternalIdentifier(
    for reminderExternalIdentifier: String
  ) {
    appState.removeRuntimeProjectionTaskSourceRuntimeState(
      for: reminderExternalIdentifier
    )
  }

  func noteSourceRuntimeState(
    for reminderExternalIdentifier: String?
  ) -> ReminderTaskSourceRuntimeState? {
    guard let reminderExternalIdentifier = normalizedNonEmptyString(reminderExternalIdentifier) else {
      return nil
    }
    return taskSourceRuntimeStateByReminderExternalIdentifier[reminderExternalIdentifier]
  }

  func mutateTaskSourceRuntimeState(
    for reminderExternalIdentifier: String?,
    mutate: (inout ReminderTaskSourceRuntimeState) -> Void
  ) {
    guard let reminderExternalIdentifier = normalizedNonEmptyString(reminderExternalIdentifier) else {
      return
    }

    var runtimeState =
      taskSourceRuntimeStateByReminderExternalIdentifier[reminderExternalIdentifier]
      ?? ReminderTaskSourceRuntimeState(
        reminderExternalIdentifier: reminderExternalIdentifier,
        lastImportedNormalizedNoteHash: nil,
        lastExportedNormalizedNoteHash: nil,
        lastObservedReminderModifiedAt: nil,
        lastObservedReminderRawPayloadRaw: nil,
        noteConflictStateRaw: nil
      )
    mutate(&runtimeState)
    replaceTaskSourceRuntimeStateByReminderExternalIdentifier(
      for: reminderExternalIdentifier,
      runtimeState: runtimeState
    )
  }

  func reminderNoteConflictState(
    for reminderExternalIdentifier: String?
  ) -> ReminderNoteSourceConflictState? {
    ReminderNoteSourceConflictStateCodec.decode(
      noteSourceRuntimeState(for: reminderExternalIdentifier)?.noteConflictStateRaw
    )
  }

  func updateTaskSourceRuntimeState(
    for snapshot: OutlinerLiveReminderSnapshot,
    exportedHash: String? = nil
  ) {
    mutateTaskSourceRuntimeState(for: snapshot.reminderExternalIdentifier) { runtimeState in
      runtimeState.lastImportedNormalizedNoteHash = ReminderNoteSourceMutationService.hash(
        for: snapshot.parsedBody
      )
      if let exportedHash {
        runtimeState.lastExportedNormalizedNoteHash = exportedHash
      }
      runtimeState.lastObservedReminderModifiedAt = snapshot.lastModifiedAt
      runtimeState.lastObservedReminderRawPayloadRaw =
        normalizedNonEmptyString(snapshot.rawPreservationPayloadRaw)
    }
  }

  func recordObservedNoteSourceImport(
    reminderExternalIdentifier: String?,
    remoteObservation: ReminderNoteSourceObservation,
    rawPreservationPayloadRaw: String? = nil
  ) {
    mutateTaskSourceRuntimeState(for: reminderExternalIdentifier) { runtimeState in
      runtimeState.lastImportedNormalizedNoteHash = remoteObservation.normalizedNoteHash
      runtimeState.lastObservedReminderModifiedAt = remoteObservation.remoteModifiedAt
      runtimeState.lastObservedReminderRawPayloadRaw =
        normalizedNonEmptyString(rawPreservationPayloadRaw)
      runtimeState.noteConflictStateRaw = nil
    }
  }

  func persistReminderNoteConflictState(
    _ conflictState: ReminderNoteSourceConflictState?,
    for projection: OutlinerReminderProjection,
    remote: OutlinerRemoteReminderImport? = nil
  ) {
    let reminderExternalIdentifier =
      normalizedNonEmptyString(remote?.reminderExternalIdentifier)
      ?? normalizedNonEmptyString(projection.reminderExternalIdentifier)
      ?? normalizedNonEmptyString(
        resolvedTaskState(for: projection.contentID, defaultTitle: projection.title)
          .reminderExternalIdentifier
      )
    mutateTaskSourceRuntimeState(for: reminderExternalIdentifier) { runtimeState in
      runtimeState.noteConflictStateRaw = ReminderNoteSourceConflictStateCodec.encode(conflictState)
      if let remoteModifiedAt = remote?.lastModifiedAt {
        runtimeState.lastObservedReminderModifiedAt = remoteModifiedAt
      }
      if let rawPreservationPayloadRaw = remote?.rawPreservationPayloadRaw {
        runtimeState.lastObservedReminderRawPayloadRaw =
          normalizedNonEmptyString(rawPreservationPayloadRaw)
      }
    }
    if let remote {
      liveSync.bindImportedReminder(remote, to: projection)
      appState.installRuntimeProjectionReminderIdentity(
        for: projection.contentID,
        reminderIdentifier: remote.reminderIdentifier,
        reminderExternalIdentifier: remote.reminderExternalIdentifier,
        modifiedAt: remote.lastModifiedAt
      )
    }
    mutateTaskSessionOverlay(for: projection.contentID) { overlay in
      overlay.reminderNoteConflictExcerpt = conflictState?.excerpt
    }

    if conflictState == nil {
      reminderConflictResolutionContentIDs.remove(projection.contentID)
      expandedReminderConflictDiffContentIDs.remove(projection.contentID)
    }
  }

  @discardableResult
  func storeObservedRemoteImport(
    _ remote: OutlinerRemoteReminderImport,
    for projection: OutlinerReminderProjection
  ) -> Bool {
    let previousReminderIdentifier = projection.reminderIdentifier
    var didChange = false

    if previousReminderIdentifier != remote.reminderIdentifier {
      didChange = true
    }
    if projection.reminderExternalIdentifier != remote.reminderExternalIdentifier {
      didChange = true
    }
    if projection.reminderOwnerCalendarID != remote.calendarIdentifier {
      didChange = true
    }
    if projection.noteText != remote.parsedBody {
      didChange = true
    }
    if projection.remoteLastModifiedAt != remote.lastModifiedAt {
      didChange = true
    }
    if normalizedNonEmptyString(remote.rawPreservationPayloadRaw) != nil {
      didChange = true
    }

    var metadata = resolvedReminderMetadata(for: projection.nodeID)
    if metadata.dueDate != remote.dueDate || metadata.hasExplicitTime != remote.hasExplicitTime {
      metadata.dueDate = remote.dueDate
      metadata.hasExplicitTime = remote.hasExplicitTime
      didChange = true
    }
    if metadata.recurrence != remote.recurrence {
      metadata.recurrence = remote.recurrence
      didChange = true
    }
    if metadata.priority != remote.priority {
      metadata.priority = remote.priority
      didChange = true
    }

    guard didChange else { return false }

    liveSync.bindImportedReminder(remote, to: projection)
    appState.installRuntimeProjectionReminderIdentity(
      for: projection.contentID,
      reminderIdentifier: remote.reminderIdentifier,
      reminderExternalIdentifier: remote.reminderExternalIdentifier,
      modifiedAt: remote.lastModifiedAt
    )
    clearTaskSessionOverlay(for: projection.contentID)
    let peerNodeIDs = canonicalPeerNodeIDs(for: projection.nodeID, in: syncedProjects)
    if let previousReminderIdentifier, previousReminderIdentifier != remote.reminderIdentifier {
      removeReminderMetadataByReminderIdentifier(for: previousReminderIdentifier)
    }
    if metadata.hasMeaningfulContent {
      for peerNodeID in peerNodeIDs {
        replaceReminderMetadataByNodeID(for: peerNodeID, metadata: metadata)
      }
      replaceReminderMetadataByReminderIdentifier(for: remote.reminderIdentifier, metadata: metadata)
    } else {
      for peerNodeID in peerNodeIDs {
        removeReminderMetadataByNodeID(for: peerNodeID)
      }
      removeReminderMetadataByReminderIdentifier(for: remote.reminderIdentifier)
    }

    return true
  }
  var hasActiveReminderPushEditingFocus: Bool {
    reminderPushEditingBoundary != nil
  }

  var shouldDeferPendingReminderPushForEditingFocus: Bool {
    guard let activeBoundary = reminderPushEditingBoundary else {
      return false
    }
    let deferredBoundary = pendingAutoPushDeferredBoundary ?? activeBoundary
    guard activeBoundary == deferredBoundary else {
      return false
    }
    return !canCommitPendingReminderPushDuringIdle(activeBoundary)
  }

  func rememberPendingReminderPushDeferralAnchorIfNeeded() {
    guard pendingAutoPushDeferredBoundary == nil else { return }
    pendingAutoPushDeferredBoundary = reminderPushEditingBoundary
  }

  func clearPendingReminderPushDeferralAnchor() {
    pendingAutoPushDeferredBoundary = nil
  }

  func beginReminderPushEditing(for nodeID: UUID) {
    let boundary = reminderSubtreeCommitBoundary(for: nodeID)
    guard reminderPushEditingBoundary != boundary else { return }
    reminderPushEditingBoundary = boundary
    synchronizeReminderPushEditingState()
  }

  func endReminderPushEditing(for nodeID: UUID) {
    let endingBoundary = reminderSubtreeCommitBoundary(for: nodeID)
    guard reminderPushEditingBoundary == endingBoundary else { return }
    DispatchQueue.main.async {
      self.reminderPushEditingBoundary = self.reminderSubtreeCommitBoundary(for: self.focusedNodeID)
      self.synchronizeReminderPushEditingState()
    }
  }

  func synchronizeReminderPushEditingState() {
    DispatchQueue.main.async {
      let activeBoundary = self.reminderSubtreeCommitBoundary(for: self.focusedNodeID)
      self.reminderPushEditingBoundary = activeBoundary
      if self.hasActiveReminderPushEditingFocus {
        self.appState.beginEditorSession(
          id: self.outlinerEditingSessionID,
          syncRelevant: true,
          syncKind: self.reminderPushEditingBoundary == .projectTitle ? .title : .subtree,
          contentID: self.reminderPushEditingBoundary?.contentID,
          projectID: self.currentProjectID
        )
      } else {
        self.appState.endEditorSession(id: self.outlinerEditingSessionID)
      }

      self.commitPendingReminderNoteSourceDirectSaveIfNeeded(
        excluding: activeBoundary
      )
    }
  }

  func relatedReminderCommitContentIDs(
    for activeContentID: UUID
  ) -> Set<UUID> {
    let documentTreeIndex = OutlineTreeIndex(document: uiDocument)
    guard let activeTaskNode = documentTreeIndex.taskNode(contentID: activeContentID) else {
      return [activeContentID]
    }

    var relatedContentIDs: Set<UUID> = [activeContentID]
    var currentNodeID = activeTaskNode.id
    while let parentID = documentTreeIndex.parentOf(id: currentNodeID),
          let parentNode = documentTreeIndex.findNode(id: parentID)
    {
      if parentNode.type.isTask {
        relatedContentIDs.insert(parentNode.canonicalID)
      }
      currentNodeID = parentID
    }

    func collectDescendantTaskContentIDs(from nodes: [OutlineNode]) {
      for node in nodes {
        if node.type.isTask {
          relatedContentIDs.insert(node.canonicalID)
        }
        collectDescendantTaskContentIDs(from: node.children)
      }
    }

    collectDescendantTaskContentIDs(from: activeTaskNode.children)
    return relatedContentIDs
  }

  func pendingReminderNoteSourceDirectCommitContentIDs(
    excluding activeBoundary: ReminderSubtreeCommitBoundary?
  ) -> Set<UUID> {
    guard let activeBoundary else {
      return pendingReminderPushContentIDs
    }
    switch activeBoundary {
    case .projectTitle:
      return []
    case let .taskSubtree(contentID):
      return pendingReminderPushContentIDs.subtracting(
        relatedReminderCommitContentIDs(for: contentID)
      )
    }
  }

  func commitPendingReminderNoteSourceDirectSaveIfNeeded(
    excluding activeBoundary: ReminderSubtreeCommitBoundary?
  ) {
    let eligibleContentIDs = pendingReminderNoteSourceDirectCommitContentIDs(
      excluding: activeBoundary
    )
    guard !eligibleContentIDs.isEmpty else { return }
    if isAutoPushing || reminderNoteDirectCommitTask != nil {
      hasPendingDirectReminderNoteCommit = true
      return
    }

    reminderNoteDirectCommitTask = Task { @MainActor in
      await self.pushLocalChanges(
        requestedContentIDs: eligibleContentIDs,
        directCommit: true
      )
      self.reminderNoteDirectCommitTask = nil
      guard self.hasPendingDirectReminderNoteCommit else { return }
      self.hasPendingDirectReminderNoteCommit = false
      self.commitPendingReminderNoteSourceDirectSaveIfNeeded(
        excluding: self.reminderPushEditingBoundary
      )
    }
  }

  func canCommitPendingReminderPushDuringIdle(_ boundary: ReminderSubtreeCommitBoundary) -> Bool {
    guard case let .taskSubtree(contentID) = boundary else { return false }
    guard let lastEditedAt = reminderPushLastEditedAtByContentID[contentID] else { return false }
    return Date().timeIntervalSince(lastEditedAt) >= 1.5
  }
}
