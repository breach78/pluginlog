import Foundation

struct ReminderDeletedTaskTombstone: Codable, Equatable, Sendable {
  var reminderExternalIdentifier: String
  var deletedAt: Date
}

private struct ReminderDeletedTaskTombstonePayload: Codable, Equatable {
  var taskTombstones: [ReminderDeletedTaskTombstone]

  static let empty = ReminderDeletedTaskTombstonePayload(taskTombstones: [])
}

enum ReminderDeletedTaskTombstoneStore {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var fileURL: URL?
  private nonisolated(unsafe) static var payload = ReminderDeletedTaskTombstonePayload.empty
  private static let tombstoneTTL: TimeInterval = 24 * 60 * 60

  static func install(dataDirectory: URL?) {
    lock.lock()
    defer { lock.unlock() }
    fileURL = dataDirectory?.appendingPathComponent("retained-deleted-reminder-tasks.json")
    loadLocked()
  }

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    fileURL = nil
    payload = .empty
  }

  static func upsertTaskDeletion(
    reminderExternalIdentifier: String?,
    deletedAt: Date = .now
  ) {
    guard let reminderExternalIdentifier = normalizedIdentifier(reminderExternalIdentifier) else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    pruneExpiredLocked(now: deletedAt)
    payload.taskTombstones.removeAll {
      $0.reminderExternalIdentifier == reminderExternalIdentifier
    }
    payload.taskTombstones.append(
      ReminderDeletedTaskTombstone(
        reminderExternalIdentifier: reminderExternalIdentifier,
        deletedAt: deletedAt
      )
    )
    persistLocked()
  }

  static func shouldSuppressImport(
    reminderExternalIdentifier: String?,
    remoteModifiedAt: Date?,
    now: Date = .now
  ) -> Bool {
    guard let reminderExternalIdentifier = normalizedIdentifier(reminderExternalIdentifier) else {
      return false
    }
    lock.lock()
    defer { lock.unlock() }
    pruneExpiredLocked(now: now)
    guard let tombstone = payload.taskTombstones.first(where: {
      $0.reminderExternalIdentifier == reminderExternalIdentifier
    }) else {
      return false
    }
    if let remoteModifiedAt,
      remoteModifiedAt.timeIntervalSince(tombstone.deletedAt) > 0.5
    {
      return false
    }
    return true
  }

  private static func loadLocked() {
    guard let fileURL,
      let data = try? Data(contentsOf: fileURL),
      let decoded = try? JSONDecoder().decode(ReminderDeletedTaskTombstonePayload.self, from: data)
    else {
      payload = .empty
      return
    }
    payload = decoded
  }

  private static func persistLocked() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(payload)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.sync.error(
        "deleted reminder task tombstone persist failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private static func pruneExpiredLocked(now: Date) {
    payload.taskTombstones.removeAll { now.timeIntervalSince($0.deletedAt) > tombstoneTTL }
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}
