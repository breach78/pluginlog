import AppKit
import SwiftUI

struct LinkedTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var measuredHeight: CGFloat

  let font: NSFont
  let vaultRootURL: URL?
  let allowsNewlines: Bool
  let lineHeightMultiple: CGFloat

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder

    let textView = NSTextView()
    textView.delegate = context.coordinator
    textView.isEditable = true
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 0, height: 2)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.allowsUndo = true
    textView.isAutomaticLinkDetectionEnabled = false
    textView.font = font
    textView.string = text
    context.coordinator.applyAttributes(to: textView)

    scrollView.documentView = textView
    context.coordinator.textView = textView
    DispatchQueue.main.async {
      context.coordinator.updateMeasuredHeight()
    }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = scrollView.documentView as? NSTextView else { return }
    let styleChanged = context.coordinator.updateFontIfNeeded(on: textView)
    if textView.string != text {
      context.coordinator.isApplyingText = true
      textView.string = text
      context.coordinator.isApplyingText = false
      context.coordinator.cancelDeferredUpdates()
      context.coordinator.applyAttributes(to: textView)
      context.coordinator.scheduleMeasuredHeightUpdate()
      return
    }
    if styleChanged {
      context.coordinator.applyAttributes(to: textView)
      context.coordinator.scheduleMeasuredHeightUpdate()
    } else {
      context.coordinator.updateMeasuredHeightIfWidthChanged()
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: LinkedTextEditor
    weak var textView: NSTextView?
    var isApplyingText = false
    private var attributeRefreshTask: Task<Void, Never>?
    private var heightMeasurementTask: Task<Void, Never>?
    private var lastMeasuredWidth: CGFloat = 0
    private let linkDetector = try? NSDataDetector(
      types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    private let markdownLinkRegex = try? NSRegularExpression(
      pattern: #"!?\[([^\]]+)\]\(([^)]+)\)"#
    )

    private static let attributeRefreshDelayNanoseconds: UInt64 = 180_000_000
    private static let heightMeasurementDelayNanoseconds: UInt64 = 120_000_000

    init(_ parent: LinkedTextEditor) {
      self.parent = parent
    }

    deinit {
      attributeRefreshTask?.cancel()
      heightMeasurementTask?.cancel()
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingText, let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      textView.typingAttributes = baseAttributes()
      scheduleAttributeRefresh(for: textView)
      scheduleMeasuredHeightUpdate()
    }

    func textView(
      _ textView: NSTextView,
      shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      guard !parent.allowsNewlines, let replacementString else { return true }
      guard replacementString.contains(where: \.isNewline) else { return true }
      let normalized = replacementString
        .replacingOccurrences(of: "\r\n", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
      textView.insertText(normalized, replacementRange: affectedCharRange)
      return false
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      if let url = resolvedURL(from: link) {
        NSWorkspace.shared.open(url)
        return true
      }
      return false
    }

    func updateFontIfNeeded(on textView: NSTextView) -> Bool {
      guard
        textView.font?.fontName == parent.font.fontName,
        textView.font?.pointSize == parent.font.pointSize
      else {
        textView.font = parent.font
        return true
      }
      return false
    }

    func applyAttributes(to textView: NSTextView) {
      guard let storage = textView.textStorage else { return }
      attributeRefreshTask?.cancel()
      attributeRefreshTask = nil
      let selectedRanges = textView.selectedRanges
      let fullRange = NSRange(location: 0, length: storage.length)
      let attributes = baseAttributes()
      textView.typingAttributes = attributes
      storage.beginEditing()
      if fullRange.length > 0 {
        storage.setAttributes(attributes, range: fullRange)
      }
      applyDetectedLinks(in: storage)
      applyMarkdownLinks(in: storage)
      storage.endEditing()
      textView.selectedRanges = selectedRanges
    }

    func updateMeasuredHeight() {
      guard let textView, let textContainer = textView.textContainer else { return }
      heightMeasurementTask?.cancel()
      heightMeasurementTask = nil
      lastMeasuredWidth = currentMeasuredWidth()
      textView.layoutManager?.ensureLayout(for: textContainer)
      let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
      let height = ceil(usedRect.height + textView.textContainerInset.height * 2 + 6)
      if abs(parent.measuredHeight - height) > 1 {
        parent.measuredHeight = height
      }
    }

    func updateMeasuredHeightIfWidthChanged() {
      let width = currentMeasuredWidth()
      guard abs(lastMeasuredWidth - width) > 1 else { return }
      scheduleMeasuredHeightUpdate()
    }

    func scheduleAttributeRefresh(for textView: NSTextView) {
      attributeRefreshTask?.cancel()
      attributeRefreshTask = Task { @MainActor [weak self, weak textView] in
        try? await Task.sleep(nanoseconds: Self.attributeRefreshDelayNanoseconds)
        guard !Task.isCancelled, let self, let textView else { return }
        self.applyAttributes(to: textView)
      }
    }

    func scheduleMeasuredHeightUpdate() {
      heightMeasurementTask?.cancel()
      heightMeasurementTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: Self.heightMeasurementDelayNanoseconds)
        guard !Task.isCancelled, let self else { return }
        self.updateMeasuredHeight()
      }
    }

    func cancelDeferredUpdates() {
      attributeRefreshTask?.cancel()
      attributeRefreshTask = nil
      heightMeasurementTask?.cancel()
      heightMeasurementTask = nil
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.lineHeightMultiple = parent.lineHeightMultiple
      return [
        .font: parent.font,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraphStyle,
      ]
    }

    private func applyDetectedLinks(in storage: NSTextStorage) {
      guard let linkDetector else { return }
      let string = storage.string
      let range = NSRange(location: 0, length: storage.length)
      linkDetector.enumerateMatches(in: string, range: range) { match, _, _ in
        guard let match, let url = match.url else { return }
        storage.addAttributes(
          linkAttributes(url.absoluteString),
          range: match.range
        )
      }
    }

    private func applyMarkdownLinks(in storage: NSTextStorage) {
      guard let markdownLinkRegex else { return }
      let string = storage.string
      let range = NSRange(location: 0, length: storage.length)
      for match in markdownLinkRegex.matches(in: string, range: range) {
        guard
          match.numberOfRanges >= 3,
          let destinationRange = Range(match.range(at: 2), in: string)
        else { continue }
        let destination = String(string[destinationRange])
        storage.addAttributes(
          linkAttributes(destination),
          range: match.range(at: 1)
        )
      }
    }

    private func linkAttributes(_ destination: String) -> [NSAttributedString.Key: Any] {
      [
        .link: destination,
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .font: parent.font,
      ]
    }

    private func resolvedURL(from link: Any) -> URL? {
      if let url = link as? URL {
        return url
      }
      let raw = String(describing: link)
      if raw.hasPrefix("raw/assets/"), let vaultRootURL = parent.vaultRootURL {
        return vaultRootURL.appendingPathComponent(raw.removingPercentEncoding ?? raw)
      }
      if let url = URL(string: raw), url.scheme != nil {
        return url
      }
      return nil
    }

    private func currentMeasuredWidth() -> CGFloat {
      let width = textView?.enclosingScrollView?.contentSize.width ?? textView?.bounds.width ?? 0
      return width.rounded()
    }
  }
}
