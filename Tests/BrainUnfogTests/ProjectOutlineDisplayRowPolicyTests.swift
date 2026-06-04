import Foundation
import Testing
@testable import BrainUnfog

struct ProjectOutlineDisplayRowPolicyTests {
  @Test func allowsOnlyUnfocusedPlainNormalBlocks() {
    let block = ProjectOutlineBlock(depth: 0, text: "plain text")

    #expect(
      ProjectOutlineDisplayRowPolicy.canUsePlainDisplay(
        block: block,
        isFocused: false,
        isBlockSelectionActive: false,
        isBlockSelected: false,
        isHighlighted: false,
        dropPlacement: nil
      )
    )
  }

  @Test func rejectsFocusedSelectedHighlightedAndDropRows() {
    let block = ProjectOutlineBlock(depth: 0, text: "plain text")

    #expect(!ProjectOutlineDisplayRowPolicy.canUsePlainDisplay(
      block: block,
      isFocused: true,
      isBlockSelectionActive: false,
      isBlockSelected: false,
      isHighlighted: false,
      dropPlacement: nil
    ))
    #expect(!ProjectOutlineDisplayRowPolicy.canUsePlainDisplay(
      block: block,
      isFocused: false,
      isBlockSelectionActive: false,
      isBlockSelected: true,
      isHighlighted: false,
      dropPlacement: nil
    ))
    #expect(!ProjectOutlineDisplayRowPolicy.canUsePlainDisplay(
      block: block,
      isFocused: false,
      isBlockSelectionActive: false,
      isBlockSelected: false,
      isHighlighted: true,
      dropPlacement: nil
    ))
    #expect(!ProjectOutlineDisplayRowPolicy.canUsePlainDisplay(
      block: block,
      isFocused: false,
      isBlockSelectionActive: false,
      isBlockSelected: false,
      isHighlighted: false,
      dropPlacement: .before
    ))
  }

  @Test func rejectsTaskAttachmentAndLinkRows() throws {
    let taskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let taskBlock = ProjectOutlineBlock(
      depth: 0,
      text: "",
      taskBinding: ProjectOutlineTaskBinding(taskID: taskID, taskExternalIdentifier: nil)
    )
    let attachmentBlock = ProjectOutlineBlock(
      depth: 0,
      text: "[file.pdf](raw/assets/file.pdf)"
    )
    let linkBlock = ProjectOutlineBlock(depth: 0, text: "https://example.com")

    for block in [taskBlock, attachmentBlock, linkBlock] {
      #expect(!ProjectOutlineDisplayRowPolicy.canUsePlainDisplay(
        block: block,
        isFocused: false,
        isBlockSelectionActive: false,
        isBlockSelected: false,
        isHighlighted: false,
        dropPlacement: nil
      ))
    }
  }
}
