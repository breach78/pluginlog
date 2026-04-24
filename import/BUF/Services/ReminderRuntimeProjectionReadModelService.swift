import Foundation
import SwiftData

struct ReminderWorkspaceSurfaceProjection {
  let projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord]
  let projectSummaries: [UUID: ProjectSummaryRecord]
  let scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
}

private struct ArchivedWorkspaceProjectSurfaceRecord {
  let id: UUID
  let title: String
  let colorHex: String?
  let reminderListIdentifier: String
  let reminderListExternalIdentifier: String
  let updatedAt: Date
  let createdAt: Date
  let isArchived: Bool
  let progressStageRaw: String?
}

enum ReminderRuntimeProjectionReadModelService {
  @MainActor
  static func workspaceProjectDescriptors(
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    context: ModelContext? = nil
  ) -> [WorkspaceProjectDescriptor] {
    _ = context
    let runtimeDescriptors = runtimeWorkspaceProjectDescriptors(runtimeSnapshot: runtimeSnapshot)
    let archivedProjects = fetchArchivedWorkspaceProjects()
    guard !archivedProjects.isEmpty else { return runtimeDescriptors }

    return mergedWorkspaceProjectDescriptors(
      runtimeDescriptors: runtimeDescriptors,
      archivedProjects: archivedProjects
    )
  }

  @MainActor
  static func workspaceSurfaceProjection(
    projectIDs: [UUID],
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    context: ModelContext? = nil
  ) -> ReminderWorkspaceSurfaceProjection {
    _ = context
    let normalizedProjectIDs = normalizedProjectIDs(projectIDs)
    guard let runtimeSnapshot else {
      return ReminderWorkspaceSurfaceProjection(
        projectSnapshots: [:],
        projectSummaries: [:],
        scheduleEntriesByProjectID: [:]
      )
    }

    let runtimeProjectSnapshots = WorkspaceProjectRuntimeRecordBuilder.records(
      from: runtimeSnapshot,
      projectIDs: normalizedProjectIDs
    )
    let projectsByID = Dictionary(uniqueKeysWithValues: runtimeSnapshot.projects.map { ($0.id, $0) })
    let runtimeScheduleEntriesByProjectID = normalizedProjectIDs.reduce(
      into: [UUID: [ScheduleSliceEntry]]()
    ) { partialResult, projectID in
      guard
        let project = projectsByID[projectID],
        let projectSnapshot = runtimeProjectSnapshots[projectID]
      else {
        return
      }

      partialResult[projectID] = buildScheduleEntries(
        for: project,
        projectSnapshot: projectSnapshot,
        runtimeSnapshot: runtimeSnapshot
      )
    }
    let runtimeProjectSummaries = normalizedProjectIDs.reduce(
      into: [UUID: ProjectSummaryRecord]()
    ) { partialResult, projectID in
      guard let projectSnapshot = runtimeProjectSnapshots[projectID] else { return }
      partialResult[projectID] = buildProjectSummary(
        from: runtimeScheduleEntriesByProjectID[projectID] ?? [],
        projectSnapshot: projectSnapshot
      )
    }

    return ReminderWorkspaceSurfaceProjection(
      projectSnapshots: runtimeProjectSnapshots,
      projectSummaries: runtimeProjectSummaries,
      scheduleEntriesByProjectID: runtimeScheduleEntriesByProjectID
    )
  }

  @MainActor
  static func projectSummaries(
    projectIDs: [UUID],
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    context: ModelContext? = nil
  ) -> [UUID: ProjectSummaryRecord] {
    workspaceSurfaceProjection(
      projectIDs: projectIDs,
      runtimeSnapshot: runtimeSnapshot,
      context: context
    ).projectSummaries
  }

  @MainActor
  static func scheduleEntries(
    projectIDs: [UUID],
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    context: ModelContext? = nil
  ) -> [UUID: [ScheduleSliceEntry]] {
    workspaceSurfaceProjection(
      projectIDs: projectIDs,
      runtimeSnapshot: runtimeSnapshot,
      context: context
    ).scheduleEntriesByProjectID
  }

