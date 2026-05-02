import CoreGraphics
import XCTest
@testable import BrainUnfog

final class TimelineBoardReadPathTests: XCTestCase {
  func testScrollOriginChangeIgnoresInitialAndSameOriginNotifications() {
    XCTAssertFalse(
      TimelineBoardReadPath.didScrollOriginChange(from: nil, to: CGPoint(x: 10, y: 20))
    )
    XCTAssertFalse(
      TimelineBoardReadPath.didScrollOriginChange(
        from: CGPoint(x: 10, y: 20),
        to: CGPoint(x: 10.2, y: 20.2)
      )
    )
  }

  func testScrollOriginChangeDetectsRealMovement() {
    XCTAssertTrue(
      TimelineBoardReadPath.didScrollOriginChange(
        from: CGPoint(x: 10, y: 20),
        to: CGPoint(x: 11, y: 20)
      )
    )
    XCTAssertTrue(
      TimelineBoardReadPath.didScrollOriginChange(
        from: CGPoint(x: 10, y: 20),
        to: CGPoint(x: 10, y: 21)
      )
    )
  }

  func testTimelineVisibleDayRangeIsOneWeekBeforeThroughTwoMonthsAfterToday() {
    XCTAssertEqual(TimelineBoardReadPath.visibleDayRange, -7...61)
    XCTAssertEqual(Array(TimelineBoardReadPath.visibleDayRange).count, 69)
  }

  func testTimelineVisibleDayRangeExpandsOneWeekBeforeOldestPastIncompleteTask() {
    let calendar = Calendar(identifier: .gregorian)
    let anchorDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
    let oldIncompleteDay = calendar.date(byAdding: .day, value: -12, to: anchorDate)!
    let futureIncompleteDay = calendar.date(byAdding: .day, value: 4, to: anchorDate)!
    let bar = makeBar(
      projectID: UUID(),
      title: "Project",
      dailyTaskCounts: [
        oldIncompleteDay: 1,
        futureIncompleteDay: 1,
      ]
    )

    XCTAssertEqual(
      TimelineBoardReadPath.resolvedVisibleDayRange(
        for: [bar],
        anchorDate: anchorDate,
        calendar: calendar
      ),
      -19...61
    )
  }

  func testTimelineVisibleDayRangeIgnoresFutureIncompleteTasksWhenExpandingPast() {
    let calendar = Calendar(identifier: .gregorian)
    let anchorDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
    let futureIncompleteDay = calendar.date(byAdding: .day, value: 4, to: anchorDate)!
    let bar = makeBar(
      projectID: UUID(),
      title: "Project",
      dailyTaskCounts: [futureIncompleteDay: 1]
    )

    XCTAssertEqual(
      TimelineBoardReadPath.resolvedVisibleDayRange(
        for: [bar],
        anchorDate: anchorDate,
        calendar: calendar
      ),
      TimelineBoardReadPath.visibleDayRange
    )
  }

  func testLoadingStateStopsWhenRetainedReadIsBlocked() {
    let projectID = UUID()

    XCTAssertFalse(
      TimelineBoardReadPath.shouldShowLoadingState(
        projectIDs: [projectID],
        workspaceProjectSnapshots: [:],
        scheduleEntriesByProjectID: [:],
        readBlocker: .partialProjectCoverage(missingProjectIDs: [projectID])
      )
    )
  }

  func testLoadingStateRequiresIncompleteCoverageWithoutBlocker() {
    let projectID = UUID()

    XCTAssertTrue(
      TimelineBoardReadPath.shouldShowLoadingState(
        projectIDs: [projectID],
        workspaceProjectSnapshots: [:],
        scheduleEntriesByProjectID: [:],
        readBlocker: nil
      )
    )
  }

  func testLoadingStateStopsWhenCoverageIsComplete() {
    let projectID = UUID()

    XCTAssertFalse(
      TimelineBoardReadPath.shouldShowLoadingState(
        projectIDs: [projectID],
        workspaceProjectSnapshots: [projectID: makeProject(projectID: projectID)],
        scheduleEntriesByProjectID: [projectID: []],
        readBlocker: nil
      )
    )
  }

