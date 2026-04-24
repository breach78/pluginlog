import SwiftData
import SwiftUI

// Composition root only.
// Row/canvas ownership: TimelineBoardRows.swift
// Overlay ownership: TimelineBoardOverlays.swift
// Action/undo ownership: TimelineBoardActions.swift
// Refresh/scroll ownership: TimelineBoardRefresh.swift
struct TimelineBoardView: View {
  struct TimelineBoardSnapshot {
    let bars: [TimelineProjectBar]
    let watchedSourceSignature: Int
    let rowLayouts: [TimelineRowLayout]
    let barsPresentationSignature: Int
  }

  struct TimelineViewportSnapshot {
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let rowsHeight: CGFloat
    let boardWidth: CGFloat
    let boardHeight: CGFloat
    let visibleLowerOffset: Int
    let visibleUpperOffset: Int
    let boardVersion: Int
    let leftVersion: Int
    let topVersion: Int
    let shouldPublishVerticalOffset: Bool
    let shouldPublishPreciseHoverOffsets: Bool
  }

  final class TimelineScrollSessionMetrics {
    let startedAt: Date
    var offsetEvents: Int
    var preciseHoverOffsetEvents: Int
    var suppressedTaskBadgeHoverEvents: Int
    var suppressedDayHeaderHoverEvents: Int
    var lastHorizontalOffset: CGFloat
    var lastVerticalOffset: CGFloat

    init(
      startedAt: Date,
      offsetEvents: Int,
      preciseHoverOffsetEvents: Int,
      suppressedTaskBadgeHoverEvents: Int,
      suppressedDayHeaderHoverEvents: Int,
      lastHorizontalOffset: CGFloat,
      lastVerticalOffset: CGFloat
    ) {
      self.startedAt = startedAt
      self.offsetEvents = offsetEvents
      self.preciseHoverOffsetEvents = preciseHoverOffsetEvents
      self.suppressedTaskBadgeHoverEvents = suppressedTaskBadgeHoverEvents
      self.suppressedDayHeaderHoverEvents = suppressedDayHeaderHoverEvents
      self.lastHorizontalOffset = lastHorizontalOffset
      self.lastVerticalOffset = lastVerticalOffset
    }
  }

  @Binding var projectListSortMode: ProjectListSortMode
  @EnvironmentObject var appState: AppState
  @Environment(\.modelContext) var modelContext
  @Environment(\.undoManager) var undoManager

  let projectIDs: [UUID]
  let showsProjectPassthroughFrames: Bool
  let isActive: Bool
  let selectedProjectID: UUID?
  let onSelectProject: (UUID) -> Void
  let onToggleProjectSelection: (UUID) -> Void

