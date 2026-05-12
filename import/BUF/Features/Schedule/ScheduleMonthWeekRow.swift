import SwiftUI

struct ScheduleMonthWeekRow: View {
  let layout: ScheduleMonthWeekLayout
  let today: Date
  let visibleItemLimit: Int
  let selectedDate: Date?
  @State private var activeDragDate: Date?
  @State private var activeDragFeedback: ScheduleMonthDragFeedback?
  let calendar: Calendar
  let gridLineColor: Color
  let gridLineWidth: CGFloat
  let externalDragTargetDate: Date?
  let onSelectDay: (Date, [ScheduleMonthItem]) -> Void
  let onToggleTaskCompletion: (UUID, UUID, Bool) -> Void
  let onMoveItem: (ScheduleMonthDragItem, ScheduleInteractionTarget) -> Void
  let externalDayDropTarget: ScheduleMonthDropTarget?
  let onRowDropTargetsChanged: (Date, [ScheduleMonthDropTarget]) -> Void
  @State private var rowFrameInScreen: CGRect = .null

  private var visibleAllDaySegments: [ScheduleMonthAllDaySpanSegment] {
    layout.allDaySegments.filter { $0.rowIndex < visibleAllDayRowLimit }
  }

  private var visibleAllDayRowLimit: Int {
    max(0, visibleItemLimit)
  }

  private var rowCoordinateSpaceName: String {
    "schedule-month-week-\(layout.weekStart.timeIntervalSinceReferenceDate)"
  }

  var body: some View {
    GeometryReader { rowProxy in
      let rowSize = rowProxy.size
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
          ForEach(0..<layout.days.count, id: \.self) { dayIndex in
            let dayLayout = layout.days[dayIndex]

            ScheduleMonthDayCell(
              day: dayLayout.day,
              monthStart: layout.monthStart,
              today: today,
              items: dayLayout.inlineItems,
              visibleItemLimit: inlineVisibleItemLimit(on: dayIndex),
              hiddenAllDayItemCount: hiddenAllDayItemCount(on: dayIndex),
              reservedAllDayRowCount: visibleAllDayRowCount(on: dayIndex),
              isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: dayLayout.day) } ?? false,
              isDragTarget: isDragTarget(dayLayout.day),
              weekStart: layout.weekStart,
              rowSize: rowSize,
              rowCoordinateSpaceName: rowCoordinateSpaceName,
              rowFrameInScreen: rowFrameInScreen,
              activeDragDate: $activeDragDate,
              activeDragFeedback: $activeDragFeedback,
              calendar: calendar,
              onSelect: {
                onSelectDay(dayLayout.normalizedDay, dayLayout.allItems)
              },
              onToggleTaskCompletion: onToggleTaskCompletion,
              onMoveItem: onMoveItem,
              externalDayDropTarget: externalDayDropTarget
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }

        let columnWidth = rowSize.width / 7
        ForEach(visibleAllDaySegments) { segment in
          if segment.startDayIndex < layout.days.count {
            let segmentDay = layout.days[segment.startDayIndex]
            let width = max(0, columnWidth * CGFloat(segment.daySpanCount) - 4)
            let x = columnWidth * CGFloat(segment.startDayIndex) + width / 2 + 2
            let y = ScheduleMonthLayoutMetrics.allDaySpanTopOffset
              + CGFloat(segment.rowIndex) * ScheduleMonthLayoutMetrics.allDaySpanRowHeight
              + ScheduleMonthLayoutMetrics.allDaySpanHeight / 2

            ScheduleMonthAllDaySpanRow(segment: segment)
              .modifier(
                ScheduleMonthLocalDragModifier(
                  item: segment.item,
                  weekStart: layout.weekStart,
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
                TapGesture().onEnded {
                  onSelectDay(segmentDay.normalizedDay, segmentDay.allItems)
                }
              )
              .frame(width: width, height: ScheduleMonthLayoutMetrics.allDaySpanHeight)
              .position(x: x, y: y)
          }
        }

        ScheduleMonthWeekGridLines(
          color: gridLineColor,
          lineWidth: gridLineWidth
        )
        .allowsHitTesting(false)

        if let feedback = activeDragFeedback, feedback.weekStart == layout.weekStart {
          ScheduleMonthDragFeedbackMarker(feedback: feedback)
            .position(x: feedback.location.x, y: feedback.location.y)
            .allowsHitTesting(false)
        }
      }
      .coordinateSpace(name: rowCoordinateSpaceName)
      .background(
        ScheduleScreenFrameReporter { frame in
          rowFrameInScreen = frame
          onRowDropTargetsChanged(layout.weekStart, dropTargets(rowFrame: frame))
        }
      )
    }
    .onDisappear {
      onRowDropTargetsChanged(layout.weekStart, [])
    }
    .zIndex(activeDragFeedback == nil ? 0 : 1)
  }

  private func dropTargets(rowFrame: CGRect) -> [ScheduleMonthDropTarget] {
    guard !rowFrame.isNull, rowFrame.width > 0, rowFrame.height > 0 else { return [] }
    let columnWidth = rowFrame.width / CGFloat(max(1, layout.days.count))
    return layout.days.enumerated().map { dayIndex, dayLayout in
      ScheduleMonthDropTarget(
        day: calendar.startOfDay(for: dayLayout.day),
        frame: CGRect(
          x: rowFrame.minX + columnWidth * CGFloat(dayIndex),
          y: rowFrame.minY,
          width: columnWidth,
          height: rowFrame.height
        )
      )
    }
  }

  private func inlineVisibleItemLimit(on dayIndex: Int) -> Int {
    max(0, visibleItemLimit - visibleAllDayRowCount(on: dayIndex))
  }

  private func isDragTarget(_ day: Date) -> Bool {
    activeDragDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
      || externalDragTargetDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
  }

  private func visibleAllDayRowCount(on dayIndex: Int) -> Int {
    ScheduleMonthSpanLayout.visibleAllDayRowCount(
      on: dayIndex,
      segments: layout.allDaySegments,
      visibleRowLimit: visibleAllDayRowLimit
    )
  }

  private func hiddenAllDayItemCount(on dayIndex: Int) -> Int {
    ScheduleMonthSpanLayout.hiddenAllDayItemCount(
      on: dayIndex,
      segments: layout.allDaySegments,
      visibleRowLimit: visibleAllDayRowLimit
    )
  }
}

struct ScheduleMonthHorizontalGridLine: View {
  let color: Color
  let lineWidth: CGFloat

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color(nsColor: .windowBackgroundColor))
      Rectangle()
        .fill(color)
    }
    .frame(height: lineWidth)
  }
}

private struct ScheduleMonthWeekGridLines: View {
  let color: Color
  let lineWidth: CGFloat

  var body: some View {
    Canvas { context, size in
      let y = lineWidth / 2
      let columnWidth = size.width / 7
      var path = Path()

      for columnIndex in 1..<7 {
        let x = columnWidth * CGFloat(columnIndex)
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
      }

      path.move(to: CGPoint(x: 0, y: y))
      path.addLine(to: CGPoint(x: size.width, y: y))

      context.stroke(
        path,
        with: .color(Color(nsColor: .windowBackgroundColor)),
        lineWidth: lineWidth
      )
      context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }
  }
}
