import Foundation

enum LinkedTextEditorMarkdownPresentationMode {
  case source
  case livePreview
}

struct LinkedTextEditorMarkdownListInputReplacement: Equatable {
  let range: NSRange
  let text: String
}

struct LinkedTextEditorMarkdownListParagraph: Equatable {
  let range: NSRange
  let prefix: String
  let markerRange: NSRange
}

enum LinkedTextEditorMarkdownListInputPolicy {
  private enum ListMarkerKind: Equatable {
    case bullet
    case ordered(Int)
  }

  private struct ListLine {
    let lineRange: NSRange
    let prefixRange: NSRange
    let content: String
    let markerKind: ListMarkerKind
    let level: Int

    var hasContent: Bool {
      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private static let markerColumnWidth = 4
  private static let nestingWidth = 4
  private static let listPrefixRegex = try! NSRegularExpression(
    pattern: #"^([ ]*)(-|\d{1,3}\.)[ ]+"#
  )

  static func replacement(
    in text: String,
    affectedRange: NSRange,
    replacementString: String
  ) -> LinkedTextEditorMarkdownListInputReplacement? {
    guard affectedRange.length == 0 else { return nil }
    if replacementString == " " {
      return spaceReplacement(in: text, affectedRange: affectedRange)
    }
    if replacementString == "\t" {
      return tabReplacement(in: text, affectedRange: affectedRange)
    }
    if replacementString.contains(where: \.isNewline) {
      return newlineReplacement(in: text, affectedRange: affectedRange)
    }
    return nil
  }

  private static func spaceReplacement(
    in text: String,
    affectedRange: NSRange
  ) -> LinkedTextEditorMarkdownListInputReplacement? {
    let nsString = text as NSString
    guard affectedRange.location <= nsString.length else { return nil }

    let lineRange = nsString.lineRange(for: NSRange(location: affectedRange.location, length: 0))
    let prefixRange = NSRange(
      location: lineRange.location,
      length: affectedRange.location - lineRange.location
    )
    guard prefixRange.length >= 1 else { return nil }

    let prefix = nsString.substring(with: prefixRange)
    let leadingSpaces = prefix.prefix { $0 == " " }.count
    let level = leadingSpaces / nestingWidth
    let marker = prefix.trimmingCharacters(in: .whitespaces)
    if marker == "-" {
      return LinkedTextEditorMarkdownListInputReplacement(
        range: prefixRange,
        text: bulletPrefix(level: level)
      )
    }
    guard let number = orderedListNumber(in: marker) else { return nil }
    return LinkedTextEditorMarkdownListInputReplacement(
      range: prefixRange,
      text: orderedPrefix(number: number, level: level)
    )
  }

  private static func newlineReplacement(
    in text: String,
    affectedRange: NSRange
  ) -> LinkedTextEditorMarkdownListInputReplacement? {
    guard let line = listLine(in: text, at: affectedRange.location) else { return nil }
    guard line.hasContent else {
      return emptyLineReplacement(in: text, line: line)
    }

    let nextPrefix: String
    switch line.markerKind {
    case .bullet:
      nextPrefix = bulletPrefix(level: line.level)
    case .ordered(let number):
      nextPrefix = orderedPrefix(number: number + 1, level: line.level)
    }
    return LinkedTextEditorMarkdownListInputReplacement(
      range: affectedRange,
      text: "\n\(nextPrefix)"
    )
  }

  private static func emptyLineReplacement(
    in text: String,
    line: ListLine
  ) -> LinkedTextEditorMarkdownListInputReplacement {
    guard line.level > 0 else {
      return LinkedTextEditorMarkdownListInputReplacement(range: line.prefixRange, text: "")
    }

    let nextLevel = line.level - 1
    let nextPrefix = outdentedPrefix(in: text, before: line.lineRange.location, level: nextLevel)
      ?? defaultPrefix(for: line.markerKind, level: nextLevel)
    return LinkedTextEditorMarkdownListInputReplacement(
      range: line.prefixRange,
      text: nextPrefix
    )
  }

  private static func tabReplacement(
    in text: String,
    affectedRange: NSRange
  ) -> LinkedTextEditorMarkdownListInputReplacement? {
    guard let line = listLine(in: text, at: affectedRange.location) else { return nil }
    let nextLevel = line.level + 1
    let nextPrefix: String
    switch line.markerKind {
    case .bullet:
      nextPrefix = bulletPrefix(level: nextLevel)
    case .ordered:
      nextPrefix = orderedPrefix(number: 1, level: nextLevel)
    }
    return LinkedTextEditorMarkdownListInputReplacement(
      range: line.prefixRange,
      text: nextPrefix
    )
  }

  private static func outdentedPrefix(
    in text: String,
    before location: Int,
    level: Int
  ) -> String? {
    let nsString = text as NSString
    var searchLocation = max(0, min(location, nsString.length))
    while searchLocation > 0 {
      let lineRange = nsString.lineRange(
        for: NSRange(location: searchLocation - 1, length: 0)
      )
      if let previousLine = listLine(in: text, at: lineRange.location) {
        if previousLine.level == level {
          return nextPrefix(after: previousLine)
        }
        if previousLine.level < level {
          return nil
        }
      }
      searchLocation = lineRange.location
    }
    return nil
  }

  private static func listLine(in text: String, at location: Int) -> ListLine? {
    let nsString = text as NSString
    guard location <= nsString.length else { return nil }
    let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
    let line = nsString.substring(with: lineRange)
    let lineSearchRange = NSRange(location: 0, length: (line as NSString).length)
    guard let match = listPrefixRegex.firstMatch(in: line, range: lineSearchRange),
      match.numberOfRanges >= 3
    else {
      return nil
    }

    let leadingSpaces = (line as NSString).substring(with: match.range(at: 1)).utf16.count
    let marker = (line as NSString).substring(with: match.range(at: 2))
    let markerKind: ListMarkerKind
    if marker == "-" {
      markerKind = .bullet
    } else if let number = orderedListNumber(in: marker) {
      markerKind = .ordered(number)
    } else {
      return nil
    }

    let prefixRange = NSRange(
      location: lineRange.location + match.range.location,
      length: match.range.length
    )
    let contentLocation = prefixRange.upperBound
    let contentRange = NSRange(
      location: contentLocation,
      length: max(0, lineRange.upperBound - contentLocation)
    )
    return ListLine(
      lineRange: lineRange,
      prefixRange: prefixRange,
      content: nsString.substring(with: contentRange),
      markerKind: markerKind,
      level: listLevel(leadingSpaces: leadingSpaces, marker: marker)
    )
  }

  private static func orderedListNumber(in marker: String) -> Int? {
    guard marker.hasSuffix(".") else { return nil }
    let digits = marker.dropLast()
    guard (1...3).contains(digits.count), digits.allSatisfy(\.isNumber) else { return nil }
    return Int(digits)
  }

  private static func nextPrefix(after line: ListLine) -> String {
    switch line.markerKind {
    case .bullet:
      return bulletPrefix(level: line.level)
    case .ordered(let number):
      return orderedPrefix(number: number + 1, level: line.level)
    }
  }

  private static func defaultPrefix(for markerKind: ListMarkerKind, level: Int) -> String {
    switch markerKind {
    case .bullet:
      return bulletPrefix(level: level)
    case .ordered:
      return orderedPrefix(number: 1, level: level)
    }
  }

  private static func bulletPrefix(level: Int) -> String {
    "\(String(repeating: " ", count: max(0, level) * nestingWidth + 3))- "
  }

  private static func orderedPrefix(number: Int, level: Int) -> String {
    let marker = "\(number)."
    let paddingWidth = max(0, markerColumnWidth - marker.utf16.count)
    return "\(String(repeating: " ", count: max(0, level) * nestingWidth + paddingWidth))\(marker) "
  }

  private static func listLevel(leadingSpaces: Int, marker: String) -> Int {
    let basePadding: Int
    if marker == "-" {
      basePadding = 3
    } else {
      basePadding = max(0, markerColumnWidth - marker.utf16.count)
    }
    let formattedLevel = leadingSpaces >= basePadding
      ? (leadingSpaces - basePadding) / nestingWidth
      : 0
    return max(formattedLevel, leadingSpaces / nestingWidth)
  }
}

struct LinkedTextEditorMarkdownPreviewDecoration: Equatable {
  enum Kind: Equatable {
    case hiddenSyntax
    case strong
    case emphasis
    case inlineCode
    case strikethrough
    case heading(Int)
  }

