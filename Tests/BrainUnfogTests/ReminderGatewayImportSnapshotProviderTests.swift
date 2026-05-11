@preconcurrency import EventKit
import XCTest
@testable import BrainUnfog

@MainActor
final class ReminderGatewayImportSnapshotProviderTests: XCTestCase {
  func testFetchItemsByListUsesOneBatchReminderFetch() async throws {
    let gateway = BatchImportSnapshotGateway()
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    let lists = try await provider.fetchAllLists()

    let itemsByList = try await provider.fetchItemsByList(for: lists)

    XCTAssertEqual(gateway.singleCalendarFetchCount, 0)
    XCTAssertEqual(gateway.batchCalendarFetchCount, 1)
    XCTAssertEqual(itemsByList[gateway.firstCalendar.calendarIdentifier]?.map(\.title), ["First task"])
    XCTAssertEqual(itemsByList[gateway.secondCalendar.calendarIdentifier]?.map(\.title), ["Second task"])
  }

  func testFetchAllBatchReusesFetchedCalendarsWithoutIdentifierLookups() async throws {
    let gateway = BatchImportSnapshotGateway()
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)

    let batch = try await provider.fetchAllBatch()

    XCTAssertEqual(gateway.calendarLookupCount, 0)
    XCTAssertEqual(gateway.singleCalendarFetchCount, 0)
    XCTAssertEqual(gateway.batchCalendarFetchCount, 1)
    XCTAssertEqual(batch.lists.map(\.title), ["A", "B"])
    XCTAssertEqual(batch.itemsByListIdentifier[gateway.firstCalendar.calendarIdentifier]?.map(\.title), ["First task"])
  }

  func testFetchItemsByListDropsCompletedRecurringReminders() async throws {
    let gateway = BatchImportSnapshotGateway(includeCompletedRecurringReminder: true)
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    let lists = try await provider.fetchAllLists()

    let itemsByList = try await provider.fetchItemsByList(for: lists)
    let firstListItems = try XCTUnwrap(itemsByList[gateway.firstCalendar.calendarIdentifier])

    XCTAssertEqual(firstListItems.map(\.title), ["First task"])
  }

  func testFetchItemsByListDropsCompletedOccurrenceThatLostRecurrenceRuleWhenActiveRecurringExists()
    async throws
  {
    let gateway = BatchImportSnapshotGateway(includeCompletedOccurrenceWithoutRecurrence: true)
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    let lists = try await provider.fetchAllLists()

    let itemsByList = try await provider.fetchItemsByList(for: lists)
    let firstListItems = try XCTUnwrap(itemsByList[gateway.firstCalendar.calendarIdentifier])

    XCTAssertEqual(firstListItems.filter { $0.title == "Active recurring" }.count, 1)
  }

  func testFetchItemsByListPreservesCompletedOccurrenceDateWhenDueDateWasLost()
    async throws
  {
    let gateway = BatchImportSnapshotGateway(includeCompletedOccurrenceWithoutDueDate: true)
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    let lists = try await provider.fetchAllLists()

    let itemsByList = try await provider.fetchItemsByList(for: lists)
    let firstListItems = try XCTUnwrap(itemsByList[gateway.firstCalendar.calendarIdentifier])
    let completedOccurrence = try XCTUnwrap(firstListItems.first {
      $0.title == "Due-less recurring" && $0.isCompleted
    })
    let expectedDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(
      from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30)
    ))

    XCTAssertEqual(firstListItems.filter { $0.title == "Due-less recurring" }.count, 2)
    XCTAssertEqual(completedOccurrence.dueDate, expectedDate)
    XCTAssertTrue(completedOccurrence.scheduleHasExplicitTime)
  }

  func testFetchItemsByListDropsCompletedOccurrenceAfterRestoredActiveAnchor() async throws {
    let gateway = BatchImportSnapshotGateway(includeCompletedOccurrenceAfterActiveAnchor: true)
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    let lists = try await provider.fetchAllLists()

    let itemsByList = try await provider.fetchItemsByList(for: lists)
    let firstListItems = try XCTUnwrap(itemsByList[gateway.firstCalendar.calendarIdentifier])

    XCTAssertEqual(firstListItems.filter { $0.title == "Restored recurring" }.count, 1)
  }

  func testEventKitProviderPrefersActiveRecurringReminderOverStaleCompletedIdentifier() throws {
    let gateway = ActiveRecurringResolutionGateway()
    let provider = EventKitReminderProjectProvider(gateway: gateway)
    let dueDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(
      from: DateComponents(year: 2026, month: 5, day: 2, hour: 11)
    ))

    _ = try provider.setTaskSchedule(
      for: ReminderTaskReference(
        taskID: UUID(),
        reminderIdentifier: "stale-completed-id",
        reminderExternalIdentifier: "recurring-external"
      ),
      dueDate: dueDate,
      hasExplicitTime: true
    )

    XCTAssertTrue(gateway.savedReminder === gateway.activeReminder)
    XCTAssertNotEqual(gateway.completedReminder.dueDateComponents?.day, 2)
  }
}

