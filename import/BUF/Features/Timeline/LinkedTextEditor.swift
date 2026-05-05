import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LinkedTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var measuredHeight: CGFloat

  let font: NSFont
  let vaultRootURL: URL?
  let allowsNewlines: Bool
  let lineHeightMultiple: CGFloat
  var allowsMailMessageDrops = false
  var trailingInputReserveLineCount = 0
  var trailingInputReserveActivationHeight: CGFloat = 0

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder

    let textView = LinkedTextView()
    textView.delegate = context.coordinator
    textView.linkedCoordinator = context.coordinator
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
    context.coordinator.configureMailMessageDropRegistration(on: textView)
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
    context.coordinator.configureMailMessageDropRegistration(on: textView)
    if textView.string != text {
      context.coordinator.isApplyingText = true
      textView.string = text
      context.coordinator.isApplyingText = false
      context.coordinator.clearTrailingInputReserve()
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
    private var didConfigureMailMessageDrops = false
    private var hasLinkAttributes = false
    private var pendingTrailingInputReserveExpansion = false
    private var trailingInputReserveHeightFloor: CGFloat?
    private let linkDetector = try? NSDataDetector(
      types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    private let markdownLinkRegex = try? NSRegularExpression(
      pattern: #"!?\[([^\]]+)\]\(([^)]+)\)"#
    )
    private let urlPasteboardTypes: [NSPasteboard.PasteboardType] = [
      .URL,
      NSPasteboard.PasteboardType(UTType.url.identifier),
    ]
    private let trustedTitlePasteboardTypes: [NSPasteboard.PasteboardType] = [
      .string,
      .html,
      NSPasteboard.PasteboardType(UTType.plainText.identifier),
      NSPasteboard.PasteboardType("public.utf8-plain-text"),
      NSPasteboard.PasteboardType("public.utf16-plain-text"),
      NSPasteboard.PasteboardType("public.url-name"),
      NSPasteboard.PasteboardType("org.nspasteboard.URLName"),
    ]
    private let mailSearchOnlyPasteboardTypes: [NSPasteboard.PasteboardType] = [
      NSPasteboard.PasteboardType("com.apple.mail.PasteboardTypeMessageTransfer"),
      NSPasteboard.PasteboardType("com.apple.mail.PasteboardTypeMessage"),
      NSPasteboard.PasteboardType("com.apple.mail.message"),
    ]

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
      refreshMeasuredHeightAfterUserEdit()
    }

    func textView(
      _ textView: NSTextView,
      shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      if parent.allowsNewlines,
        parent.trailingInputReserveLineCount > 0,
        let replacementString
      {
        let isEditingAtEnd = affectedCharRange.upperBound >= textView.string.utf16.count
        if !replacementString.isEmpty, isEditingAtEnd {
          pendingTrailingInputReserveExpansion = true
        } else if affectedCharRange.length > 0 || !isEditingAtEnd {
          clearTrailingInputReserve()
        }
      }

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

    func configureMailMessageDropRegistration(on textView: NSTextView) {
      guard parent.allowsMailMessageDrops, !didConfigureMailMessageDrops else { return }
      let existingTypes = textView.registeredDraggedTypes
      let supportedTypes =
        urlPasteboardTypes + trustedTitlePasteboardTypes + mailSearchOnlyPasteboardTypes
      let additionalTypes = supportedTypes.filter { !existingTypes.contains($0) }
      didConfigureMailMessageDrops = true
      guard !additionalTypes.isEmpty else { return }
      textView.registerForDraggedTypes(existingTypes + additionalTypes)
    }

    func canHandleMailMessageDrop(_ draggingInfo: any NSDraggingInfo) -> Bool {
      guard parent.allowsMailMessageDrops else { return false }
      return mailMessageLink(from: draggingInfo.draggingPasteboard) != nil
    }

    func performMailMessageDrop(
      _ draggingInfo: any NSDraggingInfo,
      in textView: NSTextView
    ) -> Bool {
      guard parent.allowsMailMessageDrops,
        let link = mailMessageLink(from: draggingInfo.draggingPasteboard)
      else {
        return false
      }

      let point = textView.convert(draggingInfo.draggingLocation, from: nil)
      let location = textView.characterIndexForInsertion(at: point)
      let safeLocation = min(max(location, 0), textView.string.utf16.count)
      textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
      let markdownLink = TaskEditMailMessageLinkService.markdownLink(for: link)
      let insertion = mailMessageInsertionText(markdownLink, in: textView.string, at: safeLocation)
      textView.insertText(insertion, replacementRange: textView.selectedRange())
      parent.text = textView.string
      textView.typingAttributes = baseAttributes()
      scheduleAttributeRefresh(for: textView)
      refreshMeasuredHeightAfterUserEdit()
      return true
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
      let hasLinkCandidates = LinkedTextEditorLinkPolicy.hasLinkCandidates(in: storage.string)
      if hasLinkCandidates {
        applyDetectedLinks(in: storage)
        applyMarkdownLinks(in: storage)
      }
      hasLinkAttributes = hasLinkCandidates
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
      let contentHeight = ceil(usedRect.height + textView.textContainerInset.height * 2 + 6)
      let lineHeight = reservedLineHeight(for: textView)
      let currentVisibleHeight = max(
        parent.measuredHeight,
        parent.trailingInputReserveActivationHeight,
        trailingInputReserveHeightFloor ?? 0
      )
      let expandsReserve = pendingTrailingInputReserveExpansion
        && LinkedTextEditorHeightPolicy.shouldExpandReserve(
          contentHeight: contentHeight,
          currentVisibleHeight: currentVisibleHeight,
          lineHeight: lineHeight
        )
      let heightPolicy = LinkedTextEditorHeightPolicy.resolvedHeight(
        contentHeight: contentHeight,
        reserveHeightFloor: trailingInputReserveHeightFloor,
        expandsReserve: expandsReserve,
        reserveLineCount: parent.trailingInputReserveLineCount,
        lineHeight: lineHeight
      )
      trailingInputReserveHeightFloor = heightPolicy.reserveHeightFloor
      pendingTrailingInputReserveExpansion = false
      let height = heightPolicy.height
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
      guard
        LinkedTextEditorLinkPolicy.hasLinkCandidates(in: textView.string)
          || hasLinkAttributes
      else {
        attributeRefreshTask?.cancel()
        attributeRefreshTask = nil
        return
      }

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

    func refreshMeasuredHeightAfterUserEdit() {
      if parent.trailingInputReserveLineCount > 0 {
        updateMeasuredHeight()
      } else {
        scheduleMeasuredHeightUpdate()
      }
    }

    func cancelDeferredUpdates() {
      attributeRefreshTask?.cancel()
      attributeRefreshTask = nil
      heightMeasurementTask?.cancel()
      heightMeasurementTask = nil
    }

    func clearTrailingInputReserve() {
      pendingTrailingInputReserveExpansion = false
      trailingInputReserveHeightFloor = nil
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

    private func reservedLineHeight(for textView: NSTextView) -> CGFloat {
      let layoutHeight = textView.layoutManager?.defaultLineHeight(for: parent.font) ?? 0
      let fontHeight = parent.font.ascender - parent.font.descender + parent.font.leading
      return ceil(max(layoutHeight, fontHeight, parent.font.pointSize) * parent.lineHeightMultiple)
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
        applyMailMessageMarkdownDisplay(in: storage, match: match, destination: destination)
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

    private func mailMessageLink(from pasteboard: NSPasteboard) -> TaskEditMailMessageLink? {
      let textCandidates = pasteboardTextCandidates(from: pasteboard)
      return TaskEditMailMessageLinkService.messageLink(
        urls: pasteboardURLs(from: pasteboard),
        textCandidates: textCandidates.search,
        titleCandidates: textCandidates.title
      )
    }

    private func pasteboardURLs(from pasteboard: NSPasteboard) -> [URL] {
      let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
      var urls = objects.compactMap { object -> URL? in
        if let url = object as? URL {
          return url
        }
        if let url = object as? NSURL {
          return url as URL
        }
        return nil
      }
      if let string = pasteboard.string(forType: .URL), let url = URL(string: string) {
        urls.append(url)
      }
      return urls
    }

    private func pasteboardTextCandidates(from pasteboard: NSPasteboard) -> MailPasteboardTextCandidates {
      var candidates = MailPasteboardTextCandidates()
      for type in trustedTitlePasteboardTypes {
        appendTrustedTitleCandidate(from: pasteboard.string(forType: type), to: &candidates)
        appendTrustedTitleCandidate(from: pasteboard.data(forType: type), to: &candidates)
      }
      for type in urlPasteboardTypes + mailSearchOnlyPasteboardTypes {
        appendSearchCandidate(from: pasteboard.string(forType: type), to: &candidates)
        appendSearchCandidate(from: pasteboard.data(forType: type), to: &candidates)
      }
      for item in pasteboard.pasteboardItems ?? [] {
        for type in item.types {
          if isTrustedTitlePasteboardType(type) {
            appendTrustedTitleCandidate(from: item.string(forType: type), to: &candidates)
            appendTrustedTitleCandidate(from: item.data(forType: type), to: &candidates)
          } else if isLikelySearchPasteboardType(type) {
            appendSearchCandidate(from: item.string(forType: type), to: &candidates)
            appendSearchCandidate(from: item.data(forType: type), to: &candidates)
          }
        }
      }
      return candidates
    }

    private func isTrustedTitlePasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
      if trustedTitlePasteboardTypes.contains(type) {
        return true
      }
      let raw = type.rawValue.lowercased()
      return raw.contains("url-name")
        || raw.contains("title")
        || raw.contains("subject")
        || raw == UTType.plainText.identifier
        || raw == UTType.html.identifier
    }

    private func isLikelySearchPasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
      let raw = type.rawValue.lowercased()
      return raw.contains("url")
        || raw.contains("text")
        || raw.contains("html")
        || raw.contains("string")
        || raw.contains("mail")
        || raw.contains("message")
    }

    private func appendTrustedTitleCandidate(
      from text: String?,
      to candidates: inout MailPasteboardTextCandidates
    ) {
      guard let text = sanitizedTextCandidate(text) else { return }
      candidates.appendTitle(text)
      candidates.appendSearch(text)
    }

    private func appendTrustedTitleCandidate(
      from data: Data?,
      to candidates: inout MailPasteboardTextCandidates
    ) {
      guard let data, data.count <= 1_048_576 else { return }
      appendTrustedTitleCandidate(from: String(data: data, encoding: .utf8), to: &candidates)
      appendTrustedTitleCandidate(from: String(data: data, encoding: .utf16), to: &candidates)
    }

    private func appendSearchCandidate(
      from text: String?,
      to candidates: inout MailPasteboardTextCandidates
    ) {
      guard let text = sanitizedTextCandidate(text) else { return }
      candidates.appendSearch(text)
    }

    private func appendSearchCandidate(
      from data: Data?,
      to candidates: inout MailPasteboardTextCandidates
    ) {
      guard let data, data.count <= 1_048_576 else { return }
      appendSearchCandidate(from: String(data: data, encoding: .utf8), to: &candidates)
      appendSearchCandidate(from: String(data: data, encoding: .utf16), to: &candidates)
    }

    private func sanitizedTextCandidate(_ text: String?) -> String? {
      guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      return text
    }

    private func applyMailMessageMarkdownDisplay(
      in storage: NSTextStorage,
      match: NSTextCheckingResult,
      destination: String
    ) {
      guard URL(string: destination)?.scheme?.lowercased() == "message" else { return }
      let labelRange = match.range(at: 1)
      let hiddenRanges = hiddenMarkdownSyntaxRanges(matchRange: match.range, labelRange: labelRange)
      for range in hiddenRanges where range.length > 0 {
        storage.removeAttribute(.link, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.addAttributes(hiddenMailMessageLinkSyntaxAttributes(), range: range)
      }
    }

    private func hiddenMarkdownSyntaxRanges(
      matchRange: NSRange,
      labelRange: NSRange
    ) -> [NSRange] {
      [
        NSRange(
          location: matchRange.location,
          length: max(0, labelRange.location - matchRange.location)
        ),
        NSRange(
          location: labelRange.upperBound,
          length: max(0, matchRange.upperBound - labelRange.upperBound)
        ),
      ]
    }

    private func hiddenMailMessageLinkSyntaxAttributes() -> [NSAttributedString.Key: Any] {
      [
        .foregroundColor: NSColor.clear,
        .font: NSFont.systemFont(ofSize: 0.1),
        .underlineStyle: 0,
      ]
    }

    private func mailMessageInsertionText(
      _ markdownLink: String,
      in currentText: String,
      at location: Int
    ) -> String {
      guard !currentText.isEmpty,
        location == currentText.utf16.count,
        !currentText.hasSuffix("\n")
      else {
        return markdownLink
      }
      return "\n\(markdownLink)"
    }

    private func currentMeasuredWidth() -> CGFloat {
      let width = textView?.enclosingScrollView?.contentSize.width ?? textView?.bounds.width ?? 0
      return width.rounded()
    }
  }
}

struct LinkedTextEditorHeightPolicyResult: Equatable {
  let height: CGFloat
  let reserveHeightFloor: CGFloat?
}

enum LinkedTextEditorHeightPolicy {
  static func shouldExpandReserve(
    contentHeight: CGFloat,
    currentVisibleHeight: CGFloat,
    lineHeight: CGFloat
  ) -> Bool {
    guard lineHeight > 0 else { return true }
    return contentHeight >= currentVisibleHeight - lineHeight
  }

  static func resolvedHeight(
    contentHeight: CGFloat,
    reserveHeightFloor: CGFloat?,
    expandsReserve: Bool,
    reserveLineCount: Int,
    lineHeight: CGFloat
  ) -> LinkedTextEditorHeightPolicyResult {
    let contentHeight = ceil(contentHeight)
    guard reserveLineCount > 0, lineHeight > 0 else {
      return LinkedTextEditorHeightPolicyResult(height: contentHeight, reserveHeightFloor: nil)
    }

    var reserveHeightFloor = reserveHeightFloor
    if expandsReserve {
      let reserveHeight = ceil(lineHeight * CGFloat(reserveLineCount))
      reserveHeightFloor = max(reserveHeightFloor ?? 0, contentHeight + reserveHeight)
    } else if let floor = reserveHeightFloor, contentHeight > floor {
      reserveHeightFloor = nil
    }

    guard let floor = reserveHeightFloor else {
      return LinkedTextEditorHeightPolicyResult(height: contentHeight, reserveHeightFloor: nil)
    }
    return LinkedTextEditorHeightPolicyResult(
      height: max(contentHeight, floor),
      reserveHeightFloor: floor
    )
  }
}

enum LinkedTextEditorLinkPolicy {
  static func hasLinkCandidates(in text: String) -> Bool {
    text.contains("://")
      || text.localizedCaseInsensitiveContains("www.")
      || text.localizedCaseInsensitiveContains("mailto:")
      || text.localizedCaseInsensitiveContains("message:")
      || text.contains("](")
      || (text.contains("@") && text.contains("."))
  }
}

private final class LinkedTextView: NSTextView {
  weak var linkedCoordinator: LinkedTextEditor.Coordinator?

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    if linkedCoordinator?.canHandleMailMessageDrop(sender) == true {
      return .copy
    }
    return super.draggingEntered(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    if linkedCoordinator?.canHandleMailMessageDrop(sender) == true {
      return .copy
    }
    return super.draggingUpdated(sender)
  }

  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if linkedCoordinator?.canHandleMailMessageDrop(sender) == true {
      return true
    }
    return super.prepareForDragOperation(sender)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if linkedCoordinator?.performMailMessageDrop(sender, in: self) == true {
      return true
    }
    return super.performDragOperation(sender)
  }
}

private struct MailPasteboardTextCandidates {
  private(set) var search: [String] = []
  private(set) var title: [String] = []

  mutating func appendSearch(_ text: String) {
    if !search.contains(text) {
      search.append(text)
    }
  }

  mutating func appendTitle(_ text: String) {
    if !title.contains(text) {
      title.append(text)
    }
  }
}
