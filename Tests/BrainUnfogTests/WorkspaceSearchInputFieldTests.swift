import AppKit
import SwiftUI
import XCTest
@testable import BrainUnfog

@MainActor
final class WorkspaceSearchInputFieldTests: XCTestCase {
  func testFieldAcceptsFirstResponderBeforeMouseDown() {
    let field = WorkspaceSearchInputField.FocusAwareTextField()

    XCTAssertTrue(field.acceptsFirstResponder)
  }

  func testAutomaticEditingDoesNotMarkWorkspaceSearchFocused() {
    let state = WorkspaceSearchInputState()
    let input = makeInput(state: state)
    let coordinator = WorkspaceSearchInputField.Coordinator(parent: input)

    coordinator.controlTextDidBeginEditing(
      Notification(
        name: NSControl.textDidBeginEditingNotification,
        object: NSTextField()
      )
    )

    XCTAssertFalse(state.isFocused)
  }

  func testUserFocusAttemptMarksWorkspaceSearchFocused() {
    let state = WorkspaceSearchInputState()
    let input = makeInput(state: state)
    let coordinator = WorkspaceSearchInputField.Coordinator(parent: input)

    coordinator.registerUserFocusAttempt()

    XCTAssertTrue(state.isFocused)
  }

  func testEditingEndDoesNotDismissWorkspaceSearch() {
    let state = WorkspaceSearchInputState()
    state.isFocused = true
    let input = makeInput(state: state)
    let coordinator = WorkspaceSearchInputField.Coordinator(parent: input)

    coordinator.controlTextDidEndEditing(
      Notification(
        name: NSControl.textDidEndEditingNotification,
        object: NSTextField()
      )
    )

    XCTAssertTrue(state.isFocused)
    XCTAssertFalse(coordinator.hasPendingUserFocusAttempt)
  }

  private func makeInput(state: WorkspaceSearchInputState) -> WorkspaceSearchInputField {
    WorkspaceSearchInputField(
      text: Binding(
        get: { state.text },
        set: { state.text = $0 }
      ),
      isFocused: Binding(
        get: { state.isFocused },
        set: { state.isFocused = $0 }
      ),
      focusRequestID: 0,
      placeholder: "전체 검색",
      onMoveUp: {},
      onMoveDown: {},
      onSubmit: {},
      onEscape: {}
    )
  }
}

private final class WorkspaceSearchInputState {
  var text = ""
  var isFocused = false
}
