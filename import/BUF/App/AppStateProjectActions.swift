import Foundation
import SwiftData

@MainActor
extension AppState {
  func resolvedOwnerProjectID(forTaskID taskID: UUID, context: ModelContext) -> UUID? {
    _ = context
    return TaskIdentityBridgeStore.projectID(for: taskID)
  }

  func resolvedTaskRecord(forTaskID taskID: UUID, context: ModelContext) -> ProjectIdentityTaskRecord? {
    _ = context
    return TaskIdentityBridgeStore.taskRecord(for: taskID)
  }

  func resolvedProjectNoteMarkdown(forProjectID projectID: UUID, context: ModelContext) -> String? {
    _ = projectID
    _ = context
    return nil
  }

  func resolvedProjectProgressStage(forProjectID projectID: UUID) -> ProjectProgressStage {
    _ = projectID
    return .do
  }

  func resolvedProjectBoardOrder(forProjectID projectID: UUID) -> Int? {
    _ = projectID
    return nil
  }

  func resolvedProjectTitle(forProjectID projectID: UUID, context: ModelContext) -> String {
    _ = context
    return TaskIdentityBridgeStore.projectTitle(for: projectID) ?? "Project"
  }

  func resolvedWorkspaceProjectDescriptors(context: ModelContext) -> [WorkspaceProjectDescriptor] {
    _ = context
    return TaskIdentityBridgeStore.projectRecords().map { record in
      WorkspaceProjectDescriptor(
        id: record.projectID,
        title: record.title,
        colorHex: nil,
        reminderListIdentifier: record.reminderListExternalIdentifier ?? "",
        updatedAt: record.updatedAt,
        createdAt: record.createdAt,
        latestTaskUpdatedAt: nil,
        isArchived: false,
        stage: .do,
        workspaceSortKey: nil
      )
    }
  }

  func reminderProjectIDsInCurrentListOrder() async -> [UUID] {
    do {
      return try await reminderProjectProvider.fetchProjectListsInCurrentOrder().map { list in
        RetainedProjectionBuilder.derivedProjectID(for: list.externalIdentifier)
      }
    } catch {
      reportError(error, logMessage: "reminderProjectIDsInCurrentListOrder failed")
      return []
    }
  }

  func resolvedRuntimeProjectionProjectIDs() -> Set<UUID> {
    TaskIdentityBridgeStore.projectIDs()
  }

  @discardableResult
  func recomputeCachedRuntimeProjectionProjects(_ projectIDs: Set<UUID>) async -> Bool {
    _ = projectIDs
    bumpWorkspaceTreeRevision()
    return true
  }

  func isActiveProjectIdentity(_ projectID: UUID, context: ModelContext) -> Bool {
    _ = context
    return TaskIdentityBridgeStore.projectTitle(for: projectID) != nil
  }

  func invalidateWorkspaceProjectCache(for identifier: UUID) async {
    _ = identifier
    bumpWorkspaceTreeRevision()
  }

  func invalidateWorkspaceProjectCaches(for identifiers: Set<UUID>) async {
    _ = identifiers
    bumpWorkspaceTreeRevision()
  }

  @discardableResult
  func createProjectList(named rawTitle: String, context: ModelContext) async -> UUID? {
    _ = context
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    guard let obsidianVaultRootURL else {
      errorMessage = "Vault path is not configured."
      return nil
    }

    do {
      let store = AppOwnedWorkspaceStore.storeForVaultRootURL(obsidianVaultRootURL)
      let reminderList = try reminderProjectProvider.createProjectList(title: title)
      let projectID = RetainedProjectionBuilder.derivedProjectID(
        for: reminderList.externalIdentifier
      )
      do {
        try await store.upsertProject(
          projectID: projectID,
          reminderListIdentifier: reminderList.identifier,
          reminderListExternalIdentifier: reminderList.externalIdentifier,
          title: reminderList.title,
          colorHex: reminderList.colorHex,
          modifiedAt: .now
        )
        try await store.setProjectionReadEnabled(true)
      } catch {
        try? reminderProjectProvider.removeProjectList(identifier: reminderList.identifier)
        throw error
      }
      TaskIdentityBridgeStore.upsertProject(
        projectID: projectID,
        title: title,
        reminderListExternalIdentifier: reminderList.externalIdentifier
      )
      bumpWorkspaceTreeRevision()
      return projectID
    } catch {
      reportError(error, logMessage: "createProjectList failed")
      return nil
    }
  }