  @State var anchorDate = Calendar.autoupdatingCurrent.startOfDay(for: .now)
  @State var dayRange: ClosedRange<Int> = -14...240
  @State var horizontalOffsetX: CGFloat = 0
  @State var verticalOffsetY: CGFloat = 0
  @State var requestedOffsetX: CGFloat?
  @State var didSetInitialScrollPosition = false
  @State var scrollRequestGeneration = 0
  @State var draggingProjectID: UUID?
  @State var projectDropIndicator: TimelineProjectDropIndicator?
  @State var taskDropTargetProjectID: UUID?
  @State var showAddProjectPopover = false
  @State var isCreatingProject = false
  @State var pendingDeleteProjectID: UUID?
  @State var pendingDeleteProjectTitle: String = ""
  @State var workspaceTimelineProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord] = [:]
  @State var workspaceTimelineProjectSummaries: [UUID: ProjectSummaryRecord] = [:]
  @State var workspaceTimelineScheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]] = [:]
  @State var retainedTimelineCalendarBridgeDecisionsByTaskID:
    [UUID: RetainedCalendarBridgeDecision] = [:]
  @State var cachedTimelineBars: [TimelineProjectBar] = []
  @State var cachedTimelineRowLayouts: [TimelineRowLayout] = []
  @State var cachedTimelineBarsSourceSignature: Int?
  @State var cachedTimelineBarsPresentationSignature: Int?
  @State var hoveredTimelineTaskBadgeID: String?
  @State var activeTimelineTaskBadgeID: String?
  @State var timelineTaskBadgeShowWorkItem: DispatchWorkItem?
  @State var timelineTaskBadgeHideWorkItem: DispatchWorkItem?
  @State var cachedTimelineDayHeaderSections: [Date: [TimelineDayHeaderOverlayProjectSection]]
    = [:]
  @State var cachedTimelineDayHeaderSourceSignature: Int?
  @State var hoveredTimelineDayHeaderOffset: Int?
  @State var activeTimelineDayHeaderOffset: Int?
  @State var timelineDayHeaderShowWorkItem: DispatchWorkItem?
  @State var timelineDayHeaderHideWorkItem: DispatchWorkItem?
  @State var midnightRefreshTimer: Timer?
  @State var isHoveringPinnedLeftColumn = false
  @State var overlayMetricsCache = TimelineOverlayMetricsCache()
  @State var timelineScrollSession: TimelineScrollSessionMetrics?
  @State var timelineScrollIdleWorkItem: DispatchWorkItem?
  @State var didPrewarmTimelineScrollMode = false

  let titleColumnWidth: CGFloat = 200
  let timelineTitleColumnHorizontalPadding: CGFloat = 12
  let priorityStageRailWidth: CGFloat = 3
  let priorityCountLaneReserve: CGFloat = 92
  let headerHeight: CGFloat = 50
  let monthHeaderReservedHeight: CGFloat = 18
  let monthLabelTopPadding: CGFloat = 1
  let rowMetrics = TimelineRowMetrics(height: 30, spacing: 8, contentInsetY: 4)
  let priorityDoRowHeightMultiplier: CGFloat = 1.5
  let progressMarkerSize: CGFloat = 8
  let horizontalEdgePadding: CGFloat = 16
  let topEdgePadding: CGFloat = 0
  let bottomEdgePadding: CGFloat = 16
  let seedPaddingDays = 21
  let fallbackPastDays = 14
  let minimumFutureDays = 240
  let monthBadgeWidth: CGFloat = 124
  let jumpLeftInsetDays = 3
  let timelineTaskBadgeOverlayWidth: CGFloat = 220
  let timelineDayHeaderOverlayWidth: CGFloat = 260
  let timelineTaskBadgeHeight: CGFloat = 18
  let timelineTaskBadgeOverlayAboveOffset: CGFloat = 8
  let timelineTaskBadgeOverlayBelowOffset: CGFloat = -4
  let timelineTaskBadgeShowDelay: TimeInterval = 0.20
  let timelineTaskBadgeHideDelay: TimeInterval = 0.26
  let timelineDayHeaderShowDelay: TimeInterval = 0.18
  let timelineDayHeaderHideDelay: TimeInterval = 0.42
  let timelineScrollIdleDelay: TimeInterval = 0.18
  let deadlineMarkerWidth: CGFloat = 10
  let completedHistoryVisiblePastDays = 14
  let reminderColorPalette: [(name: String, hex: String)] = [
    ("파랑", "#0A84FF"),
    ("남색", "#5856D6"),
    ("보라", "#BF5AF2"),
    ("분홍", "#FF2D55"),
    ("빨강", "#FF3B30"),
    ("주황", "#FF9500"),
    ("노랑", "#FFD60A"),
    ("초록", "#34C759"),
    ("청록", "#30B0C7"),
    ("하늘", "#64D2FF"),
    ("갈색", "#A2845E"),
    ("회색", "#8E8E93"),
  ]
  var dayColumnWidth: CGFloat {
    min(max(appState.timelineDayColumnWidth, 22), 88)
  }

  var calendar: Calendar { Calendar.autoupdatingCurrent }
  var dayOffsets: [Int] { Array(dayRange) }
  var timelineWidth: CGFloat { CGFloat(dayOffsets.count) * dayColumnWidth }
  var activeProjectIDs: [UUID] {
    TimelineBoardReadPath.normalizedProjectIDs(projectIDs)
  }
  var activeProjectIDSet: Set<UUID> {
    Set(activeProjectIDs)
  }
  var showsTimelineLoadingState: Bool {
    !activeProjectIDs.isEmpty
      && !TimelineBoardReadPath.hasCompleteWorkspaceCoverage(
        projectIDs: activeProjectIDs,
        workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
        scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID
      )
  }
  var isTimelineScrolling: Bool { timelineScrollSession != nil }
  var canInteractivelyReorderProjects: Bool {
    projectListSortMode.allowsInteractiveReordering
  }
  let selectionHighlightColor = Color(red: 0.84, green: 0.94, blue: 1.0)

  init(
    projectListSortMode: Binding<ProjectListSortMode>,
    projectIDs: [UUID] = [],
    showsProjectPassthroughFrames: Bool = false,
    isActive: Bool = true,
    selectedProjectID: UUID? = nil,
    onSelectProject: @escaping (UUID) -> Void,
    onToggleProjectSelection: @escaping (UUID) -> Void
  ) {
    _projectListSortMode = projectListSortMode
    self.projectIDs = projectIDs
    self.showsProjectPassthroughFrames = showsProjectPassthroughFrames
    self.isActive = isActive
    self.selectedProjectID = selectedProjectID
    self.onSelectProject = onSelectProject
    self.onToggleProjectSelection = onToggleProjectSelection
  }

  var body: some View {
    timelineBoardRoot
  }

  var timelineBoardSnapshot: TimelineBoardSnapshot {
    let isMotionSuppressed = appState.isEditorMotionSuppressed
    let watchedSourceSignature =
      isMotionSuppressed
      ? (cachedTimelineBarsSourceSignature ?? 0)
      : timelineRefreshSignature(
        projectIDs: activeProjectIDs,
        workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
        workspaceProjectSummaries: workspaceTimelineProjectSummaries,
        scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID
      )
    let hasCachedBars = !cachedTimelineBars.isEmpty
    let shouldUseCachedBars =
      !isActive
      ? hasCachedBars
      : isMotionSuppressed
      ? hasCachedBars
      : (cachedTimelineBarsSourceSignature == watchedSourceSignature && hasCachedBars)
    let bars =
      shouldUseCachedBars
      ? cachedTimelineBars
      : computedLiveBars(
        projectIDs: activeProjectIDs,
        workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
        workspaceProjectSummaries: workspaceTimelineProjectSummaries,
        scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID
      )
    let rowLayouts =
      shouldUseCachedBars && !cachedTimelineRowLayouts.isEmpty
      ? cachedTimelineRowLayouts
      : buildRowLayouts(for: bars)

    return TimelineBoardSnapshot(
      bars: bars,
      watchedSourceSignature: watchedSourceSignature,
      rowLayouts: rowLayouts,
      barsPresentationSignature:
        shouldUseCachedBars
        ? (cachedTimelineBarsPresentationSignature ?? timelineSignature(for: bars))
        : timelineSignature(for: bars)
    )
  }

  private var timelineBoardRoot: some View {
    let snapshot = timelineBoardSnapshot

    return GeometryReader { proxy in
      timelineBoardViewportSection(proxy: proxy, snapshot: snapshot)
    }
    .onAppear {
      refreshAnchorDateIfNeeded()
      let liveSourceSignature = timelineRefreshSignature(
        projectIDs: activeProjectIDs,
        workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
        workspaceProjectSummaries: workspaceTimelineProjectSummaries,
        scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID
      )
      let refreshedBars = refreshTimelineBarsIfNeeded(
        projectIDs: activeProjectIDs,
        workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
        workspaceProjectSummaries: workspaceTimelineProjectSummaries,
        scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID,
        sourceSignature: liveSourceSignature,
        force: true
      )
      refreshTimelineDayHeaderSectionsIfNeeded(
        from: refreshedBars,
        sourceSignature: liveSourceSignature,
        force: true
      )
      seedRangeIfNeeded(with: refreshedBars)
      prepareTimelineInitialViewportIfNeeded(with: refreshedBars)
      if isActive {
        scheduleMidnightRefresh()
      }
    }
    .task(
      id: TimelineBoardReadPath.workspaceLoadSignature(
        projectIDs: activeProjectIDs,
        workspaceTreeRevision: appState.workspaceTreeRevision
      )
    ) {
      await reloadWorkspaceTimelineProjectDetails(for: activeProjectIDs)
    }
    .onChange(of: appState.runtimeProjectionRevision) { _, _ in
      Task { @MainActor in
        await reloadWorkspaceTimelineProjectDetails(for: activeProjectIDs)
      }
    }
    .onChange(of: snapshot.watchedSourceSignature) { _, newSignature in
      guard isActive, !appState.isEditorMotionSuppressed else { return }
      let refreshedBars = refreshTimelineBarsIfNeeded(
        projectIDs: activeProjectIDs,
        workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
        workspaceProjectSummaries: workspaceTimelineProjectSummaries,
        scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID,
        sourceSignature: newSignature,
        force: false
      )
      refreshTimelineDayHeaderSectionsIfNeeded(
        from: refreshedBars,
        sourceSignature: newSignature,
        force: false
      )
      seedRangeIfNeeded(with: refreshedBars)
      prepareTimelineInitialViewportIfNeeded(with: refreshedBars)
    }
    .onChange(of: appState.isEditorMotionSuppressed) { _, isSuppressed in
      if isSuppressed {
        cancelTimelineTaskBadgeOverlay()
        cancelTimelineDayHeaderOverlay()
      } else if isActive {
        let liveSourceSignature = timelineRefreshSignature(
          projectIDs: activeProjectIDs,
          workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
          workspaceProjectSummaries: workspaceTimelineProjectSummaries,
          scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID
        )
        let refreshedBars = refreshTimelineBarsIfNeeded(
          projectIDs: activeProjectIDs,
          workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
          workspaceProjectSummaries: workspaceTimelineProjectSummaries,
          scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID,
          sourceSignature: liveSourceSignature,
          force: true
        )
        refreshTimelineDayHeaderSectionsIfNeeded(
          from: refreshedBars,
          sourceSignature: liveSourceSignature,
          force: true
        )
        seedRangeIfNeeded(with: refreshedBars)
        prepareTimelineInitialViewportIfNeeded(with: refreshedBars)
      }
    }
    .onChange(of: horizontalOffsetX) { _, _ in
      dismissTimelineDayHeaderHoverIfObscured()
    }
    .onChange(of: isActive) { _, active in
      if active {
        refreshAnchorDateIfNeeded()
        let liveSourceSignature = timelineRefreshSignature(
          projectIDs: activeProjectIDs,
          workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
          workspaceProjectSummaries: workspaceTimelineProjectSummaries,
          scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID
        )
        let refreshedBars = refreshTimelineBarsIfNeeded(
          projectIDs: activeProjectIDs,
          workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
          workspaceProjectSummaries: workspaceTimelineProjectSummaries,
          scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID,
          sourceSignature: liveSourceSignature,
          force: true
        )
        refreshTimelineDayHeaderSectionsIfNeeded(
          from: refreshedBars,
          sourceSignature: liveSourceSignature,
          force: true
        )
        seedRangeIfNeeded(with: refreshedBars)
        prepareTimelineInitialViewportIfNeeded(with: refreshedBars)
        scheduleMidnightRefresh()
      } else {
        cancelTimelineTaskBadgeOverlay()
        cancelTimelineDayHeaderOverlay()
        cancelMidnightRefresh()
      }
    }
    .onChange(of: appState.isHoveringTimelineTaskBadgeOverlay) { _, isHovering in
      if !isHovering {
        scheduleTimelineTaskBadgeOverlayHideIfNeeded()
      }
    }
    .onChange(of: appState.isHoveringTimelineDayHeaderOverlay) { _, isHovering in
      if !isHovering {
        scheduleTimelineDayHeaderOverlayHideIfNeeded()
      }
    }
    .onChange(of: appState.timelineJumpToTodayToken) { _, _ in
      guard !snapshot.bars.isEmpty else { return }
      requestTodayScrollPosition(isExplicitRequest: true)
    }
    .onChange(of: appState.currentDayChangeToken) { _, _ in
      guard isActive else { return }
      performTimelineDateRefresh(force: true)
      scheduleMidnightRefresh()
    }
    .onChange(of: dayColumnWidth) { oldWidth, newWidth in
      preserveLeftVisibleDayOnZoom(oldWidth: oldWidth, newWidth: newWidth)
    }
    .onDisappear {
      cancelTimelineTaskBadgeOverlay()
      cancelTimelineDayHeaderOverlay()
      cancelTimelineScrollSession()
      didPrewarmTimelineScrollMode = false
      cancelMidnightRefresh()
    }
    .confirmationDialog(
      "프로젝트를 완전히 삭제할까요?",
      isPresented: pendingTimelineDeleteDialogBinding,
      titleVisibility: .visible
    ) {
      Button("삭제", role: .destructive) {
        guard let targetID = pendingDeleteProjectID else { return }
        performPermanentDelete(targetID)
        pendingDeleteProjectID = nil
        pendingDeleteProjectTitle = ""
      }
      Button("취소", role: .cancel) {
        pendingDeleteProjectID = nil
        pendingDeleteProjectTitle = ""
      }
    } message: {
      Text("'\(pendingDeleteProjectTitle)' 프로젝트와 모든 할일/첨부를 완전히 삭제합니다.")
    }
  }

  private func timelineViewportSnapshot(
    for proxy: GeometryProxy,
    snapshot: TimelineBoardSnapshot
  ) -> TimelineViewportSnapshot {
    let viewportWidth = max(260, proxy.size.width - horizontalEdgePadding * 2)
    let viewportHeight = max(220, proxy.size.height - topEdgePadding - bottomEdgePadding)
    let timelineViewportWidth = max(dayColumnWidth, viewportWidth - titleColumnWidth)
    let rowsHeight = max(
      totalRowsHeight(for: snapshot.rowLayouts),
      viewportHeight - headerHeight
    )
    let rawVisibleLowerOffset =
      dayRange.lowerBound + Int(floor(max(0, horizontalOffsetX) / dayColumnWidth))
    let visibleLowerOffset = min(
      max(rawVisibleLowerOffset, dayRange.lowerBound),
      dayRange.upperBound
    )
    let visibleDayCount = max(1, Int(ceil(timelineViewportWidth / dayColumnWidth)))
    let visibleUpperOffset = min(dayRange.upperBound, visibleLowerOffset + visibleDayCount - 1)

    return TimelineViewportSnapshot(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      rowsHeight: rowsHeight,
      boardWidth: titleColumnWidth + timelineWidth,
      boardHeight: headerHeight + rowsHeight,
      visibleLowerOffset: visibleLowerOffset,
      visibleUpperOffset: visibleUpperOffset,
      boardVersion: boardContentSignature(
        barsPresentationSignature: snapshot.barsPresentationSignature,
        rowsHeight: rowsHeight,
        activeTimelineTaskBadgeID: activeTimelineTaskBadgeID,
        selectedProjectID: selectedProjectID,
        draggingProjectID: draggingProjectID,
        dropIndicator: projectDropIndicator,
        taskDropTargetProjectID: taskDropTargetProjectID
      ),
      leftVersion: pinnedLeftSignature(
        barsPresentationSignature: snapshot.barsPresentationSignature,
        rowsHeight: rowsHeight,
        visibleLowerOffset: visibleLowerOffset,
        visibleUpperOffset: visibleUpperOffset,
        selectedProjectID: selectedProjectID,
        draggingProjectID: draggingProjectID,
        dropIndicator: projectDropIndicator,
        taskDropTargetProjectID: taskDropTargetProjectID
      ),
      topVersion: pinnedTopSignature(),
      shouldPublishVerticalOffset: showsProjectPassthroughFrames && isActive,
      shouldPublishPreciseHoverOffsets:
        isActive
        && !isTimelineScrolling
        && (hoveredTimelineTaskBadgeID != nil || activeTimelineTaskBadgeID != nil)
    )
  }

  @ViewBuilder
  private func timelineBoardViewportSection(
    proxy: GeometryProxy,
    snapshot: TimelineBoardSnapshot
  ) -> some View {
    let viewport = timelineViewportSnapshot(for: proxy, snapshot: snapshot)

    if snapshot.bars.isEmpty {
      timelineEmptyBoardSection
    } else {
      timelineLoadedBoardSection(snapshot: snapshot, viewport: viewport)
    }
  }

  private var timelineEmptyBoardSection: some View {
    emptyState
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, horizontalEdgePadding)
      .padding(.top, topEdgePadding)
      .padding(.bottom, bottomEdgePadding)
  }

  private func timelineLoadedBoardSection(
    snapshot: TimelineBoardSnapshot,
    viewport: TimelineViewportSnapshot
  ) -> some View {
    timelineBoardScrollShell(snapshot: snapshot, viewport: viewport)
      .padding(.horizontal, horizontalEdgePadding)
      .padding(.top, topEdgePadding)
      .padding(.bottom, bottomEdgePadding)
      .background {
        timelineBoardOverlaySurface(snapshot: snapshot, viewport: viewport)
      }
  }

  private func timelineBoardScrollShell(
    snapshot: TimelineBoardSnapshot,
    viewport: TimelineViewportSnapshot
  ) -> some View {
    ZStack(alignment: .topLeading) {
      UnifiedTimelineBoardScrollView(
        boardSize: CGSize(width: viewport.boardWidth, height: viewport.boardHeight),
        titleColumnWidth: titleColumnWidth,
        headerHeight: headerHeight,
        dayColumnWidth: dayColumnWidth,
        boardContentVersion: viewport.boardVersion,
        pinnedLeftVersion: viewport.leftVersion,
        pinnedTopVersion: viewport.topVersion,
        scrollRequestGeneration: scrollRequestGeneration,
        publishOffsetY: viewport.shouldPublishVerticalOffset,
        publishPreciseHoverOffsets: viewport.shouldPublishPreciseHoverOffsets,
        scrollHoverSuppressionInterval: timelineScrollIdleDelay,
        offsetX: $horizontalOffsetX,
        offsetY: $verticalOffsetY,
        requestedOffsetX: $requestedOffsetX,
        onScrollActivity: { x, y, usedPreciseHoverOffsets in
          handleTimelineScrollActivity(
            horizontalOffsetX: x,
            verticalOffsetY: y,
            usedPreciseHoverOffsets: usedPreciseHoverOffsets
          )
        }
      ) {
        boardContent(
          bars: snapshot.bars,
          rowLayouts: snapshot.rowLayouts,
          rowsHeight: viewport.rowsHeight,
          visibleLowerOffset: viewport.visibleLowerOffset,
          visibleUpperOffset: viewport.visibleUpperOffset
        )
      } pinnedLeft: {
        leftColumnContent(
          bars: snapshot.bars,
          rowLayouts: snapshot.rowLayouts,
          rowsHeight: viewport.rowsHeight,
          visibleLowerOffset: viewport.visibleLowerOffset,
          visibleUpperOffset: viewport.visibleUpperOffset
        )
      } pinnedTop: {
        timelineHeaderStripSection
      }
      .frame(width: viewport.viewportWidth, height: viewport.viewportHeight)

      timelineMonthBadge
    }
  }

  private var timelineMonthBadge: some View {
    Text(currentMonthText)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .frame(width: monthBadgeWidth, alignment: .leading)
      .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
      .padding(.leading, titleColumnWidth + 8)
      .padding(.top, monthLabelTopPadding)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      ContentUnavailableView(
        showsTimelineLoadingState ? "타임라인 준비 중" : "No projects",
        systemImage: showsTimelineLoadingState ? "hourglass" : "calendar.badge.clock",
        description: Text(emptyStateDescription)
      )

      if !appState.isReminderStatusReady {
        Text("리마인더 상태: \(appState.reminderStatusDisplayText)")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
  }

  private var emptyStateDescription: String {
    if showsTimelineLoadingState {
      return "프로젝트를 준비하는 중입니다."
    }
    if appState.isReminderStatusDenied {
      return "리마인더 접근 권한이 필요합니다. 권한을 허용한 뒤 앱을 다시 열어 주세요."
    }
    if appState.isReminderStatusFailed {
      return "리마인더 메타데이터 준비에 실패했습니다. 상단 상태를 확인해 주세요."
    }
    if appState.isReminderStatusRefreshing {
      return "리마인더 메타데이터와 note source를 불러오는 중입니다."
    }
    return "리마인더 메타데이터와 note source가 준비되면 타임라인이 표시됩니다."
  }

  private func boardContentSignature(
    barsPresentationSignature: Int,
    rowsHeight: CGFloat,
    activeTimelineTaskBadgeID: String?,
    selectedProjectID: UUID?,
    draggingProjectID: UUID?,
    dropIndicator: TimelineProjectDropIndicator?,
    taskDropTargetProjectID: UUID?
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(barsPresentationSignature)
    hasher.combine(anchorDate.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(Int(timelineWidth))
    hasher.combine(Int(rowsHeight.rounded()))
    hasher.combine(activeTimelineTaskBadgeID)
    hasher.combine(selectedProjectID)
    hasher.combine(draggingProjectID)
    hasher.combine(dropIndicator?.targetProjectID)
    hasher.combine(dropIndicator?.placement == .before)
    hasher.combine(taskDropTargetProjectID)
    return hasher.finalize()
  }

  private func pinnedLeftSignature(
    barsPresentationSignature: Int,
    rowsHeight: CGFloat,
    visibleLowerOffset: Int,
    visibleUpperOffset: Int,
    selectedProjectID: UUID?,
    draggingProjectID: UUID?,
    dropIndicator: TimelineProjectDropIndicator?,
    taskDropTargetProjectID: UUID?
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(barsPresentationSignature)
    hasher.combine(Int(rowsHeight.rounded()))
    hasher.combine(visibleLowerOffset)
    hasher.combine(visibleUpperOffset)
    hasher.combine(selectedProjectID)
    hasher.combine(draggingProjectID)
    hasher.combine(dropIndicator?.targetProjectID)
    hasher.combine(dropIndicator?.placement == .before)
    hasher.combine(taskDropTargetProjectID)
    return hasher.finalize()
  }

  private func pinnedTopSignature() -> Int {
    var hasher = Hasher()
    hasher.combine(anchorDate.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(Int((dayColumnWidth * 100).rounded()))
    hasher.combine(Locale.autoupdatingCurrent.identifier)
    return hasher.finalize()
  }

  func handleTimelineScrollActivity(
    horizontalOffsetX: CGFloat,
    verticalOffsetY: CGFloat,
    usedPreciseHoverOffsets: Bool
  ) {
    let clampedX = max(0, horizontalOffsetX)
    let clampedY = max(0, verticalOffsetY)
    let clampedXValue = Double(clampedX)
    let clampedYValue = Double(clampedY)

    if timelineScrollSession == nil {
      timelineScrollSession = TimelineScrollSessionMetrics(
        startedAt: .now,
        offsetEvents: 1,
        preciseHoverOffsetEvents: usedPreciseHoverOffsets ? 1 : 0,
        suppressedTaskBadgeHoverEvents: 0,
        suppressedDayHeaderHoverEvents: 0,
        lastHorizontalOffset: clampedX,
        lastVerticalOffset: clampedY
      )
      cancelTimelineTaskBadgeOverlay()
      cancelTimelineDayHeaderOverlay()
      AppLogger.timeline.notice(
        "timeline scroll begin x=\(clampedXValue, privacy: .public) y=\(clampedYValue, privacy: .public) preciseHover=\(usedPreciseHoverOffsets, privacy: .public)"
      )
    } else {
      timelineScrollSession?.offsetEvents += 1
      if usedPreciseHoverOffsets {
        timelineScrollSession?.preciseHoverOffsetEvents += 1
      }
      timelineScrollSession?.lastHorizontalOffset = clampedX
      timelineScrollSession?.lastVerticalOffset = clampedY
    }

    timelineScrollIdleWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      finishTimelineScrollSession(reason: "idle")
    }
    timelineScrollIdleWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + timelineScrollIdleDelay, execute: workItem)
  }

  func recordSuppressedTimelineTaskBadgeHover() {
    guard timelineScrollSession != nil else { return }
    timelineScrollSession?.suppressedTaskBadgeHoverEvents += 1
  }

  func recordSuppressedTimelineDayHeaderHover() {
    guard timelineScrollSession != nil else { return }
    timelineScrollSession?.suppressedDayHeaderHoverEvents += 1
  }

  func finishTimelineScrollSession(reason: String) {
    timelineScrollIdleWorkItem?.cancel()
    timelineScrollIdleWorkItem = nil

    guard let session = timelineScrollSession else { return }
    timelineScrollSession = nil

    let elapsedMS = Int(Date().timeIntervalSince(session.startedAt) * 1000)
    let lastXValue = Double(session.lastHorizontalOffset)
    let lastYValue = Double(session.lastVerticalOffset)
    AppLogger.timeline.notice(
      "timeline scroll end reason=\(reason, privacy: .public) elapsed_ms=\(elapsedMS, privacy: .public) offset_events=\(session.offsetEvents, privacy: .public) precise_hover_events=\(session.preciseHoverOffsetEvents, privacy: .public) suppressed_badge_hovers=\(session.suppressedTaskBadgeHoverEvents, privacy: .public) suppressed_day_hovers=\(session.suppressedDayHeaderHoverEvents, privacy: .public) last_x=\(lastXValue, privacy: .public) last_y=\(lastYValue, privacy: .public)"
    )
  }

  func cancelTimelineScrollSession() {
    timelineScrollIdleWorkItem?.cancel()
    timelineScrollIdleWorkItem = nil
    timelineScrollSession = nil
  }

}
