import Foundation

enum CompassBoardRefreshMode: Hashable, Sendable {
  case automatic
  case storedModelOnly
  case manual
  case fullRebuild
}

struct CompassBoardRuntimeResult: Sendable {
  var snapshot: CompassBoardSnapshot
  var refreshMode: CompassBoardRefreshMode
  var bootstrapResult: CompassBootstrapRunResult?
  var deltaResult: CompassDeltaUpdateRunResult?
  var statusMessage: String
}

enum CompassBoardRuntimeServiceError: LocalizedError {
  case manualBootstrapRequired

  var errorDescription: String? {
    switch self {
    case .manualBootstrapRequired:
      return "자기모델이 아직 없다. 상단의 초기 생성을 눌러 1회 분석을 시작할 수 있다."
    }
  }
}

protocol CompassBootstrapping: Sendable {
  func bootstrap(
    forceRebuild: Bool,
    rebuildReason: CompassFullRebuildReason?
  ) async throws -> CompassBootstrapRunResult
}

extension CompassBootstrapService: CompassBootstrapping {}

protocol CompassDeltaUpdating: Sendable {
  func updateIfNeeded() async throws -> CompassDeltaUpdateRunResult
}

extension CompassDeltaUpdateService: CompassDeltaUpdating {}

@MainActor
protocol CompassSnapshotGenerating: AnyObject {
  func generateSnapshot(referenceDate: Date) async throws -> CompassBoardSnapshot
}

extension CompassRecommendationService: CompassSnapshotGenerating {}

@MainActor
protocol CompassBoardRuntimeServing: AnyObject {
  func loadSnapshot(
    referenceDate: Date,
    mode: CompassBoardRefreshMode
  ) async throws -> CompassBoardRuntimeResult
}

@MainActor
final class CompassBoardRuntimeService: CompassBoardRuntimeServing {
  private let bootstrapService: any CompassBootstrapping
  private let deltaUpdateService: any CompassDeltaUpdating
  private let recommendationService: any CompassSnapshotGenerating

  init(
    bootstrapService: any CompassBootstrapping,
    deltaUpdateService: any CompassDeltaUpdating,
    recommendationService: any CompassSnapshotGenerating
  ) {
    self.bootstrapService = bootstrapService
    self.deltaUpdateService = deltaUpdateService
    self.recommendationService = recommendationService
  }

  func loadSnapshot(
    referenceDate: Date = .now,
    mode: CompassBoardRefreshMode = .automatic
  ) async throws -> CompassBoardRuntimeResult {
    var bootstrapResult: CompassBootstrapRunResult?
    var deltaResult: CompassDeltaUpdateRunResult?

    switch mode {
    case .fullRebuild:
      bootstrapResult = try await bootstrapService.bootstrap(
        forceRebuild: true,
        rebuildReason: .manualUserRequest
      )
    case .storedModelOnly:
      break
    case .automatic:
      do {
        deltaResult = try await deltaUpdateService.updateIfNeeded()
      } catch CompassDeltaUpdateServiceError.bootstrapRequired {
        throw CompassBoardRuntimeServiceError.manualBootstrapRequired
      }
    case .manual:
      do {
        deltaResult = try await deltaUpdateService.updateIfNeeded()
      } catch CompassDeltaUpdateServiceError.bootstrapRequired {
        do {
          bootstrapResult = try await bootstrapService.bootstrap(
            forceRebuild: false,
            rebuildReason: nil
          )
        } catch CompassBootstrapServiceError.incrementalUpdateRequired {
          deltaResult = try await deltaUpdateService.updateIfNeeded()
        }
      }
    }

    do {
      let snapshot = try await recommendationService.generateSnapshot(referenceDate: referenceDate)
      return CompassBoardRuntimeResult(
        snapshot: snapshot,
        refreshMode: mode,
        bootstrapResult: bootstrapResult,
        deltaResult: deltaResult,
        statusMessage: statusMessage(
          for: mode,
          bootstrapResult: bootstrapResult,
          deltaResult: deltaResult
        )
      )
    } catch CompassRecommendationServiceError.bootstrapRequired
      where mode != .fullRebuild && bootstrapResult == nil
    {
      guard mode == .manual else {
        throw CompassBoardRuntimeServiceError.manualBootstrapRequired
      }
      let fallbackBootstrap = try await bootstrapService.bootstrap(
        forceRebuild: false,
        rebuildReason: nil
      )
      let snapshot = try await recommendationService.generateSnapshot(referenceDate: referenceDate)
      return CompassBoardRuntimeResult(
        snapshot: snapshot,
        refreshMode: mode,
        bootstrapResult: fallbackBootstrap,
        deltaResult: deltaResult,
        statusMessage: statusMessage(
          for: mode,
          bootstrapResult: fallbackBootstrap,
          deltaResult: deltaResult
        )
      )
    }
  }

  private func statusMessage(
    for mode: CompassBoardRefreshMode,
    bootstrapResult: CompassBootstrapRunResult?,
    deltaResult: CompassDeltaUpdateRunResult?
  ) -> String {
    if let bootstrapResult {
      let base: String
      if mode == .fullRebuild {
        base = "전체 저널을 다시 읽어 자기모델을 재생성했다."
      } else if bootstrapResult.reusedCachedArtifacts {
        base = "준비된 자기모델 자산을 재사용해 나침반을 불러왔다."
      } else {
        base = "초기 자기모델을 생성했다. \(bootstrapResult.generatedDaySummaryCount)일 요약을 저장했다."
      }
      return appendSafeguardNote(bootstrapResult.safeguardNote, to: base)
    }

    if let deltaResult {
      let base: String
      if deltaResult.hadChanges {
        let changedCount = deltaResult.changedDayKeys.count
        let removedCount = deltaResult.removedDayKeys.count
        if removedCount > 0 {
          base = "변경된 저널 \(changedCount)일과 삭제된 \(removedCount)일만 반영해 나침반을 갱신했다."
        } else {
          base = "변경된 저널 \(changedCount)일만 반영해 나침반을 갱신했다."
        }
        return appendSafeguardNote(deltaResult.safeguardNote, to: base)
      }

      switch mode {
      case .automatic:
        base = "저널 변경이 없어 기존 자기모델을 재사용했다."
      case .storedModelOnly:
        base = "저장된 자기모델만 읽어 나침반을 계산했다."
      case .manual:
        base = "변경된 저널이 없어 기존 자기모델로 나침반만 다시 계산했다."
      case .fullRebuild:
        base = "전체 저널을 다시 읽어 자기모델을 재생성했다."
      }
      return appendSafeguardNote(deltaResult.safeguardNote, to: base)
    }

    switch mode {
    case .automatic:
      return "저장된 자기모델로 나침반을 계산했다."
    case .storedModelOnly:
      return "저장된 자기모델만 읽어 나침반을 계산했다."
    case .manual:
      return "저장된 자기모델로 나침반을 다시 계산했다."
    case .fullRebuild:
      return "전체 저널을 다시 읽어 자기모델을 재생성했다."
    }
  }

  private func appendSafeguardNote(_ note: String?, to base: String) -> String {
    guard let note, !note.isEmpty else { return base }
    return "\(base) \(note)"
  }
}