  let kind: Kind
  let range: NSRange
}

enum LinkedTextEditorMarkdownPreviewPolicy {
  private static let listPrefixRegex = try! NSRegularExpression(
    pattern: #"(?m)^([ ]*)(-|\d{1,3}\.)[ ]+"#
  )
  private static let markdownLinkRegex = try! NSRegularExpression(
    pattern: #"!?\[([^\]]+)\]\(([^)]+)\)"#
  )
  private static let headingRegex = try! NSRegularExpression(
    pattern: #"(?m)^(#{1,6})[ \t]+(.+)$"#
  )
  private static let strongAsteriskRegex = try! NSRegularExpression(
    pattern: #"(?<!\*)\*\*(?!\s)(.+?)(?<!\s)\*\*(?!\*)"#
  )
  private static let strongUnderscoreRegex = try! NSRegularExpression(
    pattern: #"(?<!_)__(?!\s)(.+?)(?<!\s)__(?!_)"#
  )
  private static let emphasisAsteriskRegex = try! NSRegularExpression(
    pattern: #"(?<!\*)\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)"#
  )
  private static let inlineCodeRegex = try! NSRegularExpression(
    pattern: #"`([^`\n]+)`"#
  )
  private static let strikethroughRegex = try! NSRegularExpression(
    pattern: #"~~([^~\n]+)~~"#
  )

