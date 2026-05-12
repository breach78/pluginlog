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
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.trailing, 6)
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
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
      )

      VStack(spacing: 0) {
        ForEach(0..<hourCount, id: \.self) { hour in
          HStack {
            Text(hourLabel(hour))
              .font(.system(size: 10, weight: .medium, design: .monospaced))
              .foregroundStyle(.secondary)
              .padding(.top, 2)
              .padding(.trailing, 8)
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
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
      )
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
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: timeGridHeight)
            .offset(x: CGFloat(index) * dayColumnWidth)
        }

        Rectangle()
          .fill(Color.primary.opacity(0.08))
          .frame(width: 1, height: timeGridHeight)
          .offset(x: dayColumnsWidth - 1)

        ForEach(0...hourCount, id: \.self) { hour in
          Rectangle()
            .fill(Color.primary.opacity(hour == 0 ? 0 : 0.08))
            .frame(width: dayColumnsWidth, height: 1)
            .offset(y: CGFloat(hour) * hourHeight)
        }

        ForEach(0..<hourCount, id: \.self) { hour in
          Rectangle()
            .fill(Color.primary.opacity(0.02))
            .frame(width: dayColumnsWidth, height: 1)
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
        dayColumnWidth: dayColumnWidth,
        totalWidth: dayColumnsWidth,
        totalHeight: timeGridHeight,
        hourHeight: hourHeight,
        calendar: calendar
      )
    }
  }

}
