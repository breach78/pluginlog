import AppKit
import QuartzCore
import SwiftUI

final class ProjectTaskRetainedListHostedContentView: NSHostingView<AnyView> {
  let taskID: UUID
  var renderSignature: Int
  weak var layoutDelegate: ProjectTaskRetainedListRowLayoutDelegate?
  var suppressesScheduledRelayout = false

  private var isRelayoutScheduled = false

  init(taskID: UUID, renderSignature: Int, rootView: AnyView) {
    self.taskID = taskID
    self.renderSignature = renderSignature
    super.init(rootView: rootView)
  }

  @available(*, unavailable)
  required init(rootView: AnyView) {
    fatalError("init(rootView:) has not been implemented")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func invalidateIntrinsicContentSize() {
    super.invalidateIntrinsicContentSize()
    guard !suppressesScheduledRelayout else { return }
    scheduleRelayout()
  }

  private func scheduleRelayout() {
    guard !isRelayoutScheduled else { return }
    isRelayoutScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isRelayoutScheduled = false
      self.layoutDelegate?.projectTaskRetainedListRowNeedsRelayout(self.taskID)
    }
  }
}

final class ProjectTaskRetainedListShellView: NSView {
  override var isFlipped: Bool { true }

  let taskID: UUID
  let rowView: ProjectTaskRetainedListHostedContentView
  let rowMeasurementView: NSHostingView<AnyView>
  let detailView: ProjectTaskRetainedListHostedContentView
  let detailMeasurementView: NSHostingView<AnyView>
  let detailReadOnlyView = ProjectTaskRetainedListReadOnlyDetailView(frame: .zero)
  let dividerView = NSView(frame: .zero)

  private var rowMeasurementSignature: Int
  private var detailMeasurementSignature: Int
  private var measuredRowHeight: CGFloat = 1
  private var measuredDetailHeight: CGFloat = 1
  private var detailIsVisible = false
  private var needsDetailMeasurement = true
  private var suppressesBottomDivider = false
  private let collapsedDetailHeight: CGFloat = 1

  init(
    taskID: UUID,
    rowSignature: Int,
    rowContent: AnyView,
    rowMeasurementSignature: Int,
    rowMeasurementContent: AnyView,
    detailSignature: Int,
    detailContent: AnyView,
    detailMeasurementSignature: Int,
    detailMeasurementContent: AnyView
  ) {
    self.taskID = taskID
    self.rowMeasurementSignature = rowMeasurementSignature
    self.detailMeasurementSignature = detailMeasurementSignature
    self.rowView = ProjectTaskRetainedListHostedContentView(
      taskID: taskID,
      renderSignature: rowSignature,
      rootView: rowContent
    )
    self.rowMeasurementView = NSHostingView(rootView: rowMeasurementContent)
    self.detailView = ProjectTaskRetainedListHostedContentView(
      taskID: taskID,
      renderSignature: detailSignature,
      rootView: detailContent
    )
    self.detailMeasurementView = NSHostingView(rootView: detailMeasurementContent)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = true
    addSubview(rowView)
    addSubview(detailView)
    detailReadOnlyView.isHidden = true
    addSubview(detailReadOnlyView)
    dividerView.wantsLayer = true
    dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor
    addSubview(dividerView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    dividerView.frame = CGRect(x: 0, y: max(0, bounds.height - 1), width: bounds.width, height: 1)
  }

  func setLayoutDelegate(_ delegate: ProjectTaskRetainedListRowLayoutDelegate) {
    rowView.layoutDelegate = delegate
    detailView.layoutDelegate = delegate
  }

  func update(
    rowSignature: Int,
    rowContent: AnyView,
    rowMeasurementSignature: Int,
    rowMeasurementContent: AnyView,
    detailSignature: Int,
    detailContent: AnyView,
    detailMeasurementSignature: Int,
    detailMeasurementContent: AnyView,
    readOnlyDetailSnapshot: ProjectTaskReadOnlyDetailSnapshot?,
    detailIsVisible: Bool,
    suppressesBottomDivider: Bool,
    suppressesRowViewRelayout: Bool,
    suppressesDetailViewRelayout: Bool
  ) {
    rowView.suppressesScheduledRelayout = suppressesRowViewRelayout
    detailView.suppressesScheduledRelayout = suppressesDetailViewRelayout
    let hasVisibleReadOnlyDetail =
      (readOnlyDetailSnapshot?.noteRegionHeight ?? 0) > 0.5
      || !(readOnlyDetailSnapshot?.attachments.isEmpty ?? true)
    detailReadOnlyView.update(snapshot: readOnlyDetailSnapshot)
    let showsReadOnlyDetailSnapshot =
      readOnlyDetailSnapshot != nil && detailIsVisible && hasVisibleReadOnlyDetail
    detailReadOnlyView.isHidden = !showsReadOnlyDetailSnapshot
    detailView.isHidden = showsReadOnlyDetailSnapshot

    let rowContentChanged = rowView.renderSignature != rowSignature
    let detailContentChanged = self.detailView.renderSignature != detailSignature
    if rowContentChanged || detailContentChanged {
      clearPresentationAnimations()
    }

    if rowContentChanged {
      rowView.rootView = rowContent
      rowView.renderSignature = rowSignature
      rowView.layoutSubtreeIfNeeded()
    }
    if self.rowMeasurementSignature != rowMeasurementSignature {
      rowMeasurementView.rootView = rowMeasurementContent
      self.rowMeasurementSignature = rowMeasurementSignature
    }

    if detailContentChanged {
      self.detailView.rootView = detailContent
      self.detailView.renderSignature = detailSignature
      needsDetailMeasurement = true
      detailView.layoutSubtreeIfNeeded()
    }
    if self.detailMeasurementSignature != detailMeasurementSignature {
      detailMeasurementView.rootView = detailMeasurementContent
      self.detailMeasurementSignature = detailMeasurementSignature
      needsDetailMeasurement = true
    }

    self.detailIsVisible = detailIsVisible
    self.suppressesBottomDivider = suppressesBottomDivider
    dividerView.isHidden = suppressesBottomDivider
  }

  func clearPresentationAnimations() {
    layer?.removeAllAnimations()
    rowView.layer?.removeAllAnimations()
    detailView.layer?.removeAllAnimations()
    detailReadOnlyView.layer?.removeAllAnimations()
  }

  func measureHeights(width: CGFloat) -> (
    rowHeight: CGFloat,
    detailHeight: CGFloat,
    expandedDetailHeight: CGFloat
  ) {
    measureHeights(width: width, fixedDetailHeight: nil)
  }

  func measureHeights(
    width: CGFloat,
    fixedDetailHeight: CGFloat?
  ) -> (
    rowHeight: CGFloat,
    detailHeight: CGFloat,
    expandedDetailHeight: CGFloat
  ) {
    measuredRowHeight = measureHeight(of: rowMeasurementView, width: width)

    if let fixedDetailHeight {
      measuredDetailHeight = max(collapsedDetailHeight, ceil(fixedDetailHeight))
    } else if needsDetailMeasurement || detailIsVisible || measuredDetailHeight <= collapsedDetailHeight {
      measuredDetailHeight = max(
        collapsedDetailHeight,
        measureHeight(of: detailMeasurementView, width: width)
      )
      needsDetailMeasurement = false
    }

    let visibleDetailHeight = detailIsVisible ? measuredDetailHeight : collapsedDetailHeight
    applyLocalLayout(width: width)
    return (measuredRowHeight, visibleDetailHeight, measuredDetailHeight)
  }

  func applyLocalLayout(width: CGFloat) {
    rowView.frame = CGRect(x: 0, y: 0, width: width, height: measuredRowHeight)
    detailView.frame = CGRect(x: 0, y: measuredRowHeight, width: width, height: measuredDetailHeight)
    detailReadOnlyView.frame = CGRect(x: 0, y: measuredRowHeight, width: width, height: measuredDetailHeight)
    dividerView.frame = CGRect(x: 0, y: max(0, bounds.height - 1), width: width, height: 1)
  }

  func applyResolvedLayout(
    width: CGFloat,
    fixedRowHeight: CGFloat?,
    fixedDetailHeight: CGFloat?
  ) {
    if let fixedRowHeight {
      measuredRowHeight = max(1, ceil(fixedRowHeight))
    }

    if let fixedDetailHeight {
      measuredDetailHeight = max(collapsedDetailHeight, ceil(fixedDetailHeight))
      needsDetailMeasurement = false
    } else if !detailIsVisible {
      measuredDetailHeight = collapsedDetailHeight
    }

    applyLocalLayout(width: width)
  }

  private func measureHeight(of hostedView: NSHostingView<AnyView>, width: CGFloat) -> CGFloat {
    if abs(hostedView.frame.width - width) > 0.5 {
      hostedView.frame.size.width = width
    }
    hostedView.layoutSubtreeIfNeeded()
    return max(1, ceil(hostedView.fittingSize.height))
  }
}

final class ProjectTaskRetainedListOverlayView: NSView {
  override var isFlipped: Bool { true }

