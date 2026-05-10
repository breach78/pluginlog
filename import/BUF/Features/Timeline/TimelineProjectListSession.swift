import Foundation
import SwiftUI

enum TimelineProjectListDraftAnchor: Hashable {
  case beginning
  case after(UUID)

  var taskID: UUID? {
    switch self {
    case .beginning:
      return nil
    case .after(let taskID):
      return taskID
    }
  }
}

struct TimelineProjectListTaskDropIndicator: Equatable {
  let targetTaskID: UUID
  let placement: TimelineProjectDropPlacement
}

struct TimelineProjectListSession {
  typealias Task = TimelineProjectListWindowSnapshot.Task

  private struct PendingCreate {
    var anchor: TimelineProjectListDraftAnchor
    let title: String
  }

  let projectID: UUID
  private(set) var tasks: [Task]
  var draggingTaskID: UUID?
  var dropIndicator: TimelineProjectListTaskDropIndicator?
  var editingTaskID: UUID?
  var editingTitle = ""
  var draftAnchor: TimelineProjectListDraftAnchor?
  var draftTitle = ""
  var focusedEditingTaskID: UUID?
  var focusedDraftAnchor: TimelineProjectListDraftAnchor?

  private var pendingCreates: [UUID: PendingCreate] = [:]
  private var pendingRenames: [UUID: Task] = [:]
  private var pendingOpenTaskOrder: [UUID]?
  private var taskViewIDs: [UUID: UUID] = [:]

  init(snapshot: TimelineProjectListWindowSnapshot) {
    self.projectID = snapshot.projectID
    self.tasks = snapshot.tasks
  }

  mutating func applySnapshot(_ snapshot: TimelineProjectListWindowSnapshot) {
    guard snapshot.projectID == projectID else { return }
    let snapshotOpenTaskIDs = TimelineProjectListTaskOrderPolicy.openTaskIDs(from: snapshot.tasks)
    if pendingOpenTaskOrder == snapshotOpenTaskIDs {
      pendingOpenTaskOrder = nil
    }
    tasks = mergedTasks(from: snapshot.tasks)
    if let pendingOpenTaskOrder {
      tasks = reorderedTasksPreservingPendingOpenOrder(tasks, orderedOpenTaskIDs: pendingOpenTaskOrder)
    }
    pruneInvalidAnchors()
  }

  mutating func startDraft(after taskID: UUID?) {
    editingTaskID = nil
    editingTitle = ""
    focusedEditingTaskID = nil
    let anchor = taskID.map(TimelineProjectListDraftAnchor.after) ?? .beginning
    draftAnchor = anchor
    draftTitle = ""
    focusedDraftAnchor = anchor
  }

  mutating func updateDraftTitle(_ title: String) {
    draftTitle = title
  }

  mutating func startEditing(_ task: Task) {
    draftAnchor = nil
    draftTitle = ""
    focusedDraftAnchor = nil
    editingTaskID = task.id
    editingTitle = task.title
    focusedEditingTaskID = task.id
  }

  mutating func updateEditingTitle(_ title: String) {
    editingTitle = title
  }

  mutating func submitDraftOptimistically(temporaryID: UUID) -> Task? {
    let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isPendingCreate(temporaryID) else { return nil }
    let anchor = draftAnchor ?? .after(tasks.last?.id ?? temporaryID)
    let task = Task(
      id: temporaryID,
      title: TimelineBoardReadPath.timelinePreviewTitle(for: title),
      dateText: nil,
      notePreviewText: nil,
      metadataIndicators: .empty,
      isCompleted: false,
      isOverdue: false
    )
    pendingCreates[temporaryID] = PendingCreate(anchor: anchor, title: title)
    insertTask(task, after: anchor.taskID)
    let nextAnchor = TimelineProjectListDraftAnchor.after(temporaryID)
    draftAnchor = nextAnchor
    draftTitle = ""
    focusedDraftAnchor = nextAnchor
    return task
  }

  mutating func resolveOptimisticCreate(temporaryID: UUID, createdTask: Task) {
    pendingCreates.removeValue(forKey: temporaryID)
    replaceTaskID(temporaryID, with: createdTask)
    replaceAnchorID(temporaryID, with: createdTask.id)
  }

  mutating func failOptimisticCreate(temporaryID: UUID) {
    guard let pending = pendingCreates.removeValue(forKey: temporaryID) else { return }
    removeTask(temporaryID)
    draftAnchor = pending.anchor
    draftTitle = pending.title
    focusedDraftAnchor = pending.anchor
  }

  func isPendingCreate(_ taskID: UUID) -> Bool {
    pendingCreates[taskID] != nil
  }

