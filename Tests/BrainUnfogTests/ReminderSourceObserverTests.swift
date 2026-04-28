@preconcurrency import EventKit
import XCTest
@testable import BrainUnfog

@MainActor
final class ReminderSourceObserverTests: XCTestCase {
  func testEventStoreChangeSchedulesImmediateAndDelayedRefresh() async throws {
    let gateway = ObserverTestReminderGateway()
    var invalidationReasons: [SyncReason] = []
    let observer = ReminderSourceObserver(
      gateway: gateway,
      invalidateSource: { reason in
        invalidationReasons.append(reason)
        return true
      },
      handleExternalOwnerChange: { _ in true },
      eventDebounceDelay: .milliseconds(1),
      eventFollowUpDelay: .milliseconds(5),
      authorizationStatusProvider: { .fullAccess }
    )

    await observer.startObserving()
    NotificationCenter.default.post(name: .EKEventStoreChanged, object: gateway.eventStore)
    try await Task.sleep(for: .milliseconds(60))
    observer.stop()

    XCTAssertEqual(invalidationReasons, [.eventStoreChanged, .eventStoreChanged])
  }

  func testGlobalEventStoreChangeSchedulesImmediateAndDelayedRefresh() async throws {
    let gateway = ObserverTestReminderGateway()
    var invalidationReasons: [SyncReason] = []
    let observer = ReminderSourceObserver(
      gateway: gateway,
      invalidateSource: { reason in
        invalidationReasons.append(reason)
        return true
      },
      handleExternalOwnerChange: { _ in true },
      eventDebounceDelay: .milliseconds(1),
      eventFollowUpDelay: .milliseconds(5),
      authorizationStatusProvider: { .fullAccess }
    )

    await observer.startObserving()
    NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
    try await Task.sleep(for: .milliseconds(60))
    observer.stop()

    XCTAssertEqual(invalidationReasons, [.eventStoreChanged, .eventStoreChanged])
  }

  func testPeriodicPollingRefreshesWhenEventStoreNotificationIsMissing() async throws {
    let gateway = ObserverTestReminderGateway()
    var invalidationReasons: [SyncReason] = []
    let observer = ReminderSourceObserver(
      gateway: gateway,
      invalidateSource: { reason in
        invalidationReasons.append(reason)
        return true
      },
      handleExternalOwnerChange: { _ in true },
      eventDebounceDelay: .milliseconds(1),
      eventFollowUpDelay: .milliseconds(5),
      pollingInterval: .milliseconds(5),
      authorizationStatusProvider: { .fullAccess }
    )

    await observer.startObserving()
    try await Task.sleep(for: .milliseconds(40))
    observer.stop()

    XCTAssertTrue(invalidationReasons.contains(.periodic))
  }
}

@MainActor
private final class ObserverTestReminderGateway: ReminderGateway {
  let eventStore = EKEventStore()

  func requestAccess() async throws -> Bool { true }
  func fetchAllCalendars() async throws -> [EKCalendar] { [] }
  func fetchReminders(in calendar: EKCalendar, scope: ReminderFetchScope) async throws -> [EKReminder] {
    _ = calendar
    _ = scope
    return []
  }
  func defaultCalendarIdentifierForNewReminders() -> String? { nil }
  func calendar(withIdentifier identifier: String) -> EKCalendar? {
    _ = identifier
    return nil
  }
  func reminder(withIdentifier identifier: String) -> EKReminder? {
    _ = identifier
    return nil
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
    throw ObserverTestReminderGatewayError.unexpectedCall
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

private enum ObserverTestReminderGatewayError: Error {
  case unexpectedCall
}
