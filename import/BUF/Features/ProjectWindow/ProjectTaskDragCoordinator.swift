import Foundation

struct ProjectTaskDragSnapshot: Equatable {
  let taskID: UUID
  let shouldRestoreInlineDetail: Bool
}

@MainActor
struct ProjectTaskDragCoordinator {
  func beginDrag(taskID: UUID, shouldRestoreInlineDetail: Bool) -> ProjectTaskDragSnapshot {
    ProjectTaskDragSnapshot(
      taskID: taskID,
      shouldRestoreInlineDetail: shouldRestoreInlineDetail
    )
  }

  func isTaskTemporarilyCompacted(
    _ taskID: UUID,
    draggingTaskID: UUID?,
    snapshot: ProjectTaskDragSnapshot?
  ) -> Bool {
    draggingTaskID == taskID && snapshot?.taskID == taskID
  }

  func shouldForceRevealInlineDetail(
    _ taskID: UUID,
    draggingTaskID: UUID?,
    snapshot: ProjectTaskDragSnapshot?
  ) -> Bool {
    draggingTaskID == nil
      && snapshot?.taskID == taskID
      && snapshot?.shouldRestoreInlineDetail == true
  }
}
