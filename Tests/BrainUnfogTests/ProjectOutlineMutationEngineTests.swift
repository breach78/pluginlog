import Foundation
import Testing
@testable import BrainUnfog

struct ProjectOutlineMutationEngineTests {
  @Test func visibleIndicesHideCollapsedDescendantsButKeepCollapsedParentVisible() {
    let ids = Self.ids()
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A", childrenCollapsed: true),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "A.1"),
      ProjectOutlineBlock(id: ids[2], depth: 2, text: "A.1.a"),
      ProjectOutlineBlock(id: ids[3], depth: 0, text: "B"),
    ])

    let visible = ProjectOutlineMutationEngine.visibleIndices(in: document)

    #expect(visible == [0, 3])
  }

  @Test func indentRequiresPreviousSiblingAndMovesSubtree() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "B"),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "B.1"),
    ])

    let didIndent = ProjectOutlineMutationEngine.indentBlock(id: ids[1], in: &document)

    #expect(didIndent)
    #expect(document.blocks.map(\.depth) == [0, 1, 2])
  }

  @Test func indentWithoutPreviousSiblingIsNoOp() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "A.1"),
    ])

    let didIndent = ProjectOutlineMutationEngine.indentBlock(id: ids[0], in: &document)

    #expect(!didIndent)
    #expect(document.blocks.map(\.depth) == [0, 1])
  }

  @Test func outdentRootBlockIsNoOp() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
    ])

    let didOutdent = ProjectOutlineMutationEngine.outdentBlock(id: ids[0], in: &document)

    #expect(!didOutdent)
    #expect(document.blocks.map(\.depth) == [0])
  }

  @Test func outdentMovesBlockAfterParentSubtree() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "B"),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "C"),
      ProjectOutlineBlock(id: ids[3], depth: 1, text: "D"),
    ])

    let didOutdent = ProjectOutlineMutationEngine.outdentBlock(id: ids[2], in: &document)

    #expect(didOutdent)
    #expect(document.blocks.map(\.text) == ["A", "B", "D", "C"])
    #expect(document.blocks.map(\.depth) == [0, 1, 1, 0])
  }

  @Test func deletingTaskBlockAttachesChildrenToPreviousSiblingWhenAvailable() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "", taskBinding: .init(taskID: ids[0], taskExternalIdentifier: "previous")),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "", taskBinding: .init(taskID: ids[1], taskExternalIdentifier: "task")),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "child"),
    ])

    let didDelete = ProjectOutlineMutationEngine.deleteBlockReattachingChildren(
      id: ids[1],
      in: &document
    )

    #expect(didDelete)
    #expect(document.blocks.map(\.text) == ["", "child"])
    #expect(document.blocks.map(\.depth) == [0, 1])
  }

  @Test func deletingTaskBlockOutdentsChildrenWhenPreviousSiblingIsNotTask() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "previous note"),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "", taskBinding: .init(taskID: ids[1], taskExternalIdentifier: "task")),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "child"),
    ])

    let didDelete = ProjectOutlineMutationEngine.deleteBlockReattachingChildren(
      id: ids[1],
      in: &document
    )

    #expect(didDelete)
    #expect(document.blocks.map(\.text) == ["previous note", "child"])
    #expect(document.blocks.map(\.depth) == [0, 0])
  }

  @Test func deletingTaskBlockOutdentsChildrenWhenNoPreviousSiblingExists() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "", taskBinding: .init(taskID: ids[0], taskExternalIdentifier: "task")),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "child"),
    ])

    let didDelete = ProjectOutlineMutationEngine.deleteBlockReattachingChildren(
      id: ids[0],
      in: &document
    )

    #expect(didDelete)
    #expect(document.blocks.map(\.text) == ["child"])
    #expect(document.blocks.map(\.depth) == [0])
  }

  @Test func enterSplitsBlockAndFocusesNewSibling() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "abcdef"),
    ])

    let result = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: ids[0],
      textOffset: 3,
      in: &document
    )

    #expect(document.blocks.map(\.text) == ["abc", "def"])
    #expect(result?.focusedBlockID == document.blocks[1].id)
  }

  @Test func enterAtEndWithExpandedChildrenCreatesFirstChild() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "parent"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "child"),
    ])

    _ = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: ids[0],
      textOffset: 6,
      in: &document
    )

    #expect(document.blocks.map(\.depth) == [0, 1, 1])
    #expect(document.blocks.map(\.text) == ["parent", "", "child"])
  }

  @Test func enterAtEndWithCollapsedChildrenCreatesSiblingAfterSubtree() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "parent", childrenCollapsed: true),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "hidden child"),
    ])

    _ = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: ids[0],
      textOffset: 6,
      in: &document
    )

    #expect(document.blocks.map(\.text) == ["parent", "hidden child", ""])
    #expect(document.blocks.map(\.depth) == [0, 1, 0])
  }

  @Test func enterAtStartInsertsSiblingBeforeAndKeepsFocusOnCurrentBlock() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 1, text: "current"),
    ])

    let result = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: ids[0],
      textOffset: 0,
      in: &document
    )

    #expect(document.blocks.map(\.text) == ["", "current"])
    #expect(document.blocks.map(\.depth) == [1, 1])
    #expect(result?.focusedBlockID == ids[0])
  }

  @Test func enterOnEmptyIndentedBlockOutdentsInsteadOfDeleting() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 1, text: ""),
    ])

    let result = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: ids[0],
      textOffset: 0,
      in: &document
    )

    #expect(document.blocks.map(\.id) == [ids[0]])
    #expect(document.blocks.map(\.depth) == [0])
    #expect(result?.focusedBlockID == ids[0])
  }

  @Test func backspaceAtStartDeletesPreviousEmptyBlockOnly() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: ""),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "current"),
    ])

    let didHandle = ProjectOutlineMutationEngine.backspaceAtStart(
      blockID: ids[1],
      in: &document
    )

    #expect(didHandle)
    #expect(document.blocks.map(\.id) == [ids[1]])
    #expect(document.blocks.map(\.text) == ["current"])
  }

  @Test func backspaceAtStartMergesNormalBlocks() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "first "),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "second"),
    ])

    let didHandle = ProjectOutlineMutationEngine.backspaceAtStart(
      blockID: ids[1],
      in: &document
    )

    #expect(didHandle)
    #expect(document.blocks.map(\.text) == ["first second"])
  }

  @Test func backspaceAtStartDoesNotMergeTaskBlocks() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "first"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "", taskBinding: .init(taskID: ids[1], taskExternalIdentifier: "task")),
    ])

    let didHandle = ProjectOutlineMutationEngine.backspaceAtStart(
      blockID: ids[1],
      in: &document
    )

    #expect(didHandle)
    #expect(document.blocks.map(\.id) == [ids[0], ids[1]])
    #expect(document.blocks.map(\.depth) == [0, 0])
  }

  @Test func deleteAtEndMergesNextNormalBlock() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "first "),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "second"),
    ])

    let didHandle = ProjectOutlineMutationEngine.deleteAtEnd(
      blockID: ids[0],
      in: &document
    )

    #expect(didHandle)
    #expect(document.blocks.map(\.text) == ["first second"])
  }

  @Test func dropMoveBeforeCarriesWholeSubtree() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "A.1"),
      ProjectOutlineBlock(id: ids[2], depth: 0, text: "B"),
    ])

    let didMove = ProjectOutlineMutationEngine.moveBlock(
      id: ids[2],
      to: ids[0],
      placement: .before,
      in: &document
    )

    #expect(didMove)
    #expect(document.blocks.map(\.text) == ["B", "A", "A.1"])
    #expect(document.blocks.map(\.depth) == [0, 0, 1])
  }

  @Test func dropMoveAsChildClampsToTargetChildDepth() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "B"),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "B.1"),
    ])

    let didMove = ProjectOutlineMutationEngine.moveBlock(
      id: ids[0],
      to: ids[1],
      placement: .child,
      in: &document
    )

    #expect(didMove)
    #expect(document.blocks.map(\.text) == ["B", "B.1", "A"])
    #expect(document.blocks.map(\.depth) == [0, 1, 1])
  }

  @Test func dropMoveRejectsTargetInsideMovingSubtree() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "A.1"),
      ProjectOutlineBlock(id: ids[2], depth: 0, text: "B"),
    ])

    let didMove = ProjectOutlineMutationEngine.moveBlock(
      id: ids[0],
      to: ids[1],
      placement: .child,
      in: &document
    )

    #expect(!didMove)
    #expect(document.blocks.map(\.text) == ["A", "A.1", "B"])
  }

  private static func ids() -> [UUID] {
    (0..<8).map { index in
      UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index + 1))")!
    }
  }
}
