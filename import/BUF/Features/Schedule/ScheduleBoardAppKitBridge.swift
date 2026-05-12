import AppKit
import SwiftUI

final class FlippedScheduleDocumentView: NSView {
  override var isFlipped: Bool { true }
}

final class FlippedScheduleClipView: NSClipView {
  override var isFlipped: Bool { true }

  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    guard let documentView else {
      return super.constrainBoundsRect(proposedBounds)
    }

    var constrained = proposedBounds
    let documentFrame = documentView.frame
    let maxX = max(0, documentFrame.width - constrained.width)
    let maxY = max(0, documentFrame.height - constrained.height)

    constrained.origin.x = min(max(0, constrained.origin.x), maxX)
    constrained.origin.y = min(max(0, constrained.origin.y), maxY)
    return constrained
  }
}

final class ScrollPassthroughScheduleHostingView<Content: View>: NSHostingView<Content> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    super.hitTest(point)
  }
}

final class HorizontalPassthroughScheduleScrollView: NSScrollView {
  weak var horizontalScrollTarget: SnappingScheduleScrollView?

  private enum ScrollAxisLock {
    case horizontal
    case vertical
  }

  private var activeAxisLock: ScrollAxisLock?

  private var canScrollVerticallyLocally: Bool {
    guard let documentView else { return false }
    return documentView.frame.height - contentView.bounds.height > 0.5
  }

  override func scrollWheel(with event: NSEvent) {
    if event.phase.contains(.began) {
      activeAxisLock = nil
    }

    let horizontalMagnitude = abs(event.scrollingDeltaX)
    let verticalMagnitude = abs(event.scrollingDeltaY)

    guard horizontalMagnitude > 0.5 || verticalMagnitude > 0.5 else {
      resetAxisLockIfNeeded(for: event)
      super.scrollWheel(with: event)
      return
    }

    switch resolvedAxisLock(
      horizontalMagnitude: horizontalMagnitude,
      verticalMagnitude: verticalMagnitude
    ) {
    case .vertical:
      guard canScrollVerticallyLocally else { break }
      if let sanitizedEvent = sanitizedScrollEvent(from: event, zeroHorizontalAxis: true) {
        super.scrollWheel(with: sanitizedEvent)
      } else {
        super.scrollWheel(with: event)
      }
    case .horizontal:
      guard let horizontalScrollTarget else { break }
      // Cancel any snap that fired prematurely before momentum arrived
      if horizontalScrollTarget.isSnapping {
        horizontalScrollTarget.cancelSnap()
      }
      scrollHorizontally(
        horizontalScrollTarget,
        contentDelta: horizontalContentDelta(from: event)
      )
    }

    resetAxisLockIfNeeded(for: event)
  }

  private func resolvedAxisLock(
    horizontalMagnitude: CGFloat,
    verticalMagnitude: CGFloat
  ) -> ScrollAxisLock {
    if let activeAxisLock {
      return activeAxisLock
    }

    let resolved: ScrollAxisLock
    if canScrollVerticallyLocally, verticalMagnitude > horizontalMagnitude {
      resolved = .vertical
    } else {
      resolved = .horizontal
    }
    activeAxisLock = resolved
    return resolved
  }

  private func resetAxisLockIfNeeded(for event: NSEvent) {
    let gestureEnded = event.phase.contains(.ended) || event.phase.contains(.cancelled)
    let momentumEnded =
      event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
    let hasActiveMomentum =
      !event.momentumPhase.isEmpty
      && !event.momentumPhase.contains(.ended)
      && !event.momentumPhase.contains(.cancelled)

    if momentumEnded || (gestureEnded && !hasActiveMomentum) {
      if activeAxisLock == .horizontal {
        horizontalScrollTarget?.notifyExternalHorizontalScrollEnded()
      }
      activeAxisLock = nil
    }
  }

  private func horizontalContentDelta(from event: NSEvent) -> CGFloat {
    event.isDirectionInvertedFromDevice ? -event.scrollingDeltaX : event.scrollingDeltaX
  }

