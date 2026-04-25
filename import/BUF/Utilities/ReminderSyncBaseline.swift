import Foundation

struct ReminderSyncBaseline: Equatable, Sendable {
  var lastSyncedReminderTitle: String
  var lastSyncedReminderNoteBody: String
  var lastSyncedReminderModifiedAt: Date?
  var reminderNoteConflictExcerpt: String?

  init(
    lastSyncedReminderTitle: String,
    lastSyncedReminderNoteBody: String,
    lastSyncedReminderModifiedAt: Date? = nil,
    reminderNoteConflictExcerpt: String? = nil
  ) {
    self.lastSyncedReminderTitle = lastSyncedReminderTitle
    self.lastSyncedReminderNoteBody = lastSyncedReminderNoteBody
    self.lastSyncedReminderModifiedAt = lastSyncedReminderModifiedAt
    self.reminderNoteConflictExcerpt = reminderNoteConflictExcerpt
  }

  init(
    reminderTitle: String,
    parsedNote: ReminderNoteCodec.ParsedNote,
    modifiedAt: Date? = nil,
    conflictExcerpt: String? = nil
  ) {
    self.init(
      lastSyncedReminderTitle: reminderTitle,
      lastSyncedReminderNoteBody: parsedNote.body,
      lastSyncedReminderModifiedAt: modifiedAt,
      reminderNoteConflictExcerpt: conflictExcerpt
    )
  }
}

struct ReminderSyncTaskState: Codable, Equatable, Sendable {
  var title: String
  var isCompleted: Bool
  var date: String?
  var repeatRule: String?
  var noteText: String?

  init(
    title: String,
    isCompleted: Bool,
    date: String?,
    repeatRule: String?,
    noteText: String?
  ) {
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.isCompleted = isCompleted
    self.date = Self.normalizedOptional(date)
    self.repeatRule = Self.normalizedOptional(repeatRule)
    self.noteText = Self.normalizedOptional(ReminderNoteSourceCodec.normalize(noteText))
  }

  init(importedItem item: ReminderItemImportSnapshot) {
    self.init(
      title: item.title,
      isCompleted: item.isCompleted,
      date: ReminderScheduleMetadataCodec.encodeDate(
        item.dueDate,
        hasExplicitTime: item.scheduleHasExplicitTime
      ),
      repeatRule: ReminderScheduleMetadataCodec.encodeRepeat(item.recurrenceRuleRaw),
      noteText: ReminderNoteSourceCodec.normalizeReminderRawNote(item.notes)
    )
  }

  init(remoteSnapshot snapshot: ReminderTaskRemoteSnapshot) {
    self.init(
      title: snapshot.title,
      isCompleted: snapshot.isCompleted,
      date: ReminderScheduleMetadataCodec.encodeDate(
        snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime
      ),
      repeatRule: ReminderScheduleMetadataCodec.encodeRepeat(snapshot.recurrenceRuleRaw),
      noteText: ReminderNoteSourceCodec.normalizeReminderRawNote(snapshot.noteText)
    )
  }

  func replacing(field: ReminderSyncTaskField, with value: ReminderSyncTaskState) -> Self {
    var next = self
    switch field {
    case .title:
      next.title = value.title
    case .isCompleted:
      next.isCompleted = value.isCompleted
    case .date:
      next.date = value.date
    case .repeatRule:
      next.repeatRule = value.repeatRule
    case .noteText:
      next.noteText = value.noteText
    }
    return next
  }

  func value(for field: ReminderSyncTaskField) -> AnyHashable {
    switch field {
    case .title:
      return title
    case .isCompleted:
      return isCompleted
    case .date:
      return date ?? ""
    case .repeatRule:
      return repeatRule ?? ""
    case .noteText:
      return noteText ?? ""
    }
  }

  private static func normalizedOptional(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}

enum ReminderSyncTaskField: String, Codable, CaseIterable, Sendable {
  case title
  case isCompleted
  case date
  case repeatRule
  case noteText
}

struct ReminderSyncTaskBaselineRecord: Codable, Equatable, Sendable {
  var reminderExternalIdentifier: String
  var state: ReminderSyncTaskState
  var remoteModifiedAt: Date?
  var conflictedFields: [ReminderSyncTaskField]
  var updatedAt: Date

  func hasConflict(_ field: ReminderSyncTaskField) -> Bool {
    conflictedFields.contains(field)
  }
}

struct ReminderSyncTaskBaselineUpdate: Equatable, Sendable {
  var reminderExternalIdentifier: String?
  var state: ReminderSyncTaskState
  var remoteModifiedAt: Date?
  var conflictedFields: [ReminderSyncTaskField]
  var now: Date

