import AppKit
import Combine
import SwiftUI

// Composition root only.
// AppKit bridge ownership: ScheduleBoardAppKitBridge.swift
// Chrome/day-header ownership: ScheduleBoardChrome.swift
// All-day ownership: ScheduleBoardAllDayRail.swift
// Timed-grid ownership: ScheduleBoardTimeGrid.swift
// Action/interaction ownership: ScheduleBoardActions.swift

struct ScheduleQuickAddProjectOption: Identifiable, Hashable {
  let id: UUID
  let title: String
}

enum ScheduleQuickAddFailureReason: String {
  case noAvailableProject = "quick_add_no_available_project"
  case requestedProjectUnavailable = "quick_add_requested_project_unavailable"
  case noVisibleDay = "quick_add_no_visible_day"

  var userMessage: String {
    switch self {
    case .noAvailableProject:
      return "Schedule quick add를 위한 기본 프로젝트를 찾지 못했습니다."
    case .requestedProjectUnavailable:
      return "선택한 프로젝트를 일정 quick add에서 찾지 못했습니다."
    case .noVisibleDay:
      return "현재 보이는 날짜가 없어 quick add 위치를 계산하지 못했습니다."
    }
  }
}

enum ScheduleInvalidDropReason: String {
  case externalPreviewUnavailable = "external_preview_unavailable"
  case payloadProviderMissing = "payload_provider_missing"
  case payloadDecodeFailed = "payload_decode_failed"
  case projectionUnavailable = "projection_unavailable"
}

enum ScheduleUserDefaultsKey {
  static let dateBoundarySnappingEnabled = "schedule.dateBoundarySnappingEnabled"
}

enum ScheduleCalendarFailureContext: String {
  case applyPreview = "apply_preview"
  case deleteEvent = "delete_event"
  case restoreDeletedEvent = "restore_deleted_event"
  case redeleteRestoredEvent = "redelete_restored_event"
}

enum ScheduleWorkspaceLoadFallback: Equatable {
  case queryEngineUnavailable
  case partialFailure(failedProjects: Int, totalProjects: Int)

  var notice: ScheduleBoardRuntimeNotice {
    switch self {
    case .queryEngineUnavailable:
      return ScheduleBoardRuntimeNotice(
        id: "workspace_query_engine_unavailable",
        symbol: "tray.full",
        title: "워크스페이스 일정 fallback",
        message: "워크스페이스 쿼리 엔진이 아직 준비되지 않아 워크스페이스 프로젝트 일정은 잠시 숨겨집니다."
      )
    case .partialFailure(let failedProjects, let totalProjects):
      return ScheduleBoardRuntimeNotice(
        id: "workspace_partial_failure_\(failedProjects)_\(totalProjects)",
        symbol: "exclamationmark.triangle",
        title: "워크스페이스 일정 일부 누락",
        message: "\(failedProjects)/\(totalProjects)개 프로젝트 스냅샷 로드에 실패해 일부 일정만 표시합니다."
      )
    }
  }
}

enum ScheduleViewportSyncDiagnostic: String, Equatable {
  case scrollRequestQueuedWithoutViewport = "scroll_request_queued_without_viewport"
  case dragProjectionFrameUnavailable = "drag_projection_frame_unavailable"

  var notice: ScheduleBoardRuntimeNotice? {
    switch self {
    case .scrollRequestQueuedWithoutViewport:
      return ScheduleBoardRuntimeNotice(
        id: rawValue,
        symbol: "arrow.left.arrow.right.circle",
        title: "Viewport sync 대기 중",
        message: "스크롤 뷰가 아직 준비되지 않아 점프 요청을 큐에 보관했습니다."
      )
    case .dragProjectionFrameUnavailable:
      return nil
    }
  }
}

struct ScheduleBoardRuntimeNotice: Identifiable, Equatable {
  let id: String
  let symbol: String
  let title: String
  let message: String
}

struct ScheduleExternalTaskDropDelegate: DropDelegate {
  let resolvePreview: (CGPoint) -> ScheduleInteractionPreview?
  let onPerformTaskDrop: (UUID, ScheduleInteractionPreview) -> Void
  let onInvalidDrop: (CGPoint, ScheduleInvalidDropReason) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    !info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).isEmpty
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard resolvePreview(info.location) != nil else { return nil }
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    let dropLocation = info.location
    guard let preview = resolvePreview(dropLocation) else {
      onInvalidDrop(dropLocation, .externalPreviewUnavailable)
      return false
    }
    guard let provider = info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).first else {
      onInvalidDrop(dropLocation, .payloadProviderMissing)
      return false
    }

    provider.loadItem(forTypeIdentifier: TaskDragPayload.textTypeIdentifier, options: nil) {
      item, _
      in
      guard let taskID = TaskDragPayload.parseTaskID(from: item) else {
        Task { @MainActor in
          onInvalidDrop(dropLocation, .payloadDecodeFailed)
        }
        return
      }
      Task { @MainActor in
        onPerformTaskDrop(taskID, preview)
      }
    }
    return true
  }
}