  @discardableResult
  func createTask(
    inProjectID projectID: UUID,
    title rawTitle: String,
    startDate: Date? = nil,
    durationMinutes: Int? = nil,
    context: ModelContext
  ) async -> UUID? {
    _ = context
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    guard let obsidianVaultRootURL else {
      errorMessage = "Vault path is not configured."
      return nil
    }

    do {
      guard let store = try await AppOwnedRetainedTaskCommandService.enabledStore(
        vaultRootURL: obsidianVaultRootURL
      ) else {
        errorMessage = "App-owned workspace storage is not ready."
        return nil
      }
      let calendar = Calendar.autoupdatingCurrent
      let day = startDate.map { calendar.startOfDay(for: $0) }
      let timeMinutes = startDate.flatMap { date -> Int? in
        let startOfDay = calendar.startOfDay(for: date)
        guard date != startOfDay else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
      }
      let result = try await AppOwnedRetainedTaskCommandService.createTask(
        store: store,
        projectID: projectID,
        title: title,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes,
        calendar: calendar,
        reminderProjectProvider: reminderProjectProvider
      )
      bumpWorkspaceTreeRevision()
      return result.taskID
    } catch {
      reportError(error, logMessage: "createTask failed")
      return nil
    }
  }

  @discardableResult
  func saveProjectDetailTaskCompletion(
    taskID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    context: ModelContext,
    restoreScheduleFields: RetainedTaskEditFields? = nil,
    currentIsCompleted: Bool? = nil,
    currentScheduleFields: RetainedTaskEditFields? = nil,
    isRecurring: Bool = false,
    calendar: Calendar = .autoupdatingCurrent
  ) async -> Bool {
    _ = context
    guard let projectID = TaskIdentityBridgeStore.projectID(for: taskID) else { return false }
    do {
      let previousIsCompleted = currentIsCompleted ?? !isCompleted
      let targetScheduleFields = restoreScheduleFields ?? currentScheduleFields
      let shouldRestoreSchedule =
        restoreScheduleFields.map { fields in
          RecurringCompletionUndoScheduleRestorePolicy.shouldRestore(
            previousIsCompleted: previousIsCompleted,
            nextIsCompleted: isCompleted,
            isRecurring: isRecurring,
            previousFields: currentScheduleFields,
            fields: fields
          )
        } ?? false
      let shouldWriteCompletion =
        targetScheduleFields.map {
          RecurringCompletionUndoScheduleRestorePolicy.shouldWriteCompletion(
            previousIsCompleted: previousIsCompleted,
            nextIsCompleted: isCompleted,
            isRecurring: isRecurring,
            previousFields: currentScheduleFields,
            fields: $0
          )
        } ?? (previousIsCompleted != isCompleted)
      if shouldWriteCompletion {
        _ = try await RetainedTaskCommandFacade.setTaskCompletion(
          vaultRootURL: obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          isCompleted: isCompleted,
          completionDate: completionDate,
          reminderProjectProvider: reminderProjectProvider
        )
      }
      if let fields = restoreScheduleFields,
        shouldRestoreSchedule
      {
        _ = try await RetainedTaskCommandFacade.setTaskSchedule(
          vaultRootURL: obsidianVaultRootURL,
          projectID: projectID,
          taskID: taskID,
          day: fields.day,
          timeMinutes: fields.timeMinutes,
          durationMinutes: fields.durationMinutes,
          calendar: calendar,
          reminderProjectProvider: reminderProjectProvider,
          resetRecurringAnchor: isRecurring
        )
      }
      bumpWorkspaceTreeRevision()
      return true
    } catch {
      reportError(error, logMessage: "saveProjectDetailTaskCompletion failed")
      return false
    }
  }

