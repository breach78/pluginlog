import AppKit
@preconcurrency import EventKit
import Foundation

struct ReminderListImportSnapshot: Equatable, Sendable {
  let identifier: String
  let externalIdentifier: String?
  let title: String
  let colorHex: String?

  init(
    identifier: String,
    externalIdentifier: String?,
    title: String,
    colorHex: String?
  ) {
    self.identifier = identifier
    self.externalIdentifier = externalIdentifier
    self.title = title
    self.colorHex = colorHex
  }
}

struct ReminderItemImportSnapshot: Equatable, Sendable {
  let identifier: String
  let externalIdentifier: String?
  let parentExternalIdentifier: String?
  let sourceListIdentifier: String
  let sourceListTitle: String
  let title: String
  let notes: String
  let attachmentCount: Int
  let isCompleted: Bool
  let completionDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let scheduleHasExplicitTime: Bool
  let scheduledDurationMinutes: Int?
  let priority: Int
  let recurrenceRuleRaw: String?
  let isFlagged: Bool
  let requiredWorkDays: Int
  let createdAt: Date
  let modifiedAt: Date

  init(
    identifier: String,
    externalIdentifier: String?,
    parentExternalIdentifier: String?,
    sourceListIdentifier: String,
    sourceListTitle: String,
    title: String,
    notes: String,
    attachmentCount: Int,
    isCompleted: Bool,
    completionDate: Date?,
    startDate: Date?,
    dueDate: Date?,
    scheduleHasExplicitTime: Bool,
    scheduledDurationMinutes: Int?,
    priority: Int,
    recurrenceRuleRaw: String?,
    isFlagged: Bool,
    requiredWorkDays: Int,
    createdAt: Date,
    modifiedAt: Date
  ) {
    self.identifier = identifier
    self.externalIdentifier = externalIdentifier
    self.parentExternalIdentifier = parentExternalIdentifier
    self.sourceListIdentifier = sourceListIdentifier
    self.sourceListTitle = sourceListTitle
    self.title = title
    self.notes = notes
    self.attachmentCount = attachmentCount
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.startDate = startDate
    self.dueDate = dueDate
    self.scheduleHasExplicitTime = scheduleHasExplicitTime
    self.scheduledDurationMinutes = scheduledDurationMinutes
    self.priority = priority
    self.recurrenceRuleRaw = recurrenceRuleRaw
    self.isFlagged = isFlagged
    self.requiredWorkDays = requiredWorkDays
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
  }
}

struct ReminderImportSnapshotBatch: Equatable, Sendable {
  let lists: [ReminderListImportSnapshot]
  let itemsByListIdentifier: [String: [ReminderItemImportSnapshot]]

  init(
    lists: [ReminderListImportSnapshot],
    itemsByListIdentifier: [String: [ReminderItemImportSnapshot]]
  ) {
    self.lists = lists
    self.itemsByListIdentifier = itemsByListIdentifier
  }
}

@MainActor
struct ReminderGatewayImportSnapshotProvider {
  let gateway: ReminderGateway

