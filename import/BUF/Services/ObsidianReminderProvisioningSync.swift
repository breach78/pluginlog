import Foundation

@MainActor
enum ObsidianReminderProvisioningSync {
  struct SyncResult: Equatable {
    var createdProjectCount: Int
    var createdTaskCount: Int
    var updatedTaskCount: Int
    var deletedTaskCount: Int = 0
    var projectRecords: [ProjectIdentityBridgeRecord]
    var taskRecords: [TaskIdentityBridgeRecord]
  }

  enum SyncError: LocalizedError, Equatable {
    case duplicateReminderListExternalIdentifier(String)
    case duplicateReminderExternalIdentifier(String)
    case damagedTaskMetadata(line: Int, rawLine: String)

    var errorDescription: String? {
      switch self {
      case .duplicateReminderListExternalIdentifier(let identifier):
        "Duplicate Obsidian Reminder list identity: \(identifier)"
      case .duplicateReminderExternalIdentifier(let identifier):
        "Duplicate Obsidian Reminder task identity: \(identifier)"
      case .damagedTaskMetadata(let line, let rawLine):
        "Damaged Obsidian task metadata at line \(line): \(rawLine)"
      }
    }
  }

  private struct DecodedDate {
    var date: Date
    var hasExplicitTime: Bool
  }

  static func syncChangedNotes(
    fileURLs: [URL],
    store: ObsidianProjectMarkdownStore,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date = .now,
    calendar: Calendar = .autoupdatingCurrent
  ) async throws -> SyncResult {
    let allSnapshots = try await store.loadProjectNotesInScope()
    try validate(allSnapshots.map(\.note))
    let changedPaths = Set(
      fileURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
    )
    let snapshots = allSnapshots.filter {
      changedPaths.contains($0.fileURL.standardizedFileURL.resolvingSymlinksInPath().path)
    }
    return try await syncLoadedSnapshots(
      snapshots: snapshots,
      store: store,
      reminderProjectProvider: reminderProjectProvider,
      now: now,
      calendar: calendar,
      validateBeforeWrites: false
    )
  }

