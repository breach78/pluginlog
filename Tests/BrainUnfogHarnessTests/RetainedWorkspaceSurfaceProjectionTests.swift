import XCTest
@testable import BrainUnfogHarness

final class RetainedWorkspaceSurfaceProjectionTests: XCTestCase {
  func testBuildMapsRetainedSnapshotIntoScheduleSurfaceWithoutCalendarWrites() throws {
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "reminder-list-1")
    let dateOnlyTaskID = UUID()
    let timedTaskID = UUID()
    let timedDefaultDurationTaskID = UUID()
    let day = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 25)))
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 14, minute: 30))
    )
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        RetainedProject(
          identity: RetainedProjectIdentity(
            projectID: projectID,
            reminderListExternalIdentifier: "reminder-list-1"
          ),
          fileURL: URL(fileURLWithPath: "/tmp/Launch.md"),
          title: "Launch",
          noteMarkdown: "Ship notes",
          tasks: [
            makeTask(
              taskID: dateOnlyTaskID,
              title: "Date only",
              parsedDate: day,
              hasExplicitTime: false,
              durationMinutes: nil,
              calendarEventExternalIdentifier: nil
            ),
            makeTask(
              taskID: timedTaskID,
              title: "Timed",
              parsedDate: start,
              hasExplicitTime: true,
              durationMinutes: 45,
              rawRepeatRule: "weekly",
              canonicalRepeatRule: "weekly|1|",
              calendarEventExternalIdentifier: "event-1"
            ),
            makeTask(
              taskID: timedDefaultDurationTaskID,
              title: "Timed default duration",
              parsedDate: start,
              hasExplicitTime: true,
              durationMinutes: nil,
              calendarEventExternalIdentifier: nil
            ),
          ],
          usesProjectTag: true,
          isBUFOwned: true,
          hasManagedTaskSection: true,
          canSafelyPersistProjectNote: true
        )
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [projectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)
    let projectSnapshot = try XCTUnwrap(surface.projectSnapshots[projectID])
    let entries = try XCTUnwrap(surface.scheduleEntriesByProjectID[projectID])

    XCTAssertEqual(projectSnapshot.title, "Launch")
    XCTAssertEqual(projectSnapshot.projectNoteMarkdown, "Ship notes")
    XCTAssertEqual(projectSnapshot.reminderListExternalIdentifier, "reminder-list-1")
    XCTAssertEqual(entries.map(\.taskID), [dateOnlyTaskID, timedTaskID, timedDefaultDurationTaskID])
    XCTAssertFalse(entries[0].scheduleHasExplicitTime)
    XCTAssertEqual(entries[0].dueDate, day)
    XCTAssertTrue(entries[1].scheduleHasExplicitTime)
    XCTAssertEqual(entries[1].scheduledDurationMinutes, 45)
    XCTAssertEqual(entries[1].recurrenceRuleRaw, "weekly|1|")
    XCTAssertEqual(surface.projectSummaries[projectID]?.openRootTaskCount, 3)
    XCTAssertEqual(surface.calendarBridgeDecisionsByTaskID[dateOnlyTaskID], .noAction)
    XCTAssertEqual(surface.calendarBridgeDecisionsByTaskID[timedTaskID], .noAction)
    XCTAssertEqual(surface.calendarBridgeDecisionsByTaskID[timedDefaultDurationTaskID], .noAction)

    let taskDescriptors = ScheduleProjectionService.taskDescriptors(
      projectIDs: [projectID],
      projectSnapshots: surface.projectSnapshots,
      scheduleEntriesByProjectID: surface.scheduleEntriesByProjectID
    )
    let scheduleItems = WorkspaceTaskScheduleEventStore.items(
      from: taskDescriptors,
      calendar: Self.calendar
    )
    XCTAssertTrue(
      try XCTUnwrap(scheduleItems.first { $0.source == .workspaceTask(taskID: dateOnlyTaskID, projectID: projectID) })
        .isAllDay
    )
    let defaultDurationItem = try XCTUnwrap(
      scheduleItems.first {
        $0.source == .workspaceTask(taskID: timedDefaultDurationTaskID, projectID: projectID)
      }
    )
    XCTAssertEqual(defaultDurationItem.endDate.timeIntervalSince(defaultDurationItem.startDate), 15 * 60)
  }

  func testBuildBlocksPartialRequestedProjectCoverage() {
    let presentProjectID = UUID()
    let missingProjectID = UUID()
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        makeProject(projectID: presentProjectID)
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [presentProjectID, missingProjectID],
      calendar: Self.calendar
    )

    XCTAssertEqual(
      result,
      .blocked(.partialProjectCoverage(missingProjectIDs: [missingProjectID]))
    )
  }

  func testBuildBlocksIdentityFailuresWithoutFallback() {
    let projectID = UUID()
    let taskID = UUID()
    let page = makePageSnapshot(
      title: "Project",
      projectID: projectID,
      tasks: [
        .init(taskID: taskID, title: "A", isCompleted: false),
        .init(taskID: taskID, title: "B", isCompleted: false),
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      pages: [page],
      projectIDs: [projectID],
      calendar: Self.calendar
    )

    XCTAssertEqual(result, .blocked(.identityFailure(.duplicateTaskID(taskID))))
  }

  func testBuildBlocksAmbiguousSnapshotIdentitiesWithoutTrapOrOverwrite() {
    let sharedProjectID = UUID()
    let duplicateProjectResult = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: RetainedWorkspaceSnapshot(
        projects: [
          makeProject(projectID: sharedProjectID),
          makeProject(projectID: sharedProjectID),
        ]
      ),
      projectIDs: [],
      calendar: Self.calendar
    )
    XCTAssertEqual(duplicateProjectResult, .blocked(.identityFailure(.duplicateProjectID(sharedProjectID))))

    let projectID = UUID()
    let sharedEventID = "event-1"
    let duplicateEventResult = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: RetainedWorkspaceSnapshot(
        projects: [
          makeProject(
            projectID: projectID,
            tasks: [
              makeTask(
                taskID: UUID(),
                title: "A",
                calendarEventExternalIdentifier: sharedEventID
              ),
              makeTask(
                taskID: UUID(),
                title: "B",
                calendarEventExternalIdentifier: sharedEventID
              ),
            ]
          )
        ]
      ),
      projectIDs: [projectID],
      calendar: Self.calendar
    )
    XCTAssertEqual(
      duplicateEventResult,
      .blocked(.identityFailure(.duplicateCalendarEventExternalIdentifier(sharedEventID)))
    )
  }

  func testBuildBlocksTasksWithoutStableTaskIdentity() {
    let projectID = UUID()
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        makeProject(
          projectID: projectID,
          tasks: [
            makeTask(taskID: nil, title: "Plain Logseq task")
          ]
        )
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [projectID],
      calendar: Self.calendar
    )

    XCTAssertEqual(
      result,
      .blocked(.taskIdentityUnavailable(projectID: projectID, title: "Plain Logseq task"))
    )
  }

  func testLoadAllowsFallbackWhenGraphIsNotConfigured() async {
    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      graphRootURL: nil,
      projectIDs: [UUID()],
      calendar: Self.calendar
    )

    XCTAssertEqual(result, .fallbackAllowed(.graphNotConfigured))
  }

  func testResolveRetainedOnlyBlocksUnavailableRetainedLoadsWithoutFallbackData() {
    let graphMissing = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(
      .fallbackAllowed(.graphNotConfigured)
    )
    XCTAssertEqual(graphMissing.source, .blocked(.graphNotConfigured))
    XCTAssertTrue(graphMissing.projectSnapshots.isEmpty)
    XCTAssertTrue(graphMissing.scheduleEntriesByProjectID.isEmpty)
    XCTAssertTrue(graphMissing.calendarBridgeDecisionsByTaskID.isEmpty)

    let loadFailed = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(
      .fallbackAllowed(.loadFailed("disk unavailable"))
    )
    XCTAssertEqual(loadFailed.source, .blocked(.loadFailed("disk unavailable")))
    XCTAssertTrue(loadFailed.projectSnapshots.isEmpty)
    XCTAssertTrue(loadFailed.scheduleEntriesByProjectID.isEmpty)
    XCTAssertTrue(loadFailed.calendarBridgeDecisionsByTaskID.isEmpty)
  }

  func testRetainedOnlyBlockedReadsRequireConsumerCacheInvalidation() {
    XCTAssertFalse(
      RetainedWorkspaceSurfaceProjectionBuilder.shouldInvalidateConsumerCaches(for: .retained)
    )
    XCTAssertTrue(
      RetainedWorkspaceSurfaceProjectionBuilder.shouldInvalidateConsumerCaches(
        for: .blocked(.graphNotConfigured)
      )
    )
    XCTAssertTrue(
      RetainedWorkspaceSurfaceProjectionBuilder.shouldInvalidateConsumerCaches(
        for: .legacyFallback(.graphNotConfigured)
      )
    )
  }

  func testResolveKeepsRetainedSuccessAndBlocksIdentityFailures() {
    let projectID = UUID()
    let retainedProjection = RetainedWorkspaceSurfaceProjection(
      projectSnapshots: [projectID: makeWorkspaceProjectSnapshot(projectID: projectID)],
      projectSummaries: [:],
      scheduleEntriesByProjectID: [projectID: []],
      calendarBridgeDecisionsByTaskID: [:]
    )
    let retainedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolve(
      .loaded(retainedProjection)
    ) {
      XCTFail("Retained success must not consult legacy fallback")
      return ReminderWorkspaceSurfaceProjection(
        projectSnapshots: [:],
        projectSummaries: [:],
        scheduleEntriesByProjectID: [:]
      )
    }
    XCTAssertEqual(retainedRead.source, .retained)
    XCTAssertEqual(retainedRead.projectSnapshots[projectID]?.title, "Project")

    let blockedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolve(
      .blocked(.identityFailure(.duplicateTaskID(projectID)))
    ) {
      XCTFail("Blocked identity failures must not consult legacy fallback")
      return ReminderWorkspaceSurfaceProjection(
        projectSnapshots: [projectID: makeWorkspaceProjectSnapshot(projectID: projectID)],
        projectSummaries: [:],
        scheduleEntriesByProjectID: [projectID: []]
      )
    }
    XCTAssertEqual(blockedRead.source, .blocked(.identityFailure(.duplicateTaskID(projectID))))
    XCTAssertTrue(blockedRead.projectSnapshots.isEmpty)
  }

  func testResolveAllowsLegacyFallbackOnlyForUnavailableRetainedLoad() {
    let projectID = UUID()
    let resolved = RetainedWorkspaceSurfaceProjectionBuilder.resolve(
      .fallbackAllowed(.graphNotConfigured)
    ) {
      ReminderWorkspaceSurfaceProjection(
        projectSnapshots: [projectID: makeWorkspaceProjectSnapshot(projectID: projectID)],
        projectSummaries: [:],
        scheduleEntriesByProjectID: [projectID: []]
      )
    }

    XCTAssertEqual(resolved.source, .legacyFallback(.graphNotConfigured))
    XCTAssertEqual(resolved.projectSnapshots[projectID]?.id, projectID)
    XCTAssertTrue(resolved.calendarBridgeDecisionsByTaskID.isEmpty)
  }

  func testLoadBuildsFromLogseqGraphRootWhenAvailable() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedSurfaceGraph")
    let projectID = UUID()
    let taskID = UUID()
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRootURL.appendingPathComponent("pages", isDirectory: true)
    )
    _ = try await store.upsertPage(
      .init(projectID: projectID, title: "Graph Project", reminderListExternalIdentifier: nil),
      noteMarkdown: "Graph note",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Graph task",
          isCompleted: false,
          date: "2026-04-25 14:30",
          duration: "45",
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: "event-1"
        )
      ]
    )

    let result = await RetainedWorkspaceSurfaceProjectionBuilder.load(
      graphRootURL: graphRootURL,
      projectIDs: [projectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)

    XCTAssertEqual(surface.projectSnapshots[projectID]?.title, "Graph Project")
    XCTAssertEqual(surface.scheduleEntriesByProjectID[projectID]?.first?.taskID, taskID)
    XCTAssertEqual(surface.calendarBridgeDecisionsByTaskID[taskID], .noAction)
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private func makeProject(
    projectID: UUID,
    tasks: [RetainedTask] = []
  ) -> RetainedProject {
    RetainedProject(
      identity: RetainedProjectIdentity(projectID: projectID, reminderListExternalIdentifier: nil),
      fileURL: URL(fileURLWithPath: "/tmp/\(projectID.uuidString).md"),
      title: "Project",
      noteMarkdown: "",
      tasks: tasks,
      usesProjectTag: true,
      isBUFOwned: true,
      hasManagedTaskSection: true,
      canSafelyPersistProjectNote: true
    )
  }

  private func makeWorkspaceProjectSnapshot(projectID: UUID) -> WorkspaceProjectRuntimeRecord {
    WorkspaceProjectRuntimeRecord(
      id: projectID,
      title: "Project",
      colorHex: nil,
      reminderListIdentifier: nil,
      reminderListExternalIdentifier: nil,
      projectNoteMarkdown: "",
      localStartDate: nil,
      localDeadline: nil,
      progressStageRaw: nil,
      boardOrder: nil,
      createdAt: .distantPast,
      updatedAt: .distantPast,
      isArchived: false
    )
  }

  private func makeTask(
    taskID: UUID?,
    title: String,
    parsedDate: Date? = nil,
    hasExplicitTime: Bool = false,
    durationMinutes: Int? = nil,
    rawRepeatRule: String? = nil,
    canonicalRepeatRule: String? = nil,
    calendarEventExternalIdentifier: String? = nil
  ) -> RetainedTask {
    RetainedTask(
      identity: RetainedTaskIdentity(
        taskID: taskID,
        reminderExternalIdentifier: taskID == nil ? nil : "reminder-\(taskID!.uuidString)",
        calendarEventExternalIdentifier: calendarEventExternalIdentifier
      ),
      title: title,
      isCompleted: false,
      schedule: RetainedTaskSchedule(
        rawDate: parsedDate.map {
          hasExplicitTime
            ? LogseqReminderPropertyCodec.encodeDate($0, hasExplicitTime: true) ?? ""
            : LogseqReminderPropertyCodec.encodeDate($0, hasExplicitTime: false) ?? ""
        },
        parsedDate: parsedDate,
        hasExplicitTime: hasExplicitTime,
        rawDuration: durationMinutes.map(String.init),
        durationMinutes: durationMinutes,
        rawRepeatRule: rawRepeatRule,
        canonicalRepeatRule: canonicalRepeatRule
      ),
      isManagedTask: true
    )
  }

  private func makePageSnapshot(
    title: String,
    projectID: UUID?,
    tasks: [LogseqProjectPageStore.TaskRecord]
  ) -> LogseqProjectPageStore.PageSnapshot {
    LogseqProjectPageStore.PageSnapshot(
      fileURL: URL(fileURLWithPath: "/tmp/\(title).md"),
      title: title,
      projectID: projectID,
      reminderListExternalIdentifier: nil,
      usesProjectTag: true,
      isBUFOwned: true,
      hasManagedTaskSection: true,
      noteMarkdown: "",
      managedTasks: tasks,
      externalTasks: [],
      canSafelyPersistProjectNote: true
    )
  }

  private func makeGraphRoot(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}

private extension RetainedWorkspaceSurfaceProjectionLoadResult {
  var loadedProjection: RetainedWorkspaceSurfaceProjection? {
    guard case .loaded(let projection) = self else { return nil }
    return projection
  }
}
