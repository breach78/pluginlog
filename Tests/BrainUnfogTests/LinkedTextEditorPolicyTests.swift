import AppKit
import SwiftUI
import XCTest
@testable import BrainUnfog

final class LinkedTextEditorPolicyTests: XCTestCase {
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

  func testKeyboardShortcutPolicyRecognizesCommandAOnly() {
    XCTAssertTrue(
      LinkedTextEditorKeyboardShortcutPolicy.isSelectAllShortcut(
        keyCode: 0,
        modifiers: .command
      )
    )
    XCTAssertFalse(
      LinkedTextEditorKeyboardShortcutPolicy.isSelectAllShortcut(
        keyCode: 0,
        modifiers: [.command, .shift]
      )
    )
    XCTAssertFalse(
      LinkedTextEditorKeyboardShortcutPolicy.isSelectAllShortcut(
        keyCode: 1,
        modifiers: .command
      )
    )
  }

  func testSelectionVisibilityPolicyTargetsInsertionPointWithinTextBounds() {
    XCTAssertEqual(
      LinkedTextEditorSelectionVisibilityPolicy.targetRange(
        selectedRange: NSRange(location: 4, length: 2),
        textLength: 10
      ),
      NSRange(location: 6, length: 0)
    )
    XCTAssertEqual(
      LinkedTextEditorSelectionVisibilityPolicy.targetRange(
        selectedRange: NSRange(location: 12, length: 4),
        textLength: 10
      ),
      NSRange(location: 10, length: 0)
    )
  }

  func testSelectionVisibilityPolicyPadsCaretRectVerticallyOnly() {
    let rect = NSRect(x: 12, y: 24, width: 3, height: 18)
    let padded = LinkedTextEditorSelectionVisibilityPolicy.padded(rect)

    XCTAssertEqual(padded.minX, rect.minX, accuracy: 0.001)
    XCTAssertEqual(padded.width, rect.width, accuracy: 0.001)
    XCTAssertEqual(
      padded.minY,
      rect.minY - LinkedTextEditorSelectionVisibilityPolicy.verticalPadding,
      accuracy: 0.001
    )
    XCTAssertEqual(
      padded.height,
      rect.height + LinkedTextEditorSelectionVisibilityPolicy.verticalPadding * 2,
      accuracy: 0.001
    )
  }

  func testMarkdownPreviewKeepsActiveLineInSourceMode() {
    let text = "# Heading\n**Bold** and [Mail](message://abc)"
    let activeLines = LinkedTextEditorMarkdownPreviewPolicy.activeLineRanges(
      in: text,
      selectedRanges: [NSRange(location: 0, length: 0)]
    )

    let decorations = LinkedTextEditorMarkdownPreviewPolicy.decorations(
      in: text,
      activeLineRanges: activeLines
    )
    let hiddenFragments = hiddenFragments(in: text, decorations: decorations)

    XCTAssertFalse(hiddenFragments.contains("# "))
    XCTAssertTrue(hiddenFragments.contains("**"))
    XCTAssertTrue(hiddenFragments.contains("["))
    XCTAssertTrue(hiddenFragments.contains("](message://abc)"))
  }

  func testMarkdownPreviewHasNoActiveLineWhenEditorIsInactive() {
    let text = "# Heading\n**Bold** and [Mail](message://abc)"
    let activeLines = LinkedTextEditorMarkdownPreviewPolicy.activeLineRanges(
      in: text,
      selectedRanges: [NSRange(location: 0, length: 0)],
      isEditorActive: false
    )

    let decorations = LinkedTextEditorMarkdownPreviewPolicy.decorations(
      in: text,
      activeLineRanges: activeLines
    )
    let hiddenFragments = hiddenFragments(in: text, decorations: decorations)

    XCTAssertTrue(hiddenFragments.contains("# "))
    XCTAssertTrue(hiddenFragments.contains("**"))
    XCTAssertTrue(hiddenFragments.contains("["))
    XCTAssertTrue(hiddenFragments.contains("](message://abc)"))
  }

