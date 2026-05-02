import AppKit
@preconcurrency import EventKit
import Foundation

struct OwnedScheduleCalendarDescriptor: Equatable, Sendable {
  let calendarIdentifier: String
  let title: String
  let colorHex: String?
}

struct OwnedScheduleCalendarEventUpsertRequest: Equatable, Sendable {
  let externalIdentifier: String?
  let title: String
  let startDate: Date
  let durationMinutes: Int
}

@MainActor
extension ScheduleCalendarStore {
  private static let ownedCalendarIdentifierKey = "schedule.ownedCalendarIdentifier"
  private static let ownedCalendarTitle = "Brain Unfog Schedule"

  func currentOwnedCalendarIdentifier() -> String? {
    normalizedOwnedCalendarValue(
      userDefaults.string(forKey: Self.ownedCalendarIdentifierKey)
    )
  }

  func ensureOwnedCalendar() async throws -> OwnedScheduleCalendarDescriptor {
    guard try await requestAccessIfNeeded() else {
      throw ScheduleCalendarEditError.readOnlyCalendar("캘린더 접근 권한이 없습니다.")
    }

    let calendar = try resolvedOwnedCalendar()
    return OwnedScheduleCalendarDescriptor(
      calendarIdentifier: calendar.calendarIdentifier,
      title: calendar.title,
      colorHex: ColorHexCodec.hexString(from: calendar.color)
    )
  }

  func resolveOwnedEvent(
    externalIdentifier: String,
    calendarIdentifier: String?
  ) async -> ScheduleCalendarEvent? {
    guard let liveEvent = resolvedOwnedEKEvent(
      externalIdentifier: externalIdentifier,
      calendarIdentifier: calendarIdentifier
    ) else {
      return nil
    }
    return matchingVisibleEvent(for: liveEvent) ?? scheduleEvent(from: liveEvent)
  }

  func upsertOwnedEvent(
    _ request: OwnedScheduleCalendarEventUpsertRequest,
    calendarIdentifier: String
  ) async throws -> ScheduleCalendarEvent {
    guard try await requestAccessIfNeeded() else {
      throw ScheduleCalendarEditError.readOnlyCalendar("캘린더 접근 권한이 없습니다.")
    }

    let calendar = try resolvedOwnedCalendar(preferredIdentifier: calendarIdentifier)
    let trimmedTitle = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedTitle = trimmedTitle.isEmpty ? "Untitled Event" : trimmedTitle
    let durationMinutes = max(5, request.durationMinutes)
    let endDate =
      Calendar.autoupdatingCurrent.date(
        byAdding: .minute,
        value: durationMinutes,
        to: request.startDate
      ) ?? request.startDate

    let liveEvent =
      normalizedOwnedCalendarValue(request.externalIdentifier).flatMap { externalIdentifier in
        resolvedOwnedEKEvent(
          externalIdentifier: externalIdentifier,
          calendarIdentifier: calendar.calendarIdentifier
        )
      }
      ?? EKEvent(eventStore: eventStoreForCapabilities)
    liveEvent.calendar = calendar

    let didChange =
      liveEvent.title != resolvedTitle
      || liveEvent.startDate != request.startDate
      || liveEvent.endDate != endDate
      || liveEvent.isAllDay

    liveEvent.isAllDay = false
    liveEvent.title = resolvedTitle
    liveEvent.startDate = request.startDate
    liveEvent.endDate = endDate

    if didChange || liveEvent.calendarItemExternalIdentifier == nil {
      do {
        try eventStoreForCapabilities.save(liveEvent, span: .thisEvent)
      } catch {
        AppLogger.sync.error(
          "owned calendar event upsert failed: \(error.localizedDescription, privacy: .public)"
        )
        throw ScheduleCalendarEditError.saveFailed(error.localizedDescription)
      }
      await reloadCurrentRange(force: true)
      captureOwnedEventInvalidationBaseline()
    }

    if let resolvedEvent = matchingVisibleEvent(for: liveEvent) ?? scheduleEvent(from: liveEvent) {
      return resolvedEvent
    }
    throw ScheduleCalendarEditError.eventNotFound
  }

  func removeOwnedEvent(
    externalIdentifier: String,
    calendarIdentifier: String
  ) async throws -> Bool {
    guard let liveEvent = resolvedOwnedEKEvent(
      externalIdentifier: externalIdentifier,
      calendarIdentifier: calendarIdentifier
    ) else {
      return false
    }

    do {
      try eventStoreForCapabilities.remove(liveEvent, span: .thisEvent)
    } catch {
      AppLogger.sync.error(
        "owned calendar event remove failed: \(error.localizedDescription, privacy: .public)"
      )
      throw ScheduleCalendarEditError.removeFailed(error.localizedDescription)
    }

    await reloadCurrentRange(force: true)
    captureOwnedEventInvalidationBaseline()
    return true
  }

  func resolveEvent(ownerID: String) async -> ScheduleCalendarEvent? {
    let components = ownerID.split(separator: "|", omittingEmptySubsequences: false)
    guard components.count >= 4,
      let lowerInterval = TimeInterval(components[components.count - 2]),
      let upperInterval = TimeInterval(components[components.count - 1])
    else {
      return nil
    }

    let calendarIdentifier = String(components[0])
    let baseIdentifier = String(components[1])
    let lowerBound = Date(timeIntervalSinceReferenceDate: lowerInterval)
    let upperBound = Date(timeIntervalSinceReferenceDate: upperInterval)

    if let exactEvent = resolvedCalendarEvent(
      baseIdentifier: baseIdentifier,
      calendarIdentifier: calendarIdentifier,
      lowerBound: min(lowerBound, upperBound),
      upperBound: max(lowerBound, upperBound)
    ) {
      return matchingVisibleEvent(for: exactEvent) ?? scheduleEvent(from: exactEvent)
    }

    return nil
  }

