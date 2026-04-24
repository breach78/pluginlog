import Foundation

enum ScheduleCalendarOwnerIDCodec {
  static func ownerID(for event: ScheduleCalendarEvent) -> String {
    let occurrenceAnchor = event.occurrenceDate ?? event.startDate
    let endAnchor = max(event.startDate, event.endDate)
    let baseIdentifier =
      normalizedIdentifier(event.externalIdentifier)
      ?? normalizedIdentifier(event.eventIdentifier)
      ?? event.id

    return [
      event.calendarIdentifier,
      baseIdentifier,
      String(occurrenceAnchor.timeIntervalSinceReferenceDate),
      String(endAnchor.timeIntervalSinceReferenceDate),
    ]
    .joined(separator: "|")
  }

  static func stableIdentifier(for event: ScheduleCalendarEvent) -> String? {
    normalizedIdentifier(event.externalIdentifier)
      ?? normalizedIdentifier(event.eventIdentifier)
      ?? normalizedIdentifier(event.id)
  }

  static func baseIdentifier(from ownerID: String) -> String? {
    let components = ownerID.split(separator: "|", omittingEmptySubsequences: false)
    guard components.count >= 4 else { return nil }
    return normalizedIdentifier(String(components[1]))
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

enum OwnedScheduleCalendarInvalidationPolicy {
  static func changedOwnerIDs(
    previousEvents: [ScheduleCalendarEvent],
    currentEvents: [ScheduleCalendarEvent],
    ownedCalendarIdentifier: String?
  ) -> [String] {
    guard
      let ownedCalendarIdentifier = ownedCalendarIdentifier?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ),
      !ownedCalendarIdentifier.isEmpty
    else {
      return []
    }

    let previousOwnedEvents = previousEvents.filter { $0.calendarIdentifier == ownedCalendarIdentifier }
    let currentOwnedEvents = currentEvents.filter { $0.calendarIdentifier == ownedCalendarIdentifier }
    let previousByStableIdentifier = Dictionary(
      grouping: previousOwnedEvents,
      by: { ScheduleCalendarOwnerIDCodec.stableIdentifier(for: $0) ?? ScheduleCalendarOwnerIDCodec.ownerID(for: $0) }
    )
    let currentByStableIdentifier = Dictionary(
      grouping: currentOwnedEvents,
      by: { ScheduleCalendarOwnerIDCodec.stableIdentifier(for: $0) ?? ScheduleCalendarOwnerIDCodec.ownerID(for: $0) }
    )

    let allKeys = Set(previousByStableIdentifier.keys).union(currentByStableIdentifier.keys)
    var ownerIDs: [String] = []
    for key in allKeys.sorted() {
      let previousMatches = previousByStableIdentifier[key, default: []]
      let currentMatches = currentByStableIdentifier[key, default: []]

      if previousMatches.count != 1 || currentMatches.count != 1 {
        ownerIDs.append(contentsOf: previousMatches.map(ScheduleCalendarOwnerIDCodec.ownerID))
        ownerIDs.append(contentsOf: currentMatches.map(ScheduleCalendarOwnerIDCodec.ownerID))
        continue
      }

      if previousMatches[0] != currentMatches[0] {
        ownerIDs.append(ScheduleCalendarOwnerIDCodec.ownerID(for: previousMatches[0]))
      }
    }

    return Array(NSOrderedSet(array: ownerIDs)) as? [String] ?? ownerIDs
  }
}
