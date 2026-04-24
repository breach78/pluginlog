import AppKit
import SwiftUI

extension MainWorkspaceView {
  func toggleSyncQuickAddPopover() {
    guard !syncQuickAddProjects.isEmpty else {
      appState.errorMessage = "할일을 추가할 기본 목록이 없습니다."
      return
    }
    chromeState.toggleSyncQuickAddPopover()
  }

  func dismissSyncQuickAddPopover() {
    chromeState.dismissSyncQuickAddPopover()

    DispatchQueue.main.async {
      guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
      window.endEditing(for: nil)
      window.makeFirstResponder(nil)
    }
  }

  func createSyncQuickAddTask(_ title: String, projectID: UUID) {
    guard activeQuickAddProjects.contains(where: { $0.id == projectID }) else {
      appState.errorMessage = "할일을 추가할 기본 목록이 없습니다."
      return
    }

    let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    Task { @MainActor in
      guard
        let createdTaskID = await appState.createTask(
          inProjectID: projectID,
          title: title,
          startDate: today,
          durationMinutes: nil,
          context: modelContext
        )
      else {
        return
      }
      appState.registerUndo(with: undoManager, actionName: "할일 생성") {
        deleteSyncQuickAddTask(createdTaskID, actionName: "할일 생성")
      }
      selectProjectContext(projectID)
      dismissSyncQuickAddPopover()
    }
  }

  func submitSidebarNewProject(_ rawTitle: String) {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isCreatingSidebarProject else { return }

    isCreatingSidebarProject = true
    Task { @MainActor in
      let createdProjectID = await appState.createProjectList(named: title, context: modelContext)
      isCreatingSidebarProject = false

      guard let createdProjectID else { return }

      let template =
        workspaceCreatedProjectUndoTemplate(for: createdProjectID)
        ?? CreatedProjectUndoTemplate(
          title: title,
          colorHex: nil,
          sortOrder: workspaceProjectDescriptors.filter { !$0.isArchived }.count
        )
      let snapshot = CreatedProjectUndoSnapshot(
        projectID: createdProjectID,
        template: template
      )
      appState.registerUndo(with: undoManager, actionName: "프로젝트 생성") {
        appState.undoCoordinator.performAsync {
          await self.undoSidebarCreatedProject(snapshot)
        }
      }

      showSidebarAddProjectPopover = false
      selectProjectContext(createdProjectID)
    }
  }

  private func undoSidebarCreatedProject(_ snapshot: CreatedProjectUndoSnapshot) async {
    let didDelete = await appState.deleteProjectPermanently(snapshot.projectID, context: modelContext)
    guard didDelete else { return }
    appState.registerUndo(with: undoManager, actionName: "프로젝트 생성") {
      appState.undoCoordinator.performAsync {
        await self.redoSidebarCreatedProject(snapshot.template)
      }
    }
  }

  private func redoSidebarCreatedProject(_ template: CreatedProjectUndoTemplate) async {
    guard let createdProjectID = await appState.createProjectList(
      named: template.title,
      context: modelContext
    ) else {
      return
    }

    let didWriteColor = await appState.updateProjectColor(
      createdProjectID,
      to: template.colorHex,
      context: modelContext
    )
    guard didWriteColor else { return }
    let didRestoreOrder = await restoreWorkspaceManualOrder(
      insertingProjectID: createdProjectID,
      sortOrder: template.sortOrder
    )
    guard didRestoreOrder else { return }

    let snapshot = CreatedProjectUndoSnapshot(projectID: createdProjectID, template: template)
    appState.registerUndo(with: undoManager, actionName: "프로젝트 생성") {
      appState.undoCoordinator.performAsync {
        await self.undoSidebarCreatedProject(snapshot)
      }
    }
  }

