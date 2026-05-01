import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

let workspaceMainPaneCoordinateSpaceName = "workspaceMainPane"

struct TimelineProjectTapPassthroughFramePreferenceKey: PreferenceKey {
  static let defaultValue: [CGRect] = []

  static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
    value.append(contentsOf: nextValue())
  }
}

struct TimelineTaskBadgeOverlayTaskItem: Identifiable, Sendable {
  let id: String
  let taskID: UUID
  let title: String
  let isOverdue: Bool
}

struct TimelineTaskBadgeOverlayPlannedItem: Identifiable, Sendable {
  let id: String
  let taskID: UUID
  let title: String
  let targetCompletedUnits: Int
}

struct TimelineTaskBadgeOverlayPresentation: Sendable {
  let frame: CGRect
  let projectReference: WorkspaceProjectReference
  let projectColorHex: String?
  let date: Date
  let totalCount: Int
  let strongTasks: [TimelineTaskBadgeOverlayTaskItem]
  let lightTasks: [TimelineTaskBadgeOverlayPlannedItem]
  let completedTasks: [TimelineTaskBadgeOverlayTaskItem]
  let hiddenStrongCount: Int
  let hiddenLightCount: Int
  let hiddenCompletedCount: Int
}

struct TimelineTaskBadgeOverlayPresentationPreferenceKey: PreferenceKey {
  static let defaultValue: TimelineTaskBadgeOverlayPresentation? = nil

  static func reduce(
    value: inout TimelineTaskBadgeOverlayPresentation?,
    nextValue: () -> TimelineTaskBadgeOverlayPresentation?
  ) {
    value = nextValue() ?? value
  }
}

struct TimelineDayHeaderOverlayTaskItem: Identifiable, Sendable {
  let id: String
  let projectReference: WorkspaceProjectReference
  let taskID: UUID
  let title: String
  let isCompleted: Bool
  let isOverdue: Bool
}

struct TimelineDayHeaderOverlayProjectSection: Identifiable, Sendable {
  let id: UUID
  let projectReference: WorkspaceProjectReference
  let projectColorHex: String?
  let projectTitle: String
  let tasks: [TimelineDayHeaderOverlayTaskItem]
}

struct TimelineDayHeaderOverlayPresentation: Sendable {
  let frame: CGRect
  let date: Date
  let sections: [TimelineDayHeaderOverlayProjectSection]
}

struct TimelineDayHeaderOverlayPresentationPreferenceKey: PreferenceKey {
  static let defaultValue: TimelineDayHeaderOverlayPresentation? = nil

  static func reduce(
    value: inout TimelineDayHeaderOverlayPresentation?,
    nextValue: () -> TimelineDayHeaderOverlayPresentation?
  ) {
    value = nextValue() ?? value
  }
}

final class TimelineOverlayMetricsCache {
  private struct TaskBadgeKey: Hashable {
    let strongCount: Int
    let hiddenStrongCount: Int
    let lightCount: Int
    let hiddenLightCount: Int
    let completedCount: Int
    let hiddenCompletedCount: Int
  }

  private struct DayHeaderKey: Hashable {
    let taskCountsBySection: [Int]
  }

  private var taskBadgeHeights: [TaskBadgeKey: CGFloat] = [:]
  private var dayHeaderHeights: [DayHeaderKey: CGFloat] = [:]

  func taskBadgeHeight(
    for context: TimelineTaskBadgeOverlayContext,
    build: () -> CGFloat
  ) -> CGFloat {
    let key = TaskBadgeKey(
      strongCount: context.strongPreview?.tasks.count ?? 0,
      hiddenStrongCount: context.hiddenStrongCount,
      lightCount: context.lightPreview?.tasks.count ?? 0,
      hiddenLightCount: context.hiddenLightCount,
      completedCount: context.completedPreview?.tasks.count ?? 0,
      hiddenCompletedCount: context.hiddenCompletedCount
    )
    if let cached = taskBadgeHeights[key] {
      return cached
    }
    let height = build()
    taskBadgeHeights[key] = height
    return height
  }

  func dayHeaderHeight(
    for sections: [TimelineDayHeaderOverlayProjectSection],
    build: () -> CGFloat
  ) -> CGFloat {
    let key = DayHeaderKey(taskCountsBySection: sections.map { $0.tasks.count })
    if let cached = dayHeaderHeights[key] {
      return cached
    }
    let height = build()
    dayHeaderHeights[key] = height
    return height
  }
}

struct TimelineRowMetrics {
  let height: CGFloat
  let spacing: CGFloat
  let contentInsetY: CGFloat

  var contentHeight: CGFloat {
    max(0, height - contentInsetY * 2)
  }

  var midpointY: CGFloat {
    height * 0.5
  }

  var stride: CGFloat {
    height + spacing
  }

  func totalHeight(for rowCount: Int) -> CGFloat {
    guard rowCount > 0 else { return 1 }
    return CGFloat(rowCount) * height + CGFloat(max(0, rowCount - 1)) * spacing
  }

  func topPadding(for index: Int) -> CGFloat {
    index == 0 ? 0 : spacing / 2
  }

  func bottomPadding(for index: Int, totalCount: Int) -> CGFloat {
    index == totalCount - 1 ? 0 : spacing / 2
  }

  func topY(for rowIndex: Int) -> CGFloat {
    CGFloat(rowIndex) * stride
  }
}

struct TimelineRowLayout {
  let topY: CGFloat
  let metrics: TimelineRowMetrics
}

struct TaskProjectMoveSnapshot {
  let movedTaskIDs: [UUID]
  let taskProjectIDs: [UUID: UUID]
  let rootStructureByProjectID: [UUID: ReminderProjectRootStructureRecord]
  let sequenceAssignmentsByProjectID: [UUID: [UUID: String]]
}

struct CreatedProjectUndoTemplate {
  let title: String
  let colorHex: String?
  let sortOrder: Int
}

struct CreatedProjectUndoSnapshot {
  let projectID: UUID
  let template: CreatedProjectUndoTemplate
}

