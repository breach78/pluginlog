import AppKit
import SwiftUI

struct ScheduleBoardView: View {
  static let dayHeaderWeekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "EEE"
    return formatter
  }()

  static let dayHeaderDayNumberFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateFormat = "d"
    return formatter
  }()

  static let dayHeaderMonthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "MMM"
    return formatter
  }()

  @EnvironmentObject var appState: AppState
  @Environment(\.undoManager) var undoManager

  @Binding var displayMode: ScheduleBoardDisplayMode
  let projectIDs: [UUID]
  let quickAddProjectIDs: [UUID]?
  let selectedProjectID: UUID?
  let onSelectProject: (UUID) -> Void
  let dragProjectionCoordinateSpaceName: String
  let isTaskDragOverExternalTarget: Bool
  let onTaskDragProjectionChanged: ((CGPoint?, CGRect?) -> Void)?
  let onTaskDragEndedAtPoint: ((UUID, CGPoint?, CGRect?) -> Bool)?
  let onTapEmptyArea: () -> Void
  let isActive: Bool
  let onEditTask: (WorkspaceTaskEditPanelTarget) -> Void
  let onEditCalendarEvent: (ScheduleCalendarEvent) -> Void
  let onShowMonthDetail: (ScheduleMonthDetailPanelTarget) -> Void
  let externalMonthDragTargetDate: Date?
  let externalDayDropTarget: ScheduleMonthDropTarget?
  let shouldPublishMonthDropTargets: Bool
  let onMonthItemScheduleChanged: (ScheduleMonthItem) -> Void
  let onMonthDropTargetsChanged: ([ScheduleMonthDropTarget]) -> Void

  @AppStorage("BrainUnfog.ScheduleBoard.allDayVisibleRowCount")
  var storedAllDayVisibleRowCount: Int = 4
  @AppStorage(ScheduleUserDefaultsKey.dateBoundarySnappingEnabled)
  var isDateBoundarySnappingEnabled = true
  @State var dayRange: ClosedRange<Int> = -7...30
  // Root retains the shared scroll and quick-create state consumed by both the all-day rail and timed grid.
  @State var horizontalOffsetX: CGFloat = 0
  @State var verticalOffsetY: CGFloat = 0
  @State var requestedOffsetX: CGFloat?
  @State var requestedOffsetY: CGFloat?
  @State var scrollRequestGeneration: Int = 0
  @State var scrollViewportState = ScheduleScrollViewportState()
  @State var activeTaskDrag: ScheduleTaskDragState?
  @State var activeTaskResize: ScheduleTaskResizeState?
  @State var activeCalendarDrag: ScheduleCalendarDragState?
  @State var activeCalendarResize: ScheduleCalendarResizeState?
  @State var activeAllDayRailResizeStartRowCount: Int?
  @State var activeAllDayRailResizeRowCount: Int?
  @State var activeTimedQuickCreateSelection: ScheduleTimedQuickCreateSelection?
  @State var pendingTimedQuickCreateSelection: ScheduleTimedQuickCreateSelection?
  @State var calendarOverlayRefreshTask: Task<Void, Never>?
  @State var pendingCalendarEditAction: PendingScheduleCalendarEditAction?
  @State var calendarEditError: ScheduleCalendarEditError?
  @State var cachedScheduledTaskSourceSignature: Int?
  @State var cachedScheduledTaskDescriptors: [WorkspaceScheduleTaskDescriptor] = []
  @State var cachedWorkspaceScheduleTasksByID: [UUID: WorkspaceScheduleTaskDescriptor] = [:]
  @State var cachedScheduleTaskSignature: Int = 0
  @State var cachedScheduleDayHeaderSections: [Date: [TimelineDayHeaderOverlayProjectSection]] =
    [:]
  @State var cachedScheduleDayHeaderSourceSignature: Int?
  @State var cachedLayoutSourceSignature: Int?
  @State var cachedTimedEntries: [ScheduleTimedBlockLayout] = []
  @State var cachedAllDayEntries: [ScheduleAllDayLayout] = []
  @State var cachedBackgroundTimedEntries: [ScheduleTimedBlockLayout] = []
  @State var cachedBackgroundAllDayEntries: [ScheduleAllDayLayout] = []
  @State var scheduleMonthItemCache = ScheduleMonthItemCache()
  @State var optimisticScheduleTaskCompletionByID: [UUID: Bool] = [:]
  @State var optimisticScheduleTaskScheduleByID: [UUID: OptimisticScheduleTaskScheduleState] = [:]
  @State var retainedScheduleCalendarBridgeDecisionsByTaskID:
    [UUID: RetainedCalendarBridgeDecision] = [:]
  @State var retainedScheduleCalendarBridgeWriteMarkersByTaskID:
    [UUID: RetainedCalendarBridgeWriteMarker] = [:]
  @State var workspaceScheduleProjectSnapshots: [UUID: WorkspaceProjectRuntimeRecord] = [:]
  @State var workspaceScheduleSliceEntriesByProjectID: [UUID: [ScheduleSliceEntry]] = [:]
  @State var workspaceScheduleLoadGeneration = 0
  @State var workspaceScheduleLastLoadSignature: Int?
  @State var workspaceLoadFallback: ScheduleWorkspaceLoadFallback?
  @State var scheduleTaskWriteNotice: ScheduleBoardRuntimeNotice?
  @State var selectedScheduleTaskID: UUID?
  @State var suppressedTaskTapUntil: Date = .distantPast
  @State var boardFrameInGlobal: CGRect = .null
  @State var viewportSyncDiagnostic: ScheduleViewportSyncDiagnostic?
  @State var hoveredScheduleDayHeaderDate: Date?
  @State var activeScheduleDayHeaderDate: Date?
  @State var scheduleMonthAnchorDate: Date?
  @State var selectedScheduleMonthDate: Date?
  @State var scheduleDayHeaderShowWorkItem: DispatchWorkItem?
  @State var scheduleDayHeaderDetachWorkItem: DispatchWorkItem?
  @State var isCalendarPickerShown = false
  @State var committedTaskDrop: CommittedTaskDropState?

  let titleColumnWidth: CGFloat = ScheduleUITokens.Board.titleColumnWidth
  let calendarMenuLeadingInset: CGFloat = 18
  let pastDayBuffer = 7
  let defaultVisibleStartDayOffset = 0
  let defaultVisibleStartHour = 3
  let futureDayWindow = 30
  let dayColumnWidth: CGFloat = ScheduleUITokens.Board.dayColumnWidth
  let dateHeaderHeight: CGFloat = ScheduleUITokens.Board.dateHeaderHeight
  let allDayRowHeight: CGFloat = ScheduleUITokens.Board.allDayRowHeight
  let minimumAllDayVisibleRowCount = 1
  let maximumAllDayVisibleRowCount = 10

  let allDayRailPadding: CGFloat = ScheduleUITokens.Board.allDayRailPadding
  let allDayRailExtraVisibleHeight: CGFloat = ScheduleUITokens.Board.allDayRailExtraVisibleHeight
  let hourHeight: CGFloat = ScheduleUITokens.Board.hourHeight
  let hourCount = 24
  let timedBlockInset: CGFloat = ScheduleUITokens.Board.timedBlockInset
  let timedBlockColumnSpacing: CGFloat = ScheduleUITokens.Board.timedBlockColumnSpacing
  let allDayChipHorizontalInset: CGFloat = ScheduleUITokens.Board.allDayChipHorizontalInset
  let timedMinimumDuration = WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
  let dragSourcePlaceholderOpacity = ScheduleUITokens.Interaction.dragSourcePlaceholderOpacity
  let dragGhostOpacity = ScheduleUITokens.Interaction.dragGhostOpacity
  let dragGhostScale: CGFloat = ScheduleUITokens.Interaction.dragGhostScale
  let dragGhostShadowRadius: CGFloat = ScheduleUITokens.Interaction.dragGhostShadowRadius
  let dragGhostShadowYOffset: CGFloat = ScheduleUITokens.Interaction.dragGhostShadowYOffset
  let selectionHighlightColor = ScheduleUITokens.Board.selectionHighlightColor
  let layoutEngine = ScheduleDayTimelineLayoutEngine()
  let scheduleDayHeaderOverlayWidth: CGFloat = ScheduleUITokens.Board.scheduleDayHeaderOverlayWidth
  let scheduleDayHeaderShowDelay: TimeInterval = ScheduleUITokens.Board.scheduleDayHeaderShowDelay
  let scheduleOverlayDetachGraceDelay: TimeInterval =
    ScheduleUITokens.Board.scheduleOverlayDetachGraceDelay
  let scheduleItemFontScale: CGFloat = ScheduleUITokens.Board.scheduleItemFontScale

  var calendar: Calendar { .autoupdatingCurrent }
  var today: Date { appState.currentDayStart }
  func scheduleItemFontSize(_ baseSize: CGFloat) -> CGFloat {
    baseSize * scheduleItemFontScale
  }
  func scheduleItemFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .system(size: scheduleItemFontSize(size), weight: weight)
  }
  func scheduleItemFont(
    _ size: CGFloat,
    weight: Font.Weight,
    design: Font.Design
  ) -> Font {
    .system(size: scheduleItemFontSize(size), weight: weight, design: design)
  }
  var headerHeight: CGFloat {
    dateHeaderHeight + allDayRailVisibleHeight
  }
  var isAllDayRailResizing: Bool {
    activeAllDayRailResizeStartRowCount != nil
  }
  var canResizeAllDayRail: Bool {
    activeTaskDrag == nil
      && activeTaskResize == nil
      && activeCalendarDrag == nil
      && activeCalendarResize == nil
  }

  init(
    displayMode: Binding<ScheduleBoardDisplayMode> = .constant(.week),
    projectIDs: [UUID] = [],
    quickAddProjectIDs: [UUID]? = nil,
    selectedProjectID: UUID? = nil,
    onSelectProject: @escaping (UUID) -> Void,
    dragProjectionCoordinateSpaceName: String = "scheduleWorkspaceBoard",
    isTaskDragOverExternalTarget: Bool = false,
    onTaskDragProjectionChanged: ((CGPoint?, CGRect?) -> Void)? = nil,
    onTaskDragEndedAtPoint: ((UUID, CGPoint?, CGRect?) -> Bool)? = nil,
    onTapEmptyArea: @escaping () -> Void,
    isActive: Bool,
    onEditTask: @escaping (WorkspaceTaskEditPanelTarget) -> Void = { _ in },
    onEditCalendarEvent: @escaping (ScheduleCalendarEvent) -> Void = { _ in },
    onShowMonthDetail: @escaping (ScheduleMonthDetailPanelTarget) -> Void = { _ in },
    externalMonthDragTargetDate: Date? = nil,
    externalDayDropTarget: ScheduleMonthDropTarget? = nil,
    shouldPublishMonthDropTargets: Bool = false,
    onMonthItemScheduleChanged: @escaping (ScheduleMonthItem) -> Void = { _ in },
    onMonthDropTargetsChanged: @escaping ([ScheduleMonthDropTarget]) -> Void = { _ in }
  ) {
    _displayMode = displayMode
    self.projectIDs = projectIDs
    self.quickAddProjectIDs = quickAddProjectIDs
    self.selectedProjectID = selectedProjectID
    self.onSelectProject = onSelectProject
    self.dragProjectionCoordinateSpaceName = dragProjectionCoordinateSpaceName
    self.isTaskDragOverExternalTarget = isTaskDragOverExternalTarget
    self.onTaskDragProjectionChanged = onTaskDragProjectionChanged
    self.onTaskDragEndedAtPoint = onTaskDragEndedAtPoint
    self.onTapEmptyArea = onTapEmptyArea
    self.isActive = isActive
    self.onEditTask = onEditTask
    self.onEditCalendarEvent = onEditCalendarEvent
    self.onShowMonthDetail = onShowMonthDetail
    self.externalMonthDragTargetDate = externalMonthDragTargetDate
    self.externalDayDropTarget = externalDayDropTarget
    self.shouldPublishMonthDropTargets = shouldPublishMonthDropTargets
    self.onMonthItemScheduleChanged = onMonthItemScheduleChanged
    self.onMonthDropTargetsChanged = onMonthDropTargetsChanged
  }

  var allDayDropZoneFrame: CGRect {
    CGRect(
      x: titleColumnWidth,
      y: dateHeaderHeight,
      width: dayColumnsWidth,
      height: allDayRailVisibleHeight
    )
  }
  var allDayRailVisibleHeight: CGFloat {
    CGFloat(allDayVisibleRowCount) * allDayRowHeight
      + allDayRailPadding * 2
      + allDayRailExtraVisibleHeight
  }
  var allDayVisibleRowCount: Int {
    activeAllDayRailResizeRowCount
      ?? clampedAllDayVisibleRowCount(storedAllDayVisibleRowCount)
  }
  var timeGridHeight: CGFloat {
    CGFloat(hourCount) * hourHeight
  }
  var interactionMetrics: ScheduleInteractionMetrics {
    ScheduleInteractionMetrics(
      dayColumnWidth: dayColumnWidth,
      hourHeight: hourHeight,
      quarterHourHeight: quarterHourHeight,
      timeGridHeight: timeGridHeight,
      timedMinimumDurationMinutes: timedMinimumDuration
    )
  }
  var boardWidth: CGFloat {
    titleColumnWidth + CGFloat(days.count) * dayColumnWidth
  }
  var boardHeight: CGFloat {
    headerHeight + timeGridHeight
  }
  var quarterHourHeight: CGFloat {
    hourHeight / 4
  }
  var dayColumnsWidth: CGFloat {
    CGFloat(days.count) * dayColumnWidth
  }
  var currentScrollOffsetX: CGFloat {
    scrollViewportState.visibleOrigin()?.x ?? scrollViewportState.liveOffsetX
  }
  var currentScrollOffsetY: CGFloat {
    scrollViewportState.visibleOrigin()?.y ?? scrollViewportState.liveOffsetY
  }
  var days: [Date] {
    Array(dayRange).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: today)
    }
  }
  var monthAnchorDate: Date {
    scheduleMonthAnchorDate ?? today
  }
  var monthAnchorDateBinding: Binding<Date> {
    Binding(
      get: { monthAnchorDate },
      set: { scheduleMonthAnchorDate = calendar.startOfDay(for: $0) }
    )
  }
  var dayIndexByDate: [Date: Int] {
    Dictionary(uniqueKeysWithValues: days.enumerated().map { index, day in (day, index) })
  }
  var activeProjectIDs: [UUID] {
    ScheduleBoardReadPath.normalizedProjectIDs(
      projectIDs: projectIDs
    )
  }
  var activeQuickAddProjectIDs: [UUID] {
    ScheduleBoardReadPath.normalizedProjectIDs(
      projectIDs: quickAddProjectIDs ?? activeProjectIDs
    )
  }
  var workspaceScheduleTasks: [WorkspaceScheduleTaskDescriptor] {
    scheduleTaskDescriptorsApplyingOptimisticSchedule(
      ScheduleProjectionService.taskDescriptors(
        projectIDs: activeProjectIDs,
        projectSnapshots: workspaceScheduleProjectSnapshots,
        scheduleEntriesByProjectID: workspaceScheduleSliceEntriesByProjectID
      )
    )
  }
  var scheduleQuickAddProjects: [ScheduleQuickAddProjectOption] {
    scheduleQuickAddState.options
  }
  var scheduleQuickAddState: ScheduleBoardReadPath.QuickAddState {
    ScheduleBoardReadPath.quickAddState(
      projectIDs: activeQuickAddProjectIDs,
      projectSnapshots: workspaceScheduleProjectSnapshots,
      selectedProjectID: selectedProjectID,
      appSelectedProjectID: appState.selectedProjectID,
      defaultReminderCalendarIdentifier: appState.defaultReminderCalendarIdentifier
    )
  }
  var scheduleQuickAddProjectID: UUID? {
    scheduleQuickAddState.defaultProjectID
  }
  var scheduleTaskSourceSignature: Int {
    let baseSignature = ScheduleBoardReadPath.sourceSignature(
      today: today,
      projectIDs: activeProjectIDs,
      projectSnapshots: workspaceScheduleProjectSnapshots,
      scheduleEntriesByProjectID: workspaceScheduleSliceEntriesByProjectID
    )
    return scheduleTaskSourceSignatureApplyingOptimisticSchedule(baseSignature: baseSignature)
  }
  var scheduleCalendarOverlayProjection: ScheduleCalendarOverlayProjection {
    appState.resolvedScheduleCalendarOverlayProjection()
  }
  var scheduleTaskSignature: Int {
    resolvedScheduleTaskSnapshot(preferCached: appState.isEditorMotionSuppressed || !isActive)
      .signature
  }
  var scheduleOverlayMotionContext: MotionContext {
    MotionContext(
      tier: .overlay,
      isTyping: appState.isEditorMotionSuppressed,
      isDragging: activeTaskDrag != nil
        || activeTaskResize != nil
        || activeCalendarDrag != nil
        || activeCalendarResize != nil
        || isAllDayRailResizing
    )
  }
  var scheduleOverlayMotionQuality: MotionQuality {
    MotionSystem.quality(for: scheduleOverlayMotionContext)
  }
  var scheduleOverlayPresentationAnimation: Animation? {
    if isScheduleBoardTransientInteractionActive {
      return nil
    }
    return MotionSystem.animation(
      for: .overlayFade,
      quality: scheduleOverlayMotionQuality
    )
  }
  var isScheduleBoardTransientInteractionActive: Bool {
    activeTaskDrag != nil || activeTaskResize != nil
      || activeCalendarDrag != nil || activeCalendarResize != nil
  }
  var scheduleOverlayCardStyle: OverlaySurfaceStyle {
    OverlaySurfaceStyle.card(quality: scheduleOverlayMotionQuality)
  }
  var scheduleRuntimeNotice: ScheduleBoardRuntimeNotice? {
    if scheduleCalendarOverlayProjection.accessDenied {
      return ScheduleBoardRuntimeNotice(
        id: "calendar_access_denied",
        symbol: "calendar.badge.exclamationmark",
        title: "캘린더 일정 fallback",
        message: "캘린더 접근 권한이 없어 Reminders/Calendar 일정은 숨기고 프로젝트 일정만 표시합니다."
      )
    }
    if let workspaceLoadFallback {
      return workspaceLoadFallback.notice
    }
    if let scheduleTaskWriteNotice {
      return scheduleTaskWriteNotice
    }
    if let viewportNotice = viewportSyncDiagnostic?.notice {
      return viewportNotice
    }
    return nil
  }
  var boardInteractionSignature: Int {
    var hasher = Hasher()
    hasher.combine(activeTaskDrag?.taskID)
    hasher.combine(activeTaskResize?.taskID)
    hasher.combine(activeTaskResize?.edge == .start ? 0 : 1)
    hasher.combine(activeCalendarDrag?.eventID)
    hasher.combine(activeCalendarResize?.eventID)
    hasher.combine(activeCalendarResize?.edge == .start ? 0 : 1)
    hasher.combine(activeAllDayRailResizeRowCount)
    return hasher.finalize()
  }
  var overlayPresentationSignature: Int {
    var hasher = Hasher()
    hasher.combine(selectedScheduleTaskID)
    hasher.combine(activeTaskDrag?.taskID)
    hasher.combine(activeTaskResize?.taskID)
    hasher.combine(activeTaskResize?.edge == .start ? 0 : 1)
    hasher.combine(activeCalendarDrag?.eventID)
    hasher.combine(activeCalendarResize?.eventID)
    hasher.combine(activeCalendarResize?.edge == .start ? 0 : 1)
    hasher.combine(activeTimedQuickCreateSelection?.dayIndex)
    hasher.combine(activeTimedQuickCreateSelection?.startMinutes)
    hasher.combine(activeTimedQuickCreateSelection?.durationMinutes)
    hasher.combine(pendingTimedQuickCreateSelection?.dayIndex)
    hasher.combine(pendingTimedQuickCreateSelection?.startMinutes)
    hasher.combine(pendingTimedQuickCreateSelection?.durationMinutes)
    return hasher.finalize()
  }
  func boardContentVersion(layoutSourceSignature: Int) -> Int {
    var hasher = Hasher()
    hasher.combine(
      ScheduleBoardHostingInvalidationPolicy.boardContentVersion(
        today: today,
        dayRange: dayRange,
        layoutSourceSignature: layoutSourceSignature,
        selectedScheduleTaskID: selectedScheduleTaskID,
        transientInteractionSignature: boardInteractionSignature
      )
    )
    hasher.combine(allDayVisibleRowCount)
    return hasher.finalize()
  }
  var pinnedLeftVersion: Int {
    allDayVisibleRowCount
  }

  func pinnedTopVersion(layoutSourceSignature: Int) -> Int {
    var hasher = Hasher()
    hasher.combine(
      ScheduleBoardHostingInvalidationPolicy.pinnedTopVersion(
        today: today,
        dayRange: dayRange,
        layoutSourceSignature: layoutSourceSignature,
        calendarSourcesSignature: scheduleCalendarOverlayProjection.calendarsSignature,
        selectedScheduleTaskID: selectedScheduleTaskID,
        transientInteractionSignature: boardInteractionSignature
      )
    )
    hasher.combine(allDayVisibleRowCount)
    return hasher.finalize()
  }

  func clampedAllDayVisibleRowCount(_ rowCount: Int) -> Int {
    min(max(rowCount, minimumAllDayVisibleRowCount), maximumAllDayVisibleRowCount)
  }

  func updateAllDayRailResize(translationHeight: CGFloat) {
    let startRowCount = activeAllDayRailResizeStartRowCount ?? allDayVisibleRowCount
    activeAllDayRailResizeStartRowCount = startRowCount
    let rowDelta = Int((translationHeight / allDayRowHeight).rounded())
    let nextRowCount = clampedAllDayVisibleRowCount(startRowCount + rowDelta)
    if activeAllDayRailResizeRowCount != nextRowCount {
      activeAllDayRailResizeRowCount = nextRowCount
    }
  }

  func commitAllDayRailResize() {
    if let rowCount = activeAllDayRailResizeRowCount {
      storedAllDayVisibleRowCount = clampedAllDayVisibleRowCount(rowCount)
    } else {
      storedAllDayVisibleRowCount = clampedAllDayVisibleRowCount(storedAllDayVisibleRowCount)
    }
    activeAllDayRailResizeStartRowCount = nil
    activeAllDayRailResizeRowCount = nil
  }

  func cancelAllDayRailResize() {
    activeAllDayRailResizeStartRowCount = nil
    activeAllDayRailResizeRowCount = nil
  }

  struct ScheduleBoardBodyContext {
    let filteredEvents: [ScheduleCalendarEvent]
    let backgroundEvents: [ScheduleCalendarEvent]
    let filteredEventHash: Int
    let liveTaskSourceSignature: Int
    let taskSnapshot: ScheduleTaskSnapshotCache
    let taskSignature: Int
    let liveLayoutSourceSignature: Int
    let layoutSourceSignature: Int
    let layoutCache: ScheduleLayoutCache
  }

  func makeBodyContext() -> ScheduleBoardBodyContext {
    let isMotionSuppressed = appState.isEditorMotionSuppressed
    let usesFrozenHostedContent =
      isMotionSuppressed || !isActive || isScheduleBoardTransientInteractionActive
    let calendarOverlayProjection = appState.resolvedScheduleCalendarOverlayProjection()
    let filteredEvents = calendarOverlayProjection.foregroundEvents
    let backgroundEvents = calendarOverlayProjection.backgroundEvents
    let filteredEventHash = calendarOverlayProjection.visibleEventsSignature
    let liveTaskSourceSignature =
      usesFrozenHostedContent
      ? (cachedScheduledTaskSourceSignature ?? 0)
      : scheduleTaskSourceSignature
    let taskSnapshot = resolvedScheduleTaskSnapshot(
      preferCached: usesFrozenHostedContent
    )
    let taskSignature = taskSnapshot.signature
    let liveLayoutSourceSignature =
      usesFrozenHostedContent
      ? (cachedLayoutSourceSignature
        ?? scheduleLayoutSourceSignature(
          filteredEventHash: filteredEventHash,
          taskSignature: taskSignature
        ))
      : scheduleLayoutSourceSignature(
        filteredEventHash: filteredEventHash,
        taskSignature: taskSignature
      )
    let layoutSourceSignature = resolvedScheduleLayoutSourceSignature(
      filteredEventHash: filteredEventHash,
      taskSignature: taskSignature,
      preferCached: usesFrozenHostedContent
    )
    let useCachedLayouts =
      usesFrozenHostedContent
      ? cachedLayoutSourceSignature != nil
      : cachedLayoutSourceSignature == layoutSourceSignature
    let layoutCache =
      useCachedLayouts
      ? ScheduleLayoutCache(
        timedEntries: cachedTimedEntries,
        allDayEntries: cachedAllDayEntries,
        backgroundTimedEntries: cachedBackgroundTimedEntries,
        backgroundAllDayEntries: cachedBackgroundAllDayEntries
      )
      : buildLayoutCache(
        filteredEvents: filteredEvents,
        backgroundEvents: backgroundEvents,
        taskSnapshot: taskSnapshot
      )

    return ScheduleBoardBodyContext(
      filteredEvents: filteredEvents,
      backgroundEvents: backgroundEvents,
      filteredEventHash: filteredEventHash,
      liveTaskSourceSignature: liveTaskSourceSignature,
      taskSnapshot: taskSnapshot,
      taskSignature: taskSignature,
      liveLayoutSourceSignature: liveLayoutSourceSignature,
      layoutSourceSignature: layoutSourceSignature,
      layoutCache: layoutCache
    )
  }
}
