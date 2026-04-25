import Foundation

enum ObsidianReminderImportFormatting {
  struct PreservedDescendantTaskBlocks {
    var orderedIdentifiers: [String]
    var blocksByIdentifier: [String: [String]]
  }

  static func taskState(
    _ task: ObsidianProjectTask,
    calendar: Calendar
  ) -> ReminderSyncTaskState {
    ReminderSyncTaskState(
      title: task.title,
      isCompleted: task.isCompleted,
      date: encodedDate(metadata: task.metadata),
      repeatRule: encodeRepeat(task.metadata?.repeatRule),
      noteText: reminderNoteText(for: task)
    )
  }

  static func metadata(
    existing: ObsidianTaskMetadata?,
    reminderExternalIdentifier: String?,
    state: ReminderSyncTaskState,
    calendar: Calendar
  ) -> ObsidianTaskMetadata {
    let dateFields = dateFields(from: state.date, calendar: calendar)
    return ObsidianTaskMetadata(
      reminderExternalIdentifier: normalized(reminderExternalIdentifier)
        ?? existing?.reminderExternalIdentifier,
      date: dateFields.date,
      time: dateFields.time,
      durationMinutes: existing?.durationMinutes,
      repeatRule: encodeRepeat(state.repeatRule)
    )
  }

  static func taskLine(
    _ state: ReminderSyncTaskState,
    existing task: ObsidianProjectTask
  ) -> String {
    let checkbox = state.isCompleted ? "x" : " "
    let block = task.blockIdentifier.map { " \($0)" } ?? ""
    return "\(task.indentation)- [\(checkbox)] \(state.title)\(block)"
  }

  static func renderMetadataLine(
    _ metadata: ObsidianTaskMetadata,
    indentation: String
  ) -> String {
    let note = ObsidianProjectNote(
      frontmatter: nil,
      bodyMarkdown: "- [ ] _",
      tasks: [
        ObsidianProjectTask(
          bodyLineIndex: 0,
          metadataLineIndex: nil,
          indentation: "",
          title: "_",
          isCompleted: false,
          blockIdentifier: nil,
          metadata: metadata,
          rawMetadataLine: nil,
          metadataIsDamaged: false,
          subtreeMarkdown: ""
        ),
      ],
      diagnostics: [],
      normalizedContentHash: ""
    )
    return ObsidianProjectNoteRenderer.render(note)
      .components(separatedBy: "\n")
      .dropFirst()
      .first
      .map { indentation + $0.trimmingCharacters(in: .whitespaces) }
      ?? "\(indentation)%% brain-unfog: {} %%"
  }

  static func subtreeLines(
    fromReminderNote noteText: String,
    parentIndentation: String
  ) -> [String] {
    renderedSubtreeLines(
      fromReminderNote: noteText,
      parentIndentation: parentIndentation,
      preservedTaskBlocks: PreservedDescendantTaskBlocks(
        orderedIdentifiers: [],
        blocksByIdentifier: [:]
      )
    )
  }

  static func parseTaskLineIndentation(_ line: String) -> String? {
    let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
    let marker = line.dropFirst(indentation.count)
    guard marker.hasPrefix("- [") else { return nil }
    return indentation
  }

  static func taskSubtreeEndIndex(
    from index: Int,
    task: ObsidianProjectTask,
    in bodyLines: [String]
  ) -> Int {
    taskSubtreeEndIndex(from: index, taskIndentation: task.indentation, in: bodyLines)
  }

