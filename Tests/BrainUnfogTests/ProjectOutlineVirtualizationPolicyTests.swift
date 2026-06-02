import Foundation
import Testing
@testable import BrainUnfog

struct ProjectOutlineVirtualizationPolicyTests {
  @Test func emptyListReturnsEmptyRange() {
    let range = ProjectOutlineVirtualizationPolicy.range(
      itemIDs: [],
      rowHeights: [:],
      scrollOffset: 100,
      viewportHeight: 400
    )

    #expect(range.startIndex == 0)
    #expect(range.endIndex == 0)
    #expect(range.topSpacerHeight == 0)
    #expect(range.bottomSpacerHeight == 0)
  }

  @Test func returnsOnlyRowsAroundViewportWithSpacerHeights() {
    let ids = (0..<10).map { _ in UUID() }
    let heights = Dictionary(uniqueKeysWithValues: ids.map { ($0, CGFloat(10)) })

    let range = ProjectOutlineVirtualizationPolicy.range(
      itemIDs: ids,
      rowHeights: heights,
      scrollOffset: 35,
      viewportHeight: 20,
      defaultRowHeight: 10,
      overscanHeight: 0
    )

    #expect(range.indices == 3..<6)
    #expect(range.topSpacerHeight == 30)
    #expect(range.bottomSpacerHeight == 40)
  }

  @Test func usesDefaultHeightForUnknownRows() {
    let ids = (0..<5).map { _ in UUID() }

    let range = ProjectOutlineVirtualizationPolicy.range(
      itemIDs: ids,
      rowHeights: [ids[0]: 20],
      scrollOffset: 20,
      viewportHeight: 20,
      defaultRowHeight: 10,
      overscanHeight: 0
    )

    #expect(range.indices == 0..<4)
    #expect(range.topSpacerHeight == 0)
    #expect(range.bottomSpacerHeight == 10)
  }

  @Test func includesPinnedRowsOutsideViewport() {
    let ids = (0..<8).map { _ in UUID() }
    let heights = Dictionary(uniqueKeysWithValues: ids.map { ($0, CGFloat(10)) })

    let range = ProjectOutlineVirtualizationPolicy.range(
      itemIDs: ids,
      rowHeights: heights,
      scrollOffset: 50,
      viewportHeight: 10,
      defaultRowHeight: 10,
      overscanHeight: 0,
      pinnedIDs: [ids[1]]
    )

    #expect(range.indices == 1..<7)
    #expect(range.topSpacerHeight == 10)
    #expect(range.bottomSpacerHeight == 10)
  }
}
