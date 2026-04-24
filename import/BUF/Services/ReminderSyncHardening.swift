@preconcurrency import EventKit
import CoreLocation
import CryptoKit
import Foundation
import SwiftData

struct ReminderSyncLogicalDedupKey: Codable, Hashable, Sendable {
  var contentID: UUID
  var baseBaselineVersion: String
  var localMutationRevision: String
}

struct ReminderSyncPendingOperationRecord: Codable, Equatable, Sendable {
  struct RemoteIdentity: Codable, Equatable, Sendable {
    var calendarIdentifier: String
    var reminderIdentifier: String?
    var reminderExternalIdentifier: String?
    var baselineRemoteLastModifiedAt: Date?
  }

  struct PayloadSummary: Codable, Equatable, Sendable {
    var title: String
    var isCompleted: Bool
    var completionDate: Date?
    var unifiedReminderDate: Date?
    var hasExplicitTime: Bool
    var priority: Int
    var recurrenceRuleRaw: String?
    var parentExternalIdentifier: String?
    var reminderNoteDigest: String
    var reminderRawPayloadRaw: String?
  }

  var operationID: UUID
  var logicalDedupKey: ReminderSyncLogicalDedupKey
  var contentID: UUID
  var projectID: UUID?
  var remoteIdentity: RemoteIdentity
  var payloadSummary: PayloadSummary
  var enqueuedAt: Date
  var remoteWriteCompletedAt: Date?
}

extension ReminderSyncPendingOperationRecord {
  init(
    content: TaskContentCanonicalSnapshot,
    projectID: UUID?,
    calendarIdentifier: String,
    parentExternalIdentifier: String?,
    reminder: EKReminder?,
    operationID: UUID = UUID(),
    enqueuedAt: Date = .now
  ) {
    let logicalDedupKey = ReminderSyncLogicalDedup.key(for: content)

    self.operationID = operationID
    self.logicalDedupKey = logicalDedupKey
    self.contentID = content.id
    self.projectID = projectID
    self.remoteIdentity = RemoteIdentity(
      calendarIdentifier: calendarIdentifier,
      reminderIdentifier: content.reminderIdentifier ?? reminder?.calendarItemIdentifier,
      reminderExternalIdentifier: content.reminderExternalIdentifier ?? reminder?.calendarItemExternalIdentifier,
      baselineRemoteLastModifiedAt: content.remoteLastModifiedAt
    )
    self.payloadSummary = PayloadSummary(
      title: content.title,
      isCompleted: content.isCompleted,
      completionDate: content.completionDate,
      unifiedReminderDate: ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: content.dueDate,
        startDate: content.startDate
      ),
      hasExplicitTime: content.scheduleHasExplicitTime,
      priority: content.priority,
      recurrenceRuleRaw: content.recurrenceRuleRaw,
      parentExternalIdentifier: parentExternalIdentifier,
      reminderNoteDigest: ReminderSyncLogicalDedup.digest(for: content.reminderNoteText),
      reminderRawPayloadRaw: content.reminderRawPayloadRaw
    )
    self.enqueuedAt = enqueuedAt
    self.remoteWriteCompletedAt = nil
  }

  init(
    contentID: UUID,
    projectID: UUID?,
    calendarIdentifier: String,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?,
    baselineRemoteLastModifiedAt: Date?,
    title: String,
    isCompleted: Bool,
    unifiedReminderDate: Date?,
    hasExplicitTime: Bool,
    priority: Int,
    recurrenceRuleRaw: String?,
    parentExternalIdentifier: String?,
    reminderNoteText: String,
    reminderRawPayloadRaw: String?,
    localUpdatedAt: Date,
    operationID: UUID = UUID(),
    enqueuedAt: Date = .now
  ) {
    let logicalDedupKey = ReminderSyncLogicalDedup.key(
      contentID: contentID,
      reminderIdentifier: reminderIdentifier,
      reminderExternalIdentifier: reminderExternalIdentifier,
      remoteLastModifiedAt: baselineRemoteLastModifiedAt,
      localUpdatedAt: localUpdatedAt
    )

    self.operationID = operationID
    self.logicalDedupKey = logicalDedupKey
    self.contentID = contentID
    self.projectID = projectID
    self.remoteIdentity = RemoteIdentity(
      calendarIdentifier: calendarIdentifier,
      reminderIdentifier: reminderIdentifier,
      reminderExternalIdentifier: reminderExternalIdentifier,
      baselineRemoteLastModifiedAt: baselineRemoteLastModifiedAt
    )
    self.payloadSummary = PayloadSummary(
      title: title,
      isCompleted: isCompleted,
      completionDate: isCompleted ? .now : nil,
      unifiedReminderDate: unifiedReminderDate,
      hasExplicitTime: hasExplicitTime,
      priority: priority,
      recurrenceRuleRaw: recurrenceRuleRaw,
      parentExternalIdentifier: parentExternalIdentifier,
      reminderNoteDigest: ReminderSyncLogicalDedup.digest(for: reminderNoteText),
      reminderRawPayloadRaw: reminderRawPayloadRaw
    )
    self.enqueuedAt = enqueuedAt
    self.remoteWriteCompletedAt = nil
  }
}

