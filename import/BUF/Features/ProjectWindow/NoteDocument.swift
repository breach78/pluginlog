import Foundation

struct NoteDocument: Equatable {
  enum MutationStyle {
    case stored
    case liveEditor
  }

  struct MutationResult: Equatable {
    let markdown: String
    let selection: NSRange
  }

  var blocks: [NoteDocumentBlock]

  init(blocks: [NoteDocumentBlock] = []) {
    self.blocks = blocks
  }

  init(markdown: String) {
    self.blocks = Self.parseBlocks(from: markdown)
  }

  var markdown: String {
    Self.serialize(blocks: blocks)
  }

  var referencedAttachmentIDs: Set<UUID> {
    Set(blocks.compactMap { block in
      guard case .attachment(let attachment) = block else { return nil }
      return attachment.attachmentID
    })
  }

  static func parse(_ markdown: String) -> NoteDocument {
    NoteDocument(markdown: markdown)
  }

  static func hasAttachmentReferences(in markdown: String) -> Bool {
    !NoteDocument(markdown: markdown).referencedAttachmentIDs.isEmpty
  }

  static func attachmentBlocks(for attachments: [AttachmentEntity]) -> [NoteDocumentBlock] {
    attachments.map { attachment in
      .attachment(
        NoteAttachmentBlock(
          attachmentID: attachment.id,
          filename: attachment.originalFilename
        )
      )
    }
  }

  static func insertingAttachments(
    for attachments: [AttachmentEntity],
    into markdown: String,
    selectionRange: NSRange?,
    style: MutationStyle
  ) -> MutationResult {
    insertingBlocks(
      attachmentBlocks(for: attachments),
      into: markdown,
      selectionRange: selectionRange,
      style: style
    )
  }

  static func insertingBlocks(
    _ blocks: [NoteDocumentBlock],
    into markdown: String,
    selectionRange: NSRange?,
    style: MutationStyle
  ) -> MutationResult {
    let insertedMarkdown = serialize(blocks: blocks)
    guard !insertedMarkdown.isEmpty else {
      let selection = clampedSelection(
        selectionRange,
        maxLength: (markdown as NSString).length
      )
      return MutationResult(markdown: markdown, selection: selection)
    }

    let insertionResult =
      switch style {
      case .stored:
        ProjectNoteAttachmentEmbedding.insertTokenBlockResult(
          insertedMarkdown,
          into: markdown,
          selectionRange: selectionRange
        )
      case .liveEditor:
        ProjectNoteAttachmentEmbedding.insertRenderableTokenBlockResult(
          insertedMarkdown,
          into: markdown,
          selectionRange: selectionRange
        )
      }

    return MutationResult(
      markdown: insertionResult.text,
      selection: insertionResult.selection
    )
  }

  static func removingAttachments(
    withIDs attachmentIDs: Set<UUID>,
    from markdown: String,
    selectionRange: NSRange?
  ) -> MutationResult {
    guard !attachmentIDs.isEmpty else {
      let selection = clampedSelection(
        selectionRange,
        maxLength: (markdown as NSString).length
      )
      return MutationResult(markdown: markdown, selection: selection)
    }

    let filteredBlocks = NoteDocument(markdown: markdown).blocks.filter { block in
      guard case .attachment(let attachment) = block else { return true }
      return !attachmentIDs.contains(attachment.attachmentID)
    }
    let updatedMarkdown = serialize(blocks: filteredBlocks)
    let selection = clampedSelection(
      selectionRange,
      maxLength: (updatedMarkdown as NSString).length
    )
    return MutationResult(markdown: updatedMarkdown, selection: selection)
  }

  static func displayBlocks(
    markdown: String,
    activeAttachments: [AttachmentEntity],
    archivedAttachmentIDs: Set<UUID> = []
  ) -> [NoteDisplayBlock] {
    displayBlocks(
      document: NoteDocument(markdown: markdown),
      activeAttachments: activeAttachments,
      archivedAttachmentIDs: archivedAttachmentIDs
    )
  }

  static func displayBlocks(
    document: NoteDocument,
    activeAttachments: [AttachmentEntity],
    archivedAttachmentIDs: Set<UUID> = []
  ) -> [NoteDisplayBlock] {
    var activeAttachmentsByID = Dictionary(uniqueKeysWithValues: activeAttachments.map { ($0.id, $0) })
    var rendered: [NoteDisplayBlock] = []

    for block in document.blocks {
      switch block {
      case .paragraph(let paragraph):
        if !paragraph.markdownText.isEmpty {
          rendered.append(.text(paragraph.markdownText))
        }
      case .attachment(let attachment):
        if let resolved = activeAttachmentsByID.removeValue(forKey: attachment.attachmentID) {
          rendered.append(
            .attachment(
              NoteDisplayAttachmentBlock(
                attachmentID: resolved.id,
                filename: resolved.originalFilename,
                byteSize: resolved.byteSize,
                isLegacy: false,
                availability: .available
              )
            )
          )
        } else {
          rendered.append(
            .attachment(
              NoteDisplayAttachmentBlock(
                attachmentID: attachment.attachmentID,
                filename: attachment.filename,
                byteSize: nil,
                isLegacy: false,
                availability: archivedAttachmentIDs.contains(attachment.attachmentID) ? .archived : .missing
              )
            )
          )
        }
      }
    }

    for attachment in activeAttachments where activeAttachmentsByID[attachment.id] != nil {
      activeAttachmentsByID.removeValue(forKey: attachment.id)
      rendered.append(
        .attachment(
          NoteDisplayAttachmentBlock(
            attachmentID: attachment.id,
            filename: attachment.originalFilename,
            byteSize: attachment.byteSize,
            isLegacy: true,
            availability: .available
          )
        )
      )
    }

    return rendered
  }