  static func hasPreviewCandidates(in text: String) -> Bool {
    text.contains("](")
      || text.contains("#")
      || text.contains("*")
      || text.contains("__")
      || text.contains("`")
      || text.contains("~~")
  }

  static func hasListCandidates(in text: String) -> Bool {
    text.contains("- ") || text.contains(". ")
  }

  static func listParagraphs(in text: String) -> [LinkedTextEditorMarkdownListParagraph] {
    guard hasListCandidates(in: text) else { return [] }
    let nsString = text as NSString
    let range = NSRange(location: 0, length: nsString.length)
    return listPrefixRegex.matches(in: text, range: range).map { match in
      LinkedTextEditorMarkdownListParagraph(
        range: nsString.lineRange(for: NSRange(location: match.range.location, length: 0)),
        prefix: nsString.substring(with: match.range),
        markerRange: match.range(at: 2)
      )
    }
  }

  static func activeLineRanges(in text: String, selectedRanges: [NSRange]) -> [NSRange] {
    let nsString = text as NSString
    let length = nsString.length
    guard length > 0 else {
      return [NSRange(location: 0, length: 0)]
    }

    let ranges = selectedRanges.isEmpty ? [NSRange(location: 0, length: 0)] : selectedRanges
    var activeLines: [NSRange] = []
    for range in ranges {
      let lowerBound = min(max(range.location, 0), length)
      let upperBound = min(max(range.location + range.length, lowerBound), length)
      let effectiveUpperBound = range.length > 0
        ? max(lowerBound, upperBound - 1)
        : lowerBound
      appendLineRanges(
        from: lowerBound,
        through: effectiveUpperBound,
        in: nsString,
        to: &activeLines
      )
    }
    return activeLines
  }

  static func activeLineRanges(
    in text: String,
    selectedRanges: [NSRange],
    isEditorActive: Bool
  ) -> [NSRange] {
    guard isEditorActive else { return [] }
    return activeLineRanges(in: text, selectedRanges: selectedRanges)
  }

  static func decorations(
    in text: String,
    activeLineRanges: [NSRange]
  ) -> [LinkedTextEditorMarkdownPreviewDecoration] {
    guard hasPreviewCandidates(in: text) else { return [] }
    let range = NSRange(location: 0, length: (text as NSString).length)
    var decorations: [LinkedTextEditorMarkdownPreviewDecoration] = []
    appendHeadingDecorations(
      in: text,
      range: range,
      activeLineRanges: activeLineRanges,
      to: &decorations
    )
    appendLinkDecorations(
      in: text,
      range: range,
      activeLineRanges: activeLineRanges,
      to: &decorations
    )
    appendDelimitedDecorations(
      in: text,
      regex: strongAsteriskRegex,
      kind: .strong,
      activeLineRanges: activeLineRanges,
      to: &decorations
    )
    appendDelimitedDecorations(
      in: text,
      regex: strongUnderscoreRegex,
      kind: .strong,
      activeLineRanges: activeLineRanges,
      to: &decorations
    )
    appendDelimitedDecorations(
      in: text,
      regex: emphasisAsteriskRegex,
      kind: .emphasis,
      activeLineRanges: activeLineRanges,
      to: &decorations
    )
    appendDelimitedDecorations(
      in: text,
      regex: inlineCodeRegex,
      kind: .inlineCode,
      activeLineRanges: activeLineRanges,
      to: &decorations
    )
    appendDelimitedDecorations(
      in: text,
      regex: strikethroughRegex,
      kind: .strikethrough,
      activeLineRanges: activeLineRanges,
      to: &decorations
    )
    return decorations.sorted {
      if $0.range.location == $1.range.location {
        return $0.range.length < $1.range.length
      }
      return $0.range.location < $1.range.location
    }
  }

