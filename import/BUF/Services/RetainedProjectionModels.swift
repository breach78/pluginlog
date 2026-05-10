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
  let isArchived: Bool
  let colorHex: String?
  let localStartDate: Date?
  let localDeadline: Date?
  let progressStage: ProjectProgressStage
  let boardOrder: Int?
  let updatedAt: Date

  init(
    identity: RetainedProjectIdentity,
    fileURL: URL,
    title: String,
    noteMarkdown: String,
    tasks: [RetainedTask],
    usesProjectTag: Bool,
    isBUFOwned: Bool,
    hasManagedTaskSection: Bool,
    canSafelyPersistProjectNote: Bool,
    isArchived: Bool = false,
    colorHex: String? = nil,
    localStartDate: Date? = nil,
    localDeadline: Date? = nil,
    progressStage: ProjectProgressStage = .do,
    boardOrder: Int? = nil,
    updatedAt: Date = .distantPast
  ) {
    self.identity = identity
    self.fileURL = fileURL
    self.title = title
    self.noteMarkdown = noteMarkdown
    self.tasks = tasks
    self.usesProjectTag = usesProjectTag
    self.isBUFOwned = isBUFOwned
    self.hasManagedTaskSection = hasManagedTaskSection
    self.canSafelyPersistProjectNote = canSafelyPersistProjectNote
    self.isArchived = isArchived
    self.colorHex = colorHex
    self.localStartDate = localStartDate
    self.localDeadline = localDeadline
    self.progressStage = progressStage
    self.boardOrder = boardOrder
    self.updatedAt = updatedAt
  }
}

struct RetainedProjectIdentity: Equatable, Sendable {
  let projectID: UUID
  let reminderListExternalIdentifier: String?
}

struct RetainedTask: Equatable, Sendable {
  let identity: RetainedTaskIdentity
  let title: String
  let noteText: String
  let isCompleted: Bool
  let schedule: RetainedTaskSchedule
  let isManagedTask: Bool
  let priority: Int

  init(
    identity: RetainedTaskIdentity,
    title: String,
    noteText: String,
    isCompleted: Bool,
    schedule: RetainedTaskSchedule,
    isManagedTask: Bool,
    priority: Int = 0
  ) {
    self.identity = identity
    self.title = title
    self.noteText = noteText
    self.isCompleted = isCompleted
    self.schedule = schedule
    self.isManagedTask = isManagedTask
    self.priority = priority
  }
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
