import Foundation

enum ObsidianReminderImportFormatting {
  struct PreservedDescendantTaskBlocks {
    var orderedIdentifiers: [String]
    var blocksByIdentifier: [String: [String]]
  }

  struct FlatReminderTaskBlockInput {
    var externalIdentifier: String
    var title: String
    var isCompleted: Bool
    var metadata: ObsidianTaskMetadata
    var noteText: String?
  }

  enum TaskMarkerResolutionError: Error, Equatable {
    case duplicateTaskMarker(String)
    case unresolvedTaskMarker(String)
    case cyclicTaskMarker(String)
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

  static func flatReminderTaskBodyLines(
    _ inputs: [FlatReminderTaskBlockInput],
    outline: ObsidianReminderOutlineState? = nil
  ) throws -> [String] {
    let tasksByID = try flatTasksByIdentifier(inputs)
    if let outline {
      return try flatReminderTaskBodyLines(inputs, tasksByID: tasksByID, outline: outline)
    }
    let referencedIDs = try referencedTaskIdentifiers(in: inputs, tasksByID: tasksByID)
    var consumedIDs = Set<String>()
    var bodyLines: [String] = []

    for input in inputs where !referencedIDs.contains(input.externalIdentifier) {
      bodyLines.append(
        contentsOf: try renderFlatReminderTaskBlock(
          input.externalIdentifier,
          parentIndentation: "",
          tasksByID: tasksByID,
          consumedIDs: &consumedIDs,
          stack: []
        )
      )
    }

    for input in inputs where !consumedIDs.contains(input.externalIdentifier) {
      bodyLines.append(
        contentsOf: try renderFlatReminderTaskBlock(
          input.externalIdentifier,
          parentIndentation: "",
          tasksByID: tasksByID,
          consumedIDs: &consumedIDs,
          stack: []
        )
      )
    }

    return bodyLines
  }

  static func unresolvedReminderNoteTaskMarkers(in bodyMarkdown: String) -> [String] {
    bodyMarkdown.components(separatedBy: "\n").compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("%% brain-unfog:") else { return nil }
      return reminderNoteTaskMarkerIdentifier(from: markdownListContent(from: trimmed))
    }
  }

  static func unresolvedReminderNoteTaskMarkers(in note: ObsidianProjectNote) -> [String] {
    let knownTaskIdentifiers = Set(note.tasks.compactMap {
      normalized($0.reminderExternalIdentifier)
    })
    return unresolvedReminderNoteTaskMarkers(in: note.bodyMarkdown).filter {
      !knownTaskIdentifiers.contains($0)
    }
  }