  static func displaySections(
    markdown: String,
    activeAttachments: [AttachmentEntity],
    archivedAttachmentIDs: Set<UUID> = []
  ) -> NoteDisplaySections {
    displaySections(
      document: NoteDocument(markdown: markdown),
      activeAttachments: activeAttachments,
      archivedAttachmentIDs: archivedAttachmentIDs
    )
  }

  static func displaySections(
    document: NoteDocument,
    activeAttachments: [AttachmentEntity],
    archivedAttachmentIDs: Set<UUID> = []
  ) -> NoteDisplaySections {
    let renderedBlocks = displayBlocks(
      document: document,
      activeAttachments: activeAttachments,
      archivedAttachmentIDs: archivedAttachmentIDs
    )
    var bodyBlocks: [NoteDisplayBlock] = []
    var attachmentBlocks: [NoteDisplayAttachmentBlock] = []

    for block in renderedBlocks {
      switch block {
      case .text:
        bodyBlocks.append(block)
      case .attachment(let attachment):
        attachmentBlocks.append(attachment)
      }
    }

    return NoteDisplaySections(
      bodyBlocks: bodyBlocks,
      attachmentBlocks: attachmentBlocks
    )
  }

  static func serialize(blocks: [NoteDocumentBlock]) -> String {
    blocks.map { block in
      switch block {
      case .paragraph(let paragraph):
        paragraph.markdownText
      case .attachment(let attachment):
        ProjectNoteAttachmentEmbedding.token(
          id: attachment.attachmentID,
          filename: attachment.filename
        )
      }
    }
    .joined(separator: "\n")
  }

  private static func parseBlocks(from markdown: String) -> [NoteDocumentBlock] {
    guard !markdown.isEmpty else { return [] }

    let normalized = markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

    var parsed: [NoteDocumentBlock] = []
    var paragraphLines: [String] = []
    var hasBufferedParagraph = false

    func flushParagraph() {
      guard hasBufferedParagraph else { return }
      parsed.append(.paragraph(NoteParagraphBlock(markdownText: paragraphLines.joined(separator: "\n"))))
      paragraphLines.removeAll(keepingCapacity: true)
      hasBufferedParagraph = false
    }

    for rawLine in lines {
      let line = String(rawLine)
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if let match = ProjectNoteAttachmentEmbedding.tokenLineMatch(inEntireLine: trimmed) {
        flushParagraph()
        parsed.append(
          .attachment(
            NoteAttachmentBlock(
              attachmentID: match.attachmentID,
              filename: decodeTokenFilename(match.filename)
            )
          )
        )
      } else {
        paragraphLines.append(line)
        hasBufferedParagraph = true
      }
    }

    flushParagraph()
    return parsed
  }

  private static func decodeTokenFilename(_ raw: String) -> String {
    raw.replacingOccurrences(of: #"\]"#, with: "]")
  }

  private static func clampedSelection(_ selection: NSRange?, maxLength: Int) -> NSRange {
    guard let selection else {
      return NSRange(location: maxLength, length: 0)
    }

    let location = min(max(0, selection.location), maxLength)
    let availableLength = max(0, maxLength - location)
    let length = min(max(0, selection.length), availableLength)
    return NSRange(location: location, length: length)
  }
}

enum NoteDocumentBlock: Identifiable, Equatable {
  case paragraph(NoteParagraphBlock)
  case attachment(NoteAttachmentBlock)

  var id: UUID {
    switch self {
    case .paragraph(let paragraph):
      paragraph.id
    case .attachment(let attachment):
      attachment.id
    }
  }
}

struct NoteParagraphBlock: Identifiable, Equatable {
  let id: UUID
  var markdownText: String

  init(id: UUID = UUID(), markdownText: String) {
    self.id = id
    self.markdownText = markdownText
  }

  static func == (lhs: NoteParagraphBlock, rhs: NoteParagraphBlock) -> Bool {
    lhs.markdownText == rhs.markdownText
  }
}

struct NoteAttachmentBlock: Identifiable, Equatable {
  let id: UUID
  let attachmentID: UUID
  var filename: String
  var caption: String?

  init(
    id: UUID = UUID(),
    attachmentID: UUID,
    filename: String,
    caption: String? = nil
  ) {
    self.id = id
    self.attachmentID = attachmentID
    self.filename = filename
    self.caption = caption
  }

  static func == (lhs: NoteAttachmentBlock, rhs: NoteAttachmentBlock) -> Bool {
    lhs.attachmentID == rhs.attachmentID
      && lhs.filename == rhs.filename
      && lhs.caption == rhs.caption
  }
}

enum NoteDisplayAttachmentAvailability: Hashable {
  case available
  case missing
  case archived
}

enum NoteDisplayBlock: Identifiable, Equatable {
  case text(String)
  case attachment(NoteDisplayAttachmentBlock)

  var id: String {
    switch self {
    case .text(let text):
      return "text:\(text)"
    case .attachment(let attachment):
      return "attachment:\(attachment.attachmentID.uuidString):\(attachment.isLegacy):\(attachment.availability)"
    }
  }
}

struct NoteDisplayAttachmentBlock: Identifiable, Equatable {
  let attachmentID: UUID
  var filename: String
  var byteSize: Int64?
  var isLegacy: Bool
  var availability: NoteDisplayAttachmentAvailability

  var id: UUID { attachmentID }
}

struct NoteDisplaySections: Equatable {
  let bodyBlocks: [NoteDisplayBlock]
  let attachmentBlocks: [NoteDisplayAttachmentBlock]
}
