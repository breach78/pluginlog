import XCTest
@testable import BrainUnfog

@MainActor
final class UndoRedoPolicyMatrixTests: XCTestCase {
  func testTaskCreateUndoRedoAndRedoInvalidationAfterNewAction() {
    let harness = UndoRedoPolicyHarness()
    let first = MatrixTask(title: "First")
    let second = MatrixTask(title: "Second")
    let third = MatrixTask(title: "Third")

    harness.perform { harness.createTask(first) }
    harness.perform { harness.createTask(second) }
    XCTAssertEqual(harness.taskOrder, [first.id, second.id])

    harness.undo()
    XCTAssertEqual(harness.taskOrder, [first.id])
    XCTAssertTrue(harness.undoManager.canRedo)

    harness.perform { harness.createTask(third) }
    XCTAssertEqual(harness.taskOrder, [first.id, third.id])
    XCTAssertFalse(harness.undoManager.canRedo)
  }

  func testTaskDeleteUndoRedoRestoresSnapshotFieldsCompletionAndSchedule() {
    let harness = UndoRedoPolicyHarness()
    let task = MatrixTask(
      title: "Delete me",
      note: "note",
      dayKey: "2026-04-29",
      timeMinutes: 9 * 60,
      durationMinutes: 45,
      isCompleted: true,
      completionToken: "done"
    )
    harness.createTask(task, registerUndo: false)

    harness.perform { harness.deleteTask(task.id) }
    XCTAssertNil(harness.tasks[task.id])

    harness.undo()
    XCTAssertEqual(harness.tasks[task.id], task)
    XCTAssertEqual(harness.taskOrder, [task.id])

    harness.redo()
    XCTAssertNil(harness.tasks[task.id])
    XCTAssertTrue(harness.taskOrder.isEmpty)
  }

  func testTaskEditFieldsUndoRedoCoversTitleNoteDateTimeAndDuration() {
    let harness = UndoRedoPolicyHarness()
    let task = MatrixTask(title: "Before")
    let edited = task.updating(
      title: "After",
      note: "body",
      dayKey: "2026-05-01",
      timeMinutes: 13 * 60 + 30,
      durationMinutes: 90
    )
    harness.createTask(task, registerUndo: false)

    harness.perform { harness.replaceTask(edited, actionName: "할일 편집") }
    XCTAssertEqual(harness.tasks[task.id], edited)

    harness.undo()
    XCTAssertEqual(harness.tasks[task.id], task)

    harness.redo()
    XCTAssertEqual(harness.tasks[task.id], edited)
  }

  func testTaskCompletionUndoRedoCoversCompleteAndCancel() {
    let harness = UndoRedoPolicyHarness()
    let task = MatrixTask(title: "Completion")
    let completed = task.updating(isCompleted: true, completionToken: "completed")
    harness.createTask(task, registerUndo: false)

    harness.perform { harness.replaceTask(completed, actionName: "할일 완료") }
    XCTAssertEqual(harness.tasks[task.id], completed)
    harness.undo()
    XCTAssertEqual(harness.tasks[task.id], task)
    harness.redo()
    XCTAssertEqual(harness.tasks[task.id], completed)

    harness.perform { harness.replaceTask(task, actionName: "할일 완료 취소") }
    XCTAssertEqual(harness.tasks[task.id], task)
    harness.undo()
    XCTAssertEqual(harness.tasks[task.id], completed)
    harness.redo()
    XCTAssertEqual(harness.tasks[task.id], task)
  }

  func testRecurringCompletionUndoRestoresScheduleOnlyThenRedoCompletesAgain() {
    let harness = UndoRedoPolicyHarness()
    let original = MatrixTask(
      title: "Recurring",
      dayKey: "2026-04-30",
      timeMinutes: 13 * 60,
      durationMinutes: 45
    )
    let advancedNextOccurrence = MatrixTask(
      id: original.id,
      title: "Recurring",
      dayKey: "2026-05-08"
    )
    harness.createTask(original, registerUndo: false)

    harness.perform {
      harness.completeRecurringTask(
        original.id,
        advancedNextOccurrence: advancedNextOccurrence
      )
    }
    XCTAssertEqual(harness.tasks[original.id], advancedNextOccurrence)
    XCTAssertEqual(harness.completionWrites, [true])

    harness.undo()
    XCTAssertEqual(harness.tasks[original.id], original)
    XCTAssertEqual(harness.completionWrites, [true])
    XCTAssertEqual(harness.scheduleRestoreWrites, [original])

    harness.redo()
    XCTAssertEqual(harness.tasks[original.id], advancedNextOccurrence)
    XCTAssertEqual(harness.completionWrites, [true, true])
  }