struct ScheduleQuickAddPopoverContent: View {
  let projects: [ScheduleQuickAddProjectOption]
  let onSubmit: (String, UUID) -> Void
  let onCancel: () -> Void

  @State var title: String = ""
  @State var selectedProjectID: UUID?
  @State var isFieldFocused = false

  init(
    projects: [ScheduleQuickAddProjectOption],
    defaultProjectID: UUID?,
    onSubmit: @escaping (String, UUID) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.projects = projects
    self.onSubmit = onSubmit
    self.onCancel = onCancel
    _selectedProjectID = State(initialValue: defaultProjectID ?? projects.first?.id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("할일 추가")
        .font(.system(size: 12, weight: .semibold))

      EscapeAwareTextField(
        text: $title,
        isFocused: $isFieldFocused,
        placeholder: "할일 입력",
        onSubmit: submit,
        onEscape: onCancel
      )
      .frame(height: 22)

      Menu {
        ForEach(projects) { project in
          Button {
            selectedProjectID = project.id
          } label: {
            if selectedProjectID == project.id {
              Label(project.title, systemImage: "checkmark")
            } else {
              Text(project.title)
            }
          }
        }
      } label: {
        HStack(spacing: 8) {
          Text(selectedProjectTitle)
            .lineLimit(1)
          Spacer(minLength: 0)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
        )
      }
      .menuStyle(.borderlessButton)

      HStack(spacing: 8) {
        Spacer(minLength: 0)

        Button("취소") {
          onCancel()
        }

        Button("추가") {
          submit()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedProjectID == nil
        )
      }
    }
    .padding(12)
    .frame(width: 260)
    .onAppear {
      DispatchQueue.main.async {
        isFieldFocused = true
      }
    }
    .onExitCommand {
      onCancel()
    }
  }

  var selectedProjectTitle: String {
    projects.first(where: { $0.id == selectedProjectID })?.title ?? "목록 선택"
  }

  func submit() {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let selectedProjectID else { return }
    onSubmit(trimmed, selectedProjectID)
  }
}

final class ScheduleQuickAddContextMenuView: NSView {
  weak var coordinator: ScheduleQuickAddContextMenuRegion.Coordinator?

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  override func rightMouseDown(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    coordinator?.presentMenu(from: self, event: event, location: location)
  }

  override func mouseDown(with event: NSEvent) {
    guard let coordinator else {
      super.mouseDown(with: event)
      return
    }

    guard coordinator.allowsTimedDragCreation else {
      coordinator.handleBackgroundTap()
      return
    }

    let startLocation = convert(event.locationInWindow, from: nil)
    coordinator.beginTimedDrag(at: startLocation)

    window?.trackEvents(
      matching: [.leftMouseDragged, .leftMouseUp],
      timeout: NSEvent.foreverDuration,
      mode: .eventTracking
    ) { [weak self] trackedEvent, stop in
      guard let self, let trackedEvent else {
        stop.pointee = true
        return
      }

      let location = self.convert(trackedEvent.locationInWindow, from: nil)
      switch trackedEvent.type {
      case .leftMouseDragged:
        coordinator.updateTimedDrag(to: location)
      case .leftMouseUp:
        coordinator.finishTimedDrag(at: location)
        stop.pointee = true
      default:
        break
      }
    }
  }
}

struct ScheduleQuickAddContextMenuRegion: NSViewRepresentable {
  let isAllDayRegion: Bool
  let canCreateTask: Bool
  let projects: [ScheduleQuickAddProjectOption]
  let defaultProjectID: UUID?
  let onCreateTask: (String, UUID, CGPoint, Bool) -> Void
  let onUnavailable: () -> Void
  let onBackgroundTap: (() -> Void)?
  let allowsTimedDragCreation: Bool
  let onTimedDragPreview: ((CGPoint, CGPoint) -> Void)?
  let onTimedDragCommit: ((CGPoint, CGPoint) -> Void)?
  let onTimedDragCancel: (() -> Void)?

