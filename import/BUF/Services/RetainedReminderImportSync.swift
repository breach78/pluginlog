import Foundation

enum RetainedReminderImportSync {
  struct SyncResult: Equatable {
    var importedProjectCount: Int
    var importedTaskCount: Int
    var projectRecords: [ProjectIdentityBridgeRecord]
    var taskRecords: [TaskIdentityBridgeRecord]
  }

  static func sync(
    batch: ReminderImportSnapshotBatch,
    store: LogseqProjectPageStore,
    now: Date = .now
  ) async throws -> SyncResult {
    var projectRecords: [ProjectIdentityBridgeRecord] = []
    var taskRecords: [TaskIdentityBridgeRecord] = []
    var importedProjectCount = 0
    var importedTaskCount = 0

    for list in batch.lists {
      guard let listExternalIdentifier = normalized(list.externalIdentifier) ?? normalized(list.identifier),
        let title = normalized(list.title)
      else {
        continue
      }

      let projectID = RetainedProjectionBuilder.derivedProjectID(
        for: listExternalIdentifier
      )
      let items = batch.itemsByListIdentifier[list.identifier] ?? []
      let managedTasks = items.compactMap { item -> LogseqProjectPageStore.TaskRecord? in
        guard let taskIdentifier = normalized(item.externalIdentifier) ?? normalized(item.identifier),
          let taskTitle = normalized(item.title)
        else {
          return nil
        }

        let taskID = ReminderProjectionIdentity.taskID(for: taskIdentifier)
        taskRecords.append(
          TaskIdentityBridgeRecord(
            taskID: taskID,
            title: taskTitle,
            reminderExternalIdentifier: taskIdentifier,
            ownerProjectID: projectID,
            createdAt: item.createdAt,
            updatedAt: item.modifiedAt
          )
        )

        return LogseqProjectPageStore.TaskRecord(
          taskID: nil,
          title: taskTitle,
          isCompleted: item.isCompleted,
          date: LogseqReminderPropertyCodec.encodeDate(
            item.dueDate,
            hasExplicitTime: item.scheduleHasExplicitTime
          ),
          duration: nil,
          repeatRule: LogseqReminderPropertyCodec.encodeRepeat(item.recurrenceRuleRaw),
          reminderExternalIdentifier: taskIdentifier,
          calendarEventExternalIdentifier: nil
        )
      }

      try await upsertOrClaimProjectPage(
        store: store,
        identity: LogseqProjectPageStore.ProjectIdentity(
          projectID: projectID,
          title: title,
          reminderListExternalIdentifier: listExternalIdentifier
        ),
        managedTasks: managedTasks
      )

      let latestTaskUpdate = items.map(\.modifiedAt).max()
      projectRecords.append(
        ProjectIdentityBridgeRecord(
          projectID: projectID,
          title: title,
          reminderListExternalIdentifier: listExternalIdentifier,
          createdAt: now,
          updatedAt: latestTaskUpdate ?? now
        )
      )
      importedProjectCount += 1
      importedTaskCount += managedTasks.count
    }

    return SyncResult(
      importedProjectCount: importedProjectCount,
      importedTaskCount: importedTaskCount,
      projectRecords: projectRecords,
      taskRecords: taskRecords
    )
  }

  private static func upsertOrClaimProjectPage(
    store: LogseqProjectPageStore,
    identity: LogseqProjectPageStore.ProjectIdentity,
    managedTasks: [LogseqProjectPageStore.TaskRecord]
  ) async throws {
    do {
      _ = try await store.upsertPage(
        identity,
        noteMarkdown: "",
        managedTasks: managedTasks
      )
    } catch LogseqProjectPageStore.StoreError.pageNotOwned {
      guard let claimablePage = try await store.loadClaimableTaggedPage(for: identity) else {
        throw LogseqProjectPageStore.StoreError.pageNotOwned
      }
      _ = try await store.claimTaggedPage(
        at: claimablePage.fileURL,
        as: identity,
        noteMarkdown: claimablePage.noteMarkdown,
        managedTasks: managedTasks
      )
    }
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
