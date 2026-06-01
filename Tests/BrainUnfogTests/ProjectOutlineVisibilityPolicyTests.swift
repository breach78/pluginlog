import Foundation
import Testing
@testable import BrainUnfog

struct ProjectOutlineVisibilityPolicyTests {
  @Test func hidesCompletedTaskSubtree() throws {
    let completedTaskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let visibleTaskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(depth: 0, text: "위"),
      ProjectOutlineBlock(
        depth: 0,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(
          taskID: completedTaskID,
          taskExternalIdentifier: nil
        )
      ),
      ProjectOutlineBlock(depth: 1, text: "완료 항목의 자식"),
      ProjectOutlineBlock(
        depth: 0,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(
          taskID: visibleTaskID,
          taskExternalIdentifier: nil
        )
      ),
    ])

    let visible = ProjectOutlineVisibilityPolicy.visibleIndices(
      in: document,
      focusRootID: nil,
      hiddenTaskIDs: [completedTaskID]
    )

    #expect(visible == [0, 3])
  }

  @Test func respectsCollapsedBlocksBeforeHidingCompletedTasks() throws {
    let completedTaskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(depth: 0, text: "접힌 부모", childrenCollapsed: true),
      ProjectOutlineBlock(
        depth: 1,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(
          taskID: completedTaskID,
          taskExternalIdentifier: nil
        )
      ),
      ProjectOutlineBlock(depth: 0, text: "다음"),
    ])

    let visible = ProjectOutlineVisibilityPolicy.visibleIndices(
      in: document,
      focusRootID: nil,
      hiddenTaskIDs: [completedTaskID]
    )

    #expect(visible == [0, 2])
  }
}
