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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(item.isCompleted ? .secondary : .primary)
            .lineLimit(1)

          Spacer(minLength: 0)
        }
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, itemIsCalendar ? 8 : 0)
    .frame(height: 24)
    .background {
      if itemIsCalendar {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(color.opacity(item.isBackgroundCalendar ? 0.16 : 0.24))
      }
    }
    .contentShape(Rectangle())
    .opacity(isInteracting ? 0.22 : opacity)
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
      .frame(width: 26, height: 24)
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
    item.isCompleted || item.isBackgroundCalendar ? 0.45 : 1
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
              .padding(.top, 1)
          }

          VStack(alignment: .leading, spacing: 2) {
            Text(layout.item.title)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(layout.item.isCompleted ? .secondary : .primary)
              .lineLimit(2)

            if let subtitle = layout.item.subtitle, !subtitle.isEmpty, layout.height >= 52 {
              Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if layout.height >= 68 {
              Text(timeText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture(perform: onOpen)

          Spacer(minLength: 0)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)

      if canResize && allowsStartResize {
        resizeHandle(edge: .start)
          .frame(maxHeight: .infinity, alignment: .top)
      }

      if canResize && allowsEndResize {
        resizeHandle(edge: .end)
          .frame(maxHeight: .infinity, alignment: .bottom)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .opacity(isInteracting ? 0.22 : baseOpacity)
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
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(color.opacity(layout.item.isCompleted ? 0.08 : 0.16))
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(color)
            .frame(width: 3)
        }
    case .calendarEvent:
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(color.opacity(layout.item.isBackgroundCalendar ? 0.12 : 0.2))
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(color.opacity(0.95))
            .frame(width: 3)
        }
    }
  }

  private var openHitArea: some View {
    HStack(spacing: 0) {
      if itemIsTask {
        Color.clear
          .frame(width: 34)
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
      .frame(width: 26, height: 24)
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
      .frame(height: 10)
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
    layout.item.isCompleted || layout.item.isBackgroundCalendar ? 0.45 : 1
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
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(.white)
      }
    }
    .frame(width: 16, height: 16)
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
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, itemIsCalendar ? 8 : 0)
    .frame(height: 24)
    .background {
      if itemIsCalendar {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(color.opacity(item.isBackgroundCalendar ? 0.12 : 0.2))
      }
    }
    .opacity(0.72)
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
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(color.opacity(0.18))
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(color)
            .frame(width: 3)
        }

      HStack(alignment: .top, spacing: 7) {
        if itemIsTask {
          ScheduleMonthDayTaskMarker(color: color, isCompleted: item.isCompleted)
            .frame(width: 18, height: 18)
        }
        Text(item.title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
    }
    .opacity(0.72)
    .allowsHitTesting(false)
  }

  private var itemIsTask: Bool {
    if case .workspaceTask = item.source { return true }
    return false
  }
}
