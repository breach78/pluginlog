import AppKit
import QuartzCore

private let retainedTaskListNoteLayoutProbeLoggingEnabled = false

let retainedTaskListSlowSyncThresholdMS: Int = 12
let retainedTaskListSlowRelayoutThresholdMS: Int = 12
let retainedTaskListMountedBufferMinimum: CGFloat = 260
let retainedTaskListMountedBufferViewportFactor: CGFloat = 0.45
let retainedTaskListShellRetentionMinimum: CGFloat = 420
let retainedTaskListShellRetentionViewportFactor: CGFloat = 0.72
let retainedTaskListRelayoutTriggerMinimum: CGFloat = 96
let retainedTaskListRelayoutTriggerViewportFactor: CGFloat = 0.2
let retainedTaskListImmediateRelayoutOvershootThreshold: CGFloat = 72

extension ProjectTaskRetainedListView.Coordinator {
  func relayoutRows(
    animated: Bool,
    reusableRange: Range<Int>? = nil,
    reason: String
  ) {
    pendingIdleRelayoutWorkItem?.cancel()
    pendingIdleRelayoutWorkItem = nil
    pendingIdleRelayoutReason = nil
    pendingIdleRelayoutRange = nil
    let startedAt = CACurrentMediaTime()
    let width = max(0, floor(lastMeasuredWidth))
    guard width > 1 else { return }

    let scrollAnchorState = currentScrollAnchorState()

    var rowHeights: [UUID: CGFloat] = [:]
    var detailHeights: [UUID: CGFloat] = [:]
    let normalizedReusableRange =
      reusableRange.map { max(0, $0.lowerBound)..<min(rowOrder.count, $0.upperBound) }
    let reusableIDs = reusableTaskIDs(for: normalizedReusableRange)

    for taskID in rowOrder {
      if reusableIDs.contains(taskID),
        let previousLayout = lastAppliedLayout,
        let shellFrame = previousLayout.shellFrames[taskID],
        let rowFrame = previousLayout.rowFrames[taskID]
      {
        rowHeights[taskID] = rowFrame.height
        detailHeights[taskID] = max(0, shellFrame.height - rowFrame.height)
        continue
      }

      guard let item = itemsByID[taskID] else { continue }
      if let fixedRowHeight = item.fixedRowHeight {
        rowHeights[taskID] = fixedRowHeight
        detailHeights[taskID] = max(1, ceil(item.fixedDetailHeight ?? 1))
        continue
      }
      let estimated = measurementCache.estimatedHeights(
        for: taskID,
        detailIsVisible: item.detailIsVisible
      )
      rowHeights[taskID] = estimated.rowHeight
      detailHeights[taskID] = max(estimated.detailHeight, item.fixedDetailHeight ?? 0)
    }

    let estimatedLayout = layoutEngine.makeLayout(
      rowOrder: rowOrder,
      availableWidth: width,
      rowHeights: rowHeights,
      detailHeights: detailHeights,
      previousLayout: lastAppliedLayout,
      reusableRange: normalizedReusableRange
    )

    let mountedTaskIDs = mountedTaskIDs(for: estimatedLayout)
    let newMountedTaskIDs = syncMountedShells(mountedTaskIDs)
    let measurementTaskIDs = measurementTaskIDs(
      mountedTaskIDs: mountedTaskIDs,
      newMountedTaskIDs: newMountedTaskIDs,
      reusableIDs: reusableIDs
    )
    lastMountedTaskCount = mountedTaskIDs.count
    lastMeasuredTaskCount = measurementTaskIDs.count
    lastHostedViewCount = mountedTaskIDs.count * 4
    lastVirtualizationPressure =
      rowOrder.count >= 40 && mountedTaskIDs.count * 100 >= max(1, rowOrder.count) * 80
    publishLiveWindowTaskIDsIfNeeded(mountedTaskIDs)

    for taskID in measurementTaskIDs {
      guard let shellView = shellViews[taskID] else { continue }
      guard let item = itemsByID[taskID] else { continue }
      if item.fixedRowHeight != nil {
        continue
      }
      let measured = shellView.measureHeights(width: width, fixedDetailHeight: item.fixedDetailHeight)
      rowHeights[taskID] = measured.rowHeight
      detailHeights[taskID] = measured.detailHeight
      if item.fixedDetailHeight == nil {
        measurementCache.store(
          rowHeight: measured.rowHeight,
          expandedDetailHeight: measured.expandedDetailHeight,
          for: taskID
        )
      }
    }

    let layout = layoutEngine.makeLayout(
      rowOrder: rowOrder,
      availableWidth: width,
      rowHeights: rowHeights,
      detailHeights: detailHeights,
      previousLayout: lastAppliedLayout,
      reusableRange: normalizedReusableRange
    )

    if retainedTaskListNoteLayoutProbeLoggingEnabled,
      let scrollAnchorTaskID,
      let rowFrame = layout.rowFrames[scrollAnchorTaskID],
      let shellFrame = layout.shellFrames[scrollAnchorTaskID]
    {
      AppLogger.ui.info(
        "task-note relayout task=\(scrollAnchorTaskID.uuidString, privacy: .public) rowMinY=\(Int(rowFrame.minY.rounded()), privacy: .public) rowHeight=\(Int(rowFrame.height.rounded()), privacy: .public) shellHeight=\(Int(shellFrame.height.rounded()), privacy: .public) contentHeight=\(Int(layout.contentHeight.rounded()), privacy: .public)"
      )
    }

    lastAppliedLayout = layout
    lastAppliedLayoutFootprint = currentLayoutFootprint

    synchronizeMountedShellLayouts(taskIDs: mountedTaskIDs, width: width)

    let effectiveMotionQuality: MotionQuality =
      animated && !isScrollInteractionActive
      ? motionQuality
      : .disabled
    lastSyncAnimated = effectiveMotionQuality.allowsAnimation
    let visualUpdate = visualLayoutUpdate(for: layout)
    animationCoordinator.applyShellFrames(
      rowOrder: rowOrder,
      shellViews: shellViews,
      shellFrames: visualUpdate.layout.shellFrames,
      rowFrames: visualUpdate.layout.rowFrames,
      overlayView: containerView.overlayView,
      motionQuality: effectiveMotionQuality,
      affectedRange: visualUpdate.affectedRange
        ?? affectedAnimationRange(
          from: normalizedReusableRange,
          totalCount: rowOrder.count
        ),
      instantTaskIDs: newMountedTaskIDs
    )
    publishRowFramesIfNeeded(visualUpdate.layout.rowFrames)

    if abs(contentHeight.wrappedValue - layout.contentHeight) > 0.5 {
      DispatchQueue.main.async {
        self.contentHeight.wrappedValue = layout.contentHeight
      }
    }

    if !isScrollInteractionActive {
      restoreScrollAnchorIfNeeded(scrollAnchorState, layout: layout)
    }
    scrollRelayoutTriggerRect = virtualizationWindow().relayoutTriggerRect

    let elapsedMS = Int(((CACurrentMediaTime() - startedAt) * 1000).rounded())
    let mountedRatio =
      rowOrder.isEmpty
      ? 0
      : Int((Double(mountedTaskIDs.count) / Double(rowOrder.count) * 100).rounded())
    if let performanceSessionID, let performanceProjectID {
      ProjectDetailTaskListPerformanceRecorder.shared.recordRelayout(
        sessionID: performanceSessionID,
        projectID: performanceProjectID,
        elapsedMS: elapsedMS,
        rows: self.rowOrder.count,
        mounted: mountedTaskIDs.count,
        mountedRatio: mountedRatio,
        measured: measurementTaskIDs.count,
        reused: reusableIDs.count,
        hostedViews: self.lastHostedViewCount,
        animated: animated,
        virtualizationPressure: self.lastVirtualizationPressure,
        reason: reason
      )
    }
    if ProjectDetailTaskListPerformanceRecorder.isEnabled,
      elapsedMS >= retainedTaskListSlowRelayoutThresholdMS
    {
      AppLogger.ui.info(
        "task-list relayout slow \(elapsedMS, privacy: .public)ms reason=\(reason, privacy: .public) rows=\(self.rowOrder.count, privacy: .public) mounted=\(mountedTaskIDs.count, privacy: .public) mountedRatio=\(mountedRatio, privacy: .public)% measured=\(measurementTaskIDs.count, privacy: .public) reused=\(reusableIDs.count, privacy: .public) hostedViews=\(self.lastHostedViewCount, privacy: .public) editingNoteHosts=\(self.editingNoteHosts, privacy: .public) referenceLiveNoteHosts=\(self.referenceLiveNoteHosts, privacy: .public) referenceFrozenNoteHosts=\(self.referenceFrozenNoteHosts, privacy: .public) visibleOpenNotes=\(self.visibleOpenNotes, privacy: .public) animated=\(animated, privacy: .public) virtualizationPressure=\(self.lastVirtualizationPressure, privacy: .public)"
      )
    }
  }

