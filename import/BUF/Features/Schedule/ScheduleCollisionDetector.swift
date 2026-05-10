import Foundation

struct ScheduleTimedPlacementCandidate: Identifiable, Hashable {
  let id: String
  let itemID: String
  let dayIndex: Int
  let startMinute: Int
  let durationMinutes: Int
  let endMinute: Int
  let sourceStartDay: Date
  let sourceStartMinute: Int
  let sourceDurationMinutes: Int
  let isFirstSegment: Bool
  let isLastSegment: Bool
}

struct ScheduleTimedPlacement: Identifiable, Hashable {
  let id: String
  let itemID: String
  let dayIndex: Int
  let startMinute: Int
  let durationMinutes: Int
  let endMinute: Int
  let sourceStartDay: Date
  let sourceStartMinute: Int
  let sourceDurationMinutes: Int
  let isFirstSegment: Bool
  let isLastSegment: Bool
  let column: Int
  let columnCount: Int
  let columnSpan: Int
}

protocol ScheduleCollisionDetecting {
  func place(_ entries: [ScheduleTimedPlacementCandidate]) -> [ScheduleTimedPlacement]
}

struct DefaultScheduleCollisionDetector: ScheduleCollisionDetecting {
  func place(_ entries: [ScheduleTimedPlacementCandidate]) -> [ScheduleTimedPlacement] {
    let grouped = Dictionary(grouping: entries, by: \.dayIndex)
    var result: [ScheduleTimedPlacement] = []

    for dayIndex in grouped.keys.sorted() {
      let dayEntries = grouped[dayIndex, default: []]
        .sorted { lhs, rhs in
          if lhs.startMinute != rhs.startMinute {
            return lhs.startMinute < rhs.startMinute
          }
          if lhs.endMinute != rhs.endMinute {
            return lhs.endMinute > rhs.endMinute
          }
          return lhs.id < rhs.id
        }

      var activeColumns: [(endMinute: Int, column: Int)] = []
      var cluster: [(entry: ScheduleTimedPlacementCandidate, column: Int)] = []
      var clusterColumnCount = 0

      func flushCluster() {
        guard !cluster.isEmpty else { return }
        let normalizedColumnCount = max(1, clusterColumnCount)
        for item in cluster {
          let expandableColumnSpan = expandedColumnSpan(
            for: item,
            in: cluster,
            totalColumnCount: normalizedColumnCount
          )
          result.append(
            ScheduleTimedPlacement(
              id: item.entry.id,
              itemID: item.entry.itemID,
              dayIndex: item.entry.dayIndex,
              startMinute: item.entry.startMinute,
              durationMinutes: item.entry.durationMinutes,
              endMinute: item.entry.endMinute,
              sourceStartDay: item.entry.sourceStartDay,
              sourceStartMinute: item.entry.sourceStartMinute,
              sourceDurationMinutes: item.entry.sourceDurationMinutes,
              isFirstSegment: item.entry.isFirstSegment,
              isLastSegment: item.entry.isLastSegment,
              column: item.column,
              columnCount: normalizedColumnCount,
              columnSpan: expandableColumnSpan
            )
          )
        }
        cluster.removeAll()
        clusterColumnCount = 0
      }

      for entry in dayEntries {
        activeColumns.removeAll { $0.endMinute <= entry.startMinute }
        if activeColumns.isEmpty {
          flushCluster()
        }

        let occupiedColumns = Set(activeColumns.map(\.column))
        var column = 0
        while occupiedColumns.contains(column) {
          column += 1
        }

        activeColumns.append((endMinute: entry.endMinute, column: column))
        cluster.append((entry: entry, column: column))
        clusterColumnCount = max(clusterColumnCount, activeColumns.count)
      }

      flushCluster()
    }

    return result
  }

  private func expandedColumnSpan(
    for item: (entry: ScheduleTimedPlacementCandidate, column: Int),
    in cluster: [(entry: ScheduleTimedPlacementCandidate, column: Int)],
    totalColumnCount: Int
  ) -> Int {
    guard item.column < totalColumnCount - 1 else { return 1 }

    var span = 1
    for candidateColumn in (item.column + 1)..<totalColumnCount {
      let isBlocked = cluster.contains { other in
        guard other.column == candidateColumn else { return false }
        return other.entry.startMinute < item.entry.endMinute
          && other.entry.endMinute > item.entry.startMinute
      }
      if isBlocked {
        break
      }
      span += 1
    }
    return span
  }
}
