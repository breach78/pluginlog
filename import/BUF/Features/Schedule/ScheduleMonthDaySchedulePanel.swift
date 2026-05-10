import AppKit
import SwiftUI

struct ScheduleMonthDaySchedulePanel: View {
  let target: ScheduleMonthDetailPanelTarget
  let calendar: Calendar
  let quickAddProjects: [ScheduleQuickAddProjectOption]
  let defaultQuickAddProjectID: UUID?
  let onOpenItem: (ScheduleMonthItem) -> Void
  let onToggleTaskCompletion: (ScheduleMonthItem, Bool) async -> ScheduleMonthItem?
  let onUpdateItemSchedule: (ScheduleMonthItem, Date, Int?, Int?) async -> ScheduleMonthItem?
  let onCreateTask: (String, UUID, Date, Int?, Int?) async -> ScheduleMonthItem?
  let onDeleteItem: (ScheduleMonthItem, ScheduleCalendarRecurringEditScope?) async -> Bool
  let resolveExternalMonthDropDay: (CGPoint) -> Date?
  let onExternalMonthDragTargetChanged: (Date?) -> Void
  let onDropTargetChanged: (ScheduleMonthDropTarget?) -> Void

  @State private var items: [ScheduleMonthItem]
  @State private var activeMutationPreview: ScheduleMonthDayScheduleMutationPreview?
  @State private var activeCreatePreview: ScheduleMonthDayScheduleCreatePreview?
  @State private var pendingCreatePreview: ScheduleMonthDayScheduleCreatePreview?
  @State private var savingItemIDs: Set<String> = []
  @State private var timeScrollResetID = UUID()
  @State private var timeContentMinYInPanel: CGFloat = 0
  @State private var activeItemDragState: ScheduleMonthDayItemDragState?
  @State private var activeItemResizeState: ScheduleMonthDayItemResizeState?
  @State private var resizeBlockedMoveItemID: String?
  @State private var panelFrameInScreen: CGRect = .null
  @State private var timeContentFrameInScreen: CGRect = .null

