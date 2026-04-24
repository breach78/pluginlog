import SwiftUI

extension OutlineFlattenedEntry: Equatable {
  static func == (lhs: OutlineFlattenedEntry, rhs: OutlineFlattenedEntry) -> Bool {
    lhs.id == rhs.id
      && lhs.depth == rhs.depth
      && lhs.node == rhs.node
      && lhs.hasChildren == rhs.hasChildren
      && lhs.isCollapsed == rhs.isCollapsed
  }
}

extension OutlineVisibleTreeNode: Equatable {
  static func == (lhs: OutlineVisibleTreeNode, rhs: OutlineVisibleTreeNode) -> Bool {
    lhs.entry == rhs.entry
      && lhs.rowIndex == rhs.rowIndex
      && lhs.rowCount == rhs.rowCount
      && lhs.children == rhs.children
  }
}

@MainActor
final class OutlinerViewportState: ObservableObject {
  @Published var zoomPath: [UUID] = []
  @Published var zoomScreenHistory: [[UUID]] = []
  @Published var visibleEntries: [OutlineFlattenedEntry] = []
  @Published var visibleTreeNodes: [OutlineVisibleTreeNode] = []
  @Published var visibleRowCount = 0
  @Published var virtualizationViewportHeight: CGFloat = 0
  @Published var virtualizationVisibleStartIndex = 0

  @discardableResult
  func applyVisibleProjection(
    entries: [OutlineFlattenedEntry],
    treeNodes: [OutlineVisibleTreeNode]
  ) -> Bool {
    var didChange = false

    if visibleEntries != entries {
      visibleEntries = entries
      didChange = true
    }

    let nextRowCount = entries.count
    if visibleRowCount != nextRowCount {
      visibleRowCount = nextRowCount
      didChange = true
    }

    if visibleTreeNodes != treeNodes {
      visibleTreeNodes = treeNodes
      didChange = true
    }

    return didChange
  }
}