enum ReminderSyncLogicalDedup {
  static func key(for content: TaskContentCanonicalSnapshot) -> ReminderSyncLogicalDedupKey {
    ReminderSyncLogicalDedupKey(
      contentID: content.id,
      baseBaselineVersion: baseBaselineVersion(for: content),
      localMutationRevision: localMutationRevision(for: content)
    )
  }

  static func baseBaselineVersion(for content: TaskContentCanonicalSnapshot) -> String {
    let reminderIdentifier = normalizedIdentifier(content.reminderIdentifier) ?? "nil"
    let externalIdentifier = normalizedIdentifier(content.reminderExternalIdentifier) ?? "nil"
    let modifiedAt = timestampString(content.remoteLastModifiedAt)
    return "identifier=\(reminderIdentifier)|external=\(externalIdentifier)|modifiedAt=\(modifiedAt)"
  }

  static func localMutationRevision(for content: TaskContentCanonicalSnapshot) -> String {
    timestampString(content.localUpdatedAt)
  }

  static func key(
    contentID: UUID,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?,
    remoteLastModifiedAt: Date?,
    localUpdatedAt: Date
  ) -> ReminderSyncLogicalDedupKey {
    ReminderSyncLogicalDedupKey(
      contentID: contentID,
      baseBaselineVersion: [
        "identifier=\(normalizedIdentifier(reminderIdentifier) ?? "nil")",
        "external=\(normalizedIdentifier(reminderExternalIdentifier) ?? "nil")",
        "modifiedAt=\(timestampString(remoteLastModifiedAt))",
      ].joined(separator: "|"),
      localMutationRevision: timestampString(localUpdatedAt)
    )
  }

  static func digest(for text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func timestampString(_ value: Date?) -> String {
    guard let value else { return "nil" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: value)
  }
}

@MainActor
final class ReminderSyncRecoveryJournalStore {
  private struct PersistedState: Codable {
    var records: [ReminderSyncPendingOperationRecord]
  }

  private let fileURL: URL?
  private let fileManager: FileManager
  private var recordsByID: [UUID: ReminderSyncPendingOperationRecord] = [:]

  init(
    fileURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    loadPersistedState()
  }

  var hasUnfinishedOperations: Bool {
    !recordsByID.isEmpty
  }

  func unfinishedOperationsSorted() -> [ReminderSyncPendingOperationRecord] {
    recordsByID.values.sorted { lhs, rhs in
      if lhs.enqueuedAt != rhs.enqueuedAt {
        return lhs.enqueuedAt < rhs.enqueuedAt
      }
      return lhs.operationID.uuidString < rhs.operationID.uuidString
    }
  }

  @discardableResult
  func enqueue(_ record: ReminderSyncPendingOperationRecord) -> ReminderSyncPendingOperationRecord {
    if let existing = recordsByID[record.operationID] {
      return existing
    }

    if let logicalDuplicate = unfinishedOperationsSorted().first(where: {
      $0.logicalDedupKey == record.logicalDedupKey
    }) {
      return logicalDuplicate
    }

    recordsByID[record.operationID] = record
    persistState()
    return record
  }

  @discardableResult
  func markRemoteWriteCompleted(
    operationID: UUID,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?,
    remoteLastModifiedAt: Date?,
    completedAt: Date = .now
  ) -> ReminderSyncPendingOperationRecord? {
    guard var record = recordsByID[operationID] else { return nil }
    record.remoteIdentity.reminderIdentifier = normalizedIdentifier(reminderIdentifier)
    record.remoteIdentity.reminderExternalIdentifier = normalizedIdentifier(reminderExternalIdentifier)
    record.remoteIdentity.baselineRemoteLastModifiedAt = remoteLastModifiedAt
    record.remoteWriteCompletedAt = completedAt
    recordsByID[operationID] = record
    persistState()
    return record
  }

