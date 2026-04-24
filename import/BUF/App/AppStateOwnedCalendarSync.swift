import Foundation

@MainActor
extension AppState {
  @discardableResult
  func syncOwnedCalendarEvents(
    for projectIDs: Set<UUID>
  ) async -> Bool {
    guard !projectIDs.isEmpty else { return false }
    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else { return false }

    let resolvedProjectIDs = projectIDs.intersection(Set(snapshot.projects.map(\.id)))
    guard !resolvedProjectIDs.isEmpty else { return false }

    let bindings = ownedCalendarBindings(for: resolvedProjectIDs, snapshot: snapshot)
    let ambiguousOwnedEventIdentifiers =
      ManagedLogseqSyncHardening.ambiguousOwnedCalendarEventIdentifiers(
        resolvedProjectIDs
          .sorted(by: { $0.uuidString < $1.uuidString })
          .compactMap { projectID in
            snapshot.projects.first(where: { $0.id == projectID })
          }
          .flatMap { runtimeLogseqTaskBindings(for: $0, snapshot: snapshot) }
      )
    var payload = loadRuntimeProjectionSidecarPayload()
    var ownedCalendarDescriptor: OwnedScheduleCalendarDescriptor?
    var didMutateSidecar = false

    do {
      for binding in bindings {
        if let calendarEventExternalIdentifier = normalizedProjectionValue(
          binding.calendarEventExternalIdentifier
        ),
          ambiguousOwnedEventIdentifiers.contains(calendarEventExternalIdentifier)
        {
          AppLogger.sync.error(
            "syncOwnedCalendarEvents skipped ambiguous owned calendar event identifier"
          )
          continue
        }
        if let request = binding.upsertRequest {
          let descriptor = try await resolvedOwnedCalendarDescriptor(
            existing: &ownedCalendarDescriptor
          )
          let event = try await calendarServiceRegistry.scheduleCalendarService.upsertOwnedEvent(
            request,
            calendarIdentifier: descriptor.calendarIdentifier
          )
          let resolvedIdentifier =
            normalizedProjectionValue(event.externalIdentifier)
            ?? normalizedProjectionValue(event.eventIdentifier)
          if updateOwnedCalendarEventIdentifier(
            resolvedIdentifier,
            for: binding,
            payload: &payload,
            snapshot: &snapshot
          ) {
            didMutateSidecar = true
          }
        } else if let existingEventIdentifier = normalizedProjectionValue(
          binding.calendarEventExternalIdentifier
        ) {
          let descriptor = try await resolvedOwnedCalendarDescriptor(
            existing: &ownedCalendarDescriptor
          )
          _ = try await calendarServiceRegistry.scheduleCalendarService.removeOwnedEvent(
            externalIdentifier: existingEventIdentifier,
            calendarIdentifier: descriptor.calendarIdentifier
          )
          if updateOwnedCalendarEventIdentifier(
            nil,
            for: binding,
            payload: &payload,
            snapshot: &snapshot
          ) {
            didMutateSidecar = true
          }
        }
      }
    } catch {
      reportError(error, logMessage: "syncOwnedCalendarEvents failed")
      return false
    }

    if didMutateSidecar {
      syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
      saveRuntimeProjectionSidecarPayload(payload)
      installCachedRuntimeProjectionSnapshot(snapshot)
    }

    await persistManagedLogseqPages(for: resolvedProjectIDs, snapshot: snapshot)
    return didMutateSidecar || !bindings.isEmpty
  }

  @discardableResult
  func applyOwnedCalendarExternalChanges(
    ownerIDs: [String]
  ) async -> Bool {
    let normalizedOwnerIDs = Array(
      NSOrderedSet(array: ownerIDs.compactMap(normalizedProjectionValue))
    ) as? [String] ?? []
    guard !normalizedOwnerIDs.isEmpty else { return false }
    guard var snapshot = cachedOutlinerRuntimeProjectionSnapshot else { return false }

    let bindings = ownedCalendarBindings(
      for: Set(snapshot.projects.map(\.id)),
      snapshot: snapshot
    )
    let bindingsByEventIdentifier = Dictionary(grouping: bindings.compactMap { binding in
      normalizedProjectionValue(binding.calendarEventExternalIdentifier).map { ($0, binding) }
    }) { $0.0 }
    .mapValues { matches in
      ReminderTaskAdoptionPolicy.uniqueMatch(from: matches.map(\.1))
    }

    var didHandleAnyOwner = false
    var didMutateSidecar = false
    var payload = loadRuntimeProjectionSidecarPayload()
    var touchedProjectIDs: Set<UUID> = []
    for ownerID in normalizedOwnerIDs {
      guard let event = await calendarServiceRegistry.scheduleCalendarService.resolveEvent(
        ownerID: ownerID
      ) else {
        guard
          let eventIdentifier = ScheduleCalendarOwnerIDCodec.baseIdentifier(from: ownerID),
          let binding = bindingsByEventIdentifier[eventIdentifier] ?? nil
        else {
          continue
        }
        if updateOwnedCalendarEventIdentifier(
          nil,
          for: binding,
          payload: &payload,
          snapshot: &snapshot
        ) {
          didMutateSidecar = true
          touchedProjectIDs.insert(binding.projectID)
        }
        didHandleAnyOwner = true
        continue
      }

      let eventIdentifier =
        normalizedProjectionValue(event.externalIdentifier)
        ?? normalizedProjectionValue(event.eventIdentifier)
      guard let eventIdentifier,
        let binding = bindingsByEventIdentifier[eventIdentifier] ?? nil
      else {
        continue
      }

      let scheduleValue = OwnedScheduleCalendarSyncPolicy.taskScheduleValue(for: event)
      didHandleAnyOwner = true
      _ = await performTaskScheduleSplitWrite(
        TaskScheduleSplitWrite(
          projectID: binding.projectID,
          taskID: binding.taskID,
          day: scheduleValue.day,
          timeMinutes: scheduleValue.timeMinutes,
          durationMinutes: scheduleValue.durationMinutes
        )
      )
    }

    if didMutateSidecar {
      syncRuntimeProjectionSidecarState(snapshot: &snapshot, payload: payload)
      saveRuntimeProjectionSidecarPayload(payload)
      installCachedRuntimeProjectionSnapshot(snapshot)
      await persistManagedLogseqPages(for: touchedProjectIDs, snapshot: snapshot)
    }

    return didHandleAnyOwner
  }

