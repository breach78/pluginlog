import AppKit
import Foundation
import UniformTypeIdentifiers

enum TaskInlineVerticalDirection {
  case up
  case down
}

let supportedAttachmentDropTypes: [UTType] = [
  .fileURL,
  .png,
  .jpeg,
  .tiff,
  .heic,
  .image,
]

enum TaskInlineCursorPlacement {
  case start
  case end
  case preserve
}

enum MarkdownLivePreviewStyler {
  struct AttachmentPreviewParagraph: Equatable {
    let attachmentID: UUID
    let paragraphRange: NSRange
    let visibleRange: NSRange
  }

  private static let listLeadingInset: CGFloat = 10
  private static let listMarkerTrailingGap: CGFloat = 2
  private static let orderedListAlignmentSample = "000"
  private static let markdownSignalCharacterSet = CharacterSet(charactersIn: "#>*+_`~[]()")
  private static let headingRegex = makeRegex(
    pattern: #"^(#{1,6})(\s+)(.+)$"#, options: [.anchorsMatchLines])
  private static let blockquoteRegex = makeRegex(
    pattern: #"^(\s*>\s+)(.+)$"#, options: [.anchorsMatchLines])
  private static let checklistRegex = makeRegex(
    pattern: #"^(\s*[-*+]\s+\[(?: |x|X)\]\s+)(.+)$"#, options: [.anchorsMatchLines])
  private static let unorderedListRegex = makeRegex(
    pattern: #"^(\s*[-*+]\s+)(.+)$"#, options: [.anchorsMatchLines])
  private static let orderedListRegex = makeRegex(
    pattern: #"^(\s*\d+[.)]\s+)(.+)$"#, options: [.anchorsMatchLines])
  private static let horizontalRuleRegex = makeRegex(
    pattern: #"^\s*(?:[-*_]\s*){3,}$"#, options: [.anchorsMatchLines])
  private static let markdownLinkRegex = makeRegex(
    pattern: #"\[([^\]]+)\]\(([^)\s][^)]*)\)"#)
  private static let inlineCodeRegex = makeRegex(pattern: #"`([^`\n]+)`"#)
  private static let boldRegex = makeRegex(pattern: #"(\*\*|__)(.+?)(\1)"#)
  private static let italicAsteriskRegex = makeRegex(
    pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
  private static let italicUnderscoreRegex = makeRegex(
    pattern: #"(?<!_)_([^_\n]+)_(?!_)"#)
  private static let strikethroughRegex = makeRegex(pattern: #"~~([^~\n]+)~~"#)
  private static let bareLinkDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue)

  static func attributedString(
    for rawText: String,
    fontSize: CGFloat,
    lineSpacing: CGFloat,
    editingParagraphRange: NSRange?,
    collapsesInactiveHeadingPrefixes: Bool = false,
    fontProvider: ((CGFloat, NSFont.Weight) -> NSFont)? = nil
  ) -> NSAttributedString {
    let nsText = rawText as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    let rendered = NSMutableAttributedString(string: rawText)
    let resolvedFontProvider = fontProvider ?? { size, weight in
      NoteTypography.nsFont(size: size, weight: weight)
    }
    let baseFont = resolvedFontProvider(fontSize, .regular)
    let baseParagraphStyle = paragraphStyle(lineSpacing: lineSpacing)
    let baseAttributes: [NSAttributedString.Key: Any] = [
      .font: baseFont,
      .paragraphStyle: baseParagraphStyle,
      .foregroundColor: NSColor.textColor,
    ]

    if fullRange.length > 0 {
      rendered.setAttributes(baseAttributes, range: fullRange)
    }

    guard requiresStyledPresentation(for: rawText) else {
      return rendered
    }

    var excludedLinkRanges: [NSRange] = []
    var paragraphLocation = 0
    while paragraphLocation < nsText.length {
      let paragraphRange = nsText.paragraphRange(
        for: NSRange(location: paragraphLocation, length: 0))
      let visibleRange = visibleRange(for: paragraphRange, in: nsText)
      defer { paragraphLocation = NSMaxRange(paragraphRange) }

      guard visibleRange.length > 0 else { continue }
      let paragraphText = nsText.substring(with: visibleRange)
      if let tokenMatch = ProjectNoteAttachmentEmbedding.tokenLineMatch(inEntireLine: paragraphText) {
        excludedLinkRanges.append(visibleRange)
        styleAttachmentTokenParagraph(
          tokenMatch,
          paragraphRange: paragraphRange,
          visibleRange: visibleRange,
          fontSize: fontSize,
          lineSpacing: lineSpacing,
          rendered: rendered,
          fontProvider: resolvedFontProvider
        )
        continue
      }
      guard
        shouldRender(paragraphRange: paragraphRange, editingParagraphRange: editingParagraphRange)
      else { continue }
      styleParagraph(
        paragraphText,
        paragraphRange: paragraphRange,
        visibleRange: visibleRange,
        fontSize: fontSize,
        lineSpacing: lineSpacing,
        rendered: rendered,
        excludedLinkRanges: &excludedLinkRanges,
        collapsesInactiveHeadingPrefixes: collapsesInactiveHeadingPrefixes,
        fontProvider: resolvedFontProvider
      )
    }

    applyBareLinks(
      to: rendered,
      rawText: rawText,
      excludedRanges: excludedLinkRanges,
      editingParagraphRange: editingParagraphRange,
      fontSize: fontSize,
      fontProvider: resolvedFontProvider
    )

    return rendered
  }

  static func renderedAttachmentPreviewParagraphs(
    in rawText: String,
    editingParagraphRange: NSRange?
  ) -> [AttachmentPreviewParagraph] {
    let nsText = rawText as NSString
    var paragraphs: [AttachmentPreviewParagraph] = []
    var paragraphLocation = 0

    while paragraphLocation < nsText.length {
      let paragraphRange = nsText.paragraphRange(
        for: NSRange(location: paragraphLocation, length: 0))
      let visibleRange = visibleRange(for: paragraphRange, in: nsText)
      defer { paragraphLocation = NSMaxRange(paragraphRange) }

      guard visibleRange.length > 0 else { continue }
      let paragraphText = nsText.substring(with: visibleRange)
      guard let tokenMatch = ProjectNoteAttachmentEmbedding.tokenLineMatch(inEntireLine: paragraphText)
      else {
        guard
          shouldRender(paragraphRange: paragraphRange, editingParagraphRange: editingParagraphRange)
        else { continue }
        continue
      }

      paragraphs.append(
        AttachmentPreviewParagraph(
          attachmentID: tokenMatch.attachmentID,
          paragraphRange: paragraphRange,
          visibleRange: visibleRange
        )
      )
    }

    return paragraphs
  }

  static func requiresStyledPresentation(for rawText: String) -> Bool {
    if rawText.isEmpty {
      return false
    }

    if rawText.contains("http://")
      || rawText.contains("https://")
      || rawText.contains("www.")
      || rawText.contains("- [")
      || rawText.contains("* ")
      || rawText.contains("- ")
      || rawText.contains("+ ")
      || rawText.contains("~~")
      || rawText.contains("**")
      || rawText.contains("__")
    {
      return true
    }

    return rawText.rangeOfCharacter(from: markdownSignalCharacterSet) != nil
  }

  private static func shouldRender(paragraphRange: NSRange, editingParagraphRange: NSRange?) -> Bool
  {
    guard let editingParagraphRange else { return true }
    return NSIntersectionRange(paragraphRange, editingParagraphRange).length == 0
  }

  private static func visibleRange(for paragraphRange: NSRange, in text: NSString) -> NSRange {
    var length = paragraphRange.length
    while length > 0 {
      let scalar = text.character(at: paragraphRange.location + length - 1)
      guard scalar == 10 || scalar == 13 else { break }
      length -= 1
    }
    return NSRange(location: paragraphRange.location, length: length)
  }

  private static func paragraphStyle(
    lineSpacing: CGFloat,
    headIndent: CGFloat = 0,
    firstLineHeadIndent: CGFloat = 0,
    spacingBefore: CGFloat = 0,
    spacingAfter: CGFloat = 0
  ) -> NSMutableParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = lineSpacing
    paragraph.headIndent = headIndent
    paragraph.firstLineHeadIndent = firstLineHeadIndent
    paragraph.paragraphSpacingBefore = spacingBefore
    paragraph.paragraphSpacing = spacingAfter
    paragraph.tabStops = []
    return paragraph
  }

  private static func continuationIndent(
    for prefix: String, font: NSFont, extraPadding: CGFloat = 4
  ) -> CGFloat {
    let width = ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
    return max(0, width + extraPadding)
  }

  private enum MarkdownListKind {
    case checklist
    case unordered
    case ordered
  }

  private struct MarkdownListPrefixComponents {
    let leadingWhitespace: String
    let marker: String
    let trailingWhitespace: String
    let markerRangeInPrefix: NSRange

    var trailingMarkerRangeInPrefix: NSRange? {
      guard markerRangeInPrefix.length > 0 else { return nil }
      return NSRange(location: NSMaxRange(markerRangeInPrefix) - 1, length: 1)
    }
  }

  private struct MarkdownListLayout {
    let paragraphStyle: NSMutableParagraphStyle
    let trailingMarkerRangeInPrefix: NSRange?
    let trailingMarkerKern: CGFloat?
  }

  private static func listPrefixComponents(for prefix: String) -> MarkdownListPrefixComponents {
    let nsPrefix = prefix as NSString
    let length = nsPrefix.length
    var leadingLength = 0
    while leadingLength < length {
      let scalar = nsPrefix.character(at: leadingLength)
      guard scalar == 9 || scalar == 32 else { break }
      leadingLength += 1
    }

    var trailingLength = 0
    while trailingLength < length - leadingLength {
      let scalar = nsPrefix.character(at: length - trailingLength - 1)
      guard scalar == 9 || scalar == 32 else { break }
      trailingLength += 1
    }

    let markerLength = max(0, length - leadingLength - trailingLength)
    let markerRange = NSRange(location: leadingLength, length: markerLength)

    return MarkdownListPrefixComponents(
      leadingWhitespace: nsPrefix.substring(with: NSRange(location: 0, length: leadingLength)),
      marker: markerLength > 0 ? nsPrefix.substring(with: markerRange) : "",
      trailingWhitespace: trailingLength > 0
        ? nsPrefix.substring(with: NSRange(location: length - trailingLength, length: trailingLength))
        : "",
      markerRangeInPrefix: markerRange
    )
  }

  private static func renderedWidth(of text: String, font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width)
  }

  private static func listLayout(
    for prefix: String,
    font: NSFont,
    lineSpacing: CGFloat,
    kind: MarkdownListKind
  ) -> MarkdownListLayout {
    let components = listPrefixComponents(for: prefix)
    let leadingWhitespaceWidth = renderedWidth(of: components.leadingWhitespace, font: font)
    let markerWidth = renderedWidth(of: components.marker, font: font)
    let trailingWhitespaceWidth = renderedWidth(of: components.trailingWhitespace, font: font)
    let actualMarkerSlotWidth = markerWidth + listMarkerTrailingGap
    let orderedAlignmentSlotWidth =
      renderedWidth(of: "\(orderedListAlignmentSample).", font: font) + listMarkerTrailingGap

    let reservedMarkerSlotWidth: CGFloat
    switch kind {
    case .ordered:
      reservedMarkerSlotWidth = orderedAlignmentSlotWidth
    case .unordered:
      reservedMarkerSlotWidth = orderedAlignmentSlotWidth
    case .checklist:
      reservedMarkerSlotWidth = actualMarkerSlotWidth
    }

    let firstLineHeadIndent =
      listLeadingInset + leadingWhitespaceWidth
      + max(0, reservedMarkerSlotWidth - actualMarkerSlotWidth)
    let headIndent = listLeadingInset + leadingWhitespaceWidth + reservedMarkerSlotWidth

    return MarkdownListLayout(
      paragraphStyle: paragraphStyle(
        lineSpacing: lineSpacing,
        headIndent: headIndent,
        firstLineHeadIndent: firstLineHeadIndent,
        spacingAfter: 1
      ),
      trailingMarkerRangeInPrefix: components.trailingMarkerRangeInPrefix,
      trailingMarkerKern: components.trailingMarkerRangeInPrefix == nil
        ? nil
        : (listMarkerTrailingGap - trailingWhitespaceWidth)
    )
  }

  private static func styleParagraph(
    _ paragraphText: String,
    paragraphRange: NSRange,
    visibleRange: NSRange,
    fontSize: CGFloat,
    lineSpacing: CGFloat,
    rendered: NSMutableAttributedString,
    excludedLinkRanges: inout [NSRange],
    collapsesInactiveHeadingPrefixes: Bool,
    fontProvider: (CGFloat, NSFont.Weight) -> NSFont
  ) {
    let baseFont = fontProvider(fontSize, .regular)
    let syntaxFont = fontProvider(max(11, fontSize * 0.86), .regular)
    let italicizedBaseFont = italicFont(from: baseFont)
    let headingFontSizes: [CGFloat] = [
      max(fontSize + 11, 26), max(fontSize + 8, 22), max(fontSize + 5, 19), max(fontSize + 3, 17),
      max(fontSize + 1, 15), fontSize,
    ]

    let paragraphNS = paragraphText as NSString
    let localRange = NSRange(location: 0, length: paragraphNS.length)
    let syntaxAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.55),
      .font: syntaxFont,
    ]

    if let tokenMatch = ProjectNoteAttachmentEmbedding.tokenLineMatch(inEntireLine: paragraphText) {
      excludedLinkRanges.append(visibleRange)
      styleAttachmentTokenParagraph(
        tokenMatch,
        paragraphRange: paragraphRange,
        visibleRange: visibleRange,
        fontSize: fontSize,
        lineSpacing: lineSpacing,
        rendered: rendered,
        fontProvider: fontProvider
      )
      return
    }

    if horizontalRuleRegex?.firstMatch(in: paragraphText, options: [], range: localRange) != nil {
      rendered.addAttributes(
        [
          .foregroundColor: NSColor.separatorColor,
          .paragraphStyle: paragraphStyle(
            lineSpacing: lineSpacing,
            spacingBefore: 4,
            spacingAfter: 4
          ),
        ],
        range: visibleRange
      )
      return
    }

    if let match = headingRegex?.firstMatch(in: paragraphText, options: [], range: localRange) {
      let level = max(1, min(6, match.range(at: 1).length))
      let prefixRange = globalRange(
        from: NSRange(
          location: match.range.location,
          length: match.range(at: 1).length + match.range(at: 2).length),
        offset: visibleRange.location)
      let contentRange = globalRange(from: match.range(at: 3), offset: visibleRange.location)
      rendered.addAttributes(
        [
          .font: fontProvider(headingFontSizes[level - 1], level <= 2 ? .bold : .semibold),
          .paragraphStyle: paragraphStyle(
            lineSpacing: max(2, lineSpacing * 0.5),
            spacingBefore: level == 1 ? 6 : 3,
            spacingAfter: 4
          ),
        ],
        range: paragraphRange
      )
      rendered.addAttributes(
        [
          .foregroundColor: NSColor.clear,
          .font: collapsesInactiveHeadingPrefixes
            ? fontProvider(0.1, .regular)
            : syntaxFont,
        ],
        range: prefixRange
      )
      rendered.addAttribute(.foregroundColor, value: NSColor.textColor, range: contentRange)
    } else if let match = checklistRegex?.firstMatch(
      in: paragraphText, options: [], range: localRange)
    {
      let prefixRange = globalRange(from: match.range(at: 1), offset: visibleRange.location)
      let contentRange = globalRange(from: match.range(at: 2), offset: visibleRange.location)
      let prefix = paragraphNS.substring(with: match.range(at: 1))
      let isChecked = prefix.contains("[x]") || prefix.contains("[X]")
      let layout = listLayout(for: prefix, font: syntaxFont, lineSpacing: lineSpacing, kind: .checklist)
      rendered.addAttributes(
        [
          .paragraphStyle: layout.paragraphStyle
        ],
        range: paragraphRange
      )
      rendered.addAttributes(
        [
          .foregroundColor: (isChecked ? NSColor.systemGreen : NSColor.secondaryLabelColor)
            .withAlphaComponent(0.75),
          .font: syntaxFont,
        ],
        range: prefixRange
      )
      if let trailingMarkerRangeInPrefix = layout.trailingMarkerRangeInPrefix,
        let trailingMarkerKern = layout.trailingMarkerKern
      {
        rendered.addAttribute(
          .kern,
          value: trailingMarkerKern,
          range: globalRange(from: trailingMarkerRangeInPrefix, offset: prefixRange.location)
        )
      }
      if isChecked {
        rendered.addAttributes(
          [
            .foregroundColor: NSColor.secondaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: NSColor.secondaryLabelColor.withAlphaComponent(0.7),
          ],
          range: contentRange
        )
      }
    } else if let match = blockquoteRegex?.firstMatch(
      in: paragraphText, options: [], range: localRange)
    {
      let prefixRange = globalRange(from: match.range(at: 1), offset: visibleRange.location)
      let prefix = paragraphNS.substring(with: match.range(at: 1))
      let indent = continuationIndent(for: prefix, font: syntaxFont)
      rendered.addAttributes(syntaxAttributes, range: prefixRange)
      rendered.addAttributes(
        [
          .paragraphStyle: paragraphStyle(
            lineSpacing: lineSpacing,
            headIndent: indent,
            firstLineHeadIndent: 0,
            spacingAfter: 1
          )
        ],
        range: paragraphRange
      )
    } else if let match = orderedListRegex?.firstMatch(
      in: paragraphText, options: [], range: localRange)
    {
      let prefixRange = globalRange(from: match.range(at: 1), offset: visibleRange.location)
      let prefix = paragraphNS.substring(with: match.range(at: 1))
      let layout = listLayout(for: prefix, font: syntaxFont, lineSpacing: lineSpacing, kind: .ordered)
      rendered.addAttributes(syntaxAttributes, range: prefixRange)
      if let trailingMarkerRangeInPrefix = layout.trailingMarkerRangeInPrefix,
        let trailingMarkerKern = layout.trailingMarkerKern
      {
        rendered.addAttribute(
          .kern,
          value: trailingMarkerKern,
          range: globalRange(from: trailingMarkerRangeInPrefix, offset: prefixRange.location)
        )
      }
      rendered.addAttributes(
        [
          .paragraphStyle: layout.paragraphStyle
        ],
        range: paragraphRange
      )
    } else if let match = unorderedListRegex?.firstMatch(
      in: paragraphText, options: [], range: localRange)
    {
      let prefixRange = globalRange(from: match.range(at: 1), offset: visibleRange.location)
      let prefix = paragraphNS.substring(with: match.range(at: 1))
      let layout = listLayout(for: prefix, font: syntaxFont, lineSpacing: lineSpacing, kind: .unordered)
      rendered.addAttributes(syntaxAttributes, range: prefixRange)
      if let trailingMarkerRangeInPrefix = layout.trailingMarkerRangeInPrefix,
        let trailingMarkerKern = layout.trailingMarkerKern
      {
        rendered.addAttribute(
          .kern,
          value: trailingMarkerKern,
          range: globalRange(from: trailingMarkerRangeInPrefix, offset: prefixRange.location)
        )
      }
      rendered.addAttributes(
        [
          .paragraphStyle: layout.paragraphStyle
        ],
        range: paragraphRange
      )
    }

    excludedLinkRanges.append(
      contentsOf: applyMarkdownLinks(
        in: paragraphText,
        offset: visibleRange.location,
        rendered: rendered,
        fontSize: fontSize,
        fontProvider: fontProvider
      ))
    applyInlineCode(
      in: paragraphText,
      offset: visibleRange.location,
      rendered: rendered,
      fontSize: fontSize,
      fontProvider: fontProvider
    )
    applyDelimitedStyle(
      regex: strikethroughRegex,
      paragraphText: paragraphText,
      offset: visibleRange.location,
      contentAttributes: [
        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        .strikethroughColor: NSColor.secondaryLabelColor.withAlphaComponent(0.7),
        .foregroundColor: NSColor.secondaryLabelColor,
      ],
      delimiterAttributes: syntaxAttributes,
      rendered: rendered,
      leadingDelimiterRange: { match in
        match.range(at: 0).location == NSNotFound
          ? nil : NSRange(location: match.range.location, length: 2)
      },
      contentRange: { $0.range(at: 1) },
      trailingDelimiterRange: { match in
        let full = match.range(at: 0)
        return NSRange(location: full.location + full.length - 2, length: 2)
      }
    )
    applyDelimitedStyle(
      regex: boldRegex,
      paragraphText: paragraphText,
      offset: visibleRange.location,
      contentAttributes: [.font: fontProvider(fontSize, .semibold)],
      delimiterAttributes: syntaxAttributes,
      rendered: rendered,
      leadingDelimiterRange: { $0.range(at: 1) },
      contentRange: { $0.range(at: 2) },
      trailingDelimiterRange: { $0.range(at: 3) }
    )
    applyDelimitedStyle(
      regex: italicAsteriskRegex,
      paragraphText: paragraphText,
      offset: visibleRange.location,
      contentAttributes: [.font: italicizedBaseFont],
      delimiterAttributes: syntaxAttributes,
      rendered: rendered,
      leadingDelimiterRange: { match in NSRange(location: match.range.location, length: 1) },
      contentRange: { $0.range(at: 1) },
      trailingDelimiterRange: { match in
        let full = match.range(at: 0)
        return NSRange(location: full.location + full.length - 1, length: 1)
      }
    )
    applyDelimitedStyle(
      regex: italicUnderscoreRegex,
      paragraphText: paragraphText,
      offset: visibleRange.location,
      contentAttributes: [.font: italicizedBaseFont],
      delimiterAttributes: syntaxAttributes,
      rendered: rendered,
      leadingDelimiterRange: { match in NSRange(location: match.range.location, length: 1) },
      contentRange: { $0.range(at: 1) },
      trailingDelimiterRange: { match in
        let full = match.range(at: 0)
        return NSRange(location: full.location + full.length - 1, length: 1)
      }
    )
  }

  private static func styleAttachmentTokenParagraph(
    _ tokenMatch: ProjectNoteAttachmentEmbedding.TokenLineMatch,
    paragraphRange: NSRange,
    visibleRange: NSRange,
    fontSize: CGFloat,
    lineSpacing: CGFloat,
    rendered: NSMutableAttributedString,
    fontProvider: (CGFloat, NSFont.Weight) -> NSFont
  ) {
    let hiddenFont = fontProvider(0.1, .regular)
    let displayRange = globalRange(from: tokenMatch.filenameRange, offset: visibleRange.location)
    let prefixRange = NSRange(
      location: visibleRange.location,
      length: max(0, tokenMatch.filenameRange.location)
    )
    let suffixLocation = tokenMatch.filenameRange.location + tokenMatch.filenameRange.length
    let suffixRange = NSRange(
      location: visibleRange.location + suffixLocation,
      length: max(0, tokenMatch.fullRange.length - suffixLocation)
    )
    let paragraphStyle = paragraphStyle(
      lineSpacing: max(0, lineSpacing * 0.35),
      headIndent: 34,
      firstLineHeadIndent: 34,
      spacingBefore: 4,
      spacingAfter: 4
    )
    paragraphStyle.tailIndent = -26
    rendered.addAttributes(
      [
        .paragraphStyle: paragraphStyle,
        .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.72),
      ],
      range: visibleRange
    )

    if prefixRange.length > 0 {
      rendered.addAttributes(
        [
          .foregroundColor: NSColor.clear,
          .font: hiddenFont,
        ],
        range: prefixRange
      )
    }

    if suffixRange.length > 0 {
      rendered.addAttributes(
        [
          .foregroundColor: NSColor.clear,
          .font: hiddenFont,
        ],
        range: suffixRange
      )
    }

    rendered.addAttributes(
      [
        .font: fontProvider(fontSize, .regular),
        .foregroundColor: NSColor.textColor,
        .underlineStyle: 0,
      ],
      range: displayRange
    )
  }

  private static func applyMarkdownLinks(
    in paragraphText: String,
    offset: Int,
    rendered: NSMutableAttributedString,
    fontSize: CGFloat,
    fontProvider: (CGFloat, NSFont.Weight) -> NSFont
  ) -> [NSRange] {
    let paragraphNS = paragraphText as NSString
    let localRange = NSRange(location: 0, length: paragraphNS.length)
    let syntaxAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.55),
      .font: fontProvider(max(11, fontSize * 0.86), .regular),
    ]
    var ranges: [NSRange] = []

    guard let markdownLinkRegex else { return ranges }

    for match in markdownLinkRegex.matches(in: paragraphText, options: [], range: localRange) {
      let full = globalRange(from: match.range(at: 0), offset: offset)
      let label = globalRange(from: match.range(at: 1), offset: offset)
      let destination = paragraphNS.substring(with: match.range(at: 2))
      let leadingSyntax = NSRange(
        location: full.location, length: max(0, label.location - full.location))
      let trailingSyntaxStart = NSMaxRange(label)
      let trailingSyntax = NSRange(
        location: trailingSyntaxStart, length: max(0, NSMaxRange(full) - trailingSyntaxStart))

      if leadingSyntax.length > 0 {
        rendered.addAttributes(syntaxAttributes, range: leadingSyntax)
      }
      if trailingSyntax.length > 0 {
        rendered.addAttributes(syntaxAttributes, range: trailingSyntax)
      }

      rendered.addAttributes(
        [
          .foregroundColor: NSColor.linkColor,
          .underlineStyle: NSUnderlineStyle.single.rawValue,
        ],
        range: label
      )

      if let url = normalizedURL(from: destination) {
        rendered.addAttribute(.link, value: url, range: label)
      }

      ranges.append(full)
    }

    return ranges
  }

  private static func applyInlineCode(
    in paragraphText: String,
    offset: Int,
    rendered: NSMutableAttributedString,
    fontSize: CGFloat,
    fontProvider: (CGFloat, NSFont.Weight) -> NSFont
  ) {
    let paragraphNS = paragraphText as NSString
    let localRange = NSRange(location: 0, length: paragraphNS.length)
    let syntaxAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.55),
      .font: fontProvider(max(11, fontSize * 0.86), .regular),
    ]

    guard let inlineCodeRegex else { return }

    for match in inlineCodeRegex.matches(in: paragraphText, options: [], range: localRange) {
      let full = match.range(at: 0)
      let content = match.range(at: 1)
      let globalContent = globalRange(from: content, offset: offset)
      let leadingTick = globalRange(
        from: NSRange(location: full.location, length: 1), offset: offset)
      let trailingTick = globalRange(
        from: NSRange(location: full.location + full.length - 1, length: 1), offset: offset)

      rendered.addAttributes(syntaxAttributes, range: leadingTick)
      rendered.addAttributes(syntaxAttributes, range: trailingTick)
      rendered.addAttributes(
        [
          .font: fontProvider(max(12, fontSize * 0.95), .regular),
          .backgroundColor: NSColor.controlBackgroundColor,
          .foregroundColor: NSColor.labelColor,
        ],
        range: globalContent
      )
    }
  }

  private static func applyDelimitedStyle(
    regex: NSRegularExpression?,
    paragraphText: String,
    offset: Int,
    contentAttributes: [NSAttributedString.Key: Any],
    delimiterAttributes: [NSAttributedString.Key: Any],
    rendered: NSMutableAttributedString,
    leadingDelimiterRange: (NSTextCheckingResult) -> NSRange?,
    contentRange: (NSTextCheckingResult) -> NSRange,
    trailingDelimiterRange: (NSTextCheckingResult) -> NSRange?
  ) {
    guard let regex else { return }
    let paragraphNS = paragraphText as NSString
    let localRange = NSRange(location: 0, length: paragraphNS.length)
    for match in regex.matches(in: paragraphText, options: [], range: localRange) {
      if let leading = leadingDelimiterRange(match), leading.length > 0 {
        rendered.addAttributes(
          delimiterAttributes, range: globalRange(from: leading, offset: offset))
      }
      let content = contentRange(match)
      if content.length > 0 {
        rendered.addAttributes(contentAttributes, range: globalRange(from: content, offset: offset))
      }
      if let trailing = trailingDelimiterRange(match), trailing.length > 0 {
        rendered.addAttributes(
          delimiterAttributes, range: globalRange(from: trailing, offset: offset))
      }
    }
  }

  private static func applyBareLinks(
    to rendered: NSMutableAttributedString,
    rawText: String,
    excludedRanges: [NSRange],
    editingParagraphRange: NSRange?,
    fontSize: CGFloat,
    fontProvider: (CGFloat, NSFont.Weight) -> NSFont
  ) {
    guard let detector = bareLinkDetector else { return }
    let nsText = rawText as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    guard fullRange.length > 0 else { return }

    detector.enumerateMatches(in: rawText, options: [], range: fullRange) { result, _, _ in
      guard let result, result.resultType == .link, result.range.length > 0 else { return }
      guard excludedRanges.allSatisfy({ NSIntersectionRange($0, result.range).length == 0 }) else {
        return
      }
      if let editingParagraphRange,
        NSIntersectionRange(editingParagraphRange, result.range).length > 0
      {
        return
      }
      guard let url = result.url else { return }
      rendered.addAttributes(
        [
          .link: url,
          .foregroundColor: NSColor.linkColor,
          .underlineStyle: NSUnderlineStyle.single.rawValue,
          .font: fontProvider(fontSize, .regular),
        ],
        range: result.range
      )
    }
  }

  private static func italicFont(from baseFont: NSFont) -> NSFont {
    NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
  }

  private static func makeRegex(
    pattern: String,
    options: NSRegularExpression.Options = []
  ) -> NSRegularExpression? {
    do {
      return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
      AppLogger.ui.error(
        "markdown regex compile failed. pattern=\(pattern, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  private static func normalizedURL(from destination: String) -> URL? {
    if let direct = URL(string: destination), direct.scheme != nil {
      return direct
    }
    if destination.lowercased().hasPrefix("www.") {
      return URL(string: "https://\(destination)")
    }
    return URL(string: destination)
  }

  private static func globalRange(from localRange: NSRange, offset: Int) -> NSRange {
    NSRange(location: localRange.location + offset, length: localRange.length)
  }
}
