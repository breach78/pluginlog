import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let projectDetailNoteDropPasteboardTypes: [NSPasteboard.PasteboardType] = [
  NSPasteboard.PasteboardType(UTType.projectDetailAttachmentReference.identifier),
  NSPasteboard.PasteboardType(UTType.fileURL.identifier),
]

private enum ProjectDetailNoteLayoutMetrics {
  static let fontSize: CGFloat = 14
  static let lineSpacing: CGFloat = 4
  static let textContainerInset = NSSize(width: 0, height: 4)
  static let emptyTaskPaddingHorizontal: CGFloat = 10
  static let emptyTaskPaddingVertical: CGFloat = 8
  static let projectPlaceholderPaddingHorizontal: CGFloat = 14
  static let projectPlaceholderPaddingVertical: CGFloat = 14
  static let taskPlaceholderPaddingVertical: CGFloat = 8
}

private struct ProjectDetailNoteSurfaceHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

private func noteIntrinsicHeight(
  usedRectHeight: CGFloat,
  textContainerInset: NSSize,
  minimumHeight: CGFloat
) -> CGFloat {
  ceil(max(minimumHeight, usedRectHeight + textContainerInset.height * 2))
}

struct ProjectDetailNoteSection: View {
  let node: BlockNodeSnapshot
  let displayedText: String
  @Binding var draftText: String
  let emptyPlaceholder: String
  let scrollAnchorID: String?
  let canEdit: Bool
  let isEditing: Bool
  let showsLiveEditorWhenEmpty: Bool
  let requestedCursorLocation: Int?
  let focusRequestID: Int
  let onBeginEditing: () -> Void
  let onTextChange: (String) -> Void
  let onEndEditing: (String) -> Void
  let allowsInternalAttachmentDrop: () -> Bool
  let onInternalAttachmentDrop: () -> Bool
  let onAttachmentFileDrop: ([URL]) -> Bool
  let onAttachmentDropTargetChange: (Bool) -> Void
  let onActivateEditor: () -> Void
  let onActivateEditorAtCharacterIndex: (Int?) -> Void
  let onEditingDisappear: () -> Void
  let decorateEditingSurface: (AnyView) -> AnyView
  let decorateDisplaySurface: (AnyView) -> AnyView
  @State private var lastDisplaySurfaceHeight: CGFloat = 0

  var body: some View {
    let trimmedDisplayedText = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
    let usesProjectNoteSurfaceStyle = node.kind == .project
    let showsInlineEditor = canEdit && (isEditing || (showsLiveEditorWhenEmpty && trimmedDisplayedText.isEmpty))

    Group {
      if showsInlineEditor {
        stableEditingSurface(
          decorateEditingSurface(
            AnyView(
              ProjectDetailLiveNoteEditor(
                text: $draftText,
                minHeight: node.isRoot ? 34 : 28,
                fontSize: ProjectDetailNoteLayoutMetrics.fontSize,
                isFocused: isEditing,
                requestedCursorLocation: requestedCursorLocation,
                focusRequestID: focusRequestID,
                onBeginEditing: onBeginEditing,
                onTextChange: onTextChange,
                onEndEditing: onEndEditing,
                allowsInternalAttachmentDrop: allowsInternalAttachmentDrop,
                onInternalAttachmentDrop: onInternalAttachmentDrop,
                onAttachmentFileDrop: onAttachmentFileDrop,
                onAttachmentDropTargetChange: onAttachmentDropTargetChange,
                onActivateEditor: onActivateEditor
              )
              .onDisappear {
                onEditingDisappear()
              }
            )
          )
        )
      } else if !trimmedDisplayedText.isEmpty {
        measuredDisplaySurface(
          decorateDisplaySurface(
            AnyView(
              ProjectDetailMarkdownSnapshotView(
                text: displayedText,
                fontSize: ProjectDetailNoteLayoutMetrics.fontSize,
                lineSpacing: ProjectDetailNoteLayoutMetrics.lineSpacing,
                onActivateEditorAtCharacterIndex: canEdit ? onActivateEditorAtCharacterIndex : nil
              )
              .frame(maxWidth: .infinity, alignment: .leading)
            )
          )
        )
      } else if canEdit {
        measuredDisplaySurface(
          decorateDisplaySurface(
            AnyView(
              Text(emptyPlaceholder)
                .font(sectionFont(size: ProjectDetailNoteLayoutMetrics.fontSize, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.38))
                .frame(
                  maxWidth: .infinity,
                  minHeight: node.isRoot ? 78 : (usesProjectNoteSurfaceStyle ? 52 : 28),
                  alignment: .topLeading
                )
                .padding(
                  .horizontal,
                  usesProjectNoteSurfaceStyle
                    ? ProjectDetailNoteLayoutMetrics.projectPlaceholderPaddingHorizontal
                    : 0
                )
                .padding(
                  .vertical,
                  usesProjectNoteSurfaceStyle
                    ? ProjectDetailNoteLayoutMetrics.projectPlaceholderPaddingVertical
                    : 6
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                  onActivateEditorAtCharacterIndex(0)
                }
            )
          )
        )
      } else {
        EmptyView()
      }
    }
    .id(scrollAnchorID)
  }

