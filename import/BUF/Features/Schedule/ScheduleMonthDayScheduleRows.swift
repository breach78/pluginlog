import SwiftUI

struct ScheduleMonthDayAllDayItemRow: View {
  let item: ScheduleMonthItem
  let isSaving: Bool
  let canDrag: Bool
  let isInteracting: Bool
  let coordinateSpaceName: String
  let onOpen: () -> Void
  let onToggleCompletion: () -> Void
  let onDeleteItem: (ScheduleCalendarRecurringEditScope?) -> Void
  let onMoveChanged: (DragGesture.Value) -> Void
  let onMoveEnded: (DragGesture.Value) -> Void

  var body: some View {
    HStack(spacing: 7) {
      if itemIsTask {
        marker
      }

      Button(action: onOpen) {
        HStack(spacing: 0) {
          Text(item.title)
            .font(.system(size: ScheduleUITokens.DayPanelRow.titleFontSize, weight: .semibold))
            .foregroundStyle(item.isCompleted ? .secondary : .primary)
            .lineLimit(1)

          Spacer(minLength: 0)
        }
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, itemIsCalendar ? ScheduleUITokens.DayPanelRow.allDayCalendarHorizontalPadding : 0)
    .frame(height: ScheduleUITokens.DayPanelRow.allDayRowHeight)
    .background {
      if itemIsCalendar {
        RoundedRectangle(cornerRadius: ScheduleUITokens.DayPanelRow.allDayCornerRadius, style: .continuous)
          .fill(color.opacity(
            item.isBackgroundCalendar
              ? ScheduleUITokens.EventBlock.dayPanelAllDayBackgroundCalendarFillOpacity
              : ScheduleUITokens.EventBlock.dayPanelAllDayCalendarFillOpacity
          ))
      }
    }
    .contentShape(Rectangle())
    .opacity(isInteracting ? ScheduleUITokens.DayPanelRow.interactingOpacity : opacity)
    .contextMenu {
      ScheduleMonthDayDeleteContextMenu(
        item: item,
        isSaving: isSaving,
        onDeleteItem: onDeleteItem
      )
    }
    .simultaneousGesture(dragGesture)
  }

  @ViewBuilder
  private var marker: some View {
    if itemIsTask {
      ScheduleMonthDayTaskMarker(color: color, isCompleted: item.isCompleted)
      .frame(
        width: ScheduleUITokens.DayPanelRow.markerHitWidth,
        height: ScheduleUITokens.DayPanelRow.markerHitHeight
      )
      .contentShape(Rectangle())
      .highPriorityGesture(
        TapGesture().onEnded {
          guard !isSaving else { return }
          onToggleCompletion()
        }
      )
    }
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .named(coordinateSpaceName))
      .onChanged { value in
        guard canDrag, !isSaving else { return }
        onMoveChanged(value)
      }
      .onEnded { value in
        guard canDrag, !isSaving else { return }
        onMoveEnded(value)
      }
  }

  private var itemIsTask: Bool {
    if case .workspaceTask = item.source { return true }
    return false
  }

  private var itemIsCalendar: Bool {
    if case .calendarEvent = item.source { return true }
    return false
  }

  private var color: Color {
    ColorHexCodec.color(from: item.colorHex) ?? .accentColor
  }

  private var opacity: Double {
    item.isCompleted || item.isBackgroundCalendar ? ScheduleUITokens.DayPanelRow.baseMutedOpacity : 1
  }
}

struct ScheduleMonthDayTimedItemBlock: View {
  let layout: ScheduleMonthDayTimedItemLayout
  let color: Color
  let isSaving: Bool
  let canDrag: Bool
  let canResize: Bool
  let allowsStartResize: Bool
  let allowsEndResize: Bool
  let isInteracting: Bool
  let coordinateSpaceName: String
  let onOpen: () -> Void
  let onToggleCompletion: () -> Void
  let onDeleteItem: (ScheduleCalendarRecurringEditScope?) -> Void
  let onMoveChanged: (DragGesture.Value) -> Void
  let onMoveEnded: (DragGesture.Value) -> Void
  let onResizeChanged: (ScheduleResizeEdge, DragGesture.Value) -> Void
  let onResizeEnded: (ScheduleResizeEdge, DragGesture.Value) -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      surface

