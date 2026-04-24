import Foundation

enum ReminderProjectionSidecarMutationService {
  @discardableResult
  static func mutateProjectRootStructure(
    reminderListExternalIdentifier: String,
    mutation: (inout ReminderProjectRootStructureRecord) -> Void,
    store: ReminderProjectionSidecarStore
  ) -> ReminderProjectRootStructureRecord? {
    guard let reminderListExternalIdentifier = ReminderProjectionIdentity.normalized(
      reminderListExternalIdentifier
    ) else {
      return nil
    }

    var payload = store.load() ?? .empty
    var record = payload.projectRootStructureByReminderListExternalIdentifier[
      reminderListExternalIdentifier
    ] ?? ReminderProjectRootStructureMutationService.record(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      rootNodes: [],
      existing: nil
    )
    mutation(&record)
    payload.projectRootStructureByReminderListExternalIdentifier[reminderListExternalIdentifier] =
      record
    try? store.save(payload)
    return payload.projectRootStructureByReminderListExternalIdentifier[
      reminderListExternalIdentifier]
  }

  @discardableResult
  static func mutateProjectFeature(
    reminderListExternalIdentifier: String,
    mutation: (inout ReminderProjectFeatureSidecarRecord) -> Void,
    store: ReminderProjectionSidecarStore
  ) -> ReminderProjectFeatureSidecarRecord? {
    guard let reminderListExternalIdentifier = ReminderProjectionIdentity.normalized(
      reminderListExternalIdentifier
    ) else {
      return nil
    }

    var payload = store.load() ?? .empty
    var record = payload.projectFeatureSidecarByReminderListExternalIdentifier[
      reminderListExternalIdentifier
    ] ?? ReminderProjectFeatureMutationService.projectFeatureRecord(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      projectNoteMarkdown: "",
      localStartDate: nil,
      localDeadline: nil,
      progressStageRaw: nil,
      boardOrder: nil,
      existing: nil
    )
    mutation(&record)

    if record.hasMeaningfulContent {
      payload.projectFeatureSidecarByReminderListExternalIdentifier[reminderListExternalIdentifier] =
        record
    } else {
      payload.projectFeatureSidecarByReminderListExternalIdentifier.removeValue(
        forKey: reminderListExternalIdentifier
      )
    }

    try? store.save(payload)
    return payload.projectFeatureSidecarByReminderListExternalIdentifier[
      reminderListExternalIdentifier]
  }

  @discardableResult
  static func mutateTaskFeature(
    reminderExternalIdentifier: String,
    mutation: (inout ReminderTaskFeatureSidecarRecord) -> Void,
    store: ReminderProjectionSidecarStore
  ) -> ReminderTaskFeatureSidecarRecord? {
    guard let reminderExternalIdentifier = ReminderProjectionIdentity.normalized(
      reminderExternalIdentifier
    ) else {
      return nil
    }

    var payload = store.load() ?? .empty
    var record = payload.taskFeatureSidecarByReminderExternalIdentifier[
      reminderExternalIdentifier
    ] ?? AppFeatureMutationService.taskFeatureRecord(
      reminderExternalIdentifier: reminderExternalIdentifier,
      featureSidecar: OutlinerTaskSidecarMetadata()
    )
    mutation(&record)

    if record.hasMeaningfulContent {
      payload.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier] = record
    } else {
      payload.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
        forKey: reminderExternalIdentifier
      )
    }

    try? store.save(payload)
    return payload.taskFeatureSidecarByReminderExternalIdentifier[reminderExternalIdentifier]
  }

  @discardableResult
  static func mutateTaskOrder(
    reminderListExternalIdentifier: String,
    orderedExternalIdentifiers: [String],
    store: ReminderProjectionSidecarStore
  ) -> ReminderProjectTaskOrderRecord? {
    guard let reminderListExternalIdentifier = ReminderProjectionIdentity.normalized(
      reminderListExternalIdentifier
    ) else {
      return nil
    }

    var payload = store.load() ?? .empty
    let record = ReminderProjectTaskOrderMutationService.record(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      orderedTopLevelReminderExternalIdentifiers: orderedExternalIdentifiers,
      existing: payload.projectTaskOrderByReminderListExternalIdentifier[
        reminderListExternalIdentifier]
    )
    payload.projectTaskOrderByReminderListExternalIdentifier[reminderListExternalIdentifier] =
      record
    try? store.save(payload)
    return record
  }
}
