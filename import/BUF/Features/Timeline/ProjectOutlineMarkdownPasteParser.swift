import Foundation

enum ProjectOutlineMarkdownPasteParser {
  static func blocks(from markdown: String) -> [ProjectOutlineBlock]? {
    let lines = markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)

    guard lines.contains(where: isStructuredLine) else { return nil }

    var blocks: [ProjectOutlineBlock] = []
    var headingStack: [(level: Int, depth: Int)] = []
    var paragraphLines: [String] = []
    var paragraphDepth = 0

    func flushParagraph() {
      guard !paragraphLines.isEmpty else { return }
      blocks.append(ProjectOutlineBlock(
        depth: paragraphDepth,
        text: paragraphLines.joined(separator: " ")
      ))
      paragraphLines.removeAll(keepingCapacity: true)
    }

    for line in lines {
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        flushParagraph()
        continue
      }

      if let heading = heading(from: line) {
        flushParagraph()
        while headingStack.last.map({ $0.level >= heading.level }) == true {
          headingStack.removeLast()
        }
        let depth = headingStack.last.map { $0.depth + 1 } ?? 0
        blocks.append(ProjectOutlineBlock(depth: depth, text: heading.text))
        headingStack.append((heading.level, depth))
        continue
      }

      if let item = listItem(from: line) {
        flushParagraph()
        let sectionDepth = headingStack.last.map { $0.depth + 1 } ?? 0
        blocks.append(ProjectOutlineBlock(
          depth: sectionDepth + item.indent,
          text: item.text,
          taskBinding: item.isTask
            ? ProjectOutlineTaskBinding(taskID: nil, taskExternalIdentifier: nil)
            : nil
        ))
        continue
      }

      if paragraphLines.isEmpty {
        paragraphDepth = headingStack.last.map { $0.depth + 1 } ?? 0
      }
      paragraphLines.append(strippingBlockquotePrefix(from: line))
    }

    flushParagraph()
    return blocks.isEmpty ? nil : normalized(blocks)
  }

  private static func isStructuredLine(_ line: String) -> Bool {
    heading(from: line) != nil || listItem(from: line) != nil
  }

  private static func heading(from line: String) -> (level: Int, text: String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let marker = trimmed.prefix { $0 == "#" }
    guard (1...6).contains(marker.count),
      trimmed.dropFirst(marker.count).first == " "
    else {
      return nil
    }
    let text = trimmed.dropFirst(marker.count + 1)
      .trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : (marker.count, text)
  }

  private static func listItem(
    from line: String
  ) -> (indent: Int, text: String, isTask: Bool)? {
    let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
    let trimmed = line.dropFirst(leadingWhitespace.count)
    guard let marker = trimmed.first,
      "-+*".contains(marker),
      trimmed.dropFirst().first == " "
    else {
      return nil
    }

    var content = String(trimmed.dropFirst(2))
    var isTask = false
    if content.count >= 4 {
      let prefix = content.prefix(4).lowercased()
      if prefix == "[ ] " || prefix == "[x] " {
        isTask = true
        content.removeFirst(4)
      }
    }

    let spaceCount = leadingWhitespace.reduce(into: 0) { count, character in
      count += character == "\t" ? 2 : 1
    }
    return (max(0, spaceCount / 2), content, isTask)
  }

  private static func strippingBlockquotePrefix(from line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix(">") else { return trimmed }
    return String(trimmed.dropFirst())
      .trimmingCharacters(in: .whitespaces)
  }

  private static func normalized(_ blocks: [ProjectOutlineBlock]) -> [ProjectOutlineBlock] {
    guard let minimumDepth = blocks.map(\.depth).min(), minimumDepth > 0 else {
      return blocks
    }
    return blocks.map { block in
      var result = block
      result.depth -= minimumDepth
      return result
    }
  }
}
