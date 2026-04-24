import Foundation

enum ReminderProjectionSidecarReadService {
  static func rootStructureRecord(
    reminderListExternalIdentifier: String?,
    dataDirectory: URL?
  ) -> ReminderProjectRootStructureRecord? {
    _ = reminderListExternalIdentifier
    _ = dataDirectory
    return nil
  }

  static func resolveProjectNodeIDForRootBullet(
    _ bulletID: UUID,
    dataDirectory: URL?,
    resolveProjectNodeID: (String) throws -> UUID?
  ) rethrows -> UUID? {
    _ = bulletID
    _ = dataDirectory
    _ = resolveProjectNodeID
    return nil
  }
}