  private func scrollHorizontally(_ scrollView: NSScrollView, contentDelta: CGFloat) {
    guard let documentView = scrollView.documentView else { return }

    let clipView = scrollView.contentView
    let bounds = clipView.bounds
    let maxX = max(0, documentView.frame.width - bounds.width)
    let targetX = min(max(0, bounds.origin.x + contentDelta), maxX)

    guard abs(targetX - bounds.origin.x) > 0.01 else { return }

    clipView.scroll(to: CGPoint(x: targetX, y: bounds.origin.y))
    scrollView.reflectScrolledClipView(clipView)
  }

  private func sanitizedScrollEvent(
    from event: NSEvent,
    zeroHorizontalAxis: Bool = false,
    zeroVerticalAxis: Bool = false
  ) -> NSEvent? {
    guard let cgEvent = event.cgEvent?.copy() else { return nil }

    if zeroVerticalAxis {
      zeroScrollAxis(1, in: cgEvent)
    }
    if zeroHorizontalAxis {
      zeroScrollAxis(2, in: cgEvent)
    }

    return NSEvent(cgEvent: cgEvent)
  }

  private func zeroScrollAxis(_ axis: Int, in event: CGEvent) {
    let fields: [CGEventField]
    switch axis {
    case 1:
      fields = [
        .scrollWheelEventDeltaAxis1,
        .scrollWheelEventFixedPtDeltaAxis1,
        .scrollWheelEventPointDeltaAxis1
      ]
    case 2:
      fields = [
        .scrollWheelEventDeltaAxis2,
        .scrollWheelEventFixedPtDeltaAxis2,
        .scrollWheelEventPointDeltaAxis2
      ]
    default:
      return
    }

    for field in fields {
      event.setIntegerValueField(field, value: 0)
    }
  }
}

enum ScheduleDateBoundarySnapPolicy {
  static func targetX(
    isEnabled: Bool,
    originX: CGFloat,
    dayColumnWidth: CGFloat,
    documentWidth: CGFloat,
    viewportWidth: CGFloat
  ) -> CGFloat? {
    guard isEnabled, dayColumnWidth > 0.5 else { return nil }
    let maxX = max(0, documentWidth - viewportWidth)
    let targetX = min(max(0, round(originX / dayColumnWidth) * dayColumnWidth), maxX)
    guard abs(targetX - originX) > 0.5 else { return nil }
    return targetX
  }
}

final class SnappingScheduleScrollView: NSScrollView {
  var dayColumnWidth: CGFloat = 0
  var isDateBoundarySnappingEnabled = true {
    didSet {
      if !isDateBoundarySnappingEnabled {
        cancelActiveSnap()
      }
    }
  }
  private(set) var isSnapping = false
  var onSnapDidFinish: (() -> Void)?
  private var activeSnap: ScheduleSnapAnimation?

  func notifyExternalHorizontalScrollEnded() {
    triggerSnap()
  }

  func cancelSnap() {
    cancelActiveSnap()
  }

  override func scrollWheel(with event: NSEvent) {
    guard isDateBoundarySnappingEnabled else {
      cancelActiveSnap()
      super.scrollWheel(with: event)
      return
    }

    // Cancel any snap that may have started prematurely (before momentum began)
    if event.phase.contains(.began) || event.momentumPhase.contains(.began) {
      cancelActiveSnap()
    }

    // Also cancel if ongoing momentum arrives while we're already snapping
    let hasActiveMomentum =
      !event.momentumPhase.isEmpty
      && !event.momentumPhase.contains(.ended)
      && !event.momentumPhase.contains(.cancelled)
    if isSnapping && hasActiveMomentum {
      cancelActiveSnap()
    }

    super.scrollWheel(with: event)

    let gestureEnded = event.phase.contains(.ended) || event.phase.contains(.cancelled)
    let momentumEnded =
      event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)