  var rowFrames: [UUID: CGRect] = [:] {
    didSet { needsDisplay = true }
  }

  var rowOrder: [UUID] = [] {
    didSet { needsDisplay = true }
  }

  var highlightedTaskID: UUID? {
    didSet { needsDisplay = true }
  }

  var dropIndicator: TaskDropIndicator? {
    didSet { needsDisplay = true }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    if let highlightedTaskID,
      let rect = rowFrames[highlightedTaskID]
    {
      NSColor.systemYellow.withAlphaComponent(0.34).setFill()
      NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    }

    if let dropIndicator,
      let rect = rowFrames[dropIndicator.targetTaskID],
      let y = insertionIndicatorY(for: dropIndicator, targetRect: rect)
    {
      NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
      NSBezierPath(rect: CGRect(x: rect.minX, y: y, width: rect.width, height: 2)).fill()
    }
  }

  private func insertionIndicatorY(
    for indicator: TaskDropIndicator,
    targetRect: CGRect
  ) -> CGFloat? {
    let lineHeight: CGFloat = 2
    guard let targetIndex = rowOrder.firstIndex(of: indicator.targetTaskID) else {
      return indicator.placement == .before ? targetRect.minY : max(targetRect.minY, targetRect.maxY - lineHeight)
    }

    switch indicator.placement {
    case .before:
      guard targetIndex > 0,
        let previousRect = rowFrames[rowOrder[targetIndex - 1]]
      else {
        return targetRect.minY
      }
      return ((previousRect.maxY + targetRect.minY) * 0.5) - (lineHeight * 0.5)
    case .after:
      guard targetIndex < rowOrder.count - 1,
        let nextRect = rowFrames[rowOrder[targetIndex + 1]]
      else {
        return max(targetRect.minY, targetRect.maxY - lineHeight)
      }
      return ((targetRect.maxY + nextRect.minY) * 0.5) - (lineHeight * 0.5)
    }
  }
}

final class ProjectTaskRetainedListContainerView: NSView {
  override var isFlipped: Bool { true }

  let overlayView = ProjectTaskRetainedListOverlayView(frame: .zero)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    addSubview(overlayView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    overlayView.frame = bounds
  }
}
