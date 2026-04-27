import AppKit
import XCTest
@testable import BrainUnfog

@MainActor
final class WorkspaceTextResponderReleasePolicyTests: XCTestCase {
  func testDoesNotReleaseWithoutActiveEditPanel() {
    XCTAssertFalse(
      WorkspaceTextResponderReleasePolicy.shouldReleaseTextResponder(
        hasActiveEditPanel: false,
        firstResponder: NSTextView(),
        mouseHitView: NSView()
      )
    )
  }

  func testDoesNotReleaseNonTextResponder() {
    XCTAssertFalse(
      WorkspaceTextResponderReleasePolicy.shouldReleaseTextResponder(
        hasActiveEditPanel: true,
        firstResponder: NSButton(),
        mouseHitView: NSView()
      )
    )
  }

  func testDoesNotReleaseWhenClickStaysInsideTextResponder() {
    let textView = NSTextView()
    let childView = NSView()
    textView.addSubview(childView)

    XCTAssertFalse(
      WorkspaceTextResponderReleasePolicy.shouldReleaseTextResponder(
        hasActiveEditPanel: true,
        firstResponder: textView,
        mouseHitView: childView
      )
    )
  }

  func testReleasesWhenClickMovesOutsideTextResponder() {
    XCTAssertTrue(
      WorkspaceTextResponderReleasePolicy.shouldReleaseTextResponder(
        hasActiveEditPanel: true,
        firstResponder: NSTextView(),
        mouseHitView: NSView()
      )
    )
  }
}
