import XCTest
@testable import BrainUnfog

final class LinkedTextEditorPolicyTests: XCTestCase {
  func testTrailingReserveExpandsMeasuredHeightInOneChunk() {
    let result = LinkedTextEditorHeightPolicy.resolvedHeight(
      contentHeight: 100,
      reserveHeightFloor: nil,
      expandsReserve: true,
      reserveLineCount: 5,
      lineHeight: 12
    )

    XCTAssertEqual(result.height, 160)
    XCTAssertEqual(result.reserveHeightFloor, 160)
  }

  func testTrailingReserveKeepsHeightStableWhileContentFits() {
    let result = LinkedTextEditorHeightPolicy.resolvedHeight(
      contentHeight: 124,
      reserveHeightFloor: 160,
      expandsReserve: false,
      reserveLineCount: 5,
      lineHeight: 12
    )

    XCTAssertEqual(result.height, 160)
    XCTAssertEqual(result.reserveHeightFloor, 160)
  }

  func testTrailingReserveClearsWhenContentExceedsFloor() {
    let result = LinkedTextEditorHeightPolicy.resolvedHeight(
      contentHeight: 172,
      reserveHeightFloor: 160,
      expandsReserve: false,
      reserveLineCount: 5,
      lineHeight: 12
    )

    XCTAssertEqual(result.height, 172)
    XCTAssertNil(result.reserveHeightFloor)
  }

  func testLinkCandidatePolicySkipsPlainText() {
    XCTAssertFalse(
      LinkedTextEditorLinkPolicy.hasLinkCandidates(in: "평범한 노트 입력 중입니다.")
    )
  }

  func testLinkCandidatePolicyDetectsMarkdownAndURLs() {
    XCTAssertTrue(
      LinkedTextEditorLinkPolicy.hasLinkCandidates(in: "[메일](message://abc)")
    )
    XCTAssertTrue(
      LinkedTextEditorLinkPolicy.hasLinkCandidates(in: "https://example.com")
    )
    XCTAssertTrue(
      LinkedTextEditorLinkPolicy.hasLinkCandidates(in: "me@example.com")
    )
  }
}
