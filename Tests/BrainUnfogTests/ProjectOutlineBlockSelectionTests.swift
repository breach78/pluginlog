import Foundation
import Testing
@testable import BrainUnfog

struct ProjectOutlineBlockSelectionTests {
  @Test func selectedIDsUseContinuousVisualRange() {
    let ids = Self.ids()
    let selection = ProjectOutlineBlockSelection(anchorID: ids[3], headID: ids[1])

    #expect(selection.selectedIDs(in: ids, depths: Self.flatDepths(for: ids)) == [ids[1], ids[2], ids[3]])
  }

  @Test func adjacentIDMovesPastSelectionEdges() {
    let ids = Self.ids()
    let selection = ProjectOutlineBlockSelection(anchorID: ids[1], headID: ids[3])

    #expect(selection.adjacentID(afterSelectionBy: -1, in: ids, depths: Self.flatDepths(for: ids)) == ids[0])
    #expect(selection.adjacentID(afterSelectionBy: 1, in: ids, depths: Self.flatDepths(for: ids)) == ids[4])
  }

  @Test func adjacentIDClampsAtDocumentEdges() {
    let ids = Self.ids()
    let selection = ProjectOutlineBlockSelection(anchorID: ids[0], headID: ids[4])

    #expect(selection.adjacentID(afterSelectionBy: -1, in: ids, depths: Self.flatDepths(for: ids)) == ids[0])
    #expect(selection.adjacentID(afterSelectionBy: 1, in: ids, depths: Self.flatDepths(for: ids)) == ids[4])
  }

  @Test func selectedParentIncludesVisibleDescendants() {
    let ids = Self.ids()
    let depths = [
      ids[0]: 0,
      ids[1]: 1,
      ids[2]: 2,
      ids[3]: 1,
      ids[4]: 0,
    ]
    let selection = ProjectOutlineBlockSelection(anchorID: ids[0], headID: ids[0])

    #expect(selection.selectedIDs(in: ids, depths: depths) == [ids[0], ids[1], ids[2], ids[3]])
  }

  @Test func adjacentIDSkipsAutoSelectedDescendants() {
    let ids = Self.ids()
    let depths = [
      ids[0]: 0,
      ids[1]: 1,
      ids[2]: 2,
      ids[3]: 1,
      ids[4]: 0,
    ]
    let selection = ProjectOutlineBlockSelection(anchorID: ids[0], headID: ids[0])

    #expect(selection.adjacentID(afterSelectionBy: 1, in: ids, depths: depths) == ids[4])
  }

  private static func ids() -> [UUID] {
    (0..<5).map { index in
      UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index + 1))")!
    }
  }

  private static func flatDepths(for ids: [UUID]) -> [UUID: Int] {
    Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
  }
}
