import AppKit
import QuartzCore
import SwiftUI

@MainActor
struct ProjectTaskRetainedListView: NSViewRepresentable {
  let items: [ProjectTaskRetainedListItem]
  let availableWidth: CGFloat
  let performanceSessionID: UUID
  let performanceProjectID: UUID
  let editingNoteHosts: Int
  let referenceLiveNoteHosts: Int
  let referenceFrozenNoteHosts: Int
  let visibleOpenNotes: Int
  let highlightedTaskID: UUID?
  let dropIndicator: TaskDropIndicator?
  let localDraggedTaskID: UUID?
  let localDropIndicator: TaskDropIndicator?
  let scrollAnchorTaskID: UUID?
  let pinnedTaskIDs: Set<UUID>
  let liveWindowRelevantTaskIDs: Set<UUID>
  let isDragSessionActive: Bool
  let motionQuality: MotionQuality

  @Binding var contentHeight: CGFloat
  @Binding var rowFrames: [UUID: CGRect]
  @Binding var liveWindowTaskIDs: Set<UUID>
  let rowFrameStore: ProjectTaskRetainedListFrameStore

  @MainActor
  final class Coordinator: NSObject, ProjectTaskRetainedListRowLayoutDelegate {
    let containerView = ProjectTaskRetainedListContainerView(frame: .zero)
    let layoutEngine = ProjectTaskRetainedListLayoutEngine()
    let animationCoordinator = ProjectTaskListAnimationCoordinator()
    let measurementCache = ProjectTaskMeasurementCache()

    var shellViews: [UUID: ProjectTaskRetainedListShellView] = [:]
    var itemsByID: [UUID: ProjectTaskRetainedListItem] = [:]
    var rowOrder: [UUID] = []
    var pinnedTaskIDs: Set<UUID> = []
    var localDraggedTaskID: UUID?
    var localDropIndicator: TaskDropIndicator?
    var scrollAnchorTaskID: UUID?
    var liveWindowRelevantTaskIDs: Set<UUID> = []
    var contentHeight: Binding<CGFloat>
    var rowFrames: Binding<[UUID: CGRect]>
    var liveWindowTaskIDs: Binding<Set<UUID>>
    var rowFrameStore: ProjectTaskRetainedListFrameStore
    var motionQuality: MotionQuality = .full
    var isDragSessionActive = false
    var lastMeasuredWidth: CGFloat = 0
    var dividerSuppressionTaskID: UUID?
    var currentLayoutFootprint: ProjectTaskRetainedListLayoutFootprint?
    var lastAppliedLayoutFootprint: ProjectTaskRetainedListLayoutFootprint?
    var lastAppliedLayout: ProjectTaskRetainedListLayoutResult?
    var lastMountedTaskCount = 0
    var lastMeasuredTaskCount = 0
    var lastHostedViewCount = 0
    var lastSyncAnimated = false
    var lastVirtualizationPressure = false
    var performanceSessionID: UUID?
    var performanceProjectID: UUID?
    var editingNoteHosts = 0
    var referenceLiveNoteHosts = 0
    var referenceFrozenNoteHosts = 0
    var visibleOpenNotes = 0
    var scrollRelayoutTriggerRect: CGRect?
    var scrollRelayoutScheduled = false
    var isPerformingImmediateScrollRelayout = false
    var pendingImmediateScrollRelayout = false
    var lastObservedScrollBoundsChangeAt: CFTimeInterval = 0
    var pendingIdleRelayoutWorkItem: DispatchWorkItem?
    var pendingIdleRelayoutReason: String?
    var pendingIdleRelayoutRange: Range<Int>?
    weak var observedClipView: NSClipView?

    init(
      contentHeight: Binding<CGFloat>,
      rowFrames: Binding<[UUID: CGRect]>,
      liveWindowTaskIDs: Binding<Set<UUID>>,
      rowFrameStore: ProjectTaskRetainedListFrameStore
    ) {
      self.contentHeight = contentHeight
      self.rowFrames = rowFrames
      self.liveWindowTaskIDs = liveWindowTaskIDs
      self.rowFrameStore = rowFrameStore
      super.init()
    }

    func projectTaskRetainedListRowNeedsRelayout(_ taskID: UUID) {
      guard shellViews[taskID] != nil else { return }
      if let item = itemsByID[taskID],
        item.fixedRowHeight != nil,
        item.fixedDetailHeight != nil
      {
        return
      }
      let reusableRange =
        rowOrder.firstIndex(of: taskID)
        .map { $0..<(min(rowOrder.count, $0 + 1)) }
      if isDragSessionActive,
        let reusableRange
      {
        relayoutRows(
          animated: false,
          reusableRange: reusableRange,
          reason: "drag-invalidate"
        )
        return
      }
      if isScrollInteractionActive {
        scheduleIdleDeferredRelayout(reason: "row-invalidate", reusableRange: reusableRange)
        return
      }
      relayoutRows(
        animated: motionQuality.allowsAnimation && !isScrollInteractionActive,
        reusableRange: reusableRange,
        reason: "row-invalidate"
      )
    }

