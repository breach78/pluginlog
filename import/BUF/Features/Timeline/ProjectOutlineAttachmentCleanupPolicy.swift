import Foundation

enum ProjectOutlineAttachmentCleanupPolicy {
  static func removedAttachments(
    oldMarkdown: String,
    newMarkdown: String,
    vaultRootURL: URL?
  ) -> [ProjectOutlineInlineAttachment] {
    let oldAttachments = ProjectOutlineAttachmentInlineCodec.attachments(
      in: oldMarkdown,
      vaultRootURL: vaultRootURL
    )
    let newPaths = Set(
      ProjectOutlineAttachmentInlineCodec.attachments(
        in: newMarkdown,
        vaultRootURL: vaultRootURL
      )
      .map(\.relativePath)
    )
    var removedByPath: [String: ProjectOutlineInlineAttachment] = [:]
    for attachment in oldAttachments where !newPaths.contains(attachment.relativePath) {
      removedByPath[attachment.relativePath] = attachment
    }
    return removedByPath.values.sorted { $0.relativePath < $1.relativePath }
  }
}
