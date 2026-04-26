import Foundation

enum ObsidianReminderImportSync {
  struct SyncResult: Equatable {
    var importedProjectCount: Int
    var importedTaskCount: Int
    var updatedTaskCount: Int
    var deletedTaskCount: Int = 0
    var projectRecords: [ProjectIdentityBridgeRecord]
    var taskRecords: [TaskIdentityBridgeRecord]
  }

  enum SyncError: LocalizedError, Equatable {
    case duplicateReminderListExternalIdentifier(String)
    case duplicateReminderExternalIdentifier(String)
    case missingReminderListExternalIdentifier(String)
    case missingReminderExternalIdentifier(String)
    case damagedTaskMetadata(line: Int, rawLine: String)

    var errorDescription: String? {
      switch self {
      case .duplicateReminderListExternalIdentifier(let identifier):
        "Duplicate Reminder list identity in import batch: \(identifier)"
      case .duplicateReminderExternalIdentifier(let identifier):
        "Duplicate Reminder task identity in import batch: \(identifier)"
      case .missingReminderListExternalIdentifier(let title):
        "Reminder list is missing a stable identity: \(title)"
      case .missingReminderExternalIdentifier(let title):
        "Reminder task is missing a stable identity: \(title)"
      case .damagedTaskMetadata(let line, let rawLine):
        "Damaged Obsidian task metadata at line \(line): \(rawLine)"
      }
    }
  }

  private struct NormalizedList {
    var list: ReminderListImportSnapshot
    var externalIdentifier: String
    var title: String
  }

  private struct NormalizedItem {
    var item: ReminderItemImportSnapshot
    var externalIdentifier: String
    var title: String
    var state: ReminderSyncTaskState
  }

  private struct MergeDecision {
    var state: ReminderSyncTaskState
    var nextBaseline: ReminderSyncTaskState
    var conflictedFields: [ReminderSyncTaskField]
    var changedFields: Set<ReminderSyncTaskField>
  }

  static func sync(
    batch: ReminderImportSnapshotBatch,
    store: ObsidianProjectMarkdownStore,
    now: Date = .now,
    calendar: Calendar = .autoupdatingCurrent
  ) async throws -> SyncResult {
    let snapshots = try await store.loadProjectNotesInScope()
    try validateExistingNotes(snapshots.map(\.note))
    let snapshotsByListID = try snapshotsByReminderListExternalIdentifier(snapshots)
    let lists = try normalizedReminderLists(from: batch.lists)
    let duplicateTitleCounts = duplicateTitleCounts(in: lists)
    try validateReminderTaskIdentities(in: batch)

    var importedProjectCount = 0
    var importedTaskCount = 0
    var updatedTaskCount = 0
    var deletedTaskCount = 0
    var projectRecords: [ProjectIdentityBridgeRecord] = []
    var taskRecords: [TaskIdentityBridgeRecord] = []

    for list in lists {
      let items = try normalizedItems(
        batch.itemsByListIdentifier[list.list.identifier] ?? []
      )
      let projectID = RetainedProjectionBuilder.derivedProjectID(for: list.externalIdentifier)

      if let snapshot = snapshotsByListID[list.externalIdentifier] {
        let merge = mergeExistingNote(
          snapshot: snapshot,
          list: list,
          items: items,
          now: now,
          calendar: calendar
        )
        if merge.noteChanged {
          _ = try await store.writeProjectNote(
            merge.note,
            preferredFileName: snapshot.fileURL.lastPathComponent,
            expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: snapshot)
          )
          removeDeletedTaskSidecarRecords(merge.deletedReminderExternalIdentifiers)
        }
        ReminderSyncBaselineStore.upsertMany(merge.baselineUpdates)
        importedTaskCount += merge.importedTaskCount
        updatedTaskCount += merge.updatedTaskCount
        deletedTaskCount += merge.deletedTaskCount
        projectRecords.append(
          ProjectIdentityBridgeRecord(
            projectID: projectID,
            title: projectTitle(from: snapshot),
            reminderListExternalIdentifier: list.externalIdentifier,
            createdAt: now,
            updatedAt: items.map(\.item.modifiedAt).max() ?? now
          )
        )
        taskRecords.append(contentsOf: taskRecordsForItems(items, projectID: projectID, now: now))
      } else {
        let note = makeNote(for: list, items: items)
        _ = try await store.writeProjectNote(
          note,
          preferredFileName: preferredFileName(
            for: list,
            duplicateTitleCounts: duplicateTitleCounts
          )
        )
        let baselineUpdates = items.map {
          ReminderSyncTaskBaselineUpdate(
            reminderExternalIdentifier: $0.externalIdentifier,
            state: $0.state,
            remoteModifiedAt: $0.item.modifiedAt,
            now: now
          )
        }
        ReminderSyncBaselineStore.upsertMany(baselineUpdates)
        importedProjectCount += 1
        importedTaskCount += items.count
        projectRecords.append(
          ProjectIdentityBridgeRecord(
            projectID: projectID,
            title: list.title,
            reminderListExternalIdentifier: list.externalIdentifier,
            createdAt: now,
            updatedAt: items.map(\.item.modifiedAt).max() ?? now
          )
        )
        taskRecords.append(contentsOf: taskRecordsForItems(items, projectID: projectID, now: now))
      }
    }