  func publishRowFramesIfNeeded(_ frames: [UUID: CGRect]) {
    rowFrameStore.rowFrames = frames
    guard rowFrames.wrappedValue != frames else { return }
    DispatchQueue.main.async {
      guard self.rowFrames.wrappedValue != frames else { return }
      self.rowFrames.wrappedValue = frames
    }
  }

  func publishLiveWindowTaskIDsIfNeeded(_ taskIDs: Set<UUID>) {
    rowFrameStore.liveWindowTaskIDs = taskIDs
    let publishedTaskIDs =
      liveWindowRelevantTaskIDs.isEmpty
      ? Set<UUID>()
      : taskIDs.intersection(liveWindowRelevantTaskIDs)
    guard liveWindowTaskIDs.wrappedValue != publishedTaskIDs else { return }
    DispatchQueue.main.async {
      guard self.liveWindowTaskIDs.wrappedValue != publishedTaskIDs else { return }
      self.liveWindowTaskIDs.wrappedValue = publishedTaskIDs
    }
  }

  func refreshPublishedLiveWindowTaskIDs() {
    publishLiveWindowTaskIDsIfNeeded(rowFrameStore.liveWindowTaskIDs)
  }

  func visualLayoutUpdate(
    for layout: ProjectTaskRetainedListLayoutResult
  ) -> (layout: ProjectTaskRetainedListLayoutResult, affectedRange: Range<Int>?) {
    guard let localDraggedTaskID,
      let localDropIndicator
    else {
      return (layout, nil)
    }

    guard let sourceIndex = rowOrder.firstIndex(of: localDraggedTaskID),
      let sourceShellFrame = layout.shellFrames[localDraggedTaskID],
      let sourceRowFrame = layout.rowFrames[localDraggedTaskID],
      let targetIndex = rowOrder.firstIndex(of: localDropIndicator.targetTaskID)
    else {
      return (layout, nil)
    }

    let rawInsertionIndex =
      localDropIndicator.placement == .before
      ? targetIndex
      : targetIndex + 1
    let insertionIndex = max(0, min(rowOrder.count, rawInsertionIndex))

    if insertionIndex == sourceIndex || insertionIndex == sourceIndex + 1 {
      return (layout, nil)
    }

    var shellFrames = layout.shellFrames
    var rowFrames = layout.rowFrames
    let shellHeight = sourceShellFrame.height
    let rowHeight = sourceRowFrame.height

    if sourceIndex < insertionIndex {
      for index in (sourceIndex + 1)..<insertionIndex {
        let taskID = rowOrder[index]
        if var frame = shellFrames[taskID] {
          frame.origin.y -= shellHeight
          shellFrames[taskID] = frame
        }
        if var frame = rowFrames[taskID] {
          frame.origin.y -= shellHeight
          rowFrames[taskID] = frame
        }
      }

      let placeholderMinY: CGFloat
      if insertionIndex == rowOrder.count {
        placeholderMinY = max(0, layout.contentHeight - shellHeight)
      } else if insertionIndex > 0,
        let previousFrame = shellFrames[rowOrder[insertionIndex - 1]]
      {
        placeholderMinY = previousFrame.maxY
      } else {
        placeholderMinY = 0
      }

      shellFrames[localDraggedTaskID] = CGRect(
        x: sourceShellFrame.minX,
        y: placeholderMinY,
        width: sourceShellFrame.width,
        height: sourceShellFrame.height
      )
      rowFrames[localDraggedTaskID] = CGRect(
        x: sourceRowFrame.minX,
        y: placeholderMinY,
        width: sourceRowFrame.width,
        height: rowHeight
      )
    } else {
      for index in insertionIndex..<sourceIndex {
        let taskID = rowOrder[index]
        if var frame = shellFrames[taskID] {
          frame.origin.y += shellHeight
          shellFrames[taskID] = frame
        }
        if var frame = rowFrames[taskID] {
          frame.origin.y += shellHeight
          rowFrames[taskID] = frame
        }
      }

      let placeholderMinY = layout.shellFrames[rowOrder[insertionIndex]]?.minY ?? sourceShellFrame.minY
      shellFrames[localDraggedTaskID] = CGRect(
        x: sourceShellFrame.minX,
        y: placeholderMinY,
        width: sourceShellFrame.width,
        height: sourceShellFrame.height
      )
      rowFrames[localDraggedTaskID] = CGRect(
        x: sourceRowFrame.minX,
        y: placeholderMinY,
        width: sourceRowFrame.width,
        height: rowHeight
      )
    }

    let affectedRange = min(sourceIndex, insertionIndex)..<min(rowOrder.count, max(sourceIndex, insertionIndex) + 1)
    return (
      ProjectTaskRetainedListLayoutResult(
        shellFrames: shellFrames,
        rowFrames: rowFrames,
        contentHeight: layout.contentHeight
      ),
      affectedRange
    )
  }

