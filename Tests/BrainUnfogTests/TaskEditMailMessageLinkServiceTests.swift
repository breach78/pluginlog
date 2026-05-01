import XCTest
@testable import BrainUnfog

final class TaskEditMailMessageLinkServiceTests: XCTestCase {
  func testBuildsMarkdownLinkForMessageURLAndEscapesTitle() {
    let link = TaskEditMailMessageLink(
      title: "Project [Status]",
      urlString: "message://%3Cabc@example.com%3E"
    )

    XCTAssertEqual(
      TaskEditMailMessageLinkService.markdownLink(for: link),
      "[Project \\[Status\\]](message://%3Cabc@example.com%3E)"
    )
  }

  func testBuildsMailLinkFromURLAndPlainTextTitle() {
    let payload = TaskEditMailMessageLinkService.messageLink(
      urls: [URL(string: "message://%3Cabc@example.com%3E")!],
      textCandidates: ["Project status update"]
    )

    XCTAssertEqual(
      payload,
      TaskEditMailMessageLink(
        title: "Project status update",
        urlString: "message://%3Cabc@example.com%3E"
      )
    )
  }

  func testUsesTrustedTitleCandidatesInsteadOfSearchOnlyMailPayload() {
    let payload = TaskEditMailMessageLinkService.messageLink(
      urls: [URL(string: "message://%3Cabc@example.com%3E")!],
      textCandidates: ["混獵慧敗ㄒㄟ協裕ㅂ祭桓澰托錄餐枋"],
      titleCandidates: ["Jury Invitation - 13th Montreal Asian International Film Festival"]
    )

    XCTAssertEqual(
      payload,
      TaskEditMailMessageLink(
        title: "Jury Invitation - 13th Montreal Asian International Film Festival",
        urlString: "message://%3Cabc@example.com%3E"
      )
    )
  }

  func testExtractsMailLinkFromHTMLAnchorCandidate() {
    let payload = TaskEditMailMessageLinkService.messageLink(
      urls: [],
      textCandidates: [
        #"<a href="message://%3Cabc@example.com%3E">Project status update</a>"#
      ]
    )

    XCTAssertEqual(
      payload,
      TaskEditMailMessageLink(
        title: "Project status update",
        urlString: "message://%3Cabc@example.com%3E"
      )
    )
  }

  func testBuildsMailLinkFromMessageIDHeaderFallback() {
    let payload = TaskEditMailMessageLinkService.messageLink(
      urls: [],
      textCandidates: [
        """
        Subject: Budget update
        Message-ID: <budget-123@example.com>
        """
      ]
    )

    XCTAssertEqual(
      payload,
      TaskEditMailMessageLink(
        title: "Budget update",
        urlString: "message://%3Cbudget-123@example.com%3E"
      )
    )
  }

  func testUsesSubjectHeaderFromSearchOnlyPayloadWhenTrustedTitleIsMissing() {
    let payload = TaskEditMailMessageLinkService.messageLink(
      urls: [],
      textCandidates: [
        """
        Subject: Jury Invitation - 13th Montreal Asian International Film Festival
        Message-ID: <jury-123@example.com>
        """
      ],
      titleCandidates: []
    )

    XCTAssertEqual(
      payload,
      TaskEditMailMessageLink(
        title: "Jury Invitation - 13th Montreal Asian International Film Festival",
        urlString: "message://%3Cjury-123@example.com%3E"
      )
    )
  }

  func testIgnoresNonMailMessageURLs() {
    let payload = TaskEditMailMessageLinkService.messageLink(
      urls: [URL(string: "https://example.com")!],
      textCandidates: ["Example"]
    )

    XCTAssertNil(payload)
  }
}
