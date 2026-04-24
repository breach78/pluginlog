import Foundation

enum ProjectNoteAttachmentEmbedding {
  static let scheme = "buf-attachment"

  struct TokenLineMatch: Equatable {
    let filename: String
    let attachmentID: UUID
    let fullRange: NSRange
    let filenameRange: NSRange
    let idRange: NSRange
  }

  enum Block: Equatable {
    case text(String)
    case attachment(UUID)
  }

  struct InsertionResult: Equatable {
    let text: String
    let selection: NSRange
  }

  private static let tokenPattern =
    #"\[attachment:\s*((?:\\\]|[^\]])+)\]\(buf-attachment://([0-9A-Fa-f-]{36})\)"#
  private static let tokenRegex: NSRegularExpression = {
    do {
      return try NSRegularExpression(pattern: tokenPattern)
    } catch {
      preconditionFailure("Attachment token regex must compile: \(error.localizedDescription)")
    }
  }()

  static func token(id: UUID, filename: String) -> String {
    let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayName = trimmed.isEmpty ? "Attachment" : trimmed
    let escapedName = displayName.replacingOccurrences(of: "]", with: "\\]")
    return "[attachment: \(escapedName)](\(scheme)://\(id.uuidString.lowercased()))"
  }

  static func token(for attachment: AttachmentEntity) -> String {
    token(id: attachment.id, filename: attachment.originalFilename)
  }

  static func tokenLineMatch(inEntireLine line: String) -> TokenLineMatch? {
    let nsLine = line as NSString
    let range = NSRange(location: 0, length: nsLine.length)
    guard
      let match = tokenRegex.firstMatch(in: line, options: [], range: range),
      match.range.location == 0,
      match.range.length == range.length
    else {
      return nil
    }

    let nameRange = match.range(at: 1)
    let idRange = match.range(at: 2)
    guard nameRange.location != NSNotFound, idRange.location != NSNotFound else { return nil }
    let idString = nsLine.substring(with: idRange)
    guard let attachmentID = UUID(uuidString: idString) else { return nil }

    return TokenLineMatch(
      filename: nsLine.substring(with: nameRange),
      attachmentID: attachmentID,
      fullRange: match.range,
      filenameRange: nameRange,
      idRange: idRange
    )
  }

  static func blocks(in markdown: String) -> [Block] {
    guard !markdown.isEmpty else { return [] }

    var parsed: [Block] = []
    var textBuffer: [String] = []

    func flushTextBuffer() {
      guard !textBuffer.isEmpty else { return }
      let joined = textBuffer.joined(separator: "\n")
      if !joined.isEmpty {
        parsed.append(.text(joined))
      }
      textBuffer.removeAll(keepingCapacity: true)
    }

    markdown.components(separatedBy: .newlines).forEach { line in
      if let attachmentID = attachmentID(inEntireLine: line) {
        flushTextBuffer()
        parsed.append(.attachment(attachmentID))
      } else {
        textBuffer.append(line)
      }
    }

    flushTextBuffer()
    return parsed
  }

  static func referencedAttachmentIDs(in markdown: String) -> Set<UUID> {
    Set(blocks(in: markdown).compactMap { block in
      guard case .attachment(let id) = block else { return nil }
      return id
    })
  }

  static func removingAllTokens(from markdown: String) -> String {
    removingTokens(for: referencedAttachmentIDs(in: markdown), from: markdown)
  }

  static func removingTokens(for attachmentIDs: Set<UUID>, from markdown: String) -> String {
    guard !attachmentIDs.isEmpty, !markdown.isEmpty else { return markdown }

    let filteredLines = markdown
      .components(separatedBy: .newlines)
      .filter { line in
        guard let attachmentID = attachmentID(inEntireLine: line) else { return true }
        return !attachmentIDs.contains(attachmentID)
      }

    return filteredLines.joined(separator: "\n")
  }

