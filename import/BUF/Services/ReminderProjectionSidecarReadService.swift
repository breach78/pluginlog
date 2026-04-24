import Foundation

enum ReminderProjectionSidecarReadService {
  static func loadSanitizedPayload(dataDirectory: URL?) -> ReminderProjectionSidecarPayload {
    var payload = ReminderProjectionSidecarStoreFactory.make(dataDirectory: dataDirectory)?.load() ?? .empty
    payload.stripAppMemoryReadModels()
    _ = payload.cutDuplicateProjectReminderConnections()
    return payload
  }

  static func rootStructureRecord(
    reminderListExternalIdentifier: String?,
    dataDirectory: URL?
  ) -> ReminderProjectRootStructureRecord? {
    guard let normalizedReminderListExternalIdentifier = ReminderProjectionIdentity.normalized(
      reminderListExternalIdentifier
    ) else {
      return nil
    }

    return loadSanitizedPayload(dataDirectory: dataDirectory)
      .projectRootStructureByReminderListExternalIdentifier[normalizedReminderListExternalIdentifier]
  }

  static func resolveProjectNodeIDForRootBullet(
    _ bulletID: UUID,
    dataDirectory: URL?,
    resolveProjectNodeID: (String) throws -> UUID?
  ) rethrows -> UUID? {
    let payload = loadSanitizedPayload(dataDirectory: dataDirectory)
    for (reminderListExternalIdentifier, record) in
      payload.projectRootStructureByReminderListExternalIdentifier
    {
      let hasMatchingBullet = ReminderProjectRootStructureCodec.normalizedRecords(
        from: record.rootNodes
      ).contains { record in
        guard case .bullet(let id, _, _) = record else { return false }
        return id == bulletID
      }
      guard hasMatchingBullet else { continue }

      if let projectNodeID = try resolveProjectNodeID(reminderListExternalIdentifier) {
        return projectNodeID
      }
    }
    return nil
  }
}
