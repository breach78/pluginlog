import XCTest
@testable import BrainUnfog

final class WorkspaceEscapeKeyPolicyTests: XCTestCase {
  func testActiveEditPanelTextResponderLetsEditorHandleEscapeBeforeWorkspaceActions() {
    XCTAssertEqual(
      WorkspaceEscapeKeyPolicy.action(
        hasActiveEditPanelTextResponder: true,
        hasSearchQuery: true,
        hasInspectorSelection: true,
        hasEditPanel: true
      ),
      .passThrough
    )
  }

  func testSearchClearRunsBeforePanelDismissals() {
    XCTAssertEqual(
      WorkspaceEscapeKeyPolicy.action(
        hasActiveEditPanelTextResponder: false,
        hasSearchQuery: true,
        hasInspectorSelection: true,
        hasEditPanel: true
      ),
      .clearSearch
    )
  }

  func testInspectorDismissRunsBeforeEditPanelDismissal() {
    XCTAssertEqual(
      WorkspaceEscapeKeyPolicy.action(
        hasActiveEditPanelTextResponder: false,
        hasSearchQuery: false,
        hasInspectorSelection: true,
        hasEditPanel: true
      ),
      .dismissInspector
    )
  }

  func testEditPanelDismissalIsLastHandledEscapeAction() {
    XCTAssertEqual(
      WorkspaceEscapeKeyPolicy.action(
        hasActiveEditPanelTextResponder: false,
        hasSearchQuery: false,
        hasInspectorSelection: false,
        hasEditPanel: true
      ),
      .dismissEditPanel
    )
  }

  func testEscapePassesThroughWhenNothingHandlesIt() {
    XCTAssertEqual(
      WorkspaceEscapeKeyPolicy.action(
        hasActiveEditPanelTextResponder: false,
        hasSearchQuery: false,
        hasInspectorSelection: false,
        hasEditPanel: false
      ),
      .passThrough
    )
  }
}
