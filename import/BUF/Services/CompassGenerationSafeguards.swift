import Foundation

struct CompassGenerationSafeguards: Hashable, Sendable {
  var bootstrapRecentWeekLLMLimit: Int
  var bootstrapRecentMonthLLMLimit: Int
  var bootstrapMaxLLMRequests: Int
  var bootstrapMaxKnownTokens: Int
  var deltaMaxLLMRequests: Int
  var deltaMaxKnownTokens: Int
  var maxConsecutiveFailures: Int

  static let `default` = CompassGenerationSafeguards(
    bootstrapRecentWeekLLMLimit: 8,
    bootstrapRecentMonthLLMLimit: 6,
    bootstrapMaxLLMRequests: 16,
    bootstrapMaxKnownTokens: 80_000,
    deltaMaxLLMRequests: 4,
    deltaMaxKnownTokens: 24_000,
    maxConsecutiveFailures: 2
  )
}

final class CompassGenerationCircuitBreaker: @unchecked Sendable {
  let maxRequests: Int
  let maxKnownTokens: Int
  let maxConsecutiveFailures: Int

  private(set) var attemptedRequestCount = 0
  private(set) var knownTotalTokens = 0
  private(set) var consecutiveFailures = 0
  private(set) var stopReason: String?

  init(maxRequests: Int, maxKnownTokens: Int, maxConsecutiveFailures: Int) {
    self.maxRequests = max(1, maxRequests)
    self.maxKnownTokens = max(1, maxKnownTokens)
    self.maxConsecutiveFailures = max(1, maxConsecutiveFailures)
  }

  func shouldAttempt(budgetMessage: String, tokenBudgetMessage: String) -> Bool {
    guard stopReason == nil else { return false }
    guard attemptedRequestCount < maxRequests else {
      stopReason = budgetMessage
      return false
    }
    guard knownTotalTokens < maxKnownTokens else {
      stopReason = tokenBudgetMessage
      return false
    }
    return true
  }

  func recordSuccess(totalTokens: Int?, tokenBudgetMessage: String) {
    attemptedRequestCount += 1
    knownTotalTokens += max(0, totalTokens ?? 0)
    consecutiveFailures = 0
    guard stopReason == nil, knownTotalTokens >= maxKnownTokens else { return }
    stopReason = tokenBudgetMessage
  }

  func recordFailure(_ message: String) {
    attemptedRequestCount += 1
    consecutiveFailures += 1

    guard stopReason == nil, consecutiveFailures >= maxConsecutiveFailures else { return }
    stopReason = message
  }
}
