import AppKit
import Combine
@preconcurrency import EventKit
import Foundation

struct ScheduleCalendarSource: Identifiable, Hashable {
  let id: String
  let title: String
  let colorHex: String?
  let isVisible: Bool
  let isBackgroundOnly: Bool
}

struct ScheduleCalendarEvent: Identifiable, Hashable, Sendable {
  let id: String
  let eventIdentifier: String?
  let externalIdentifier: String?
  let occurrenceDate: Date?
  let calendarIdentifier: String
  let calendarTitle: String
  let calendarColorHex: String?
  let title: String
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
  let isRecurring: Bool
  let isDetached: Bool
  let canEditTiming: Bool
  let editTimingRestrictionReason: String?

  var revealIdentifier: String? {
    if let externalIdentifier, !externalIdentifier.isEmpty {
      return externalIdentifier
    }
    if let eventIdentifier, !eventIdentifier.isEmpty {
      return eventIdentifier
    }
    return nil
  }
}

struct DeletedScheduleCalendarEventSnapshot {
  let calendarIdentifier: String
  let title: String
  let notes: String?
  let location: String?
  let url: URL?
  let timeZone: TimeZone?
  let availability: EKEventAvailability
  let structuredLocation: EKStructuredLocation?
  let alarms: [EKAlarm]
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
  let recurrenceRules: [EKRecurrenceRule]
  let scope: ScheduleCalendarRecurringEditScope
  let wasRecurring: Bool
}

extension DeletedScheduleCalendarEventSnapshot: @unchecked Sendable {}

enum ScheduleCalendarRecurringEditScope: String, Identifiable, Sendable {
  case thisEvent
  case futureEvents

  var id: String { rawValue }

  var title: String {
    switch self {
    case .thisEvent:
      return "이 일정만"
    case .futureEvents:
      return "이후 반복 일정"
    }
  }

  var eventKitSpan: EKSpan {
    switch self {
    case .thisEvent:
      return .thisEvent
    case .futureEvents:
      return .futureEvents
    }
  }
}

enum ScheduleCalendarEditError: LocalizedError, Identifiable {
  case eventNotFound
  case readOnlyCalendar(String?)
  case invitedEvent
  case unsupportedMultiDay
  case unsupportedBirthdayEvent
  case invalidTarget
  case saveFailed(String)
  case removeFailed(String)

  var id: String { errorDescription ?? UUID().uuidString }

  var errorDescription: String? {
    switch self {
    case .eventNotFound:
      return "원본 캘린더 이벤트를 찾지 못했습니다."
    case .readOnlyCalendar(let reason):
      return reason ?? "이 캘린더 이벤트는 수정할 수 없습니다."
    case .invitedEvent:
      return "초대되었거나 참석자가 있는 일정은 앱에서 시간 변경을 지원하지 않습니다."
    case .unsupportedMultiDay:
      return "여러 날에 걸친 일정은 아직 앱에서 시간 변경을 지원하지 않습니다."
    case .unsupportedBirthdayEvent:
      return "생일 일정은 앱에서 수정하지 않습니다."
    case .invalidTarget:
      return "이동할 시간 정보를 계산하지 못했습니다."
    case .saveFailed(let message):
      return message
    case .removeFailed(let message):
      return message
    }
  }
}

private struct ScheduleTimingEditability {
  let canEditTiming: Bool
  let restrictionReason: String?
}

private struct ScheduleResolvedTimingTarget {
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
}

@MainActor
protocol ScheduleCalendarMirrorFetching: AnyObject {
  var calendars: [ScheduleCalendarSource] { get }
  var events: [ScheduleCalendarEvent] { get }
  var visibleEvents: [ScheduleCalendarEvent] { get }
  var calendarsSignature: Int { get }
  var visibleEventsSignature: Int { get }
  var accessDenied: Bool { get }

  func filteredEvents() -> [ScheduleCalendarEvent]
  func isCalendarVisible(_ calendarIdentifier: String) -> Bool
  func isCalendarBackgroundOnly(_ calendarIdentifier: String) -> Bool
  func toggleCalendarVisibility(_ calendarIdentifier: String)
  func toggleCalendarBackgroundOnly(_ calendarIdentifier: String)
  func foregroundVisibleEvents() -> [ScheduleCalendarEvent]
  func backgroundVisibleEvents() -> [ScheduleCalendarEvent]
  func refresh(visibleRange: ClosedRange<Date>) async
  func refresh(visibleRange: ClosedRange<Date>, force: Bool) async
}

