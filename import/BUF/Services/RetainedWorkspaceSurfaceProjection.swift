import Foundation

struct RetainedWorkspaceSurfaceProjection: Equatable {
  let projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord]
  let projectSummaries: [UUID: ProjectSummaryRecord]
  let scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  let calendarBridgeDecisionsByTaskID: [UUID: RetainedCalendarBridgeDecision]

  static let empty = RetainedWorkspaceSurfaceProjection(
    projectSnapshots: [:],
    projectSummaries: [:],
    scheduleEntriesByProjectID: [:],
    calendarBridgeDecisionsByTaskID: [:]
  )
}

enum RetainedWorkspaceSurfaceProjectionMergePolicy {
  static func merge(
    existing: RetainedWorkspaceSurfaceProjection,
    loaded: RetainedWorkspaceSurfaceProjection,
    replacingProjectIDs: Set<UUID>
  ) -> RetainedWorkspaceSurfaceProjection {
    let staleTaskIDs = taskIDs(
      in: existing.scheduleEntriesByProjectID,
      projectIDs: replacingProjectIDs
    )
    var calendarBridgeDecisionsByTaskID = existing.calendarBridgeDecisionsByTaskID
    for taskID in staleTaskIDs {
      calendarBridgeDecisionsByTaskID.removeValue(forKey: taskID)
    }
    for (taskID, decision) in loaded.calendarBridgeDecisionsByTaskID {
      calendarBridgeDecisionsByTaskID[taskID] = decision
    }

    return RetainedWorkspaceSurfaceProjection(
      projectSnapshots: replacing(
        existing.projectSnapshots,
        with: loaded.projectSnapshots,
        for: replacingProjectIDs
      ),
      projectSummaries: replacing(
        existing.projectSummaries,
        with: loaded.projectSummaries,
        for: replacingProjectIDs
      ),
      scheduleEntriesByProjectID: replacing(
        existing.scheduleEntriesByProjectID,
        with: loaded.scheduleEntriesByProjectID,
        for: replacingProjectIDs
      ),
      calendarBridgeDecisionsByTaskID: calendarBridgeDecisionsByTaskID
    )
  }

  static func filteredWriteMarkers(
    existingMarkers: [UUID: RetainedCalendarBridgeWriteMarker],
    existing: RetainedWorkspaceSurfaceProjection,
    loaded: RetainedWorkspaceSurfaceProjection,
    replacingProjectIDs: Set<UUID>
  ) -> [UUID: RetainedCalendarBridgeWriteMarker] {
    let staleTaskIDs = taskIDs(
      in: existing.scheduleEntriesByProjectID,
      projectIDs: replacingProjectIDs
    )
    let mergedTaskIDs = Set(
      merge(
        existing: existing,
        loaded: loaded,
        replacingProjectIDs: replacingProjectIDs
      ).calendarBridgeDecisionsByTaskID.keys
    )
    return existingMarkers.filter { taskID, _ in
      !staleTaskIDs.contains(taskID) && mergedTaskIDs.contains(taskID)
    }
  }

  private static func replacing<Value>(
    _ existing: [UUID: Value],
    with loaded: [UUID: Value],
    for projectIDs: Set<UUID>
  ) -> [UUID: Value] {
    var result = existing
    for projectID in projectIDs {
      result.removeValue(forKey: projectID)
    }
    for (projectID, value) in loaded {
      result[projectID] = value
    }
    return result
  }

  private static func taskIDs(
    in scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]],
    projectIDs: Set<UUID>
  ) -> Set<UUID> {
    Set(projectIDs.flatMap { scheduleEntriesByProjectID[$0] ?? [] }.map(\.taskID))
  }
}

enum RetainedWorkspaceSurfaceProjectionBlocker: Equatable {
  case identityFailure(RetainedProjectionBuilder.Error)
  case partialProjectCoverage(missingProjectIDs: [UUID])
  case taskIdentityUnavailable(projectID: UUID, title: String)
  case obsidianVaultNotConfigured
  case loadFailed(String)

  var userMessage: String {
    switch self {
    case .identityFailure(let error):
      return error.localizedDescription
    case .partialProjectCoverage(let missingProjectIDs):
      return "Retained projection is missing \(missingProjectIDs.count) requested project(s)."
    case .taskIdentityUnavailable(_, let title):
      return "Retained task cannot be shown in Schedule/Timeline without a stable task id: \(title)"
    case .obsidianVaultNotConfigured:
      return "Obsidian vault is not configured for Schedule/Timeline retained projection."
    case .loadFailed(let message):
      return "Retained projection load failed: \(message)"
    }
  }

