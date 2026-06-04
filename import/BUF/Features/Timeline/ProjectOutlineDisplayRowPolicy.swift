import Foundation

enum ProjectOutlineDisplayRowPolicy {
  static func canUsePlainDisplay(
    block: ProjectOutlineBlock,
    isFocused: Bool,
    isBlockSelectionActive: Bool,
    isBlockSelected: Bool,
    isHighlighted: Bool,
    dropPlacement: ProjectOutlineDropPlacement?
  ) -> Bool {
    guard !isFocused,
      !block.isTaskBlock,
      !isBlockSelectionActive,
      !isBlockSelected,
      !isHighlighted,
      dropPlacement == nil
    else {
      return false
    }
    return isPlainDisplayText(block.text)
  }

  static func isPlainDisplayText(_ text: String) -> Bool {
    !ProjectOutlineAttachmentInlineCodec.containsAttachment(in: text)
      && !containsLinkLikeText(text)
  }

  private static func containsLinkLikeText(_ text: String) -> Bool {
    text.localizedCaseInsensitiveContains("://")
      || text.localizedCaseInsensitiveContains("www.")
  }
}
