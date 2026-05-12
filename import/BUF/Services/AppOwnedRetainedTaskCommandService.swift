import Foundation

@MainActor
enum AppOwnedRetainedTaskCommandService {
  static func enabledStore(vaultRootURL: URL?) async throws -> AppOwnedWorkspaceStore? {
    guard let vaultRootURL else { return nil }
    let store = AppOwnedWorkspaceStore.storeForVaultRootURL(vaultRootURL)
    guard try await store.isProjectionReadEnabled(),
      try await store.hasImportedWorkspace()
    else {
      return nil
    }
    return store
  }

  static func createTask(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    title rawTitle: String,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw RetainedTaskCommandError.retainedProjectionFailed("empty task title")
    }
    let project = try await store.projectReference(projectID: projectID)
    let dueDate = scheduledDate(day: day, timeMinutes: timeMinutes, calendar: calendar)
    let hasExplicitTime = dueDate != nil && timeMinutes != nil
    guard let metadata = try reminderProjectProvider.createTaskReminder(
      inProject: project.reminderListIdentifier,
      title: title,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      noteText: ""
    ), let reminderExternalIdentifier = normalized(metadata.externalIdentifier) else {
      throw RetainedTaskCommandError.retainedProjectionFailed("created reminder missing external id")
    }
    let taskID = ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
    do {
      try await store.upsertTask(
        projectID: projectID,
        taskID: taskID,
        reminderIdentifier: metadata.identifier,
        reminderExternalIdentifier: reminderExternalIdentifier,
        title: title,
        noteText: "",
        isCompleted: false,
        completionDate: nil,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime,
        durationMinutes: durationMinutes,
        priority: 0,
        modifiedAt: metadata.modifiedAt
      )
    } catch {
      _ = try? reminderProjectProvider.removeTaskReminder(
        for: ReminderTaskReference(
          taskID: taskID,
          reminderIdentifier: metadata.identifier,
          reminderExternalIdentifier: reminderExternalIdentifier
        )
      )
      throw error
    }
    updateBaseline(
      reminderExternalIdentifier: reminderExternalIdentifier,
      title: title,
      isCompleted: false,
      noteText: "",
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      recurrenceRuleRaw: nil,
      remoteModifiedAt: metadata.modifiedAt
    )
    TaskIdentityBridgeStore.upsertProject(
      projectID: projectID,
      title: project.title,
      reminderListExternalIdentifier: project.reminderListExternalIdentifier ?? project.reminderListIdentifier
    )
    TaskIdentityBridgeStore.upsertTask(
      taskID: taskID,
      title: title,
      reminderExternalIdentifier: reminderExternalIdentifier,
      ownerProjectID: projectID
    )
    return RetainedTaskCommandResult(
      projectID: projectID,
      taskID: taskID,
      calendarBridgeDecision: .noAction,
      calendarWriteMarker: nil
    )
  }

  static func taskEditFields(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    taskID: UUID,
    calendar: Calendar
  ) async throws -> RetainedTaskEditFields {
    let task = try await store.taskReference(projectID: projectID, taskID: taskID)
    return RetainedTaskEditFields(
      title: task.title,
      noteText: task.noteText,
      day: task.dueDate.map { calendar.startOfDay(for: $0) },
      timeMinutes: task.hasExplicitTime ? task.dueDate.map { minutesSinceStartOfDay(for: $0, calendar: calendar) } : nil,
      durationMinutes: task.durationMinutes,
      recurrenceRuleRaw: task.recurrenceRuleRaw,
      updatesRecurrence: true
    )
  }

  static func updateTaskEditFields(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    taskID: UUID,
    fields rawFields: RetainedTaskEditFields,
    calendar: Calendar,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let task = try await store.taskReference(projectID: projectID, taskID: taskID)
    let dueDate = scheduledDate(day: rawFields.day, timeMinutes: rawFields.timeMinutes, calendar: calendar)
    let hasExplicitTime = dueDate != nil && rawFields.timeMinutes != nil
    let effectiveDurationMinutes = hasExplicitTime ? (rawFields.durationMinutes ?? task.durationMinutes) : nil
    let recurrenceRuleRaw = rawFields.updatesRecurrence
      ? normalized(rawFields.recurrenceRuleRaw)
      : task.recurrenceRuleRaw
    let reference = reminderReference(task)
    var latestModifiedAt: Date?

    if rawFields.title != task.title {
      latestModifiedAt = try reminderProjectProvider.setTaskTitle(
        for: reference,
        title: rawFields.title
      )?.modifiedAt
    }
    if rawFields.noteText != task.noteText {
      latestModifiedAt = try reminderProjectProvider.setTaskReminderNote(
        for: reference,
        noteText: rawFields.noteText
      )?.modifiedAt ?? latestModifiedAt
    }
    if dueDate != task.dueDate || hasExplicitTime != task.hasExplicitTime {
      latestModifiedAt = try reminderProjectProvider.setTaskSchedule(
        for: reference,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime
      )?.modifiedAt ?? latestModifiedAt
    }
    if rawFields.updatesRecurrence, recurrenceRuleRaw != normalized(task.recurrenceRuleRaw) {
      latestModifiedAt = try reminderProjectProvider.setTaskRecurrence(
        for: reference,
        recurrenceRuleRaw: recurrenceRuleRaw
      )?.modifiedAt ?? latestModifiedAt
    }

    let modifiedAt = latestModifiedAt ?? .now
    try await store.upsertTask(
      projectID: projectID,
      taskID: taskID,
      reminderIdentifier: task.reminderIdentifier,
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      title: rawFields.title,
      noteText: rawFields.noteText,
      isCompleted: task.isCompleted,
      completionDate: task.completionDate,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      durationMinutes: effectiveDurationMinutes,
      recurrenceRuleRaw: recurrenceRuleRaw,
      priority: task.priority,
      modifiedAt: modifiedAt,
      appendIfMissing: false
    )
    updateBaseline(
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      title: rawFields.title,
      isCompleted: task.isCompleted,
      noteText: rawFields.noteText,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      recurrenceRuleRaw: recurrenceRuleRaw,
      remoteModifiedAt: modifiedAt
    )
    TaskIdentityBridgeStore.upsertTask(
      taskID: taskID,
      title: rawFields.title,
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      ownerProjectID: projectID
    )
    return commandResult(projectID: projectID, taskID: taskID)
  }

  static func setTaskCompletion(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    taskID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let task = try await store.taskReference(projectID: projectID, taskID: taskID)
    let reference = reminderReference(task)
    let resolvedCompletionDate = completionDate ?? .now
    guard let metadata = try reminderProjectProvider.setTaskCompletion(
      for: reference,
      isCompleted: isCompleted,
      completionDate: isCompleted ? resolvedCompletionDate : nil
    ) else {
      throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
    }
    if isCompleted,
      normalized(task.recurrenceRuleRaw) != nil,
      var remoteSnapshot = try recurringCompletionSnapshot(
        reference: reference,
        reminderProjectProvider: reminderProjectProvider
      )
    {
      if task.hasExplicitTime,
        remoteSnapshot.hasExplicitTime,
        let nextDueDate = remoteSnapshot.dueDate,
        let scheduleMetadata = try reminderProjectProvider.setTaskSchedule(
          for: reference,
          dueDate: nextDueDate,
          hasExplicitTime: false
        )
      {
        remoteSnapshot = try recurringCompletionSnapshot(
          reference: reference,
          reminderProjectProvider: reminderProjectProvider
        ) ?? remoteSnapshotClearingExplicitTime(remoteSnapshot, modifiedAt: scheduleMetadata.modifiedAt)
      }
      let activeReminderExternalIdentifier =
        remoteSnapshot.externalIdentifier ?? task.reminderExternalIdentifier
      try await store.upsertTask(
        projectID: projectID,
        taskID: taskID,
        reminderIdentifier: remoteSnapshot.identifier,
        reminderExternalIdentifier: activeReminderExternalIdentifier,
        title: remoteSnapshot.title,
        noteText: remoteSnapshot.noteText,
        isCompleted: remoteSnapshot.isCompleted,
        completionDate: remoteSnapshot.completionDate,
        dueDate: remoteSnapshot.dueDate,
        hasExplicitTime: remoteSnapshot.hasExplicitTime,
        durationMinutes: remoteSnapshot.hasExplicitTime ? task.durationMinutes : nil,
        recurrenceRuleRaw: remoteSnapshot.recurrenceRuleRaw,
        priority: remoteSnapshot.priority,
        modifiedAt: remoteSnapshot.modifiedAt,
        appendIfMissing: false
      )
      _ = try await store.upsertLocalCompletedRecurringOccurrence(
        projectID: projectID,
        sourceTask: AppOwnedWorkspaceStore.TaskReference(
          projectID: task.projectID,
          taskID: task.taskID,
          reminderIdentifier: task.reminderIdentifier,
          reminderExternalIdentifier: activeReminderExternalIdentifier,
          title: task.title,
          noteText: task.noteText,
          isCompleted: true,
          completionDate: resolvedCompletionDate,
          dueDate: task.dueDate,
          hasExplicitTime: task.hasExplicitTime,
          durationMinutes: task.durationMinutes,
          recurrenceRuleRaw: task.recurrenceRuleRaw,
          priority: task.priority
        ),
        completionDate: resolvedCompletionDate,
        modifiedAt: remoteSnapshot.modifiedAt
      )
      updateBaseline(
        reminderExternalIdentifier: activeReminderExternalIdentifier,
        title: remoteSnapshot.title,
        isCompleted: remoteSnapshot.isCompleted,
        noteText: remoteSnapshot.noteText,
        dueDate: remoteSnapshot.dueDate,
        hasExplicitTime: remoteSnapshot.hasExplicitTime,
        recurrenceRuleRaw: remoteSnapshot.recurrenceRuleRaw,
        remoteModifiedAt: remoteSnapshot.modifiedAt
      )
      TaskIdentityBridgeStore.upsertTask(
        taskID: taskID,
        title: remoteSnapshot.title,
        reminderExternalIdentifier: activeReminderExternalIdentifier,
        ownerProjectID: projectID
      )
      return commandResult(projectID: projectID, taskID: taskID)
    }
    try await store.upsertTask(
      projectID: projectID,
      taskID: taskID,
      reminderIdentifier: task.reminderIdentifier,
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      title: task.title,
      noteText: task.noteText,
      isCompleted: isCompleted,
      completionDate: isCompleted ? resolvedCompletionDate : nil,
      dueDate: task.dueDate,
      hasExplicitTime: task.hasExplicitTime,
      durationMinutes: task.durationMinutes,
      recurrenceRuleRaw: task.recurrenceRuleRaw,
      modifiedAt: metadata.modifiedAt,
      appendIfMissing: false
    )
    updateBaseline(
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      title: task.title,
      isCompleted: isCompleted,
      noteText: task.noteText,
      dueDate: task.dueDate,
      hasExplicitTime: task.hasExplicitTime,
      recurrenceRuleRaw: task.recurrenceRuleRaw,
      remoteModifiedAt: metadata.modifiedAt
    )
    return commandResult(projectID: projectID, taskID: taskID)
  }

  static func setTaskSchedule(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    taskID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar,
    reminderProjectProvider: ReminderProjectProvider,
    resetRecurringAnchor: Bool = false
  ) async throws -> RetainedTaskCommandResult {
    let task = try await store.taskReference(projectID: projectID, taskID: taskID)
    let dueDate = scheduledDate(day: day, timeMinutes: timeMinutes, calendar: calendar)
    let hasExplicitTime = dueDate != nil && timeMinutes != nil
    let effectiveDurationMinutes = hasExplicitTime ? (durationMinutes ?? task.durationMinutes) : nil
    var taskForStorage = task
    var remoteMetadata: ReminderTaskRemoteMetadata?
    if resetRecurringAnchor, normalized(task.recurrenceRuleRaw) != nil {
      let project = try await store.projectReference(projectID: projectID)
      return try await recreateRecurringReminderAnchor(
        store: store,
        project: project,
        task: task,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime,
        durationMinutes: effectiveDurationMinutes,
        reminderProjectProvider: reminderProjectProvider
      )
    }
    let scheduleDateChanged = !matchesScheduleDate(task, dueDate: dueDate, hasExplicitTime: hasExplicitTime)
    let modifiedAt: Date
    if scheduleDateChanged {
      let metadata = try reminderProjectProvider.setTaskSchedule(
        for: reminderReference(task),
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime
      )
      if let metadata {
        remoteMetadata = metadata
      } else {
        switch try await retryScheduleAfterReminderRefresh(
          store: store,
          projectID: projectID,
          originalTask: task,
          dueDate: dueDate,
          hasExplicitTime: hasExplicitTime,
          reminderProjectProvider: reminderProjectProvider
        ) {
        case .resolved(let refreshedTask, let metadata):
          taskForStorage = refreshedTask
          remoteMetadata = metadata
        case .removedStaleTask:
          return commandResult(projectID: projectID, taskID: taskID)
        case .unresolved:
          throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
        }
      }
      guard let remoteMetadata else {
        throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
      }
      modifiedAt = remoteMetadata.modifiedAt
      updateBaseline(
        reminderExternalIdentifier: normalized(remoteMetadata.externalIdentifier)
          ?? taskForStorage.reminderExternalIdentifier,
        title: task.title,
        isCompleted: task.isCompleted,
        noteText: task.noteText,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime,
        recurrenceRuleRaw: taskForStorage.recurrenceRuleRaw,
        remoteModifiedAt: remoteMetadata.modifiedAt
      )
    } else {
      modifiedAt = .now
    }
    try await store.upsertTask(
      projectID: projectID,
      taskID: taskID,
      reminderIdentifier: remoteMetadata?.identifier ?? taskForStorage.reminderIdentifier,
      reminderExternalIdentifier: normalized(remoteMetadata?.externalIdentifier)
        ?? taskForStorage.reminderExternalIdentifier,
      title: taskForStorage.title,
      noteText: taskForStorage.noteText,
      isCompleted: taskForStorage.isCompleted,
      completionDate: taskForStorage.completionDate,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      durationMinutes: effectiveDurationMinutes,
      recurrenceRuleRaw: taskForStorage.recurrenceRuleRaw,
      priority: taskForStorage.priority,
      modifiedAt: modifiedAt,
      appendIfMissing: false
    )
    return commandResult(projectID: projectID, taskID: taskID)
  }

  private enum ReminderScheduleRetryResult {
    case resolved(AppOwnedWorkspaceStore.TaskReference, ReminderTaskRemoteMetadata)
    case removedStaleTask
    case unresolved
  }

  private static func retryScheduleAfterReminderRefresh(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    originalTask: AppOwnedWorkspaceStore.TaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> ReminderScheduleRetryResult {
    let project = try await store.projectReference(projectID: projectID)
    guard let batch = try await reminderProjectProvider.fetchImportSnapshotBatch(
      forListIdentifiers: [project.reminderListIdentifier]
    ) else {
      return .unresolved
    }

    try await store.replaceReminderSnapshot(
      batch,
      importedAt: .now,
      coverage: .listedProjectsOnly
    )

    let refreshedTask: AppOwnedWorkspaceStore.TaskReference
    do {
      refreshedTask = try await store.taskReference(projectID: projectID, taskID: originalTask.taskID)
    } catch RetainedTaskCommandError.taskNotFound {
      return .removedStaleTask
    }

    guard let metadata = try reminderProjectProvider.setTaskSchedule(
      for: reminderReference(refreshedTask),
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime
    ) else {
      return .unresolved
    }
    return .resolved(refreshedTask, metadata)
  }

  private static func recreateRecurringReminderAnchor(
    store: AppOwnedWorkspaceStore,
    project: AppOwnedWorkspaceStore.ProjectReference,
    task: AppOwnedWorkspaceStore.TaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool,
    durationMinutes: Int?,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let oldReference = reminderReference(task)
    guard let createdMetadata = try reminderProjectProvider.createTaskReminder(
      inProject: project.reminderListIdentifier,
      title: task.title,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      noteText: task.noteText
    ), let createdExternalIdentifier = normalized(createdMetadata.externalIdentifier) else {
      throw RetainedTaskCommandError.retainedProjectionFailed("recreated reminder missing external id")
    }

    let newReference = ReminderTaskReference(
      taskID: task.taskID,
      reminderIdentifier: createdMetadata.identifier,
      reminderExternalIdentifier: createdExternalIdentifier
    )
    var didRemoveOldReminder = false
    do {
      var modifiedAt = createdMetadata.modifiedAt
      if let recurrenceRuleRaw = normalized(task.recurrenceRuleRaw) {
        modifiedAt = try reminderProjectProvider.setTaskRecurrence(
          for: newReference,
          recurrenceRuleRaw: recurrenceRuleRaw
        )?.modifiedAt ?? modifiedAt
      }
      guard try reminderProjectProvider.removeTaskReminder(for: oldReference) else {
        throw RetainedTaskCommandError.reminderOwnerUnresolved(task.taskID)
      }
      didRemoveOldReminder = true

      let remoteSnapshot = try reminderProjectProvider.taskSnapshot(for: newReference)
      let reminderIdentifier = remoteSnapshot?.identifier ?? createdMetadata.identifier
      let reminderExternalIdentifier =
        normalized(remoteSnapshot?.externalIdentifier) ?? createdExternalIdentifier
      let title = remoteSnapshot?.title ?? task.title
      let noteText = remoteSnapshot?.noteText ?? task.noteText
      let storedDueDate = remoteSnapshot?.dueDate ?? dueDate
      let storedHasExplicitTime = remoteSnapshot?.hasExplicitTime ?? hasExplicitTime
      let recurrenceRuleRaw = remoteSnapshot?.recurrenceRuleRaw ?? task.recurrenceRuleRaw
      let storedModifiedAt = remoteSnapshot?.modifiedAt ?? modifiedAt

      try await store.upsertTask(
        projectID: project.projectID,
        taskID: task.taskID,
        reminderIdentifier: reminderIdentifier,
        reminderExternalIdentifier: reminderExternalIdentifier,
        title: title,
        noteText: noteText,
        isCompleted: false,
        completionDate: nil,
        dueDate: storedDueDate,
        hasExplicitTime: storedHasExplicitTime,
        durationMinutes: storedHasExplicitTime ? durationMinutes : nil,
        recurrenceRuleRaw: recurrenceRuleRaw,
        priority: remoteSnapshot?.priority ?? task.priority,
        modifiedAt: storedModifiedAt,
        appendIfMissing: false
      )
      try await store.deleteLocalCompletedRecurringOccurrence(
        projectID: project.projectID,
        baseExternalIdentifier: task.reminderExternalIdentifier,
        dueDate: dueDate,
        hasExplicitTime: hasExplicitTime
      )
      if let oldExternalIdentifier = normalized(task.reminderExternalIdentifier),
        oldExternalIdentifier != reminderExternalIdentifier
      {
        ReminderSyncBaselineStore.remove(reminderExternalIdentifier: oldExternalIdentifier)
      }
      updateBaseline(
        reminderExternalIdentifier: reminderExternalIdentifier,
        title: title,
        isCompleted: false,
        noteText: noteText,
        dueDate: storedDueDate,
        hasExplicitTime: storedHasExplicitTime,
        recurrenceRuleRaw: recurrenceRuleRaw,
        remoteModifiedAt: storedModifiedAt
      )
      TaskIdentityBridgeStore.upsertTask(
        taskID: task.taskID,
        title: title,
        reminderExternalIdentifier: reminderExternalIdentifier,
        ownerProjectID: project.projectID
      )
      return commandResult(projectID: project.projectID, taskID: task.taskID)
    } catch {
      if !didRemoveOldReminder {
        _ = try? reminderProjectProvider.removeTaskReminder(for: newReference)
      }
      throw error
    }
  }

  static func deleteTask(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    taskID: UUID,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskDeletionResult {
    let task = try await store.taskReference(projectID: projectID, taskID: taskID)
    let didRemoveReminder = try reminderProjectProvider.removeTaskReminder(for: reminderReference(task))
    if !didRemoveReminder {
      AppLogger.sync.info(
        "deleteTask continuing after missing reminder for task \(taskID.uuidString, privacy: .public)"
      )
    }
    try await store.deleteTask(taskID: taskID)
    if let reminderExternalIdentifier = task.reminderExternalIdentifier {
      ReminderSyncBaselineStore.remove(reminderExternalIdentifier: reminderExternalIdentifier)
    }
    TaskIdentityBridgeStore.removeTask(taskID: taskID)
    return RetainedTaskDeletionResult(
      projectID: projectID,
      taskID: taskID,
      reminderExternalIdentifier: task.reminderExternalIdentifier ?? task.reminderIdentifier
    )
  }

  static func moveTask(
    store: AppOwnedWorkspaceStore,
    taskID: UUID,
    sourceProjectID: UUID,
    targetProjectID: UUID,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let targetProject = try await store.projectReference(projectID: targetProjectID)
    let task = try await store.taskReference(projectID: sourceProjectID, taskID: taskID)
    guard try reminderProjectProvider.moveTaskReminder(
      for: reminderReference(task),
      toProject: targetProject.reminderListIdentifier
    ) != nil else {
      throw RetainedTaskCommandError.reminderOwnerUnresolved(taskID)
    }
    try await store.moveTask(taskID: taskID, toProjectID: targetProjectID)
    TaskIdentityBridgeStore.upsertTask(
      taskID: taskID,
      title: task.title,
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      ownerProjectID: targetProjectID
    )
    return commandResult(projectID: targetProjectID, taskID: taskID)
  }

  private static func commandResult(projectID: UUID, taskID: UUID) -> RetainedTaskCommandResult {
    RetainedTaskCommandResult(
      projectID: projectID,
      taskID: taskID,
      calendarBridgeDecision: .noAction,
      calendarWriteMarker: nil
    )
  }

  private static func reminderReference(
    _ task: AppOwnedWorkspaceStore.TaskReference
  ) -> ReminderTaskReference {
    ReminderTaskReference(
      taskID: task.taskID,
      reminderIdentifier: task.reminderIdentifier,
      reminderExternalIdentifier: task.reminderExternalIdentifier
    )
  }

  private static func updateBaseline(
    reminderExternalIdentifier: String?,
    title: String,
    isCompleted: Bool,
    noteText: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    recurrenceRuleRaw: String?,
    remoteModifiedAt: Date?
  ) {
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: reminderExternalIdentifier,
      state: ReminderSyncTaskState(
        title: title,
        isCompleted: isCompleted,
        date: ReminderScheduleMetadataCodec.encodeDate(dueDate, hasExplicitTime: hasExplicitTime),
        repeatRule: ReminderScheduleMetadataCodec.encodeRepeat(recurrenceRuleRaw),
        noteText: noteText
      ),
      remoteModifiedAt: remoteModifiedAt
    )
  }

  private static func matchesScheduleDate(
    _ task: AppOwnedWorkspaceStore.TaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) -> Bool {
    ReminderScheduleMetadataCodec.encodeDate(
      task.dueDate,
      hasExplicitTime: task.hasExplicitTime
    ) == ReminderScheduleMetadataCodec.encodeDate(
      dueDate,
      hasExplicitTime: hasExplicitTime
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

  private static func minutesSinceStartOfDay(for date: Date, calendar: Calendar) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
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