  func testTaskScheduleUndoRedoCoversDateTimeDurationSetAndClear() {
    let harness = UndoRedoPolicyHarness()
    let task = MatrixTask(title: "Schedule")
    let scheduled = task.updating(
      dayKey: "2026-04-30",
      timeMinutes: 10 * 60,
      durationMinutes: 30
    )
    harness.createTask(task, registerUndo: false)

    harness.perform { harness.replaceTask(scheduled, actionName: "일정 배치") }
    XCTAssertEqual(harness.tasks[task.id], scheduled)
    harness.undo()
    XCTAssertEqual(harness.tasks[task.id], task)
    harness.redo()
    XCTAssertEqual(harness.tasks[task.id], scheduled)

    harness.perform { harness.replaceTask(task, actionName: "일정 제거") }
    XCTAssertEqual(harness.tasks[task.id], task)
    harness.undo()
    XCTAssertEqual(harness.tasks[task.id], scheduled)
    harness.redo()
    XCTAssertEqual(harness.tasks[task.id], task)
  }

  func testTaskOrderUndoRedo() {
    let harness = UndoRedoPolicyHarness()
    let first = MatrixTask(title: "A")
    let second = MatrixTask(title: "B")
    let third = MatrixTask(title: "C")
    [first, second, third].forEach { harness.createTask($0, registerUndo: false) }

    harness.perform { harness.reorderTasks([third.id, first.id, second.id]) }
    XCTAssertEqual(harness.taskOrder, [third.id, first.id, second.id])
    harness.undo()
    XCTAssertEqual(harness.taskOrder, [first.id, second.id, third.id])
    harness.redo()
    XCTAssertEqual(harness.taskOrder, [third.id, first.id, second.id])
  }

  func testProjectOrderUndoRedo() {
    let harness = UndoRedoPolicyHarness()
    let first = UUID()
    let second = UUID()
    let third = UUID()
    harness.projectOrder = [first, second, third]

    harness.perform { harness.reorderProjects([second, third, first]) }
    XCTAssertEqual(harness.projectOrder, [second, third, first])
    harness.undo()
    XCTAssertEqual(harness.projectOrder, [first, second, third])
    harness.redo()
    XCTAssertEqual(harness.projectOrder, [second, third, first])
  }

  func testMixedTimelineAndScheduleActionChainUndoRedo() {
    let harness = UndoRedoPolicyHarness()
    let first = MatrixTask(title: "First")
    let second = MatrixTask(title: "Second")
    harness.projectOrder = [UUID(), UUID()]
    [first, second].forEach { harness.createTask($0, registerUndo: false) }
    let edited = first.updating(title: "Renamed", note: "note")
    let scheduled = edited.updating(dayKey: "2026-05-02", timeMinutes: 8 * 60, durationMinutes: 60)
    let completed = scheduled.updating(isCompleted: true, completionToken: "done")

    harness.perform { harness.replaceTask(edited, actionName: "할일 편집") }
    harness.perform { harness.replaceTask(scheduled, actionName: "일정 배치") }
    harness.perform { harness.replaceTask(completed, actionName: "할일 완료") }
    harness.perform { harness.reorderTasks([second.id, first.id]) }
    harness.perform { harness.reorderProjects(harness.projectOrder.reversed()) }
    harness.perform { harness.deleteTask(first.id) }

    harness.undoAll()
    XCTAssertEqual(harness.tasks[first.id], first)
    XCTAssertEqual(harness.tasks[second.id], second)
    XCTAssertEqual(harness.taskOrder, [first.id, second.id])

    harness.redoAll()
    XCTAssertNil(harness.tasks[first.id])
    XCTAssertEqual(harness.tasks[second.id], second)
    XCTAssertEqual(harness.taskOrder, [second.id])
  }
}

private struct MatrixTask: Equatable {
  let id: UUID
  var title: String
  var note: String
  var dayKey: String?
  var timeMinutes: Int?
  var durationMinutes: Int?
  var isCompleted: Bool
  var completionToken: String?

  init(
    id: UUID = UUID(),
    title: String,
    note: String = "",
    dayKey: String? = nil,
    timeMinutes: Int? = nil,
    durationMinutes: Int? = nil,
    isCompleted: Bool = false,
    completionToken: String? = nil
  ) {
    self.id = id
    self.title = title
    self.note = note
    self.dayKey = dayKey
    self.timeMinutes = timeMinutes
    self.durationMinutes = durationMinutes
    self.isCompleted = isCompleted
    self.completionToken = completionToken
  }

  func updating(
    title: String? = nil,
    note: String? = nil,
    dayKey: String? = nil,
    timeMinutes: Int? = nil,
    durationMinutes: Int? = nil,
    isCompleted: Bool? = nil,
    completionToken: String? = nil
  ) -> MatrixTask {
    MatrixTask(
      id: id,
      title: title ?? self.title,
      note: note ?? self.note,
      dayKey: dayKey ?? self.dayKey,
      timeMinutes: timeMinutes ?? self.timeMinutes,
      durationMinutes: durationMinutes ?? self.durationMinutes,
      isCompleted: isCompleted ?? self.isCompleted,
      completionToken: completionToken ?? self.completionToken
    )
  }
}

