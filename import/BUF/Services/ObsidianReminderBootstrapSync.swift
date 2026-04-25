import Foundation

enum ObsidianReminderBootstrapSync {
  struct SyncResult: Equatable {
    var importedProjectCount: Int
    var importedTaskCount: Int
  }

  enum BootstrapError: LocalizedError, Equatable {
    case duplicateReminderListExternalIdentifier(String)
    case duplicateReminderExternalIdentifier(String)
    case missingReminderListExternalIdentifier(String)
    case missingReminderExternalIdentifier(String)
    case repairNeeded(ObsidianProjectNoteValidationIssue)
    case unsafeExistingNoteContent(String)

    var errorDescription: String? {
      switch self {
      case .duplicateReminderListExternalIdentifier(let identifier):
        "Duplicate Reminder list identity in Obsidian bootstrap batch: \(identifier)"
      case .duplicateReminderExternalIdentifier(let identifier):
        "Duplicate Reminder task identity in Obsidian bootstrap batch: \(identifier)"
      case .missingReminderListExternalIdentifier(let title):
        "Reminder list is missing a stable identity: \(title)"
      case .missingReminderExternalIdentifier(let title):
        "Reminder task is missing a stable identity: \(title)"
      case .repairNeeded(let issue):
        "Existing Obsidian project note needs repair before bootstrap can write: \(issue)"
      case .unsafeExistingNoteContent(let path):
        "Existing Obsidian project note contains local-only content that bootstrap cannot overwrite safely: \(path)"
      }
    }
  }

  static func sync(
    batch: ReminderImportSnapshotBatch,
    store: ObsidianProjectMarkdownStore,
    now: Date = .now
  ) async throws -> SyncResult {
    let existingSnapshots = try await store.loadProjectNotesInScope()
    try validateExistingNotes(existingSnapshots.map(\.note))
    let snapshotsByListID = try snapshotsByReminderListExternalIdentifier(existingSnapshots)

    let normalizedLists = try normalizedReminderLists(from: batch.lists)
    let duplicateTitleCounts = duplicateTitleCounts(in: normalizedLists)
    try validateReminderTaskIdentities(in: batch)

    var importedProjectCount = 0
    var importedTaskCount = 0

    for list in normalizedLists {
      let items = batch.itemsByListIdentifier[list.list.identifier] ?? []
      let note = try makeNote(for: list, items: items)
      if let existingSnapshot = snapshotsByListID[list.externalIdentifier] {
        try validateExistingNoteIsSafeForBootstrapOverwrite(
          existingSnapshot,
          incomingTaskIDs: Set(note.tasks.compactMap { normalized($0.reminderExternalIdentifier) })
        )
      }
      let preferredFileName = snapshotsByListID[list.externalIdentifier]?.fileURL.lastPathComponent
        ?? preferredFileName(for: list, duplicateTitleCounts: duplicateTitleCounts)
      let baseline = snapshotsByListID[list.externalIdentifier].map {
        ObsidianProjectMarkdownStore.WriteBaseline(snapshot: $0)
      }

      _ = try await store.writeProjectNote(
        note,
        preferredFileName: preferredFileName,
        expectedBaseline: baseline
      )
      ReminderSyncBaselineStore.upsertMany(
        items.compactMap { item in
          let taskID = normalized(item.externalIdentifier) ?? normalized(item.identifier)
          return ReminderSyncTaskBaselineUpdate(
            reminderExternalIdentifier: taskID,
            state: ReminderSyncTaskState(importedItem: item),
            remoteModifiedAt: item.modifiedAt,
            now: now
          )
        }
      )
      importedProjectCount += 1
      importedTaskCount += note.tasks.count
    }

    return SyncResult(
      importedProjectCount: importedProjectCount,
      importedTaskCount: importedTaskCount
    )
  }

  private struct NormalizedList {
    var list: ReminderListImportSnapshot
    var externalIdentifier: String
    var title: String
  }