  private func sectionFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    AppleSDGothicNeoTypography.font(size: size, weight: weight)
  }

  private func measuredDisplaySurface<Content: View>(_ content: Content) -> some View {
    content
      .background {
        GeometryReader { proxy in
          Color.clear.preference(
            key: ProjectDetailNoteSurfaceHeightPreferenceKey.self,
            value: proxy.size.height
          )
        }
      }
      .onPreferenceChange(ProjectDetailNoteSurfaceHeightPreferenceKey.self) { height in
        guard height > 0, abs(height - lastDisplaySurfaceHeight) > 0.5 else { return }
        lastDisplaySurfaceHeight = height
      }
  }

  @ViewBuilder
  private func stableEditingSurface<Content: View>(_ content: Content) -> some View {
    if lastDisplaySurfaceHeight > 0 {
      content.frame(minHeight: lastDisplaySurfaceHeight, alignment: .topLeading)
    } else {
      content
    }
  }
}

private final class ProjectDetailMarkdownTextView: NSTextView {
  var onActivateEditorAtCharacterIndex: ((Int?) -> Void)?

  override var intrinsicContentSize: NSSize {
    guard let layoutManager, let textContainer else {
      return NSSize(width: NSView.noIntrinsicMetric, height: 16)
    }

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    let height = noteIntrinsicHeight(
      usedRectHeight: usedRect.height,
      textContainerInset: textContainerInset,
      minimumHeight: 16
    )
    return NSSize(width: NSView.noIntrinsicMetric, height: max(16, height))
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    invalidateIntrinsicContentSize()
  }

  override func layout() {
    super.layout()
    invalidateIntrinsicContentSize()
  }

  override func mouseDown(with event: NSEvent) {
    guard let onActivateEditorAtCharacterIndex else {
      super.mouseDown(with: event)
      return
    }

    let localPoint = convert(event.locationInWindow, from: nil)
    onActivateEditorAtCharacterIndex(characterIndex(at: localPoint))
  }

  private func characterIndex(at point: NSPoint) -> Int? {
    guard let layoutManager, let textContainer else { return nil }

    let containerPoint = NSPoint(
      x: point.x - textContainerInset.width - textContainer.lineFragmentPadding,
      y: point.y - textContainerInset.height
    )
    let glyphIndex = layoutManager.glyphIndex(
      for: containerPoint,
      in: textContainer,
      fractionOfDistanceThroughGlyph: nil
    )
    let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
    return max(0, min(characterIndex, string.utf16.count))
  }
}

private final class ProjectDetailLiveNoteEditorTextView: NSTextView {
  var minContentHeight: CGFloat = 28
  var onEscape: (() -> Void)?
  var allowsInternalAttachmentDrop: (() -> Bool)?
  var onInternalAttachmentDrop: (() -> Bool)?
  var onAttachmentFileDrop: (([URL]) -> Bool)?
  var onAttachmentDropTargetChange: ((Bool) -> Void)?
  var onActivateEditor: (() -> Void)?
  var requiresExplicitActivation = false
  var suppressNextSelectionReveal = false

  override var intrinsicContentSize: NSSize {
    guard let layoutManager, let textContainer else {
      return NSSize(width: NSView.noIntrinsicMetric, height: minContentHeight)
    }

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    let height = noteIntrinsicHeight(
      usedRectHeight: usedRect.height,
      textContainerInset: textContainerInset,
      minimumHeight: minContentHeight
    )
    return NSSize(width: NSView.noIntrinsicMetric, height: max(minContentHeight, height))
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    textContainer?.containerSize = NSSize(
      width: max(1, newSize.width),
      height: CGFloat.greatestFiniteMagnitude
    )
    invalidateIntrinsicContentSize()
  }