      openHitArea

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .top, spacing: 7) {
          if itemIsTask {
            marker
              .padding(.top, ScheduleUITokens.DayPanelRow.markerTopPadding)
          }

          VStack(alignment: .leading, spacing: 2) {
            Text(layout.item.title)
              .font(.system(size: ScheduleUITokens.DayPanelRow.titleFontSize, weight: .semibold))
              .foregroundStyle(layout.item.isCompleted ? .secondary : .primary)
              .lineLimit(ScheduleMonthDayTimedBlockMetrics.titleLineLimit(forBlockHeight: layout.height))

            if let subtitle = layout.item.subtitle,
              !subtitle.isEmpty,
              layout.height >= ScheduleUITokens.DayPanelRow.timedSubtitleMinHeight
            {
              Text(subtitle)
                .font(.system(size: ScheduleUITokens.DayPanelRow.supplementalFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if layout.height >= ScheduleUITokens.DayPanelRow.timedTimeMinHeight {
              Text(timeText)
                .font(.system(size: ScheduleUITokens.DayPanelRow.supplementalFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture(perform: onOpen)

          Spacer(minLength: 0)
        }
      }
      .padding(.horizontal, ScheduleUITokens.DayPanelRow.horizontalPadding)
      .padding(
        .vertical,
        ScheduleMonthDayTimedBlockMetrics.contentVerticalPadding(forBlockHeight: layout.height)
      )

      if canResize && allowsStartResize {
        resizeHandle(edge: .start)
          .frame(maxHeight: .infinity, alignment: .top)
      }

      if canResize && allowsEndResize {
        resizeHandle(edge: .end)
          .frame(maxHeight: .infinity, alignment: .bottom)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: ScheduleUITokens.DayPanelRow.timedCornerRadius, style: .continuous))
    .opacity(isInteracting ? ScheduleUITokens.DayPanelRow.interactingOpacity : baseOpacity)
    .clipped()
    .contextMenu {
      ScheduleMonthDayDeleteContextMenu(
        item: layout.item,
        isSaving: isSaving,
        onDeleteItem: onDeleteItem
      )
    }
    .simultaneousGesture(moveGesture)
  }

  @ViewBuilder
  private var surface: some View {
    switch layout.item.source {
    case .workspaceTask:
      RoundedRectangle(cornerRadius: ScheduleUITokens.DayPanelRow.timedCornerRadius, style: .continuous)
        .fill(color.opacity(
          layout.item.isCompleted
            ? ScheduleUITokens.EventBlock.dayPanelCompletedTaskFillOpacity
            : ScheduleUITokens.EventBlock.dayPanelTaskFillOpacity
        ))
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(color)
            .frame(width: ScheduleUITokens.DayPanelRow.colorStripeWidth)
        }
    case .calendarEvent:
      RoundedRectangle(cornerRadius: ScheduleUITokens.DayPanelRow.timedCornerRadius, style: .continuous)
        .fill(color.opacity(
          layout.item.isBackgroundCalendar
            ? ScheduleUITokens.EventBlock.dayPanelBackgroundCalendarFillOpacity
            : ScheduleUITokens.EventBlock.dayPanelCalendarFillOpacity
        ))
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(color.opacity(ScheduleUITokens.EventBlock.dayPanelCalendarStripeForegroundOpacity))
            .frame(width: ScheduleUITokens.DayPanelRow.colorStripeWidth)
        }
    }
  }

  private var openHitArea: some View {
    HStack(spacing: 0) {
      if itemIsTask {
        Color.clear
          .frame(width: ScheduleUITokens.DayPanelRow.openHitAreaTaskWidth)
          .allowsHitTesting(false)
      }

      Rectangle()
        .fill(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
  }

  @ViewBuilder
  private var marker: some View {
    if itemIsTask {
      ScheduleMonthDayTaskMarker(color: color, isCompleted: layout.item.isCompleted)
      .frame(
        width: ScheduleUITokens.DayPanelRow.markerHitWidth,
        height: ScheduleMonthDayTimedBlockMetrics.markerHitHeight(forBlockHeight: layout.height)
      )
      .contentShape(Rectangle())
      .highPriorityGesture(
        TapGesture().onEnded {
          guard !isSaving else { return }
          onToggleCompletion()
        }
      )
    }
  }

  private var moveGesture: some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .named(coordinateSpaceName))
      .onChanged { value in
        guard canDrag, !isSaving else { return }
        onMoveChanged(value)
      }
      .onEnded { value in
        guard canDrag, !isSaving else { return }
        onMoveEnded(value)
      }
  }

  private func resizeHandle(edge: ScheduleResizeEdge) -> some View {
    Rectangle()
      .fill(Color.clear)
      .frame(height: ScheduleUITokens.DayPanelRow.resizeHandleHeight)
      .overlay {
        ScheduleCursorRegion(cursor: .resizeUpDown)
      }
      .contentShape(Rectangle())
      .highPriorityGesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
          .onChanged { value in
            onResizeChanged(edge, value)
          }
          .onEnded { value in
            onResizeEnded(edge, value)
          }
      )
      .help(edge == .start ? "시작 시간 조절" : "종료 시간 조절")
  }

  private var itemIsTask: Bool {
    if case .workspaceTask = layout.item.source { return true }
    return false
  }

  private var baseOpacity: Double {
    layout.item.isCompleted || layout.item.isBackgroundCalendar
      ? ScheduleUITokens.DayPanelRow.baseMutedOpacity
      : 1
  }

  private var timeText: String {
    let start = ScheduleMonthDayTimeFormatter.timeText(from: layout.item.startDate)
    let end = ScheduleMonthDayTimeFormatter.timeText(from: layout.item.endDate)
    return "\(start)-\(end)"
  }
}

