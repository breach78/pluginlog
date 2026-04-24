import AppKit
import SwiftUI

private struct OutlineNodeRowDisplayMeasurementKey: Hashable {
  let text: String
  let widthBucket: Int
  let fontSizeBucket: Int
}

final class OutlineNodeRowDisplayTextView: NSTextView {
  private static var heightCache: [OutlineNodeRowDisplayMeasurementKey: CGFloat] = [:]

  var onActivate: ((Int, NSEvent.ModifierFlags) -> Void)?
  var onMeasuredContentHeightChange: ((CGFloat) -> Void)?
  var usesInteractiveCursor = false
  var measurementCacheText = ""
  var measurementCacheFontSize: CGFloat = OutlinerCanvasMetrics.fontSize
  private var lastReportedContentHeight: CGFloat = 0
  private var lastMeasuredWidth: CGFloat = 0
  private var pendingMeasuredContentHeight: CGFloat?
  private var hasScheduledMeasuredContentHeightDispatch = false

  override var intrinsicContentSize: NSSize {
    guard textContainer != nil else {
      return NSSize(width: NSView.noIntrinsicMetric, height: OutlineRowLayoutSpec.rowMinHeight)
    }

    let height = max(OutlineRowLayoutSpec.rowMinHeight, measuredContentHeight())
    return NSSize(width: NSView.noIntrinsicMetric, height: height)
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    let measuredWidth = max(1, newSize.width)
    let widthChanged = abs(lastMeasuredWidth - measuredWidth) > 0.5
    lastMeasuredWidth = measuredWidth
    textContainer?.containerSize = NSSize(
      width: measuredWidth,
      height: CGFloat.greatestFiniteMagnitude
    )
    let heightChanged = reportMeasuredContentHeightIfNeeded()
    if widthChanged || heightChanged {
      invalidateIntrinsicContentSize()
    }
  }

  override func layout() {
    super.layout()
    if reportMeasuredContentHeightIfNeeded() {
      invalidateIntrinsicContentSize()
    }
  }

  override func mouseDown(with event: NSEvent) {
    onActivate?(
      activationLocation(for: event),
      event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    )
  }

  override func resetCursorRects() {
    discardCursorRects()
    if usesInteractiveCursor {
      super.resetCursorRects()
    } else {
      addCursorRect(bounds, cursor: .arrow)
    }
  }

  @discardableResult
  func reportMeasuredContentHeightIfNeeded() -> Bool {
    guard textContainer != nil else { return false }
    let contentHeight = measuredContentHeight()
    guard abs(contentHeight - lastReportedContentHeight) > 0.5 else { return false }
    lastReportedContentHeight = contentHeight
    enqueueMeasuredContentHeightChange(contentHeight)
    return true
  }

  private func measurementKey(for width: CGFloat) -> OutlineNodeRowDisplayMeasurementKey {
    OutlineNodeRowDisplayMeasurementKey(
      text: measurementCacheText,
      widthBucket: Int((width * 2).rounded(.toNearestOrAwayFromZero)),
      fontSizeBucket: Int((measurementCacheFontSize * 10).rounded(.toNearestOrAwayFromZero))
    )
  }

