import SwiftUI

enum MotionTransaction {
  static func perform(
    _ token: MotionToken,
    quality: MotionQuality = .full,
    body: () -> Void
  ) {
    if let animation = MotionSystem.animation(for: token, quality: quality) {
      withAnimation(animation, body)
    } else {
      withoutAnimation(body)
    }
  }

  static func perform(
    _ token: MotionToken,
    context: MotionContext,
    body: () -> Void
  ) {
    perform(token, quality: MotionSystem.quality(for: context), body: body)
  }

  static func withResult<Result>(
    _ token: MotionToken,
    context: MotionContext,
    body: () -> Result
  ) -> Result {
    let quality = MotionSystem.quality(for: context)
    if let animation = MotionSystem.animation(for: token, quality: quality) {
      var result: Result!
      withAnimation(animation) {
        result = body()
      }
      return result
    }

    return withoutAnimation(body)
  }

  static func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
  }

  static func withoutAnimation<Result>(_ body: () -> Result) -> Result {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    var result: Result!
    withTransaction(transaction) {
      result = body()
    }
    return result
  }

  static func performIfAllowed(
    _ token: MotionToken,
    context: MotionContext,
    fallbackToNoAnimation: Bool = true,
    body: () -> Void
  ) {
    let quality = MotionSystem.quality(for: context)
    guard quality.allowsAnimation else {
      if fallbackToNoAnimation {
        withoutAnimation(body)
      }
      return
    }
    perform(token, quality: quality, body: body)
  }
}
