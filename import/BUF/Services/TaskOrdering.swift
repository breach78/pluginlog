import Foundation

struct TaskOrderingSnapshot: Identifiable, Hashable, Sendable {
  let id: UUID
  let rowOrder: Int
  let createdAt: Date
}

enum TaskRowOrderTieBreaker {
  case identifier
  case creationDate
}

enum TaskOrdering {
  /// Returns a stable comparator for row-ordered task snapshots that can optionally fall back to creation date.
  static func rowOrderComparator(
    tieBreaker: TaskRowOrderTieBreaker = .identifier
  ) -> (TaskOrderingSnapshot, TaskOrderingSnapshot) -> Bool {
    { lhs, rhs in
      if lhs.rowOrder != rhs.rowOrder {
        return lhs.rowOrder < rhs.rowOrder
      }

      if tieBreaker == .creationDate, lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
      }

      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  /// Sorts task snapshots with the shared stable row-order comparator.
  static func ordered(
    _ tasks: [TaskOrderingSnapshot],
    tieBreaker: TaskRowOrderTieBreaker = .identifier
  ) -> [TaskOrderingSnapshot] {
    tasks.sorted(by: rowOrderComparator(tieBreaker: tieBreaker))
  }

  static func orderedIdentifiers(
    _ tasks: [TaskOrderingSnapshot],
    tieBreaker: TaskRowOrderTieBreaker = .identifier
  ) -> [UUID] {
    ordered(tasks, tieBreaker: tieBreaker).map(\.id)
  }

  static func reorderedIdentifiers(
    in identifiers: [UUID],
    draggedID: UUID,
    targetID: UUID,
    placeAfterTarget: Bool
  ) -> [UUID]? {
    guard draggedID != targetID else { return nil }
    guard let draggedIndex = identifiers.firstIndex(of: draggedID) else { return nil }

    var reorderedIdentifiers = identifiers
    reorderedIdentifiers.remove(at: draggedIndex)

    guard let targetIndex = reorderedIdentifiers.firstIndex(of: targetID) else { return nil }
    let insertionIndex = placeAfterTarget ? (targetIndex + 1) : targetIndex
    reorderedIdentifiers.insert(draggedID, at: min(max(0, insertionIndex), reorderedIdentifiers.count))
    return reorderedIdentifiers
  }

  static func integratingVisibleIdentifiers(
    _ visibleIdentifiers: [UUID],
    into fullIdentifiers: [UUID]
  ) -> [UUID] {
    let visibleIdentifierSet = Set(visibleIdentifiers)
    var visibleIterator = visibleIdentifiers.makeIterator()

    return fullIdentifiers.map { identifier in
      guard visibleIdentifierSet.contains(identifier) else { return identifier }
      return visibleIterator.next() ?? identifier
    }
  }
}
