import Foundation
import SwiftData

/// Phase 13 cleanup boundary freeze:
/// - `Snapshot` and value helpers may remain in app steady-state.
/// - Full canonical load/save entrypoints were quarantined to test support in Phase 1.
struct OutlinerIntegratedTaskState: Equatable {
  var contentID: UUID
  var reminderIdentifier: String?
  var reminderExternalIdentifier: String?
  var ownerProjectID: UUID?
  var ownerCalendarID: String?
  var parentTaskRemoteExternalIdentifier: String?
  var reminderNoteText: String
  var reminderRawPayloadRaw: String?
  var attachmentCount: Int
  var featureSidecar: OutlinerTaskSidecarMetadata
  var reminderMetadata: ReminderMetadataSnapshot
  var reminderNoteConflictExcerpt: String?
  var baseline: ReminderSyncBaseline
  var remoteLastModifiedAt: Date?
  var localUpdatedAt: Date
  var isFlagged: Bool
  var isDirty: Bool

  init(content: TaskContent) {
    let normalizedNoteText = ReminderNoteSourceCodec.parseReminderRawNote(
      content.reminderNoteText
    ).normalizedText
    let recurrence = OutlinerIntegratedStore.decodeRecurrence(rawValue: content.recurrenceRuleRaw)
    let baselineBody =
      content.lastSyncedReminderNoteBody.isEmpty
      ? normalizedNoteText
      : content.lastSyncedReminderNoteBody
    self.contentID = content.id
    self.reminderIdentifier = content.reminderIdentifier
    self.reminderExternalIdentifier = content.reminderExternalIdentifier
    self.ownerProjectID = content.reminderOwnerProjectID
    self.ownerCalendarID = content.reminderOwnerCalendarID
    self.parentTaskRemoteExternalIdentifier = content.parentTaskRemoteExternalIdentifier
    self.reminderNoteText = normalizedNoteText
    self.reminderRawPayloadRaw = content.reminderRawPayloadRaw
    self.attachmentCount = max(0, content.attachmentCount)
    self.featureSidecar = OutlinerTaskSidecarMetadata(
      requiredWorkDays: max(0, content.requiredWorkDays),
      scheduledDurationMinutes: content.scheduledDurationMinutes,
      attachmentPreviews: []
    )
    self.reminderMetadata = ReminderMetadataSnapshot(
      dueDate: content.dueDate,
      hasExplicitTime: content.scheduleHasExplicitTime,
      recurrence: recurrence,
      priority: content.priority
    )
    self.reminderNoteConflictExcerpt = content.reminderNoteConflictExcerpt
    self.baseline = ReminderSyncBaseline(
      lastSyncedReminderTitle: content.lastSyncedReminderTitle,
      lastSyncedReminderNoteBody: baselineBody,
      lastSyncedReminderModifiedAt: content.lastSyncedReminderModifiedAt,
      reminderNoteConflictExcerpt: content.reminderNoteConflictExcerpt
    )
    self.remoteLastModifiedAt = content.remoteLastModifiedAt
    self.localUpdatedAt = content.localUpdatedAt
    self.isFlagged = content.isFlagged
    self.isDirty = content.isDirty
  }

  var reminderBacked: Bool {
    Self.normalized(reminderIdentifier) != nil || Self.normalized(reminderExternalIdentifier) != nil
  }

  mutating func applyReminderSourceBaseline(
    reminderTitle: String,
    normalizedNoteText: String,
    modifiedAt: Date?
  ) {
    reminderNoteConflictExcerpt = nil
    baseline = ReminderSyncBaseline(
      lastSyncedReminderTitle: reminderTitle,
      lastSyncedReminderNoteBody: normalizedNoteText,
      lastSyncedReminderModifiedAt: modifiedAt,
      reminderNoteConflictExcerpt: nil
    )
  }

  mutating func applyRemoteSnapshot(
    title: String,
    rawNote: String,
    rawPreservationPayloadRaw: String?,
    modifiedAt: Date?,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?,
    calendarIdentifier: String?
  ) {
    let normalizedNoteText = ReminderNoteSourceCodec.parseReminderRawNote(rawNote).normalizedText
    reminderNoteText = normalizedNoteText
    reminderRawPayloadRaw = rawPreservationPayloadRaw
    self.reminderIdentifier = Self.normalized(reminderIdentifier)
    self.reminderExternalIdentifier = Self.normalized(reminderExternalIdentifier)
    if let calendarIdentifier = Self.normalized(calendarIdentifier) {
      ownerCalendarID = calendarIdentifier
    }
    applyReminderSourceBaseline(
      reminderTitle: title,
      normalizedNoteText: normalizedNoteText,
      modifiedAt: modifiedAt
    )
    remoteLastModifiedAt = modifiedAt
    localUpdatedAt = .now
  }