@MainActor
private final class UndoRedoPolicyHarness {
  let appState = AppState(isPreviewAppState: true)
  let undoManager = UndoManager()
  var tasks: [UUID: MatrixTask] = [:]
  var taskOrder: [UUID] = []
  var projectOrder: [UUID] = []
  var completionWrites: [Bool] = []
  var scheduleRestoreWrites: [MatrixTask] = []

  init() {
    undoManager.groupsByEvent = false
  }

  func perform(_ action: () -> Void) {
    undoManager.beginUndoGrouping()
    action()
    undoManager.endUndoGrouping()
  }

  func undo() {
    undoManager.undo()
  }

  func redo() {
    undoManager.redo()
  }

  func undoAll() {
    while undoManager.canUndo {
      undo()
    }
  }

  func redoAll() {
    while undoManager.canRedo {
      redo()
    }
  }

  func createTask(_ task: MatrixTask, registerUndo: Bool = true) {
    tasks[task.id] = task
    if !taskOrder.contains(task.id) {
      taskOrder.append(task.id)
    }
    guard registerUndo else { return }
    register("할일 추가") {
      self.deleteTask(task.id, registerUndo: true)
    }
  }

  func deleteTask(_ taskID: UUID, registerUndo: Bool = true) {
    guard let task = tasks.removeValue(forKey: taskID) else { return }
    let previousOrder = taskOrder
    taskOrder.removeAll { $0 == taskID }
    guard registerUndo else { return }
    register("할일 삭제") {
      self.recreateTask(task, order: previousOrder, registerUndo: true)
    }
  }

  func recreateTask(_ task: MatrixTask, order: [UUID], registerUndo: Bool = true) {
    tasks[task.id] = task
    taskOrder = order.filter { $0 == task.id || tasks[$0] != nil }
    if !taskOrder.contains(task.id) {
      taskOrder.append(task.id)
    }
    guard registerUndo else { return }
    register("할일 삭제 취소") {
      self.deleteTask(task.id, registerUndo: true)
    }
  }

  func replaceTask(_ nextTask: MatrixTask, actionName: String, registerUndo: Bool = true) {
    guard let previousTask = tasks[nextTask.id], previousTask != nextTask else { return }
    tasks[nextTask.id] = nextTask
    guard registerUndo else { return }
    register(actionName) {
      self.replaceTask(previousTask, actionName: actionName, registerUndo: true)
    }
  }

  func completeRecurringTask(
    _ taskID: UUID,
    advancedNextOccurrence: MatrixTask,
    registerUndo: Bool = true
  ) {
    guard let previousTask = tasks[taskID] else { return }
    completionWrites.append(true)
    tasks[taskID] = advancedNextOccurrence
    guard registerUndo else { return }
    register("할일 완료") {
      self.restoreRecurringCompletion(
        taskID,
        targetTask: previousTask,
        redoAdvancedNextOccurrence: advancedNextOccurrence,
        registerUndo: true
      )
    }
  }

  func restoreRecurringCompletion(
    _ taskID: UUID,
    targetTask: MatrixTask,
    redoAdvancedNextOccurrence: MatrixTask,
    registerUndo: Bool = true
  ) {
    guard tasks[taskID] != nil else { return }
    scheduleRestoreWrites.append(targetTask)
    tasks[taskID] = targetTask
    guard registerUndo else { return }
    register("할일 완료 취소") {
      self.completeRecurringTask(
        taskID,
        advancedNextOccurrence: redoAdvancedNextOccurrence,
        registerUndo: true
      )
    }
  }

  func reorderTasks(_ nextOrder: [UUID], registerUndo: Bool = true) {
    let normalizedOrder = nextOrder.filter { tasks[$0] != nil }
    guard normalizedOrder != taskOrder else { return }
    let previousOrder = taskOrder
    taskOrder = normalizedOrder
    guard registerUndo else { return }
    register("목록 순서 변경") {
      self.reorderTasks(previousOrder, registerUndo: true)
    }
  }

  func reorderProjects(_ nextOrder: [UUID], registerUndo: Bool = true) {
    guard nextOrder != projectOrder else { return }
    let previousOrder = projectOrder
    projectOrder = nextOrder
    guard registerUndo else { return }
    register("프로젝트 순서 변경") {
      self.reorderProjects(previousOrder, registerUndo: true)
    }
  }

  private func register(_ actionName: String, handler: @escaping @MainActor () -> Void) {
    appState.registerUndo(with: undoManager, actionName: actionName, handler: handler)
  }
}