  func updateVisibleRectObservation() {
    guard let clipView = containerView.enclosingScrollView?.contentView else { return }
    guard observedClipView !== clipView else { return }

    if let observedClipView {
      NotificationCenter.default.removeObserver(
        self,
        name: NSView.boundsDidChangeNotification,
        object: observedClipView
      )
    }

    clipView.postsBoundsChangedNotifications = true
    observedClipView = clipView
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleObservedClipViewBoundsChange(_:)),
      name: NSView.boundsDidChangeNotification,
      object: clipView
    )
  }

  @objc func handleObservedClipViewBoundsChange(_ notification: Notification) {
    lastObservedScrollBoundsChangeAt = CACurrentMediaTime()
    guard shouldRelayoutForVisibleRectChange() else { return }
    scheduleScrollRelayout()
  }

  var isScrollInteractionActive: Bool {
    (CACurrentMediaTime() - lastObservedScrollBoundsChangeAt) < 0.14
  }

  func mountedTaskIDs(for layout: ProjectTaskRetainedListLayoutResult) -> Set<UUID> {
    let bufferedRect = virtualizationWindow().bufferedRect

    var mounted = pinnedTaskIDs
    for taskID in rowOrder {
      guard let frame = layout.shellFrames[taskID] else { continue }
      if frame.intersects(bufferedRect) {
        mounted.insert(taskID)
      }
    }
    return mounted
  }

  func synchronizeMountedShellLayouts(taskIDs: Set<UUID>, width: CGFloat) {
    for taskID in taskIDs {
      guard let shellView = shellViews[taskID], let item = itemsByID[taskID] else { continue }
      shellView.applyResolvedLayout(
        width: width,
        fixedRowHeight: item.fixedRowHeight,
        fixedDetailHeight: item.fixedDetailHeight
      )
    }
  }

  func syncMountedShells(
    _ mountedTaskIDs: Set<UUID>,
    refreshExistingContent: Bool = true
  ) -> Set<UUID> {
    let removedIDs = Set(shellViews.keys).subtracting(mountedTaskIDs)
    for taskID in removedIDs {
      shellViews[taskID]?.clearPresentationAnimations()
      shellViews[taskID]?.removeFromSuperview()
      shellViews.removeValue(forKey: taskID)
    }

    var newMountedTaskIDs: Set<UUID> = []
    for taskID in rowOrder where mountedTaskIDs.contains(taskID) {
      guard let item = itemsByID[taskID] else { continue }
      if let existing = shellViews[taskID] {
        if refreshExistingContent {
          existing.update(
            rowSignature: item.rowRenderSignature,
            rowContent: item.rowContent,
            rowMeasurementSignature: item.rowMeasurementSignature,
            rowMeasurementContent: item.rowMeasurementContent,
            detailSignature: item.detailRenderSignature,
            detailContent: item.detailContent,
            detailMeasurementSignature: item.detailMeasurementSignature,
            detailMeasurementContent: item.detailMeasurementContent,
            readOnlyDetailSnapshot: item.readOnlyDetailSnapshot,
            detailIsVisible: item.detailIsVisible,
            suppressesBottomDivider: item.id == dividerSuppressionTaskID,
            suppressesRowViewRelayout: item.fixedRowHeight != nil,
            suppressesDetailViewRelayout: item.fixedDetailHeight != nil
          )
        }
      } else {
        newMountedTaskIDs.insert(item.id)
        let shellView = ProjectTaskRetainedListShellView(
          taskID: item.id,
          rowSignature: item.rowRenderSignature,
          rowContent: item.rowContent,
          rowMeasurementSignature: item.rowMeasurementSignature,
          rowMeasurementContent: item.rowMeasurementContent,
          detailSignature: item.detailRenderSignature,
          detailContent: item.detailContent,
          detailMeasurementSignature: item.detailMeasurementSignature,
          detailMeasurementContent: item.detailMeasurementContent
        )
        shellView.setLayoutDelegate(self)
        shellView.update(
          rowSignature: item.rowRenderSignature,
          rowContent: item.rowContent,
          rowMeasurementSignature: item.rowMeasurementSignature,
          rowMeasurementContent: item.rowMeasurementContent,
          detailSignature: item.detailRenderSignature,
          detailContent: item.detailContent,
          detailMeasurementSignature: item.detailMeasurementSignature,
          detailMeasurementContent: item.detailMeasurementContent,
          readOnlyDetailSnapshot: item.readOnlyDetailSnapshot,
          detailIsVisible: item.detailIsVisible,
          suppressesBottomDivider: item.id == dividerSuppressionTaskID,
          suppressesRowViewRelayout: item.fixedRowHeight != nil,
          suppressesDetailViewRelayout: item.fixedDetailHeight != nil
        )
        shellViews[item.id] = shellView
        containerView.addSubview(shellView, positioned: .below, relativeTo: containerView.overlayView)
      }
    }

    return newMountedTaskIDs
  }

  func reusableLayoutRange() -> Range<Int>? {
    guard
      let currentLayoutFootprint,
      let lastAppliedLayoutFootprint,
      lastAppliedLayout != nil,
      currentLayoutFootprint.availableWidth == lastAppliedLayoutFootprint.availableWidth,
      currentLayoutFootprint.rowOrder.count == lastAppliedLayoutFootprint.rowOrder.count
    else { return nil }

    let rowCount = currentLayoutFootprint.rowOrder.count
    var firstChangedIndex: Int?
    var lastChangedIndex: Int?

    for index in 0..<rowCount {
      let currentTaskID = currentLayoutFootprint.rowOrder[index]
      let previousTaskID = lastAppliedLayoutFootprint.rowOrder[index]
      let currentEntry = currentLayoutFootprint.entries[currentTaskID]
      let previousEntry = lastAppliedLayoutFootprint.entries[previousTaskID]
      let didChange =
        currentTaskID != previousTaskID
        || currentEntry != previousEntry

      guard didChange else { continue }
      if firstChangedIndex == nil {
        firstChangedIndex = index
      }
      lastChangedIndex = index
    }

    guard let firstChangedIndex, let lastChangedIndex else { return nil }
    return firstChangedIndex..<(lastChangedIndex + 1)
  }

  func reusableTaskIDs(for reusableRange: Range<Int>?) -> Set<UUID> {
    guard let reusableRange else { return [] }

    let prefixTaskIDs = rowOrder.prefix(reusableRange.lowerBound)
    let suffixTaskIDs = rowOrder.dropFirst(reusableRange.upperBound)
    return Set(prefixTaskIDs).union(suffixTaskIDs)
  }

  func measurementTaskIDs(
    mountedTaskIDs: Set<UUID>,
    newMountedTaskIDs: Set<UUID>,
    reusableIDs: Set<UUID>
  ) -> Set<UUID> {
    let reusableMountedTaskIDs = mountedTaskIDs.intersection(reusableIDs).subtracting(newMountedTaskIDs)
    return mountedTaskIDs.subtracting(reusableMountedTaskIDs)
  }

  func affectedAnimationRange(
    from reusableRange: Range<Int>?,
    totalCount: Int
  ) -> Range<Int>? {
    guard let reusableRange else { return nil }
    return reusableRange.lowerBound..<min(totalCount, reusableRange.upperBound + 1)
  }

  func currentScrollAnchorState() -> (taskID: UUID, topOffset: CGFloat)? {
    guard let scrollAnchorTaskID,
      let previousLayout = lastAppliedLayout,
      let rowFrame = previousLayout.rowFrames[scrollAnchorTaskID]
    else { return nil }

    let visibleRect = containerView.visibleRect
    return (scrollAnchorTaskID, rowFrame.minY - visibleRect.minY)
  }

  func restoreScrollAnchorIfNeeded(
    _ scrollAnchorState: (taskID: UUID, topOffset: CGFloat)?,
    layout: ProjectTaskRetainedListLayoutResult
  ) {
    guard let scrollAnchorState,
      let rowFrame = layout.rowFrames[scrollAnchorState.taskID],
      let scrollView = containerView.enclosingScrollView
    else { return }

    let clipView = scrollView.contentView
    let currentBounds = clipView.bounds
    let maxY = max(0, layout.contentHeight - currentBounds.height)
    let targetY = min(max(0, rowFrame.minY - scrollAnchorState.topOffset), maxY)
    guard abs(currentBounds.origin.y - targetY) > 0.5 else { return }

    if retainedTaskListNoteLayoutProbeLoggingEnabled {
      AppLogger.ui.info(
        "task-note scroll-anchor task=\(scrollAnchorState.taskID.uuidString, privacy: .public) currentY=\(Int(currentBounds.origin.y.rounded()), privacy: .public) targetY=\(Int(targetY.rounded()), privacy: .public) rowMinY=\(Int(rowFrame.minY.rounded()), privacy: .public) topOffset=\(Int(scrollAnchorState.topOffset.rounded()), privacy: .public)"
      )
    }

    clipView.scroll(to: CGPoint(x: currentBounds.origin.x, y: targetY))
    scrollView.reflectScrolledClipView(clipView)
  }

  func virtualizationWindow() -> (
    visibleRect: CGRect,
    bufferedRect: CGRect,
    relayoutTriggerRect: CGRect
  ) {
    let visibleRect = containerView.visibleRect
    let fallbackHeight = max(containerView.bounds.height, 900)
    let baseRect =
      visibleRect.height > 1
      ? visibleRect
      : CGRect(x: 0, y: 0, width: max(0, floor(lastMeasuredWidth)), height: fallbackHeight)
    let relayoutBufferHeight = max(
      retainedTaskListMountedBufferMinimum,
      baseRect.height * retainedTaskListMountedBufferViewportFactor
    )
    let mountedBufferHeight = max(
      retainedTaskListShellRetentionMinimum,
      baseRect.height * retainedTaskListShellRetentionViewportFactor
    )
    let bufferedRect = baseRect.insetBy(dx: 0, dy: -mountedBufferHeight)
    let relayoutBufferedRect = baseRect.insetBy(dx: 0, dy: -relayoutBufferHeight)
    // Keep a hysteresis band so pure scrolling does not force a relayout on every bounds tick.
    let triggerInset = min(
      relayoutBufferHeight * 0.5,
      max(
        retainedTaskListRelayoutTriggerMinimum,
        baseRect.height * retainedTaskListRelayoutTriggerViewportFactor
      )
    )
    let relayoutTriggerRect = relayoutBufferedRect.insetBy(dx: 0, dy: triggerInset)
    return (baseRect, bufferedRect, relayoutTriggerRect)
  }

  func shouldRelayoutForVisibleRectChange() -> Bool {
    guard lastAppliedLayout != nil else { return true }
    let window = virtualizationWindow()
    guard let scrollRelayoutTriggerRect else { return true }
    if abs(window.visibleRect.width - scrollRelayoutTriggerRect.width) > 0.5 {
      return true
    }
    return !scrollRelayoutTriggerRect.contains(window.visibleRect)
  }

  func canDeferDataDrivenRelayout() -> Bool {
    guard
      let currentLayoutFootprint,
      let lastAppliedLayoutFootprint,
      lastAppliedLayout != nil
    else { return false }
    return currentLayoutFootprint.availableWidth == lastAppliedLayoutFootprint.availableWidth
      && currentLayoutFootprint.rowOrder == lastAppliedLayoutFootprint.rowOrder
  }

  func scheduleIdleDeferredRelayout(reason: String, reusableRange: Range<Int>? = nil) {
    pendingIdleRelayoutReason = reason
    if let reusableRange {
      if let existingRange = pendingIdleRelayoutRange {
        let lowerBound = min(existingRange.lowerBound, reusableRange.lowerBound)
        let upperBound = max(existingRange.upperBound, reusableRange.upperBound)
        pendingIdleRelayoutRange = lowerBound..<upperBound
      } else {
        pendingIdleRelayoutRange = reusableRange
      }
    } else {
      pendingIdleRelayoutRange = nil
    }
    pendingIdleRelayoutWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      if self.isScrollInteractionActive {
        self.scheduleIdleDeferredRelayout(reason: reason, reusableRange: reusableRange)
        return
      }

      let resolvedReason = self.pendingIdleRelayoutReason ?? reason
      let resolvedRange = self.pendingIdleRelayoutRange
      self.pendingIdleRelayoutWorkItem = nil
      self.pendingIdleRelayoutReason = nil
      self.pendingIdleRelayoutRange = nil
      self.relayoutRows(animated: false, reusableRange: resolvedRange, reason: resolvedReason)
    }

    pendingIdleRelayoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
  }

  func canUseScrollWindowSync() -> Bool {
    guard lastAppliedLayout != nil else { return false }
    let window = virtualizationWindow()
    guard let scrollRelayoutTriggerRect else { return false }
    return abs(window.visibleRect.width - scrollRelayoutTriggerRect.width) <= 0.5
  }

  func shouldUseImmediateScrollRelayout() -> Bool {
    let window = virtualizationWindow()
    guard let scrollRelayoutTriggerRect else { return true }
    if abs(window.visibleRect.width - scrollRelayoutTriggerRect.width) > 0.5 {
      return true
    }

    let upwardOvershoot = max(0, scrollRelayoutTriggerRect.minY - window.visibleRect.minY)
    let downwardOvershoot = max(0, window.visibleRect.maxY - scrollRelayoutTriggerRect.maxY)
    let overshoot = max(upwardOvershoot, downwardOvershoot)
    return overshoot >= retainedTaskListImmediateRelayoutOvershootThreshold
  }

  func performScrollWindowSync(immediate: Bool, refreshExistingContent: Bool) {
    let startedAt = CACurrentMediaTime()
    guard let layout = lastAppliedLayout else {
      relayoutRows(animated: false, reason: "scroll-window-sync-fallback")
      return
    }

    let mountedTaskIDs = mountedTaskIDs(for: layout)
    let newMountedTaskIDs = syncMountedShells(
      mountedTaskIDs,
      refreshExistingContent: refreshExistingContent
    )
    lastMountedTaskCount = mountedTaskIDs.count
    lastMeasuredTaskCount = 0
    lastHostedViewCount = mountedTaskIDs.count * 4
    lastVirtualizationPressure =
      rowOrder.count >= 40 && mountedTaskIDs.count * 100 >= max(1, rowOrder.count) * 80
    publishLiveWindowTaskIDsIfNeeded(mountedTaskIDs)

    synchronizeMountedShellLayouts(taskIDs: mountedTaskIDs, width: lastMeasuredWidth)

    let visualUpdate = visualLayoutUpdate(for: layout)
    animationCoordinator.applyShellFrames(
      rowOrder: rowOrder,
      shellViews: shellViews,
      shellFrames: visualUpdate.layout.shellFrames,
      rowFrames: visualUpdate.layout.rowFrames,
      overlayView: containerView.overlayView,
      motionQuality: .disabled,
      affectedRange: nil,
      instantTaskIDs: newMountedTaskIDs
    )
    scrollRelayoutTriggerRect = virtualizationWindow().relayoutTriggerRect

    let elapsedMS = Int(((CACurrentMediaTime() - startedAt) * 1000).rounded())
    if let performanceSessionID, let performanceProjectID {
      ProjectDetailTaskListPerformanceRecorder.shared.recordWindowSync(
        sessionID: performanceSessionID,
        projectID: performanceProjectID,
        elapsedMS: elapsedMS,
        rows: rowOrder.count,
        mounted: mountedTaskIDs.count,
        hostedViews: lastHostedViewCount,
        instantMounted: newMountedTaskIDs.count,
        immediate: immediate,
        refreshedContent: refreshExistingContent,
        virtualizationPressure: lastVirtualizationPressure
      )
    }
    if ProjectDetailTaskListPerformanceRecorder.isEnabled,
      elapsedMS >= retainedTaskListSlowSyncThresholdMS
    {
      let rowCount = self.rowOrder.count
      let hostedViewCount = self.lastHostedViewCount
      let virtualizationPressure = self.lastVirtualizationPressure
      AppLogger.ui.info(
        "task-list window-sync slow \(elapsedMS, privacy: .public)ms rows=\(rowCount, privacy: .public) mounted=\(mountedTaskIDs.count, privacy: .public) hostedViews=\(hostedViewCount, privacy: .public) instantMounted=\(newMountedTaskIDs.count, privacy: .public) editingNoteHosts=\(self.editingNoteHosts, privacy: .public) referenceLiveNoteHosts=\(self.referenceLiveNoteHosts, privacy: .public) referenceFrozenNoteHosts=\(self.referenceFrozenNoteHosts, privacy: .public) visibleOpenNotes=\(self.visibleOpenNotes, privacy: .public) immediate=\(immediate, privacy: .public) refreshedContent=\(refreshExistingContent, privacy: .public) virtualizationPressure=\(virtualizationPressure, privacy: .public)"
      )
    }
  }

  func scheduleScrollRelayout() {
    if shouldUseImmediateScrollRelayout() {
      if isPerformingImmediateScrollRelayout {
        pendingImmediateScrollRelayout = true
        return
      }

      isPerformingImmediateScrollRelayout = true
      if canUseScrollWindowSync() {
        performScrollWindowSync(immediate: true, refreshExistingContent: false)
      } else {
        relayoutRows(animated: false, reason: "scroll-immediate")
      }
      isPerformingImmediateScrollRelayout = false

      guard pendingImmediateScrollRelayout else { return }
      pendingImmediateScrollRelayout = false
      DispatchQueue.main.async { [weak self] in
        self?.scheduleScrollRelayout()
      }
      return
    }

    guard !scrollRelayoutScheduled else { return }
    scrollRelayoutScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.scrollRelayoutScheduled = false
      if self.canUseScrollWindowSync() {
        self.performScrollWindowSync(immediate: false, refreshExistingContent: false)
      } else {
        self.relayoutRows(animated: false, reason: "scroll-coalesced")
      }
    }
  }
}
