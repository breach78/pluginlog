import AppKit
import QuartzCore

@MainActor
struct ProjectTaskListAnimationCoordinator {
  func applyShellFrames(
    rowOrder: [UUID],
    shellViews: [UUID: ProjectTaskRetainedListShellView],
    shellFrames: [UUID: CGRect],
    rowFrames: [UUID: CGRect],
    overlayView: ProjectTaskRetainedListOverlayView,
    motionQuality: MotionQuality,
    affectedRange: Range<Int>? = nil,
    instantTaskIDs: Set<UUID> = []
  ) {
    let effectiveRowOrder: [UUID] =
      affectedRange.map { range in
        let rangeTaskIDs = Set(rowOrder[max(0, range.lowerBound)..<min(rowOrder.count, range.upperBound)])
          .union(instantTaskIDs)
        return rowOrder.filter { rangeTaskIDs.contains($0) }
      } ?? rowOrder

    let applyFrames = {
      for taskID in effectiveRowOrder {
        guard
          let shellView = shellViews[taskID],
          let targetFrame = shellFrames[taskID]
        else { continue }

        if shellView.frame.integral != targetFrame.integral {
          shellView.frame = targetFrame
        }
      }
      overlayView.rowFrames = rowFrames
    }

    guard motionQuality.allowsAnimation else {
      applyFrames()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = animationDuration(for: motionQuality)
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      for taskID in effectiveRowOrder {
        guard
          let shellView = shellViews[taskID],
          let targetFrame = shellFrames[taskID]
        else { continue }

        if instantTaskIDs.contains(taskID) {
          if shellView.frame.integral != targetFrame.integral {
            shellView.frame = targetFrame
          }
          continue
        }

        if shellView.frame.integral != targetFrame.integral {
          shellView.animator().frame = targetFrame
        }
      }
    }
    overlayView.rowFrames = rowFrames
  }

  private func animationDuration(for quality: MotionQuality) -> TimeInterval {
    switch quality {
    case .full:
      return 0.24
    case .reduced:
      return 0.14
    case .minimal:
      return 0.08
    case .disabled:
      return 0
    }
  }
}