  private static func normalizedReminderLists(
    from lists: [ReminderListImportSnapshot]
  ) throws -> [NormalizedList] {
    var seenListIDs: Set<String> = []
    var result: [NormalizedList] = []

    for list in lists {
      guard let title = normalized(list.title) else { continue }
      guard let externalIdentifier = normalized(list.externalIdentifier) ?? normalized(list.identifier) else {
        throw BootstrapError.missingReminderListExternalIdentifier(title)
      }
      guard seenListIDs.insert(externalIdentifier).inserted else {
        throw BootstrapError.duplicateReminderListExternalIdentifier(externalIdentifier)
      }
      result.append(NormalizedList(list: list, externalIdentifier: externalIdentifier, title: title))
    }

    return result
  }

  private static func validateReminderTaskIdentities(
    in batch: ReminderImportSnapshotBatch
  ) throws {
    var seenTaskIDs: Set<String> = []
    for items in batch.itemsByListIdentifier.values {
      for item in items {
        guard let taskID = normalized(item.externalIdentifier) ?? normalized(item.identifier) else {
          throw BootstrapError.missingReminderExternalIdentifier(item.title)
        }
        guard seenTaskIDs.insert(taskID).inserted else {
          throw BootstrapError.duplicateReminderExternalIdentifier(taskID)
        }
      }
    }
  }

  private static func validateExistingNotes(_ notes: [ObsidianProjectNote]) throws {
    for issue in ObsidianProjectNoteValidation.issues(in: notes) {
      throw BootstrapError.repairNeeded(issue)
    }
  }

  private static func snapshotsByReminderListExternalIdentifier(
    _ snapshots: [ObsidianProjectMarkdownStore.Snapshot]
  ) throws -> [String: ObsidianProjectMarkdownStore.Snapshot] {
    var result: [String: ObsidianProjectMarkdownStore.Snapshot] = [:]
    for snapshot in snapshots {
      guard let listID = normalized(snapshot.note.reminderListExternalIdentifier) else { continue }
      guard result[listID] == nil else {
        throw BootstrapError.repairNeeded(.duplicateReminderListExternalIdentifier(listID))
      }
      result[listID] = snapshot
    }
    return result
  }

  private static func makeNote(
    for list: NormalizedList,
    items: [ReminderItemImportSnapshot]
  ) throws -> ObsidianProjectNote {
    let bodyLines = try makeBodyLines(items: items)
    return ObsidianProjectNoteParser.parse(
      ObsidianProjectNoteRenderer.render(
        ObsidianProjectNote(
          frontmatter: ObsidianProjectFrontmatter(
            tags: ["프로젝트"],
            reminderListExternalIdentifier: list.externalIdentifier,
            preservedLines: []
          ),
          bodyMarkdown: bodyLines.joined(separator: "\n"),
          tasks: [],
          diagnostics: [],
          normalizedContentHash: ""
        )
      )
    )
  }

  private static func makeBodyLines(items: [ReminderItemImportSnapshot]) throws -> [String] {
    try items.map { item -> [String] in
      guard let title = normalized(item.title) else {
        return []
      }
      guard let taskID = normalized(item.externalIdentifier) ?? normalized(item.identifier) else {
        throw BootstrapError.missingReminderExternalIdentifier(title)
      }

      let checkbox = item.isCompleted ? "x" : " "
      var lines = ["- [\(checkbox)] \(title)"]
      lines.append("  \(metadataLine(for: item, taskID: taskID))")
      lines.append(contentsOf: subtreeLines(fromReminderNote: item.notes))
      return lines
    }
    .flatMap { $0 }
  }

