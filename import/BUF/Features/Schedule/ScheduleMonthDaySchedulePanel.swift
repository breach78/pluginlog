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

  @State var items: [ScheduleMonthItem]
  @State var activeMutationPreview: ScheduleMonthDayScheduleMutationPreview?
  @State var activeCreatePreview: ScheduleMonthDayScheduleCreatePreview?
  @State var pendingCreatePreview: ScheduleMonthDayScheduleCreatePreview?
  @State var savingItemIDs: Set<String> = []
  @State var timeScrollResetID = UUID()
  @State var timeContentMinYInPanel: CGFloat = 0
  @State var activeItemDragState: ScheduleMonthDayItemDragState?
  @State var activeItemResizeState: ScheduleMonthDayItemResizeState?
  @State var resizeBlockedMoveItemID: String?
  @State var panelFrameInScreen: CGRect = .null
  @State var timeContentFrameInScreen: CGRect = .null

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

  func scrollTimeGridToInitialPosition(_ proxy: ScrollViewProxy) {
    let delays: [TimeInterval] = [0, 0.05, 0.18]
    for delay in delays {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        proxy.scrollTo(Self.nightScrollID, anchor: .top)
      }
    }
  }

  var panelFrameReporter: some View {
    ScheduleScreenFrameReporter { frame in
      panelFrameInScreen = frame
      reportDropTarget(frame: frame)
      updateTimeContentOffset(timeFrame: timeContentFrameInScreen, panelFrame: frame)
    }
  }

  func reportDropTarget(frame: CGRect) {
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

  var allDaySection: some View {
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

  var allDaySectionHeight: CGFloat {
    max(22, CGFloat(allDayRowCount) * Self.allDayRowHeight + 20)
  }

  var allDayRowCount: Int {
    allDayItems.count + (activeDragPreviewIsAllDay ? 1 : 0)
  }

  var timedSchedule: some View {
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

  var timeContentFrameReporter: some View {
    ScheduleScreenFrameReporter { frame in
      timeContentFrameInScreen = frame
      updateTimeContentOffset(timeFrame: frame, panelFrame: panelFrameInScreen)
    }
  }

  func updateTimeContentOffset(timeFrame: CGRect, panelFrame: CGRect) {
    guard !timeFrame.isNull, !panelFrame.isNull else { return }
    timeContentMinYInPanel = panelFrame.maxY - timeFrame.maxY
  }

  var timeScrollAnchorLayer: some View {
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
  func hiddenTimedItemsIndicator(proxy: ScrollViewProxy) -> some View {
    if hasHiddenTimedItemsAboveVisibleStart {
      Button {
        revealHiddenTimedItems(proxy: proxy)
      } label: {
        Image(systemName: "arrowtriangle.up.fill")
          .font(.system(size: ScheduleUITokens.MonthDayPanel.hiddenIndicatorFontSize, weight: .bold))
          .foregroundStyle(
            Color.secondary.opacity(ScheduleUITokens.MonthDayPanel.hiddenIndicatorOpacity)
          )
          .frame(
            width: ScheduleUITokens.MonthDayPanel.hiddenIndicatorWidth,
            height: ScheduleUITokens.MonthDayPanel.hiddenIndicatorHeight
          )
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

  var timeAxis: some View {
    ZStack(alignment: .topTrailing) {
      ForEach(0...24, id: \.self) { hour in
        Text(hour == 24 ? "" : Self.timeLabel(hour: hour))
          .font(.system(size: ScheduleUITokens.MonthDayPanel.timeAxisFontSize))
          .foregroundStyle(.secondary)
          .frame(width: Self.timeGutterWidth - 10, alignment: .trailing)
          .offset(
            y: CGFloat(hour) * Self.hourHeight
              + ScheduleUITokens.MonthDayPanel.timeAxisLabelTopPadding
          )
      }
    }
    .padding(.trailing, ScheduleUITokens.MonthDayPanel.timeAxisLabelTrailingPadding)
  }

  var timedGridLines: some View {
    ZStack(alignment: .topLeading) {
      ForEach(0...24, id: \.self) { hour in
        Rectangle()
          .fill(
            Color(nsColor: .separatorColor).opacity(
              hour % 6 == 0
                ? ScheduleUITokens.MonthDayPanel.majorGridLineOpacity
                : ScheduleUITokens.MonthDayPanel.minorGridLineOpacity
            )
          )
          .frame(height: 1)
          .offset(y: CGFloat(hour) * Self.hourHeight)
      }
    }
  }

  var allDayItems: [ScheduleMonthItem] {
    displayedItems
      .filter(\.isAllDay)
      .sorted { lhs, rhs in
        itemSortKey(lhs, calendar: calendar) < itemSortKey(rhs, calendar: calendar)
      }
  }

  var timedItems: [ScheduleMonthItem] {
    displayedItems
      .filter { !$0.isAllDay }
      .sorted { lhs, rhs in
        itemSortKey(lhs, calendar: calendar) < itemSortKey(rhs, calendar: calendar)
      }
  }

  var visibleStartMinute: Int {
    let scrollOffsetY = max(0, allDaySectionHeight + Self.dividerHeight - timeContentMinYInPanel)
    return ScheduleHiddenTimedItemIndicatorPolicy.visibleStartMinute(
      scrollOffsetY: scrollOffsetY,
      hourHeight: Self.hourHeight
    )
  }

  var hasHiddenTimedItemsAboveVisibleStart: Bool {
    let intervals = timedItems.compactMap(timedInterval)
    return ScheduleHiddenTimedItemIndicatorPolicy.hasHiddenTimedItem(
      visibleStartMinute: visibleStartMinute,
      endMinutes: intervals.map(\.endMinute)
    )
  }

  var displayedItems: [ScheduleMonthItem] {
    items
  }

  var activeDragPreviewIsAllDay: Bool {
    guard activeItemDragState != nil, let activeMutationPreview else { return false }
    return activeMutationPreview.timeMinutes == nil
  }

  func timedLayouts(for width: CGFloat) -> [ScheduleMonthDayTimedItemLayout] {
    let intervals = timedItems.compactMap(timedInterval)
    return ScheduleMonthDayTimedLayoutBuilder.layouts(
      intervals: intervals,
      width: width,
      hourHeight: Self.hourHeight
    )
  }

  func timedInterval(for item: ScheduleMonthItem) -> ScheduleMonthDayTimedInterval? {
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

  func sourceTopScheduleY(for layout: ScheduleMonthDayTimedItemLayout) -> CGFloat {
    let targetDay = calendar.startOfDay(for: target.date)
    let relativeMinute = calendar.dateComponents(
      [.minute],
      from: targetDay,
      to: layout.item.startDate
    ).minute ?? layout.startMinute
    return CGFloat(relativeMinute) / 60 * Self.hourHeight
  }

  func createPreviewBlock(
    _ preview: ScheduleMonthDayScheduleCreatePreview,
    width: CGFloat
  ) -> some View {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
      .fill(Color.accentColor.opacity(ScheduleUITokens.MonthDayPanel.dropTargetFillOpacity))
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(
            Color.accentColor.opacity(ScheduleUITokens.MonthDayPanel.dropTargetStrokeOpacity),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
          )
      )
      .frame(width: max(40, width - 12), height: height(forDuration: preview.durationMinutes))
      .offset(x: 6, y: y(forMinute: preview.timeMinutes))
      .allowsHitTesting(false)
  }

  func pendingCreateCard(
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
        .shadow(
          color: .black.opacity(ScheduleUITokens.Panel.floatingPopoverShadowOpacity),
          radius: ScheduleUITokens.Panel.floatingPopoverShadowRadius,
          y: ScheduleUITokens.Panel.floatingPopoverShadowYOffset
        )
    )
    .position(
      x: min(max(140, width * 0.5), max(140, width - 140)),
      y: min(Self.timeGridHeight - 86, max(86, y(forMinute: preview.timeMinutes) + 76))
    )
    .zIndex(20)
  }

  func revealHiddenTimedItems(proxy: ScrollViewProxy) {
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
}
