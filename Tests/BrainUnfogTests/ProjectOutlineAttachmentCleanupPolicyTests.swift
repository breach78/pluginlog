import Foundation
import Testing

@testable import BrainUnfog

struct ProjectOutlineAttachmentCleanupPolicyTests {
  @Test
  func keepsAttachmentWhenAnotherReferenceRemains() {
    let root = URL(fileURLWithPath: "/vault")
    let oldMarkdown = """
      [A.pdf](raw/assets/A.pdf)
      [A copy](raw/assets/A.pdf)
      """
    let newMarkdown = "[A copy](raw/assets/A.pdf)"

    let removed = ProjectOutlineAttachmentCleanupPolicy.removedAttachments(
      oldMarkdown: oldMarkdown,
      newMarkdown: newMarkdown,
      vaultRootURL: root
    )

    #expect(removed.isEmpty)
  }

  @Test
  func reportsAttachmentWhenLastReferenceIsRemoved() {
    let root = URL(fileURLWithPath: "/vault")

    let removed = ProjectOutlineAttachmentCleanupPolicy.removedAttachments(
      oldMarkdown: "[A.pdf](raw/assets/A.pdf) [B.pdf](raw/assets/B.pdf)",
      newMarkdown: "[B.pdf](raw/assets/B.pdf)",
      vaultRootURL: root
    )

    #expect(removed.map(\.relativePath) == ["raw/assets/A.pdf"])
  }
}
