import Foundation

struct ObsidianReminderOutlineState: Codable, Equatable, Sendable {
  var roots: [ObsidianReminderOutlineChild]
  var taskChildrenByReminderID: [String: [ObsidianReminderOutlineChild]]

  init(
    roots: [ObsidianReminderOutlineChild] = [],
    taskChildrenByReminderID: [String: [ObsidianReminderOutlineChild]] = [:]
  ) {
    self.roots = roots
    self.taskChildrenByReminderID = taskChildrenByReminderID
  }

  func humanNoteText(forTaskID taskID: String) -> String {
    Self.normalizedNoteText(humanNoteLines(in: taskChildrenByReminderID[taskID] ?? []))
  }

  private func humanNoteLines(
    in children: [ObsidianReminderOutlineChild],
    indentationLevel: Int = 0
  ) -> [String] {
    var result: [String] = []
    for child in children {
      switch child {
      case .task:
        continue
      case .bullet(let text, let descendants):
        result.append("\(String(repeating: " ", count: indentationLevel))\(text)")
        result.append(contentsOf: humanNoteLines(in: descendants, indentationLevel: indentationLevel + 1))
      }
    }
    return result
  }

  private static func normalizedNoteText(_ lines: [String]) -> String {
    ReminderNoteSourceCodec.normalize(lines.joined(separator: "\n"))
  }
}

enum ObsidianReminderOutlineChild: Codable, Equatable, Sendable {
  case task(String)
  case bullet(text: String, children: [ObsidianReminderOutlineChild])

  private enum CodingKeys: String, CodingKey {
    case type
    case id
    case text
    case children
  }

  private enum ChildType: String, Codable {
    case task
    case bullet
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(ChildType.self, forKey: .type)
    switch type {
    case .task:
      self = .task(try container.decode(String.self, forKey: .id))
    case .bullet:
      self = .bullet(
        text: try container.decode(String.self, forKey: .text),
        children: try container.decodeIfPresent(
          [ObsidianReminderOutlineChild].self,
          forKey: .children
        ) ?? []
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .task(let id):
      try container.encode(ChildType.task, forKey: .type)
      try container.encode(id, forKey: .id)
    case .bullet(let text, let children):
      try container.encode(ChildType.bullet, forKey: .type)
      try container.encode(text, forKey: .text)
      if !children.isEmpty {
        try container.encode(children, forKey: .children)
      }
    }
  }
}

struct ObsidianReminderOutlineStateStore {
  private struct Payload: Codable, Equatable {
    var schemaVersion: Int
    var listsByReminderID: [String: ObsidianReminderOutlineState]

    static let currentSchemaVersion = 1
    static let empty = Payload(schemaVersion: currentSchemaVersion, listsByReminderID: [:])
  }

  private let vaultRootURL: URL
  private let fileManager: FileManager

  init(vaultRootURL: URL, fileManager: FileManager = .default) {
    self.vaultRootURL = vaultRootURL.standardizedFileURL
    self.fileManager = fileManager
  }

  func loadListOutline(for listID: String) throws -> ObsidianReminderOutlineState? {
    let key = normalized(listID)
    guard let key else { return nil }
    return try loadPayload().listsByReminderID[key]
  }

  func upsertListOutline(
    _ outline: ObsidianReminderOutlineState,
    forListID listID: String
  ) throws {
    guard let key = normalized(listID) else { return }
    var payload = try loadPayload()
    payload.schemaVersion = Payload.currentSchemaVersion
    payload.listsByReminderID[key] = outline
    try writePayload(payload)
  }

  func upsertListOutline(
    from note: ObsidianProjectNote,
    forListID listID: String
  ) throws {
    try upsertListOutline(Self.outline(from: note), forListID: listID)
  }