@MainActor
private final class BatchImportSnapshotGateway: ReminderGateway {
  let eventStore = EKEventStore()
  let firstCalendar: EKCalendar
  let secondCalendar: EKCalendar
  private let reminders: [EKReminder]
  private let completedReminders: [EKReminder]
  var singleCalendarFetchCount = 0
  var batchCalendarFetchCount = 0
  var calendarLookupCount = 0

  init(
    includeCompletedRecurringReminder: Bool = false,
    includeCompletedOccurrenceWithoutRecurrence: Bool = false,
    includeCompletedOccurrenceAfterActiveAnchor: Bool = false,
    includeCompletedOccurrenceWithoutDueDate: Bool = false
  ) {
    firstCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
    firstCalendar.title = "A"
    secondCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
    secondCalendar.title = "B"

    let firstReminder = EKReminder(eventStore: eventStore)
    firstReminder.calendar = firstCalendar
    firstReminder.title = "First task"
    var primaryReminders = [firstReminder]
    if includeCompletedOccurrenceWithoutRecurrence {
      let activeRecurring = EKReminder(eventStore: eventStore)
      activeRecurring.calendar = firstCalendar
      activeRecurring.title = "Active recurring"
      activeRecurring.dueDateComponents = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        year: 2026,
        month: 5,
        day: 8
      )
      activeRecurring.addRecurrenceRule(
        EKRecurrenceRule(recurrenceWith: .daily, interval: 3, end: nil)
      )
      let completedOccurrence = EKReminder(eventStore: eventStore)
      completedOccurrence.calendar = firstCalendar
      completedOccurrence.title = "Completed occurrence"
      completedOccurrence.dueDateComponents = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        year: 2026,
        month: 5,
        day: 2
      )
      completedOccurrence.isCompleted = true
      completedOccurrence.completionDate = Date(timeIntervalSinceReferenceDate: 700)
      completedOccurrence.notes = activeRecurring.notes
      activeRecurring.title = "Active recurring"
      completedOccurrence.title = "Active recurring"
      primaryReminders.append(activeRecurring)
      primaryReminders.append(completedOccurrence)
    }
    if includeCompletedOccurrenceAfterActiveAnchor {
      let activeRecurring = EKReminder(eventStore: eventStore)
      activeRecurring.calendar = firstCalendar
      activeRecurring.title = "Restored recurring"
      activeRecurring.dueDateComponents = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        year: 2026,
        month: 5,
        day: 2,
        hour: 9,
        minute: 45
      )
      activeRecurring.addRecurrenceRule(
        EKRecurrenceRule(recurrenceWith: .daily, interval: 3, end: nil)
      )
      let completedOccurrence = EKReminder(eventStore: eventStore)
      completedOccurrence.calendar = firstCalendar
      completedOccurrence.title = "Restored recurring"
      completedOccurrence.dueDateComponents = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        year: 2026,
        month: 5,
        day: 2,
        hour: 12
      )
      completedOccurrence.isCompleted = true
      completedOccurrence.completionDate = Date(timeIntervalSinceReferenceDate: 700)
      primaryReminders.append(activeRecurring)
      primaryReminders.append(completedOccurrence)
    }
    if includeCompletedOccurrenceWithoutDueDate {
      let activeRecurring = EKReminder(eventStore: eventStore)
      activeRecurring.calendar = firstCalendar
      activeRecurring.title = "Due-less recurring"
      activeRecurring.dueDateComponents = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        year: 2026,
        month: 5,
        day: 5,
        hour: 9,
        minute: 30
      )
      activeRecurring.addRecurrenceRule(
        EKRecurrenceRule(recurrenceWith: .daily, interval: 3, end: nil)
      )
      let completedOccurrence = EKReminder(eventStore: eventStore)
      completedOccurrence.calendar = firstCalendar
      completedOccurrence.title = activeRecurring.title
      completedOccurrence.isCompleted = true
      completedOccurrence.completionDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 5, day: 2, hour: 9, minute: 30)
      )
      completedOccurrence.notes = activeRecurring.notes
      primaryReminders.append(activeRecurring)
      primaryReminders.append(completedOccurrence)
    }
    let secondReminder = EKReminder(eventStore: eventStore)
    secondReminder.calendar = secondCalendar
    secondReminder.title = "Second task"
    reminders = primaryReminders + [secondReminder]

    if includeCompletedRecurringReminder {
      let completedReminder = EKReminder(eventStore: eventStore)
      completedReminder.calendar = firstCalendar
      completedReminder.title = "Completed recurring"
      completedReminder.dueDateComponents = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        year: 2026,
        month: 4,
        day: 30,
        hour: 12,
        minute: 0
      )
      completedReminder.isCompleted = true
      completedReminder.completionDate = Date(timeIntervalSince1970: 1_777_536_000)
      completedReminder.addRecurrenceRule(
        EKRecurrenceRule(recurrenceWith: .daily, interval: 8, end: nil)
      )
      completedReminders = [completedReminder]
    } else {
      completedReminders = []
    }
  }

  func requestAccess() async throws -> Bool { true }

  func fetchAllCalendars() async throws -> [EKCalendar] {
    [firstCalendar, secondCalendar]
  }

  func fetchReminders(in calendar: EKCalendar, scope: ReminderFetchScope) async throws -> [EKReminder] {
    _ = calendar
    _ = scope
    singleCalendarFetchCount += 1
    return []
  }

  func fetchReminders(in calendars: [EKCalendar], scope: ReminderFetchScope) async throws -> [EKReminder] {
    _ = calendars
    batchCalendarFetchCount += 1
    switch scope {
    case .completedByCompletionDate:
      return completedReminders
    case .all, .incompleteOnly:
      return reminders
    }
  }

  func defaultCalendarIdentifierForNewReminders() -> String? { nil }

  func calendar(withIdentifier identifier: String) -> EKCalendar? {
    calendarLookupCount += 1
    return [firstCalendar, secondCalendar].first { $0.calendarIdentifier == identifier }
  }

  func reminder(withIdentifier identifier: String) -> EKReminder? {
    reminders.first { $0.calendarItemIdentifier == identifier }
  }

  func reminders(withExternalIdentifier externalIdentifier: String) -> [EKReminder] {
    _ = externalIdentifier
    return []
  }

  func lastModifiedDate(for reminder: EKReminder) -> Date? {
    _ = reminder
    return nil
  }

  func makeReminder(in calendar: EKCalendar) -> EKReminder {
    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = calendar
    return reminder
  }

  func createCalendar(title: String) throws -> EKCalendar {
    _ = title
    throw BatchImportSnapshotGatewayError.unexpectedCall
  }

  func save(_ reminder: EKReminder) throws {
    _ = reminder
  }

  func remove(_ reminder: EKReminder) throws {
    _ = reminder
  }

  func save(_ calendar: EKCalendar) throws {
    _ = calendar
  }

  func remove(_ calendar: EKCalendar) throws {
    _ = calendar
  }
}