  override func didChangeText() {
    super.didChangeText()
    invalidateIntrinsicContentSize()
  }

  override func layout() {
    super.layout()
    invalidateIntrinsicContentSize()
  }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }

  override func mouseDown(with event: NSEvent) {
    if requiresExplicitActivation {
      onActivateEditor?()
      return
    }
    super.mouseDown(with: event)
  }

  override func scrollRangeToVisible(_ range: NSRange) {
    if suppressNextSelectionReveal {
      suppressNextSelectionReveal = false
      return
    }
    super.scrollRangeToVisible(range)
  }

  func preserveViewportWhileActivatingEditor(_ work: () -> Void) {
    guard let scrollView = enclosingScrollView else {
      work()
      return
    }

    let preservedOrigin = scrollView.contentView.bounds.origin
    work()
    scrollView.contentView.scroll(to: preservedOrigin)
    scrollView.reflectScrolledClipView(scrollView.contentView)

    DispatchQueue.main.async {
      scrollView.contentView.scroll(to: preservedOrigin)
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    if hasInternalAttachmentDrag(sender) {
      guard allowsInternalAttachmentDrop?() == true else { return [] }
      onAttachmentDropTargetChange?(true)
      return .move
    }

    guard attachmentDropURLs(from: sender) != nil else {
      return super.draggingEntered(sender)
    }

    onAttachmentDropTargetChange?(true)
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    if hasInternalAttachmentDrag(sender) {
      guard allowsInternalAttachmentDrop?() == true else { return [] }
      onAttachmentDropTargetChange?(true)
      return .move
    }

    guard attachmentDropURLs(from: sender) != nil else {
      return super.draggingUpdated(sender)
    }

    onAttachmentDropTargetChange?(true)
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    if hasInternalAttachmentDrag(sender) {
      onAttachmentDropTargetChange?(false)
      return
    }

    if attachmentDropURLs(from: sender) != nil {
      onAttachmentDropTargetChange?(false)
      return
    }

    super.draggingExited(sender)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if hasInternalAttachmentDrag(sender) {
      return allowsInternalAttachmentDrop?() == true
    }

    guard attachmentDropURLs(from: sender) != nil else {
      return super.prepareForDragOperation(sender)
    }

    return true
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if hasInternalAttachmentDrag(sender) {
      onAttachmentDropTargetChange?(false)
      guard allowsInternalAttachmentDrop?() == true else { return false }
      return onInternalAttachmentDrop?() ?? false
    }

    guard let urls = attachmentDropURLs(from: sender) else {
      return super.performDragOperation(sender)
    }

    onAttachmentDropTargetChange?(false)
    return onAttachmentFileDrop?(urls) ?? false
  }

  override func concludeDragOperation(_ sender: NSDraggingInfo?) {
    if hasInternalAttachmentDrag(sender) {
      onAttachmentDropTargetChange?(false)
      return
    }

    if attachmentDropURLs(from: sender) != nil {
      onAttachmentDropTargetChange?(false)
      return
    }

    super.concludeDragOperation(sender)
  }

  private func attachmentDropURLs(from draggingInfo: NSDraggingInfo?) -> [URL]? {
    guard onAttachmentFileDrop != nil else { return nil }
    guard let draggingInfo else { return nil }

    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]
    guard
      let urls = draggingInfo.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: options
      ) as? [URL],
      !urls.isEmpty
    else {
      return nil
    }

    return urls
  }

  private func hasInternalAttachmentDrag(_ draggingInfo: NSDraggingInfo?) -> Bool {
    guard allowsInternalAttachmentDrop != nil || onInternalAttachmentDrop != nil else { return false }
    guard let types = draggingInfo?.draggingPasteboard.types else { return false }
    let payloadType = NSPasteboard.PasteboardType(UTType.projectDetailAttachmentReference.identifier)
    return types.contains(payloadType)
  }
}