struct ProjectColorUndoSnapshot {
  let projectID: UUID
  let colorHex: String?
}

struct TimelineCreatedProjectUndoTemplate {
  let title: String
  let colorHex: String?
}

struct TimelineCreatedProjectUndoSnapshot {
  let projectID: UUID
  let template: TimelineCreatedProjectUndoTemplate
}

struct TimelineTaskCompletionUndoSnapshot: Equatable {
  let taskID: UUID
  let projectID: UUID
  let isCompleted: Bool
  let completionDate: Date?
  let isRecurring: Bool
  let occurrenceDate: Date?
  let editFields: RetainedTaskEditFields
}

struct TimelinePlannedWorkUndoSnapshot: Equatable {
  let taskID: UUID
  let projectID: UUID
  let completedUnits: Int
  let completedOn: Date
}

struct TimelineProjectSortOrderUndoSnapshot {
  let sortOrdersByProjectID: [UUID: Int]
}

struct TimelineProjectBucketOrderUndoSnapshot {
  let boardOrdersByProjectID: [UUID: Int?]
  let stagesByProjectID: [UUID: ProjectProgressStage]
}

enum TimelineProjectManualOrderStore {
  private static let storageKey = "workspace.timelineProjectManualOrder.v1"

  static func load(defaults: UserDefaults = .standard) -> [UUID: Int64] {
    guard let data = defaults.data(forKey: storageKey),
      let raw = try? JSONDecoder().decode([String: Int64].self, from: data)
    else {
      return [:]
    }
    return raw.reduce(into: [UUID: Int64]()) { result, item in
      guard let id = UUID(uuidString: item.key) else { return }
      result[id] = item.value
    }
  }

  static func save(_ order: [UUID: Int64], defaults: UserDefaults = .standard) {
    let raw = Dictionary(uniqueKeysWithValues: order.map { ($0.key.uuidString, $0.value) })
    guard let data = try? JSONEncoder().encode(raw) else { return }
    defaults.set(data, forKey: storageKey)
  }

  static func mergedOrder(
    existing: [UUID: Int64],
    reminderOrderedProjectIDs: [UUID],
    availableProjectIDs: [UUID]
  ) -> [UUID: Int64] {
    let availableSet = Set(availableProjectIDs)
    var next = existing.filter { availableSet.contains($0.key) }
    let knownProjectIDs = Set(next.keys)
    let missingProjectIDs = reminderOrderedProjectIDs.filter { projectID in
      availableSet.contains(projectID) && !knownProjectIDs.contains(projectID)
    }
    guard !missingProjectIDs.isEmpty else { return next }

    let maxExistingOrder = next.values.max() ?? -1
    for (offset, projectID) in missingProjectIDs.enumerated() {
      next[projectID] = maxExistingOrder + Int64(offset) + 1
    }
    return next
  }
}

enum TimelineProjectTaskManualOrderStore {
  private static let storageKey = "workspace.timelineProjectTaskManualOrder.v1"

  static func load(defaults: UserDefaults = .standard) -> [UUID: [UUID: Int64]] {
    guard let data = defaults.data(forKey: storageKey),
      let raw = try? JSONDecoder().decode([String: [String: Int64]].self, from: data)
    else {
      return [:]
    }
    return raw.reduce(into: [UUID: [UUID: Int64]]()) { result, projectItem in
      guard let projectID = UUID(uuidString: projectItem.key) else { return }
      result[projectID] = projectItem.value.reduce(into: [UUID: Int64]()) { tasks, taskItem in
        guard let taskID = UUID(uuidString: taskItem.key) else { return }
        tasks[taskID] = taskItem.value
      }
    }
  }

  static func save(_ order: [UUID: [UUID: Int64]], defaults: UserDefaults = .standard) {
    let raw = Dictionary(
      uniqueKeysWithValues: order.map { projectID, taskOrder in
        (
          projectID.uuidString,
          Dictionary(uniqueKeysWithValues: taskOrder.map { ($0.key.uuidString, $0.value) })
        )
      }
    )
    guard let data = try? JSONEncoder().encode(raw) else { return }
    defaults.set(data, forKey: storageKey)
  }

  static func projectOrder(
    for projectID: UUID,
    defaults: UserDefaults = .standard
  ) -> [UUID: Int64] {
    load(defaults: defaults)[projectID] ?? [:]
  }

  static func saveProjectOrder(
    _ orderedTaskIDs: [UUID],
    for projectID: UUID,
    defaults: UserDefaults = .standard
  ) {
    var allOrders = load(defaults: defaults)
    allOrders[projectID] = orderMap(for: orderedTaskIDs)
    save(allOrders, defaults: defaults)
  }

  static func orderedTaskIDs(
    _ taskIDs: [UUID],
    using storedOrder: [UUID: Int64]
  ) -> [UUID] {
    guard !storedOrder.isEmpty else { return taskIDs }
    let defaultIndexes = Dictionary(uniqueKeysWithValues: taskIDs.enumerated().map { ($0.element, $0.offset) })
    return taskIDs.sorted { lhs, rhs in
      switch (storedOrder[lhs], storedOrder[rhs]) {
      case let (lhsOrder?, rhsOrder?):
        if lhsOrder != rhsOrder {
          return lhsOrder < rhsOrder
        }
        return (defaultIndexes[lhs] ?? 0) < (defaultIndexes[rhs] ?? 0)
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        return (defaultIndexes[lhs] ?? 0) < (defaultIndexes[rhs] ?? 0)
      }
    }
  }

  static func orderMap(for orderedTaskIDs: [UUID]) -> [UUID: Int64] {
    Dictionary(uniqueKeysWithValues: orderedTaskIDs.enumerated().map {
      ($0.element, Int64($0.offset))
    })
  }

  static func insertedTaskIDs(
    _ taskIDs: [UUID],
    insertedID: UUID,
    after anchorID: UUID?
  ) -> [UUID] {
    var ordered = taskIDs.filter { $0 != insertedID }
    guard let anchorID, let anchorIndex = ordered.firstIndex(of: anchorID) else {
      ordered.append(insertedID)
      return ordered
    }
    ordered.insert(insertedID, at: min(anchorIndex + 1, ordered.count))
    return ordered
  }

