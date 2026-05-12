import XCTest
@testable import BrainUnfog

final class ScheduleTaskDescriptorLookupPolicyTests: XCTestCase {
  func testFallbackDescriptorIsUsedWhenTransientCacheMissesTask() {
    let taskID = UUID()
    let fallbackDescriptor = makeDescriptor(taskID: taskID, title: "Resize target")

    let resolved = ScheduleTaskDescriptorLookupPolicy.descriptor(
      for: taskID,
      cached: [:],
      fallback: { [taskID: fallbackDescriptor] }
    )

    XCTAssertEqual(resolved?.taskRow.id, taskID)
    XCTAssertEqual(resolved?.taskRow.title, "Resize target")
  }

  func testCachedDescriptorWinsWhenAvailable() {
    let taskID = UUID()
    let cachedDescriptor = makeDescriptor(taskID: taskID, title: "Cached")
    let fallbackDescriptor = makeDescriptor(taskID: taskID, title: "Fallback")

    let resolved = ScheduleTaskDescriptorLookupPolicy.descriptor(
      for: taskID,
      cached: [taskID: cachedDescriptor],
      fallback: { [taskID: fallbackDescriptor] }
    )

    XCTAssertEqual(resolved?.taskRow.title, "Cached")
  }

  private func makeDescriptor(taskID: UUID, title: String) -> WorkspaceScheduleTaskDescriptor {
    WorkspaceScheduleTaskDescriptor(
      projectID: UUID(),
      projectTitle: "Project",
      projectColorHex: "#4A90E2",
      taskRow: TaskRowSnapshot(
        id: taskID,
        title: title,
        reminderDate: Date(timeIntervalSince1970: 0),
        scheduleHasExplicitTime: true,
        scheduledDurationMinutes: 30,
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
        createdAt: .distantPast,
        isArchived: false
      )
    )
  }
}
