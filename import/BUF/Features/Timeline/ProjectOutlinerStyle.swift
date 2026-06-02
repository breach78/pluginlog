import AppKit
import SwiftUI

enum ProjectOutlineBlockColorPalette {
  struct Style {
    let backgroundColor: Color
    let nsTextColor: NSColor
  }

  static func name(for color: ProjectOutlineBlockColor) -> String {
    switch color {
    case .mist: "미스트"
    case .sage: "세이지"
    case .moss: "모스"
    case .sand: "샌드"
    case .clay: "클레이"
    case .rose: "로즈"
    case .dusk: "더스크"
    case .slate: "슬레이트"
    }
  }

  static func style(for color: ProjectOutlineBlockColor?) -> Style {
    guard let color else {
      return Style(backgroundColor: .clear, nsTextColor: .labelColor)
    }
    let rgb: (Double, Double, Double)
    switch color {
    case .mist: rgb = (0.78, 0.84, 0.87)
    case .sage: rgb = (0.74, 0.82, 0.74)
    case .moss: rgb = (0.55, 0.66, 0.53)
    case .sand: rgb = (0.84, 0.78, 0.65)
    case .clay: rgb = (0.72, 0.60, 0.53)
    case .rose: rgb = (0.78, 0.64, 0.66)
    case .dusk: rgb = (0.58, 0.58, 0.70)
    case .slate: rgb = (0.39, 0.45, 0.50)
    }
    return Style(
      backgroundColor: Color(red: rgb.0, green: rgb.1, blue: rgb.2).opacity(0.85),
      nsTextColor: contrastTextColor(red: rgb.0, green: rgb.1, blue: rgb.2)
    )
  }

  private static func contrastTextColor(red: Double, green: Double, blue: Double) -> NSColor {
    let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
    return luminance > 0.58 ? .black : .white
  }
}

let projectOutlinerFont = Font.custom("SansMonoCJKFinalDraft", size: 15)
let projectOutlinerChipFont = Font.custom("SansMonoCJKFinalDraft-Bold", size: 12)
let projectOutlinerBulletHitSize: CGFloat = 21
let projectOutlinerIndentWidth: CGFloat = 40
let projectOutlinerDropIndicatorBaseLeading: CGFloat = 40

@MainActor
var projectOutlinerNSFont: NSFont {
  guard let font = NSFont(name: "SansMonoCJKFinalDraft", size: 15) else {
    fatalError("Missing font: SansMonoCJKFinalDraft")
  }
  return font
}
