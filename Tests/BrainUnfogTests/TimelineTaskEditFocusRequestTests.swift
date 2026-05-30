import Foundation
import Testing
@testable import BrainUnfog

struct TimelineTaskEditFocusRequestTests {
  @Test func repeatedTaskEditRequestsRemainDistinctForFocusRefresh() {
    let projectID = UUID()
    let taskID = UUID()
    let fields = RetainedTaskEditFields(
      title: "Task",
      noteText: "Note",
      day: nil,
      timeMinutes: nil,
      durationMinutes: nil
    )

    let first = WorkspaceTaskEditPanelTarget(
      projectID: projectID,
      taskID: taskID,
      initialFields: fields,
      initialFocus: .note,
      focusRequestID: 1
    )
    let second = WorkspaceTaskEditPanelTarget(
      projectID: projectID,
      taskID: taskID,
      initialFields: fields,
      initialFocus: .note,
      focusRequestID: 2
    )

    #expect(first != second)
    #expect(second.initialFocus == .note)
    #expect(second.focusRequestID == 2)
  }
}