struct ScheduleMonthDayDeleteContextMenu: View {
  let item: ScheduleMonthItem
  let isSaving: Bool
  let onDeleteItem: (ScheduleCalendarRecurringEditScope?) -> Void

  var body: some View {
    if !isSaving {
      switch item.source {
      case .workspaceTask:
        if !item.isPreparationSlot {
          Button(role: .destructive) {
            onDeleteItem(nil)
          } label: {
            Label("삭제", systemImage: "trash")
          }
        }
      case .calendarEvent:
        if let event = item.calendarEvent, event.canEditTiming, !item.isBackgroundCalendar {
          if event.isRecurring {
            Button(role: .destructive) {
              onDeleteItem(.thisEvent)
            } label: {
              Label("이 일정만 삭제", systemImage: "trash")
            }

            Button(role: .destructive) {
              onDeleteItem(.futureEvents)
            } label: {
              Label("이후 반복 일정 삭제", systemImage: "trash")
            }
          } else {
            Button(role: .destructive) {
              onDeleteItem(.thisEvent)
            } label: {
              Label("삭제", systemImage: "trash")
            }
          }
        }
      }
    }
  }
}

struct ScheduleMonthDayTaskMarker: View {
  let color: Color
  let isCompleted: Bool

  var body: some View {
    ZStack {
      Circle()
        .strokeBorder(color, lineWidth: 1.8)
      if isCompleted {
        Circle()
          .fill(color)
        Image(systemName: "checkmark")
          .font(.system(size: ScheduleUITokens.Icon.scheduleItemAccessoryFontSize, weight: .bold))
          .foregroundStyle(.white)
      }
    }
    .frame(
      width: ScheduleUITokens.DayPanelRow.taskMarkerSize,
      height: ScheduleUITokens.DayPanelRow.taskMarkerSize
    )
  }
}

struct ScheduleMonthDayDragPreviewRow: View {
  let item: ScheduleMonthItem
  let color: Color

  var body: some View {
    HStack(spacing: 7) {
      if itemIsTask {
        ScheduleMonthDayTaskMarker(color: color, isCompleted: item.isCompleted)
      }
      Text(item.title)
        .font(.system(size: ScheduleUITokens.DayPanelRow.titleFontSize, weight: .semibold))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, itemIsCalendar ? ScheduleUITokens.DayPanelRow.allDayCalendarHorizontalPadding : 0)
    .frame(height: ScheduleUITokens.DayPanelRow.allDayRowHeight)
    .background {
      if itemIsCalendar {
        RoundedRectangle(cornerRadius: ScheduleUITokens.DayPanelRow.allDayCornerRadius, style: .continuous)
          .fill(color.opacity(
            item.isBackgroundCalendar
              ? ScheduleUITokens.EventBlock.dayPanelBackgroundCalendarFillOpacity
              : ScheduleUITokens.EventBlock.dayPanelCalendarFillOpacity
          ))
      }
    }
    .opacity(ScheduleUITokens.DayPanelRow.dragPreviewOpacity)
    .allowsHitTesting(false)
  }

  private var itemIsTask: Bool {
    if case .workspaceTask = item.source { return true }
    return false
  }

  private var itemIsCalendar: Bool {
    if case .calendarEvent = item.source { return true }
    return false
  }
}

struct ScheduleMonthDayTimedDragPreviewBlock: View {
  let item: ScheduleMonthItem
  let color: Color

  var body: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: ScheduleUITokens.DayPanelRow.timedCornerRadius, style: .continuous)
        .fill(color.opacity(ScheduleUITokens.EventBlock.dayPanelDragPreviewFillOpacity))
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(color)
            .frame(width: ScheduleUITokens.DayPanelRow.colorStripeWidth)
        }

      HStack(alignment: .top, spacing: 7) {
        if itemIsTask {
          ScheduleMonthDayTaskMarker(color: color, isCompleted: item.isCompleted)
            .frame(
              width: ScheduleUITokens.DayPanelRow.dragPreviewMarkerSize,
              height: ScheduleUITokens.DayPanelRow.dragPreviewMarkerSize
            )
        }
        Text(item.title)
          .font(.system(size: ScheduleUITokens.DayPanelRow.titleFontSize, weight: .semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, ScheduleUITokens.DayPanelRow.horizontalPadding)
      .padding(.vertical, ScheduleUITokens.DayPanelRow.verticalPadding)
    }
    .opacity(ScheduleUITokens.DayPanelRow.dragPreviewOpacity)
    .allowsHitTesting(false)
  }

  private var itemIsTask: Bool {
    if case .workspaceTask = item.source { return true }
    return false
  }
}