    if momentumEnded || (gestureEnded && !hasActiveMomentum) {
      triggerSnap()
    }
  }

  private func cancelActiveSnap() {
    activeSnap?.cancel()
    activeSnap = nil
    isSnapping = false
  }

  private func triggerSnap() {
    let bounds = contentView.bounds
    guard let docWidth = documentView?.frame.width else { return }
    guard let targetX = ScheduleDateBoundarySnapPolicy.targetX(
      isEnabled: isDateBoundarySnappingEnabled,
      originX: bounds.origin.x,
      dayColumnWidth: dayColumnWidth,
      documentWidth: docWidth,
      viewportWidth: bounds.width
    ) else {
      return
    }

    activeSnap?.cancel()
    let distance = abs(targetX - bounds.origin.x)
    let fraction = min(1, distance / max(1, dayColumnWidth))
    let duration = 0.14 + 0.16 * CFTimeInterval(fraction)
    isSnapping = true
    let snap = ScheduleSnapAnimation(
      scrollView: self,
      fromX: bounds.origin.x,
      fromY: bounds.origin.y,
      targetX: targetX,
      duration: duration,
      onCompletion: { [weak self] in
        guard let self else { return }
        self.isSnapping = false
        self.activeSnap = nil
        self.onSnapDidFinish?()
      }
    )
    activeSnap = snap
    snap.start()
  }
}
final class ScheduleSnapAnimation {
  private weak var scrollView: NSScrollView?
  private let fromX: CGFloat
  private let fromY: CGFloat
  private let targetX: CGFloat
  private let duration: CFTimeInterval
  private let startedAt = CACurrentMediaTime()
  private var timer: Timer?
  private var onCompletion: (() -> Void)?

  init(
    scrollView: NSScrollView,
    fromX: CGFloat,
    fromY: CGFloat,
    targetX: CGFloat,
    duration: CFTimeInterval,
    onCompletion: (() -> Void)? = nil
  ) {
    self.scrollView = scrollView
    self.fromX = fromX
    self.fromY = fromY
    self.targetX = targetX
    self.duration = duration
    self.onCompletion = onCompletion
  }

  func start() {
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
  }

  private func tick() {
    guard let scrollView else { stopTimer(); return }
    let elapsed = CACurrentMediaTime() - startedAt
    let t = min(1, elapsed / max(0.001, duration))
    let eased = 1 - pow(1 - t, 3)
    let x = fromX + (targetX - fromX) * CGFloat(eased)
    let currentY = scrollView.contentView.bounds.origin.y
    scrollView.contentView.scroll(to: CGPoint(x: x, y: currentY))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    if t >= 1 {
      stopTimer()
      let completion = onCompletion
      onCompletion = nil
      completion?()
    }
  }

  func cancel() {
    onCompletion = nil
    stopTimer()
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }
}

final class ScheduleCursorRectView: NSView {
  var cursor: NSCursor = .arrow {
    didSet {
      needsDisplay = true
      window?.invalidateCursorRects(for: self)
    }
  }

  private var trackingArea: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [
        .activeInKeyWindow,
        .inVisibleRect,
        .mouseEnteredAndExited,
        .mouseMoved,
        .cursorUpdate,
        .enabledDuringMouseDrag
      ],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    self.trackingArea = trackingArea
  }

  override func cursorUpdate(with event: NSEvent) {
    cursor.set()
  }

  override func mouseEntered(with event: NSEvent) {
    cursor.set()
  }

  override func mouseMoved(with event: NSEvent) {
    cursor.set()
  }
}

struct ScheduleCursorRegion: NSViewRepresentable {
  let cursor: NSCursor

  func makeNSView(context: Context) -> ScheduleCursorRectView {
    let view = ScheduleCursorRectView()
    view.cursor = cursor
    return view
  }

  func updateNSView(_ nsView: ScheduleCursorRectView, context: Context) {
    nsView.cursor = cursor
  }
}