  static func syncLoadedSnapshots(
    snapshots: [ObsidianProjectMarkdownStore.Snapshot],
    store: ObsidianProjectMarkdownStore,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date,
    calendar: Calendar = .autoupdatingCurrent,
    validateBeforeWrites: Bool = true
  ) async throws -> SyncResult {
    if validateBeforeWrites {
      try validate(snapshots.map(\.note))
    }

    var createdProjectCount = 0
    var createdTaskCount = 0
    var updatedTaskCount = 0
    var deletedTaskCount = 0
    var projectRecords: [ProjectIdentityBridgeRecord] = []
    var taskRecords: [TaskIdentityBridgeRecord] = []

    for snapshot in snapshots {
      var note = snapshot.note
      guard note.isSyncScopeCandidate else { continue }

      let listIdentifier: String
      var didMutateNote = false
      var didCreateProject = false
      if let existingListID = normalized(note.reminderListExternalIdentifier) {
        listIdentifier = existingListID
      } else if let pending = ReminderPendingBindingStore.projectBinding(
        pageFileURL: snapshot.fileURL,
        pageTitle: projectTitle(from: snapshot),
        now: now
      ) {
        listIdentifier = pending.reminderListExternalIdentifier
        note = note.withReminderListExternalIdentifier(listIdentifier)
        didMutateNote = true
      } else {
        guard !containsBoundReminderTasks(note) else { continue }
        guard note.isProjectTagged else { continue }
        let createdList = try reminderProjectProvider.createProjectList(
          title: projectTitle(from: snapshot)
        )
        listIdentifier = createdList.externalIdentifier
        ReminderPendingBindingStore.upsertProjectBinding(
          pageFileURL: snapshot.fileURL,
          pageTitle: projectTitle(from: snapshot),
          reminderListExternalIdentifier: listIdentifier,
          now: now
        )
        note = note.withReminderListExternalIdentifier(listIdentifier)
        didMutateNote = true
        didCreateProject = true
        createdProjectCount += 1
      }

      let projectID = RetainedProjectionBuilder.derivedProjectID(for: listIdentifier)
      let remoteSnapshots = await remoteTaskSnapshotsByExternalIdentifier(
        inListIdentifier: listIdentifier,
        reminderProjectProvider: reminderProjectProvider
      )
      var noteWithTaskIDs = note

      for (taskIndex, task) in note.tasks.enumerated() {
        guard normalized(task.reminderExternalIdentifier) == nil else { continue }
        guard let taskIdentifier = try createOrResolveTaskBinding(
          task,
          taskIndex: taskIndex,
          snapshot: snapshot,
          listIdentifier: listIdentifier,
          remoteSnapshots: remoteSnapshots,
          reminderProjectProvider: reminderProjectProvider,
          now: now,
          calendar: calendar
        ) else { continue }

        noteWithTaskIDs = noteWithTaskIDs.updatingTaskMetadata(
          bodyLineIndex: task.bodyLineIndex
        ) { metadata in
          var next = metadata ?? ObsidianTaskMetadata(
            reminderExternalIdentifier: nil,
            date: nil,
            time: nil,
            durationMinutes: nil,
            repeatRule: nil
          )
          next.reminderExternalIdentifier = taskIdentifier
          return next
        }
        didMutateNote = true
        createdTaskCount += 1
        taskRecords.append(
          TaskIdentityBridgeRecord(
            taskID: ReminderProjectionIdentity.taskID(for: taskIdentifier),
            title: task.title,
            reminderExternalIdentifier: taskIdentifier,
            ownerProjectID: projectID,
            createdAt: now,
            updatedAt: now
          )
        )
      }

      if didMutateNote {
        _ = try await store.writeProjectNote(
          noteWithTaskIDs,
          preferredFileName: snapshot.fileURL.lastPathComponent,
          expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: snapshot),
          allowClaimingUnownedProject: true
        )
        ReminderPendingBindingStore.removeProjectBinding(
          pageFileURL: snapshot.fileURL,
          pageTitle: projectTitle(from: snapshot)
        )
        for (taskIndex, task) in note.tasks.enumerated()
        where normalized(task.reminderExternalIdentifier) == nil {
          ReminderPendingBindingStore.removeTaskBinding(
            pageFileURL: snapshot.fileURL,
            listExternalIdentifier: listIdentifier,
            taskIndex: taskIndex,
            taskFingerprint: taskFingerprint(task)
          )
        }
      }

      for task in note.tasks {
        guard let reminderExternalIdentifier = normalized(task.reminderExternalIdentifier) else {
          continue
        }
        if try applyExistingReminderUpdates(
          task,
          projectID: projectID,
          listIdentifier: listIdentifier,
          reminderExternalIdentifier: reminderExternalIdentifier,
          remoteSnapshot: remoteSnapshots?[reminderExternalIdentifier],
          reminderProjectProvider: reminderProjectProvider,
          now: now,
          calendar: calendar,
          taskRecords: &taskRecords
        ) {
          updatedTaskCount += 1
        }
      }

      let deletionResult = try ObsidianReminderDeletionSync.deleteRemoteTasksMissingFromNote(
        note: noteWithTaskIDs,
        listIdentifier: listIdentifier,
        remoteSnapshotsByExternalIdentifier: remoteSnapshots,
        reminderProjectProvider: reminderProjectProvider,
        now: now,
        calendar: calendar
      )
      deletedTaskCount += deletionResult.deletedTaskCount

      if didCreateProject || note.reminderListExternalIdentifier == nil {
        projectRecords.append(
          ProjectIdentityBridgeRecord(
            projectID: projectID,
            title: projectTitle(from: snapshot),
            reminderListExternalIdentifier: listIdentifier,
            createdAt: now,
            updatedAt: now
          )
        )
      }
    }

