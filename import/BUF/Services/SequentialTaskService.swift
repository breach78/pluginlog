import Foundation

struct SequentialTaskEntry: Equatable {
  let id: UUID
  let isCompleted: Bool
}

struct SequentialTaskSegment: Equatable {
  let groupID: String
  let taskIDs: [UUID]

  var leaderTaskID: UUID { taskIDs[0] }
  var tailTaskID: UUID { taskIDs[taskIDs.count - 1] }
}

struct SequentialTaskPresentation: Equatable {
  static let empty = SequentialTaskPresentation(
    normalizedAssignments: [:],
    segmentsByTaskID: [:],
    displayNumbers: [:],
    suggestedNumbers: [:]
  )

  let normalizedAssignments: [UUID: String]
  let segmentsByTaskID: [UUID: SequentialTaskSegment]
  let displayNumbers: [UUID: Int]
  let suggestedNumbers: [UUID: Int]
}

struct SequentialTaskSuggestion: Equatable {
  let number: Int
  let anchorTaskID: UUID
  let existingGroupID: String?
}

enum SequentialTaskService {
  static let assignmentsDidChangeNotification = Notification.Name
    .reminderAppTaskSequenceAssignmentsDidChange

  static func assignmentsKey(for projectID: UUID) -> String {
    "project.taskSequenceAssignments.\(projectID.uuidString)"
  }

  static func loadAssignments(
    for projectID: UUID,
    defaults: UserDefaults = .standard
  ) -> [UUID: String] {
    let rawAssignments =
      defaults.dictionary(forKey: assignmentsKey(for: projectID)) as? [String: String] ?? [:]
    return rawAssignments.reduce(into: [UUID: String]()) { result, item in
      guard let taskID = UUID(uuidString: item.key), !item.value.isEmpty else { return }
      result[taskID] = item.value
    }
  }

  static func persistAssignments(
    _ assignments: [UUID: String],
    for projectID: UUID,
    defaults: UserDefaults = .standard
  ) {
    let key = assignmentsKey(for: projectID)
    guard !assignments.isEmpty else {
      defaults.removeObject(forKey: key)
      return
    }

    let rawAssignments = assignments.reduce(into: [String: String]()) { result, item in
      result[item.key.uuidString] = item.value
    }
    defaults.set(rawAssignments, forKey: key)
  }

  static func postAssignmentsDidChange(projectIDs: [UUID]) {
    guard !projectIDs.isEmpty else { return }
    NotificationCenter.default.post(
      name: assignmentsDidChangeNotification,
      object: nil,
      userInfo: ["projectIDs": projectIDs.map(\.uuidString)]
    )
  }

