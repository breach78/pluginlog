import Foundation
import SwiftData

extension AppState {
  @MainActor
  func installCachedRuntimeProjectionSnapshot(
    _ runtimeSnapshot: OutlineProjectionRuntimeSnapshot
  ) {
    cachedOutlinerRuntimeProjectionSnapshot = runtimeSnapshot
    TaskIdentityBridgeStore.seed(from: runtimeSnapshot)
  }

  @MainActor
  func loadRuntimeProjectionSnapshotFromSource() async -> OutlineProjectionRuntimeSnapshot? {
    try? await ReminderSourceProjectionSnapshotLoader.load(
      gateway: reminderGateway,
      dataDirectory: storageCoordinator.paths?.dataDirectory,
      normalizedSQLiteURL: storageCoordinator.paths?.normalizedSQLiteURL
    )
  }

  var journalSummaryProviderSignature: String {
    "hybrid-foundation-gemini-v1"
  }

  var journalSummaryLegacyProviderSignatures: [String] {
    ["foundation-two-stage", "gemini-gemini-3.1-pro-preview"]
      .filter { $0 != journalSummaryProviderSignature }
  }

  func loadProjectNoteFromSource(projectID: UUID, context: ModelContext) async -> String? {
    guard
      let pageStore = logseqProjectPageStore(),
      let project = projectForLogseqSync(projectID: projectID, context: context)
    else {
      return resolvedProjectNoteMarkdown(forProjectID: projectID, context: context) ?? ""
    }

    do {
      let snapshot = try await pageStore.loadProjectPage(
        for: logseqProjectPageIdentity(for: project)
      )
      return snapshot?.noteMarkdown ?? resolvedProjectNoteMarkdown(forProjectID: projectID, context: context) ?? ""
    } catch {
      reportError(error, logMessage: "loadProjectNoteFromSource failed")
      return resolvedProjectNoteMarkdown(forProjectID: projectID, context: context) ?? ""
    }
  }

  func persistProjectNoteToSource(_ note: String, projectID: UUID, context: ModelContext) async {
    _ = await send(
      .writeOwnerField(
        ownerStore: .sidecar,
        write: .projectMetadata(
          ProjectMetadataWrite(
            projectID: projectID,
            mutation: .projectNote(note)
          )
        )
      ),
      waitForEditorIdle: false
    )

    guard
      let pageStore = logseqProjectPageStore(),
      let project = projectForLogseqSync(projectID: projectID, context: context)
    else {
      return
    }

    do {
      let identity = logseqProjectPageIdentity(for: project)
      let existingPage = try await pageStore.loadProjectPage(for: identity)
      if let existingPage {
        guard existingPage.canSafelyPersistProjectNote else {
          return
        }
      }
      let managedTasks =
        if cachedOutlinerRuntimeProjectionSnapshot != nil {
          logseqManagedTaskRecords(for: project)
        } else if let existingPage {
          existingPage.managedTasks
        } else {
          logseqManagedTaskRecords(for: project)
        }
      _ = try await pageStore.upsertPage(
        identity,
        noteMarkdown: note,
        managedTasks: managedTasks
      )
    } catch {
      reportError(error, logMessage: "persistProjectNoteToSource page store write failed")
    }
  }

  func loadJournalEntriesFromSource(for day: Date) async -> [ObsidianJournalEntry] {
    guard let journalStore else { return [] }

    do {
      return try await journalStore.entries(for: day)
    } catch {
      reportError(error, logMessage: "loadJournalEntriesFromSource failed")
      return []
    }
  }

  func loadAvailableJournalDaysFromSource() async -> [Date] {
    guard let journalStore else { return [] }

    do {
      return try await journalStore.availableDays()
    } catch {
      reportError(error, logMessage: "loadAvailableJournalDaysFromSource failed")
      return []
    }
  }

  func appendJournalEntryToSource(_ text: String, occurredAt: Date = .now) async
    -> ObsidianJournalEntry?
  {
    await saveJournalEntryToSource(text, existingEntryID: nil, occurredAt: occurredAt)
  }

