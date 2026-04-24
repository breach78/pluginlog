import SwiftUI

enum ScheduleAnimationEngine {
  static let selection = MotionSystem.animation(for: .selectionMove)
  static let handleHover = MotionSystem.animation(for: .hoverFade)
  static let interactionPreview = MotionSystem.animation(for: .interactionPreview)
  static let interactionCommit = MotionSystem.animation(for: .interactionCommit)
}
