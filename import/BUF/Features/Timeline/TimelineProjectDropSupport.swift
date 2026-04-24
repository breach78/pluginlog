import SwiftUI
import UniformTypeIdentifiers

enum TimelineProjectDropPlacement {
  case before
  case after
}

struct TimelineProjectDropIndicator: Equatable {
  let targetProjectID: UUID
  let placement: TimelineProjectDropPlacement
}

struct TimelineProjectDropTarget {
  let projectID: UUID
  let minY: CGFloat
  let midY: CGFloat
  let maxY: CGFloat
}

struct TimelineProjectRowDropDelegate: DropDelegate {
  let targetProjectID: UUID
  @Binding var draggingProjectID: UUID?
  @Binding var dropIndicator: TimelineProjectDropIndicator?
  @Binding var taskDropTargetProjectID: UUID?
  let onPerformDrop:
    (_ draggedID: UUID, _ targetID: UUID, _ placement: TimelineProjectDropPlacement) -> Void
  let onPerformTaskDrop: (_ taskID: UUID, _ targetProjectID: UUID) -> Void

  private func hasProjectProvider(_ info: DropInfo) -> Bool {
    !info.itemProviders(for: [ProjectDragPayload.projectType.identifier]).isEmpty
  }

  private func isLocalProjectDrag(_ info: DropInfo) -> Bool {
    draggingProjectID != nil && hasProjectProvider(info)
  }

  private func isForeignProjectDrag(_ info: DropInfo) -> Bool {
    draggingProjectID == nil && hasProjectProvider(info)
  }

  func validateDrop(info: DropInfo) -> Bool {
    if isLocalProjectDrag(info) || isForeignProjectDrag(info) {
      return true
    }
    return !info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).isEmpty
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    if isLocalProjectDrag(info) {
      taskDropTargetProjectID = nil

      let placement: TimelineProjectDropPlacement = info.location.y < 20 ? .before : .after
      if draggingProjectID == targetProjectID {
        dropIndicator = nil
      } else {
        let indicator = TimelineProjectDropIndicator(
          targetProjectID: targetProjectID, placement: placement)
        if dropIndicator != indicator {
          dropIndicator = indicator
        }
      }

      return DropProposal(operation: .move)
    }

    if isForeignProjectDrag(info) {
      dropIndicator = nil
      taskDropTargetProjectID = nil
      return DropProposal(operation: .move)
    }

    dropIndicator = nil
    if taskDropTargetProjectID != targetProjectID {
      taskDropTargetProjectID = targetProjectID
    }

    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggingProjectID = nil
      dropIndicator = nil
      taskDropTargetProjectID = nil
    }

    if isLocalProjectDrag(info) || isForeignProjectDrag(info) {
      let placement = dropIndicator?.placement ?? .after
      if let draggingProjectID {
        guard draggingProjectID != targetProjectID else { return false }
        onPerformDrop(draggingProjectID, targetProjectID, placement)
        return true
      }

      guard
        let provider = info.itemProviders(for: [ProjectDragPayload.projectType.identifier]).first
      else {
        return false
      }

      let targetID = targetProjectID
      provider.loadItem(
        forTypeIdentifier: ProjectDragPayload.projectType.identifier,
        options: nil
      ) { item, _ in
        guard
          let draggedID = ProjectDragPayload.parseProjectID(from: item),
          draggedID != targetID
        else {
          return
        }

        Task { @MainActor in
          onPerformDrop(draggedID, targetID, placement)
        }
      }
      return true
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
    if dropIndicator?.targetProjectID == targetProjectID {
      dropIndicator = nil
    }
    if taskDropTargetProjectID == targetProjectID {
      taskDropTargetProjectID = nil
    }
  }
}

struct TimelineProjectListDropDelegate: DropDelegate {
  let targets: [TimelineProjectDropTarget]
  @Binding var draggingProjectID: UUID?
  @Binding var dropIndicator: TimelineProjectDropIndicator?
  @Binding var taskDropTargetProjectID: UUID?
  let onPerformDrop:
    (_ draggedID: UUID, _ targetID: UUID, _ placement: TimelineProjectDropPlacement) -> Void
  let onPerformTaskDrop: (_ taskID: UUID, _ targetProjectID: UUID) -> Void

  private func hasProjectProvider(_ info: DropInfo) -> Bool {
    !info.itemProviders(for: [ProjectDragPayload.projectType.identifier]).isEmpty
  }

  private func isLocalProjectDrag(_ info: DropInfo) -> Bool {
    draggingProjectID != nil && hasProjectProvider(info)
  }

  private func isForeignProjectDrag(_ info: DropInfo) -> Bool {
    draggingProjectID == nil && hasProjectProvider(info)
  }

  private func target(at location: CGPoint) -> (projectID: UUID, placement: TimelineProjectDropPlacement)? {
    guard !targets.isEmpty else { return nil }
    let y = location.y
    if y <= targets[0].minY {
      return (targets[0].projectID, .before)
    }
    if let last = targets.last, y >= last.maxY {
      return (last.projectID, .after)
    }
    guard let target = targets.first(where: { y >= $0.minY && y <= $0.maxY }) else {
      return nil
    }
    return (target.projectID, y < target.midY ? .before : .after)
  }

  func validateDrop(info: DropInfo) -> Bool {
    if isLocalProjectDrag(info) || isForeignProjectDrag(info) {
      return true
    }
    return !info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).isEmpty
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let target = target(at: info.location) else {
      dropIndicator = nil
      taskDropTargetProjectID = nil
      return DropProposal(operation: .move)
    }

    if isLocalProjectDrag(info) {
      taskDropTargetProjectID = nil
      if draggingProjectID == target.projectID {
        dropIndicator = nil
      } else {
        let indicator = TimelineProjectDropIndicator(
          targetProjectID: target.projectID,
          placement: target.placement
        )
        if dropIndicator != indicator {
          dropIndicator = indicator
        }
      }
      return DropProposal(operation: .move)
    }

    if isForeignProjectDrag(info) {
      dropIndicator = nil
      taskDropTargetProjectID = nil
      return DropProposal(operation: .move)
    }

    dropIndicator = nil
    if taskDropTargetProjectID != target.projectID {
      taskDropTargetProjectID = target.projectID
    }
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggingProjectID = nil
      dropIndicator = nil
      taskDropTargetProjectID = nil
    }

    guard let target = target(at: info.location) else {
      return false
    }

    if isLocalProjectDrag(info) || isForeignProjectDrag(info) {
      if let draggingProjectID {
        guard draggingProjectID != target.projectID else { return false }
        onPerformDrop(draggingProjectID, target.projectID, target.placement)
        return true
      }

      guard
        let provider = info.itemProviders(for: [ProjectDragPayload.projectType.identifier]).first
      else {
        return false
      }

      let targetID = target.projectID
      let placement = target.placement
      provider.loadItem(
        forTypeIdentifier: ProjectDragPayload.projectType.identifier,
        options: nil
      ) { item, _ in
        guard
          let draggedID = ProjectDragPayload.parseProjectID(from: item),
          draggedID != targetID
        else {
          return
        }

        Task { @MainActor in
          onPerformDrop(draggedID, targetID, placement)
        }
      }
      return true
    }

    guard let provider = info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).first else {
      return false
    }
    let targetID = target.projectID
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
    dropIndicator = nil
    taskDropTargetProjectID = nil
  }
}