  static func removedTaskIDs(
    _ taskIDs: [UUID],
    removedID: UUID
  ) -> [UUID] {
    taskIDs.filter { $0 != removedID }
  }
}

enum TimelineProjectListDraftPolicy {
  static func shouldCancelDraft(title: String) -> Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

enum TimelineTaskCompletionTogglePolicy {
  static func nextIsCompleted(currentIsCompleted: Bool) -> Bool {
    !currentIsCompleted
  }

  static func completionDate(nextIsCompleted: Bool, now: Date = .now) -> Date? {
    nextIsCompleted ? now : nil
  }
}

enum TimelineHiddenProjectStore {
  private static let storageKey = "workspace.timelineHiddenProjects.v1"

  static func load(defaults: UserDefaults = .standard) -> Set<UUID> {
    guard let raw = defaults.stringArray(forKey: storageKey) else {
      return []
    }
    return Set(raw.compactMap(UUID.init(uuidString:)))
  }

  static func save(_ projectIDs: Set<UUID>, defaults: UserDefaults = .standard) {
    guard !projectIDs.isEmpty else {
      defaults.removeObject(forKey: storageKey)
      return
    }
    let raw = projectIDs.map(\.uuidString).sorted()
    defaults.set(raw, forKey: storageKey)
  }
}

struct TimelineCompletedCountLayout: Identifiable {
  let id: String
  let date: Date
  let x: CGFloat
  let count: Int
  let badgeWidth: CGFloat
  let hoverTargetID: String
}

final class FlippedTimelineDocumentView: NSView {
  override var isFlipped: Bool { true }
}

@MainActor
final class TimelineOverlayHoverExclusionRegistry {
  static let shared = TimelineOverlayHoverExclusionRegistry()

  private let views = NSHashTable<NSView>.weakObjects()

  private init() {}

  func register(_ view: NSView) {
    views.add(view)
  }

  func unregister(_ view: NSView) {
    views.remove(view)
  }

  func contains(windowLocation: NSPoint, in window: NSWindow) -> Bool {
    views.allObjects.contains { view in
      guard view.window === window, !view.isHidden else { return false }
      let localPoint = view.convert(windowLocation, from: nil)
      return view.bounds.contains(localPoint)
    }
  }
}

final class FlippedTimelineClipView: NSClipView {
  var onMouseMovedInVisibleRect: ((NSEvent, FlippedTimelineClipView) -> Void)?
  var onMouseExitedVisibleRect: (() -> Void)?
  private var timelineTrackingArea: NSTrackingArea?
  private var eventMonitor: Any?

  override var isFlipped: Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let timelineTrackingArea {
      removeTrackingArea(timelineTrackingArea)
    }
    let nextTrackingArea = NSTrackingArea(
      rect: bounds,
      options: [
        .activeAlways,
        .inVisibleRect,
        .mouseEnteredAndExited,
        .mouseMoved,
        .enabledDuringMouseDrag,
      ],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(nextTrackingArea)
    timelineTrackingArea = nextTrackingArea
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil {
      removeEventMonitor()
      onMouseExitedVisibleRect?()
    }
    super.viewWillMove(toWindow: newWindow)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    installEventMonitorIfNeeded()
  }

  override func mouseMoved(with event: NSEvent) {
    refreshHoverFromWindowEvent(event)
    super.mouseMoved(with: event)
  }

  override func mouseDragged(with event: NSEvent) {
    refreshHoverFromWindowEvent(event)
    super.mouseDragged(with: event)
  }

  override func mouseExited(with event: NSEvent) {
    onMouseExitedVisibleRect?()
    super.mouseExited(with: event)
  }

  private func installEventMonitorIfNeeded() {
    guard eventMonitor == nil, window != nil else { return }
    eventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    ) { [weak self] event in
      self?.refreshHoverFromWindowEvent(event)
      return event
    }
  }

  private func removeEventMonitor() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
    }
    eventMonitor = nil
  }

  private func refreshHoverFromWindowEvent(_ event: NSEvent) {
    guard let window, event.window === window else {
      onMouseExitedVisibleRect?()
      return
    }

    let localPoint = convert(event.locationInWindow, from: nil)
    guard bounds.contains(localPoint),
      !TimelineOverlayHoverExclusionRegistry.shared.contains(
        windowLocation: event.locationInWindow,
        in: window
      )
    else {
      onMouseExitedVisibleRect?()
      return
    }

    onMouseMovedInVisibleRect?(event, self)
  }

  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    guard let documentView else {
      return super.constrainBoundsRect(proposedBounds)
    }

    var constrained = proposedBounds
    let docFrame = documentView.frame

    let maxX = max(0, docFrame.width - constrained.width)
    let maxY = max(0, docFrame.height - constrained.height)

    constrained.origin.x = min(max(0, constrained.origin.x), maxX)
    constrained.origin.y = min(max(0, constrained.origin.y), maxY)

    return constrained
  }
}

final class TimelineInteractionScrollView: NSScrollView {
  var noteUserScrollActivity: (() -> Void)?
  var beginUserScrollSession: (() -> Void)?

  override func scrollWheel(with event: NSEvent) {
    noteUserScrollActivity?()
    beginUserScrollSession?()
    super.scrollWheel(with: event)
  }
}

final class ScrollPassthroughHostingView<Content: View>: NSHostingView<Content> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    return super.hitTest(point)
  }
}

final class LeftClickMenuHostingView<Content: View>: NSHostingView<Content> {
  var presentMenu: ((NSEvent, NSView) -> Void)?

  override func mouseDown(with event: NSEvent) {
    guard let presentMenu else {
      super.mouseDown(with: event)
      return
    }
    presentMenu(event, self)
  }
}

