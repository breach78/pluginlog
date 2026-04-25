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

  init(task: LogseqProjectPageStore.TaskRecord) {
    self.init(
      title: task.title,
      isCompleted: task.isCompleted,
      date: task.date,
      repeatRule: task.repeatRule,
      noteText: task.noteText
    )
  }

  init(importedItem item: ReminderItemImportSnapshot) {
    self.init(
      title: item.title,
      isCompleted: item.isCompleted,
      date: LogseqReminderPropertyCodec.encodeDate(
        item.dueDate,
        hasExplicitTime: item.scheduleHasExplicitTime
      ),
      repeatRule: LogseqReminderPropertyCodec.encodeRepeat(item.recurrenceRuleRaw),
      noteText: ReminderNoteSourceCodec.normalizeReminderRawNote(item.notes)
    )
  }

  init(remoteSnapshot snapshot: ReminderTaskRemoteSnapshot) {
    self.init(
      title: snapshot.title,
      isCompleted: snapshot.isCompleted,
      date: LogseqReminderPropertyCodec.encodeDate(
        snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime
      ),
      repeatRule: LogseqReminderPropertyCodec.encodeRepeat(snapshot.recurrenceRuleRaw),
      noteText: ReminderNoteSourceCodec.normalizeReminderRawNote(snapshot.noteText)
    )
  }

  func applying(to task: LogseqProjectPageStore.TaskRecord) -> LogseqProjectPageStore.TaskRecord {
    LogseqProjectPageStore.TaskRecord(
      taskID: task.taskID,
      title: title,
      isCompleted: isCompleted,
      date: date,
      duration: task.duration,
      repeatRule: repeatRule,
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      calendarEventExternalIdentifier: task.calendarEventExternalIdentifier,
      noteText: noteText
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

enum ReminderSyncTaskMerge {
  struct ImportDecision: Equatable {
    var mergedTask: LogseqProjectPageStore.TaskRecord
    var nextBaseline: ReminderSyncTaskState
    var nextBaselineRemoteModifiedAt: Date?
    var conflictedFields: [ReminderSyncTaskField]
  }

  static func mergeImportedTask(
    localTask: LogseqProjectPageStore.TaskRecord,
    remoteTask: LogseqProjectPageStore.TaskRecord,
    remoteModifiedAt: Date?,
    baseline: ReminderSyncTaskBaselineRecord?
  ) -> ImportDecision {
    let local = ReminderSyncTaskState(task: localTask)
    let remote = ReminderSyncTaskState(task: remoteTask)
    guard let baseline else {
      return ImportDecision(
        mergedTask: remote.applying(to: localTask),
        nextBaseline: remote,
        nextBaselineRemoteModifiedAt: remoteModifiedAt,
        conflictedFields: []
      )
    }
    if remoteSnapshotIsOlderThanBaseline(
      remoteModifiedAt: remoteModifiedAt,
      baselineRemoteModifiedAt: baseline.remoteModifiedAt
    ) {
      return ImportDecision(
        mergedTask: localTask,
        nextBaseline: baseline.state,
        nextBaselineRemoteModifiedAt: baseline.remoteModifiedAt,
        conflictedFields: baseline.conflictedFields
      )
    }

    var merged = local
    var nextBaseline = baseline.state
    var conflicts = baseline.conflictedFields
    var shouldClearLocalNoteSubtree = false
    for field in ReminderSyncTaskField.allCases {
      let baseValue = baseline.state.value(for: field)
      let localValue = local.value(for: field)
      let remoteValue = remote.value(for: field)
      let localChanged = localValue != baseValue
      let remoteChanged = remoteValue != baseValue

      if localChanged && remoteChanged && localValue != remoteValue {
        conflicts.append(field)
        continue
      }
      conflicts.removeAll { $0 == field }
      if remoteChanged {
        merged = merged.replacing(field: field, with: remote)
        nextBaseline = nextBaseline.replacing(field: field, with: remote)
        if field == .noteText, remote.noteText == nil {
          shouldClearLocalNoteSubtree = true
        }
      } else if !localChanged {
        nextBaseline = nextBaseline.replacing(field: field, with: local)
      }
    }
    var mergedTask = merged.applying(to: localTask)
    if shouldClearLocalNoteSubtree {
      mergedTask.noteText = ""
    }

    return ImportDecision(
      mergedTask: mergedTask,
      nextBaseline: nextBaseline,
      nextBaselineRemoteModifiedAt: remoteModifiedAt,
      conflictedFields: Array(Set(conflicts)).sorted { $0.rawValue < $1.rawValue }
    )
  }

  static func fieldsToPush(
    localTask: LogseqProjectPageStore.TaskRecord,
    remoteSnapshot: ReminderTaskRemoteSnapshot,
    baseline: ReminderSyncTaskBaselineRecord?
  ) -> [ReminderSyncTaskField] {
    let local = ReminderSyncTaskState(task: localTask)
    let remote = ReminderSyncTaskState(remoteSnapshot: remoteSnapshot)
    guard let baseline else {
      return []
    }
    guard !remoteSnapshotIsOlderThanBaseline(
      remoteModifiedAt: remoteSnapshot.modifiedAt,
      baselineRemoteModifiedAt: baseline.remoteModifiedAt
    ) else {
      return []
    }
    return ReminderSyncTaskField.allCases.filter { field in
      guard !baseline.hasConflict(field) else { return false }
      let localChanged = local.value(for: field) != baseline.state.value(for: field)
      let remoteChanged = remote.value(for: field) != baseline.state.value(for: field)
      guard localChanged else { return false }
      guard !remoteChanged else { return local.value(for: field) == remote.value(for: field) }
      return local.value(for: field) != remote.value(for: field)
    }
  }

  static func baselineAfterPush(
    previous baseline: ReminderSyncTaskBaselineRecord?,
    localTask: LogseqProjectPageStore.TaskRecord,
    remoteSnapshot: ReminderTaskRemoteSnapshot,
    pushedFields: [ReminderSyncTaskField]
  ) -> (state: ReminderSyncTaskState, conflicts: [ReminderSyncTaskField]) {
    let local = ReminderSyncTaskState(task: localTask)
    let remote = ReminderSyncTaskState(remoteSnapshot: remoteSnapshot)
    var next = baseline?.state ?? remote
    var conflicts = baseline?.conflictedFields ?? []
    for field in pushedFields {
      next = next.replacing(field: field, with: local)
      conflicts.removeAll { $0 == field }
    }
    for field in ReminderSyncTaskField.allCases where local.value(for: field) == remote.value(for: field) {
      next = next.replacing(field: field, with: local)
      conflicts.removeAll { $0 == field }
    }
    return (next, Array(Set(conflicts)).sorted { $0.rawValue < $1.rawValue })
  }

  private static func remoteSnapshotIsOlderThanBaseline(
    remoteModifiedAt: Date?,
    baselineRemoteModifiedAt: Date?
  ) -> Bool {
    guard let remoteModifiedAt, let baselineRemoteModifiedAt else {
      return false
    }
    return baselineRemoteModifiedAt.timeIntervalSince(remoteModifiedAt) > 0.5
  }

}
