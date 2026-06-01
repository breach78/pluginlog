import AppKit
import Foundation

struct ProjectOutlineInlineAttachment: Equatable, Hashable, Identifiable {
  let displayName: String
  let relativePath: String
  let fileURL: URL

  var id: String { relativePath }

  init(displayName: String, relativePath: String, fileURL: URL) {
    self.displayName = displayName
    self.relativePath = relativePath
    self.fileURL = fileURL
  }

  init(_ attachment: TaskEditAttachment) {
    self.displayName = attachment.displayName
    self.relativePath = attachment.relativePath
    self.fileURL = attachment.fileURL
  }

  var taskEditAttachment: TaskEditAttachment {
    TaskEditAttachment(
      displayName: displayName,
      relativePath: relativePath,
      fileURL: fileURL
    )
  }
}

final class ProjectOutlineAttachmentTextAttachment: NSTextAttachment {
  let outlineAttachment: ProjectOutlineInlineAttachment

  init(attachment: ProjectOutlineInlineAttachment, font: NSFont) {
    self.outlineAttachment = attachment
    super.init(data: nil, ofType: nil)
    image = ProjectOutlineAttachmentChipRenderer.image(for: attachment, font: font)
  }

  required init?(coder: NSCoder) {
    nil
  }
}

enum ProjectOutlineAttachmentInlineCodec {
  static let attachmentAttribute = NSAttributedString.Key("ProjectOutlineAttachment")
  static let objectReplacement = "\u{fffc}"

  static func attributedString(
    from markdown: String,
    vaultRootURL: URL?,
    font: NSFont
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let nsMarkdown = markdown as NSString
    var cursor = 0

    for match in attachmentMatches(in: markdown) {
      guard match.range.location >= cursor else { continue }
      if match.range.location > cursor {
        result.append(
          NSAttributedString(
            string: nsMarkdown.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
            attributes: textAttributes(font: font)
          )
        )
      }
      result.append(attributedChip(for: match.attachment(vaultRootURL: vaultRootURL), font: font))
      cursor = match.range.location + match.range.length
    }

    if cursor < nsMarkdown.length {
      result.append(
        NSAttributedString(
          string: nsMarkdown.substring(from: cursor),
          attributes: textAttributes(font: font)
        )
      )
    }
    return result
  }

  static func attributedChip(
    for attachment: ProjectOutlineInlineAttachment,
    font: NSFont
  ) -> NSAttributedString {
    let textAttachment = ProjectOutlineAttachmentTextAttachment(
      attachment: attachment,
      font: font
    )
    let chip = NSMutableAttributedString(attachment: textAttachment)
    chip.addAttribute(attachmentAttribute, value: attachment, range: NSRange(location: 0, length: chip.length))
    return chip
  }

  static func markdown(from attributedString: NSAttributedString) -> String {
    var output = ""
    var index = 0
    while index < attributedString.length {
      let range = NSRange(location: index, length: 1)
      if let attachment = attributedString.attribute(
        attachmentAttribute,
        at: index,
        effectiveRange: nil
      ) as? ProjectOutlineInlineAttachment {
        output += markdownLink(for: attachment)
      } else {
        let value = attributedString.attributedSubstring(from: range).string
        if value != objectReplacement {
          output += value
        }
      }
      index += 1
    }
    return output
  }

  static func markdownLink(for attachment: ProjectOutlineInlineAttachment) -> String {
    "[\(escapedLabel(attachment.displayName))](\(attachment.relativePath))"
  }

  static func attachments(in markdown: String, vaultRootURL: URL?) -> [ProjectOutlineInlineAttachment] {
    attachmentMatches(in: markdown).map { $0.attachment(vaultRootURL: vaultRootURL) }
  }