  private func measuredContentHeight() -> CGFloat {
    guard let layoutManager, let textContainer else { return OutlineRowLayoutSpec.rowMinHeight }

    let measuredWidth = max(1, lastMeasuredWidth)
    let cacheKey = measurementKey(for: measuredWidth)
    if let cachedHeight = Self.heightCache[cacheKey] {
      return cachedHeight
    }

    layoutManager.ensureLayout(for: textContainer)
    let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height)
    Self.heightCache[cacheKey] = contentHeight
    return contentHeight
  }

  private func activationLocation(for event: NSEvent) -> Int {
    let textLength = (string as NSString).length
    guard textLength > 0,
          let layoutManager,
          let textContainer
    else {
      return 0
    }

    layoutManager.ensureLayout(for: textContainer)
    let containerOrigin = CGPoint(
      x: textContainerInset.width + textContainer.lineFragmentPadding,
      y: textContainerInset.height
    )
    let locationInView = convert(event.locationInWindow, from: nil)
    let locationInContainer = CGPoint(
      x: locationInView.x - containerOrigin.x,
      y: locationInView.y - containerOrigin.y
    )

    var fraction: CGFloat = 0
    let baseIndex = layoutManager.characterIndex(
      for: locationInContainer,
      in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: &fraction
    )
    let insertionIndex = fraction > 0.5 ? baseIndex + 1 : baseIndex
    return max(0, min(insertionIndex, textLength))
  }

  private func enqueueMeasuredContentHeightChange(_ contentHeight: CGFloat) {
    pendingMeasuredContentHeight = contentHeight
    guard !hasScheduledMeasuredContentHeightDispatch else { return }
    hasScheduledMeasuredContentHeightDispatch = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.hasScheduledMeasuredContentHeightDispatch = false
      guard let pendingMeasuredContentHeight = self.pendingMeasuredContentHeight else { return }
      self.pendingMeasuredContentHeight = nil
      self.onMeasuredContentHeightChange?(pendingMeasuredContentHeight)
    }
  }
}

struct OutlineNodeRowDisplay: NSViewRepresentable {
  let text: String
  let fontSize: CGFloat
  let onActivate: (Int, NSEvent.ModifierFlags) -> Void
  let onMeasuredContentHeightChange: (CGFloat) -> Void

  @MainActor
  final class Coordinator: NSObject {
    var parent: OutlineNodeRowDisplay

    init(parent: OutlineNodeRowDisplay) {
      self.parent = parent
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> OutlineNodeRowDisplayTextView {
    let textView = OutlineNodeRowDisplayTextView()
    textView.isRichText = false
    textView.isEditable = false
    textView.isSelectable = false
    textView.drawsBackground = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.autoresizingMask = [.width]
    textView.textContainerInset = .zero
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.lineBreakMode = .byWordWrapping
    textView.textContainer?.containerSize = NSSize(
      width: 1,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textColor = .labelColor
    textView.insertionPointColor = .labelColor
    textView.onActivate = { location, modifiers in
      context.coordinator.parent.onActivate(location, modifiers)
    }
    textView.onMeasuredContentHeightChange = { height in
      context.coordinator.parent.onMeasuredContentHeightChange(height)
    }
    textView.usesInteractiveCursor = false
    applyFormatting(to: textView)
    return textView
  }

  func updateNSView(_ textView: OutlineNodeRowDisplayTextView, context: Context) {
    context.coordinator.parent = self
    textView.onActivate = { location, modifiers in
      context.coordinator.parent.onActivate(location, modifiers)
    }
    textView.onMeasuredContentHeightChange = { height in
      context.coordinator.parent.onMeasuredContentHeightChange(height)
    }
    textView.usesInteractiveCursor = false
    let targetFont = OutlinerFonts.nsFont(size: fontSize)
    if textView.font != targetFont || textView.string != text {
      applyFormatting(to: textView)
    }
    textView.window?.invalidateCursorRects(for: textView)
  }

  private func applyFormatting(to textView: OutlineNodeRowDisplayTextView) {
    let font = OutlinerFonts.nsFont(size: fontSize)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.lineSpacing = OutlineRowLayoutSpec.textLineSpacing
    paragraphStyle.minimumLineHeight = OutlineRowLayoutSpec.rowMinHeight
    paragraphStyle.maximumLineHeight = OutlineRowLayoutSpec.rowMinHeight

    let attrStr = OutlineInlineFormatter.attributedString(
      from: text,
      fontSize: OutlinerFonts.resolvedSize(fontSize),
      baseFont: font,
      paragraphStyle: paragraphStyle
    )

    textView.font = font
    textView.measurementCacheText = text
    textView.measurementCacheFontSize = font.pointSize
    textView.textStorage?.setAttributedString(attrStr)
    if textView.reportMeasuredContentHeightIfNeeded() {
      textView.invalidateIntrinsicContentSize()
    }
  }
}
