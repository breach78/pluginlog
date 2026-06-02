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
  case focusPreviousAt(offset: Int)
  case focusNextAt(offset: Int)
  case extendBlockSelectionUp
  case extendBlockSelectionDown
  case exitBlockSelectionUp
  case exitBlockSelectionDown
  case exitBlockSelectionLeft
  case exitBlockSelectionRight
  case clearBlockSelection
  case deleteBlockSelection
  case selectAllVisibleBlocks
  case mergeBackspaceAtStart(text: String)
}

enum ProjectOutlineFocusPlacement {
  case preserve
  case start
  case end
  case offset(Int)
}

enum ProjectOutlineAttachmentTextAction {
  case open(ProjectOutlineInlineAttachment)
  case rename(ProjectOutlineInlineAttachment)
  case delete(ProjectOutlineInlineAttachment)
}

struct ProjectOutlineAttachmentHit: Equatable {
  let attachment: ProjectOutlineInlineAttachment
  let range: NSRange
  let bounds: NSRect
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
  var textColor: NSColor = .labelColor
  let onCommand: (ProjectOutlineTextCommand) -> Void
  var onReveal: () -> Void = {}
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
    textView.vaultRootURL = vaultRootURL
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
    textView.revealHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onReveal()
    }
    textView.blurHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onBlur()
    }
    textView.drawsBackground = false
    textView.isAutomaticLinkDetectionEnabled = false
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
    textView.allowsUndo = false
    textView.font = font
    context.coordinator.applyStorageText(text, to: textView, preserveSelection: false)
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
    textView.vaultRootURL = vaultRootURL
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
    textView.revealHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onReveal()
    }
    textView.blurHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onBlur()
    }
    var needsHeightUpdate = false
    if textView.font != font || !context.coordinator.appliedTextColor.isEqual(textColor) {
      textView.font = font
      textView.typingAttributes = [.font: font, .foregroundColor: textColor]
      context.coordinator.applyStorageText(
        context.coordinator.displayedText,
        to: textView,
        preserveSelection: true
      )
      needsHeightUpdate = true
    }
    if context.coordinator.displayedText != text {
      context.coordinator.isApplyingText = true
      context.coordinator.applyStorageText(text, to: textView, preserveSelection: true)
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
    var revealHandler: (() -> Void)?
    var blurHandler: (() -> Void)?
    var isBlockSelectionActiveProvider: (() -> Bool)?
    var fileDropHandler: (([URL], Int) -> Void)?
    var attachmentActionHandler: ((ProjectOutlineAttachmentTextAction) -> Void)?
    var vaultRootURL: URL?
    private var lastSelectAllDate: Date?
    private var contextAttachment: ProjectOutlineInlineAttachment?
    private var pendingAttachmentMouseDown: (hit: ProjectOutlineAttachmentHit, event: NSEvent)?
    private static let insertionPointWidth: CGFloat = 2

    override func mouseDown(with event: NSEvent) {
      focusHandler?()
      if let hit = attachmentHit(at: event) {
        setSelectedRange(hit.range)
        pendingAttachmentMouseDown = (hit, event)
        return
      }
      pendingAttachmentMouseDown = nil
      super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
      guard let pendingAttachmentMouseDown else {
        super.mouseDragged(with: event)
        return
      }
      let distance = hypot(
        event.locationInWindow.x - pendingAttachmentMouseDown.event.locationInWindow.x,
        event.locationInWindow.y - pendingAttachmentMouseDown.event.locationInWindow.y
      )
      guard distance >= 3 else { return }
      let hit = pendingAttachmentMouseDown.hit
      self.pendingAttachmentMouseDown = nil
      let draggingItem = NSDraggingItem(
        pasteboardWriter: ProjectOutlineAttachmentDragProvider.pasteboardWriter(
          for: hit.attachment
        )
      )
      let image = (textStorage?.attribute(.attachment, at: hit.range.location, effectiveRange: nil)
        as? ProjectOutlineAttachmentTextAttachment)?.image
      draggingItem.setDraggingFrame(hit.bounds, contents: image)
      beginDraggingSession(with: [draggingItem], event: pendingAttachmentMouseDown.event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
      if let pendingAttachmentMouseDown {
        self.pendingAttachmentMouseDown = nil
        attachmentActionHandler?(.open(pendingAttachmentMouseDown.hit.attachment))
        return
      }
      super.mouseUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
      let didResign = super.resignFirstResponder()
      guard didResign else { return false }
      let range = selectedRange()
      if range.length > 0 {
        setSelectedRange(NSRange(location: range.location + range.length, length: 0))
      }
      setNeedsDisplay(bounds)
      return true
    }

    override func drawInsertionPoint(
      in rect: NSRect,
      color: NSColor,
      turnedOn flag: Bool
    ) {
      guard flag, window?.firstResponder === self else { return }
      var insertionRect = rect
      insertionRect.origin.x = max(0, rect.midX - Self.insertionPointWidth / 2)
      insertionRect.size.width = Self.insertionPointWidth
      color.setFill()
      insertionRect.fill()
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
      let caretPadding = Self.insertionPointWidth
      super.setNeedsDisplay(invalidRect.insetBy(dx: -caretPadding, dy: 0))
    }

    override func copy(_ sender: Any?) {
      guard writeSelectedTextToPasteboard() else {
        super.copy(sender)
        return
      }
    }

    override func cut(_ sender: Any?) {
      guard writeSelectedTextToPasteboard() else {
        super.cut(sender)
        return
      }
      replaceCharacters(in: selectedRange(), with: "")
      didChangeText()
    }

    override func paste(_ sender: Any?) {
      guard let string = NSPasteboard.general.string(forType: .string),
        ProjectOutlineAttachmentInlineCodec.containsAttachment(in: string)
      else {
        super.paste(sender)
        return
      }
      let attributed = ProjectOutlineAttachmentInlineCodec.attributedString(
        from: string,
        vaultRootURL: vaultRootURL,
        font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
      )
      textStorage?.replaceCharacters(in: selectedRange(), with: attributed)
      setSelectedRange(NSRange(location: selectedRange().location + attributed.length, length: 0))
      didChangeText()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
      guard let attachment = attachmentHit(at: event)?.attachment else {
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

    override func draggingSession(
      _ session: NSDraggingSession,
      sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
      .copy
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
        revealCaretIfNeeded()
        return
      }

      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let isCommand = modifiers.contains(.command)
      let isShift = modifiers.contains(.shift)
      let isOption = modifiers.contains(.option)
      let hasNavigationModifier = isCommand || isShift || isOption
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
        case 48 where isShift:
          commandHandler?(.shiftTab)
        case 48:
          commandHandler?(.tab)
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
          revealCaretIfNeeded()
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
      case 36 where isCommand || isOption, 76 where isCommand || isOption:
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
      case 126 where !hasNavigationModifier:
        handleVerticalArrowKey(event, movingUp: true)
      case 125 where !hasNavigationModifier:
        handleVerticalArrowKey(event, movingUp: false)
      case 53:
        commandHandler?(.escape)
      default:
        super.keyDown(with: event)
        revealCaretIfNeeded()
      }
    }

    override func insertNewline(_ sender: Any?) {
      guard !hasMarkedText() else {
        super.insertNewline(sender)
        return
      }
      commandHandler?(.enter(offset: selectedRange().location))
    }

    func attachmentHit(at event: NSEvent) -> ProjectOutlineAttachmentHit? {
      let point = convert(event.locationInWindow, from: nil)
      return attachmentHit(at: point)
    }

    func revealCaretIfNeeded() {
      guard window?.firstResponder === self else { return }
      scrollRangeToVisible(selectedRange())
      revealHandler?()
    }

    private func handleVerticalArrowKey(_ event: NSEvent, movingUp: Bool) {
      let beforeRange = selectedRange()
      super.keyDown(with: event)
      let afterRange = selectedRange()
      if NSEqualRanges(beforeRange, afterRange) {
        commandHandler?(movingUp
          ? .focusPreviousAt(offset: beforeRange.location)
          : .focusNextAt(offset: beforeRange.location))
        return
      }
      revealCaretIfNeeded()
    }

    func attachmentHit(at point: NSPoint) -> ProjectOutlineAttachmentHit? {
      guard let layoutManager, let textContainer, textStorage?.length ?? 0 > 0 else {
        return nil
      }
      let containerPoint = NSPoint(
        x: point.x - textContainerOrigin.x,
        y: point.y - textContainerOrigin.y
      )
      let glyphIndex = layoutManager.glyphIndex(
        for: containerPoint,
        in: textContainer,
        fractionOfDistanceThroughGlyph: nil
      )
      guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
      let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
      let candidates = [characterIndex, characterIndex - 1]
        .filter { $0 >= 0 && $0 < (textStorage?.length ?? 0) }
      for candidate in candidates {
        var effectiveRange = NSRange(location: 0, length: 0)
        if let attachment = textStorage?.attribute(
          ProjectOutlineAttachmentInlineCodec.attachmentAttribute,
          at: candidate,
          effectiveRange: &effectiveRange
        ) as? ProjectOutlineInlineAttachment {
          let glyphRange = layoutManager.glyphRange(
            forCharacterRange: effectiveRange,
            actualCharacterRange: nil
          )
          var bounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
          bounds.origin.x += textContainerOrigin.x
          bounds.origin.y += textContainerOrigin.y
          guard bounds.insetBy(dx: -1, dy: -1).contains(point) else { continue }
          return ProjectOutlineAttachmentHit(
            attachment: attachment,
            range: effectiveRange,
            bounds: bounds
          )
        }
      }
      return nil
    }

    private func writeSelectedTextToPasteboard() -> Bool {
      let selectedRange = selectedRange()
      guard selectedRange.length > 0,
        let selected = textStorage?.attributedSubstring(from: selectedRange)
      else {
        return false
      }
      let storageText = ProjectOutlineAttachmentInlineCodec.storageText(from: selected)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(storageText, forType: .string)
      return true
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
    var displayedText: String
    var appliedTextColor: NSColor
    private var isMeasuringHeight = false
    private var lastLinkedText: String?
    private var lastMeasuredText: String?
    private var lastMeasuredContainerWidth: CGFloat = 0

    init(parent: ProjectOutlineTextEditor) {
      self.parent = parent
      self.displayedText = parent.text
      self.appliedTextColor = parent.textColor
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingText, let textView = notification.object as? NSTextView else { return }
      let nextText: String
      if ProjectOutlineAttachmentInlineCodec.containsAttachment(in: textView.attributedString()) {
        nextText = ProjectOutlineAttachmentInlineCodec.storageText(from: textView.attributedString())
      } else {
        nextText = textView.string
      }
      displayedText = nextText
      parent.text = nextText
      applyLinkAttributes(to: textView)
      updateMeasuredHeight()
      (textView as? CommandTextView)?.revealCaretIfNeeded()
    }

    func handle(_ command: ProjectOutlineTextCommand) {
      switch command {
      case .enter(let offset):
        parent.onCommand(.enter(offset: storageOffset(forDisplayOffset: offset)))
      case .backspaceAtStart:
        parent.onCommand(.mergeBackspaceAtStart(text: currentStorageText()))
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

    func currentStorageText() -> String {
      guard let textView else { return parent.text }
      let storageText: String
      if ProjectOutlineAttachmentInlineCodec.containsAttachment(in: textView.attributedString()) {
        storageText = ProjectOutlineAttachmentInlineCodec.storageText(from: textView.attributedString())
      } else {
        storageText = textView.string
      }
      displayedText = storageText
      return storageText
    }

    func applyStorageText(
      _ storageText: String,
      to textView: NSTextView,
      preserveSelection: Bool
    ) {
      let selectedRange = textView.selectedRange()
      let attributed = ProjectOutlineAttachmentInlineCodec.attributedString(
        from: storageText,
        vaultRootURL: parent.vaultRootURL,
        font: parent.font,
        textColor: parent.textColor
      )
      invalidateMeasurementCache()
      textView.textStorage?.setAttributedString(attributed)
      textView.layoutManager?.invalidateLayout(
        forCharacterRange: NSRange(location: 0, length: attributed.length),
        actualCharacterRange: nil
      )
      textView.typingAttributes = [.font: parent.font, .foregroundColor: parent.textColor]
      appliedTextColor = parent.textColor
      applyLinkAttributes(to: textView)
      displayedText = storageText
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

    func textView(
      _ textView: NSTextView,
      clickedOnLink link: Any,
      at charIndex: Int
    ) -> Bool {
      guard let url = link as? URL else { return false }
      NSWorkspace.shared.open(url)
      return true
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
      let widthChanged = updateWrappingWidth(from: textView.enclosingScrollView)
      guard let textContainer = textView.textContainer else { return }
      let containerWidth = textContainer.containerSize.width
      if !ensureLayout,
        !widthChanged,
        lastMeasuredText == textView.string,
        abs(lastMeasuredContainerWidth - containerWidth) <= 0.5
      {
        return
      }
      if ensureLayout || widthChanged {
        textView.layoutManager?.ensureLayout(for: textContainer)
      }
      let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
      let height = max(24, ceil(usedRect.height + textView.textContainerInset.height * 2 + 2))
      lastMeasuredText = textView.string
      lastMeasuredContainerWidth = containerWidth
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
      let nextFrame = CGRect(x: 0, y: 0, width: width, height: height)
      guard abs(textView.frame.origin.x - nextFrame.origin.x) > 0.5
        || abs(textView.frame.origin.y - nextFrame.origin.y) > 0.5
        || abs(textView.frame.width - nextFrame.width) > 0.5
        || abs(textView.frame.height - nextFrame.height) > 0.5
      else { return }
      textView.frame = nextFrame
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
        if abs(textView.frame.width - width) > 0.5 {
          textView.frame.size.width = width
        }
        return true
      }
      return false
    }

    private func invalidateMeasurementCache() {
      lastMeasuredText = nil
      lastMeasuredContainerWidth = 0
    }

    private func applyLinkAttributes(to textView: NSTextView) {
      guard let storage = textView.textStorage else { return }
      let fullRange = NSRange(location: 0, length: storage.length)
      guard fullRange.length > 0 else {
        lastLinkedText = nil
        return
      }
      let text = storage.string
      guard text.contains("://") else {
        guard lastLinkedText != nil else { return }
        storage.beginEditing()
        storage.removeAttribute(.link, range: fullRange)
        storage.removeAttribute(.underlineStyle, range: fullRange)
        storage.removeAttribute(.foregroundColor, range: fullRange)
        storage.addAttributes(
          [.font: parent.font, .foregroundColor: parent.textColor],
          range: fullRange
        )
        storage.endEditing()
        lastLinkedText = nil
        textView.typingAttributes = [.font: parent.font, .foregroundColor: parent.textColor]
        return
      }
      guard lastLinkedText != text else { return }
      storage.beginEditing()
      storage.removeAttribute(.link, range: fullRange)
      storage.removeAttribute(.underlineStyle, range: fullRange)
      storage.removeAttribute(.foregroundColor, range: fullRange)
      storage.addAttributes(
        [.font: parent.font, .foregroundColor: parent.textColor],
        range: fullRange
      )
      let plainText = storage.string as NSString
      for match in Self.linkRegex.matches(in: text, range: fullRange) {
        let matchedText = plainText.substring(with: match.range)
        guard let url = Self.linkURL(from: matchedText) else { continue }
        storage.addAttributes(
          [
            .link: url,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
          ],
          range: match.range
        )
      }
      storage.endEditing()
      lastLinkedText = text
      textView.typingAttributes = [.font: parent.font, .foregroundColor: parent.textColor]
    }

    private static let linkRegex = try! NSRegularExpression(
      pattern: #"\b[A-Za-z][A-Za-z0-9+.-]*://[^\s<>()]+"#
    )

    private static func linkURL(from rawText: String) -> URL? {
      let trimmed = rawText.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
      return URL(string: trimmed)
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
      textView.revealCaretIfNeeded()
    }

    private func applyFocusPlacement(to textView: NSTextView) {
      switch parent.focusPlacement {
      case .preserve:
        return
      case .start:
        textView.setSelectedRange(NSRange(location: 0, length: 0))
      case .end:
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
      case .offset(let offset):
        let clampedOffset = max(0, min(offset, textView.string.utf16.count))
        textView.setSelectedRange(NSRange(location: clampedOffset, length: 0))
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