  func testTimelineSortsByRecentModificationNewestFirst() {
    let olderID = UUID()
    let newerID = UUID()
    let olderDate = Date(timeIntervalSince1970: 100)
    let newerDate = Date(timeIntervalSince1970: 200)
    let bars = [
      makeBar(projectID: olderID, title: "Older"),
      makeBar(projectID: newerID, title: "Newer"),
    ]

    let ordered = TimelineBoardReadPath.orderedBars(
      bars,
      mode: .recent,
      workspaceProjectSnapshots: [
        olderID: makeProject(projectID: olderID, title: "Older", updatedAt: olderDate),
        newerID: makeProject(projectID: newerID, title: "Newer", updatedAt: newerDate),
      ],
      workspaceProjectSummaries: [
        olderID: makeSummary(latestTaskUpdatedAt: .distantPast),
        newerID: makeSummary(latestTaskUpdatedAt: .distantPast),
      ],
      manualOrderByProjectID: [:]
    )

    XCTAssertEqual(ordered.map(\.projectID), [newerID, olderID])
  }

  func testTimelineSortsByKoreanTitleAscending() {
    let firstID = UUID()
    let secondID = UUID()
    let bars = [
      makeBar(projectID: secondID, title: "나다"),
      makeBar(projectID: firstID, title: "가다"),
    ]

    let ordered = TimelineBoardReadPath.orderedBars(
      bars,
      mode: .title,
      workspaceProjectSnapshots: [:],
      workspaceProjectSummaries: [:],
      manualOrderByProjectID: [:]
    )

    XCTAssertEqual(ordered.map(\.projectID), [firstID, secondID])
  }

  func testTimelineGroupsByStageAndKeepsManualOrderWithinEachStage() {
    let doFirstID = UUID()
    let doSecondID = UUID()
    let decideID = UUID()
    let areaID = UUID()
    let laterID = UUID()
    let bars = [
      makeBar(projectID: laterID, title: "Later"),
      makeBar(projectID: doSecondID, title: "Do second"),
      makeBar(projectID: areaID, title: "Area"),
      makeBar(projectID: doFirstID, title: "Do first"),
      makeBar(projectID: decideID, title: "Decide"),
    ]

    let ordered = TimelineBoardReadPath.orderedBars(
      bars,
      mode: .priority,
      workspaceProjectSnapshots: [
        doFirstID: makeProject(projectID: doFirstID, stage: .do),
        doSecondID: makeProject(projectID: doSecondID, stage: .do),
        decideID: makeProject(projectID: decideID, stage: .decide),
        areaID: makeProject(projectID: areaID, stage: .area),
        laterID: makeProject(projectID: laterID, stage: .later),
      ],
      workspaceProjectSummaries: [:],
      manualOrderByProjectID: [
        doFirstID: 10,
        doSecondID: 20,
      ]
    )

    XCTAssertEqual(ordered.map(\.projectID), [doFirstID, doSecondID, decideID, areaID, laterID])
  }

  func testTimelineSortModeDefaultsToManualAndCyclesThroughModes() {
    XCTAssertEqual(ProjectListSortMode.resolvedTimeline(storedRawValue: nil), .manual)
    XCTAssertEqual(ProjectListSortMode.resolvedTimeline(storedRawValue: "manual"), .manual)
    XCTAssertEqual(ProjectListSortMode.manual.nextTimeline, .recent)
    XCTAssertEqual(ProjectListSortMode.recent.nextTimeline, .title)
    XCTAssertEqual(ProjectListSortMode.title.nextTimeline, .priority)
    XCTAssertEqual(ProjectListSortMode.priority.nextTimeline, .manual)
  }

  func testVisibleProjectIDsFiltersTimelineHiddenProjectsAfterDeduping() {
    let visibleID = UUID()
    let hiddenID = UUID()

    XCTAssertEqual(
      TimelineBoardReadPath.visibleProjectIDs(
        [visibleID, hiddenID, visibleID],
        hiddenProjectIDs: [hiddenID]
      ),
      [visibleID]
    )
  }