  func remove(operationID: UUID) {
    guard recordsByID.removeValue(forKey: operationID) != nil else { return }
    persistState()
  }

  func pruneResolvedEntries(tasks: [TaskContentCanonicalSnapshot]) {
    guard !recordsByID.isEmpty else { return }

    let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    var removedAny = false

    for record in unfinishedOperationsSorted() {
      guard let task = tasksByID[record.contentID] else {
        recordsByID.removeValue(forKey: record.operationID)
        removedAny = true
        continue
      }

      if ReminderSyncLogicalDedup.key(for: task) == record.logicalDedupKey {
        continue
      }

      recordsByID.removeValue(forKey: record.operationID)
      removedAny = true
    }

    if removedAny {
      persistState()
    }
  }

  private func loadPersistedState() {
    guard let fileURL, fileManager.fileExists(atPath: fileURL.path) else { return }

    do {
      let data = try Data(contentsOf: fileURL)
      let state = try JSONDecoder().decode(PersistedState.self, from: data)
      recordsByID = Dictionary(uniqueKeysWithValues: state.records.map { ($0.operationID, $0) })
    } catch {
      AppLogger.sync.error(
        "load reminder sync recovery journal failed: \(error.localizedDescription, privacy: .public)"
      )
      recordsByID = [:]
    }
  }

