import XCTest
@testable import BrainUnfog

final class WorkspaceProjectReadPathTests: XCTestCase {
  func testQuickAddProjectIDsFilterHiddenProjectsUnlessExplicitlyShown() {
    let firstID = UUID()
    let hiddenID = UUID()
    let secondID = UUID()

    XCTAssertEqual(
      MainWorkspaceView.WorkspaceProjectReadPath.quickAddProjectIDs(
        [firstID, hiddenID, firstID, secondID],
        hiddenProjectIDs: [hiddenID],
        showsHiddenProjects: false
      ),
      [firstID, secondID]
    )

    XCTAssertEqual(
      MainWorkspaceView.WorkspaceProjectReadPath.quickAddProjectIDs(
        [firstID, hiddenID, firstID, secondID],
        hiddenProjectIDs: [hiddenID],
        showsHiddenProjects: true
      ),
      [firstID, hiddenID, secondID]
    )
  }

  func testQuickAddDescriptorsPreserveFilteredProjectOrderAndSkipUnavailableProjects() {
    let firstID = UUID()
    let secondID = UUID()
    let archivedID = UUID()
    let unboundID = UUID()

    let descriptors = [
      makeDescriptor(id: archivedID, title: "Archived", reminderListIdentifier: "archived", isArchived: true),
      makeDescriptor(id: firstID, title: "First", reminderListIdentifier: "first"),
      makeDescriptor(id: unboundID, title: "Unbound", reminderListIdentifier: ""),
      makeDescriptor(id: secondID, title: "Second", reminderListIdentifier: "second"),
    ]

    XCTAssertEqual(
      MainWorkspaceView.WorkspaceProjectReadPath.activeQuickAddDescriptors(
        descriptors: descriptors,
        projectIDs: [secondID, archivedID, unboundID, firstID]
      ).map(\.id),
      [secondID, firstID]
    )
  }

  private func makeDescriptor(
    id: UUID,
    title: String,
    reminderListIdentifier: String,
    isArchived: Bool = false
  ) -> WorkspaceProjectDescriptor {
    WorkspaceProjectDescriptor(
      id: id,
      title: title,
      colorHex: nil,
      reminderListIdentifier: reminderListIdentifier,
      updatedAt: .distantPast,
      createdAt: .distantPast,
      latestTaskUpdatedAt: nil,
      isArchived: isArchived,
      stage: .do,
      workspaceSortKey: nil
    )
  }
}
