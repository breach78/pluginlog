import AppKit
import Foundation
import SwiftUI

let journalDraftEditorMinimumHeight: CGFloat = 56

final class JournalMarkdownTextView: NSTextView {
  override var intrinsicContentSize: NSSize {
    guard let layoutManager, let textContainer else {
      return NSSize(width: NSView.noIntrinsicMetric, height: 16)
    }

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    let targetHeight = ceil(usedRect.height + textContainerInset.height * 2)
    return NSSize(width: NSView.noIntrinsicMetric, height: max(16, targetHeight))
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    invalidateIntrinsicContentSize()
  }
}

struct JournalMarkdownLabel: NSViewRepresentable {
  let markdown: String

  @MainActor
  final class Coordinator: NSObject {
    var parent: JournalMarkdownLabel
    private var lastRenderedMarkdown: String = ""

    init(parent: JournalMarkdownLabel) {
      self.parent = parent
    }

    func refresh(on textView: JournalMarkdownTextView, force: Bool = false) {
      guard force || lastRenderedMarkdown != parent.markdown else { return }
      textView.textStorage?.setAttributedString(parent.attributedString())
      lastRenderedMarkdown = parent.markdown
      textView.invalidateIntrinsicContentSize()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> JournalMarkdownTextView {
    let textView = JournalMarkdownTextView()
    textView.isEditable = false
    textView.isSelectable = false
    textView.isRichText = true
    textView.importsGraphics = false
    textView.drawsBackground = false
    textView.textContainerInset = .zero
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.lineBreakMode = .byWordWrapping
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    context.coordinator.refresh(on: textView, force: true)
    return textView
  }

  func updateNSView(_ textView: JournalMarkdownTextView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.refresh(on: textView)
  }

  private func attributedString() -> NSAttributedString {
    let rendered = NSMutableAttributedString()
    let headingFont =
      NSFont(name: "SansMonoCJKFinalDraft-Bold", size: 14)
      ?? .boldSystemFont(ofSize: 14)
    let bodyFont =
      NSFont(name: "SansMonoCJKFinalDraft", size: 14)
      ?? .systemFont(ofSize: 14)

    let headingParagraph = NSMutableParagraphStyle()
    headingParagraph.lineBreakMode = .byWordWrapping
    headingParagraph.lineSpacing = 4
    headingParagraph.paragraphSpacingBefore = 10
    headingParagraph.paragraphSpacing = 6

    let bodyParagraph = NSMutableParagraphStyle()
    bodyParagraph.lineBreakMode = .byWordWrapping
    bodyParagraph.lineSpacing = 4
    bodyParagraph.paragraphSpacing = 5

    let bulletParagraph = NSMutableParagraphStyle()
    bulletParagraph.lineBreakMode = .byWordWrapping
    bulletParagraph.lineSpacing = 4
    bulletParagraph.headIndent = 24
    bulletParagraph.firstLineHeadIndent = 0
    bulletParagraph.paragraphSpacing = 4

    let normalizedLines = markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")

    for rawLine in normalizedLines {
      let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

      if trimmed.isEmpty {
        continue
      }

      if trimmed.hasPrefix("## ") {
        continue
      }

      let attributedLine: NSAttributedString
      if trimmed.hasPrefix("### ") {
        let heading = strippedHeadingText(from: String(trimmed.dropFirst(4)))
        guard !heading.isEmpty else { continue }
        attributedLine = NSAttributedString(
          string: heading + "\n",
          attributes: [
            .font: headingFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: headingParagraph,
          ]
        )
      } else if trimmed.hasPrefix("- ") {
        let body = strippedInlineMarkdown(from: String(trimmed.dropFirst(2)))
        guard !body.isEmpty else { continue }
        let bullet = NSMutableAttributedString(
          string: "• " + body + "\n",
          attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: bulletParagraph,
          ]
        )

        if let colonIndex = body.firstIndex(of: ":") {
          let prefix = String(body[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
          if !prefix.isEmpty {
            let nsBody = body as NSString
            let prefixRange = nsBody.range(of: prefix)
            if prefixRange.location != NSNotFound {
              bullet.addAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                range: NSRange(location: prefixRange.location + 2, length: prefixRange.length)
              )
            }
          }
        }

        attributedLine = bullet
      } else {
        let body = strippedInlineMarkdown(from: trimmed)
        guard !body.isEmpty else { continue }
        attributedLine = NSAttributedString(
          string: body + "\n",
          attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: bodyParagraph,
          ]
        )
      }

      rendered.append(attributedLine)
    }

    return rendered
  }