  func testTimelineHiddenProjectStorePersistsProjectIDs() throws {
    let suiteName = "TimelineHiddenProjectStoreTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let firstID = UUID()
    let secondID = UUID()

    TimelineHiddenProjectStore.save([firstID, secondID], defaults: defaults)

    XCTAssertEqual(TimelineHiddenProjectStore.load(defaults: defaults), [firstID, secondID])

    TimelineHiddenProjectStore.save([], defaults: defaults)

    XCTAssertEqual(TimelineHiddenProjectStore.load(defaults: defaults), [])
  }

  func testTimelineManualOrderSeedsMissingProjectsFromReminderOrder() {
    let firstID = UUID()
    let secondID = UUID()
    let thirdID = UUID()
    let unavailableID = UUID()

    let order = TimelineProjectManualOrderStore.mergedOrder(
      existing: [:],
      reminderOrderedProjectIDs: [secondID, unavailableID, firstID, thirdID],
      availableProjectIDs: [firstID, secondID, thirdID]
    )

    XCTAssertEqual(order[secondID], 0)
    XCTAssertEqual(order[firstID], 1)
    XCTAssertEqual(order[thirdID], 2)
    XCTAssertNil(order[unavailableID])
  }

  func testTimelineManualOrderPreservesExistingDragOrderAndAppendsMissingReminderProjects() {
    let firstID = UUID()
    let secondID = UUID()
    let thirdID = UUID()

    let order = TimelineProjectManualOrderStore.mergedOrder(
      existing: [thirdID: 0, firstID: 1],
      reminderOrderedProjectIDs: [firstID, secondID, thirdID],
      availableProjectIDs: [firstID, secondID, thirdID]
    )

    XCTAssertEqual(order[thirdID], 0)
    XCTAssertEqual(order[firstID], 1)
    XCTAssertEqual(order[secondID], 2)
  }

  func testTimelineManualOrderMergesFromLatestStoredOrderSnapshot() throws {
    let suiteName = "TimelineProjectManualOrderStoreLatestTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let firstID = UUID()
    let secondID = UUID()
    let thirdID = UUID()

    TimelineProjectManualOrderStore.save([thirdID: 0, firstID: 1], defaults: defaults)

    let order = TimelineProjectManualOrderStore.mergedStoredOrder(
      reminderOrderedProjectIDs: [firstID, secondID, thirdID],
      availableProjectIDs: [firstID, secondID, thirdID],
      defaults: defaults
    )

    XCTAssertEqual(order[thirdID], 0)
    XCTAssertEqual(order[firstID], 1)
    XCTAssertEqual(order[secondID], 2)
  }

  func testTimelineProjectTaskManualOrderPersistsPerProject() throws {
    let suiteName = "TimelineProjectTaskManualOrderStoreTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let projectID = UUID()
    let firstTaskID = UUID()
    let secondTaskID = UUID()

    TimelineProjectTaskManualOrderStore.saveProjectOrder(
      [secondTaskID, firstTaskID],
      for: projectID,
      defaults: defaults
    )

    XCTAssertEqual(
      TimelineProjectTaskManualOrderStore.projectOrder(for: projectID, defaults: defaults),
      [secondTaskID: 0, firstTaskID: 1]
    )
  }

  func testTimelineProjectTaskManualOrderSavesFirstManualReorder() {
    let firstTaskID = UUID()
    let secondTaskID = UUID()

    XCTAssertTrue(
      TimelineProjectTaskManualOrderStore.shouldSaveProjectOrder(
        [secondTaskID, firstTaskID],
        currentStoredOrder: [:]
      )
    )
  }

  func testTimelineProjectTaskManualOrderAppliesStoredOrderAndAppendsNewTasks() {
    let firstTaskID = UUID()
    let secondTaskID = UUID()
    let thirdTaskID = UUID()

    XCTAssertEqual(
      TimelineProjectTaskManualOrderStore.orderedTaskIDs(
        [firstTaskID, secondTaskID, thirdTaskID],
        using: [secondTaskID: 0, firstTaskID: 1]
      ),
      [secondTaskID, firstTaskID, thirdTaskID]
    )
  }

  func testTaskDropReordersWithinProjectListWindow() {
    let firstTaskID = UUID()
    let secondTaskID = UUID()
    let thirdTaskID = UUID()

    XCTAssertEqual(
      TimelineBoardReadPath.reorderedTaskIDsAfterDrop(
        [firstTaskID, secondTaskID, thirdTaskID],
        draggedID: firstTaskID,
        targetID: thirdTaskID,
        placement: .after
      ),
      [secondTaskID, thirdTaskID, firstTaskID]
    )
  }