  @MainActor
  static func workspaceCreatedProjectUndoTemplate(
    projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    context: ModelContext? = nil
  ) -> CreatedProjectUndoTemplate? {
    let descriptor = workspaceProjectDescriptors(
      runtimeSnapshot: runtimeSnapshot,
      context: context
    )
    .first { $0.id == projectID }
    guard let descriptor else { return nil }
    return CreatedProjectUndoTemplate(
      title: descriptor.title,
      colorHex: descriptor.colorHex,
      sortOrder: Int(descriptor.workspaceSortKey ?? Int64.max)
    )
  }

  @MainActor
  static func createdProjectUndoTemplate(
    projectID: UUID,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?
  ) -> TimelineCreatedProjectUndoTemplate? {
    let record = workspaceSurfaceProjection(
      projectIDs: [projectID],
      runtimeSnapshot: runtimeSnapshot
    ).projectSnapshots[projectID]
    guard let record else { return nil }
    return TimelineCreatedProjectUndoTemplate(title: record.title, colorHex: record.colorHex)
  }

  private static func runtimeWorkspaceProjectDescriptors(
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?
  ) -> [WorkspaceProjectDescriptor] {
    guard let runtimeSnapshot else { return [] }

    return runtimeSnapshot.projects.enumerated().map { index, project in
      let featureSidecar = runtimeSnapshot.projectFeatureSidecarByProjectID[project.id]
      let latestTaskUpdatedAt = project.document.flatten().compactMap { entry -> Date? in
        guard entry.node.type.isTask,
          let reminderExternalIdentifier = normalized(entry.node.reminderExternalIdentifier)
        else {
          return nil
        }
        return runtimeSnapshot.reminderModifiedAtByReminderExternalIdentifier[
          reminderExternalIdentifier
        ]
      }
      .max()
      let updatedAt = [featureSidecar?.updatedAt, latestTaskUpdatedAt].compactMap { $0 }.max()
        ?? .distantPast
      let createdAt = featureSidecar?.createdAt ?? latestTaskUpdatedAt ?? .distantPast

      return WorkspaceProjectDescriptor(
        id: project.id,
        title: resolvedProjectTitle(primary: project.title, fallback: nil),
        colorHex: runtimeSnapshot.projectColorHexByProjectID[project.id],
        reminderListIdentifier:
          runtimeSnapshot.projectReminderListIdentifierByProjectID[project.id]
          ?? runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[project.id]
          ?? project.id.uuidString,
        updatedAt: updatedAt,
        createdAt: createdAt,
        latestTaskUpdatedAt: latestTaskUpdatedAt,
        isArchived: false,
        stage: resolvedStage(
          primaryRawValue: featureSidecar?.progressStageRaw,
          fallbackStage: nil
        ),
        boardOrder: featureSidecar?.boardOrder,
        workspaceSortKey: Int64(index)
      )
    }
  }

  private static func resolvedProjectTitle(primary: String?, fallback: String?) -> String {
    if let primary = normalized(primary) {
      return primary
    }
    if let fallback = normalized(fallback) {
      return fallback
    }
    return OutlinerProject.defaultTitle
  }

  private static func resolvedStage(
    primaryRawValue: String?,
    fallbackStage: ProjectProgressStage?
  ) -> ProjectProgressStage {
    if let primaryRawValue,
      let stage = Int(primaryRawValue).flatMap(ProjectProgressStage.init(rawValue:))
    {
      return stage
    }
    return fallbackStage ?? .do
  }

  private static func buildProjectSummary(
    from scheduleEntries: [ScheduleSliceEntry],
    projectSnapshot: WorkspaceProjectRuntimeRecord
  ) -> ProjectSummaryRecord {
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: .now)
    let stage = projectSnapshot.progressStageRaw
      .flatMap(Int.init)
      .flatMap(ProjectProgressStage.init(rawValue:))
      ?? .do

