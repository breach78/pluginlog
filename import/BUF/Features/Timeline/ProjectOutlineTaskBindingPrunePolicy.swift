import Foundation

enum ProjectOutlineTaskBindingPrunePolicy {
  @discardableResult
  static func pruneUnknownTaskBlocks(
    in document: inout ProjectOutlineDocument,
    knownTaskIDs: Set<UUID>
  ) -> Bool {
    let orphanBlockIDs = document.blocks.compactMap { block -> UUID? in
      guard let taskID = block.taskBinding?.taskID else { return nil }
      return knownTaskIDs.contains(taskID) ? nil : block.id
    }
    guard !orphanBlockIDs.isEmpty else { return false }
    for blockID in orphanBlockIDs {
      _ = ProjectOutlineMutationEngine.deleteBlockReattachingChildren(
        id: blockID,
        in: &document
      )
    }
    return true
  }
}
