import Foundation

enum ObsidianReminderDeletionSync {
  struct RemoteDeletionResult: Equatable {
    var deletedTaskCount: Int
  }

  struct LocalDeletionResult: Equatable {
    var note: ObsidianProjectNote
    var deletedReminderExternalIdentifiers: [String]
  }

  @MainActor
  static func deleteRemoteTasksMissingFromNote(
    note: ObsidianProjectNote,
    listIdentifier: String,
    remoteSnapshotsByExternalIdentifier: [String: ReminderTaskRemoteSnapshot]?,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date,
    calendar: Calendar
  ) throws -> RemoteDeletionResult {
    guard let remoteSnapshotsByExternalIdentifier else {
      return RemoteDeletionResult(deletedTaskCount: 0)
    }

    let localTaskIDs = Set(
      note.tasks.compactMap { normalized($0.reminderExternalIdentifier) }
    )
    var deletedTaskCount = 0

    for (reminderExternalIdentifier, remoteSnapshot) in remoteSnapshotsByExternalIdentifier {
      guard !localTaskIDs.contains(reminderExternalIdentifier) else { continue }
      guard normalized(remoteSnapshot.calendarIdentifier) == listIdentifier else { continue }
      guard canDeleteRemoteTask(
        reminderExternalIdentifier: reminderExternalIdentifier,
        remoteSnapshot: remoteSnapshot,
        calendar: calendar
      ) else {
        continue
      }
      guard !ReminderDeletedTaskTombstoneStore.shouldSuppressImport(
        reminderExternalIdentifier: reminderExternalIdentifier,
        remoteModifiedAt: remoteSnapshot.modifiedAt,
        now: now
      ) else {
        continue
      }

      let taskID = ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
      let reference = ReminderTaskReference(
        taskID: taskID,
        reminderIdentifier: remoteSnapshot.identifier,
        reminderExternalIdentifier: reminderExternalIdentifier
      )
      guard try reminderProjectProvider.removeTaskReminder(for: reference) else { continue }
      ReminderDeletedTaskTombstoneStore.upsertTaskDeletion(
        reminderExternalIdentifier: reminderExternalIdentifier,
        deletedAt: now
      )
      ReminderSyncBaselineStore.remove(reminderExternalIdentifier: reminderExternalIdentifier)
      TaskIdentityBridgeStore.removeTask(taskID: taskID)
      deletedTaskCount += 1
    }

    return RemoteDeletionResult(deletedTaskCount: deletedTaskCount)
  }

  static func noteRemovingLocalTasksMissingFromRemote(
    snapshot: ObsidianProjectMarkdownStore.Snapshot,
    remoteTaskExternalIdentifiers: Set<String>,
    calendar: Calendar
  ) -> LocalDeletionResult {
    let bodyLines = snapshot.note.bodyMarkdown.components(separatedBy: "\n")
    let candidateTasks = snapshot.note.tasks.filter { task in
      guard let identifier = normalized(task.reminderExternalIdentifier) else { return false }
      guard !remoteTaskExternalIdentifiers.contains(identifier) else { return false }
      return canDeleteLocalTask(task, calendar: calendar)
    }
    guard !candidateTasks.isEmpty else {
      return LocalDeletionResult(note: snapshot.note, deletedReminderExternalIdentifiers: [])
    }

    let candidateLineIndexes = Set(candidateTasks.map(\.bodyLineIndex))
    var selectedTasks: [ObsidianProjectTask] = []
    for task in candidateTasks {
      guard hasNoCandidateAncestor(
        task,
        candidateLineIndexes: candidateLineIndexes,
        allTasks: snapshot.note.tasks,
        bodyLines: bodyLines
      ) else {
        continue
      }
      guard allSyncedDescendantsAreCandidates(
        task,
        candidateLineIndexes: candidateLineIndexes,
        allTasks: snapshot.note.tasks,
        bodyLines: bodyLines
      ) else {
        continue
      }
      selectedTasks.append(task)
    }

    guard !selectedTasks.isEmpty else {
      return LocalDeletionResult(note: snapshot.note, deletedReminderExternalIdentifiers: [])
    }

    var nextBodyLines = bodyLines
    var deletedIdentifiers: [String] = []
    for task in selectedTasks.sorted(by: { $0.bodyLineIndex > $1.bodyLineIndex }) {
      let endIndex = ObsidianReminderImportFormatting.taskSubtreeEndIndex(
        from: task.bodyLineIndex,
        task: task,
        in: nextBodyLines
      )
      deletedIdentifiers.append(
        contentsOf: syncedCandidateIdentifiers(
          in: task.bodyLineIndex..<endIndex,
          candidateLineIndexes: candidateLineIndexes,
          allTasks: snapshot.note.tasks
        )
      )
      nextBodyLines.removeSubrange(task.bodyLineIndex..<endIndex)
    }

    let nextNote = ObsidianReminderImportFormatting.reparsedNote(
      from: snapshot.note,
      bodyLines: nextBodyLines
    )
    return LocalDeletionResult(
      note: nextNote,
      deletedReminderExternalIdentifiers: Array(Set(deletedIdentifiers)).sorted()
    )
  }