  private func resolvedOwnedCalendar(
    preferredIdentifier: String? = nil
  ) throws -> EKCalendar {
    let normalizedPreferredIdentifier = normalizedOwnedCalendarValue(preferredIdentifier)
    if let normalizedPreferredIdentifier,
      let calendar = eventStoreForCapabilities.calendar(withIdentifier: normalizedPreferredIdentifier),
      isOwnedCalendar(calendar)
    {
      persistOwnedCalendarIdentifier(normalizedPreferredIdentifier)
      return calendar
    }

    if let storedIdentifier = currentOwnedCalendarIdentifier(),
      let calendar = eventStoreForCapabilities.calendar(withIdentifier: storedIdentifier),
      isOwnedCalendar(calendar)
    {
      return calendar
    }
    clearOwnedCalendarIdentifier()

    let titleMatches = eventStoreForCapabilities.calendars(for: .event).filter {
      $0.title == Self.ownedCalendarTitle
    }
    if !titleMatches.isEmpty {
      AppLogger.sync.error(
        "owned calendar resolution failed closed because titled calendars exist without a trusted identifier"
      )
      throw ScheduleCalendarEditError.readOnlyCalendar(
        "BUF 전용 캘린더 식별자를 복구해야 합니다."
      )
    }

    guard let source = preferredEventSource() else {
      throw ScheduleCalendarEditError.readOnlyCalendar("쓰기 가능한 이벤트 소스를 찾지 못했습니다.")
    }

    let calendar = EKCalendar(for: .event, eventStore: eventStoreForCapabilities)
    calendar.source = source
    calendar.title = Self.ownedCalendarTitle
    if let defaultColor = eventStoreForCapabilities.defaultCalendarForNewEvents?.cgColor {
      calendar.cgColor = defaultColor
    }

    do {
      try eventStoreForCapabilities.saveCalendar(calendar, commit: true)
    } catch {
      AppLogger.sync.error(
        "owned calendar create failed: \(error.localizedDescription, privacy: .public)"
      )
      throw ScheduleCalendarEditError.saveFailed(error.localizedDescription)
    }

    persistOwnedCalendarIdentifier(calendar.calendarIdentifier)
    captureOwnedEventInvalidationBaseline()
    return calendar
  }

  private func resolvedOwnedEKEvent(
    externalIdentifier: String,
    calendarIdentifier: String?
  ) -> EKEvent? {
    let normalizedExternalIdentifier = normalizedOwnedCalendarValue(externalIdentifier)
    guard let normalizedExternalIdentifier else { return nil }

    let matches = eventStoreForCapabilities.calendarItems(withExternalIdentifier: normalizedExternalIdentifier)
      .compactMap { $0 as? EKEvent }
      .filter { event in
        guard let calendarIdentifier = normalizedOwnedCalendarValue(calendarIdentifier) else {
          return true
        }
        return event.calendar.calendarIdentifier == calendarIdentifier
      }
    return ReminderTaskAdoptionPolicy.uniqueMatch(from: matches)
  }

  private func resolvedCalendarEvent(
    baseIdentifier: String,
    calendarIdentifier: String,
    lowerBound: Date,
    upperBound: Date
  ) -> EKEvent? {
    if let candidate = eventStoreForCapabilities.event(withIdentifier: baseIdentifier),
      candidate.calendar.calendarIdentifier == calendarIdentifier
    {
      return candidate
    }

    if let candidate = ReminderTaskAdoptionPolicy.uniqueMatch(
      from: eventStoreForCapabilities.calendarItems(withExternalIdentifier: baseIdentifier)
        .compactMap { $0 as? EKEvent }
        .filter { $0.calendar.calendarIdentifier == calendarIdentifier }
    ) {
      return candidate
    }

    let rangePadding = TimeInterval(24 * 60 * 60)
    let range = (lowerBound - rangePadding)...(upperBound + rangePadding)
    let calendars = eventStoreForCapabilities.calendar(withIdentifier: calendarIdentifier).map { [$0] }
    let predicate = eventStoreForCapabilities.predicateForEvents(
      withStart: range.lowerBound,
      end: range.upperBound,
      calendars: calendars
    )
    let matches = eventStoreForCapabilities.events(matching: predicate).filter { event in
      guard event.calendar.calendarIdentifier == calendarIdentifier else { return false }
      if event.eventIdentifier == baseIdentifier || event.calendarItemExternalIdentifier == baseIdentifier {
        return true
      }
      return occurrenceIdentifier(for: event) == baseIdentifier
    }
    return ReminderTaskAdoptionPolicy.uniqueMatch(from: matches)
  }

  private func preferredEventSource() -> EKSource? {
    if let source = eventStoreForCapabilities.defaultCalendarForNewEvents?.source {
      return source
    }

    let sources = eventStoreForCapabilities.sources
    let preferredSourceTypes: [EKSourceType] = [.local, .calDAV, .exchange]
    for sourceType in preferredSourceTypes {
      if let source = sources.first(where: { $0.sourceType == sourceType }) {
        return source
      }
    }
    return sources.first
  }

  private func persistOwnedCalendarIdentifier(_ calendarIdentifier: String) {
    userDefaults.set(calendarIdentifier, forKey: Self.ownedCalendarIdentifierKey)
  }

  private func clearOwnedCalendarIdentifier() {
    userDefaults.removeObject(forKey: Self.ownedCalendarIdentifierKey)
  }

  private func isOwnedCalendar(_ calendar: EKCalendar) -> Bool {
    calendar.title == Self.ownedCalendarTitle
  }

  private func normalizedOwnedCalendarValue(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