  func testProjectListTaskOrderPolicySavesNextOpenTaskOrderAfterDrop() {
    let firstTaskID = UUID()
    let completedTaskID = UUID()
    let thirdTaskID = UUID()
    let tasks = [
      projectListTask(id: firstTaskID, isCompleted: false),
      projectListTask(id: completedTaskID, isCompleted: true),
      projectListTask(id: thirdTaskID, isCompleted: false),
    ]
    let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

    let reorderedTasks = TimelineProjectListTaskOrderPolicy.reorderedTasks(
      [thirdTaskID, completedTaskID, firstTaskID],
      tasksByID: tasksByID
    )

    XCTAssertEqual(reorderedTasks.map(\.id), [thirdTaskID, completedTaskID, firstTaskID])
    XCTAssertEqual(
      TimelineProjectListTaskOrderPolicy.openTaskIDs(from: reorderedTasks),
      [thirdTaskID, firstTaskID]
    )
  }

  func testTimelineProjectTaskManualOrderInsertsCreatedTaskAfterAnchor() {
    let firstTaskID = UUID()
    let secondTaskID = UUID()
    let createdTaskID = UUID()

    XCTAssertEqual(
      TimelineProjectTaskManualOrderStore.insertedTaskIDs(
        [firstTaskID, secondTaskID],
        insertedID: createdTaskID,
        after: firstTaskID
      ),
      [firstTaskID, createdTaskID, secondTaskID]
    )
  }

  func testTimelineProjectTaskManualOrderAppendsCreatedTaskWithoutAnchor() {
    let firstTaskID = UUID()
    let createdTaskID = UUID()

    XCTAssertEqual(
      TimelineProjectTaskManualOrderStore.insertedTaskIDs(
        [firstTaskID],
        insertedID: createdTaskID,
        after: UUID()
      ),
      [firstTaskID, createdTaskID]
    )
  }

  func testTimelineProjectListDraftPolicyCancelsOnlyEmptyDrafts() {
    XCTAssertTrue(TimelineProjectListDraftPolicy.shouldCancelDraft(title: "   \n"))
    XCTAssertFalse(TimelineProjectListDraftPolicy.shouldCancelDraft(title: "새 할일"))
  }

  func testTimelineTaskCompletionTogglePolicyFlipsCompletionState() {
    let now = Date(timeIntervalSince1970: 1_776_880_000)

    XCTAssertTrue(TimelineTaskCompletionTogglePolicy.nextIsCompleted(currentIsCompleted: false))
    XCTAssertFalse(TimelineTaskCompletionTogglePolicy.nextIsCompleted(currentIsCompleted: true))
    XCTAssertEqual(
      TimelineTaskCompletionTogglePolicy.completionDate(nextIsCompleted: true, now: now),
      now
    )
    XCTAssertNil(TimelineTaskCompletionTogglePolicy.completionDate(nextIsCompleted: false, now: now))
  }

  func testTimelineProjectTaskManualOrderRemovesCompletedTask() {
    let firstTaskID = UUID()
    let completedTaskID = UUID()
    let thirdTaskID = UUID()

    XCTAssertEqual(
      TimelineProjectTaskManualOrderStore.removedTaskIDs(
        [firstTaskID, completedTaskID, thirdTaskID],
        removedID: completedTaskID
      ),
      [firstTaskID, thirdTaskID]
    )
  }

  func testProjectDropReordersWithinExistingGroup() {
    let firstID = UUID()
    let secondID = UUID()
    let thirdID = UUID()

    XCTAssertEqual(
      TimelineBoardReadPath.reorderedProjectIDsAfterDrop(
        [firstID, secondID, thirdID],
        draggedID: thirdID,
        targetID: firstID,
        placement: .after
      ),
      [firstID, thirdID, secondID]
    )
  }

