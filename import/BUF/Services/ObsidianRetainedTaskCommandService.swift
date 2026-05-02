import Foundation

@MainActor
enum ObsidianRetainedTaskCommandService {
  private static let reminderTimestampTolerance: TimeInterval = 0.5
  private static let mutationGate = RetainedTaskCommandMutationGate()

  static func createTask(
    vaultRootURL: URL?,
    projectID: UUID,
    title rawTitle: String,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar = .autoupdatingCurrent,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw RetainedTaskCommandError.retainedProjectionFailed("empty task title")
    }
    let lease = await mutationLease(projectID: projectID)
    defer { releaseMutationLease(lease) }

    let context = try await projectContext(vaultRootURL: vaultRootURL, projectID: projectID)
    let dueDate = scheduledDate(day: day, timeMinutes: timeMinutes, calendar: calendar)
    let hasExplicitTime = dueDate != nil && timeMinutes != nil
    guard let remoteMetadata = try reminderProjectProvider.createTaskReminder(
      inProject: context.reminderListExternalIdentifier,
      title: title,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      noteText: ""
    ), let reminderExternalIdentifier = normalized(remoteMetadata.externalIdentifier) else {
      throw RetainedTaskCommandError.retainedProjectionFailed("created reminder missing external id")
    }

    let taskID = ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
    do {
      let writtenSnapshot = try await writeCreatedTask(
        using: context,
        title: title,
        reminderExternalIdentifier: reminderExternalIdentifier,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes,
        calendar: calendar
      )
      try updateBaseline(
        from: writtenSnapshot,
        taskID: taskID,
        reminderExternalIdentifier: reminderExternalIdentifier,
        remoteModifiedAt: remoteMetadata.modifiedAt,
        pushedFields: [.title, .date],
        previousBaseline: nil
      )
      return try result(projectID: projectID, taskID: taskID, snapshot: writtenSnapshot)
    } catch {
      _ = try? reminderProjectProvider.removeTaskReminder(
        for: ReminderTaskReference(
          taskID: taskID,
          reminderIdentifier: remoteMetadata.identifier,
          reminderExternalIdentifier: reminderExternalIdentifier
        )
      )
      throw error
    }
  }

  static func setTaskCompletion(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let lease = await mutationLease(projectID: projectID, taskID: taskID)
    defer { releaseMutationLease(lease) }

    let context = try await commandContext(
      vaultRootURL: vaultRootURL,
      projectID: projectID,
      taskID: taskID
    )
    let reminderReference = try reminderReference(for: context.task, taskID: taskID)
    let previousState = ObsidianReminderImportFormatting.taskState(
      context.task,
      calendar: .autoupdatingCurrent
    )
    let isRecurringCompletion = isCompleted && normalized(previousState.repeatRule) != nil
    let shouldClearNextRecurringTime = isRecurringCompletion
      && context.retainedTask.schedule.hasExplicitTime
    let originalBaseline = try assertReminderWriteAllowed(
      reference: reminderReference,
      field: .isCompleted,
      reminderProjectProvider: reminderProjectProvider
    )
    if shouldClearNextRecurringTime {
      _ = try assertReminderWriteAllowed(
        reference: reminderReference,
        field: .date,
        reminderProjectProvider: reminderProjectProvider
      )
    }
    if isRecurringCompletion {
      guard let metadata = try reminderProjectProvider.setTaskCompletion(
        for: reminderReference,
        isCompleted: true,
        completionDate: completionDate ?? .now
      ) else {
        throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
      }
      if var remoteSnapshot = try recurringCompletionSnapshot(
        reference: reminderReference,
        reminderProjectProvider: reminderProjectProvider
      ) {
        if shouldClearNextRecurringTime,
          remoteSnapshot.hasExplicitTime,
          let nextDueDate = remoteSnapshot.dueDate
        {
          guard let scheduleMetadata = try reminderProjectProvider.setTaskSchedule(
            for: reminderReference,
            dueDate: nextDueDate,
            hasExplicitTime: false
          ) else {
            throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
          }
          remoteSnapshot = try recurringCompletionSnapshot(
            reference: reminderReference,
            reminderProjectProvider: reminderProjectProvider
          )
            ?? remoteSnapshotClearingExplicitTime(
              remoteSnapshot,
              modifiedAt: scheduleMetadata.modifiedAt
            )
        }
        let resultSnapshot = try await writeTask(
          using: context,
          mutate: { task, bodyLines in
            applyRecurringCompletionSnapshot(
              remoteSnapshot,
              to: task,
              in: &bodyLines,
              calendar: .autoupdatingCurrent
            )
          }
        )
        try updateBaseline(
          from: resultSnapshot,
          taskID: taskID,
          reminderExternalIdentifier: reminderReference.reminderExternalIdentifier,
          remoteModifiedAt: remoteSnapshot.modifiedAt,
          pushedFields: [.isCompleted, .date],
          previousBaseline: originalBaseline
        )
        return try result(projectID: projectID, taskID: taskID, snapshot: resultSnapshot)
      }

      let writtenSnapshot = try await writeTask(
        using: context,
        mutate: { task, bodyLines in
          var nextState = ObsidianReminderImportFormatting.taskState(
            task,
            calendar: .autoupdatingCurrent
          )
          nextState.isCompleted = true
          applyTaskState(nextState, to: task, in: &bodyLines, calendar: .autoupdatingCurrent)
        }
      )
      try updateBaseline(
        from: writtenSnapshot,
        taskID: taskID,
        reminderExternalIdentifier: reminderReference.reminderExternalIdentifier,
        remoteModifiedAt: metadata.modifiedAt,
        pushedFields: [.isCompleted],
        previousBaseline: originalBaseline
      )
      return try result(projectID: projectID, taskID: taskID, snapshot: writtenSnapshot)
    }
    let writtenSnapshot = try await writeTask(
      using: context,
      mutate: { task, bodyLines in
        var nextState = ObsidianReminderImportFormatting.taskState(task, calendar: .autoupdatingCurrent)
        nextState.isCompleted = isCompleted
        applyTaskState(nextState, to: task, in: &bodyLines, calendar: .autoupdatingCurrent)
      }
    )

    do {
      guard let metadata = try reminderProjectProvider.setTaskCompletion(
        for: reminderReference,
        isCompleted: isCompleted,
        completionDate: isCompleted ? (completionDate ?? .now) : nil
      ) else {
        throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
      }
      try updateBaseline(
        from: writtenSnapshot,
        taskID: taskID,
        reminderExternalIdentifier: reminderReference.reminderExternalIdentifier,
        remoteModifiedAt: metadata.modifiedAt,
        pushedFields: [.isCompleted],
        previousBaseline: originalBaseline
      )
    } catch {
      try await rollbackObsidianWrite(
        context: context,
        writtenSnapshot: writtenSnapshot,
        writeError: error
      )
    }

    return try result(projectID: projectID, taskID: taskID, snapshot: writtenSnapshot)
  }

  static func setTaskSchedule(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar = .autoupdatingCurrent,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let lease = await mutationLease(projectID: projectID, taskID: taskID)
    defer { releaseMutationLease(lease) }

    let context = try await commandContext(
      vaultRootURL: vaultRootURL,
      projectID: projectID,
      taskID: taskID
    )
    let reminderReference = try reminderReference(for: context.task, taskID: taskID)
    let previousState = ObsidianReminderImportFormatting.taskState(
      context.task,
      calendar: calendar
    )
    let dueDate = scheduledDate(day: day, timeMinutes: timeMinutes, calendar: calendar)
    let hasExplicitTime = dueDate != nil && timeMinutes != nil
    let nextDate = ReminderScheduleMetadataCodec.encodeDate(
      dueDate,
      hasExplicitTime: hasExplicitTime
    )

    let originalBaseline: ReminderSyncTaskBaselineRecord?
    if previousState.date != nextDate {
      originalBaseline = try assertReminderWriteAllowed(
        reference: reminderReference,
        field: .date,
        reminderProjectProvider: reminderProjectProvider
      )
    } else {
      originalBaseline = ReminderSyncBaselineStore.baseline(
        for: context.task.reminderExternalIdentifier
      )
    }

    let writtenSnapshot = try await writeTask(
      using: context,
      mutate: { task, bodyLines in
        let metadata = scheduleMetadata(
          existing: task.metadata,
          reminderExternalIdentifier: task.reminderExternalIdentifier,
          day: day,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes,
          calendar: calendar
        )
        applyMetadata(metadata, to: task, in: &bodyLines)
      }
    )

    if previousState.date != nextDate {
      do {
        guard let metadata = try reminderProjectProvider.setTaskSchedule(
          for: reminderReference,
          dueDate: dueDate,
          hasExplicitTime: hasExplicitTime
        ) else {
          throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
        }
        try updateBaseline(
          from: writtenSnapshot,
          taskID: taskID,
          reminderExternalIdentifier: reminderReference.reminderExternalIdentifier,
          remoteModifiedAt: metadata.modifiedAt,
          pushedFields: [.date],
          previousBaseline: originalBaseline
        )
      } catch {
        try await rollbackObsidianWrite(
          context: context,
          writtenSnapshot: writtenSnapshot,
          writeError: error
        )
      }
    }

    return try result(projectID: projectID, taskID: taskID, snapshot: writtenSnapshot)
  }

  static func deleteTask(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskDeletionResult {
    let lease = await mutationLease(projectID: projectID, taskID: taskID)
    defer { releaseMutationLease(lease) }

    let context = try await commandContext(
      vaultRootURL: vaultRootURL,
      projectID: projectID,
      taskID: taskID
    )
    let reminderReference = try reminderReference(for: context.task, taskID: taskID)
    guard let reminderExternalIdentifier = reminderReference.reminderExternalIdentifier else {
      throw RetainedTaskCommandError.missingReminderExternalIdentifier(taskID)
    }
    _ = try assertReminderDeleteAllowed(
      reference: reminderReference,
      reminderProjectProvider: reminderProjectProvider
    )

    let writtenSnapshot = try await writeDeletedTask(using: context)
    do {
      guard try reminderProjectProvider.removeTaskReminder(for: reminderReference) else {
        throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
      }
    } catch {
      try await rollbackObsidianWrite(
        context: context,
        writtenSnapshot: writtenSnapshot,
        writeError: error
      )
    }

    ReminderSyncBaselineStore.remove(
      reminderExternalIdentifier: reminderExternalIdentifier
    )
    TaskIdentityBridgeStore.removeTask(taskID: taskID)
    return RetainedTaskDeletionResult(
      projectID: projectID,
      taskID: taskID,
      reminderExternalIdentifier: reminderExternalIdentifier
    )
  }

  static func moveTask(
    vaultRootURL: URL?,
    taskID: UUID,
    sourceProjectID: UUID,
    targetProjectID: UUID,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    guard sourceProjectID != targetProjectID else {
      throw RetainedTaskCommandError.retainedProjectionFailed("task already belongs to target project")
    }
    let lease = await mutationLease(
      sourceProjectID: sourceProjectID,
      targetProjectID: targetProjectID,
      taskID: taskID
    )
    defer { releaseMutationLease(lease) }

    let sourceContext = try await commandContext(
      vaultRootURL: vaultRootURL,
      projectID: sourceProjectID,
      taskID: taskID
    )
    let targetContext = try await projectContext(
      vaultRootURL: vaultRootURL,
      projectID: targetProjectID
    )
    let reminderReference = try reminderReference(for: sourceContext.task, taskID: taskID)
    let originalBaseline = try assertReminderDeleteAllowed(
      reference: reminderReference,
      reminderProjectProvider: reminderProjectProvider
    )
    let (sourceWrittenSnapshot, movedLines) = try await writeRemovedTaskForMove(
      using: sourceContext
    )

    let targetWrittenSnapshot: ObsidianProjectMarkdownStore.Snapshot
    do {
      targetWrittenSnapshot = try await writeMovedTask(
        using: targetContext,
        movedLines: movedLines,
        validationNotes: [sourceWrittenSnapshot.note]
      )
    } catch {
      try await rollbackProjectNote(
        store: sourceContext.store,
        originalSnapshot: sourceContext.snapshot,
        writtenSnapshot: sourceWrittenSnapshot,
        writeError: error
      )
      throw error
    }

    do {
      guard let metadata = try reminderProjectProvider.moveTaskReminder(
        for: reminderReference,
        toProject: targetContext.reminderListExternalIdentifier
      ) else {
        throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
      }
      try updateBaseline(
        from: targetWrittenSnapshot,
        taskID: taskID,
        reminderExternalIdentifier: reminderReference.reminderExternalIdentifier,
        remoteModifiedAt: metadata.modifiedAt,
        pushedFields: [],
        previousBaseline: originalBaseline
      )
      if let movedTask = targetWrittenSnapshot.note.tasks.first(
        where: { retainedTaskID(for: $0) == taskID }
      ) {
        TaskIdentityBridgeStore.upsertTask(
          taskID: taskID,
          title: movedTask.title,
          reminderExternalIdentifier: reminderReference.reminderExternalIdentifier,
          ownerProjectID: targetProjectID
        )
      }
      return try result(
        projectID: targetProjectID,
        taskID: taskID,
        snapshot: targetWrittenSnapshot
      )
    } catch {
      try await rollbackProjectNote(
        store: targetContext.store,
        originalSnapshot: targetContext.snapshot,
        writtenSnapshot: targetWrittenSnapshot,
        writeError: error
      )
      try await rollbackProjectNote(
        store: sourceContext.store,
        originalSnapshot: sourceContext.snapshot,
        writtenSnapshot: sourceWrittenSnapshot,
        writeError: error
      )
      throw error
    }
  }

  static func taskEditFields(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    calendar: Calendar = .autoupdatingCurrent
  ) async throws -> RetainedTaskEditFields {
    let context = try await commandContext(
      vaultRootURL: vaultRootURL,
      projectID: projectID,
      taskID: taskID
    )
    let parsedDate = context.retainedTask.schedule.parsedDate
    return RetainedTaskEditFields(
      title: context.task.title,
      noteText: ObsidianReminderImportFormatting.reminderNoteText(for: context.task),
      day: parsedDate.map { calendar.startOfDay(for: $0) },
      timeMinutes: context.retainedTask.schedule.hasExplicitTime
        ? parsedDate.map { minutesSinceStartOfDay(for: $0, calendar: calendar) }
        : nil,
      durationMinutes: context.retainedTask.schedule.durationMinutes
    )
  }

  static func updateTaskEditFields(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    fields rawFields: RetainedTaskEditFields,
    calendar: Calendar = .autoupdatingCurrent,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let title = rawFields.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw RetainedTaskCommandError.retainedProjectionFailed("empty task title")
    }
    let lease = await mutationLease(projectID: projectID, taskID: taskID)
    defer { releaseMutationLease(lease) }

    let context = try await commandContext(
      vaultRootURL: vaultRootURL,
      projectID: projectID,
      taskID: taskID
    )
    let reminderReference = try reminderReference(for: context.task, taskID: taskID)
    let previousState = ObsidianReminderImportFormatting.taskState(
      context.task,
      calendar: calendar
    )
    let dueDate = scheduledDate(day: rawFields.day, timeMinutes: rawFields.timeMinutes, calendar: calendar)
    let hasExplicitTime = dueDate != nil && rawFields.timeMinutes != nil
    let nextState = ReminderSyncTaskState(
      title: title,
      isCompleted: previousState.isCompleted,
      date: ReminderScheduleMetadataCodec.encodeDate(dueDate, hasExplicitTime: hasExplicitTime),
      repeatRule: previousState.repeatRule,
      noteText: rawFields.noteText
    )
    let changedFields = editableChangedFields(from: previousState, to: nextState)
    guard !changedFields.isEmpty else {
      return try result(projectID: projectID, taskID: taskID, snapshot: context.snapshot)
    }

    var originalBaseline: ReminderSyncTaskBaselineRecord?
    for field in changedFields {
      let baseline = try assertReminderWriteAllowed(
        reference: reminderReference,
        field: field,
        reminderProjectProvider: reminderProjectProvider
      )
      originalBaseline = originalBaseline ?? baseline
    }

    let writtenSnapshot = try await writeTask(
      using: context,
      mutate: { task, bodyLines in
        bodyLines[task.bodyLineIndex] = ObsidianReminderImportFormatting.taskLine(
          nextState,
          existing: task
        )
        let metadata = scheduleMetadata(
          existing: task.metadata,
          reminderExternalIdentifier: task.reminderExternalIdentifier,
          day: rawFields.day,
          timeMinutes: rawFields.timeMinutes,
          durationMinutes: hasExplicitTime ? rawFields.durationMinutes : nil,
          calendar: calendar
        )
        let metadataLineIndex = applyMetadata(metadata, to: task, in: &bodyLines)
        replaceTaskNoteSubtree(
          nextState.noteText,
          task: task,
          metadataLineIndex: metadataLineIndex,
          in: &bodyLines
        )
      }
    )

    do {
      var remoteModifiedAt: Date?
      if changedFields.contains(.title) {
        guard let metadata = try reminderProjectProvider.setTaskTitle(
          for: reminderReference,
          title: nextState.title
        ) else {
          throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
        }
        remoteModifiedAt = metadata.modifiedAt
      }
      if changedFields.contains(.noteText) {
        guard let metadata = try reminderProjectProvider.setTaskReminderNote(
          for: reminderReference,
          noteText: nextState.noteText ?? ""
        ) else {
          throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
        }
        remoteModifiedAt = metadata.modifiedAt
      }
      if changedFields.contains(.date) {
        guard let metadata = try reminderProjectProvider.setTaskSchedule(
          for: reminderReference,
          dueDate: dueDate,
          hasExplicitTime: hasExplicitTime
        ) else {
          throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
        }
        remoteModifiedAt = metadata.modifiedAt
      }
      try updateBaseline(
        from: writtenSnapshot,
        taskID: taskID,
        reminderExternalIdentifier: reminderReference.reminderExternalIdentifier,
        remoteModifiedAt: remoteModifiedAt,
        pushedFields: changedFields,
        previousBaseline: originalBaseline
      )
    } catch {
      try await rollbackObsidianWrite(
        context: context,
        writtenSnapshot: writtenSnapshot,
        writeError: error
      )
    }

    return try result(projectID: projectID, taskID: taskID, snapshot: writtenSnapshot)
  }

  private struct CommandContext {
    let store: ObsidianProjectMarkdownStore
    let snapshot: ObsidianProjectMarkdownStore.Snapshot
    let task: ObsidianProjectTask
    let retainedTask: RetainedTask
  }

  private struct ProjectCommandContext {
    let store: ObsidianProjectMarkdownStore
    let snapshot: ObsidianProjectMarkdownStore.Snapshot
    let reminderListExternalIdentifier: String
  }

  private static func mutationLease(
    projectID: UUID,
    taskID: UUID? = nil
  ) async -> RetainedTaskCommandMutationLease {
    var keys: Set<RetainedTaskCommandMutationKey> = [.project(projectID)]
    if let taskID {
      keys.insert(.task(taskID))
    }
    return await mutationGate.acquire(keys)
  }

  private static func mutationLease(
    sourceProjectID: UUID,
    targetProjectID: UUID,
    taskID: UUID
  ) async -> RetainedTaskCommandMutationLease {
    await mutationGate.acquire([
      .project(sourceProjectID),
      .project(targetProjectID),
      .task(taskID),
    ])
  }

  private static func releaseMutationLease(_ lease: RetainedTaskCommandMutationLease) {
    Task {
      await lease.release()
    }
  }

  private static func projectContext(
    vaultRootURL: URL?,
    projectID: UUID
  ) async throws -> ProjectCommandContext {
    guard let vaultRootURL else {
      throw RetainedTaskCommandError.obsidianVaultNotConfigured
    }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultRootURL)
    let snapshots = try await store.loadProjectNotesInScope()
    try validateNotes(snapshots.map(\.note))
    guard let snapshot = snapshots.first(where: { retainedProjectID(for: $0) == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    guard let reminderListExternalIdentifier = normalized(
      snapshot.note.reminderListExternalIdentifier
    ) else {
      throw RetainedTaskCommandError.unsafeProjectNote(projectID)
    }
    return ProjectCommandContext(
      store: store,
      snapshot: snapshot,
      reminderListExternalIdentifier: reminderListExternalIdentifier
    )
  }

  private static func commandContext(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID
  ) async throws -> CommandContext {
    guard let vaultRootURL else {
      throw RetainedTaskCommandError.obsidianVaultNotConfigured
    }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultRootURL)
    let snapshots = try await store.loadProjectNotesInScope()
    try validateNotes(snapshots.map(\.note))
    let retainedSnapshot = try ObsidianRetainedProjectionAdapter.build(snapshots: snapshots)
    guard let project = retainedSnapshot.projects.first(where: { $0.identity.projectID == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    guard let retainedTask = project.tasks.first(where: { $0.identity.taskID == taskID }) else {
      throw RetainedTaskCommandError.taskNotFound(taskID)
    }
    guard retainedTask.identity.reminderExternalIdentifier != nil else {
      throw RetainedTaskCommandError.missingReminderExternalIdentifier(taskID)
    }
    guard let snapshot = snapshots.first(where: { retainedProjectID(for: $0) == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    guard let task = snapshot.note.tasks.first(where: { retainedTaskID(for: $0) == taskID }) else {
      throw RetainedTaskCommandError.unmanagedTask(taskID)
    }
    guard snapshot.note.reminderListExternalIdentifier != nil else {
      throw RetainedTaskCommandError.unsafeProjectNote(projectID)
    }
    return CommandContext(
      store: store,
      snapshot: snapshot,
      task: task,
      retainedTask: retainedTask
    )
  }

  private static func writeTask(
    using context: CommandContext,
    mutate: (ObsidianProjectTask, inout [String]) -> Void
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    var bodyLines = context.snapshot.note.bodyMarkdown.components(separatedBy: "\n")
    guard bodyLines.indices.contains(context.task.bodyLineIndex) else {
      throw RetainedTaskCommandError.unmanagedTask(context.retainedTask.identity.taskID ?? UUID())
    }
    mutate(context.task, &bodyLines)
    let note = ObsidianReminderImportFormatting.reparsedNote(
      from: context.snapshot.note,
      bodyLines: bodyLines
    )
    try validateNotes([note])
    return try await context.store.writeProjectNote(
      note,
      preferredFileName: context.snapshot.fileURL.lastPathComponent,
      expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: context.snapshot)
    )
  }

  private static func writeDeletedTask(
    using context: CommandContext
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    var bodyLines = context.snapshot.note.bodyMarkdown.components(separatedBy: "\n")
    guard bodyLines.indices.contains(context.task.bodyLineIndex) else {
      throw RetainedTaskCommandError.unmanagedTask(context.retainedTask.identity.taskID ?? UUID())
    }
    let deletionRange = taskDeletionRange(for: context.task, in: bodyLines)
    bodyLines.removeSubrange(deletionRange)
    let note = ObsidianReminderImportFormatting.reparsedNote(
      from: context.snapshot.note,
      bodyLines: bodyLines
    )
    try validateNotes([note])
    return try await context.store.writeProjectNote(
      note,
      preferredFileName: context.snapshot.fileURL.lastPathComponent,
      expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: context.snapshot)
    )
  }

  private static func writeRemovedTaskForMove(
    using context: CommandContext
  ) async throws -> (ObsidianProjectMarkdownStore.Snapshot, [String]) {
    var bodyLines = context.snapshot.note.bodyMarkdown.components(separatedBy: "\n")
    guard bodyLines.indices.contains(context.task.bodyLineIndex) else {
      throw RetainedTaskCommandError.unmanagedTask(context.retainedTask.identity.taskID ?? UUID())
    }
    let deletionRange = taskDeletionRange(for: context.task, in: bodyLines)
    let movedLines = Array(bodyLines[deletionRange])
    bodyLines.removeSubrange(deletionRange)
    let note = ObsidianReminderImportFormatting.reparsedNote(
      from: context.snapshot.note,
      bodyLines: bodyLines
    )
    try validateNotes([note])
    let snapshot = try await context.store.writeProjectNote(
      note,
      preferredFileName: context.snapshot.fileURL.lastPathComponent,
      expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: context.snapshot)
    )
    return (snapshot, movedLines)
  }

  private static func writeMovedTask(
    using context: ProjectCommandContext,
    movedLines: [String],
    validationNotes: [ObsidianProjectNote]
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    var bodyLines = context.snapshot.note.bodyMarkdown.isEmpty
      ? []
      : context.snapshot.note.bodyMarkdown.components(separatedBy: "\n")
    bodyLines.append(contentsOf: movedLines)
    let note = ObsidianReminderImportFormatting.reparsedNote(
      from: context.snapshot.note,
      bodyLines: bodyLines
    )
    try validateNotes(validationNotes + [note])
    return try await context.store.writeProjectNote(
      note,
      preferredFileName: context.snapshot.fileURL.lastPathComponent,
      expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: context.snapshot)
    )
  }

  private static func writeCreatedTask(
    using context: ProjectCommandContext,
    title: String,
    reminderExternalIdentifier: String,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    var bodyLines = context.snapshot.note.bodyMarkdown.isEmpty
      ? []
      : context.snapshot.note.bodyMarkdown.components(separatedBy: "\n")
    bodyLines.append("- [ ] \(title)")
    let metadata = scheduleMetadata(
      existing: nil,
      reminderExternalIdentifier: reminderExternalIdentifier,
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes,
      calendar: calendar
    )
    bodyLines.append(
      ObsidianReminderImportFormatting.renderMetadataLine(metadata, indentation: "  ")
    )
    let note = ObsidianReminderImportFormatting.reparsedNote(
      from: context.snapshot.note,
      bodyLines: bodyLines
    )
    try validateNotes([note])
    return try await context.store.writeProjectNote(
      note,
      preferredFileName: context.snapshot.fileURL.lastPathComponent,
      expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: context.snapshot)
    )
  }

  private static func rollbackObsidianWrite(
    context: CommandContext,
    writtenSnapshot: ObsidianProjectMarkdownStore.Snapshot,
    writeError: Error
  ) async throws -> Never {
    try await rollbackProjectNote(
      store: context.store,
      originalSnapshot: context.snapshot,
      writtenSnapshot: writtenSnapshot,
      writeError: writeError
    )
    throw writeError
  }

  private static func rollbackProjectNote(
    store: ObsidianProjectMarkdownStore,
    originalSnapshot: ObsidianProjectMarkdownStore.Snapshot,
    writtenSnapshot: ObsidianProjectMarkdownStore.Snapshot,
    writeError: Error
  ) async throws {
    do {
      let currentSnapshot = try await store.loadProjectNotesInScope(
        at: [writtenSnapshot.fileURL]
      ).first
      guard let currentSnapshot,
        currentSnapshot.rawMarkdown == writtenSnapshot.rawMarkdown
      else {
        throw RetainedTaskCommandError.rollbackFailed(
          writeError: writeError.localizedDescription,
          rollbackError: "Obsidian note changed after command write"
        )
      }
      _ = try await store.writeProjectNote(
        originalSnapshot.note,
        preferredFileName: originalSnapshot.fileURL.lastPathComponent,
        expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: currentSnapshot)
      )
    } catch {
      throw RetainedTaskCommandError.rollbackFailed(
        writeError: writeError.localizedDescription,
        rollbackError: error.localizedDescription
      )
    }
  }

  private static func applyTaskState(
    _ state: ReminderSyncTaskState,
    to task: ObsidianProjectTask,
    in bodyLines: inout [String],
    calendar: Calendar
  ) {
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
    applyMetadata(metadata, to: task, in: &bodyLines)
  }

  private static func recurringCompletionSnapshot(
    reference: ReminderTaskReference,
    reminderProjectProvider: ReminderProjectProvider
  ) throws -> ReminderTaskRemoteSnapshot? {
    guard let snapshot = try reminderProjectProvider.taskSnapshot(for: reference),
      normalized(snapshot.recurrenceRuleRaw) != nil
    else {
      return nil
    }
    return snapshot
  }

  private static func remoteSnapshotClearingExplicitTime(
    _ snapshot: ReminderTaskRemoteSnapshot,
    modifiedAt: Date
  ) -> ReminderTaskRemoteSnapshot {
    ReminderTaskRemoteSnapshot(
      identifier: snapshot.identifier,
      externalIdentifier: snapshot.externalIdentifier,
      calendarIdentifier: snapshot.calendarIdentifier,
      title: snapshot.title,
      noteText: snapshot.noteText,
      isCompleted: snapshot.isCompleted,
      completionDate: snapshot.completionDate,
      startDate: snapshot.startDate,
      dueDate: snapshot.dueDate,
      hasExplicitTime: false,
      priority: snapshot.priority,
      recurrenceRuleRaw: snapshot.recurrenceRuleRaw,
      modifiedAt: modifiedAt
    )
  }

  private static func applyRecurringCompletionSnapshot(
    _ snapshot: ReminderTaskRemoteSnapshot,
    to task: ObsidianProjectTask,
    in bodyLines: inout [String],
    calendar: Calendar
  ) {
    let remoteState = ReminderSyncTaskState(remoteSnapshot: snapshot)
    var nextState = ObsidianReminderImportFormatting.taskState(task, calendar: calendar)
    nextState.isCompleted = remoteState.isCompleted
    nextState.date = remoteState.date
    bodyLines[task.bodyLineIndex] = ObsidianReminderImportFormatting.taskLine(
      nextState,
      existing: task
    )
    let baseMetadata = ObsidianReminderImportFormatting.metadata(
      existing: task.metadata,
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      state: nextState,
      calendar: calendar
    )
    let metadata = ObsidianTaskMetadata(
      reminderExternalIdentifier: baseMetadata.reminderExternalIdentifier,
      date: baseMetadata.date,
      time: baseMetadata.time,
      durationMinutes: snapshot.hasExplicitTime ? task.metadata?.durationMinutes : nil,
      repeatRule: baseMetadata.repeatRule
    )
    applyMetadata(metadata, to: task, in: &bodyLines)
  }

  @discardableResult
  private static func applyMetadata(
    _ metadata: ObsidianTaskMetadata,
    to task: ObsidianProjectTask,
    in bodyLines: inout [String]
  ) -> Int {
    let metadataLine = ObsidianReminderImportFormatting.renderMetadataLine(
      metadata,
      indentation: task.indentation + "  "
    )
    if let metadataLineIndex = task.metadataLineIndex,
      bodyLines.indices.contains(metadataLineIndex)
    {
      bodyLines[metadataLineIndex] = metadataLine
      return metadataLineIndex
    } else {
      let insertionIndex = min(task.bodyLineIndex + 1, bodyLines.count)
      bodyLines.insert(metadataLine, at: insertionIndex)
      return insertionIndex
    }
  }

  private static func replaceTaskNoteSubtree(
    _ noteText: String?,
    task: ObsidianProjectTask,
    metadataLineIndex: Int,
    in bodyLines: inout [String]
  ) {
    let subtreeEndIndex = ObsidianReminderImportFormatting.taskSubtreeEndIndex(
      from: task.bodyLineIndex,
      task: task,
      in: bodyLines
    )
    let ownContentEndIndex = min(metadataLineIndex + 1, bodyLines.count)
    let preserved = preservedDescendantTaskBlocks(
      from: ownContentEndIndex,
      to: subtreeEndIndex,
      parentTask: task,
      in: bodyLines
    )
    let replacement = ObsidianReminderImportFormatting.renderedSubtreeLines(
      fromReminderNote: noteText,
      parentIndentation: task.indentation,
      preservedTaskBlocks: preserved
    )
    bodyLines.replaceSubrange(ownContentEndIndex..<subtreeEndIndex, with: replacement)
  }

  private static func preservedDescendantTaskBlocks(
    from startIndex: Int,
    to endIndex: Int,
    parentTask: ObsidianProjectTask,
    in bodyLines: [String]
  ) -> ObsidianReminderImportFormatting.PreservedDescendantTaskBlocks {
    var orderedIdentifiers: [String] = []
    var blocksByIdentifier: [String: [String]] = [:]
    var index = startIndex
    while index < endIndex {
      guard
        bodyLines.indices.contains(index),
        let parsedIndentation = ObsidianReminderImportFormatting.parseTaskLineIndentation(
          bodyLines[index]
        ),
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
      if let identifier = ObsidianReminderImportFormatting.reminderIdentifier(
        in: Array(bodyLines[index..<blockEnd])
      ), blocksByIdentifier[identifier] == nil {
        orderedIdentifiers.append(identifier)
        blocksByIdentifier[identifier] = Array(bodyLines[index..<blockEnd])
      }
      index = blockEnd
    }
    return ObsidianReminderImportFormatting.PreservedDescendantTaskBlocks(
      orderedIdentifiers: orderedIdentifiers,
      blocksByIdentifier: blocksByIdentifier
    )
  }

  private static func updateBaseline(
    from snapshot: ObsidianProjectMarkdownStore.Snapshot,
    taskID: UUID,
    reminderExternalIdentifier: String?,
    remoteModifiedAt: Date?,
    pushedFields: [ReminderSyncTaskField],
    previousBaseline: ReminderSyncTaskBaselineRecord?
  ) throws {
    guard let task = snapshot.note.tasks.first(where: { retainedTaskID(for: $0) == taskID }) else {
      throw RetainedTaskCommandError.taskNotFound(taskID)
    }
    let local = ObsidianReminderImportFormatting.taskState(task, calendar: .autoupdatingCurrent)
    var next = previousBaseline?.state ?? local
    var conflicts = previousBaseline?.conflictedFields ?? []
    for field in pushedFields {
      next = next.replacing(field: field, with: local)
      conflicts.removeAll { $0 == field }
    }
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: reminderExternalIdentifier,
      state: next,
      remoteModifiedAt: remoteModifiedAt,
      conflictedFields: conflicts,
      now: .now
    )
  }

  private static func assertReminderWriteAllowed(
    reference: ReminderTaskReference,
    field: ReminderSyncTaskField,
    reminderProjectProvider: ReminderProjectProvider
  ) throws -> ReminderSyncTaskBaselineRecord {
    guard let baseline = ReminderSyncBaselineStore.baseline(
      for: reference.reminderExternalIdentifier
    ) else {
      throw RetainedTaskCommandError.retainedProjectionFailed("missing reminder sync baseline")
    }
    guard let baselineRemoteModifiedAt = baseline.remoteModifiedAt else {
      throw RetainedTaskCommandError.retainedProjectionFailed("missing reminder baseline timestamp")
    }
    guard let remoteSnapshot = try reminderProjectProvider.taskSnapshot(for: reference) else {
      throw RetainedTaskCommandError.reminderOwnerUnresolved(reference.taskID)
    }
    let remoteModificationDelta = remoteSnapshot.modifiedAt.timeIntervalSince(baselineRemoteModifiedAt)
    if remoteModificationDelta < -reminderTimestampTolerance {
      return baseline
    }
    let remoteState = ReminderSyncTaskState(remoteSnapshot: remoteSnapshot)
    guard remoteState.value(for: field) == baseline.state.value(for: field) else {
      throw RetainedTaskCommandError.retainedProjectionFailed("remote reminder changed \(field.rawValue)")
    }
    return baseline
  }

  private static func assertReminderDeleteAllowed(
    reference: ReminderTaskReference,
    reminderProjectProvider: ReminderProjectProvider
  ) throws -> ReminderSyncTaskBaselineRecord {
    guard let baseline = ReminderSyncBaselineStore.baseline(
      for: reference.reminderExternalIdentifier
    ) else {
      throw RetainedTaskCommandError.retainedProjectionFailed("missing reminder sync baseline")
    }
    guard let baselineRemoteModifiedAt = baseline.remoteModifiedAt else {
      throw RetainedTaskCommandError.retainedProjectionFailed("missing reminder baseline timestamp")
    }
    guard let remoteSnapshot = try reminderProjectProvider.taskSnapshot(for: reference) else {
      throw RetainedTaskCommandError.reminderOwnerUnresolved(reference.taskID)
    }
    guard remoteSnapshot.modifiedAt.timeIntervalSince(baselineRemoteModifiedAt) <= reminderTimestampTolerance else {
      throw RetainedTaskCommandError.retainedProjectionFailed("stale reminder sync baseline")
    }
    return baseline
  }

  private static func result(
    projectID: UUID,
    taskID: UUID,
    snapshot: ObsidianProjectMarkdownStore.Snapshot
  ) throws -> RetainedTaskCommandResult {
    let retainedSnapshot = try ObsidianRetainedProjectionAdapter.build(snapshots: [snapshot])
    guard let task = retainedSnapshot.tasks.first(where: { $0.identity.taskID == taskID }) else {
      throw RetainedTaskCommandError.taskNotFound(taskID)
    }
    let calendarBridgeDecision = RetainedCalendarBridgePolicy.decision(for: task)
    return RetainedTaskCommandResult(
      projectID: projectID,
      taskID: taskID,
      calendarBridgeDecision: calendarBridgeDecision,
      calendarWriteMarker: RetainedCalendarBridgeWriteLoopGuard.marker(
        taskID: taskID,
        decision: calendarBridgeDecision
      )
    )
  }

  private static func reminderReference(
    for task: ObsidianProjectTask,
    taskID: UUID
  ) throws -> ReminderTaskReference {
    guard let reminderExternalIdentifier = normalized(task.reminderExternalIdentifier) else {
      throw RetainedTaskCommandError.missingReminderExternalIdentifier(taskID)
    }
    return ReminderTaskReference(
      taskID: taskID,
      reminderIdentifier: nil,
      reminderExternalIdentifier: reminderExternalIdentifier
    )
  }

  private static func taskDeletionRange(
    for task: ObsidianProjectTask,
    in bodyLines: [String]
  ) -> Range<Int> {
    let taskIndentationWidth = ObsidianReminderImportFormatting.indentationWidth(task.indentation)
    let lowerBound = task.bodyLineIndex
    let upperBound = bodyLines.indices.dropFirst(task.bodyLineIndex + 1).first { index in
      guard index != task.metadataLineIndex else { return false }
      let line = bodyLines[index]
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        return false
      }
      return leadingIndentationWidth(of: line) <= taskIndentationWidth
    } ?? bodyLines.count
    return lowerBound..<upperBound
  }

  private static func leadingIndentationWidth(of line: String) -> Int {
    let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
    return ObsidianReminderImportFormatting.indentationWidth(indentation)
  }

  private static func scheduleMetadata(
    existing: ObsidianTaskMetadata?,
    reminderExternalIdentifier: String?,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar
  ) -> ObsidianTaskMetadata {
    let hasExplicitTime = day != nil && timeMinutes != nil
    return ObsidianTaskMetadata(
      reminderExternalIdentifier: normalized(reminderExternalIdentifier)
        ?? existing?.reminderExternalIdentifier,
      date: day.map { dayFormatter.string(from: calendar.startOfDay(for: $0)) },
      time: timeMinutes.map(timeString),
      durationMinutes: hasExplicitTime ? normalizedDuration(durationMinutes) : nil,
      repeatRule: existing?.repeatRule
    )
  }

  private static func scheduledDate(
    day: Date?,
    timeMinutes: Int?,
    calendar: Calendar
  ) -> Date? {
    guard let day else { return nil }
    let normalizedDay = calendar.startOfDay(for: day)
    guard let timeMinutes else { return normalizedDay }
    let boundedMinutes = min(max(0, timeMinutes), 23 * 60 + 59)
    return calendar.date(
      bySettingHour: boundedMinutes / 60,
      minute: boundedMinutes % 60,
      second: 0,
      of: normalizedDay
    ) ?? normalizedDay
  }

  private static func editableChangedFields(
    from previous: ReminderSyncTaskState,
    to next: ReminderSyncTaskState
  ) -> [ReminderSyncTaskField] {
    [.title, .noteText, .date].filter {
      previous.value(for: $0) != next.value(for: $0)
    }
  }

  private static func minutesSinceStartOfDay(for date: Date, calendar: Calendar) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  private static func normalizedDuration(_ durationMinutes: Int?) -> Int? {
    guard let durationMinutes, durationMinutes > 0 else { return nil }
    return durationMinutes
  }

  private static func timeString(_ minutes: Int) -> String {
    let bounded = min(max(0, minutes), 23 * 60 + 59)
    return String(format: "%02d:%02d", bounded / 60, bounded % 60)
  }

  private static func retainedProjectID(
    for snapshot: ObsidianProjectMarkdownStore.Snapshot
  ) -> UUID? {
    guard let listID = normalized(snapshot.note.reminderListExternalIdentifier) else {
      return nil
    }
    return RetainedProjectionBuilder.derivedProjectID(for: listID)
  }

  private static func retainedTaskID(for task: ObsidianProjectTask) -> UUID? {
    guard let reminderExternalIdentifier = normalized(task.reminderExternalIdentifier) else {
      return nil
    }
    return ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
  }

  private static func validateNotes(_ notes: [ObsidianProjectNote]) throws {
    for issue in ObsidianProjectNoteValidation.issues(in: notes) {
      switch issue {
      case .duplicateReminderListExternalIdentifier(let identifier):
        throw RetainedTaskCommandError.retainedProjectionFailed(
          "duplicate reminder_list_external_id \(identifier)"
        )
      case .duplicateReminderExternalIdentifier(let identifier):
        throw RetainedTaskCommandError.retainedProjectionFailed(
          "duplicate reminder_external_id \(identifier)"
        )
      case .damagedTaskMetadata(let line, let rawLine):
        throw RetainedTaskCommandError.retainedProjectionFailed(
          "damaged metadata line \(line): \(rawLine)"
        )
      }
    }
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
