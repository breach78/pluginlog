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
    guard let obsidianVaultRootURL else {
      errorMessage = "Obsidian vault is not configured."
      return nil
    }

    do {
      let store = ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
      let preferredFileName = try await store.availableProjectFileName(preferredTitle: title)
      let reminderList = try reminderProjectProvider.createProjectList(title: title)
      let projectID = RetainedProjectionBuilder.derivedProjectID(
        for: reminderList.externalIdentifier
      )
      do {
        _ = try await store.writeProjectNote(
          ObsidianProjectNote(
            frontmatter: ObsidianProjectFrontmatter(
              tags: ["프로젝트"],
              reminderListExternalIdentifier: reminderList.externalIdentifier,
              colorHex: reminderList.colorHex,
              preservedLines: []
            ),
            bodyMarkdown: "",
            tasks: [],
            diagnostics: [],
            normalizedContentHash: ""
          ),
          preferredFileName: preferredFileName
        )
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
  func createProjectStub(context: ModelContext) async -> ObsidianProjectMarkdownStore.Snapshot? {
    _ = context
    guard let obsidianVaultRootURL else {
      errorMessage = "Obsidian vault is not configured."
      return nil
    }

    do {
      let snapshot = try await ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
        .createProjectStub()
      bumpWorkspaceTreeRevision()
      return snapshot
    } catch {
      reportError(error, logMessage: "createProjectStub failed")
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
      errorMessage = "Obsidian vault is not configured."
      return nil
    }

    do {
      let store = ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
      let snapshots = try await store.loadProjectNotesInScope()
      guard let snapshot = snapshots.first(where: { snapshot in
        guard let listID = snapshot.note.reminderListExternalIdentifier else { return false }
        return RetainedProjectionBuilder.derivedProjectID(for: listID) == projectID
      }),
        let reminderListIdentifier = snapshot.note.reminderListExternalIdentifier
      else {
        errorMessage = "할일을 추가할 Obsidian 프로젝트 노트를 찾지 못했습니다."
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
      guard let reminderExternalIdentifier = remote?.externalIdentifier else {
        errorMessage = "생성된 Reminder task external id를 확인하지 못했습니다."
        return nil
      }
      let taskID = ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
      let note = noteByAppendingTask(
        title: title,
        reminderExternalIdentifier: reminderExternalIdentifier,
        startDate: startDate,
        hasExplicitTime: hasExplicitTime,
        durationMinutes: durationMinutes,
        to: snapshot.note
      )
      _ = try await store.writeProjectNote(
        note,
        preferredFileName: snapshot.fileURL.lastPathComponent,
        expectedBaseline: ObsidianProjectMarkdownStore.WriteBaseline(snapshot: snapshot)
      )
      ReminderSyncBaselineStore.upsert(
        reminderExternalIdentifier: reminderExternalIdentifier,
        state: ReminderSyncTaskState(
          title: title,
          isCompleted: false,
          date: ReminderScheduleMetadataCodec.encodeDate(
            startDate,
            hasExplicitTime: hasExplicitTime
          ),
          repeatRule: nil,
          noteText: nil
        ),
        remoteModifiedAt: remote?.modifiedAt
      )
      TaskIdentityBridgeStore.upsertProject(
        projectID: projectID,
        title: snapshot.fileURL.deletingPathExtension().lastPathComponent,
        reminderListExternalIdentifier: reminderListIdentifier
      )
      TaskIdentityBridgeStore.upsertTask(
        taskID: taskID,
        title: title,
        reminderExternalIdentifier: reminderExternalIdentifier,
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
      _ = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
        vaultRootURL: obsidianVaultRootURL,
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
      _ = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
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

  private func noteByAppendingTask(
    title: String,
    reminderExternalIdentifier: String,
    startDate: Date?,
    hasExplicitTime: Bool,
    durationMinutes: Int?,
    to note: ObsidianProjectNote
  ) -> ObsidianProjectNote {
    var bodyLines = note.bodyMarkdown.isEmpty ? [] : note.bodyMarkdown.components(separatedBy: "\n")
    bodyLines.append("- [ ] \(title)")
    let metadata = ObsidianTaskMetadata(
      reminderExternalIdentifier: reminderExternalIdentifier,
      date: startDate.map { formatObsidianDate($0) },
      time: hasExplicitTime ? startDate.map { formatObsidianTime($0) } : nil,
      durationMinutes: durationMinutes,
      repeatRule: nil
    )
    bodyLines.append(
      ObsidianReminderImportFormatting.renderMetadataLine(metadata, indentation: "  ")
    )
    return ObsidianProjectNoteParser.parse(
      ObsidianProjectNoteRenderer.render(
        ObsidianProjectNote(
          frontmatter: note.frontmatter,
          bodyMarkdown: bodyLines.joined(separator: "\n"),
          tasks: [],
          diagnostics: [],
          normalizedContentHash: ""
        )
      )
    )
  }

  private func formatObsidianDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private func formatObsidianTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  @discardableResult
  func renameProject(_ projectID: UUID, to rawTitle: String, context: ModelContext) async -> Bool {
    _ = context
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return false }
    let previousRecord = TaskIdentityBridgeStore.projectRecord(for: projectID)
    do {
      let updatedSnapshot = try await ObsidianRetainedProjectCommandService.setProjectTitle(
        vaultRootURL: obsidianVaultRootURL,
        projectID: projectID,
        title: title,
        reminderProjectProvider: reminderProjectProvider
      )
      let reminderListExternalIdentifier = updatedSnapshot.note.reminderListExternalIdentifier
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
    _ = boardOrdersByProjectID
    return false
  }

  @discardableResult
  func deleteProjectPermanently(_ projectID: UUID, context: ModelContext) async -> Bool {
    _ = context
    do {
      let result = try await ObsidianProjectDeletionSync.deleteProject(
        vaultRootURL: obsidianVaultRootURL,
        projectID: projectID,
        reminderProjectProvider: reminderProjectProvider,
        now: .now
      )
      if selectedProjectID == result.deletedProjectID {
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
