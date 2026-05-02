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

@MainActor
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

@MainActor
struct ScheduleVerticalRailScrollView<Content: View>: NSViewRepresentable {
  let contentSize: CGSize
  let visibleHeight: CGFloat
  let isScrollEnabled: Bool
  let viewportState: ScheduleScrollViewportState
  let content: Content

  init(
    contentSize: CGSize,
    visibleHeight: CGFloat,
    isScrollEnabled: Bool,
    viewportState: ScheduleScrollViewportState,
    @ViewBuilder content: () -> Content
  ) {
    self.contentSize = contentSize
    self.visibleHeight = visibleHeight
    self.isScrollEnabled = isScrollEnabled
    self.viewportState = viewportState
    self.content = content()
  }

  @MainActor
  final class Coordinator {
    let hostingView: NSHostingView<Content>

    init(content: Content) {
      self.hostingView = NSHostingView(rootView: content)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(content: content)
  }

  func makeNSView(context: Context) -> HorizontalPassthroughScheduleScrollView {
    let scrollView = HorizontalPassthroughScheduleScrollView()
    let clipView = FlippedScheduleClipView()
    clipView.drawsBackground = false
    scrollView.contentView = clipView
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.autohidesScrollers = true
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = true
    scrollView.usesPredominantAxisScrolling = false
    scrollView.horizontalScrollElasticity = .none
    scrollView.verticalScrollElasticity = .none
    scrollView.documentView = context.coordinator.hostingView
    scrollView.horizontalScrollTarget = viewportState.scrollView
    return scrollView
  }

  func updateNSView(_ nsView: HorizontalPassthroughScheduleScrollView, context: Context) {
    nsView.horizontalScrollTarget = viewportState.scrollView
    context.coordinator.hostingView.rootView = content

    let documentFrame = CGRect(origin: .zero, size: contentSize)
    if !context.coordinator.hostingView.frame.equalTo(documentFrame) {
      context.coordinator.hostingView.frame = documentFrame
    }

    nsView.hasVerticalScroller = isScrollEnabled

    if !isScrollEnabled {
      let currentOrigin = nsView.contentView.bounds.origin
      if abs(currentOrigin.y) > 0.5 {
        nsView.contentView.scroll(to: CGPoint(x: currentOrigin.x, y: 0))
        nsView.reflectScrolledClipView(nsView.contentView)
      }
    }
  }
}

@MainActor
final class ScheduleScrollViewportState {
  var liveOffsetX: CGFloat = 0
  var liveOffsetY: CGFloat = 0
  weak var scrollView: SnappingScheduleScrollView?
  private var viewportChangeListeners: [UUID: () -> Void] = [:]

  func pointerViewportLocation() -> CGPoint? {
    guard let scrollView, let window = scrollView.window else { return nil }
    let screenPoint = NSEvent.mouseLocation
    let windowPoint = window.convertPoint(fromScreen: screenPoint)
    let contentPoint = scrollView.contentView.convert(windowPoint, from: nil)
    let visibleOrigin = scrollView.contentView.bounds.origin
    return CGPoint(
      x: contentPoint.x - visibleOrigin.x,
      y: contentPoint.y - visibleOrigin.y
    )
  }

  func addViewportChangeListener(_ listener: @escaping () -> Void) -> UUID {
    let id = UUID()
    viewportChangeListeners[id] = listener
    return id
  }

  func removeViewportChangeListener(_ id: UUID) {
    viewportChangeListeners.removeValue(forKey: id)
  }