  static func insertTokens(
    for attachments: [AttachmentEntity],
    into markdown: String,
    selectionRange: NSRange?
  ) -> String {
    let tokens = attachments.map(token(for:)).joined(separator: "\n")
    return insertTokenBlock(tokens, into: markdown, selectionRange: selectionRange)
  }

  static func insertTokenBlock(
    _ tokenBlock: String,
    into markdown: String,
    selectionRange: NSRange?
  ) -> String {
    insertTokenBlockResult(tokenBlock, into: markdown, selectionRange: selectionRange).text
  }

  static func insertTokenBlockResult(
    _ tokenBlock: String,
    into markdown: String,
    selectionRange: NSRange?
  ) -> InsertionResult {
    guard !tokenBlock.isEmpty else {
      let baseLength = (markdown as NSString).length
      return InsertionResult(
        text: markdown,
        selection: NSRange(location: baseLength, length: 0)
      )
    }
    guard !markdown.isEmpty else {
      let insertedLength = (tokenBlock as NSString).length
      return InsertionResult(
        text: tokenBlock,
        selection: NSRange(location: insertedLength, length: 0)
      )
    }

    let nsMarkdown = markdown as NSString
    let clampedRange = clamp(selectionRange, maxLength: nsMarkdown.length)
    let insertionRange = NSRange(location: clampedRange.location, length: 0)
    let insertionLocation = insertionRange.location

    let leadingBreak = needsLeadingLineBreak(in: nsMarkdown, insertionLocation: insertionLocation)
    let trailingBreak = needsTrailingLineBreak(in: nsMarkdown, insertionLocation: insertionLocation)

    let replacement = "\(leadingBreak)\(tokenBlock)\(trailingBreak)"
    let updated = nsMarkdown.replacingCharacters(in: insertionRange, with: replacement)
    let nextLocation = insertionRange.location + (replacement as NSString).length
    return InsertionResult(
      text: updated,
      selection: NSRange(location: nextLocation, length: 0)
    )
  }

  static func insertRenderableTokenBlockResult(
    _ tokenBlock: String,
    into markdown: String,
    selectionRange: NSRange?
  ) -> InsertionResult {
    var result = insertTokenBlockResult(tokenBlock, into: markdown, selectionRange: selectionRange)
    var location = min(result.selection.location, (result.text as NSString).length)
    let nsText = result.text as NSString

    while location < nsText.length {
      let scalar = nsText.character(at: location)
      guard scalar == 10 || scalar == 13 else { break }
      location += 1
    }

    if location != result.selection.location {
      return InsertionResult(
        text: result.text,
        selection: NSRange(location: location, length: 0)
      )
    }

    guard !result.text.hasSuffix("\n") else { return result }

    result = InsertionResult(
      text: result.text + "\n",
      selection: NSRange(location: (result.text as NSString).length + 1, length: 0)
    )
    return result
  }

  private static func attachmentID(inEntireLine line: String) -> UUID? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return tokenLineMatch(inEntireLine: trimmed)?.attachmentID
  }

  private static func clamp(_ range: NSRange?, maxLength: Int) -> NSRange {
    guard let range else {
      return NSRange(location: maxLength, length: 0)
    }
    let location = min(max(0, range.location), maxLength)
    let length = min(max(0, range.length), max(0, maxLength - location))
    return NSRange(location: location, length: length)
  }

  private static func needsLeadingLineBreak(in text: NSString, insertionLocation: Int) -> String {
    guard insertionLocation > 0 else { return "" }
    let previousScalar = text.character(at: insertionLocation - 1)
    return previousScalar == 10 || previousScalar == 13 ? "" : "\n"
  }

  private static func needsTrailingLineBreak(in text: NSString, insertionLocation: Int) -> String {
    guard insertionLocation < text.length else { return "" }
    let scalar = text.character(at: insertionLocation)
    return scalar == 10 || scalar == 13 ? "" : "\n"
  }
}