  private func ownedCalendarBindings(
    for projectIDs: Set<UUID>,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> [OwnedCalendarTaskBinding] {
    projectIDs
      .sorted(by: { $0.uuidString < $1.uuidString })
      .compactMap { projectID in
        snapshot.projects.first(where: { $0.id == projectID }).map { (projectID, $0) }
      }
      .flatMap { projectID, project in
        runtimeLogseqTaskBindings(for: project, snapshot: snapshot).compactMap { binding in
          guard let reminderExternalIdentifier = normalizedProjectionValue(
            binding.reminderExternalIdentifier
          ) else {
            return nil
          }

          return OwnedCalendarTaskBinding(
            projectID: projectID,
            taskID: binding.taskID,
            reminderExternalIdentifier: reminderExternalIdentifier,
            calendarEventExternalIdentifier: normalizedProjectionValue(
              binding.calendarEventExternalIdentifier
            ),
            upsertRequest: OwnedScheduleCalendarSyncPolicy.upsertRequest(
              title: binding.title,
              dueDate: binding.dueDate,
              hasExplicitTime: binding.hasExplicitTime,
              durationMinutes: binding.durationMinutes,
              existingExternalIdentifier: binding.calendarEventExternalIdentifier
            )
          )
        }
      }
  }

  private func resolvedOwnedCalendarDescriptor(
    existing: inout OwnedScheduleCalendarDescriptor?
  ) async throws -> OwnedScheduleCalendarDescriptor {
    if let existing {
      return existing
    }
    let descriptor = try await calendarServiceRegistry.scheduleCalendarService.ensureOwnedCalendar()
    existing = descriptor
    return descriptor
  }

  private func updateOwnedCalendarEventIdentifier(
    _ calendarEventExternalIdentifier: String?,
    for binding: OwnedCalendarTaskBinding,
    payload: inout ReminderProjectionSidecarPayload,
    snapshot: inout OutlineProjectionRuntimeSnapshot
  ) -> Bool {
    let resolvedIdentifier = normalizedProjectionValue(calendarEventExternalIdentifier)
    let existingRecord =
      payload.taskFeatureSidecarByReminderExternalIdentifier[binding.reminderExternalIdentifier]
      ?? snapshot.taskFeatureSidecarByReminderExternalIdentifier[binding.reminderExternalIdentifier]
    let existingIdentifier = normalizedProjectionValue(
      existingRecord?.ownedCalendarEventExternalIdentifier
    )
    guard existingIdentifier != resolvedIdentifier else {
      return false
    }

    let metadata =
      existingRecord?.featureSidecarMetadata
      ?? snapshot.taskFeatureSidecarByReminderExternalIdentifier[binding.reminderExternalIdentifier]?
        .featureSidecarMetadata
      ?? OutlinerTaskSidecarMetadata()
    let nextRecord = AppFeatureMutationService.taskFeatureRecord(
      reminderExternalIdentifier: binding.reminderExternalIdentifier,
      featureSidecar: metadata,
      existing: existingRecord,
      ownedCalendarEventExternalIdentifier: resolvedIdentifier
    )

    if nextRecord.hasMeaningfulContent {
      payload.taskFeatureSidecarByReminderExternalIdentifier[binding.reminderExternalIdentifier] =
        nextRecord
    } else {
      payload.taskFeatureSidecarByReminderExternalIdentifier.removeValue(
        forKey: binding.reminderExternalIdentifier
      )
    }
    return true
  }
}

private struct OwnedCalendarTaskBinding: Equatable, Sendable {
  let projectID: UUID
  let taskID: UUID
  let reminderExternalIdentifier: String
  let calendarEventExternalIdentifier: String?
  let upsertRequest: OwnedScheduleCalendarEventUpsertRequest?
}
