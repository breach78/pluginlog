import Foundation

enum ObsidianProjectNoteParser {
  static func parse(_ markdown: String) -> ObsidianProjectNote {
    let normalizedMarkdown = normalizeLineEndings(markdown)
    let lines = normalizedMarkdown.components(separatedBy: "\n")
    var diagnostics: [ObsidianProjectNoteDiagnostic] = []

    let frontmatterResult = parseFrontmatter(lines: lines)
    let frontmatter = frontmatterResult.frontmatter
    let bodyStartIndex = frontmatterResult.bodyStartIndex
    if frontmatterResult.isUnclosed {
      diagnostics.append(.unclosedFrontmatter)
    }

    let bodyLines = Array(lines.dropFirst(bodyStartIndex))
    let taskInfos = parseTaskInfos(bodyLines)
    let tasks = taskInfos.map { info -> ObsidianProjectTask in
      let metadataResult = parseMetadata(
        after: info.lineIndex,
        taskIndentationCount: info.indentationCount,
        bodyLines: bodyLines
      )
      if case let .damaged(line, rawLine) = metadataResult.diagnostic {
        diagnostics.append(.damagedTaskMetadata(line: line, rawLine: rawLine))
      }

      return ObsidianProjectTask(
        bodyLineIndex: info.lineIndex,
        metadataLineIndex: metadataResult.lineIndex,
        indentation: info.indentation,
        title: info.title,
        isCompleted: info.isCompleted,
        blockIdentifier: info.blockIdentifier,
        metadata: metadataResult.metadata,
        rawMetadataLine: metadataResult.rawLine,
        metadataIsDamaged: metadataResult.diagnostic != nil,
        subtreeMarkdown: subtreeMarkdown(
          for: info,
          metadataLineIndex: metadataResult.lineIndex,
          bodyLines: bodyLines
        )
      )
    }

    return ObsidianProjectNote(
      frontmatter: frontmatter,
      bodyMarkdown: bodyLines.joined(separator: "\n"),
      tasks: tasks,
      diagnostics: diagnostics,
      normalizedContentHash: stableFingerprint(normalizedMarkdown)
    )
  }

  static func parseFrontmatterOnly(_ markdown: String) -> ObsidianProjectFrontmatter? {
    let normalizedMarkdown = normalizeLineEndings(markdown)
    let lines = normalizedMarkdown.components(separatedBy: "\n")
    return parseFrontmatter(lines: lines).frontmatter
  }

  private struct FrontmatterResult {
    var frontmatter: ObsidianProjectFrontmatter?
    var bodyStartIndex: Int
    var isUnclosed: Bool
  }

  private struct TaskInfo {
    var lineIndex: Int
    var indentation: String
    var indentationCount: Int
    var title: String
    var isCompleted: Bool
    var blockIdentifier: String?
  }

  private enum MetadataDiagnostic {
    case damaged(line: Int, rawLine: String)
  }

  private enum MetadataCandidate {
    case none
    case valid(String)
    case damaged
  }

  private struct MetadataResult {
    var lineIndex: Int?
    var metadata: ObsidianTaskMetadata?
    var rawLine: String?
    var diagnostic: MetadataDiagnostic?
  }

  private static func parseFrontmatter(lines: [String]) -> FrontmatterResult {
    guard lines.first == "---" else {
      return FrontmatterResult(frontmatter: nil, bodyStartIndex: 0, isUnclosed: false)
    }
    guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else {
      return FrontmatterResult(frontmatter: nil, bodyStartIndex: 0, isUnclosed: true)
    }

    let rawLines = Array(lines[1..<closingIndex])
    let parsed = parseFrontmatterLines(rawLines)
    return FrontmatterResult(
      frontmatter: parsed,
      bodyStartIndex: closingIndex + 1,
      isUnclosed: false
    )
  }