private struct ProjectDetailLiveNoteEditor: NSViewRepresentable {
  @Binding var text: String
  let minHeight: CGFloat
  let fontSize: CGFloat
  let isFocused: Bool
  let requestedCursorLocation: Int?
  let focusRequestID: Int
  let onBeginEditing: () -> Void
  let onTextChange: (String) -> Void
  let onEndEditing: (String) -> Void
  let allowsInternalAttachmentDrop: () -> Bool
  let onInternalAttachmentDrop: () -> Bool
  let onAttachmentFileDrop: ([URL]) -> Bool
  let onAttachmentDropTargetChange: (Bool) -> Void
  let onActivateEditor: () -> Void

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ProjectDetailLiveNoteEditor
    var isApplyingExternalText = false
    var lastAppliedFocusRequestID: Int?

    init(parent: ProjectDetailLiveNoteEditor) {
      self.parent = parent
    }

    func textDidBeginEditing(_ notification: Notification) {
      parent.onBeginEditing()
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      guard !isApplyingExternalText else { return }
      parent.text = textView.string
      parent.onTextChange(textView.string)
    }

    func textDidEndEditing(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.onEndEditing(textView.string)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> ProjectDetailLiveNoteEditorTextView {
    let textView = ProjectDetailLiveNoteEditorTextView()
    textView.delegate = context.coordinator
    textView.minContentHeight = minHeight
    textView.allowsInternalAttachmentDrop = allowsInternalAttachmentDrop
    textView.onInternalAttachmentDrop = onInternalAttachmentDrop
    textView.onAttachmentFileDrop = onAttachmentFileDrop
    textView.onAttachmentDropTargetChange = onAttachmentDropTargetChange
    textView.onActivateEditor = onActivateEditor
    textView.onEscape = { [weak textView, weak coordinator = context.coordinator] in
      guard let textView, let coordinator else { return }
      coordinator.parent.text = textView.string
      coordinator.parent.onEndEditing(textView.string)
      textView.window?.makeFirstResponder(nil)
    }
    textView.isEditable = isFocused
    textView.isSelectable = isFocused
    textView.requiresExplicitActivation = !isFocused
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsImageEditing = false
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.allowsUndo = true
    textView.usesFindPanel = false
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
    textView.textContainerInset = ProjectDetailNoteLayoutMetrics.textContainerInset
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.lineBreakMode = .byWordWrapping
    textView.textContainer?.containerSize = NSSize(
      width: 1,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.font = AppleSDGothicNeoTypography.nsFont(size: fontSize)
    textView.textColor = .labelColor
    textView.insertionPointColor = .labelColor
    textView.string = text
    textView.registerForDraggedTypes(projectDetailNoteDropPasteboardTypes)
    applyEditorStyle(to: textView)
    return textView
  }

  func updateNSView(_ textView: ProjectDetailLiveNoteEditorTextView, context: Context) {
    context.coordinator.parent = self
    textView.minContentHeight = minHeight
    textView.allowsInternalAttachmentDrop = allowsInternalAttachmentDrop
    textView.onInternalAttachmentDrop = onInternalAttachmentDrop
    textView.onAttachmentFileDrop = onAttachmentFileDrop
    textView.onAttachmentDropTargetChange = onAttachmentDropTargetChange
    textView.onActivateEditor = onActivateEditor
    textView.onEscape = { [weak textView, weak coordinator = context.coordinator] in
      guard let textView, let coordinator else { return }
      coordinator.parent.text = textView.string
      coordinator.parent.onEndEditing(textView.string)
      textView.window?.makeFirstResponder(nil)
    }
    textView.requiresExplicitActivation = !isFocused
    textView.isEditable = isFocused
    textView.isSelectable = isFocused

    let targetFont = AppleSDGothicNeoTypography.nsFont(size: fontSize)
    let fontDidChange = textView.font != targetFont
    if fontDidChange {
      textView.font = targetFont
    }
    applyEditorTypingAttributes(to: textView)

    if !context.coordinator.isApplyingExternalText,
      textView.string != text,
      textView.window?.firstResponder !== textView
    {
      context.coordinator.isApplyingExternalText = true
      textView.string = text
      applyEditorStyle(to: textView)
      context.coordinator.isApplyingExternalText = false
      textView.invalidateIntrinsicContentSize()
    } else if fontDidChange, textView.window?.firstResponder !== textView {
      applyEditorStyle(to: textView)
    }

    if isFocused {
      guard context.coordinator.lastAppliedFocusRequestID != focusRequestID else { return }
      context.coordinator.lastAppliedFocusRequestID = focusRequestID
      DispatchQueue.main.async {
        guard textView.window?.firstResponder !== textView else { return }
        let endLocation = (textView.string as NSString).length
        let requestedLocation = min(max(0, requestedCursorLocation ?? 0), endLocation)
        textView.preserveViewportWhileActivatingEditor {
          textView.suppressNextSelectionReveal = true
          textView.setSelectedRange(NSRange(location: requestedLocation, length: 0))
          textView.window?.makeFirstResponder(textView)
        }
      }
    } else if textView.window?.firstResponder === textView {
      textView.window?.makeFirstResponder(nil)
    }
  }

  private var editorParagraphStyle: NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = ProjectDetailNoteLayoutMetrics.lineSpacing
    return style
  }

  private var editorAttributes: [NSAttributedString.Key: Any] {
    [
      .font: AppleSDGothicNeoTypography.nsFont(size: fontSize),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: editorParagraphStyle,
    ]
  }

  private func applyEditorTypingAttributes(to textView: ProjectDetailLiveNoteEditorTextView) {
    var typingAttributes = textView.typingAttributes
    editorAttributes.forEach { key, value in
      typingAttributes[key] = value
    }
    textView.typingAttributes = typingAttributes
  }

  private func applyEditorStyle(to textView: ProjectDetailLiveNoteEditorTextView) {
    applyEditorTypingAttributes(to: textView)
    guard let textStorage = textView.textStorage else { return }
    let fullRange = NSRange(location: 0, length: textStorage.length)
    guard fullRange.length > 0 else { return }

    let selectedRange = textView.selectedRange()
    textStorage.beginEditing()
    textStorage.addAttributes(editorAttributes, range: fullRange)
    textStorage.endEditing()
    textView.setSelectedRange(selectedRange)
  }
}

private struct ProjectDetailMarkdownSnapshotView: NSViewRepresentable {
  let text: String
  let fontSize: CGFloat
  let lineSpacing: CGFloat
  let onActivateEditorAtCharacterIndex: ((Int?) -> Void)?

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ProjectDetailMarkdownSnapshotView
    private var lastRenderedText: String = ""
    private var lastRenderedFontSize: CGFloat = -1
    private var lastRenderedLineSpacing: CGFloat = -1

