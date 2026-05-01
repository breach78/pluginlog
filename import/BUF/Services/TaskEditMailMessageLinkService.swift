import Foundation

struct TaskEditMailMessageLink: Equatable, Sendable {
  let title: String
  let urlString: String
}

enum TaskEditMailMessageLinkService {
  static let fallbackTitle = "Apple Mail 메시지"

  static func messageLink(
    urls: [URL],
    textCandidates: [String],
    titleCandidates: [String]? = nil
  ) -> TaskEditMailMessageLink? {
    guard let urlString = firstMailMessageURLString(urls: urls, textCandidates: textCandidates) else {
      return nil
    }
    let resolvedTitleCandidates = titleCandidates ?? textCandidates
    return TaskEditMailMessageLink(
      title: displayTitle(
        from: resolvedTitleCandidates,
        subjectCandidates: uniqueStrings(resolvedTitleCandidates + textCandidates),
        excluding: urlString
      ),
      urlString: urlString
    )
  }

  static func markdownLink(for link: TaskEditMailMessageLink) -> String {
    "[\(escapedMarkdownLabel(link.title))](\(link.urlString))"
  }

  static func mailMessageURLString(in text: String) -> String? {
    let pattern = #"(?i)\bmessage:(?://)?[^\s<>"'\]\)]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let matchRange = Range(match.range, in: text)
    else {
      return nil
    }
    let raw = String(text[matchRange])
    return normalizedMailMessageURLString(raw)
  }

  private static func firstMailMessageURLString(
    urls: [URL],
    textCandidates: [String]
  ) -> String? {
    for url in urls {
      if let normalized = normalizedMailMessageURLString(url.absoluteString) {
        return normalized
      }
    }
    for text in textCandidates {
      if let normalized = mailMessageURLString(in: text) {
        return normalized
      }
    }
    for text in textCandidates {
      if let normalized = mailMessageURLStringFromHeader(in: text) {
        return normalized
      }
    }
    return nil
  }

  private static func normalizedMailMessageURLString(_ raw: String) -> String? {
    let trimmed = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'"))
      .trimmingTrailingCharacters(in: CharacterSet(charactersIn: ".,;"))
    guard let url = URL(string: trimmed), url.scheme?.lowercased() == "message" else {
      return nil
    }
    return trimmed
  }

  private static func mailMessageURLStringFromHeader(in text: String) -> String? {
    let pattern = #"(?im)^Message-ID:\s*<([^>\r\n]+)>"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let idRange = Range(match.range(at: 1), in: text)
    else {
      return nil
    }
    let messageID = String(text[idRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !messageID.isEmpty else { return nil }
    let encodedID = encodedMailMessageID(messageID)
    return "message://%3C\(encodedID)%3E"
  }

  private static func displayTitle(
    from textCandidates: [String],
    subjectCandidates: [String],
    excluding urlString: String
  ) -> String {
    let fallback = fallbackTitle
    if let subject = subjectTitle(from: subjectCandidates) {
      return subject
    }
    for candidate in textCandidates {
      let normalized = candidate
        .replacingOccurrences(of: urlString, with: " ")
        .replacingOccurrences(of: urlString.removingPercentEncoding ?? urlString, with: " ")
        .replacingOccurrences(
          of: #"<[^>]+>"#,
          with: " ",
          options: .regularExpression
        )
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
      let lines = normalized
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      if let title = lines.first(where: { line in
        !line.isEmpty && mailMessageURLString(in: line) == nil
      }) {
        return String(title.prefix(160))
      }
    }
    return fallback
  }

  private static func subjectTitle(from textCandidates: [String]) -> String? {
    let pattern = #"(?im)^Subject:\s*(.+)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    for candidate in textCandidates {
      let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
      guard let match = regex.firstMatch(in: candidate, range: range),
        let subjectRange = Range(match.range(at: 1), in: candidate)
      else {
        continue
      }
      let subject = String(candidate[subjectRange])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !subject.isEmpty {
        return String(subject.prefix(160))
      }
    }
    return nil
  }

  private static func uniqueStrings(_ values: [String]) -> [String] {
    var result: [String] = []
    for value in values where !result.contains(value) {
      result.append(value)
    }
    return result
  }

  private static func escapedMarkdownLabel(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "[", with: "\\[")
      .replacingOccurrences(of: "]", with: "\\]")
  }

  private static func encodedMailMessageID(_ messageID: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "<>[]()")
    return messageID.addingPercentEncoding(withAllowedCharacters: allowed) ?? messageID
  }
}

private extension String {
  func trimmingTrailingCharacters(in characterSet: CharacterSet) -> String {
    var result = self
    while let scalar = result.unicodeScalars.last, characterSet.contains(scalar) {
      result.removeLast()
    }
    return result
  }
}