  static func outline(from note: ObsidianProjectNote) -> ObsidianReminderOutlineState {
    let bodyLines = note.bodyMarkdown.components(separatedBy: "\n")
    let tasksByLine = Dictionary(uniqueKeysWithValues: note.tasks.map { ($0.bodyLineIndex, $0) })
    let metadataLines = Set(note.tasks.compactMap(\.metadataLineIndex))
    let knownTaskIdentifiers = Set(note.tasks.compactMap {
      normalized($0.reminderExternalIdentifier)
    })
    var taskChildrenByReminderID: [String: [ObsidianReminderOutlineChild]] = [:]
    var index = 0
    let roots = parseChildren(
      in: bodyLines,
      index: &index,
      parentIndentationWidth: -1,
      tasksByLine: tasksByLine,
      metadataLines: metadataLines,
      knownTaskIdentifiers: knownTaskIdentifiers,
      taskChildrenByReminderID: &taskChildrenByReminderID
    )
    return ObsidianReminderOutlineState(
      roots: roots,
      taskChildrenByReminderID: taskChildrenByReminderID
    )
  }

  private static func parseChildren(
    in bodyLines: [String],
    index: inout Int,
    parentIndentationWidth: Int,
    tasksByLine: [Int: ObsidianProjectTask],
    metadataLines: Set<Int>,
    knownTaskIdentifiers: Set<String>,
    taskChildrenByReminderID: inout [String: [ObsidianReminderOutlineChild]]
  ) -> [ObsidianReminderOutlineChild] {
    var children: [ObsidianReminderOutlineChild] = []

    while index < bodyLines.count {
      if metadataLines.contains(index) {
        index += 1
        continue
      }
      let line = bodyLines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else {
        index += 1
        continue
      }
      let indentationWidth = leadingIndentationWidth(of: line)
      guard indentationWidth > parentIndentationWidth else { break }

      if let task = tasksByLine[index] {
        index += 1
        let taskChildren = parseChildren(
          in: bodyLines,
          index: &index,
          parentIndentationWidth: indentationWidth,
          tasksByLine: tasksByLine,
          metadataLines: metadataLines,
          knownTaskIdentifiers: knownTaskIdentifiers,
          taskChildrenByReminderID: &taskChildrenByReminderID
        )
        if let taskID = normalized(task.reminderExternalIdentifier) {
          taskChildrenByReminderID[taskID] = taskChildren
          children.append(.task(taskID))
        }
        continue
      }

      if let bulletText = markdownBulletText(from: trimmed) {
        index += 1
        if let taskIdentifier = ObsidianReminderImportFormatting
          .reminderNoteTaskMarkerIdentifier(from: bulletText),
          knownTaskIdentifiers.contains(taskIdentifier)
        {
          let descendants = parseChildren(
            in: bodyLines,
            index: &index,
            parentIndentationWidth: indentationWidth,
            tasksByLine: tasksByLine,
            metadataLines: metadataLines,
            knownTaskIdentifiers: knownTaskIdentifiers,
            taskChildrenByReminderID: &taskChildrenByReminderID
          )
          if taskChildrenByReminderID[taskIdentifier] == nil, !descendants.isEmpty {
            taskChildrenByReminderID[taskIdentifier] = descendants
          }
          children.append(.task(taskIdentifier))
          continue
        }
        let descendants = parseChildren(
          in: bodyLines,
          index: &index,
          parentIndentationWidth: indentationWidth,
          tasksByLine: tasksByLine,
          metadataLines: metadataLines,
          knownTaskIdentifiers: knownTaskIdentifiers,
          taskChildrenByReminderID: &taskChildrenByReminderID
        )
        children.append(.bullet(text: bulletText, children: descendants))
        continue
      }

      index += 1
    }

    return children
  }

  private func loadPayload() throws -> Payload {
    let url = stateFileURL
    guard fileManager.fileExists(atPath: url.path) else { return .empty }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty else { return .empty }
    return try JSONDecoder().decode(Payload.self, from: data)
  }

  private func writePayload(_ payload: Payload) throws {
    try fileManager.createDirectory(at: stateFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(payload)
    try data.write(to: stateFileURL, options: .atomic)
  }

  private var stateFileURL: URL {
    vaultRootURL
      .appendingPathComponent(".buf", isDirectory: true)
      .appendingPathComponent("reminder-outline-state.json", isDirectory: false)
  }

  private static func markdownBulletText(from trimmedLine: String) -> String? {
    guard trimmedLine.hasPrefix("- ") else { return nil }
    let value = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    return value.isEmpty ? nil : value
  }

  private static func leadingIndentationWidth(of line: String) -> Int {
    line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { total, character in
      total + (character == "\t" ? 2 : 1)
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

  private func normalized(_ value: String?) -> String? {
    Self.normalized(value)
  }
}
