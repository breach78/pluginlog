import Foundation

enum AppOwnerStore: String, Sendable {
  case reminder
  case calendar
  case sidecar
}

enum AppOwnerField: String, Sendable {
  case listMetadata
  case taskFields
  case eventFields
  case title
  case isCompleted
  case note
  case dueDate
  case recurrence
  case metadata
  case startDate
  case endDate
  case isAllDay
  case calendarId
}

extension AppOwnerField {
  static let reminderTaskExternalChangeFields: [AppOwnerField] = [
    .title,
    .isCompleted,
    .note,
    .dueDate,
    .recurrence,
    .metadata,
  ]

  static let calendarEventExternalChangeFields: [AppOwnerField] = [
    .title,
    .startDate,
    .endDate,
    .isAllDay,
    .recurrence,
    .calendarId,
  ]
}

enum AppCommand: Sendable {
  case externalOwnerChange(
    ownerStore: AppOwnerStore,
    ownerIDs: [String],
    changedFields: [AppOwnerField]
  )
}
