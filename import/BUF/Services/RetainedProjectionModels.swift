import Foundation

struct RetainedWorkspaceSnapshot: Equatable, Sendable {
  let projects: [RetainedProject]

  var tasks: [RetainedTask] {
    projects.flatMap(\.tasks)
  }
}

struct RetainedProject: Equatable, Sendable {
  let identity: RetainedProjectIdentity
  let fileURL: URL
  let title: String
  let noteMarkdown: String
  let tasks: [RetainedTask]
  let usesProjectTag: Bool
  let isBUFOwned: Bool
  let hasManagedTaskSection: Bool
  let canSafelyPersistProjectNote: Bool
}

struct RetainedProjectIdentity: Equatable, Sendable {
  let projectID: UUID
  let reminderListExternalIdentifier: String?
}

struct RetainedTask: Equatable, Sendable {
  let identity: RetainedTaskIdentity
  let title: String
  let isCompleted: Bool
  let schedule: RetainedTaskSchedule
  let isManagedTask: Bool
}

struct RetainedTaskIdentity: Equatable, Sendable {
  let taskID: UUID?
  let reminderExternalIdentifier: String?
  let calendarEventExternalIdentifier: String?

  var isCalendarBridgeManaged: Bool {
    taskID != nil && (reminderExternalIdentifier != nil || calendarEventExternalIdentifier != nil)
  }
}

struct RetainedTaskSchedule: Equatable, Sendable {
  let rawDate: String?
  let parsedDate: Date?
  let hasExplicitTime: Bool
  let rawDuration: String?
  let durationMinutes: Int?
  let rawRepeatRule: String?
  let canonicalRepeatRule: String?

  var hasDateValue: Bool {
    Self.normalized(rawDate) != nil
  }

  var hasDurationValue: Bool {
    Self.normalized(rawDuration) != nil
  }

  var hasDamagedDateValue: Bool {
    hasDateValue && parsedDate == nil
  }

  var hasDamagedDurationValue: Bool {
    hasDurationValue && durationMinutes == nil
  }

  var isCalendarOwnedCandidate: Bool {
    parsedDate != nil && hasExplicitTime && durationMinutes != nil
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

struct RetainedCalendarBridgeUpsertRequest: Equatable, Sendable {
  let externalIdentifier: String?
  let title: String
  let startDate: Date
  let durationMinutes: Int
}

enum RetainedCalendarBridgeBlocker: Equatable, Sendable {
  case ambiguousOwnedEventIdentifier(String)
  case unmanagedTaskIdentity
  case invalidDate(String)
  case invalidDuration(String)
}

enum RetainedCalendarBridgeDecision: Equatable, Sendable {
  case noAction
  case upsert(RetainedCalendarBridgeUpsertRequest)
  case removeOwnedEvent(externalIdentifier: String)
  case failClosed(RetainedCalendarBridgeBlocker)
}
