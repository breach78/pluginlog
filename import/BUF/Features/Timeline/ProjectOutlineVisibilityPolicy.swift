import Foundation

enum ProjectOutlineVisibilityPolicy {
  static func visibleIndices(
    in document: ProjectOutlineDocument,
    focusRootID: UUID?,
    hiddenTaskIDs: Set<UUID>
  ) -> [Int] {
    let indices = ProjectOutlineMutationEngine.visibleIndices(
      in: document,
      focusRootID: focusRootID
    )
    guard !hiddenTaskIDs.isEmpty else { return indices }

    var visible: [Int] = []
    var hiddenDepth: Int?
    for index in indices {
      let block = document.blocks[index]
      if let depth = hiddenDepth {
        if block.depth > depth {
          continue
        }
        hiddenDepth = nil
      }

      if let taskID = block.taskBinding?.taskID, hiddenTaskIDs.contains(taskID) {
        if ProjectOutlineMutationEngine.hasChildren(at: index, in: document) {
          hiddenDepth = block.depth
        }
        continue
      }

      visible.append(index)
    }
    return visible
  }
}