    let rootTasks = scheduleEntries.filter { $0.parentTaskID == nil }
    var openRootTaskCount = 0
    var completedRootTaskCount = 0
    var undatedOpenRootTaskCount = 0
    var overdueOpenRootTaskCount = 0
    var todayTaskCount = 0
    var upcomingDates: [Date] = []

    for task in rootTasks {
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
      stageRaw: stage.storageRawValue,
      progress: stage.progressValue,
      latestTaskUpdatedAt: scheduleEntries.map(\.localUpdatedAt).max(),
      title: projectSnapshot.title,
      colorHex: projectSnapshot.colorHex,
      isArchived: projectSnapshot.isArchived
    )
  }

  private static func buildScheduleEntries(
    for project: OutlinerProject,
    projectSnapshot: WorkspaceProjectRuntimeRecord,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot
  ) -> [ScheduleSliceEntry] {
    var entries: [ScheduleSliceEntry] = []
    var rowOrder = 0

    func visit(nodes: [OutlineNode], parentTaskID: UUID?) {
      for node in nodes {
        let nextParentTaskID = node.type.isTask ? node.canonicalID : parentTaskID
        if node.type.isTask {
          entries.append(
            buildScheduleEntry(
              for: node,
              parentTaskID: parentTaskID,
              rowOrder: rowOrder,
              projectSnapshot: projectSnapshot,
              runtimeSnapshot: runtimeSnapshot
            )
          )
          rowOrder += 1
        }
        visit(nodes: node.children, parentTaskID: nextParentTaskID)
      }
    }

    visit(nodes: project.document.rootNodes, parentTaskID: nil)
    return entries
  }

  private static func buildScheduleEntry(
    for node: OutlineNode,
    parentTaskID: UUID?,
    rowOrder: Int,
    projectSnapshot: WorkspaceProjectRuntimeRecord,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot
  ) -> ScheduleSliceEntry {
    let reminderMetadata = runtimeSnapshot.reminderMetadata(for: node)
    let reminderExternalIdentifier = normalized(node.reminderExternalIdentifier)
    let featureSidecar = reminderExternalIdentifier.flatMap {
      runtimeSnapshot.taskFeatureSidecarByReminderExternalIdentifier[$0]
    }
    let remoteModifiedAt = reminderExternalIdentifier.flatMap {
      runtimeSnapshot.reminderModifiedAtByReminderExternalIdentifier[$0]
    }
    let effectiveUpdatedAt = [featureSidecar?.updatedAt, remoteModifiedAt, projectSnapshot.updatedAt]
      .compactMap { $0 }
      .max() ?? .distantPast
    let effectiveCreatedAt = featureSidecar?.createdAt ?? effectiveUpdatedAt
    let attachmentCount = featureSidecar.map {
      ReminderAttachmentManifestCodec.decode($0.attachmentManifestRaw).count
    } ?? 0
    let encodedReminderNote = ReminderNoteSourceMutationService.plan(for: node) {
      $0.reminderExternalIdentifier
    }.normalizedNoteText

    return ScheduleSliceEntry(
      taskID: node.canonicalID,
      parentTaskID: parentTaskID,
      title: node.text,
      displayedDate: reminderMetadata?.dueDate,
      startDate: nil,
      dueDate: reminderMetadata?.dueDate,
      scheduleHasExplicitTime: reminderMetadata?.hasExplicitTime ?? false,
      scheduledDurationMinutes: featureSidecar?.scheduledDurationMinutes,
      isCompleted: node.type.isCompleted,
      completionDate: node.type.isCompleted ? (reminderMetadata?.completionDate ?? effectiveUpdatedAt) : nil,
      recurrenceRuleRaw: OutlinerIntegratedStore.encodeRecurrence(reminderMetadata?.recurrence),
      attachmentCount: attachmentCount,
      reminderNoteText: encodedReminderNote,
      requiredWorkDays: 0,
      completedWorkUnits: 0,
      completedWorkUnitDates: [],
      preparationScheduleOverridesRaw: "",
      rowOrder: rowOrder,
      priority: max(0, min(9, reminderMetadata?.priority ?? 0)),
      isFlagged: featureSidecar?.isFlagged ?? false,
      isArchived: projectSnapshot.isArchived,
      localUpdatedAt: effectiveUpdatedAt,
      createdAt: effectiveCreatedAt
    )
  }

  private static func normalizedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return projectIDs.filter { seen.insert($0).inserted }
  }

  private static func mergedWorkspaceProjectDescriptors(
    runtimeDescriptors: [WorkspaceProjectDescriptor],
    archivedProjects: [UUID: ArchivedWorkspaceProjectSurfaceRecord]
  ) -> [WorkspaceProjectDescriptor] {
    let runtimeDescriptorsByID = Dictionary(uniqueKeysWithValues: runtimeDescriptors.map { ($0.id, $0) })
    var orderedProjectIDs = runtimeDescriptors.map(\.id)
    var seenProjectIDs = Set(orderedProjectIDs)
    for projectID in archivedProjects.keys where seenProjectIDs.insert(projectID).inserted {
      orderedProjectIDs.append(projectID)
    }

    return orderedProjectIDs.map { projectID in
      let runtimeDescriptor = runtimeDescriptorsByID[projectID]
      let archivedProject = archivedProjects[projectID]

      let stage = runtimeDescriptor?.stage
        ?? resolvedStage(
          primaryRawValue: archivedProject?.progressStageRaw,
          fallbackStage: nil
        )
      let updatedAt = [
        runtimeDescriptor?.updatedAt,
        archivedProject?.updatedAt,
      ].compactMap { $0 }.max() ?? .distantPast
      let createdAt =
        runtimeDescriptor?.createdAt
        ?? archivedProject?.createdAt
        ?? updatedAt

      return WorkspaceProjectDescriptor(
        id: projectID,
        title: resolvedProjectTitle(
          primary: runtimeDescriptor?.title,
          fallback: archivedProject?.title
        ),
        colorHex:
          runtimeDescriptor?.colorHex
          ?? archivedProject?.colorHex,
        reminderListIdentifier:
          normalized(runtimeDescriptor?.reminderListIdentifier)
          ?? normalized(archivedProject?.reminderListIdentifier)
          ?? normalized(archivedProject?.reminderListExternalIdentifier)
          ?? projectID.uuidString,
        updatedAt: updatedAt,
        createdAt: createdAt,
        latestTaskUpdatedAt: runtimeDescriptor?.latestTaskUpdatedAt,
        isArchived:
          archivedProject?.isArchived
          ?? runtimeDescriptor?.isArchived
          ?? false,
        stage: stage,
        boardOrder: runtimeDescriptor?.boardOrder,
        workspaceSortKey: runtimeDescriptor?.workspaceSortKey
      )
    }
  }

  private static func fetchArchivedWorkspaceProjects() -> [UUID: ArchivedWorkspaceProjectSurfaceRecord] {
    Dictionary(
      uniqueKeysWithValues: ArchivedProjectBundleOwner.allBundles().map { bundle in
        (
          bundle.archivedProjectID,
          ArchivedWorkspaceProjectSurfaceRecord(
            id: bundle.archivedProjectID,
            title: bundle.title,
            colorHex: bundle.colorHex,
            reminderListIdentifier: bundle.reminderListIdentifier,
            reminderListExternalIdentifier: bundle.reminderListExternalIdentifier,
            updatedAt: max(bundle.archivedAt, bundle.projectFeature?.updatedAt ?? .distantPast),
            createdAt: bundle.projectFeature?.createdAt ?? bundle.archivedAt,
            isArchived: true,
            progressStageRaw: normalized(bundle.projectFeature?.progressStageRaw)
          )
        )
      }
    )
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
