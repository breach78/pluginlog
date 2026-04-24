import Foundation
import SwiftData

private let projectTaskPromotionEnabled = false

@MainActor
extension AppState {
  func projectMirrorPlacementStore() -> TaskMirrorPlacementStore? {
    storageCoordinator.paths.map {
      TaskMirrorPlacementStore(databaseURL: $0.normalizedSQLiteURL)
    }
  }

  func archivedProjectBundleStore() -> ArchivedProjectBundleStore? {
    ArchivedProjectBundleStoreFactory.make(
      dataDirectory: storageCoordinator.paths?.dataDirectory
    )
  }

  func resolvedOwnerProjectID(forTaskID taskID: UUID, context: ModelContext) -> UUID? {
    ProjectIdentityResolver.ownerProjectID(
      forTaskID: taskID,
      runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
      reminderGateway: reminderGateway,
      context: context,
      dataDirectory: storageCoordinator.paths?.dataDirectory
    )
  }

  func resolvedTaskRecord(forTaskID taskID: UUID, context: ModelContext) -> ProjectIdentityTaskRecord? {
    ProjectIdentityResolver.taskRecord(
      forTaskID: taskID,
      runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
      reminderGateway: reminderGateway,
      context: context,
      dataDirectory: storageCoordinator.paths?.dataDirectory
    )
  }

  func resolvedProjectNoteMarkdown(forProjectID projectID: UUID, context: ModelContext) -> String? {
    ProjectIdentityResolver.projectNoteMarkdown(
      forProjectID: projectID,
      runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
      context: context
    )
  }

  func resolvedProjectProgressStage(forProjectID projectID: UUID) -> ProjectProgressStage {
    cachedOutlinerRuntimeProjectionSnapshot?
      .projectFeatureSidecarByProjectID[projectID]?
      .progressStageRaw
      .flatMap { rawValue in
        Int(rawValue).flatMap(ProjectProgressStage.init(rawValue:))
      }
      ?? .do
  }

  func resolvedProjectBoardOrder(forProjectID projectID: UUID) -> Int? {
    cachedOutlinerRuntimeProjectionSnapshot?
      .projectFeatureSidecarByProjectID[projectID]?
      .boardOrder
  }

  func resolvedProjectTitle(forProjectID projectID: UUID, context: ModelContext) -> String {
    ProjectIdentityResolver.projectTitle(
      forProjectID: projectID,
      runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
      reminderGateway: reminderGateway,
      dataDirectory: storageCoordinator.paths?.dataDirectory,
      context: context
    )
  }

  func isActiveProjectIdentity(_ projectID: UUID, context: ModelContext) -> Bool {
    ProjectIdentityResolver.isActiveProject(
      projectID,
      runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
      reminderGateway: reminderGateway,
      dataDirectory: storageCoordinator.paths?.dataDirectory,
      context: context
    )
  }

  func projectDocumentStore(for projectID: UUID) -> ProjectDocumentStore? {
    guard let modelContainer else { return nil }
    if let existing = projectCommandDispatcherRegistry[projectID] {
      return existing
    }

    let store = ProjectDocumentStore(
      projectID: projectID,
      modelContainer: modelContainer,
      reminderProjectProvider: reminderProjectProvider,
      projectionSidecarStore: runtimeProjectionSidecarStore(),
      mirrorPlacementStore: projectMirrorPlacementStore(),
      attachmentStore: attachmentStore,
      workspaceTreeRepository: workspaceTreeRepository,
      indexUpdateQueue: projectIndexUpdateQueue,
      runtimeSnapshotProvider: { [weak self] in
        self?.cachedOutlinerRuntimeProjectionSnapshot
      },
      sidecarOwnerFieldWriter: { [weak self] write in
        guard let self else { return false }
        return await self.send(
          .writeOwnerField(ownerStore: .sidecar, write: write),
          waitForEditorIdle: false
        )
      },
      appStateCommandSender: { [weak self] command, waitForEditorIdle in
        guard let self else { return false }
        return await self.send(command, waitForEditorIdle: waitForEditorIdle)
      }
    )
    projectCommandDispatcherRegistry[projectID] = store
    observeProjectDocumentStore(store, projectID: projectID)
    return store
  }

  func discardProjectDocumentStore(for projectID: UUID) {
    projectDocumentStoreChangeCancellables[projectID]?.cancel()
    projectDocumentStoreChangeCancellables[projectID] = nil
    projectCommandDispatcherRegistry[projectID] = nil
  }

  func projectDocumentStore(forTaskID taskID: UUID, context: ModelContext) -> ProjectDocumentStore? {
    guard let resolvedProjectID = resolvedOwnerProjectID(forTaskID: taskID, context: context) else {
      return nil
    }
    return projectDocumentStore(for: resolvedProjectID)
  }

  func resolvedProjectRootNodes(forProjectID projectID: UUID) -> [OutlineNode]? {
    cachedOutlinerRuntimeProjectionSnapshot?
      .projects
      .first(where: { $0.id == projectID })?
      .document
      .rootNodes
  }

  func projectRootStructureSnapshot(for projectID: UUID) -> ReminderProjectRootStructureRecord? {
    guard let reminderListExternalIdentifier = resolvedProjectReminderListExternalIdentifier(projectID: projectID),
      let rootNodes = resolvedProjectRootNodes(forProjectID: projectID)
    else {
      return nil
    }

    return ReminderProjectRootStructureMutationService.record(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      rootNodes: ReminderProjectRootStructureCodec.rootNodes(from: rootNodes),
      existing: cachedOutlinerRuntimeProjectionSnapshot?
        .projectRootStructureByReminderListExternalIdentifier[reminderListExternalIdentifier]
    )
  }

  func invalidateWorkspaceProjectCache(for identifier: UUID) async {
    _ = identifier
  }

  func invalidateWorkspaceProjectCaches(for identifiers: Set<UUID>) async {
    guard !identifiers.isEmpty else { return }
    for identifier in identifiers.sorted(by: { $0.uuidString < $1.uuidString }) {
      await invalidateWorkspaceProjectCache(for: identifier)
    }
  }

  func updateProjectDocumentTitle(_ rawTitle: String, projectID: UUID) async {
    guard
      let reminderListIdentifier = normalizedProjectionValue(
        cachedOutlinerRuntimeProjectionSnapshot?.projectReminderListIdentifierByProjectID[projectID]
      )
    else {
      errorMessage = "프로젝트 목록 식별자를 찾지 못했습니다."
      return
    }

    let didWrite = await send(
      .writeOwnerField(
        ownerStore: .reminder,
        write: .listMetadata(
          ReminderListMetadataWrite(
            projectID: projectID,
            reminderListIdentifier: reminderListIdentifier,
            reminderListExternalIdentifier: normalizedProjectionValue(
              cachedOutlinerRuntimeProjectionSnapshot?.projectReminderListExternalIdentifierByProjectID[
                projectID]
            ),
            mutation: .title(rawTitle)
          )
        )
      ),
      waitForEditorIdle: false
    )
    if !didWrite {
      errorMessage = "프로젝트 제목 저장에 실패했습니다."
    }
  }

  func setProjectDocumentStage(_ stage: ProjectProgressStage, projectID: UUID) {
    Task { @MainActor in
      let didWrite = await send(
        .writeOwnerField(
          ownerStore: .sidecar,
          write: .projectMetadata(
            ProjectMetadataWrite(
              projectID: projectID,
              mutation: .progressStage(stage)
            )
          )
        ),
        waitForEditorIdle: false
      )
      if !didWrite {
        self.errorMessage = "프로젝트 상태 저장에 실패했습니다."
      }
    }
  }

