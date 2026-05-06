import AppKit
import XCTest
@testable import BrainUnfog

@MainActor
final class TimelineProjectListWindowPresenterTests: XCTestCase {
  func testProjectListWindowUsesFloatingPanelBehavior() {
    let window = NSPanel()

    TimelineProjectListWindowPresenter.configureWindowLevel(window)

    XCTAssertEqual(window.level, .floating)
    XCTAssertTrue(window.isFloatingPanel)
    XCTAssertTrue(window.hidesOnDeactivate)
  }

  func testInitialFocusPolicyTargetsTextResponders() {
    XCTAssertTrue(TimelineProjectListWindowPresenter.shouldClearInitialFocus(NSTextView()))
    XCTAssertTrue(TimelineProjectListWindowPresenter.shouldClearInitialFocus(NSTextField()))
    XCTAssertFalse(TimelineProjectListWindowPresenter.shouldClearInitialFocus(NSView()))
    XCTAssertFalse(TimelineProjectListWindowPresenter.shouldClearInitialFocus(nil))
  }

  func testPresentCreatesSeparateWindowsForDifferentProjects() {
    let presenter = TimelineProjectListWindowPresenter.shared
    presenter.closeAllWindows()
    defer { presenter.closeAllWindows() }

    let firstProjectID = UUID()
    let secondProjectID = UUID()

    presenter.present(
      snapshot: makeSnapshot(projectID: firstProjectID, title: "First"),
      onToggleTaskCompletion: { _, _ in true },
      onEditTask: { _ in },
      onReorderTasks: { _, _, _ in },
      onCreateTask: { _, _ in nil },
      onRenameTask: { _, _, _ in nil },
      onDeleteTask: { _, _ in true },
      onRenameProject: { _, _ in }
    )
    presenter.present(
      snapshot: makeSnapshot(projectID: secondProjectID, title: "Second"),
      onToggleTaskCompletion: { _, _ in true },
      onEditTask: { _ in },
      onReorderTasks: { _, _, _ in },
      onCreateTask: { _, _ in nil },
      onRenameTask: { _, _, _ in nil },
      onDeleteTask: { _, _ in true },
      onRenameProject: { _, _ in }
    )

    XCTAssertEqual(presenter.presentedProjectIDs.count, 2)
    XCTAssertEqual(Set(presenter.presentedProjectIDs), [firstProjectID, secondProjectID])
  }

  func testRefreshUpdatesEveryOpenWindowForProject() {
    let presenter = TimelineProjectListWindowPresenter.shared
    presenter.closeAllWindows()
    defer { presenter.closeAllWindows() }

    let projectID = UUID()

    presenter.present(
      snapshot: makeSnapshot(projectID: projectID, title: "Before"),
      onToggleTaskCompletion: { _, _ in true },
      onEditTask: { _ in },
      onReorderTasks: { _, _, _ in },
      onCreateTask: { _, _ in nil },
      onRenameTask: { _, _, _ in nil },
      onDeleteTask: { _, _ in true },
      onRenameProject: { _, _ in }
    )
    presenter.present(
      snapshot: makeSnapshot(projectID: projectID, title: "Before"),
      onToggleTaskCompletion: { _, _ in true },
      onEditTask: { _ in },
      onReorderTasks: { _, _, _ in },
      onCreateTask: { _, _ in nil },
      onRenameTask: { _, _, _ in nil },
      onDeleteTask: { _, _ in true },
      onRenameProject: { _, _ in }
    )

    XCTAssertEqual(presenter.refresh(snapshot: makeSnapshot(projectID: projectID, title: "After")), 2)
    XCTAssertEqual(presenter.refresh(snapshot: makeSnapshot(projectID: projectID, title: "After")), 0)
  }

  private func makeSnapshot(
    projectID: UUID,
    title: String
  ) -> TimelineProjectListWindowSnapshot {
    TimelineProjectListWindowSnapshot(
      projectID: projectID,
      title: title,
      colorHex: nil,
      tasks: []
    )
  }
}
