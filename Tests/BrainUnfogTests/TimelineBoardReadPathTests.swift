import XCTest
@testable import BrainUnfog

final class TimelineBoardReadPathTests: XCTestCase {
  func testTimelineVisibleDayRangeIsFourDaysBeforeThroughTwoMonthsAfterToday() {
    XCTAssertEqual(TimelineBoardReadPath.visibleDayRange, -4...61)
    XCTAssertEqual(Array(TimelineBoardReadPath.visibleDayRange).count, 66)
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
      -4
    )
    XCTAssertEqual(
      TimelineBoardReadPath.dayHeaderHoverOffset(
        locationX: 44 * 4 + 1,
        dayRange: TimelineBoardReadPath.visibleDayRange,
        dayColumnWidth: 44
      ),
      0
    )
    XCTAssertNil(
      TimelineBoardReadPath.dayHeaderHoverOffset(
        locationX: 44 * 66,
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
      -2
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
      dailyTaskCounts: [:],
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
    rowOrder: Int
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
      attachmentCount: 0,
      reminderNoteText: "",
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
