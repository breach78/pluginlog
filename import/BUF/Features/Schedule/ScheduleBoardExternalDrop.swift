import AppKit
import SwiftUI

struct ScheduleExternalTaskDropDelegate: DropDelegate {
  let resolveTarget: (CGPoint) -> ScheduleInteractionTarget?
  let onPerformTaskDrop: (UUID, ScheduleInteractionTarget) -> Void
  let onInvalidDrop: (CGPoint, ScheduleInvalidDropReason) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    !info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).isEmpty
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard resolveTarget(info.location) != nil else { return nil }
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    let dropLocation = info.location
    guard let target = resolveTarget(dropLocation) else {
      onInvalidDrop(dropLocation, .externalPreviewUnavailable)
      return false
    }
    guard let provider = info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).first else {
      onInvalidDrop(dropLocation, .payloadProviderMissing)
      return false
    }

    provider.loadItem(forTypeIdentifier: TaskDragPayload.textTypeIdentifier, options: nil) {
      item, _
      in
      guard let taskID = TaskDragPayload.parseTaskID(from: item) else {
        Task { @MainActor in
          onInvalidDrop(dropLocation, .payloadDecodeFailed)
        }
        return
      }
      Task { @MainActor in
        onPerformTaskDrop(taskID, target)
      }
    }
    return true
  }
}
