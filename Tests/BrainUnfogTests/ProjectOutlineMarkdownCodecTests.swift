import Foundation
import Testing
@testable import BrainUnfog

struct ProjectOutlineMarkdownCodecTests {
  @Test func taskMarkerRoundTripsWithoutTitleCopyAndPreservesUnknownAttributes() throws {
    let blockID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let taskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    let markdown =
      #"  - {{buf-task block="11111111-1111-1111-1111-111111111111" task="22222222-2222-2222-2222-222222222222" external="external-1" priority="later"}}"#

    let document = ProjectOutlineMarkdownCodec.document(from: markdown)
    let block = try #require(document.blocks.first)

    #expect(block.id == blockID)
    #expect(block.depth == 1)
    #expect(block.text.isEmpty)
    #expect(block.taskBinding?.taskID == taskID)
    #expect(block.taskBinding?.taskExternalIdentifier == "external-1")
    #expect(block.taskBinding?.preservedAttributes["priority"] == "later")

    let rendered = ProjectOutlineMarkdownCodec.markdown(from: document)
    #expect(rendered.contains(#"priority="later""#))
    #expect(rendered.contains(#"external="external-1""#))
    #expect(rendered.contains("할일") == false)
  }

  @Test func invalidTaskMarkerDegradesToNormalBlock() {
    let document = ProjectOutlineMarkdownCodec.document(
      from: #"- {{buf-task task="22222222-2222-2222-2222-222222222222"}}"#
    )

    #expect(document.blocks.count == 1)
    #expect(document.blocks[0].taskBinding == nil)
    #expect(document.blocks[0].text.contains("buf-task"))
  }

  @Test func normalBlocksRoundTripWithDepthAndSoftNewlineEscapes() {
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(depth: 0, text: "부모"),
      ProjectOutlineBlock(depth: 1, text: "첫 줄\n둘째 줄"),
    ])

    let markdown = ProjectOutlineMarkdownCodec.markdown(from: document)
    let decoded = ProjectOutlineMarkdownCodec.document(from: markdown)

    #expect(markdown == "- 부모\n  - 첫 줄\\n둘째 줄")
    #expect(decoded.blocks.map(\.depth) == document.blocks.map(\.depth))
    #expect(decoded.blocks.map(\.text) == document.blocks.map(\.text))
  }

  @Test func blockColorRoundTripsForNormalAndTaskBlocks() throws {
    let blockID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let taskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(depth: 0, text: "노트", colorToken: .sage),
      ProjectOutlineBlock(
        id: blockID,
        depth: 1,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(taskID: taskID, taskExternalIdentifier: nil),
        colorToken: .slate
      ),
    ])

    let markdown = ProjectOutlineMarkdownCodec.markdown(from: document)
    let decoded = ProjectOutlineMarkdownCodec.document(from: markdown)

    #expect(markdown.contains(#"{{buf-block color="sage"}}"#))
    #expect(markdown.contains(#"{{buf-block color="slate"}}"#))
    #expect(decoded.blocks.map(\.colorToken) == [.sage, .slate])
    #expect(decoded.blocks[1].taskBinding?.taskID == taskID)
  }

  @Test func pendingTaskBlockWithoutReminderIDDoesNotPersistTaskMarker() {
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(
        depth: 0,
        text: "할일 제목",
        taskBinding: ProjectOutlineTaskBinding(taskID: nil, taskExternalIdentifier: nil)
      ),
    ])

    let markdown = ProjectOutlineMarkdownCodec.markdown(from: document)
    let decoded = ProjectOutlineMarkdownCodec.document(from: markdown)

    #expect(markdown == "- 할일 제목")
    #expect(decoded.blocks.first?.taskBinding == nil)
    #expect(decoded.blocks.first?.text == "할일 제목")
  }

  @Test func checkboxInputPolicyConvertsOnlyCompletedMarkerAtCaretEnd() {
    #expect(
      ProjectOutlineCheckboxInputPolicy.shouldConvertToTask(
        text: "[]",
        selectedRange: NSRange(location: 2, length: 0)
      )
    )
    #expect(
      ProjectOutlineCheckboxInputPolicy.shouldConvertToTask(
        text: "[ ]",
        selectedRange: NSRange(location: 3, length: 0)
      )
    )
    #expect(
      !ProjectOutlineCheckboxInputPolicy.shouldConvertToTask(
        text: "[] 제목",
        selectedRange: NSRange(location: 2, length: 0)
      )
    )
  }
}