  static func presentation(
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> SequentialTaskPresentation {
    let normalized = normalizedAssignments(entries: entries, assignments: assignments)
    let segments = contiguousSegments(entries: entries, assignments: normalized)

    var segmentsByTaskID: [UUID: SequentialTaskSegment] = [:]
    var displayNumbers: [UUID: Int] = [:]
    var suggestedNumbers: [UUID: Int] = [:]

    for segment in segments {
      var displayNumber = 0
      let activeCount = activeTaskCount(in: segment, entries: entries)

      for taskID in segment.taskIDs {
        segmentsByTaskID[taskID] = segment

        guard let entry = entries.first(where: { $0.id == taskID }) else { continue }
        guard !entry.isCompleted else { continue }

        displayNumber += 1
        displayNumbers[taskID] = displayNumber
      }

      if let activeTailTaskID = activeTailTaskID(in: segment, entries: entries),
        let activeTailIndex = entries.firstIndex(where: { $0.id == activeTailTaskID }),
        let candidateIndex = nextIncompleteIndex(after: activeTailIndex, entries: entries)
      {
        let candidate = entries[candidateIndex]
        if segmentsByTaskID[candidate.id] == nil {
          suggestedNumbers[candidate.id] = activeCount + 1
        }
      }
    }

    return SequentialTaskPresentation(
      normalizedAssignments: normalized,
      segmentsByTaskID: segmentsByTaskID,
      displayNumbers: displayNumbers,
      suggestedNumbers: suggestedNumbers
    )
  }

  static func normalizedAssignments(
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> [UUID: String] {
    var normalized: [UUID: String] = [:]
    var seenSourceGroupIDs: Set<String> = []

    for segment in contiguousSegments(entries: entries, assignments: assignments) {
      let groupID =
        seenSourceGroupIDs.contains(segment.groupID)
        ? UUID().uuidString
        : segment.groupID
      seenSourceGroupIDs.insert(segment.groupID)

      for taskID in segment.taskIDs {
        normalized[taskID] = groupID
      }
    }

    return normalized
  }

  static func segment(
    containing taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> SequentialTaskSegment? {
    presentation(entries: entries, assignments: assignments).segmentsByTaskID[taskID]
  }

  static func displayNumber(
    for taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> Int? {
    presentation(entries: entries, assignments: assignments).displayNumbers[taskID]
  }

  static func suggestedNextNumber(
    for taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> Int? {
    suggestedSequence(for: taskID, entries: entries, assignments: assignments)?.number
  }

  static func suggestedSequence(
    for taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> SequentialTaskSuggestion? {
    let presentation = presentation(entries: entries, assignments: assignments)
    let normalized = presentation.normalizedAssignments

    guard let currentIndex = entries.firstIndex(where: { $0.id == taskID }) else { return nil }
    guard !entries[currentIndex].isCompleted else { return nil }
    guard let number = presentation.suggestedNumbers[taskID] else { return nil }
    guard let previousIndex = previousIncompleteIndex(before: currentIndex, entries: entries) else {
      return nil
    }

    let anchorEntry = entries[previousIndex]
    if let existingGroupID = normalized[anchorEntry.id] {
      guard let segment = presentation.segmentsByTaskID[anchorEntry.id],
        activeTailTaskID(in: segment, entries: entries) == anchorEntry.id
      else {
        return nil
      }

      return SequentialTaskSuggestion(
        number: number,
        anchorTaskID: anchorEntry.id,
        existingGroupID: existingGroupID
      )
    }

    guard number == 2 else { return nil }
    guard presentation.segmentsByTaskID[anchorEntry.id] == nil else { return nil }

    return SequentialTaskSuggestion(
      number: number,
      anchorTaskID: anchorEntry.id,
      existingGroupID: nil
    )
  }

  static func canStartSequence(
    for taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> Bool {
    let normalized = normalizedAssignments(entries: entries, assignments: assignments)
    guard let entry = entries.first(where: { $0.id == taskID }) else { return false }
    guard !entry.isCompleted else { return false }
    return segment(containing: taskID, entries: entries, assignments: normalized) == nil
  }

  static func startingSequence(
    with taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> [UUID: String] {
    let normalized = normalizedAssignments(entries: entries, assignments: assignments)
    guard canStartSequence(for: taskID, entries: entries, assignments: normalized) else {
      return normalized
    }

    var updated = normalized
    updated[taskID] = UUID().uuidString
    return normalizedAssignments(entries: entries, assignments: updated)
  }

  static func applyingSuggestedSequence(
    to taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> [UUID: String] {
    let normalized = normalizedAssignments(entries: entries, assignments: assignments)
    guard let suggestion = suggestedSequence(for: taskID, entries: entries, assignments: normalized)
    else {
      return normalized
    }
    var updated = normalized

    if let existingGroupID = suggestion.existingGroupID {
      updated[taskID] = existingGroupID
    } else {
      let groupID = UUID().uuidString
      updated[suggestion.anchorTaskID] = groupID
      updated[taskID] = groupID
    }

    return normalizedAssignments(entries: entries, assignments: updated)
  }

  static func shouldDetachTaskAfterReorderingWithinProject(
    taskID: UUID,
    insertionIndex: Int,
    remainingOrderedTaskIDs: [UUID],
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> Bool {
    let normalized = normalizedAssignments(entries: entries, assignments: assignments)
    guard let segment = segment(containing: taskID, entries: entries, assignments: normalized),
      segment.leaderTaskID != taskID
    else {
      return false
    }

    let remainingMemberIndices = segment.taskIDs
      .filter { $0 != taskID }
      .compactMap { remainingOrderedTaskIDs.firstIndex(of: $0) }
      .sorted()

    guard let firstIndex = remainingMemberIndices.first,
      let lastIndex = remainingMemberIndices.last
    else {
      return true
    }

    return insertionIndex < firstIndex || insertionIndex > (lastIndex + 1)
  }

  static func removingSequence(
    containing taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> [UUID: String] {
    let normalized = normalizedAssignments(entries: entries, assignments: assignments)
    guard let segment = segment(containing: taskID, entries: entries, assignments: normalized)
    else {
      return normalized
    }

    var updated = normalized
    for memberID in segment.taskIDs {
      updated.removeValue(forKey: memberID)
    }
    return updated
  }

  static func dragUnitTaskIDs(
    for taskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> [UUID] {
    guard let segment = segment(containing: taskID, entries: entries, assignments: assignments),
      segment.leaderTaskID == taskID
    else {
      return [taskID]
    }

    return segment.taskIDs
  }

  static func appendingNewTask(
    _ newTaskID: UUID,
    after sourceTaskID: UUID,
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> [UUID: String] {
    let normalized = normalizedAssignments(entries: entries, assignments: assignments)
    guard
      let segment = segment(containing: sourceTaskID, entries: entries, assignments: normalized),
      activeTailTaskID(in: segment, entries: entries) == sourceTaskID
    else {
      return normalized
    }

    var updated = normalized
    updated[newTaskID] = segment.groupID
    return normalizedAssignments(entries: entries, assignments: updated)
  }

  private static func contiguousSegments(
    entries: [SequentialTaskEntry],
    assignments: [UUID: String]
  ) -> [SequentialTaskSegment] {
    var segments: [SequentialTaskSegment] = []
    var index = 0

    while index < entries.count {
      let entry = entries[index]
      guard let groupID = assignments[entry.id], !groupID.isEmpty else {
        index += 1
        continue
      }

      var taskIDs: [UUID] = [entry.id]
      var nextIndex = index + 1

      while nextIndex < entries.count {
        let nextEntry = entries[nextIndex]

        if let nextGroupID = assignments[nextEntry.id] {
          guard nextGroupID == groupID else { break }
          taskIDs.append(nextEntry.id)
          nextIndex += 1
          continue
        }

        guard nextEntry.isCompleted else { break }
        nextIndex += 1
      }

      segments.append(SequentialTaskSegment(groupID: groupID, taskIDs: taskIDs))
      index = nextIndex
    }

    return segments
  }

  private static func activeTailTaskID(
    in segment: SequentialTaskSegment,
    entries: [SequentialTaskEntry]
  ) -> UUID? {
    segment.taskIDs.last { taskID in
      entries.first(where: { $0.id == taskID })?.isCompleted == false
    }
  }

  private static func activeTaskCount(
    in segment: SequentialTaskSegment,
    entries: [SequentialTaskEntry]
  ) -> Int {
    segment.taskIDs.reduce(into: 0) { count, taskID in
      if entries.first(where: { $0.id == taskID })?.isCompleted == false {
        count += 1
      }
    }
  }

  private static func previousIncompleteIndex(
    before index: Int,
    entries: [SequentialTaskEntry]
  ) -> Int? {
    guard index > 0 else { return nil }
    for candidate in stride(from: index - 1, through: 0, by: -1) {
      if !entries[candidate].isCompleted {
        return candidate
      }
    }
    return nil
  }

  private static func nextIncompleteIndex(
    after index: Int,
    entries: [SequentialTaskEntry]
  ) -> Int? {
    guard index + 1 < entries.count else { return nil }
    for candidate in (index + 1)..<entries.count {
      if !entries[candidate].isCompleted {
        return candidate
      }
    }
    return nil
  }
}
