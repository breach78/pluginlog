import XCTest
@testable import BrainUnfog

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
              noteText: "Date-only note",
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
    XCTAssertEqual(entries[0].reminderNoteText, "Date-only note")
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
    XCTAssertEqual(defaultDurationItem.endDate.timeIntervalSince(defaultDurationItem.startDate), 30 * 60)
  }

  func testUserFlowScheduleSurfacesShareRetainedProjectionSource() throws {
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: "reminder-list-1")
    let taskID = UUID()
    let start = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 9, minute: 15))
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
          noteMarkdown: "",
          tasks: [
            makeTask(
              taskID: taskID,
              title: "Shared schedule",
              parsedDate: start,
              hasExplicitTime: true,
              durationMinutes: 75,
              calendarEventExternalIdentifier: nil
            )
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
    let descriptors = ScheduleProjectionService.taskDescriptors(
      projectIDs: [projectID],
      projectSnapshots: surface.projectSnapshots,
      scheduleEntriesByProjectID: surface.scheduleEntriesByProjectID
    )

    let boardItem = try XCTUnwrap(
      WorkspaceTaskScheduleEventStore.items(from: descriptors, calendar: Self.calendar)
        .first { $0.source == .workspaceTask(taskID: taskID, projectID: projectID) }
    )
    let monthItem = try XCTUnwrap(
      ScheduleMonthItemFactory.items(
        workspaceTasks: descriptors,
        foregroundEvents: [],
        backgroundEvents: [],
        calendar: Self.calendar
      )
      .first { $0.source == .workspaceTask(taskID: taskID, projectID: projectID) }
    )

    XCTAssertEqual(boardItem.startDate, start)
    XCTAssertEqual(boardItem.endDate.timeIntervalSince(boardItem.startDate), 75 * 60)
    XCTAssertEqual(monthItem.startDate, boardItem.startDate)
    XCTAssertEqual(monthItem.endDate, boardItem.endDate)
    XCTAssertFalse(monthItem.isAllDay)
  }

  func testOpenRecurringTasksKeepStoredAnchorDateInsteadOfExpandedCalendarOccurrence() throws {
    let projectID = UUID()
    let taskID = UUID()
    let storedDueDate = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 6))
    )
    let currentDay = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 10))
    )
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        makeProject(
          projectID: projectID,
          tasks: [
            makeTask(
              taskID: taskID,
              title: "Daily",
              parsedDate: storedDueDate,
              rawRepeatRule: "daily|1",
              canonicalRepeatRule: "daily|1"
            )
          ]
        )
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [projectID],
      calendar: Self.calendar,
      now: currentDay
    )
    let surface = try XCTUnwrap(result.loadedProjection)
    let entry = try XCTUnwrap(surface.scheduleEntriesByProjectID[projectID]?.first)

    XCTAssertEqual(entry.dueDate, storedDueDate)
    XCTAssertEqual(entry.displayedDate, storedDueDate)
    XCTAssertEqual(surface.projectSummaries[projectID]?.todayTaskCount, 0)
    XCTAssertEqual(surface.projectSummaries[projectID]?.overdueOpenRootTaskCount, 1)
    let descriptor = try XCTUnwrap(
      ScheduleProjectionService.taskDescriptors(
        projectIDs: [projectID],
        projectSnapshots: surface.projectSnapshots,
        scheduleEntriesByProjectID: surface.scheduleEntriesByProjectID
      ).first
    )
    XCTAssertEqual(descriptor.taskRow.reminderDate, storedDueDate)
    XCTAssertEqual(
      ReminderTaskDateCanonicalizer.unifiedDate(
        dueDate: entry.dueDate,
        startDate: entry.startDate,
        displayedDate: entry.displayedDate
      ),
      storedDueDate
    )
  }

  func testTimelineRuntimeBarsKeepAllDatedTaskPreviewItems() throws {
    let projectID = UUID()
    let scheduledDay = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 25))
    )
    let taskIDs = (0..<6).map { _ in UUID() }
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        makeProject(
          projectID: projectID,
          tasks: taskIDs.enumerated().map { index, taskID in
            makeTask(taskID: taskID, title: "Task \(index + 1)", parsedDate: scheduledDay)
          }
        )
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [projectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)
    let bar = try XCTUnwrap(
      TimelineProjectionService.runtimeBars(
        service: DefaultTimelineService(),
        projectIDs: [projectID],
        projectSnapshots: surface.projectSnapshots,
        projectSummariesByID: surface.projectSummaries,
        scheduleEntriesByProjectID: surface.scheduleEntriesByProjectID
      ).first
    )
    let previewDay = Calendar.autoupdatingCurrent.startOfDay(for: scheduledDay)
    let preview = try XCTUnwrap(bar.dailyTaskPreviews[previewDay])

    XCTAssertEqual(bar.dailyTaskCounts[previewDay], taskIDs.count)
    XCTAssertEqual(preview.totalCount, taskIDs.count)
    XCTAssertEqual(preview.tasks.map(\.taskID), taskIDs)
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
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        makeProject(
          projectID: projectID,
          tasks: [
            makeTask(taskID: taskID, title: "A"),
            makeTask(taskID: taskID, title: "B"),
          ]
        )
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
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

  func testBuildSkipsTasksWithoutStableTaskIdentity() throws {
    let projectID = UUID()
    let stableTaskID = UUID()
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        makeProject(
          projectID: projectID,
          tasks: [
            makeTask(taskID: nil, title: "Plain task"),
            makeTask(taskID: stableTaskID, title: "Reminder-backed task"),
          ]
        )
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [projectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)

    XCTAssertEqual(surface.projectSnapshots[projectID]?.title, "Project")
    XCTAssertEqual(surface.scheduleEntriesByProjectID[projectID]?.map(\.taskID), [stableTaskID])
    XCTAssertEqual(surface.calendarBridgeDecisionsByTaskID[stableTaskID], .noAction)
  }

  func testBuildProjectsCarryTimelineFrontmatterIntoRuntimeBars() throws {
    let listID = "reminder-list-1"
    let projectID = RetainedProjectionBuilder.derivedProjectID(for: listID)
    let taskID = UUID()
    let firstTaskDay = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 10))
    )
    let deadline = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 30))
    )
    let explicitStart = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))
    )
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        RetainedProject(
          identity: RetainedProjectIdentity(
            projectID: projectID,
            reminderListExternalIdentifier: listID
          ),
          fileURL: URL(fileURLWithPath: "/tmp/Launch.md"),
          title: "Launch",
          noteMarkdown: "",
          tasks: [
            makeTask(taskID: taskID, title: "Dated", parsedDate: firstTaskDay),
          ],
          usesProjectTag: true,
          isBUFOwned: true,
          hasManagedTaskSection: false,
          canSafelyPersistProjectNote: false,
          isArchived: false,
          colorHex: "#34C759",
          localStartDate: explicitStart,
          localDeadline: deadline,
          progressStage: .later
        )
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [projectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)
    let project = try XCTUnwrap(surface.projectSnapshots[projectID])
    let summary = try XCTUnwrap(surface.projectSummaries[projectID])
    let bar = try XCTUnwrap(
      TimelineProjectionService.runtimeBars(
        service: DefaultTimelineService(),
        projectIDs: [projectID],
        projectSnapshots: surface.projectSnapshots,
        projectSummariesByID: surface.projectSummaries,
        scheduleEntriesByProjectID: surface.scheduleEntriesByProjectID
      ).first
    )

    XCTAssertEqual(project.colorHex, "#34C759")
    XCTAssertEqual(project.localStartDate, explicitStart)
    XCTAssertEqual(project.localDeadline, deadline)
    XCTAssertEqual(project.progressStageRaw, ProjectProgressStage.later.storageRawValue)
    XCTAssertEqual(summary.stageRaw, ProjectProgressStage.later.storageRawValue)
    XCTAssertEqual(summary.deadline, deadline)
    XCTAssertEqual(bar.colorHex, "#34C759")
    XCTAssertEqual(bar.start, Calendar.autoupdatingCurrent.startOfDay(for: explicitStart))
    XCTAssertEqual(bar.end, Calendar.autoupdatingCurrent.startOfDay(for: deadline))
    XCTAssertEqual(ProjectProgressStage.from(progress: bar.progress), .later)
  }

  func testArchivedProjectsAreFilteredFromTimelineAndScheduleProjections() throws {
    let activeProjectID = UUID()
    let archivedProjectID = UUID()
    let activeTaskID = UUID()
    let archivedTaskID = UUID()
    let scheduledDay = try XCTUnwrap(
      Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 25))
    )
    let snapshot = RetainedWorkspaceSnapshot(
      projects: [
        makeProject(
          projectID: activeProjectID,
          tasks: [
            makeTask(taskID: activeTaskID, title: "Active task", parsedDate: scheduledDay),
          ],
          isArchived: false
        ),
        makeProject(
          projectID: archivedProjectID,
          tasks: [
            makeTask(taskID: archivedTaskID, title: "Archived task", parsedDate: scheduledDay),
          ],
          isArchived: true
        ),
      ]
    )

    let result = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [activeProjectID, archivedProjectID],
      calendar: Self.calendar
    )
    let surface = try XCTUnwrap(result.loadedProjection)

    let bars = TimelineProjectionService.runtimeBars(
      service: DefaultTimelineService(),
      projectIDs: [activeProjectID, archivedProjectID],
      projectSnapshots: surface.projectSnapshots,
      projectSummariesByID: surface.projectSummaries,
      scheduleEntriesByProjectID: surface.scheduleEntriesByProjectID
    )
    let descriptors = ScheduleProjectionService.taskDescriptors(
      projectIDs: [activeProjectID, archivedProjectID],
      projectSnapshots: surface.projectSnapshots,
      scheduleEntriesByProjectID: surface.scheduleEntriesByProjectID
    )

    XCTAssertEqual(bars.map(\.projectID), [activeProjectID])
    XCTAssertEqual(descriptors.map(\.projectID), [activeProjectID])
    XCTAssertEqual(descriptors.map(\.taskRow.id), [activeTaskID])
  }

  func testResolveRetainedOnlyBlocksUnavailableRetainedLoadsWithoutFallbackData() {
    let vaultMissing = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(
      .blocked(.obsidianVaultNotConfigured)
    )
    XCTAssertEqual(vaultMissing.source, .blocked(.obsidianVaultNotConfigured))
    XCTAssertEqual(
      vaultMissing.errorMessage,
      RetainedWorkspaceSurfaceProjectionBlocker.obsidianVaultNotConfigured.userMessage
    )
    XCTAssertTrue(vaultMissing.projectSnapshots.isEmpty)
    XCTAssertTrue(vaultMissing.scheduleEntriesByProjectID.isEmpty)
    XCTAssertTrue(vaultMissing.calendarBridgeDecisionsByTaskID.isEmpty)

    let loadFailed = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(
      .blocked(.loadFailed("disk unavailable"))
    )
    XCTAssertEqual(loadFailed.source, .blocked(.loadFailed("disk unavailable")))
    XCTAssertEqual(
      loadFailed.errorMessage,
      RetainedWorkspaceSurfaceProjectionBlocker.loadFailed("disk unavailable").userMessage
    )
    XCTAssertTrue(loadFailed.projectSnapshots.isEmpty)
    XCTAssertTrue(loadFailed.scheduleEntriesByProjectID.isEmpty)
    XCTAssertTrue(loadFailed.calendarBridgeDecisionsByTaskID.isEmpty)
  }

  func testTaskIdentityUnavailableBlocksWithoutGlobalErrorAlert() {
    let projectID = UUID()

    let blockedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(
      .blocked(.taskIdentityUnavailable(projectID: projectID, title: "Plain task"))
    )

    XCTAssertEqual(
      blockedRead.source,
      .blocked(.taskIdentityUnavailable(projectID: projectID, title: "Plain task"))
    )
    XCTAssertNil(blockedRead.errorMessage)
    XCTAssertTrue(blockedRead.projectSnapshots.isEmpty)
    XCTAssertTrue(blockedRead.scheduleEntriesByProjectID.isEmpty)
  }

  func testPartialProjectCoverageBlocksWithoutGlobalErrorAlert() {
    let missingProjectID = UUID()

    let blockedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(
      .blocked(.partialProjectCoverage(missingProjectIDs: [missingProjectID]))
    )

    XCTAssertEqual(
      blockedRead.source,
      .blocked(.partialProjectCoverage(missingProjectIDs: [missingProjectID]))
    )
    XCTAssertNil(blockedRead.errorMessage)
    XCTAssertTrue(blockedRead.projectSnapshots.isEmpty)
    XCTAssertTrue(blockedRead.scheduleEntriesByProjectID.isEmpty)
  }

  func testRetainedOnlyReadsRequireConsumerCacheInvalidation() {
    XCTAssertTrue(
      RetainedWorkspaceSurfaceProjectionBuilder.shouldInvalidateConsumerCaches(for: .retained)
    )
    XCTAssertTrue(
      RetainedWorkspaceSurfaceProjectionBuilder.shouldInvalidateConsumerCaches(
        for: .blocked(.obsidianVaultNotConfigured)
      )
    )
  }

  func testResolveRetainedOnlyKeepsRetainedSuccessAndBlocksIdentityFailures() {
    let projectID = UUID()
    let retainedProjection = RetainedWorkspaceSurfaceProjection(
      projectSnapshots: [projectID: makeWorkspaceProjectSnapshot(projectID: projectID)],
      projectSummaries: [:],
      scheduleEntriesByProjectID: [projectID: []],
      calendarBridgeDecisionsByTaskID: [:]
    )
    let retainedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(
      .loaded(retainedProjection)
    )
    XCTAssertEqual(retainedRead.source, .retained)
    XCTAssertEqual(retainedRead.projectSnapshots[projectID]?.title, "Project")

    let blockedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(
      .blocked(.identityFailure(.duplicateTaskID(projectID)))
    )
    XCTAssertEqual(blockedRead.source, .blocked(.identityFailure(.duplicateTaskID(projectID))))
    XCTAssertTrue(blockedRead.projectSnapshots.isEmpty)
  }

  func testPartialMergeReplacesOnlyRequestedProjects() {
    let firstProjectID = UUID()
    let secondProjectID = UUID()
    let staleTaskID = UUID()
    let freshTaskID = UUID()
    let untouchedTaskID = UUID()
    let existing = RetainedWorkspaceSurfaceProjection(
      projectSnapshots: [
        firstProjectID: makeWorkspaceProjectSnapshot(projectID: firstProjectID, title: "Old"),
        secondProjectID: makeWorkspaceProjectSnapshot(projectID: secondProjectID, title: "Keep"),
      ],
      projectSummaries: [
        firstProjectID: makeSummary(title: "Old"),
        secondProjectID: makeSummary(title: "Keep"),
      ],
      scheduleEntriesByProjectID: [
        firstProjectID: [makeEntry(taskID: staleTaskID, title: "Old task")],
        secondProjectID: [makeEntry(taskID: untouchedTaskID, title: "Keep task")],
      ],
      calendarBridgeDecisionsByTaskID: [
        staleTaskID: .noAction,
        untouchedTaskID: .noAction,
      ]
    )
    let loaded = RetainedWorkspaceSurfaceProjection(
      projectSnapshots: [
        firstProjectID: makeWorkspaceProjectSnapshot(projectID: firstProjectID, title: "New")
      ],
      projectSummaries: [
        firstProjectID: makeSummary(title: "New")
      ],
      scheduleEntriesByProjectID: [
        firstProjectID: [makeEntry(taskID: freshTaskID, title: "New task")]
      ],
      calendarBridgeDecisionsByTaskID: [
        freshTaskID: .noAction
      ]
    )

    let merged = RetainedWorkspaceSurfaceProjectionMergePolicy.merge(
      existing: existing,
      loaded: loaded,
      replacingProjectIDs: [firstProjectID]
    )

    XCTAssertEqual(merged.projectSnapshots[firstProjectID]?.title, "New")
    XCTAssertEqual(merged.projectSnapshots[secondProjectID]?.title, "Keep")
    XCTAssertEqual(merged.scheduleEntriesByProjectID[firstProjectID]?.map(\.taskID), [freshTaskID])
    XCTAssertEqual(merged.scheduleEntriesByProjectID[secondProjectID]?.map(\.taskID), [untouchedTaskID])
    XCTAssertNil(merged.calendarBridgeDecisionsByTaskID[staleTaskID])
    XCTAssertEqual(merged.calendarBridgeDecisionsByTaskID[freshTaskID], .noAction)
    XCTAssertEqual(merged.calendarBridgeDecisionsByTaskID[untouchedTaskID], .noAction)
  }

  func testPartialMergeFiltersWriteMarkersForReplacedProjectTasks() {
    let projectID = UUID()
    let staleTaskID = UUID()
    let freshTaskID = UUID()
    let untouchedTaskID = UUID()
    let existing = RetainedWorkspaceSurfaceProjection(
      projectSnapshots: [projectID: makeWorkspaceProjectSnapshot(projectID: projectID)],
      projectSummaries: [projectID: makeSummary(title: "Project")],
      scheduleEntriesByProjectID: [projectID: [makeEntry(taskID: staleTaskID, title: "Old")]],
      calendarBridgeDecisionsByTaskID: [staleTaskID: .noAction, untouchedTaskID: .noAction]
    )
    let loaded = RetainedWorkspaceSurfaceProjection(
      projectSnapshots: [projectID: makeWorkspaceProjectSnapshot(projectID: projectID)],
      projectSummaries: [projectID: makeSummary(title: "Project")],
      scheduleEntriesByProjectID: [projectID: [makeEntry(taskID: freshTaskID, title: "New")]],
      calendarBridgeDecisionsByTaskID: [freshTaskID: .noAction]
    )
    let markers = [
      staleTaskID: RetainedCalendarBridgeWriteMarker(
        taskID: staleTaskID,
        operation: .upsertOwnedEvent,
        externalIdentifier: nil,
        title: "Old",
        startDate: nil,
        durationMinutes: nil
      ),
      untouchedTaskID: RetainedCalendarBridgeWriteMarker(
        taskID: untouchedTaskID,
        operation: .upsertOwnedEvent,
        externalIdentifier: nil,
        title: "Keep",
        startDate: nil,
        durationMinutes: nil
      ),
    ]

    let filtered = RetainedWorkspaceSurfaceProjectionMergePolicy.filteredWriteMarkers(
      existingMarkers: markers,
      existing: existing,
      loaded: loaded,
      replacingProjectIDs: [projectID]
    )

    XCTAssertNil(filtered[staleTaskID])
    XCTAssertNil(filtered[freshTaskID])
    XCTAssertEqual(filtered[untouchedTaskID]?.taskID, untouchedTaskID)
  }

  func testProjectStageOverrideKeepsPendingStageOverStaleReload() {
    let projectID = UUID()
    let projection = RetainedWorkspaceSurfaceProjection(
      projectSnapshots: [
        projectID: makeWorkspaceProjectSnapshot(projectID: projectID, stage: .do)
      ],
      projectSummaries: [
        projectID: makeSummary(title: "Project", stage: .do)
      ],
      scheduleEntriesByProjectID: [:],
      calendarBridgeDecisionsByTaskID: [:]
    )

    let overridden = RetainedWorkspaceProjectStageOverridePolicy.apply(
      [projectID: .decide],
      to: projection
    )

    XCTAssertEqual(
      overridden.projectSnapshots[projectID]?.progressStageRaw,
      ProjectProgressStage.decide.storageRawValue
    )
    XCTAssertEqual(
      overridden.projectSummaries[projectID]?.stageRaw,
      ProjectProgressStage.decide.storageRawValue
    )
    XCTAssertEqual(
      overridden.projectSummaries[projectID]?.progress,
      ProjectProgressStage.decide.progressValue
    )
  }

  func testProjectionBuildRecordsPerformanceMeasurement() throws {
    SyncPerformanceCounter.reset()
    defer { SyncPerformanceCounter.reset() }
    let projectID = UUID()
    let snapshot = RetainedWorkspaceSnapshot(projects: [makeProject(projectID: projectID)])

    _ = RetainedWorkspaceSurfaceProjectionBuilder.build(
      snapshot: snapshot,
      projectIDs: [projectID],
      calendar: Self.calendar,
      now: .distantPast
    )

    let operationSnapshot = SyncPerformanceCounter.operationSnapshot()
    XCTAssertEqual(operationSnapshot[SyncPerformanceOperation.projectionBuild.rawValue]?.count, 1)
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private func makeProject(
    projectID: UUID,
    tasks: [RetainedTask] = [],
    isArchived: Bool = false
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
      canSafelyPersistProjectNote: true,
      isArchived: isArchived
    )
  }

  private func makeWorkspaceProjectSnapshot(
    projectID: UUID,
    title: String = "Project",
    stage: ProjectProgressStage? = nil
  ) -> WorkspaceProjectRuntimeRecord {
    WorkspaceProjectRuntimeRecord(
      id: projectID,
      title: title,
      colorHex: nil,
      reminderListIdentifier: nil,
      reminderListExternalIdentifier: nil,
      projectNoteMarkdown: "",
      localStartDate: nil,
      localDeadline: nil,
      progressStageRaw: stage?.storageRawValue,
      boardOrder: nil,
      createdAt: .distantPast,
      updatedAt: .distantPast,
      isArchived: false
    )
  }

  private func makeSummary(
    title: String,
    stage: ProjectProgressStage = .do
  ) -> ProjectSummaryRecord {
    ProjectSummaryRecord(
      openRootTaskCount: 0,
      completedRootTaskCount: 0,
      undatedOpenRootTaskCount: 0,
      overdueOpenRootTaskCount: 0,
      todayTaskCount: 0,
      nextUpcomingDate: nil,
      deadline: nil,
      stageRaw: stage.storageRawValue,
      progress: stage.progressValue,
      latestTaskUpdatedAt: nil,
      title: title,
      colorHex: nil,
      isArchived: false
    )
  }

  private func makeEntry(taskID: UUID, title: String) -> ScheduleSliceEntry {
    ScheduleSliceEntry(
      taskID: taskID,
      parentTaskID: nil,
      title: title,
      displayedDate: nil,
      startDate: nil,
      dueDate: nil,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      isCompleted: false,
      completionDate: nil,
      recurrenceRuleRaw: nil,
      isLocalCompletedRecurringOccurrence: false,
      attachmentCount: 0,
      hasReminderNoteContent: false,
      reminderNoteText: "",
      requiredWorkDays: 0,
      completedWorkUnits: 0,
      completedWorkUnitDates: [],
      preparationScheduleOverridesRaw: "",
      rowOrder: 0,
      priority: 0,
      isFlagged: false,
      isArchived: false,
      localUpdatedAt: .distantPast,
      createdAt: .distantPast
    )
  }

  private func makeTask(
    taskID: UUID?,
    title: String,
    noteText: String = "",
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
      noteText: noteText,
      isCompleted: false,
      schedule: RetainedTaskSchedule(
        rawDate: parsedDate.map {
          hasExplicitTime
            ? ReminderScheduleMetadataCodec.encodeDate($0, hasExplicitTime: true) ?? ""
            : ReminderScheduleMetadataCodec.encodeDate($0, hasExplicitTime: false) ?? ""
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

}

private extension RetainedWorkspaceSurfaceProjectionLoadResult {
  var loadedProjection: RetainedWorkspaceSurfaceProjection? {
    guard case .loaded(let projection) = self else { return nil }
    return projection
  }
}
