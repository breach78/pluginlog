import XCTest
@testable import BrainUnfog

final class WorkspaceOverdueTaskRolloverPlannerTests: XCTestCase {
  func testTargetsIncludeOnlyOpenTasksBeforeToday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    let projectID = UUID()
    let overdueTaskID = UUID()

    let targets = WorkspaceOverdueTaskRolloverPlanner.targets(
      projectIDs: [projectID],
      projectSnapshots: [projectID: makeProject(projectID: projectID)],
      scheduleEntriesByProjectID: [
        projectID: [
          makeEntry(taskID: overdueTaskID, displayedDate: yesterday),
          makeEntry(displayedDate: yesterday, isCompleted: true),
          makeEntry(displayedDate: today),
          makeEntry(displayedDate: tomorrow),
          makeEntry(displayedDate: nil),
          makeEntry(displayedDate: yesterday, isArchived: true),
        ]
      ],
      today: today,
      calendar: calendar
    )

    XCTAssertEqual(targets, [
      WorkspaceOverdueTaskRolloverTarget(projectID: projectID, taskID: overdueTaskID)
    ])
  }

  func testTargetsSkipArchivedProjectsAndDuplicateTaskIDs() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let firstProjectID = UUID()
    let archivedProjectID = UUID()
    let taskID = UUID()

    let targets = WorkspaceOverdueTaskRolloverPlanner.targets(
      projectIDs: [firstProjectID, archivedProjectID],
      projectSnapshots: [
        firstProjectID: makeProject(projectID: firstProjectID),
        archivedProjectID: makeProject(projectID: archivedProjectID, isArchived: true),
      ],
      scheduleEntriesByProjectID: [
        firstProjectID: [
          makeEntry(taskID: taskID, displayedDate: yesterday),
          makeEntry(taskID: taskID, displayedDate: yesterday),
        ],
        archivedProjectID: [
          makeEntry(displayedDate: yesterday)
        ],
      ],
      today: today,
      calendar: calendar
    )

    XCTAssertEqual(targets, [
      WorkspaceOverdueTaskRolloverTarget(projectID: firstProjectID, taskID: taskID)
    ])
  }

  private func makeProject(
    projectID: UUID,
    isArchived: Bool = false
  ) -> WorkspaceProjectRuntimeRecord {
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
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0),
      isArchived: isArchived
    )
  }

  private func makeEntry(
    taskID: UUID = UUID(),
    displayedDate: Date?,
    isCompleted: Bool = false,
    isArchived: Bool = false
  ) -> ScheduleSliceEntry {
    ScheduleSliceEntry(
      taskID: taskID,
      parentTaskID: nil,
      title: "Task",
      displayedDate: displayedDate,
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
      localUpdatedAt: Date(timeIntervalSince1970: 0),
      createdAt: Date(timeIntervalSince1970: 0)
    )
  }
}
