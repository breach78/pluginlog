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
    guard let pageStore = logseqProjectPageStore() else {
      errorMessage = "Logseq graph is not configured."
      return nil
    }

    do {
      let reminderList = try reminderProjectProvider.createProjectList(title: title)
      let projectID = RetainedProjectionBuilder.derivedProjectID(
        for: reminderList.externalIdentifier
      )
      try await pageStore.upsertPage(
        .init(
          projectID: projectID,
          title: title,
          reminderListExternalIdentifier: reminderList.externalIdentifier
        ),
        noteMarkdown: "",
        managedTasks: []
      )
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
    guard let pageStore = logseqProjectPageStore() else {
      errorMessage = "Logseq graph is not configured."
      return nil
    }

    do {
      let pages = try await pageStore.loadProjectPagesInScope()
      guard let page = pages.first(where: { $0.projectID == projectID }),
        let reminderListIdentifier = page.reminderListExternalIdentifier
      else {
        errorMessage = "할일을 추가할 Logseq 프로젝트 페이지를 찾지 못했습니다."
        return nil
      }

      let hasExplicitTime = startDate != nil && Calendar.autoupdatingCurrent.component(.hour, from: startDate!) != 0
      let remote = try reminderProjectProvider.createTaskReminder(
        inProject: reminderListIdentifier,
        title: title,
        dueDate: startDate,
        hasExplicitTime: hasExplicitTime,
        noteText: ""
      )
      let taskID = UUID()
      var tasks = page.managedTasks
      tasks.append(
        .init(
          taskID: taskID,
          title: title,
          isCompleted: false,
          date: LogseqReminderPropertyCodec.encodeDate(startDate, hasExplicitTime: hasExplicitTime),
          duration: durationMinutes.map(String.init),
          repeatRule: nil,
          reminderExternalIdentifier: remote?.externalIdentifier,
          calendarEventExternalIdentifier: nil
        )
      )
      try await pageStore.upsertPage(
        .init(
          projectID: projectID,
          title: page.title,
          reminderListExternalIdentifier: page.reminderListExternalIdentifier
        ),
        noteMarkdown: page.noteMarkdown,
        managedTasks: tasks
      )
      TaskIdentityBridgeStore.upsertTask(
        taskID: taskID,
        title: title,
        reminderExternalIdentifier: remote?.externalIdentifier,
        ownerProjectID: projectID
      )
      bumpWorkspaceTreeRevision()
      return taskID
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
    context: ModelContext
  ) async -> Bool {
    _ = context
    guard let projectID = TaskIdentityBridgeStore.projectID(for: taskID) else { return false }
    do {
      _ = try await RetainedTaskCommandService.setTaskCompletion(
        graphRootURL: logseqGraphRootURL,
        projectID: projectID,
        taskID: taskID,
        isCompleted: isCompleted,
        completionDate: completionDate,
        reminderProjectProvider: reminderProjectProvider
      )
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
      _ = try await RetainedTaskCommandService.setTaskSchedule(
        graphRootURL: logseqGraphRootURL,
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
    _ = boardOrdersByProjectID
    return false
  }

  @discardableResult
  func deleteProjectPermanently(_ projectID: UUID, context: ModelContext) async -> Bool {
    _ = projectID
    _ = context
    errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "project-delete")
    return false
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