  func testMarkdownPreviewDecoratesInactiveLineOnly() {
    let text = "# Heading\n**Bold** and [Mail](message://abc)"
    let activeLines = LinkedTextEditorMarkdownPreviewPolicy.activeLineRanges(
      in: text,
      selectedRanges: [NSRange(location: (text as NSString).length, length: 0)]
    )

    let decorations = LinkedTextEditorMarkdownPreviewPolicy.decorations(
      in: text,
      activeLineRanges: activeLines
    )

    XCTAssertTrue(hiddenFragments(in: text, decorations: decorations).contains("# "))
    XCTAssertTrue(
      decorations.contains(
        LinkedTextEditorMarkdownPreviewDecoration(
          kind: .heading(1),
          range: (text as NSString).range(of: "Heading")
        )
      )
    )
  }

  func testMarkdownPreviewTracksHeadingLevels() {
    let text = "# One\n## Two\n### Three"
    let decorations = LinkedTextEditorMarkdownPreviewPolicy.decorations(
      in: text,
      activeLineRanges: []
    )

    XCTAssertTrue(
      decorations.contains(
        LinkedTextEditorMarkdownPreviewDecoration(
          kind: .heading(1),
          range: (text as NSString).range(of: "One")
        )
      )
    )
    XCTAssertTrue(
      decorations.contains(
        LinkedTextEditorMarkdownPreviewDecoration(
          kind: .heading(2),
          range: (text as NSString).range(of: "Two")
        )
      )
    )
    XCTAssertTrue(
      decorations.contains(
        LinkedTextEditorMarkdownPreviewDecoration(
          kind: .heading(3),
          range: (text as NSString).range(of: "Three")
        )
      )
    )
  }

  func testMarkdownPreviewTreatsSelectedParagraphsAsActive() {
    let text = "# Heading\n**Bold**\n`Code`"
    let selection = NSRange(location: 0, length: (text as NSString).range(of: "**Bold**").upperBound)
    let activeLines = LinkedTextEditorMarkdownPreviewPolicy.activeLineRanges(
      in: text,
      selectedRanges: [selection]
    )

    let decorations = LinkedTextEditorMarkdownPreviewPolicy.decorations(
      in: text,
      activeLineRanges: activeLines
    )
    let hiddenFragments = hiddenFragments(in: text, decorations: decorations)

    XCTAssertFalse(hiddenFragments.contains("# "))
    XCTAssertFalse(hiddenFragments.contains("**"))
    XCTAssertTrue(hiddenFragments.contains("`"))
  }

