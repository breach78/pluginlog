import AppKit
import SwiftUI

extension ScheduleBoardView {
  var scheduleBoardLeftAxisSection: some View {
    leftAxisContent
  }

  var scheduleBoardInteractionOverlaySection: some View {
    floatingInteractionOverlay()
  }

  func scheduleTimedGridSection(
    timedEntries: [ScheduleTimedBlockLayout],
    backgroundTimedEntries: [ScheduleTimedBlockLayout]
  ) -> some View {
    boardContent(
      timedEntries: timedEntries,
      backgroundTimedEntries: backgroundTimedEntries
    )
  }

  func boardContent(
    timedEntries: [ScheduleTimedBlockLayout],
    backgroundTimedEntries: [ScheduleTimedBlockLayout]
  ) -> some View {
    HStack(spacing: 0) {
      Color.clear
        .frame(width: titleColumnWidth, height: boardHeight)

      VStack(spacing: 0) {
        Color.clear
          .frame(width: dayColumnsWidth, height: headerHeight)

        ZStack(alignment: .topLeading) {
          gridBackground

          ForEach(backgroundTimedEntries) { layout in
            timedBlock(layout)
              .allowsHitTesting(false)
          }

          currentTimeIndicator
            .allowsHitTesting(false)

          ForEach(timedEntries) { layout in
            timedBlock(layout)
          }
        }
        .frame(width: dayColumnsWidth, height: timeGridHeight, alignment: .topLeading)
        .clipped()
      }
      .frame(width: dayColumnsWidth, height: boardHeight, alignment: .topLeading)
    }
    .frame(width: boardWidth, height: boardHeight, alignment: .topLeading)
  }

  var leftAxisContent: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        Color.clear
          .frame(height: dateHeaderHeight)

        HStack {
          Text("All-day")
            .font(.system(size: ScheduleUITokens.Board.allDayAxisLabelFontSize, weight: .medium))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.trailing, ScheduleUITokens.Board.axisLabelTrailingPadding)
        }
        .frame(
          maxWidth: .infinity,
          minHeight: allDayRailVisibleHeight,
          maxHeight: allDayRailVisibleHeight,
          alignment: .trailing
        )
        .background(Color.clear)
      }
      .background(
        Rectangle()
          .fill(Color(nsColor: .windowBackgroundColor).opacity(
            ScheduleUITokens.Board.allDayAxisBackgroundOpacity
          ))
      )

      VStack(spacing: 0) {
        ForEach(0..<hourCount, id: \.self) { hour in
          HStack {
            Text(hourLabel(hour))
              .font(.system(
                size: ScheduleUITokens.Board.timeAxisLabelFontSize,
                weight: .medium,
                design: .monospaced
              ))
              .foregroundStyle(.secondary)
              .padding(.top, ScheduleUITokens.Board.timeAxisLabelTopPadding)
              .padding(.trailing, ScheduleUITokens.Board.timeAxisLabelTrailingPadding)
          }
          .frame(
            maxWidth: .infinity,
            minHeight: hourHeight,
            maxHeight: hourHeight,
            alignment: .topTrailing
          )
        }
      }
      .background(
        Rectangle()
          .fill(Color(nsColor: .windowBackgroundColor).opacity(
            ScheduleUITokens.Board.timeAxisBackgroundOpacity
          ))
      )
    }
    .overlay(alignment: .topLeading) {
      currentTimeAxisLabel
        .allowsHitTesting(false)
    }
    .frame(width: titleColumnWidth, height: boardHeight, alignment: .top)
  }

  var scheduleTimedQuickAddSection: some View {
    ScheduleQuickAddContextMenuRegion(
      isAllDayRegion: false,
      canCreateTask: scheduleQuickAddProjectID != nil,
      projects: scheduleQuickAddProjects,
      defaultProjectID: scheduleQuickAddProjectID,
      onCreateTask: createScheduleTask,
      onUnavailable: { handleUnavailableScheduleQuickAdd() },
      onBackgroundTap: handleScheduleBackgroundTap,
      allowsTimedDragCreation: true,
      onTimedDragPreview: updateTimedQuickCreateSelection,
      onTimedDragCommit: commitTimedQuickCreateSelection,
      onTimedDragCancel: cancelTimedQuickCreateSelection
    )
  }

  var gridBackground: some View {
    ZStack(alignment: .topLeading) {
      scheduleTimedQuickAddSection
        .frame(width: dayColumnsWidth, height: timeGridHeight)

      ZStack(alignment: .topLeading) {
        Rectangle()
          .fill(Color(nsColor: .windowBackgroundColor))

        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
          Rectangle()
            .fill(dayColumnBackgroundColor(for: day, section: .timeline))
            .frame(width: dayColumnWidth, height: timeGridHeight)
            .offset(x: CGFloat(index) * dayColumnWidth)

          Rectangle()
            .fill(Color.primary.opacity(ScheduleUITokens.Board.gridLineOpacity))
            .frame(width: ScheduleUITokens.Board.gridLineWidth, height: timeGridHeight)
            .offset(x: CGFloat(index) * dayColumnWidth)
        }

        Rectangle()
          .fill(Color.primary.opacity(ScheduleUITokens.Board.gridLineOpacity))
          .frame(width: ScheduleUITokens.Board.gridLineWidth, height: timeGridHeight)
          .offset(x: dayColumnsWidth - 1)

        ForEach(0...hourCount, id: \.self) { hour in
          Rectangle()
            .fill(Color.primary.opacity(hour == 0 ? 0 : ScheduleUITokens.Board.gridLineOpacity))
            .frame(width: dayColumnsWidth, height: ScheduleUITokens.Board.gridLineWidth)
            .offset(y: CGFloat(hour) * hourHeight)
        }

        ForEach(0..<hourCount, id: \.self) { hour in
          Rectangle()
            .fill(Color.primary.opacity(ScheduleUITokens.Board.minorGridLineOpacity))
            .frame(width: dayColumnsWidth, height: ScheduleUITokens.Board.gridLineWidth)
            .offset(y: CGFloat(hour) * hourHeight + hourHeight / 2)
        }
      }
      .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  var currentTimeIndicator: some View {
    if isActive {
      ScheduleCurrentTimeIndicator(
        dayRange: dayRange,
        totalWidth: dayColumnsWidth,
        totalHeight: timeGridHeight,
        hourHeight: hourHeight,
        calendar: calendar
      )
    }
  }

  @ViewBuilder
  var currentTimeAxisLabel: some View {
    if isActive {
      ScheduleCurrentTimeAxisLabel(
        headerHeight: headerHeight,
        totalHeight: boardHeight,
        hourHeight: hourHeight,
        calendar: calendar
      )
    }
  }

}