    func sync(
      items: [ProjectTaskRetainedListItem],
      availableWidth: CGFloat,
      highlightedTaskID: UUID?,
      dropIndicator: TaskDropIndicator?,
      localDraggedTaskID: UUID?,
      localDropIndicator: TaskDropIndicator?,
      scrollAnchorTaskID: UUID?,
      pinnedTaskIDs: Set<UUID>,
      isDragSessionActive: Bool,
      motionQuality: MotionQuality
    ) {
      let startedAt = CACurrentMediaTime()
      var usedLayoutFastPath = false
      lastSyncAnimated = false

      defer {
        let elapsedMS = Int(((CACurrentMediaTime() - startedAt) * 1000).rounded())
        if let performanceSessionID, let performanceProjectID {
          ProjectDetailTaskListPerformanceRecorder.shared.recordSync(
            sessionID: performanceSessionID,
            projectID: performanceProjectID,
            elapsedMS: elapsedMS,
            rows: items.count,
            mounted: self.lastMountedTaskCount,
            measured: self.lastMeasuredTaskCount,
            hostedViews: self.lastHostedViewCount,
            pinned: pinnedTaskIDs.count,
            animated: self.lastSyncAnimated,
            fastPath: usedLayoutFastPath,
            virtualizationPressure: self.lastVirtualizationPressure
          )
        }
        if ProjectDetailTaskListPerformanceRecorder.isEnabled,
          elapsedMS >= retainedTaskListSlowSyncThresholdMS
        {
          AppLogger.ui.info(
            "task-list sync slow \(elapsedMS, privacy: .public)ms rows=\(items.count, privacy: .public) mounted=\(self.lastMountedTaskCount, privacy: .public) measured=\(self.lastMeasuredTaskCount, privacy: .public) hostedViews=\(self.lastHostedViewCount, privacy: .public) pinned=\(pinnedTaskIDs.count, privacy: .public) editingNoteHosts=\(self.editingNoteHosts, privacy: .public) referenceLiveNoteHosts=\(self.referenceLiveNoteHosts, privacy: .public) referenceFrozenNoteHosts=\(self.referenceFrozenNoteHosts, privacy: .public) visibleOpenNotes=\(self.visibleOpenNotes, privacy: .public) animated=\(self.lastSyncAnimated, privacy: .public) fastPath=\(usedLayoutFastPath, privacy: .public) virtualizationPressure=\(self.lastVirtualizationPressure, privacy: .public)"
          )
        }
      }

      self.motionQuality = motionQuality
      self.isDragSessionActive = isDragSessionActive
      self.pinnedTaskIDs = pinnedTaskIDs
      self.localDraggedTaskID = localDraggedTaskID
      self.localDropIndicator = localDropIndicator
      self.scrollAnchorTaskID = scrollAnchorTaskID
      containerView.overlayView.highlightedTaskID = highlightedTaskID
      containerView.overlayView.dropIndicator = localDraggedTaskID == nil ? dropIndicator : nil

      let clampedWidth = max(0, floor(availableWidth))
      if clampedWidth > 1 {
        lastMeasuredWidth = clampedWidth
      }
      measurementCache.updateWidth(lastMeasuredWidth)

      let itemIDs = Set(items.map(\.id))
      itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
      measurementCache.removeMissing(keeping: itemIDs)

      rowOrder = items.map(\.id)
      containerView.overlayView.rowOrder = rowOrder
      currentLayoutFootprint = ProjectTaskRetainedListLayoutFootprint(
        rowOrder: rowOrder,
        availableWidth: lastMeasuredWidth,
        entries: Dictionary(
          uniqueKeysWithValues: items.map {
            (
              $0.id,
              ProjectTaskRetainedListLayoutFootprint.Entry(
                rowMeasurementSignature: $0.rowMeasurementSignature,
                detailMeasurementSignature: $0.detailMeasurementSignature,
                detailIsVisible: $0.detailIsVisible,
                fixedRowHeight: $0.fixedRowHeight.map { Int($0.rounded()) },
                fixedDetailHeight: $0.fixedDetailHeight.map { Int($0.rounded()) }
              )
            )
          }
        )
      )
      dividerSuppressionTaskID = taskDropDividerSuppressionTaskID(
        rowOrder: rowOrder,
        dropIndicator: dropIndicator
      )

      if let currentLayoutFootprint,
        let lastAppliedLayout,
        currentLayoutFootprint == lastAppliedLayoutFootprint
      {
        usedLayoutFastPath = true
        let mountedTaskIDs = mountedTaskIDs(for: lastAppliedLayout)
        let newMountedTaskIDs = syncMountedShells(mountedTaskIDs)
        lastMountedTaskCount = mountedTaskIDs.count
        lastMeasuredTaskCount = 0
        lastHostedViewCount = mountedTaskIDs.count * 4
        lastVirtualizationPressure =
          rowOrder.count >= 40 && mountedTaskIDs.count * 100 >= max(1, rowOrder.count) * 80
        synchronizeMountedShellLayouts(taskIDs: mountedTaskIDs, width: lastMeasuredWidth)
        publishLiveWindowTaskIDsIfNeeded(mountedTaskIDs)
        let visualUpdate = visualLayoutUpdate(for: lastAppliedLayout)
        let shouldAnimateFastPathFrames =
          isDragSessionActive
          || localDraggedTaskID != nil
          || localDropIndicator != nil
          || dropIndicator != nil
        let fastPathMotionQuality: MotionQuality = shouldAnimateFastPathFrames ? motionQuality : .disabled
        lastSyncAnimated = fastPathMotionQuality.allowsAnimation
        animationCoordinator.applyShellFrames(
          rowOrder: rowOrder,
          shellViews: shellViews,
          shellFrames: visualUpdate.layout.shellFrames,
          rowFrames: visualUpdate.layout.rowFrames,
          overlayView: containerView.overlayView,
          motionQuality: fastPathMotionQuality,
          affectedRange: visualUpdate.affectedRange,
          instantTaskIDs: newMountedTaskIDs
        )
        publishRowFramesIfNeeded(visualUpdate.layout.rowFrames)
        if abs(contentHeight.wrappedValue - lastAppliedLayout.contentHeight) > 0.5 {
          DispatchQueue.main.async {
            self.contentHeight.wrappedValue = lastAppliedLayout.contentHeight
          }
        }
        return
      }

      for item in items {
        measurementCache.prepare(
          taskID: item.id,
          rowMeasurementSignature: item.rowMeasurementSignature,
          detailMeasurementSignature: item.detailMeasurementSignature
        )
      }
      updateVisibleRectObservation()
      let reusableRange = reusableLayoutRange()
      if isScrollInteractionActive,
        canDeferDataDrivenRelayout()
      {
        performScrollWindowSync(immediate: false, refreshExistingContent: true)
        scheduleIdleDeferredRelayout(reason: "data-change", reusableRange: reusableRange)
        return
      }
      relayoutRows(
        animated: motionQuality.allowsAnimation && !isScrollInteractionActive,
        reusableRange: reusableRange,
        reason: "data-change"
      )
    }

  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      contentHeight: $contentHeight,
      rowFrames: $rowFrames,
      liveWindowTaskIDs: $liveWindowTaskIDs,
      rowFrameStore: rowFrameStore
    )
  }

  func makeNSView(context: Context) -> ProjectTaskRetainedListContainerView {
    context.coordinator.containerView
  }

  func updateNSView(_ nsView: ProjectTaskRetainedListContainerView, context: Context) {
    context.coordinator.contentHeight = $contentHeight
    context.coordinator.rowFrames = $rowFrames
    context.coordinator.liveWindowTaskIDs = $liveWindowTaskIDs
    context.coordinator.liveWindowRelevantTaskIDs = liveWindowRelevantTaskIDs
    context.coordinator.rowFrameStore = rowFrameStore
    context.coordinator.refreshPublishedLiveWindowTaskIDs()
    context.coordinator.performanceSessionID = performanceSessionID
    context.coordinator.performanceProjectID = performanceProjectID
    context.coordinator.editingNoteHosts = editingNoteHosts
    context.coordinator.referenceLiveNoteHosts = referenceLiveNoteHosts
    context.coordinator.referenceFrozenNoteHosts = referenceFrozenNoteHosts
    context.coordinator.visibleOpenNotes = visibleOpenNotes
    ProjectDetailTaskListPerformanceRecorder.shared.touchSession(
      performanceSessionID,
      projectID: performanceProjectID
    )
    context.coordinator.sync(
      items: items,
      availableWidth: availableWidth,
      highlightedTaskID: highlightedTaskID,
      dropIndicator: dropIndicator,
      localDraggedTaskID: localDraggedTaskID,
      localDropIndicator: localDropIndicator,
      scrollAnchorTaskID: scrollAnchorTaskID,
      pinnedTaskIDs: pinnedTaskIDs,
      isDragSessionActive: isDragSessionActive,
      motionQuality: motionQuality
    )
  }
}
