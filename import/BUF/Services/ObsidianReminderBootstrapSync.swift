import Foundation

enum ObsidianReminderBootstrapSync {
  struct SyncResult: Equatable {
    var importedProjectCount: Int
    var importedTaskCount: Int
    var projectRecords: [ProjectIdentityBridgeRecord]
    var taskRecords: [TaskIdentityBridgeRecord]
  }

  enum BootstrapError: LocalizedError, Equatable {
    case duplicateReminderListExternalIdentifier(String)
    case duplicateReminderExternalIdentifier(String)
    case missingReminderListExternalIdentifier(String)
    case missingReminderExternalIdentifier(String)
    case duplicateReminderNoteTaskMarker(String)
    case unresolvedReminderNoteTaskMarker(String)
    case cyclicReminderNoteTaskMarker(String)
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
      case .duplicateReminderNoteTaskMarker(let identifier):
        "Reminder note references task more than once: \(identifier)"
      case .unresolvedReminderNoteTaskMarker(let identifier):
        "Reminder note references an unknown task marker: \(identifier)"
      case .cyclicReminderNoteTaskMarker(let identifier):
        "Reminder note task marker cycle detected at: \(identifier)"
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
    let fileNaming = ObsidianReminderListFileNaming(
      titles: normalizedLists.map(\.title)
    )
    try validateReminderTaskIdentities(in: batch)
    let outlineStore = ObsidianReminderOutlineStateStore(vaultRootURL: await store.vaultRoot())

    var importedProjectCount = 0
    var importedTaskCount = 0
    var projectRecords: [ProjectIdentityBridgeRecord] = []
    var taskRecords: [TaskIdentityBridgeRecord] = []

    for list in normalizedLists {
      let items = batch.itemsByListIdentifier[list.list.identifier] ?? []
      let note = try makeNote(
        for: list,
        items: items,
        outline: try outlineStore.loadListOutline(for: list.externalIdentifier)
      )
      let projectID = RetainedProjectionBuilder.derivedProjectID(for: list.externalIdentifier)
      if let existingSnapshot = snapshotsByListID[list.externalIdentifier] {
        try validateExistingNoteIsSafeForBootstrapOverwrite(
          existingSnapshot,
          incomingTaskIDs: Set(note.tasks.compactMap { normalized($0.reminderExternalIdentifier) })
        )
      }
      let preferredFileName = snapshotsByListID[list.externalIdentifier]?.fileURL.lastPathComponent
        ?? fileNaming.preferredFileName(
          title: list.title,
          externalIdentifier: list.externalIdentifier
        )
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
      projectRecords.append(
        ProjectIdentityBridgeRecord(
          projectID: projectID,
          title: list.title,
          reminderListExternalIdentifier: list.externalIdentifier,
          createdAt: now,
          updatedAt: items.map(\.modifiedAt).max() ?? now
        )
      )
      taskRecords.append(contentsOf: taskRecordsForItems(items, projectID: projectID, now: now))
    }

    return SyncResult(
      importedProjectCount: importedProjectCount,
      importedTaskCount: importedTaskCount,
      projectRecords: projectRecords,
      taskRecords: taskRecords
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
    for note in notes {
      if let marker = ObsidianReminderImportFormatting
        .unresolvedReminderNoteTaskMarkers(in: note)
        .first
      {
        throw BootstrapError.unresolvedReminderNoteTaskMarker(marker)
      }
    }
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
    items: [ReminderItemImportSnapshot],
    outline: ObsidianReminderOutlineState?
  ) throws -> ObsidianProjectNote {
    let bodyLines = try makeBodyLines(items: items, outline: outline)
    return ObsidianProjectNoteParser.parse(
      ObsidianProjectNoteRenderer.render(
        ObsidianProjectNote(
          frontmatter: ObsidianProjectFrontmatter(
            tags: ["프로젝트"],
            reminderListExternalIdentifier: list.externalIdentifier,
            colorHex: normalized(list.list.colorHex),
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

  private static func makeBodyLines(
    items: [ReminderItemImportSnapshot],
    outline: ObsidianReminderOutlineState? = nil
  ) throws -> [String] {
    let inputs = try items.compactMap { item -> ObsidianReminderImportFormatting.FlatReminderTaskBlockInput? in
      guard let title = normalized(item.title) else {
        return nil
      }
      guard let taskID = normalized(item.externalIdentifier) ?? normalized(item.identifier) else {
        throw BootstrapError.missingReminderExternalIdentifier(title)
      }
      return ObsidianReminderImportFormatting.FlatReminderTaskBlockInput(
        externalIdentifier: taskID,
        title: title,
        isCompleted: item.isCompleted,
        metadata: metadata(for: item, taskID: taskID),
        noteText: item.notes
      )
    }

    do {
      return try ObsidianReminderImportFormatting.flatReminderTaskBodyLines(
        inputs,
        outline: outline
      )
    } catch let error as ObsidianReminderImportFormatting.TaskMarkerResolutionError {
      throw bootstrapError(from: error)
    } catch {
      throw error
    }
  }

  private static func metadata(
    for item: ReminderItemImportSnapshot,
    taskID: String
  ) -> ObsidianTaskMetadata {
    let schedule = scheduleFields(from: item)
    return ObsidianTaskMetadata(
      reminderExternalIdentifier: taskID,
      date: schedule.date,
      time: schedule.time,
      durationMinutes: nil,
      repeatRule: encodeRepeat(item.recurrenceRuleRaw)
    )
  }

  private static func bootstrapError(
    from error: ObsidianReminderImportFormatting.TaskMarkerResolutionError
  ) -> BootstrapError {
    switch error {
    case .duplicateTaskMarker(let identifier):
      return .duplicateReminderNoteTaskMarker(identifier)
    case .unresolvedTaskMarker(let identifier):
      return .unresolvedReminderNoteTaskMarker(identifier)
    case .cyclicTaskMarker(let identifier):
      return .cyclicReminderNoteTaskMarker(identifier)
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

  private static func taskRecordsForItems(
    _ items: [ReminderItemImportSnapshot],
    projectID: UUID,
    now: Date
  ) -> [TaskIdentityBridgeRecord] {
    items.compactMap { item in
      guard let title = normalized(item.title),
        let taskID = normalized(item.externalIdentifier) ?? normalized(item.identifier)
      else {
        return nil
      }
      return TaskIdentityBridgeRecord(
        taskID: ReminderProjectionIdentity.taskID(for: taskID),
        title: title,
        reminderExternalIdentifier: taskID,
        ownerProjectID: projectID,
        createdAt: item.createdAt,
        updatedAt: item.modifiedAt > item.createdAt ? item.modifiedAt : now
      )
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
    ReminderScheduleMetadataCodec.encodeRepeat(rawValue)
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

}
