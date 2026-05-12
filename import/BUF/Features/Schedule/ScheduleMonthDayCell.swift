import SwiftUI

struct ScheduleMonthDayCell: View {
  let day: Date
  let displayedMonthStart: Date
  let today: Date
  let items: [ScheduleMonthItem]
  let visibleItemLimit: Int
  let hiddenAllDayItemCount: Int
  let reservedAllDayRowCount: Int
  let isSelected: Bool
  let isDragTarget: Bool
  let weekStart: Date
  let rowSize: CGSize
  let rowCoordinateSpaceName: String
  let rowFrameInScreen: CGRect
  @Binding var activeDragDate: Date?
  @Binding var activeDragFeedback: ScheduleMonthDragFeedback?
  let calendar: Calendar
  let onSelect: () -> Void
  let onToggleTaskCompletion: (UUID, UUID, Bool) -> Void
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void
  let externalDayDropTarget: ScheduleMonthDropTarget?

  @State private var suppressedSelectUntil: Date = .distantPast

  private var visibleRowCapacity: Int {
    max(0, visibleItemLimit)
  }

  private var shouldShowOverflowRow: Bool {
    visibleRowCapacity > 0 && (hiddenAllDayItemCount > 0 || items.count > visibleRowCapacity)
  }

  var visibleItems: [ScheduleMonthItem] {
    let itemLimit = shouldShowOverflowRow
      ? max(0, visibleRowCapacity - 1)
      : visibleRowCapacity
    return Array(items.prefix(itemLimit))
  }

  var hiddenItemCount: Int {
    guard shouldShowOverflowRow else { return 0 }
    return hiddenAllDayItemCount + max(0, items.count - visibleItems.count)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      cellBackground
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      cellContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .contentShape(Rectangle())
    .onTapGesture(perform: selectIfNotSuppressed)
    .onDrop(
      of: ScheduleMonthDragPayload.dropTypeIdentifiers,
      delegate: ScheduleMonthExternalItemDropDelegate(
        targetDay: day,
        activeDragDate: $activeDragDate,
        calendar: calendar,
        onMoveItem: onMoveItem
      )
    )
    .clipped()
  }