    return SyncResult(
      createdProjectCount: createdProjectCount,
      createdTaskCount: createdTaskCount,
      updatedTaskCount: updatedTaskCount,
      deletedTaskCount: deletedTaskCount,
      projectRecords: projectRecords,
      taskRecords: taskRecords
    )
  }

  private static func createOrResolveTaskBinding(
    _ task: ObsidianProjectTask,
    taskIndex: Int,
    snapshot: ObsidianProjectMarkdownStore.Snapshot,
    listIdentifier: String,
    remoteSnapshots: [String: ReminderTaskRemoteSnapshot]?,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date,
    calendar: Calendar
  ) throws -> String? {
    let fingerprint = taskFingerprint(task)
    if let pending = ReminderPendingBindingStore.taskBinding(
      pageFileURL: snapshot.fileURL,
      listExternalIdentifier: listIdentifier,
      taskIndex: taskIndex,
      taskFingerprint: fingerprint,
      now: now
    ) {
      guard let remoteSnapshots else { return nil }
      if let remote = remoteSnapshots[pending.reminderExternalIdentifier],
        remote.calendarIdentifier == listIdentifier,
        normalized(remote.title) == normalized(task.title)
      {
        return pending.reminderExternalIdentifier
      }
    } else if ReminderPendingBindingStore.hasTaskBindingForPageListIndex(
      pageFileURL: snapshot.fileURL,
      listExternalIdentifier: listIdentifier,
      taskIndex: taskIndex,
      now: now
    ) {
      return nil
    }

    let localState = taskState(task, calendar: calendar)
    let decodedDate = decodeDate(localState.date)
    guard let metadata = try reminderProjectProvider.createTaskReminder(
      inProject: listIdentifier,
      title: task.title,
      dueDate: decodedDate?.date,
      hasExplicitTime: decodedDate?.hasExplicitTime ?? false,
      noteText: ObsidianReminderImportFormatting.reminderNoteText(for: task)
    ) else {
      return nil
    }
    let taskIdentifier = metadata.externalIdentifier ?? metadata.identifier
    ReminderPendingBindingStore.upsertTaskBinding(
      pageFileURL: snapshot.fileURL,
      listExternalIdentifier: listIdentifier,
      taskIndex: taskIndex,
      taskTitle: task.title,
      taskFingerprint: fingerprint,
      reminderExternalIdentifier: taskIdentifier,
      now: now
    )
    let reference = ReminderTaskReference(
      taskID: ReminderProjectionIdentity.taskID(for: taskIdentifier),
      reminderIdentifier: metadata.identifier,
      reminderExternalIdentifier: taskIdentifier
    )
    if task.isCompleted {
      _ = try reminderProjectProvider.setTaskCompletion(
        for: reference,
        isCompleted: true,
        completionDate: nil
      )
    }
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: taskIdentifier,
      state: localState,
      remoteModifiedAt: metadata.modifiedAt,
      now: now
    )
    return taskIdentifier
  }

  private static func applyExistingReminderUpdates(
    _ task: ObsidianProjectTask,
    projectID: UUID,
    listIdentifier: String,
    reminderExternalIdentifier: String,
    remoteSnapshot: ReminderTaskRemoteSnapshot?,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date,
    calendar: Calendar,
    taskRecords: inout [TaskIdentityBridgeRecord]
  ) throws -> Bool {
    let taskID = ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
    let reference = ReminderTaskReference(
      taskID: taskID,
      reminderIdentifier: remoteSnapshot?.identifier,
      reminderExternalIdentifier: reminderExternalIdentifier
    )
    let snapshot = try remoteSnapshot ?? reminderProjectProvider.taskSnapshot(for: reference)
    guard let snapshot,
      let baseline = ReminderSyncBaselineStore.baseline(for: reminderExternalIdentifier)
    else {
      return false
    }

    let localState = taskState(task, calendar: calendar)
    let fieldsToPush = fieldsToPush(
      local: localState,
      remote: ReminderSyncTaskState(remoteSnapshot: snapshot),
      remoteModifiedAt: snapshot.modifiedAt,
      baseline: baseline
    )
    guard !fieldsToPush.isEmpty else { return false }

    var updatedAt: Date?
    var pushedFields: [ReminderSyncTaskField] = []
    if fieldsToPush.contains(.title), normalized(snapshot.title) != normalized(task.title) {
      updatedAt = try reminderProjectProvider.setTaskTitle(for: reference, title: task.title)?
        .modifiedAt ?? updatedAt
      pushedFields.append(.title)
    }
    if fieldsToPush.contains(.isCompleted), snapshot.isCompleted != task.isCompleted {
      updatedAt = try reminderProjectProvider.setTaskCompletion(
        for: reference,
        isCompleted: task.isCompleted,
        completionDate: nil
      )?.modifiedAt ?? updatedAt
      pushedFields.append(.isCompleted)
    }
    if fieldsToPush.contains(.noteText),
      ReminderNoteSourceCodec.normalize(snapshot.noteText)
      != ReminderNoteSourceCodec.normalize(localState.noteText)
    {
      updatedAt = try reminderProjectProvider.setTaskReminderNote(
        for: reference,
        noteText: localState.noteText ?? ""
      )?.modifiedAt ?? updatedAt
      pushedFields.append(.noteText)
    }
    if fieldsToPush.contains(.date) {
      let desiredDate = decodeDate(localState.date)
      if encodeDate(
        snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime
      ) != localState.date {
        updatedAt = try reminderProjectProvider.setTaskSchedule(
          for: reference,
          dueDate: desiredDate?.date,
          hasExplicitTime: desiredDate?.hasExplicitTime ?? false
        )?.modifiedAt ?? updatedAt
        pushedFields.append(.date)
      }
    }
    guard let updatedAt else { return false }
    let nextBaseline = baselineAfterPush(
      previous: baseline,
      local: localState,
      remote: ReminderSyncTaskState(remoteSnapshot: snapshot),
      pushedFields: pushedFields
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: reminderExternalIdentifier,
      state: nextBaseline.state,
      remoteModifiedAt: updatedAt,
      conflictedFields: nextBaseline.conflicts,
      now: now
    )
    taskRecords.append(
      TaskIdentityBridgeRecord(
        taskID: taskID,
        title: task.title,
        reminderExternalIdentifier: reminderExternalIdentifier,
        ownerProjectID: projectID,
        createdAt: now,
        updatedAt: updatedAt
      )
    )
    _ = listIdentifier
    return true
  }

  private static func remoteTaskSnapshotsByExternalIdentifier(
    inListIdentifier listIdentifier: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async -> [String: ReminderTaskRemoteSnapshot]? {
    guard let batch = try? await reminderProjectProvider.fetchImportSnapshotBatch(
      forListIdentifiers: [listIdentifier]
    ) else {
      return nil
    }
    var result: [String: ReminderTaskRemoteSnapshot] = [:]
    var duplicates: Set<String> = []
    for item in batch.itemsByListIdentifier[listIdentifier] ?? [] {
      guard let externalID = normalized(item.externalIdentifier) ?? normalized(item.identifier) else {
        continue
      }
      if result[externalID] != nil {
        result.removeValue(forKey: externalID)
        duplicates.insert(externalID)
        continue
      }
      guard !duplicates.contains(externalID) else { continue }
      result[externalID] = ReminderTaskRemoteSnapshot(
        identifier: item.identifier,
        externalIdentifier: externalID,
        calendarIdentifier: item.sourceListIdentifier,
        title: item.title,
        noteText: ReminderNoteSourceCodec.normalizeReminderRawNote(item.notes),
        isCompleted: item.isCompleted,
        completionDate: item.completionDate,
        startDate: item.startDate,
        dueDate: item.dueDate,
        hasExplicitTime: item.scheduleHasExplicitTime,
        priority: item.priority,
        recurrenceRuleRaw: item.recurrenceRuleRaw,
        modifiedAt: item.modifiedAt
      )
    }
    return result
  }

  private static func fieldsToPush(
    local: ReminderSyncTaskState,
    remote: ReminderSyncTaskState,
    remoteModifiedAt: Date?,
    baseline: ReminderSyncTaskBaselineRecord
  ) -> [ReminderSyncTaskField] {
    guard !remoteSnapshotIsOlderThanBaseline(
      remoteModifiedAt: remoteModifiedAt,
      baselineRemoteModifiedAt: baseline.remoteModifiedAt
    ) else {
      return []
    }
    return ReminderSyncTaskField.allCases.filter { field in
      guard field != .repeatRule else { return false }
      guard !baseline.hasConflict(field) else { return false }
      let localChanged = local.value(for: field) != baseline.state.value(for: field)
      let remoteChanged = remote.value(for: field) != baseline.state.value(for: field)
      guard localChanged else { return false }
      guard !remoteChanged else { return local.value(for: field) == remote.value(for: field) }
      return local.value(for: field) != remote.value(for: field)
    }
  }

  private static func baselineAfterPush(
    previous baseline: ReminderSyncTaskBaselineRecord,
    local: ReminderSyncTaskState,
    remote: ReminderSyncTaskState,
    pushedFields: [ReminderSyncTaskField]
  ) -> (state: ReminderSyncTaskState, conflicts: [ReminderSyncTaskField]) {
    var next = baseline.state
    var conflicts = baseline.conflictedFields
    for field in pushedFields {
      next = next.replacing(field: field, with: local)
      conflicts.removeAll { $0 == field }
    }
    for field in ReminderSyncTaskField.allCases where local.value(for: field) == remote.value(for: field) {
      next = next.replacing(field: field, with: local)
      conflicts.removeAll { $0 == field }
    }
    return (next, Array(Set(conflicts)).sorted { $0.rawValue < $1.rawValue })
  }

  private static func remoteSnapshotIsOlderThanBaseline(
    remoteModifiedAt: Date?,
    baselineRemoteModifiedAt: Date?
  ) -> Bool {
    guard let remoteModifiedAt, let baselineRemoteModifiedAt else { return false }
    return baselineRemoteModifiedAt.timeIntervalSince(remoteModifiedAt) > 0.5
  }

  private static func taskState(
    _ task: ObsidianProjectTask,
    calendar: Calendar
  ) -> ReminderSyncTaskState {
    ReminderSyncTaskState(
      title: task.title,
      isCompleted: task.isCompleted,
      date: encodedDate(metadata: task.metadata, calendar: calendar),
      repeatRule: encodeRepeat(task.metadata?.repeatRule),
      noteText: ObsidianReminderImportFormatting.reminderNoteText(for: task)
    )
  }

  private static func encodedDate(
    metadata: ObsidianTaskMetadata?,
    calendar: Calendar
  ) -> String? {
    guard let day = normalized(metadata?.date) else { return nil }
    guard let time = normalized(metadata?.time) else { return day }
    var components = DateComponents()
    let dayParts = day.split(separator: "-")
    let timeParts = time.split(separator: ":")
    guard dayParts.count == 3,
      timeParts.count == 2,
      let year = Int(dayParts[0]),
      let month = Int(dayParts[1]),
      let dateDay = Int(dayParts[2]),
      let hour = Int(timeParts[0]),
      let minute = Int(timeParts[1])
    else {
      return day
    }
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = dateDay
    components.hour = hour
    components.minute = minute
    return encodeDate(calendar.date(from: components), hasExplicitTime: true)
  }

  private static func taskFingerprint(_ task: ObsidianProjectTask) -> String {
    [
      fingerprint(task.title),
      task.isCompleted ? "done" : "todo",
      fingerprint(encodedDate(metadata: task.metadata, calendar: .autoupdatingCurrent) ?? ""),
      fingerprint(task.metadata?.repeatRule ?? ""),
      fingerprint(ObsidianReminderImportFormatting.reminderNoteText(for: task)),
    ].joined(separator: "|")
  }

  private static func containsBoundReminderTasks(_ note: ObsidianProjectNote) -> Bool {
    note.tasks.contains { normalized($0.reminderExternalIdentifier) != nil }
  }

  private static func validate(_ notes: [ObsidianProjectNote]) throws {
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

  private static func decodeDate(_ rawValue: String?) -> DecodedDate? {
    guard let normalized = normalized(rawValue) else { return nil }
    if let date = dateFormatter.date(from: normalized) {
      return DecodedDate(date: date, hasExplicitTime: true)
    }
    if let date = dayFormatter.date(from: normalized) {
      return DecodedDate(date: date, hasExplicitTime: false)
    }
    return nil
  }

  private static func encodeDate(_ date: Date?, hasExplicitTime: Bool) -> String? {
    guard let date else { return nil }
    return hasExplicitTime
      ? dateFormatter.string(from: date)
      : dayFormatter.string(from: Calendar.autoupdatingCurrent.startOfDay(for: date))
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

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()

  private static func projectTitle(from snapshot: ObsidianProjectMarkdownStore.Snapshot) -> String {
    snapshot.fileURL.deletingPathExtension().lastPathComponent
  }

  private static func fingerprint(_ value: String) -> String {
    value
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .lowercased()
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

private extension ObsidianProjectNote {
  func withReminderListExternalIdentifier(_ identifier: String) -> Self {
    var next = self
    let frontmatter = next.frontmatter ?? ObsidianProjectFrontmatter(
      tags: ["프로젝트"],
      reminderListExternalIdentifier: nil,
      preservedLines: []
    )
    next.frontmatter = ObsidianProjectFrontmatter(
      tags: frontmatter.tags.isEmpty ? ["프로젝트"] : frontmatter.tags,
      reminderListExternalIdentifier: identifier,
      preservedLines: frontmatter.preservedLines
    )
    return next
  }

  func updatingTaskMetadata(
    bodyLineIndex: Int,
    update: (ObsidianTaskMetadata?) -> ObsidianTaskMetadata
  ) -> Self {
    var next = self
    guard let index = next.tasks.firstIndex(where: { $0.bodyLineIndex == bodyLineIndex }) else {
      return next
    }
    next.tasks[index].metadata = update(next.tasks[index].metadata)
    next.tasks[index].metadataIsDamaged = false
    return next
  }
}
