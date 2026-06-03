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

  @Test func visibleChildrenIgnoreHiddenCompletedTaskSubtrees() throws {
    let parentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let completedTaskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let visibleTaskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(id: parentID, depth: 0, text: "부모"),
      ProjectOutlineBlock(
        depth: 1,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(
          taskID: completedTaskID,
          taskExternalIdentifier: nil
        )
      ),
      ProjectOutlineBlock(depth: 2, text: "완료 항목의 숨겨진 자식"),
      ProjectOutlineBlock(
        depth: 0,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(
          taskID: visibleTaskID,
          taskExternalIdentifier: nil
        )
      ),
    ])

    let hasChildren = ProjectOutlineVisibilityPolicy.hasVisibleChildren(
      blockID: parentID,
      in: document,
      hiddenTaskIDs: [completedTaskID]
    )

    #expect(!hasChildren)
  }

  @Test func displayContextKeepsCollapsedTaskChildMarker() throws {
    let parentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let taskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(
        id: parentID,
        depth: 0,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(
          taskID: taskID,
          taskExternalIdentifier: nil
        ),
        childrenCollapsed: true
      ),
      ProjectOutlineBlock(depth: 1, text: "자식"),
      ProjectOutlineBlock(depth: 0, text: "다음"),
    ])

    let context = ProjectOutlinerDisplayContext(
      document: document,
      focusRootID: nil,
      hiddenTaskIDs: [],
      selection: nil
    )

    #expect(context.blocks.map { $0.id } == [parentID, document.blocks[2].id])
    #expect(context.blocks.first?.hasVisibleChildren == true)
  }
}