    return SyncResult(
      importedProjectCount: importedProjectCount,
      importedTaskCount: importedTaskCount,
      updatedTaskCount: updatedTaskCount,
      deletedTaskCount: deletedTaskCount,
      projectRecords: projectRecords,
      taskRecords: taskRecords
    )
  }

  private struct ExistingMergeResult {
    var note: ObsidianProjectNote
    var noteChanged: Bool
    var importedTaskCount: Int
    var updatedTaskCount: Int
    var deletedTaskCount: Int
    var deletedReminderExternalIdentifiers: [String]
    var baselineUpdates: [ReminderSyncTaskBaselineUpdate]
  }

  private static func mergeExistingNote(
    snapshot: ObsidianProjectMarkdownStore.Snapshot,
    list: NormalizedList,
    items: [NormalizedItem],
    now: Date,
    calendar: Calendar
  ) -> ExistingMergeResult {
    var bodyLines = snapshot.note.bodyMarkdown.components(separatedBy: "\n")
    let tasksByID = Dictionary(
      uniqueKeysWithValues: snapshot.note.tasks.compactMap { task -> (String, ObsidianProjectTask)? in
        guard let id = normalized(task.reminderExternalIdentifier) else { return nil }
        return (id, task)
      }
    )
    var baselineUpdates: [ReminderSyncTaskBaselineUpdate] = []
    var noteTextUpdates: [String: ReminderSyncTaskState] = [:]
    var importedTaskCount = 0
    var updatedTaskCount = 0

    for item in items {
      guard let task = tasksByID[item.externalIdentifier] else { continue }
      let local = ObsidianReminderImportFormatting.taskState(task, calendar: calendar)
      var decision = mergeDecision(
        local: local,
        remote: item.state,
        remoteModifiedAt: item.item.modifiedAt,
        baseline: ReminderSyncBaselineStore.baseline(for: item.externalIdentifier)
      )
      if decision.changedFields.contains(.noteText),
        !canSafelyReplaceTaskSubtree(item.state.noteText, task: task, in: bodyLines)
      {
        decision.changedFields.remove(.noteText)
        decision.nextBaseline = decision.nextBaseline.replacing(field: .noteText, with: local)
        decision.conflictedFields.append(.noteText)
        decision.conflictedFields = Array(Set(decision.conflictedFields)).sorted {
          $0.rawValue < $1.rawValue
        }
      }
      baselineUpdates.append(
        ReminderSyncTaskBaselineUpdate(
          reminderExternalIdentifier: item.externalIdentifier,
          state: decision.nextBaseline,
          remoteModifiedAt: item.item.modifiedAt,
          conflictedFields: decision.conflictedFields,
          now: now
        )
      )
      guard !decision.changedFields.isEmpty else { continue }
      updatedTaskCount += 1
      applyOwnTaskFields(
        decision.state,
        to: task,
        in: &bodyLines,
        calendar: calendar
      )
      if decision.changedFields.contains(.noteText) {
        noteTextUpdates[item.externalIdentifier] = decision.state
      }
    }

    var reparsed = ObsidianReminderImportFormatting.reparsedNote(
      from: snapshot.note,
      bodyLines: bodyLines
    )
    for item in items where tasksByID[item.externalIdentifier] == nil {
      appendTask(item, to: &bodyLines, calendar: calendar)
      baselineUpdates.append(
        ReminderSyncTaskBaselineUpdate(
          reminderExternalIdentifier: item.externalIdentifier,
          state: item.state,
          remoteModifiedAt: item.item.modifiedAt,
          now: now
        )
      )
      importedTaskCount += 1
    }

    if !noteTextUpdates.isEmpty {
      reparsed = ObsidianReminderImportFormatting.reparsedNote(
        from: snapshot.note,
        bodyLines: bodyLines
      )
      bodyLines = applyNoteTextUpdates(noteTextUpdates, to: reparsed)
    }

    let deletion = ObsidianReminderDeletionSync.noteRemovingLocalTasksMissingFromRemote(
      snapshot: ObsidianProjectMarkdownStore.Snapshot(
        fileURL: snapshot.fileURL,
        vaultRelativePath: snapshot.vaultRelativePath,
        note: ObsidianReminderImportFormatting.reparsedNote(
          from: snapshot.note,
          bodyLines: bodyLines
        ),
        rawMarkdown: bodyLines.joined(separator: "\n"),
        contentModificationDate: snapshot.contentModificationDate
      ),
      remoteTaskExternalIdentifiers: Set(items.map(\.externalIdentifier)),
      calendar: calendar
    )

    let nextNote = deletion.note.updatingFrontmatterColor(list.list.colorHex)
    let rendered = ObsidianProjectNoteRenderer.render(nextNote)
    let noteChanged = ObsidianReminderImportFormatting.normalizeForComparison(rendered)
      != ObsidianReminderImportFormatting.normalizeForComparison(snapshot.rawMarkdown)

    return ExistingMergeResult(
      note: nextNote,
      noteChanged: noteChanged,
      importedTaskCount: importedTaskCount,
      updatedTaskCount: updatedTaskCount,
      deletedTaskCount: deletion.deletedReminderExternalIdentifiers.count,
      deletedReminderExternalIdentifiers: deletion.deletedReminderExternalIdentifiers,
      baselineUpdates: baselineUpdates
    )
  }

  private static func removeDeletedTaskSidecarRecords(_ identifiers: [String]) {
    for identifier in identifiers {
      ReminderSyncBaselineStore.remove(reminderExternalIdentifier: identifier)
      TaskIdentityBridgeStore.removeTask(
        taskID: ReminderProjectionIdentity.taskID(for: identifier)
      )
    }
  }

  private static func mergeDecision(
    local: ReminderSyncTaskState,
    remote: ReminderSyncTaskState,
    remoteModifiedAt: Date?,
    baseline: ReminderSyncTaskBaselineRecord?
  ) -> MergeDecision {
    guard let baseline else {
      if local == remote {
        return MergeDecision(
          state: local,
          nextBaseline: remote,
          conflictedFields: [],
          changedFields: []
        )
      }
      let conflicts = ReminderSyncTaskField.allCases.filter {
        local.value(for: $0) != remote.value(for: $0)
      }
      return MergeDecision(
        state: local,
        nextBaseline: local,
        conflictedFields: conflicts,
        changedFields: []
      )
    }
    if remoteSnapshotIsOlderThanBaseline(
      remoteModifiedAt: remoteModifiedAt,
      baselineRemoteModifiedAt: baseline.remoteModifiedAt
    ) {
      return MergeDecision(
        state: local,
        nextBaseline: baseline.state,
        conflictedFields: baseline.conflictedFields,
        changedFields: []
      )
    }

    var merged = local
    var nextBaseline = baseline.state
    var conflicts = baseline.conflictedFields
    var changedFields = Set<ReminderSyncTaskField>()

    for field in ReminderSyncTaskField.allCases {
      let baseValue = baseline.state.value(for: field)
      let localValue = local.value(for: field)
      let remoteValue = remote.value(for: field)
      let localChanged = localValue != baseValue
      let remoteChanged = remoteValue != baseValue

      if localChanged && remoteChanged && localValue != remoteValue {
        conflicts.append(field)
        continue
      }
      conflicts.removeAll { $0 == field }
      if remoteChanged {
        merged = merged.replacing(field: field, with: remote)
        nextBaseline = nextBaseline.replacing(field: field, with: remote)
        if localValue != remoteValue {
          changedFields.insert(field)
        }
      } else if !localChanged {
        nextBaseline = nextBaseline.replacing(field: field, with: local)
      }
    }

    return MergeDecision(
      state: merged,
      nextBaseline: nextBaseline,
      conflictedFields: Array(Set(conflicts)).sorted { $0.rawValue < $1.rawValue },
      changedFields: changedFields
    )
  }

  private static func applyOwnTaskFields(
    _ state: ReminderSyncTaskState,
    to task: ObsidianProjectTask,
    in bodyLines: inout [String],
    calendar: Calendar
  ) {
    guard bodyLines.indices.contains(task.bodyLineIndex) else { return }
    bodyLines[task.bodyLineIndex] = ObsidianReminderImportFormatting.taskLine(
      state,
      existing: task
    )
    let metadata = ObsidianReminderImportFormatting.metadata(
      existing: task.metadata,
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      state: state,
      calendar: calendar
    )
    let metadataLine = ObsidianReminderImportFormatting.renderMetadataLine(
      metadata,
      indentation: task.indentation + "  "
    )
    if let metadataLineIndex = task.metadataLineIndex,
      bodyLines.indices.contains(metadataLineIndex)
    {
      bodyLines[metadataLineIndex] = metadataLine
    } else {
      bodyLines.insert(metadataLine, at: min(task.bodyLineIndex + 1, bodyLines.count))
    }
  }

  private static func applyNoteTextUpdates(
    _ updates: [String: ReminderSyncTaskState],
    to note: ObsidianProjectNote
  ) -> [String] {
    var bodyLines = note.bodyMarkdown.components(separatedBy: "\n")
    let tasks = note.tasks.compactMap { task -> (String, ObsidianProjectTask)? in
      guard let id = normalized(task.reminderExternalIdentifier),
        updates[id] != nil
      else {
        return nil
      }
      return (id, task)
    }
    .sorted { lhs, rhs in lhs.1.bodyLineIndex > rhs.1.bodyLineIndex }

    for (identifier, task) in tasks {
      guard let state = updates[identifier] else { continue }
      replaceTaskSubtree(state.noteText, task: task, in: &bodyLines)
    }
    return bodyLines
  }

  private static func replaceTaskSubtree(
    _ noteText: String?,
    task: ObsidianProjectTask,
    in bodyLines: inout [String]
  ) {
    let subtreeEndIndex = ObsidianReminderImportFormatting.taskSubtreeEndIndex(
      from: task.bodyLineIndex,
      task: task,
      in: bodyLines
    )
    let ownContentEndIndex = task.metadataLineIndex.map { min($0 + 1, bodyLines.count) }
      ?? min(task.bodyLineIndex + 1, bodyLines.count)
    let preserved = preservedDescendantTaskBlocks(
      from: ownContentEndIndex,
      to: subtreeEndIndex,
      parentTask: task,
      in: bodyLines
    )
    let replacement = renderedSubtreeLines(
      fromReminderNote: noteText,
      parentIndentation: task.indentation,
      preservedTaskBlocks: preserved
    )
    bodyLines.replaceSubrange(ownContentEndIndex..<subtreeEndIndex, with: replacement)
  }

  private static func canSafelyReplaceTaskSubtree(
    _ noteText: String?,
    task: ObsidianProjectTask,
    in bodyLines: [String]
  ) -> Bool {
    let subtreeEndIndex = ObsidianReminderImportFormatting.taskSubtreeEndIndex(
      from: task.bodyLineIndex,
      task: task,
      in: bodyLines
    )
    let ownContentEndIndex = task.metadataLineIndex.map { min($0 + 1, bodyLines.count) }
      ?? min(task.bodyLineIndex + 1, bodyLines.count)
    let preserved = preservedDescendantTaskBlocks(
      from: ownContentEndIndex,
      to: subtreeEndIndex,
      parentTask: task,
      in: bodyLines
    )
    var seenMarkers: Set<String> = []
    for marker in reminderNoteTaskMarkers(in: noteText) {
      guard seenMarkers.insert(marker).inserted,
        preserved.blocksByIdentifier[marker] != nil
      else {
        return false
      }
    }
    return true
  }

  private struct PreservedDescendantTaskBlocks {
    var orderedIdentifiers: [String]
    var blocksByIdentifier: [String: [String]]
  }

  private static func preservedDescendantTaskBlocks(
    from startIndex: Int,
    to endIndex: Int,
    parentTask: ObsidianProjectTask,
    in bodyLines: [String]
  ) -> PreservedDescendantTaskBlocks {
    var orderedIdentifiers: [String] = []
    var blocksByIdentifier: [String: [String]] = [:]
    var index = startIndex
    while index < endIndex {
      guard let parsedIndentation = ObsidianReminderImportFormatting
        .parseTaskLineIndentation(bodyLines[index]),
        ObsidianReminderImportFormatting.indentationWidth(parsedIndentation)
          > ObsidianReminderImportFormatting.indentationWidth(parentTask.indentation)
      else {
        index += 1
        continue
      }
      let blockEnd = ObsidianReminderImportFormatting.taskSubtreeEndIndex(
        from: index,
        taskIndentation: parsedIndentation,
        in: bodyLines
      )
      if let identifier = ObsidianReminderImportFormatting
        .reminderIdentifier(in: Array(bodyLines[index..<blockEnd])),
        blocksByIdentifier[identifier] == nil
      {
        orderedIdentifiers.append(identifier)
        blocksByIdentifier[identifier] = Array(bodyLines[index..<blockEnd])
      }
      index = blockEnd
    }
    return PreservedDescendantTaskBlocks(
      orderedIdentifiers: orderedIdentifiers,
      blocksByIdentifier: blocksByIdentifier
    )
  }

  private static func renderedSubtreeLines(
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
      if let taskIdentifier = ObsidianReminderImportFormatting
        .reminderNoteTaskMarkerIdentifier(from: content) {
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

  private static func reminderNoteTaskMarkers(in noteText: String?) -> [String] {
    let normalizedNote = ReminderNoteSourceCodec.normalize(noteText)
    guard !normalizedNote.isEmpty else { return [] }
    return normalizedNote.components(separatedBy: "\n").compactMap { rawLine in
      let content = rawLine
        .trimmingCharacters(in: .whitespaces)
      return ObsidianReminderImportFormatting.reminderNoteTaskMarkerIdentifier(from: content)
    }
  }

  private static func appendTask(
    _ item: NormalizedItem,
    to bodyLines: inout [String],
    calendar: Calendar
  ) {
    if bodyLines.count == 1, bodyLines[0].isEmpty {
      bodyLines.removeAll()
    }
    let metadata = ObsidianReminderImportFormatting.metadata(
      existing: nil,
      reminderExternalIdentifier: item.externalIdentifier,
      state: item.state,
      calendar: calendar
    )
    bodyLines.append("- [\(item.item.isCompleted ? "x" : " ")] \(item.title)")
    bodyLines.append(ObsidianReminderImportFormatting.renderMetadataLine(metadata, indentation: "  "))
    bodyLines.append(
      contentsOf: ObsidianReminderImportFormatting.subtreeLines(
        fromReminderNote: item.item.notes,
        parentIndentation: ""
      )
    )
  }

  private static func makeNote(
    for list: NormalizedList,
    items: [NormalizedItem]
  ) -> ObsidianProjectNote {
    var bodyLines: [String] = []
    for item in items {
      appendTask(item, to: &bodyLines, calendar: .autoupdatingCurrent)
    }
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

  private static func validateExistingNotes(_ notes: [ObsidianProjectNote]) throws {
    for issue in ObsidianProjectNoteValidation.issues(in: notes) {
      switch issue {
      case .duplicateReminderListExternalIdentifier(let identifier):
        throw SyncError.duplicateReminderListExternalIdentifier(identifier)
      case .duplicateReminderExternalIdentifier(let identifier):
        throw SyncError.duplicateReminderExternalIdentifier(identifier)
      case .damagedTaskMetadata(let line, let rawLine):
        throw SyncError.damagedTaskMetadata(line: line, rawLine: rawLine)
      }
    }
  }

  private static func snapshotsByReminderListExternalIdentifier(
    _ snapshots: [ObsidianProjectMarkdownStore.Snapshot]
  ) throws -> [String: ObsidianProjectMarkdownStore.Snapshot] {
    var result: [String: ObsidianProjectMarkdownStore.Snapshot] = [:]
    for snapshot in snapshots {
      guard let listID = normalized(snapshot.note.reminderListExternalIdentifier) else { continue }
      guard result[listID] == nil else {
        throw SyncError.duplicateReminderListExternalIdentifier(listID)
      }
      result[listID] = snapshot
    }
    return result
  }

  private static func normalizedReminderLists(
    from lists: [ReminderListImportSnapshot]
  ) throws -> [NormalizedList] {
    var seen: Set<String> = []
    var result: [NormalizedList] = []
    for list in lists {
      guard let title = normalized(list.title) else { continue }
      guard let externalID = normalized(list.externalIdentifier) ?? normalized(list.identifier) else {
        throw SyncError.missingReminderListExternalIdentifier(title)
      }
      guard seen.insert(externalID).inserted else {
        throw SyncError.duplicateReminderListExternalIdentifier(externalID)
      }
      result.append(NormalizedList(list: list, externalIdentifier: externalID, title: title))
    }
    return result
  }

  private static func validateReminderTaskIdentities(
    in batch: ReminderImportSnapshotBatch
  ) throws {
    var seen: Set<String> = []
    for items in batch.itemsByListIdentifier.values {
      for item in items {
        guard let taskID = normalized(item.externalIdentifier) ?? normalized(item.identifier) else {
          throw SyncError.missingReminderExternalIdentifier(item.title)
        }
        guard seen.insert(taskID).inserted else {
          throw SyncError.duplicateReminderExternalIdentifier(taskID)
        }
      }
    }
  }

  private static func normalizedItems(
    _ items: [ReminderItemImportSnapshot]
  ) throws -> [NormalizedItem] {
    try items.compactMap { item in
      guard let title = normalized(item.title) else { return nil }
      guard let taskID = normalized(item.externalIdentifier) ?? normalized(item.identifier) else {
        throw SyncError.missingReminderExternalIdentifier(title)
      }
      return NormalizedItem(
        item: item,
        externalIdentifier: taskID,
        title: title,
        state: ReminderSyncTaskState(importedItem: item)
      )
    }
  }

  private static func taskRecordsForItems(
    _ items: [NormalizedItem],
    projectID: UUID,
    now: Date
  ) -> [TaskIdentityBridgeRecord] {
    items.map { item in
      TaskIdentityBridgeRecord(
        taskID: ReminderProjectionIdentity.taskID(for: item.externalIdentifier),
        title: item.title,
        reminderExternalIdentifier: item.externalIdentifier,
        ownerProjectID: projectID,
        createdAt: item.item.createdAt,
        updatedAt: item.item.modifiedAt > item.item.createdAt ? item.item.modifiedAt : now
      )
    }
  }

  private static func remoteSnapshotIsOlderThanBaseline(
    remoteModifiedAt: Date?,
    baselineRemoteModifiedAt: Date?
  ) -> Bool {
    guard let remoteModifiedAt, let baselineRemoteModifiedAt else { return false }
    return baselineRemoteModifiedAt.timeIntervalSince(remoteModifiedAt) > 0.5
  }

  private static func projectTitle(from snapshot: ObsidianProjectMarkdownStore.Snapshot) -> String {
    snapshot.fileURL.deletingPathExtension().lastPathComponent
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
    return "\(list.title) - \(String(list.externalIdentifier.prefix(8)))"
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

  fileprivate static func normalizedColor(_ value: String?) -> String? {
    normalized(value)
  }
}

private extension ObsidianProjectNote {
  func updatingFrontmatterColor(_ colorHex: String?) -> Self {
    var next = self
    guard let frontmatter = next.frontmatter else { return next }
    next.frontmatter = ObsidianProjectFrontmatter(
      tags: frontmatter.tags,
      reminderListExternalIdentifier: frontmatter.reminderListExternalIdentifier,
      colorHex: ObsidianReminderImportSync.normalizedColor(colorHex),
      projectStage: frontmatter.projectStage,
      startDate: frontmatter.startDate,
      deadline: frontmatter.deadline,
      preservedLines: frontmatter.preservedLines,
      hideCompletedTasks: frontmatter.hideCompletedTasks,
      isArchived: frontmatter.isArchived
    )
    return next
  }
}
