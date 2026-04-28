import AppKit
import XCTest
@testable import BrainUnfog

@MainActor
final class TimelineProjectListWindowPresenterTests: XCTestCase {
  func testProjectListWindowUsesNormalLevel() {
    let window = NSWindow()

    TimelineProjectListWindowPresenter.configureWindowLevel(window)

    XCTAssertEqual(window.level, .normal)
  }
}
