import SwiftUI

@MainActor
final class OutlinerSelectionState: ObservableObject {
  @Published var focusedNodeID: UUID?
  @Published var pendingSelectionRequest: OutlineNodeSelectionRequest?
  @Published var isProjectTitleFocused = false
  @Published var selectedNodeIDs: Set<UUID> = []
  @Published var selectedNodeOrder: [UUID] = []
  @Published var blockSelectionLeadNodeID: UUID?
  @Published var blockSelectionDirection: OutlineBlockSelectionDirection?
}

@MainActor
final class OutlinerEditState: ObservableObject {
  @Published var localHideCompleted = false
  @Published var isSearchBarVisible = false
  @Published var searchQuery = ""
  @Published var dropTargetNodeID: UUID?
  @Published var dropPlacement: OutlineNodeDragDropEngine.Placement?
  @Published var hoveredNodeID: UUID?
  @Published var isHoverSuppressedForScroll = false
}
