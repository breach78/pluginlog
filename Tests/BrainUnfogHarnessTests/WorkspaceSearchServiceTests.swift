import XCTest
@testable import BrainUnfogHarness

final class WorkspaceSearchServiceTests: XCTestCase {
  func testTaskResultsMatchRetainedScheduleEntryTitles() {
    let projectID = UUID()
    let taskID = UUID()
    let project = makeProject(projectID: projectID, title: "여행")
    let entry = makeEntry(taskID: taskID, title: "비자 신청 준비")

    let results = WorkspaceSearchService.taskResults(
      projectSnapshots: [projectID: project],
      scheduleEntriesByProjectID: [projectID: [entry]],
      rawQuery: "비자"
    )

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.entityKind, .task)
    XCTAssertEqual(results.first?.matchKind, .taskTitle)
    XCTAssertEqual(results.first?.title, "비자 신청 준비")
    XCTAssertEqual(results.first?.subtitle, "여행")
    XCTAssertEqual(results.first?.navigationTarget, .taskRow(projectID: projectID, taskID: taskID))
  }

  func testTaskResultsSkipArchivedProjectsAndTasks() {
    let archivedProjectID = UUID()
    let activeProjectID = UUID()
    let archivedTaskID = UUID()

    let results = WorkspaceSearchService.taskResults(
      projectSnapshots: [
        archivedProjectID: makeProject(projectID: archivedProjectID, isArchived: true),
        activeProjectID: makeProject(projectID: activeProjectID),
      ],
      scheduleEntriesByProjectID: [
        archivedProjectID: [makeEntry(taskID: UUID(), title: "아카이브 검색")],
        activeProjectID: [makeEntry(taskID: archivedTaskID, title: "아카이브 검색", isArchived: true)],
      ],
      rawQuery: "아카이브"
    )

    XCTAssertTrue(results.isEmpty)
  }

  private func makeProject(
    projectID: UUID,
    title: String = "Project",
    isArchived: Bool = false
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
      progressStageRaw: nil,
      boardOrder: nil,
      createdAt: .distantPast,
      updatedAt: .distantPast,
      isArchived: isArchived
    )
  }

  private func makeEntry(
    taskID: UUID,
    title: String,
    isCompleted: Bool = false,
    isArchived: Bool = false
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
      completionDate: nil,
      recurrenceRuleRaw: nil,
      attachmentCount: 0,
      reminderNoteText: "",
      requiredWorkDays: 0,
      completedWorkUnits: 0,
      completedWorkUnitDates: [],
      preparationScheduleOverridesRaw: "",
      rowOrder: 0,
      priority: 0,
      isFlagged: false,
      isArchived: isArchived,
      localUpdatedAt: .distantPast,
      createdAt: .distantPast
    )
  }
}
