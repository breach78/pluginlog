import SwiftUI

enum TaskDropPlacement {
  case before
  case after
}

struct TaskDropIndicator: Equatable {
  let targetTaskID: UUID
  let placement: TaskDropPlacement
}

private enum TaskDropIndicatorThreshold {
  static let baseBeforeThreshold: CGFloat = 18
  static let hysteresis: CGFloat = 6
  static let downwardOverlayProbeOffset: CGFloat = 10
}

func resolvedTaskDropPlacement(
  locationY: CGFloat,
  previousIndicator: TaskDropIndicator?,
  targetTaskID: UUID
) -> TaskDropPlacement {
  let threshold = TaskDropIndicatorThreshold.baseBeforeThreshold
  let hysteresis = TaskDropIndicatorThreshold.hysteresis

  guard previousIndicator?.targetTaskID == targetTaskID else {
    return locationY < threshold ? .before : .after
  }

  switch previousIndicator?.placement {
  case .before:
    return locationY <= (threshold + hysteresis) ? .before : .after
  case .after:
    return locationY < (threshold - hysteresis) ? .before : .after
  case nil:
    return locationY < threshold ? .before : .after
  }
}

func taskDropDividerSuppressionTaskID(
  rowOrder: [UUID],
  dropIndicator: TaskDropIndicator?
) -> UUID? {
  guard let dropIndicator else { return nil }

  switch dropIndicator.placement {
  case .after:
    return dropIndicator.targetTaskID
  case .before:
    guard let targetIndex = rowOrder.firstIndex(of: dropIndicator.targetTaskID), targetIndex > 0 else {
      return nil
    }
    return rowOrder[targetIndex - 1]
  }
}

func resolvedLocalTaskDropIndicator(
  dragProbeY: CGFloat,
  dragDirectionY: CGFloat,
  previousIndicator: TaskDropIndicator?,
  draggedTaskID: UUID,
  rowOrder: [UUID],
  rowFrames: [UUID: CGRect]
) -> TaskDropIndicator? {
  let candidateTaskIDs = rowOrder.filter { $0 != draggedTaskID && rowFrames[$0] != nil }
  guard !candidateTaskIDs.isEmpty else { return nil }

  let targetTaskID: UUID
  if let nearestTaskID = candidateTaskIDs.min(
    by: {
      let lhsDistance = abs((rowFrames[$0]?.midY ?? 0) - dragProbeY)
      let rhsDistance = abs((rowFrames[$1]?.midY ?? 0) - dragProbeY)
      return lhsDistance < rhsDistance
    }
  ) {
    targetTaskID = nearestTaskID
  } else {
    return nil
  }

  guard let targetRect = rowFrames[targetTaskID] else { return nil }
  let placement: TaskDropPlacement
  let hysteresis = TaskDropIndicatorThreshold.hysteresis

  if dragDirectionY < 0 {
    let boundaryY = targetRect.maxY
    guard previousIndicator?.targetTaskID == targetTaskID else {
      placement = dragProbeY < boundaryY ? .before : .after
      return TaskDropIndicator(targetTaskID: targetTaskID, placement: placement)
    }

    switch previousIndicator?.placement {
    case .before:
      placement = dragProbeY <= (boundaryY + hysteresis) ? .before : .after
    case .after:
      placement = dragProbeY < (boundaryY - hysteresis) ? .before : .after
    case nil:
      placement = dragProbeY < boundaryY ? .before : .after
    }
    return TaskDropIndicator(targetTaskID: targetTaskID, placement: placement)
  }

  if dragDirectionY > 0 {
    let boundaryY = targetRect.minY
    guard previousIndicator?.targetTaskID == targetTaskID else {
      placement = dragProbeY > boundaryY ? .after : .before
      return TaskDropIndicator(targetTaskID: targetTaskID, placement: placement)
    }

    switch previousIndicator?.placement {
    case .after:
      placement = dragProbeY >= (boundaryY - hysteresis) ? .after : .before
    case .before:
      placement = dragProbeY > (boundaryY + hysteresis) ? .after : .before
    case nil:
      placement = dragProbeY > boundaryY ? .after : .before
    }
    return TaskDropIndicator(targetTaskID: targetTaskID, placement: placement)
  }

  placement = resolvedTaskDropPlacement(
    locationY: dragProbeY - targetRect.minY,
    previousIndicator: previousIndicator,
    targetTaskID: targetTaskID
  )
  return TaskDropIndicator(targetTaskID: targetTaskID, placement: placement)
}