  private static func metadataLine(
    for item: ReminderItemImportSnapshot,
    taskID: String
  ) -> String {
    let schedule = scheduleFields(from: item)
    var fields = [#""reminder_external_id":"\#(jsonEscaped(taskID))""#]
    if let date = schedule.date {
      fields.append(#""date":"\#(jsonEscaped(date))""#)
    }
    if let time = schedule.time {
      fields.append(#""time":"\#(jsonEscaped(time))""#)
    }
    if let repeatRule = encodeRepeat(item.recurrenceRuleRaw) {
      fields.append(#""repeat":"\#(jsonEscaped(repeatRule))""#)
    }
    return "%% brain-unfog: {\(fields.joined(separator: ","))} %%"
  }

  private static func subtreeLines(fromReminderNote noteText: String) -> [String] {
    let normalizedNote = ReminderNoteSourceCodec.normalizeReminderRawNote(noteText)
    guard !normalizedNote.isEmpty else { return [] }

    return normalizedNote.components(separatedBy: "\n").compactMap { rawLine in
      let leadingSpaces = rawLine.prefix { $0 == " " }.count
      let content = String(rawLine.dropFirst(leadingSpaces))
        .trimmingCharacters(in: .whitespaces)
      guard !content.isEmpty else { return nil }
      let indentation = "  " + String(repeating: "  ", count: leadingSpaces)
      return "\(indentation)- \(content)"
    }
  }

  private static func scheduleFields(
    from item: ReminderItemImportSnapshot
  ) -> (date: String?, time: String?) {
    guard let dueDate = item.dueDate else { return (nil, nil) }
    if item.scheduleHasExplicitTime {
      return (dateOnlyFormatter.string(from: dueDate), timeOnlyFormatter.string(from: dueDate))
    }
    return (dateOnlyFormatter.string(from: dueDate), nil)
  }

  private static func duplicateTitleCounts(
    in lists: [NormalizedList]
  ) -> [String: Int] {
    var counts: [String: Int] = [:]
    for list in lists {
      counts[normalizedTitleKey(list.title), default: 0] += 1
    }
    return counts
  }

  private static func preferredFileName(
    for list: NormalizedList,
    duplicateTitleCounts: [String: Int]
  ) -> String {
    guard (duplicateTitleCounts[normalizedTitleKey(list.title)] ?? 0) > 1 else {
      return list.title
    }
    return "\(list.title) - \(shortIdentifier(list.externalIdentifier))"
  }

  private static func shortIdentifier(_ identifier: String) -> String {
    String(identifier.prefix(8))
  }

  private static func normalizedTitleKey(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  private static func validateExistingNoteIsSafeForBootstrapOverwrite(
    _ snapshot: ObsidianProjectMarkdownStore.Snapshot,
    incomingTaskIDs: Set<String>
  ) throws {
    let existingTaskIDs = try snapshot.note.tasks.map { task -> String in
      guard let taskID = normalized(task.reminderExternalIdentifier) else {
        throw BootstrapError.unsafeExistingNoteContent(snapshot.vaultRelativePath)
      }
      return taskID
    }
    guard Set(existingTaskIDs).isSubset(of: incomingTaskIDs) else {
      throw BootstrapError.unsafeExistingNoteContent(snapshot.vaultRelativePath)
    }

    let bodyLines = snapshot.note.bodyMarkdown.components(separatedBy: "\n")
    let coveredLines = coveredTaskLineIndexes(in: snapshot.note)
    for index in bodyLines.indices where !coveredLines.contains(index) {
      guard bodyLines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw BootstrapError.unsafeExistingNoteContent(snapshot.vaultRelativePath)
      }
    }
  }

  private static func coveredTaskLineIndexes(in note: ObsidianProjectNote) -> Set<Int> {
    var covered = Set<Int>()
    for task in note.tasks {
      covered.insert(task.bodyLineIndex)
      if let metadataLineIndex = task.metadataLineIndex {
        covered.insert(metadataLineIndex)
      }
      guard !task.subtreeMarkdown.isEmpty else { continue }
      let subtreeLineCount = task.subtreeMarkdown.components(separatedBy: "\n").count
      guard subtreeLineCount > 0 else { continue }
      let firstSubtreeIndex = task.bodyLineIndex + 1
      for index in firstSubtreeIndex..<(firstSubtreeIndex + subtreeLineCount) {
        covered.insert(index)
      }
    }
    return covered
  }

  private static func encodeRepeat(_ rawValue: String?) -> String? {
    guard let value = normalized(rawValue)?.lowercased() else { return nil }
    if value == "daily" || value.hasPrefix("daily|") { return "daily" }
    if value == "weekly" || value.hasPrefix("weekly|") { return "weekly" }
    if value == "monthly" || value.hasPrefix("monthly|") { return "monthly" }
    if value == "yearly" || value.hasPrefix("yearly|") { return "yearly" }
    return nil
  }

  private static let dateOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let timeOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static func jsonEscaped(_ value: String) -> String {
    var result = ""
    for character in value {
      switch character {
      case "\\":
        result.append(#"\\"#)
      case "\"":
        result.append(#"\""#)
      case "\n":
        result.append(#"\n"#)
      case "\r":
        result.append(#"\r"#)
      case "\t":
        result.append(#"\t"#)
      default:
        result.append(character)
      }
    }
    return result
  }
}
