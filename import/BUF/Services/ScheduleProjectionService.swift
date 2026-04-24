import Foundation

enum ScheduleProjectionService {
  static func taskDescriptors(
    projectIDs: [UUID],
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]]
  ) -> [WorkspaceScheduleTaskDescriptor] {
    normalizedProjectIDs(projectIDs)
      .compactMap { projectID -> (WorkspaceProjectRuntimeRecord, [ScheduleSliceEntry])? in
        guard
          let project = projectSnapshots[projectID],
          let scheduleEntries = scheduleEntriesByProjectID[projectID]
        else {
          return nil
        }
        return (project, scheduleEntries)
      }
      .filter { !$0.0.isArchived }
      .flatMap { project, scheduleEntries in
        scheduleEntries.map { entry in
          WorkspaceScheduleTaskDescriptor(
            projectID: project.id,
            projectTitle: project.title,
            projectColorHex: project.colorHex,
            taskRow: entry.taskRowSnapshot(projectID: project.id)
          )
        }
      }
  }

  static func buildTaskSnapshot(
    taskDescriptors: [WorkspaceScheduleTaskDescriptor],
    sourceSignature: Int
  ) -> ScheduleTaskSnapshotCache {
    let workspaceTasksByID = Dictionary(
      uniqueKeysWithValues: taskDescriptors.map { ($0.taskRow.id, $0) }
    )
    var orderedDescriptors: [WorkspaceScheduleTaskDescriptor] = []
    var seen = Set<UUID>()
    for descriptor in taskDescriptors where seen.insert(descriptor.taskRow.id).inserted {
      orderedDescriptors.append(descriptor)
    }

    var hasher = Hasher()
    for descriptor in orderedDescriptors {
      hasher.combine(descriptor.projectID)
      hasher.combine(descriptor.projectTitle)
      hasher.combine(descriptor.projectColorHex)
      hasher.combine(descriptor.taskRow.renderFingerprint)
    }

    return ScheduleTaskSnapshotCache(
      sourceSignature: sourceSignature,
      taskDescriptors: orderedDescriptors,
      workspaceTasksByID: workspaceTasksByID,
      signature: hasher.finalize()
    )
  }

  private static func normalizedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return projectIDs.filter { seen.insert($0).inserted }
  }
}
