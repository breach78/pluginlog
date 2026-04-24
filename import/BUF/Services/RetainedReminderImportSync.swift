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
      var remoteModifiedAtByReminderIdentifier: [String: Date] = [:]
      let importedTasks = items.compactMap { item -> LogseqProjectPageStore.TaskRecord? in
        guard let taskIdentifier = normalized(item.externalIdentifier) ?? normalized(item.identifier),
          let taskTitle = normalized(item.title)
        else {
          return nil
        }
        remoteModifiedAtByReminderIdentifier[taskIdentifier] = item.modifiedAt

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
        importedTasks: importedTasks,
        remoteModifiedAtByReminderIdentifier: remoteModifiedAtByReminderIdentifier
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
      importedTaskCount += importedTasks.count
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
    importedTasks: [LogseqProjectPageStore.TaskRecord],
    remoteModifiedAtByReminderIdentifier: [String: Date]
  ) async throws {
    do {
      _ = try await store.upsertReminderBackedPage(
        identity,
        importedTasks: importedTasks,
        remoteModifiedAtByReminderIdentifier: remoteModifiedAtByReminderIdentifier
      )
    } catch LogseqProjectPageStore.StoreError.pageNotOwned {
      guard let claimablePage = try await store.loadClaimableTaggedPage(for: identity) else {
        throw LogseqProjectPageStore.StoreError.pageNotOwned
      }
      _ = try await store.claimReminderBackedTaggedPage(
        at: claimablePage.fileURL,
        as: identity,
        importedTasks: importedTasks
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
