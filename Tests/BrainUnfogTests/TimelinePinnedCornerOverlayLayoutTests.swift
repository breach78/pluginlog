import CoreGraphics
import Testing
@testable import BrainUnfog

struct TimelinePinnedCornerOverlayLayoutTests {
  @Test func keepsCornerContentVerticallyFixedWhileHorizontalOriginTracksVisibleBounds() {
    let layout = TimelinePinnedCornerOverlayLayout(
      visibleBounds: CGRect(x: 120, y: 240, width: 500, height: 320),
      titleColumnWidth: 200,
      headerHeight: 50
    )

    #expect(layout.overlayFrame == CGRect(x: 40, y: -80, width: 284, height: 130))
    #expect(layout.contentFrame == CGRect(x: 80, y: 80, width: 200, height: 50))
  }

  @Test func clampsBleedAndHeaderInputsToNonNegativeFrames() {
    let layout = TimelinePinnedCornerOverlayLayout(
      visibleBounds: CGRect(x: 10, y: 20, width: 100, height: 100),
      titleColumnWidth: -1,
      headerHeight: -2,
      leadingBleed: -3,
      topBleed: -4,
      trailingBleed: -5
    )

    #expect(layout.overlayFrame == CGRect(x: 10, y: 0, width: 0, height: 0))
    #expect(layout.contentFrame == CGRect(x: 0, y: 0, width: 0, height: 0))
  }
}
