import Foundation

enum RetainedCalendarBridgePolicy {
  static func decision(
    for task: RetainedTask,
    ambiguousOwnedEventIdentifiers: Set<String> = []
  ) -> RetainedCalendarBridgeDecision {
    let existingExternalIdentifier = task.identity.calendarEventExternalIdentifier

    guard task.identity.isCalendarBridgeManaged else {
      guard let existingExternalIdentifier else { return .noAction }
      _ = existingExternalIdentifier
      return .failClosed(.unmanagedTaskIdentity)
    }

    if let existingExternalIdentifier,
      ambiguousOwnedEventIdentifiers.contains(existingExternalIdentifier)
    {
      return .failClosed(.ambiguousOwnedEventIdentifier(existingExternalIdentifier))
    }

    if let existingExternalIdentifier, task.schedule.hasDamagedDateValue {
      return .failClosed(.invalidDate(existingExternalIdentifier))
    }

    if let existingExternalIdentifier,
      task.schedule.hasExplicitTime,
      task.schedule.hasDamagedDurationValue
    {
      return .failClosed(.invalidDuration(existingExternalIdentifier))
    }

    guard let parsedDate = task.schedule.parsedDate else {
      guard let existingExternalIdentifier else { return .noAction }
      return .removeOwnedEvent(externalIdentifier: existingExternalIdentifier)
    }

    guard task.schedule.hasExplicitTime else {
      guard let existingExternalIdentifier else { return .noAction }
      return .removeOwnedEvent(externalIdentifier: existingExternalIdentifier)
    }

    guard let durationMinutes = task.schedule.durationMinutes else {
      guard let existingExternalIdentifier else { return .noAction }
      return .removeOwnedEvent(externalIdentifier: existingExternalIdentifier)
    }

    return .upsert(
      RetainedCalendarBridgeUpsertRequest(
        externalIdentifier: existingExternalIdentifier,
        title: task.title,
        startDate: parsedDate,
        durationMinutes: durationMinutes
      )
    )
  }
}
