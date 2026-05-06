import XCTest
@testable import BrainUnfog

final class TimelineProjectListSessionTests: XCTestCase {
  func testApplySnapshotPreservesDraftWhileMergingLatestTasks() {
    let projectID = UUID()
    let firstID = UUID()
    let secondID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: firstID, title: "First")
      ])
    )
    session.startDraft(after: firstID)
    session.updateDraftTitle("New task")

    session.applySnapshot(
      snapshot(projectID: projectID, tasks: [
        task(id: firstID, title: "First updated"),
        task(id: secondID, title: "Second"),
      ])
    )

    XCTAssertEqual(session.tasks.map(\.id), [firstID, secondID])
    XCTAssertEqual(session.tasks.first?.title, "First updated")
    XCTAssertEqual(session.draftAnchor, .after(firstID))
    XCTAssertEqual(session.draftTitle, "New task")
    XCTAssertEqual(session.focusedDraftAnchor, .after(firstID))
  }

  func testApplySnapshotPreservesEditingFields() {
    let projectID = UUID()
    let taskID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: taskID, title: "Original")
      ])
    )
    session.startEditing(task(id: taskID, title: "Original"))
    session.updateEditingTitle("Local edit")

    session.applySnapshot(
      snapshot(projectID: projectID, tasks: [
        task(id: taskID, title: "Remote edit")
      ])
    )

    XCTAssertEqual(session.tasks.first?.title, "Remote edit")
    XCTAssertEqual(session.editingTaskID, taskID)
    XCTAssertEqual(session.editingTitle, "Local edit")
    XCTAssertEqual(session.focusedEditingTaskID, taskID)
  }

  func testApplySnapshotKeepsPendingOptimisticRename() {
    let projectID = UUID()
    let taskID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: taskID, title: "Original")
      ])
    )
    session.startEditing(task(id: taskID, title: "Original"))
    session.updateEditingTitle("Renamed")

    _ = session.submitRenameOptimistically(taskID: taskID)
    session.applySnapshot(
      snapshot(projectID: projectID, tasks: [
        task(id: taskID, title: "Original")
      ])
    )

    XCTAssertEqual(session.tasks.first?.title, "Renamed")
  }

  func testOptimisticCreateSuccessReplacesTemporaryIdentifier() {
    let projectID = UUID()
    let firstID = UUID()
    let secondID = UUID()
    let temporaryID = UUID()
    let createdID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: firstID, title: "First"),
        task(id: secondID, title: "Second"),
      ])
    )
    session.startDraft(after: firstID)
    session.updateDraftTitle("Created")

    let optimisticTask = session.submitDraftOptimistically(temporaryID: temporaryID)
    XCTAssertEqual(optimisticTask?.id, temporaryID)
    XCTAssertEqual(session.tasks.map(\.id), [firstID, temporaryID, secondID])
    XCTAssertTrue(session.isPendingCreate(temporaryID))

    session.resolveOptimisticCreate(
      temporaryID: temporaryID,
      createdTask: task(id: createdID, title: "Created")
    )

    XCTAssertEqual(session.tasks.map(\.id), [firstID, createdID, secondID])
    XCTAssertFalse(session.isPendingCreate(temporaryID))
    XCTAssertEqual(session.draftAnchor, .after(createdID))
    XCTAssertEqual(session.focusedDraftAnchor, .after(createdID))
  }

  func testPersistableOpenTaskIDsExcludePendingCreate() {
    let projectID = UUID()
    let firstID = UUID()
    let temporaryID = UUID()
    let createdID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: firstID, title: "First")
      ])
    )
    session.startDraft(after: firstID)
    session.updateDraftTitle("Created")

    _ = session.submitDraftOptimistically(temporaryID: temporaryID)
    XCTAssertEqual(session.openTaskIDs, [firstID, temporaryID])
    XCTAssertEqual(session.persistableOpenTaskIDs, [firstID])

    session.resolveOptimisticCreate(
      temporaryID: temporaryID,
      createdTask: task(id: createdID, title: "Created")
    )

    XCTAssertEqual(session.persistableOpenTaskIDs, [firstID, createdID])
  }

  func testOptimisticCreateFailureRestoresDraftAtOriginalAnchor() {
    let projectID = UUID()
    let firstID = UUID()
    let temporaryID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: firstID, title: "First")
      ])
    )
    session.startDraft(after: firstID)
    session.updateDraftTitle("Created")
    _ = session.submitDraftOptimistically(temporaryID: temporaryID)

    session.failOptimisticCreate(temporaryID: temporaryID)

    XCTAssertEqual(session.tasks.map(\.id), [firstID])
    XCTAssertFalse(session.isPendingCreate(temporaryID))
    XCTAssertEqual(session.draftAnchor, .after(firstID))
    XCTAssertEqual(session.draftTitle, "Created")
    XCTAssertEqual(session.focusedDraftAnchor, .after(firstID))
  }

  func testLiveReorderPreviewCommitsOpenTaskOrderOnly() {
    let projectID = UUID()
    let firstID = UUID()
    let completedID = UUID()
    let thirdID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: firstID, title: "First"),
        task(id: completedID, title: "Completed", isCompleted: true),
        task(id: thirdID, title: "Third"),
      ])
    )
    session.beginDragging(taskID: firstID)

    XCTAssertTrue(
      session.previewDrop(draggedID: firstID, targetID: thirdID, placement: .after)
    )
    XCTAssertEqual(session.tasks.map(\.id), [firstID, completedID, thirdID])

    let committedOpenTaskIDs = session.commitDrop()
    XCTAssertEqual(committedOpenTaskIDs, [thirdID, firstID])
    XCTAssertEqual(session.tasks.map(\.id), [thirdID, firstID, completedID])
    XCTAssertNil(session.draggingTaskID)
    XCTAssertNil(session.dropIndicator)
  }

  func testApplySnapshotKeepsPendingLocalTaskReorderUntilSnapshotMatches() {
    let projectID = UUID()
    let firstID = UUID()
    let secondID = UUID()
    let thirdID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: firstID, title: "First"),
        task(id: secondID, title: "Second"),
        task(id: thirdID, title: "Third"),
      ])
    )
    session.beginDragging(taskID: firstID)
    XCTAssertTrue(
      session.previewDrop(draggedID: firstID, targetID: thirdID, placement: .after)
    )
    XCTAssertEqual(session.commitDrop(), [secondID, thirdID, firstID])

    session.applySnapshot(
      snapshot(projectID: projectID, tasks: [
        task(id: firstID, title: "First"),
        task(id: secondID, title: "Second"),
        task(id: thirdID, title: "Third"),
      ])
    )

    XCTAssertEqual(session.tasks.map(\.id), [secondID, thirdID, firstID])

    session.applySnapshot(
      snapshot(projectID: projectID, tasks: [
        task(id: secondID, title: "Second"),
        task(id: thirdID, title: "Third"),
        task(id: firstID, title: "First"),
      ])
    )

    XCTAssertEqual(session.tasks.map(\.id), [secondID, thirdID, firstID])
  }

  func testOptimisticRenameFailureRestoresPreviousTask() {
    let projectID = UUID()
    let taskID = UUID()
    var session = TimelineProjectListSession(
      snapshot: snapshot(projectID: projectID, tasks: [
        task(id: taskID, title: "Original")
      ])
    )
    session.startEditing(task(id: taskID, title: "Original"))
    session.updateEditingTitle("Renamed")

    let renamed = session.submitRenameOptimistically(taskID: taskID)
    XCTAssertEqual(renamed?.title, "Renamed")
    XCTAssertEqual(session.tasks.first?.title, "Renamed")

    session.failOptimisticRename(taskID: taskID)
    XCTAssertEqual(session.tasks.first?.title, "Original")
  }

  func testWriteQueueRunsOperationsInOrder() async {
    let queue = TimelineProjectListWriteQueue()
    let recorder = WriteQueueRecorder()

    await queue.enqueue {
      await recorder.append(1)
    }
    await queue.enqueue {
      await recorder.append(2)
    }
    await queue.drain()

    let values = await recorder.allValues()
    XCTAssertEqual(values, [1, 2])
  }

  func testProjectNoteDirtyPolicyIgnoresTrailingNewlines() {
    XCTAssertFalse(
      TimelineProjectNoteAutoSavePolicy.isDirty(
        currentText: "저장하라고.\n\n",
        committedText: "저장하라고."
      )
    )
  }

  func testProjectNoteDirtyPolicyDetectsContentChanges() {
    XCTAssertTrue(
      TimelineProjectNoteAutoSavePolicy.isDirty(
        currentText: "새 내용",
        committedText: "이전 내용"
      )
    )
  }

  private func snapshot(
    projectID: UUID,
    tasks: [TimelineProjectListWindowSnapshot.Task]
  ) -> TimelineProjectListWindowSnapshot {
    TimelineProjectListWindowSnapshot(
      projectID: projectID,
      title: "Project",
      colorHex: nil,
      tasks: tasks
    )
  }

  private func task(
    id: UUID,
    title: String,
    isCompleted: Bool = false
  ) -> TimelineProjectListWindowSnapshot.Task {
    TimelineProjectListWindowSnapshot.Task(
      id: id,
      title: title,
      dateText: nil,
      notePreviewText: nil,
      isCompleted: isCompleted,
      isOverdue: false
    )
  }
}

private actor WriteQueueRecorder {
  private(set) var values: [Int] = []

  func append(_ value: Int) {
    values.append(value)
  }

  func allValues() -> [Int] {
    values
  }
}
