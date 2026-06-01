import Foundation
import Testing
@testable import BrainUnfog

struct ProjectOutlineTaskListMigrationPolicyTests {
  @Test func appendsOnlyTasksMissingFromOutlineAtRootDepth() throws {
    let existingTaskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let newTaskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(depth: 0, text: "프로젝트 노트"),
      ProjectOutlineBlock(
        depth: 1,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(
          taskID: existingTaskID,
          taskExternalIdentifier: nil
        )
      ),
    ])

    let didAppend = ProjectOutlineTaskListMigrationPolicy.appendMissingTaskBlocks(
      to: &document,
      taskIDs: [existingTaskID, newTaskID, newTaskID]
    )

    #expect(didAppend)
    #expect(document.blocks.count == 3)
    #expect(document.blocks[2].depth == 0)
    #expect(document.blocks[2].text.isEmpty)
    #expect(document.blocks[2].taskBinding?.taskID == newTaskID)
  }

  @Test func replacesSingleEmptyPlaceholderWithTaskBlocks() throws {
    let firstTaskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let secondTaskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    var document = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(depth: 0, text: ""),
    ])

    let didAppend = ProjectOutlineTaskListMigrationPolicy.appendMissingTaskBlocks(
      to: &document,
      taskIDs: [firstTaskID, secondTaskID]
    )

    #expect(didAppend)
    #expect(document.blocks.map { $0.taskBinding?.taskID } == [firstTaskID, secondTaskID])
  }

  @Test func leavesDocumentUnchangedWhenEveryTaskAlreadyExists() throws {
    let taskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let original = ProjectOutlineDocument(blocks: [
      ProjectOutlineBlock(
        depth: 0,
        text: "",
        taskBinding: ProjectOutlineTaskBinding(taskID: taskID, taskExternalIdentifier: nil)
      ),
    ])
    var document = original

    let didAppend = ProjectOutlineTaskListMigrationPolicy.appendMissingTaskBlocks(
      to: &document,
      taskIDs: [taskID]
    )

    #expect(!didAppend)
    #expect(document == original)
  }
}
