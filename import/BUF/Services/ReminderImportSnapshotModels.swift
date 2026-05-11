import AppKit
@preconcurrency import EventKit
import Foundation

struct ReminderListImportSnapshot: Codable, Equatable, Sendable {
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

struct ReminderItemImportSnapshot: Codable, Equatable, Sendable {
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

struct ReminderImportSnapshotBatch: Codable, Equatable, Sendable {
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

    let importSelection = try await fetchImportReminders(in: calendars)
    let reminders = importSelection.reminders
    for reminder in reminders {
      let listIdentifier = reminder.calendar.calendarIdentifier
      guard let list = listsByIdentifier[listIdentifier] else { continue }
      itemsByListIdentifier[listIdentifier, default: []].append(
        snapshot(
          for: reminder,
          list: list,
          fallbackDueDate: importSelection.fallbackDueDatesByReminderIdentifier[
            reminder.calendarItemIdentifier
          ]
        )
      )
    }

    for list in lists {
      itemsByListIdentifier[list.identifier] = (itemsByListIdentifier[list.identifier] ?? [])
        .sorted(by: reminderComparator(_:_:))
    }

    return itemsByListIdentifier
  }

  private struct ImportReminderSelection {
    let reminders: [EKReminder]
    let fallbackDueDatesByReminderIdentifier: [String: Date]
  }

  private func fetchImportReminders(in calendars: [EKCalendar]) async throws -> ImportReminderSelection {
    let primaryReminders = try await gateway.fetchReminders(in: calendars, scope: .all)
    let fallbackDueDatesByReminderIdentifier = completedOccurrenceFallbackDueDates(
      in: primaryReminders
    )
    return ImportReminderSelection(
      reminders: primaryReminders.filter {
        shouldImportReminder(
          $0,
          in: primaryReminders,
          fallbackDueDate: fallbackDueDatesByReminderIdentifier[$0.calendarItemIdentifier]
        )
      },
      fallbackDueDatesByReminderIdentifier: fallbackDueDatesByReminderIdentifier
    )
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
    list: ReminderListImportSnapshot,
    fallbackDueDate: Date? = nil
  ) -> ReminderItemImportSnapshot {
    let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
      ?? fallbackDueDate
    let completionDate = reminder.completionDate
    let recurrenceRuleRaw = encodedRecurrence(reminder.recurrenceRules?.first)

    let hasExplicitTime = reminder.dueDateComponents.map(hasExplicitTime(in:))
      ?? fallbackDueDate.map(hasExplicitTime(in:))
      ?? false
    return ReminderItemImportSnapshot(
      identifier: reminder.calendarItemIdentifier,
      externalIdentifier: importedExternalIdentifier(
        for: reminder,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime,
        completionDate: completionDate
      ),
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
      scheduleHasExplicitTime: hasExplicitTime,
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

  private func hasExplicitTime(in date: Date) -> Bool {
    let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    return (components.hour ?? 0) != 0
      || (components.minute ?? 0) != 0
      || (components.second ?? 0) != 0
  }

  private func importedExternalIdentifier(
    for reminder: EKReminder,
    dueDate: Date?,
    hasExplicitTime: Bool,
    completionDate: Date?
  ) -> String? {
    let originalIdentifier = normalized(reminder.calendarItemExternalIdentifier)
    guard isCompletedRecurringReminder(reminder) else {
      return originalIdentifier
    }

    guard let baseIdentifier = originalIdentifier ?? normalized(reminder.calendarItemIdentifier) else {
      return nil
    }
    let occurrenceKey = ReminderScheduleMetadataCodec.encodeDate(
      dueDate,
      hasExplicitTime: hasExplicitTime
    )
      ?? completionDate.map { ISO8601DateFormatter().string(from: $0) }
      ?? normalized(reminder.calendarItemIdentifier)
      ?? "unknown"
    return "\(baseIdentifier)::completed::\(occurrenceKey)"
  }

  private func isCompletedRecurringReminder(_ reminder: EKReminder) -> Bool {
    reminder.isCompleted && !(reminder.recurrenceRules?.isEmpty ?? true)
  }

  private func shouldImportReminder(
    _ reminder: EKReminder,
    in reminders: [EKReminder],
    fallbackDueDate: Date?
  ) -> Bool {
    guard reminder.isCompleted else { return true }
    if isCompletedRecurringReminder(reminder) {
      return false
    }
    if fallbackDueDate != nil {
      return true
    }
    guard let completedCandidate = recurringOccurrenceCandidate(for: reminder) else {
      return true
    }
    return !reminders.contains { activeReminder in
      guard let activeCandidate = activeRecurringCandidate(for: activeReminder),
        activeCandidate.signature == completedCandidate.signature
      else {
        return false
      }
      return true
    }
  }

  private struct RecurringOccurrenceSignature: Hashable {
    let calendarIdentifier: String
    let title: String
    let notes: String
  }

  private struct ActiveRecurringCandidate {
    let signature: RecurringOccurrenceSignature
    let dueDate: Date?
  }

  private struct CompletedOccurrenceCandidate {
    let signature: RecurringOccurrenceSignature
    let dueDate: Date?
  }

  private func activeRecurringCandidate(for reminder: EKReminder) -> ActiveRecurringCandidate? {
    guard !reminder.isCompleted,
      !(reminder.recurrenceRules?.isEmpty ?? true)
    else {
      return nil
    }
    return ActiveRecurringCandidate(
      signature: recurringOccurrenceSignature(for: reminder),
      dueDate: dueDate(for: reminder)
    )
  }

  private func recurringOccurrenceCandidate(for reminder: EKReminder) -> CompletedOccurrenceCandidate? {
    guard reminder.isCompleted,
      dueDate(for: reminder) != nil || reminder.completionDate != nil
    else {
      return nil
    }
    return CompletedOccurrenceCandidate(
      signature: recurringOccurrenceSignature(for: reminder),
      dueDate: dueDate(for: reminder) ?? reminder.completionDate
    )
  }

  private func completedOccurrenceFallbackDueDates(in reminders: [EKReminder]) -> [String: Date] {
    let activeRecurringSignatures = Set(
      reminders.compactMap { activeRecurringCandidate(for: $0)?.signature }
    )
    guard !activeRecurringSignatures.isEmpty else { return [:] }

    return reminders.reduce(into: [String: Date]()) { result, reminder in
      guard reminder.isCompleted,
        dueDate(for: reminder) == nil,
        let completionDate = reminder.completionDate,
        activeRecurringSignatures.contains(recurringOccurrenceSignature(for: reminder))
      else {
        return
      }
      result[reminder.calendarItemIdentifier] = completionDate
    }
  }

  private func recurringOccurrenceSignature(for reminder: EKReminder) -> RecurringOccurrenceSignature {
    RecurringOccurrenceSignature(
      calendarIdentifier: reminder.calendar.calendarIdentifier,
      title: normalizedSignatureText(reminder.title),
      notes: normalizedSignatureText(reminder.notes)
    )
  }

  private func dueDate(for reminder: EKReminder) -> Date? {
    reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
  }

  private func normalizedSignatureText(_ value: String?) -> String {
    (value ?? "")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func normalized(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
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
