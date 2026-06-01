import AppKit
import Foundation
import Testing
@testable import BrainUnfog

struct ProjectOutlineAttachmentInlineCodecTests {
  @Test func markdownAttachmentRendersAsSingleAttachmentCharacterAndRoundTrips() {
    let root = URL(fileURLWithPath: "/tmp/vault")
    let markdown = "before [Report.pdf](raw/assets/Report.pdf) after"
    let attributed = ProjectOutlineAttachmentInlineCodec.attributedString(
      from: markdown,
      vaultRootURL: root,
      font: NSFont.systemFont(ofSize: 13)
    )

    #expect(attributed.string == "before \(ProjectOutlineAttachmentInlineCodec.objectReplacement) after")
    #expect(ProjectOutlineAttachmentInlineCodec.markdown(from: attributed) == markdown)
  }

  @Test func replacingAttachmentCanRenameDisplayLabelWithoutChangingPath() {
    let root = URL(fileURLWithPath: "/tmp/vault")
    let markdown = "see [Report.pdf](raw/assets/Report.pdf)"
    let replacement = ProjectOutlineInlineAttachment(
      displayName: "Final.pdf",
      relativePath: "raw/assets/Report.pdf",
      fileURL: root.appendingPathComponent("raw/assets/Report.pdf")
    )

    let renamed = ProjectOutlineAttachmentInlineCodec.markdownByReplacingAttachment(
      in: markdown,
      matching: "raw/assets/Report.pdf",
      with: replacement
    )

    #expect(renamed == "see [Final.pdf](raw/assets/Report.pdf)")
  }

  @Test func removingAttachmentDropsOnlyMatchingLink() {
    let markdown = "[A.pdf](raw/assets/A.pdf) [B.pdf](raw/assets/B.pdf)"

    let removed = ProjectOutlineAttachmentInlineCodec.markdownByReplacingAttachment(
      in: markdown,
      matching: "raw/assets/A.pdf",
      with: nil
    )

    #expect(removed == " [B.pdf](raw/assets/B.pdf)")
  }

  @Test func replacingAllAttachmentsUpdatesDuplicateReferences() {
    let root = URL(fileURLWithPath: "/tmp/vault")
    let markdown = "[A.pdf](raw/assets/A.pdf) and [old.pdf](raw/assets/A.pdf)"
    let replacement = ProjectOutlineInlineAttachment(
      displayName: "Renamed.pdf",
      relativePath: "raw/assets/A.pdf",
      fileURL: root.appendingPathComponent("raw/assets/A.pdf")
    )

    let renamed = ProjectOutlineAttachmentInlineCodec.markdownByReplacingAllAttachments(
      in: markdown,
      matching: "raw/assets/A.pdf",
      with: replacement
    )

    #expect(renamed == "[Renamed.pdf](raw/assets/A.pdf) and [Renamed.pdf](raw/assets/A.pdf)")
  }

  @Test func attachmentLabelsCanContainClosingBracket() {
    let root = URL(fileURLWithPath: "/tmp/vault")
    let attachment = ProjectOutlineInlineAttachment(
      displayName: "A]B.pdf",
      relativePath: "raw/assets/A%5DB.pdf",
      fileURL: root.appendingPathComponent("raw/assets/A]B.pdf")
    )
    let markdown = ProjectOutlineAttachmentInlineCodec.markdownLink(for: attachment)

    let parsed = ProjectOutlineAttachmentInlineCodec.attachments(
      in: markdown,
      vaultRootURL: root
    )

    #expect(markdown == "[A\\]B.pdf](raw/assets/A%5DB.pdf)")
    #expect(parsed.first?.displayName == "A]B.pdf")
  }

  @Test func containsAttachmentRecognizesOnlyAttachmentLinks() {
    #expect(ProjectOutlineAttachmentInlineCodec.containsAttachment(in: "[A](raw/assets/A.pdf)"))
    #expect(!ProjectOutlineAttachmentInlineCodec.containsAttachment(in: "[A](https://example.com)"))
  }

  @Test func attachmentChipUsesRegularFontScale() throws {
    let font = NSFont.systemFont(ofSize: 15)
    let attachment = ProjectOutlineInlineAttachment(
      displayName: "Report.pdf",
      relativePath: "raw/assets/Report.pdf",
      fileURL: URL(fileURLWithPath: "/tmp/vault/raw/assets/Report.pdf")
    )

    let attributed = ProjectOutlineAttachmentInlineCodec.attributedChip(
      for: attachment,
      font: font
    )
    let textAttachment = try #require(
      attributed.attribute(.attachment, at: 0, effectiveRange: nil)
        as? ProjectOutlineAttachmentTextAttachment
    )

    #expect(textAttachment.image?.size.height ?? 0 <= 21)
    #expect(textAttachment.bounds.height <= 21)
  }
}
