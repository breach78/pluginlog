import AppKit

@MainActor
enum WorkspaceTextResponderReleasePolicy {
  static func shouldReleaseTextResponder(
    hasActiveEditPanel: Bool,
    firstResponder: NSResponder?,
    mouseHitView: NSView?
  ) -> Bool {
    guard hasActiveEditPanel, isTextResponder(firstResponder) else { return false }
    guard let responderView = firstResponder as? NSView, let mouseHitView else {
      return true
    }
    if let scrollView = responderView.enclosingScrollView,
      isView(mouseHitView, inside: scrollView)
    {
      return false
    }
    return !isView(mouseHitView, inside: responderView)
  }

  static func isTextResponder(_ responder: NSResponder?) -> Bool {
    responder is NSTextView || responder is NSTextField
  }

  private static func isView(_ view: NSView, inside ancestor: NSView) -> Bool {
    var current: NSView? = view
    while let candidate = current {
      if candidate === ancestor {
        return true
      }
      current = candidate.superview
    }
    return false
  }
}