  func saveJournalEntryToSource(
    _ text: String,
    existingEntryID: String?,
    occurredAt: Date = .now
  ) async -> ObsidianJournalEntry? {
    guard let journalStore else { return nil }

    do {
      let savedEntry = try await journalStore.saveEntry(
        text,
        existingEntryID: existingEntryID,
        at: occurredAt
      )
      NotificationCenter.default.post(
        name: .reminderAppJournalEntriesDidChange,
        object: nil,
        userInfo: ["day": savedEntry.day]
      )
      return savedEntry
    } catch {
      reportError(error, logMessage: "saveJournalEntryToSource failed")
      return nil
    }
  }

  func saveJournalDaySummaryBackupToSource(
    _ markdown: String,
    for day: Date,
    summaryInputSignature: String?,
    usage: GeminiGenerateContentSummaryService.SummaryUsage?
  ) async {
    guard let journalStore else { return }

    do {
      try await journalStore.saveDaySummaryBackup(
        markdown,
        for: day,
        providerSignature: journalSummaryProviderSignature,
        summaryInputSignature: summaryInputSignature,
        usage: usage
      )
    } catch {
      reportError(error, logMessage: "saveJournalDaySummaryBackupToSource failed")
    }
  }

  func loadJournalDaySummaryBackupFromSource(
    for day: Date
  ) async -> ObsidianJournalDaySummaryBackupLoadResult {
    guard let journalStore else { return .missing }

    do {
      return try await journalStore.loadDaySummaryBackup(for: day)
    } catch {
      reportError(error, logMessage: "loadJournalDaySummaryBackupFromSource failed")
      return .missing
    }
  }