    init(parent: ProjectDetailMarkdownSnapshotView) {
      self.parent = parent
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      if let url = link as? URL {
        do {
          try ApplePlatformDocumentOpener.shared.open(url)
          return true
        } catch {
          return false
        }
      }

      if let string = link as? String, let url = URL(string: string) {
        do {
          try ApplePlatformDocumentOpener.shared.open(url)
          return true
        } catch {
          return false
        }
      }

      return false
    }

    func refreshRenderedTextIfNeeded(on textView: ProjectDetailMarkdownTextView, force: Bool = false) {
      let needsTextRefresh =
        force
        || lastRenderedText != parent.text
        || abs(lastRenderedFontSize - parent.fontSize) > 0.5
        || abs(lastRenderedLineSpacing - parent.lineSpacing) > 0.5

      guard needsTextRefresh else { return }

      textView.textStorage?.setAttributedString(
        MarkdownLivePreviewStyler.attributedString(
          for: parent.text,
          fontSize: parent.fontSize,
          lineSpacing: parent.lineSpacing,
          editingParagraphRange: nil,
          fontProvider: AppleSDGothicNeoTypography.nsFont
        )
      )
      lastRenderedText = parent.text
      lastRenderedFontSize = parent.fontSize
      lastRenderedLineSpacing = parent.lineSpacing
      textView.invalidateIntrinsicContentSize()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> ProjectDetailMarkdownTextView {
    let textView = ProjectDetailMarkdownTextView()
    textView.delegate = context.coordinator
    textView.onActivateEditorAtCharacterIndex = onActivateEditorAtCharacterIndex
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = true
    textView.importsGraphics = false
    textView.drawsBackground = false
    textView.textContainerInset = ProjectDetailNoteLayoutMetrics.textContainerInset
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.lineBreakMode = .byWordWrapping
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.linkTextAttributes = [
      .foregroundColor: NSColor.linkColor,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]
    context.coordinator.refreshRenderedTextIfNeeded(on: textView, force: true)
    return textView
  }

  func updateNSView(_ textView: ProjectDetailMarkdownTextView, context: Context) {
    context.coordinator.parent = self
    textView.onActivateEditorAtCharacterIndex = onActivateEditorAtCharacterIndex
    context.coordinator.refreshRenderedTextIfNeeded(on: textView)
  }
}
