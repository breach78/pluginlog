import Foundation

enum ObsidianReminderImportSync {
  struct SyncResult: Equatable {
    var importedProjectCount: Int
    var importedTaskCount: Int
    var updatedTaskCount: Int
    var deletedTaskCount: Int = 0
    var deletedProjectCount: Int = 0
    var deletedProjectIDs: [UUID] = []
    var projectRecords: [ProjectIdentityBridgeRecord]
    var taskRecords: [TaskIdentityBridgeRecord]
  }

  enum SyncError: LocalizedError, Equatable {
    case duplicateReminderListExternalIdentifier(String)
    case duplicateReminderExternalIdentifier(String)
    case missingReminderListExternalIdentifier(String)
    case missingReminderExternalIdentifier(String)
    case duplicateReminderNoteTaskMarker(String)
    case unresolvedReminderNoteTaskMarker(String)
    case cyclicReminderNoteTaskMarker(String)
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
      case .duplicateReminderNoteTaskMarker(let identifier):
        "Reminder note references task more than once: \(identifier)"
      case .unresolvedReminderNoteTaskMarker(let identifier):
        "Reminder note references an unknown task marker: \(identifier)"
      case .cyclicReminderNoteTaskMarker(let identifier):
        "Reminder note task marker cycle detected at: \(identifier)"
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
    let vaultRootURL = await store.vaultRoot()
    let lifecycleStore = ProjectLifecycleStore(vaultRootURL: vaultRootURL)
    let archiveStore = ObsidianReminderArchiveStore(vaultRootURL: vaultRootURL)
    let allLists = try normalizedReminderLists(from: batch.lists)
    var lists: [NormalizedList] = []
    for list in allLists {
      guard try !lifecycleStore.shouldSkipImport(forListIdentifier: list.externalIdentifier) else {
        continue
      }
      lists.append(list)
    }
    let duplicateTitleCounts = duplicateTitleCounts(in: lists)
    try validateReminderTaskIdentities(in: batch)
    let outlineStore = ObsidianReminderOutlineStateStore(vaultRootURL: vaultRootURL)

    var importedProjectCount = 0
    var importedTaskCount = 0
    var updatedTaskCount = 0
    var deletedTaskCount = 0
    var deletedProjectCount = 0
    var deletedProjectIDs: [UUID] = []
    var projectRecords: [ProjectIdentityBridgeRecord] = []
    var taskRecords: [TaskIdentityBridgeRecord] = []