  @discardableResult
  func writeWorkspaceProjectOrder(
    _ orderedProjectIDs: [UUID]
  ) async -> Bool {
    let normalizedProjectIDs = Array(NSOrderedSet(array: orderedProjectIDs)) as? [UUID]
      ?? orderedProjectIDs
    guard !normalizedProjectIDs.isEmpty else { return false }

    let didWrite = await send(
      .writeOwnerField(
        ownerStore: .sidecar,
        write: .ordering(
          ProjectOrderingWrite(
            mutation: .workspace(orderedProjectIDs: normalizedProjectIDs)
          )
        )
      ),
      waitForEditorIdle: false
    )
    if !didWrite {
      errorMessage = "프로젝트 순서 저장에 실패했습니다."
    }
    return didWrite
  }

  @discardableResult
  func writeProjectBoardOrder(
    _ boardOrder: Int?,
    projectID: UUID
  ) async -> Bool {
    let didWrite = await send(
      .writeOwnerField(
        ownerStore: .sidecar,
        write: .appSupplement(
          AppSupplementWrite(
            mutation: .projectBoardOrder(
              projectID: projectID,
              boardOrder: boardOrder
            )
          )
        )
      ),
      waitForEditorIdle: false
    )
    if !didWrite {
      errorMessage = "프로젝트 보드 순서 저장에 실패했습니다."
    }
    return didWrite
  }

  @discardableResult
  func writeProjectBoardOrders(
    _ boardOrdersByProjectID: [UUID: Int?]
  ) async -> Bool {
    let orderedProjectIDs = boardOrdersByProjectID.keys.sorted { $0.uuidString < $1.uuidString }
    guard !orderedProjectIDs.isEmpty else { return true }

    var didWriteAll = true
    for projectID in orderedProjectIDs {
      let didWrite = await writeProjectBoardOrder(
        boardOrdersByProjectID[projectID] ?? nil,
        projectID: projectID
      )
      didWriteAll = didWriteAll && didWrite
    }
    return didWriteAll
  }

  @discardableResult
  func writeProjectBucketOrder(
    projectIDsInOrder: [UUID]
  ) async -> Bool {
    let boardOrdersByProjectID = Dictionary(
      uniqueKeysWithValues: projectIDsInOrder.enumerated().map { index, projectID in
        (projectID, Optional(index))
      }
    )
    return await writeProjectBoardOrders(boardOrdersByProjectID)
  }

  func handleProjectDocumentTitleMutationResult(
    _ result: ProjectMutationResult,
    projectID: UUID
  ) async {
    guard result.didMutateWorkspaceTree else { return }
    await invalidateWorkspaceProjectCache(for: projectID)
    bumpWorkspaceTreeRevision()
  }

  func handleArchivedProjectDocumentMutation(projectID: UUID) {
    if selectedProjectID == projectID {
      selectedProjectID = nil
    }
  }

  func handleDeletedProjectDocumentMutation(
    projectID: UUID,
    result: ProjectMutationResult
  ) async throws {
    if selectedProjectID == projectID {
      selectedProjectID = nil
    }
    discardProjectDocumentStore(for: projectID)
    try deletePromotedTaskArchives(for: result.deletedWorkspaceNodeIDs)
    if !result.deletedWorkspaceNodeIDs.isEmpty {
      bumpWorkspaceTreeRevision()
    }
  }
}

extension AppState {
  @discardableResult
  func createTask(
    inProjectID projectID: UUID,
    title: String,
    parentTaskID: UUID? = nil,
    rootBulletID: UUID? = nil,
    insertionSlot: Int? = nil,
    startDate: Date? = nil,
    durationMinutes: Int? = nil,
    context: ModelContext
  )
    async -> UUID?
  {
    do {
      let result = try await dispatchProjectCommand(
        in: projectID,
        .createTask(
          title: title,
          parentTaskID: parentTaskID,
          rootBulletID: rootBulletID,
          insertionSlot: insertionSlot,
          day: startDate,
          timeMinutes: explicitTimeMinutes(from: startDate),
          durationMinutes: durationMinutes
        )
      )
      return result.createdTaskID
    } catch {
      reportError(error, logMessage: "createTask failed")
      return nil
    }
  }

  @discardableResult
  func reorderProjectDetailTasks(
    inProjectID projectID: UUID,
    visibleTaskIDs: [UUID],
    draggedID: UUID,
    targetID: UUID,
    placement: TaskDropPlacement,
    context: ModelContext
  ) -> Bool {
    guard draggedID != targetID else { return false }

    guard
      let currentVisibleRootTaskIDs = visibleRootTaskIDs(inProjectID: projectID),
      currentVisibleRootTaskIDs.contains(draggedID),
      currentVisibleRootTaskIDs.contains(targetID),
      let reorderedVisibleTaskIDs = TaskOrdering.reorderedIdentifiers(
        in: currentVisibleRootTaskIDs,
        draggedID: draggedID,
        targetID: targetID,
        placeAfterTarget: placement == .after
      )
    else {
      return false
    }

    let orderedReminderExternalIdentifiers = reorderedVisibleTaskIDs.compactMap { taskID in
      resolvedTaskRecord(forTaskID: taskID, context: context)?.reminderExternalIdentifier
    }
    guard orderedReminderExternalIdentifiers.count == reorderedVisibleTaskIDs.count else {
      errorMessage = "정렬 대상 식별자를 찾지 못했습니다."
      return false
    }

    Task { @MainActor in
      let _ = await send(
        .writeOwnerField(
          ownerStore: .sidecar,
          write: .ordering(
            ProjectOrderingWrite(
              mutation: .project(
                projectID: projectID,
                orderedTopLevelReminderExternalIdentifiers: orderedReminderExternalIdentifiers
              )
            )
          )
        ),
        waitForEditorIdle: false
      )
    }
    return true
  }

  @discardableResult
  func persistProjectDetailTaskOrder(
    inProjectID projectID: UUID,
    orderedVisibleTaskIDs: [UUID],
    context: ModelContext
  ) -> Bool {
    let orderedReminderExternalIdentifiers = orderedVisibleTaskIDs.compactMap { taskID in
      resolvedTaskRecord(forTaskID: taskID, context: context)?.reminderExternalIdentifier
    }
    guard orderedReminderExternalIdentifiers.count == orderedVisibleTaskIDs.count else {
      errorMessage = "정렬 대상 식별자를 찾지 못했습니다."
      return false
    }

    Task { @MainActor in
      let _ = await send(
        .writeOwnerField(
          ownerStore: .sidecar,
          write: .ordering(
            ProjectOrderingWrite(
              mutation: .project(
                projectID: projectID,
                orderedTopLevelReminderExternalIdentifiers: orderedReminderExternalIdentifiers
              )
            )
          )
        ),
        waitForEditorIdle: false
      )
    }
    return true
  }

  private func visibleRootTaskIDs(inProjectID projectID: UUID) -> [UUID]? {
    resolvedProjectRootNodes(forProjectID: projectID)?.compactMap { node in
      node.type.isTask ? node.canonicalID : nil
    }
  }

  @discardableResult
  func saveProjectDetailProjectNote(
    _ note: String,
    projectID: UUID,
    context: ModelContext
  ) -> Bool {
    let currentNote = resolvedProjectNoteMarkdown(forProjectID: projectID, context: context)
    guard currentNote != note else { return false }

    Task { @MainActor in
      let didWrite = await send(
        .writeOwnerField(
          ownerStore: .sidecar,
          write: .projectMetadata(
            ProjectMetadataWrite(
              projectID: projectID,
              mutation: .projectNote(note)
            )
          )
        ),
        waitForEditorIdle: false
      )
      if !didWrite {
        self.errorMessage = "프로젝트 메모 저장에 실패했습니다."
      }
    }
    return true
  }

