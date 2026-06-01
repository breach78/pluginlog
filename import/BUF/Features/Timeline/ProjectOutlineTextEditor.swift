import AppKit
import SwiftUI

enum ProjectOutlineTextCommand {
  case enter(offset: Int)
  case tab
  case shiftTab
  case backspaceAtStart
  case deleteAtEnd
  case commandEnter
  case commandShiftUp
  case commandShiftDown
  case commandUp
  case commandDown
  case escape
  case convertToTask
  case zoomIn
  case zoomOut
  case zoomHome
  case zoomPreviousSibling
  case zoomNextSibling
  case focusPrevious
  case focusNext
  case extendBlockSelectionUp
  case extendBlockSelectionDown
  case exitBlockSelectionUp
  case exitBlockSelectionDown
  case exitBlockSelectionLeft
  case exitBlockSelectionRight
  case clearBlockSelection
  case deleteBlockSelection
  case selectAllVisibleBlocks
}

enum ProjectOutlineFocusPlacement {
  case preserve
  case start
  case end
}

enum ProjectOutlineAttachmentTextAction {
  case open(ProjectOutlineInlineAttachment)
  case rename(ProjectOutlineInlineAttachment)
  case delete(ProjectOutlineInlineAttachment)
}

struct ProjectOutlineTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var measuredHeight: CGFloat

  var vaultRootURL: URL? = nil
  let isFocused: Bool
  let focusRequestID: UInt64
  let focusPlacement: ProjectOutlineFocusPlacement
  let isBlockSelectionActive: Bool
  let font: NSFont
  let onCommand: (ProjectOutlineTextCommand) -> Void
  var onImportFiles: ([URL], Int) -> Void = { _, _ in }
  var onOpenAttachment: (ProjectOutlineInlineAttachment) -> Void = { _ in }
  var onRenameAttachment: (ProjectOutlineInlineAttachment) -> Void = { _ in }
  var onDeleteAttachment: (ProjectOutlineInlineAttachment) -> Void = { _ in }
  let onFocus: () -> Void
  var onBlur: () -> Void = {}

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder

    let textView = CommandTextView()
    textView.delegate = context.coordinator
    textView.commandHandler = { [weak coordinator = context.coordinator] command in
      coordinator?.handle(command)
    }
    textView.fileDropHandler = { [weak coordinator = context.coordinator] urls, displayOffset in
      guard let coordinator else { return }
      coordinator.parent.onImportFiles(
        urls,
        coordinator.storageOffset(forDisplayOffset: displayOffset)
      )
    }
    textView.attachmentActionHandler = { [weak coordinator = context.coordinator] action in
      coordinator?.handle(action)
    }
    textView.isBlockSelectionActiveProvider = { [weak coordinator = context.coordinator] in
      coordinator?.parent.isBlockSelectionActive ?? false
    }
    textView.focusHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onFocus()
    }
    textView.blurHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onBlur()
    }
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 0, height: 1)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.minSize = NSSize(width: 0, height: 24)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.frame = CGRect(x: 0, y: 0, width: 1, height: max(24, measuredHeight))
    textView.allowsUndo = true
    textView.font = font
    context.coordinator.applyMarkdown(text, to: textView, preserveSelection: false)
    textView.layoutManager?.delegate = context.coordinator
    textView.registerForDraggedTypes([.fileURL])

    scrollView.documentView = textView
    context.coordinator.textView = textView
    DispatchQueue.main.async {
      context.coordinator.updateMeasuredHeight()
    }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = scrollView.documentView as? CommandTextView else { return }
    textView.commandHandler = { [weak coordinator = context.coordinator] command in
      coordinator?.handle(command)
    }
    textView.fileDropHandler = { [weak coordinator = context.coordinator] urls, displayOffset in
      guard let coordinator else { return }
      coordinator.parent.onImportFiles(
        urls,
        coordinator.storageOffset(forDisplayOffset: displayOffset)
      )
    }
    textView.attachmentActionHandler = { [weak coordinator = context.coordinator] action in
      coordinator?.handle(action)
    }
    textView.isBlockSelectionActiveProvider = { [weak coordinator = context.coordinator] in
      coordinator?.parent.isBlockSelectionActive ?? false
    }
    textView.focusHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onFocus()
    }
    textView.blurHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onBlur()
    }
    var needsHeightUpdate = false
    if textView.font != font {
      textView.font = font
      textView.typingAttributes = [.font: font]
      needsHeightUpdate = true
    }
    if context.coordinator.currentMarkdown() != text {
      context.coordinator.isApplyingText = true
      context.coordinator.applyMarkdown(text, to: textView, preserveSelection: true)
      context.coordinator.isApplyingText = false
      needsHeightUpdate = true
    }
    if context.coordinator.updateWrappingWidth(from: scrollView) {
      needsHeightUpdate = true
    }
    if needsHeightUpdate || textView.frame.height < 1 {
      context.coordinator.updateMeasuredHeight()
    } else {
      context.coordinator.syncTextViewFrame(height: measuredHeight)
    }
    if isFocused,
      context.coordinator.lastFocusRequestID != focusRequestID
    {
      context.coordinator.applyFocusIfNeeded()
      context.coordinator.lastFocusRequestID = focusRequestID
    }
  }

  final class CommandTextView: NSTextView {
    var commandHandler: ((ProjectOutlineTextCommand) -> Void)?
    var focusHandler: (() -> Void)?
    var blurHandler: (() -> Void)?
    var isBlockSelectionActiveProvider: (() -> Bool)?
    var fileDropHandler: (([URL], Int) -> Void)?
    var attachmentActionHandler: ((ProjectOutlineAttachmentTextAction) -> Void)?
    private var lastSelectAllDate: Date?
    private var contextAttachment: ProjectOutlineInlineAttachment?

    override func mouseDown(with event: NSEvent) {
      focusHandler?()
      if let attachment = attachment(at: event) {
        attachmentActionHandler?(.open(attachment))
        return
      }
      super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
      guard let attachment = attachment(at: event) else {
        return super.menu(for: event)
      }
      contextAttachment = attachment
      let menu = NSMenu()
      let openItem = menu.addItem(
        withTitle: "열기",
        action: #selector(openContextAttachment),
        keyEquivalent: ""
      )
      openItem.target = self
      let renameItem = menu.addItem(
        withTitle: "이름 변경",
        action: #selector(renameContextAttachment),
        keyEquivalent: ""
      )
      renameItem.target = self
      menu.addItem(.separator())
      let deleteItem = menu.addItem(
        withTitle: "삭제",
        action: #selector(deleteContextAttachment),
        keyEquivalent: ""
      )
      deleteItem.target = self
      return menu
    }

    @objc private func openContextAttachment() {
      guard let contextAttachment else { return }
      attachmentActionHandler?(.open(contextAttachment))
    }

    @objc private func renameContextAttachment() {
      guard let contextAttachment else { return }
      attachmentActionHandler?(.rename(contextAttachment))
    }

    @objc private func deleteContextAttachment() {
      guard let contextAttachment else { return }
      attachmentActionHandler?(.delete(contextAttachment))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
      guard fileURLs(from: sender.draggingPasteboard).isEmpty == false else {
        return super.draggingEntered(sender)
      }
      return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
      fileURLs(from: sender.draggingPasteboard).isEmpty == false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
      let urls = fileURLs(from: sender.draggingPasteboard)
      guard !urls.isEmpty else { return false }
      let point = convert(sender.draggingLocation, from: nil)
      let displayOffset = characterIndexForInsertion(at: point)
      fileDropHandler?(urls, displayOffset)
      return true
    }

    override func keyDown(with event: NSEvent) {
      guard !hasMarkedText() else {
        super.keyDown(with: event)
        return
      }

      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let isCommand = modifiers.contains(.command)
      let isShift = modifiers.contains(.shift)
      let hasNavigationModifier = isCommand || isShift || modifiers.contains(.option)
        || modifiers.contains(.control)
      let key = event.charactersIgnoringModifiers

      if isBlockSelectionActiveProvider?() == true {
        switch event.keyCode {
        case 126 where isCommand && isShift:
          commandHandler?(.commandShiftUp)
        case 125 where isCommand && isShift:
          commandHandler?(.commandShiftDown)
        case 126 where isShift:
          commandHandler?(.extendBlockSelectionUp)
        case 125 where isShift:
          commandHandler?(.extendBlockSelectionDown)
        case 126:
          commandHandler?(.exitBlockSelectionUp)
        case 125:
          commandHandler?(.exitBlockSelectionDown)
        case 123:
          commandHandler?(.exitBlockSelectionLeft)
        case 124:
          commandHandler?(.exitBlockSelectionRight)
        case 51, 117:
          commandHandler?(.deleteBlockSelection)
        case 53:
          commandHandler?(.clearBlockSelection)
        default:
          super.keyDown(with: event)
        }
        return
      }

      if isCommand, key == "a" {
        let now = Date()
        if let lastSelectAllDate, now.timeIntervalSince(lastSelectAllDate) < 0.8 {
          self.lastSelectAllDate = nil
          setSelectedRange(NSRange(location: 0, length: 0))
          commandHandler?(.selectAllVisibleBlocks)
        } else {
          lastSelectAllDate = now
          selectAll(nil)
        }
        return
      }

      if isCommand, key == "." {
        commandHandler?(.zoomIn)
        return
      }
      if isCommand, key == "," {
        commandHandler?(.zoomOut)
        return
      }
      if isCommand, key == "'" {
        commandHandler?(.zoomHome)
        return
      }
      if isCommand, isShift, key == "[" {
        commandHandler?(.zoomPreviousSibling)
        return
      }
      if isCommand, isShift, key == "]" {
        commandHandler?(.zoomNextSibling)
        return
      }

      switch event.keyCode {
      case 36 where isCommand, 76 where isCommand:
        commandHandler?(.commandEnter)
      case 36 where !isShift, 76 where !isShift:
        commandHandler?(.enter(offset: selectedRange().location))
      case 48 where isShift:
        commandHandler?(.shiftTab)
      case 48:
        commandHandler?(.tab)
      case 49
        where ProjectOutlineCheckboxInputPolicy.shouldConvertToTask(
          text: string,
          selectedRange: selectedRange()
        ):
        commandHandler?(.convertToTask)
      case 51 where selectedRange().location == 0 && selectedRange().length == 0:
        commandHandler?(.backspaceAtStart)
      case 117 where selectedRange().location == string.utf16.count && selectedRange().length == 0:
        commandHandler?(.deleteAtEnd)
      case 123 where !hasNavigationModifier && selectedRange().location == 0 && selectedRange().length == 0:
        commandHandler?(.focusPrevious)
      case 124
        where !hasNavigationModifier && selectedRange().location == string.utf16.count
          && selectedRange().length == 0:
        commandHandler?(.focusNext)
      case 126
        where isShift && !isCommand && selectedRange().location == 0:
        commandHandler?(.extendBlockSelectionUp)
      case 125
        where isShift && !isCommand && selectedRange().location + selectedRange().length
          == string.utf16.count:
        commandHandler?(.extendBlockSelectionDown)
      case 126 where isCommand && isShift:
        commandHandler?(.commandShiftUp)
      case 125 where isCommand && isShift:
        commandHandler?(.commandShiftDown)
      case 126 where isCommand:
        commandHandler?(.commandUp)
      case 125 where isCommand:
        commandHandler?(.commandDown)
      case 126 where selectedRange().location == 0 && selectedRange().length == 0:
        commandHandler?(.focusPrevious)
      case 125 where selectedRange().location == string.utf16.count && selectedRange().length == 0:
        commandHandler?(.focusNext)
      case 53:
        commandHandler?(.escape)
      default:
        super.keyDown(with: event)
      }
    }

    override func insertNewline(_ sender: Any?) {
      guard !hasMarkedText() else {
        super.insertNewline(sender)
        return
      }
      commandHandler?(.enter(offset: selectedRange().location))
    }

    private func attachment(at event: NSEvent) -> ProjectOutlineInlineAttachment? {
      let point = convert(event.locationInWindow, from: nil)
      let index = characterIndexForInsertion(at: point)
      return attachment(near: index)
    }

    private func attachment(near index: Int) -> ProjectOutlineInlineAttachment? {
      guard textStorage?.length ?? 0 > 0 else { return nil }
      let length = textStorage?.length ?? 0
      let candidates = [index, index - 1].filter { $0 >= 0 && $0 < length }
      for candidate in candidates {
        if let attachment = textStorage?.attribute(
          ProjectOutlineAttachmentInlineCodec.attachmentAttribute,
          at: candidate,
          effectiveRange: nil
        ) as? ProjectOutlineInlineAttachment {
          return attachment
        }
      }
      return nil
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
      let options: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
      ]
      return pasteboard
        .readObjects(forClasses: [NSURL.self], options: options)?
        .compactMap { object in
          if let url = object as? URL {
            return url
          }
          if let url = object as? NSURL {
            return url as URL
          }
          return nil
        }
        ?? []
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSLayoutManagerDelegate {
    var parent: ProjectOutlineTextEditor
    weak var textView: CommandTextView?
    var isApplyingText = false
    var lastFocusRequestID: UInt64 = 0
    private var isMeasuringHeight = false

    init(parent: ProjectOutlineTextEditor) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingText, let textView = notification.object as? NSTextView else { return }
      parent.text = ProjectOutlineAttachmentInlineCodec.markdown(from: textView.attributedString())
      updateMeasuredHeight()
    }

    func handle(_ command: ProjectOutlineTextCommand) {
      switch command {
      case .enter(let offset):
        parent.onCommand(.enter(offset: storageOffset(forDisplayOffset: offset)))
      default:
        parent.onCommand(command)
      }
    }

    func handle(_ action: ProjectOutlineAttachmentTextAction) {
      switch action {
      case .open(let attachment):
        parent.onOpenAttachment(attachment)
      case .rename(let attachment):
        parent.onRenameAttachment(attachment)
      case .delete(let attachment):
        parent.onDeleteAttachment(attachment)
      }
    }

    func currentMarkdown() -> String {
      guard let textView else { return parent.text }
      return ProjectOutlineAttachmentInlineCodec.markdown(from: textView.attributedString())
    }

    func applyMarkdown(
      _ markdown: String,
      to textView: NSTextView,
      preserveSelection: Bool
    ) {
      let selectedRange = textView.selectedRange()
      let attributed = ProjectOutlineAttachmentInlineCodec.attributedString(
        from: markdown,
        vaultRootURL: parent.vaultRootURL,
        font: parent.font
      )
      textView.textStorage?.setAttributedString(attributed)
      textView.typingAttributes = [.font: parent.font, .foregroundColor: NSColor.labelColor]
      guard preserveSelection else { return }
      let clampedLocation = min(selectedRange.location, attributed.length)
      let clampedLength = min(selectedRange.length, max(0, attributed.length - clampedLocation))
      textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
    }

    func storageOffset(forDisplayOffset displayOffset: Int) -> Int {
      guard let textView else { return displayOffset }
      let attributed = textView.attributedString()
      let displayLimit = min(max(0, displayOffset), attributed.length)
      var storageOffset = 0
      var index = 0
      while index < displayLimit {
        if let attachment = attributed.attribute(
          ProjectOutlineAttachmentInlineCodec.attachmentAttribute,
          at: index,
          effectiveRange: nil
        ) as? ProjectOutlineInlineAttachment {
          storageOffset += (ProjectOutlineAttachmentInlineCodec.markdownLink(for: attachment) as NSString)
            .length
        } else {
          let value = attributed.attributedSubstring(from: NSRange(location: index, length: 1)).string
          storageOffset += (value as NSString).length
        }
        index += 1
      }
      return storageOffset
    }

    func textDidBeginEditing(_ notification: Notification) {
      parent.onFocus()
    }

    func textDidEndEditing(_ notification: Notification) {
      parent.onBlur()
    }

    func layoutManager(
      _ layoutManager: NSLayoutManager,
      didCompleteLayoutFor textContainer: NSTextContainer?,
      atEnd layoutFinishedFlag: Bool
    ) {
      guard layoutFinishedFlag else { return }
      updateMeasuredHeight(ensureLayout: false)
    }

    func updateMeasuredHeight(ensureLayout: Bool = true) {
      guard !isMeasuringHeight else { return }
      guard let textView else { return }
      isMeasuringHeight = true
      defer { isMeasuringHeight = false }
      _ = updateWrappingWidth(from: textView.enclosingScrollView)
      guard let textContainer = textView.textContainer else { return }
      if ensureLayout {
        textView.layoutManager?.ensureLayout(for: textContainer)
      }
      let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
      let height = max(24, ceil(usedRect.height + textView.textContainerInset.height * 2 + 2))
      syncTextViewFrame(height: height)
      if abs(parent.measuredHeight - height) > 0.5 {
        parent.measuredHeight = height
      }
      if let scrollView = textView.enclosingScrollView,
        scrollView.contentView.bounds.origin.y != 0
      {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }

    func syncTextViewFrame(height: CGFloat) {
      guard let textView else { return }
      let width = max(1, textView.enclosingScrollView?.contentSize.width ?? textView.frame.width)
      if abs(textView.frame.width - width) > 0.5 || abs(textView.frame.height - height) > 0.5 {
        textView.frame = CGRect(x: 0, y: 0, width: width, height: height)
      }
      textView.needsDisplay = true
      textView.enclosingScrollView?.needsDisplay = true
    }

    func updateWrappingWidth(from scrollView: NSScrollView?) -> Bool {
      guard let textView, let textContainer = textView.textContainer else { return false }
      let width = max(1, scrollView?.contentSize.width ?? textView.bounds.width)
      if abs(textContainer.containerSize.width - width) > 0.5 {
        textContainer.containerSize = NSSize(
          width: width,
          height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame.size.width = width
        return true
      }
      syncTextViewFrame(height: max(24, parent.measuredHeight))
      return false
    }

    func applyFocusIfNeeded() {
      guard let textView else { return }
      guard let window = textView.window else {
        DispatchQueue.main.async { [weak self] in
          self?.applyFocusIfNeeded()
        }
        return
      }
      if window.firstResponder !== textView {
        window.makeFirstResponder(textView)
      }
      applyFocusPlacement(to: textView)
    }

    private func applyFocusPlacement(to textView: NSTextView) {
      switch parent.focusPlacement {
      case .preserve:
        return
      case .start:
        textView.setSelectedRange(NSRange(location: 0, length: 0))
      case .end:
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
      }
    }
  }
}

enum ProjectOutlineCheckboxInputPolicy {
  static func shouldConvertToTask(text: String, selectedRange: NSRange) -> Bool {
    guard selectedRange.length == 0 else { return false }
    let nsText = text as NSString
    guard selectedRange.location == nsText.length else { return false }
    let prefix = nsText.substring(to: selectedRange.location)
    return prefix == "[]" || prefix == "[ ]"
  }
}