  private static func canDeleteRemoteTask(
    reminderExternalIdentifier: String,
    remoteSnapshot: ReminderTaskRemoteSnapshot,
    calendar: Calendar
  ) -> Bool {
    guard let baseline = ReminderSyncBaselineStore.baseline(
      for: reminderExternalIdentifier
    ) else {
      return false
    }
    guard baseline.conflictedFields.isEmpty else { return false }
    guard let baselineRemoteModifiedAt = baseline.remoteModifiedAt else { return false }
    guard remoteSnapshot.modifiedAt.timeIntervalSince(baselineRemoteModifiedAt) <= 0.5 else {
      return false
    }
    _ = calendar
    return ReminderSyncTaskState(remoteSnapshot: remoteSnapshot) == baseline.state
  }

  private static func canDeleteLocalTask(
    _ task: ObsidianProjectTask,
    calendar: Calendar
  ) -> Bool {
    guard let identifier = normalized(task.reminderExternalIdentifier),
      let baseline = ReminderSyncBaselineStore.baseline(for: identifier)
    else {
      return false
    }
    guard baseline.conflictedFields.isEmpty else { return false }
    guard baseline.remoteModifiedAt != nil else { return false }
    return ObsidianReminderImportFormatting.taskState(task, calendar: calendar) == baseline.state
  }

  private static func hasNoCandidateAncestor(
    _ task: ObsidianProjectTask,
    candidateLineIndexes: Set<Int>,
    allTasks: [ObsidianProjectTask],
    bodyLines: [String]
  ) -> Bool {
    !allTasks.contains { possibleAncestor in
      guard possibleAncestor.bodyLineIndex < task.bodyLineIndex,
        candidateLineIndexes.contains(possibleAncestor.bodyLineIndex)
      else {
        return false
      }
      let endIndex = ObsidianReminderImportFormatting.taskSubtreeEndIndex(
        from: possibleAncestor.bodyLineIndex,
        task: possibleAncestor,
        in: bodyLines
      )
      return task.bodyLineIndex < endIndex
    }
  }

  private static func allSyncedDescendantsAreCandidates(
    _ task: ObsidianProjectTask,
    candidateLineIndexes: Set<Int>,
    allTasks: [ObsidianProjectTask],
    bodyLines: [String]
  ) -> Bool {
    let endIndex = ObsidianReminderImportFormatting.taskSubtreeEndIndex(
      from: task.bodyLineIndex,
      task: task,
      in: bodyLines
    )
    for descendant in allTasks where descendant.bodyLineIndex > task.bodyLineIndex
      && descendant.bodyLineIndex < endIndex {
      guard normalized(descendant.reminderExternalIdentifier) == nil
        || candidateLineIndexes.contains(descendant.bodyLineIndex)
      else {
        return false
      }
    }
    return true
  }

  private static func syncedCandidateIdentifiers(
    in range: Range<Int>,
    candidateLineIndexes: Set<Int>,
    allTasks: [ObsidianProjectTask]
  ) -> [String] {
    allTasks.compactMap { task in
      guard range.contains(task.bodyLineIndex),
        candidateLineIndexes.contains(task.bodyLineIndex)
      else {
        return nil
      }
      return normalized(task.reminderExternalIdentifier)
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