  init(
    reminderExternalIdentifier: String?,
    state: ReminderSyncTaskState,
    remoteModifiedAt: Date?,
    conflictedFields: [ReminderSyncTaskField] = [],
    now: Date = .now
  ) {
    self.reminderExternalIdentifier = reminderExternalIdentifier
    self.state = state
    self.remoteModifiedAt = remoteModifiedAt
    self.conflictedFields = conflictedFields
    self.now = now
  }
}

private struct ReminderSyncBaselinePayload: Codable, Equatable {
  var schemaVersion: Int
  var taskBaselines: [ReminderSyncTaskBaselineRecord]

  static let currentSchemaVersion = 1
  static let empty = ReminderSyncBaselinePayload(
    schemaVersion: currentSchemaVersion,
    taskBaselines: []
  )
}

enum ReminderSyncBaselineStore {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var fileURL: URL?
  private nonisolated(unsafe) static var baselinesByReminderExternalIdentifier:
    [String: ReminderSyncTaskBaselineRecord] = [:]

  static func install(dataDirectory: URL?) {
    lock.lock()
    defer { lock.unlock() }
    fileURL = dataDirectory?.appendingPathComponent("retained-sync-baselines.json")
    loadLocked()
  }

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    fileURL = nil
    baselinesByReminderExternalIdentifier = [:]
  }

  static func baseline(for reminderExternalIdentifier: String?) -> ReminderSyncTaskBaselineRecord? {
    guard let key = normalizedIdentifier(reminderExternalIdentifier) else { return nil }
    lock.lock()
    defer { lock.unlock() }
    guard fileURL != nil else { return nil }
    return baselinesByReminderExternalIdentifier[key]
  }

  static func upsert(
    reminderExternalIdentifier: String?,
    state: ReminderSyncTaskState,
    remoteModifiedAt: Date?,
    conflictedFields: [ReminderSyncTaskField] = [],
    now: Date = .now
  ) {
    upsertMany([
      ReminderSyncTaskBaselineUpdate(
        reminderExternalIdentifier: reminderExternalIdentifier,
        state: state,
        remoteModifiedAt: remoteModifiedAt,
        conflictedFields: conflictedFields,
        now: now
      ),
    ])
  }

  static func upsertMany(_ updates: [ReminderSyncTaskBaselineUpdate]) {
    guard !updates.isEmpty else { return }
    lock.lock()
    guard fileURL != nil else {
      lock.unlock()
      return
    }
    var didChange = false
    for update in updates {
      guard let key = normalizedIdentifier(update.reminderExternalIdentifier) else { continue }
      let conflictedFields = Array(Set(update.conflictedFields)).sorted {
        $0.rawValue < $1.rawValue
      }
      if let existing = baselinesByReminderExternalIdentifier[key],
        existing.state == update.state,
        existing.remoteModifiedAt == update.remoteModifiedAt,
        existing.conflictedFields == conflictedFields
      {
        continue
      }
      baselinesByReminderExternalIdentifier[key] = ReminderSyncTaskBaselineRecord(
        reminderExternalIdentifier: key,
        state: update.state,
        remoteModifiedAt: update.remoteModifiedAt,
        conflictedFields: conflictedFields,
        updatedAt: update.now
      )
      didChange = true
    }
    if didChange {
      persistLocked()
    }
    lock.unlock()
  }

  static func remove(reminderExternalIdentifier: String?) {
    guard let key = normalizedIdentifier(reminderExternalIdentifier) else { return }
    lock.lock()
    guard fileURL != nil else {
      lock.unlock()
      return
    }
    let didRemove = baselinesByReminderExternalIdentifier.removeValue(forKey: key) != nil
    if didRemove {
      persistLocked()
    }
    lock.unlock()
  }

  private static func loadLocked() {
    guard let fileURL,
      let data = try? Data(contentsOf: fileURL),
      let payload = try? JSONDecoder().decode(ReminderSyncBaselinePayload.self, from: data),
      payload.schemaVersion == ReminderSyncBaselinePayload.currentSchemaVersion
    else {
      baselinesByReminderExternalIdentifier = [:]
      return
    }
    baselinesByReminderExternalIdentifier = [:]
    for record in payload.taskBaselines {
      guard let key = normalizedIdentifier(record.reminderExternalIdentifier) else { continue }
      if let previous = baselinesByReminderExternalIdentifier[key],
        previous.updatedAt > record.updatedAt
      {
        continue
      }
      baselinesByReminderExternalIdentifier[key] = record
    }
  }

  private static func persistLocked() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let payload = ReminderSyncBaselinePayload(
        schemaVersion: ReminderSyncBaselinePayload.currentSchemaVersion,
        taskBaselines: Array(baselinesByReminderExternalIdentifier.values)
          .sorted { $0.reminderExternalIdentifier < $1.reminderExternalIdentifier }
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(payload)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.sync.error(
        "reminder sync baseline persist failed: \(error.localizedDescription, privacy: .public)"
      )
    }
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
