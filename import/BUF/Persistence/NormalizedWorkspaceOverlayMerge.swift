import Foundation

enum NormalizedWorkspaceOverlayMerge {
  static func merged(
    source: NormalizedSourceSnapshot,
    overlay: WorkspaceSubtreeSnapshot
  ) -> NormalizedSourceSnapshot {
    let sourceNodeIDs = Set(source.workspaceNodes.map(\.id))
    let sourceTaskIDs = Set(source.tasks.map(\.id))

    let preservedNodes = overlay.nodes.filter { node in
      guard node.id != NormalizedSourceSnapshot.rootNodeID else { return false }
      return !sourceNodeIDs.contains(node.id)
    }
    let preservedNodeIDs = Set(preservedNodes.map(\.id))
    let preservedTasks = overlay.tasks.filter { task in
      !sourceTaskIDs.contains(task.id) && preservedNodeIDs.contains(task.workspaceNodeID)
    }

    guard !preservedNodes.isEmpty || !preservedTasks.isEmpty else {
      return source
    }

    let mergedNodes = (source.workspaceNodes + preservedNodes).sorted(by: nodeComparator)
    let mergedTasks = (source.tasks + preservedTasks).sorted(by: taskComparator)
    let digest = NormalizedSourceDigest(
      projectCount: mergedNodes.filter { $0.kind == .project }.count,
      taskCount: mergedTasks.count,
      taskClonePlacementCount: source.taskClonePlacements.count,
      attachmentCount: source.attachments.count,
      latestProjectUpdatedAt: mergedNodes
        .filter { $0.id != NormalizedSourceSnapshot.rootNodeID }
        .map(\.updatedAt)
        .max(),
      latestTaskUpdatedAt: mergedTasks.map(\.localUpdatedAt).max(),
      latestTaskClonePlacementUpdatedAt: source.taskClonePlacements.map(\.updatedAt).max(),
      latestAttachmentUpdatedAt: source.attachments.map(\.updatedAt).max()
    )

    return NormalizedSourceSnapshot(
      digest: digest,
      workspaceNodes: mergedNodes,
      tasks: mergedTasks,
      taskClonePlacements: source.taskClonePlacements,
      attachments: source.attachments,
      calendarEventMirrors: source.calendarEventMirrors
    )
  }

  private static func nodeComparator(_ lhs: WorkspaceNodeRecord, _ rhs: WorkspaceNodeRecord) -> Bool {
    let leftParent = lhs.parentID?.uuidString ?? ""
    let rightParent = rhs.parentID?.uuidString ?? ""
    if leftParent != rightParent {
      return leftParent < rightParent
    }
    if lhs.sortKey != rhs.sortKey {
      return lhs.sortKey < rhs.sortKey
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private static func taskComparator(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
    if lhs.workspaceNodeID != rhs.workspaceNodeID {
      return lhs.workspaceNodeID.uuidString < rhs.workspaceNodeID.uuidString
    }
    if lhs.rowOrder != rhs.rowOrder {
      return lhs.rowOrder < rhs.rowOrder
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}
