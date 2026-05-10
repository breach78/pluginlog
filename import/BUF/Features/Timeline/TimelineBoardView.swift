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

  struct TimelineProjectRenameRequest: Identifiable, Equatable {
    let id: UUID
    let title: String
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
  @Binding var hiddenTimelineProjectIDs: Set<UUID>
  @EnvironmentObject var appState: AppState
  @Environment(\.modelContext) var modelContext
  @Environment(\.undoManager) var undoManager

  let showsHiddenProjects: Bool
  let projectIDs: [UUID]
  let showsProjectPassthroughFrames: Bool
  let isActive: Bool
  let isInteractionObscured: Bool
  let selectedProjectID: UUID?
  let onSelectProject: (UUID) -> Void
  let onToggleProjectSelection: (UUID) -> Void
  let onOpenProjectListPanel: (UUID) -> Void
  let onEditTask: (WorkspaceTaskEditPanelTarget) -> Void
  let onTaskDeleted: (UUID, UUID) -> Void

  @State var anchorDate = Calendar.autoupdatingCurrent.startOfDay(for: .now)
  @State var dayRange: ClosedRange<Int> = TimelineBoardReadPath.visibleDayRange
  @State var horizontalOffsetX: CGFloat = 0
  @State var verticalOffsetY: CGFloat = 0
  @State var requestedOffsetX: CGFloat?
  @State var didSetInitialScrollPosition = false
  @State var scrollRequestGeneration = 0
  @State var draggingProjectID: UUID?
  @State var projectDropIndicator: TimelineProjectDropIndicator?
  @State var taskDropTargetProjectID: UUID?
  @State var isCreatingProject = false
  @State var isNewProjectSheetPresented = false
  @State var pendingRenameProject: TimelineProjectRenameRequest?
  @State var isRenamingProject = false
  @State var pendingDeleteProjectID: UUID?
  @State var pendingDeleteProjectTitle: String = ""
  @State var workspaceTimelineProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord] = [:]
  @State var workspaceTimelineProjectSummaries: [UUID: ProjectSummaryRecord] = [:]
  @State var workspaceTimelineScheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]] = [:]
  @State var pendingTimelineProjectStageOverrides: [UUID: ProjectProgressStage] = [:]
  @State var retainedTimelineReadBlocker: RetainedWorkspaceSurfaceProjectionBlocker?
  @State var retainedTimelineCalendarBridgeDecisionsByTaskID:
    [UUID: RetainedCalendarBridgeDecision] = [:]
  @State var retainedTimelineCalendarBridgeWriteMarkersByTaskID:
    [UUID: RetainedCalendarBridgeWriteMarker] = [:]
  @State var cachedTimelineBars: [TimelineProjectBar] = []
  @State var cachedTimelineRowLayouts: [TimelineRowLayout] = []
  @State var cachedTimelineBarsSourceSignature: Int?
  @State var cachedTimelineBarsPresentationSignature: Int?
  @State var hoveredTimelineTaskBadgeID: String?
  @State var activeTimelineTaskBadgeID: String?
  @State var timelineTaskBadgeShowWorkItem: DispatchWorkItem?
  @State var timelineTaskBadgeDetachWorkItem: DispatchWorkItem?
  @State var cachedTimelineDayHeaderSections: [Date: [TimelineDayHeaderOverlayProjectSection]]
    = [:]
  @State var cachedTimelineDayHeaderSourceSignature: Int?
  @State var hoveredTimelineDayHeaderOffset: Int?
  @State var activeTimelineDayHeaderOffset: Int?
  @State var timelineDayHeaderShowWorkItem: DispatchWorkItem?
  @State var timelineDayHeaderDetachWorkItem: DispatchWorkItem?
  @State var activeTimelineProjectListPopoverProjectID: UUID?
  @State var activeTimelineTaskEditTarget: TimelineTaskEditTarget?
  @State var timelineProjectManualOrder = TimelineProjectManualOrderStore.load()
  @State var didReconcileTimelineProjectBoardOrder = false
  @State var workspaceTimelineLoadGeneration = 0
  @State var workspaceTimelineLastLoadSignature: Int?
  @State var midnightRefreshTimer: Timer?
  @State var isHoveringPinnedLeftColumn = false
  @State var overlayMetricsCache = TimelineOverlayMetricsCache()
  @State var timelineScrollSession: TimelineScrollSessionMetrics?
  @State var timelineScrollIdleWorkItem: DispatchWorkItem?
  @State var didPrewarmTimelineScrollMode = false
  @State var immediateSelectedProjectID: UUID?
  @State var selectionCommitTask: Task<Void, Never>?
  @State var suppressedTimelineTaskTapUntil: Date = .distantPast

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
  let monthBadgeWidth: CGFloat = 124
  let jumpLeftInsetDays = 3
  let timelineTaskBadgeOverlayWidth: CGFloat = 220
  let timelineDayHeaderOverlayWidth: CGFloat = 260
  let timelineProjectListPopoverWidth: CGFloat = 320
  let timelineTaskBadgeHeight: CGFloat = 18
  let timelineTaskBadgeOverlayAboveOffset: CGFloat = 8
  let timelineTaskBadgeOverlayBelowOffset: CGFloat = -4
  let timelineTaskBadgeShowDelay: TimeInterval = 0.20
  let timelineDayHeaderShowDelay: TimeInterval = 0.20
  let timelineOverlayDetachGraceDelay: TimeInterval = 0.08
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
    TimelineBoardReadPath.visibleProjectIDs(
      projectIDs,
      hiddenProjectIDs: showsHiddenProjects ? [] : hiddenTimelineProjectIDs
    )
  }
  var activeProjectIDSet: Set<UUID> {
    Set(activeProjectIDs)
  }
  var showsTimelineLoadingState: Bool {
    TimelineBoardReadPath.shouldShowLoadingState(
      projectIDs: activeProjectIDs,
      workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
      scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID,
      readBlocker: retainedTimelineReadBlocker
    )
  }
  var isTimelineScrolling: Bool { timelineScrollSession != nil }
  var canInteractivelyReorderProjects: Bool {
    projectListSortMode.allowsInteractiveReordering
  }
  var hasOnlyHiddenTimelineProjects: Bool {
    !TimelineBoardReadPath.normalizedProjectIDs(projectIDs).isEmpty
      && activeProjectIDs.isEmpty
  }
  let selectionHighlightColor = Color(red: 0.84, green: 0.94, blue: 1.0)

  init(
    projectListSortMode: Binding<ProjectListSortMode>,
    hiddenProjectIDs: Binding<Set<UUID>>,
    showsHiddenProjects: Bool = false,
    projectIDs: [UUID] = [],
    showsProjectPassthroughFrames: Bool = false,
    isActive: Bool = true,
    isInteractionObscured: Bool = false,
    selectedProjectID: UUID? = nil,
    onSelectProject: @escaping (UUID) -> Void,
    onToggleProjectSelection: @escaping (UUID) -> Void,
    onOpenProjectListPanel: @escaping (UUID) -> Void = { _ in },
    onEditTask: @escaping (WorkspaceTaskEditPanelTarget) -> Void = { _ in },
    onTaskDeleted: @escaping (UUID, UUID) -> Void = { _, _ in }
  ) {
    _projectListSortMode = projectListSortMode
    _hiddenTimelineProjectIDs = hiddenProjectIDs
    self.showsHiddenProjects = showsHiddenProjects
    self.projectIDs = projectIDs
    self.showsProjectPassthroughFrames = showsProjectPassthroughFrames
    self.isActive = isActive
    self.isInteractionObscured = isInteractionObscured
    self.selectedProjectID = selectedProjectID
    _immediateSelectedProjectID = State(initialValue: selectedProjectID)
    self.onSelectProject = onSelectProject
    self.onToggleProjectSelection = onToggleProjectSelection
    self.onOpenProjectListPanel = onOpenProjectListPanel
    self.onEditTask = onEditTask
    self.onTaskDeleted = onTaskDeleted
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
    let hasCachedSnapshot = cachedTimelineBarsSourceSignature != nil
    let bars =
      hasCachedSnapshot
      ? cachedTimelineBars
      : computedLiveBars(
        projectIDs: activeProjectIDs,
        workspaceProjectSnapshots: workspaceTimelineProjectSnapshots,
        workspaceProjectSummaries: workspaceTimelineProjectSummaries,
        scheduleEntriesByProjectID: workspaceTimelineScheduleEntriesByProjectID
      )
    let rowLayouts =
      hasCachedSnapshot
      ? cachedTimelineRowLayouts
      : buildRowLayouts(for: bars)

    return TimelineBoardSnapshot(
      bars: bars,
      watchedSourceSignature: watchedSourceSignature,
      rowLayouts: rowLayouts,
      barsPresentationSignature:
        hasCachedSnapshot
        ? (cachedTimelineBarsPresentationSignature ?? timelineSignature(for: bars))
        : timelineSignature(for: bars)
    )
  }

  private var timelineBoardRoot: some View {
    let snapshot = timelineBoardSnapshot
    let visibleProjectOrder = snapshot.bars.map(\.projectID)

    return GeometryReader { proxy in
      timelineBoardViewportSection(proxy: proxy, snapshot: snapshot)
    }
    .onAppear {
      appState.updateTimelineProjectListVisibleOrder(visibleProjectOrder)
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
      appState.updateTimelineProjectListVisibleOrder(refreshedBars.map(\.projectID))
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
    .task(id: activeProjectIDs) {
      await seedTimelineProjectManualOrderFromRemindersIfNeeded(for: activeProjectIDs)
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
      appState.updateTimelineProjectListVisibleOrder(refreshedBars.map(\.projectID))
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
        appState.updateTimelineProjectListVisibleOrder(refreshedBars.map(\.projectID))
        refreshTimelineDayHeaderSectionsIfNeeded(
          from: refreshedBars,
          sourceSignature: liveSourceSignature,
          force: true
        )
        seedRangeIfNeeded(with: refreshedBars)
        prepareTimelineInitialViewportIfNeeded(with: refreshedBars)
      }
    }
    .onChange(of: isInteractionObscured) { _, isObscured in
      if isObscured {
        cancelTimelineTaskBadgeOverlay()
        cancelTimelineDayHeaderOverlay()
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
        appState.updateTimelineProjectListVisibleOrder(refreshedBars.map(\.projectID))
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
      if isHovering {
        timelineTaskBadgeDetachWorkItem?.cancel()
        timelineTaskBadgeDetachWorkItem = nil
      } else {
        dismissTimelineTaskBadgeOverlayIfDetached()
      }
    }
    .onChange(of: appState.isHoveringTimelineDayHeaderOverlay) { _, isHovering in
      if isHovering {
        timelineDayHeaderDetachWorkItem?.cancel()
        timelineDayHeaderDetachWorkItem = nil
      } else {
        dismissTimelineDayHeaderOverlayIfDetached()
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
    .onChange(of: selectedProjectID) { _, projectID in
      immediateSelectedProjectID = projectID
    }
    .onChange(of: visibleProjectOrder) { _, nextOrder in
      appState.updateTimelineProjectListVisibleOrder(nextOrder)
    }
    .onDisappear {
      selectionCommitTask?.cancel()
      cancelTimelineTaskBadgeOverlay()
      cancelTimelineDayHeaderOverlay()
      cancelTimelineScrollSession()
      didPrewarmTimelineScrollMode = false
      cancelMidnightRefresh()
    }
    .sheet(isPresented: $isNewProjectSheetPresented) {
      WorkspaceNewProjectSheetContent(
        isCreating: isCreatingProject,
        onSubmit: createTimelineProject(named:),
        onCancel: {
          isNewProjectSheetPresented = false
        }
      )
    }
    .sheet(item: $pendingRenameProject) { request in
      WorkspaceRenameProjectSheetContent(
        originalTitle: request.title,
        isRenaming: isRenamingProject,
        onSubmit: { title in
          submitTimelineProjectRename(projectID: request.id, title: title)
        },
        onCancel: {
          pendingRenameProject = nil
        }
      )
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
        activeProjectListPopoverProjectID: activeTimelineProjectListPopoverProjectID,
        activeTaskEditTarget: activeTimelineTaskEditTarget,
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
        dayRange: dayRange,
        dayColumnWidth: dayColumnWidth,
        boardContentVersion: viewport.boardVersion,
        pinnedLeftVersion: viewport.leftVersion,
        pinnedTopVersion: viewport.topVersion,
        scrollRequestGeneration: scrollRequestGeneration,
        publishOffsetY: viewport.shouldPublishVerticalOffset,
        publishPreciseHoverOffsets: viewport.shouldPublishPreciseHoverOffsets,
        isDayHeaderHoverEnabled:
          isActive
          && !isInteractionObscured
          && !isTimelineScrolling
          && !appState.isEditorMotionSuppressed,
        isTaskBadgeHoverEnabled:
          isActive
          && !isInteractionObscured
          && !isTimelineScrolling
          && !appState.isEditorMotionSuppressed,
        taskBadgeHitTargets: timelineTaskBadgeHitTargets(
          bars: snapshot.bars,
          rowLayouts: snapshot.rowLayouts
        ),
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
        },
        onDayHeaderHover: { offset, isHovering in
          updateTimelineDayHeaderHover(offset, isHovering: isHovering)
        },
        onDayHeaderHoverCleared: {
          clearTimelineDayHeaderTriggerHover(deferClose: true)
        },
        onTaskBadgeHover: { badgeID, isHovering in
          updateTimelineTaskBadgeHover(badgeID, isHovering: isHovering)
        },
        onTaskBadgeHoverCleared: {
          clearTimelineTaskBadgeTriggerHover(deferClose: true)
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
      .allowsHitTesting(false)
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
    if let retainedTimelineReadBlocker {
      return retainedTimelineReadBlocker.userMessage
    }
    if showsTimelineLoadingState {
      return "프로젝트를 준비하는 중입니다."
    }
    if hasOnlyHiddenTimelineProjects {
      return "숨긴 목록은 타임라인에서만 표시되지 않습니다."
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
    activeProjectListPopoverProjectID: UUID?,
    activeTaskEditTarget: TimelineTaskEditTarget?,
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
    hasher.combine(activeProjectListPopoverProjectID)
    hasher.combine(activeTaskEditTarget?.projectID)
    hasher.combine(activeTaskEditTarget?.taskID)
    hasher.combine(draggingProjectID)
    hasher.combine(dropIndicator?.targetProjectID)
    hasher.combine(dropIndicator?.placement == .before)
    hasher.combine(taskDropTargetProjectID)
    return hasher.finalize()
  }

  private func pinnedTopSignature() -> Int {
    TimelineBoardReadPath.pinnedTopSignature(
      anchorDate: anchorDate,
      dayRange: dayRange,
      dayColumnWidth: dayColumnWidth,
      localeIdentifier: Locale.autoupdatingCurrent.identifier,
      isTimelineScrolling: isTimelineScrolling
    )
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