  func notifyViewportChangeListeners() {
    for listener in viewportChangeListeners.values {
      listener()
    }
  }
}

@MainActor
struct UnifiedScheduleBoardScrollView<
  BoardContent: View, PinnedLeft: View, PinnedTop: View
>: NSViewRepresentable {
  let boardSize: CGSize
  let titleColumnWidth: CGFloat
  let headerHeight: CGFloat
  let dayColumnWidth: CGFloat
  let boardContentVersion: Int
  let pinnedLeftVersion: Int
  let pinnedTopVersion: Int
  let scrollRequestGeneration: Int
  let publishesLiveOffsets: Bool
  let isDateBoundarySnappingEnabled: Bool
  let viewportState: ScheduleScrollViewportState

  @Binding var offsetX: CGFloat
  @Binding var offsetY: CGFloat
  @Binding var requestedOffsetX: CGFloat?
  @Binding var requestedOffsetY: CGFloat?

  let boardContent: BoardContent
  let pinnedLeft: PinnedLeft
  let pinnedTop: PinnedTop

  init(
    boardSize: CGSize,
    titleColumnWidth: CGFloat,
    headerHeight: CGFloat,
    dayColumnWidth: CGFloat,
    boardContentVersion: Int,
    pinnedLeftVersion: Int,
    pinnedTopVersion: Int,
    scrollRequestGeneration: Int,
    publishesLiveOffsets: Bool,
    isDateBoundarySnappingEnabled: Bool,
    viewportState: ScheduleScrollViewportState,
    offsetX: Binding<CGFloat>,
    offsetY: Binding<CGFloat>,
    requestedOffsetX: Binding<CGFloat?>,
    requestedOffsetY: Binding<CGFloat?>,
    @ViewBuilder boardContent: () -> BoardContent,
    @ViewBuilder pinnedLeft: () -> PinnedLeft,
    @ViewBuilder pinnedTop: () -> PinnedTop
  ) {
    self.boardSize = boardSize
    self.titleColumnWidth = titleColumnWidth
    self.headerHeight = headerHeight
    self.dayColumnWidth = dayColumnWidth
    self.boardContentVersion = boardContentVersion
    self.pinnedLeftVersion = pinnedLeftVersion
    self.pinnedTopVersion = pinnedTopVersion
    self.scrollRequestGeneration = scrollRequestGeneration
    self.publishesLiveOffsets = publishesLiveOffsets
    self.isDateBoundarySnappingEnabled = isDateBoundarySnappingEnabled
    self.viewportState = viewportState
    self._offsetX = offsetX
    self._offsetY = offsetY
    self._requestedOffsetX = requestedOffsetX
    self._requestedOffsetY = requestedOffsetY
    self.boardContent = boardContent()
    self.pinnedLeft = pinnedLeft()
    self.pinnedTop = pinnedTop()
  }

  @MainActor
  final class Coordinator: NSObject {
    let documentView = FlippedScheduleDocumentView()
    let boardHosting: NSHostingView<BoardContent>
    let leftHosting: ScrollPassthroughScheduleHostingView<PinnedLeft>
    let topHosting: ScrollPassthroughScheduleHostingView<PinnedTop>

    var lastBoardContentVersion: Int
    var lastPinnedLeftVersion: Int
    var lastPinnedTopVersion: Int
    var offsetX: Binding<CGFloat>
    var offsetY: Binding<CGFloat>
    var titleColumnWidth: CGFloat
    var headerHeight: CGFloat
    var dayColumnWidth: CGFloat
    let viewportState: ScheduleScrollViewportState
    var publishesLiveOffsets: Bool
    var lastPublishedDayBucket: Int = .min
    var lastScrollRequestGeneration: Int
    var hasAppliedRequestedOffset = false
    weak var scrollView: NSScrollView?

    init(
      boardContent: BoardContent,
      pinnedLeft: PinnedLeft,
      pinnedTop: PinnedTop,
      boardContentVersion: Int,
      pinnedLeftVersion: Int,
      pinnedTopVersion: Int,
      offsetX: Binding<CGFloat>,
      offsetY: Binding<CGFloat>,
      titleColumnWidth: CGFloat,
      headerHeight: CGFloat,
      dayColumnWidth: CGFloat,
      viewportState: ScheduleScrollViewportState,
      publishesLiveOffsets: Bool,
      scrollRequestGeneration: Int
    ) {
      self.boardHosting = NSHostingView(rootView: boardContent)
      self.leftHosting = ScrollPassthroughScheduleHostingView(rootView: pinnedLeft)
      self.topHosting = ScrollPassthroughScheduleHostingView(rootView: pinnedTop)
      self.lastBoardContentVersion = boardContentVersion
      self.lastPinnedLeftVersion = pinnedLeftVersion
      self.lastPinnedTopVersion = pinnedTopVersion
      self.offsetX = offsetX
      self.offsetY = offsetY
      self.titleColumnWidth = titleColumnWidth
      self.headerHeight = headerHeight
      self.dayColumnWidth = dayColumnWidth
      self.viewportState = viewportState
      self.publishesLiveOffsets = publishesLiveOffsets
      self.lastScrollRequestGeneration = scrollRequestGeneration
      super.init()
      documentView.addSubview(boardHosting)
    }

    @objc func boundsDidChange(_ notification: Notification) {
      guard let scrollView else { return }
      let isSnapping = (scrollView as? SnappingScheduleScrollView)?.isSnapping ?? false
      if !isSnapping {
        clampVisibleOriginIfNeeded()
      }
      let origin = scrollView.contentView.bounds.origin
      let x = max(0, origin.x)
      let y = max(0, origin.y)
      if !isSnapping {
        publishVisibleOffsets(x: x, y: y)
      }
      layoutPinnedOverlays(boardSize: documentView.frame.size)
    }

    @objc func frameDidChange(_ notification: Notification) {
      clampVisibleOriginIfNeeded()
      layoutPinnedOverlays(boardSize: documentView.frame.size)
    }

    func clampVisibleOriginIfNeeded() {
      guard let scrollView else { return }
      let bounds = scrollView.contentView.bounds
      let viewportSize = bounds.size
      let boardSize = documentView.frame.size
      let maxX = max(0, boardSize.width - viewportSize.width)
      let maxY = max(0, boardSize.height - viewportSize.height)
      let clampedX = min(max(0, bounds.origin.x), maxX)
      let clampedY = min(max(0, bounds.origin.y), maxY)

      guard abs(bounds.origin.x - clampedX) > 0.5 || abs(bounds.origin.y - clampedY) > 0.5 else {
        return
      }

      scrollView.contentView.scroll(to: CGPoint(x: clampedX, y: clampedY))
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func layoutPinnedOverlays(boardSize: CGSize) {
      guard let scrollView else { return }
      let bounds = scrollView.contentView.bounds
      let contentWidth = max(0, boardSize.width - titleColumnWidth)

      let leftFrame = CGRect(
        x: bounds.origin.x,
        y: 0,
        width: titleColumnWidth,
        height: boardSize.height
      )
      if !leftHosting.frame.equalTo(leftFrame) {
        leftHosting.frame = leftFrame
      }

      let topFrame = CGRect(
        x: titleColumnWidth,
        y: bounds.origin.y,
        width: contentWidth,
        height: headerHeight
      )
      if !topHosting.frame.equalTo(topFrame) {
        topHosting.frame = topFrame
      }
    }

    func publishVisibleOffsets(x: CGFloat, y: CGFloat) {
      let didChangeX = abs(viewportState.liveOffsetX - x) > 0.5
      let didChangeY = abs(viewportState.liveOffsetY - y) > 0.5
      guard didChangeX || didChangeY else { return }

      viewportState.liveOffsetX = x
      viewportState.liveOffsetY = y
      viewportState.notifyViewportChangeListeners()

      let bucket = Int(floor(x / max(1, dayColumnWidth)))
      if publishesLiveOffsets {
        lastPublishedDayBucket = bucket
        publish(offsetX, value: x)
        publish(offsetY, value: y)
        return
      }

      if bucket != lastPublishedDayBucket {
        lastPublishedDayBucket = bucket
        publish(offsetX, value: x)
      }
    }

    private func publish(_ binding: Binding<CGFloat>, value: CGFloat) {
      guard abs(binding.wrappedValue - value) > 0.5 else { return }
      DispatchQueue.main.async {
        if abs(binding.wrappedValue - value) > 0.5 {
          binding.wrappedValue = value
        }
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      boardContent: boardContent,
      pinnedLeft: pinnedLeft,
      pinnedTop: pinnedTop,
      boardContentVersion: boardContentVersion,
      pinnedLeftVersion: pinnedLeftVersion,
      pinnedTopVersion: pinnedTopVersion,
      offsetX: $offsetX,
      offsetY: $offsetY,
      titleColumnWidth: titleColumnWidth,
      headerHeight: headerHeight,
      dayColumnWidth: dayColumnWidth,
      viewportState: viewportState,
      publishesLiveOffsets: publishesLiveOffsets,
      scrollRequestGeneration: scrollRequestGeneration
    )
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = SnappingScheduleScrollView()
    scrollView.dayColumnWidth = dayColumnWidth
    scrollView.isDateBoundarySnappingEnabled = isDateBoundarySnappingEnabled
    let clipView = FlippedScheduleClipView()
    clipView.drawsBackground = false
    scrollView.contentView = clipView
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.usesPredominantAxisScrolling = false
    scrollView.horizontalScrollElasticity = .none
    scrollView.verticalScrollElasticity = .none

    scrollView.documentView = context.coordinator.documentView
    context.coordinator.scrollView = scrollView
    viewportState.scrollView = scrollView

    scrollView.onSnapDidFinish = { [weak coordinator = context.coordinator, weak scrollView] in
      guard let coordinator, let scrollView else { return }
      let origin = scrollView.contentView.bounds.origin
      coordinator.publishVisibleOffsets(
        x: max(0, origin.x),
        y: max(0, origin.y)
      )
    }

    context.coordinator.leftHosting.wantsLayer = true
    context.coordinator.topHosting.wantsLayer = true
    context.coordinator.leftHosting.layer?.zPosition = 1
    context.coordinator.topHosting.layer?.zPosition = 2

    scrollView.contentView.wantsLayer = true
    scrollView.contentView.layer?.masksToBounds = true
    scrollView.contentView.addSubview(context.coordinator.leftHosting)
    scrollView.contentView.addSubview(context.coordinator.topHosting)
    scrollView.contentView.postsBoundsChangedNotifications = true
    scrollView.contentView.postsFrameChangedNotifications = true

    NotificationCenter.default.addObserver(
      context.coordinator,
      selector: #selector(Coordinator.boundsDidChange(_:)),
      name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView
    )
    NotificationCenter.default.addObserver(
      context.coordinator,
      selector: #selector(Coordinator.frameDidChange(_:)),
      name: NSView.frameDidChangeNotification,
      object: scrollView.contentView
    )
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let coordinator = context.coordinator
    viewportState.scrollView = scrollView as? SnappingScheduleScrollView
    if let snappingScrollView = scrollView as? SnappingScheduleScrollView {
      snappingScrollView.dayColumnWidth = dayColumnWidth
      snappingScrollView.isDateBoundarySnappingEnabled = isDateBoundarySnappingEnabled
    }

    if coordinator.lastBoardContentVersion != boardContentVersion {
      coordinator.boardHosting.rootView = boardContent
      coordinator.lastBoardContentVersion = boardContentVersion
    }
    if coordinator.lastPinnedLeftVersion != pinnedLeftVersion {
      coordinator.leftHosting.rootView = pinnedLeft
      coordinator.lastPinnedLeftVersion = pinnedLeftVersion
    }
    if coordinator.lastPinnedTopVersion != pinnedTopVersion {
      coordinator.topHosting.rootView = pinnedTop
      coordinator.lastPinnedTopVersion = pinnedTopVersion
    }

    coordinator.offsetX = $offsetX
    coordinator.offsetY = $offsetY
    coordinator.titleColumnWidth = titleColumnWidth
    coordinator.headerHeight = headerHeight
    coordinator.dayColumnWidth = dayColumnWidth
    coordinator.publishesLiveOffsets = publishesLiveOffsets

    if coordinator.lastScrollRequestGeneration != scrollRequestGeneration {
      coordinator.lastScrollRequestGeneration = scrollRequestGeneration
      coordinator.hasAppliedRequestedOffset = false
    }

    let documentFrame = CGRect(origin: .zero, size: boardSize)
    if !coordinator.documentView.frame.equalTo(documentFrame) {
      coordinator.documentView.frame = documentFrame
    }
    if !coordinator.boardHosting.frame.equalTo(coordinator.documentView.bounds) {
      coordinator.boardHosting.frame = coordinator.documentView.bounds
    }

    let viewportSize = scrollView.contentView.bounds.size
    let maxX = max(0, boardSize.width - viewportSize.width)
    let maxY = max(0, boardSize.height - viewportSize.height)
    let current = scrollView.contentView.bounds.origin

    let hasRequestedProgrammaticScroll =
      requestedOffsetX != nil || requestedOffsetY != nil

    if hasRequestedProgrammaticScroll, !coordinator.hasAppliedRequestedOffset {
      let targetX = min(max(0, requestedOffsetX ?? current.x), maxX)
      let targetY = min(max(0, requestedOffsetY ?? current.y), maxY)
      if abs(current.x - targetX) > 0.5 || abs(current.y - targetY) > 0.5 {
        scrollView.contentView.scroll(to: CGPoint(x: targetX, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
      coordinator.hasAppliedRequestedOffset = true
      let requestedBinding = _requestedOffsetX
      let requestedVerticalBinding = _requestedOffsetY
      DispatchQueue.main.async {
        if requestedBinding.wrappedValue != nil {
          requestedBinding.wrappedValue = nil
        }
        if requestedVerticalBinding.wrappedValue != nil {
          requestedVerticalBinding.wrappedValue = nil
        }
      }
    }

    let isSnapping = (scrollView as? SnappingScheduleScrollView)?.isSnapping ?? false

    if !isSnapping {
      let clampedX = min(max(0, current.x), maxX)
      let clampedY = min(max(0, current.y), maxY)
      if abs(current.x - clampedX) > 0.5 || abs(current.y - clampedY) > 0.5 {
        scrollView.contentView.scroll(to: CGPoint(x: clampedX, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }

    coordinator.layoutPinnedOverlays(boardSize: boardSize)

    if !isSnapping {
      let liveX = max(0, scrollView.contentView.bounds.origin.x)
      let liveY = max(0, scrollView.contentView.bounds.origin.y)
      coordinator.publishVisibleOffsets(x: liveX, y: liveY)
    }
  }

  static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    NotificationCenter.default.removeObserver(
      coordinator,
      name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView
    )
    NotificationCenter.default.removeObserver(
      coordinator,
      name: NSView.frameDidChangeNotification,
      object: scrollView.contentView
    )
  }
}