  mutating func submitRenameOptimistically(taskID: UUID) -> Task? {
    let title = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, let index = tasks.firstIndex(where: { $0.id == taskID }) else {
      return nil
    }
    let previous = tasks[index]
    guard title != previous.title else {
      clearEditing()
      return previous
    }
    pendingRenames[taskID] = previous
    let renamed = Task(
      id: previous.id,
      title: TimelineBoardReadPath.timelinePreviewTitle(for: title),
      dateText: previous.dateText,
      notePreviewText: previous.notePreviewText,
      metadataIndicators: previous.metadataIndicators,
      isCompleted: previous.isCompleted,
      isOverdue: previous.isOverdue
    )
    tasks[index] = renamed
    clearEditing()
    return renamed
  }

  mutating func resolveOptimisticRename(taskID: UUID, updatedTask: Task) {
    pendingRenames.removeValue(forKey: taskID)
    replaceTask(updatedTask)
  }

  mutating func failOptimisticRename(taskID: UUID) {
    guard let previous = pendingRenames.removeValue(forKey: taskID) else { return }
    replaceTask(previous)
  }

  mutating func beginDragging(taskID: UUID) {
    draggingTaskID = taskID
  }

  mutating func previewDrop(
    draggedID: UUID,
    targetID: UUID,
    placement: TimelineProjectDropPlacement
  ) -> Bool {
    guard draggingTaskID == draggedID || draggingTaskID == nil else { return false }
    guard TimelineBoardReadPath.reorderedTaskIDsAfterDrop(
      openTaskIDs,
      draggedID: draggedID,
      targetID: targetID,
      placement: placement
    ) != nil else {
      return false
    }
    draggingTaskID = draggedID
    dropIndicator = TimelineProjectListTaskDropIndicator(
      targetTaskID: targetID,
      placement: placement
    )
    return true
  }

  mutating func commitDrop() -> [UUID] {
    guard
      let currentDraggingTaskID = draggingTaskID,
      let currentDropIndicator = dropIndicator,
      let orderedTaskIDs = TimelineBoardReadPath.reorderedTaskIDsAfterDrop(
        openTaskIDs,
        draggedID: currentDraggingTaskID,
        targetID: currentDropIndicator.targetTaskID,
        placement: currentDropIndicator.placement
      )
    else {
      self.draggingTaskID = nil
      self.dropIndicator = nil
      return []
    }
    tasks = reorderedTasksPreservingPendingOpenOrder(tasks, orderedOpenTaskIDs: orderedTaskIDs)
    pendingOpenTaskOrder = orderedTaskIDs
    draggingTaskID = nil
    dropIndicator = nil
    return orderedTaskIDs
  }

  mutating func cancelDrag() {
    draggingTaskID = nil
    dropIndicator = nil
  }