  func testProjectDropInsertsDraggedProjectIntoTargetGroupWhenStageChanges() {
    let draggedID = UUID()
    let firstTargetID = UUID()
    let secondTargetID = UUID()

    XCTAssertEqual(
      TimelineBoardReadPath.reorderedProjectIDsAfterDrop(
        [firstTargetID, secondTargetID],
        draggedID: draggedID,
        targetID: firstTargetID,
        placement: .before
      ),
      [draggedID, firstTargetID, secondTargetID]
    )
  }

  func testPinnedTopSignatureChangesWhenScrollSuppressionEnds() {
    let anchorDate = Date(timeIntervalSince1970: 1_000)

    XCTAssertNotEqual(
      TimelineBoardReadPath.pinnedTopSignature(
        anchorDate: anchorDate,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44,
        localeIdentifier: "ko_KR",
        isTimelineScrolling: true
      ),
      TimelineBoardReadPath.pinnedTopSignature(
        anchorDate: anchorDate,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44,
        localeIdentifier: "ko_KR",
        isTimelineScrolling: false
      )
    )
  }

  func testDayHeaderHoverOffsetMapsLocalXIntoVisibleDayRange() {
    XCTAssertEqual(
      TimelineBoardReadPath.dayHeaderHoverOffset(
        locationX: 0,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44
      ),
      -7
    )
    XCTAssertEqual(
      TimelineBoardReadPath.dayHeaderHoverOffset(
        locationX: 44 * 7 + 1,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44
      ),
      0
    )
    XCTAssertNil(
      TimelineBoardReadPath.dayHeaderHoverOffset(
        locationX: 44 * 69,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44
      )
    )
  }

  func testDayHeaderHoverOffsetMapsPinnedHeaderCoordinatesAfterHorizontalScroll() {
    XCTAssertEqual(
      TimelineBoardReadPath.dayHeaderHoverOffset(
        contentLocation: CGPoint(x: 88 + 320, y: 120 + 10),
        visibleBoundsOrigin: CGPoint(x: 88, y: 120),
        titleColumnWidth: 320,
        headerHeight: 64,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44
      ),
      -5
    )
    XCTAssertNil(
      TimelineBoardReadPath.dayHeaderHoverOffset(
        contentLocation: CGPoint(x: 88 + 319, y: 120 + 10),
        visibleBoundsOrigin: CGPoint(x: 88, y: 120),
        titleColumnWidth: 320,
        headerHeight: 64,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44
      )
    )
    XCTAssertNil(
      TimelineBoardReadPath.dayHeaderHoverOffset(
        contentLocation: CGPoint(x: 88 + 320, y: 120 + 64),
        visibleBoundsOrigin: CGPoint(x: 88, y: 120),
        titleColumnWidth: 320,
        headerHeight: 64,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44
      )
    )
  }

  func testTaskBadgeHoverIgnoresBadgesObscuredByPinnedLeftColumn() {
    let target = TimelineTaskBadgeHitTarget(
      badgeID: "badge",
      rect: CGRect(x: 88 + 300, y: 120 + 80, width: 40, height: 24)
    )

    XCTAssertNil(
      TimelineBoardReadPath.taskBadgeHoverID(
        contentLocation: CGPoint(x: 88 + 319, y: 120 + 88),
        visibleBoundsOrigin: CGPoint(x: 88, y: 120),
        titleColumnWidth: 320,
        headerHeight: 64,
        targets: [target]
      )
    )
  }

  func testTaskBadgeHoverAllowsVisibleBadgesAfterPinnedLeftColumn() {
    let target = TimelineTaskBadgeHitTarget(
      badgeID: "badge",
      rect: CGRect(x: 88 + 320, y: 120 + 80, width: 40, height: 24)
    )

    XCTAssertEqual(
      TimelineBoardReadPath.taskBadgeHoverID(
        contentLocation: CGPoint(x: 88 + 321, y: 120 + 88),
        visibleBoundsOrigin: CGPoint(x: 88, y: 120),
        titleColumnWidth: 320,
        headerHeight: 64,
        targets: [target]
      ),
      "badge"
    )
  }

  func testProjectColorHexUsesTimelineBarColorForOverlayReference() {
    let projectID = UUID()

    XCTAssertEqual(
      TimelineBoardReadPath.projectColorHex(
        forProjectReference: .project(projectID),
        in: [makeBar(projectID: projectID, title: "Project", colorHex: "#FF3344")]
      ),
      "#FF3344"
    )
  }