  private static func parseFrontmatterLines(_ lines: [String]) -> ObsidianProjectFrontmatter {
    var tags: [String] = []
    var listID: String?
    var hideCompletedTasks = true
    var isArchived = false
    var consumed: Set<Int> = []

    for index in lines.indices {
      let line = lines[index]
      guard let keyValue = yamlKeyValue(line) else { continue }
      switch keyValue.key {
      case "tags":
        consumed.insert(index)
        tags.append(contentsOf: parseInlineTags(keyValue.value))
        var cursor = index + 1
        while cursor < lines.count {
          let candidate = lines[cursor]
          let trimmed = candidate.trimmingCharacters(in: .whitespaces)
          guard candidate.hasPrefix(" "), trimmed.hasPrefix("- ") else { break }
          consumed.insert(cursor)
          if let tag = normalizedTag(String(trimmed.dropFirst(2))) {
            tags.append(tag)
          }
          cursor += 1
        }
      case "reminder_list_external_id":
        consumed.insert(index)
        listID = normalizedScalar(keyValue.value)
      case "완료 가리기":
        consumed.insert(index)
        hideCompletedTasks = boolScalar(keyValue.value)
      case "아카이브":
        consumed.insert(index)
        isArchived = boolScalar(keyValue.value)
      case "brain_unfog_project_id", "brain_unfog_task_id":
        consumed.insert(index)
      default:
        break
      }
    }

    let preserved = lines.enumerated().compactMap { index, line in
      consumed.contains(index) ? nil : line
    }
    return ObsidianProjectFrontmatter(
      tags: unique(tags.compactMap(normalizedTag)),
      reminderListExternalIdentifier: listID,
      preservedLines: preserved,
      hideCompletedTasks: hideCompletedTasks,
      isArchived: isArchived
    )
  }

  private static func parseTaskInfos(_ lines: [String]) -> [TaskInfo] {
    lines.enumerated().compactMap { index, line in
      parseTaskInfo(line, lineIndex: index)
    }
  }

  private static func parseTaskInfo(_ line: String, lineIndex: Int) -> TaskInfo? {
    let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
    let markerStart = line.dropFirst(indentation.count)
    guard markerStart.hasPrefix("- [") else { return nil }
    let markerEndIndex = markerStart.index(markerStart.startIndex, offsetBy: 4, limitedBy: markerStart.endIndex)
    guard let markerEndIndex,
      markerEndIndex < markerStart.endIndex,
      markerStart[markerEndIndex] == "]",
      markerStart.index(after: markerEndIndex) < markerStart.endIndex,
      markerStart[markerStart.index(after: markerEndIndex)] == " "
    else {
      return nil
    }

    let statusIndex = markerStart.index(markerStart.startIndex, offsetBy: 3)
    let status = markerStart[statusIndex]
    guard status == " " || status == "x" || status == "X" else { return nil }

    let titleStart = markerStart.index(markerEndIndex, offsetBy: 2)
    var title = String(markerStart[titleStart...])
    let blockIdentifier = removeTrailingBlockIdentifier(from: &title)

    return TaskInfo(
      lineIndex: lineIndex,
      indentation: indentation,
      indentationCount: indentationWidth(indentation),
      title: title.trimmingCharacters(in: .whitespaces),
      isCompleted: status == "x" || status == "X",
      blockIdentifier: blockIdentifier
    )
  }

  private static func parseMetadata(
    after taskLineIndex: Int,
    taskIndentationCount: Int,
    bodyLines: [String]
  ) -> MetadataResult {
    let candidateIndex = taskLineIndex + 1
    guard bodyLines.indices.contains(candidateIndex) else {
      return MetadataResult(lineIndex: nil, metadata: nil, rawLine: nil, diagnostic: nil)
    }
    let line = bodyLines[candidateIndex]
    guard leadingIndentationWidth(line) > taskIndentationCount else {
      return MetadataResult(lineIndex: nil, metadata: nil, rawLine: nil, diagnostic: nil)
    }

    switch brainUnfogMetadataJSON(in: line) {
    case .none:
      return MetadataResult(lineIndex: nil, metadata: nil, rawLine: nil, diagnostic: nil)
    case .damaged:
      return MetadataResult(
        lineIndex: candidateIndex,
        metadata: nil,
        rawLine: line,
        diagnostic: .damaged(line: candidateIndex, rawLine: line)
      )
    case .valid(let json):
      guard let metadata = parseMetadataJSON(json) else {
        return MetadataResult(
          lineIndex: candidateIndex,
          metadata: nil,
          rawLine: line,
          diagnostic: .damaged(line: candidateIndex, rawLine: line)
        )
      }
      return MetadataResult(lineIndex: candidateIndex, metadata: metadata, rawLine: line, diagnostic: nil)
    }
  }