  func testMarkdownListInputPadsBulletMarkerOnSpace() {
    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: "-",
        affectedRange: NSRange(location: 1, length: 0),
        replacementString: " "
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: NSRange(location: 0, length: 1),
        text: "   - "
      )
    )
  }

  func testMarkdownListInputPadsOrderedMarkersToThreeDigitColumn() {
    XCTAssertEqual(
      listReplacementText(for: "1."),
      "  1. "
    )
    XCTAssertEqual(
      listReplacementText(for: "10."),
      " 10. "
    )
    XCTAssertEqual(
      listReplacementText(for: "100."),
      "100. "
    )
  }

  func testMarkdownListInputOnlyTransformsLineStartMarkers() {
    XCTAssertNil(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: "note -",
        affectedRange: NSRange(location: 6, length: 0),
        replacementString: " "
      )
    )

    let text = "first\n1."
    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: text,
        affectedRange: NSRange(location: (text as NSString).length, length: 0),
        replacementString: " "
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: NSRange(location: 6, length: 2),
        text: "  1. "
      )
    )
  }

  func testMarkdownListInputContinuesBulletOnEnterAfterContent() {
    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: "   - item",
        affectedRange: NSRange(location: 9, length: 0),
        replacementString: "\n"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: NSRange(location: 9, length: 0),
        text: "\n   - "
      )
    )
  }

  func testMarkdownListInputContinuesOrderedListWithNextNumber() {
    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: "  1. item",
        affectedRange: NSRange(location: 9, length: 0),
        replacementString: "\n"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: NSRange(location: 9, length: 0),
        text: "\n  2. "
      )
    )
  }

  func testMarkdownListInputExitsListOnEnterWithoutContent() {
    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: "first\n  2. ",
        affectedRange: NSRange(location: 11, length: 0),
        replacementString: "\n"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: NSRange(location: 6, length: 5),
        text: ""
      )
    )
  }

  func testMarkdownListInputOutdentsNestedBulletOnEnterWithoutContent() {
    let text = "   - parent\n       - "
    let prefixRange = (text as NSString).range(of: "       - ", options: .backwards)

    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: text,
        affectedRange: NSRange(location: (text as NSString).length, length: 0),
        replacementString: "\n"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: prefixRange,
        text: "   - "
      )
    )
  }

  func testMarkdownListInputOutdentsNestedOrderedListToParentNextNumber() {
    let text = "  1. parent\n      1. child\n      2. "
    let prefixRange = (text as NSString).range(of: "      2. ", options: .backwards)

    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: text,
        affectedRange: NSRange(location: (text as NSString).length, length: 0),
        replacementString: "\n"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: prefixRange,
        text: "  2. "
      )
    )
  }

  func testMarkdownListInputOutdentsNestedBulletToOrderedParentContext() {
    let text = "  1. parent\n       - child\n       - "
    let prefixRange = (text as NSString).range(of: "       - ", options: .backwards)

    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: text,
        affectedRange: NSRange(location: (text as NSString).length, length: 0),
        replacementString: "\n"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: prefixRange,
        text: "  2. "
      )
    )
  }

  func testMarkdownListInputIndentsBulletOnTab() {
    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: "   - item",
        affectedRange: NSRange(location: 5, length: 0),
        replacementString: "\t"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: NSRange(location: 0, length: 5),
        text: "       - "
      )
    )
  }

  func testMarkdownListInputIndentsOrderedListAndRestartsNumberOnTab() {
    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: "  2. item",
        affectedRange: NSRange(location: 5, length: 0),
        replacementString: "\t"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: NSRange(location: 0, length: 5),
        text: "      1. "
      )
    )
  }

  func testMarkdownListInputContinuesNestedOrderedList() {
    XCTAssertEqual(
      LinkedTextEditorMarkdownListInputPolicy.replacement(
        in: "      1. item",
        affectedRange: NSRange(location: 13, length: 0),
        replacementString: "\n"
      ),
      LinkedTextEditorMarkdownListInputReplacement(
        range: NSRange(location: 13, length: 0),
        text: "\n      2. "
      )
    )
  }

  @MainActor
  func testMarkdownListInputProgrammaticReplacementDoesNotReenterDelegate() {
    var editorText = "  1. item"
    var measuredHeight: CGFloat = 0
    let editor = LinkedTextEditor(
      text: Binding(get: { editorText }, set: { editorText = $0 }),
      measuredHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
      font: .systemFont(ofSize: 14),
      vaultRootURL: nil,
      allowsNewlines: true,
      lineHeightMultiple: 1,
      markdownPresentationMode: .livePreview
    )
    let coordinator = LinkedTextEditor.Coordinator(editor)
    let textView = NSTextView()
    textView.delegate = coordinator
    textView.string = editorText

    let shouldApplyOriginalInput = coordinator.textView(
      textView,
      shouldChangeTextIn: NSRange(location: (editorText as NSString).length, length: 0),
      replacementString: "\n"
    )

    XCTAssertFalse(shouldApplyOriginalInput)
    XCTAssertEqual(textView.string, "  1. item\n  2. ")
    XCTAssertEqual(editorText, textView.string)
  }

  @MainActor
  func testEscapeCommandInvokesEditorEscapeHandler() {
    var editorText = "note"
    var measuredHeight: CGFloat = 0
    var escapeCount = 0
    let editor = LinkedTextEditor(
      text: Binding(get: { editorText }, set: { editorText = $0 }),
      measuredHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
      font: .systemFont(ofSize: 14),
      vaultRootURL: nil,
      allowsNewlines: true,
      lineHeightMultiple: 1,
      onEscape: {
        escapeCount += 1
      }
    )
    let coordinator = LinkedTextEditor.Coordinator(editor)

    let handled = coordinator.textView(
      NSTextView(),
      doCommandBy: #selector(NSResponder.cancelOperation(_:))
    )

    XCTAssertTrue(handled)
    XCTAssertEqual(escapeCount, 1)
  }

  @MainActor
  func testTextChangeRefreshesMeasuredHeightSynchronously() {
    var editorText = "one"
    var measuredHeight: CGFloat = 0
    let editor = LinkedTextEditor(
      text: Binding(get: { editorText }, set: { editorText = $0 }),
      measuredHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
      font: .systemFont(ofSize: 14),
      vaultRootURL: nil,
      allowsNewlines: true,
      lineHeightMultiple: 1
    )
    let coordinator = LinkedTextEditor.Coordinator(editor)
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainerInset = NSSize(width: 0, height: 2)
    textView.font = .systemFont(ofSize: 14)
    textView.string = "one\ntwo"
    coordinator.textView = textView

    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    XCTAssertEqual(editorText, "one\ntwo")
    XCTAssertGreaterThan(measuredHeight, 0)
  }

  @MainActor
  func testAttributeRefreshDefersWhileMarkedTextIsActive() async throws {
    var editorText = "**bold**. "
    var measuredHeight: CGFloat = 0
    let editor = LinkedTextEditor(
      text: Binding(get: { editorText }, set: { editorText = $0 }),
      measuredHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
      font: .systemFont(ofSize: 14),
      vaultRootURL: nil,
      allowsNewlines: true,
      lineHeightMultiple: 1,
      markdownPresentationMode: .livePreview
    )
    let coordinator = LinkedTextEditor.Coordinator(editor)
    let textView = MarkedTextView()
    textView.string = editorText
    coordinator.textView = textView

    coordinator.scheduleAttributeRefresh(for: textView)
    try await Task.sleep(nanoseconds: 240_000_000)

    let markedFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    if let markedFont {
      XCTAssertNotEqual(markedFont.pointSize, 0.1, accuracy: 0.001)
    }

    textView.reportsMarkedText = false
    coordinator.scheduleAttributeRefresh(for: textView)
    try await Task.sleep(nanoseconds: 240_000_000)

    let previewFont = try XCTUnwrap(
      textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    XCTAssertEqual(previewFont.pointSize, 0.1, accuracy: 0.001)
  }

  func testMarkdownPreviewFindsListParagraphPrefixesForHangingIndent() {
    let text = "   - bullet wraps\nplain\n  1. ordered wraps\n100. ordered"
    let paragraphs = LinkedTextEditorMarkdownPreviewPolicy.listParagraphs(in: text)

    XCTAssertEqual(
      paragraphs.map(\.prefix),
      ["   - ", "  1. ", "100. "]
    )
    XCTAssertEqual(
      paragraphs.map { (text as NSString).substring(with: $0.range) },
      ["   - bullet wraps\n", "  1. ordered wraps\n", "100. ordered"]
    )
    XCTAssertEqual(
      paragraphs.map { (text as NSString).substring(with: $0.markerRange) },
      ["-", "1.", "100."]
    )
  }

  private func hiddenFragments(
    in text: String,
    decorations: [LinkedTextEditorMarkdownPreviewDecoration]
  ) -> [String] {
    let nsString = text as NSString
    return decorations
      .filter { $0.kind == .hiddenSyntax }
      .map { nsString.substring(with: $0.range) }
  }

  private func listReplacementText(for marker: String) -> String? {
    LinkedTextEditorMarkdownListInputPolicy.replacement(
      in: marker,
      affectedRange: NSRange(location: (marker as NSString).length, length: 0),
      replacementString: " "
    )?.text
  }
}

private final class MarkedTextView: NSTextView {
  var reportsMarkedText = true

  override func hasMarkedText() -> Bool {
    reportsMarkedText
  }
}
