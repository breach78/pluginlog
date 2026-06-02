import AppKit
import XCTest
@testable import BrainUnfog

@MainActor
final class TimelineProjectListWindowPresenterTests: XCTestCase {
  func testProjectListWindowBehavesLikeNormalWindowWhenAppDeactivates() {
    let window = NSPanel()

    TimelineProjectListWindowPresenter.configureWindowLevel(window)

    XCTAssertEqual(window.level, .normal)
    XCTAssertFalse(window.isFloatingPanel)
    XCTAssertFalse(window.hidesOnDeactivate)
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

  func testPresentReusesExistingWindowForProject() {
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

    XCTAssertEqual(presenter.presentedProjectIDs, [projectID])
    XCTAssertEqual(presenter.refresh(snapshot: makeSnapshot(projectID: projectID, title: "After")), 1)
    XCTAssertEqual(presenter.refresh(snapshot: makeSnapshot(projectID: projectID, title: "After")), 0)
  }

  func testFrameAutosaveNameIsProjectScoped() {
    let firstProjectID = UUID()
    let secondProjectID = UUID()

    XCTAssertNotEqual(
      TimelineProjectListWindowPresenter.frameAutosaveName(for: firstProjectID),
      TimelineProjectListWindowPresenter.frameAutosaveName(for: secondProjectID)
    )
    XCTAssertTrue(
      TimelineProjectListWindowPresenter.frameAutosaveName(for: firstProjectID)
        .contains(firstProjectID.uuidString)
    )
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
