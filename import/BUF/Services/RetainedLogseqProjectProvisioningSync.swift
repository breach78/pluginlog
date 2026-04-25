import Foundation

@MainActor
enum RetainedLogseqProjectProvisioningSync {
  enum SyncMode: Equatable {
    case fullPush
    case missingBindingsOnly
  }

  private enum RemoteBindingPresence {
    case exists
    case missing
    case unavailable
  }

  struct SyncResult: Equatable {
    var createdProjectCount: Int
    var createdTaskCount: Int
    var projectRecords: [ProjectIdentityBridgeRecord]
    var taskRecords: [TaskIdentityBridgeRecord]
  }

  static func sync(
    store: LogseqProjectPageStore,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date = .now,
    mode: SyncMode = .fullPush
  ) async throws -> SyncResult {
    let pages = try await store.loadProjectPagesInScope()
    return try await sync(
      pages: pages,
      store: store,
      reminderProjectProvider: reminderProjectProvider,
      now: now,
      mode: mode
    )
  }

  static func syncChangedPages(
    fileURLs: [URL],
    store: LogseqProjectPageStore,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date = .now,
    mode: SyncMode = .fullPush
  ) async throws -> SyncResult {
    let pages = try await store.loadProjectPagesInScope(at: fileURLs)
    return try await sync(
      pages: pages,
      store: store,
      reminderProjectProvider: reminderProjectProvider,
      now: now,
      mode: mode
    )
  }

