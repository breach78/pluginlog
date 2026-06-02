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

  @Test func indentSelectionMovesContiguousRootSubtreesTogether() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "B"),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "B.1"),
      ProjectOutlineBlock(id: ids[3], depth: 0, text: "C"),
    ])

    let didIndent = ProjectOutlineMutationEngine.indentSelection(
      ids: [ids[1], ids[2], ids[3]],
      in: &document
    )

    #expect(didIndent)
    #expect(document.blocks.map(\.depth) == [0, 1, 2, 1])
  }

  @Test func indentSelectionRejectsPartialSubtreeSelection() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "B"),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "B.1"),
    ])

    let didIndent = ProjectOutlineMutationEngine.indentSelection(
      ids: [ids[1]],
      in: &document
    )

    #expect(!didIndent)
    #expect(document.blocks.map(\.depth) == [0, 0, 1])
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

  @Test func outdentSelectionMovesContiguousRootSubtreesAfterParentSubtree() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "B"),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "C"),
      ProjectOutlineBlock(id: ids[3], depth: 1, text: "D"),
      ProjectOutlineBlock(id: ids[4], depth: 0, text: "E"),
    ])

    let didOutdent = ProjectOutlineMutationEngine.outdentSelection(
      ids: [ids[1], ids[2]],
      in: &document
    )

    #expect(didOutdent)
    #expect(document.blocks.map(\.text) == ["A", "D", "B", "C", "E"])
    #expect(document.blocks.map(\.depth) == [0, 1, 0, 0, 0])
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

  @Test func enterAtEndWithHiddenChildrenOverrideCreatesSiblingAfterSubtree() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "parent"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "hidden child"),
      ProjectOutlineBlock(id: ids[2], depth: 0, text: "next"),
    ])

    let result = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: ids[0],
      textOffset: 6,
      hasExpandedChildrenOverride: false,
      in: &document
    )

    #expect(result?.focusedBlockID == document.blocks[2].id)
    #expect(document.blocks.map(\.text) == ["parent", "hidden child", "", "next"])
    #expect(document.blocks.map(\.depth) == [0, 1, 0, 0])
  }

  @Test func enterOnTaskBlockCreatesNormalSiblingAfterTaskSubtree() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(
        id: ids[0],
        depth: 0,
        text: "",
        taskBinding: .init(taskID: ids[0], taskExternalIdentifier: "task")
      ),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "child"),
      ProjectOutlineBlock(id: ids[2], depth: 0, text: "next"),
    ])

    let result = ProjectOutlineMutationEngine.insertSiblingAfterSubtree(
      blockID: ids[0],
      in: &document
    )

    #expect(result?.focusedBlockID == document.blocks[2].id)
    #expect(document.blocks.map(\.text) == ["", "child", "", "next"])
    #expect(document.blocks.map(\.depth) == [0, 1, 0, 0])
    #expect(document.blocks[2].taskBinding == nil)
  }

  @Test func insertFirstChildCreatesNormalChildAfterTaskBlock() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(
        id: ids[0],
        depth: 0,
        text: "",
        taskBinding: .init(taskID: ids[0], taskExternalIdentifier: "task")
      ),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "child"),
    ])

    let result = ProjectOutlineMutationEngine.insertFirstChild(blockID: ids[0], in: &document)

    #expect(result?.focusedBlockID == document.blocks[1].id)
    #expect(document.blocks.map(\.text) == ["", "", "child"])
    #expect(document.blocks.map(\.depth) == [0, 1, 1])
    #expect(document.blocks[1].taskBinding == nil)
  }

  @Test func zoomVisibleIndicesTreatFocusRootAsTemporaryRoot() {
    let ids = Self.ids()
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "A.1"),
      ProjectOutlineBlock(id: ids[2], depth: 2, text: "A.1.a"),
      ProjectOutlineBlock(id: ids[3], depth: 0, text: "B"),
    ])

    let visible = ProjectOutlineMutationEngine.visibleIndices(
      in: document,
      focusRootID: ids[1]
    )

    #expect(visible == [1, 2])
  }

  @Test func zoomHelpersReturnAncestorsAndSiblings() {
    let ids = Self.ids()
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "A"),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "A.1"),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "A.2"),
      ProjectOutlineBlock(id: ids[3], depth: 2, text: "A.2.a"),
    ])

    #expect(ProjectOutlineMutationEngine.parentID(for: ids[3], in: document) == ids[2])
    #expect(ProjectOutlineMutationEngine.ancestorIDs(for: ids[3], in: document) == [ids[0], ids[2]])
    #expect(ProjectOutlineMutationEngine.previousSiblingID(for: ids[2], in: document) == ids[1])
    #expect(ProjectOutlineMutationEngine.nextSiblingID(for: ids[1], in: document) == ids[2])
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

  @Test func enterOnEmptyIndentedBlockCreatesNextEmptySibling() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 1, text: ""),
    ])

    let result = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: ids[0],
      textOffset: 0,
      in: &document
    )

    #expect(document.blocks.map(\.text) == ["", ""])
    #expect(document.blocks.map(\.depth) == [1, 1])
    #expect(result?.focusedBlockID == document.blocks[1].id)
  }

  @Test func backspaceAtStartMergesIntoPreviousEmptyBlock() {
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
    #expect(document.blocks.map(\.id) == [ids[0]])
    #expect(document.blocks.map(\.text) == ["current"])
  }

  @Test func backspaceAtStartMergesIntoPreviousVisibleBlockWhenParentHasChildren() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: ""),
      ProjectOutlineBlock(id: ids[1], depth: 1, text: "child"),
      ProjectOutlineBlock(id: ids[2], depth: 0, text: "current"),
    ])

    let didHandle = ProjectOutlineMutationEngine.backspaceAtStart(
      blockID: ids[2],
      in: &document
    )

    #expect(didHandle)
    #expect(document.blocks.map(\.id) == [ids[0], ids[1]])
    #expect(document.blocks.map(\.text) == ["", "childcurrent"])
    #expect(document.blocks.map(\.depth) == [0, 1])
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
    #expect(document.blocks.map(\.id) == [ids[0]])
    #expect(document.blocks.map(\.text) == ["first second"])
  }

  @Test func backspaceAtStartReturnsMergeCaretBeforeAppendedText() throws {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "앞"),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "뒤"),
    ])

    let result = try #require(
      ProjectOutlineMutationEngine.backspaceAtStartResult(blockID: ids[1], in: &document)
    )

    #expect(document.blocks.map(\.text) == ["앞뒤"])
    #expect(result.focusedBlockID == ids[0])
    #expect(result.focusOffset == "앞".utf16.count)
  }

  @Test func backspaceAtStartDeletesCurrentEmptyBlockAndFocusesPreviousEnd() throws {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "previous"),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: ""),
    ])

    let result = try #require(
      ProjectOutlineMutationEngine.backspaceAtStartResult(blockID: ids[1], in: &document)
    )

    #expect(document.blocks.map(\.id) == [ids[0]])
    #expect(result.focusedBlockID == ids[0])
    #expect(result.focusOffset == "previous".utf16.count)
  }

  @Test func backspaceAtStartDoesNotMergeBlockWithChildren() {
    let ids = Self.ids()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: ids[0], depth: 0, text: "first "),
      ProjectOutlineBlock(id: ids[1], depth: 0, text: "second"),
      ProjectOutlineBlock(id: ids[2], depth: 1, text: "child"),
    ])

    let didHandle = ProjectOutlineMutationEngine.backspaceAtStart(
      blockID: ids[1],
      in: &document
    )

    #expect(!didHandle)
    #expect(document.blocks.map(\.text) == ["first ", "second", "child"])
    #expect(document.blocks.map(\.depth) == [0, 0, 1])
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
