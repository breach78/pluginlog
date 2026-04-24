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
      forceExistingReminderUpdates: false,
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
      forceExistingReminderUpdates: true,
      now: now
    )
  }

  private static func sync(
    pages: [LogseqProjectPageStore.PageSnapshot],
    store: LogseqProjectPageStore,
    reminderProjectProvider: ReminderProjectProvider,
    forceExistingReminderUpdates: Bool,
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
      let pageModifiedAt = modificationDate(of: page.fileURL)
      var taskIdentifiersByIndex: [Int: String] = [:]

      for (taskIndex, task) in page.externalTasks.enumerated() {
        if let reminderExternalIdentifier = normalized(task.reminderExternalIdentifier) {
          try applyExistingReminderUpdates(
            task,
            projectID: projectID,
            reminderExternalIdentifier: reminderExternalIdentifier,
            reminderProjectProvider: reminderProjectProvider,
            forceExistingReminderUpdates: forceExistingReminderUpdates,
            pageModifiedAt: pageModifiedAt,
            taskRecords: &taskRecords,
            now: now
          )
          continue
        }

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

  private static func applyExistingReminderUpdates(
    _ task: LogseqProjectPageStore.TaskRecord,
    projectID: UUID,
    reminderExternalIdentifier: String,
    reminderProjectProvider: ReminderProjectProvider,
    forceExistingReminderUpdates: Bool,
    pageModifiedAt: Date?,
    taskRecords: inout [TaskIdentityBridgeRecord],
    now: Date
  ) throws {
    let taskID = ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
    let reference = ReminderTaskReference(
      taskID: taskID,
      reminderIdentifier: nil,
      reminderExternalIdentifier: reminderExternalIdentifier
    )

    guard let snapshot = try reminderProjectProvider.taskSnapshot(for: reference) else {
      return
    }
    guard forceExistingReminderUpdates || localPageIsNewerThanRemote(pageModifiedAt, snapshot.modifiedAt) else {
      return
    }

    var updatedAt: Date?
    if normalized(snapshot.title) != normalized(task.title) {
      let metadata = try reminderProjectProvider.setTaskTitle(
        for: reference,
        title: task.title
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
    }

    if snapshot.isCompleted != task.isCompleted {
      let metadata = try reminderProjectProvider.setTaskCompletion(
        for: reference,
        isCompleted: task.isCompleted,
        completionDate: nil
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
    }

    let desiredDate = LogseqReminderPropertyCodec.decodeDate(task.date)
    if encodedDate(snapshot.dueDate, hasExplicitTime: snapshot.hasExplicitTime)
      != encodedDate(desiredDate?.date, hasExplicitTime: desiredDate?.hasExplicitTime ?? false)
    {
      let metadata = try reminderProjectProvider.setTaskSchedule(
        for: reference,
        dueDate: desiredDate?.date,
        hasExplicitTime: desiredDate?.hasExplicitTime ?? false
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
    }

    let desiredRecurrence = LogseqReminderPropertyCodec.decodeRepeat(task.repeatRule)
    let remoteRecurrence = LogseqReminderPropertyCodec.decodeRepeat(snapshot.recurrenceRuleRaw)
    if desiredRecurrence != remoteRecurrence {
      let metadata = try reminderProjectProvider.setTaskRecurrence(
        for: reference,
        recurrenceRuleRaw: desiredRecurrence
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
    }

    guard let updatedAt else { return }
    taskRecords.append(
      TaskIdentityBridgeRecord(
        taskID: taskID,
        title: task.title,
        reminderExternalIdentifier: reminderExternalIdentifier,
        ownerProjectID: projectID,
        createdAt: now,
        updatedAt: updatedAt
      )
    )
  }

  private static func encodedDate(_ date: Date?, hasExplicitTime: Bool) -> String? {
    LogseqReminderPropertyCodec.encodeDate(date, hasExplicitTime: hasExplicitTime)
  }

  private static func localPageIsNewerThanRemote(_ pageModifiedAt: Date?, _ remoteModifiedAt: Date) -> Bool {
    guard let pageModifiedAt else { return false }
    return pageModifiedAt.timeIntervalSince(remoteModifiedAt) > 0.5
  }

  private static func modificationDate(of fileURL: URL) -> Date? {
    try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
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