  init(
    target: ScheduleMonthDetailPanelTarget,
    calendar: Calendar,
    quickAddProjects: [ScheduleQuickAddProjectOption],
    defaultQuickAddProjectID: UUID?,
    onOpenItem: @escaping (ScheduleMonthItem) -> Void,
    onToggleTaskCompletion: @escaping (ScheduleMonthItem, Bool) async -> ScheduleMonthItem?,
    onUpdateItemSchedule: @escaping (ScheduleMonthItem, Date, Int?, Int?) async -> ScheduleMonthItem?,
    onCreateTask: @escaping (String, UUID, Date, Int?, Int?) async -> ScheduleMonthItem?,
    onDeleteItem: @escaping (ScheduleMonthItem, ScheduleCalendarRecurringEditScope?) async -> Bool,
    resolveExternalMonthDropDay: @escaping (CGPoint) -> Date?,
    onExternalMonthDragTargetChanged: @escaping (Date?) -> Void,
    onDropTargetChanged: @escaping (ScheduleMonthDropTarget?) -> Void = { _ in }
  ) {
    self.target = target
    self.calendar = calendar
    self.quickAddProjects = quickAddProjects
    self.defaultQuickAddProjectID = defaultQuickAddProjectID
    self.onOpenItem = onOpenItem
    self.onToggleTaskCompletion = onToggleTaskCompletion
    self.onUpdateItemSchedule = onUpdateItemSchedule
    self.onCreateTask = onCreateTask
    self.onDeleteItem = onDeleteItem
    self.resolveExternalMonthDropDay = resolveExternalMonthDropDay
    self.onExternalMonthDragTargetChanged = onExternalMonthDragTargetChanged
    self.onDropTargetChanged = onDropTargetChanged
    _items = State(initialValue: Self.sortedItems(target.items, calendar: calendar))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      allDaySection

      Divider()

      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            Color.clear
              .frame(height: 1)
              .id(Self.topScrollID)

            timedSchedule

            Color.clear
              .frame(height: 1)
              .id(Self.bottomScrollID)
          }
        }
        .scrollIndicators(.visible)
        .id(timeScrollResetID)
        .onAppear {
          scrollTimeGridToInitialPosition(proxy)
        }
        .onChange(of: timeScrollResetID) { _, _ in
          scrollTimeGridToInitialPosition(proxy)
        }
      }
      .background(Color(nsColor: .textBackgroundColor))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color(nsColor: .textBackgroundColor))
    .coordinateSpace(name: Self.panelCoordinateSpaceName)
    .transaction { transaction in
      if activeMutationPreview != nil || activeCreatePreview != nil {
        transaction.animation = nil
      }
    }
    .background(panelFrameReporter)
    .onChange(of: target.items) { _, newItems in
      items = Self.sortedItems(newItems, calendar: calendar)
    }
    .onChange(of: target.date) { _, _ in
      items = Self.sortedItems(target.items, calendar: calendar)
      activeMutationPreview = nil
      activeCreatePreview = nil
      pendingCreatePreview = nil
      activeItemDragState = nil
      activeItemResizeState = nil
      resizeBlockedMoveItemID = nil
      savingItemIDs = []
      onExternalMonthDragTargetChanged(nil)
      reportDropTarget(frame: panelFrameInScreen)
      timeScrollResetID = UUID()
    }
    .onDisappear {
      onExternalMonthDragTargetChanged(nil)
      onDropTargetChanged(nil)
    }
  }

  private func scrollTimeGridToInitialPosition(_ proxy: ScrollViewProxy) {
    let delays: [TimeInterval] = [0, 0.05, 0.18]
    for delay in delays {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        proxy.scrollTo(Self.nightScrollID, anchor: .top)
      }
    }
  }

  private var panelFrameReporter: some View {
    ScheduleScreenFrameReporter { frame in
      panelFrameInScreen = frame
      reportDropTarget(frame: frame)
      updateTimeContentOffset(timeFrame: timeContentFrameInScreen, panelFrame: frame)
    }
  }

  private func reportDropTarget(frame: CGRect) {
    if frame.isNull {
      onDropTargetChanged(nil)
    } else {
      onDropTargetChanged(
        ScheduleMonthDropTarget(
          day: calendar.startOfDay(for: target.date),
          frame: frame
        )
      )
    }
  }

  private var allDaySection: some View {
    ZStack(alignment: .topLeading) {
      ScheduleQuickAddContextMenuRegion(
        isAllDayRegion: true,
        canCreateTask: !quickAddProjects.isEmpty,
        projects: quickAddProjects,
        defaultProjectID: defaultQuickAddProjectID,
        onCreateTask: { title, projectID, _, _ in
          createTask(title: title, projectID: projectID, timeMinutes: nil, durationMinutes: nil)
        },
        onUnavailable: {},
        onBackgroundTap: nil,
        allowsTimedDragCreation: false,
        onTimedDragPreview: nil,
        onTimedDragCommit: nil,
        onTimedDragCancel: nil
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      VStack(alignment: .leading, spacing: 7) {
        ForEach(allDayItems) { item in
          ScheduleMonthDayAllDayItemRow(
            item: item,
            isSaving: savingItemIDs.contains(item.id),
            canDrag: canUpdateSchedule(for: item),
            isInteracting: activeItemDragState?.itemID == item.id,
            coordinateSpaceName: Self.panelCoordinateSpaceName,
            onOpen: {
              onOpenItem(item)
            },
            onToggleCompletion: {
              toggleCompletion(for: item)
            },
            onDeleteItem: { scope in
              deleteItem(item, scope: scope)
            },
            onMoveChanged: { value in
              updateMovePreview(for: item, drag: value, originalTopScheduleY: nil, originalX: nil, originalWidth: nil)
            },
            onMoveEnded: { value in
              finishMovePreview(for: item, drag: value, originalTopScheduleY: nil, originalX: nil, originalWidth: nil)
            }
          )
        }
        if activeDragPreviewIsAllDay, let activeItemDragState {
          ScheduleMonthDayDragPreviewRow(
            item: activeItemDragState.originalItem,
            color: itemColor(activeItemDragState.originalItem)
          )
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
    }
    .frame(height: allDaySectionHeight, alignment: .topLeading)
  }

  private var allDaySectionHeight: CGFloat {
    max(22, CGFloat(allDayRowCount) * Self.allDayRowHeight + 20)
  }

  private var allDayRowCount: Int {
    allDayItems.count + (activeDragPreviewIsAllDay ? 1 : 0)
  }

  private var timedSchedule: some View {
    GeometryReader { proxy in
      let gridWidth = max(0, proxy.size.width - Self.timeGutterWidth)

      HStack(alignment: .top, spacing: 0) {
        timeAxis
          .frame(width: Self.timeGutterWidth, height: Self.timeGridHeight, alignment: .topTrailing)

        ZStack(alignment: .topLeading) {
          timeScrollAnchorLayer

          timedGridLines

          ScheduleQuickAddContextMenuRegion(
            isAllDayRegion: false,
            canCreateTask: !quickAddProjects.isEmpty,
            projects: quickAddProjects,
            defaultProjectID: defaultQuickAddProjectID,
            onCreateTask: { title, projectID, location, _ in
              let timeMinutes = snappedTimeMinutes(forY: location.y)
              createTask(
                title: title,
                projectID: projectID,
                timeMinutes: timeMinutes,
                durationMinutes: Self.minimumDurationMinutes
              )
            },
            onUnavailable: {},
            onBackgroundTap: {
              pendingCreatePreview = nil
              activeCreatePreview = nil
            },
            allowsTimedDragCreation: true,
            onTimedDragPreview: { start, end in
              activeCreatePreview = createPreview(from: start, to: end)
            },
            onTimedDragCommit: { start, end in
              pendingCreatePreview = createPreview(from: start, to: end)
              activeCreatePreview = nil
            },
            onTimedDragCancel: {
              activeCreatePreview = nil
            }
          )
          .frame(width: gridWidth, height: Self.timeGridHeight)

          ForEach(timedLayouts(for: gridWidth)) { layout in
            ScheduleMonthDayTimedItemBlock(
              layout: layout,
              color: itemColor(layout.item),
              isSaving: savingItemIDs.contains(layout.item.id),
              canDrag: canUpdateSchedule(for: layout.item),
              canResize: canResizeSchedule(for: layout.item),
              isInteracting: activeMutationPreview?.itemID == layout.item.id,
              coordinateSpaceName: Self.panelCoordinateSpaceName,
              onOpen: {
                onOpenItem(layout.item)
              },
              onToggleCompletion: {
                toggleCompletion(for: layout.item)
              },
              onDeleteItem: { scope in
                deleteItem(layout.item, scope: scope)
              },
              onMoveChanged: { value in
                updateMovePreview(for: layout.item, drag: value, originalTopScheduleY: layout.y, originalX: layout.x, originalWidth: layout.width)
              },
              onMoveEnded: { value in
                finishMovePreview(for: layout.item, drag: value, originalTopScheduleY: layout.y, originalX: layout.x, originalWidth: layout.width)
              },
              onResizeChanged: { edge, value in
                updateResizePreview(for: layout, edge: edge, drag: value)
              },
              onResizeEnded: { edge, value in
                finishResizePreview(for: layout, edge: edge, drag: value)
              }
            )
            .frame(width: layout.width, height: layout.height)
            .offset(x: layout.x, y: layout.y)
            .zIndex(activeMutationPreview?.itemID == layout.item.id ? 5 : 2)
          }

          ScheduleMonthDayCurrentTimeIndicator(
            day: target.date,
            width: gridWidth,
            height: Self.timeGridHeight,
            hourHeight: Self.hourHeight,
            calendar: calendar
          )
          .zIndex(6)

          if let activeCreatePreview {
            createPreviewBlock(activeCreatePreview, width: gridWidth)
          }

          if let activeMutationPreview,
            let activeItemDragState,
            let timeMinutes = activeMutationPreview.timeMinutes
          {
            ScheduleMonthDayTimedDragPreviewBlock(
              item: activeItemDragState.originalItem,
              color: itemColor(activeItemDragState.originalItem)
            )
            .frame(
              width: activeItemDragState.originalWidth ?? max(40, gridWidth - 12),
              height: height(forDuration: activeMutationPreview.durationMinutes ?? durationMinutes(
                for: activeItemDragState.originalItem
              )),
              alignment: .topLeading
            )
            .offset(x: activeItemDragState.originalX ?? 6, y: y(forMinute: timeMinutes))
            .zIndex(10)
          }

          if let activeMutationPreview,
            let activeItemResizeState,
            let timeMinutes = activeMutationPreview.timeMinutes
          {
            ScheduleMonthDayTimedDragPreviewBlock(
              item: activeItemResizeState.originalItem,
              color: itemColor(activeItemResizeState.originalItem)
            )
            .frame(
              width: activeItemResizeState.originalWidth,
              height: height(forDuration: activeMutationPreview.durationMinutes ?? durationMinutes(
                for: activeItemResizeState.originalItem
              )),
              alignment: .topLeading
            )
            .offset(x: activeItemResizeState.originalX, y: y(forMinute: timeMinutes))
            .zIndex(11)
          }

          if let pendingCreatePreview {
            pendingCreateCard(pendingCreatePreview, width: gridWidth)
          }
        }
        .frame(width: gridWidth, height: Self.timeGridHeight, alignment: .topLeading)
        .background(timeContentFrameReporter)
      }
    }
    .frame(height: Self.timeGridHeight)
  }

  private var timeContentFrameReporter: some View {
    ScheduleScreenFrameReporter { frame in
      timeContentFrameInScreen = frame
      updateTimeContentOffset(timeFrame: frame, panelFrame: panelFrameInScreen)
    }
  }

  private func updateTimeContentOffset(timeFrame: CGRect, panelFrame: CGRect) {
    guard !timeFrame.isNull, !panelFrame.isNull else { return }
    timeContentMinYInPanel = panelFrame.maxY - timeFrame.maxY
  }

  private var timeScrollAnchorLayer: some View {
    VStack(spacing: 0) {
      Color.clear
        .frame(height: CGFloat(Self.initialVisibleHour) * Self.hourHeight)
      Color.clear
        .frame(height: 1)
        .id(Self.nightScrollID)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .allowsHitTesting(false)
  }

  private var timeAxis: some View {
    ZStack(alignment: .topTrailing) {
      ForEach(0...24, id: \.self) { hour in
        Text(hour == 24 ? "" : Self.timeLabel(hour: hour))
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .frame(width: Self.timeGutterWidth - 10, alignment: .trailing)
          .offset(y: hour == 0 ? 2 : CGFloat(hour) * Self.hourHeight - 7)
      }
    }
    .padding(.trailing, 7)
  }

  private var timedGridLines: some View {
    ZStack(alignment: .topLeading) {
      ForEach(0...24, id: \.self) { hour in
        Rectangle()
          .fill(Color(nsColor: .separatorColor).opacity(hour % 6 == 0 ? 0.45 : 0.25))
          .frame(height: 1)
          .offset(y: CGFloat(hour) * Self.hourHeight)
      }
    }
  }

  private var allDayItems: [ScheduleMonthItem] {
    displayedItems
      .filter(\.isAllDay)
      .sorted { lhs, rhs in
        itemSortKey(lhs, calendar: calendar) < itemSortKey(rhs, calendar: calendar)
      }
  }

  private var timedItems: [ScheduleMonthItem] {
    displayedItems
      .filter { !$0.isAllDay }
      .sorted { lhs, rhs in
        itemSortKey(lhs, calendar: calendar) < itemSortKey(rhs, calendar: calendar)
      }
  }

  private var displayedItems: [ScheduleMonthItem] {
    items
  }

  private var activeDragPreviewIsAllDay: Bool {
    guard activeItemDragState != nil, let activeMutationPreview else { return false }
    return activeMutationPreview.timeMinutes == nil
  }

  private func timedLayouts(for width: CGFloat) -> [ScheduleMonthDayTimedItemLayout] {
    let intervals = timedItems.map {
      ScheduleMonthDayTimedInterval(
        item: $0,
        startMinute: startMinute(for: $0),
        durationMinutes: durationMinutes(for: $0)
      )
    }
    return ScheduleMonthDayTimedLayoutBuilder.layouts(
      intervals: intervals,
      width: width,
      hourHeight: Self.hourHeight
    )
  }

  private func createPreviewBlock(
    _ preview: ScheduleMonthDayScheduleCreatePreview,
    width: CGFloat
  ) -> some View {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
      .fill(Color.accentColor.opacity(0.18))
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      )
      .frame(width: max(40, width - 12), height: height(forDuration: preview.durationMinutes))
      .offset(x: 6, y: y(forMinute: preview.timeMinutes))
      .allowsHitTesting(false)
  }

  private func pendingCreateCard(
    _ preview: ScheduleMonthDayScheduleCreatePreview,
    width: CGFloat
  ) -> some View {
    ScheduleQuickAddPopoverContent(
      projects: quickAddProjects,
      defaultProjectID: defaultQuickAddProjectID,
      onSubmit: { title, projectID in
        createTask(
          title: title,
          projectID: projectID,
          timeMinutes: preview.timeMinutes,
          durationMinutes: preview.durationMinutes
        )
      },
      onCancel: {
        pendingCreatePreview = nil
      }
    )
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    )
    .position(
      x: min(max(140, width * 0.5), max(140, width - 140)),
      y: min(Self.timeGridHeight - 86, max(86, y(forMinute: preview.timeMinutes) + 76))
    )
    .zIndex(20)
  }

  private func toggleCompletion(for item: ScheduleMonthItem) {
    guard case .workspaceTask = item.source else { return }
    guard !savingItemIDs.contains(item.id) else { return }
    let next = !item.isCompleted
    let optimistic = item.replacing(isCompleted: next)
    replaceItem(optimistic)
    savingItemIDs.insert(item.id)
    Task { @MainActor in
      defer { savingItemIDs.remove(item.id) }
      guard let saved = await onToggleTaskCompletion(item, next) else {
        replaceItem(item)
        return
      }
      replaceItem(saved)
    }
  }

  private func deleteItem(
    _ item: ScheduleMonthItem,
    scope: ScheduleCalendarRecurringEditScope?
  ) {
    guard !savingItemIDs.contains(item.id) else { return }
    let previousItems = items
    removeItem(item.id)
    savingItemIDs.insert(item.id)
    Task { @MainActor in
      defer { savingItemIDs.remove(item.id) }
      guard await onDeleteItem(item, scope) else {
        items = previousItems
        return
      }
    }
  }

  private func commitMutationPreview(
    _ preview: ScheduleMonthDayScheduleMutationPreview,
    item: ScheduleMonthItem
  ) {
    activeMutationPreview = nil
    activeItemDragState = nil
    activeItemResizeState = nil
    guard canUpdateSchedule(for: item) else { return }
    guard !savingItemIDs.contains(item.id) else { return }
    let updated = item.applyingSchedulePreview(preview, calendar: calendar)
    guard updated.startDate != item.startDate
      || updated.endDate != item.endDate
      || updated.isAllDay != item.isAllDay
    else {
      return
    }

    replaceOrRemoveForCurrentDay(updated)
    savingItemIDs.insert(item.id)
    Task { @MainActor in
      defer { savingItemIDs.remove(item.id) }
      guard
        let saved = await onUpdateItemSchedule(
          item,
          preview.day,
          preview.timeMinutes,
          preview.durationMinutes
        )
      else {
        replaceOrRemoveForCurrentDay(item)
        return
      }
      replaceOrRemoveForCurrentDay(saved)
    }
  }

  private func updateMovePreview(
    for item: ScheduleMonthItem,
    drag: DragGesture.Value,
    originalTopScheduleY: CGFloat?,
    originalX: CGFloat?,
    originalWidth: CGFloat?
  ) {
    guard canUpdateSchedule(for: item) else { return }
    guard resizeBlockedMoveItemID != item.id, activeItemResizeState == nil else { return }
    let state = updatedDragState(
      for: item,
      drag: drag,
      originalTopScheduleY: originalTopScheduleY,
      originalX: originalX,
      originalWidth: originalWidth
    )
    let externalDrop = externalMonthDropContext(for: drag)
    if externalDrop.isExternal {
      activeMutationPreview = nil
      onExternalMonthDragTargetChanged(externalDrop.day)
      updateMoveCursor(isExternalDrop: true, externalDropDay: externalDrop.day)
      return
    }
    onExternalMonthDragTargetChanged(nil)
    updateMoveCursor(isExternalDrop: false, externalDropDay: nil)
    activeMutationPreview = movePreview(for: state)
  }

  private func finishMovePreview(
    for item: ScheduleMonthItem,
    drag: DragGesture.Value,
    originalTopScheduleY: CGFloat?,
    originalX: CGFloat?,
    originalWidth: CGFloat?
  ) {
    guard canUpdateSchedule(for: item) else { return }
    guard resizeBlockedMoveItemID != item.id, activeItemResizeState == nil else {
      if resizeBlockedMoveItemID == item.id {
        resizeBlockedMoveItemID = nil
      }
      return
    }
    let state = updatedDragState(
      for: item,
      drag: drag,
      originalTopScheduleY: originalTopScheduleY,
      originalX: originalX,
      originalWidth: originalWidth
    )
    defer { NSCursor.arrow.set() }
    let externalDrop = externalMonthDropContext(for: drag)
    if externalDrop.isExternal {
      defer { onExternalMonthDragTargetChanged(nil) }
      guard let targetDay = externalDrop.day else {
        activeMutationPreview = nil
        activeItemDragState = nil
        return
      }
      let preview = externalMonthDropPreview(for: state, targetDay: targetDay)
      commitMutationPreview(preview, item: state.originalItem)
      return
    }
    onExternalMonthDragTargetChanged(nil)
    let preview = movePreview(for: state)
    commitMutationPreview(preview, item: state.originalItem)
  }

  private func updateResizePreview(
    for layout: ScheduleMonthDayTimedItemLayout,
    edge: ScheduleResizeEdge,
    drag: DragGesture.Value
  ) {
    let item = layout.item
    guard canResizeSchedule(for: item) else { return }
    let state = resizeState(for: layout, edge: edge, drag: drag)
    activeMutationPreview = resizePreview(for: state, currentPointerPanelY: drag.location.y)
  }

  private func finishResizePreview(
    for layout: ScheduleMonthDayTimedItemLayout,
    edge: ScheduleResizeEdge,
    drag: DragGesture.Value
  ) {
    let item = layout.item
    guard canResizeSchedule(for: item) else { return }
    let state = resizeState(for: layout, edge: edge, drag: drag)
    let preview = resizePreview(for: state, currentPointerPanelY: drag.location.y)
    let blockedItemID = state.itemID
    commitMutationPreview(preview, item: state.originalItem)
    DispatchQueue.main.async {
      if resizeBlockedMoveItemID == blockedItemID {
        resizeBlockedMoveItemID = nil
      }
    }
  }

  private func updatedDragState(
    for item: ScheduleMonthItem,
    drag: DragGesture.Value,
    originalTopScheduleY: CGFloat?,
    originalX: CGFloat?,
    originalWidth: CGFloat?
  ) -> ScheduleMonthDayItemDragState {
    let state: ScheduleMonthDayItemDragState
    if let activeItemDragState, activeItemDragState.itemID == item.id {
      state = activeItemDragState
    } else {
      let originalPointerScheduleY = drag.startLocation.y - timeContentMinYInPanel
      state = ScheduleMonthDayItemDragState(
        itemID: item.id,
        originalItem: item,
        originalTimeMinutes: item.isAllDay ? nil : startMinute(for: item),
        originalDurationMinutes: item.isAllDay ? nil : durationMinutes(for: item),
        originalPointerScheduleY: originalPointerScheduleY,
        originalTopScheduleY: originalTopScheduleY ?? (originalPointerScheduleY - Self.allDayRowHeight / 2),
        originalX: originalX,
        originalWidth: originalWidth,
        allDayBoundaryYInPanel: allDaySectionHeight + Self.dividerHeight,
        timeContentMinYInPanel: timeContentMinYInPanel,
        isInAllDayZone: item.isAllDay
      )
      activeItemResizeState = nil
    }
    let next = ScheduleMonthDayInteractionAdapter.updatedDragState(
      state,
      drag: DragGestureProxy(
        locationY: drag.location.y,
        translation: drag.translation
      ),
      allDayRowHeight: Self.allDayRowHeight,
      timeContentMinYInPanel: timeContentMinYInPanel
    )
    activeItemDragState = next
    return next
  }

  private func resizeState(
    for layout: ScheduleMonthDayTimedItemLayout,
    edge: ScheduleResizeEdge,
    drag: DragGesture.Value
  ) -> ScheduleMonthDayItemResizeState {
    let item = layout.item
    if let activeItemResizeState,
      activeItemResizeState.itemID == item.id,
      activeItemResizeState.edge == edge
    {
      return activeItemResizeState
    }

    let state = ScheduleMonthDayItemResizeState(
      itemID: item.id,
      originalItem: item,
      originalTimeMinutes: startMinute(for: item),
      originalDurationMinutes: durationMinutes(for: item),
      originalPointerScheduleY: drag.startLocation.y - timeContentMinYInPanel,
      originalEdgeScheduleY: edge == .start ? layout.y : layout.y + layout.height,
      originalX: layout.x,
      originalWidth: layout.width,
      timeContentMinYInPanel: timeContentMinYInPanel,
      edge: edge
    )
    activeItemResizeState = state
    activeItemDragState = nil
    resizeBlockedMoveItemID = item.id
    return state
  }

  private func createTask(
    title: String,
    projectID: UUID,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) {
    pendingCreatePreview = nil
    activeCreatePreview = nil
    Task { @MainActor in
      guard
        let created = await onCreateTask(
          title,
          projectID,
          calendar.startOfDay(for: target.date),
          timeMinutes,
          durationMinutes
        )
      else { return }
      replaceItem(created)
    }
  }

  private func replaceItem(_ item: ScheduleMonthItem) {
    if let index = items.firstIndex(where: { $0.id == item.id }) {
      items[index] = item
    } else {
      items.append(item)
    }
    items = Self.sortedItems(items, calendar: calendar)
  }

  private func replaceOrRemoveForCurrentDay(_ item: ScheduleMonthItem) {
    if itemBelongsToCurrentDay(item) {
      replaceItem(item)
    } else {
      removeItem(item.id)
    }
  }

  private func removeItem(_ itemID: String) {
    items.removeAll { $0.id == itemID }
  }

  private func itemBelongsToCurrentDay(_ item: ScheduleMonthItem) -> Bool {
    let day = calendar.startOfDay(for: target.date)
    if item.isAllDay {
      let start = calendar.startOfDay(for: item.startDate)
      let end = calendar.startOfDay(for: item.endDate)
      return start <= day && day < end
    }
    return calendar.isDate(item.startDate, inSameDayAs: day)
  }

  private func movePreview(
    for state: ScheduleMonthDayItemDragState
  ) -> ScheduleMonthDayScheduleMutationPreview {
    ScheduleMonthDayInteractionAdapter.movePreview(
      for: state,
      targetDay: calendar.startOfDay(for: target.date),
      calendar: calendar,
      metrics: interactionMetrics
    )
  }

  private func externalMonthDropPreview(
    for state: ScheduleMonthDayItemDragState,
    targetDay: Date
  ) -> ScheduleMonthDayScheduleMutationPreview {
    ScheduleMonthDayScheduleMutationPreview(
      itemID: state.itemID,
      day: calendar.startOfDay(for: targetDay),
      timeMinutes: state.originalTimeMinutes,
      durationMinutes: state.originalDurationMinutes
    )
  }

  private func externalMonthDropContext(for drag: DragGesture.Value) -> (
    isExternal: Bool,
    day: Date?
  ) {
    let screenPoint = NSEvent.mouseLocation
    let targetDay = externalMonthDropDay(at: screenPoint)
    let leftPanel = ScheduleMonthDayInteractionAdapter.isExternalMonthDropLocation(
      locationXInPanel: panelX(forScreenX: screenPoint.x),
      translation: drag.translation
    )
    return (targetDay != nil || leftPanel, targetDay)
  }

  private func externalMonthDropDay(at screenPoint: CGPoint) -> Date? {
    guard !panelFrameInScreen.isNull else { return nil }
    return resolveExternalMonthDropDay(screenPoint)
  }

  private func panelX(forScreenX x: CGFloat) -> CGFloat {
    guard !panelFrameInScreen.isNull else { return x }
    return x - panelFrameInScreen.minX
  }

  private func updateMoveCursor(isExternalDrop: Bool, externalDropDay day: Date?) {
    if day != nil {
      NSCursor.dragCopy.set()
    } else if isExternalDrop {
      NSCursor.operationNotAllowed.set()
    } else if activeItemDragState != nil {
      NSCursor.closedHand.set()
    }
  }

  private func resizePreview(
    for state: ScheduleMonthDayItemResizeState,
    currentPointerPanelY: CGFloat
  ) -> ScheduleMonthDayScheduleMutationPreview {
    ScheduleMonthDayInteractionAdapter.resizePreview(
      for: state,
      currentPointerPanelY: currentPointerPanelY,
      targetDay: calendar.startOfDay(for: target.date),
      metrics: interactionMetrics
    )
  }

  private func createPreview(
    from startLocation: CGPoint,
    to endLocation: CGPoint
  ) -> ScheduleMonthDayScheduleCreatePreview {
    let start = snappedTimeMinutes(forY: startLocation.y)
    let end = snappedTimeMinutes(forY: endLocation.y)
    let lower = min(start, end)
    let upper = max(start, end)
    let duration = max(Self.minimumDurationMinutes, upper - lower)
    let clampedStart = Self.clampedTimeMinute(lower, durationMinutes: duration)
    return ScheduleMonthDayScheduleCreatePreview(
      timeMinutes: clampedStart,
      durationMinutes: min(duration, (24 * 60) - clampedStart)
    )
  }

  private func startMinute(for item: ScheduleMonthItem) -> Int {
    let components = calendar.dateComponents([.hour, .minute], from: item.startDate)
    return min(23 * 60 + 45, max(0, (components.hour ?? 0) * 60 + (components.minute ?? 0)))
  }

  private func durationMinutes(for item: ScheduleMonthItem) -> Int {
    ScheduleMonthDayInteractionAdapter.clampedDuration(
      item.durationMinutes ?? Self.minimumDurationMinutes,
      startMinute: startMinute(for: item),
      metrics: interactionMetrics
    )
  }

  private func snappedTimeMinutes(forY y: CGFloat) -> Int {
    ScheduleMonthDayInteractionAdapter.snappedTimeMinutes(for: y, metrics: interactionMetrics)
  }

  private func y(forMinute minute: Int) -> CGFloat {
    CGFloat(minute) / 60 * Self.hourHeight
  }

  private func height(forDuration duration: Int) -> CGFloat {
    max(28, CGFloat(duration) / 60 * Self.hourHeight)
  }

  private func itemColor(_ item: ScheduleMonthItem) -> Color {
    ColorHexCodec.color(from: item.colorHex) ?? .accentColor
  }

  private func canUpdateSchedule(for item: ScheduleMonthItem) -> Bool {
    guard !item.isBackgroundCalendar else { return false }
    switch item.source {
    case .workspaceTask:
      return true
    case .calendarEvent:
      return item.calendarEvent?.canEditTiming == true
    }
  }

  private func canResizeSchedule(for item: ScheduleMonthItem) -> Bool {
    guard canUpdateSchedule(for: item), !item.isAllDay else { return false }
    switch item.source {
    case .workspaceTask:
      return true
    case .calendarEvent:
      return item.calendarEvent?.spansMultipleDays == false
    }
  }

  private var interactionMetrics: ScheduleInteractionMetrics {
    ScheduleMonthDayInteractionAdapter.metrics(
      hourHeight: Self.hourHeight,
      minimumDurationMinutes: Self.minimumDurationMinutes
    )
  }

  private static func sortedItems(
    _ items: [ScheduleMonthItem],
    calendar: Calendar
  ) -> [ScheduleMonthItem] {
    items.sorted { itemSortKey($0, calendar: calendar) < itemSortKey($1, calendar: calendar) }
  }

  private static func clampedTimeMinute(_ minute: Int, durationMinutes: Int) -> Int {
    let latestStart = max(0, (24 * 60) - durationMinutes)
    return min(latestStart, max(0, minute))
  }

  private static func timeLabel(hour: Int) -> String {
    if hour == 0 { return "오전 12" }
    if hour < 12 { return "오전 \(hour)" }
    if hour == 12 { return "오후 12" }
    return "오후 \(hour - 12)"
  }

  private static let timeGutterWidth: CGFloat = 64
  private static let hourHeight: CGFloat = 56
  private static let allDayRowHeight: CGFloat = 30
  private static let minimumDurationMinutes = 30
  private static let dividerHeight: CGFloat = 1
  private static let initialVisibleHour = 18
  private static let topScrollID = "schedule-month-detail-time-top"
  private static let bottomScrollID = "schedule-month-detail-time-bottom"
  private static let nightScrollID = "schedule-month-detail-time-night"
  private static let panelCoordinateSpaceName = "schedule-month-detail-panel"
  private static var quarterHourHeight: CGFloat { hourHeight / 4 }
  private static var timeGridHeight: CGFloat { hourHeight * 24 }
}

private struct ScheduleMonthDayCurrentTimeIndicator: View {
  private static let refreshIntervalSeconds: TimeInterval = 60

  let day: Date
  let width: CGFloat
  let height: CGFloat
  let hourHeight: CGFloat
  let calendar: Calendar

  var body: some View {
    TimelineView(.periodic(from: .now, by: Self.refreshIntervalSeconds)) { context in
      ZStack(alignment: .topLeading) {
        if calendar.isDate(day, inSameDayAs: context.date) {
          let y = currentTimeY(for: context.date)

          Rectangle()
            .fill(Color.red.opacity(0.78))
            .frame(width: width, height: 2)
            .offset(y: y - 1)

          Circle()
            .fill(Color.red.opacity(0.9))
            .frame(width: 7, height: 7)
            .offset(x: 1, y: y - 3.5)
        }
      }
      .frame(width: width, height: height, alignment: .topLeading)
    }
    .allowsHitTesting(false)
  }

  private func currentTimeY(for date: Date) -> CGFloat {
    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
    let minutes =
      CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
      + CGFloat(components.second ?? 0) / 60
    return minutes / 60 * hourHeight
  }
}
