import Foundation

struct ReminderProjectionBootstrapSeedResult {
  var runtimeSnapshot: OutlineProjectionRuntimeSnapshot
  var sidecarPayload: ReminderProjectionSidecarPayload
  var didSeed: Bool
}

enum ReminderProjectionBootstrapSeedService {
  static func seeded(
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot,
    existingPayload: ReminderProjectionSidecarPayload,
    now: Date = .now
  ) -> ReminderProjectionBootstrapSeedResult {
    var payload = existingPayload
    var didSeed = false

    if payload.workspaceStructureRecord == nil {
      let orderedReminderListExternalIdentifiers = runtimeSnapshot.projects.compactMap { project in
        runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[project.id]
      }
      if !orderedReminderListExternalIdentifiers.isEmpty {
        payload.workspaceStructureRecord = ReminderWorkspaceStructureMutationService.record(
          orderedReminderListExternalIdentifiers: orderedReminderListExternalIdentifiers,
          existing: nil,
          now: now
        )
        didSeed = true
      }
    }

    for project in runtimeSnapshot.projects {
      guard let reminderListExternalIdentifier =
        runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[project.id]
      else {
        continue
      }
      if payload.projectTaskOrderByReminderListExternalIdentifier[reminderListExternalIdentifier] == nil
      {
        let orderedTopLevelReminderExternalIdentifiers: [String] = project.document.rootNodes.compactMap {
          node -> String? in
          guard node.type.isTask else { return nil }
          return ReminderProjectionIdentity.normalized(node.reminderExternalIdentifier)
        }
        payload.projectTaskOrderByReminderListExternalIdentifier[reminderListExternalIdentifier] =
          ReminderProjectTaskOrderMutationService.record(
            reminderListExternalIdentifier: reminderListExternalIdentifier,
            orderedTopLevelReminderExternalIdentifiers: orderedTopLevelReminderExternalIdentifiers,
            existing: nil,
            now: now
          )
        didSeed = true
      }

      if payload.projectRootStructureByReminderListExternalIdentifier[reminderListExternalIdentifier] == nil
      {
        payload.projectRootStructureByReminderListExternalIdentifier[reminderListExternalIdentifier] =
          ReminderProjectRootStructureMutationService.record(
            reminderListExternalIdentifier: reminderListExternalIdentifier,
            rootNodes: ReminderProjectRootStructureCodec.rootNodes(from: project.document.rootNodes),
            existing: nil,
            now: now
          )
        didSeed = true
      }
    }

    guard didSeed else {
      return ReminderProjectionBootstrapSeedResult(
        runtimeSnapshot: runtimeSnapshot,
        sidecarPayload: existingPayload,
        didSeed: false
      )
    }

    return ReminderProjectionBootstrapSeedResult(
      runtimeSnapshot: runtimeSnapshot.withBootstrapSeedPayload(payload),
      sidecarPayload: payload,
      didSeed: true
    )
  }
}

private extension OutlineProjectionRuntimeSnapshot {
  func withBootstrapSeedPayload(
    _ payload: ReminderProjectionSidecarPayload
  ) -> OutlineProjectionRuntimeSnapshot {
    OutlineProjectionRuntimeSnapshot(
      projects: projects,
      currentProjectID: currentProjectID,
      featureSidecarByReminderIdentifier: featureSidecarByReminderIdentifier,
      featureSidecarByNodeID: featureSidecarByNodeID,
      reminderMetadataByReminderIdentifier: reminderMetadataByReminderIdentifier,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      projectReminderListIdentifierByProjectID: projectReminderListIdentifierByProjectID,
      projectReminderListExternalIdentifierByProjectID:
        projectReminderListExternalIdentifierByProjectID,
      projectColorHexByProjectID: projectColorHexByProjectID,
      reminderModifiedAtByReminderExternalIdentifier: reminderModifiedAtByReminderExternalIdentifier,
      workspaceStructureRecord: payload.workspaceStructureRecord,
      projectTaskOrderByReminderListExternalIdentifier:
        payload.projectTaskOrderByReminderListExternalIdentifier,
      projectRootStructureByReminderListExternalIdentifier:
        payload.projectRootStructureByReminderListExternalIdentifier,
      projectFeatureSidecarByProjectID: projectFeatureSidecarByProjectID,
      projectFeatureSidecarByReminderListExternalIdentifier:
        projectFeatureSidecarByReminderListExternalIdentifier,
      taskFeatureSidecarByReminderExternalIdentifier:
        taskFeatureSidecarByReminderExternalIdentifier,
      taskSourceRuntimeStateByReminderExternalIdentifier:
        taskSourceRuntimeStateByReminderExternalIdentifier,
      projectionEngine: projectionEngine
    )
    .withProjectConnectionSidecarState(
      payload.projectConnectionSidecarByReminderListExternalIdentifier
    )
  }
}