  private var cellContent: some View {
    VStack(alignment: .leading, spacing: ScheduleMonthLayoutMetrics.itemRowSpacing) {
      dayNumber
        .frame(height: ScheduleMonthLayoutMetrics.dayNumberHeight)
        .frame(maxWidth: .infinity, alignment: .trailing)

      if reservedAllDayRowCount > 0 {
        Color.clear
          .frame(height: CGFloat(reservedAllDayRowCount) * ScheduleMonthLayoutMetrics.allDaySpanRowHeight)
      }

      ForEach(visibleItems) { item in
        ScheduleMonthCompactItemRow(
          item: item,
          isCompletedTask: isCompletedTask(item),
          onToggleCompletion: completionToggleAction(for: item),
          onPressCompletionControl: completionPressAction(for: item)
        )
        .modifier(
          ScheduleMonthLocalDragModifier(
            item: item,
            weekStart: weekStart,
            rowSize: rowSize,
            rowCoordinateSpaceName: rowCoordinateSpaceName,
            rowFrameInScreen: rowFrameInScreen,
            activeDragDate: $activeDragDate,
            activeDragFeedback: $activeDragFeedback,
            calendar: calendar,
            onMoveItem: onMoveItem,
            externalDayDropTarget: externalDayDropTarget
          )
        )
        .simultaneousGesture(
          TapGesture().onEnded(selectIfNotSuppressed)
        )
      }

      if hiddenItemCount > 0 {
        Text("+\(hiddenItemCount)개")
          .font(.system(size: ScheduleUITokens.MonthCell.overflowFontSize, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.leading, 5)
          .frame(height: ScheduleMonthLayoutMetrics.itemRowHeight, alignment: .leading)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, ScheduleMonthLayoutMetrics.dayCellHorizontalPadding)
    .padding(.vertical, ScheduleMonthLayoutMetrics.dayCellTopPadding)
  }

  @ViewBuilder
  private var dayNumber: some View {
    let number = "\(calendar.component(.day, from: day))일"
    if calendar.isDate(day, inSameDayAs: today) {
      Text("\(calendar.component(.day, from: day))")
        .font(.system(size: ScheduleUITokens.MonthCell.dayNumberFontSize, weight: .bold))
        .foregroundStyle(Color.white)
        .frame(width: ScheduleUITokens.Month.dayNumberHeight, height: ScheduleUITokens.Month.dayNumberHeight)
        .background(Circle().fill(Color.red.opacity(ScheduleUITokens.Month.todayBadgeFillOpacity)))
        .accessibilityLabel(number)
    } else {
      Text(number)
        .font(.system(size: ScheduleUITokens.MonthCell.dayNumberFontSize, weight: .semibold))
        .foregroundStyle(dayNumberColor)
        .lineLimit(1)
    }
  }

  private var dayNumberColor: Color {
    calendar.isDate(day, equalTo: displayedMonthStart, toGranularity: .month)
      ? .primary
      : .secondary.opacity(ScheduleUITokens.Opacity.mutedSecondaryText)
  }

  private func isCompletedTask(_ item: ScheduleMonthItem) -> Bool {
    guard item.isCompleted else { return false }
    guard case .workspaceTask = item.source else { return false }
    return true
  }

  private func completionToggleAction(for item: ScheduleMonthItem) -> (() -> Void)? {
    guard !item.isPreparationSlot else { return nil }
    guard case .workspaceTask(let taskID, let projectID) = item.source else { return nil }
    return {
      suppressSelectionAfterCompletionPress()
      onToggleTaskCompletion(taskID, projectID, item.isCompleted)
    }
  }

  private func completionPressAction(for item: ScheduleMonthItem) -> (() -> Void)? {
    guard !item.isPreparationSlot else { return nil }
    guard case .workspaceTask = item.source else { return nil }
    return {
      suppressSelectionAfterCompletionPress()
    }
  }

  private func suppressSelectionAfterCompletionPress() {
    suppressedSelectUntil = TaskTapSuppressionPolicy.suppressedUntil(
      now: Date(),
      duration: TaskTapSuppressionPolicy.completionControlDuration
    )
  }

  private func selectIfNotSuppressed() {
    guard TaskTapSuppressionPolicy.shouldHandleTaskTap(
      now: Date(),
      suppressedUntil: suppressedSelectUntil
    ) else {
      return
    }
    onSelect()
  }

  @ViewBuilder
  private var cellBackground: some View {
    if isDragTarget {
      Rectangle()
        .fill(Color.accentColor.opacity(ScheduleUITokens.Opacity.dragTargetMonthCellBackground))
    } else if isSelected {
      Rectangle()
        .fill(Color.accentColor.opacity(ScheduleUITokens.Opacity.selectedMonthCellBackground))
    } else if calendar.isDate(day, inSameDayAs: today) {
      Rectangle()
        .fill(Color.accentColor.opacity(ScheduleUITokens.Opacity.todayMonthCellBackground))
    }
  }
}

struct ScheduleMonthAllDaySpanRow: View {
  let segment: ScheduleMonthAllDaySpanSegment

  private var item: ScheduleMonthItem {
    segment.item
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "calendar")
        .font(.system(size: ScheduleUITokens.MonthCell.allDayIconFontSize, weight: .semibold))
        .foregroundStyle(itemColor)

      Text(item.title)
        .font(.system(size: ScheduleUITokens.MonthCell.allDayTitleFontSize, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(itemColor.opacity(item.isBackgroundCalendar ? 0.22 : 0.20))
    }
    .opacity(item.isBackgroundCalendar ? 0.50 : 1)
  }

  private var itemColor: Color {
    ColorHexCodec.color(from: item.colorHex) ?? .accentColor
  }
}

private struct ScheduleMonthCompactItemRow: View {
  let item: ScheduleMonthItem
  let isCompletedTask: Bool
  let onToggleCompletion: (() -> Void)?
  let onPressCompletionControl: (() -> Void)?

  private static let timeFormatStyle = Date.FormatStyle(
    date: .omitted,
    time: .shortened
  )
  .locale(Locale(identifier: "ko_KR"))

  private var rowOpacity: Double {
    if isCompletedTask { return ScheduleUITokens.Opacity.completedMonthScheduleItem }
    if item.isBackgroundCalendar { return ScheduleUITokens.Opacity.backgroundMonthCalendarItem }
    return 1
  }

  var body: some View {
    HStack(spacing: 4) {
      markerControl

      Text(item.title)
        .font(.system(size: ScheduleUITokens.MonthCell.itemTitleFontSize, weight: .regular))
        .foregroundStyle(textColor)
        .lineLimit(1)
        .truncationMode(.tail)

      if let timeText {
        Spacer(minLength: 2)
        Text(timeText)
          .font(.system(size: ScheduleUITokens.MonthCell.itemTimeFontSize))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(height: ScheduleMonthLayoutMetrics.itemRowHeight)
    .opacity(rowOpacity)
  }

  @ViewBuilder
  private var markerControl: some View {
    if let onToggleCompletion {
      Button(action: onToggleCompletion) {
        marker
          .frame(
            width: ScheduleUITokens.MonthCell.markerControlWidth,
            height: ScheduleMonthLayoutMetrics.itemRowHeight
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .simultaneousGesture(
        taskCompletionPressGesture {
          onPressCompletionControl?()
        }
      )
      .help(item.isCompleted ? "완료 취소" : "완료")
    } else {
      marker
        .frame(
          width: ScheduleUITokens.MonthCell.markerControlWidth,
          height: ScheduleMonthLayoutMetrics.itemRowHeight
        )
    }
  }

  @ViewBuilder
  private var marker: some View {
    switch item.source {
    case .workspaceTask:
      if isCompletedTask {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: ScheduleUITokens.MonthCell.completedTaskIconFontSize, weight: .semibold))
          .foregroundStyle(itemColor)
      } else {
        Circle()
          .strokeBorder(itemColor, lineWidth: 1.4)
          .frame(
            width: ScheduleUITokens.MonthCell.taskMarkerSize,
            height: ScheduleUITokens.MonthCell.taskMarkerSize
          )
      }
    case .calendarEvent:
      if item.isAllDay {
        Image(systemName: "calendar")
          .font(.system(size: ScheduleUITokens.MonthCell.allDayCalendarIconFontSize, weight: .semibold))
          .foregroundStyle(itemColor)
      } else {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(itemColor)
          .frame(
            width: ScheduleUITokens.MonthCell.calendarStripeWidth,
            height: ScheduleUITokens.MonthCell.timedCalendarStripeHeight
          )
      }
    }
  }

  private var itemColor: Color {
    ColorHexCodec.color(from: item.colorHex) ?? .accentColor
  }

  private var textColor: Color {
    isCompletedTask ? .secondary : .primary
  }

  private var timeText: String? {
    guard case .calendarEvent = item.source, !item.isAllDay else {
      return nil
    }
    return item.startDate.formatted(Self.timeFormatStyle)
  }
}

struct ScheduleMonthDragFeedbackMarker: View {
  let feedback: ScheduleMonthDragFeedback

  var body: some View {
    ZStack {
      Circle()
        .fill(Color(nsColor: .windowBackgroundColor))
        .overlay {
          Circle()
            .strokeBorder(
              itemColor.opacity(ScheduleUITokens.MonthCell.dragFeedbackStrokeOpacity),
              lineWidth: 1.2
            )
        }
        .shadow(
          color: Color.black.opacity(ScheduleUITokens.Shadow.dragPreviewOpacity),
          radius: ScheduleUITokens.Shadow.dragPreviewRadius,
          x: 0,
          y: ScheduleUITokens.Shadow.dragPreviewYOffset
        )

      marker
    }
    .frame(
      width: ScheduleUITokens.MonthCell.dragFeedbackSize,
      height: ScheduleUITokens.MonthCell.dragFeedbackSize
    )
  }

  @ViewBuilder
  private var marker: some View {
    switch feedback.source {
    case .workspaceTask:
      if feedback.isCompleted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(
            size: ScheduleUITokens.MonthCell.dragFeedbackCompletedTaskIconFontSize,
            weight: .semibold
          ))
          .foregroundStyle(itemColor)
      } else {
        Circle()
          .strokeBorder(itemColor, lineWidth: 1.8)
          .frame(
            width: ScheduleUITokens.MonthCell.dragFeedbackTaskOutlineSize,
            height: ScheduleUITokens.MonthCell.dragFeedbackTaskOutlineSize
          )
      }
    case .calendarEvent:
      if feedback.isAllDay {
        Image(systemName: "calendar")
          .font(.system(size: ScheduleUITokens.MonthCell.dragFeedbackCalendarIconFontSize, weight: .semibold))
          .foregroundStyle(itemColor)
      } else {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(itemColor)
          .frame(
            width: ScheduleUITokens.MonthCell.dragFeedbackTimedCalendarStripeWidth,
            height: ScheduleUITokens.MonthCell.timedCalendarStripeHeight
          )
      }
    }
  }

  private var itemColor: Color {
    ColorHexCodec.color(from: feedback.colorHex) ?? .accentColor
  }
}

struct ScheduleMonthLocalDragModifier: ViewModifier {
  let item: ScheduleMonthItem
  let weekStart: Date
  let rowSize: CGSize
  let rowCoordinateSpaceName: String
  let rowFrameInScreen: CGRect
  @Binding var activeDragDate: Date?
  @Binding var activeDragFeedback: ScheduleMonthDragFeedback?
  let calendar: Calendar
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void
  let externalDayDropTarget: ScheduleMonthDropTarget?

  @State private var dragSession: ScheduleMonthDragSessionState?

  func body(content: Content) -> some View {
    if let dragItem = ScheduleMonthDragSupport.dragItem(for: item) {
      content
        .contentShape(Rectangle())
        .highPriorityGesture(
          DragGesture(minimumDistance: 6, coordinateSpace: .named(rowCoordinateSpaceName))
            .onChanged { value in
              updateDrag(value, dragItem: dragItem)
            }
            .onEnded { value in
              finishDrag(value, dragItem: dragItem)
            }
        )
    } else {
      content
    }
  }

  private func updateDrag(_ value: DragGesture.Value, dragItem _: ScheduleMonthDragItem) {
    let originalStartDay = calendar.startOfDay(for: item.startDate)
    if let externalTargetDay = externalDayPanelTargetDay(for: value) {
      let session = ScheduleMonthDragSessionState.external(
        targetDay: externalTargetDay,
        calendar: calendar
      )
      activeDragDate = session.highlightDay
      activeDragFeedback = ScheduleMonthDragFeedback(
        item: item,
        weekStart: weekStart,
        location: value.location
      )
      dragSession = session
      NSCursor.dragCopy.set()
      return
    }

    let resolvedStartPointerDay =
      dragSession?.startPointerDay
      ?? ScheduleMonthDragGeometry.day(
        at: value.startLocation,
        weekStart: weekStart,
        rowSize: rowSize,
        calendar: calendar
      )
    guard let resolvedStartPointerDay,
      let currentPointerDay = ScheduleMonthDragGeometry.day(
        at: value.location,
        weekStart: weekStart,
        rowSize: rowSize,
        calendar: calendar
      )
    else {
      return
    }

    guard let session = ScheduleMonthDragSessionState.local(
      originalStartDay: originalStartDay,
      startPointerDay: resolvedStartPointerDay,
      currentPointerDay: currentPointerDay,
      calendar: calendar
    ) else { return }

    dragSession = session
    activeDragDate = session.highlightDay
    NSCursor.closedHand.set()
    activeDragFeedback = ScheduleMonthDragFeedback(
      item: item,
      weekStart: weekStart,
      location: value.location
    )
  }

  private func finishDrag(_ value: DragGesture.Value, dragItem: ScheduleMonthDragItem) {
    defer { NSCursor.arrow.set() }
    updateDrag(value, dragItem: dragItem)
    let target = dragSession?.target

    dragSession = nil
    activeDragDate = nil
    activeDragFeedback = nil

    guard let target else { return }
    onMoveItem(dragItem, target)
  }

  private func externalDayPanelTargetDay(for value: DragGesture.Value) -> Date? {
    guard
      let screenPoint = ScheduleScreenPointMapper.screenPoint(
        localLocation: value.location,
        in: rowFrameInScreen
      )
    else {
      return nil
    }
    return ScheduleMonthDropTargetResolver.day(
      at: screenPoint,
      target: externalDayDropTarget,
      calendar: calendar
    )
  }
}

private struct ScheduleMonthExternalItemDropDelegate: DropDelegate {
  let targetDay: Date
  @Binding var activeDragDate: Date?
  let calendar: Calendar
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    dropProvider(in: info) != nil
  }

  func dropEntered(info _: DropInfo) {
    activeDragDate = calendar.startOfDay(for: targetDay)
  }

  func dropExited(info _: DropInfo) {
    if let activeDragDate,
      calendar.isDate(activeDragDate, inSameDayAs: targetDay)
    {
      self.activeDragDate = nil
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    validateDrop(info: info) ? DropProposal(operation: .move) : nil
  }

  func performDrop(info: DropInfo) -> Bool {
    activeDragDate = nil
    guard let provider = dropProvider(in: info) else {
      return false
    }
    let target = ScheduleMonthDragSessionState.external(
      targetDay: targetDay,
      calendar: calendar
    ).target
    loadDragItem(from: provider) { dragItem in
      guard let dragItem else { return }
      onMoveItem(dragItem, target)
    }
    return true
  }

  private func dropProvider(in info: DropInfo) -> NSItemProvider? {
    ScheduleMonthDragPayload.dropTypeIdentifiers.lazy.compactMap { typeIdentifier in
      info.itemProviders(for: [typeIdentifier]).first
    }.first
  }

  private func loadDragItem(
    from provider: NSItemProvider,
    completion: @escaping @MainActor (ScheduleMonthDragItem?) -> Void
  ) {
    let preferredType =
      ScheduleMonthDragPayload.dropTypeIdentifiers.first {
        provider.hasItemConformingToTypeIdentifier($0)
      } ?? ScheduleMonthDragPayload.textTypeIdentifier

    provider.loadItem(forTypeIdentifier: preferredType, options: nil) { item, _ in
      let dragItem = ScheduleMonthDragPayload.parseItem(from: item)
      Task { @MainActor in
        completion(dragItem)
      }
    }
  }
}
