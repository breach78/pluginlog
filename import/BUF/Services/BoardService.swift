import Foundation

enum BoardService {
  static func reorderedVisibleTaskIDs(
    _ taskIDs: [UUID],
    movingTaskID: UUID,
    targetIndex: Int
  ) -> [UUID] {
    var orderedTaskIDs = taskIDs.filter { $0 != movingTaskID }
    let safeIndex = min(max(0, targetIndex), orderedTaskIDs.count)
    orderedTaskIDs.insert(movingTaskID, at: safeIndex)
    return orderedTaskIDs
  }
}