  static func taskSubtreeEndIndex(
    from index: Int,
    taskIndentation: String,
    in bodyLines: [String]
  ) -> Int {
    let taskIndent = indentationWidth(taskIndentation)
    var cursor = index + 1
    while cursor < bodyLines.count {
      let line = bodyLines[cursor]
      if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        cursor += 1
        continue
      }
      if indentationWidth(leadingWhitespacePrefix(of: line)) <= taskIndent {
        return cursor
      }
      cursor += 1
    }
    return bodyLines.count
  }

  static func reminderIdentifier(in lines: [String]) -> String? {
    for line in lines {
      guard let range = line.range(
        of: #""reminder_external_id"\s*:\s*"([^"]+)""#,
        options: .regularExpression
      ) else { continue }
      let match = String(line[range])
      guard let valueRange = match.range(
        of: #""([^"]+)"\s*$"#,
        options: .regularExpression
      ) else { continue }
      return String(match[valueRange])
        .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }
    return nil
  }

  static func reminderNoteTaskMarkerIdentifier(from content: String) -> String? {
    guard content.hasPrefix("t:") else { return nil }
    return normalized(String(content.dropFirst(2)))
  }

  static func reparsedNote(
    from note: ObsidianProjectNote,
    bodyLines: [String]
  ) -> ObsidianProjectNote {
    ObsidianProjectNoteParser.parse(
      ObsidianProjectNoteRenderer.render(
        ObsidianProjectNote(
          frontmatter: note.frontmatter,
          bodyMarkdown: bodyLines.joined(separator: "\n"),
          tasks: [],
          diagnostics: [],
          normalizedContentHash: ""
        )
      )
    )
  }

  static func renderedSubtreeLines(
    fromReminderNote noteText: String?,
    parentIndentation: String,
    preservedTaskBlocks: PreservedDescendantTaskBlocks
  ) -> [String] {
    let normalizedNote = ReminderNoteSourceCodec.normalize(noteText)
    var replacement: [String] = []
    var referencedTaskIdentifiers = Set<String>()
    if !normalizedNote.isEmpty {
      for rawLine in normalizedNote.components(separatedBy: "\n") {
        let leadingSpaces = rawLine.prefix { $0 == " " }.count
        let content = String(rawLine.dropFirst(leadingSpaces))
          .trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { continue }
        if let taskIdentifier = reminderNoteTaskMarkerIdentifier(from: content) {
          if let taskBlock = preservedTaskBlocks.blocksByIdentifier[taskIdentifier] {
            replacement.append(contentsOf: taskBlock)
            referencedTaskIdentifiers.insert(taskIdentifier)
          }
          continue
        }
        let indent = parentIndentation + "  " + String(repeating: "  ", count: leadingSpaces)
        replacement.append("\(indent)- \(content)")
      }
    }
    for taskIdentifier in preservedTaskBlocks.orderedIdentifiers
    where !referencedTaskIdentifiers.contains(taskIdentifier) {
      if let taskBlock = preservedTaskBlocks.blocksByIdentifier[taskIdentifier] {
        replacement.append(contentsOf: taskBlock)
      }
    }
    return replacement
  }

  static func normalizeForComparison(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func encodedDate(metadata: ObsidianTaskMetadata?) -> String? {
    guard let day = normalized(metadata?.date) else { return nil }
    guard let time = normalized(metadata?.time) else { return day }
    return "\(day) \(time)"
  }

  private static func dateFields(
    from rawValue: String?,
    calendar: Calendar
  ) -> (date: String?, time: String?) {
    guard let rawValue = normalized(rawValue) else { return (nil, nil) }
    if let date = dateTimeFormatter.date(from: rawValue) {
      return (dayFormatter.string(from: date), timeFormatter.string(from: date))
    }
    if let date = dayFormatter.date(from: rawValue) {
      return (dayFormatter.string(from: calendar.startOfDay(for: date)), nil)
    }
    return (rawValue, nil)
  }

  private static func reminderNoteText(for task: ObsidianProjectTask) -> String {
    let lines = task.subtreeMarkdown.components(separatedBy: "\n")
    var noteLines: [String] = []
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("%% brain-unfog:") else { continue }
      let content = markdownListContent(from: trimmed)
      guard !content.isEmpty else { continue }
      let noteIndent = max(0, logicalIndentLevel(of: leadingWhitespacePrefix(of: line))
        - logicalIndentLevel(of: task.indentation) - 1)
      noteLines.append("\(String(repeating: " ", count: noteIndent))\(content)")
    }
    return ReminderNoteSourceCodec.normalize(noteLines.joined(separator: "\n"))
  }

  private static func markdownListContent(from trimmedLine: String) -> String {
    if trimmedLine.hasPrefix("- [") {
      let end = trimmedLine.index(trimmedLine.startIndex, offsetBy: 5, limitedBy: trimmedLine.endIndex)
      if let end, end <= trimmedLine.endIndex {
        return String(trimmedLine[end...]).trimmingCharacters(in: .whitespaces)
      }
    }
    if trimmedLine.hasPrefix("- ") {
      return String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
    return trimmedLine
  }

  private static func encodeRepeat(_ rawValue: String?) -> String? {
    ReminderScheduleMetadataCodec.encodeRepeat(rawValue)
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()

  private static func leadingWhitespacePrefix(of line: String) -> String {
    String(line.prefix { $0 == " " || $0 == "\t" })
  }

  private static func logicalIndentLevel(of prefix: String) -> Int {
    var level = 0
    var pendingSpaces = 0
    for character in prefix {
      if character == "\t" {
        level += pendingSpaces / 2
        if pendingSpaces % 2 != 0 { level += 1 }
        pendingSpaces = 0
        level += 1
      } else if character == " " {
        pendingSpaces += 1
      }
    }
    level += pendingSpaces / 2
    if pendingSpaces % 2 != 0 { level += 1 }
    return level
  }

  static func indentationWidth(_ indentation: String) -> Int {
    indentation.reduce(0) { count, character in
      count + (character == "\t" ? 2 : 1)
    }
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
