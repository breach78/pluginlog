import Foundation

private enum ReminderOwnerCommandError: LocalizedError {
  case scopedRecomputeFailed

  var errorDescription: String? {
    switch self {
    case .scopedRecomputeFailed:
      return "Reminder owner change scoped recompute failed"
    }
  }
}

@MainActor
extension AppState {
  @discardableResult
  func handleReminderOwnerFieldWrite(
    _ write: AppOwnerFieldWrite,
    waitForEditorIdle: Bool
  ) async -> Bool {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else { return false }
    }

    let reminderProjectProvider = reminderProjectProvider

    do {
      switch write {
      case let .listMetadata(write):
        switch write.mutation {
        case let .title(rawTitle):
          let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
          let resolvedTitle = title.isEmpty ? OutlinerProject.defaultTitle : title
          guard try reminderProjectProvider.setProjectTitle(
            identifier: write.reminderListIdentifier,
            title: resolvedTitle
          ) != nil else {
            syncStatus = "Reminder list metadata write skipped (owner unresolved)"
            return false
          }

        case let .colorHex(colorHex):
          guard try reminderProjectProvider.setProjectColor(
            identifier: write.reminderListIdentifier,
            colorHex: colorHex
          ) != nil else {
            syncStatus = "Reminder list metadata write skipped (owner unresolved)"
            return false
          }
        }

          return await applyReminderOwnerScopedRecompute(
            ownerIDs: [write.reminderListIdentifier, write.reminderListExternalIdentifier]
              .compactMap(normalizedProjectionValue),
            changedFields: [.listMetadata],
            successStatusPrefix: "Reminder list metadata",
            fallbackProjectIDs: [write.projectID]
          )

      case let .taskFields(write):
        let taskReference = ReminderTaskReference(
          taskID: write.taskID,
          reminderIdentifier: normalizedProjectionValue(write.reminderIdentifier),
          reminderExternalIdentifier: normalizedProjectionValue(write.reminderExternalIdentifier)
        )

        switch write.mutation {
        case let .title(rawTitle):
          let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !title.isEmpty else {
            syncStatus = "Reminder task write skipped (invalid title)"
            return false
          }
          guard try reminderProjectProvider.setTaskTitle(
            for: taskReference,
            title: title
          ) != nil else {
            syncStatus = "Reminder task write skipped (owner unresolved)"
            return false
          }
          return await applyReminderOwnerScopedRecompute(
            ownerIDs: reminderTaskOwnerIDs(for: write),
            changedFields: [.taskFields],
            successStatusPrefix: "Reminder task",
            fallbackProjectIDs: [write.projectID]
          )

        case let .note(note):
          guard try reminderProjectProvider.setTaskReminderNote(
            for: taskReference,
            noteText: ReminderNoteSourceCodec.normalize(note)
          ) != nil else {
            syncStatus = "Reminder task write skipped (owner unresolved)"
            return false
          }
          return await applyReminderOwnerScopedRecompute(
            ownerIDs: reminderTaskOwnerIDs(for: write),
            changedFields: [.taskFields],
            successStatusPrefix: "Reminder task",
            fallbackProjectIDs: [write.projectID]
          )

        case let .schedule(dueDate, hasExplicitTime):
          guard try reminderProjectProvider.setTaskSchedule(
            for: taskReference,
            dueDate: dueDate,
            hasExplicitTime: hasExplicitTime
          ) != nil else {
            syncStatus = "Reminder task write skipped (owner unresolved)"
            return false
          }
          return await applyReminderOwnerScopedRecompute(
            ownerIDs: reminderTaskOwnerIDs(for: write),
            changedFields: [.taskFields],
            successStatusPrefix: "Reminder task",
            fallbackProjectIDs: [write.projectID]
          )

        case let .recurrence(recurrenceRuleRaw):
          guard try reminderProjectProvider.setTaskRecurrence(
            for: taskReference,
            recurrenceRuleRaw: recurrenceRuleRaw
          ) != nil else {
            syncStatus = "Reminder task write skipped (owner unresolved)"
            return false
          }
          return await applyReminderOwnerScopedRecompute(
            ownerIDs: reminderTaskOwnerIDs(for: write),
            changedFields: [.taskFields],
            successStatusPrefix: "Reminder task",
            fallbackProjectIDs: [write.projectID]
          )

        case let .presentationPriority(priority):
          let normalizedPriority = max(0, min(9, priority))
          guard try reminderProjectProvider.setTaskPresentation(
            for: taskReference,
            priority: normalizedPriority
          ) != nil else {
            syncStatus = "Reminder task write skipped (owner unresolved)"
            return false
          }
          return await applyReminderOwnerScopedRecompute(
            ownerIDs: reminderTaskOwnerIDs(for: write),
            changedFields: [.taskFields],
            successStatusPrefix: "Reminder task",
            fallbackProjectIDs: [write.projectID]
          )

        case let .completion(isCompleted, completionDate):
          let resolvedCompletionDate = isCompleted ? (completionDate ?? .now) : nil
          guard try reminderProjectProvider.setTaskCompletion(
            for: taskReference,
            isCompleted: isCompleted,
            completionDate: resolvedCompletionDate
          ) != nil else {
            syncStatus = "Reminder task write skipped (owner unresolved)"
            return false
          }
          return await applyReminderOwnerScopedRecompute(
            ownerIDs: reminderTaskOwnerIDs(for: write),
            changedFields: [.taskFields],
            successStatusPrefix: "Reminder task",
            fallbackProjectIDs: [write.projectID]
          )
        }

      case .reminderListBinding,
        .removeReminderListBinding,
        .projectMetadata,
        .treeStructure,
        .ordering,
        .appSupplement,
        .eventFields:
        syncStatus = "Reminder owner write skipped (unsupported field)"
        return false
      }
    } catch {
      reportError(error, logMessage: "handleReminderOwnerFieldWrite failed")
      return false
    }
  }

  @discardableResult
  func handleReminderExternalOwnerChange(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool
  ) async -> Bool {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else { return false }
    }

    let handledListMetadata = changedFields.contains(.listMetadata)
    let handledTaskFields =
      changedFields.contains(.taskFields)
      || changedFields.contains(.title)
      || changedFields.contains(.isCompleted)
      || changedFields.contains(.note)
      || changedFields.contains(.dueDate)
      || changedFields.contains(.recurrence)
      || changedFields.contains(.metadata)
    guard handledListMetadata || handledTaskFields else {
      syncStatus = "Reminder external change skipped (unsupported field)"
      return false
    }

    return await applyReminderOwnerScopedRecompute(
      ownerIDs: ownerIDs.compactMap(normalizedProjectionValue),
      changedFields: changedFields,
      successStatusPrefix: "Scoped reminder refresh"
    )
  }

  private func applyReminderOwnerScopedRecompute(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    successStatusPrefix: String,
    fallbackProjectIDs: Set<UUID> = []
  ) async -> Bool {
    let normalizedOwnerIDs = Array(NSOrderedSet(array: ownerIDs.compactMap(normalizedProjectionValue)))
      as? [String] ?? []
    guard !normalizedOwnerIDs.isEmpty || !fallbackProjectIDs.isEmpty else {
      syncStatus = "Reminder owner change skipped (scope unresolved)"
      return false
    }

    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else {
      syncStatus = "Reminder owner change skipped (projection unavailable)"
      return false
    }

    var payload = loadRuntimeProjectionSidecarPayload()
    let disconnectedProjectIDs = payload.cutDuplicateProjectReminderConnections()
    let affectedProjectIDs = affectedReminderProjectIDs(
      ownerIDs: normalizedOwnerIDs,
      changedFields: changedFields,
      snapshot: snapshot,
      payload: payload
    )
    let resolvedAffectedProjectIDs = affectedProjectIDs
      .union(fallbackProjectIDs)
      .union(disconnectedProjectIDs)
    guard !resolvedAffectedProjectIDs.isEmpty else {
      syncStatus = "Reminder owner change skipped (scope unresolved)"
      return false
    }

    let scopedProjectIDs = resolvedAffectedProjectIDs.intersection(Set(snapshot.projects.map(\.id)))
    if let anchorProjectID = scopedProjectIDs.sorted(by: { $0.uuidString < $1.uuidString }).first,
      let store = projectDocumentStore(for: anchorProjectID)
    {
      guard await patchRuntimeProjectionProjects(
        from: store,
        projectIDs: scopedProjectIDs,
        snapshot: &snapshot,
        payload: &payload
      ) else {
        syncStatus = "Reminder owner change skipped (scoped recompute failed)"
        return false
      }
    }

    await invalidateWorkspaceProjectCaches(for: resolvedAffectedProjectIDs)
    await syncWorkspaceProjectIdentities(for: resolvedAffectedProjectIDs, snapshot: snapshot)
    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    saveRuntimeProjectionSidecarPayload(payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
    await persistManagedLogseqPages(for: resolvedAffectedProjectIDs, snapshot: snapshot)
    bumpWorkspaceTreeRevision()
    syncStarted = true
    syncStatus = "\(successStatusPrefix) (\(resolvedAffectedProjectIDs.count) project)"
    return true
  }

  func removeReminderTasks(
    _ references: [ReminderTaskReference],
    waitForEditorIdle: Bool = false
  ) async throws -> [ReminderTaskReference] {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else { return [] }
    }

    var normalizedReferences: [ReminderTaskReference] = []
    var seenTaskIDs = Set<UUID>()
    for reference in references where
      normalizedProjectionValue(reference.reminderIdentifier) != nil
        || normalizedProjectionValue(reference.reminderExternalIdentifier) != nil
    {
      guard seenTaskIDs.insert(reference.taskID).inserted else { continue }
      normalizedReferences.append(reference)
    }

    guard !normalizedReferences.isEmpty else { return [] }

    var removedReferences: [ReminderTaskReference] = []
    for reference in normalizedReferences {
      guard try reminderProjectProvider.removeTaskReminder(for: reference) else { continue }
      removedReferences.append(reference)
    }
    guard !removedReferences.isEmpty else { return [] }

    let ownerIDs =
      Array(
        NSOrderedSet(
          array: removedReferences.flatMap { reference in
            [
              normalizedProjectionValue(reference.reminderIdentifier),
              normalizedProjectionValue(reference.reminderExternalIdentifier),
            ].compactMap { $0 }
          }
        )
      ) as? [String] ?? []

    guard
      await handleReminderExternalOwnerChange(
        ownerIDs: ownerIDs,
        changedFields: [.taskFields],
        waitForEditorIdle: false
      )
    else {
      throw ReminderOwnerCommandError.scopedRecomputeFailed
    }
    return removedReferences
  }

  private func affectedReminderProjectIDs(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    snapshot: OutlineProjectionRuntimeSnapshot,
    payload: ReminderProjectionSidecarPayload
  ) -> Set<UUID> {
    let normalizedOwnerIDs = Set(ownerIDs.compactMap(normalizedProjectionValue))
    guard !normalizedOwnerIDs.isEmpty else { return [] }

    var projectIDs: Set<UUID> = []
    if changedFields.contains(.listMetadata) {
      projectIDs.formUnion(payload.affectedProjectIDs(forOwnerIDs: ownerIDs))
    }

    let handlesTaskFields =
      changedFields.contains(.taskFields)
      || changedFields.contains(.title)
      || changedFields.contains(.isCompleted)
      || changedFields.contains(.note)
      || changedFields.contains(.dueDate)
      || changedFields.contains(.recurrence)
      || changedFields.contains(.metadata)
    if handlesTaskFields {
      projectIDs.formUnion(payload.affectedProjectIDs(forOwnerIDs: ownerIDs))
      projectIDs.formUnion(
        affectedReminderTaskProjectIDs(
          ownerIDs: normalizedOwnerIDs,
          snapshot: snapshot
        )
      )
    }

    return projectIDs
  }

  private func affectedReminderTaskProjectIDs(
    ownerIDs: Set<String>,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> Set<UUID> {
    guard !ownerIDs.isEmpty else { return [] }

    var projectIDs: Set<UUID> = []
    var unresolvedOwnerIDs = ownerIDs

    for ownerID in ownerIDs {
      guard let taskID = TaskIdentityBridgeStore.taskID(for: ownerID) else { continue }
      if let location = snapshot.taskLocation(for: taskID) {
        projectIDs.insert(snapshot.projects[location.projectIndex].id)
        unresolvedOwnerIDs.remove(ownerID)
        continue
      }
      if let ownerProjectID = TaskIdentityBridgeStore.record(for: taskID)?.ownerProjectID {
        projectIDs.insert(ownerProjectID)
        unresolvedOwnerIDs.remove(ownerID)
      }
    }

    guard !unresolvedOwnerIDs.isEmpty else { return projectIDs }

    let projectIDsByOwnerID = reminderTaskProjectIDsByOwnerID(in: snapshot)
    for ownerID in unresolvedOwnerIDs {
      projectIDs.formUnion(projectIDsByOwnerID[ownerID] ?? [])
    }

    return projectIDs
  }

  private func reminderTaskProjectIDsByOwnerID(
    in snapshot: OutlineProjectionRuntimeSnapshot
  ) -> [String: Set<UUID>] {
    var projectIDsByOwnerID: [String: Set<UUID>] = [:]

    for project in snapshot.projects {
      for entry in project.document.flatten() where entry.node.type.isTask {
        if let reminderIdentifier = normalizedProjectionValue(entry.node.reminderIdentifier) {
          projectIDsByOwnerID[reminderIdentifier, default: []].insert(project.id)
        }
        if let reminderExternalIdentifier = normalizedProjectionValue(
          entry.node.reminderExternalIdentifier
        ) {
          projectIDsByOwnerID[reminderExternalIdentifier, default: []].insert(project.id)
        }
      }
    }

    return projectIDsByOwnerID
  }

  private func reminderTaskOwnerIDs(for write: ReminderTaskFieldsWrite) -> [String] {
    [write.reminderIdentifier, write.reminderExternalIdentifier]
      .compactMap(normalizedProjectionValue)
  }
}
