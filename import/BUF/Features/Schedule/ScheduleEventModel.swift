import Foundation

struct ScheduleEventCapabilities: OptionSet, Hashable, Sendable {
  let rawValue: Int

  static let reveal = ScheduleEventCapabilities(rawValue: 1 << 0)
  static let complete = ScheduleEventCapabilities(rawValue: 1 << 1)
  static let drag = ScheduleEventCapabilities(rawValue: 1 << 2)
  static let resize = ScheduleEventCapabilities(rawValue: 1 << 3)
}

enum ScheduleEventSource: Hashable, Sendable {
  case workspaceTask(taskID: UUID, projectID: UUID)
  case calendarEvent(eventID: String)
}

struct ScheduleEventModel: Identifiable, Hashable, Sendable {
  let id: String
  let source: ScheduleEventSource
  let title: String
  let subtitle: String?
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
  let colorHex: String?
  let isCompleted: Bool
  let isPreparationSlot: Bool
  let targetCompletedWorkUnits: Int?
  let capabilities: ScheduleEventCapabilities
}
