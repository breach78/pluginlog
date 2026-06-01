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

  static func hasVisibleChildren(
    blockID: UUID,
    in document: ProjectOutlineDocument,
    hiddenTaskIDs: Set<UUID>
  ) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return false
    }
    let parentDepth = document.blocks[index].depth
    var cursor = index + 1
    while document.blocks.indices.contains(cursor), document.blocks[cursor].depth > parentDepth {
      let child = document.blocks[cursor]
      if child.depth == parentDepth + 1 {
        if let taskID = child.taskBinding?.taskID, hiddenTaskIDs.contains(taskID) {
          cursor = ProjectOutlineMutationEngine.subtreeRange(at: cursor, in: document).upperBound
          continue
        }
        return true
      }
      cursor += 1
    }
    return false
  }
}
