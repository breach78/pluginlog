import Testing

@testable import BrainUnfog

struct ProjectOutlineMarkdownPasteParserTests {
  @Test func headingsBecomeParentsOfFollowingListItems() throws {
    let blocks = try #require(ProjectOutlineMarkdownPasteParser.blocks(from: """
      ## 일정

      - [ ] 제출 준비
        - 자료 확인
      - 회의
      """))

    #expect(blocks.map(\.text) == ["일정", "제출 준비", "자료 확인", "회의"])
    #expect(blocks.map(\.depth) == [0, 1, 2, 1])
    #expect(blocks.map(\.isTaskBlock) == [false, true, false, false])
  }

  @Test func nestedHeadingsAndParagraphsPreserveSectionHierarchy() throws {
    let blocks = try #require(ProjectOutlineMarkdownPasteParser.blocks(from: """
      ## 신청서

      설명 문장입니다.

      ### 정보

      - [x] 제작사명
      """))

    #expect(blocks.map(\.text) == ["신청서", "설명 문장입니다.", "정보", "제작사명"])
    #expect(blocks.map(\.depth) == [0, 1, 1, 2])
    #expect(blocks.last?.isTaskBlock == true)
  }

  @Test func plainTextIsNotClaimedAsStructuredMarkdown() {
    #expect(ProjectOutlineMarkdownPasteParser.blocks(from: "첫 줄\n둘째 줄") == nil)
  }
}