  mutating func clearReminderLink() {
    reminderIdentifier = nil
    reminderExternalIdentifier = nil
    reminderNoteText = ""
    reminderRawPayloadRaw = nil
    remoteLastModifiedAt = nil
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

struct OutlinerTaskSessionOverlayState: Equatable {
  var reminderNoteConflictExcerpt: String?
  var pendingRemovalReminderIdentifier: String?
  var pendingRemovalReminderExternalIdentifier: String?

  var hasPendingRemovalReference: Bool {
    Self.normalized(pendingRemovalReminderIdentifier) != nil
      || Self.normalized(pendingRemovalReminderExternalIdentifier) != nil
  }

  var isEmpty: Bool {
    Self.normalized(reminderNoteConflictExcerpt) == nil && !hasPendingRemovalReference
  }

  mutating func storePendingRemovalReference(
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?
  ) {
    pendingRemovalReminderIdentifier = Self.normalized(reminderIdentifier)
    pendingRemovalReminderExternalIdentifier = Self.normalized(reminderExternalIdentifier)
  }

  mutating func clearPendingRemovalReference() {
    pendingRemovalReminderIdentifier = nil
    pendingRemovalReminderExternalIdentifier = nil
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

enum OutlinerReminderOwnerStatus: Equatable {
  case resolved(projectID: UUID, calendarIdentifier: String)
  case ownerMissing
  case ownerPermissionLost(projectID: UUID, calendarIdentifier: String)
  case ownerDrift(projectID: UUID, expectedCalendarIdentifier: String, actualCalendarIdentifier: String?)
}

enum OutlinerIntegratedStore {
  struct Snapshot {
    let projects: [OutlinerProject]
    let taskStatesByContentID: [UUID: OutlinerIntegratedTaskState]

    var reminderLinksByContentID: [UUID: String] {
      taskStatesByContentID.reduce(into: [:]) { partialResult, entry in
        if let reminderIdentifier = normalized(entry.value.reminderIdentifier) {
          partialResult[entry.key] = reminderIdentifier
        }
      }
    }

    var inferredFirstSyncCompleted: Bool {
      taskStatesByContentID.values.contains { $0.reminderBacked }
    }
  }

  @MainActor
  static func ownerStatus(
    for taskState: OutlinerIntegratedTaskState,
    currentProjectID: UUID,
    projects: [OutlinerProject],
    projectRecordsByID: [UUID: ProjectRecord],
    reminderGateway: ReminderGateway?
  ) -> OutlinerReminderOwnerStatus {
    guard taskState.reminderBacked else {
      guard
        let currentProject = projectRecordsByID[currentProjectID],
        let calendarIdentifier = normalized(currentProject.projectReminderListIdentifier)
      else { return .ownerMissing }
      return .resolved(projectID: currentProjectID, calendarIdentifier: calendarIdentifier)
    }

    guard let ownerProjectID = taskState.ownerProjectID,
          let ownerCalendarID = normalized(taskState.ownerCalendarID)
    else {
      return .ownerMissing
    }

    guard let ownerProject = projectRecordsByID[ownerProjectID] else {
      return .ownerMissing
    }

    let actualCalendarIdentifier = normalized(ownerProject.projectReminderListIdentifier)
    if actualCalendarIdentifier != ownerCalendarID {
      return .ownerDrift(
        projectID: ownerProjectID,
        expectedCalendarIdentifier: ownerCalendarID,
        actualCalendarIdentifier: actualCalendarIdentifier
      )
    }

    if let reminderGateway, reminderGateway.calendar(withIdentifier: ownerCalendarID) == nil {
      return .ownerPermissionLost(projectID: ownerProjectID, calendarIdentifier: ownerCalendarID)
    }

    let projectIDs = Set(projects.map(\.id))
    guard projectIDs.contains(ownerProjectID) else {
      return .ownerMissing
    }
    return .resolved(projectID: ownerProjectID, calendarIdentifier: ownerCalendarID)
  }

  static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  static func decodeRecurrence(rawValue: String?) -> OutlinerRecurrenceSample? {
    guard let rawValue = normalized(rawValue) else { return nil }
    let parts = rawValue.components(separatedBy: "|")
    guard let kind = parts.first else { return nil }
    switch kind {
    case "daily":
      return .daily(interval: max(1, Int(parts[safe: 1] ?? "") ?? 1))
    case "weekly":
      let interval = max(1, Int(parts[safe: 1] ?? "") ?? 1)
      let weekdays = parts[safe: 2]?
        .split(separator: ",")
        .compactMap { Int($0) } ?? []
      return .weekly(interval: interval, weekdays: weekdays)
    case "monthly":
      return .monthly(interval: max(1, Int(parts[safe: 1] ?? "") ?? 1))
    case "yearly":
      return .yearly(interval: max(1, Int(parts[safe: 1] ?? "") ?? 1))
    default:
      return nil
    }
  }

  static func encodeRecurrence(_ recurrence: OutlinerRecurrenceSample?) -> String? {
    guard let recurrence else { return nil }
    switch recurrence {
    case let .daily(interval):
      return "daily|\(max(1, interval))"
    case let .weekly(interval, weekdays):
      let weekdayText = weekdays.map(String.init).joined(separator: ",")
      return "weekly|\(max(1, interval))|\(weekdayText)"
    case let .monthly(interval):
      return "monthly|\(max(1, interval))"
    case let .yearly(interval):
      return "yearly|\(max(1, interval))"
    }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}
