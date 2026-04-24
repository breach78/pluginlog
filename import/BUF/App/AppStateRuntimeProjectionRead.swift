import Foundation
import SwiftData

struct OutlinerRuntimeProjectionTaskSnapshot {
  let reminderIdentifier: String?
  let taskRecord: ProjectIdentityTaskRecord
  let remoteLastModifiedAt: Date?
}

@MainActor
extension AppState {
  func installCachedOutlinerSessionSnapshot(_ snapshot: OutlinerSessionSnapshot) {
    cachedOutlinerSessionSnapshot = snapshot
  }

  func hasCachedRuntimeProjectionSnapshot() -> Bool {
    cachedOutlinerRuntimeProjectionSnapshot != nil
  }

  func resolvedRuntimeProjectionSidecarPayload() -> ReminderProjectionSidecarPayload {
    loadRuntimeProjectionSidecarPayload()
  }

  func resolvedRuntimeProjectionProjectConnections()
    -> [String: ReminderProjectConnectionSidecarRecord]
  {
    resolvedRuntimeProjectionSidecarPayload()
      .projectConnectionSidecarByReminderListExternalIdentifier
  }

  func persistRuntimeProjectionSidecarPayload(_ payload: ReminderProjectionSidecarPayload) {
    saveRuntimeProjectionSidecarPayload(payload)
  }

  func resolvedRuntimeProjectionSnapshot() -> OutlineProjectionRuntimeSnapshot? {
    cachedOutlinerRuntimeProjectionSnapshot
  }

  func resolvedRuntimeProjectionProjects() -> [OutlinerProject] {
    cachedOutlinerRuntimeProjectionSnapshot?.projects ?? [OutlinerProject.sampleProject]
  }

  func resolvedRuntimeProjectionProjectIDs() -> Set<UUID> {
    Set(cachedOutlinerRuntimeProjectionSnapshot?.projects.map(\.id) ?? [])
  }

  func mutateCachedRuntimeProjectionSnapshot(
    _ mutate: (inout OutlineProjectionRuntimeSnapshot) -> Void
  ) {
    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else { return }
    mutate(&snapshot)
    installCachedRuntimeProjectionSnapshot(snapshot)
  }

