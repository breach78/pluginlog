import AppKit
import SwiftUI

struct OverlaySurfaceStyle: Equatable, Sendable {
  let cornerRadius: CGFloat
  let fillOpacity: Double
  let strokeOpacity: Double
  let strokeWidth: CGFloat
  let shadowOpacity: Double
  let shadowRadius: CGFloat
  let shadowX: CGFloat
  let shadowY: CGFloat
  let useCompositingGroup: Bool

  static func card(
    quality: MotionQuality = .full
  ) -> OverlaySurfaceStyle {
    switch quality {
    case .full:
      return OverlaySurfaceStyle(
        cornerRadius: 12,
        fillOpacity: 0.985,
        strokeOpacity: 0.18,
        strokeWidth: 0.8,
        shadowOpacity: 0.12,
        shadowRadius: 10,
        shadowX: 0,
        shadowY: 5,
        useCompositingGroup: true
      )
    case .reduced:
      return OverlaySurfaceStyle(
        cornerRadius: 12,
        fillOpacity: 0.985,
        strokeOpacity: 0.16,
        strokeWidth: 0.8,
        shadowOpacity: 0.08,
        shadowRadius: 6,
        shadowX: 0,
        shadowY: 3,
        useCompositingGroup: false
      )
    case .minimal:
      return OverlaySurfaceStyle(
        cornerRadius: 12,
        fillOpacity: 0.985,
        strokeOpacity: 0.14,
        strokeWidth: 0.7,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowX: 0,
        shadowY: 0,
        useCompositingGroup: false
      )
    case .disabled:
      return OverlaySurfaceStyle(
        cornerRadius: 12,
        fillOpacity: 0.985,
        strokeOpacity: 0.14,
        strokeWidth: 0.7,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowX: 0,
        shadowY: 0,
        useCompositingGroup: false
      )
    }
  }

  static func lightweight(
    quality: MotionQuality = .full
  ) -> OverlaySurfaceStyle {
    switch quality {
    case .full:
      return OverlaySurfaceStyle(
        cornerRadius: 8,
        fillOpacity: 0.98,
        strokeOpacity: 0.14,
        strokeWidth: 0.7,
        shadowOpacity: 0.08,
        shadowRadius: 4,
        shadowX: 0,
        shadowY: 2,
        useCompositingGroup: false
      )
    case .reduced, .minimal, .disabled:
      return OverlaySurfaceStyle(
        cornerRadius: 8,
        fillOpacity: 0.98,
        strokeOpacity: 0.12,
        strokeWidth: 0.7,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowX: 0,
        shadowY: 0,
        useCompositingGroup: false
      )
    }
  }
}

private struct OverlaySurfaceModifier: ViewModifier {
  let cornerRadius: CGFloat
  let fillColor: Color
  let strokeColor: Color
  let style: OverlaySurfaceStyle

  @ViewBuilder
  func body(content: Content) -> some View {
    let decorated = content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(fillColor.opacity(style.fillOpacity))
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(strokeColor.opacity(style.strokeOpacity), lineWidth: style.strokeWidth)
      }
      .shadow(
        color: .black.opacity(style.shadowOpacity),
        radius: style.shadowRadius,
        x: style.shadowX,
        y: style.shadowY
      )

    if style.useCompositingGroup {
      decorated.compositingGroup()
    } else {
      decorated
    }
  }
}

extension View {
  func overlaySurface(
    cornerRadius: CGFloat,
    fillColor: Color = Color(nsColor: .windowBackgroundColor),
    strokeColor: Color = .secondary,
    style: OverlaySurfaceStyle
  ) -> some View {
    modifier(
      OverlaySurfaceModifier(
        cornerRadius: cornerRadius,
        fillColor: fillColor,
        strokeColor: strokeColor,
        style: style
      ))
  }
}
