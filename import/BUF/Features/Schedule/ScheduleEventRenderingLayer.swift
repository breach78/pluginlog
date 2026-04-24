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
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    let baseFillOpacity: Double = {
      if isPreparationSlot {
        return isCompleted ? 0.14 : 0.2
      }
      return isCompleted ? 0.14 : 0.22
    }()
    let selectionFillOpacity = isSelected ? (isCompleted ? 0.12 : 0.18) : 0
    let selectionStrokeOpacity = isSelected ? (isCompleted ? 0.22 : 0.34) : 0

    shape
      .fill(isSelected ? color.opacity(isCompleted ? 0.72 : 0.95) : color.opacity(baseFillOpacity))
      .overlay {
        shape
          .fill(selectionHighlightColor.opacity(isSelected ? 0 : selectionFillOpacity))
          .overlay {
            shape
              .stroke(color.opacity(isSelected ? 0.98 : selectionStrokeOpacity), lineWidth: 1)
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
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(color.opacity(isBackgroundCalendar ? 0.08 : 0.18))
      .overlay {
        if isBackgroundCalendar {
          ScheduleBackgroundStripeOverlay(lineColor: Color.white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
      }
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
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    let baseFillColor =
      isPreparationSlot ? color.opacity(0.11) : Color(nsColor: .controlBackgroundColor)
    let selectionFillOpacity = isSelected ? 0.16 : 0
    let selectionStrokeOpacity = isSelected ? 0.28 : 0

    shape
      .fill(isSelected ? color.opacity(0.95) : baseFillColor)
      .overlay {
        shape
          .fill(selectionHighlightColor.opacity(isSelected ? 0 : selectionFillOpacity))
          .overlay {
            shape
              .stroke(color.opacity(isSelected ? 0.98 : selectionStrokeOpacity), lineWidth: 1)
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
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(color.opacity(isBackgroundCalendar ? 0.07 : 0.14))
      .overlay {
        if isBackgroundCalendar {
          ScheduleBackgroundStripeOverlay(lineColor: Color.white.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
      .overlay {
        content
      }
  }
}
