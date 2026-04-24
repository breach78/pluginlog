import Foundation

struct ProjectDetailBlockPageRetryPolicy: Equatable {
  let maxAttempts: Int
  let retryDelayNanoseconds: UInt64
  let engineWarmupPollCount: Int
  let engineWarmupDelayNanoseconds: UInt64

  static let hostDefault = Self(
    maxAttempts: 12,
    retryDelayNanoseconds: 250_000_000,
    engineWarmupPollCount: 20,
    engineWarmupDelayNanoseconds: 100_000_000
  )

  func shouldRetry(after error: Error, attempt: Int) -> Bool {
    attempt < maxAttempts && ProjectDetailBlockPageLoadFailure.isTransientLock(error)
  }
}

enum ProjectDetailBlockPageReloadTrigger: String, CaseIterable, Equatable {
  case initialLoad = "initial-load"
  case engineReady = "engine-ready"
  case pageRefresh = "page-refresh"
  case failureRetry = "failure-retry"
}

enum ProjectDetailBlockPageLoadFailure: Equatable {
  case engineUnavailable
  case missingTarget
  case missingProjectSnapshot
  case transientLockExhausted
  case queryFailed(String)

  var logName: String {
    switch self {
    case .engineUnavailable:
      return "engine-unavailable"
    case .missingTarget:
      return "missing-target"
    case .missingProjectSnapshot:
      return "missing-project-snapshot"
    case .transientLockExhausted:
      return "transient-lock-exhausted"
    case .queryFailed:
      return "query-failed"
    }
  }

  var allowsRetry: Bool {
    switch self {
    case .engineUnavailable,
      .transientLockExhausted,
      .queryFailed:
      return true
    case .missingTarget,
      .missingProjectSnapshot:
      return false
    }
  }

  var title: String {
    switch self {
    case .engineUnavailable:
      return "프로젝트 페이지 엔진이 아직 준비되지 않았습니다"
    case .missingTarget:
      return "프로젝트 페이지 대상을 찾지 못했습니다"
    case .missingProjectSnapshot:
      return "프로젝트 페이지 데이터를 찾지 못했습니다"
    case .transientLockExhausted:
      return "프로젝트 페이지가 아직 잠겨 있습니다"
    case .queryFailed:
      return "프로젝트 페이지를 열 수 없습니다"
    }
  }

  var message: String {
    switch self {
    case .engineUnavailable:
      return "로컬 block page 엔진이 준비되면 다시 시도할 수 있습니다"
    case .missingTarget:
      return "현재 요청과 연결된 프로젝트 페이지 대상을 확인하지 못했습니다"
    case .missingProjectSnapshot:
      return "요청한 프로젝트의 페이지 데이터를 찾지 못했습니다"
    case .transientLockExhausted:
      return "데이터베이스 잠금이 풀리지 않아 프로젝트 페이지를 준비하지 못했습니다"
    case .queryFailed(let message):
      return message
    }
  }

  static func finalFailure(for error: Error) -> Self {
    if isTransientLock(error) {
      return .transientLockExhausted
    }

    let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    if message.isEmpty {
      return .queryFailed("프로젝트 페이지를 다시 불러오지 못했습니다")
    }
    return .queryFailed(message)
  }

  static func isTransientLock(_ error: Error) -> Bool {
    error.localizedDescription.localizedCaseInsensitiveContains("database is locked")
  }
}

enum ProjectDetailBlockPageLoadFailureScenario: String, CaseIterable, Equatable {
  case engineUnavailable = "engine-unavailable"
  case missingTarget = "missing-target"
  case missingProjectSnapshot = "missing-project-snapshot"
  case transientLockExhausted = "transient-lock-exhausted"
  case queryFailed = "query-failed"

  var representativeFailure: ProjectDetailBlockPageLoadFailure {
    switch self {
    case .engineUnavailable:
      return .engineUnavailable
    case .missingTarget:
      return .missingTarget
    case .missingProjectSnapshot:
      return .missingProjectSnapshot
    case .transientLockExhausted:
      return .transientLockExhausted
    case .queryFailed:
      return .queryFailed("프로젝트 페이지를 다시 불러오지 못했습니다")
    }
  }
}

struct ProjectDetailBlockPageLoadTestPlan: Equatable {
  let failureScenarios: [ProjectDetailBlockPageLoadFailureScenario]
  let reloadTriggers: [ProjectDetailBlockPageReloadTrigger]
  let manualChecks: [String]

  static let hostDefault = Self(
    failureScenarios: ProjectDetailBlockPageLoadFailureScenario.allCases,
    reloadTriggers: ProjectDetailBlockPageReloadTrigger.allCases,
    manualChecks: [
      "엔진 미준비 상태 fallback",
      "다시 시도 버튼",
    ]
  )
}
