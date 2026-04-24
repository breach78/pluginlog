import Foundation

private enum CalendarOwnerCommandError: LocalizedError {
  case unsupportedField
  case unsupportedCommand
  case scopedRecomputeFailed

  var errorDescription: String? {
    switch self {
    case .unsupportedField:
      return "Calendar owner write skipped (unsupported field)"
    case .unsupportedCommand:
      return "Calendar owner command skipped (unsupported command)"
    case .scopedRecomputeFailed:
      return "Calendar owner change scoped recompute failed"
    }
  }
}

private struct CalendarEventOwnerDescriptor: Sendable {
  let ownerID: String
  let calendarIdentifier: String
  let lowerBound: Date
  let upperBound: Date

  var range: ClosedRange<Date> {
    min(lowerBound, upperBound)...max(lowerBound, upperBound)
  }
}

@MainActor
extension AppState {
  @discardableResult
  func handleCalendarOwnerFieldWrite(
    _ write: AppOwnerFieldWrite,
    waitForEditorIdle: Bool
  ) async -> Bool {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else { return false }
    }

    do {
      _ = try await executeCalendarOwnerFieldWrite(write)
      syncStatus = "Calendar event updated"
      return true
    } catch let error as CalendarOwnerCommandError {
      syncStatus = error.localizedDescription
      errorMessage = error.localizedDescription
      return false
    } catch let error as ScheduleCalendarEditError {
      syncStatus = "Calendar event write failed"
      errorMessage = error.localizedDescription
      return false
    } catch {
      reportError(error, logMessage: "handleCalendarOwnerFieldWrite failed")
      return false
    }
  }

  @discardableResult
  func handleCalendarExternalOwnerChange(
    ownerIDs: [String],
    changedFields: [AppOwnerField],
    waitForEditorIdle: Bool
  ) async -> Bool {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else { return false }
    }

    let handledEventFields = AppOwnerField.calendarEventExternalChangeFields.contains {
      changedFields.contains($0)
    }
    guard handledEventFields else {
      syncStatus = "Calendar external change skipped (unsupported field)"
      return false
    }

    let normalizedOwnerIDs = Array(
      NSOrderedSet(array: ownerIDs.compactMap(normalizedProjectionValue))
    ) as? [String] ?? []
    guard !normalizedOwnerIDs.isEmpty else {
      syncStatus = "Calendar external change skipped (scope unresolved)"
      return false
    }

    if await applyOwnedCalendarExternalChanges(ownerIDs: normalizedOwnerIDs) {
      syncStatus = "Owned calendar task refresh"
      return true
    }

    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else {
      syncStatus = "Calendar external change skipped (projection unavailable)"
      return false
    }

    var payload = loadRuntimeProjectionSidecarPayload()
    let disconnectedProjectIDs = payload.cutDuplicateProjectReminderConnections()
    let affectedProjectIDs = affectedCalendarEventProjectIDs(
      ownerIDs: normalizedOwnerIDs,
      snapshot: snapshot
    )
    .union(disconnectedProjectIDs)
    guard !affectedProjectIDs.isEmpty else {
      syncStatus = "Calendar external change skipped (scope unresolved)"
      return false
    }

    let scopedProjectIDs = affectedProjectIDs.intersection(Set(snapshot.projects.map(\.id)))
    if let anchorProjectID = scopedProjectIDs.sorted(by: { $0.uuidString < $1.uuidString }).first,
      let store = projectDocumentStore(for: anchorProjectID)
    {
      guard await patchRuntimeProjectionProjects(
        from: store,
        projectIDs: scopedProjectIDs,
        snapshot: &snapshot,
        payload: &payload
      ) else {
        syncStatus = "Calendar external change skipped (scoped recompute failed)"
        return false
      }
    }

    await invalidateWorkspaceProjectCaches(for: affectedProjectIDs)
    await syncWorkspaceProjectIdentities(for: affectedProjectIDs, snapshot: snapshot)
    syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
    saveRuntimeProjectionSidecarPayload(payload)
    installCachedRuntimeProjectionSnapshot(snapshot)
    bumpWorkspaceTreeRevision()
    syncStarted = true
    syncStatus = "Scoped calendar refresh (\(affectedProjectIDs.count) project)"
    return true
  }

  func writeScheduleCalendarEventTiming(
    _ event: ScheduleCalendarEvent,
    preview: ScheduleInteractionPreview,
    scope: ScheduleCalendarRecurringEditScope
  ) async throws -> ScheduleCalendarEvent {
    let command = AppCommand.writeOwnerField(
      ownerStore: .calendar,
      write: .eventFields(
        CalendarEventFieldsWrite(
          event: event,
          mutation: .timing(
            preview: preview,
            scope: scope
          )
        )
      )
    )
    let updatedEvent = try await executeCalendarOwnerCommand(command)
    try await applyCalendarMutationScopedRecompute(ownerIDs: [calendarEventOwnerID(for: updatedEvent)])
    return updatedEvent
  }

  func deleteScheduleCalendarEvent(
    _ event: ScheduleCalendarEvent,
    scope: ScheduleCalendarRecurringEditScope,
    waitForEditorIdle: Bool = false
  ) async throws -> DeletedScheduleCalendarEventSnapshot {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else {
        throw CalendarOwnerCommandError.scopedRecomputeFailed
      }
    }

    let snapshot = try await calendarServiceRegistry.scheduleCalendarService.delete(
      event,
      scope: scope
    )
    try await applyCalendarMutationScopedRecompute(ownerIDs: [calendarEventOwnerID(for: event)])
    return snapshot
  }

  func restoreDeletedScheduleCalendarEvent(
    _ snapshot: DeletedScheduleCalendarEventSnapshot,
    waitForEditorIdle: Bool = false
  ) async throws -> ScheduleCalendarEvent {
    if waitForEditorIdle, (isEditorActive || !activeExplicitEditorSessionIDs.isEmpty) {
      guard await waitForEditorToBecomeIdle() else {
        throw CalendarOwnerCommandError.scopedRecomputeFailed
      }
    }

    let restoredEvent = try await calendarServiceRegistry.scheduleCalendarService.restoreDeletedEvent(
      snapshot
    )
    try await applyCalendarMutationScopedRecompute(ownerIDs: [calendarEventOwnerID(for: restoredEvent)])
    return restoredEvent
  }

  private func executeCalendarOwnerCommand(
    _ command: AppCommand
  ) async throws -> ScheduleCalendarEvent {
    guard case let .writeOwnerField(ownerStore, write) = command,
      ownerStore == .calendar
    else {
      throw CalendarOwnerCommandError.unsupportedCommand
    }
    return try await executeCalendarOwnerFieldWrite(write)
  }

  private func executeCalendarOwnerFieldWrite(
    _ write: AppOwnerFieldWrite
  ) async throws -> ScheduleCalendarEvent {
    guard case let .eventFields(eventWrite) = write else {
      throw CalendarOwnerCommandError.unsupportedField
    }

    return try await calendarServiceRegistry.scheduleCalendarService.applyOwnerFieldWrite(
      eventWrite
    )
  }

  private func affectedCalendarEventProjectIDs(
    ownerIDs: [String],
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> Set<UUID> {
    let ownerDescriptors = calendarEventOwnerDescriptors(ownerIDs)
    guard !ownerDescriptors.isEmpty else { return [] }

    let rangeIndex = calendarEventRangeIndex(in: snapshot)
    guard !rangeIndex.isEmpty else { return [] }

    var projectIDs: Set<UUID> = []
    for descriptor in ownerDescriptors {
      for (projectID, indexedRanges) in rangeIndex {
        if indexedRanges.contains(where: { calendarEventRangesOverlap($0, descriptor.range) }) {
          projectIDs.insert(projectID)
        }
      }
    }
    return projectIDs
  }

  private func calendarEventOwnerDescriptors(
    _ ownerIDs: [String]
  ) -> [CalendarEventOwnerDescriptor] {
    ownerIDs.compactMap { ownerID in
      let components = ownerID.split(separator: "|", omittingEmptySubsequences: false)
      guard components.count >= 4,
        let lowerInterval = TimeInterval(components[components.count - 2]),
        let upperInterval = TimeInterval(components[components.count - 1])
      else {
        return nil
      }

      return CalendarEventOwnerDescriptor(
        ownerID: ownerID,
        calendarIdentifier: String(components[0]),
        lowerBound: Date(timeIntervalSinceReferenceDate: lowerInterval),
        upperBound: Date(timeIntervalSinceReferenceDate: upperInterval)
      )
    }
  }

  private func calendarEventRangeIndex(
    in snapshot: OutlineProjectionRuntimeSnapshot
  ) -> [UUID: [ClosedRange<Date>]] {
    let projectIDs = snapshot.projects.map(\.id)
    guard !projectIDs.isEmpty else { return [:] }

    let projection = ReminderRuntimeProjectionReadModelService.workspaceSurfaceProjection(
      projectIDs: projectIDs,
      runtimeSnapshot: snapshot
    )
    let taskDescriptors = ScheduleProjectionService.taskDescriptors(
      projectIDs: projectIDs,
      projectSnapshots: projection.projectSnapshots,
      scheduleEntriesByProjectID: projection.scheduleEntriesByProjectID
    )
    let taskEvents = WorkspaceTaskScheduleEventStore.items(from: taskDescriptors)

    return taskEvents.reduce(into: [UUID: [ClosedRange<Date>]]()) { partialResult, event in
      guard case let .workspaceTask(_, projectID) = event.source else { return }
      let upperBound = max(event.startDate, event.endDate)
      partialResult[projectID, default: []].append(event.startDate...upperBound)
    }
  }

  private func calendarEventRangesOverlap(
    _ lhs: ClosedRange<Date>,
    _ rhs: ClosedRange<Date>
  ) -> Bool {
    lhs.lowerBound <= rhs.upperBound && rhs.lowerBound <= lhs.upperBound
  }

  private func applyCalendarMutationScopedRecompute(ownerIDs: [String]) async throws {
    guard
      await handleCalendarExternalOwnerChange(
        ownerIDs: ownerIDs,
        changedFields: AppOwnerField.calendarEventExternalChangeFields,
        waitForEditorIdle: false
      )
    else {
      throw CalendarOwnerCommandError.scopedRecomputeFailed
    }
  }

  private func calendarEventOwnerID(for event: ScheduleCalendarEvent) -> String {
    ScheduleCalendarOwnerIDCodec.ownerID(for: event)
  }
}