  private static func sync(
    pages: [LogseqProjectPageStore.PageSnapshot],
    store: LogseqProjectPageStore,
    reminderProjectProvider: ReminderProjectProvider,
    now: Date,
    mode: SyncMode
  ) async throws -> SyncResult {
    var createdProjectCount = 0
    var createdTaskCount = 0
    var projectRecords: [ProjectIdentityBridgeRecord] = []
    var taskRecords: [TaskIdentityBridgeRecord] = []

    for page in pages {
      guard page.usesProjectTag || page.reminderListExternalIdentifier != nil else { continue }
      guard !page.hasAmbiguousReminderListExternalIdentifier else {
        AppLogger.sync.error(
          "logseq provisioning skipped ambiguous reminder list id page=\(page.title, privacy: .public)"
        )
        continue
      }

      let listIdentifier: String
      var resolvedListIdentifier = normalized(page.reminderListExternalIdentifier)
      if resolvedListIdentifier == nil,
        let pendingBinding = ReminderPendingBindingStore.projectBinding(
        pageFileURL: page.fileURL,
        pageTitle: page.title,
        now: now
      ) {
        switch await remoteListPresence(
          pendingBinding,
          pendingBinding.reminderListExternalIdentifier,
          reminderProjectProvider: reminderProjectProvider
        ) {
        case .exists:
          resolvedListIdentifier = pendingBinding.reminderListExternalIdentifier
        case .missing:
          break
        case .unavailable:
          AppLogger.sync.info(
            "logseq provisioning skipped pending list until remote verification is available"
          )
          continue
        }
      } else if ReminderPendingBindingStore.hasProjectBindingForPage(
        pageFileURL: page.fileURL,
        now: now
      ) {
        AppLogger.sync.info(
          "logseq provisioning skipped page with unmatched pending list binding"
        )
        continue
      }

      if let resolvedListIdentifier {
        listIdentifier = resolvedListIdentifier
      } else {
        guard mode == .fullPush else {
          continue
        }
        guard page.usesProjectTag else { continue }
        let createdList = try reminderProjectProvider.createProjectList(title: page.title)
        listIdentifier = createdList.externalIdentifier
        ReminderPendingBindingStore.upsertProjectBinding(
          pageFileURL: page.fileURL,
          pageTitle: page.title,
          reminderListExternalIdentifier: listIdentifier,
          now: now
        )
        createdProjectCount += 1
      }

      let projectID = RetainedProjectionBuilder.derivedProjectID(for: listIdentifier)
      let prefetchedRemoteSnapshotsByExternalIdentifier =
        await remoteTaskSnapshotsByExternalIdentifier(
          inListIdentifier: listIdentifier,
          reminderProjectProvider: reminderProjectProvider
        )
      var taskIdentifiersByIndex: [Int: String] = [:]
      let blockedReminderIdentifiers = duplicatedReminderIdentifiers(in: page.externalTasks)

      for (taskIndex, task) in page.externalTasks.enumerated() {
        guard !task.hasAmbiguousReminderExternalIdentifier else {
          AppLogger.sync.error(
            "logseq provisioning skipped ambiguous reminder task id title=\(task.title, privacy: .public)"
          )
          continue
        }
        if let reminderExternalIdentifier = normalized(task.reminderExternalIdentifier) {
          guard !blockedReminderIdentifiers.contains(reminderExternalIdentifier) else {
            continue
          }
          guard mode == .fullPush else {
            continue
          }
          try applyExistingReminderUpdates(
            task,
            projectID: projectID,
            reminderExternalIdentifier: reminderExternalIdentifier,
            prefetchedRemoteSnapshot:
              prefetchedRemoteSnapshotsByExternalIdentifier?[reminderExternalIdentifier],
            reminderProjectProvider: reminderProjectProvider,
            taskRecords: &taskRecords,
            now: now
          )
          continue
        }

        if let pendingBinding = ReminderPendingBindingStore.taskBinding(
          pageFileURL: page.fileURL,
          listExternalIdentifier: listIdentifier,
          taskIndex: taskIndex,
          task: task,
          now: now
        ) {
          guard let prefetchedRemoteSnapshotsByExternalIdentifier else {
            AppLogger.sync.info(
              "logseq provisioning skipped pending task until remote verification is available"
            )
            continue
          }
          if remoteTaskBindingMatches(
            pendingBinding,
            listIdentifier: listIdentifier,
            snapshotsByExternalIdentifier: prefetchedRemoteSnapshotsByExternalIdentifier
          ) {
            let taskIdentifier = pendingBinding.reminderExternalIdentifier
            taskIdentifiersByIndex[taskIndex] = taskIdentifier
            taskRecords.append(
              TaskIdentityBridgeRecord(
                taskID: ReminderProjectionIdentity.taskID(for: taskIdentifier),
                title: task.title,
                reminderExternalIdentifier: taskIdentifier,
                ownerProjectID: projectID,
                createdAt: now,
                updatedAt: now
              )
            )
            continue
          }
        } else if ReminderPendingBindingStore.hasTaskBindingForPageListIndex(
          pageFileURL: page.fileURL,
          listExternalIdentifier: listIdentifier,
          taskIndex: taskIndex,
          now: now
        ) {
          AppLogger.sync.info(
            "logseq provisioning skipped task with unmatched pending binding"
          )
          continue
        }

        guard mode == .fullPush else {
          continue
        }
        let decodedDate = LogseqReminderPropertyCodec.decodeDate(task.date)
        guard let metadata = try reminderProjectProvider.createTaskReminder(
          inProject: listIdentifier,
          title: task.title,
          dueDate: decodedDate?.date,
          hasExplicitTime: decodedDate?.hasExplicitTime ?? false,
          noteText: task.noteText ?? ""
        ) else {
          continue
        }
        let taskIdentifier = metadata.externalIdentifier ?? metadata.identifier
        taskIdentifiersByIndex[taskIndex] = taskIdentifier
        ReminderPendingBindingStore.upsertTaskBinding(
          pageFileURL: page.fileURL,
          listExternalIdentifier: listIdentifier,
          taskIndex: taskIndex,
          task: task,
          reminderExternalIdentifier: taskIdentifier,
          now: now
        )
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
        ReminderSyncBaselineStore.upsert(
          reminderExternalIdentifier: taskIdentifier,
          state: ReminderSyncTaskState(task: task),
          remoteModifiedAt: metadata.modifiedAt,
          now: now
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
        if page.reminderListExternalIdentifier == nil {
          ReminderPendingBindingStore.removeProjectBinding(
            pageFileURL: page.fileURL,
            pageTitle: page.title
          )
        }
        for (taskIndex, _) in taskIdentifiersByIndex {
          ReminderPendingBindingStore.removeTaskBinding(
            pageFileURL: page.fileURL,
            listExternalIdentifier: listIdentifier,
            taskIndex: taskIndex,
            task: page.externalTasks[taskIndex]
          )
        }
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
    prefetchedRemoteSnapshot: ReminderTaskRemoteSnapshot?,
    reminderProjectProvider: ReminderProjectProvider,
    taskRecords: inout [TaskIdentityBridgeRecord],
    now: Date
  ) throws {
    let taskID = ReminderProjectionIdentity.taskID(for: reminderExternalIdentifier)
    let reference = ReminderTaskReference(
      taskID: taskID,
      reminderIdentifier: prefetchedRemoteSnapshot?.identifier,
      reminderExternalIdentifier: reminderExternalIdentifier
    )

    let snapshot: ReminderTaskRemoteSnapshot?
    if let prefetchedRemoteSnapshot {
      snapshot = prefetchedRemoteSnapshot
    } else {
      snapshot = try reminderProjectProvider.taskSnapshot(for: reference)
    }
    guard let snapshot else {
      AppLogger.sync.info(
        "logseq reminder push skipped missing remote snapshot external=\(reminderExternalIdentifier, privacy: .public)"
      )
      return
    }
    guard let baseline = ReminderSyncBaselineStore.baseline(for: reminderExternalIdentifier) else {
      AppLogger.sync.info(
        "logseq reminder push skipped missing baseline external=\(reminderExternalIdentifier, privacy: .public)"
      )
      return
    }
    let fieldsToPush = ReminderSyncTaskMerge.fieldsToPush(
      localTask: task,
      remoteSnapshot: snapshot,
      baseline: baseline
    )
    guard !fieldsToPush.isEmpty else {
      return
    }
    let pushedFieldNames = fieldsToPush.map(\.rawValue).joined(separator: ",")
    AppLogger.sync.info(
      "logseq reminder push fields=\(pushedFieldNames, privacy: .public) external=\(reminderExternalIdentifier, privacy: .public)"
    )

    var updatedAt: Date?
    var pushedFields: [ReminderSyncTaskField] = []
    if fieldsToPush.contains(.title), normalized(snapshot.title) != normalized(task.title) {
      let metadata = try reminderProjectProvider.setTaskTitle(
        for: reference,
        title: task.title
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
      pushedFields.append(.title)
    }

    if fieldsToPush.contains(.isCompleted), snapshot.isCompleted != task.isCompleted {
      let metadata = try reminderProjectProvider.setTaskCompletion(
        for: reference,
        isCompleted: task.isCompleted,
        completionDate: nil
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
      pushedFields.append(.isCompleted)
    }

    if fieldsToPush.contains(.noteText),
      shouldWriteReminderNote(
        localNoteText: task.noteText,
        remoteNoteText: snapshot.noteText,
        allowEmptyLocalWrite: true
      )
    {
      let metadata = try reminderProjectProvider.setTaskReminderNote(
        for: reference,
        noteText: task.noteText ?? ""
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
      pushedFields.append(.noteText)
    }

    let desiredDate = LogseqReminderPropertyCodec.decodeDate(task.date)
    if fieldsToPush.contains(.date),
      encodedDate(snapshot.dueDate, hasExplicitTime: snapshot.hasExplicitTime)
      != encodedDate(desiredDate?.date, hasExplicitTime: desiredDate?.hasExplicitTime ?? false)
    {
      let metadata = try reminderProjectProvider.setTaskSchedule(
        for: reference,
        dueDate: desiredDate?.date,
        hasExplicitTime: desiredDate?.hasExplicitTime ?? false
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
      pushedFields.append(.date)
    }

    let desiredRecurrence = LogseqReminderPropertyCodec.decodeRepeat(task.repeatRule)
    let remoteRecurrence = LogseqReminderPropertyCodec.decodeRepeat(snapshot.recurrenceRuleRaw)
    if fieldsToPush.contains(.repeatRule), desiredRecurrence != remoteRecurrence {
      let metadata = try reminderProjectProvider.setTaskRecurrence(
        for: reference,
        recurrenceRuleRaw: desiredRecurrence
      )
      updatedAt = metadata?.modifiedAt ?? updatedAt
      pushedFields.append(.repeatRule)
    }

    guard let updatedAt else { return }
    let nextBaseline = ReminderSyncTaskMerge.baselineAfterPush(
      previous: baseline,
      localTask: task,
      remoteSnapshot: snapshot,
      pushedFields: pushedFields
    )
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: reminderExternalIdentifier,
      state: nextBaseline.state,
      remoteModifiedAt: updatedAt,
      conflictedFields: nextBaseline.conflicts,
      now: now
    )
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

  private static func remoteTaskSnapshotsByExternalIdentifier(
    inListIdentifier listIdentifier: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async -> [String: ReminderTaskRemoteSnapshot]? {
    guard let batch = try? await reminderProjectProvider.fetchImportSnapshotBatch(
      forListIdentifiers: [listIdentifier]
    ) else {
      return nil
    }

    let items = batch.itemsByListIdentifier[listIdentifier] ?? []
    var snapshotsByIdentifier: [String: ReminderTaskRemoteSnapshot] = [:]
    var duplicatedIdentifiers: Set<String> = []

    for item in items {
      guard let reminderExternalIdentifier = normalized(item.externalIdentifier)
        ?? normalized(item.identifier)
      else {
        continue
      }
      if snapshotsByIdentifier[reminderExternalIdentifier] != nil {
        duplicatedIdentifiers.insert(reminderExternalIdentifier)
        snapshotsByIdentifier.removeValue(forKey: reminderExternalIdentifier)
        continue
      }
      guard !duplicatedIdentifiers.contains(reminderExternalIdentifier) else {
        continue
      }
      snapshotsByIdentifier[reminderExternalIdentifier] = ReminderTaskRemoteSnapshot(
        identifier: item.identifier,
        externalIdentifier: reminderExternalIdentifier,
        calendarIdentifier: item.sourceListIdentifier,
        title: item.title,
        noteText: ReminderNoteSourceCodec.normalizeReminderRawNote(item.notes),
        isCompleted: item.isCompleted,
        completionDate: item.completionDate,
        startDate: item.startDate,
        dueDate: item.dueDate,
        hasExplicitTime: item.scheduleHasExplicitTime,
        priority: item.priority,
        recurrenceRuleRaw: item.recurrenceRuleRaw,
        modifiedAt: item.modifiedAt
      )
    }

    return snapshotsByIdentifier
  }

  private static func remoteListPresence(
    _ binding: ReminderPendingProjectBinding,
    _ listIdentifier: String,
    reminderProjectProvider: ReminderProjectProvider
  ) async -> RemoteBindingPresence {
    guard let batch = try? await reminderProjectProvider.fetchImportSnapshotBatch(
      forListIdentifiers: [listIdentifier]
    ) else {
      return .unavailable
    }
    return batch.lists.contains {
      ($0.identifier == listIdentifier || $0.externalIdentifier == listIdentifier)
        && fingerprint($0.title) == binding.pageTitleFingerprint
    } ? .exists : .missing
  }

  private static func remoteTaskBindingMatches(
    _ binding: ReminderPendingTaskBinding,
    listIdentifier: String,
    snapshotsByExternalIdentifier: [String: ReminderTaskRemoteSnapshot]
  ) -> Bool {
    guard let snapshot = snapshotsByExternalIdentifier[binding.reminderExternalIdentifier] else {
      return false
    }
    return snapshot.calendarIdentifier == listIdentifier
      && fingerprint(snapshot.title) == binding.taskTitleFingerprint
  }

  private static func fingerprint(_ value: String) -> String {
    value
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .lowercased()
  }

  private static func encodedDate(_ date: Date?, hasExplicitTime: Bool) -> String? {
    LogseqReminderPropertyCodec.encodeDate(date, hasExplicitTime: hasExplicitTime)
  }

  private static func shouldWriteReminderNote(
    localNoteText: String?,
    remoteNoteText: String,
    allowEmptyLocalWrite: Bool = false
  ) -> Bool {
    let local = ReminderNoteSourceCodec.normalize(localNoteText)
    let remote = ReminderNoteSourceCodec.normalize(remoteNoteText)
    guard local != remote else { return false }
    if allowEmptyLocalWrite { return true }
    return !local.isEmpty || remote.isEmpty
  }

  private static func duplicatedReminderIdentifiers(
    in tasks: [LogseqProjectPageStore.TaskRecord]
  ) -> Set<String> {
    var seen: Set<String> = []
    var duplicates: Set<String> = []
    for task in tasks {
      guard let reminderExternalIdentifier = normalized(task.reminderExternalIdentifier) else {
        continue
      }
      if !seen.insert(reminderExternalIdentifier).inserted {
        duplicates.insert(reminderExternalIdentifier)
      }
    }
    return duplicates
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