  private func persistState() {
    guard let fileURL else { return }

    do {
      let state = PersistedState(records: unfinishedOperationsSorted())
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(state)
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
      )
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.sync.error(
        "persist reminder sync recovery journal failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

@MainActor
final class ReminderSyncEditGate {
  enum SessionKind: String, Codable, CaseIterable {
    case generic
    case title
    case subtree
    case schedule
  }

  struct Session: Codable, Equatable, Sendable {
    var sessionID: String
    var ownerWindowID: String?
    var startedAt: Date
    var lastHeartbeatAt: Date
    var sessionKind: SessionKind
    var contentID: UUID?
    var projectID: UUID?
  }

  struct ManualRevalidateRecord: Codable, Equatable, Sendable {
    var contentID: UUID?
    var projectID: UUID?
    var reason: String
    var markedAt: Date
  }

  struct SweepResult: Equatable, Sendable {
    var cancelledSessionIDs: [String]
    var forcedManualRevalidateCount: Int
  }

  private struct PersistedState: Codable {
    var sessions: [Session]
    var manualRevalidations: [ManualRevalidateRecord]
  }

  private let fileURL: URL?
  private let ttl: TimeInterval
  private let fileManager: FileManager
  private var sessionsByID: [String: Session] = [:]
  private var manualRevalidations: [ManualRevalidateRecord] = []

  var onStateChange: (() -> Void)?

  init(
    fileURL: URL? = nil,
    ttl: TimeInterval = 30,
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.ttl = ttl
    self.fileManager = fileManager
    loadPersistedState()
  }

  var hasActiveSessions: Bool {
    !sessionsByID.isEmpty
  }

  var needsManualRevalidate: Bool {
    !manualRevalidations.isEmpty
  }

  func beginSession(
    sessionID: String,
    ownerWindowID: String?,
    kind: SessionKind,
    contentID: UUID? = nil,
    projectID: UUID? = nil,
    now: Date = .now
  ) {
    let session = Session(
      sessionID: sessionID,
      ownerWindowID: ownerWindowID,
      startedAt: now,
      lastHeartbeatAt: now,
      sessionKind: kind,
      contentID: contentID,
      projectID: projectID
    )
    sessionsByID[sessionID] = session
    persistState()
    onStateChange?()
  }

  func heartbeat(sessionID: String, now: Date = .now) {
    guard var session = sessionsByID[sessionID] else { return }
    session.lastHeartbeatAt = now
    sessionsByID[sessionID] = session
  }

  func heartbeatAllSessions(now: Date = .now) {
    guard !sessionsByID.isEmpty else { return }
    for sessionID in sessionsByID.keys {
      heartbeat(sessionID: sessionID, now: now)
    }
  }

  func endSession(sessionID: String) {
    guard sessionsByID.removeValue(forKey: sessionID) != nil else { return }
    persistState()
    onStateChange?()
  }

  func cancelSessionsOwnedByWindow(_ ownerWindowID: String) {
    let removedIDs = sessionsByID.values
      .filter { $0.ownerWindowID == ownerWindowID }
      .map(\.sessionID)

    guard !removedIDs.isEmpty else { return }
    for sessionID in removedIDs {
      sessionsByID.removeValue(forKey: sessionID)
    }
    persistState()
    onStateChange?()
  }

  func clearAllManualRevalidation() {
    guard !manualRevalidations.isEmpty else { return }
    manualRevalidations = []
    persistState()
    onStateChange?()
  }

  func sweepOrphanedSessions(
    activeOwnerWindowIDs: Set<String>,
    now: Date = .now
  ) -> SweepResult {
    var cancelledSessionIDs: [String] = []
    var forcedManualRevalidateCount = 0

    for session in sessionsByID.values.sorted(by: { $0.startedAt < $1.startedAt }) {
      let ttlExpired = now.timeIntervalSince(session.lastHeartbeatAt) > ttl
      let ownerLost = ownerWindowLost(session.ownerWindowID, activeOwnerWindowIDs: activeOwnerWindowIDs)

      guard ttlExpired, ownerLost else { continue }

      sessionsByID.removeValue(forKey: session.sessionID)
      cancelledSessionIDs.append(session.sessionID)
      forcedManualRevalidateCount += markNeedsManualRevalidate(
        contentID: session.contentID,
        projectID: session.projectID,
        reason: "forcedCancel:\(session.sessionKind.rawValue)",
        markedAt: now
      )
    }

    if !cancelledSessionIDs.isEmpty {
      persistState()
      onStateChange?()
    }

    return SweepResult(
      cancelledSessionIDs: cancelledSessionIDs,
      forcedManualRevalidateCount: forcedManualRevalidateCount
    )
  }

  private func ownerWindowLost(
    _ ownerWindowID: String?,
    activeOwnerWindowIDs: Set<String>
  ) -> Bool {
    guard let ownerWindowID, !ownerWindowID.isEmpty else { return true }
    return !activeOwnerWindowIDs.contains(ownerWindowID)
  }

  private func markNeedsManualRevalidate(
    contentID: UUID?,
    projectID: UUID?,
    reason: String,
    markedAt: Date
  ) -> Int {
    if manualRevalidations.contains(where: {
      $0.contentID == contentID && $0.projectID == projectID && $0.reason == reason
    }) {
      return 0
    }

    manualRevalidations.append(
      ManualRevalidateRecord(
        contentID: contentID,
        projectID: projectID,
        reason: reason,
        markedAt: markedAt
      )
    )
    manualRevalidations.sort { lhs, rhs in
      if lhs.markedAt != rhs.markedAt {
        return lhs.markedAt < rhs.markedAt
      }
      return manualRevalidateSortKey(lhs) < manualRevalidateSortKey(rhs)
    }
    return 1
  }

  private func manualRevalidateSortKey(_ record: ManualRevalidateRecord) -> String {
    [
      record.projectID?.uuidString ?? "nil",
      record.contentID?.uuidString ?? "nil",
      record.reason,
    ].joined(separator: "|")
  }

  private func loadPersistedState() {
    guard let fileURL, fileManager.fileExists(atPath: fileURL.path) else { return }

    do {
      let data = try Data(contentsOf: fileURL)
      let state = try JSONDecoder().decode(PersistedState.self, from: data)
      sessionsByID = Dictionary(uniqueKeysWithValues: state.sessions.map { ($0.sessionID, $0) })
      manualRevalidations = state.manualRevalidations
    } catch {
      AppLogger.sync.error(
        "load reminder sync edit gate failed: \(error.localizedDescription, privacy: .public)"
      )
      sessionsByID = [:]
      manualRevalidations = []
    }
  }

  private func persistState() {
    guard let fileURL else { return }

    do {
      let state = PersistedState(
        sessions: sessionsByID.values.sorted { lhs, rhs in
          if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
          }
          return lhs.sessionID < rhs.sessionID
        },
        manualRevalidations: manualRevalidations
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(state)
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
      )
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.sync.error(
        "persist reminder sync edit gate failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}

struct ReminderSyncRawPreservationPayload: Codable, Equatable, Sendable {
  struct Alarm: Codable, Equatable, Sendable {
    var absoluteDate: Date?
    var relativeOffset: TimeInterval?
    var proximityRaw: Int?
    var structuredLocationTitle: String?
    var latitude: Double?
    var longitude: Double?
    var radius: Double?
  }

  struct Participant: Codable, Equatable, Sendable {
    var name: String?
    var url: String?
    var participantStatusRaw: Int
    var participantRoleRaw: Int
    var participantTypeRaw: Int
    var isCurrentUser: Bool
  }

  var alarms: [Alarm]
  var organizer: Participant?
  var attendees: [Participant]
}

enum ReminderSyncRawPreservationCodec {
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let decoder = JSONDecoder()

  static func encode(reminder: EKReminder) -> String? {
    let alarms = (reminder.alarms ?? []).map { alarm in
      let coordinate = alarm.structuredLocation?.geoLocation?.coordinate
      return ReminderSyncRawPreservationPayload.Alarm(
        absoluteDate: alarm.absoluteDate,
        relativeOffset: alarm.absoluteDate == nil ? alarm.relativeOffset : nil,
        proximityRaw: alarm.proximity.rawValue,
        structuredLocationTitle: normalizedString(alarm.structuredLocation?.title),
        latitude: coordinate?.latitude,
        longitude: coordinate?.longitude,
        radius: alarm.structuredLocation?.radius
      )
    }

    let attendees = (reminder.attendees ?? []).map(participantPayload(from:))
    let payload = ReminderSyncRawPreservationPayload(
      alarms: alarms,
      organizer: nil,
      attendees: attendees
    )

    guard !payload.alarms.isEmpty || !payload.attendees.isEmpty else {
      return nil
    }

    guard let data = try? encoder.encode(payload) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func decode(rawValue: String?) -> ReminderSyncRawPreservationPayload? {
    guard let rawValue = normalizedString(rawValue) else { return nil }
    guard let data = rawValue.data(using: .utf8) else { return nil }
    return try? decoder.decode(ReminderSyncRawPreservationPayload.self, from: data)
  }

  private static func participantPayload(from participant: EKParticipant) -> ReminderSyncRawPreservationPayload.Participant {
    ReminderSyncRawPreservationPayload.Participant(
      name: normalizedString(participant.name),
      url: normalizedString(participant.url.absoluteString),
      participantStatusRaw: participant.participantStatus.rawValue,
      participantRoleRaw: participant.participantRole.rawValue,
      participantTypeRaw: participant.participantType.rawValue,
      isCurrentUser: participant.isCurrentUser
    )
  }

  private static func normalizedString(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

struct ReminderSyncReadOnlySurface: Equatable, Sendable {
  let locationSummary: String
  let sharingSummary: String
  let assigneeSummary: String
  let tagSummary: String

  static let empty = ReminderSyncReadOnlySurface(
    locationSummary: "없음",
    sharingSummary: "없음",
    assigneeSummary: "없음",
    tagSummary: "필드 예약"
  )
}

enum ReminderSyncReadOnlySurfaceBuilder {
  static func make(from rawPayloadRaw: String?) -> ReminderSyncReadOnlySurface {
    guard let payload = ReminderSyncRawPreservationCodec.decode(rawValue: rawPayloadRaw) else {
      return .empty
    }

    let visibleParticipants = sharedParticipants(in: payload)
    return ReminderSyncReadOnlySurface(
      locationSummary: locationSummary(for: payload.alarms),
      sharingSummary: visibleParticipants.isEmpty ? "없음" : "\(visibleParticipants.count)명",
      assigneeSummary: assigneeSummary(for: visibleParticipants),
      tagSummary: "필드 예약"
    )
  }

  private static func locationSummary(
    for alarms: [ReminderSyncRawPreservationPayload.Alarm]
  ) -> String {
    let locations = alarms.compactMap { alarm -> String? in
      if let title = normalized(alarm.structuredLocationTitle) {
        return title
      }
      guard let latitude = alarm.latitude, let longitude = alarm.longitude else { return nil }
      return String(format: "%.4f, %.4f", latitude, longitude)
    }

    guard let firstLocation = locations.first else { return "없음" }
    guard locations.count > 1 else { return firstLocation }
    return "\(firstLocation) 외 \(locations.count - 1)곳"
  }

  private static func sharedParticipants(
    in payload: ReminderSyncRawPreservationPayload
  ) -> [ReminderSyncRawPreservationPayload.Participant] {
    let attendees = payload.attendees.filter { !$0.isCurrentUser }
    if let organizer = payload.organizer, !organizer.isCurrentUser {
      return [organizer] + attendees
    }
    return attendees
  }

  private static func assigneeSummary(
    for participants: [ReminderSyncRawPreservationPayload.Participant]
  ) -> String {
    guard let first = participants.first else { return "없음" }
    let primary = normalized(first.name) ?? normalized(first.url) ?? "이름 없음"
    guard participants.count > 1 else { return primary }
    return "\(primary) 외 \(participants.count - 1)명"
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
