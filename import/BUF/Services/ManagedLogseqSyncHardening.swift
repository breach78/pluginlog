import Foundation

enum ManagedLogseqSyncHardening {
  static func hasAmbiguousManagedTaskIdentities(
    _ tasks: [LogseqProjectPageStore.TaskRecord]
  ) -> Bool {
    hasDuplicateValues(tasks.compactMap(\.taskID))
      || hasDuplicateValues(tasks.compactMap { normalizedIdentifier($0.reminderExternalIdentifier) })
      || hasDuplicateValues(tasks.compactMap { normalizedIdentifier($0.calendarEventExternalIdentifier) })
  }

  static func allowsManagedTaskCreation(
    _ task: LogseqProjectPageStore.TaskRecord,
    remoteMatchCount: Int
  ) -> Bool {
    if task.taskID != nil {
      return false
    }

    if normalizedIdentifier(task.calendarEventExternalIdentifier) != nil {
      return false
    }

    if normalizedIdentifier(task.reminderExternalIdentifier) != nil {
      return remoteMatchCount == 1
    }

    return true
  }

  static func isConsistentProjectIdentity(
    pageProjectID: UUID?,
    reminderListExternalIdentifier: String?
  ) -> Bool {
    guard
      let pageProjectID,
      let reminderListExternalIdentifier = normalizedIdentifier(reminderListExternalIdentifier)
    else {
      return true
    }

    return pageProjectID == ReminderProjectionIdentity.projectID(for: reminderListExternalIdentifier)
  }

  static func ambiguousOwnedCalendarEventIdentifiers(
    _ bindings: [AppState.RuntimeLogseqTaskBinding]
  ) -> Set<String> {
    let groupedBindings = Dictionary(grouping: bindings.compactMap { binding in
      normalizedIdentifier(binding.calendarEventExternalIdentifier).map { ($0, binding.taskID) }
    }) { $0.0 }

    return Set(
      groupedBindings.compactMap { key, matches in
        let uniqueTaskIDs = Set(matches.map(\.1))
        return uniqueTaskIDs.count > 1 ? key : nil
      }
    )
  }

  static func uniqueBindingsByReminderExternalIdentifier(
    _ bindings: [AppState.RuntimeLogseqTaskBinding]
  ) -> [String: AppState.RuntimeLogseqTaskBinding] {
    Dictionary(grouping: bindings.compactMap { binding in
      normalizedIdentifier(binding.reminderExternalIdentifier).map { ($0, binding) }
    }) { $0.0 }
    .compactMapValues { matches in
      ReminderTaskAdoptionPolicy.uniqueMatch(from: matches.map(\.1))
    }
  }

  private static func hasDuplicateValues<T: Hashable>(_ values: [T]) -> Bool {
    var seen: Set<T> = []
    for value in values {
      if !seen.insert(value).inserted {
        return true
      }
    }
    return false
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