func resolvedLocalTaskDropIndicatorForLiftedOverlay(
  overlayFrame: CGRect,
  dragDirectionY: CGFloat,
  draggedTaskID: UUID,
  rowOrder: [UUID],
  rowFrames: [UUID: CGRect]
) -> TaskDropIndicator? {
  let candidateTaskIDs = rowOrder.filter { $0 != draggedTaskID && rowFrames[$0] != nil }
  guard !candidateTaskIDs.isEmpty else { return nil }

  var slotTopYByInsertionIndex: [Int: CGFloat] = [:]
  if let firstTaskID = candidateTaskIDs.first,
    let firstRect = rowFrames[firstTaskID]
  {
    slotTopYByInsertionIndex[0] = firstRect.minY
  }

  for (index, taskID) in candidateTaskIDs.enumerated() {
    guard let rect = rowFrames[taskID] else { continue }
    slotTopYByInsertionIndex[index + 1] = rect.maxY
  }

  guard !slotTopYByInsertionIndex.isEmpty else { return nil }

  let directionalLead = min(max(overlayFrame.height * 0.35, 10), 20)
  let overlayProbeY: CGFloat
  if dragDirectionY > 0 {
    overlayProbeY = overlayFrame.maxY - directionalLead + TaskDropIndicatorThreshold.downwardOverlayProbeOffset
  } else if dragDirectionY < 0 {
    overlayProbeY = overlayFrame.minY - directionalLead
  } else {
    overlayProbeY = overlayFrame.minY
  }
  guard let resolvedInsertionIndex = slotTopYByInsertionIndex.min(
    by: { abs($0.value - overlayProbeY) < abs($1.value - overlayProbeY) }
  )?.key else {
    return nil
  }

  if resolvedInsertionIndex <= 0 {
    return TaskDropIndicator(targetTaskID: candidateTaskIDs[0], placement: .before)
  }

  if resolvedInsertionIndex >= candidateTaskIDs.count {
    return TaskDropIndicator(targetTaskID: candidateTaskIDs[candidateTaskIDs.count - 1], placement: .after)
  }

  return TaskDropIndicator(
    targetTaskID: candidateTaskIDs[resolvedInsertionIndex],
    placement: .before
  )
}

struct TaskRowDropDelegate: DropDelegate {
  let targetTaskID: UUID
  @Binding var draggingTaskID: UUID?
  @Binding var dropIndicator: TaskDropIndicator?
  let onPerformDrop: (_ draggedID: UUID, _ targetID: UUID, _ placement: TaskDropPlacement) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    draggingTaskID != nil
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let draggingTaskID else {
      dropIndicator = nil
      return DropProposal(operation: .cancel)
    }

    if draggingTaskID == targetTaskID {
      dropIndicator = nil
    } else {
      let placement = resolvedTaskDropPlacement(
        locationY: info.location.y,
        previousIndicator: dropIndicator,
        targetTaskID: targetTaskID
      )
      let indicator = TaskDropIndicator(targetTaskID: targetTaskID, placement: placement)
      if dropIndicator != indicator {
        dropIndicator = indicator
      }
    }

    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggingTaskID = nil
      dropIndicator = nil
    }

    guard let draggingTaskID else { return false }
    guard draggingTaskID != targetTaskID else { return false }

    let placement = dropIndicator?.placement ?? .after
    onPerformDrop(draggingTaskID, targetTaskID, placement)
    return true
  }

  func dropExited(info: DropInfo) {
    if dropIndicator?.targetTaskID == targetTaskID {
      dropIndicator = nil
    }
  }
}