  @discardableResult
  func saveProjectDetailTaskReminderNote(
    _ note: String,
    taskID: UUID,
    context: ModelContext
  ) -> Bool {
    guard
      let resolvedTaskWrite = resolvedReminderTaskWriteContext(
        taskID: taskID,
        context: context
      )
    else {
      return false
    }

    Task { @MainActor in
      let didWrite = await send(
        .writeOwnerField(
          ownerStore: .reminder,
          write: .taskFields(
            ReminderTaskFieldsWrite(
              projectID: resolvedTaskWrite.ownerProjectID,
              taskID: taskID,
              reminderIdentifier: resolvedTaskWrite.reminderIdentifier,
              reminderExternalIdentifier: resolvedTaskWrite.reminderExternalIdentifier,
              mutation: .note(note)
            )
          )
        ),
        waitForEditorIdle: false
      )
      if !didWrite {
        self.errorMessage = "리마인더 메모 저장에 실패했습니다."
      }
    }
    return true
  }

  @discardableResult
  func saveProjectDetailTaskTitle(
    _ rawTitle: String,
    taskID: UUID,
    context: ModelContext
  ) -> Bool {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return false }
    guard
      let resolvedTaskWrite = resolvedReminderTaskWriteContext(
        taskID: taskID,
        context: context
      )
    else {
      return false
    }
    guard resolvedTaskWrite.task.title != title else { return false }