  private func deleteSyncQuickAddTask(_ taskID: UUID, actionName: String) {
    appState.undoCoordinator.performAsync {
      do {
        guard let snapshot = try await appState.deleteTaskPermanentlyWithUndoSnapshot(
          taskID,
          context: modelContext
        ) else {
          return
        }
        appState.registerUndo(with: undoManager, actionName: actionName) {
          restoreSyncQuickAddTask(snapshot, actionName: actionName)
        }
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  private func restoreSyncQuickAddTask(
    _ snapshot: TaskDeletionUndoSnapshot,
    actionName: String
  ) {
    appState.undoCoordinator.performAsync {
      do {
        try await appState.restoreDeletedTaskFromUndo(snapshot, context: modelContext)
        selectProjectContext(snapshot.projectID)
        appState.registerUndo(with: undoManager, actionName: actionName) {
          deleteSyncQuickAddTask(snapshot.task.id, actionName: actionName)
        }
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func dismissInspectorSelection() {
    inspectorSelection = nil
    selectProjectContext(nil)
  }

  func revealTimelineTaskDetail(taskID: UUID, projectID: UUID) {
    _ = taskID
    openProjectPage(for: projectID)
  }

  func completeTimelineTask(_ taskID: UUID, projectID: UUID) {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "task-completion")
    _ = taskID
    _ = projectID
  }

  private func updateTimelineTaskCompletion(
    taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    targetState: TaskItem.CompletionMutationSnapshot? = nil,
    registerUndo: Bool
  ) {
    guard let task = appState.resolvedTaskRecord(forTaskID: taskID, context: modelContext) else {
      return
    }

    let previousState = TaskItem.CompletionMutationSnapshot(
      isCompleted: task.isCompleted,
      completionDate: task.completionDate,
      startDate: task.startDate,
      dueDate: task.dueDate,
      scheduleHasExplicitTime: task.scheduleHasExplicitTime,
      scheduledDurationMinutes: task.scheduledDurationMinutes
    )
    let nextState =
      targetState
      ?? timelineCompletionMutationSnapshot(
        for: task,
        isCompleted: isCompleted,
        completionDate: completionDate
      )
    guard previousState != nextState else {
      return
    }
    Task { @MainActor in
      let resolvedCompletionDate: Date?
      if nextState.isCompleted,
        !(task.recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
      {
        resolvedCompletionDate =
          ReminderTaskDateCanonicalizer.unifiedDate(
            dueDate: task.dueDate,
            startDate: task.startDate
          )
          ?? nextState.completionDate
          ?? .now
      } else {
        resolvedCompletionDate = nextState.completionDate
      }

      let didWrite = await appState.saveProjectDetailTaskCompletion(
        taskID: taskID,
        isCompleted: nextState.isCompleted,
        completionDate: resolvedCompletionDate,
        context: modelContext
      )
      guard didWrite else { return }

      guard registerUndo else { return }
      appState.registerUndo(
        with: undoManager,
        actionName: nextState.isCompleted ? "할일 완료" : "할일 완료 취소"
      ) {
        self.updateTimelineTaskCompletion(
          taskID: taskID,
          projectID: projectID,
          isCompleted: previousState.isCompleted,
          completionDate: previousState.completionDate,
          targetState: previousState,
          registerUndo: true
        )
      }
    }
  }

  func completeTimelinePlannedWork(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date
  ) {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: "planned-work-progress")
    _ = taskID
    _ = projectID
    _ = targetCompletedUnits
    _ = completedOn
  }


  private func updateTimelinePlannedWorkProgress(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date,
    registerUndo: Bool
  ) {
    guard
      let task = appState.resolvedTaskRecord(forTaskID: taskID, context: modelContext),
      !task.isCompleted
    else {
      return
    }

    let normalizedTarget = max(0, min(targetCompletedUnits, max(0, task.requiredWorkDays)))
    let previousCompletedUnits = task.completedWorkUnits
    guard normalizedTarget != previousCompletedUnits else { return }

    Task { @MainActor in
      let didWrite = await appState.saveProjectDetailTaskPlannedWorkProgress(
        taskID: taskID,
        targetCompletedUnits: normalizedTarget,
        completedOn: completedOn,
        context: modelContext
      )
      guard didWrite else { return }

      guard registerUndo else { return }
      appState.registerUndo(with: undoManager, actionName: "예상 작업 체크") {
        self.updateTimelinePlannedWorkProgress(
          taskID: taskID,
          projectID: projectID,
          targetCompletedUnits: previousCompletedUnits,
          completedOn: completedOn,
          registerUndo: true
        )
      }
    }
  }

  private func timelineCompletionMutationSnapshot(
    for task: ProjectIdentityTaskRecord,
    isCompleted: Bool,
    completionDate: Date?,
    calendar: Calendar = .autoupdatingCurrent
  ) -> TaskItem.CompletionMutationSnapshot {
    let normalizedReminderDateStorage = ReminderTaskDateCanonicalizer.normalizedStorage(
      dueDate: task.dueDate,
      startDate: task.startDate
    )
    var snapshot = TaskItem.CompletionMutationSnapshot(
      isCompleted: task.isCompleted,
      completionDate: task.completionDate,
      startDate: normalizedReminderDateStorage.startDate,
      dueDate: normalizedReminderDateStorage.dueDate,
      scheduleHasExplicitTime: task.scheduleHasExplicitTime,
      scheduledDurationMinutes: task.scheduledDurationMinutes
    )
    snapshot.isCompleted = isCompleted
    snapshot.completionDate = isCompleted ? (completionDate ?? .now) : nil

    if isCompleted, task.recurrenceRuleRaw != nil, snapshot.scheduleHasExplicitTime {
      snapshot.clearExplicitTime(calendar: calendar)
    }

    return snapshot
  }

  func nonInspectorPassthroughRects(viewModePickerFrame: CGRect?) -> [CGRect] {
    var rects: [CGRect] = []
    if let viewModePickerFrame {
      rects.append(viewModePickerFrame)
    }
    return rects
  }

  func nonInspectorVisualExclusionRects(viewModePickerFrame: CGRect?) -> [CGRect] {
    []
  }

  func nonInspectorDimOverlay(
    visualExclusions: [CGRect],
    passthroughRects: [CGRect]
  ) -> some View {
    WorkspaceDismissOverlay(
      visualExclusionRects: visualExclusions,
      passthroughRects: passthroughRects
    ) {
      dismissWorkspaceSearchPanel()
      dismissInspectorSelection()
    }
  }

  func archiveProjectFromList(_ projectID: UUID) {
    if workspaceSelectionContainsProject(projectID) {
      dismissInspectorSelection()
    }
    Task { @MainActor in
      _ = await appState.archiveProject(projectID, context: modelContext)
    }
  }

  func performPermanentDelete(_ projectID: UUID) {
    if workspaceSelectionContainsProject(projectID) {
      dismissInspectorSelection()
    }

    Task { @MainActor in
      await appState.deleteProjectPermanently(projectID, context: modelContext)
    }
  }

  var pendingProjectDeleteDialogBinding: Binding<Bool> {
    Binding(
      get: { pendingPermanentDeleteProject != nil },
      set: { isPresented in
        if !isPresented {
          pendingPermanentDeleteProject = nil
        }
      }
    )
  }

  func moveProjects(from source: IndexSet, to destination: Int) {
    guard canInteractivelyReorderSidebarProjects else {
      return
    }

    guard appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    switch projectListSortMode {
    case .manual:
      let orderedProjectIDs = orderedVisibleProjectDescriptors.map(\.id)
      let snapshot = ProjectSortOrderUndoSnapshot(
        sortOrdersByProjectID: ProjectOrderMutationService.captureManualSortOrders(
          projectIDs: orderedProjectIDs
        )
      )
      var reorderedProjectIDs = orderedProjectIDs
      reorderedProjectIDs.move(fromOffsets: source, toOffset: destination)
      Task { @MainActor in
        let didWrite = await appState.writeWorkspaceProjectOrder(reorderedProjectIDs)
        guard didWrite else { return }
        appState.registerUndo(with: undoManager, actionName: "프로젝트 순서 변경") {
          self.applyProjectSortOrderUndoSnapshot(snapshot)
        }
      }
    case .bucketGrouped, .priority:
      guard let firstSourceIndex = source.first,
        orderedVisibleProjectDescriptors.indices.contains(firstSourceIndex)
      else {
        return
      }

      let orderedDescriptors = orderedVisibleProjectDescriptors
      let bucketStage = ProjectOrdering.bucketStage(for: orderedDescriptors[firstSourceIndex])
      let originalBucketIDs = orderedDescriptors
        .filter { ProjectOrdering.bucketStage(for: $0) == bucketStage }
        .map(\.id)
      guard
        let reorderedBucket = ProjectOrdering.reorderedBucketProjects(
          from: orderedDescriptors,
          moving: source,
          to: destination
        )
      else {
        return
      }

      let reorderedBucketIDs = reorderedBucket.map(\.id)
      guard reorderedBucketIDs != originalBucketIDs else {
        return
      }

      let snapshot = ProjectBucketOrderUndoSnapshot(
        boardOrdersByProjectID: Dictionary(
          uniqueKeysWithValues: workspaceProjectDescriptors.map {
            ($0.id, $0.boardOrder)
          }
        )
      )
      Task { @MainActor in
        let didWrite = await appState.writeProjectBucketOrder(projectIDsInOrder: reorderedBucketIDs)
        guard didWrite else { return }
        appState.registerUndo(with: undoManager, actionName: "프로젝트 묶음 순서 변경") {
          self.applyProjectBucketOrderUndoSnapshot(snapshot)
        }
      }
    case .recentlyModified:
      return
    }
  }

  func moveTaskToProjectFromSidebar(_ taskID: UUID, targetProjectID: UUID) {
    guard let sourceProjectID = appState.resolvedOwnerProjectID(forTaskID: taskID, context: modelContext) else {
      return
    }

    let movedTaskIDs = sidebarTaskSequenceDragUnit(taskID: taskID, sourceProjectID: sourceProjectID)
    let relatedProjectIDs = Array(Set([sourceProjectID, targetProjectID]))
    let snapshot = captureSidebarTaskProjectMoveSnapshot(
      movedTaskIDs: movedTaskIDs,
      relatedProjectIDs: relatedProjectIDs
    )

    Task { @MainActor in
      guard
        await appState.moveTaskSequence(
          taskIDs: movedTaskIDs,
          sourceProjectID: sourceProjectID,
          targetProjectID: targetProjectID
        )
      else {
        return
      }
      applySequenceAssignmentsAfterSidebarProjectMove(
        movedTaskIDs: movedTaskIDs,
        sourceProjectID: sourceProjectID,
        targetProjectID: targetProjectID
      )
      if let snapshot {
        appState.registerUndo(with: undoManager, actionName: "할일 이동") {
          self.restoreSidebarTaskProjectMove(snapshot, registerUndo: true)
        }
      }
      sidebarTaskDropTargetProjectID = nil
      selectProjectContext(targetProjectID)
    }
  }

  private func applyProjectSortOrderUndoSnapshot(_ snapshot: ProjectSortOrderUndoSnapshot) {
    let projectIDs = Set(snapshot.sortOrdersByProjectID.keys)
    let redoSnapshot = ProjectSortOrderUndoSnapshot(
      sortOrdersByProjectID: ProjectOrderMutationService.captureManualSortOrders(
        projectIDs: ProjectOrdering.ordered(
          workspaceProjectDescriptors.filter { projectIDs.contains($0.id) },
          mode: .manual
        ).map(\.id)
      )
    )
    let orderedProjectIDs = ProjectOrderMutationService.orderedProjectIDs(
      from: snapshot.sortOrdersByProjectID
    )
    Task { @MainActor in
      let didWrite = await appState.writeWorkspaceProjectOrder(orderedProjectIDs)
      guard didWrite else { return }
      appState.registerUndo(with: undoManager, actionName: "프로젝트 순서 변경") {
        self.applyProjectSortOrderUndoSnapshot(redoSnapshot)
      }
    }
  }

  private func applyProjectBucketOrderUndoSnapshot(_ snapshot: ProjectBucketOrderUndoSnapshot) {
    Task { @MainActor in
      let redoSnapshot = ProjectBucketOrderUndoSnapshot(
        boardOrdersByProjectID: Dictionary(
          uniqueKeysWithValues: workspaceProjectDescriptors
            .filter { snapshot.boardOrdersByProjectID.keys.contains($0.id) }
            .map { ($0.id, $0.boardOrder) }
        )
      )

      let didWrite = await appState.writeProjectBoardOrders(snapshot.boardOrdersByProjectID)
      guard didWrite else { return }
      appState.registerUndo(with: undoManager, actionName: "프로젝트 묶음 순서 변경") {
        self.applyProjectBucketOrderUndoSnapshot(redoSnapshot)
      }
    }
  }

  private func sidebarTaskSequenceDragUnit(taskID: UUID, sourceProjectID: UUID) -> [UUID] {
    let entries = sequentialEntries(in: sourceProjectID)
    let assignments = SequentialTaskService.loadAssignments(for: sourceProjectID)
    let presentation = SequentialTaskService.presentation(
      entries: entries,
      assignments: assignments
    )

    guard let segment = presentation.segmentsByTaskID[taskID], segment.leaderTaskID == taskID else {
      return [taskID]
    }
    return segment.taskIDs
  }

  private func captureSidebarTaskProjectMoveSnapshot(
    movedTaskIDs: [UUID],
    relatedProjectIDs: [UUID]
  ) -> TaskProjectMoveSnapshot? {
    var taskProjectIDs: [UUID: UUID] = [:]
    for taskID in movedTaskIDs {
      guard let projectID = appState.resolvedOwnerProjectID(forTaskID: taskID, context: modelContext) else {
        return nil
      }
      taskProjectIDs[taskID] = projectID
    }

    let involvedProjectIDs = Set(relatedProjectIDs).union(taskProjectIDs.values)
    var rootStructureByProjectID: [UUID: ReminderProjectRootStructureRecord] = [:]
    var sequenceAssignmentsByProjectID: [UUID: [UUID: String]] = [:]

    for projectID in involvedProjectIDs {
      guard let rootStructure = appState.projectRootStructureSnapshot(for: projectID) else {
        return nil
      }
      rootStructureByProjectID[projectID] = rootStructure
      sequenceAssignmentsByProjectID[projectID] = SequentialTaskService.loadAssignments(for: projectID)
    }

    return TaskProjectMoveSnapshot(
      movedTaskIDs: movedTaskIDs,
      taskProjectIDs: taskProjectIDs,
      rootStructureByProjectID: rootStructureByProjectID,
      sequenceAssignmentsByProjectID: sequenceAssignmentsByProjectID
    )
  }

  private func restoreSidebarTaskProjectMove(
    _ snapshot: TaskProjectMoveSnapshot,
    registerUndo: Bool
  ) {
    Task { @MainActor in
      let relatedProjectIDs = Array(snapshot.rootStructureByProjectID.keys)
      let redoSnapshot =
        registerUndo
        ? captureSidebarTaskProjectMoveSnapshot(
          movedTaskIDs: snapshot.movedTaskIDs,
          relatedProjectIDs: relatedProjectIDs
        )
        : nil

      let currentTaskProjectIDs = currentTaskProjectIDs(for: snapshot.movedTaskIDs)
      let tasksByCurrentProjectID = Dictionary(grouping: snapshot.movedTaskIDs) {
        currentTaskProjectIDs[$0]
      }

      var moveGroupsByProjectID: [UUID: [(targetProjectID: UUID, taskIDs: [UUID])]] = [:]
      for (currentProjectID, taskIDs) in tasksByCurrentProjectID {
        guard let currentProjectID else { continue }
        let taskIDsByTargetProjectID = Dictionary(grouping: taskIDs) {
          snapshot.taskProjectIDs[$0] ?? currentProjectID
        }
        for (targetProjectID, groupedTaskIDs) in taskIDsByTargetProjectID {
          moveGroupsByProjectID[currentProjectID, default: []].append(
            (targetProjectID: targetProjectID, taskIDs: groupedTaskIDs)
          )
        }
      }

      let batchedProjectIDs = Set(moveGroupsByProjectID.keys)
        .union(snapshot.rootStructureByProjectID.keys)
      for projectID in batchedProjectIDs {
        for moveGroup in moveGroupsByProjectID[projectID] ?? [] {
          guard
            await appState.moveTaskSequence(
              taskIDs: moveGroup.taskIDs,
              sourceProjectID: projectID,
              targetProjectID: moveGroup.targetProjectID
            )
          else {
            return
          }
        }

        if let rootStructure = snapshot.rootStructureByProjectID[projectID] {
          guard
            await appState.writeProjectRootStructure(
              projectID,
              rootNodes: rootStructure.rootNodes
            )
          else {
            return
          }
        }
      }

      for (projectID, assignments) in snapshot.sequenceAssignmentsByProjectID {
        SequentialTaskService.persistAssignments(assignments, for: projectID)
      }
      SequentialTaskService.postAssignmentsDidChange(
        projectIDs: Array(snapshot.sequenceAssignmentsByProjectID.keys)
      )

      guard registerUndo, let redoSnapshot else { return }
      appState.registerUndo(with: undoManager, actionName: "할일 이동") {
        self.restoreSidebarTaskProjectMove(redoSnapshot, registerUndo: true)
      }
    }
  }

  private func workspaceCreatedProjectUndoTemplate(for projectID: UUID) -> CreatedProjectUndoTemplate? {
    ReminderRuntimeProjectionReadModelService.workspaceCreatedProjectUndoTemplate(
      projectID: projectID,
      runtimeSnapshot: appState.cachedOutlinerRuntimeProjectionSnapshot,
      context: modelContext
    )
  }

  private func restoreWorkspaceManualOrder(
    insertingProjectID projectID: UUID,
    sortOrder: Int
  ) async -> Bool {
    let descriptors = ReminderRuntimeProjectionReadModelService.workspaceProjectDescriptors(
      runtimeSnapshot: appState.cachedOutlinerRuntimeProjectionSnapshot,
      context: modelContext
    )
    .filter { !$0.isArchived }
    var orderedProjectIDs = ProjectOrdering.ordered(descriptors, mode: .manual).map(\.id)
    orderedProjectIDs.removeAll { $0 == projectID }
    let insertionIndex = min(max(0, sortOrder), orderedProjectIDs.count)
    orderedProjectIDs.insert(projectID, at: insertionIndex)
    return await appState.writeWorkspaceProjectOrder(orderedProjectIDs)
  }

  private func workspaceScheduleEntries(
    for projectIDs: [UUID]
  ) -> [UUID: [ScheduleSliceEntry]] {
    ReminderRuntimeProjectionReadModelService.scheduleEntries(
      projectIDs: projectIDs,
      runtimeSnapshot: appState.cachedOutlinerRuntimeProjectionSnapshot,
      context: modelContext
    )
  }

  private func orderedVisibleRootScheduleEntries(in projectID: UUID) -> [ScheduleSliceEntry] {
    let entries = workspaceScheduleEntries(for: [projectID])[projectID] ?? []
    let allTaskIDs = Set(entries.map(\.taskID))
    return entries
      .filter { entry in
        guard let parentTaskID = entry.parentTaskID else { return true }
        return !allTaskIDs.contains(parentTaskID)
      }
      .sorted { lhs, rhs in
        if lhs.rowOrder != rhs.rowOrder {
          return lhs.rowOrder < rhs.rowOrder
        }
        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt < rhs.createdAt
        }
        return lhs.taskID.uuidString < rhs.taskID.uuidString
      }
  }

  private func orderedVisibleRootTaskIDs(in projectID: UUID) -> [UUID] {
    orderedVisibleRootScheduleEntries(in: projectID).map(\.taskID)
  }

  private func sequentialEntries(in projectID: UUID) -> [SequentialTaskEntry] {
    orderedVisibleRootScheduleEntries(in: projectID).map { entry in
      SequentialTaskEntry(id: entry.taskID, isCompleted: entry.isCompleted)
    }
  }

  private func applySequenceAssignmentsAfterSidebarProjectMove(
    movedTaskIDs: [UUID],
    sourceProjectID: UUID,
    targetProjectID: UUID
  ) {
    if sourceProjectID == targetProjectID {
      let normalized = SequentialTaskService.normalizedAssignments(
        entries: sequentialEntries(in: sourceProjectID),
        assignments: SequentialTaskService.loadAssignments(for: sourceProjectID)
      )
      SequentialTaskService.persistAssignments(normalized, for: sourceProjectID)
      SequentialTaskService.postAssignmentsDidChange(projectIDs: [sourceProjectID])
      return
    }

    var sourceAssignments = SequentialTaskService.loadAssignments(for: sourceProjectID)
    for taskID in movedTaskIDs {
      sourceAssignments.removeValue(forKey: taskID)
    }
    let normalizedSource = SequentialTaskService.normalizedAssignments(
      entries: sequentialEntries(in: sourceProjectID),
      assignments: sourceAssignments
    )
    SequentialTaskService.persistAssignments(normalizedSource, for: sourceProjectID)

    var targetAssignments = SequentialTaskService.loadAssignments(for: targetProjectID)
    if movedTaskIDs.count >= 2 {
      let groupID = UUID().uuidString
      for taskID in movedTaskIDs {
        targetAssignments[taskID] = groupID
      }
    } else {
      for taskID in movedTaskIDs {
        targetAssignments.removeValue(forKey: taskID)
      }
    }

    let normalizedTarget = SequentialTaskService.normalizedAssignments(
      entries: sequentialEntries(in: targetProjectID),
      assignments: targetAssignments
    )
    SequentialTaskService.persistAssignments(normalizedTarget, for: targetProjectID)
    SequentialTaskService.postAssignmentsDidChange(projectIDs: [sourceProjectID, targetProjectID])
  }

  private func currentTaskProjectIDs(for taskIDs: [UUID]) -> [UUID: UUID] {
    let trackedTaskIDs = Set(taskIDs)
    guard !trackedTaskIDs.isEmpty else { return [:] }

    let scheduleEntriesByProjectID = workspaceScheduleEntries(for: workspaceProjectDescriptors.map(\.id))
    var taskProjectIDs: [UUID: UUID] = [:]
    for (projectID, entries) in scheduleEntriesByProjectID {
      for entry in entries where trackedTaskIDs.contains(entry.taskID) {
        taskProjectIDs[entry.taskID] = projectID
      }
    }
    return taskProjectIDs
  }

  private func toggleProjectListSortMode() {
    projectListSortMode = projectListSortMode.nextSidebar
  }

  func installLocalKeyMonitor() {
    removeLocalKeyMonitor()

    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handleKeyDown(event)
    }
  }

  func removeLocalKeyMonitor() {
    guard let localKeyMonitor else { return }
    NSEvent.removeMonitor(localKeyMonitor)
    self.localKeyMonitor = nil
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if shouldFocusWorkspaceSearch(for: event) {
      focusWorkspaceSearch()
      return nil
    }

    guard event.keyCode == 53 else { return event }
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return event }

    if dismissActiveSearchState(in: window) {
      return nil
    }

    if inspectorSelection != nil, appState.consumeWorkspaceProjectDetailEscape() {
      return nil
    }

    if hasVisiblePopoverWindow() {
      return event
    }

    if isEditingText(in: window) {
      NotificationCenter.default.post(name: .reminderAppEditingEscapePressed, object: nil)
      window.endEditing(for: nil)
      window.makeFirstResponder(nil)
      return nil
    }

    if inspectorSelection != nil {
      dismissInspectorSelection()
      return nil
    }

    if shouldSuppressFullscreenEscape(in: window) {
      return nil
    }

    return event
  }

  private func shouldFocusWorkspaceSearch(for event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags == .command else { return false }
    return event.charactersIgnoringModifiers?.lowercased() == "f"
  }

  private func dismissActiveSearchState(in window: NSWindow) -> Bool {
    let hasWorkspaceSearchQuery =
      !chromeState.workspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if chromeState.workspaceSearchFocused || hasWorkspaceSearchQuery {
      clearWorkspaceSearch()
      chromeState.dismissWorkspaceSearch()
      if isWorkspaceSearchFirstResponder(in: window) {
        window.endEditing(for: nil)
        window.makeFirstResponder(nil)
      }
      return true
    }

    let hasProjectFilterQuery =
      !appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if hasProjectFilterQuery {
      appState.clearSearchText()
      if isEditingText(in: window) {
        window.endEditing(for: nil)
        window.makeFirstResponder(nil)
      }
      return true
    }

    return false
  }

  private func shouldSuppressFullscreenEscape(in window: NSWindow) -> Bool {
    window.styleMask.contains(.fullScreen)
  }

  private func isEditingText(in window: NSWindow) -> Bool {
    guard let responder = window.firstResponder else { return false }

    if responder is NSTextView {
      return true
    }

    if let control = responder as? NSControl {
      return control.currentEditor() != nil
    }

    if let view = responder as? NSView {
      if view is NSTextField || view is NSSearchField {
        return true
      }
      if let control = view as? NSControl {
        return control.currentEditor() != nil
      }
    }

    return false
  }

  func presentInitialSyncAlertIfNeeded() {
    guard appState.shouldPromptForInitialSyncConsent else { return }

    showInitialSyncAlert = true
  }

  private func hasVisiblePopoverWindow() -> Bool {
    NSApp.windows.contains { window in
      guard window.isVisible else { return false }
      return String(describing: type(of: window)).localizedCaseInsensitiveContains("popover")
    }
  }
}
