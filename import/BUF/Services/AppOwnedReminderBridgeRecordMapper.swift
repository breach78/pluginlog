import Foundation

enum AppOwnedReminderBridgeRecordMapper {
  static func records(
    from snapshot: RetainedWorkspaceSnapshot,
    importedAt: Date
  ) -> (projects: [ProjectIdentityBridgeRecord], tasks: [TaskIdentityBridgeRecord]) {
    let projects = snapshot.projects.map { project in
      ProjectIdentityBridgeRecord(
        projectID: project.identity.projectID,
        title: project.title,
        reminderListExternalIdentifier: project.identity.reminderListExternalIdentifier,
        createdAt: importedAt,
        updatedAt: project.updatedAt
      )
    }
    let tasks = snapshot.projects.flatMap { project in
      project.tasks.compactMap { task -> TaskIdentityBridgeRecord? in
        guard let taskID = task.identity.taskID else { return nil }
        return TaskIdentityBridgeRecord(
          taskID: taskID,
          title: task.title,
          reminderExternalIdentifier: task.identity.reminderExternalIdentifier,
          ownerProjectID: project.identity.projectID,
          createdAt: importedAt,
          updatedAt: importedAt
        )
      }
    }
    return (projects, tasks)
  }

  static func records(
    from batch: ReminderImportSnapshotBatch,
    importedAt: Date
  ) -> (projects: [ProjectIdentityBridgeRecord], tasks: [TaskIdentityBridgeRecord]) {
    let listsByIdentifier = Dictionary(uniqueKeysWithValues: batch.lists.map { ($0.identifier, $0) })
    var projects = batch.lists.map { list in
      let projectIdentity = normalized(list.externalIdentifier) ?? list.identifier
      return ProjectIdentityBridgeRecord(
        projectID: RetainedProjectionBuilder.derivedProjectID(for: projectIdentity),
        title: list.title,
        reminderListExternalIdentifier: projectIdentity,
        createdAt: importedAt,
        updatedAt: importedAt
      )
    }
    for (listIdentifier, items) in batch.itemsByListIdentifier where listsByIdentifier[listIdentifier] == nil {
      projects.append(
        ProjectIdentityBridgeRecord(
          projectID: RetainedProjectionBuilder.derivedProjectID(for: listIdentifier),
          title: items.first?.sourceListTitle ?? "Imported Reminders",
          reminderListExternalIdentifier: listIdentifier,
          createdAt: importedAt,
          updatedAt: importedAt
        )
      )
    }
    let tasks = batch.itemsByListIdentifier.flatMap { listIdentifier, items in
      items.map { item in
        let list = listsByIdentifier[listIdentifier]
        let projectIdentity = normalized(list?.externalIdentifier) ?? listIdentifier
        let taskIdentity = normalized(item.externalIdentifier) ?? item.identifier
        return TaskIdentityBridgeRecord(
          taskID: ReminderProjectionIdentity.taskID(for: taskIdentity),
          title: item.title,
          reminderExternalIdentifier: taskIdentity,
          ownerProjectID: RetainedProjectionBuilder.derivedProjectID(for: projectIdentity),
          createdAt: item.createdAt,
          updatedAt: item.modifiedAt
        )
      }
    }
    return (projects, tasks)
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