  static func parseTaskLineIndentation(_ line: String) -> String? {
    let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
    let marker = line.dropFirst(indentation.count)
    guard checkboxTaskTitleStart(in: marker) != nil else { return nil }
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
        guard !content.isEmpty else {
          replacement.append("")
          continue
        }
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

  private static func flatTasksByIdentifier(
    _ inputs: [FlatReminderTaskBlockInput]
  ) throws -> [String: FlatReminderTaskBlockInput] {
    var result: [String: FlatReminderTaskBlockInput] = [:]
    for input in inputs {
      guard result[input.externalIdentifier] == nil else {
        throw TaskMarkerResolutionError.duplicateTaskMarker(input.externalIdentifier)
      }
      result[input.externalIdentifier] = input
    }
    return result
  }

  private static func flatReminderTaskBodyLines(
    _ inputs: [FlatReminderTaskBlockInput],
    tasksByID: [String: FlatReminderTaskBlockInput],
    outline: ObsidianReminderOutlineState
  ) throws -> [String] {
    var consumedIDs = Set<String>()
    var bodyLines = try renderOutlineChildren(
      outline.roots,
      parentIndentation: "",
      tasksByID: tasksByID,
      outline: outline,
      consumedIDs: &consumedIDs,
      stack: []
    )

    for input in inputs where !consumedIDs.contains(input.externalIdentifier) {
      bodyLines.append(
        contentsOf: try renderFlatReminderTaskBlock(
          input.externalIdentifier,
          parentIndentation: "",
          tasksByID: tasksByID,
          outline: outline,
          consumedIDs: &consumedIDs,
          stack: []
        )
      )
    }

    return bodyLines
  }

  private static func referencedTaskIdentifiers(
    in inputs: [FlatReminderTaskBlockInput],
    tasksByID: [String: FlatReminderTaskBlockInput]
  ) throws -> Set<String> {
    var result = Set<String>()
    for input in inputs {
      for marker in reminderNoteTaskMarkers(in: input.noteText) {
        guard tasksByID[marker] != nil else {
          throw TaskMarkerResolutionError.unresolvedTaskMarker(marker)
        }
        result.insert(marker)
      }
    }
    return result
  }

  private static func renderFlatReminderTaskBlock(
    _ identifier: String,
    parentIndentation: String,
    tasksByID: [String: FlatReminderTaskBlockInput],
    outline: ObsidianReminderOutlineState? = nil,
    consumedIDs: inout Set<String>,
    stack: [String]
  ) throws -> [String] {
    guard !stack.contains(identifier) else {
      throw TaskMarkerResolutionError.cyclicTaskMarker(identifier)
    }
    guard !consumedIDs.contains(identifier) else {
      throw TaskMarkerResolutionError.duplicateTaskMarker(identifier)
    }
    guard let input = tasksByID[identifier] else {
      throw TaskMarkerResolutionError.unresolvedTaskMarker(identifier)
    }

    consumedIDs.insert(identifier)
    let checkbox = input.isCompleted ? "x" : " "
    var block = ["\(parentIndentation)- [\(checkbox)] \(input.title)"]
    block.append(renderMetadataLine(input.metadata, indentation: parentIndentation + "  "))
    block.append(
      contentsOf: try renderDescendantLines(
        for: input,
        identifier: identifier,
        parentIndentation: parentIndentation,
        tasksByID: tasksByID,
        outline: outline,
        consumedIDs: &consumedIDs,
        stack: stack + [identifier]
      )
    )
    return block
  }

  private static func renderDescendantLines(
    for input: FlatReminderTaskBlockInput,
    identifier: String,
    parentIndentation: String,
    tasksByID: [String: FlatReminderTaskBlockInput],
    outline: ObsidianReminderOutlineState?,
    consumedIDs: inout Set<String>,
    stack: [String]
  ) throws -> [String] {
    guard let outlineChildren = outline?.taskChildrenByReminderID[identifier] else {
      return try renderFlatReminderNoteLines(
        input.noteText,
        parentIndentation: parentIndentation,
        tasksByID: tasksByID,
        consumedIDs: &consumedIDs,
        stack: stack
      )
    }

    let remoteNote = ReminderNoteSourceCodec.normalize(input.noteText)
    let outlineNote = outline?.humanNoteText(forTaskID: identifier) ?? ""
    if remoteNote.isEmpty || remoteNote == outlineNote {
      return try renderOutlineChildren(
        outlineChildren,
        parentIndentation: parentIndentation + "  ",
        tasksByID: tasksByID,
        outline: outline,
        consumedIDs: &consumedIDs,
        stack: stack
      )
    }

    // Remote note text is authoritative, but saved outline children can still carry nested tasks.
    var result = try renderFlatReminderNoteLines(
      input.noteText,
      parentIndentation: parentIndentation,
      tasksByID: tasksByID,
      consumedIDs: &consumedIDs,
      stack: stack
    )
    result.append(
      contentsOf: try renderOutlineTaskChildren(
        outlineChildren,
        parentIndentation: parentIndentation + "  ",
        tasksByID: tasksByID,
        outline: outline,
        consumedIDs: &consumedIDs,
        stack: stack
      )
    )
    return result
  }

  private static func renderOutlineChildren(
    _ children: [ObsidianReminderOutlineChild],
    parentIndentation: String,
    tasksByID: [String: FlatReminderTaskBlockInput],
    outline: ObsidianReminderOutlineState?,
    consumedIDs: inout Set<String>,
    stack: [String]
  ) throws -> [String] {
    var result: [String] = []
    for child in children {
      switch child {
      case .task(let identifier):
        guard tasksByID[identifier] != nil else { continue }
        result.append(
          contentsOf: try renderFlatReminderTaskBlock(
            identifier,
            parentIndentation: parentIndentation,
            tasksByID: tasksByID,
            outline: outline,
            consumedIDs: &consumedIDs,
            stack: stack
          )
        )
      case .bullet(let text, let descendants):
        result.append("\(parentIndentation)- \(text)")
        result.append(
          contentsOf: try renderOutlineChildren(
            descendants,
            parentIndentation: parentIndentation + "  ",
            tasksByID: tasksByID,
            outline: outline,
            consumedIDs: &consumedIDs,
            stack: stack
          )
        )
      }
    }
    return result
  }

  private static func renderOutlineTaskChildren(
    _ children: [ObsidianReminderOutlineChild],
    parentIndentation: String,
    tasksByID: [String: FlatReminderTaskBlockInput],
    outline: ObsidianReminderOutlineState?,
    consumedIDs: inout Set<String>,
    stack: [String]
  ) throws -> [String] {
    var result: [String] = []
    for child in children {
      switch child {
      case .task(let identifier):
        guard tasksByID[identifier] != nil else { continue }
        result.append(
          contentsOf: try renderFlatReminderTaskBlock(
            identifier,
            parentIndentation: parentIndentation,
            tasksByID: tasksByID,
            outline: outline,
            consumedIDs: &consumedIDs,
            stack: stack
          )
        )
      case .bullet(_, let descendants):
        result.append(
          contentsOf: try renderOutlineTaskChildren(
            descendants,
            parentIndentation: parentIndentation,
            tasksByID: tasksByID,
            outline: outline,
            consumedIDs: &consumedIDs,
            stack: stack
          )
        )
      }
    }
    return result
  }

  private static func renderFlatReminderNoteLines(
    _ noteText: String?,
    parentIndentation: String,
    tasksByID: [String: FlatReminderTaskBlockInput],
    consumedIDs: inout Set<String>,
    stack: [String]
  ) throws -> [String] {
    let normalizedNote = ReminderNoteSourceCodec.normalize(noteText)
    guard !normalizedNote.isEmpty else { return [] }

    var result: [String] = []
    for rawLine in normalizedNote.components(separatedBy: "\n") {
      let leadingSpaces = rawLine.prefix { $0 == " " }.count
      let content = String(rawLine.dropFirst(leadingSpaces))
        .trimmingCharacters(in: .whitespaces)
      guard !content.isEmpty else {
        result.append("")
        continue
      }
      let indentation = parentIndentation + "  " + String(repeating: "  ", count: leadingSpaces)
      if let taskIdentifier = reminderNoteTaskMarkerIdentifier(from: content) {
        result.append(
          contentsOf: try renderFlatReminderTaskBlock(
            taskIdentifier,
            parentIndentation: indentation,
            tasksByID: tasksByID,
            consumedIDs: &consumedIDs,
            stack: stack
          )
        )
      } else {
        result.append("\(indentation)- \(content)")
      }
    }
    return result
  }

  private static func reminderNoteTaskMarkers(in noteText: String?) -> [String] {
    let normalizedNote = ReminderNoteSourceCodec.normalize(noteText)
    guard !normalizedNote.isEmpty else { return [] }
    return normalizedNote.components(separatedBy: "\n").compactMap { rawLine in
      reminderNoteTaskMarkerIdentifier(
        from: rawLine.trimmingCharacters(in: .whitespaces)
      )
    }
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

  static func reminderNoteText(for task: ObsidianProjectTask) -> String {
    let lines = task.subtreeMarkdown.components(separatedBy: "\n")
    var noteLines: [String] = []
    var index = 0
    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else {
        noteLines.append("")
        index += 1
        continue
      }
      guard !trimmed.hasPrefix("%% brain-unfog:") else {
        index += 1
        continue
      }
      if let taskIndentation = parseTaskLineIndentation(line) {
        let blockEnd = taskSubtreeEndIndex(
          from: index,
          taskIndentation: taskIndentation,
          in: lines
        )
        index = blockEnd
        continue
      }
      let content = markdownListContent(from: trimmed)
      guard !content.isEmpty else {
        index += 1
        continue
      }
      if reminderNoteTaskMarkerIdentifier(from: content) != nil {
        index += 1
        continue
      }
      let noteIndent = reminderNoteIndent(for: line, parentIndentation: task.indentation)
      noteLines.append("\(String(repeating: " ", count: noteIndent))\(content)")
      index += 1
    }
    return ReminderNoteSourceCodec.normalize(noteLines.joined(separator: "\n"))
  }

  private static func reminderNoteIndent(
    for line: String,
    parentIndentation: String
  ) -> Int {
    max(0, logicalIndentLevel(of: leadingWhitespacePrefix(of: line))
      - logicalIndentLevel(of: parentIndentation) - 1)
  }

  private static func markdownListContent(from trimmedLine: String) -> String {
    if let titleStart = checkboxTaskTitleStart(in: trimmedLine[...]) {
      return String(trimmedLine[titleStart...]).trimmingCharacters(in: .whitespaces)
    }
    if trimmedLine.hasPrefix("- ") {
      return String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
    return trimmedLine
  }

  private static func checkboxTaskTitleStart(in marker: Substring) -> String.Index? {
    guard marker.hasPrefix("- [") else { return nil }
    let markerEndIndex = marker.index(marker.startIndex, offsetBy: 4, limitedBy: marker.endIndex)
    guard let markerEndIndex,
      markerEndIndex < marker.endIndex,
      marker[markerEndIndex] == "]",
      marker.index(after: markerEndIndex) < marker.endIndex,
      marker[marker.index(after: markerEndIndex)] == " "
    else {
      return nil
    }
    let statusIndex = marker.index(marker.startIndex, offsetBy: 3)
    let status = marker[statusIndex]
    guard status == " " || status == "x" || status == "X" else { return nil }
    return marker.index(markerEndIndex, offsetBy: 2)
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
