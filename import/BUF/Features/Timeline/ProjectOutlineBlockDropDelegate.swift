import SwiftUI
import UniformTypeIdentifiers

struct ProjectOutlineBlockDropDelegate: DropDelegate {
  let targetID: UUID
  let rowHeight: CGFloat
  let focusRootID: UUID?
  @Binding var document: ProjectOutlineDocument
  @Binding var draggingBlockID: UUID?
  @Binding var dropIndicator: ProjectOutlineDropIndicator?

  func validateDrop(info: DropInfo) -> Bool {
    guard let draggingBlockID,
      isDropInsideFocusRoot(draggingBlockID: draggingBlockID)
    else { return false }
    return info.hasItemsConforming(to: [UTType.text.identifier])
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let draggingBlockID,
      draggingBlockID != targetID,
      isDropInsideFocusRoot(draggingBlockID: draggingBlockID)
    else {
      dropIndicator = nil
      return nil
    }
    let placement = placement(for: info)
    guard isValidPlacementInsideFocusRoot(placement) else {
      dropIndicator = nil
      return nil
    }
    dropIndicator = ProjectOutlineDropIndicator(targetID: targetID, placement: placement)
    return DropProposal(operation: .move)
  }

  func dropExited(info _: DropInfo) {
    if dropIndicator?.targetID == targetID {
      dropIndicator = nil
    }
  }

  func performDrop(info: DropInfo) -> Bool {
    let placement = dropIndicator?.targetID == targetID
      ? dropIndicator?.placement ?? placement(for: info)
      : placement(for: info)
    defer {
      draggingBlockID = nil
      dropIndicator = nil
    }
    guard let draggingBlockID else { return false }
    guard isValidPlacementInsideFocusRoot(placement) else { return false }
    return ProjectOutlineMutationEngine.moveBlock(
      id: draggingBlockID,
      to: targetID,
      placement: placement,
      in: &document
    )
  }

  private func placement(for info: DropInfo) -> ProjectOutlineDropPlacement {
    guard let targetIndex = document.blocks.firstIndex(where: { $0.id == targetID }) else {
      return .after
    }

    let targetDepth = document.blocks[targetIndex].depth
    let height = max(rowHeight, 24)
    if info.location.y < height * 0.25 {
      return .before
    }
    if info.location.y > height * 0.75 {
      return .after
    }

    let childThreshold = CGFloat(targetDepth + 1) * 20 + 36
    return info.location.x >= childThreshold ? .child : .after
  }

  private func isDropInsideFocusRoot(draggingBlockID: UUID) -> Bool {
    guard let focusRootID,
      let rootIndex = document.blocks.firstIndex(where: { $0.id == focusRootID }),
      let draggingIndex = document.blocks.firstIndex(where: { $0.id == draggingBlockID }),
      let targetIndex = document.blocks.firstIndex(where: { $0.id == targetID })
    else {
      return true
    }
    let rootRange = ProjectOutlineMutationEngine.subtreeRange(at: rootIndex, in: document)
    return rootRange.contains(draggingIndex) && rootRange.contains(targetIndex)
  }

  private func isValidPlacementInsideFocusRoot(_ placement: ProjectOutlineDropPlacement) -> Bool {
    guard let focusRootID, targetID == focusRootID else { return true }
    return placement == .child
  }
}
