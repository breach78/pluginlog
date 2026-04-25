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

  func fetchAllBatch() async throws -> ReminderImportSnapshotBatch {
    let calendars = try await gateway.fetchAllCalendars()
    return try await batch(for: calendars)
  }

  func fetchItemsByList(
    for lists: [ReminderListImportSnapshot]
  ) async throws -> [String: [ReminderItemImportSnapshot]] {
    let calendarsByIdentifier = Dictionary(
      uniqueKeysWithValues: lists.compactMap { list in
        gateway.calendar(withIdentifier: list.identifier).map { (list.identifier, $0) }
      }
    )
    return try await fetchItemsByList(for: lists, calendarsByIdentifier: calendarsByIdentifier)
  }

  private func fetchItemsByList(
    for lists: [ReminderListImportSnapshot],
    calendarsByIdentifier: [String: EKCalendar]
  ) async throws -> [String: [ReminderItemImportSnapshot]] {
    var itemsByListIdentifier: [String: [ReminderItemImportSnapshot]] = [:]
    let listsByIdentifier = Dictionary(uniqueKeysWithValues: lists.map { ($0.identifier, $0) })
    let calendars = lists.compactMap { calendarsByIdentifier[$0.identifier] }

    for list in lists {
      guard calendarsByIdentifier[list.identifier] != nil else {
        itemsByListIdentifier[list.identifier] = []
        continue
      }
    }

    let reminders = try await gateway.fetchReminders(in: calendars, scope: .all)
    for reminder in reminders {
      let listIdentifier = reminder.calendar.calendarIdentifier
      guard let list = listsByIdentifier[listIdentifier] else { continue }
      itemsByListIdentifier[listIdentifier, default: []].append(snapshot(for: reminder, list: list))
    }

    for list in lists {
      itemsByListIdentifier[list.identifier] = (itemsByListIdentifier[list.identifier] ?? [])
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

    let calendarsByIdentifier = Dictionary(
      uniqueKeysWithValues: normalizedIdentifiers.compactMap { identifier in
        gateway.calendar(withIdentifier: identifier).map { (identifier, $0) }
      }
    )
    let lists = normalizedIdentifiers.compactMap { identifier in
      calendarsByIdentifier[identifier].map(listSnapshot(for:))
    }
    return try await batch(for: lists, calendarsByIdentifier: calendarsByIdentifier)
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

  private func batch(for calendars: [EKCalendar]) async throws -> ReminderImportSnapshotBatch {
    var calendarsByIdentifier: [String: EKCalendar] = [:]
    for calendar in calendars {
      calendarsByIdentifier[calendar.calendarIdentifier] = calendar
    }
    let lists = calendars.map(listSnapshot(for:))
    return try await batch(for: lists, calendarsByIdentifier: calendarsByIdentifier)
  }

  private func batch(
    for lists: [ReminderListImportSnapshot],
    calendarsByIdentifier: [String: EKCalendar]
  ) async throws -> ReminderImportSnapshotBatch {
    let itemsByListIdentifier = try await fetchItemsByList(
      for: lists,
      calendarsByIdentifier: calendarsByIdentifier
    )
    return ReminderImportSnapshotBatch(
      lists: lists.sorted { lhs, rhs in
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      },
      itemsByListIdentifier: itemsByListIdentifier
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
