import AppKit
import SwiftUI

struct ScheduleBoardGlobalFramePreferenceKey: PreferenceKey {
  static let defaultValue: CGRect = .null

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

enum ScheduleBoardHostingInvalidationPolicy {
  static func boardContentVersion(
    today: Date,
    dayRange: ClosedRange<Int>,
    layoutSourceSignature: Int,
    selectedScheduleTaskID: UUID?,
    transientInteractionSignature: Int
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(today.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(layoutSourceSignature)
    hasher.combine(selectedScheduleTaskID)
    hasher.combine(transientInteractionSignature)
    return hasher.finalize()
  }

  static func pinnedTopVersion(
    today: Date,
    dayRange: ClosedRange<Int>,
    layoutSourceSignature: Int,
    calendarSourcesSignature: Int,
    selectedScheduleTaskID: UUID?,
    transientInteractionSignature _: Int
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(today.timeIntervalSinceReferenceDate)
    hasher.combine(dayRange.lowerBound)
    hasher.combine(dayRange.upperBound)
    hasher.combine(layoutSourceSignature)
    hasher.combine(calendarSourcesSignature)
    hasher.combine(selectedScheduleTaskID)
    return hasher.finalize()
  }
}

enum TaskTapSuppressionPolicy {
  static let completionControlDuration: TimeInterval = 0.2

  static func suppressedUntil(now: Date, duration: TimeInterval) -> Date {
    now.addingTimeInterval(duration)
  }

  static func shouldHandleTaskTap(now: Date, suppressedUntil: Date) -> Bool {
    now >= suppressedUntil
  }
}

@MainActor
func taskCompletionPressGesture(onPress: @escaping () -> Void) -> some Gesture {
  DragGesture(minimumDistance: 0)
    .onChanged { _ in onPress() }
}