  func testDayHeaderSectionsBuildFromCurrentBars() {
    let projectID = UUID()
    let overdueTaskID = UUID()
    let completedTaskID = UUID()
    let today = Date(timeIntervalSince1970: 1_775_340_000)
    let overdueDay = today.addingTimeInterval(-86_400)
    let bar = makeBar(
      projectID: projectID,
      title: "Project",
      colorHex: "#34C759",
      dailyTaskPreviews: [
        overdueDay: TimelineDayPreview(
          totalCount: 1,
          tasks: [
            TimelineProjectTaskPreview(
              id: "overdue",
              taskID: overdueTaskID,
              title: "  Overdue task  ",
              isCompleted: false,
              isOverdue: true,
              targetCompletedWorkUnits: 0
            ),
          ]
        ),
      ],
      dailyCompletedTaskPreviews: [
        today: TimelineDayPreview(
          totalCount: 1,
          tasks: [
            TimelineProjectTaskPreview(
              id: "completed",
              taskID: completedTaskID,
              title: "Completed task",
              isCompleted: true,
              isOverdue: false,
              targetCompletedWorkUnits: 0
            ),
          ]
        ),
      ]
    )

    let sectionsByDay = TimelineBoardReadPath.dayHeaderSectionsByDay(
      from: [bar],
      today: today
    )

    let overdueSection = sectionsByDay[overdueDay]?.first
    XCTAssertEqual(overdueSection?.projectColorHex, "#34C759")
    XCTAssertEqual(overdueSection?.tasks.first?.title, "Overdue task")
    XCTAssertEqual(overdueSection?.tasks.first?.isOverdue, true)

    let todayTasks = sectionsByDay[today]?.first?.tasks ?? []
    XCTAssertTrue(todayTasks.contains { $0.taskID == overdueTaskID && $0.isOverdue })
    XCTAssertTrue(todayTasks.contains { $0.taskID == completedTaskID && $0.isCompleted })
  }

  func testDayHeaderSectionsKeepStableTaskOrderForOverdueTasks() {
    let projectID = UUID()
    let olderTaskID = UUID()
    let newerTaskID = UUID()
    let today = Date(timeIntervalSince1970: 1_775_340_000)
    let olderDay = today.addingTimeInterval(-172_800)
    let newerDay = today.addingTimeInterval(-86_400)
    let olderPreview = TimelineDayPreview(
      totalCount: 1,
      tasks: [
        TimelineProjectTaskPreview(
          id: "older",
          taskID: olderTaskID,
          title: "Older overdue",
          isCompleted: false,
          isOverdue: true,
          targetCompletedWorkUnits: 0
        ),
      ]
    )
    let newerPreview = TimelineDayPreview(
      totalCount: 1,
      tasks: [
        TimelineProjectTaskPreview(
          id: "newer",
          taskID: newerTaskID,
          title: "Newer overdue",
          isCompleted: false,
          isOverdue: true,
          targetCompletedWorkUnits: 0
        ),
      ]
    )

    let firstSections = TimelineBoardReadPath.dayHeaderSectionsByDay(
      from: [
        makeBar(
          projectID: projectID,
          title: "Project",
          dailyTaskPreviews: [
            newerDay: newerPreview,
            olderDay: olderPreview,
          ]
        ),
      ],
      today: today
    )
    let secondSections = TimelineBoardReadPath.dayHeaderSectionsByDay(
      from: [
        makeBar(
          projectID: projectID,
          title: "Project",
          dailyTaskPreviews: [
            olderDay: olderPreview,
            newerDay: newerPreview,
          ]
        ),
      ],
      today: today
    )

    let firstTaskIDs = firstSections[today]?.first?.tasks.map(\.taskID)
    let secondTaskIDs = secondSections[today]?.first?.tasks.map(\.taskID)
    XCTAssertEqual(firstTaskIDs, [olderTaskID, newerTaskID])
    XCTAssertEqual(secondTaskIDs, firstTaskIDs)
  }

