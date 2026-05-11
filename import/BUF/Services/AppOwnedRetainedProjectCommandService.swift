import Foundation

struct AppOwnedProjectSnapshot: Equatable {
  let projectID: UUID
  let reminderListExternalIdentifier: String?
  let title: String
  let noteMarkdown: String
  let colorHex: String?
  let progressStage: ProjectProgressStage
  let localStartDate: Date?
  let localDeadline: Date?
  let isArchived: Bool
  let updatedAt: Date
}

@MainActor
enum AppOwnedRetainedProjectCommandService {
  static func setProjectTitle(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    title rawTitle: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> AppOwnedProjectSnapshot {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw RetainedTaskCommandError.retainedProjectionFailed("empty project title")
    }
    let project = try await store.projectReference(projectID: projectID)
    let remote = try reminderProjectProvider.setProjectTitle(
      identifier: project.reminderListIdentifier,
      title: title
    )
    let resolvedTitle = normalized(remote?.title) ?? title
    try await store.updateProjectTitle(projectID: projectID, title: resolvedTitle, modifiedAt: .now)
    TaskIdentityBridgeStore.upsertProject(
      projectID: projectID,
      title: resolvedTitle,
      reminderListExternalIdentifier: project.reminderListExternalIdentifier ?? project.reminderListIdentifier
    )
    return try await projectSnapshot(
      store: store,
      projectID: projectID
    )
  }

  static func setProjectStage(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    stage: ProjectProgressStage
  ) async throws -> AppOwnedProjectSnapshot {
    try await store.updateProjectStage(projectID: projectID, stage: stage, modifiedAt: .now)
    return try await projectSnapshot(
      store: store,
      projectID: projectID
    )
  }

  static func setProjectNote(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    noteText: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> String {
    let normalizedNoteText = ReminderNoteSourceCodec.normalize(noteText)
    let project = try await store.projectReference(projectID: projectID)

    if let existingTask = try await store.projectNoteTaskReference(projectID: projectID),
      try await updateExistingProjectNoteIfStillBound(
        existingTask,
        noteText: normalizedNoteText,
        store: store,
        reminderProjectProvider: reminderProjectProvider
      )
    {
      return normalizedNoteText
    }

    guard !normalizedNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return normalizedNoteText
    }

    return try await createProjectNoteReminder(
      project: project,
      noteText: normalizedNoteText,
      store: store,
      reminderProjectProvider: reminderProjectProvider
    )
  }

