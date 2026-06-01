import Testing

@testable import BrainUnfog

struct ProjectOutlineTextInsertionPolicyTests {
  @Test
  func insertsAtUtf16OffsetInKoreanText() {
    let text = "가나다"

    let result = ProjectOutlineTextInsertionPolicy.insert("X", into: text, utf16Offset: 1)

    #expect(result == "가X나다")
  }

  @Test
  func clampsOutOfBoundsOffsets() {
    #expect(ProjectOutlineTextInsertionPolicy.insert("A", into: "text", utf16Offset: -10) == "Atext")
    #expect(ProjectOutlineTextInsertionPolicy.insert("Z", into: "text", utf16Offset: 99) == "textZ")
  }
}
