import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceProjectTaskDropDelegate: DropDelegate {
  let targetProjectID: UUID
  @Binding var taskDropTargetProjectID: UUID?
  let onPerformTaskDrop: (_ taskID: UUID, _ targetProjectID: UUID) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    !info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).isEmpty
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    if taskDropTargetProjectID != targetProjectID {
      taskDropTargetProjectID = targetProjectID
    }
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      taskDropTargetProjectID = nil
    }

    guard let provider = info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).first else {
      return false
    }

    let targetID = targetProjectID

    provider.loadItem(forTypeIdentifier: TaskDragPayload.textTypeIdentifier, options: nil) { item, _ in
      guard
        let taskID = TaskDragPayload.parseTaskID(from: item)
      else {
        return
      }

      Task { @MainActor in
        onPerformTaskDrop(taskID, targetID)
      }
    }
    return true
  }

  func dropExited(info: DropInfo) {
    if taskDropTargetProjectID == targetProjectID {
      taskDropTargetProjectID = nil
    }
  }
}