  static func markdownByReplacingAttachment(
    in markdown: String,
    matching relativePath: String,
    with replacement: ProjectOutlineInlineAttachment?
  ) -> String {
    let matches = attachmentMatches(in: markdown)
    guard let match = matches.first(where: { $0.relativePath == relativePath }) else {
      return markdown
    }
    let nsMarkdown = markdown as NSString
    let next = replacement.map(markdownLink) ?? ""
    return nsMarkdown.replacingCharacters(in: match.range, with: next)
  }

  static func markdownByReplacingAllAttachments(
    in markdown: String,
    matching relativePath: String,
    with replacement: ProjectOutlineInlineAttachment?
  ) -> String {
    let matches = attachmentMatches(in: markdown)
      .filter { $0.relativePath == relativePath }
      .reversed()
    guard !matches.isEmpty else { return markdown }
    let result = NSMutableString(string: markdown)
    let next = replacement.map(markdownLink) ?? ""
    for match in matches {
      result.replaceCharacters(in: match.range, with: next)
    }
    return result as String
  }

  private static func attachmentMatches(in markdown: String) -> [AttachmentMatch] {
    guard let regex = attachmentRegex else { return [] }
    let nsMarkdown = markdown as NSString
    let range = NSRange(location: 0, length: nsMarkdown.length)
    return regex.matches(in: markdown, range: range).compactMap { match in
      guard match.numberOfRanges == 3 else { return nil }
      return AttachmentMatch(
        range: match.range,
        displayName: unescapedLabel(nsMarkdown.substring(with: match.range(at: 1))),
        relativePath: nsMarkdown.substring(with: match.range(at: 2))
      )
    }
  }

  private static func textAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
    [.font: font, .foregroundColor: NSColor.labelColor]
  }

  private static let attachmentRegex = try? NSRegularExpression(
    pattern: #"!?\[((?:\\.|[^\]])+)\]\((raw/assets/[^)]+)\)"#
  )

  private static func escapedLabel(_ label: String) -> String {
    label
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "]", with: "\\]")
  }

  private static func unescapedLabel(_ label: String) -> String {
    var result = ""
    var isEscaping = false
    for character in label {
      if isEscaping {
        result.append(character)
        isEscaping = false
      } else if character == "\\" {
        isEscaping = true
      } else {
        result.append(character)
      }
    }
    if isEscaping {
      result.append("\\")
    }
    return result
  }

  private struct AttachmentMatch {
    let range: NSRange
    let displayName: String
    let relativePath: String

    func attachment(vaultRootURL: URL?) -> ProjectOutlineInlineAttachment {
      let decodedPath = relativePath.removingPercentEncoding ?? relativePath
      let fileURL = vaultRootURL?
        .appendingPathComponent(decodedPath)
        .standardizedFileURL
        ?? URL(fileURLWithPath: decodedPath)
      return ProjectOutlineInlineAttachment(
        displayName: displayName,
        relativePath: relativePath,
        fileURL: fileURL
      )
    }
  }
}

private enum ProjectOutlineAttachmentChipRenderer {
  static func image(for attachment: ProjectOutlineInlineAttachment, font: NSFont) -> NSImage {
    let label = attachment.displayName as NSString
    let labelFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: labelFont,
      .foregroundColor: NSColor.labelColor,
    ]
    let textSize = label.size(withAttributes: attributes)
    let height: CGFloat = max(22, ceil(textSize.height) + 6)
    let width: CGFloat = min(260, ceil(textSize.width) + 34)
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    NSColor.controlBackgroundColor.withAlphaComponent(0.86).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()

    NSColor.secondaryLabelColor.setStroke()
    NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()

    if let icon = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil) {
      icon.size = NSSize(width: 13, height: 13)
      icon.draw(in: NSRect(x: 8, y: (height - 13) / 2, width: 13, height: 13))
    }
    label.draw(
      in: NSRect(x: 26, y: (height - textSize.height) / 2 - 1, width: width - 32, height: textSize.height + 2),
      withAttributes: attributes
    )
    return image
  }
}