  func prepareProjectNoteStore() async {
    guard let pageStore = logseqProjectPageStore() else { return }

    do {
      try await pageStore.preparePagesDirectory()
    } catch {
      errorMessage = error.localizedDescription
      AppLogger.storage.error(
        "prepareProjectNoteStore failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  func prepareJournalStore() async {
    guard let journalStore else { return }

    do {
      try await journalStore.prepareDirectory()
    } catch {
      errorMessage = error.localizedDescription
      AppLogger.storage.error(
        "prepareJournalStore failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func refreshAllProjectNotesFromSource(context: ModelContext) async {
    guard let pageStore = logseqProjectPageStore() else { return }

    do {
      let projects = try context.fetch(FetchDescriptor<Project>())
      var didChange = false

      for project in projects {
        guard let snapshot = try await pageStore.loadProjectPage(
          for: logseqProjectPageIdentity(for: project)
        ) else {
          continue
        }

        if project.projectNoteMarkdown != snapshot.noteMarkdown {
          project.projectNoteMarkdown = snapshot.noteMarkdown
          didChange = true
        }
      }

      if didChange {
        try context.save()
      }
    } catch {
      reportError(error, logMessage: "refreshAllProjectNotesFromSource failed")
    }
  }

  func refreshPrivateObsidianStores() {
    if isPrivateObsidianFeaturesEnabled, let obsidianProjectsRootURL {
      journalStore = ObsidianJournalStore(rootURL: obsidianJournalsRootURL(for: obsidianProjectsRootURL))
    } else {
      journalStore = nil
    }
    if logseqProjectPageStore() != nil {
      Task { @MainActor [weak self] in
        await self?.prepareProjectNoteStore()
      }
    }
  }

  private func obsidianProjectNotesRootURL(for configuredURL: URL) -> URL {
    if isLegacyObsidianProjectsFolder(configuredURL) {
      return configuredURL
    }

    return configuredURL
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
  }

  private func obsidianJournalsRootURL(for configuredURL: URL) -> URL {
    if isLegacyObsidianProjectsFolder(configuredURL) {
      return configuredURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("journals", isDirectory: true)
    }

    return configuredURL.appendingPathComponent("journals", isDirectory: true)
  }

  private func isLegacyObsidianProjectsFolder(_ url: URL) -> Bool {
    url.lastPathComponent.caseInsensitiveCompare("projects") == .orderedSame
      && url.deletingLastPathComponent().lastPathComponent.caseInsensitiveCompare("pages")
        == .orderedSame
  }

  private func logseqProjectPageStore() -> LogseqProjectPageStore? {
    guard let logseqGraphRootURL else { return nil }
    return LogseqProjectPageStore(
      pagesRootURL: logseqGraphRootURL.appendingPathComponent("pages", isDirectory: true)
    )
  }

  private func projectForLogseqSync(
    projectID: UUID,
    context: ModelContext
  ) -> Project? {
    try? context.fetch(
      FetchDescriptor<Project>(
        predicate: #Predicate<Project> { project in
          project.id == projectID
        }
      )
    ).first
  }

  private func logseqProjectPageIdentity(
    for project: Project
  ) -> LogseqProjectPageStore.ProjectIdentity {
    LogseqProjectPageStore.ProjectIdentity(
      projectID: project.id,
      title: project.title,
      reminderListExternalIdentifier: resolvedProjectReminderListExternalIdentifier(
        projectID: project.id
      )
    )
  }

  func logseqManagedTaskRecords(
    for project: Project
  ) -> [LogseqProjectPageStore.TaskRecord] {
    if let snapshot = cachedOutlinerRuntimeProjectionSnapshot,
      let runtimeProject = snapshot.projects.first(where: { $0.id == project.id })
    {
      return logseqManagedTaskRecords(for: runtimeProject, snapshot: snapshot)
    }

    return project.tasks
      .sorted { lhs, rhs in
        if lhs.rowOrder != rhs.rowOrder {
          return lhs.rowOrder < rhs.rowOrder
        }
        return lhs.createdAt < rhs.createdAt
      }
      .map { task in
        LogseqProjectPageStore.TaskRecord(
          taskID: task.id,
          title: task.title,
          isCompleted: task.isCompleted,
          date: logseqTaskDateValue(for: task),
          duration: task.scheduledDurationMinutes.map(String.init),
          repeatRule: LogseqReminderPropertyCodec.encodeRepeat(task.recurrenceRuleRaw),
          reminderExternalIdentifier: task.reminderExternalIdentifier,
          calendarEventExternalIdentifier: nil
        )
      }
  }

  private func logseqTaskDateValue(for task: TaskItem) -> String? {
    LogseqReminderPropertyCodec.encodeDate(
      task.dueDate,
      hasExplicitTime: task.scheduleHasExplicitTime
    )
  }

  private func logseqTaskDurationMinutes(from rawValue: String?) -> Int? {
    guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty
    else {
      return nil
    }
    guard let durationMinutes = Int(rawValue), durationMinutes > 0 else {
      return nil
    }
    return max(5, durationMinutes)
  }

  func reconcileManagedLogseqPagesWithReminderSource() async {
    guard let pageStore = logseqProjectPageStore(),
      let modelContainer
    else {
      return
    }

    let context = ModelContext(modelContainer)

    do {
      let pageSnapshots = try await pageStore.loadProjectPagesInScope()
      guard !pageSnapshots.isEmpty else { return }

      let reminderListsByExternalIdentifier = try await reminderListSnapshotsByExternalIdentifier()
      var touchedProjectIDs: Set<UUID> = []

      for pageSnapshot in pageSnapshots {
        if pageSnapshot.projectID == nil, !pageSnapshot.externalTasks.isEmpty {
          continue
        }
        guard let projectID = await ensureManagedLogseqProject(
          for: pageSnapshot,
          context: context,
          reminderListsByExternalIdentifier: reminderListsByExternalIdentifier
        ) else {
          continue
        }
        guard let runtimeSnapshot = cachedOutlinerRuntimeProjectionSnapshot,
          let project = runtimeSnapshot.projects.first(where: { $0.id == projectID })
        else {
          continue
        }

        if await applyManagedLogseqPage(
          pageSnapshot,
          projectID: projectID,
          project: project,
          snapshot: runtimeSnapshot
        ) {
          touchedProjectIDs.insert(projectID)
        }
      }

      if let runtimeSnapshot = cachedOutlinerRuntimeProjectionSnapshot {
        await persistManagedLogseqPages(
          for: touchedProjectIDs,
          snapshot: runtimeSnapshot
        )
      }
    } catch {
      reportError(error, logMessage: "reconcileManagedLogseqPagesWithReminderSource failed")
    }
  }

  func persistManagedLogseqPages(
    for projectIDs: Set<UUID>,
    snapshot: OutlineProjectionRuntimeSnapshot? = nil
  ) async {
    guard let pageStore = logseqProjectPageStore() else { return }
    let resolvedSnapshot = snapshot ?? cachedOutlinerRuntimeProjectionSnapshot
    guard let resolvedSnapshot, !projectIDs.isEmpty else { return }

    for projectID in projectIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard let project = resolvedSnapshot.projects.first(where: { $0.id == projectID }) else {
        continue
      }

      let identity = logseqProjectPageIdentity(
        for: projectID,
        snapshot: resolvedSnapshot
      )
      let existingPage = try? await pageStore.loadProjectPage(for: identity)
      let claimCandidate =
        existingPage == nil
        ? (try? await pageStore.loadClaimableTaggedPage(for: identity))
        : nil
      let targetPage = existingPage ?? claimCandidate

      if targetPage?.canSafelyPersistProjectNote == false {
        continue
      }
      let noteMarkdown = targetPage?.noteMarkdown
        ?? resolvedProjectNoteMarkdown(for: projectID, snapshot: resolvedSnapshot)
      let managedTasks = logseqManagedTaskRecords(for: project, snapshot: resolvedSnapshot)
      guard !ManagedLogseqSyncHardening.hasAmbiguousManagedTaskIdentities(managedTasks) else {
        AppLogger.sync.error(
          "persistManagedLogseqPages skipped ambiguous managed task identities for project \(projectID.uuidString, privacy: .public)"
        )
        continue
      }

      do {
        if let claimCandidate {
          _ = try await pageStore.claimTaggedPage(
            at: claimCandidate.fileURL,
            as: identity,
            noteMarkdown: noteMarkdown,
            managedTasks: managedTasks
          )
        } else {
          _ = try await pageStore.upsertPage(
            identity,
            noteMarkdown: noteMarkdown,
            managedTasks: managedTasks
          )
        }
      } catch {
        reportError(error, logMessage: "persistManagedLogseqPages failed")
      }
    }
  }

  private func ensureManagedLogseqProject(
    for pageSnapshot: LogseqProjectPageStore.PageSnapshot,
    context: ModelContext,
    reminderListsByExternalIdentifier: [String: ReminderListImportSnapshot]
  ) async -> UUID? {
    guard ManagedLogseqSyncHardening.isConsistentProjectIdentity(
      pageProjectID: pageSnapshot.projectID,
      reminderListExternalIdentifier: pageSnapshot.reminderListExternalIdentifier
    ) else {
      AppLogger.sync.error("ensureManagedLogseqProject skipped inconsistent hidden project identity")
      return nil
    }

    if let runtimeSnapshot = cachedOutlinerRuntimeProjectionSnapshot,
      let existingProjectID = existingManagedLogseqProjectID(
        for: pageSnapshot,
        snapshot: runtimeSnapshot
      )
    {
      return existingProjectID
    }

    if let reminderListExternalIdentifier = normalizedProjectionValue(
      pageSnapshot.reminderListExternalIdentifier
    ),
      let listSnapshot = reminderListsByExternalIdentifier[reminderListExternalIdentifier]
    {
      return await adoptManagedLogseqProject(
        pageSnapshot,
        listSnapshot: listSnapshot
      )
    }

    return await createProjectList(named: pageSnapshot.title, context: context)
  }

  private func existingManagedLogseqProjectID(
    for pageSnapshot: LogseqProjectPageStore.PageSnapshot,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> UUID? {
    let projectIDMatch = pageSnapshot.projectID.flatMap { projectID in
      snapshot.projects.contains(where: { $0.id == projectID }) ? projectID : nil
    }
    let hasProjectIdentifier = pageSnapshot.projectID != nil
    let reminderListExternalIdentifier = normalizedProjectionValue(
      pageSnapshot.reminderListExternalIdentifier
    )
    let reminderListMatch = reminderListExternalIdentifier.flatMap { externalIdentifier in
      snapshot.projectReminderListExternalIdentifierByProjectID.first { _, value in
        normalizedProjectionValue(value) == externalIdentifier
      }?.key
    }

    if hasProjectIdentifier, reminderListExternalIdentifier != nil {
      guard projectIDMatch == reminderListMatch else {
        return nil
      }
      return projectIDMatch
    }

    if hasProjectIdentifier {
      return projectIDMatch
    }

    return reminderListMatch
  }

  private func adoptManagedLogseqProject(
    _ pageSnapshot: LogseqProjectPageStore.PageSnapshot,
    listSnapshot: ReminderListImportSnapshot
  ) async -> UUID? {
    guard let workspaceTreeRepository,
      let reminderListExternalIdentifier = normalizedProjectionValue(listSnapshot.externalIdentifier)
    else {
      return nil
    }

    let projectID = ReminderProjectionIdentity.projectID(
      for: reminderListExternalIdentifier
    )

    do {
      let existingNodes = try await workspaceTreeRepository.fetchProjectNodes(
        canonicalProjectID: projectID,
        includeArchived: true
      )

      if existingNodes.isEmpty {
        _ = try await workspaceTreeRepository.createProject(
          title: pageSnapshot.title,
          colorHex: listSnapshot.colorHex,
          noteMarkdown: pageSnapshot.noteMarkdown,
          canonicalProjectID: projectID,
          reminderListIdentifier: listSnapshot.identifier,
          reminderListExternalIdentifier: reminderListExternalIdentifier
        )
        let existingProjectIDs = cachedOutlinerRuntimeProjectionSnapshot?.projects.map(\.id) ?? []
        _ = await writeWorkspaceProjectOrder(existingProjectIDs + [projectID])
        bumpWorkspaceTreeRevision()
      }

      _ = await writeProjectReminderBinding(
        projectID: projectID,
        reminderListIdentifier: listSnapshot.identifier,
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        waitForEditorIdle: false
      )
      _ = await recomputeCachedRuntimeProjectionProjects([projectID])
      return projectID
    } catch {
      reportError(error, logMessage: "adoptManagedLogseqProject failed")
      return nil
    }
  }

  private func applyManagedLogseqPage(
    _ pageSnapshot: LogseqProjectPageStore.PageSnapshot,
    projectID: UUID,
    project: OutlinerProject,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) async -> Bool {
    guard !ManagedLogseqSyncHardening.hasAmbiguousManagedTaskIdentities(pageSnapshot.managedTasks)
    else {
      AppLogger.sync.error(
        "applyManagedLogseqPage skipped ambiguous managed task identities for project \(projectID.uuidString, privacy: .public)"
      )
      return false
    }

    if let reminderListIdentifier = normalizedProjectionValue(
      snapshot.projectReminderListIdentifierByProjectID[projectID]
    ),
      pageSnapshot.title != project.title
    {
      _ = await send(
        .writeOwnerField(
          ownerStore: .reminder,
          write: .listMetadata(
            ReminderListMetadataWrite(
              projectID: projectID,
              reminderListIdentifier: reminderListIdentifier,
              reminderListExternalIdentifier: normalizedProjectionValue(
                snapshot.projectReminderListExternalIdentifierByProjectID[projectID]
              ),
              mutation: .title(pageSnapshot.title)
            )
          )
        ),
        waitForEditorIdle: false
      )
    }

    let currentBindings = runtimeLogseqTaskBindings(
      for: project,
      snapshot: snapshot
    )
    let bindingsByTaskID = Dictionary(
      uniqueKeysWithValues: currentBindings.map { ($0.taskID, $0) }
    )
    let bindingsByExternalIdentifier =
      ManagedLogseqSyncHardening.uniqueBindingsByReminderExternalIdentifier(currentBindings)

    for taskRecord in pageSnapshot.managedTasks {
      if let taskID = taskRecord.taskID,
        let binding = bindingsByTaskID[taskID]
      {
        await applyManagedLogseqTaskFields(
          taskRecord,
          current: binding,
          projectID: projectID
        )
        continue
      }

      if let reminderExternalIdentifier = normalizedProjectionValue(
        taskRecord.reminderExternalIdentifier
      ),
        let binding = bindingsByExternalIdentifier[reminderExternalIdentifier]
      {
        await applyManagedLogseqTaskFields(
          taskRecord,
          current: binding,
          projectID: projectID
        )
        continue
      }

      _ = await createManagedLogseqTask(
        taskRecord,
        projectID: projectID,
        snapshot: snapshot
      )
    }
    return true
  }

  private func applyManagedLogseqTaskFields(
    _ taskRecord: LogseqProjectPageStore.TaskRecord,
    current: RuntimeLogseqTaskBinding,
    projectID: UUID
  ) async {
    let trimmedTitle = taskRecord.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let reminderIdentifier = normalizedProjectionValue(current.reminderIdentifier)
    let reminderExternalIdentifier = normalizedProjectionValue(current.reminderExternalIdentifier)

    if !trimmedTitle.isEmpty, trimmedTitle != current.title {
      _ = await send(
        .writeOwnerField(
          ownerStore: .reminder,
          write: .taskFields(
            ReminderTaskFieldsWrite(
              projectID: projectID,
              taskID: current.taskID,
              reminderIdentifier: reminderIdentifier,
              reminderExternalIdentifier: reminderExternalIdentifier,
              mutation: .title(trimmedTitle)
            )
          )
        ),
        waitForEditorIdle: false
      )
    }

    if current.isCompleted != taskRecord.isCompleted {
      _ = await send(
        .writeOwnerField(
          ownerStore: .reminder,
          write: .taskFields(
            ReminderTaskFieldsWrite(
              projectID: projectID,
              taskID: current.taskID,
              reminderIdentifier: reminderIdentifier,
              reminderExternalIdentifier: reminderExternalIdentifier,
              mutation: .completion(
                isCompleted: taskRecord.isCompleted,
                completionDate: taskRecord.isCompleted ? .now : nil
              )
            )
          )
        ),
        waitForEditorIdle: false
      )
    }

    let decodedDate = LogseqReminderPropertyCodec.decodeDate(taskRecord.date)
    let didUpdateSchedule =
      current.dueDate != decodedDate?.date
      || current.hasExplicitTime != (decodedDate?.hasExplicitTime ?? false)
    if didUpdateSchedule {
      _ = await send(
        .writeOwnerField(
          ownerStore: .reminder,
          write: .taskFields(
            ReminderTaskFieldsWrite(
              projectID: projectID,
              taskID: current.taskID,
              reminderIdentifier: reminderIdentifier,
              reminderExternalIdentifier: reminderExternalIdentifier,
              mutation: .schedule(
                dueDate: decodedDate?.date,
                hasExplicitTime: decodedDate?.hasExplicitTime ?? false
              )
            )
          )
        ),
        waitForEditorIdle: false
      )
    }

    let decodedDurationMinutes = logseqTaskDurationMinutes(from: taskRecord.duration)
    let didUpdateDuration = decodedDurationMinutes != current.durationMinutes
    if didUpdateDuration {
      _ = await send(
        .writeOwnerField(
          ownerStore: .sidecar,
          write: .appSupplement(
            AppSupplementWrite(
              mutation: .taskScheduledDuration(
                taskID: current.taskID,
                scheduledDurationMinutes: decodedDurationMinutes
              )
            )
          )
        ),
        waitForEditorIdle: false
      )
    }

    let decodedRepeat = LogseqReminderPropertyCodec.decodeRepeat(taskRecord.repeatRule)
    if normalizedProjectionValue(decodedRepeat) != normalizedProjectionValue(current.recurrenceRuleRaw) {
      _ = await send(
        .writeOwnerField(
          ownerStore: .reminder,
          write: .taskFields(
            ReminderTaskFieldsWrite(
              projectID: projectID,
              taskID: current.taskID,
              reminderIdentifier: reminderIdentifier,
              reminderExternalIdentifier: reminderExternalIdentifier,
              mutation: .recurrence(decodedRepeat)
            )
          )
        ),
        waitForEditorIdle: false
      )
    }

    if didUpdateSchedule || didUpdateDuration {
      _ = await syncOwnedCalendarEvents(for: [projectID])
    }
  }

  private func createManagedLogseqTask(
    _ taskRecord: LogseqProjectPageStore.TaskRecord,
    projectID: UUID,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) async -> UUID? {
    guard let workspaceTreeRepository,
      let projectNodeID = try? await workspaceTreeRepository.fetchProjectNodes(
        canonicalProjectID: projectID,
        includeArchived: false
      ).first?.id
    else {
      return nil
    }

    let trimmedTitle = taskRecord.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return nil }

    let decodedDate = LogseqReminderPropertyCodec.decodeDate(taskRecord.date)
    let decodedRepeat = LogseqReminderPropertyCodec.decodeRepeat(taskRecord.repeatRule)
    let reminderListIdentifier = normalizedProjectionValue(
      snapshot.projectReminderListIdentifierByProjectID[projectID]
    )

    do {
      let remoteMatches = normalizedProjectionValue(taskRecord.reminderExternalIdentifier)
        .map { externalIdentifier in
          reminderGateway.reminders(withExternalIdentifier: externalIdentifier).filter { reminder in
            ReminderTaskAdoptionPolicy.allowsExternalReminderAdoption(
              candidateCalendarIdentifier: reminder.calendar.calendarIdentifier,
              targetReminderListIdentifier: reminderListIdentifier
            )
          }
        } ?? []
      if remoteMatches.count > 1 {
        AppLogger.sync.error(
          "createManagedLogseqTask found multiple reminder matches for external identifier")
      }
      guard ManagedLogseqSyncHardening.allowsManagedTaskCreation(
        taskRecord,
        remoteMatchCount: remoteMatches.count
      ) else {
        AppLogger.sync.error("createManagedLogseqTask skipped damaged or ambiguous hidden identity")
        return nil
      }
      let remoteReference = ReminderTaskAdoptionPolicy.uniqueMatch(from: remoteMatches)

      let reminderIdentifier: String?
      let reminderExternalIdentifier: String?
      let remoteModifiedAt: Date?
      let initialDueDate: Date?
      let initialHasExplicitTime: Bool

      if let remoteReference {
        reminderIdentifier = remoteReference.calendarItemIdentifier
        reminderExternalIdentifier = remoteReference.calendarItemExternalIdentifier
        remoteModifiedAt = reminderGateway.lastModifiedDate(for: remoteReference)
        initialDueDate = remoteReference.dueDateComponents.flatMap {
          Calendar.autoupdatingCurrent.date(from: $0)
        }
        initialHasExplicitTime =
          remoteReference.dueDateComponents?.hour != nil
          || remoteReference.dueDateComponents?.minute != nil
          || remoteReference.dueDateComponents?.second != nil
      } else {
        guard
          let reminderListIdentifier,
          let metadata = try reminderProjectProvider.createTaskReminder(
            inProject: reminderListIdentifier,
            title: trimmedTitle,
            dueDate: decodedDate?.date,
            hasExplicitTime: decodedDate?.hasExplicitTime ?? false,
            noteText: ""
          )
        else {
          return nil
        }
        reminderIdentifier = metadata.identifier
        reminderExternalIdentifier = normalizedProjectionValue(metadata.externalIdentifier)
        remoteModifiedAt = metadata.modifiedAt
        initialDueDate = decodedDate?.date
        initialHasExplicitTime = decodedDate?.hasExplicitTime ?? false
      }

      let createdTask = try await workspaceTreeRepository.createTask(
        title: trimmedTitle,
        parentNodeID: projectNodeID,
        reminderIdentifier: reminderIdentifier,
        reminderExternalIdentifier: reminderExternalIdentifier,
        remoteLastModifiedAt: remoteModifiedAt
      )

      _ = await recomputeCachedRuntimeProjectionProjects([projectID])
      await applyManagedLogseqTaskFields(
        taskRecord,
        current: RuntimeLogseqTaskBinding(
          taskID: createdTask.id,
          reminderIdentifier: reminderIdentifier,
          reminderExternalIdentifier: reminderExternalIdentifier,
          title: trimmedTitle,
          isCompleted: false,
          dueDate: initialDueDate,
          hasExplicitTime: initialHasExplicitTime,
          recurrenceRuleRaw: nil,
          durationMinutes: nil,
          calendarEventExternalIdentifier: nil
        ),
        projectID: projectID
      )

      if decodedRepeat != nil, taskRecord.repeatRule != nil {
        _ = await recomputeCachedRuntimeProjectionProjects([projectID])
      }
      return createdTask.id
    } catch {
      reportError(error, logMessage: "createManagedLogseqTask failed")
      return nil
    }
  }

  private func reminderListSnapshotsByExternalIdentifier() async throws
    -> [String: ReminderListImportSnapshot]
  {
    let lists = try await ReminderGatewayImportSnapshotProvider(gateway: reminderGateway)
      .fetchAllLists()
    return lists.reduce(into: [String: ReminderListImportSnapshot]()) { partialResult, list in
      guard let externalIdentifier = normalizedProjectionValue(list.externalIdentifier) else {
        return
      }
      partialResult[externalIdentifier] = list
    }
  }

  private func logseqProjectPageIdentity(
    for projectID: UUID,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> LogseqProjectPageStore.ProjectIdentity {
    let projectTitle = snapshot.projects.first(where: { $0.id == projectID })?.title
      ?? OutlinerProject.defaultTitle
    return LogseqProjectPageStore.ProjectIdentity(
      projectID: projectID,
      title: projectTitle,
      reminderListExternalIdentifier: normalizedProjectionValue(
        snapshot.projectReminderListExternalIdentifierByProjectID[projectID]
      )
    )
  }

  private func resolvedProjectNoteMarkdown(
    for projectID: UUID,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> String {
    if let noteMarkdown = snapshot.projectFeatureSidecarByProjectID[projectID]?.projectNoteMarkdown {
      return noteMarkdown
    }
    if let reminderListExternalIdentifier = normalizedProjectionValue(
      snapshot.projectReminderListExternalIdentifierByProjectID[projectID]
    ) {
      return snapshot.projectFeatureSidecarByReminderListExternalIdentifier[
        reminderListExternalIdentifier
      ]?.projectNoteMarkdown ?? ""
    }
    return ""
  }

  func logseqManagedTaskRecords(
    for project: OutlinerProject,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> [LogseqProjectPageStore.TaskRecord] {
    runtimeLogseqTaskBindings(for: project, snapshot: snapshot)
      .map { binding in
        LogseqProjectPageStore.TaskRecord(
          taskID: binding.taskID,
          title: binding.title,
          isCompleted: binding.isCompleted,
          date: LogseqReminderPropertyCodec.encodeDate(
            binding.dueDate,
            hasExplicitTime: binding.hasExplicitTime
          ),
          duration: binding.durationMinutes.map(String.init),
          repeatRule: LogseqReminderPropertyCodec.encodeRepeat(binding.recurrenceRuleRaw),
          reminderExternalIdentifier: binding.reminderExternalIdentifier,
          calendarEventExternalIdentifier: binding.calendarEventExternalIdentifier
        )
      }
  }

  func runtimeLogseqTaskBindings(
    for project: OutlinerProject,
    snapshot: OutlineProjectionRuntimeSnapshot
  ) -> [RuntimeLogseqTaskBinding] {
    project.document.flatten().compactMap { entry in
      guard entry.node.type.isTask else { return nil }
      guard TaskIdentityBridgeStore.record(for: entry.node.canonicalID)?.ownerProjectID == project.id else {
        return nil
      }

      let reminderMetadata = snapshot.reminderMetadata(for: entry.node)
      let reminderExternalIdentifier = normalizedProjectionValue(entry.node.reminderExternalIdentifier)
      let durationMinutes =
        snapshot.featureSidecarByNodeID[entry.node.id]?.scheduledDurationMinutes
        ?? reminderExternalIdentifier.flatMap {
          snapshot.taskFeatureSidecarByReminderExternalIdentifier[$0]?.scheduledDurationMinutes
        }
      let calendarEventExternalIdentifier = reminderExternalIdentifier.flatMap {
        normalizedProjectionValue(
          snapshot.taskFeatureSidecarByReminderExternalIdentifier[$0]?
            .ownedCalendarEventExternalIdentifier
        )
      }

      return RuntimeLogseqTaskBinding(
        taskID: entry.node.canonicalID,
        reminderIdentifier: normalizedProjectionValue(entry.node.reminderIdentifier),
        reminderExternalIdentifier: reminderExternalIdentifier,
        title: entry.node.text,
        isCompleted: entry.node.type.isCompleted,
        dueDate: reminderMetadata?.dueDate,
        hasExplicitTime: reminderMetadata?.hasExplicitTime ?? false,
        recurrenceRuleRaw: OutlinerIntegratedStore.encodeRecurrence(reminderMetadata?.recurrence),
        durationMinutes: durationMinutes,
        calendarEventExternalIdentifier: calendarEventExternalIdentifier
      )
    }
  }

  struct RuntimeLogseqTaskBinding: Sendable {
    let taskID: UUID
    let reminderIdentifier: String?
    let reminderExternalIdentifier: String?
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
    let hasExplicitTime: Bool
    let recurrenceRuleRaw: String?
    let durationMinutes: Int?
    let calendarEventExternalIdentifier: String?
  }

}
