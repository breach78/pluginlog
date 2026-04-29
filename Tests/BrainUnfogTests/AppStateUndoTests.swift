import XCTest
@testable import BrainUnfog

@MainActor
final class AppStateUndoTests: XCTestCase {
  func testRegisterUndoEnqueuesHandlerInUndoManager() async {
    let appState = AppState(isPreviewAppState: true)
    let undoManager = UndoManager()
    var didUndo = false

    appState.registerUndo(with: undoManager, actionName: "테스트") {
      didUndo = true
    }

    XCTAssertTrue(undoManager.canUndo)
    undoManager.undo()
    await Task.yield()

    XCTAssertTrue(didUndo)
  }
}
