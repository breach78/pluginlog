import AppKit
import SwiftUI

extension NSUserInterfaceItemIdentifier {
  static let workspaceSearchField = NSUserInterfaceItemIdentifier(
    "workspaceSearchField")
}

/// AppKit-backed search field so arrow and escape keys can be intercepted before SwiftUI consumes them.
struct WorkspaceSearchInputField: NSViewRepresentable {
  @Binding var text: String
  @Binding var isFocused: Bool
  let focusRequestID: Int
  let placeholder: String
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onSubmit: () -> Void
  let onEscape: () -> Void

  final class FocusAwareTextField: NSTextField {
    var onUserFocusAttempt: (() -> Void)?
    var onFocusEnded: (() -> Void)?
    private var allowsNextFocusAcquisition = false

    override var acceptsFirstResponder: Bool {
      allowsNextFocusAcquisition
        || window?.firstResponder === self
        || window?.firstResponder === currentEditor()
    }

    func allowProgrammaticFocus() {
      allowsNextFocusAcquisition = true
    }

    override func mouseDown(with event: NSEvent) {
      allowsNextFocusAcquisition = true
      onUserFocusAttempt?()
      super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
      let isAlreadyFirstResponder =
        window?.firstResponder === self || window?.firstResponder === currentEditor()
      guard allowsNextFocusAcquisition || isAlreadyFirstResponder else {
        return false
      }

      let didBecomeFirstResponder = super.becomeFirstResponder()
      allowsNextFocusAcquisition = false
      return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
      allowsNextFocusAcquisition = false
      let didResign = super.resignFirstResponder()
      if didResign {
        onFocusEnded?()
      }
      return didResign
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: WorkspaceSearchInputField
    var hasPendingUserFocusAttempt = false
    var lastAppliedFocusRequestID = 0

    init(parent: WorkspaceSearchInputField) {
      self.parent = parent
    }

    func registerUserFocusAttempt() {
      hasPendingUserFocusAttempt = true
      if !parent.isFocused {
        parent.isFocused = true
      }
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
      guard parent.isFocused || hasPendingUserFocusAttempt else {
        if let field = obj.object as? NSTextField {
          field.window?.makeFirstResponder(nil)
        }
        return
      }
      if !parent.isFocused {
        parent.isFocused = true
      }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
      hasPendingUserFocusAttempt = false
      if parent.isFocused {
        parent.isFocused = false
      }
    }

    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSTextField else { return }
      if parent.text != field.stringValue {
        parent.text = field.stringValue
      }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
      -> Bool
    {
      switch commandSelector {
      case #selector(NSResponder.moveUp(_:)):
        parent.onMoveUp()
        return true
      case #selector(NSResponder.moveDown(_:)):
        parent.onMoveDown()
        return true
      case #selector(NSResponder.insertNewline(_:)):
        parent.onSubmit()
        return true
      case #selector(NSResponder.cancelOperation(_:)):
        parent.onEscape()
        return true
      default:
        return false
      }
    }

    func isFirstResponder(for field: NSTextField, in window: NSWindow) -> Bool {
      window.firstResponder === field || window.firstResponder === field.currentEditor()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> FocusAwareTextField {
    let field = FocusAwareTextField()
    field.delegate = context.coordinator
    field.identifier = .workspaceSearchField
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.isBezeled = false
    field.isEditable = true
    field.isSelectable = true
    field.font = AppInputTypography.nsFont(size: AppInputTypography.defaultPointSize)
    field.placeholderString = placeholder
    field.stringValue = text
    field.onUserFocusAttempt = { [weak coordinator = context.coordinator] in
      coordinator?.registerUserFocusAttempt()
    }
    field.onFocusEnded = { [weak coordinator = context.coordinator] in
      coordinator?.hasPendingUserFocusAttempt = false
    }
    return field
  }

  func updateNSView(_ field: FocusAwareTextField, context: Context) {
    context.coordinator.parent = self
    let targetFont = AppInputTypography.nsFont(size: AppInputTypography.defaultPointSize)
    if field.font?.fontName != targetFont.fontName
      || abs((field.font?.pointSize ?? 0) - targetFont.pointSize) > 0.5
    {
      field.font = targetFont
    }

    if field.stringValue != text {
      field.stringValue = text
    }

    if field.placeholderString != placeholder {
      field.placeholderString = placeholder
    }

    guard let window = field.window else { return }

    let isFirstResponderForField =
      context.coordinator.isFirstResponder(for: field, in: window)

    if !isFocused && isFirstResponderForField {
      window.makeFirstResponder(nil)
      return
    }

    guard isFocused, !isFirstResponderForField else { return }
    guard context.coordinator.lastAppliedFocusRequestID != focusRequestID else { return }

    context.coordinator.lastAppliedFocusRequestID = focusRequestID
    field.allowProgrammaticFocus()
    if window.makeFirstResponder(field) {
      field.currentEditor()?.selectedRange = NSRange(
        location: 0,
        length: field.stringValue.utf16.count
      )
    }
  }
}

struct WorkspaceSearchFieldFramePreferenceKey: PreferenceKey {
  static let defaultValue: CGRect? = nil

  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
    value = nextValue() ?? value
  }
}

struct EscapeAwareTextField: NSViewRepresentable {
  @Binding var text: String
  @Binding var isFocused: Bool
  let placeholder: String
  let onSubmit: () -> Void
  let onEscape: () -> Void

  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: EscapeAwareTextField
    var pendingFocusWorkItem: DispatchWorkItem?