  func testProjectListPopoverEntriesExcludeArchivedAndCompletedTasks() {
    let openFirstID = UUID()
    let openSecondID = UUID()
    let completedID = UUID()
    let archivedID = UUID()

    let ordered = TimelineBoardReadPath.projectListPopoverEntries(
      from: [
        makeScheduleEntry(taskID: completedID, title: "Completed", isCompleted: true, rowOrder: 0),
        makeScheduleEntry(taskID: openSecondID, title: "Second", rowOrder: 20),
        makeScheduleEntry(taskID: archivedID, title: "Archived", isArchived: true, rowOrder: -1),
        makeScheduleEntry(taskID: openFirstID, title: "First", rowOrder: 10),
      ]
    )

    XCTAssertEqual(ordered.map(\.taskID), [openFirstID, openSecondID])
  }

  func testProjectListWindowEntriesIncludeCompletedTasksAfterOpenTasks() {
    let openFirstID = UUID()
    let openSecondID = UUID()
    let completedID = UUID()
    let archivedID = UUID()

    let ordered = TimelineBoardReadPath.projectListWindowEntries(
      from: [
        makeScheduleEntry(taskID: completedID, title: "Completed", isCompleted: true, rowOrder: 0),
        makeScheduleEntry(taskID: openSecondID, title: "Second", rowOrder: 20),
        makeScheduleEntry(taskID: archivedID, title: "Archived", isArchived: true, rowOrder: -1),
        makeScheduleEntry(taskID: openFirstID, title: "First", rowOrder: 10),
      ]
    )

    XCTAssertEqual(ordered.map(\.taskID), [openFirstID, openSecondID, completedID])
  }

  func testProjectListDefaultEditableEntryUsesWindowOrder() {
    let projectID = UUID()
    let openFirstID = UUID()
    let openSecondID = UUID()
    let completedID = UUID()

    let entry = TimelineProjectListWindowSnapshotFactory.defaultEditableEntry(
      projectID: projectID,
      entries: [
        makeScheduleEntry(taskID: completedID, title: "Completed", isCompleted: true, rowOrder: 0),
        makeScheduleEntry(taskID: openSecondID, title: "Second", rowOrder: 20),
        makeScheduleEntry(taskID: openFirstID, title: "First", rowOrder: 10),
      ]
    )

    XCTAssertEqual(entry?.taskID, openFirstID)
  }

  func testScheduleSourceSignatureIgnoresNoteBodyWhenVisibleMetadataIsUnchanged() {
    let projectID = UUID()
    let taskID = UUID()
    let today = Date(timeIntervalSinceReferenceDate: 100)
    let project = makeProject(projectID: projectID)
    let firstEntry = makeScheduleEntry(
      taskID: taskID,
      title: "Task",
      rowOrder: 0,
      hasReminderNoteContent: true,
      reminderNoteText: String(repeating: "first note ", count: 200)
    )
    let secondEntry = makeScheduleEntry(
      taskID: taskID,
      title: "Task",
      rowOrder: 0,
      hasReminderNoteContent: true,
      reminderNoteText: String(repeating: "second note ", count: 200)
    )

    let firstSignature = ScheduleBoardReadPath.sourceSignature(
      today: today,
      projectIDs: [projectID],
      projectSnapshots: [projectID: project],
      scheduleEntriesByProjectID: [projectID: [firstEntry]]
    )
    let secondSignature = ScheduleBoardReadPath.sourceSignature(
      today: today,
      projectIDs: [projectID],
      projectSnapshots: [projectID: project],
      scheduleEntriesByProjectID: [projectID: [secondEntry]]
    )

    XCTAssertEqual(firstSignature, secondSignature)
  }

  func testScheduleSourceSignatureTracksNoteIconVisibility() {
    let projectID = UUID()
    let taskID = UUID()
    let today = Date(timeIntervalSinceReferenceDate: 100)
    let project = makeProject(projectID: projectID)
    let emptyNoteEntry = makeScheduleEntry(
      taskID: taskID,
      title: "Task",
      rowOrder: 0,
      hasReminderNoteContent: false,
      reminderNoteText: ""
    )
    let visibleNoteEntry = makeScheduleEntry(
      taskID: taskID,
      title: "Task",
      rowOrder: 0,
      hasReminderNoteContent: true,
      reminderNoteText: "visible note"
    )

    let emptySignature = ScheduleBoardReadPath.sourceSignature(
      today: today,
      projectIDs: [projectID],
      projectSnapshots: [projectID: project],
      scheduleEntriesByProjectID: [projectID: [emptyNoteEntry]]
    )
    let visibleSignature = ScheduleBoardReadPath.sourceSignature(
      today: today,
      projectIDs: [projectID],
      projectSnapshots: [projectID: project],
      scheduleEntriesByProjectID: [projectID: [visibleNoteEntry]]
    )

    XCTAssertNotEqual(emptySignature, visibleSignature)
  }

