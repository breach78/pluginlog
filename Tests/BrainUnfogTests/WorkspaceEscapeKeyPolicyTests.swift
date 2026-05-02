import XCTest
@testable import BrainUnfog

final class WorkspaceEscapeKeyPolicyTests: XCTestCase {
  func testTextResponderReleaseRunsBeforeOtherEscapeActions() {
    XCTAssertEqual(
      WorkspaceEscapeKeyPolicy.action(
        didReleaseTextResponder: true,
        hasSearchQuery: true,
        hasInspectorSelection: true,
        hasEditPanel: true
      ),
      .releaseTextResponder
    )
  }

  func testSearchClearRunsBeforePanelDismissals() {
    XCTAssertEqual(
      WorkspaceEscapeKeyPolicy.action(
        didReleaseTextResponder: false,
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
        didReleaseTextResponder: false,
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
        didReleaseTextResponder: false,
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
        didReleaseTextResponder: false,
        hasSearchQuery: false,
        hasInspectorSelection: false,
        hasEditPanel: false
      ),
      .passThrough
    )
  }
}