struct LeftClickMenuButton<Content: View>: NSViewRepresentable {
  final class Coordinator: NSObject {
    var selectedStage: ProjectProgressStage
    var onSelect: (ProjectProgressStage) -> Void

    init(
      selectedStage: ProjectProgressStage,
      onSelect: @escaping (ProjectProgressStage) -> Void
    ) {
      self.selectedStage = selectedStage
      self.onSelect = onSelect
    }
  }

  let content: Content
  let selectedStage: ProjectProgressStage
  let onSelect: (ProjectProgressStage) -> Void

  init(
    selectedStage: ProjectProgressStage,
    onSelect: @escaping (ProjectProgressStage) -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
    self.selectedStage = selectedStage
    self.onSelect = onSelect
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selectedStage: selectedStage, onSelect: onSelect)
  }

  func makeNSView(context: Context) -> LeftClickMenuHostingView<Content> {
    let view = LeftClickMenuHostingView(rootView: content)
    view.presentMenu = { event, hostView in
      AppKitContextMenuRenderer.shared.present(
        menuDescriptors(with: context.coordinator),
        with: event,
        for: hostView
      )
    }
    return view
  }

  func updateNSView(_ nsView: LeftClickMenuHostingView<Content>, context: Context) {
    nsView.rootView = content
    context.coordinator.selectedStage = selectedStage
    context.coordinator.onSelect = onSelect
    nsView.presentMenu = { event, hostView in
      AppKitContextMenuRenderer.shared.present(
        menuDescriptors(with: context.coordinator),
        with: event,
        for: hostView
      )
    }
  }

  private func menuDescriptors(with coordinator: Coordinator) -> [PlatformContextActionDescriptor] {
    ProjectProgressStage.allCases.map { stage in
      PlatformContextActionDescriptor.action(
        stage.label,
        state: stage == coordinator.selectedStage ? .on : .off
      ) {
        coordinator.onSelect(stage)
      }
    }
  }
}

enum TimelineTaskBadgeVisualStyle {
  case strong
  case light
  case overdue
}

struct TimelineTaskBadgeLayout: Identifiable {
  let id: String
  let projectReference: WorkspaceProjectReference
  let date: Date
  let rowIndex: Int
  let x: CGFloat
  let badgeWidth: CGFloat
  let count: Int
  let strongPreview: TimelineDayPreview?
  let lightPreview: TimelineWorkDayPreview?
  let visualStyle: TimelineTaskBadgeVisualStyle
}

struct TimelineTaskBadgeHitTarget: Equatable {
  let badgeID: String
  let rect: CGRect
}

struct TimelineTaskBadgeOverlayContext {
  let badgeID: String
  let projectReference: WorkspaceProjectReference
  let date: Date
  let badgeMinX: CGFloat
  let badgeMaxX: CGFloat
  let badgeMidY: CGFloat
  let strongPreview: TimelineDayPreview?
  let lightPreview: TimelineWorkDayPreview?
  let completedPreview: TimelineDayPreview?

  var hiddenStrongCount: Int {
    max(0, (strongPreview?.totalCount ?? 0) - (strongPreview?.tasks.count ?? 0))
  }

  var hiddenLightCount: Int {
    max(0, (lightPreview?.totalCount ?? 0) - (lightPreview?.tasks.count ?? 0))
  }

  var totalCount: Int {
    (strongPreview?.totalCount ?? 0) + (lightPreview?.totalCount ?? 0)
      + (completedPreview?.totalCount ?? 0)
  }

  var hiddenCompletedCount: Int {
    max(0, (completedPreview?.totalCount ?? 0) - (completedPreview?.tasks.count ?? 0))
  }
}

enum TimelineTaskBadgeOverlayPlacement {
  case above
  case below
}

struct TimelineTaskBadgeOverlayLayout {
  let position: CGPoint
  let placement: TimelineTaskBadgeOverlayPlacement
}

struct TimelineProjectRowDropModifier: ViewModifier {
  let bar: TimelineProjectBar
  @Binding var draggingProjectID: UUID?
  @Binding var dropIndicator: TimelineProjectDropIndicator?
  @Binding var taskDropTargetProjectID: UUID?
  let onPerformDrop: (UUID, UUID, TimelineProjectDropPlacement) -> Void
  let onPerformTaskDrop: (UUID, UUID) -> Void

  func body(content: Content) -> some View {
    content.onDrop(
      of: [UTType.text.identifier],
      delegate: TimelineProjectRowDropDelegate(
        targetProjectID: bar.projectID,
        draggingProjectID: $draggingProjectID,
        dropIndicator: $dropIndicator,
        taskDropTargetProjectID: $taskDropTargetProjectID,
        onPerformDrop: onPerformDrop,
        onPerformTaskDrop: onPerformTaskDrop
      )
    )
  }
}

struct TimelineProjectDragModifier: ViewModifier {
  let bar: TimelineProjectBar
  @Binding var draggingProjectID: UUID?

  func body(content: Content) -> some View {
    content.onDrag {
      draggingProjectID = bar.projectID
      return ProjectDragPayload.itemProvider(for: bar.projectID)
    }
  }
}

@MainActor
struct UnifiedTimelineBoardScrollView<
  BoardContent: View, PinnedLeft: View, PinnedTop: View