    Task { @MainActor in
      let didWrite = await send(
        .writeOwnerField(
          ownerStore: .reminder,
          write: .taskFields(
            ReminderTaskFieldsWrite(
              projectID: resolvedTaskWrite.ownerProjectID,
              taskID: taskID,
              reminderIdentifier: resolvedTaskWrite.reminderIdentifier,
              reminderExternalIdentifier: resolvedTaskWrite.reminderExternalIdentifier,
              mutation: .title(title)
            )
          )
        ),
        waitForEditorIdle: false
      )
      if !didWrite {
        self.errorMessage = "할일 제목 저장에 실패했습니다."
      }
    }
    return true
  }

  @discardableResult
  func saveProjectDetailTaskDueDate(
    _ date: Date?,
    taskID: UUID,
    context: ModelContext
  ) -> Bool {
    guard let task = resolvedTaskRecord(forTaskID: taskID, context: context) else {
      errorMessage = "할 일을 찾지 못했습니다."
      return false
    }

    let explicitTimeMinutes =
      task.scheduleHasExplicitTime
      ? self.explicitTimeMinutes(from: task.dueDate)
      : nil
    return saveProjectDetailTaskSchedule(
      day: date,
      hasExplicitTime: task.scheduleHasExplicitTime,
      timeMinutes: explicitTimeMinutes,
      durationMinutes: task.scheduledDurationMinutes,
      requiredWorkDays: task.requiredWorkDays,
      taskID: taskID,
      context: context
    )
  }

  @discardableResult
  func saveProjectDetailTaskSchedule(
    day: Date?,
    hasExplicitTime: Bool,
    timeMinutes: Int?,
    durationMinutes: Int?,
    requiredWorkDays: Int,
    taskID: UUID,
    context: ModelContext
  ) -> Bool {
    _ = requiredWorkDays
    guard let task = resolvedTaskRecord(forTaskID: taskID, context: context) else {
      errorMessage = "할 일을 찾지 못했습니다."
      return false
    }
    let normalizedTime = hasExplicitTime ? timeMinutes : nil
    let normalizedDuration = hasExplicitTime ? durationMinutes : nil
    let dueDate = ProjectDocumentStore.scheduleStorage(
      day: day,
      timeMinutes: normalizedTime,
      durationMinutes: normalizedDuration
    ).dueDate
    guard
      task.dueDate != dueDate
        || task.scheduleHasExplicitTime != hasExplicitTime
        || task.scheduledDurationMinutes != normalizedDuration
    else {
      return false
    }

    Task { @MainActor in
      _ = await writeProjectDetailTaskSchedule(
        day: day,
        hasExplicitTime: hasExplicitTime,
        timeMinutes: timeMinutes,
        durationMinutes: durationMinutes,
        taskID: taskID,
        context: context
      )
    }
    return true
  }

  @discardableResult
  func writeProjectDetailTaskSchedule(
    day: Date?,
    hasExplicitTime: Bool,
    timeMinutes: Int?,
    durationMinutes: Int?,
    taskID: UUID,
    context: ModelContext
  ) async -> Bool {
    guard
      let resolvedTaskWrite = resolvedReminderTaskWriteContext(
        taskID: taskID,
        context: context
      )
    else {
      return false
    }
    let normalizedTime = hasExplicitTime ? timeMinutes : nil
    let normalizedDuration = hasExplicitTime ? durationMinutes : nil
    return await send(
      .taskScheduleSplit(
        TaskScheduleSplitWrite(
          projectID: resolvedTaskWrite.ownerProjectID,
          taskID: taskID,
          day: day,
          timeMinutes: normalizedTime,
          durationMinutes: normalizedDuration
        )
      ),
      waitForEditorIdle: false
    )
  }

  @discardableResult
  func saveProjectDetailTaskCompletion(
    taskID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    context: ModelContext
  ) async -> Bool {
    guard
      let resolvedTaskWrite = resolvedReminderTaskWriteContext(
        taskID: taskID,
        context: context
      )
    else {
      return false
    }
    let task = resolvedTaskWrite.task

    let resolvedCompletionDate = isCompleted ? (completionDate ?? .now) : nil
    guard task.isCompleted != isCompleted || task.completionDate != resolvedCompletionDate else {
      return false
    }

    let didWrite = await send(
      .writeOwnerField(
        ownerStore: .reminder,
        write: .taskFields(
          ReminderTaskFieldsWrite(
            projectID: resolvedTaskWrite.ownerProjectID,
            taskID: taskID,
            reminderIdentifier: resolvedTaskWrite.reminderIdentifier,
            reminderExternalIdentifier: resolvedTaskWrite.reminderExternalIdentifier,
            mutation: .completion(
              isCompleted: isCompleted,
              completionDate: resolvedCompletionDate
            )
          )
        )
      ),
      waitForEditorIdle: false
    )
    if !didWrite {
      errorMessage = "할일 완료 상태 저장에 실패했습니다."
    }
    return didWrite
  }

  private func resolvedReminderTaskWriteContext(
    taskID: UUID,
    context: ModelContext
  ) -> (
    task: ProjectIdentityTaskRecord,
    ownerProjectID: UUID,
    reminderIdentifier: String?,
    reminderExternalIdentifier: String?
  )? {
    guard let task = resolvedTaskRecord(forTaskID: taskID, context: context) else {
      errorMessage = "할 일을 찾지 못했습니다."
      return nil
    }
    guard let ownerProjectID = task.reminderOwnerProjectID ?? resolvedOwnerProjectID(forTaskID: taskID, context: context)
    else {
      errorMessage = "할 일을 찾지 못했습니다."
      return nil
    }

    let persistedTask = try? context.fetch(
      FetchDescriptor<TaskItem>(
        predicate: #Predicate<TaskItem> { item in
          item.id == taskID
        }
      )
    ).first
    let reminderIdentifier = normalizedProjectionValue(persistedTask?.reminderIdentifier)
    let reminderExternalIdentifier = normalizedProjectionValue(
      task.reminderExternalIdentifier
        ?? persistedTask?.reminderExternalIdentifier
        ?? TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID)
    )
    guard reminderIdentifier != nil || reminderExternalIdentifier != nil else {
      errorMessage = "리마인더 식별자를 찾지 못했습니다."
      return nil
    }

    return (task, ownerProjectID, reminderIdentifier, reminderExternalIdentifier)
  }

  @discardableResult
  func saveProjectDetailTaskPresentation(
    taskID: UUID,
    boardStage: BoardStage,
    importance: ImportanceLevel,
    priority: Int,
    isFlagged: Bool,
    context: ModelContext
  ) async -> Bool {
    guard let task = resolvedTaskRecord(forTaskID: taskID, context: context) else {
      errorMessage = "할 일을 찾지 못했습니다."
      return false
    }
    guard
      let ownerProjectID =
        task.reminderOwnerProjectID
        ?? resolvedOwnerProjectID(forTaskID: taskID, context: context)
    else {
      errorMessage = "할 일을 찾지 못했습니다."
      return false
    }
    let normalizedPriority = max(0, min(9, priority))
    let shouldWriteReminderPriority = task.priority != normalizedPriority
    let shouldWriteSupplement =
      task.boardStage != boardStage
      || task.importance != importance
      || task.isFlagged != isFlagged
    guard shouldWriteReminderPriority || shouldWriteSupplement else { return false }

    return await send(
      .taskPresentationSplit(
        TaskPresentationSplitWrite(
          projectID: ownerProjectID,
          taskID: taskID,
          boardStage: boardStage,
          importance: importance,
          priority: normalizedPriority,
          isFlagged: isFlagged
        )
      ),
      waitForEditorIdle: false
    )
  }

  func performTaskScheduleSplitWrite(
    _ write: TaskScheduleSplitWrite
  ) async -> Bool {
    guard let modelContainer else {
      errorMessage = "할일 일정 저장에 실패했습니다."
      return false
    }
    let context = ModelContext(modelContainer)
    guard let resolvedTaskWrite = resolvedReminderTaskWriteContext(
      taskID: write.taskID,
      context: context
    ) else {
      return false
    }
    let task = resolvedTaskWrite.task
    let nextStorage = ProjectDocumentStore.scheduleStorage(
      day: write.day,
      timeMinutes: write.timeMinutes,
      durationMinutes: write.durationMinutes
    )
    let previousScheduleState = ProjectTaskScheduleMutationSnapshot(
      isCompleted: task.isCompleted,
      completionDate: task.completionDate,
      startDate: task.startDate,
      dueDate: task.dueDate,
      scheduleHasExplicitTime: task.scheduleHasExplicitTime,
      scheduledDurationMinutes: task.scheduledDurationMinutes
    )
    let nextScheduleState = ProjectTaskScheduleMutationSnapshot(
      isCompleted: task.isCompleted,
      completionDate: task.completionDate,
      startDate: nextStorage.startDate,
      dueDate: nextStorage.dueDate,
      scheduleHasExplicitTime: nextStorage.hasExplicitTime,
      scheduledDurationMinutes: nextStorage.durationMinutes
    )
    guard previousScheduleState != nextScheduleState else { return false }

    let reminderWrite = ReminderTaskFieldsWrite(
      projectID: resolvedTaskWrite.ownerProjectID,
      taskID: write.taskID,
      reminderIdentifier: resolvedTaskWrite.reminderIdentifier,
      reminderExternalIdentifier: resolvedTaskWrite.reminderExternalIdentifier,
      mutation: .schedule(
        dueDate: nextStorage.dueDate,
        hasExplicitTime: nextStorage.hasExplicitTime
      )
    )
    guard await send(
      .writeOwnerField(ownerStore: .reminder, write: .taskFields(reminderWrite)),
      waitForEditorIdle: false
    ) else {
      errorMessage = "할일 일정 저장에 실패했습니다."
      return false
    }

    let supplementWrite = AppSupplementWrite(
      mutation: .taskScheduledDuration(
        taskID: write.taskID,
        scheduledDurationMinutes: nextStorage.durationMinutes
      )
    )
    guard await send(
      .writeOwnerField(ownerStore: .sidecar, write: .appSupplement(supplementWrite)),
      waitForEditorIdle: false
    ) else {
      _ = await send(
        .writeOwnerField(
          ownerStore: .reminder,
          write: .taskFields(
            ReminderTaskFieldsWrite(
              projectID: resolvedTaskWrite.ownerProjectID,
              taskID: write.taskID,
              reminderIdentifier: resolvedTaskWrite.reminderIdentifier,
              reminderExternalIdentifier: resolvedTaskWrite.reminderExternalIdentifier,
              mutation: .schedule(
                dueDate: previousScheduleState.dueDate,
                hasExplicitTime: previousScheduleState.scheduleHasExplicitTime
              )
            )
          )
        ),
        waitForEditorIdle: false
      )
      errorMessage = "할일 일정 부가정보 저장에 실패했습니다."
      return false
    }

    if let summary = ProjectHistoryService.taskScheduleChangeSummary(
      previousState: previousScheduleState,
      nextState: nextScheduleState
    ) {
      ProjectHistoryService.recordTaskScheduleChanged(
        projectID: resolvedTaskWrite.ownerProjectID,
        taskID: write.taskID,
        taskTitle: task.title,
        summary: summary,
        occurredAt: .now,
        in: context
      )
    }
    _ = await syncOwnedCalendarEvents(for: [resolvedTaskWrite.ownerProjectID])
    return true
  }

  func performTaskPresentationSplitWrite(
    _ write: TaskPresentationSplitWrite
  ) async -> Bool {
    guard let modelContainer else {
      errorMessage = "할일 표시 상태 저장에 실패했습니다."
      return false
    }
    let context = ModelContext(modelContainer)
    guard let resolvedTaskWrite = resolvedReminderTaskWriteContext(
      taskID: write.taskID,
      context: context
    ) else {
      return false
    }
    let task = resolvedTaskWrite.task
    let normalizedPriority = max(0, min(9, write.priority))
    let shouldWriteReminderPriority = task.priority != normalizedPriority
    let shouldWriteSupplement =
      task.boardStage != write.boardStage
      || task.importance != write.importance
      || task.isFlagged != write.isFlagged
    guard shouldWriteReminderPriority || shouldWriteSupplement else { return false }

    if shouldWriteReminderPriority {
      let reminderWrite = ReminderTaskFieldsWrite(
        projectID: resolvedTaskWrite.ownerProjectID,
        taskID: write.taskID,
        reminderIdentifier: resolvedTaskWrite.reminderIdentifier,
        reminderExternalIdentifier: resolvedTaskWrite.reminderExternalIdentifier,
        mutation: .presentationPriority(normalizedPriority)
      )
      guard await send(
        .writeOwnerField(ownerStore: .reminder, write: .taskFields(reminderWrite)),
        waitForEditorIdle: false
      ) else {
        errorMessage = "할일 우선순위 저장에 실패했습니다."
        return false
      }
    }

    guard shouldWriteSupplement else { return true }
    let supplementWrite = AppSupplementWrite(
      mutation: .taskPresentation(
        taskID: write.taskID,
        boardStage: write.boardStage,
        importance: write.importance,
        isFlagged: write.isFlagged
      )
    )
    guard await send(
      .writeOwnerField(ownerStore: .sidecar, write: .appSupplement(supplementWrite)),
      waitForEditorIdle: false
    ) else {
      if shouldWriteReminderPriority {
        _ = await send(
          .writeOwnerField(
            ownerStore: .reminder,
            write: .taskFields(
              ReminderTaskFieldsWrite(
                projectID: resolvedTaskWrite.ownerProjectID,
                taskID: write.taskID,
                reminderIdentifier: resolvedTaskWrite.reminderIdentifier,
                reminderExternalIdentifier: resolvedTaskWrite.reminderExternalIdentifier,
                mutation: .presentationPriority(task.priority)
              )
            )
          ),
          waitForEditorIdle: false
        )
      }
      errorMessage = "할일 표시 상태 저장에 실패했습니다."
      return false
    }
    return true
  }

  @discardableResult
  func saveProjectDetailTaskPlannedWorkProgress(
    taskID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date,
    context: ModelContext
  ) async -> Bool {
    guard let task = resolvedTaskRecord(forTaskID: taskID, context: context) else {
      errorMessage = "할 일을 찾지 못했습니다."
      return false
    }
    guard !task.isCompleted else { return false }

    let normalizedRequiredWorkDays = max(0, task.requiredWorkDays)
    let normalizedTarget = max(0, min(targetCompletedUnits, normalizedRequiredWorkDays))
    let previousCompletedUnits = task.completedWorkUnits
    guard previousCompletedUnits != normalizedTarget else { return false }

    let recordedAt = Calendar.autoupdatingCurrent.startOfDay(for: completedOn)
    var dates = ProjectDocumentStore.decodedCompletedWorkUnitDates(
      raw: task.completedWorkUnitDatesRaw,
      requiredCount: previousCompletedUnits,
      defaultDate: completedOn
    )
    if normalizedTarget > previousCompletedUnits {
      dates.append(
        contentsOf: Array(
          repeating: recordedAt,
          count: normalizedTarget - previousCompletedUnits
        )
      )
    } else {
      dates = Array(dates.prefix(normalizedTarget))
    }

    let didWrite = await send(
      .writeOwnerField(
        ownerStore: .sidecar,
        write: .appSupplement(
          AppSupplementWrite(
            mutation: .taskPlannedWorkProgress(
              taskID: taskID,
              completedWorkUnits: normalizedTarget,
              completedWorkUnitDatesRaw: ProjectDocumentStore.encodedCompletedWorkUnitDates(dates)
            )
          )
        )
      ),
      waitForEditorIdle: false
    )
    if !didWrite {
      errorMessage = "예상 작업 진행 저장에 실패했습니다."
    }
    return didWrite
  }

  func saveProjectDetailTaskReminderNoteFromAnySource(
    _ note: String,
    taskID: UUID,
    context: ModelContext
  ) async -> Bool {
    do {
      if resolvedTaskRecord(forTaskID: taskID, context: context) != nil {
        return saveProjectDetailTaskReminderNote(
          note,
          taskID: taskID,
          context: context
        )
      }

      guard let workspaceTreeRepository else {
        errorMessage = "할 일을 찾지 못했습니다."
        return false
      }
      guard let current = try await workspaceTreeRepository.fetchTask(id: taskID) else {
        errorMessage = "할 일을 찾지 못했습니다."
        return false
      }
      guard current.reminderNoteText != note else { return false }

      _ = try await workspaceTreeRepository.updateTaskReminderNote(
        of: taskID,
        reminderText: note,
        remoteLastModifiedAt: current.remoteLastModifiedAt
      )
      await invalidateWorkspaceProjectCache(for: current.workspaceNodeID)
      await MainActor.run {
        self.bumpWorkspaceTreeRevision()
      }
      return true
    } catch {
      reportError(error, logMessage: "saveProjectDetailTaskReminderNoteFromAnySource failed")
      return false
    }
  }

  @discardableResult
  func createProjectDetailWorkspaceTask(
    under parentNodeID: UUID,
    parentTaskID: UUID? = nil,
    title: String
  ) async -> UUID? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let workspaceTreeRepository else {
      errorMessage = "워크스페이스 저장소를 찾지 못했습니다."
      return nil
    }

    do {
      let task = try await workspaceTreeRepository.createTask(
        title: trimmed,
        parentNodeID: parentNodeID,
        parentTaskID: parentTaskID
      )
      await invalidateWorkspaceProjectCache(for: parentNodeID)
      await MainActor.run {
        self.bumpWorkspaceTreeRevision()
      }
      return task.id
    } catch {
      reportError(error, logMessage: "createProjectDetailWorkspaceTask failed")
      return nil
    }
  }

  @discardableResult
  func saveProjectDetailWorkspaceNodeNote(_ note: String, nodeID: UUID) async -> Bool {
    guard let workspaceTreeRepository else {
      errorMessage = "프로젝트 노드 저장소를 찾지 못했습니다."
      return false
    }

    do {
      guard let current = try await workspaceTreeRepository.fetchNode(id: nodeID) else {
        errorMessage = "프로젝트를 찾지 못했습니다."
        return false
      }

      guard current.noteMarkdown != note else { return false }

      _ = try await workspaceTreeRepository.updateNote(of: nodeID, markdown: note)
      await MainActor.run {
        self.bumpWorkspaceTreeRevision()
      }
      return true
    } catch {
      reportError(error, logMessage: "saveProjectDetailWorkspaceNodeNote failed")
      return false
    }
  }

  @discardableResult
  func promoteProjectDetailTaskToProject(
    taskID: UUID,
    parentNodeID: UUID,
    context: ModelContext
  ) async -> UUID? {
    _ = (taskID, parentNodeID, context)
    guard projectTaskPromotionEnabled else { return nil }
    return nil
  }

  func projectDetailAttachments(
    for owner: AttachmentOwner,
    context: ModelContext
  ) -> [AttachmentEntity] {
    let ownerType = owner.ownerType.rawValue
    let ownerID = owner.ownerID

    return
      (try? context.fetch(
        FetchDescriptor<AttachmentEntity>(
          predicate: #Predicate {
            $0.ownerTypeRaw == ownerType && $0.ownerID == ownerID && !$0.isArchived
          },
          sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
      )) ?? []
  }

  @discardableResult
  func importProjectDetailAttachments(
    from urls: [URL],
    into owner: AttachmentOwner,
    context: ModelContext
  ) -> Bool {
    guard !urls.isEmpty else { return false }
    let ownerProjectID: UUID?
    switch owner {
    case let .project(projectID):
      ownerProjectID = projectID
    case let .task(taskID):
      ownerProjectID = resolvedOwnerProjectID(forTaskID: taskID, context: context)
    }
    guard let ownerProjectID else {
      errorMessage = "첨부 저장소를 사용할 수 없습니다."
      return false
    }

    return applyProjectAttachmentMutation(
      .importFiles(urls: urls, owner: owner),
      ownerProjectID: ownerProjectID
    )
  }

  func openProjectDetailAttachment(_ attachmentID: UUID, context: ModelContext) {
    guard let attachmentStore else {
      errorMessage = "첨부 저장소를 사용할 수 없습니다."
      return
    }

    let descriptor = FetchDescriptor<AttachmentEntity>(
      predicate: #Predicate { $0.id == attachmentID }
    )

    do {
      guard let attachment = try context.fetch(descriptor).first else { return }
      let url = try attachmentStore.resolve(attachment)
      try platformUIFoundation.documentOpener.open(url)
    } catch {
      reportError(error, logMessage: "openProjectDetailAttachment failed")
    }
  }

  func revealProjectDetailAttachment(_ attachmentID: UUID, context: ModelContext) {
    guard let attachmentStore else {
      errorMessage = "첨부 저장소를 사용할 수 없습니다."
      return
    }

    let descriptor = FetchDescriptor<AttachmentEntity>(
      predicate: #Predicate { $0.id == attachmentID }
    )

    do {
      guard let attachment = try context.fetch(descriptor).first else { return }
      let url = try attachmentStore.resolve(attachment)
      platformUIFoundation.documentOpener.revealInFiles([url])
    } catch {
      reportError(error, logMessage: "revealProjectDetailAttachment failed")
    }
  }

  func projectDetailAttachmentDragItemProvider(
    _ attachmentID: UUID,
    context: ModelContext
  ) -> NSItemProvider? {
    guard let attachmentStore else { return nil }

    let descriptor = FetchDescriptor<AttachmentEntity>(
      predicate: #Predicate { $0.id == attachmentID }
    )

    do {
      guard let attachment = try context.fetch(descriptor).first else { return nil }
      let sourceURL = try attachmentStore.resolve(attachment)
      let exportURL = try ApplePlatformDragBridge.shared.materializeFileExport(
        sourceURL: sourceURL,
        displayFilename: attachment.originalFilename,
        exportID: attachment.id
      )
      return NSItemProvider(object: exportURL as NSURL)
    } catch {
      return nil
    }
  }

  @discardableResult
  func deleteProjectDetailAttachment(_ attachmentID: UUID, context: ModelContext) -> Bool {
    let descriptor = FetchDescriptor<AttachmentEntity>(
      predicate: #Predicate { $0.id == attachmentID }
    )

    do {
      guard let attachment = try context.fetch(descriptor).first else { return false }
      let ownerProjectID: UUID?
      switch attachment.ownerType {
      case .project:
        ownerProjectID = attachment.ownerID
      case .task:
        ownerProjectID = resolvedOwnerProjectID(
          forTaskID: attachment.ownerID,
          context: context
        )
      }
      guard let ownerProjectID else {
        errorMessage = "첨부 저장소를 사용할 수 없습니다."
        return false
      }
      return applyProjectAttachmentMutation(
        .delete(attachmentID: attachmentID),
        ownerProjectID: ownerProjectID
      )
    } catch {
      reportError(error, logMessage: "deleteProjectDetailAttachment failed")
      return false
    }
  }

  @discardableResult
  func moveProjectDetailAttachment(
    _ attachmentID: UUID,
    to owner: AttachmentOwner,
    context: ModelContext
  ) -> Bool {
    let descriptor = FetchDescriptor<AttachmentEntity>(
      predicate: #Predicate { $0.id == attachmentID }
    )

    do {
      guard let attachment = try context.fetch(descriptor).first else { return false }

      let currentOwner: AttachmentOwner = attachment.ownerType == .project
        ? .project(attachment.ownerID)
        : .task(attachment.ownerID)
      guard currentOwner != owner else { return false }

      let ownerProjectID: UUID?
      switch currentOwner {
      case let .project(projectID):
        ownerProjectID = projectID
      case let .task(taskID):
        ownerProjectID = resolvedOwnerProjectID(forTaskID: taskID, context: context)
      }
      guard let ownerProjectID else {
        errorMessage = "첨부 저장소를 사용할 수 없습니다."
        return false
      }
      return applyProjectAttachmentMutation(
        .move(attachmentID: attachmentID, owner: owner),
        ownerProjectID: ownerProjectID
      )
    } catch {
      reportError(error, logMessage: "moveProjectDetailAttachment failed")
      return false
    }
  }

  @discardableResult
  func createProjectList(named rawTitle: String, context: ModelContext) async -> UUID? {
    guard let modelContainer else {
      errorMessage = ProjectDocumentStoreError.modelContainerUnavailable.localizedDescription
      return nil
    }
    _ = context

    do {
      let historyContext = ModelContext(modelContainer)
      let result = try await ProjectLifecycleService.createProject(
        title: rawTitle,
        reminderProjectProvider: reminderProjectProvider,
        workspaceTreeRepository: workspaceTreeRepository,
        historyContext: historyContext
      )
      guard let result else { return nil }
      _ = await writeProjectReminderBinding(
        projectID: result.projectID,
        reminderListIdentifier: result.reminderListIdentifier,
        reminderListExternalIdentifier: result.reminderListExternalIdentifier,
        waitForEditorIdle: false
      )
      let existingProjectIDs = cachedOutlinerRuntimeProjectionSnapshot?.projects.map(\.id) ?? []
      _ = await writeWorkspaceProjectOrder(existingProjectIDs + [result.projectID])
      if result.didMutateWorkspaceTree {
        bumpWorkspaceTreeRevision()
      }
      _ = await recomputeCachedRuntimeProjectionProjects([result.projectID])
      return result.projectID
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func recordTaskCompletionHistory(taskID: UUID, context: ModelContext) {
    guard let task = resolvedTaskRecord(forTaskID: taskID, context: context) else {
      return
    }
    guard let projectID = task.reminderOwnerProjectID else { return }
    ProjectHistoryService.recordTaskCompletionChange(
      projectID: projectID,
      taskID: taskID,
      taskTitle: task.title,
      isCompleted: task.isCompleted,
      completionDate: task.completionDate,
      localUpdatedAt: task.localUpdatedAt,
      in: context
    )
  }

  func moveTaskToProjectTop(_ taskID: UUID, targetProjectID: UUID, context: ModelContext) {
    Task { @MainActor in
      do {
        guard let sourceProjectID = resolvedOwnerProjectID(forTaskID: taskID, context: context) else {
          return
        }
        _ = try await dispatchProjectCommand(
          in: sourceProjectID,
          .moveTask(taskIDs: [taskID], targetProjectID: targetProjectID)
        )
      } catch {
        reportError(error, logMessage: "moveTaskToProjectTop failed")
      }
    }
  }

  @discardableResult
  func updateProjectColor(_ projectID: UUID, to colorHex: String?, context: ModelContext) async -> Bool {
    _ = context
    guard
      let reminderListIdentifier = normalizedProjectionValue(
        cachedOutlinerRuntimeProjectionSnapshot?.projectReminderListIdentifierByProjectID[projectID]
      )
    else {
      errorMessage = "프로젝트 목록 식별자를 찾지 못했습니다."
      return false
    }

    let didWrite = await send(
      .writeOwnerField(
        ownerStore: .reminder,
        write: .listMetadata(
          ReminderListMetadataWrite(
            projectID: projectID,
            reminderListIdentifier: reminderListIdentifier,
            reminderListExternalIdentifier: normalizedProjectionValue(
              cachedOutlinerRuntimeProjectionSnapshot?.projectReminderListExternalIdentifierByProjectID[
                projectID]
            ),
            mutation: .colorHex(colorHex)
          )
        )
      ),
      waitForEditorIdle: false
    )
    if !didWrite {
      errorMessage = "프로젝트 색상 저장에 실패했습니다."
    }
    return didWrite
  }

  func repairAllWorkspaceProjectIdentitiesIfNeeded(context: ModelContext) async {
    do {
      _ = context
      guard let cachedOutlinerRuntimeProjectionSnapshot else { return }
      let runtimeSnapshot = cachedOutlinerRuntimeProjectionSnapshot
      try await repairWorkspaceProjectIdentitiesIfNeeded(
        using: runtimeSnapshot,
        repository: workspaceTreeRepository
      )
    } catch {
      reportError(error, logMessage: "repairAllWorkspaceProjectIdentitiesIfNeeded failed")
    }
  }

  func repairWorkspaceProjectIdentityIfNeeded(projectID: UUID, context: ModelContext) async {
    do {
      _ = context
      guard let cachedOutlinerRuntimeProjectionSnapshot else { return }
      let runtimeSnapshot = cachedOutlinerRuntimeProjectionSnapshot
      guard runtimeSnapshot.projects.contains(where: { $0.id == projectID }) else { return }
      try await repairWorkspaceProjectIdentitiesIfNeeded(
        using: runtimeSnapshot,
        repository: workspaceTreeRepository
      )
    } catch {
      reportError(error, logMessage: "repairWorkspaceProjectIdentityIfNeeded failed")
    }
  }

  @discardableResult
  func writeProjectReminderBinding(
    projectID: UUID,
    reminderListIdentifier: String?,
    reminderListExternalIdentifier: String?,
    waitForEditorIdle: Bool = false
  ) async -> Bool {
    guard let reminderListExternalIdentifier else {
      return await send(
        .writeOwnerField(
          ownerStore: .sidecar,
          write: .removeReminderListBinding(projectID: projectID)
        ),
        waitForEditorIdle: waitForEditorIdle
      )
    }

    return await send(
      .writeOwnerField(
        ownerStore: .sidecar,
        write: .reminderListBinding(
          ProjectReminderConnectionWrite(
            projectID: projectID,
            reminderListIdentifier: reminderListIdentifier,
            reminderListExternalIdentifier: reminderListExternalIdentifier
          )
        )
      ),
      waitForEditorIdle: waitForEditorIdle
    )
  }

  @discardableResult
  func deleteProjectPermanently(_ projectID: UUID, context: ModelContext) async -> Bool {
    guard let modelContainer else {
      errorMessage = ProjectDocumentStoreError.modelContainerUnavailable.localizedDescription
      return false
    }
    _ = context

    do {
      let result = try await ProjectLifecycleService.deleteProject(
        projectID: projectID,
        runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
        modelContainer: modelContainer,
        reminderProjectProvider: reminderProjectProvider,
        archiveBundleStore: archivedProjectBundleStore(),
        mirrorPlacementStore: projectMirrorPlacementStore(),
        attachmentStore: attachmentStore,
        workspaceTreeRepository: workspaceTreeRepository
      )
      _ = await writeProjectReminderBinding(
        projectID: result.deletedProjectID,
        reminderListIdentifier: nil,
        reminderListExternalIdentifier: nil,
        waitForEditorIdle: false
      )
      if selectedProjectID == projectID {
        selectedProjectID = nil
      }
      discardProjectDocumentStore(for: projectID)
      try deletePromotedTaskArchives(for: result.deletedWorkspaceNodeIDs)
      if !result.deletedWorkspaceNodeIDs.isEmpty {
        bumpWorkspaceTreeRevision()
      }
      _ = await removeCachedRuntimeProjectionProjects([result.deletedProjectID])
      guard
        await removeProjectSidecars(
          projectID: result.deletedProjectID,
          reminderListExternalIdentifier: result.reminderListExternalIdentifier,
          reminderExternalIdentifiers: result.taskReminderExternalIdentifiers
        )
      else {
        errorMessage = "프로젝트 삭제 Sidecar 정리에 실패했습니다."
        return false
      }
      return true
    } catch {
      reportError(error, logMessage: "deleteProjectPermanently failed")
      return false
    }
  }

  func deleteTaskPermanently(_ taskID: UUID, context: ModelContext) async {
    do {
      _ = try await deleteTaskWithSidecarCleanup(taskID, context: context)
    } catch {
      reportError(error, logMessage: "deleteTaskPermanently failed")
    }
  }

  func deleteTaskPermanentlyWithUndoSnapshot(_ taskID: UUID, context: ModelContext) async throws
    -> TaskDeletionUndoSnapshot?
  {
    try await deleteTaskWithSidecarCleanup(taskID, context: context)
  }

  func restoreDeletedTaskFromUndo(_ snapshot: TaskDeletionUndoSnapshot, context: ModelContext) async throws {
    try await dispatchRestoreDeletedTaskFromUndoSnapshot(snapshot)
    _ = await recomputeCachedRuntimeProjectionProjects([snapshot.projectID])
  }

  private func deleteTaskWithSidecarCleanup(
    _ taskID: UUID,
    context: ModelContext
  ) async throws -> TaskDeletionUndoSnapshot? {
    guard let snapshot = try await dispatchDeleteTaskWithUndoSnapshot(taskID: taskID, context: context) else {
      return nil
    }

    guard await removeDeletedTaskSidecars(from: snapshot) else {
      do {
        try await dispatchRestoreDeletedTaskFromUndoSnapshot(snapshot)
      } catch {
        _ = await recomputeCachedRuntimeProjectionProjects([snapshot.projectID])
        throw ProjectDocumentStoreError.taskRestoreFailed(taskID)
      }
      _ = await recomputeCachedRuntimeProjectionProjects([snapshot.projectID])
      throw ProjectDocumentStoreError.taskDeleteCleanupFailed(taskID)
    }

    _ = await recomputeCachedRuntimeProjectionProjects([snapshot.projectID])
    return snapshot
  }

  private func removeDeletedTaskSidecars(from snapshot: TaskDeletionUndoSnapshot) async -> Bool {
    let reminderExternalIdentifiers = deletedTaskReminderExternalIdentifiers(in: snapshot.root)
    guard !reminderExternalIdentifiers.isEmpty else { return true }

    return await send(
      .writeOwnerField(
        ownerStore: .sidecar,
        write: .appSupplement(
          AppSupplementWrite(
            mutation: .removeDeletedTaskSidecars(
              projectID: snapshot.projectID,
              reminderExternalIdentifiers: reminderExternalIdentifiers
            )
          )
        )
      ),
      waitForEditorIdle: false
    )
  }

  private func removeProjectSidecars(
    projectID: UUID,
    reminderListExternalIdentifier: String,
    reminderExternalIdentifiers: [String]
  ) async -> Bool {
    await send(
      .writeOwnerField(
        ownerStore: .sidecar,
        write: .appSupplement(
          AppSupplementWrite(
            mutation: .removeProjectSidecars(
              projectID: projectID,
              reminderListExternalIdentifier: reminderListExternalIdentifier,
              reminderExternalIdentifiers: reminderExternalIdentifiers
            )
          )
        )
      ),
      waitForEditorIdle: false
    )
  }

  private func restoreArchivedProjectSidecars(
    from result: ProjectLifecycleRestoreResult
  ) async -> Bool {
    await send(
      .writeOwnerField(
        ownerStore: .sidecar,
        write: .appSupplement(
          AppSupplementWrite(
            mutation: .restoreArchivedProjectSidecars(
              projectID: result.restoredProjectID,
              reminderListExternalIdentifier: result.reminderListExternalIdentifier,
              archiveBundle: result.archiveBundle,
              restoredTaskIdentities: result.restoredTaskIdentities
            )
          )
        )
      ),
      waitForEditorIdle: false
    )
  }

  private func deletedTaskReminderExternalIdentifiers(
    in snapshot: TaskDeletionUndoNodeSnapshot
  ) -> [String] {
    var reminderExternalIdentifiers: [String] = []
    if let reminderExternalIdentifier = snapshot.task.reminderExternalIdentifier,
      !reminderExternalIdentifier.isEmpty
    {
      reminderExternalIdentifiers.append(reminderExternalIdentifier)
    }
    for child in snapshot.children {
      reminderExternalIdentifiers.append(
        contentsOf: deletedTaskReminderExternalIdentifiers(in: child)
      )
    }
    return Array(NSOrderedSet(array: reminderExternalIdentifiers)) as? [String]
      ?? reminderExternalIdentifiers
  }

  @discardableResult
  func archiveProject(_ id: UUID, context: ModelContext) async -> Bool {
    guard let modelContainer else {
      errorMessage = ProjectDocumentStoreError.modelContainerUnavailable.localizedDescription
      return false
    }
    _ = context

    do {
      let result = try await ProjectLifecycleService.archiveProject(
        projectID: id,
        runtimeSnapshot: cachedOutlinerRuntimeProjectionSnapshot,
        sidecarPayload: loadRuntimeProjectionSidecarPayload(),
        modelContainer: modelContainer,
        reminderProjectProvider: reminderProjectProvider,
        archiveBundleStore: archivedProjectBundleStore(),
        attachmentStore: attachmentStore,
        workspaceTreeRepository: workspaceTreeRepository
      )
      _ = await writeProjectReminderBinding(
        projectID: id,
        reminderListIdentifier: nil,
        reminderListExternalIdentifier: nil,
        waitForEditorIdle: false
      )
      handleArchivedProjectDocumentMutation(projectID: id)
      discardProjectDocumentStore(for: id)
      bumpWorkspaceTreeRevision()
      _ = await removeCachedRuntimeProjectionProjects([id])
      guard
        await removeProjectSidecars(
          projectID: result.archivedProjectID,
          reminderListExternalIdentifier: result.reminderListExternalIdentifier,
          reminderExternalIdentifiers: result.taskReminderExternalIdentifiers
        )
      else {
        errorMessage = "프로젝트 아카이브 Sidecar 정리에 실패했습니다."
        return false
      }
      return true
    } catch {
      reportError(error, logMessage: "archiveProject failed")
      return false
    }
  }

  @discardableResult
  func restoreProject(_ id: UUID, context: ModelContext) async -> UUID? {
    guard let modelContainer else {
      errorMessage = ProjectDocumentStoreError.modelContainerUnavailable.localizedDescription
      return nil
    }
    _ = context

    do {
      let result = try await ProjectLifecycleService.restoreProject(
        archivedProjectID: id,
        modelContainer: modelContainer,
        reminderProjectProvider: reminderProjectProvider,
        archiveBundleStore: archivedProjectBundleStore(),
        mirrorPlacementStore: projectMirrorPlacementStore(),
        attachmentStore: attachmentStore,
        workspaceTreeRepository: workspaceTreeRepository
      )
      _ = await writeProjectReminderBinding(
        projectID: result.restoredProjectID,
        reminderListIdentifier: result.reminderListIdentifier,
        reminderListExternalIdentifier: result.reminderListExternalIdentifier,
        waitForEditorIdle: false
      )
      guard await restoreArchivedProjectSidecars(from: result) else {
        errorMessage = "프로젝트 복원 Sidecar 정리에 실패했습니다."
        return nil
      }
      discardProjectDocumentStore(for: id)
      selectedProjectID = result.restoredProjectID
      bumpWorkspaceTreeRevision()
      _ = await recomputeCachedRuntimeProjectionProjects([result.restoredProjectID])
      return result.restoredProjectID
    } catch {
      reportError(error, logMessage: "restoreProject failed")
      return nil
    }
  }

  func importAttachment(owner: AttachmentOwner, context: ModelContext) {
    guard let attachmentStore else { return }
    Task { @MainActor in
      do {
        let urls = try await platformUIFoundation.pathPicker.pick(
          request: PlatformPathPickerRequest(
            kind: .files,
            message: "첨부할 파일을 선택해 주세요."
          )
        )
        guard let sourceURL = urls.first else { return }
        _ = try attachmentStore.import(from: sourceURL, owner: owner, in: context)
      } catch {
        reportError(error, logMessage: "importAttachment failed")
      }
    }
  }

  private func mergedSnapshotPreservingWorkspaceOverlay(_ snapshot: NormalizedSourceSnapshot) async throws
    -> NormalizedSourceSnapshot
  {
    try await WorkspaceOverlaySnapshotMerge.mergedSourceSnapshot(
      snapshot,
      workspaceTreeRepository: workspaceTreeRepository
    )
  }

  private func scheduleProjectDetailReorderPersistence(context: ModelContext) {
    pendingProjectDetailReorderPersistenceTask?.cancel()
    pendingProjectDetailReorderPersistenceTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled else { return }

      let didSave = self.saveContext(
        context,
        logMessage: "project detail reorder save failed"
      )
      _ = didSave

      self.pendingProjectDetailReorderPersistenceTask = nil
    }
  }

  private func explicitTimeMinutes(from date: Date?) -> Int? {
    guard let date else { return nil }
    let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
    let hasExplicitTime = (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0
    guard hasExplicitTime else { return nil }
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  private struct WorkspaceProjectIdentityRecord {
    let id: UUID
    let title: String
    let colorHex: String?
    let reminderListIdentifier: String
    let reminderListExternalIdentifier: String
  }

  private func repairWorkspaceProjectIdentitiesIfNeeded(
    using runtimeSnapshot: OutlineProjectionRuntimeSnapshot,
    repository: WorkspaceTreeRepository?
  ) async throws {
    guard let repository else { return }

    let projects = runtimeSnapshot.projects.compactMap { project -> WorkspaceProjectIdentityRecord? in
      guard
        let reminderListIdentifier = normalizedWorkspaceProjectIdentityValue(
          runtimeSnapshot.projectReminderListIdentifierByProjectID[project.id]
        ),
        let reminderListExternalIdentifier = normalizedWorkspaceProjectIdentityValue(
          runtimeSnapshot.projectReminderListExternalIdentifierByProjectID[project.id]
        )
      else {
        return nil
      }

      return WorkspaceProjectIdentityRecord(
        id: project.id,
        title: project.title,
        colorHex: runtimeSnapshot.projectColorHexByProjectID[project.id],
        reminderListIdentifier: reminderListIdentifier,
        reminderListExternalIdentifier: reminderListExternalIdentifier
      )
    }
    let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    guard !projectsByID.isEmpty else { return }
    let projectsByReminderListIdentifier = projects.reduce(into: [String: Set<UUID>]()) {
      partialResult, project in
      guard let key = normalizedWorkspaceProjectIdentityValue(project.reminderListIdentifier) else {
        return
      }
      partialResult[key, default: []].insert(project.id)
    }
    let projectsByReminderListExternalIdentifier = projects.reduce(into: [String: Set<UUID>]()) {
      partialResult, project in
      guard let key = normalizedWorkspaceProjectIdentityValue(project.reminderListExternalIdentifier)
      else {
        return
      }
      partialResult[key, default: []].insert(project.id)
    }

    let projectNodes = try await repository.projectNodes(includeArchived: true)
    var didRepairWorkspaceNode = false

    for node in projectNodes {
      guard
        let project = resolvedWorkspaceProject(
          for: node,
          projectsByID: projectsByID,
          projectsByReminderListIdentifier: projectsByReminderListIdentifier,
          projectsByReminderListExternalIdentifier: projectsByReminderListExternalIdentifier
        )
      else { continue }
      if workspaceProjectIdentityNeedsRepair(node: node, canonicalProject: project) {
        if node.projectID != project.id {
          _ = try await repository.relinkProjectIdentity(
            of: node.id,
            canonicalProjectID: project.id,
            title: project.title,
            colorHex: project.colorHex,
            reminderListIdentifier: project.reminderListIdentifier,
            reminderListExternalIdentifier: project.reminderListExternalIdentifier
          )
        } else {
          _ = try await repository.updateProjectIdentity(
            of: node.id,
            title: project.title,
            colorHex: project.colorHex,
            reminderListIdentifier: project.reminderListIdentifier,
            reminderListExternalIdentifier: project.reminderListExternalIdentifier
          )
        }
        didRepairWorkspaceNode = true
      }
    }

    guard didRepairWorkspaceNode else { return }
    bumpWorkspaceTreeRevision()
  }

  private func workspaceProjectIdentityNeedsRepair(
    node: WorkspaceNodeRecord,
    canonicalProject: WorkspaceProjectIdentityRecord
  ) -> Bool {
    node.projectID != canonicalProject.id
      || node.reminderListIdentifier != canonicalProject.reminderListIdentifier
      || node.reminderListExternalIdentifier != canonicalProject.reminderListExternalIdentifier
      || node.title != canonicalProject.title
      || node.colorHex != canonicalProject.colorHex
  }

  private func resolvedWorkspaceProject(
    for node: WorkspaceNodeRecord,
    projectsByID: [UUID: WorkspaceProjectIdentityRecord],
    projectsByReminderListIdentifier: [String: Set<UUID>],
    projectsByReminderListExternalIdentifier: [String: Set<UUID>]
  ) -> WorkspaceProjectIdentityRecord? {
    if let directProject = projectsByID[node.id] {
      return directProject
    }

    var matchedIDs = Set<UUID>()
    if let reminderListIdentifier = normalizedWorkspaceProjectIdentityValue(node.reminderListIdentifier),
      let projectIDs = projectsByReminderListIdentifier[reminderListIdentifier],
      projectIDs.count == 1
    {
      matchedIDs.formUnion(projectIDs)
    }
    if let reminderListExternalIdentifier = normalizedWorkspaceProjectIdentityValue(
      node.reminderListExternalIdentifier
    ), let projectIDs = projectsByReminderListExternalIdentifier[reminderListExternalIdentifier],
      projectIDs.count == 1
    {
      matchedIDs.formUnion(projectIDs)
    }

    guard matchedIDs.count == 1, let projectID = matchedIDs.first else { return nil }
    return projectsByID[projectID]
  }

  private func normalizedWorkspaceProjectIdentityValue(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private func promotedTaskArchiveDirectoryURL() throws -> URL {
    guard let paths = storageCoordinator.paths else {
      throw StorageError.noContainerConfigured
    }
    return paths.cacheDirectory
      .appendingPathComponent("promoted-task-archives", conformingTo: .directory)
  }

  private func deletePromotedTaskArchives(for nodeIDs: Set<UUID>) throws {
    guard !nodeIDs.isEmpty else { return }

    let directory = try promotedTaskArchiveDirectoryURL()
    let fileManager = FileManager.default
    for nodeID in nodeIDs {
      let fileURL = directory.appendingPathComponent(nodeID.uuidString).appendingPathExtension("json")
      guard fileManager.fileExists(atPath: fileURL.path) else { continue }
      try fileManager.removeItem(at: fileURL)
    }
  }
}
