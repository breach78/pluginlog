import AppKit
import SwiftData
import SwiftUI

extension TimelineBoardView {
  func allowTimelineMutation(_ feature: String) -> Bool {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.timeline, feature: feature)
    return false
  }

  func submitNewProject(_ rawTitle: String) {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    guard !isCreatingProject else { return }
    guard allowTimelineMutation("create-project") else { return }

    isCreatingProject = true
    Task { @MainActor in
      let createdProjectID = await appState.createProjectList(named: title, context: modelContext)
      isCreatingProject = false

      guard let createdProjectID else { return }
      let template =
        timelineCreatedProjectUndoTemplate(for: createdProjectID)
        ?? TimelineCreatedProjectUndoTemplate(title: title, colorHex: nil)
      let snapshot = TimelineCreatedProjectUndoSnapshot(
        projectID: createdProjectID,
        template: template
      )

      appState.registerUndo(with: undoManager, actionName: "프로젝트 생성") {
        appState.undoCoordinator.performAsync {
          await self.undoCreatedProject(snapshot)
        }
      }

      showAddProjectPopover = false
      appState.selectedProjectID = createdProjectID
      await refreshTimelineProjectState(including: [createdProjectID])
      onSelectProject(createdProjectID)
    }
  }

  private func undoCreatedProject(_ snapshot: TimelineCreatedProjectUndoSnapshot) async {
    let didDelete = await appState.deleteProjectPermanently(snapshot.projectID, context: modelContext)
    guard didDelete else { return }
    await refreshTimelineProjectState(excluding: [snapshot.projectID])
    appState.registerUndo(with: undoManager, actionName: "프로젝트 생성") {
      appState.undoCoordinator.performAsync {
        await self.redoCreatedProject(snapshot.template)
      }
    }
  }

  private func redoCreatedProject(_ template: TimelineCreatedProjectUndoTemplate) async {
    guard let createdProjectID = await appState.createProjectList(
      named: template.title,
      context: modelContext
    ) else {
      return
    }

    if let colorHex = template.colorHex {
      let didWriteColor = await appState.updateProjectColor(
        createdProjectID,
        to: colorHex,
        context: modelContext
      )
      guard didWriteColor else { return }
    }
    await refreshTimelineProjectState(including: [createdProjectID])

    let snapshot = TimelineCreatedProjectUndoSnapshot(
      projectID: createdProjectID,
      template: template
    )
    appState.registerUndo(with: undoManager, actionName: "프로젝트 생성") {
      appState.undoCoordinator.performAsync {
        await self.undoCreatedProject(snapshot)
      }
    }
  }

  func openScheduleDay(for offset: Int) {
    cancelTimelineDayHeaderOverlay()
    appState.jumpSchedule(to: date(for: offset))
  }

  func revealTimelineTaskDetail(taskID: UUID, projectID: UUID) {
    _ = taskID
    appState.selectedProjectID = projectID
    onSelectProject(projectID)
    cancelTimelineTaskBadgeOverlay()
    cancelTimelineDayHeaderOverlay()
  }

  func completeTimelineTask(_ taskID: UUID, projectID: UUID) {
    updateTimelineTaskCompletion(
      taskID: taskID,
      projectID: projectID,
      isCompleted: true,
      completionDate: .now,
      targetState: nil,
      registerUndo: true
    )
  }

  private func updateTimelineTaskCompletion(
    taskID: UUID,
    projectID: UUID,
    isCompleted: Bool,
    completionDate: Date?,
    targetState: TimelineTaskCompletionUndoSnapshot?,
    registerUndo: Bool
  ) {
    guard let previousState = timelineTaskCompletionState(taskID: taskID, projectID: projectID) else {
      return
    }

    let nextState =
      targetState
      ?? TimelineTaskCompletionUndoSnapshot(
        taskID: taskID,
        projectID: projectID,
        isCompleted: isCompleted,
        completionDate: isCompleted ? (completionDate ?? .now) : nil,
        isRecurring: previousState.isRecurring,
        occurrenceDate: previousState.occurrenceDate
      )
    guard previousState != nextState else { return }
    guard allowTimelineMutation("task-completion") else { return }

    Task { @MainActor in
      let didWrite = await appState.saveProjectDetailTaskCompletion(
        taskID: taskID,
        isCompleted: nextState.isCompleted,
        completionDate: nextState.isCompleted && nextState.isRecurring
          ? (nextState.occurrenceDate ?? nextState.completionDate)
          : nextState.completionDate,
        context: modelContext
      )
      guard didWrite else { return }
      await refreshTimelineProjectState(including: [projectID])

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
    updateTimelinePlannedWorkProgress(
      taskID: taskID,
      projectID: projectID,
      targetCompletedUnits: targetCompletedUnits,
      completedOn: completedOn,
      targetState: nil,
      registerUndo: true
    )
  }

  private func updateTimelinePlannedWorkProgress(
    taskID: UUID,
    projectID: UUID,
    targetCompletedUnits: Int,
    completedOn: Date,
    targetState: TimelinePlannedWorkUndoSnapshot?,
    registerUndo: Bool
  ) {
    guard let currentEntry = scheduleEntry(taskID: taskID, projectID: projectID) else {
      return
    }

    let previousState = TimelinePlannedWorkUndoSnapshot(
      taskID: taskID,
      projectID: projectID,
      completedUnits: currentEntry.completedWorkUnits,
      completedOn: completedOn
    )
    let normalizedTarget = max(0, min(targetCompletedUnits, currentEntry.requiredWorkDays))
    let nextState =
      targetState
      ?? TimelinePlannedWorkUndoSnapshot(
        taskID: taskID,
        projectID: projectID,
        completedUnits: normalizedTarget,
        completedOn: completedOn
      )
    guard previousState != nextState else { return }
    guard allowTimelineMutation("planned-work-progress") else { return }

    Task { @MainActor in
      let didWrite = await appState.saveProjectDetailTaskPlannedWorkProgress(
        taskID: taskID,
        targetCompletedUnits: nextState.completedUnits,
        completedOn: nextState.completedOn,
        context: modelContext
      )
      guard didWrite else { return }
      await refreshTimelineProjectState(including: [projectID])

      guard registerUndo else { return }
      appState.registerUndo(with: undoManager, actionName: "예상 작업 체크") {
        self.updateTimelinePlannedWorkProgress(
          taskID: taskID,
          projectID: projectID,
          targetCompletedUnits: previousState.completedUnits,
          completedOn: previousState.completedOn,
          targetState: previousState,
          registerUndo: true
        )
      }
    }
  }

  func archiveProjectFromTimeline(_ projectID: UUID) {
    guard allowTimelineMutation("archive-project") else { return }

    Task { @MainActor in
      let didArchive = await appState.archiveProject(projectID, context: modelContext)
      guard didArchive else { return }
      await refreshTimelineProjectState(excluding: [projectID])
    }
  }

  func updateTimelineProjectColor(projectID: UUID, hex: String) {
    let previousColorHex = workspaceTimelineProjectSnapshots[projectID]?.colorHex
    let snapshot = ProjectColorUndoSnapshot(projectID: projectID, colorHex: previousColorHex)
    guard allowTimelineMutation("project-color") else { return }

    Task { @MainActor in
      let didWrite = await appState.updateProjectColor(projectID, to: hex, context: modelContext)
      guard didWrite else { return }

      await refreshTimelineProjectState(including: [projectID])
      appState.registerUndo(with: undoManager, actionName: "프로젝트 색상 변경") {
        self.applyProjectColorUndoSnapshot(snapshot)
      }
    }
  }

  private func applyProjectColorUndoSnapshot(_ snapshot: ProjectColorUndoSnapshot) {
    let redoSnapshot = ProjectColorUndoSnapshot(
      projectID: snapshot.projectID,
      colorHex: workspaceTimelineProjectSnapshots[snapshot.projectID]?.colorHex
    )

    Task { @MainActor in
      let didWrite = await appState.updateProjectColor(
        snapshot.projectID,
        to: snapshot.colorHex,
        context: modelContext
      )
      guard didWrite else { return }

      await refreshTimelineProjectState(including: [snapshot.projectID])
      appState.registerUndo(with: undoManager, actionName: "프로젝트 색상 변경") {
        self.applyProjectColorUndoSnapshot(redoSnapshot)
      }
    }
  }

  func updateTimelineProjectStage(
    projectID: UUID,
    stage: ProjectProgressStage,
    registerUndo: Bool = true
  ) {
    let currentStage = timelineProjectStage(for: projectID)
    guard currentStage != stage else { return }
    guard allowTimelineMutation("project-stage") else { return }

    Task { @MainActor in
      guard await appState.writeProjectStage(projectID, stage: stage) else { return }
      await refreshTimelineProjectState(including: [projectID])

      guard registerUndo else { return }
      appState.registerUndo(with: undoManager, actionName: "분류 변경") {
        self.updateTimelineProjectStage(
          projectID: projectID,
          stage: currentStage,
          registerUndo: true
        )
      }
    }
  }

  func colorSwatchMenuImage(hex: String, selected: Bool) -> NSImage {
    let size = NSSize(width: 12, height: 12)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let color = ColorHexCodec.nsColor(from: hex) ?? .gray
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
    let path = NSBezierPath(ovalIn: rect)
    color.setFill()
    path.fill()

    let strokeColor = selected ? NSColor.white : NSColor.black.withAlphaComponent(0.22)
    strokeColor.setStroke()
    path.lineWidth = selected ? 1.8 : 1
    path.stroke()

    image.isTemplate = false
    return image
  }

  func requestPermanentDelete(for bar: TimelineProjectBar) {
    guard allowTimelineMutation("delete-project") else { return }

    pendingDeleteProjectID = bar.projectID
    pendingDeleteProjectTitle = bar.title
  }

  func performPermanentDelete(_ projectID: UUID) {
    guard allowTimelineMutation("delete-project") else { return }

    Task { @MainActor in
      let didDelete = await appState.deleteProjectPermanently(projectID, context: modelContext)
      guard didDelete else { return }
      await refreshTimelineProjectState(excluding: [projectID])
    }
  }

  func moveTaskToProjectTop(taskID: UUID, targetProjectID: UUID) {
    guard let sourceProjectID = taskProjectID(for: taskID) else { return }
    guard allowTimelineMutation("move-task") else { return }

    let movedTaskIDs = taskSequenceDragUnit(taskID: taskID, sourceProjectID: sourceProjectID)
    let relatedProjectIDs = Array(Set([sourceProjectID, targetProjectID]))
    guard
      let snapshot = captureTaskProjectMoveSnapshot(
        movedTaskIDs: movedTaskIDs,
        relatedProjectIDs: relatedProjectIDs
      )
    else {
      return
    }

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
      await refreshTimelineProjectState(including: relatedProjectIDs)
      applySequenceAssignmentsAfterProjectMove(
        movedTaskIDs: movedTaskIDs,
        sourceProjectID: sourceProjectID,
        targetProjectID: targetProjectID
      )
      appState.registerUndo(with: undoManager, actionName: "할일 이동") {
        self.restoreTaskProjectMove(snapshot, registerUndo: true)
      }
    }
  }

  private func taskSequenceDragUnit(taskID: UUID, sourceProjectID: UUID) -> [UUID] {
    let entries = sequentialEntries(in: sourceProjectID)
    let assignments = SequentialTaskService.loadAssignments(for: sourceProjectID)
    let presentation = SequentialTaskService.presentation(entries: entries, assignments: assignments)

    guard let segment = presentation.segmentsByTaskID[taskID], segment.leaderTaskID == taskID else {
      return [taskID]
    }
    return segment.taskIDs
  }

  private func captureTaskProjectMoveSnapshot(
    movedTaskIDs: [UUID],
    relatedProjectIDs: [UUID]
  ) -> TaskProjectMoveSnapshot? {
    var taskProjectIDs: [UUID: UUID] = [:]
    for taskID in movedTaskIDs {
      guard let projectID = taskProjectID(for: taskID) else { return nil }
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

  private func applySequenceAssignmentsAfterProjectMove(
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

  private func restoreTaskProjectMove(
    _ snapshot: TaskProjectMoveSnapshot,
    registerUndo: Bool
  ) {
    Task { @MainActor in
      let relatedProjectIDs = Array(snapshot.rootStructureByProjectID.keys)
      let redoSnapshot =
        registerUndo
        ? captureTaskProjectMoveSnapshot(
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

      await refreshTimelineProjectState(including: relatedProjectIDs)

      for (projectID, assignments) in snapshot.sequenceAssignmentsByProjectID {
        SequentialTaskService.persistAssignments(assignments, for: projectID)
      }
      SequentialTaskService.postAssignmentsDidChange(
        projectIDs: Array(snapshot.sequenceAssignmentsByProjectID.keys)
      )

      guard registerUndo, let redoSnapshot else { return }
      appState.registerUndo(with: undoManager, actionName: "할일 이동") {
        self.restoreTaskProjectMove(redoSnapshot, registerUndo: true)
      }
    }
  }

  var pendingTimelineDeleteDialogBinding: Binding<Bool> {
    Binding(
      get: { pendingDeleteProjectID != nil },
      set: { isPresented in
        if !isPresented {
          pendingDeleteProjectID = nil
          pendingDeleteProjectTitle = ""
        }
      }
    )
  }

  func reorderProjects(
    draggedID: UUID,
    targetID: UUID,
    placement: TimelineProjectDropPlacement
  ) {
    defer { clearProjectDragFeedback() }
    guard projectListSortMode.allowsInteractiveReordering else { return }
    guard draggedID != targetID else { return }
    guard allowTimelineMutation("reorder-projects") else { return }

    let orderedBars = timelineBoardSnapshot.bars
    let orderedProjectIDs = orderedBars.map { $0.projectID }

    switch projectListSortMode {
    case .manual:
      guard
        let reorderedProjectIDs = reorderedProjectIDs(
          from: orderedProjectIDs,
          draggedID: draggedID,
          targetID: targetID,
          placeAfter: placement == .after
        ),
        reorderedProjectIDs != orderedProjectIDs
      else {
        return
      }

      let snapshot = TimelineProjectSortOrderUndoSnapshot(
        sortOrdersByProjectID: ProjectOrderMutationService.captureManualSortOrders(
          projectIDs: orderedProjectIDs
        )
      )
      Task { @MainActor in
        let didWrite = await appState.writeWorkspaceProjectOrder(reorderedProjectIDs)
        guard didWrite else { return }
        appState.registerUndo(with: undoManager, actionName: "프로젝트 순서 변경") {
          self.applyTimelineProjectSortOrderUndoSnapshot(snapshot)
        }
      }

    case .bucketGrouped, .priority:
      let stagesByProjectID = Dictionary(
        uniqueKeysWithValues: orderedBars.map { ($0.projectID, priorityStage(for: $0)) }
      )
      guard
        let sourceStage = stagesByProjectID[draggedID],
        let targetStage = stagesByProjectID[targetID]
      else {
        return
      }

      let snapshot = captureTimelineProjectBucketOrderUndoSnapshot(from: orderedBars)

      if sourceStage != targetStage {
        let sourceBucketIDs = orderedBars
          .filter { $0.projectID != draggedID && stagesByProjectID[$0.projectID] == sourceStage }
          .map { $0.projectID }
        var targetBucketIDs = orderedBars
          .filter { $0.projectID != draggedID && stagesByProjectID[$0.projectID] == targetStage }
          .map { $0.projectID }
        guard let targetIndex = targetBucketIDs.firstIndex(of: targetID) else { return }

        let insertionIndex = min(
          max(0, placement == .before ? targetIndex : targetIndex + 1),
          targetBucketIDs.count
        )
        targetBucketIDs.insert(draggedID, at: insertionIndex)

        Task { @MainActor in
          let didWriteSourceBucket = await appState.writeProjectBucketOrder(
            projectIDsInOrder: sourceBucketIDs
          )
          guard didWriteSourceBucket else { return }
          guard await appState.writeProjectStage(draggedID, stage: targetStage) else { return }
          let didWriteTargetBucket = await appState.writeProjectBucketOrder(
            projectIDsInOrder: targetBucketIDs
          )
          guard didWriteTargetBucket else { return }
          await refreshTimelineProjectState(including: [draggedID])
          appState.registerUndo(with: undoManager, actionName: "프로젝트 묶음 순서 변경") {
            self.applyTimelineProjectBucketOrderUndoSnapshot(snapshot)
          }
        }
        return
      }

      let bucketIDs = orderedBars
        .filter { stagesByProjectID[$0.projectID] == sourceStage }
        .map { $0.projectID }
      guard
        let reorderedBucketIDs = reorderedProjectIDs(
          from: bucketIDs,
          draggedID: draggedID,
          targetID: targetID,
          placeAfter: placement == .after
        ),
        reorderedBucketIDs != bucketIDs
      else {
        return
      }

      Task { @MainActor in
        let didWrite = await appState.writeProjectBucketOrder(projectIDsInOrder: reorderedBucketIDs)
        guard didWrite else { return }
        appState.registerUndo(with: undoManager, actionName: "프로젝트 묶음 순서 변경") {
          self.applyTimelineProjectBucketOrderUndoSnapshot(snapshot)
        }
      }

    case .recentlyModified:
      return
    }
  }

  private func applyTimelineProjectSortOrderUndoSnapshot(
    _ snapshot: TimelineProjectSortOrderUndoSnapshot
  ) {
    let trackedProjectIDs = Set(snapshot.sortOrdersByProjectID.keys)
    let redoSnapshot = TimelineProjectSortOrderUndoSnapshot(
      sortOrdersByProjectID: ProjectOrderMutationService.captureManualSortOrders(
        projectIDs: timelineBoardSnapshot.bars.map(\.projectID).filter { trackedProjectIDs.contains($0) }
      )
    )
    let orderedProjectIDs = ProjectOrderMutationService.orderedProjectIDs(
      from: snapshot.sortOrdersByProjectID
    )
    Task { @MainActor in
      let didWrite = await appState.writeWorkspaceProjectOrder(orderedProjectIDs)
      guard didWrite else { return }
      appState.registerUndo(with: undoManager, actionName: "프로젝트 순서 변경") {
        self.applyTimelineProjectSortOrderUndoSnapshot(redoSnapshot)
      }
    }
  }

  private func applyTimelineProjectBucketOrderUndoSnapshot(
    _ snapshot: TimelineProjectBucketOrderUndoSnapshot
  ) {
    Task { @MainActor in
      let redoSnapshot = captureTimelineProjectBucketOrderUndoSnapshot(from: timelineBoardSnapshot.bars)

      for (projectID, stage) in snapshot.stagesByProjectID {
        let currentStage = timelineProjectStage(for: projectID)
        guard currentStage != stage else { continue }
        guard await appState.writeProjectStage(projectID, stage: stage) else { return }
      }
      let didWrite = await appState.writeProjectBoardOrders(snapshot.boardOrdersByProjectID)
      guard didWrite else { return }
      await refreshTimelineProjectState(including: Array(snapshot.stagesByProjectID.keys))
      appState.registerUndo(with: undoManager, actionName: "프로젝트 묶음 순서 변경") {
        self.applyTimelineProjectBucketOrderUndoSnapshot(redoSnapshot)
      }
    }
  }

  private func clearProjectDragFeedback() {
    draggingProjectID = nil
    projectDropIndicator = nil
    taskDropTargetProjectID = nil
  }

  private func refreshTimelineProjectState(
    including additionalProjectIDs: [UUID] = [],
    excluding excludedProjectIDs: [UUID] = []
  ) async {
    let excluded = Set(excludedProjectIDs)
    let requestedProjectIDs = TimelineBoardReadPath.normalizedProjectIDs(
      (activeProjectIDs + additionalProjectIDs).filter { !excluded.contains($0) }
    )
    await reloadWorkspaceTimelineProjectDetails(for: requestedProjectIDs)
  }

  private func timelineCreatedProjectUndoTemplate(
    for projectID: UUID
  ) -> TimelineCreatedProjectUndoTemplate? {
    ReminderRuntimeProjectionReadModelService.createdProjectUndoTemplate(
      projectID: projectID,
      runtimeSnapshot: appState.cachedOutlinerRuntimeProjectionSnapshot
    )
  }

  private func timelineTaskCompletionState(
    taskID: UUID,
    projectID: UUID
  ) -> TimelineTaskCompletionUndoSnapshot? {
    guard let entry = scheduleEntry(taskID: taskID, projectID: projectID) else { return nil }
    return TimelineTaskCompletionUndoSnapshot(
      taskID: taskID,
      projectID: projectID,
      isCompleted: entry.isCompleted,
      completionDate: entry.completionDate,
      isRecurring: !(entry.recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
      occurrenceDate: ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: entry.dueDate,
        startDate: entry.startDate,
        displayedDate: entry.displayedDate
      )
    )
  }

  private func scheduleEntry(taskID: UUID, projectID: UUID) -> ScheduleSliceEntry? {
    workspaceTimelineScheduleEntriesByProjectID[projectID]?.first(where: { $0.taskID == taskID })
  }

  private func timelineProjectStage(for projectID: UUID) -> ProjectProgressStage {
    if
      let stageRaw = workspaceTimelineProjectSummaries[projectID]?.stageRaw,
      let stageValue = Int(stageRaw),
      let stage = ProjectProgressStage(rawValue: stageValue)
    {
      return stage
    }

    if
      let stageRaw = workspaceTimelineProjectSnapshots[projectID]?.progressStageRaw,
      let stageValue = Int(stageRaw),
      let stage = ProjectProgressStage(rawValue: stageValue)
    {
      return stage
    }

    if let bar = timelineBoardSnapshot.bars.first(where: { $0.projectID == projectID }) {
      return ProjectProgressStage.from(progress: bar.progress)
    }

    return .do
  }

  private func taskProjectID(for taskID: UUID) -> UUID? {
    for (projectID, entries) in workspaceTimelineScheduleEntriesByProjectID {
      if entries.contains(where: { $0.taskID == taskID }) {
        return projectID
      }
    }
    return nil
  }

  private func currentTaskProjectIDs(for taskIDs: [UUID]) -> [UUID: UUID] {
    Dictionary(uniqueKeysWithValues: taskIDs.compactMap { taskID in
      taskProjectID(for: taskID).map { (taskID, $0) }
    })
  }

  private func orderedVisibleRootTaskIDs(in projectID: UUID) -> [UUID] {
    let entries = workspaceTimelineScheduleEntriesByProjectID[projectID] ?? []
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
      .map(\.taskID)
  }

  private func sequentialEntries(in projectID: UUID) -> [SequentialTaskEntry] {
    let entriesByTaskID = Dictionary(
      uniqueKeysWithValues: (workspaceTimelineScheduleEntriesByProjectID[projectID] ?? []).map {
        ($0.taskID, $0)
      }
    )
    return orderedVisibleRootTaskIDs(in: projectID).compactMap { taskID in
      guard let entry = entriesByTaskID[taskID] else { return nil }
      return SequentialTaskEntry(id: taskID, isCompleted: entry.isCompleted)
    }
  }

  private func captureTimelineProjectBucketOrderUndoSnapshot(
    from bars: [TimelineProjectBar]
  ) -> TimelineProjectBucketOrderUndoSnapshot {
    let projectIDs = bars.map(\.projectID)
    return TimelineProjectBucketOrderUndoSnapshot(
      boardOrdersByProjectID: Dictionary(
        uniqueKeysWithValues: projectIDs.map {
          ($0, workspaceTimelineProjectSnapshots[$0]?.boardOrder)
        }
      ),
      stagesByProjectID: Dictionary(
        uniqueKeysWithValues: bars.map { ($0.projectID, priorityStage(for: $0)) }
      )
    )
  }

  private func reorderedProjectIDs(
    from projectIDs: [UUID],
    draggedID: UUID,
    targetID: UUID,
    placeAfter: Bool
  ) -> [UUID]? {
    var reordered = projectIDs
    guard
      let sourceIndex = reordered.firstIndex(of: draggedID),
      let targetIndex = reordered.firstIndex(of: targetID)
    else {
      return nil
    }
    if sourceIndex == targetIndex { return nil }

    let movedProjectID = reordered.remove(at: sourceIndex)
    var adjustedTargetIndex = targetIndex
    if sourceIndex < adjustedTargetIndex {
      adjustedTargetIndex -= 1
    }
    let rawInsertionIndex = placeAfter ? adjustedTargetIndex + 1 : adjustedTargetIndex
    let insertionIndex = min(max(0, rawInsertionIndex), reordered.count)
    reordered.insert(movedProjectID, at: insertionIndex)
    return reordered
  }
}
