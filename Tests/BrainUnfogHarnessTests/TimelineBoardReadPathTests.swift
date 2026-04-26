import XCTest
@testable import BrainUnfogHarness

final class TimelineBoardReadPathTests: XCTestCase {
  func testTimelineVisibleDayRangeIsFourDaysBeforeThroughFourWeeksAfterToday() {
    XCTAssertEqual(TimelineBoardReadPath.visibleDayRange, -4...28)
    XCTAssertEqual(Array(TimelineBoardReadPath.visibleDayRange).count, 33)
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

  func testTimelineSortModeSkipsLegacyManualMode() {
    XCTAssertEqual(ProjectListSortMode.resolvedTimeline(storedRawValue: nil), .recent)
    XCTAssertEqual(ProjectListSortMode.resolvedTimeline(storedRawValue: "manual"), .recent)
    XCTAssertEqual(ProjectListSortMode.recent.nextTimeline, .title)
    XCTAssertEqual(ProjectListSortMode.title.nextTimeline, .priority)
    XCTAssertEqual(ProjectListSortMode.priority.nextTimeline, .recent)
  }

  func testPinnedTopSignatureChangesWhenScrollSuppressionEnds() {
    let anchorDate = Date(timeIntervalSince1970: 1_000)

    XCTAssertNotEqual(
      TimelineBoardReadPath.pinnedTopSignature(
        anchorDate: anchorDate,
        dayRange: -4...28,
        dayColumnWidth: 44,
        localeIdentifier: "ko_KR",
        isTimelineScrolling: true
      ),
      TimelineBoardReadPath.pinnedTopSignature(
        anchorDate: anchorDate,
        dayRange: -4...28,
        dayColumnWidth: 44,
        localeIdentifier: "ko_KR",
        isTimelineScrolling: false
      )
    )
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

  private func makeBar(projectID: UUID, title: String) -> TimelineProjectBar {
    TimelineProjectBar(
      projectID: projectID,
      title: title,
      colorHex: nil,
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
      dailyTaskPreviews: [:],
      dailyCompletedTaskPreviews: [:],
      dailyPlannedWorkPreviews: [:],
      projectReference: .project(projectID)
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
