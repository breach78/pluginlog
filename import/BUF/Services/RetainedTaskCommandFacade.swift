import Foundation

@MainActor
enum RetainedTaskCommandFacade {
  private static let mutationGate = RetainedTaskCommandMutationGate()

  private static func appOwnedStore(vaultRootURL: URL?) async throws -> AppOwnedWorkspaceStore {
    if let store = try await AppOwnedRetainedTaskCommandService.enabledStore(vaultRootURL: vaultRootURL) {
      return store
    }
    throw RetainedTaskCommandError.retainedProjectionFailed(
      "app-owned workspace storage is unavailable"
    )
  }

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
    let lease = await mutationLease(projectID: projectID)
    defer { releaseMutationLease(lease) }
    let store = try await appOwnedStore(vaultRootURL: vaultRootURL)

    return try await AppOwnedRetainedTaskCommandService.createTask(
      store: store,
      projectID: projectID,
      title: rawTitle,
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes,
      calendar: calendar,
      reminderProjectProvider: reminderProjectProvider
    )
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
    let store = try await appOwnedStore(vaultRootURL: vaultRootURL)

    return try await AppOwnedRetainedTaskCommandService.setTaskCompletion(
      store: store,
      projectID: projectID,
      taskID: taskID,
      isCompleted: isCompleted,
      completionDate: completionDate,
      reminderProjectProvider: reminderProjectProvider
    )
  }

  static func setTaskSchedule(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    calendar: Calendar = .autoupdatingCurrent,
    reminderProjectProvider: ReminderProjectProvider,
    resetRecurringAnchor: Bool = false
  ) async throws -> RetainedTaskCommandResult {
    let lease = await mutationLease(projectID: projectID, taskID: taskID)
    defer { releaseMutationLease(lease) }
    let store = try await appOwnedStore(vaultRootURL: vaultRootURL)

    return try await AppOwnedRetainedTaskCommandService.setTaskSchedule(
      store: store,
      projectID: projectID,
      taskID: taskID,
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes,
      calendar: calendar,
      reminderProjectProvider: reminderProjectProvider,
      resetRecurringAnchor: resetRecurringAnchor
    )
  }

  static func deleteTask(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskDeletionResult {
    let lease = await mutationLease(projectID: projectID, taskID: taskID)
    defer { releaseMutationLease(lease) }
    let store = try await appOwnedStore(vaultRootURL: vaultRootURL)

    return try await AppOwnedRetainedTaskCommandService.deleteTask(
      store: store,
      projectID: projectID,
      taskID: taskID,
      reminderProjectProvider: reminderProjectProvider
    )
  }

  static func moveTask(
    vaultRootURL: URL?,
    taskID: UUID,
    sourceProjectID: UUID,
    targetProjectID: UUID,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws -> RetainedTaskCommandResult {
    let lease = await mutationLease(
      sourceProjectID: sourceProjectID,
      targetProjectID: targetProjectID,
      taskID: taskID
    )
    defer { releaseMutationLease(lease) }
    let store = try await appOwnedStore(vaultRootURL: vaultRootURL)

    return try await AppOwnedRetainedTaskCommandService.moveTask(
      store: store,
      taskID: taskID,
      sourceProjectID: sourceProjectID,
      targetProjectID: targetProjectID,
      reminderProjectProvider: reminderProjectProvider
    )
  }

  static func taskEditFields(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    calendar: Calendar = .autoupdatingCurrent
  ) async throws -> RetainedTaskEditFields {
    let store = try await appOwnedStore(vaultRootURL: vaultRootURL)
    return try await AppOwnedRetainedTaskCommandService.taskEditFields(
      store: store,
      projectID: projectID,
      taskID: taskID,
      calendar: calendar
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
    let lease = await mutationLease(projectID: projectID, taskID: taskID)
    defer { releaseMutationLease(lease) }
    let store = try await appOwnedStore(vaultRootURL: vaultRootURL)

    return try await AppOwnedRetainedTaskCommandService.updateTaskEditFields(
      store: store,
      projectID: projectID,
      taskID: taskID,
      fields: rawFields,
      calendar: calendar,
      reminderProjectProvider: reminderProjectProvider
    )
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
}