  static func setProjectColor(
    store: AppOwnedWorkspaceStore,
    projectID: UUID,
    colorHex: String?,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> AppOwnedProjectSnapshot {
    let project = try await store.projectReference(projectID: projectID)
    let remote = try reminderProjectProvider.setProjectColor(
      identifier: project.reminderListIdentifier,
      colorHex: colorHex
    )
    let resolvedColor = normalized(remote?.colorHex) ?? normalized(colorHex)
    try await store.updateProjectColor(projectID: projectID, colorHex: resolvedColor, modifiedAt: .now)
    return try await projectSnapshot(
      store: store,
      projectID: projectID
    )
  }

  private static func updateExistingProjectNoteIfStillBound(
    _ task: AppOwnedWorkspaceStore.TaskReference,
    noteText: String,
    store: AppOwnedWorkspaceStore,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> Bool {
    let reference = reminderReference(task)
    guard let snapshot = try reminderProjectProvider.taskSnapshot(for: reference) else {
      try await store.deleteTask(taskID: task.taskID)
      return false
    }
    guard ProjectNoteReminderPolicy.isProjectNoteReminder(
      title: snapshot.title,
      priority: snapshot.priority
    ) else {
      try await store.upsertTask(
        projectID: task.projectID,
        taskID: task.taskID,
        reminderIdentifier: snapshot.identifier,
        reminderExternalIdentifier: normalized(snapshot.externalIdentifier)
          ?? task.reminderExternalIdentifier,
        title: snapshot.title,
        noteText: snapshot.noteText,
        isCompleted: snapshot.isCompleted,
        completionDate: snapshot.completionDate,
        dueDate: snapshot.dueDate,
        hasExplicitTime: snapshot.hasExplicitTime,
        durationMinutes: nil,
        recurrenceRuleRaw: snapshot.recurrenceRuleRaw,
        priority: snapshot.priority,
        modifiedAt: snapshot.modifiedAt,
        appendIfMissing: false
      )
      TaskIdentityBridgeStore.upsertTask(
        taskID: task.taskID,
        title: snapshot.title,
        reminderExternalIdentifier: normalized(snapshot.externalIdentifier)
          ?? task.reminderExternalIdentifier,
        ownerProjectID: task.projectID
      )
      return false
    }

    let modifiedAt: Date
    if snapshot.noteText != noteText {
      modifiedAt = try reminderProjectProvider.setTaskReminderNote(
        for: reference,
        noteText: noteText
      )?.modifiedAt ?? .now
    } else {
      modifiedAt = snapshot.modifiedAt
    }

    try await store.upsertTask(
      projectID: task.projectID,
      taskID: task.taskID,
      reminderIdentifier: snapshot.identifier,
      reminderExternalIdentifier: normalized(snapshot.externalIdentifier)
        ?? task.reminderExternalIdentifier,
      title: ProjectNoteReminderPolicy.title,
      noteText: noteText,
      isCompleted: snapshot.isCompleted,
      completionDate: snapshot.completionDate,
      dueDate: snapshot.dueDate,
      hasExplicitTime: snapshot.hasExplicitTime,
      durationMinutes: nil,
      recurrenceRuleRaw: snapshot.recurrenceRuleRaw,
      priority: ProjectNoteReminderPolicy.lowPriority,
      modifiedAt: modifiedAt,
      appendIfMissing: false
    )
    return true
  }

  private static func createProjectNoteReminder(
    project: AppOwnedWorkspaceStore.ProjectReference,
    noteText: String,
    store: AppOwnedWorkspaceStore,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> String {
    guard let metadata = try reminderProjectProvider.createTaskReminder(
      inProject: project.reminderListIdentifier,
      title: ProjectNoteReminderPolicy.title,
      dueDate: nil,
      hasExplicitTime: false,
      noteText: noteText
    ), let externalIdentifier = normalized(metadata.externalIdentifier) else {
      throw RetainedTaskCommandError.retainedProjectionFailed(
        "created project note reminder missing external id"
      )
    }

    let taskID = ReminderProjectionIdentity.taskID(for: externalIdentifier)
    let reference = ReminderTaskReference(
      taskID: taskID,
      reminderIdentifier: metadata.identifier,
      reminderExternalIdentifier: externalIdentifier
    )
    do {
      let presentationMetadata = try reminderProjectProvider.setTaskPresentation(
        for: reference,
        priority: ProjectNoteReminderPolicy.lowPriority
      )
      try await store.upsertTask(
        projectID: project.projectID,
        taskID: taskID,
        reminderIdentifier: metadata.identifier,
        reminderExternalIdentifier: externalIdentifier,
        title: ProjectNoteReminderPolicy.title,
        noteText: noteText,
        isCompleted: false,
        completionDate: nil,
        dueDate: nil,
        hasExplicitTime: false,
        durationMinutes: nil,
        recurrenceRuleRaw: nil,
        priority: ProjectNoteReminderPolicy.lowPriority,
        modifiedAt: presentationMetadata?.modifiedAt ?? metadata.modifiedAt
      )
      return noteText
    } catch {
      _ = try? reminderProjectProvider.removeTaskReminder(for: reference)
      throw error
    }
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

  private static func projectSnapshot(
    store: AppOwnedWorkspaceStore,
    projectID: UUID
  ) async throws -> AppOwnedProjectSnapshot {
    let workspace = try await store.loadRetainedWorkspaceSnapshot(projectIDs: [projectID])
    guard let project = workspace.projects.first(where: { $0.identity.projectID == projectID }) else {
      throw RetainedTaskCommandError.projectNotFound(projectID)
    }
    return AppOwnedProjectSnapshot(
      projectID: project.identity.projectID,
      reminderListExternalIdentifier: project.identity.reminderListExternalIdentifier,
      title: project.title,
      noteMarkdown: project.noteMarkdown,
      colorHex: project.colorHex,
      progressStage: project.progressStage,
      localStartDate: project.localStartDate,
      localDeadline: project.localDeadline,
      isArchived: project.isArchived,
      updatedAt: project.updatedAt
    )
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