  func fetchAllLists() async throws -> [ReminderListImportSnapshot] {
    try await gateway.fetchAllCalendars()
      .map(listSnapshot(for:))
      .sorted { lhs, rhs in
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
  }

  func fetchItemsByList(
    for lists: [ReminderListImportSnapshot]
  ) async throws -> [String: [ReminderItemImportSnapshot]] {
    var itemsByListIdentifier: [String: [ReminderItemImportSnapshot]] = [:]

    for list in lists {
      guard let calendar = gateway.calendar(withIdentifier: list.identifier) else {
        itemsByListIdentifier[list.identifier] = []
        continue
      }
      let reminders = try await gateway.fetchReminders(in: calendar, scope: .all)
      itemsByListIdentifier[list.identifier] = reminders
        .map { snapshot(for: $0, list: list) }
        .sorted(by: reminderComparator(_:_:))
    }

    return itemsByListIdentifier
  }

  func fetchBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch {
    let normalizedIdentifiers = Array(
      NSOrderedSet(
        array: identifiers.compactMap { identifier in
          let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
          return trimmed.isEmpty ? nil : trimmed
        }
      )
    ) as? [String] ?? identifiers

    var lists: [ReminderListImportSnapshot] = []
    var itemsByListIdentifier: [String: [ReminderItemImportSnapshot]] = [:]

    for identifier in normalizedIdentifiers {
      guard let calendar = gateway.calendar(withIdentifier: identifier) else { continue }
      let list = listSnapshot(for: calendar)
      lists.append(list)
      let reminders = try await gateway.fetchReminders(in: calendar, scope: .all)
      itemsByListIdentifier[list.identifier] = reminders
        .map { snapshot(for: $0, list: list) }
        .sorted(by: reminderComparator(_:_:))
    }

    return ReminderImportSnapshotBatch(
      lists: lists.sorted { lhs, rhs in
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      },
      itemsByListIdentifier: itemsByListIdentifier
    )
  }

  func listSnapshot(for calendar: EKCalendar) -> ReminderListImportSnapshot {
    ReminderListImportSnapshot(
      identifier: calendar.calendarIdentifier,
      externalIdentifier: calendar.calendarIdentifier,
      title: calendar.title,
      colorHex: calendar.cgColor.flatMap { cgColor in
        ColorHexCodec.hexString(from: NSColor(cgColor: cgColor))
      }
    )
  }

  private func snapshot(
    for reminder: EKReminder,
    list: ReminderListImportSnapshot
  ) -> ReminderItemImportSnapshot {
    let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    let completionDate = reminder.completionDate
    let recurrenceRuleRaw = encodedRecurrence(reminder.recurrenceRules?.first)

    return ReminderItemImportSnapshot(
      identifier: reminder.calendarItemIdentifier,
      externalIdentifier: reminder.calendarItemExternalIdentifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: list.identifier,
      sourceListTitle: list.title,
      title: reminder.title ?? "",
      notes: reminder.notes ?? "",
      attachmentCount: 0,
      isCompleted: reminder.isCompleted,
      completionDate: completionDate,
      startDate: nil,
      dueDate: dueDate,
      scheduleHasExplicitTime: reminder.dueDateComponents.map(hasExplicitTime(in:)) ?? false,
      scheduledDurationMinutes: nil,
      priority: reminder.priority,
      recurrenceRuleRaw: recurrenceRuleRaw,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: reminder.creationDate ?? .distantPast,
      modifiedAt: gateway.lastModifiedDate(for: reminder) ?? reminder.creationDate ?? .distantPast
    )
  }

  private func reminderComparator(
    _ lhs: ReminderItemImportSnapshot,
    _ rhs: ReminderItemImportSnapshot
  ) -> Bool {
    if lhs.isCompleted != rhs.isCompleted {
      return rhs.isCompleted
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.identifier.localizedStandardCompare(rhs.identifier) == .orderedAscending
  }

  private func hasExplicitTime(in components: DateComponents) -> Bool {
    components.hour != nil || components.minute != nil || components.second != nil
  }

  private func encodedRecurrence(_ rule: EKRecurrenceRule?) -> String? {
    guard let rule else { return nil }

    switch rule.frequency {
    case .daily:
      return "daily|\(max(1, rule.interval))"
    case .weekly:
      let weekdays = (rule.daysOfTheWeek ?? [])
        .map(\.dayOfTheWeek.rawValue)
        .sorted()
        .map(String.init)
        .joined(separator: ",")
      return "weekly|\(max(1, rule.interval))|\(weekdays)"
    case .monthly:
      return "monthly|\(max(1, rule.interval))"
    case .yearly:
      return "yearly|\(max(1, rule.interval))"
    @unknown default:
      return nil
    }
  }
}