  mutating func replaceTask(_ task: Task) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    tasks[index] = task
  }

  mutating func setTaskCompletion(_ taskID: UUID, isCompleted: Bool) {
    guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
    let task = tasks[index]
    tasks[index] = Task(
      id: task.id,
      title: task.title,
      dateText: task.dateText,
      notePreviewText: task.notePreviewText,
      metadataIndicators: task.metadataIndicators,
      isCompleted: isCompleted,
      isOverdue: isCompleted ? false : task.isOverdue
    )
    if editingTaskID == taskID {
      clearEditing()
    }
    if draftAnchor == .after(taskID) {
      draftAnchor = nil
      draftTitle = ""
      focusedDraftAnchor = nil
    }
  }

  mutating func removeTask(_ taskID: UUID) {
    tasks.removeAll { $0.id == taskID }
    if editingTaskID == taskID {
      clearEditing()
    }
    if draftAnchor == .after(taskID) {
      draftAnchor = nil
      draftTitle = ""
      focusedDraftAnchor = nil
    }
  }

  var openTaskIDs: [UUID] {
    TimelineProjectListTaskOrderPolicy.openTaskIDs(from: tasks)
  }

  var persistableOpenTaskIDs: [UUID] {
    openTaskIDs.filter { !isPendingCreate($0) }
  }

  func viewID(for taskID: UUID) -> UUID {
    taskViewIDs[taskID] ?? taskID
  }

  func visibleTasks(showsCompletedTasks: Bool) -> [Task] {
    showsCompletedTasks ? tasks : tasks.filter { !$0.isCompleted }
  }

  private mutating func insertTask(_ task: Task, after anchorID: UUID?) {
    let orderedIDs = TimelineProjectTaskManualOrderStore.insertedTaskIDs(
      tasks.map(\.id),
      insertedID: task.id,
      after: anchorID
    )
    var tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    tasksByID[task.id] = task
    tasks = orderedIDs.compactMap { tasksByID[$0] }
  }

  private mutating func replaceTaskID(_ oldID: UUID, with task: Task) {
    let stableViewID = taskViewIDs.removeValue(forKey: oldID) ?? oldID
    taskViewIDs[task.id] = stableViewID
    tasks.removeAll { $0.id == task.id && $0.id != oldID }
    guard let index = tasks.firstIndex(where: { $0.id == oldID }) else {
      replaceTask(task)
      return
    }
    tasks[index] = task
  }

  private mutating func replaceAnchorID(_ oldID: UUID, with newID: UUID) {
    if draftAnchor == .after(oldID) {
      draftAnchor = .after(newID)
    }
    if focusedDraftAnchor == .after(oldID) {
      focusedDraftAnchor = .after(newID)
    }
    let retargetedTemporaryIDs = pendingCreates.keys.filter {
      pendingCreates[$0]?.anchor == .after(oldID)
    }
    for temporaryID in retargetedTemporaryIDs {
      pendingCreates[temporaryID]?.anchor = .after(newID)
    }
  }

  private mutating func clearEditing() {
    editingTaskID = nil
    editingTitle = ""
    focusedEditingTaskID = nil
  }

  private func mergedTasks(from snapshotTasks: [Task]) -> [Task] {
    var merged = snapshotTasks.map { snapshotTask in
      guard pendingRenames[snapshotTask.id] != nil,
        let localTask = tasks.first(where: { $0.id == snapshotTask.id })
      else {
        return snapshotTask
      }
      return localTask
    }

    let mergedIDs = Set(merged.map(\.id))
    let localPendingTasks = tasks.filter { pendingCreates[$0.id] != nil && !mergedIDs.contains($0.id) }
    guard !localPendingTasks.isEmpty else { return merged }

    for pendingTask in localPendingTasks {
      let anchor = pendingCreates[pendingTask.id]?.anchor.taskID
      let orderedIDs = TimelineProjectTaskManualOrderStore.insertedTaskIDs(
        merged.map(\.id),
        insertedID: pendingTask.id,
        after: anchor
      )
      var tasksByID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
      tasksByID[pendingTask.id] = pendingTask
      merged = orderedIDs.compactMap { tasksByID[$0] }
    }
    return merged
  }

  private mutating func pruneInvalidAnchors() {
    let taskIDs = Set(tasks.map(\.id))
    if let editingTaskID, !taskIDs.contains(editingTaskID) {
      clearEditing()
    }
    if let anchorID = draftAnchor?.taskID, !taskIDs.contains(anchorID) {
      draftAnchor = nil
      focusedDraftAnchor = nil
    }
    pendingRenames = pendingRenames.filter { taskIDs.contains($0.key) }
    taskViewIDs = taskViewIDs.filter { taskIDs.contains($0.key) }
  }

  private func reorderedTasksPreservingPendingOpenOrder(
    _ tasks: [Task],
    orderedOpenTaskIDs: [UUID]
  ) -> [Task] {
    let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    var seen = Set<UUID>()
    let reorderedOpenTasks: [Task] = orderedOpenTaskIDs.compactMap { taskID in
      guard
        let task = tasksByID[taskID],
        !task.isCompleted,
        seen.insert(taskID).inserted
      else {
        return nil
      }
      return task
    }
    let remainingOpenTasks = tasks.filter { task in
      !task.isCompleted && seen.insert(task.id).inserted
    }
    let completedTasks = tasks.filter(\.isCompleted)
    return reorderedOpenTasks + remainingOpenTasks + completedTasks
  }
}

@MainActor
final class TimelineProjectListWriteQueue {
  private var tail: Task<Void, Never>?

  func enqueue(_ operation: @escaping @MainActor () async -> Void) {
    let previous = tail
    let next = Task { @MainActor in
      await previous?.value
      await operation()
    }
    tail = next
  }

  func drain() async {
    await tail?.value
  }
}

@MainActor
final class TimelineProjectListSessionStore: ObservableObject {
  @Published private(set) var session: TimelineProjectListSession

  init(snapshot: TimelineProjectListWindowSnapshot) {
    self.session = TimelineProjectListSession(snapshot: snapshot)
  }

  func applySnapshot(_ snapshot: TimelineProjectListWindowSnapshot) {
    update { session in
      session.applySnapshot(snapshot)
    }
  }

  func update(_ mutate: (inout TimelineProjectListSession) -> Void) {
    var next = session
    mutate(&next)
    session = next
  }
}
