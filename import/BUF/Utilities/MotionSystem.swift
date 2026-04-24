import SwiftUI

enum MotionSurfaceTier: String, CaseIterable, Sendable {
  case hotPath
  case localTransition
  case overlay
  case presentation
}

enum MotionQuality: String, CaseIterable, Sendable {
  case full
  case reduced
  case minimal
  case disabled

  var allowsAnimation: Bool {
    self != .disabled
  }
}

enum MotionToken: String, CaseIterable, Sendable {
  case selectionMove
  case localRevealExpand
  case localRevealCollapse
  case overlayFade
  case panelSlide
  case hoverFade
  case interactionPreview
  case interactionCommit
  case highlightPulseIn
  case highlightPulseOut
  case scrollToTarget
}

struct MotionContext: Equatable, Sendable {
  let tier: MotionSurfaceTier
  var isTyping: Bool = false
  var isScrolling: Bool = false
  var isDragging: Bool = false
  var isHovering: Bool = false

  init(
    tier: MotionSurfaceTier,
    isTyping: Bool = false,
    isScrolling: Bool = false,
    isDragging: Bool = false,
    isHovering: Bool = false
  ) {
    self.tier = tier
    self.isTyping = isTyping
    self.isScrolling = isScrolling
    self.isDragging = isDragging
    self.isHovering = isHovering
  }
}

enum MotionSystem {
  static func quality(for context: MotionContext) -> MotionQuality {
    if context.isTyping {
      switch context.tier {
      case .presentation:
        return .minimal
      case .overlay:
        return .minimal
      case .hotPath, .localTransition:
        return .disabled
      }
    }

    if context.isDragging {
      switch context.tier {
      case .presentation:
        return .reduced
      case .overlay:
        return .minimal
      case .hotPath, .localTransition:
        return .minimal
      }
    }

    if context.isScrolling {
      switch context.tier {
      case .presentation:
        return .reduced
      case .overlay:
        return .minimal
      case .hotPath:
        return .disabled
      case .localTransition:
        return .reduced
      }
    }

    if context.isHovering {
      switch context.tier {
      case .overlay:
        return .reduced
      case .hotPath, .localTransition, .presentation:
        return .full
      }
    }

    return .full
  }

  static func animation(
    for token: MotionToken,
    quality: MotionQuality = .full
  ) -> Animation? {
    guard quality.allowsAnimation else { return nil }

    switch (token, quality) {
    case (.selectionMove, .full):
      return .easeOut(duration: 0.14)
    case (.selectionMove, .reduced):
      return .easeOut(duration: 0.1)
    case (.selectionMove, .minimal):
      return .linear(duration: 0.08)

    case (.localRevealExpand, .full):
      return .spring(response: 0.26, dampingFraction: 0.84)
    case (.localRevealExpand, .reduced):
      return .easeOut(duration: 0.18)
    case (.localRevealExpand, .minimal):
      return .linear(duration: 0.12)

    case (.localRevealCollapse, .full):
      return .spring(response: 0.22, dampingFraction: 0.9)
    case (.localRevealCollapse, .reduced):
      return .easeOut(duration: 0.14)
    case (.localRevealCollapse, .minimal):
      return .linear(duration: 0.1)

    case (.overlayFade, .full):
      return .easeOut(duration: 0.12)
    case (.overlayFade, .reduced):
      return .easeOut(duration: 0.09)
    case (.overlayFade, .minimal):
      return .linear(duration: 0.06)

    case (.panelSlide, .full):
      return .easeInOut(duration: 0.2)
    case (.panelSlide, .reduced):
      return .easeOut(duration: 0.16)
    case (.panelSlide, .minimal):
      return .linear(duration: 0.1)

    case (.hoverFade, .full):
      return .easeOut(duration: 0.12)
    case (.hoverFade, .reduced):
      return .easeOut(duration: 0.08)
    case (.hoverFade, .minimal):
      return .linear(duration: 0.05)

    case (.interactionPreview, .full):
      return .spring(response: 0.24, dampingFraction: 0.86)
    case (.interactionPreview, .reduced):
      return .easeOut(duration: 0.14)
    case (.interactionPreview, .minimal):
      return .linear(duration: 0.08)

    case (.interactionCommit, .full):
      return .spring(response: 0.25, dampingFraction: 0.8)
    case (.interactionCommit, .reduced):
      return .easeOut(duration: 0.16)
    case (.interactionCommit, .minimal):
      return .linear(duration: 0.1)

    case (.highlightPulseIn, .full):
      return .easeInOut(duration: 0.18)
    case (.highlightPulseIn, .reduced):
      return .easeOut(duration: 0.12)
    case (.highlightPulseIn, .minimal):
      return .linear(duration: 0.08)

    case (.highlightPulseOut, .full):
      return .easeOut(duration: 0.45)
    case (.highlightPulseOut, .reduced):
      return .easeOut(duration: 0.24)
    case (.highlightPulseOut, .minimal):
      return .linear(duration: 0.12)

    case (.scrollToTarget, .full):
      return .easeInOut(duration: 0.22)
    case (.scrollToTarget, .reduced):
      return .easeOut(duration: 0.16)
    case (.scrollToTarget, .minimal):
      return .linear(duration: 0.1)

    case (_, .disabled):
      return nil
    }
  }
}
