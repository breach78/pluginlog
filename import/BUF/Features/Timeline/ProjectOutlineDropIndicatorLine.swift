import SwiftUI

struct ProjectOutlineDropIndicatorLine: View {
  var body: some View {
    Rectangle()
      .fill(Color.accentColor)
      .frame(height: 2)
      .cornerRadius(1)
      .allowsHitTesting(false)
  }
}
