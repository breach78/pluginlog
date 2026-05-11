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
        ZStack(alignment: .topLeading) {
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

          hiddenTimedItemsIndicator(proxy: proxy)
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
              allowsStartResize: layout.isFirstSegment,
              allowsEndResize: layout.isLastSegment,
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
                updateMovePreview(for: layout.item, drag: value, originalTopScheduleY: sourceTopScheduleY(for: layout), originalX: layout.x, originalWidth: layout.width)
              },
              onMoveEnded: { value in
                finishMovePreview(for: layout.item, drag: value, originalTopScheduleY: sourceTopScheduleY(for: layout), originalX: layout.x, originalWidth: layout.width)
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
    ZStack(alignment: .topLeading) {
      VStack(spacing: 0) {
        Color.clear
          .frame(height: CGFloat(Self.initialVisibleHour) * Self.hourHeight)
        Color.clear
          .frame(height: 1)
          .id(Self.nightScrollID)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

      ForEach(0...96, id: \.self) { quarter in
        Color.clear
          .frame(width: 1, height: 1)
          .offset(y: CGFloat(quarter) * Self.quarterHourHeight)
          .id(Self.timeScrollID(forQuarter: quarter))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func hiddenTimedItemsIndicator(proxy: ScrollViewProxy) -> some View {
    if hasHiddenTimedItemsAboveVisibleStart {
      Button {
        revealHiddenTimedItems(proxy: proxy)
      } label: {
        Image(systemName: "arrowtriangle.up.fill")
          .font(.system(size: 8.4, weight: .bold))
          .foregroundStyle(Color.secondary.opacity(0.68))
          .frame(width: 18, height: 12)
      }
      .buttonStyle(.plain)
      .help("위쪽 숨겨진 시간대에 항목 있음")
      .padding(.leading, Self.timeGutterWidth)
      .frame(height: 12, alignment: .topLeading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .offset(y: 4)
      .zIndex(30)
    }
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

  private var visibleStartMinute: Int {
    let scrollOffsetY = max(0, allDaySectionHeight + Self.dividerHeight - timeContentMinYInPanel)
    return ScheduleHiddenTimedItemIndicatorPolicy.visibleStartMinute(
      scrollOffsetY: scrollOffsetY,
      hourHeight: Self.hourHeight
    )
  }

  private var hasHiddenTimedItemsAboveVisibleStart: Bool {
    let intervals = timedItems.compactMap(timedInterval)
    return ScheduleHiddenTimedItemIndicatorPolicy.hasHiddenTimedItem(
      visibleStartMinute: visibleStartMinute,
      endMinutes: intervals.map(\.endMinute)
    )
  }

  private var displayedItems: [ScheduleMonthItem] {
    items
  }

  private var activeDragPreviewIsAllDay: Bool {
    guard activeItemDragState != nil, let activeMutationPreview else { return false }
    return activeMutationPreview.timeMinutes == nil
  }

  private func timedLayouts(for width: CGFloat) -> [ScheduleMonthDayTimedItemLayout] {
    let intervals = timedItems.compactMap(timedInterval)
    return ScheduleMonthDayTimedLayoutBuilder.layouts(
      intervals: intervals,
      width: width,
      hourHeight: Self.hourHeight
    )
  }

  private func timedInterval(for item: ScheduleMonthItem) -> ScheduleMonthDayTimedInterval? {
    let dayStart = calendar.startOfDay(for: target.date)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
      return nil
    }
    let segmentStart = max(item.startDate, dayStart)
    let segmentEnd = min(item.endDate, dayEnd)
    guard segmentEnd > segmentStart else { return nil }

    let sourceStartComponents = calendar.dateComponents([.hour, .minute], from: item.startDate)
    let sourceStartMinute =
      (sourceStartComponents.hour ?? 0) * 60 + (sourceStartComponents.minute ?? 0)
    let startMinute = calendar.dateComponents([.minute], from: dayStart, to: segmentStart).minute ?? 0
    let segmentDurationMinutes = max(
      Self.minimumDurationMinutes,
      calendar.dateComponents([.minute], from: segmentStart, to: segmentEnd).minute ?? 0
    )

    return ScheduleMonthDayTimedInterval(
      item: item,
      startMinute: max(0, min(23 * 60 + 45, startMinute)),
      durationMinutes: min(segmentDurationMinutes, max(Self.minimumDurationMinutes, (24 * 60) - startMinute)),
      sourceStartDay: calendar.startOfDay(for: item.startDate),
      sourceStartMinute: sourceStartMinute,
      sourceDurationMinutes: durationMinutes(for: item),
      isFirstSegment: calendar.isDate(item.startDate, inSameDayAs: dayStart),
      isLastSegment: item.endDate <= dayEnd
    )
  }

  private func sourceTopScheduleY(for layout: ScheduleMonthDayTimedItemLayout) -> CGFloat {
    let targetDay = calendar.startOfDay(for: target.date)
    let relativeMinute = calendar.dateComponents(
      [.minute],
      from: targetDay,
      to: layout.item.startDate
    ).minute ?? layout.startMinute
    return CGFloat(relativeMinute) / 60 * Self.hourHeight
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

  private func revealHiddenTimedItems(proxy: ScrollViewProxy) {
    let intervals = timedItems.compactMap(timedInterval)
    let policyIntervals = intervals.map { interval in
      (startMinute: interval.startMinute, endMinute: interval.endMinute)
    }
    guard let targetMinute = ScheduleHiddenTimedItemIndicatorPolicy.earliestHiddenStartMinute(
      visibleStartMinute: visibleStartMinute,
      intervals: policyIntervals
    ) else {
      return
    }

    let revealMinute = max(0, targetMinute - 15)
    let quarter = min(96, max(0, Int(floor(Double(revealMinute) / 15.0))))
    withAnimation(.easeOut(duration: 0.16)) {
      proxy.scrollTo(Self.timeScrollID(forQuarter: quarter), anchor: .top)
    }
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

  private func commitMutationSession(
    _ session: ScheduleInteractionSession,
    item: ScheduleMonthItem,
    itemID: String
  ) {
    activeMutationPreview = nil
    activeItemDragState = nil
    activeItemResizeState = nil
    guard canUpdateSchedule(for: item) else { return }
    guard !savingItemIDs.contains(item.id) else { return }
    guard let command = session.command else { return }
    let commandPreview = command
      .schedulePreview(fallbackDay: calendar.startOfDay(for: target.date))
      .monthDayPreview(itemID: itemID, fallbackDay: calendar.startOfDay(for: target.date))
    let updated = item.applyingSchedulePreview(commandPreview, calendar: calendar)
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
          commandPreview.day,
          commandPreview.timeMinutes,
          commandPreview.durationMinutes
        )
      else {
        replaceOrRemoveForCurrentDay(item)
        return
      }
      replaceOrRemoveForCurrentDay(saved)
    }
  }

  private func interactionIdentity(for item: ScheduleMonthItem) -> ScheduleInteractionItemIdentity? {
    switch item.source {
    case .workspaceTask(let taskID, _):
      return .task(taskID)
    case .calendarEvent(let eventID):
      return .calendarEvent(eventID)
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
    activeMutationPreview = moveMutationPreview(for: state)
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
      guard let session = externalMonthDropSession(for: state, targetDay: targetDay) else {
        activeMutationPreview = nil
        activeItemDragState = nil
        return
      }
      commitMutationSession(session, item: state.originalItem, itemID: state.itemID)
      return
    }
    onExternalMonthDragTargetChanged(nil)
    guard let session = moveSession(for: state) else { return }
    commitMutationSession(session, item: state.originalItem, itemID: state.itemID)
  }

  private func updateResizePreview(
    for layout: ScheduleMonthDayTimedItemLayout,
    edge: ScheduleResizeEdge,
    drag: DragGesture.Value
  ) {
    let item = layout.item
    guard canResizeSchedule(for: item) else { return }
    let state = resizeState(for: layout, edge: edge, drag: drag)
    activeMutationPreview = resizeMutationPreview(for: state, currentPointerPanelY: drag.location.y)
  }

  private func finishResizePreview(
    for layout: ScheduleMonthDayTimedItemLayout,
    edge: ScheduleResizeEdge,
    drag: DragGesture.Value
  ) {
    let item = layout.item
    guard canResizeSchedule(for: item) else { return }
    let state = resizeState(for: layout, edge: edge, drag: drag)
    guard let session = resizeSession(for: state, currentPointerPanelY: drag.location.y) else { return }
    let blockedItemID = state.itemID
    commitMutationSession(session, item: state.originalItem, itemID: state.itemID)
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
      originalTimeMinutes: layout.sourceStartMinute,
      originalDurationMinutes: layout.sourceDurationMinutes,
      originalPointerScheduleY: drag.startLocation.y - timeContentMinYInPanel,
      originalEdgeScheduleY: edge == .start
        ? sourceTopScheduleY(for: layout)
        : sourceTopScheduleY(for: layout)
          + CGFloat(layout.sourceDurationMinutes) / 60 * Self.hourHeight,
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
    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
      return calendar.isDate(item.startDate, inSameDayAs: day)
    }
    return item.startDate < nextDay && item.endDate > day
  }

  private func moveMutationPreview(
    for state: ScheduleMonthDayItemDragState
  ) -> ScheduleMonthDayScheduleMutationPreview? {
    moveSession(for: state)?.preview.monthDayPreview(
      itemID: state.itemID,
      fallbackDay: calendar.startOfDay(for: target.date)
    )
  }

  private func moveSession(
    for state: ScheduleMonthDayItemDragState
  ) -> ScheduleInteractionSession? {
    guard let identity = interactionIdentity(for: state.originalItem) else { return nil }
    let targetDay = calendar.startOfDay(for: target.date)
    return ScheduleInteractionSession.move(
      identity: identity,
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      target: ScheduleMonthDayInteractionAdapter.moveTarget(
        for: state,
        targetDay: targetDay,
        calendar: calendar,
        metrics: interactionMetrics
      ),
      metrics: interactionMetrics
    )
  }

  private func externalMonthDropSession(
    for state: ScheduleMonthDayItemDragState,
    targetDay: Date
  ) -> ScheduleInteractionSession? {
    guard let identity = interactionIdentity(for: state.originalItem) else { return nil }
    return ScheduleInteractionSession.move(
      identity: identity,
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      target: ScheduleMonthDayInteractionAdapter.externalMonthDropTarget(
        targetDay: targetDay,
        calendar: calendar
      ),
      metrics: interactionMetrics
    )
  }

  private func externalMonthDropContext(for drag: DragGesture.Value) -> (
    isExternal: Bool,
    day: Date?
  ) {
    guard
      let screenPoint = ScheduleScreenPointMapper.screenPoint(
        localLocation: drag.location,
        in: panelFrameInScreen
      )
    else {
      return (false, nil)
    }
    let targetDay = externalMonthDropDay(at: screenPoint)
    let leftPanel = ScheduleMonthDayInteractionAdapter.isExternalMonthDropLocation(
      locationXInPanel: drag.location.x,
      translation: drag.translation
    )
    return (targetDay != nil || leftPanel, targetDay)
  }

  private func externalMonthDropDay(at screenPoint: CGPoint) -> Date? {
    guard !panelFrameInScreen.isNull else { return nil }
    return resolveExternalMonthDropDay(screenPoint)
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

  private func resizeMutationPreview(
    for state: ScheduleMonthDayItemResizeState,
    currentPointerPanelY: CGFloat
  ) -> ScheduleMonthDayScheduleMutationPreview? {
    resizeSession(for: state, currentPointerPanelY: currentPointerPanelY)?.preview.monthDayPreview(
      itemID: state.itemID,
      fallbackDay: calendar.startOfDay(for: target.date)
    )
  }

  private func resizeSession(
    for state: ScheduleMonthDayItemResizeState,
    currentPointerPanelY: CGFloat
  ) -> ScheduleInteractionSession? {
    guard let identity = interactionIdentity(for: state.originalItem) else { return nil }
    let targetDay = calendar.startOfDay(for: target.date)
    return ScheduleInteractionSession.resize(
      identity: identity,
      originalDay: calendar.startOfDay(for: state.originalItem.startDate),
      originalTimeMinutes: state.originalTimeMinutes,
      originalDurationMinutes: state.originalDurationMinutes,
      isStartEdge: state.edge == .start,
      target: ScheduleMonthDayInteractionAdapter.resizeTarget(
        for: state,
        currentPointerPanelY: currentPointerPanelY,
        targetDay: targetDay,
        calendar: calendar,
        metrics: interactionMetrics
      ),
      metrics: interactionMetrics,
      calendar: calendar
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
    max(Self.minimumDurationMinutes, item.durationMinutes ?? Self.minimumDurationMinutes)
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
      return item.calendarEvent?.canEditTiming == true
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

  private static func timeScrollID(forQuarter quarter: Int) -> String {
    "schedule-month-detail-time-quarter-\(quarter)"
  }
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