    init(parent: EscapeAwareTextField) {
      self.parent = parent
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
      pendingFocusWorkItem?.cancel()
      if !parent.isFocused {
        parent.isFocused = true
      }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
      pendingFocusWorkItem?.cancel()
      if parent.isFocused {
        parent.isFocused = false
      }
    }

    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSTextField else { return }
      if parent.text != field.stringValue {
        parent.text = field.stringValue
      }
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      switch commandSelector {
      case #selector(NSResponder.insertNewline(_:)):
        parent.onSubmit()
        return true
      case #selector(NSResponder.cancelOperation(_:)):
        parent.onEscape()
        return true
      default:
        return false
      }
    }

    func isFirstResponder(for field: NSTextField, in window: NSWindow) -> Bool {
      window.firstResponder === field || window.firstResponder === field.currentEditor()
    }

    func scheduleFocusApplication(for field: NSTextField, attempt: Int = 0) {
      pendingFocusWorkItem?.cancel()

      let work = DispatchWorkItem { [weak self, weak field] in
        guard let self, let field else { return }
        self.applyFocusIfPossible(for: field, attempt: attempt)
      }

      pendingFocusWorkItem = work
      DispatchQueue.main.async(execute: work)
    }

    private func applyFocusIfPossible(for field: NSTextField, attempt: Int) {
      guard parent.isFocused else { return }

      guard let window = field.window else {
        retryFocusApplication(for: field, attempt: attempt)
        return
      }

      if !window.isKeyWindow {
        window.makeKeyAndOrderFront(nil)
      }

      if !isFirstResponder(for: field, in: window) {
        let didFocus = window.makeFirstResponder(field)
        if !didFocus {
          retryFocusApplication(for: field, attempt: attempt)
          return
        }
      }

      if let editor = field.currentEditor() as? NSTextView {
        let length = (field.stringValue as NSString).length
        let selection = NSRange(location: length, length: 0)
        editor.setSelectedRange(selection)
        editor.scrollRangeToVisible(selection)
      }
    }

    private func retryFocusApplication(for field: NSTextField, attempt: Int) {
      guard attempt < 8 else { return }

      pendingFocusWorkItem?.cancel()
      let work = DispatchWorkItem { [weak self, weak field] in
        guard let self, let field else { return }
        self.applyFocusIfPossible(for: field, attempt: attempt + 1)
      }

      pendingFocusWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16), execute: work)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField()
    field.delegate = context.coordinator
    field.isBordered = true
    field.isBezeled = true
    field.drawsBackground = true
    field.focusRingType = .default
    field.isEditable = true
    field.isSelectable = true
    field.font = AppInputTypography.nsFont(size: AppInputTypography.defaultPointSize)
    field.placeholderString = placeholder
    field.stringValue = text
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.parent = self
    let targetFont = AppInputTypography.nsFont(size: AppInputTypography.defaultPointSize)
    if field.font?.fontName != targetFont.fontName
      || abs((field.font?.pointSize ?? 0) - targetFont.pointSize) > 0.5
    {
      field.font = targetFont
    }

    if field.stringValue != text {
      field.stringValue = text
    }

    if field.placeholderString != placeholder {
      field.placeholderString = placeholder
    }

    if isFocused {
      if let window = field.window {
        let isFirstResponder = context.coordinator.isFirstResponder(for: field, in: window)
        if !isFirstResponder {
          context.coordinator.scheduleFocusApplication(for: field)
        }
      } else {
        context.coordinator.scheduleFocusApplication(for: field)
      }
      return
    }

    context.coordinator.pendingFocusWorkItem?.cancel()
    guard let window = field.window else { return }
    let isFirstResponder = context.coordinator.isFirstResponder(for: field, in: window)
    if isFirstResponder {
      window.makeFirstResponder(nil)
    }
  }
}
