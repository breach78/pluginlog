import AppKit
import SwiftUI

private struct ScheduleBackgroundStripeOverlay: View {
  let lineColor: Color

  var body: some View {
    GeometryReader { proxy in
      Canvas { context, size in
        var path = Path()
        let spacing: CGFloat = 9
        let diagonal = size.height + 24
        var startX: CGFloat = -size.height

        while startX <= size.width + size.height {
          path.move(to: CGPoint(x: startX, y: size.height))
          path.addLine(to: CGPoint(x: startX + diagonal, y: 0))
          startX += spacing
        }

        context.stroke(path, with: .color(lineColor), lineWidth: 1.3)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .allowsHitTesting(false)
  }
}

struct ScheduleRoundedRectangleStrokeOverlay: View {
  let cornerRadius: CGFloat
  let color: Color
  let lineWidth: CGFloat
  let lineCap: CGLineCap
  let dash: [CGFloat]

  init(
    cornerRadius: CGFloat,
    color: Color,
    lineWidth: CGFloat,
    lineCap: CGLineCap = .butt,
    dash: [CGFloat] = []
  ) {
    self.cornerRadius = cornerRadius
    self.color = color
    self.lineWidth = lineWidth
    self.lineCap = lineCap
    self.dash = dash
  }

  var body: some View {
    Canvas { context, size in
      guard lineWidth > 0, size.width > lineWidth, size.height > lineWidth else { return }
      let inset = lineWidth / 2
      let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
      guard rect.width > 0, rect.height > 0 else { return }
      let path = Path(roundedRect: rect, cornerRadius: max(0, cornerRadius - inset))
      let style = StrokeStyle(
        lineWidth: lineWidth,
        lineCap: lineCap,
        lineJoin: .round,
        dash: dash
      )
      context.stroke(path, with: .color(color), style: style)
    }
    .allowsHitTesting(false)
  }
}

struct ScheduleCircleStrokeOverlay: View {
  let color: Color
  let lineWidth: CGFloat
  let lineCap: CGLineCap
  let dash: [CGFloat]

  init(
    color: Color,
    lineWidth: CGFloat,
    lineCap: CGLineCap = .butt,
    dash: [CGFloat] = []
  ) {
    self.color = color
    self.lineWidth = lineWidth
    self.lineCap = lineCap
    self.dash = dash
  }

  var body: some View {
    Canvas { context, size in
      guard lineWidth > 0, size.width > lineWidth, size.height > lineWidth else { return }
      let inset = lineWidth / 2
      let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
      guard rect.width > 0, rect.height > 0 else { return }
      let style = StrokeStyle(
        lineWidth: lineWidth,
        lineCap: lineCap,
        lineJoin: .round,
        dash: dash
      )
      context.stroke(Path(ellipseIn: rect), with: .color(color), style: style)
    }
    .allowsHitTesting(false)
  }
}

struct ScheduleTaskBlockSurface<Content: View>: View {
  let color: Color
  let isSelected: Bool
  let isCompleted: Bool
  let isPreparationSlot: Bool
  let selectionHighlightColor: Color
  private let content: Content

  init(
    color: Color,
    isSelected: Bool,
    isCompleted: Bool,
    isPreparationSlot: Bool,
    selectionHighlightColor: Color,
    @ViewBuilder content: () -> Content
  ) {
    self.color = color
    self.isSelected = isSelected
    self.isCompleted = isCompleted
    self.isPreparationSlot = isPreparationSlot
    self.selectionHighlightColor = selectionHighlightColor
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    let baseFillOpacity: Double = {
      if isPreparationSlot {
        return isCompleted ? 0.14 : 0.2
      }
      return isCompleted ? 0.14 : 0.22
    }()
    let selectionFillOpacity = isSelected ? (isCompleted ? 0.12 : 0.18) : 0
    let selectionStrokeOpacity = isSelected ? (isCompleted ? 0.22 : 0.34) : 0
    let strokeOpacity = isSelected ? 0.98 : selectionStrokeOpacity

    shape
      .fill(isSelected ? color.opacity(isCompleted ? 0.72 : 0.95) : color.opacity(baseFillOpacity))
      .overlay {
        shape
          .fill(selectionHighlightColor.opacity(isSelected ? 0 : selectionFillOpacity))
          .overlay {
            if strokeOpacity > 0 {
              ScheduleRoundedRectangleStrokeOverlay(
                cornerRadius: 6,
                color: color.opacity(strokeOpacity),
                lineWidth: 1
              )
            }
          }
      }
      .overlay {
        content
      }
  }
}

struct ScheduleEventBlockSurface<Content: View>: View {
  let color: Color
  let isBackgroundCalendar: Bool
  private let content: Content

  init(
    color: Color,
    isBackgroundCalendar: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.color = color
    self.isBackgroundCalendar = isBackgroundCalendar
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    shape
      .fill(color.opacity(isBackgroundCalendar ? 0.08 : 0.14))
      .overlay {
        if isBackgroundCalendar {
          ScheduleBackgroundStripeOverlay(lineColor: Color.white.opacity(0.5))
            .clipShape(shape)
        }
      }
      .overlay(alignment: .leading) {
        if !isBackgroundCalendar {
          Rectangle()
            .fill(color.opacity(0.88))
            .frame(width: 3)
        }
      }
      .clipShape(shape)
      .overlay {
        content
      }
  }
}

struct ScheduleTaskChipSurface<Content: View>: View {
  let color: Color
  let isSelected: Bool
  let isPreparationSlot: Bool
  let selectionHighlightColor: Color
  private let content: Content

  init(
    color: Color,
    isSelected: Bool,
    isPreparationSlot: Bool,
    selectionHighlightColor: Color,
    @ViewBuilder content: () -> Content
  ) {
    self.color = color
    self.isSelected = isSelected
    self.isPreparationSlot = isPreparationSlot
    self.selectionHighlightColor = selectionHighlightColor
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    let baseFillColor =
      isPreparationSlot ? color.opacity(0.11) : Color(nsColor: .controlBackgroundColor)
    let selectionFillOpacity = isSelected ? 0.16 : 0
    let selectionStrokeOpacity = isSelected ? 0.28 : 0
    let strokeOpacity = isSelected ? 0.98 : selectionStrokeOpacity

    shape
      .fill(isSelected ? color.opacity(0.95) : baseFillColor)
      .overlay {
        shape
          .fill(selectionHighlightColor.opacity(isSelected ? 0 : selectionFillOpacity))
          .overlay {
            if strokeOpacity > 0 {
              ScheduleRoundedRectangleStrokeOverlay(
                cornerRadius: 10,
                color: color.opacity(strokeOpacity),
                lineWidth: 1
              )
            }
          }
      }
      .overlay {
        content
      }
  }
}

struct ScheduleEventChipSurface<Content: View>: View {
  let color: Color
  let isBackgroundCalendar: Bool
  private let content: Content

  init(
    color: Color,
    isBackgroundCalendar: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.color = color
    self.isBackgroundCalendar = isBackgroundCalendar
    self.content = content()
  }

  var body: some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(color.opacity(isBackgroundCalendar ? 0.07 : 0.14))
      .overlay {
        if isBackgroundCalendar {
          ScheduleBackgroundStripeOverlay(lineColor: Color.white.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
      }
      .overlay {
        content
      }
  }
}