@MainActor
protocol ScheduleCalendarCapabilityProviding: AnyObject {
  func reveal(_ event: ScheduleCalendarEvent)
  func applyTimingChange(
    to event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent
  func delete(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> DeletedScheduleCalendarEventSnapshot
  func restoreDeletedEvent(_ snapshot: DeletedScheduleCalendarEventSnapshot) async throws
    -> ScheduleCalendarEvent
}

@MainActor
protocol ScheduleCalendarServicing: AnyObject, ScheduleCalendarMirrorFetching,
  ScheduleCalendarCapabilityProviding
{
  var overlayProjection: ScheduleCalendarOverlayProjection { get }
  var overlayProjectionPublisher: AnyPublisher<ScheduleCalendarOverlayProjection, Never> { get }
  var ownedEventInvalidationPublisher: AnyPublisher<[String], Never> { get }
  func requestCalendarAccessOnceIfNeeded() async -> Bool
  func applyOwnerFieldWrite(_ write: CalendarEventFieldsWrite) async throws -> ScheduleCalendarEvent
  func ensureOwnedCalendar() async throws -> OwnedScheduleCalendarDescriptor
  func resolveOwnedEvent(
    externalIdentifier: String,
    calendarIdentifier: String?
  ) async -> ScheduleCalendarEvent?
  func upsertOwnedEvent(
    _ request: OwnedScheduleCalendarEventUpsertRequest,
    calendarIdentifier: String
  ) async throws -> ScheduleCalendarEvent
  func removeOwnedEvent(
    externalIdentifier: String,
    calendarIdentifier: String
  ) async throws -> Bool
  func resolveEvent(ownerID: String) async -> ScheduleCalendarEvent?
}

enum ScheduleCalendarAccessPromptPolicy {
  static let promptAttemptedKey = "schedule.calendarAccessPromptAttempted"

  static func shouldRequestAccess(
    authorizationStatus: EKAuthorizationStatus,
    promptAttempted: Bool
  ) -> Bool {
    switch authorizationStatus {
    case .notDetermined:
      return !promptAttempted
    case .fullAccess, .authorized, .writeOnly, .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  static func hasStalePromptAttempt(
    authorizationStatus: EKAuthorizationStatus,
    promptAttempted: Bool
  ) -> Bool {
    _ = authorizationStatus
    _ = promptAttempted
    return false
  }

  static func shouldPersistPromptAttempt(after authorizationStatus: EKAuthorizationStatus) -> Bool {
    switch authorizationStatus {
    case .notDetermined, .fullAccess, .authorized, .writeOnly, .denied, .restricted:
      return true
    @unknown default:
      return false
    }
  }
}

private struct ScheduleCalendarProjectionStateSnapshot {
  let calendars: [ScheduleCalendarSource]
  let events: [ScheduleCalendarEvent]
  let visibleEvents: [ScheduleCalendarEvent]
  let calendarsSignature: Int
  let visibleEventsSignature: Int
  let accessDenied: Bool

  static let empty = ScheduleCalendarProjectionStateSnapshot(
    calendars: [],
    events: [],
    visibleEvents: [],
    calendarsSignature: 0,
    visibleEventsSignature: 0,
    accessDenied: false
  )

  var overlayProjection: ScheduleCalendarOverlayProjection {
    let backgroundCalendarIdentifiers = Set(
      calendars
        .filter(\.isBackgroundOnly)
        .map(\.id)
    )
    return ScheduleCalendarOverlayProjection(
      calendarSources: calendars,
      foregroundEvents: visibleEvents.filter { event in
        !backgroundCalendarIdentifiers.contains(event.calendarIdentifier)
      },
      backgroundEvents: visibleEvents.filter { event in
        backgroundCalendarIdentifiers.contains(event.calendarIdentifier)
      },
      calendarsSignature: calendarsSignature,
      visibleEventsSignature: visibleEventsSignature,
      accessDenied: accessDenied
    )
  }
}

@MainActor
private final class ScheduleCalendarProjectionState {
  private static let visibleCalendarIdentifiersKey = "schedule.visibleCalendarIdentifiers"
  private static let backgroundCalendarIdentifiersKey = "schedule.backgroundCalendarIdentifiers"

  private let userDefaults: UserDefaults
  private var visibleCalendarIdentifiers: Set<String>
  private var backgroundCalendarIdentifiers: Set<String>
  private(set) var snapshot: ScheduleCalendarProjectionStateSnapshot = .empty

  init(userDefaults: UserDefaults) {
    self.userDefaults = userDefaults
    self.visibleCalendarIdentifiers = Set(
      userDefaults.stringArray(forKey: Self.visibleCalendarIdentifiersKey) ?? []
    )
    self.backgroundCalendarIdentifiers = Set(
      userDefaults.stringArray(forKey: Self.backgroundCalendarIdentifiersKey) ?? []
    )
  }

  func filteredEvents() -> [ScheduleCalendarEvent] {
    snapshot.visibleEvents
  }

  func isCalendarVisible(_ calendarIdentifier: String) -> Bool {
    visibleCalendarIdentifiers.contains(calendarIdentifier)
  }

  func isCalendarBackgroundOnly(_ calendarIdentifier: String) -> Bool {
    backgroundCalendarIdentifiers.contains(calendarIdentifier)
  }

  func toggleCalendarVisibility(_ calendarIdentifier: String, eventCalendars: [EKCalendar]) {
    if visibleCalendarIdentifiers.contains(calendarIdentifier) {
      visibleCalendarIdentifiers.remove(calendarIdentifier)
    } else {
      visibleCalendarIdentifiers.insert(calendarIdentifier)
    }
    persistVisibleCalendarIdentifiers()
    snapshot = makeSnapshot(
      eventCalendars: eventCalendars,
      events: snapshot.events,
      accessDenied: snapshot.accessDenied
    )
  }

  func toggleCalendarBackgroundOnly(_ calendarIdentifier: String, eventCalendars: [EKCalendar]) {
    if backgroundCalendarIdentifiers.contains(calendarIdentifier) {
      backgroundCalendarIdentifiers.remove(calendarIdentifier)
    } else {
      backgroundCalendarIdentifiers.insert(calendarIdentifier)
    }
    persistBackgroundCalendarIdentifiers()
    snapshot = makeSnapshot(
      eventCalendars: eventCalendars,
      events: snapshot.events,
      accessDenied: snapshot.accessDenied
    )
  }

  func applyAccessDenied() {
    snapshot = ScheduleCalendarProjectionStateSnapshot(
      calendars: [],
      events: [],
      visibleEvents: [],
      calendarsSignature: 0,
      visibleEventsSignature: 0,
      accessDenied: true
    )
  }

  func applyLoadedCalendars(
    _ eventCalendars: [EKCalendar],
    events: [ScheduleCalendarEvent]
  ) {
    snapshot = makeSnapshot(
      eventCalendars: eventCalendars,
      events: events,
      accessDenied: false
    )
  }

  private func makeSnapshot(
    eventCalendars: [EKCalendar],
    events: [ScheduleCalendarEvent],
    accessDenied: Bool
  ) -> ScheduleCalendarProjectionStateSnapshot {
    let availableIdentifiers = Set(eventCalendars.map(\.calendarIdentifier))
    visibleCalendarIdentifiers = visibleCalendarIdentifiers.intersection(availableIdentifiers)
    backgroundCalendarIdentifiers = backgroundCalendarIdentifiers.intersection(availableIdentifiers)
    if visibleCalendarIdentifiers.isEmpty {
      visibleCalendarIdentifiers = availableIdentifiers
      persistVisibleCalendarIdentifiers()
    }
    persistBackgroundCalendarIdentifiers()

    let calendars = eventCalendars.map { calendar in
      ScheduleCalendarSource(
        id: calendar.calendarIdentifier,
        title: calendar.title,
        colorHex: ColorHexCodec.hexString(from: calendar.color),
        isVisible: visibleCalendarIdentifiers.contains(calendar.calendarIdentifier),
        isBackgroundOnly: backgroundCalendarIdentifiers.contains(calendar.calendarIdentifier)
      )
    }
    let visibleEvents = events.filter { visibleCalendarIdentifiers.contains($0.calendarIdentifier) }

    var visibleEventsHasher = Hasher()
    for event in visibleEvents {
      visibleEventsHasher.combine(event)
      visibleEventsHasher.combine(backgroundCalendarIdentifiers.contains(event.calendarIdentifier))
    }

    return ScheduleCalendarProjectionStateSnapshot(
      calendars: calendars,
      events: events,
      visibleEvents: visibleEvents,
      calendarsSignature: signature(for: calendars),
      visibleEventsSignature: visibleEventsHasher.finalize(),
      accessDenied: accessDenied
    )
  }

  private func persistVisibleCalendarIdentifiers() {
    userDefaults.set(
      Array(visibleCalendarIdentifiers).sorted(),
      forKey: Self.visibleCalendarIdentifiersKey
    )
  }

  private func persistBackgroundCalendarIdentifiers() {
    userDefaults.set(
      Array(backgroundCalendarIdentifiers).sorted(),
      forKey: Self.backgroundCalendarIdentifiersKey
    )
  }

  private func signature<T: Hashable>(for items: [T]) -> Int {
    var hasher = Hasher()
    for item in items {
      hasher.combine(item)
    }
    return hasher.finalize()
  }
}

@MainActor
private protocol ScheduleCalendarCapabilitySupporting: ScheduleCalendarMirrorFetching {
  var eventStoreForCapabilities: EKEventStore { get }

  func reloadCurrentRange(force: Bool) async
  func captureOwnedEventInvalidationBaseline()
  func resolvedEvent(for event: ScheduleCalendarEvent) throws -> EKEvent
  func timingEditability(
    for event: EKEvent,
    calendar: Calendar
  ) -> ScheduleTimingEditability
  func resolvedTimingTarget(
    for event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview
  ) throws -> ScheduleResolvedTimingTarget
  func moveRecurringOccurrenceAsStandalone(
    _ event: EKEvent,
    to target: ScheduleResolvedTimingTarget
  ) throws -> EKEvent
  func matchingVisibleEvent(for event: EKEvent) -> ScheduleCalendarEvent?
  func scheduleEvent(from event: EKEvent) -> ScheduleCalendarEvent?
  func appleScriptEscaped(_ value: String) -> String
}

@MainActor
private final class DefaultScheduleCalendarCapabilityService: ScheduleCalendarCapabilityProviding {
  private unowned let support: any ScheduleCalendarCapabilitySupporting
  private let documentOpener: any PlatformDocumentOpening

  init(
    support: any ScheduleCalendarCapabilitySupporting,
    documentOpener: any PlatformDocumentOpening = ApplePlatformDocumentOpener.shared
  ) {
    self.support = support
    self.documentOpener = documentOpener
  }

  func reveal(_ event: ScheduleCalendarEvent) {
    guard let revealIdentifier = event.revealIdentifier else {
      try? documentOpener.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
      return
    }

    let calendarName = support.appleScriptEscaped(event.calendarTitle)
    let escapedIdentifier = support.appleScriptEscaped(revealIdentifier)
    let script = """
    tell application "Calendar"
      activate
      try
        tell first calendar whose name is "\(calendarName)"
          show (first event whose uid is "\(escapedIdentifier)")
        end tell
      end try
    end tell
    """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]

    do {
      try process.run()
    } catch {
      AppLogger.sync.error(
        "reveal calendar event failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  func applyTimingChange(
    to event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    let target = try support.resolvedTimingTarget(for: event, preview: preview)
    let liveEvent = try support.resolvedEvent(for: event)
    let editability = support.timingEditability(for: liveEvent, calendar: .autoupdatingCurrent)
    guard editability.canEditTiming else {
      throw ScheduleCalendarEditError.readOnlyCalendar(editability.restrictionReason)
    }

    let eventStore = support.eventStoreForCapabilities
    let savedEvent: EKEvent
    do {
      if scope == .thisEvent, event.isRecurring {
        savedEvent = try support.moveRecurringOccurrenceAsStandalone(liveEvent, to: target)
      } else {
        liveEvent.startDate = target.startDate
        liveEvent.endDate = target.endDate
        liveEvent.isAllDay = target.isAllDay
        try eventStore.save(liveEvent, span: scope.eventKitSpan)
        savedEvent = liveEvent
      }
    } catch let error as ScheduleCalendarEditError {
      throw error
    } catch {
      AppLogger.sync.error(
        "calendar event save failed: \(error.localizedDescription, privacy: .public)"
      )
      throw ScheduleCalendarEditError.saveFailed(error.localizedDescription)
    }

    await support.reloadCurrentRange(force: true)
    support.captureOwnedEventInvalidationBaseline()
    if let updatedEvent = support.matchingVisibleEvent(for: savedEvent) ?? support.scheduleEvent(from: savedEvent) {
      return updatedEvent
    }
    throw ScheduleCalendarEditError.eventNotFound
  }

  func delete(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> DeletedScheduleCalendarEventSnapshot {
    let liveEvent = try support.resolvedEvent(for: event)
    let editability = support.timingEditability(for: liveEvent, calendar: .autoupdatingCurrent)
    guard editability.canEditTiming else {
      throw ScheduleCalendarEditError.readOnlyCalendar(editability.restrictionReason)
    }

    let snapshot = DeletedScheduleCalendarEventSnapshot(
      calendarIdentifier: liveEvent.calendar.calendarIdentifier,
      title: liveEvent.title ?? "",
      notes: liveEvent.notes,
      location: liveEvent.location,
      url: liveEvent.url,
      timeZone: liveEvent.timeZone,
      availability: liveEvent.availability,
      structuredLocation: liveEvent.structuredLocation?.copy() as? EKStructuredLocation,
      alarms: liveEvent.alarms?.compactMap { $0.copy() as? EKAlarm } ?? [],
      startDate: liveEvent.startDate,
      endDate: liveEvent.endDate,
      isAllDay: liveEvent.isAllDay,
      recurrenceRules: liveEvent.recurrenceRules ?? [],
      scope: scope,
      wasRecurring: event.isRecurring || liveEvent.hasRecurrenceRules
    )

    do {
      try support.eventStoreForCapabilities.remove(liveEvent, span: scope.eventKitSpan)
    } catch {
      AppLogger.sync.error(
        "calendar event remove failed: \(error.localizedDescription, privacy: .public)"
      )
      throw ScheduleCalendarEditError.removeFailed(error.localizedDescription)
    }

    await support.reloadCurrentRange(force: true)
    support.captureOwnedEventInvalidationBaseline()
    return snapshot
  }

  func restoreDeletedEvent(_ snapshot: DeletedScheduleCalendarEventSnapshot) async throws
    -> ScheduleCalendarEvent
  {
    let eventStore = support.eventStoreForCapabilities
    guard let calendar = eventStore.calendar(withIdentifier: snapshot.calendarIdentifier) else {
      throw ScheduleCalendarEditError.eventNotFound
    }

    let restored = EKEvent(eventStore: eventStore)
    restored.calendar = calendar
    restored.title = snapshot.title
    restored.notes = snapshot.notes
    restored.location = snapshot.location
    restored.url = snapshot.url
    restored.timeZone = snapshot.timeZone
    restored.availability = snapshot.availability
    restored.structuredLocation = snapshot.structuredLocation?.copy() as? EKStructuredLocation
    restored.alarms = snapshot.alarms.compactMap { $0.copy() as? EKAlarm }
    restored.startDate = snapshot.startDate
    restored.endDate = snapshot.endDate
    restored.isAllDay = snapshot.isAllDay

    if snapshot.scope == .futureEvents, snapshot.wasRecurring {
      restored.recurrenceRules = snapshot.recurrenceRules
    } else {
      restored.recurrenceRules = []
    }

    do {
      try eventStore.save(restored, span: .thisEvent)
    } catch {
      AppLogger.sync.error(
        "calendar deleted event restore failed: \(error.localizedDescription, privacy: .public)"
      )
      throw ScheduleCalendarEditError.saveFailed(error.localizedDescription)
    }

    await support.reloadCurrentRange(force: true)
    support.captureOwnedEventInvalidationBaseline()
    if let updatedEvent = support.matchingVisibleEvent(for: restored) ?? support.scheduleEvent(from: restored) {
      return updatedEvent
    }
    throw ScheduleCalendarEditError.eventNotFound
  }
}

@MainActor
final class ScheduleCalendarStore: ObservableObject, ScheduleCalendarServicing,
  ScheduleCalendarCapabilitySupporting
{
  @Published private(set) var calendars: [ScheduleCalendarSource] = []
  @Published private(set) var events: [ScheduleCalendarEvent] = []
  @Published private(set) var visibleEvents: [ScheduleCalendarEvent] = []
  @Published private(set) var calendarsSignature: Int = 0
  @Published private(set) var visibleEventsSignature: Int = 0
  @Published private(set) var accessDenied = false
  @Published private(set) var overlayProjection: ScheduleCalendarOverlayProjection = .empty

  private let eventStore = EKEventStore()
  let userDefaults: UserDefaults
  private let projectionState: ScheduleCalendarProjectionState
  private let ownedEventInvalidationSubject = PassthroughSubject<[String], Never>()
  private var currentFetchRange: ClosedRange<Date>?
  private var hasLoadedCurrentRange = false
  private var lastOwnedCalendarEventsSnapshot: [ScheduleCalendarEvent] = []
  nonisolated(unsafe) private var eventStoreObserver: NSObjectProtocol?
  private var eventStoreChangedTask: Task<Void, Never>?
  private lazy var capabilityService: ScheduleCalendarCapabilityProviding =
    DefaultScheduleCalendarCapabilityService(support: self)

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    self.projectionState = ScheduleCalendarProjectionState(userDefaults: userDefaults)
    registerEventStoreObserver()
    applyProjectionStateSnapshot(projectionState.snapshot)
    captureOwnedEventInvalidationBaseline()
  }

  deinit {
    if let eventStoreObserver {
      NotificationCenter.default.removeObserver(eventStoreObserver)
    }
    eventStoreChangedTask?.cancel()
  }

  var overlayProjectionPublisher: AnyPublisher<ScheduleCalendarOverlayProjection, Never> {
    $overlayProjection.removeDuplicates().eraseToAnyPublisher()
  }

  var ownedEventInvalidationPublisher: AnyPublisher<[String], Never> {
    ownedEventInvalidationSubject.eraseToAnyPublisher()
  }

  func filteredEvents() -> [ScheduleCalendarEvent] {
    projectionState.filteredEvents()
  }

  func isCalendarVisible(_ calendarIdentifier: String) -> Bool {
    projectionState.isCalendarVisible(calendarIdentifier)
  }

  func isCalendarBackgroundOnly(_ calendarIdentifier: String) -> Bool {
    projectionState.isCalendarBackgroundOnly(calendarIdentifier)
  }

  func toggleCalendarVisibility(_ calendarIdentifier: String) {
    projectionState.toggleCalendarVisibility(
      calendarIdentifier,
      eventCalendars: eventStore.calendars(for: .event)
    )
    applyProjectionStateSnapshot(projectionState.snapshot)
  }

  func toggleCalendarBackgroundOnly(_ calendarIdentifier: String) {
    projectionState.toggleCalendarBackgroundOnly(
      calendarIdentifier,
      eventCalendars: eventStore.calendars(for: .event)
    )
    applyProjectionStateSnapshot(projectionState.snapshot)
  }

  func foregroundVisibleEvents() -> [ScheduleCalendarEvent] {
    overlayProjection.foregroundEvents
  }

  func backgroundVisibleEvents() -> [ScheduleCalendarEvent] {
    overlayProjection.backgroundEvents
  }

  func refresh(visibleRange: ClosedRange<Date>) async {
    await refresh(visibleRange: visibleRange, force: false)
  }

  func refresh(visibleRange: ClosedRange<Date>, force: Bool) async {
    let calendar = Calendar.autoupdatingCurrent
    let visibleStartDay = calendar.startOfDay(for: visibleRange.lowerBound)
    let visibleEndDay = calendar.startOfDay(for: visibleRange.upperBound)
    let startDay = visibleStartDay
    let endDay = calendar.date(byAdding: .day, value: 1, to: visibleEndDay) ?? visibleEndDay
    let range = startDay...endDay
    await reload(range: range, force: force)
  }

  func reveal(_ event: ScheduleCalendarEvent) {
    capabilityService.reveal(event)
  }

  func applyTimingChange(
    to event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    try await capabilityService.applyTimingChange(to: event, preview: preview, scope: scope)
  }

  func applyOwnerFieldWrite(
    _ write: CalendarEventFieldsWrite
  ) async throws -> ScheduleCalendarEvent {
    switch write.mutation {
    case let .timing(preview, scope):
      return try await applyTimingChange(
        to: write.event,
        preview: preview,
        scope: scope
      )
    }
  }

  fileprivate func moveRecurringOccurrenceAsStandalone(
    _ event: EKEvent,
    to target: ScheduleResolvedTimingTarget
  ) throws -> EKEvent {
    let replacement = EKEvent(eventStore: eventStore)
    replacement.calendar = event.calendar
    replacement.title = event.title
    replacement.notes = event.notes
    replacement.location = event.location
    replacement.url = event.url
    replacement.timeZone = event.timeZone
    replacement.availability = event.availability
    replacement.structuredLocation = event.structuredLocation?.copy() as? EKStructuredLocation
    replacement.alarms = event.alarms?.compactMap { $0.copy() as? EKAlarm }
    replacement.startDate = target.startDate
    replacement.endDate = target.endDate
    replacement.isAllDay = target.isAllDay

    do {
      try eventStore.save(replacement, span: .thisEvent, commit: false)
      try eventStore.remove(event, span: .thisEvent, commit: false)
      try eventStore.commit()
      return replacement
    } catch {
      eventStore.reset()
      AppLogger.sync.error(
        "calendar recurring occurrence detach failed: \(error.localizedDescription, privacy: .public)"
      )
      throw ScheduleCalendarEditError.saveFailed(error.localizedDescription)
    }
  }

  func delete(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> DeletedScheduleCalendarEventSnapshot {
    try await capabilityService.delete(event, scope: scope)
  }

  func restoreDeletedEvent(_ snapshot: DeletedScheduleCalendarEventSnapshot) async throws
    -> ScheduleCalendarEvent
  {
    try await capabilityService.restoreDeletedEvent(snapshot)
  }

  @discardableResult
  func requestCalendarAccessOnceIfNeeded() async -> Bool {
    do {
      return try await requestAccessIfNeeded()
    } catch {
      AppLogger.sync.error(
        "calendar access request failed: \(error.localizedDescription, privacy: .public)"
      )
      return false
    }
  }

  var eventStoreForCapabilities: EKEventStore { eventStore }

  func reloadCurrentRange(force: Bool) async {
    guard let currentFetchRange else { return }
    await reload(range: currentFetchRange, force: force)
  }

  private func reload(range: ClosedRange<Date>, force: Bool) async {
    if !force, hasLoadedCurrentRange, isCovered(range, by: currentFetchRange) {
      return
    }

    do {
      let granted = try await requestAccessIfNeeded()
      guard granted else {
        projectionState.applyAccessDenied()
        applyProjectionStateSnapshot(projectionState.snapshot)
        currentFetchRange = nil
        hasLoadedCurrentRange = false
        return
      }
    } catch {
      projectionState.applyAccessDenied()
      applyProjectionStateSnapshot(projectionState.snapshot)
      currentFetchRange = nil
      hasLoadedCurrentRange = false
      AppLogger.sync.error(
        "calendar access request failed: \(error.localizedDescription, privacy: .public)"
      )
      return
    }

    let eventCalendars = eventStore.calendars(for: .event)
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

    let predicate = eventStore.predicateForEvents(
      withStart: range.lowerBound,
      end: range.upperBound,
      calendars: eventCalendars
    )
    let loadedEvents = collapsedRecurringOccurrences(
      from: eventStore.events(matching: predicate)
    )
      .sorted {
        if $0.startDate != $1.startDate {
          return $0.startDate < $1.startDate
        }
        if ($0.endDate ?? $0.startDate) != ($1.endDate ?? $1.startDate) {
          return ($0.endDate ?? $0.startDate) < ($1.endDate ?? $1.startDate)
        }
        if ($0.title ?? "") != ($1.title ?? "") {
          return ($0.title ?? "") < ($1.title ?? "")
        }
        return occurrenceIdentifier(for: $0) < occurrenceIdentifier(for: $1)
      }
      .compactMap(scheduleEvent(from:))
    currentFetchRange = range
    hasLoadedCurrentRange = true
    projectionState.applyLoadedCalendars(eventCalendars, events: loadedEvents)
    applyProjectionStateSnapshot(projectionState.snapshot)
  }

  func occurrenceIdentifier(for event: EKEvent) -> String {
    let occurrenceAnchor = event.occurrenceDate ?? event.startDate ?? .distantPast
    let endAnchor = event.endDate ?? occurrenceAnchor
    let baseIdentifier =
      event.eventIdentifier
      ?? event.calendarItemExternalIdentifier
      ?? event.calendarItemIdentifier
    return [
      event.calendar.calendarIdentifier,
      baseIdentifier,
      String(occurrenceAnchor.timeIntervalSinceReferenceDate),
      String(endAnchor.timeIntervalSinceReferenceDate),
    ]
    .joined(separator: "|")
  }

  func matchingVisibleEvent(for event: EKEvent) -> ScheduleCalendarEvent? {
    let descriptor = scheduleEvent(from: event)
    if let descriptor,
      let matchedByOccurrence = visibleEvents.first(where: { matchesVisibleEvent($0, descriptor: descriptor) })
    {
      return matchedByOccurrence
    }
    if let descriptor, !requiresOccurrenceScopedLookup(for: descriptor) {
      if let eventIdentifier = event.eventIdentifier,
        let matchedByEventIdentifier = visibleEvents.first(where: { $0.eventIdentifier == eventIdentifier })
      {
        return matchedByEventIdentifier
      }
      if let externalIdentifier = event.calendarItemExternalIdentifier,
        let matchedByExternalIdentifier = visibleEvents.first(where: { $0.externalIdentifier == externalIdentifier })
      {
        return matchedByExternalIdentifier
      }
    }
    return nil
  }

  func scheduleEvent(from event: EKEvent) -> ScheduleCalendarEvent? {
    guard let startDate = event.startDate else { return nil }
    let calendar = Calendar.autoupdatingCurrent
    let fallbackEndDate: Date
    if event.isAllDay {
      fallbackEndDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
    } else {
      fallbackEndDate = calendar.date(byAdding: .minute, value: 15, to: startDate) ?? startDate
    }
    let endDate = max(event.endDate ?? fallbackEndDate, fallbackEndDate)
    let editability = timingEditability(for: event, calendar: calendar)

    return ScheduleCalendarEvent(
      id: occurrenceIdentifier(for: event),
      eventIdentifier: event.eventIdentifier,
      externalIdentifier: event.calendarItemExternalIdentifier,
      occurrenceDate: event.occurrenceDate,
      calendarIdentifier: event.calendar.calendarIdentifier,
      calendarTitle: event.calendar.title,
      calendarColorHex: ColorHexCodec.hexString(from: event.calendar.color),
      title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? (event.title ?? "")
        : "Untitled Event",
      startDate: startDate,
      endDate: endDate,
      isAllDay: event.isAllDay,
      isRecurring: event.hasRecurrenceRules && !event.isDetached,
      isDetached: event.isDetached,
      canEditTiming: editability.canEditTiming,
      editTimingRestrictionReason: editability.restrictionReason
    )
  }

  private func collapsedRecurringOccurrences(from events: [EKEvent]) -> [EKEvent] {
    var collapsedByOccurrence: [String: EKEvent] = [:]
    var passthroughEvents: [EKEvent] = []

    for event in events {
      guard let key = recurringOccurrenceDeduplicationKey(for: event) else {
        passthroughEvents.append(event)
        continue
      }

      if let existing = collapsedByOccurrence[key] {
        collapsedByOccurrence[key] = preferredRecurringOccurrence(existing, event)
      } else {
        collapsedByOccurrence[key] = event
      }
    }

    return passthroughEvents + collapsedByOccurrence.values
  }

  private func recurringOccurrenceDeduplicationKey(for event: EKEvent) -> String? {
    guard event.hasRecurrenceRules || event.isDetached || event.occurrenceDate != nil,
      let occurrenceDate = event.occurrenceDate ?? event.startDate
    else {
      return nil
    }

    let seriesIdentifier =
      event.calendarItemExternalIdentifier
      ?? event.calendarItemIdentifier

    return [
      event.calendar.calendarIdentifier,
      seriesIdentifier,
      String(occurrenceDate.timeIntervalSinceReferenceDate),
    ]
    .joined(separator: "|")
  }

  private func preferredRecurringOccurrence(_ lhs: EKEvent, _ rhs: EKEvent) -> EKEvent {
    if lhs.isDetached != rhs.isDetached {
      return lhs.isDetached ? lhs : rhs
    }

    let lhsMoved = hasMovedFromOriginalOccurrence(lhs)
    let rhsMoved = hasMovedFromOriginalOccurrence(rhs)
    if lhsMoved != rhsMoved {
      return lhsMoved ? lhs : rhs
    }

    let lhsLastModified = lhs.lastModifiedDate ?? .distantPast
    let rhsLastModified = rhs.lastModifiedDate ?? .distantPast
    if lhsLastModified != rhsLastModified {
      return lhsLastModified > rhsLastModified ? lhs : rhs
    }

    return lhs
  }

  private func hasMovedFromOriginalOccurrence(_ event: EKEvent) -> Bool {
    guard let startDate = event.startDate,
      let occurrenceDate = event.occurrenceDate
    else {
      return false
    }

    return abs(startDate.timeIntervalSinceReferenceDate - occurrenceDate.timeIntervalSinceReferenceDate)
      >= 1
  }

  fileprivate func resolvedEvent(for event: ScheduleCalendarEvent) throws -> EKEvent {
    if requiresOccurrenceScopedLookup(for: event) {
      if let exactOccurrence = resolvedOccurrenceScopedEvent(for: event) {
        return exactOccurrence
      }
    } else {
      if let eventIdentifier = event.eventIdentifier,
        let candidate = eventStore.event(withIdentifier: eventIdentifier),
        matches(candidate, descriptor: event)
      {
        return candidate
      }

      if let externalIdentifier = event.externalIdentifier {
        let candidateItems = eventStore.calendarItems(withExternalIdentifier: externalIdentifier)
        if let exactMatch = candidateItems
          .compactMap({ $0 as? EKEvent })
          .first(where: { matches($0, descriptor: event) })
        {
          return exactMatch
        }
      }
    }

    if let candidate = findEventInRange(matching: event, range: currentFetchRange) {
      return candidate
    }

    let calendar = Calendar.autoupdatingCurrent
    let fallbackLowerBound = calendar.date(byAdding: .day, value: -30, to: event.startDate) ?? event.startDate
    let fallbackUpperBound = calendar.date(byAdding: .day, value: 30, to: event.endDate) ?? event.endDate
    if let candidate = findEventInRange(matching: event, range: fallbackLowerBound...fallbackUpperBound) {
      return candidate
    }

    throw ScheduleCalendarEditError.eventNotFound
  }

  private func findEventInRange(
    matching descriptor: ScheduleCalendarEvent,
    range: ClosedRange<Date>?
  ) -> EKEvent? {
    guard let range else { return nil }

    let calendars: [EKCalendar]?
    if let calendar = eventStore.calendar(withIdentifier: descriptor.calendarIdentifier) {
      calendars = [calendar]
    } else {
      calendars = nil
    }

    let predicate = eventStore.predicateForEvents(
      withStart: range.lowerBound,
      end: range.upperBound,
      calendars: calendars
    )
    let matchedEvents = eventStore.events(matching: predicate).filter {
      matches($0, descriptor: descriptor)
    }
    if requiresOccurrenceScopedLookup(for: descriptor) {
      return matchedEvents.reduce(Optional<EKEvent>.none) { currentBest, candidate in
        guard let currentBest else { return candidate }
        return preferredRecurringOccurrence(currentBest, candidate)
      }
    }
    return matchedEvents.first
  }

  private func matches(_ event: EKEvent, descriptor: ScheduleCalendarEvent) -> Bool {
    if occurrenceIdentifier(for: event) == descriptor.id {
      return true
    }

    guard event.calendar.calendarIdentifier == descriptor.calendarIdentifier else {
      return false
    }

    if requiresOccurrenceScopedLookup(for: descriptor) {
      return matchesOccurrenceScope(event, descriptor: descriptor)
    }

    if let eventIdentifier = descriptor.eventIdentifier,
      event.eventIdentifier == eventIdentifier
    {
      return true
    }

    guard let externalIdentifier = descriptor.externalIdentifier,
      event.calendarItemExternalIdentifier == externalIdentifier
    else {
      return false
    }

    guard let eventOccurrenceAnchor = event.occurrenceDate ?? event.startDate else {
      return false
    }
    let descriptorOccurrenceAnchor = descriptor.occurrenceDate ?? descriptor.startDate
    return abs(eventOccurrenceAnchor.timeIntervalSinceReferenceDate - descriptorOccurrenceAnchor.timeIntervalSinceReferenceDate) < 1
  }

  private func resolvedOccurrenceScopedEvent(for descriptor: ScheduleCalendarEvent) -> EKEvent? {
    let anchors = [descriptor.occurrenceDate, descriptor.startDate].compactMap { $0 }
    for anchor in anchors {
      let lowerBound = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -7, to: anchor) ?? anchor
      let upperBound = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: anchor) ?? anchor
      if let candidate = findEventInRange(matching: descriptor, range: lowerBound...upperBound) {
        return candidate
      }
    }
    return nil
  }

  private func requiresOccurrenceScopedLookup(for descriptor: ScheduleCalendarEvent) -> Bool {
    descriptor.isRecurring || descriptor.isDetached || descriptor.occurrenceDate != nil
  }

  private func matchesOccurrenceScope(_ event: EKEvent, descriptor: ScheduleCalendarEvent) -> Bool {
    guard let eventOccurrenceAnchor = event.occurrenceDate ?? event.startDate else {
      return false
    }
    let descriptorOccurrenceAnchor = descriptor.occurrenceDate ?? descriptor.startDate
    guard abs(eventOccurrenceAnchor.timeIntervalSinceReferenceDate - descriptorOccurrenceAnchor.timeIntervalSinceReferenceDate) < 1 else {
      return false
    }

    if let externalIdentifier = descriptor.externalIdentifier,
      let eventExternalIdentifier = event.calendarItemExternalIdentifier
    {
      return eventExternalIdentifier == externalIdentifier
    }

    if let eventIdentifier = descriptor.eventIdentifier,
      let candidateIdentifier = event.eventIdentifier
    {
      return candidateIdentifier == eventIdentifier
    }

    guard event.title == descriptor.title else { return false }
    guard let eventStartDate = event.startDate else { return false }
    let sameStart = abs(eventStartDate.timeIntervalSinceReferenceDate - descriptor.startDate.timeIntervalSinceReferenceDate) < 1
    let eventEndDate = event.endDate ?? eventStartDate
    let sameEnd = abs(eventEndDate.timeIntervalSinceReferenceDate - descriptor.endDate.timeIntervalSinceReferenceDate) < 1
    return sameStart && sameEnd
  }

  private func matchesVisibleEvent(_ event: ScheduleCalendarEvent, descriptor: ScheduleCalendarEvent) -> Bool {
    if event.id == descriptor.id {
      return true
    }

    guard event.calendarIdentifier == descriptor.calendarIdentifier else {
      return false
    }

    if requiresOccurrenceScopedLookup(for: descriptor) {
      let eventOccurrenceAnchor = event.occurrenceDate ?? event.startDate
      let descriptorOccurrenceAnchor = descriptor.occurrenceDate ?? descriptor.startDate
      guard abs(eventOccurrenceAnchor.timeIntervalSinceReferenceDate - descriptorOccurrenceAnchor.timeIntervalSinceReferenceDate) < 1 else {
        return false
      }
      if let externalIdentifier = descriptor.externalIdentifier, let eventExternalIdentifier = event.externalIdentifier {
        return eventExternalIdentifier == externalIdentifier
      }
      return true
    }

    if let eventIdentifier = descriptor.eventIdentifier, event.eventIdentifier == eventIdentifier {
      return true
    }
    if let externalIdentifier = descriptor.externalIdentifier, event.externalIdentifier == externalIdentifier {
      return true
    }
    return false
  }

  fileprivate func timingEditability(
    for event: EKEvent,
    calendar: Calendar
  ) -> ScheduleTimingEditability {
    guard event.calendar.allowsContentModifications, !event.calendar.isSubscribed else {
      return ScheduleTimingEditability(
        canEditTiming: false,
        restrictionReason: "읽기 전용 캘린더라서 시간 변경을 할 수 없습니다."
      )
    }

    if event.birthdayContactIdentifier != nil {
      return ScheduleTimingEditability(
        canEditTiming: false,
        restrictionReason: ScheduleCalendarEditError.unsupportedBirthdayEvent.errorDescription
      )
    }

    let attendeeCount = event.attendees?.count ?? 0
    let organizer = event.organizer
    if attendeeCount > 0 || (organizer != nil && organizer?.isCurrentUser == false) {
      return ScheduleTimingEditability(
        canEditTiming: false,
        restrictionReason: ScheduleCalendarEditError.invitedEvent.errorDescription
      )
    }

    guard let startDate = event.startDate, let endDate = event.endDate else {
      return ScheduleTimingEditability(
        canEditTiming: false,
        restrictionReason: ScheduleCalendarEditError.eventNotFound.errorDescription
      )
    }

    let startDay = calendar.startOfDay(for: startDate)
    if event.isAllDay {
      let endDay = calendar.startOfDay(for: endDate)
      let durationDays = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
      guard durationDays == 1 else {
        return ScheduleTimingEditability(
          canEditTiming: false,
          restrictionReason: ScheduleCalendarEditError.unsupportedMultiDay.errorDescription
        )
      }
    } else if !calendar.isDate(startDate, inSameDayAs: endDate) {
      return ScheduleTimingEditability(
        canEditTiming: false,
        restrictionReason: ScheduleCalendarEditError.unsupportedMultiDay.errorDescription
      )
    }

    return ScheduleTimingEditability(canEditTiming: true, restrictionReason: nil)
  }

  fileprivate func resolvedTimingTarget(
    for event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview
  ) throws -> ScheduleResolvedTimingTarget {
    let calendar = Calendar.autoupdatingCurrent
    guard let day = preview.day else {
      throw ScheduleCalendarEditError.invalidTarget
    }

    let normalizedDay = calendar.startOfDay(for: day)
    if let timeMinutes = preview.timeMinutes {
      let components = DateComponents(
        hour: max(0, min(23, timeMinutes / 60)),
        minute: max(0, min(59, timeMinutes % 60))
      )
      guard let startDate = calendar.date(byAdding: components, to: normalizedDay) else {
        throw ScheduleCalendarEditError.invalidTarget
      }
      let durationMinutes =
        max(15, preview.durationMinutes ?? currentDurationMinutes(for: event, calendar: calendar))
      guard let endDate = calendar.date(byAdding: .minute, value: durationMinutes, to: startDate) else {
        throw ScheduleCalendarEditError.invalidTarget
      }
      return ScheduleResolvedTimingTarget(startDate: startDate, endDate: endDate, isAllDay: false)
    }

    guard let endDate = calendar.date(byAdding: .day, value: 1, to: normalizedDay) else {
      throw ScheduleCalendarEditError.invalidTarget
    }
    return ScheduleResolvedTimingTarget(startDate: normalizedDay, endDate: endDate, isAllDay: true)
  }

  private func currentDurationMinutes(
    for event: ScheduleCalendarEvent,
    calendar: Calendar
  ) -> Int {
    if event.isAllDay {
      return 24 * 60
    }
    let duration = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
    return max(15, duration)
  }

  func requestAccessIfNeeded() async throws -> Bool {
    let authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    switch authorizationStatus {
    case .fullAccess, .authorized:
      return true
    case .writeOnly:
      return false
    case .denied, .restricted:
      return false
    case .notDetermined:
      let promptAttemptedKey = ScheduleCalendarAccessPromptPolicy.promptAttemptedKey
      let storedPromptAttempted = userDefaults.bool(forKey: promptAttemptedKey)
      guard ScheduleCalendarAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: authorizationStatus,
        promptAttempted: storedPromptAttempted
      ) else {
        return false
      }
      userDefaults.set(true, forKey: promptAttemptedKey)
      var granted = try await eventStore.requestFullAccessToEvents()
      if !granted && EKEventStore.authorizationStatus(for: .event) == .notDetermined {
        granted = try await requestFullAccessToEventsWithCompletionHandler()
      }
      if ScheduleCalendarAccessPromptPolicy.shouldPersistPromptAttempt(
        after: EKEventStore.authorizationStatus(for: .event)
      ) {
        userDefaults.set(true, forKey: promptAttemptedKey)
      }
      return granted
    @unknown default:
      return false
    }
  }

  private func requestFullAccessToEventsWithCompletionHandler() async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      eventStore.requestFullAccessToEvents { granted, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: granted)
        }
      }
    }
  }

  private func applyProjectionStateSnapshot(_ snapshot: ScheduleCalendarProjectionStateSnapshot) {
    calendars = snapshot.calendars
    events = snapshot.events
    visibleEvents = snapshot.visibleEvents
    calendarsSignature = snapshot.calendarsSignature
    visibleEventsSignature = snapshot.visibleEventsSignature
    accessDenied = snapshot.accessDenied
    overlayProjection = snapshot.overlayProjection
  }

  private func isCovered(_ requestedRange: ClosedRange<Date>, by currentRange: ClosedRange<Date>?) -> Bool {
    guard let currentRange else { return false }
    return currentRange.lowerBound <= requestedRange.lowerBound
      && currentRange.upperBound >= requestedRange.upperBound
  }

  fileprivate func appleScriptEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }

  private func registerEventStoreObserver() {
    eventStoreObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: eventStore,
      queue: nil
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor [weak self] in
        await self?.scheduleOwnedEventInvalidationRefresh()
      }
    }
  }

  private func scheduleOwnedEventInvalidationRefresh() async {
    eventStoreChangedTask?.cancel()
    eventStoreChangedTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard let self, !Task.isCancelled else { return }

      let previousEvents = lastOwnedCalendarEventsSnapshot
      if currentFetchRange != nil {
        await reloadCurrentRange(force: true)
      }
      let currentEvents = ownedCalendarEventsSnapshot()
      lastOwnedCalendarEventsSnapshot = currentEvents
      let ownerIDs = OwnedScheduleCalendarInvalidationPolicy.changedOwnerIDs(
        previousEvents: previousEvents,
        currentEvents: currentEvents,
        ownedCalendarIdentifier: currentOwnedCalendarIdentifier()
      )
      guard !ownerIDs.isEmpty else { return }
      ownedEventInvalidationSubject.send(ownerIDs)
    }
  }

  func captureOwnedEventInvalidationBaseline() {
    lastOwnedCalendarEventsSnapshot = ownedCalendarEventsSnapshot()
  }

  private func ownedCalendarEventsSnapshot() -> [ScheduleCalendarEvent] {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .authorized, .fullAccess:
      break
    default:
      return []
    }

    guard let calendarIdentifier = currentOwnedCalendarIdentifier(),
      let calendar = eventStore.calendar(withIdentifier: calendarIdentifier)
    else {
      return []
    }

    let calendarScope = [calendar]
    let calendarSystem = Calendar(identifier: .gregorian)
    guard
      let lowerBound = calendarSystem.date(from: DateComponents(year: 2000, month: 1, day: 1)),
      let upperBound = calendarSystem.date(from: DateComponents(year: 2100, month: 1, day: 1))
    else {
      return []
    }

    let predicate = eventStore.predicateForEvents(
      withStart: lowerBound,
      end: upperBound,
      calendars: calendarScope
    )
    return collapsedRecurringOccurrences(from: eventStore.events(matching: predicate))
      .filter { $0.calendar.calendarIdentifier == calendarIdentifier }
      .compactMap(scheduleEvent(from:))
      .sorted { lhs, rhs in
        if lhs.startDate != rhs.startDate {
          return lhs.startDate < rhs.startDate
        }
        if lhs.endDate != rhs.endDate {
          return lhs.endDate < rhs.endDate
        }
        return lhs.id < rhs.id
      }
  }
}
