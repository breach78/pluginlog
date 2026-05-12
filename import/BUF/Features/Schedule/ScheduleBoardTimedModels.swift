import AppKit
import SwiftUI

enum ScheduleItemVisualStyle {
  static let titleFontSize: CGFloat = ScheduleUITokens.ScheduleItem.titleFontSize
  static let supplementalFontSize = ScheduleUITokens.ScheduleItem.supplementalFontSize
  static let secondaryTextOpacityMultiplier =
    ScheduleUITokens.ScheduleItem.secondaryTextOpacityMultiplier
}

struct ScheduleTimedEntry: Identifiable {
  let id: String
  let dayIndex: Int
  let startMinute: Int
  let durationMinutes: Int
  let endMinute: Int
  let sourceStartDay: Date
  let sourceStartMinute: Int
  let sourceDurationMinutes: Int
  let isFirstSegment: Bool
  let isLastSegment: Bool
  let title: String
  let subtitle: String?
  let color: Color
  let isTask: Bool
  let isPreparationSlot: Bool
  let targetCompletedWorkUnits: Int?
  let taskDescriptor: WorkspaceScheduleTaskDescriptor?
  let event: ScheduleCalendarEvent?
  let isBackgroundCalendar: Bool
  let contentTopOffset: CGFloat
}

struct ScheduleTimedBlockLayout: Identifiable {
  let id: String
  let entry: ScheduleTimedEntry
  let column: Int
  let columnCount: Int
  let columnSpan: Int

  func withContentTopOffset(_ offset: CGFloat) -> ScheduleTimedBlockLayout {
    ScheduleTimedBlockLayout(
      id: id,
      entry: ScheduleTimedEntry(
        id: entry.id,
        dayIndex: entry.dayIndex,
        startMinute: entry.startMinute,
        durationMinutes: entry.durationMinutes,
        endMinute: entry.endMinute,
        sourceStartDay: entry.sourceStartDay,
        sourceStartMinute: entry.sourceStartMinute,
        sourceDurationMinutes: entry.sourceDurationMinutes,
        isFirstSegment: entry.isFirstSegment,
        isLastSegment: entry.isLastSegment,
        title: entry.title,
        subtitle: entry.subtitle,
        color: entry.color,
        isTask: entry.isTask,
        isPreparationSlot: entry.isPreparationSlot,
        targetCompletedWorkUnits: entry.targetCompletedWorkUnits,
        taskDescriptor: entry.taskDescriptor,
        event: entry.event,
        isBackgroundCalendar: entry.isBackgroundCalendar,
        contentTopOffset: offset
      ),
      column: column,
      columnCount: columnCount,
      columnSpan: columnSpan
    )
  }
}

struct ScheduleBackgroundLabelAvoidanceBlock: Hashable {
  let dayIndex: Int
  let startMinute: Int
  let endMinute: Int
}

enum ScheduleBackgroundLabelAvoidancePolicy {
  static let estimatedLabelHeight: CGFloat = 44
  static let labelGap: CGFloat = 6

  static func topOffset(
    for background: ScheduleBackgroundLabelAvoidanceBlock,
    foregroundBlocks: [ScheduleBackgroundLabelAvoidanceBlock],
    hourHeight: CGFloat,
    labelHeight: CGFloat = estimatedLabelHeight,
    gap: CGFloat = labelGap
  ) -> CGFloat {
    guard hourHeight > 0, labelHeight > 0 else { return 0 }

    let backgroundStart = min(max(0, background.startMinute), 24 * 60)
    let backgroundEnd = min(max(backgroundStart, background.endMinute), 24 * 60)
    guard backgroundEnd > backgroundStart else { return 0 }

    let labelDurationMinutes = max(1, Int(ceil(labelHeight / hourHeight * 60)))
    let gapMinutes = max(0, Int(ceil(gap / hourHeight * 60)))
    let latestLabelStart = max(backgroundStart, backgroundEnd - labelDurationMinutes)
    guard latestLabelStart > backgroundStart else { return 0 }

    var candidateStart = backgroundStart
    let obstacles = foregroundBlocks
      .filter { block in
        block.dayIndex == background.dayIndex
          && block.startMinute < backgroundEnd
          && block.endMinute > backgroundStart
      }
      .sorted { lhs, rhs in
        if lhs.startMinute != rhs.startMinute {
          return lhs.startMinute < rhs.startMinute
        }
        return lhs.endMinute < rhs.endMinute
      }

    for obstacle in obstacles {
      if candidateStart + labelDurationMinutes <= obstacle.startMinute {
        break
      }
      if candidateStart < obstacle.endMinute {
        candidateStart = obstacle.endMinute + gapMinutes
      }
      if candidateStart > latestLabelStart {
        candidateStart = latestLabelStart
        break
      }
    }

    guard candidateStart > backgroundStart else { return 0 }
    return CGFloat(candidateStart - backgroundStart) / 60 * hourHeight
  }
}

