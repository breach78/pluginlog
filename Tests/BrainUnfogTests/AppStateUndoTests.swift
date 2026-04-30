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

  func testRegisterUndoAllowsUndoHandlerToRegisterRedo() {
    let appState = AppState(isPreviewAppState: true)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var title = "After"

    undoManager.beginUndoGrouping()
    appState.registerUndo(with: undoManager, actionName: "제목 변경") {
      title = "Before"
      appState.registerUndo(with: undoManager, actionName: "제목 변경") {
        title = "After"
      }
    }
    undoManager.endUndoGrouping()

    undoManager.undo()
    XCTAssertEqual(title, "Before")
    XCTAssertTrue(undoManager.canRedo)

    undoManager.redo()
    XCTAssertEqual(title, "After")
  }

  func testRegisterUndoLimitsAppDomainHistoryToTwentyGroups() async {
    let appState = AppState(isPreviewAppState: true)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var undone: [Int] = []

    for index in 0..<25 {
      undoManager.beginUndoGrouping()
      appState.registerUndo(with: undoManager, actionName: "테스트 \(index)") {
        undone.append(index)
      }
      undoManager.endUndoGrouping()
    }

    while undoManager.canUndo {
      undoManager.undo()
      await Task.yield()
    }

    XCTAssertEqual(undoManager.levelsOfUndo, AppState.domainUndoLimit)
    XCTAssertEqual(undone, Array((5..<25).reversed()))
  }
}
