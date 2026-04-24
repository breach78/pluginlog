import Foundation

@MainActor
enum RetainedLogseqProjectProvisioningSync {
  struct SyncResult: Equatable {
    var createdProjectCount: Int
    var createdTaskCount: Int
    var projectRecords: [ProjectIdentityBridgeRecord]
    var taskRecords: [TaskIdentityBridgeRecord]
  }

  static func sync(
    store: LogseqProjectPageStore,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date = .now
  ) async throws -> SyncResult {
    let pages = try await store.loadProjectPagesInScope()
    return try await sync(
      pages: pages,
      store: store,
      reminderProjectProvider: reminderProjectProvider,
      now: now
    )
  }

  static func syncChangedPages(
    fileURLs: [URL],
    store: LogseqProjectPageStore,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date = .now
  ) async throws -> SyncResult {
    let pages = try await store.loadProjectPagesInScope(at: fileURLs)
    return try await sync(
      pages: pages,
      store: store,
      reminderProjectProvider: reminderProjectProvider,
      now: now
    )
  }

  private static func sync(
    pages: [LogseqProjectPageStore.PageSnapshot],
    store: LogseqProjectPageStore,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date
  ) async throws -> SyncResult {
    var createdProjectCount = 0
    var createdTaskCount = 0
    var projectRecords: [ProjectIdentityBridgeRecord] = []
    var taskRecords: [TaskIdentityBridgeRecord] = []

    for page in pages {
      guard page.usesProjectTag || page.reminderListExternalIdentifier != nil else { continue }

      let listIdentifier: String
      if let existingIdentifier = normalized(page.reminderListExternalIdentifier) {
        listIdentifier = existingIdentifier
      } else {
        guard page.usesProjectTag else { continue }
        let createdList = try reminderProjectProvider.createProjectList(title: page.title)
        listIdentifier = createdList.externalIdentifier
        createdProjectCount += 1
      }

      let projectID = RetainedProjectionBuilder.derivedProjectID(for: listIdentifier)
      var taskIdentifiersByIndex: [Int: String] = [:]

      for (taskIndex, task) in page.externalTasks.enumerated() {
        guard normalized(task.reminderExternalIdentifier) == nil else { continue }
        let decodedDate = LogseqReminderPropertyCodec.decodeDate(task.date)
        guard let metadata = try reminderProjectProvider.createTaskReminder(
          inProject: listIdentifier,
          title: task.title,
          dueDate: decodedDate?.date,
          hasExplicitTime: decodedDate?.hasExplicitTime ?? false,
          noteText: ""
        ) else {
          continue
        }
        let taskIdentifier = metadata.externalIdentifier ?? metadata.identifier
        taskIdentifiersByIndex[taskIndex] = taskIdentifier
        let taskID = ReminderProjectionIdentity.taskID(for: taskIdentifier)
        try applyCompletionIfNeeded(
          task,
          taskID: taskID,
          metadata: metadata,
          reminderProjectProvider: reminderProjectProvider
        )
        try applyRecurrenceIfNeeded(
          task,
          taskID: taskID,
          metadata: metadata,
          reminderProjectProvider: reminderProjectProvider
        )
        taskRecords.append(
          TaskIdentityBridgeRecord(
            taskID: taskID,
            title: task.title,
            reminderExternalIdentifier: taskIdentifier,
            ownerProjectID: projectID,
            createdAt: now,
            updatedAt: metadata.modifiedAt
          )
        )
        createdTaskCount += 1
      }

      if page.reminderListExternalIdentifier == nil || !taskIdentifiersByIndex.isEmpty {
        try await store.writeReminderProvisioning(
          to: page,
          reminderListExternalIdentifier: listIdentifier,
          externalTaskReminderIdentifiersByIndex: taskIdentifiersByIndex
        )
      }

      if page.reminderListExternalIdentifier == nil {
        projectRecords.append(
          ProjectIdentityBridgeRecord(
            projectID: projectID,
            title: page.title,
            reminderListExternalIdentifier: listIdentifier,
            createdAt: now,
            updatedAt: now
          )
        )
      }
    }

    return SyncResult(
      createdProjectCount: createdProjectCount,
      createdTaskCount: createdTaskCount,
      projectRecords: projectRecords,
      taskRecords: taskRecords
    )
  }

  private static func applyCompletionIfNeeded(
    _ task: LogseqProjectPageStore.TaskRecord,
    taskID: UUID,
    metadata: ReminderTaskRemoteMetadata,
    reminderProjectProvider: ReminderProjectProvider
  ) throws {
    guard task.isCompleted else { return }
    _ = try reminderProjectProvider.setTaskCompletion(
      for: ReminderTaskReference(
        taskID: taskID,
        reminderIdentifier: metadata.identifier,
        reminderExternalIdentifier: metadata.externalIdentifier ?? metadata.identifier
      ),
      isCompleted: true,
      completionDate: nil
    )
  }

  private static func applyRecurrenceIfNeeded(
    _ task: LogseqProjectPageStore.TaskRecord,
    taskID: UUID,
    metadata: ReminderTaskRemoteMetadata,
    reminderProjectProvider: ReminderProjectProvider
  ) throws {
    guard let recurrenceRuleRaw = LogseqReminderPropertyCodec.decodeRepeat(task.repeatRule) else {
      return
    }
    _ = try reminderProjectProvider.setTaskRecurrence(
      for: ReminderTaskReference(
        taskID: taskID,
        reminderIdentifier: metadata.identifier,
        reminderExternalIdentifier: metadata.externalIdentifier ?? metadata.identifier
      ),
      recurrenceRuleRaw: recurrenceRuleRaw
    )
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
