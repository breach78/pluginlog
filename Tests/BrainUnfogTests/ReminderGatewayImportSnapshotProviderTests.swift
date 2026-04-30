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
    XCTAssertEqual(gateway.batchCalendarFetchCount, 2)
    XCTAssertEqual(itemsByList[gateway.firstCalendar.calendarIdentifier]?.map(\.title), ["First task"])
    XCTAssertEqual(itemsByList[gateway.secondCalendar.calendarIdentifier]?.map(\.title), ["Second task"])
  }

  func testFetchAllBatchReusesFetchedCalendarsWithoutIdentifierLookups() async throws {
    let gateway = BatchImportSnapshotGateway()
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)

    let batch = try await provider.fetchAllBatch()

    XCTAssertEqual(gateway.calendarLookupCount, 0)
    XCTAssertEqual(gateway.singleCalendarFetchCount, 0)
    XCTAssertEqual(gateway.batchCalendarFetchCount, 2)
    XCTAssertEqual(batch.lists.map(\.title), ["A", "B"])
    XCTAssertEqual(batch.itemsByListIdentifier[gateway.firstCalendar.calendarIdentifier]?.map(\.title), ["First task"])
  }

  func testFetchItemsByListIncludesCompletedRecurringRemindersWithOccurrenceIdentity() async throws {
    let gateway = BatchImportSnapshotGateway(includeCompletedRecurringReminder: true)
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    let lists = try await provider.fetchAllLists()

    let itemsByList = try await provider.fetchItemsByList(for: lists)
    let firstListItems = try XCTUnwrap(itemsByList[gateway.firstCalendar.calendarIdentifier])
    let completed = try XCTUnwrap(firstListItems.first { $0.title == "Completed recurring" })

    XCTAssertEqual(firstListItems.map(\.title), ["First task", "Completed recurring"])
    XCTAssertTrue(completed.isCompleted)
    XCTAssertEqual(completed.recurrenceRuleRaw, "daily|8")
    XCTAssertTrue(completed.externalIdentifier?.contains("::completed::2026-04-30 12:00") == true)
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

  init(includeCompletedRecurringReminder: Bool = false) {
    firstCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
    firstCalendar.title = "A"
    secondCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
    secondCalendar.title = "B"

    let firstReminder = EKReminder(eventStore: eventStore)
    firstReminder.calendar = firstCalendar
    firstReminder.title = "First task"
    let secondReminder = EKReminder(eventStore: eventStore)
    secondReminder.calendar = secondCalendar
    secondReminder.title = "Second task"
    reminders = [firstReminder, secondReminder]

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
