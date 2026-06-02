import CoreGraphics
import Foundation

struct ProjectOutlineVirtualizedRange {
  let startIndex: Int
  let endIndex: Int
  let topSpacerHeight: CGFloat
  let bottomSpacerHeight: CGFloat

  var indices: Range<Int> {
    startIndex..<endIndex
  }
}

enum ProjectOutlineVirtualizationPolicy {
  static let defaultRowHeight: CGFloat = 30
  static let defaultOverscanHeight: CGFloat = 260

  static func range(
    itemIDs: [UUID],
    rowHeights: [UUID: CGFloat],
    scrollOffset: CGFloat,
    viewportHeight: CGFloat,
    defaultRowHeight: CGFloat = Self.defaultRowHeight,
    overscanHeight: CGFloat = Self.defaultOverscanHeight,
    pinnedIDs: Set<UUID> = []
  ) -> ProjectOutlineVirtualizedRange {
    guard !itemIDs.isEmpty else {
      return ProjectOutlineVirtualizedRange(
        startIndex: 0,
        endIndex: 0,
        topSpacerHeight: 0,
        bottomSpacerHeight: 0
      )
    }

    let heights = itemIDs.map { id in
      max(1, rowHeights[id] ?? defaultRowHeight)
    }
    let lowerBound = max(0, scrollOffset - overscanHeight)
    let upperBound = max(lowerBound, scrollOffset + viewportHeight + overscanHeight)

    var startIndex = 0
    var runningHeight: CGFloat = 0
    while startIndex < heights.count,
      runningHeight + heights[startIndex] < lowerBound
    {
      runningHeight += heights[startIndex]
      startIndex += 1
    }

    var endIndex = startIndex
    var visibleHeight = runningHeight
    while endIndex < heights.count, visibleHeight <= upperBound {
      visibleHeight += heights[endIndex]
      endIndex += 1
    }

    for pinnedID in pinnedIDs {
      guard let pinnedIndex = itemIDs.firstIndex(of: pinnedID) else { continue }
      startIndex = min(startIndex, pinnedIndex)
      endIndex = max(endIndex, pinnedIndex + 1)
    }

    let topSpacer = heights.prefix(startIndex).reduce(CGFloat.zero, +)
    let bottomSpacer = heights.suffix(from: endIndex).reduce(CGFloat.zero, +)
    return ProjectOutlineVirtualizedRange(
      startIndex: startIndex,
      endIndex: endIndex,
      topSpacerHeight: topSpacer,
      bottomSpacerHeight: bottomSpacer
    )
  }
}