  private func makeProject(
    projectID: UUID,
    title: String = "Project",
    updatedAt: Date = .distantPast,
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
      updatedAt: updatedAt,
      isArchived: false
    )
  }

  private func makeBar(
    projectID: UUID,
    title: String,
    colorHex: String? = nil,
    dailyTaskCounts: [Date: Int] = [:],
    dailyTaskPreviews: [Date: TimelineDayPreview] = [:],
    dailyCompletedTaskPreviews: [Date: TimelineDayPreview] = [:]
  ) -> TimelineProjectBar {
    TimelineProjectBar(
      projectID: projectID,
      title: title,
      colorHex: colorHex,
      start: nil,
      end: nil,
      deadline: nil,
      nextUpcomingDate: nil,
      progress: ProjectProgressStage.do.progressValue,
      remainingTaskCount: 0,
      undatedRemainingTaskCount: 0,
      dailyTaskCounts: dailyTaskCounts,
      dailyCompletedTaskCounts: [:],
      dailyPlannedWorkCounts: [:],
      dailyTaskPreviews: dailyTaskPreviews,
      dailyCompletedTaskPreviews: dailyCompletedTaskPreviews,
      dailyPlannedWorkPreviews: [:],
      projectReference: .project(projectID)
    )
  }

  private func makeScheduleEntry(
    taskID: UUID,
    title: String,
    isCompleted: Bool = false,
    isArchived: Bool = false,
    rowOrder: Int,
    attachmentCount: Int = 0,
    hasReminderNoteContent: Bool = false,
    reminderNoteText: String = ""
  ) -> ScheduleSliceEntry {
    ScheduleSliceEntry(
      taskID: taskID,
      parentTaskID: nil,
      title: title,
      displayedDate: nil,
      startDate: nil,
      dueDate: nil,
      scheduleHasExplicitTime: false,
      scheduledDurationMinutes: nil,
      isCompleted: isCompleted,
      completionDate: isCompleted ? .distantPast : nil,
      recurrenceRuleRaw: nil,
      isLocalCompletedRecurringOccurrence: false,
      attachmentCount: attachmentCount,
      hasReminderNoteContent: hasReminderNoteContent,
      reminderNoteText: reminderNoteText,
      requiredWorkDays: 0,
      completedWorkUnits: 0,
      completedWorkUnitDates: [],
      preparationScheduleOverridesRaw: "",
      rowOrder: rowOrder,
      priority: 0,
      isFlagged: false,
      isArchived: isArchived,
      localUpdatedAt: .distantPast,
      createdAt: .distantPast
    )
  }

  private func projectListTask(
    id: UUID,
    isCompleted: Bool
  ) -> TimelineProjectListWindowSnapshot.Task {
    TimelineProjectListWindowSnapshot.Task(
      id: id,
      title: "Task",
      dateText: nil,
      isCompleted: isCompleted,
      isOverdue: false
    )
  }

  private func makeSummary(latestTaskUpdatedAt: Date?) -> ProjectSummaryRecord {
    ProjectSummaryRecord(
      openRootTaskCount: 0,
      completedRootTaskCount: 0,
      undatedOpenRootTaskCount: 0,
      overdueOpenRootTaskCount: 0,
      todayTaskCount: 0,
      nextUpcomingDate: nil,
      deadline: nil,
      stageRaw: ProjectProgressStage.do.storageRawValue,
      progress: ProjectProgressStage.do.progressValue,
      latestTaskUpdatedAt: latestTaskUpdatedAt,
      title: "Project",
      colorHex: nil,
      isArchived: false
    )
  }

}