    for list in lists {
      let items = try normalizedItems(
        batch.itemsByListIdentifier[list.list.identifier] ?? []
      )
      let projectID = RetainedProjectionBuilder.derivedProjectID(for: list.externalIdentifier)

      if let snapshot = snapshotsByListID[list.externalIdentifier] {
        let merge = try mergeExistingNote(
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
        let note = try makeNote(
          for: list,
          items: items,
          outline: try outlineStore.loadListOutline(for: list.externalIdentifier),
          calendar: calendar
        )
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

    let remoteListExternalIdentifiers = Set(allLists.map(\.externalIdentifier))
    let deletedProjects = try await deleteLocalProjectsMissingFromReminderSourceIfNeeded(
      snapshots: snapshots,
      remoteListExternalIdentifiers: remoteListExternalIdentifiers,
      store: store,
      vaultRootURL: vaultRootURL,
      archiveStore: archiveStore,
      lifecycleStore: lifecycleStore,
      now: now
    )
    deletedProjectCount += deletedProjects.count
    deletedProjectIDs.append(contentsOf: deletedProjects.map(\.deletedProjectID))

    return SyncResult(
      importedProjectCount: importedProjectCount,
      importedTaskCount: importedTaskCount,
      updatedTaskCount: updatedTaskCount,
      deletedTaskCount: deletedTaskCount,
      deletedProjectCount: deletedProjectCount,
      deletedProjectIDs: deletedProjectIDs,
      projectRecords: projectRecords,
      taskRecords: taskRecords
    )
  }

  private static func deleteLocalProjectsMissingFromReminderSourceIfNeeded(
    snapshots: [ObsidianProjectMarkdownStore.Snapshot],
    remoteListExternalIdentifiers: Set<String>,
    store: ObsidianProjectMarkdownStore,
    vaultRootURL: URL,
    archiveStore: ObsidianReminderArchiveStore,
    lifecycleStore: ProjectLifecycleStore,
    now: Date
  ) async throws -> [ObsidianProjectDeletionSync.DeleteResult] {
    guard !remoteListExternalIdentifiers.isEmpty else { return [] }
    var deletedProjects: [ObsidianProjectDeletionSync.DeleteResult] = []
    for snapshot in snapshots {
      guard let listID = normalized(snapshot.note.reminderListExternalIdentifier) else {
        continue
      }
      let hasArchiveSnapshot = try archiveStore.load(forListIdentifier: listID) != nil
      let hasArchiveIntent = try lifecycleStore
        .shouldSuppressMissingReminderListDeletion(forListIdentifier: listID)
      if snapshot.note.frontmatter?.isArchived == true || hasArchiveSnapshot || hasArchiveIntent {
        continue
      }

      let lifecycleRecord = try lifecycleStore.record(forListIdentifier: listID)
      let lifecycleDeleteIntent = lifecycleRecord?.intent.deleteIntent
      guard lifecycleDeleteIntent != nil else {
        continue
      }

      if let deleted = try await ObsidianProjectDeletionSync
        .deleteLocalProjectForMissingReminderList(
          snapshot: snapshot,
          store: store,
          vaultRootURL: vaultRootURL,
          intent: lifecycleDeleteIntent ?? .remindersDelete,
          now: now
        )
      {
        deletedProjects.append(deleted)
      }
    }
    return deletedProjects
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
  ) throws -> ExistingMergeResult {
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
    let newItems = items.filter { tasksByID[$0.externalIdentifier] == nil }
    if !newItems.isEmpty {
      bodyLines.append(
        contentsOf: try flatTaskBodyLines(for: newItems, calendar: calendar)
      )
    }
    for item in newItems {
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
    try validateNoUnresolvedReminderNoteTaskMarkers(in: nextNote)
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
      return reminderAuthoritativeMergeDecision(local: local, remote: remote)
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

    return reminderAuthoritativeMergeDecision(local: local, remote: remote)
  }

  private static func reminderAuthoritativeMergeDecision(
    local: ReminderSyncTaskState,
    remote: ReminderSyncTaskState
  ) -> MergeDecision {
    var changedFields = Set<ReminderSyncTaskField>()
    for field in ReminderSyncTaskField.allCases
    where local.value(for: field) != remote.value(for: field) {
      changedFields.insert(field)
    }

    return MergeDecision(
      state: remote,
      nextBaseline: remote,
      conflictedFields: [],
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

  private static func flatTaskBodyLines(
    for items: [NormalizedItem],
    outline: ObsidianReminderOutlineState? = nil,
    calendar: Calendar
  ) throws -> [String] {
    let inputs = items.map { item in
      ObsidianReminderImportFormatting.FlatReminderTaskBlockInput(
        externalIdentifier: item.externalIdentifier,
        title: item.title,
        isCompleted: item.item.isCompleted,
        metadata: ObsidianReminderImportFormatting.metadata(
          existing: nil,
          reminderExternalIdentifier: item.externalIdentifier,
          state: item.state,
          calendar: calendar
        ),
        noteText: item.item.notes
      )
    }

    do {
      return try ObsidianReminderImportFormatting.flatReminderTaskBodyLines(
        inputs,
        outline: outline
      )
    } catch let error as ObsidianReminderImportFormatting.TaskMarkerResolutionError {
      throw syncError(from: error)
    } catch {
      throw error
    }
  }

  private static func syncError(
    from error: ObsidianReminderImportFormatting.TaskMarkerResolutionError
  ) -> SyncError {
    switch error {
    case .duplicateTaskMarker(let identifier):
      return .duplicateReminderNoteTaskMarker(identifier)
    case .unresolvedTaskMarker(let identifier):
      return .unresolvedReminderNoteTaskMarker(identifier)
    case .cyclicTaskMarker(let identifier):
      return .cyclicReminderNoteTaskMarker(identifier)
    }
  }

  private static func validateNoUnresolvedReminderNoteTaskMarkers(
    in note: ObsidianProjectNote
  ) throws {
    if let marker = ObsidianReminderImportFormatting
      .unresolvedReminderNoteTaskMarkers(in: note)
      .first
    {
      throw SyncError.unresolvedReminderNoteTaskMarker(marker)
    }
  }

  private static func makeNote(
    for list: NormalizedList,
    items: [NormalizedItem],
    outline: ObsidianReminderOutlineState?,
    calendar: Calendar
  ) throws -> ObsidianProjectNote {
    let bodyLines = try flatTaskBodyLines(for: items, outline: outline, calendar: calendar)
    let note = ObsidianProjectNoteParser.parse(
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
    try validateNoUnresolvedReminderNoteTaskMarkers(in: note)
    return note
  }

  private static func validateExistingNotes(_ notes: [ObsidianProjectNote]) throws {
    for note in notes {
      try validateNoUnresolvedReminderNoteTaskMarkers(in: note)
    }
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

private extension ProjectLifecycleIntent {
  var deleteIntent: ProjectLifecycleIntent? {
    switch self {
    case .appDelete:
      return self
    case .remindersDelete, .obsidianArchive:
      return nil
    }
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