  private static func parseMetadataJSON(_ json: String) -> ObsidianTaskMetadata? {
    guard let data = json.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return ObsidianTaskMetadata(
      reminderExternalIdentifier: stringValue(object["reminder_external_id"]),
      date: stringValue(object["date"]),
      time: stringValue(object["time"]),
      durationMinutes: intValue(object["duration"]),
      repeatRule: stringValue(object["repeat"])
    )
  }

  private static func subtreeMarkdown(
    for task: TaskInfo,
    metadataLineIndex: Int?,
    bodyLines: [String]
  ) -> String {
    let nextBoundaryIndex = bodyLines.indices.dropFirst(task.lineIndex + 1).first { index in
      guard index != metadataLineIndex else { return false }
      let line = bodyLines[index]
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        return false
      }
      if leadingIndentationWidth(line) <= task.indentationCount {
        return true
      }
      return false
    } ?? bodyLines.count

    let subtreeLines = bodyLines[(task.lineIndex + 1)..<nextBoundaryIndex]
      .enumerated()
      .compactMap { offset, line -> String? in
        let absoluteIndex = task.lineIndex + 1 + offset
        return absoluteIndex == metadataLineIndex ? nil : line
      }
    return subtreeLines.joined(separator: "\n")
  }

  private static func yamlKeyValue(_ line: String) -> (key: String, value: String)? {
    guard !line.hasPrefix(" "), let colonIndex = line.firstIndex(of: ":") else { return nil }
    let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
    let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
    return (key, String(value))
  }

  private static func parseInlineTags(_ value: String) -> [String] {
    guard !value.isEmpty else { return [] }
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
      return trimmed.dropFirst().dropLast().split(separator: ",").map {
        normalizedTag(String($0)) ?? ""
      }.filter { !$0.isEmpty }
    }
    return normalizedTag(trimmed).map { [$0] } ?? []
  }

  private static func normalizedTag(_ value: String) -> String? {
    var tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
    tag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    if tag.hasPrefix("[["), tag.hasSuffix("]]") {
      tag = String(tag.dropFirst(2).dropLast(2))
    }
    return tag.isEmpty ? nil : tag
  }

  private static func normalizedScalar(_ value: String) -> String? {
    let scalar = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    return scalar.isEmpty ? nil : scalar
  }

  private static func boolScalar(_ value: String) -> Bool {
    switch normalizedScalar(value)?.lowercased() {
    case "true", "yes", "on":
      return true
    default:
      return false
    }
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
  }

  private static func removeTrailingBlockIdentifier(from title: inout String) -> String? {
    guard let range = title.range(
      of: #" \^buf-[A-Za-z0-9_-]+$"#,
      options: .regularExpression
    ) else {
      return nil
    }
    let block = title[range].trimmingCharacters(in: .whitespaces)
    title.removeSubrange(range)
    return block.isEmpty ? nil : block
  }

  private static func brainUnfogMetadataJSON(in line: String) -> MetadataCandidate {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let prefix = "%% brain-unfog:"
    guard trimmed.hasPrefix(prefix) else { return .none }
    guard trimmed.hasSuffix("%%") else { return .damaged }
    return .valid(
      trimmed
        .dropFirst(prefix.count)
        .dropLast(2)
        .trimmingCharacters(in: .whitespaces)
    )
  }

  private static func stringValue(_ value: Any?) -> String? {
    switch value {
    case let value as String:
      let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return normalized.isEmpty ? nil : normalized
    default:
      return nil
    }
  }

  private static func intValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int:
      return value
    case let value as NSNumber:
      return value.intValue
    case let value as String:
      return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    default:
      return nil
    }
  }

  private static func leadingIndentationWidth(_ line: String) -> Int {
    indentationWidth(String(line.prefix { $0 == " " || $0 == "\t" }))
  }

  private static func indentationWidth(_ indentation: String) -> Int {
    indentation.reduce(0) { count, character in
      count + (character == "\t" ? 2 : 1)
    }
  }

  private static func normalizeLineEndings(_ markdown: String) -> String {
    markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func stableFingerprint(_ value: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x100000001b3
    }
    return String(format: "%016llx", hash)
  }
}
