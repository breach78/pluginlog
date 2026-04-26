import XCTest
@testable import BrainUnfog

final class ScheduleViewportSyncDiagnosticTests: XCTestCase {
  func testDragProjectionFrameDiagnosticIsNotUserFacing() {
    XCTAssertNil(ScheduleViewportSyncDiagnostic.dragProjectionFrameUnavailable.notice)
  }

  func testScrollRequestDiagnosticRemainsUserFacing() {
    XCTAssertNotNil(ScheduleViewportSyncDiagnostic.scrollRequestQueuedWithoutViewport.notice)
  }
}