  @discardableResult
  func saveProjectDetailTaskPlannedWorkProgress(
    taskID: UUID,
    completedWorkUnits: Int,
    completedWorkUnitDatesRaw: String,
    context: ModelContext
  ) async -> Bool {
    _ = taskID
    _ = completedWorkUnits
    _ = completedWorkUnitDatesRaw
    _ = context
    errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "planned-work-progress")
    return false
  }

  @discardableResult
  func writeProjectDetailTaskSchedule(
    taskID: UUID,
    projectID: UUID,
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?,
    context: ModelContext
  ) async -> Bool {
    _ = context
    do {
      _ = try await RetainedTaskCommandFacade.setTaskSchedule(
        vaultRootURL: obsidianVaultRootURL,
        projectID: projectID,
        taskID: taskID,
        day: day,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes,
        reminderProjectProvider: reminderProjectProvider
      )
      bumpWorkspaceTreeRevision()
      return true
    } catch {
      reportError(error, logMessage: "writeProjectDetailTaskSchedule failed")
      return false
    }
  }

  @discardableResult
  func renameProject(_ projectID: UUID, to rawTitle: String, context: ModelContext) async -> Bool {
    _ = context
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return false }
    let previousRecord = TaskIdentityBridgeStore.projectRecord(for: projectID)
    do {
      guard let store = try await AppOwnedRetainedTaskCommandService.enabledStore(
        vaultRootURL: obsidianVaultRootURL
      ) else {
        errorMessage = "App-owned workspace storage is not ready."
        return false
      }
      let updatedSnapshot = try await AppOwnedRetainedProjectCommandService.setProjectTitle(
        store: store,
        projectID: projectID,
        title: title,
        reminderProjectProvider: reminderProjectProvider
      )
      let reminderListExternalIdentifier = updatedSnapshot.reminderListExternalIdentifier
        ?? previousRecord?.reminderListExternalIdentifier
      TaskIdentityBridgeStore.upsertProject(
        projectID: projectID,
        title: title,
        reminderListExternalIdentifier: reminderListExternalIdentifier
      )
      syncStatus = "Renamed project"
      bumpWorkspaceTreeRevision()
      return true
    } catch {
      reportError(error, logMessage: "renameProject failed")
      return false
    }
  }

  @discardableResult
  func updateProjectColor(_ projectID: UUID, to colorHex: String?, context: ModelContext) async -> Bool {
    _ = projectID
    _ = colorHex
    _ = context
    return false
  }

  @discardableResult
  func writeWorkspaceProjectOrder(_ orderedProjectIDs: [UUID]) async -> Bool {
    _ = orderedProjectIDs
    errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "project-ordering")
    return false
  }

  @discardableResult
  func writeProjectBucketOrder(projectIDsInOrder: [UUID]) async -> Bool {
    _ = projectIDsInOrder
    return false
  }

  @discardableResult
  func writeProjectBoardOrders(_ boardOrdersByProjectID: [UUID: Int?]) async -> Bool {
    guard !boardOrdersByProjectID.isEmpty else { return true }
    do {
      guard let store = try await AppOwnedRetainedTaskCommandService.enabledStore(
        vaultRootURL: obsidianVaultRootURL
      ) else {
        return false
      }
      try await store.updateProjectBoardOrders(boardOrdersByProjectID)
      bumpWorkspaceTreeRevision()
      let nextRevision =
        UserDefaults.standard.integer(forKey: ProjectProgressStage.boardOrderRevisionStorageKey) + 1
      UserDefaults.standard.set(
        nextRevision,
        forKey: ProjectProgressStage.boardOrderRevisionStorageKey
      )
      return true
    } catch {
      reportError(error, logMessage: "writeProjectBoardOrders failed")
      return false
    }
  }

  @discardableResult
  func deleteProjectPermanently(_ projectID: UUID, context: ModelContext) async -> Bool {
    _ = context
    do {
      guard let store = try await AppOwnedRetainedTaskCommandService.enabledStore(
        vaultRootURL: obsidianVaultRootURL
      ) else {
        errorMessage = "App-owned workspace storage is not ready."
        return false
      }
      let project = try await store.projectReference(projectID: projectID)
      try reminderProjectProvider.removeProjectList(identifier: project.reminderListIdentifier)
      try await store.deleteProject(projectID: projectID)
      TaskIdentityBridgeStore.removeProjects(projectIDs: [projectID])
      if selectedProjectID == projectID {
        selectedProjectID = nil
      }
      syncStatus = "Deleted project"
      bumpWorkspaceTreeRevision()
      return true
    } catch {
      reportError(error, logMessage: "deleteProjectPermanently failed")
      return false
    }
  }

  func deleteTaskPermanently(_ taskID: UUID, context: ModelContext) async {
    _ = taskID
    _ = context
    errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "task-delete")
  }

  @discardableResult
  func archiveProject(_ id: UUID, context: ModelContext) async -> Bool {
    _ = id
    _ = context
    errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "archive")
    return false
  }
}
