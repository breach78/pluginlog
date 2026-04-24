import AppKit

enum OutlineRowLayoutSpec {
  static let indentWidth: CGFloat = 60
  static let controlSlotWidth: CGFloat = 20
  static let markerSlotWidth: CGFloat = 22
  static let markerTextSpacing: CGFloat = 5
  static let rowMinHeight: CGFloat = 23
  static let rowVerticalPadding: CGFloat = 0
  static let textLineSpacing: CGFloat = 0
  static let multilineBottomPadding: CGFloat = 5
  static let accessoryTopSpacing: CGFloat = 6
  static let guideLineWidth: CGFloat = 1.5
  static let guideLineBottomInset: CGFloat = 5
  static let dragDropTopThreshold: CGFloat = 16
  static let dragDropNestedThreshold: CGFloat = 50
  static let dropSlotHitHeight: CGFloat = 16
  static let dropIndicatorThickness: CGFloat = 2
  static let dropIndicatorTrailingInset: CGFloat = 12

  static var textLineHeight: CGFloat {
    let font = OutlinerFonts.nsFont(size: OutlinerCanvasMetrics.fontSize)
    return ceil(font.ascender - font.descender + font.leading)
  }

  static var controlHitAreaHeight: CGFloat {
    rowMinHeight + 10
  }

  static var estimatedRowHeight: CGFloat {
    rowMinHeight + (rowVerticalPadding * 2)
  }

  static func leadingTextX(depth: Int) -> CGFloat {
    CGFloat(depth) * indentWidth + controlSlotWidth + markerSlotWidth + markerTextSpacing
  }

  static func leadingAccessoryX(depth: Int) -> CGFloat {
    leadingTextX(depth: depth)
  }

  static func guideX(depthOffset: Int) -> CGFloat {
    CGFloat(depthOffset) * indentWidth + controlSlotWidth + (markerSlotWidth / 2)
  }

  static var childGuideLeadingOffset: CGFloat {
    guideX(depthOffset: 0) - indentWidth - (guideLineWidth / 2)
  }

  static func usesEditor(isFocused: Bool, isReference: Bool) -> Bool {
    isFocused && !isReference
  }

  static func showsAccessoryBand(
    isFocused: Bool,
    isTask: Bool,
    hasReminderConflict: Bool,
    hasSuggestions: Bool,
    hasAttachments: Bool
  ) -> Bool {
    hasReminderConflict || (isFocused && (isTask || hasSuggestions)) || hasAttachments
  }
}