  var shouldPresentGlobalError: Bool {
    switch self {
    case .partialProjectCoverage, .taskIdentityUnavailable:
      return false
    case .identityFailure, .obsidianVaultNotConfigured, .loadFailed:
      return true
    }
  }
}

enum RetainedWorkspaceSurfaceProjectionLoadResult: Equatable {
  case loaded(RetainedWorkspaceSurfaceProjection)
  case blocked(RetainedWorkspaceSurfaceProjectionBlocker)
}

struct RetainedWorkspaceSurfaceProjectionResolvedRead: Equatable {
  enum Source: Equatable {
    case retained
    case blocked(RetainedWorkspaceSurfaceProjectionBlocker)
  }

  let projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord]
  let projectSummaries: [UUID: ProjectSummaryRecord]
  let scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  let calendarBridgeDecisionsByTaskID: [UUID: RetainedCalendarBridgeDecision]
  let source: Source

  var errorMessage: String? {
    guard case .blocked(let blocker) = source else { return nil }
    guard blocker.shouldPresentGlobalError else { return nil }
    return blocker.userMessage
  }
}

enum RetainedWorkspaceSurfaceProjectionBuilder {
  static func load(
    obsidianVaultRootURL: URL?,
    projectIDs: [UUID],
    calendar: Calendar = .autoupdatingCurrent
  ) async -> RetainedWorkspaceSurfaceProjectionLoadResult {
    guard let obsidianVaultRootURL else {
      return .blocked(.obsidianVaultNotConfigured)
    }

    let appStore = AppOwnedWorkspaceStore.storeForVaultRootURL(obsidianVaultRootURL)
    do {
      if try await appStore.isProjectionReadEnabled(),
        try await appStore.hasImportedWorkspace()
      {
        let snapshot = try await appStore.loadRetainedWorkspaceSnapshot(projectIDs: projectIDs)
        return build(snapshot: snapshot, projectIDs: projectIDs, calendar: calendar)
      }
    } catch {
      return .blocked(.loadFailed("App-owned store load failed: \(error.localizedDescription)"))
    }

    let store = ObsidianProjectMarkdownStore(vaultRootURL: obsidianVaultRootURL)
    do {
      let requestedProjectIDs = Set(projectIDs)
      let snapshots =
        requestedProjectIDs.isEmpty
        ? try await store.loadProjectNotesInScope()
        : try await store.loadProjectNotesInScope(matchingProjectIDs: requestedProjectIDs)
      let snapshot = try ObsidianRetainedProjectionAdapter.build(
        snapshots: snapshots,
        calendar: calendar
      )
      return build(snapshot: snapshot, projectIDs: projectIDs, calendar: calendar)
    } catch let error as RetainedProjectionBuilder.Error {
      return .blocked(.identityFailure(error))
    } catch {
      return .blocked(.loadFailed(error.localizedDescription))
    }
  }

  static func build(
    snapshot: RetainedWorkspaceSnapshot,
    projectIDs: [UUID],
    calendar: Calendar = .autoupdatingCurrent
  ) -> RetainedWorkspaceSurfaceProjectionLoadResult {
    if let blocker = validateSnapshotIdentities(snapshot) {
      return .blocked(blocker)
    }

    let normalizedProjectIDs = normalizedProjectIDs(projectIDs)
    let projectsByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map {
      ($0.identity.projectID, $0)
    })
    let missingProjectIDs = normalizedProjectIDs.filter { projectsByID[$0] == nil }
    guard missingProjectIDs.isEmpty else {
      return .blocked(.partialProjectCoverage(missingProjectIDs: missingProjectIDs))
    }

    let selectedProjects =
      normalizedProjectIDs.isEmpty
      ? snapshot.projects
      : normalizedProjectIDs.compactMap { projectsByID[$0] }

