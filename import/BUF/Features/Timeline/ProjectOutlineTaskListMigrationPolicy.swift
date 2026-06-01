import Foundation

enum ProjectOutlineTaskListMigrationPolicy {
  static func appendMissingTaskBlocks(
    to document: inout ProjectOutlineDocument,
    taskIDs: [UUID]
  ) -> Bool {
    let missingTaskIDs = missingTaskIDs(in: document, taskIDs: taskIDs)
    guard !missingTaskIDs.isEmpty else { return false }

    removeEmptyPlaceholderIfNeeded(from: &document)
    document.blocks.append(
      contentsOf: missingTaskIDs.map { taskID in
        ProjectOutlineBlock(
          depth: 0,
          text: "",
          taskBinding: ProjectOutlineTaskBinding(
            taskID: taskID,
            taskExternalIdentifier: nil
          )
        )
      }
    )
    return true
  }

  private static func missingTaskIDs(
    in document: ProjectOutlineDocument,
    taskIDs: [UUID]
  ) -> [UUID] {
    let existingTaskIDs = Set(document.blocks.compactMap(\.taskBinding?.taskID))
    var seenTaskIDs = Set<UUID>()
    return taskIDs.filter { taskID in
      guard !existingTaskIDs.contains(taskID), !seenTaskIDs.contains(taskID) else {
        return false
      }
      seenTaskIDs.insert(taskID)
      return true
    }
  }

  private static func removeEmptyPlaceholderIfNeeded(from document: inout ProjectOutlineDocument) {
    guard document.blocks.count == 1,
      let block = document.blocks.first,
      block.text.isEmpty,
      block.taskBinding == nil,
      !block.childrenCollapsed
    else {
      return
    }
    document.blocks.removeAll()
  }
}