private enum BatchImportSnapshotGatewayError: Error {
  case unexpectedCall
}

@MainActor
private final class ActiveRecurringResolutionGateway: ReminderGateway {
  let eventStore = EKEventStore()
  let calendar: EKCalendar
  let activeReminder: EKReminder
  let completedReminder: EKReminder
  var savedReminder: EKReminder?

  init() {
    calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = "A"

    activeReminder = EKReminder(eventStore: eventStore)
    activeReminder.calendar = calendar
    activeReminder.title = "Recurring"
    activeReminder.isCompleted = false

    completedReminder = EKReminder(eventStore: eventStore)
    completedReminder.calendar = calendar
    completedReminder.title = "Recurring"
    completedReminder.isCompleted = true
    completedReminder.dueDateComponents = DateComponents(
      calendar: Calendar(identifier: .gregorian),
      year: 2026,
      month: 5,
      day: 5
    )
  }

  func requestAccess() async throws -> Bool { true }
  func fetchAllCalendars() async throws -> [EKCalendar] { [calendar] }
  func fetchReminders(in calendar: EKCalendar, scope: ReminderFetchScope) async throws -> [EKReminder] {
    _ = calendar
    _ = scope
    return [activeReminder, completedReminder]
  }
  func defaultCalendarIdentifierForNewReminders() -> String? { calendar.calendarIdentifier }
  func calendar(withIdentifier identifier: String) -> EKCalendar? {
    identifier == calendar.calendarIdentifier ? calendar : nil
  }
  func reminder(withIdentifier identifier: String) -> EKReminder? {
    identifier == "stale-completed-id" ? completedReminder : nil
  }
  func reminders(withExternalIdentifier externalIdentifier: String) -> [EKReminder] {
    externalIdentifier == "recurring-external" ? [completedReminder, activeReminder] : []
  }
  func lastModifiedDate(for reminder: EKReminder) -> Date? {
    _ = reminder
    return Date(timeIntervalSinceReferenceDate: 600)
  }
  func makeReminder(in calendar: EKCalendar) -> EKReminder {
    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = calendar
    return reminder
  }
  func createCalendar(title: String) throws -> EKCalendar {
    _ = title
    return calendar
  }
  func save(_ reminder: EKReminder) throws {
    savedReminder = reminder
  }
  func remove(_ reminder: EKReminder) throws {
    _ = reminder
  }
  func save(_ calendar: EKCalendar) throws {
    _ = calendar
  }
  func remove(_ calendar: EKCalendar) throws {
    _ = calendar
  }
}