  private func strippedInlineMarkdown(from text: String) -> String {
    text
      .replacingOccurrences(of: "**", with: "")
      .replacingOccurrences(of: "__", with: "")
      .replacingOccurrences(of: "`", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func strippedHeadingText(from text: String) -> String {
    let cleaned = strippedInlineMarkdown(from: text)
    let parts = cleaned.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let first = parts.first else { return cleaned }
    let firstToken = String(first)

    if isDecorativeHeadingToken(firstToken) {
      if parts.count == 2 {
        return String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return ""
    }

    return cleaned
  }

  private func isDecorativeHeadingToken(_ token: String) -> Bool {
    guard !token.isEmpty else { return false }
    return token.unicodeScalars.allSatisfy { scalar in
      scalar.properties.isEmoji
        || scalar.properties.generalCategory == .otherSymbol
        || scalar.properties.generalCategory == .modifierSymbol
        || scalar.properties.generalCategory == .mathSymbol
        || scalar.properties.generalCategory == .currencySymbol
    }
  }
}

struct JournalDraftEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var height: CGFloat
  @Binding var isFocused: Bool

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: JournalDraftEditor
    var isApplyingExternalText = false
    var isEditing = false
    var lastMeasuredWidth: CGFloat = 0

    init(parent: JournalDraftEditor) {
      self.parent = parent
    }

    func textDidBeginEditing(_ notification: Notification) {
      isEditing = true
      guard let textView = notification.object as? NSTextView else { return }
      publishFocus(true)
      applyMeasuredHeightIfNeeded(from: textView)
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView, !isApplyingExternalText else {
        return
      }

      if parent.text != textView.string {
        parent.text = textView.string
      }
      applyMeasuredHeightIfNeeded(from: textView)
    }

    func textDidEndEditing(_ notification: Notification) {
      isEditing = false
      guard let textView = notification.object as? NSTextView else { return }

      if parent.text != textView.string {
        parent.text = textView.string
      }
      publishFocus(false)
      applyMeasuredHeightIfNeeded(from: textView)
    }

    func applyTypingAttributes(to textView: NSTextView) {
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineBreakMode = .byWordWrapping
      paragraph.lineSpacing = 4

      let attributes: [NSAttributedString.Key: Any] = [
        .font: JournalTypography.nsFont(size: 16),
        .paragraphStyle: paragraph,
        .foregroundColor: NSColor.textColor,
      ]

      textView.typingAttributes = attributes

      guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }
      let selectedRange = textView.selectedRange()
      textStorage.beginEditing()
      textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
      textStorage.endEditing()
      textView.setSelectedRange(selectedRange)
    }

    func applyMeasuredHeightIfNeeded(from textView: NSTextView) {
      let targetHeight = measuredHeight(for: textView)
      guard abs(parent.height - targetHeight) > 0.5 else { return }

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        guard abs(self.parent.height - targetHeight) > 0.5 else { return }
        self.parent.height = targetHeight
      }
    }

    func measuredHeight(for textView: NSTextView) -> CGFloat {
      guard let textContainer = textView.textContainer,
        let layoutManager = textView.layoutManager
      else {
        return journalDraftEditorMinimumHeight
      }

      layoutManager.ensureLayout(for: textContainer)
      let usedHeight = layoutManager.usedRect(for: textContainer).height
      let inset = textView.textContainerInset
      let measured = ceil(usedHeight + inset.height * 2 + 6)
      return max(journalDraftEditorMinimumHeight, measured)
    }

    func publishFocus(_ focused: Bool) {
      guard parent.isFocused != focused else { return }
      DispatchQueue.main.async { [weak self] in
        self?.parent.isFocused = focused
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSTextView {
    let textView = NSTextView()
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsImageEditing = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.usesFindPanel = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.smartInsertDeleteEnabled = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.textColor = .textColor
    textView.insertionPointColor = .textColor
    textView.textContainerInset = NSSize(width: 0, height: 8)

    if let textContainer = textView.textContainer {
      textContainer.widthTracksTextView = true
      textContainer.heightTracksTextView = false
      textContainer.lineFragmentPadding = 0
      textContainer.containerSize = NSSize(
        width: 0,
        height: CGFloat.greatestFiniteMagnitude
      )
    }

    textView.string = text
    context.coordinator.applyTypingAttributes(to: textView)
    context.coordinator.lastMeasuredWidth = textView.bounds.width
    context.coordinator.applyMeasuredHeightIfNeeded(from: textView)
    return textView
  }

  func updateNSView(_ textView: NSTextView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.applyTypingAttributes(to: textView)

    if !context.coordinator.isEditing && textView.string != text {
      context.coordinator.isApplyingExternalText = true
      textView.string = text
      context.coordinator.isApplyingExternalText = false
      textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
      context.coordinator.applyMeasuredHeightIfNeeded(from: textView)
    }

    if abs(context.coordinator.lastMeasuredWidth - textView.bounds.width) > 0.5 {
      context.coordinator.lastMeasuredWidth = textView.bounds.width
      context.coordinator.applyMeasuredHeightIfNeeded(from: textView)
    }

    if isFocused {
      DispatchQueue.main.async {
        guard let window = textView.window else { return }
        guard window.firstResponder !== textView else { return }
        window.makeFirstResponder(textView)
        let selection = NSRange(location: textView.string.utf16.count, length: 0)
        textView.setSelectedRange(selection)
      }
    }
  }
}
