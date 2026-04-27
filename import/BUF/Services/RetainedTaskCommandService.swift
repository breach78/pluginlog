import Foundation

struct RetainedTaskCommandResult: Equatable, Sendable {
  let projectID: UUID
  let taskID: UUID
  let calendarBridgeDecision: RetainedCalendarBridgeDecision
  let calendarWriteMarker: RetainedCalendarBridgeWriteMarker?
}

struct RetainedTaskEditFields: Equatable, Sendable {
  var title: String
  var noteText: String
  var day: Date?
  var timeMinutes: Int?
  var durationMinutes: Int?
}

struct RetainedCalendarBridgeWriteMarker: Equatable, Hashable, Sendable {
  enum Operation: String, Equatable, Hashable, Sendable {
    case upsertOwnedEvent
    case removeOwnedEvent
  }

  let taskID: UUID
  let operation: Operation
  let externalIdentifier: String?
  let title: String?
  let startDate: Date?
  let durationMinutes: Int?
}

enum RetainedCalendarBridgeWriteLoopGuard {
  static func marker(
    taskID: UUID,
    decision: RetainedCalendarBridgeDecision
  ) -> RetainedCalendarBridgeWriteMarker? {
    switch decision {
    case .noAction, .failClosed:
      return nil
    case .upsert(let request):
      return RetainedCalendarBridgeWriteMarker(
        taskID: taskID,
        operation: .upsertOwnedEvent,
        externalIdentifier: request.externalIdentifier,
        title: request.title,
        startDate: request.startDate,
        durationMinutes: request.durationMinutes
      )
    case .removeOwnedEvent(let externalIdentifier):
      return RetainedCalendarBridgeWriteMarker(
        taskID: taskID,
        operation: .removeOwnedEvent,
        externalIdentifier: externalIdentifier,
        title: nil,
        startDate: nil,
        durationMinutes: nil
      )
    }
  }

  static func shouldSuppressEcho(
    marker: RetainedCalendarBridgeWriteMarker,
    activeMarkers: Set<RetainedCalendarBridgeWriteMarker>
  ) -> Bool {
    activeMarkers.contains(marker)
  }
}

enum RetainedTaskCommandError: LocalizedError, Equatable {
  case obsidianVaultNotConfigured
  case retainedProjectionFailed(String)
  case projectNotFound(UUID)
  case taskNotFound(UUID)
  case unmanagedTask(UUID)
  case missingReminderExternalIdentifier(UUID)
  case unsafeProjectNote(UUID)
  case reminderOwnerUnresolved(UUID)
  case rollbackFailed(writeError: String, rollbackError: String)

  var errorDescription: String? {
    switch self {
    case .obsidianVaultNotConfigured:
      return "Obsidian vault is not configured for retained task writes."
    case .retainedProjectionFailed(let message):
      return "Retained projection failed: \(message)"
    case .projectNotFound(let projectID):
      return "Retained project was not found: \(projectID.uuidString)"
    case .taskNotFound(let taskID):
      return "Retained task was not found: \(taskID.uuidString)"
    case .unmanagedTask(let taskID):
      return "Retained task is not Reminder-backed: \(taskID.uuidString)"
    case .missingReminderExternalIdentifier(let taskID):
      return "Retained task is missing reminder external id: \(taskID.uuidString)"
    case .unsafeProjectNote(let projectID):
      return "Retained project note is not safe to edit automatically: \(projectID.uuidString)"
    case .reminderOwnerUnresolved(let taskID):
      return "Reminder-backed task could not be resolved in Reminders: \(taskID.uuidString)"
    case .rollbackFailed(let writeError, let rollbackError):
      return "Retained task write failed and markdown rollback failed. write=\(writeError) rollback=\(rollbackError)"
    }
  }
}

enum RetainedSurfaceMutationSurface: Equatable, Sendable {
  case timeline
  case schedule
}

enum RetainedSurfaceMutationGate {
  static func block(_ surface: RetainedSurfaceMutationSurface, feature: String) -> String {
    let surfaceName: String
    switch surface {
    case .timeline:
      surfaceName = "Timeline"
    case .schedule:
      surfaceName = "Schedule"
    }
    return "\(surfaceName) \(feature) is not available in the retained Obsidian workspace."
  }
}
