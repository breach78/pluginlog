import Foundation

enum CompassRunPhase: String, Sendable {
  case bootstrap
  case delta
  case recommendation

  var title: String {
    switch self {
    case .bootstrap:
      return "초기 생성"
    case .delta:
      return "증분 갱신"
    case .recommendation:
      return "추천 계산"
    }
  }
}

struct CompassRunEstimate: Hashable, Sendable {
  var phase: CompassRunPhase
  var estimatedRequestCount: Int
  var requestCap: Int
  var estimatedOutputTokenUpperBound: Int
  var knownTokenCap: Int
}

struct CompassRunProgressSnapshot: Hashable, Sendable {
  var phase: CompassRunPhase
  var attemptedRequestCount: Int
  var knownTotalTokens: Int
  var requestCap: Int
  var knownTokenCap: Int
  var stopReason: String?
}

@MainActor
final class CompassRunMonitor: ObservableObject {
  @Published private(set) var isRunning = false
  @Published private(set) var estimate: CompassRunEstimate?
  @Published private(set) var progress: CompassRunProgressSnapshot?
  @Published private(set) var lastMessage: String?

  func begin(_ estimate: CompassRunEstimate) {
    self.estimate = estimate
    progress = CompassRunProgressSnapshot(
      phase: estimate.phase,
      attemptedRequestCount: 0,
      knownTotalTokens: 0,
      requestCap: estimate.requestCap,
      knownTokenCap: estimate.knownTokenCap,
      stopReason: nil
    )
    isRunning = true
    lastMessage = nil
  }

  func update(_ progress: CompassRunProgressSnapshot) {
    self.progress = progress
  }

  func finish(_ message: String? = nil) {
    isRunning = false
    if let message, !message.isEmpty {
      lastMessage = message
    }
  }

  func cancel() {
    guard let progress else { return }
    self.progress = CompassRunProgressSnapshot(
      phase: progress.phase,
      attemptedRequestCount: progress.attemptedRequestCount,
      knownTotalTokens: progress.knownTotalTokens,
      requestCap: progress.requestCap,
      knownTokenCap: progress.knownTokenCap,
      stopReason: "사용자가 실행을 중단했다."
    )
    isRunning = false
    lastMessage = "나침반 실행을 중단했다."
  }

  func reset() {
    isRunning = false
    estimate = nil
    progress = nil
    lastMessage = nil
  }
}