  @MainActor
  final class Coordinator: NSObject {
    var isAllDayRegion = false
    var canCreateTask = false
    var projects: [ScheduleQuickAddProjectOption] = []
    var defaultProjectID: UUID?
    var onCreateTask: ((String, UUID, CGPoint, Bool) -> Void)?
    var onUnavailable: (() -> Void)?
    var onBackgroundTap: (() -> Void)?
    var allowsTimedDragCreation = false
    var onTimedDragPreview: ((CGPoint, CGPoint) -> Void)?
    var onTimedDragCommit: ((CGPoint, CGPoint) -> Void)?
    var onTimedDragCancel: (() -> Void)?
    weak var hostView: ScheduleQuickAddContextMenuView?
    var lastLocation: CGPoint = .zero
    var popover: NSPopover?
    var dragStartLocation: CGPoint?
    let dragThreshold: CGFloat = 4

    func presentMenu(from view: ScheduleQuickAddContextMenuView, event: NSEvent, location: CGPoint)
    {
      lastLocation = location
      var descriptors: [PlatformContextActionDescriptor] = [
        .action("할일 추가", isEnabled: canCreateTask) { [weak self] in
          self?.openQuickAddPopover()
        }
      ]

      if !canCreateTask {
        descriptors.append(.disabled("추가할 목록이 없습니다"))
      }

      AppKitContextMenuRenderer.shared.present(descriptors, with: event, for: view)
    }

    @MainActor
    func openQuickAddPopover() {
      guard canCreateTask, let hostView else {
        onUnavailable?()
        return
      }

      popover?.close()

      let popover = NSPopover()
      popover.behavior = .transient
      popover.contentSize = NSSize(width: 260, height: 134)
      popover.contentViewController = NSHostingController(
        rootView: ScheduleQuickAddPopoverContent(
          projects: projects,
          defaultProjectID: defaultProjectID,
          onSubmit: { [weak self] title, projectID in
            guard let self else { return }
            self.onCreateTask?(title, projectID, self.lastLocation, self.isAllDayRegion)
            self.popover?.close()
            self.popover = nil
          },
          onCancel: { [weak self] in
            self?.popover?.close()
            self?.popover = nil
          }
        )
      )
      popover.show(
        relativeTo: CGRect(x: lastLocation.x, y: lastLocation.y, width: 1, height: 1),
        of: hostView,
        preferredEdge: .maxY
      )
      self.popover = popover
    }

    func beginTimedDrag(at location: CGPoint) {
      guard allowsTimedDragCreation else { return }
      dragStartLocation = location
      onTimedDragCancel?()
    }

    func updateTimedDrag(to location: CGPoint) {
      guard allowsTimedDragCreation, let dragStartLocation else { return }
      if exceedsDragThreshold(from: dragStartLocation, to: location) {
        onTimedDragPreview?(dragStartLocation, location)
      } else {
        onTimedDragCancel?()
      }
    }

    func finishTimedDrag(at location: CGPoint) {
      defer { dragStartLocation = nil }
      guard allowsTimedDragCreation, let dragStartLocation else { return }
      if exceedsDragThreshold(from: dragStartLocation, to: location) {
        onTimedDragCommit?(dragStartLocation, location)
      } else {
        onTimedDragCancel?()
        onBackgroundTap?()
      }
    }

    func handleBackgroundTap() {
      onTimedDragCancel?()
      onBackgroundTap?()
    }