  func installRuntimeProjectionProjects(_ projects: [OutlinerProject]) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.projects = projects
    }
  }

  func resolvedOutlinerSidecarMetadataByReminderIdentifier() -> [String: OutlinerTaskSidecarMetadata] {
    cachedOutlinerRuntimeProjectionSnapshot?.featureSidecarByReminderIdentifier ?? [:]
  }

  func resolvedOutlinerSidecarMetadataByNodeID() -> [UUID: OutlinerTaskSidecarMetadata] {
    cachedOutlinerRuntimeProjectionSnapshot?.featureSidecarByNodeID ?? [:]
  }

  func resolvedOutlinerReminderMetadataByReminderIdentifier() -> [String: ReminderMetadataSnapshot] {
    cachedOutlinerRuntimeProjectionSnapshot?.reminderMetadataByReminderIdentifier ?? [:]
  }

  func resolvedOutlinerReminderMetadataByNodeID() -> [UUID: ReminderMetadataSnapshot] {
    cachedOutlinerRuntimeProjectionSnapshot?.reminderMetadataByNodeID ?? [:]
  }

  func resolvedTaskFeatureSidecarByReminderExternalIdentifier()
    -> [String: ReminderTaskFeatureSidecarRecord]
  {
    cachedOutlinerRuntimeProjectionSnapshot?.taskFeatureSidecarByReminderExternalIdentifier ?? [:]
  }

  func resolvedTaskSourceRuntimeStateByReminderExternalIdentifier()
    -> [String: ReminderTaskSourceRuntimeState]
  {
    cachedOutlinerRuntimeProjectionSnapshot?.taskSourceRuntimeStateByReminderExternalIdentifier ?? [:]
  }

  func resolvedRuntimeProjectionTaskSnapshot(forTaskID taskID: UUID)
    -> OutlinerRuntimeProjectionTaskSnapshot?
  {
    guard let modelContainer else { return nil }
    let context = ModelContext(modelContainer)
    guard let taskRecord = resolvedTaskRecord(forTaskID: taskID, context: context) else { return nil }
    let reminderIdentifier = cachedOutlinerRuntimeProjectionSnapshot?.taskLocation(for: taskID).flatMap {
      normalizedProjectionValue($0.node.reminderIdentifier)
    }
    let remoteLastModifiedAt = normalizedProjectionValue(taskRecord.reminderExternalIdentifier).flatMap {
      cachedOutlinerRuntimeProjectionSnapshot?.reminderModifiedAtByReminderExternalIdentifier[$0]
    }
    return OutlinerRuntimeProjectionTaskSnapshot(
      reminderIdentifier: reminderIdentifier,
      taskRecord: taskRecord,
      remoteLastModifiedAt: remoteLastModifiedAt
    )
  }

  func installRuntimeProjectionReminderIdentity(
    for taskID: UUID,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?,
    modifiedAt: Date?
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      let normalizedReminderIdentifier = normalizedProjectionValue(reminderIdentifier)
      let normalizedReminderExternalIdentifier = normalizedProjectionValue(reminderExternalIdentifier)
      var previousExternalIdentifiers: Set<String> = []

      for projectIndex in snapshot.projects.indices {
        let matchingNodeIDs = snapshot.projects[projectIndex].document.flatten().compactMap {
          entry -> UUID? in
          guard entry.node.type.isTask, entry.node.canonicalID == taskID else { return nil }
          if let previousExternalIdentifier = normalizedProjectionValue(
            entry.node.reminderExternalIdentifier
          ) {
            previousExternalIdentifiers.insert(previousExternalIdentifier)
          }
          return entry.node.id
        }

        for nodeID in matchingNodeIDs {
          snapshot.projects[projectIndex].document.updateNode(id: nodeID) { node in
            node.reminderIdentifier = normalizedReminderIdentifier
            node.reminderExternalIdentifier = normalizedReminderExternalIdentifier
          }
        }
      }

      for previousExternalIdentifier in previousExternalIdentifiers
      where previousExternalIdentifier != normalizedReminderExternalIdentifier {
        snapshot.reminderModifiedAtByReminderExternalIdentifier.removeValue(
          forKey: previousExternalIdentifier
        )
        let previousTaskFeatureSidecar =
          snapshot.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
            forKey: previousExternalIdentifier
          )
        let previousTaskSourceRuntimeState =
          snapshot.taskSourceRuntimeStateByReminderExternalIdentifier.removeValue(
            forKey: previousExternalIdentifier
          )
        if let normalizedReminderExternalIdentifier {
          if let previousTaskFeatureSidecar,
             snapshot.taskFeatureSidecarByReminderExternalIdentifier[
               normalizedReminderExternalIdentifier
             ] == nil
          {
            snapshot.taskFeatureSidecarByReminderExternalIdentifier[
              normalizedReminderExternalIdentifier
            ] = previousTaskFeatureSidecar
          }
          if let previousTaskSourceRuntimeState,
             snapshot.taskSourceRuntimeStateByReminderExternalIdentifier[
               normalizedReminderExternalIdentifier
             ] == nil
          {
            snapshot.taskSourceRuntimeStateByReminderExternalIdentifier[
              normalizedReminderExternalIdentifier
            ] = previousTaskSourceRuntimeState
          }
        }
      }

      if let normalizedReminderExternalIdentifier {
        if let modifiedAt {
          snapshot.reminderModifiedAtByReminderExternalIdentifier[normalizedReminderExternalIdentifier] =
            modifiedAt
        }
      }
    }
  }

  func clearRuntimeProjectionReminderIdentity(
    for taskID: UUID,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?
  ) {
    installRuntimeProjectionReminderIdentity(
      for: taskID,
      reminderIdentifier: nil,
      reminderExternalIdentifier: nil,
      modifiedAt: nil
    )
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      if let normalizedReminderIdentifier = normalizedProjectionValue(reminderIdentifier) {
        snapshot.reminderMetadataByReminderIdentifier.removeValue(forKey: normalizedReminderIdentifier)
        snapshot.featureSidecarByReminderIdentifier.removeValue(forKey: normalizedReminderIdentifier)
      }
      if let normalizedReminderExternalIdentifier = normalizedProjectionValue(reminderExternalIdentifier) {
        snapshot.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
          forKey: normalizedReminderExternalIdentifier
        )
        snapshot.taskSourceRuntimeStateByReminderExternalIdentifier.removeValue(
          forKey: normalizedReminderExternalIdentifier
        )
      }
    }
  }

  func resolvedWorkspaceProjectDescriptors(context: ModelContext) -> [WorkspaceProjectDescriptor] {
    ReminderRuntimeProjectionReadModelService.workspaceProjectDescriptors(
      runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
      context: context
    )
  }

  func resolvedScopedOutlinerRuntimeProjectionSnapshot(
    for projectID: UUID
  ) -> OutlineProjectionRuntimeSnapshot? {
    guard let runtimeSnapshot = cachedOutlinerRuntimeProjectionSnapshot,
      let project = runtimeSnapshot.projects.first(where: { $0.id == projectID })
    else {
      return nil
    }

    return OutlineProjectionRuntimeSnapshot(
      projects: [project],
      currentProjectID: project.id,
      featureSidecarByReminderIdentifier: runtimeSnapshot.featureSidecarByReminderIdentifier,
      featureSidecarByNodeID: runtimeSnapshot.featureSidecarByNodeID,
      reminderMetadataByReminderIdentifier: runtimeSnapshot.reminderMetadataByReminderIdentifier,
      reminderMetadataByNodeID: runtimeSnapshot.reminderMetadataByNodeID,
      projectReminderListIdentifierByProjectID:
        runtimeSnapshot.projectReminderListIdentifierByProjectID,
      projectReminderListExternalIdentifierByProjectID:
        runtimeSnapshot.projectReminderListExternalIdentifierByProjectID,
      projectColorHexByProjectID: runtimeSnapshot.projectColorHexByProjectID,
      reminderModifiedAtByReminderExternalIdentifier:
        runtimeSnapshot.reminderModifiedAtByReminderExternalIdentifier,
      workspaceStructureRecord: runtimeSnapshot.workspaceStructureRecord,
      projectTaskOrderByReminderListExternalIdentifier:
        runtimeSnapshot.projectTaskOrderByReminderListExternalIdentifier,
      projectFeatureSidecarByProjectID: runtimeSnapshot.projectFeatureSidecarByProjectID,
      projectFeatureSidecarByReminderListExternalIdentifier:
        runtimeSnapshot.projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarByReminderExternalIdentifier:
        runtimeSnapshot.taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStateByReminderExternalIdentifier:
        runtimeSnapshot.taskSourceRuntimeStateByReminderExternalIdentifier,
      projectionEngine: runtimeSnapshot.projectionEngine
    )
  }

  func replaceRuntimeProjectionSidecarMetadataByReminderIdentifier(
    _ value: [String: OutlinerTaskSidecarMetadata]
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.featureSidecarByReminderIdentifier = value
    }
  }

  func replaceRuntimeProjectionSidecarMetadataByReminderIdentifier(
    for reminderIdentifier: String,
    metadata: OutlinerTaskSidecarMetadata
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.featureSidecarByReminderIdentifier[reminderIdentifier] = metadata
    }
  }

  func removeRuntimeProjectionSidecarMetadataByReminderIdentifier(for reminderIdentifier: String) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.featureSidecarByReminderIdentifier.removeValue(forKey: reminderIdentifier)
    }
  }

  func replaceRuntimeProjectionSidecarMetadataByNodeID(
    _ value: [UUID: OutlinerTaskSidecarMetadata]
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.featureSidecarByNodeID = value
    }
  }

  func replaceRuntimeProjectionSidecarMetadataByNodeID(
    for nodeID: UUID,
    metadata: OutlinerTaskSidecarMetadata
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.featureSidecarByNodeID[nodeID] = metadata
    }
  }

  func removeRuntimeProjectionSidecarMetadataByNodeID(for nodeID: UUID) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.featureSidecarByNodeID.removeValue(forKey: nodeID)
    }
  }

  func replaceRuntimeProjectionReminderMetadataByReminderIdentifier(
    _ value: [String: ReminderMetadataSnapshot]
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.reminderMetadataByReminderIdentifier = value
    }
  }

  func replaceRuntimeProjectionReminderMetadataByReminderIdentifier(
    for reminderIdentifier: String,
    metadata: ReminderMetadataSnapshot
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.reminderMetadataByReminderIdentifier[reminderIdentifier] = metadata
    }
  }

  func removeRuntimeProjectionReminderMetadataByReminderIdentifier(
    for reminderIdentifier: String
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.reminderMetadataByReminderIdentifier.removeValue(forKey: reminderIdentifier)
    }
  }

  func replaceRuntimeProjectionReminderMetadataByNodeID(
    _ value: [UUID: ReminderMetadataSnapshot]
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.reminderMetadataByNodeID = value
    }
  }

  func replaceRuntimeProjectionReminderMetadataByNodeID(
    for nodeID: UUID,
    metadata: ReminderMetadataSnapshot
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.reminderMetadataByNodeID[nodeID] = metadata
    }
  }

  func removeRuntimeProjectionReminderMetadataByNodeID(for nodeID: UUID) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.reminderMetadataByNodeID.removeValue(forKey: nodeID)
    }
  }

  func replaceRuntimeProjectionTaskFeatureSidecars(
    _ value: [String: ReminderTaskFeatureSidecarRecord]
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.taskFeatureSidecarByReminderExternalIdentifier = value
    }
  }

  func replaceRuntimeProjectionTaskFeatureSidecar(
    for reminderExternalIdentifier: String,
    metadata: ReminderTaskFeatureSidecarRecord
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier] =
        metadata
    }
  }

  func removeRuntimeProjectionTaskFeatureSidecar(for reminderExternalIdentifier: String) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
        forKey: reminderExternalIdentifier
      )
    }
  }

  func replaceRuntimeProjectionTaskSourceRuntimeStates(
    _ value: [String: ReminderTaskSourceRuntimeState]
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.taskSourceRuntimeStateByReminderExternalIdentifier = value
    }
  }

  func replaceRuntimeProjectionTaskSourceRuntimeState(
    for reminderExternalIdentifier: String,
    runtimeState: ReminderTaskSourceRuntimeState
  ) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.taskSourceRuntimeStateByReminderExternalIdentifier[reminderExternalIdentifier] =
        runtimeState
    }
  }

  func removeRuntimeProjectionTaskSourceRuntimeState(for reminderExternalIdentifier: String) {
    mutateCachedRuntimeProjectionSnapshot { snapshot in
      snapshot.taskSourceRuntimeStateByReminderExternalIdentifier.removeValue(
        forKey: reminderExternalIdentifier
      )
    }
  }
}