>: NSViewRepresentable {
  let boardSize: CGSize
  let titleColumnWidth: CGFloat
  let headerHeight: CGFloat
  let dayRange: ClosedRange<Int>
  let dayColumnWidth: CGFloat
  let boardContentVersion: Int
  let pinnedLeftVersion: Int
  let pinnedTopVersion: Int
  let scrollRequestGeneration: Int
  let publishOffsetY: Bool
  let publishPreciseHoverOffsets: Bool
  let isDayHeaderHoverEnabled: Bool
  let isTaskBadgeHoverEnabled: Bool
  let taskBadgeHitTargets: [TimelineTaskBadgeHitTarget]
  let scrollHoverSuppressionInterval: TimeInterval

  @Binding var offsetX: CGFloat
  @Binding var offsetY: CGFloat
  @Binding var requestedOffsetX: CGFloat?
  let onScrollActivity: (CGFloat, CGFloat, Bool) -> Void
  let onDayHeaderHover: (Int, Bool) -> Void
  let onDayHeaderHoverCleared: () -> Void
  let onTaskBadgeHover: (String, Bool) -> Void
  let onTaskBadgeHoverCleared: () -> Void

  let boardContent: BoardContent
  let pinnedLeft: PinnedLeft
  let pinnedTop: PinnedTop

  init(
    boardSize: CGSize,
    titleColumnWidth: CGFloat,
    headerHeight: CGFloat,
    dayRange: ClosedRange<Int>,
    dayColumnWidth: CGFloat,
    boardContentVersion: Int,
    pinnedLeftVersion: Int,
    pinnedTopVersion: Int,
    scrollRequestGeneration: Int,
    publishOffsetY: Bool,
    publishPreciseHoverOffsets: Bool,
    isDayHeaderHoverEnabled: Bool,
    isTaskBadgeHoverEnabled: Bool,
    taskBadgeHitTargets: [TimelineTaskBadgeHitTarget],
    scrollHoverSuppressionInterval: TimeInterval,
    offsetX: Binding<CGFloat>,
    offsetY: Binding<CGFloat>,
    requestedOffsetX: Binding<CGFloat?>,
    onScrollActivity: @escaping (CGFloat, CGFloat, Bool) -> Void,
    onDayHeaderHover: @escaping (Int, Bool) -> Void,
    onDayHeaderHoverCleared: @escaping () -> Void,
    onTaskBadgeHover: @escaping (String, Bool) -> Void,
    onTaskBadgeHoverCleared: @escaping () -> Void,
    @ViewBuilder boardContent: () -> BoardContent,
    @ViewBuilder pinnedLeft: () -> PinnedLeft,
    @ViewBuilder pinnedTop: () -> PinnedTop
  ) {
    self.boardSize = boardSize
    self.titleColumnWidth = titleColumnWidth
    self.headerHeight = headerHeight
    self.dayRange = dayRange
    self.dayColumnWidth = dayColumnWidth
    self.boardContentVersion = boardContentVersion
    self.pinnedLeftVersion = pinnedLeftVersion
    self.pinnedTopVersion = pinnedTopVersion
    self.scrollRequestGeneration = scrollRequestGeneration
    self.publishOffsetY = publishOffsetY
    self.publishPreciseHoverOffsets = publishPreciseHoverOffsets
    self.isDayHeaderHoverEnabled = isDayHeaderHoverEnabled
    self.isTaskBadgeHoverEnabled = isTaskBadgeHoverEnabled
    self.taskBadgeHitTargets = taskBadgeHitTargets
    self.scrollHoverSuppressionInterval = scrollHoverSuppressionInterval
    self._offsetX = offsetX
    self._offsetY = offsetY
    self._requestedOffsetX = requestedOffsetX
    self.onScrollActivity = onScrollActivity
    self.onDayHeaderHover = onDayHeaderHover
    self.onDayHeaderHoverCleared = onDayHeaderHoverCleared
    self.onTaskBadgeHover = onTaskBadgeHover
    self.onTaskBadgeHoverCleared = onTaskBadgeHoverCleared
    self.boardContent = boardContent()
    self.pinnedLeft = pinnedLeft()
    self.pinnedTop = pinnedTop()
  }

  @MainActor
  final class Coordinator: NSObject {
    let documentView = FlippedTimelineDocumentView()
    let boardHosting: ScrollPassthroughHostingView<BoardContent>
    let leftHosting: ScrollPassthroughHostingView<PinnedLeft>
    let topHosting: ScrollPassthroughHostingView<PinnedTop>
    var lastBoardContentVersion: Int
    var lastPinnedLeftVersion: Int
    var lastPinnedTopVersion: Int
    var offsetX: Binding<CGFloat>
    var offsetY: Binding<CGFloat>
    var titleColumnWidth: CGFloat
    var headerHeight: CGFloat
    var dayRange: ClosedRange<Int>
    var dayColumnWidth: CGFloat
    var publishOffsetY: Bool
    var publishPreciseHoverOffsets: Bool
    var isDayHeaderHoverEnabled: Bool
    var isTaskBadgeHoverEnabled: Bool
    var taskBadgeHitTargets: [TimelineTaskBadgeHitTarget]
    var scrollHoverSuppressionInterval: TimeInterval
    var lastPublishedDayBucket: Int = .min
    var lastPublishedVerticalBucket: Int = .min
    var lastScrollRequestGeneration: Int
    var hasAppliedRequestedOffset = false
    var didPrimeInitialVerticalOrigin = false
    var lastObservedScrollOrigin: CGPoint?
    var scrollHoverSuppressionDeadline: TimeInterval = 0
    var hoveredDayHeaderOffset: Int?
    var hoveredTaskBadgeID: String?
    var onScrollActivity: (CGFloat, CGFloat, Bool) -> Void
    var onDayHeaderHover: (Int, Bool) -> Void
    var onDayHeaderHoverCleared: () -> Void
    var onTaskBadgeHover: (String, Bool) -> Void
    var onTaskBadgeHoverCleared: () -> Void
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
      dayRange: ClosedRange<Int>,
      dayColumnWidth: CGFloat,
      publishOffsetY: Bool,
      publishPreciseHoverOffsets: Bool,
      isDayHeaderHoverEnabled: Bool,
      isTaskBadgeHoverEnabled: Bool,
      taskBadgeHitTargets: [TimelineTaskBadgeHitTarget],
      scrollHoverSuppressionInterval: TimeInterval,
      scrollRequestGeneration: Int,
      onScrollActivity: @escaping (CGFloat, CGFloat, Bool) -> Void,
      onDayHeaderHover: @escaping (Int, Bool) -> Void,
      onDayHeaderHoverCleared: @escaping () -> Void,
      onTaskBadgeHover: @escaping (String, Bool) -> Void,
      onTaskBadgeHoverCleared: @escaping () -> Void
    ) {
      self.boardHosting = ScrollPassthroughHostingView(rootView: boardContent)
      self.leftHosting = ScrollPassthroughHostingView(rootView: pinnedLeft)
      self.topHosting = ScrollPassthroughHostingView(rootView: pinnedTop)
      self.lastBoardContentVersion = boardContentVersion
      self.lastPinnedLeftVersion = pinnedLeftVersion
      self.lastPinnedTopVersion = pinnedTopVersion
      self.offsetX = offsetX
      self.offsetY = offsetY
      self.titleColumnWidth = titleColumnWidth
      self.headerHeight = headerHeight
      self.dayRange = dayRange
      self.dayColumnWidth = dayColumnWidth
      self.publishOffsetY = publishOffsetY
      self.publishPreciseHoverOffsets = publishPreciseHoverOffsets
      self.isDayHeaderHoverEnabled = isDayHeaderHoverEnabled
      self.isTaskBadgeHoverEnabled = isTaskBadgeHoverEnabled
      self.taskBadgeHitTargets = taskBadgeHitTargets
      self.scrollHoverSuppressionInterval = scrollHoverSuppressionInterval
      self.lastScrollRequestGeneration = scrollRequestGeneration
      self.onScrollActivity = onScrollActivity
      self.onDayHeaderHover = onDayHeaderHover
      self.onDayHeaderHoverCleared = onDayHeaderHoverCleared
      self.onTaskBadgeHover = onTaskBadgeHover
      self.onTaskBadgeHoverCleared = onTaskBadgeHoverCleared
      super.init()
      documentView.addSubview(boardHosting)
    }

    func noteUserScrollActivity() {
      scrollHoverSuppressionDeadline = CACurrentMediaTime() + scrollHoverSuppressionInterval
    }

    func beginUserScrollSessionIfNeeded() {
      guard let scrollView else { return }
      onScrollActivity(
        max(0, scrollView.contentView.bounds.origin.x),
        max(0, scrollView.contentView.bounds.origin.y),
        false
      )
    }

    func shouldSuppressHoverPrecision() -> Bool {
      CACurrentMediaTime() < scrollHoverSuppressionDeadline
    }

    @objc func boundsDidChange(_ notification: Notification) {
      clampVisibleOriginIfNeeded()
      guard let scrollView else { return }
      let x = max(0, scrollView.contentView.bounds.origin.x)
      let y = max(0, scrollView.contentView.bounds.origin.y)
      let origin = CGPoint(x: x, y: y)
      let didScroll = TimelineBoardReadPath.didScrollOriginChange(
        from: lastObservedScrollOrigin,
        to: origin
      )
      lastObservedScrollOrigin = origin
      guard didScroll else { return }
      let usedPreciseHoverOffsets = publishPreciseHoverOffsets && !shouldSuppressHoverPrecision()
      let activityHandler = onScrollActivity
      DispatchQueue.main.async {
        activityHandler(x, y, usedPreciseHoverOffsets)
      }
      let verticalStep: CGFloat = 12
      let bucket = Int(floor(x / max(1, dayColumnWidth)))
      if abs(offsetX.wrappedValue - x) > 0.5 {
        if usedPreciseHoverOffsets {
          let binding = offsetX
          DispatchQueue.main.async {
            if abs(binding.wrappedValue - x) > 0.5 {
              binding.wrappedValue = x
            }
          }
        } else if bucket != lastPublishedDayBucket {
          lastPublishedDayBucket = bucket
          let binding = offsetX
          DispatchQueue.main.async {
            if abs(binding.wrappedValue - x) > 0.5 {
              binding.wrappedValue = x
            }
          }
        }
      }
      if (publishOffsetY || usedPreciseHoverOffsets), abs(offsetY.wrappedValue - y) > 0.5 {
        let verticalBucket = Int(floor(y / verticalStep))
        if usedPreciseHoverOffsets {
          let binding = offsetY
          DispatchQueue.main.async {
            if abs(binding.wrappedValue - y) > 0.5 {
              binding.wrappedValue = y
            }
          }
        } else if verticalBucket != lastPublishedVerticalBucket {
          lastPublishedVerticalBucket = verticalBucket
          let binding = offsetY
          DispatchQueue.main.async {
            if abs(binding.wrappedValue - y) > 0.5 {
              binding.wrappedValue = y
            }
          }
        }
      }
      layoutPinnedOverlays(
        boardSize: documentView.frame.size,
        titleColumnWidth: titleColumnWidth,
        headerHeight: headerHeight
      )
      clearDayHeaderHover()
    }

    @objc func frameDidChange(_ notification: Notification) {
      clampVisibleOriginIfNeeded()
      layoutPinnedOverlays(
        boardSize: documentView.frame.size,
        titleColumnWidth: titleColumnWidth,
        headerHeight: headerHeight
      )
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

    func layoutPinnedOverlays(
      boardSize: CGSize,
      titleColumnWidth: CGFloat,
      headerHeight: CGFloat
    ) {
      guard let scrollView else { return }
      let bounds = scrollView.contentView.bounds
      let timelineWidth = max(0, boardSize.width - titleColumnWidth)

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
        width: timelineWidth,
        height: headerHeight
      )
      if !topHosting.frame.equalTo(topFrame) {
        topHosting.frame = topFrame
      }
    }

    func updateDayHeaderHover(with event: NSEvent, in clipView: FlippedTimelineClipView) {
      updateDayHeaderHover(
        windowLocation: event.locationInWindow,
        in: clipView,
        renotifySameTarget: true,
        notifyCleared: true
      )
    }

    func updateTaskBadgeHover(with event: NSEvent, in clipView: FlippedTimelineClipView) {
      updateTaskBadgeHover(
        windowLocation: event.locationInWindow,
        in: clipView,
        renotifySameTarget: true,
        notifyCleared: true
      )
    }

    func refreshDayHeaderHoverIfNeeded(in clipView: FlippedTimelineClipView) {
      guard let window = clipView.window else {
        clearDayHeaderHover(notifyCleared: false)
        return
      }
      updateDayHeaderHover(
        windowLocation: window.mouseLocationOutsideOfEventStream,
        in: clipView,
        renotifySameTarget: false,
        notifyCleared: false
      )
    }

    func refreshTaskBadgeHoverIfNeeded(in clipView: FlippedTimelineClipView) {
      guard let window = clipView.window else {
        clearTaskBadgeHover(notifyCleared: false)
        return
      }
      updateTaskBadgeHover(
        windowLocation: window.mouseLocationOutsideOfEventStream,
        in: clipView,
        renotifySameTarget: false,
        notifyCleared: false
      )
    }

    func updateDayHeaderHover(
      windowLocation: NSPoint,
      in clipView: FlippedTimelineClipView,
      renotifySameTarget: Bool,
      notifyCleared: Bool
    ) {
      guard isDayHeaderHoverEnabled else {
        clearDayHeaderHover(notifyCleared: notifyCleared)
        return
      }
      let contentLocation = clipView.convert(windowLocation, from: nil)
      guard
        let nextOffset = TimelineBoardReadPath.dayHeaderHoverOffset(
          contentLocation: contentLocation,
          visibleBoundsOrigin: clipView.bounds.origin,
          titleColumnWidth: titleColumnWidth,
          headerHeight: headerHeight,
          dayRange: dayRange,
          dayColumnWidth: dayColumnWidth
        )
      else {
        clearDayHeaderHover(notifyCleared: notifyCleared)
        return
      }

      if hoveredDayHeaderOffset == nextOffset {
        if renotifySameTarget {
          onDayHeaderHover(nextOffset, true)
        }
        return
      }
      if let hoveredDayHeaderOffset {
        onDayHeaderHover(hoveredDayHeaderOffset, false)
      }
      hoveredDayHeaderOffset = nextOffset
      onDayHeaderHover(nextOffset, true)
    }

    func updateTaskBadgeHover(
      windowLocation: NSPoint,
      in clipView: FlippedTimelineClipView,
      renotifySameTarget: Bool,
      notifyCleared: Bool
    ) {
      guard isTaskBadgeHoverEnabled else {
        clearTaskBadgeHover(notifyCleared: notifyCleared)
        return
      }
      let contentLocation = clipView.convert(windowLocation, from: nil)
      let nextBadgeID = TimelineBoardReadPath.taskBadgeHoverID(
        contentLocation: contentLocation,
        visibleBoundsOrigin: clipView.bounds.origin,
        titleColumnWidth: titleColumnWidth,
        headerHeight: headerHeight,
        targets: taskBadgeHitTargets
      )

      guard let nextBadgeID else {
        clearTaskBadgeHover(notifyCleared: notifyCleared)
        return
      }

      if hoveredTaskBadgeID == nextBadgeID {
        if renotifySameTarget {
          onTaskBadgeHover(nextBadgeID, true)
        }
        return
      }
      if let hoveredTaskBadgeID {
        onTaskBadgeHover(hoveredTaskBadgeID, false)
      }
      hoveredTaskBadgeID = nextBadgeID
      onTaskBadgeHover(nextBadgeID, true)
    }

    func clearDayHeaderHover(notifyCleared: Bool = true) {
      if let hoveredDayHeaderOffset {
        self.hoveredDayHeaderOffset = nil
        onDayHeaderHover(hoveredDayHeaderOffset, false)
      }
      if notifyCleared {
        onDayHeaderHoverCleared()
      }
    }

    func clearTaskBadgeHover(notifyCleared: Bool = true) {
      if let hoveredTaskBadgeID {
        self.hoveredTaskBadgeID = nil
        onTaskBadgeHover(hoveredTaskBadgeID, false)
      }
      if notifyCleared {
        onTaskBadgeHoverCleared()
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
      dayRange: dayRange,
      dayColumnWidth: dayColumnWidth,
      publishOffsetY: publishOffsetY,
      publishPreciseHoverOffsets: publishPreciseHoverOffsets,
      isDayHeaderHoverEnabled: isDayHeaderHoverEnabled,
      isTaskBadgeHoverEnabled: isTaskBadgeHoverEnabled,
      taskBadgeHitTargets: taskBadgeHitTargets,
      scrollHoverSuppressionInterval: scrollHoverSuppressionInterval,
      scrollRequestGeneration: scrollRequestGeneration,
      onScrollActivity: onScrollActivity,
      onDayHeaderHover: onDayHeaderHover,
      onDayHeaderHoverCleared: onDayHeaderHoverCleared,
      onTaskBadgeHover: onTaskBadgeHover,
      onTaskBadgeHoverCleared: onTaskBadgeHoverCleared
    )
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = TimelineInteractionScrollView()
    let clipView = FlippedTimelineClipView()
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
    context.coordinator.lastObservedScrollOrigin = scrollView.contentView.bounds.origin
    scrollView.noteUserScrollActivity = { [weak coordinator = context.coordinator] in
      coordinator?.noteUserScrollActivity()
    }
    scrollView.beginUserScrollSession = { [weak coordinator = context.coordinator] in
      coordinator?.beginUserScrollSessionIfNeeded()
    }
    clipView.onMouseMovedInVisibleRect = { [weak coordinator = context.coordinator] event, clipView in
      coordinator?.updateDayHeaderHover(with: event, in: clipView)
      coordinator?.updateTaskBadgeHover(with: event, in: clipView)
    }
    clipView.onMouseExitedVisibleRect = { [weak coordinator = context.coordinator] in
      coordinator?.clearDayHeaderHover()
      coordinator?.clearTaskBadgeHover()
    }

    context.coordinator.leftHosting.wantsLayer = true
    context.coordinator.topHosting.wantsLayer = true

    scrollView.contentView.wantsLayer = true
    scrollView.contentView.layer?.masksToBounds = true
    scrollView.contentView.addSubview(context.coordinator.topHosting)
    scrollView.contentView.addSubview(context.coordinator.leftHosting)

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
    coordinator.dayRange = dayRange
    coordinator.dayColumnWidth = dayColumnWidth
    coordinator.publishOffsetY = publishOffsetY
    coordinator.publishPreciseHoverOffsets = publishPreciseHoverOffsets
    coordinator.isDayHeaderHoverEnabled = isDayHeaderHoverEnabled
    coordinator.isTaskBadgeHoverEnabled = isTaskBadgeHoverEnabled
    coordinator.taskBadgeHitTargets = taskBadgeHitTargets
    coordinator.scrollHoverSuppressionInterval = scrollHoverSuppressionInterval
    coordinator.onScrollActivity = onScrollActivity
    coordinator.onDayHeaderHover = onDayHeaderHover
    coordinator.onDayHeaderHoverCleared = onDayHeaderHoverCleared
    coordinator.onTaskBadgeHover = onTaskBadgeHover
    coordinator.onTaskBadgeHoverCleared = onTaskBadgeHoverCleared
    if let interactiveScrollView = scrollView as? TimelineInteractionScrollView {
      interactiveScrollView.noteUserScrollActivity = { [weak coordinator] in
        coordinator?.noteUserScrollActivity()
      }
      interactiveScrollView.beginUserScrollSession = { [weak coordinator] in
        coordinator?.beginUserScrollSessionIfNeeded()
      }
    }
    if let clipView = scrollView.contentView as? FlippedTimelineClipView {
      clipView.onMouseMovedInVisibleRect = { [weak coordinator] event, clipView in
        coordinator?.updateDayHeaderHover(with: event, in: clipView)
        coordinator?.updateTaskBadgeHover(with: event, in: clipView)
      }
      clipView.onMouseExitedVisibleRect = { [weak coordinator] in
        coordinator?.clearDayHeaderHover()
        coordinator?.clearTaskBadgeHover()
      }
    }
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

    if !coordinator.didPrimeInitialVerticalOrigin {
      let current = scrollView.contentView.bounds.origin
      let clampedX = min(max(0, current.x), maxX)
      let clampedY = min(max(0, current.y), maxY)
      if abs(current.x - clampedX) > 0.5 || abs(current.y - clampedY) > 0.5 {
        scrollView.contentView.scroll(to: CGPoint(x: clampedX, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
      coordinator.didPrimeInitialVerticalOrigin = true
    }

    let requestedOffsetBinding = _requestedOffsetX
    if let requestedOffsetX, !coordinator.hasAppliedRequestedOffset {
      let targetX = min(max(0, requestedOffsetX), maxX)
      let current = scrollView.contentView.bounds.origin
      let clampedY = min(max(0, current.y), maxY)
      if abs(current.x - targetX) > 0.5 || abs(current.y - clampedY) > 0.5 {
        scrollView.contentView.scroll(to: CGPoint(x: targetX, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
      coordinator.hasAppliedRequestedOffset = true
      DispatchQueue.main.async {
        if requestedOffsetBinding.wrappedValue != nil {
          requestedOffsetBinding.wrappedValue = nil
        }
      }
    } else {
      if requestedOffsetX != nil {
        DispatchQueue.main.async {
          if requestedOffsetBinding.wrappedValue != nil {
            requestedOffsetBinding.wrappedValue = nil
          }
        }
      }
      let current = scrollView.contentView.bounds.origin
      let clampedX = min(max(0, current.x), maxX)
      let clampedY = min(max(0, current.y), maxY)
      if abs(current.x - clampedX) > 0.5 || abs(current.y - clampedY) > 0.5 {
        scrollView.contentView.scroll(to: CGPoint(x: clampedX, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }
    coordinator.clampVisibleOriginIfNeeded()

    coordinator.layoutPinnedOverlays(
      boardSize: boardSize,
      titleColumnWidth: titleColumnWidth,
      headerHeight: headerHeight
    )
    if scrollView.contentView is FlippedTimelineClipView {
      if !isDayHeaderHoverEnabled {
        coordinator.clearDayHeaderHover(notifyCleared: false)
      }
      if !isTaskBadgeHoverEnabled {
        coordinator.clearTaskBadgeHover(notifyCleared: false)
      }
    }

    let liveX = max(0, scrollView.contentView.bounds.origin.x)
    let usesPreciseHoverOffsets = publishPreciseHoverOffsets && !coordinator.shouldSuppressHoverPrecision()
    if abs(offsetX - liveX) > 0.5 {
      if usesPreciseHoverOffsets {
        let offsetBinding = _offsetX
        DispatchQueue.main.async {
          if abs(offsetBinding.wrappedValue - liveX) > 0.5 {
            offsetBinding.wrappedValue = liveX
          }
        }
      } else {
        let bucket = Int(floor(liveX / max(1, dayColumnWidth)))
        if bucket != coordinator.lastPublishedDayBucket {
          coordinator.lastPublishedDayBucket = bucket
          let offsetBinding = _offsetX
          DispatchQueue.main.async {
            if abs(offsetBinding.wrappedValue - liveX) > 0.5 {
              offsetBinding.wrappedValue = liveX
            }
          }
        }
      }
    }

    if publishOffsetY || usesPreciseHoverOffsets {
      let liveY = max(0, scrollView.contentView.bounds.origin.y)
      if abs(offsetY - liveY) > 0.5 {
        if usesPreciseHoverOffsets {
          let offsetBinding = _offsetY
          DispatchQueue.main.async {
            if abs(offsetBinding.wrappedValue - liveY) > 0.5 {
              offsetBinding.wrappedValue = liveY
            }
          }
        } else {
          let verticalStep: CGFloat = 12
          let verticalBucket = Int(floor(liveY / verticalStep))
          if verticalBucket != coordinator.lastPublishedVerticalBucket {
            coordinator.lastPublishedVerticalBucket = verticalBucket
            let offsetBinding = _offsetY
            DispatchQueue.main.async {
              if abs(offsetBinding.wrappedValue - liveY) > 0.5 {
                offsetBinding.wrappedValue = liveY
              }
            }
          }
        }
      }
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
