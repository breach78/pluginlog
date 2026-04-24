import CoreGraphics
import Foundation

let projectTaskLocalReorderActivationDistance: CGFloat = 6

struct ProjectTaskLocalReorderPressState: Equatable {
  let taskID: UUID
  let projectID: UUID
  let startLocation: CGPoint
}

struct ProjectTaskLocalReorderSession: Equatable {
  let taskID: UUID
  let projectID: UUID
  let startLocation: CGPoint
  let sourceRowFrame: CGRect
  let initialLiftOffsetY: CGFloat
  var currentLocation: CGPoint
}