    var projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord] = [:]
    var projectSummaries: [UUID: ProjectSummaryRecord] = [:]
    var scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]] = [:]
    var calendarBridgeDecisionsByTaskID: [UUID: RetainedCalendarBridgeDecision] = [:]

    for project in selectedProjects {
      let projectID = project.identity.projectID
      let projectTasks = ProjectNoteReminderPolicy.visibleTasks(project.tasks)
      let projectNoteMarkdown = ProjectNoteReminderPolicy.projectNoteText(in: project.tasks)
        ?? project.noteMarkdown
      let projectSnapshot = workspaceProjectSnapshot(
        for: project,
        projectNoteMarkdown: projectNoteMarkdown
      )
      var scheduleEntries: [ScheduleSliceEntry] = []

      for (index, task) in projectTasks.enumerated() {
        guard let taskID = task.identity.taskID else {
          continue
        }

        let scheduleEntry = scheduleEntry(
          for: task,
          taskID: taskID,
          projectID: projectID,
          rowOrder: index,
          projectSnapshot: projectSnapshot
        )
        scheduleEntries.append(scheduleEntry)
        calendarBridgeDecisionsByTaskID[taskID] = RetainedCalendarBridgePolicy.decision(for: task)
      }

      projectSnapshots[projectID] = projectSnapshot
      scheduleEntriesByProjectID[projectID] = scheduleEntries
      projectSummaries[projectID] = projectSummary(
        from: scheduleEntries,
        projectSnapshot: projectSnapshot,
        calendar: calendar
      )
    }

    return .loaded(
      RetainedWorkspaceSurfaceProjection(
        projectSnapshots: projectSnapshots,
        projectSummaries: projectSummaries,
        scheduleEntriesByProjectID: scheduleEntriesByProjectID,
        calendarBridgeDecisionsByTaskID: calendarBridgeDecisionsByTaskID
      )
    )
  }

  static func resolveRetainedOnly(
    _ result: RetainedWorkspaceSurfaceProjectionLoadResult
  ) -> RetainedWorkspaceSurfaceProjectionResolvedRead {
    switch result {
    case .loaded(let projection):
      return RetainedWorkspaceSurfaceProjectionResolvedRead(
        projectSnapshots: projection.projectSnapshots,
        projectSummaries: projection.projectSummaries,
        scheduleEntriesByProjectID: projection.scheduleEntriesByProjectID,
        calendarBridgeDecisionsByTaskID: projection.calendarBridgeDecisionsByTaskID,
        source: .retained
      )
    case .blocked(let blocker):
      return blockedRead(blocker)
    }
  }

  static func shouldInvalidateConsumerCaches(
    for source: RetainedWorkspaceSurfaceProjectionResolvedRead.Source
  ) -> Bool {
    switch source {
    case .retained:
      return true
    case .blocked:
      return true
    }
  }

  private static func blockedRead(
    _ blocker: RetainedWorkspaceSurfaceProjectionBlocker
  ) -> RetainedWorkspaceSurfaceProjectionResolvedRead {
    RetainedWorkspaceSurfaceProjectionResolvedRead(
      projectSnapshots: [:],
      projectSummaries: [:],
      scheduleEntriesByProjectID: [:],
      calendarBridgeDecisionsByTaskID: [:],
      source: .blocked(blocker)
    )
  }

  private static func validateSnapshotIdentities(
    _ snapshot: RetainedWorkspaceSnapshot
  ) -> RetainedWorkspaceSurfaceProjectionBlocker? {
    var seenProjectIDs: Set<UUID> = []
    var seenReminderListExternalIdentifiers: Set<String> = []
    var seenTaskIDs: Set<UUID> = []
    var seenReminderExternalIdentifiers: Set<String> = []
    var seenCalendarEventExternalIdentifiers: Set<String> = []

    for project in snapshot.projects {
      let projectID = project.identity.projectID
      guard seenProjectIDs.insert(projectID).inserted else {
        return .identityFailure(.duplicateProjectID(projectID))
      }

      if let reminderListExternalIdentifier = normalized(project.identity.reminderListExternalIdentifier) {
        guard projectID == RetainedProjectionBuilder.derivedProjectID(
          for: reminderListExternalIdentifier
        ) else {
          return .identityFailure(.conflictingProjectIdentity(pageTitle: project.title))
        }
        guard seenReminderListExternalIdentifiers.insert(reminderListExternalIdentifier).inserted else {
          return .identityFailure(
            .duplicateReminderListExternalIdentifier(reminderListExternalIdentifier)
          )
        }
      }

      for task in project.tasks {
        let reminderExternalIdentifier = normalized(task.identity.reminderExternalIdentifier)
        let calendarEventExternalIdentifier = normalized(
          task.identity.calendarEventExternalIdentifier
        )

        guard let taskID = task.identity.taskID else {
          if reminderExternalIdentifier != nil || calendarEventExternalIdentifier != nil {
            return .identityFailure(
              .damagedTaskIdentity(projectTitle: project.title, taskTitle: task.title)
            )
          }
          continue
        }
        guard seenTaskIDs.insert(taskID).inserted else {
          return .identityFailure(.duplicateTaskID(taskID))
        }
        if let reminderExternalIdentifier {
          guard seenReminderExternalIdentifiers.insert(reminderExternalIdentifier).inserted else {
            return .identityFailure(.duplicateReminderExternalIdentifier(reminderExternalIdentifier))
          }
        }
        if let calendarEventExternalIdentifier {
          guard seenCalendarEventExternalIdentifiers.insert(calendarEventExternalIdentifier).inserted else {
            return .identityFailure(
              .duplicateCalendarEventExternalIdentifier(calendarEventExternalIdentifier)
            )
          }
        }
      }
    }

    return nil
  }

  private static func workspaceProjectSnapshot(
    for project: RetainedProject,
    projectNoteMarkdown: String
  ) -> WorkspaceProjectRuntimeRecord {
    WorkspaceProjectRuntimeRecord(
      id: project.identity.projectID,
      title: project.title,
      colorHex: project.colorHex,
      reminderListIdentifier: nil,
      reminderListExternalIdentifier: project.identity.reminderListExternalIdentifier,
      projectNoteMarkdown: projectNoteMarkdown,
      localStartDate: project.localStartDate,
      localDeadline: project.localDeadline,
      progressStageRaw: project.progressStage.storageRawValue,
      boardOrder: nil,
      createdAt: .distantPast,
      updatedAt: project.updatedAt,
      isArchived: project.isArchived
    )
  }

  private static func scheduleEntry(
    for task: RetainedTask,
    taskID: UUID,
    projectID: UUID,
    rowOrder: Int,
    projectSnapshot: WorkspaceProjectRuntimeRecord
  ) -> ScheduleSliceEntry {
    ScheduleSliceEntry(
      taskID: taskID,
      parentTaskID: nil,
      title: task.title,
      displayedDate: task.schedule.parsedDate,
      startDate: nil,
      dueDate: task.schedule.parsedDate,
      scheduleHasExplicitTime: task.schedule.hasExplicitTime,
      scheduledDurationMinutes: task.schedule.durationMinutes,
      isCompleted: task.isCompleted,
      completionDate: nil,
      recurrenceRuleRaw: task.schedule.canonicalRepeatRule,
      isLocalCompletedRecurringOccurrence: AppOwnedWorkspaceStore
        .isLocalCompletedRecurringExternalIdentifier(task.identity.reminderExternalIdentifier),
      attachmentCount: 0,
      hasReminderNoteContent: hasVisibleReminderNoteContent(task.noteText),
      reminderNoteText: task.noteText,
      requiredWorkDays: 0,
      completedWorkUnits: 0,
      completedWorkUnitDates: [],
      preparationScheduleOverridesRaw: "",
      rowOrder: rowOrder,
      priority: task.priority,
      isFlagged: false,
      isArchived: projectSnapshot.isArchived,
      localUpdatedAt: .distantPast,
      createdAt: .distantPast
    )
  }

  private static func hasVisibleReminderNoteContent(_ noteText: String) -> Bool {
    !TaskEditAttachmentService.noteTextByRemovingAttachmentLinks(from: noteText)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
  }

  private static func projectSummary(
    from scheduleEntries: [ScheduleSliceEntry],
    projectSnapshot: WorkspaceProjectRuntimeRecord,
    calendar: Calendar
  ) -> ProjectSummaryRecord {
    let today = calendar.startOfDay(for: .now)
    var openRootTaskCount = 0
    var completedRootTaskCount = 0
    var undatedOpenRootTaskCount = 0
    var overdueOpenRootTaskCount = 0
    var todayTaskCount = 0
    var upcomingDates: [Date] = []

    for task in scheduleEntries where task.parentTaskID == nil {
      if task.isCompleted {
        completedRootTaskCount += 1
        continue
      }

      openRootTaskCount += 1
      guard let dueDate = task.dueDate else {
        undatedOpenRootTaskCount += 1
        continue
      }

      let day = calendar.startOfDay(for: dueDate)
      if day < today {
        overdueOpenRootTaskCount += 1
      }
      if day == today {
        todayTaskCount += 1
      }
      if day >= today {
        upcomingDates.append(day)
      }
    }

    return ProjectSummaryRecord(
      openRootTaskCount: openRootTaskCount,
      completedRootTaskCount: completedRootTaskCount,
      undatedOpenRootTaskCount: undatedOpenRootTaskCount,
      overdueOpenRootTaskCount: overdueOpenRootTaskCount,
      todayTaskCount: todayTaskCount,
      nextUpcomingDate: upcomingDates.min(),
      deadline: projectSnapshot.localDeadline,
      stageRaw: projectSnapshot.progressStageRaw ?? ProjectProgressStage.do.storageRawValue,
      progress: ProjectProgressStage.fromStorageValue(projectSnapshot.progressStageRaw)?.progressValue
        ?? ProjectProgressStage.do.progressValue,
      latestTaskUpdatedAt: scheduleEntries.map(\.localUpdatedAt).max(),
      title: projectSnapshot.title,
      colorHex: projectSnapshot.colorHex,
      isArchived: projectSnapshot.isArchived
    )
  }

  private static func normalizedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    return projectIDs.filter { seen.insert($0).inserted }
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