  private static func appendLineRanges(
    from lowerBound: Int,
    through upperBound: Int,
    in nsString: NSString,
    to activeLines: inout [NSRange]
  ) {
    var lineRange = nsString.lineRange(for: NSRange(location: lowerBound, length: 0))
    appendUnique(lineRange, to: &activeLines)
    var nextLocation = NSMaxRange(lineRange)
    while nextLocation <= upperBound && nextLocation < nsString.length {
      lineRange = nsString.lineRange(for: NSRange(location: nextLocation, length: 0))
      appendUnique(lineRange, to: &activeLines)
      nextLocation = NSMaxRange(lineRange)
    }
  }

  private static func appendUnique(_ range: NSRange, to ranges: inout [NSRange]) {
    guard !ranges.contains(range) else { return }
    ranges.append(range)
  }

  private static func appendHeadingDecorations(
    in text: String,
    range: NSRange,
    activeLineRanges: [NSRange],
    to decorations: inout [LinkedTextEditorMarkdownPreviewDecoration]
  ) {
    for match in headingRegex.matches(in: text, range: range) {
      guard shouldDecorate(match.range, activeLineRanges: activeLineRanges),
        match.numberOfRanges >= 3
      else { continue }
      let level = (text as NSString).substring(with: match.range(at: 1)).utf16.count
      let contentRange = match.range(at: 2)
      appendHiddenSyntax(around: contentRange, in: match.range, to: &decorations)
      decorations.append(
        LinkedTextEditorMarkdownPreviewDecoration(kind: .heading(level), range: contentRange)
      )
    }
  }

  private static func appendLinkDecorations(
    in text: String,
    range: NSRange,
    activeLineRanges: [NSRange],
    to decorations: inout [LinkedTextEditorMarkdownPreviewDecoration]
  ) {
    for match in markdownLinkRegex.matches(in: text, range: range) {
      guard shouldDecorate(match.range, activeLineRanges: activeLineRanges),
        match.numberOfRanges >= 2
      else { continue }
      appendHiddenSyntax(around: match.range(at: 1), in: match.range, to: &decorations)
    }
  }

  private static func appendDelimitedDecorations(
    in text: String,
    regex: NSRegularExpression,
    kind: LinkedTextEditorMarkdownPreviewDecoration.Kind,
    activeLineRanges: [NSRange],
    to decorations: inout [LinkedTextEditorMarkdownPreviewDecoration]
  ) {
    let range = NSRange(location: 0, length: (text as NSString).length)
    for match in regex.matches(in: text, range: range) {
      guard shouldDecorate(match.range, activeLineRanges: activeLineRanges),
        match.numberOfRanges >= 2
      else { continue }
      let contentRange = match.range(at: 1)
      appendHiddenSyntax(around: contentRange, in: match.range, to: &decorations)
      decorations.append(LinkedTextEditorMarkdownPreviewDecoration(kind: kind, range: contentRange))
    }
  }

  private static func appendHiddenSyntax(
    around contentRange: NSRange,
    in matchRange: NSRange,
    to decorations: inout [LinkedTextEditorMarkdownPreviewDecoration]
  ) {
    let leadingRange = NSRange(
      location: matchRange.location,
      length: max(0, contentRange.location - matchRange.location)
    )
    let trailingRange = NSRange(
      location: NSMaxRange(contentRange),
      length: max(0, NSMaxRange(matchRange) - NSMaxRange(contentRange))
    )
    if leadingRange.length > 0 {
      decorations.append(
        LinkedTextEditorMarkdownPreviewDecoration(kind: .hiddenSyntax, range: leadingRange)
      )
    }
    if trailingRange.length > 0 {
      decorations.append(
        LinkedTextEditorMarkdownPreviewDecoration(kind: .hiddenSyntax, range: trailingRange)
      )
    }
  }

  private static func shouldDecorate(_ range: NSRange, activeLineRanges: [NSRange]) -> Bool {
    !activeLineRanges.contains { NSIntersectionRange(range, $0).length > 0 }
  }
}
