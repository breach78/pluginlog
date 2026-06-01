import Foundation
import Testing

@testable import BrainUnfog

struct ProjectOutlineTaskBindingPrunePolicyTests {
  @Test
  func removesUnknownTaskBlockAndReattachesChildren() {
    let knownTaskID = UUID()
    let staleTaskID = UUID()
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(
        depth: 0,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(taskID: staleTaskID, taskExternalIdentifier: nil)
      ),
      ProjectOutlineBlock(depth: 1, text: "child"),
      ProjectOutlineBlock(
        depth: 0,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(taskID: knownTaskID, taskExternalIdentifier: nil)
      ),
    ])

    let didPrune = ProjectOutlineTaskBindingPrunePolicy.pruneUnknownTaskBlocks(
      in: &document,
      knownTaskIDs: [knownTaskID]
    )

    #expect(didPrune)
    #expect(document.blocks.count == 2)
    #expect(document.blocks[0].text == "child")
    #expect(document.blocks[0].depth == 0)
    #expect(document.blocks[1].taskBinding?.taskID == knownTaskID)
  }
}
