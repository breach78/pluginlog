import Foundation
import SwiftData

private enum ProjectCommandDispatchError: LocalizedError {
  case dispatcherUnavailable

  var errorDescription: String? {
    ProjectDocumentStoreError.modelContainerUnavailable.localizedDescription
  }
}

@MainActor
extension AppState {
  private func projectCommandDispatcher(for projectID: UUID) throws -> ProjectDocumentStore {
    guard let store = projectDocumentStore(for: projectID) else {
      throw ProjectCommandDispatchError.dispatcherUnavailable
    }
    return store
  }

  private func projectCommandDispatcher(
    forTaskID taskID: UUID,
    context: ModelContext
  ) throws -> ProjectDocumentStore {
    guard let store = projectDocumentStore(forTaskID: taskID, context: context) else {
      throw ProjectCommandDispatchError.dispatcherUnavailable
    }
    return store
  }

  func dispatchProjectCommand(
    in projectID: UUID,
    _ command: ProjectMutationCommand
  ) async throws -> ProjectMutationResult {
    try await projectCommandDispatcher(for: projectID).applyCommand(command)
  }

  func dispatchProjectImmediateCommand(
    in projectID: UUID,
    _ command: ProjectMutationCommand
  ) throws -> ProjectMutationResult {
    try projectCommandDispatcher(for: projectID).applyImmediateCommand(command)
  }

  func dispatchTaskProjectCommand(
    forTaskID taskID: UUID,
    context: ModelContext,
    _ command: ProjectMutationCommand
  ) async throws -> ProjectMutationResult {
    try await projectCommandDispatcher(forTaskID: taskID, context: context).applyCommand(command)
  }

  func dispatchDeleteTaskWithUndoSnapshot(
    taskID: UUID,
    context: ModelContext
  ) async throws -> TaskDeletionUndoSnapshot? {
    try await projectCommandDispatcher(forTaskID: taskID, context: context)
      .deleteTaskWithUndoSnapshot(taskID: taskID)
  }

  func dispatchRestoreDeletedTaskFromUndoSnapshot(
    _ snapshot: TaskDeletionUndoSnapshot
  ) async throws {
    try await projectCommandDispatcher(for: snapshot.projectID)
      .restoreDeletedTaskFromUndoSnapshot(snapshot)
  }

  @discardableResult
  func writeProjectStage(
    _ projectID: UUID,
    stage: ProjectProgressStage
  ) async -> Bool {
    do {
      _ = try await dispatchProjectCommand(in: projectID, .setProjectStage(stage))
      return true
    } catch {
      reportError(error, logMessage: "writeProjectStage failed")
      return false
    }
  }

  @discardableResult
  func moveTaskSequence(
    taskIDs: [UUID],
    sourceProjectID: UUID,
    targetProjectID: UUID
  ) async -> Bool {
    do {
      _ = try await dispatchProjectCommand(
        in: sourceProjectID,
        .moveTaskSequence(taskIDs: taskIDs, targetProjectID: targetProjectID)
      )
      return true
    } catch {
      reportError(error, logMessage: "moveTaskSequence failed")
      return false
    }
  }

  @discardableResult
  func writeProjectRootStructure(
    _ projectID: UUID,
    rootNodes: [ReminderProjectRootNodeRecord]
  ) async -> Bool {
    do {
      _ = try await dispatchProjectCommand(
        in: projectID,
        .setProjectRootStructure(rootNodes: rootNodes)
      )
      return true
    } catch {
      reportError(error, logMessage: "writeProjectRootStructure failed")
      return false
    }
  }

  @discardableResult
  func writeTaskPreparationSchedule(
    projectID: UUID,
    taskID: UUID,
    targetCompletedUnits: Int,
    isAllDay: Bool,
    timeMinutes: Int,
    durationMinutes: Int
  ) async -> Bool {
    do {
      _ = try await dispatchProjectCommand(
        in: projectID,
        .setTaskPreparationSchedule(
          taskID: taskID,
          targetCompletedUnits: targetCompletedUnits,
          isAllDay: isAllDay,
          timeMinutes: timeMinutes,
          durationMinutes: durationMinutes
        )
      )
      return true
    } catch {
      reportError(error, logMessage: "writeTaskPreparationSchedule failed")
      return false
    }
  }

  @discardableResult
  func applyProjectAttachmentMutation(
    _ mutation: ProjectAttachmentMutation,
    ownerProjectID: UUID
  ) -> Bool {
    do {
      _ = try dispatchProjectImmediateCommand(
        in: ownerProjectID,
        .applyAttachmentMutation(mutation)
      )
      return true
    } catch {
      reportError(error, logMessage: "applyProjectAttachmentMutation failed")
      return false
    }
  }
}
