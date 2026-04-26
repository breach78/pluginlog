import AppKit
import SwiftUI

final class WorkspaceDismissOverlayNSView: NSView {
  var visualExclusionRects: [CGRect] = [] {
    didSet { needsDisplay = true }
  }

  var passthroughRects: [CGRect] = [] {
    didSet { needsDisplay = true }
  }

  var onDismiss: (() -> Void)?
  private var ignoresSelfDuringHitTest = false

  override var isOpaque: Bool { false }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let overlayPath = NSBezierPath(rect: bounds)
    for excludedRect in visualExclusionRects {
      overlayPath.append(
        NSBezierPath(
          roundedRect: excludedRect,
          xRadius: 10,
          yRadius: 10
        )
      )
    }
    if !visualExclusionRects.isEmpty {
      overlayPath.windingRule = .evenOdd
    }

    NSColor.black.withAlphaComponent(0.2).setFill()
    overlayPath.fill()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !ignoresSelfDuringHitTest else { return nil }
    let expandedPassthroughRects = visualExclusionRects + passthroughRects
    if expandedPassthroughRects.contains(where: { $0.contains(point) }) {
      return nil
    }
    return self
  }

  override func mouseDown(with event: NSEvent) {
    onDismiss?()
  }

  override func scrollWheel(with event: NSEvent) {
    guard let underlyingView = underlyingView(at: event.locationInWindow) else {
      super.scrollWheel(with: event)
      return
    }
    underlyingView.scrollWheel(with: event)
  }

  private func underlyingView(at windowLocation: NSPoint) -> NSView? {
    guard let window, let rootView = window.contentView else { return nil }
    let pointInRoot = rootView.convert(windowLocation, from: nil)
    ignoresSelfDuringHitTest = true
    let hitView = rootView.hitTest(pointInRoot)
    ignoresSelfDuringHitTest = false
    guard hitView !== self else { return nil }
    return hitView
  }
}

struct WorkspaceDismissOverlay: NSViewRepresentable {
  let visualExclusionRects: [CGRect]
  let passthroughRects: [CGRect]
  let onDismiss: () -> Void

  func makeNSView(context: Context) -> WorkspaceDismissOverlayNSView {
    let view = WorkspaceDismissOverlayNSView()
    view.onDismiss = onDismiss
    return view
  }

  func updateNSView(_ nsView: WorkspaceDismissOverlayNSView, context: Context) {
    nsView.visualExclusionRects = visualExclusionRects
    nsView.passthroughRects = passthroughRects
    nsView.onDismiss = onDismiss
  }
}

struct WorkspaceViewModePickerFramePreferenceKey: PreferenceKey {
  static let defaultValue: CGRect? = nil

  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
    value = nextValue() ?? value
  }
}