enum ScheduleTimedBlockHitPriorityPolicy {
  private static let backgroundCalendarPriority = 1.0
  private static let calendarPriority = 2.0
  private static let taskPriority = 3.0
  private static let selectedTaskPriority = 4.0

  static func zIndex(
    isTask: Bool,
    taskID: UUID?,
    selectedTaskID: UUID?,
    startMinute: Int,
    isBackgroundCalendar: Bool
  ) -> Double {
    if isBackgroundCalendar {
      return backgroundCalendarPriority
    }
    if isTask {
      if let taskID, taskID == selectedTaskID {
        return selectedTaskPriority + earlierStartTieBreaker(startMinute)
      }
      return taskPriority + earlierStartTieBreaker(startMinute)
    }
    return calendarPriority + earlierStartTieBreaker(startMinute)
  }

  private static func earlierStartTieBreaker(_ startMinute: Int) -> Double {
    let boundedStartMinute = min(max(0, startMinute), 24 * 60)
    return Double((24 * 60) - boundedStartMinute) / 10_000
  }
}

enum ScheduleResizePreviewStylePolicy {
  static let targetBlockOpacity = ScheduleUITokens.Interaction.resizeTargetBlockOpacity

  static func sourceBlockOpacity(
    isResizing: Bool,
    isDragging: Bool,
    dragPlaceholderOpacity: Double = ScheduleUITokens.Interaction.dragSourcePlaceholderOpacity
  ) -> Double {
    if isResizing {
      return 0
    }
    return isDragging ? dragPlaceholderOpacity : 1
  }
}

enum ScheduleHiddenTimedItemIndicatorPolicy {
  static func visibleStartMinute(
    scrollOffsetY: CGFloat,
    hourHeight: CGFloat
  ) -> Int {
    guard hourHeight > 0 else { return 0 }
    let timelineOffsetY = max(0, scrollOffsetY)
    let rawMinute = Int(floor(timelineOffsetY / hourHeight * 60))
    return min(24 * 60, max(0, rawMinute))
  }

  static func hasHiddenTimedItem(
    visibleStartMinute: Int,
    endMinutes: [Int]
  ) -> Bool {
    guard visibleStartMinute > 0 else { return false }
    return endMinutes.contains { $0 <= visibleStartMinute }
  }

  static func earliestHiddenStartMinute(
    visibleStartMinute: Int,
    intervals: [(startMinute: Int, endMinute: Int)]
  ) -> Int? {
    guard visibleStartMinute > 0 else { return nil }

    return intervals
      .filter { $0.endMinute <= visibleStartMinute }
      .map(\.startMinute)
      .min()
  }

  static func hiddenDayIndexes(
    layouts: [ScheduleTimedBlockLayout],
    visibleStartMinute: Int
  ) -> Set<Int> {
    guard visibleStartMinute > 0 else { return [] }

    return Set(
      layouts.compactMap { layout in
        let entry = layout.entry
        return entry.endMinute <= visibleStartMinute ? entry.dayIndex : nil
      }
    )
  }

  static func earliestHiddenStartMinute(
    dayIndex: Int,
    layouts: [ScheduleTimedBlockLayout],
    visibleStartMinute: Int
  ) -> Int? {
    guard visibleStartMinute > 0 else { return nil }

    let intervals = layouts
      .compactMap { layout -> (startMinute: Int, endMinute: Int)? in
        let entry = layout.entry
        guard entry.dayIndex == dayIndex else { return nil }
        return (entry.startMinute, entry.endMinute)
      }

    return earliestHiddenStartMinute(
      visibleStartMinute: visibleStartMinute,
      intervals: intervals
    )
  }
}

struct ScheduleLayoutCache {
  let timedEntries: [ScheduleTimedBlockLayout]
  let allDayEntries: [ScheduleAllDayLayout]
  let backgroundTimedEntries: [ScheduleTimedBlockLayout]
  let backgroundAllDayEntries: [ScheduleAllDayLayout]
}

enum ScheduleDayBackgroundSection {
  case header
  case allDayRail
  case timeline
}

enum ScheduleTimedBlockDensity {
  case compact
  case standard
  case expanded
}
