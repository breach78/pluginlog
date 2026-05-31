import Foundation

enum ProjectOutlineMarkdownCodec {
  static func document(from markdown: String) -> ProjectOutlineDocument {
    let rawLines = markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)

    let blocks = rawLines.compactMap(block(from:))
    return ProjectOutlineDocument(blocks: blocks)
  }

  static func markdown(from document: ProjectOutlineDocument) -> String {
    document.blocks.map(line(from:)).joined(separator: "\n")
  }

  private static func block(from line: String) -> ProjectOutlineBlock? {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    let leadingSpaces = line.prefix { $0 == " " }.count
    let trimmedLeading = String(line.dropFirst(leadingSpaces))
    guard trimmedLeading.hasPrefix("- ") else {
      return ProjectOutlineBlock(depth: 0, text: ProjectOutlineTextCodec.decoded(line))
    }

    let depth = leadingSpaces / 2
    let content = String(trimmedLeading.dropFirst(2))
    if let marker = ProjectOutlineTaskMarkerCodec.marker(from: content) {
      return ProjectOutlineBlock(
        id: marker.blockID,
        depth: depth,
        text: "",
        taskBinding: marker.binding
      )
    }

    return ProjectOutlineBlock(depth: depth, text: ProjectOutlineTextCodec.decoded(content))
  }

  private static func line(from block: ProjectOutlineBlock) -> String {
    let indent = String(repeating: "  ", count: max(0, block.depth))
    if let binding = block.taskBinding {
      return indent + "- " + ProjectOutlineTaskMarkerCodec.marker(
        blockID: block.id,
        binding: binding
      )
    }
    return indent + "- " + ProjectOutlineTextCodec.encoded(block.text)
  }
}

enum ProjectOutlineTextCodec {
  static func encoded(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\n", with: "\\n")
  }

  static func decoded(_ text: String) -> String {
    var result = ""
    var isEscaping = false

    for character in text {
      if isEscaping {
        result.append(character == "n" ? "\n" : character)
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
}

enum ProjectOutlineTaskMarkerCodec {
  struct Marker: Equatable {
    let blockID: UUID
    let binding: ProjectOutlineTaskBinding
  }

  private static let prefix = "{{buf-task"
  private static let suffix = "}}"
  private static let knownKeys: Set<String> = ["block", "task", "external"]

  static func marker(from text: String) -> Marker? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix) else { return nil }

    let bodyStart = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
    let bodyEnd = trimmed.index(trimmed.endIndex, offsetBy: -suffix.count)
    let body = String(trimmed[bodyStart..<bodyEnd])
    let attributes = parseAttributes(in: body)
    guard let blockValue = attributes["block"], let blockID = UUID(uuidString: blockValue) else {
      return nil
    }

    let taskID = attributes["task"].flatMap(UUID.init(uuidString:))
    let preserved = attributes.filter { !knownKeys.contains($0.key) }
    return Marker(
      blockID: blockID,
      binding: ProjectOutlineTaskBinding(
        taskID: taskID,
        taskExternalIdentifier: attributes["external"],
        preservedAttributes: preserved
      )
    )
  }

  static func marker(blockID: UUID, binding: ProjectOutlineTaskBinding) -> String {
    var attributes = binding.preservedAttributes
    attributes["block"] = blockID.uuidString
    if let taskID = binding.taskID {
      attributes["task"] = taskID.uuidString
    }
    if let external = binding.taskExternalIdentifier, !external.isEmpty {
      attributes["external"] = external
    }

    let orderedKeys = ["block", "task", "external"]
      + attributes.keys.filter { !knownKeys.contains($0) }.sorted()
    let body = orderedKeys.compactMap { key -> String? in
      guard let value = attributes[key] else { return nil }
      return #"\#(key)="\#(escapedAttributeValue(value))""#
    }
    .joined(separator: " ")
    return "{{buf-task \(body)}}"
  }

  private static func parseAttributes(in text: String) -> [String: String] {
    guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z][A-Za-z0-9_-]*)="([^"]*)""#)
    else {
      return [:]
    }

    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    var attributes: [String: String] = [:]
    regex.enumerateMatches(in: text, range: range) { match, _, _ in
      guard let match, match.numberOfRanges == 3 else { return }
      let key = nsText.substring(with: match.range(at: 1))
      let value = nsText.substring(with: match.range(at: 2))
      attributes[key] = unescapedAttributeValue(value)
    }
    return attributes
  }

  private static func escapedAttributeValue(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }

  private static func unescapedAttributeValue(_ value: String) -> String {
    var result = ""
    var isEscaping = false
    for character in value {
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
}