    func exceedsDragThreshold(from start: CGPoint, to end: CGPoint) -> Bool {
      max(abs(end.x - start.x), abs(end.y - start.y)) >= dragThreshold
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> ScheduleQuickAddContextMenuView {
    let view = ScheduleQuickAddContextMenuView()
    view.coordinator = context.coordinator
    context.coordinator.hostView = view
    return view
  }

  func updateNSView(_ nsView: ScheduleQuickAddContextMenuView, context: Context) {
    context.coordinator.hostView = nsView
    context.coordinator.isAllDayRegion = isAllDayRegion
    context.coordinator.canCreateTask = canCreateTask
    context.coordinator.projects = projects
    context.coordinator.defaultProjectID = defaultProjectID
    context.coordinator.onCreateTask = onCreateTask
    context.coordinator.onUnavailable = onUnavailable
    context.coordinator.onBackgroundTap = onBackgroundTap
    context.coordinator.allowsTimedDragCreation = allowsTimedDragCreation
    context.coordinator.onTimedDragPreview = onTimedDragPreview
    context.coordinator.onTimedDragCommit = onTimedDragCommit
    context.coordinator.onTimedDragCancel = onTimedDragCancel
  }
}

enum ScheduleResizeEdge: Hashable {
  case start
  case end
}

struct ScheduleTaskDragState {
  let entryID: String
  let taskID: UUID
  let isPreparationSlot: Bool
  let targetCompletedWorkUnits: Int?
  let originalDay: Date
  let originalTimeMinutes: Int?
  let originalDurationMinutes: Int?
  let originalViewportFrame: CGRect
  let originalPointerViewportX: CGFloat
  let originalPointerViewportY: CGFloat
  let originalPointerScheduleY: CGFloat
  let originalTopScheduleY: CGFloat
  var translation: CGSize = .zero
  var currentPointerViewportLocation: CGPoint?
  var isInAllDayZone: Bool = false
}

struct CommittedTaskDropState {
  let originalFrame: CGRect
  let isOriginalAllDay: Bool
  let dropFrame: CGRect
  let color: Color
  let isAllDay: Bool
  let label: String?
}

struct ScheduleCalendarDragState {
  let eventID: String
  let originalDay: Date
  let originalTimeMinutes: Int?
  let originalDurationMinutes: Int?
  let originalViewportFrame: CGRect
  let originalPointerViewportX: CGFloat
  let originalPointerViewportY: CGFloat
  let originalPointerScheduleY: CGFloat
  let originalTopScheduleY: CGFloat
  var translation: CGSize = .zero
  var currentPointerViewportLocation: CGPoint?
  var isInAllDayZone: Bool = false
}

struct ScheduleTaskResizeState {
  let entryID: String
  let taskID: UUID
  let isPreparationSlot: Bool
  let targetCompletedWorkUnits: Int?
  let originalDay: Date
  let originalTimeMinutes: Int
  let originalDurationMinutes: Int
  let edge: ScheduleResizeEdge
  let originalViewportFrame: CGRect
  var translationHeight: CGFloat = 0
}

struct ScheduleCalendarResizeState {
  let eventID: String
  let originalDay: Date
  let originalTimeMinutes: Int
  let originalDurationMinutes: Int
  let edge: ScheduleResizeEdge
  let originalViewportFrame: CGRect
  var translationHeight: CGFloat = 0
}

struct ScheduleTimedQuickCreateSelection: Equatable {
  let dayIndex: Int
  let day: Date
  let startMinutes: Int
  let durationMinutes: Int
}

struct PendingScheduleCalendarEditAction: Identifiable {
  let id = UUID()
  let eventID: String
  let preview: ScheduleInteractionPreview
  let actionName: String
}

struct ScheduleTaskSnapshotCache {
  let sourceSignature: Int
  let taskDescriptors: [WorkspaceScheduleTaskDescriptor]
  let workspaceTasksByID: [UUID: WorkspaceScheduleTaskDescriptor]
  let signature: Int
}

struct ScheduleBoardGlobalFramePreferenceKey: PreferenceKey {
  static let defaultValue: CGRect = .null

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

enum ScheduleBoardHostingInvalidationPolicy {
  static func boardContentVersion(
    today: Date,
    dayRange: ClosedRange<Int>,
    layoutSourceSignature: Int,
    selectedScheduleTaskID: UUID?,
    transientInteractionSignature _: Int
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(today.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(layoutSourceSignature)
    hasher.combine(selectedScheduleTaskID)
    return hasher.finalize()
  }

  static func pinnedTopVersion(
    today: Date,
    dayRange: ClosedRange<Int>,
    layoutSourceSignature: Int,
    calendarSourcesSignature: Int,
    selectedScheduleTaskID: UUID?,
    transientInteractionSignature _: Int
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(today.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(layoutSourceSignature)
    hasher.combine(calendarSourcesSignature)
    hasher.combine(selectedScheduleTaskID)
    return hasher.finalize()
  }
}

enum TaskTapSuppressionPolicy {
  static let completionControlDuration: TimeInterval = 0.2

  static func suppressedUntil(now: Date, duration: TimeInterval) -> Date {
    now.addingTimeInterval(duration)
  }

  static func shouldHandleTaskTap(now: Date, suppressedUntil: Date) -> Bool {
    now >= suppressedUntil
  }
}

@MainActor
func taskCompletionPressGesture(onPress: @escaping () -> Void) -> some Gesture {
  DragGesture(minimumDistance: 0)
    .onChanged { _ in onPress() }
}

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
  @State var scheduleDayHeaderShowWorkItem: DispatchWorkItem?
  @State var scheduleDayHeaderDetachWorkItem: DispatchWorkItem?
  @State var isCalendarPickerShown = false
  @State var committedTaskDrop: CommittedTaskDropState?

  let titleColumnWidth: CGFloat = 76
  let calendarMenuLeadingInset: CGFloat = 18
  let pastDayBuffer = 7
  let defaultVisibleStartDayOffset = 0
  let defaultVisibleStartHour = 3
  let futureDayWindow = 30
  let dayColumnWidth: CGFloat = 168 * 1.7
  let dateHeaderHeight: CGFloat = 32
  let allDayRowHeight: CGFloat = 24
  let minimumAllDayVisibleRowCount = 1
  let maximumAllDayVisibleRowCount = 10

  let allDayRailPadding: CGFloat = 6
  let allDayRailExtraVisibleHeight: CGFloat = 8
  let hourHeight: CGFloat = 52
  let hourCount = 24
  let timedBlockInset: CGFloat = 4
  let timedBlockColumnSpacing: CGFloat = 3
  let allDayChipHorizontalInset: CGFloat = 5
  let timedMinimumDuration = WorkspaceTaskScheduleEventStore.defaultScheduledDurationMinutes
  let dragSourcePlaceholderOpacity = 0.34
  let dragGhostOpacity = 0.86
  let dragGhostScale: CGFloat = 1.015
  let dragGhostShadowRadius: CGFloat = 10
  let dragGhostShadowYOffset: CGFloat = 4
  let selectionHighlightColor = Color(red: 1.0, green: 0.93, blue: 0.82)
  let layoutEngine = ScheduleDayTimelineLayoutEngine()
  let scheduleDayHeaderOverlayWidth: CGFloat = 260
  let scheduleDayHeaderShowDelay: TimeInterval = 0.18
  let scheduleOverlayDetachGraceDelay: TimeInterval = 0.08
  let scheduleItemFontScale: CGFloat = 1.265

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
    onEditCalendarEvent: @escaping (ScheduleCalendarEvent) -> Void = { _ in }
  ) {
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
    scrollViewportState.liveOffsetX
  }
  var currentScrollOffsetY: CGFloat {
    scrollViewportState.liveOffsetY
  }
  var days: [Date] {
    Array(dayRange).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: today)
    }
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
    ScheduleProjectionService.taskDescriptors(
      projectIDs: activeProjectIDs,
      projectSnapshots: workspaceScheduleProjectSnapshots,
      scheduleEntriesByProjectID: workspaceScheduleSliceEntriesByProjectID
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
    ScheduleBoardReadPath.sourceSignature(
      today: today,
      projectIDs: activeProjectIDs,
      projectSnapshots: workspaceScheduleProjectSnapshots,
      scheduleEntriesByProjectID: workspaceScheduleSliceEntriesByProjectID
    )
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
    MotionSystem.animation(
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

  var body: some View {
    scheduleBoardRoot
  }

  var scheduleBoardRoot: some View {
    let context = makeBodyContext()

    return GeometryReader { geometry in
      scheduleBoardViewportSection(geometry: geometry, context: context)
    }
    .confirmationDialog(
      "반복 일정 변경",
      isPresented: Binding(
        get: { pendingCalendarEditAction != nil },
        set: { isPresented in
          if !isPresented {
            pendingCalendarEditAction = nil
          }
        }
      ),
      titleVisibility: .visible
    ) {
      Button(ScheduleCalendarRecurringEditScope.thisEvent.title) {
        commitPendingCalendarEdit(scope: .thisEvent)
      }
      Button(ScheduleCalendarRecurringEditScope.futureEvents.title) {
        commitPendingCalendarEdit(scope: .futureEvents)
      }
      Button("취소", role: .cancel) {
        pendingCalendarEditAction = nil
      }
    } message: {
      Text("반복 이벤트라서 적용 범위를 선택해야 합니다.")
    }
    .alert(item: $calendarEditError) { error in
      Alert(
        title: Text("캘린더 일정 변경 실패"),
        message: Text(error.errorDescription ?? "일정 시간을 변경하지 못했습니다."),
        dismissButton: .default(Text("확인"))
      )
    }
    .background(scheduleBoardGeometryPreferenceSurface)
    .onDrop(
      of: [TaskDragPayload.textTypeIdentifier],
      delegate: ScheduleExternalTaskDropDelegate(
        resolvePreview: externalTaskDropPreview(at:),
        onPerformTaskDrop: applyExternalTaskDrop(taskID:preview:),
        onInvalidDrop: logScheduleInvalidDrop(at:reason:)
      )
    )
    .onPreferenceChange(ScheduleBoardGlobalFramePreferenceKey.self) { frame in
      boardFrameInGlobal = frame
      if !frame.isNull, viewportSyncDiagnostic == .dragProjectionFrameUnavailable {
        viewportSyncDiagnostic = nil
      }
    }
    .onAppear {
      requestTodayScroll()
      syncScheduleBoardCaches(
        filteredEvents: context.filteredEvents,
        backgroundEvents: context.backgroundEvents,
        taskSnapshot: context.taskSnapshot,
        layoutCache: context.layoutCache,
        layoutSourceSignature: context.layoutSourceSignature,
        force: true
      )
      if isActive {
        refreshCalendarOverlay(force: scheduleCalendarOverlayProjection.accessDenied)
      }
    }
    .task(
      id: scheduleWorkspaceLoadSignature(
        projectIDs: activeProjectIDs,
        workspaceTreeRevision: appState.workspaceTreeRevision
      )
    ) {
      guard isActive else { return }
      await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
    }
    .onChange(of: appState.scheduleJumpToTodayToken) { _, _ in
      requestTodayScroll()
    }
    .onChange(of: appState.scheduleJumpToDateToken) { _, _ in
      requestScroll(to: appState.scheduleJumpTargetDate ?? .now)
    }
    .onChange(of: appState.isHoveringTimelineDayHeaderOverlay) { _, isHovering in
      if isHovering {
        scheduleDayHeaderDetachWorkItem?.cancel()
        scheduleDayHeaderDetachWorkItem = nil
      } else {
        dismissScheduleDayHeaderOverlayIfDetached()
      }
    }
    .onChange(of: appState.currentDayChangeToken) { _, _ in
      guard isActive else { return }
      syncScheduleBoardCaches(
        filteredEvents: context.filteredEvents,
        backgroundEvents: context.backgroundEvents,
        taskSnapshot: context.taskSnapshot,
        layoutCache: context.layoutCache,
        layoutSourceSignature: context.layoutSourceSignature,
        force: false
      )
      refreshCalendarOverlay(force: true)
    }
    .onChange(of: dayRange) { _, _ in
      guard isActive else { return }
      dismissScheduleDayHeaderHoverIfObscured()
      refreshCalendarOverlay()
    }
    .onChange(of: horizontalOffsetX) { _, _ in
      dismissScheduleDayHeaderHoverIfObscured()
      if scrollViewportState.scrollView != nil {
        clearScheduleViewportDiagnostic(.scrollRequestQueuedWithoutViewport)
      }
    }
    .onChange(of: verticalOffsetY) { _, _ in
      if scrollViewportState.scrollView != nil {
        clearScheduleViewportDiagnostic(.scrollRequestQueuedWithoutViewport)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .reminderAppEditingEscapePressed)) { _ in
      guard pendingTimedQuickCreateSelection != nil else { return }
      pendingTimedQuickCreateSelection = nil
      activeTimedQuickCreateSelection = nil
      cancelScheduleDayHeaderOverlay()
    }
    .onChange(of: context.liveTaskSourceSignature) { _, _ in
      guard isActive, !appState.isEditorMotionSuppressed else { return }
      refreshScheduledTaskSnapshotIfNeeded(force: false, snapshot: context.taskSnapshot)
      refreshScheduleDayHeaderSectionsIfNeeded(
        sourceSignature: refreshedScheduleDayHeaderSourceSignature(
          taskSignature: context.taskSnapshot.signature
        ),
        force: false
      )
    }
    .onChange(of: context.liveLayoutSourceSignature) { _, newSignature in
      guard isActive, !appState.isEditorMotionSuppressed else { return }
      refreshLayoutCacheIfNeeded(
        filteredEvents: context.filteredEvents,
        backgroundEvents: context.backgroundEvents,
        taskSnapshot: context.taskSnapshot,
        sourceSignature: newSignature,
        force: false,
        layoutCache: context.layoutCache
      )
    }
    .onChange(of: appState.isEditorMotionSuppressed) { _, isSuppressed in
      guard isActive, !isSuppressed else { return }
      syncScheduleBoardCaches(
        filteredEvents: context.filteredEvents,
        backgroundEvents: context.backgroundEvents,
        taskSnapshot: context.taskSnapshot,
        layoutCache: context.layoutCache,
        layoutSourceSignature: context.layoutSourceSignature,
        force: false
      )
    }
    .onChange(of: isActive) { _, active in
      if active {
        Task {
          await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
        }
        syncScheduleBoardCaches(
          filteredEvents: context.filteredEvents,
          backgroundEvents: context.backgroundEvents,
          taskSnapshot: context.taskSnapshot,
          layoutCache: context.layoutCache,
          layoutSourceSignature: context.layoutSourceSignature,
          force: false
        )
        refreshCalendarOverlay(force: true)
      } else {
        cancelScheduleDayHeaderOverlay()
        calendarOverlayRefreshTask?.cancel()
        calendarOverlayRefreshTask = nil
      }
    }
    .onDisappear {
      onTaskDragProjectionChanged?(nil, nil)
      cancelScheduleDayHeaderOverlay()
      calendarOverlayRefreshTask?.cancel()
      calendarOverlayRefreshTask = nil
    }
  }

  func scheduleBoardViewportSection(
    geometry: GeometryProxy,
    context: ScheduleBoardBodyContext
  ) -> some View {
    ZStack(alignment: .topLeading) {
      scheduleBoardScrollShell(
        geometry: geometry,
        context: context
      )

      scheduleBoardTopLeftHeaderSection

      scheduleBoardInteractionOverlaySection

      scheduleBoardChromeSection

      scheduleRuntimeNoticeSection
    }
  }

  @ViewBuilder
  var scheduleRuntimeNoticeSection: some View {
    if let notice = scheduleRuntimeNotice {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: notice.symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
          .padding(.top, 1)

        VStack(alignment: .leading, spacing: 3) {
          Text(notice.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)

          Text(notice.message)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: 360, alignment: .leading)
      .overlaySurface(
        cornerRadius: 12,
        strokeColor: .primary,
        style: scheduleOverlayCardStyle
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      .padding(.top, 12)
      .padding(.trailing, 12)
      .allowsHitTesting(false)
    }
  }

  func scheduleBoardScrollShell(
    geometry: GeometryProxy,
    context: ScheduleBoardBodyContext
  ) -> some View {
    let boardContentVersion = boardContentVersion(
      layoutSourceSignature: context.layoutSourceSignature
    )
    let pinnedTopVersion = pinnedTopVersion(
      layoutSourceSignature: context.layoutSourceSignature
    )

    return UnifiedScheduleBoardScrollView(
      boardSize: CGSize(width: boardWidth, height: boardHeight),
      titleColumnWidth: titleColumnWidth,
      headerHeight: headerHeight,
      dayColumnWidth: dayColumnWidth,
      boardContentVersion: boardContentVersion,
      pinnedLeftVersion: pinnedLeftVersion,
      pinnedTopVersion: pinnedTopVersion,
      scrollRequestGeneration: scrollRequestGeneration,
      publishesLiveOffsets: activeTaskDrag != nil || activeTaskResize != nil
        || activeCalendarDrag != nil || activeCalendarResize != nil,
      isDateBoundarySnappingEnabled: isDateBoundarySnappingEnabled,
      viewportState: scrollViewportState,
      offsetX: $horizontalOffsetX,
      offsetY: $verticalOffsetY,
      requestedOffsetX: $requestedOffsetX,
      requestedOffsetY: $requestedOffsetY
    ) {
      scheduleTimedGridSection(
        timedEntries: context.layoutCache.timedEntries,
        backgroundTimedEntries: context.layoutCache.backgroundTimedEntries
      )
    } pinnedLeft: {
      scheduleBoardLeftAxisSection
    } pinnedTop: {
      scheduleBoardHeaderRailSection(
        allDayEntries: context.layoutCache.allDayEntries,
        backgroundAllDayEntries: context.layoutCache.backgroundAllDayEntries
      )
    }
    .frame(width: geometry.size.width, height: geometry.size.height)
  }

  var scheduleBoardGeometryPreferenceSurface: some View {
    GeometryReader { proxy in
      let dragFrame = proxy.frame(in: .named(dragProjectionCoordinateSpaceName))
      let containerOrigin = proxy.frame(in: .named(workspaceMainPaneCoordinateSpaceName)).origin
      Color.clear
        .preference(
          key: ScheduleBoardGlobalFramePreferenceKey.self,
          value: dragFrame
        )
        .preference(
          key: TimelineDayHeaderOverlayPresentationPreferenceKey.self,
          value: isActive
            ? scheduleDayHeaderOverlayPresentation(containerOrigin: containerOrigin)
            : nil
        )
    }
  }

  func requestTodayScroll() {
    requestScroll(to: today)
  }

  func requestScroll(to targetDate: Date) {
    if scrollViewportState.scrollView == nil {
      recordScheduleViewportDiagnostic(.scrollRequestQueuedWithoutViewport)
    } else {
      clearScheduleViewportDiagnostic(.scrollRequestQueuedWithoutViewport)
    }
    let targetDay = calendar.startOfDay(for: targetDate)
    let targetOffset = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0
    let targetRange = (targetOffset - pastDayBuffer)...(targetOffset + futureDayWindow)
    if dayRange != targetRange {
      dayRange = targetRange
    }
    let targetIndex = max(0, targetOffset - targetRange.lowerBound)
    requestedOffsetX = CGFloat(targetIndex) * dayColumnWidth
    requestedOffsetY = headerHeight + CGFloat(defaultVisibleStartHour) * hourHeight
    scrollRequestGeneration += 1
  }

  func scheduleLayoutSourceSignature(filteredEventHash: Int, taskSignature: Int) -> Int {
    var hasher = Hasher()
    hasher.combine(today.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(taskSignature)
    hasher.combine(filteredEventHash)
    return hasher.finalize()
  }

  func resolvedScheduleLayoutSourceSignature(
    filteredEventHash: Int,
    taskSignature: Int,
    preferCached: Bool
  ) -> Int {
    if preferCached, let cachedLayoutSourceSignature {
      return cachedLayoutSourceSignature
    }
    return scheduleLayoutSourceSignature(
      filteredEventHash: filteredEventHash,
      taskSignature: taskSignature
    )
  }

  func syncScheduleBoardCaches(
    filteredEvents: [ScheduleCalendarEvent],
    backgroundEvents: [ScheduleCalendarEvent],
    taskSnapshot: ScheduleTaskSnapshotCache,
    layoutCache: ScheduleLayoutCache,
    layoutSourceSignature: Int,
    force: Bool
  ) {
    refreshScheduledTaskSnapshotIfNeeded(force: force, snapshot: taskSnapshot)
    refreshScheduleDayHeaderSectionsIfNeeded(
      sourceSignature: refreshedScheduleDayHeaderSourceSignature(
        taskSignature: taskSnapshot.signature
      ),
      force: force
    )
    refreshLayoutCacheIfNeeded(
      filteredEvents: filteredEvents,
      backgroundEvents: backgroundEvents,
      taskSnapshot: taskSnapshot,
      sourceSignature: layoutSourceSignature,
      force: force,
      layoutCache: layoutCache
    )
  }

  func applyLayoutCache(
    _ layoutCache: ScheduleLayoutCache,
    sourceSignature: Int
  ) {
    cachedTimedEntries = layoutCache.timedEntries
    cachedAllDayEntries = layoutCache.allDayEntries
    cachedBackgroundTimedEntries = layoutCache.backgroundTimedEntries
    cachedBackgroundAllDayEntries = layoutCache.backgroundAllDayEntries
    cachedLayoutSourceSignature = sourceSignature
  }

  func refreshLayoutCacheIfNeeded(
    filteredEvents: [ScheduleCalendarEvent],
    backgroundEvents: [ScheduleCalendarEvent],
    taskSnapshot: ScheduleTaskSnapshotCache,
    sourceSignature: Int,
    force: Bool,
    layoutCache: ScheduleLayoutCache? = nil
  ) {
    guard force || cachedLayoutSourceSignature != sourceSignature else { return }
    let layoutCache =
      layoutCache
      ?? buildLayoutCache(
        filteredEvents: filteredEvents,
        backgroundEvents: backgroundEvents,
        taskSnapshot: taskSnapshot
      )
    applyLayoutCache(layoutCache, sourceSignature: sourceSignature)
  }

  func resolvedScheduleTaskSnapshot(preferCached: Bool) -> ScheduleTaskSnapshotCache {
    let sourceSignature = scheduleTaskSourceSignature
    if preferCached, let cachedScheduledTaskSourceSignature {
      return ScheduleTaskSnapshotCache(
        sourceSignature: cachedScheduledTaskSourceSignature,
        taskDescriptors: cachedScheduledTaskDescriptors,
        workspaceTasksByID: cachedWorkspaceScheduleTasksByID,
        signature: cachedScheduleTaskSignature
      )
    }
    if cachedScheduledTaskSourceSignature == sourceSignature {
      return ScheduleTaskSnapshotCache(
        sourceSignature: cachedScheduledTaskSourceSignature ?? sourceSignature,
        taskDescriptors: cachedScheduledTaskDescriptors,
        workspaceTasksByID: cachedWorkspaceScheduleTasksByID,
        signature: cachedScheduleTaskSignature
      )
    }
    return buildScheduledTaskSnapshot(sourceSignature: sourceSignature)
  }

  func buildScheduledTaskSnapshot(sourceSignature: Int? = nil) -> ScheduleTaskSnapshotCache {
    let sourceSignature = sourceSignature ?? scheduleTaskSourceSignature
    return ScheduleProjectionService.buildTaskSnapshot(
      taskDescriptors: workspaceScheduleTasks,
      sourceSignature: sourceSignature
    )
  }

  func applyScheduledTaskSnapshot(_ snapshot: ScheduleTaskSnapshotCache) {
    cachedScheduledTaskSourceSignature = snapshot.sourceSignature
    cachedScheduledTaskDescriptors = snapshot.taskDescriptors
    cachedWorkspaceScheduleTasksByID = snapshot.workspaceTasksByID
    cachedScheduleTaskSignature = snapshot.signature
  }

  func refreshScheduledTaskSnapshotIfNeeded(
    force: Bool,
    snapshot: ScheduleTaskSnapshotCache? = nil
  ) {
    let snapshot = snapshot ?? buildScheduledTaskSnapshot(sourceSignature: scheduleTaskSourceSignature)
    guard force || cachedScheduledTaskSourceSignature != snapshot.sourceSignature else { return }
    applyScheduledTaskSnapshot(snapshot)
  }

}
