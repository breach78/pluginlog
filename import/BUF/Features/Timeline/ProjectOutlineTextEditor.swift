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
}

struct ProjectOutlineTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var measuredHeight: CGFloat

  let isFocused: Bool
  let font: NSFont
  let onCommand: (ProjectOutlineTextCommand) -> Void
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
      coordinator?.parent.onCommand(command)
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
    textView.allowsUndo = true
    textView.font = font
    textView.string = text

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
      coordinator?.parent.onCommand(command)
    }
    textView.focusHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onFocus()
    }
    textView.blurHandler = { [weak coordinator = context.coordinator] in
      coordinator?.parent.onBlur()
    }
    if textView.font != font {
      textView.font = font
      textView.typingAttributes = [.font: font]
    }
    if textView.string != text {
      context.coordinator.isApplyingText = true
      textView.string = text
      context.coordinator.isApplyingText = false
    }
    context.coordinator.updateWrappingWidth(from: scrollView)
    context.coordinator.updateMeasuredHeight()
    if isFocused, !context.coordinator.lastIsFocused {
      context.coordinator.applyFocusIfNeeded()
    }
    context.coordinator.lastIsFocused = isFocused
  }

  final class CommandTextView: NSTextView {
    var commandHandler: ((ProjectOutlineTextCommand) -> Void)?
    var focusHandler: (() -> Void)?
    var blurHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
      focusHandler?()
      super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
      guard !hasMarkedText() else {
        super.keyDown(with: event)
        return
      }

      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let isCommand = modifiers.contains(.command)
      let isShift = modifiers.contains(.shift)
      let key = event.charactersIgnoringModifiers

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
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ProjectOutlineTextEditor
    weak var textView: CommandTextView?
    var isApplyingText = false
    var lastIsFocused = false

    init(parent: ProjectOutlineTextEditor) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingText, let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      updateMeasuredHeight()
    }

    func textDidBeginEditing(_ notification: Notification) {
      parent.onFocus()
    }

    func textDidEndEditing(_ notification: Notification) {
      parent.onBlur()
    }

    func updateMeasuredHeight() {
      guard let textView else { return }
      updateWrappingWidth(from: textView.enclosingScrollView)
      guard let textContainer = textView.textContainer else { return }
      textView.layoutManager?.ensureLayout(for: textContainer)
      let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
      let height = max(24, ceil(usedRect.height + textView.textContainerInset.height * 2 + 2))
      if abs(parent.measuredHeight - height) > 0.5 {
        parent.measuredHeight = height
      }
    }

    func updateWrappingWidth(from scrollView: NSScrollView?) {
      guard let textView, let textContainer = textView.textContainer else { return }
      let width = max(1, scrollView?.contentSize.width ?? textView.bounds.width)
      if abs(textContainer.containerSize.width - width) > 0.5 {
        textContainer.containerSize = NSSize(
          width: width,
          height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame.size.width = width
      }
    }

    func applyFocusIfNeeded() {
      guard let textView, let window = textView.window else { return }
      guard window.firstResponder !== textView else { return }
      window.makeFirstResponder(textView)
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
