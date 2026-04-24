import Foundation

actor CompassSafetyService {
  private let modelStore: CompassModelStore
  private let promptVersions = CompassPromptVersionSet.initial

  init(modelStore: CompassModelStore) {
    self.modelStore = modelStore
  }

  func loadAnalysisStatus() async throws -> CompassAnalysisStatus? {
    guard let manifest = try await modelStore.loadManifest() else { return nil }
    let telemetry = try await modelStore.loadAnalysisTelemetry() ?? CompassAnalysisTelemetry()
    let seedManifest = try await modelStore.loadSeedManifest()
    let seedReview = try await modelStore.loadSeedReview()

    return CompassAnalysisStatus(
      schemaVersion: manifest.schemaVersion,
      promptVersions: manifest.promptVersions,
      activeModelConfiguration: manifest.activeModelConfiguration,
      lastFullAnalysisAt: manifest.lastFullAnalysisAt,
      lastIncrementalUpdateAt: manifest.lastIncrementalUpdateAt,
      usageLedger: telemetry.usageLedger,
      rebuildPolicySummary:
        "첫 진입에서는 자동으로 전체 분석하지 않는다. 초기 생성은 명시적으로 시작하고, 일별 요약은 로컬로 저장한 뒤 최근 기간 패턴과 자기모델만 Gemini로 계산한다.",
      allowedRebuildReasons: CompassFullRebuildReason.allowedUserFacingReasons,
      lastBlockedRebuildReason: telemetry.lastBlockedFullRebuildReason,
      lastBlockedRebuildAt: telemetry.lastBlockedFullRebuildAt,
      seedManifest: seedManifest,
      hasSeedReview: !(seedReview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    )
  }

  func recordUsage(
    phase: CompassUsagePhase,
    usage: GeminiGenerateContentSummaryService.SummaryUsage?
  ) async throws {
    guard let usage else { return }

    var telemetry = try await modelStore.loadAnalysisTelemetry() ?? CompassAnalysisTelemetry()
    telemetry.usageLedger.record(
      phase: phase,
      promptTokenCount: usage.promptTokenCount,
      candidatesTokenCount: usage.candidatesTokenCount,
      thoughtsTokenCount: usage.thoughtsTokenCount,
      totalTokenCount: usage.totalTokenCount
    )
    try await modelStore.saveAnalysisTelemetry(telemetry)
  }

  func recordUsageTotals(
    phase: CompassUsagePhase,
    totals: CompassTokenUsageTotals
  ) async throws {
    guard totals.requestCount > 0 else { return }

    var telemetry = try await modelStore.loadAnalysisTelemetry() ?? CompassAnalysisTelemetry()
    telemetry.usageLedger.record(
      phase: phase,
      promptTokenCount: totals.promptTokenCount,
      candidatesTokenCount: totals.candidatesTokenCount,
      thoughtsTokenCount: totals.thoughtsTokenCount,
      totalTokenCount: totals.totalTokenCount,
      requestCount: totals.requestCount
    )
    try await modelStore.saveAnalysisTelemetry(telemetry)
  }

  func recordFullRebuildReason(_ reason: CompassFullRebuildReason) async throws {
    var telemetry = try await modelStore.loadAnalysisTelemetry() ?? CompassAnalysisTelemetry()
    telemetry.lastFullRebuildReason = reason
    telemetry.lastBlockedFullRebuildAt = nil
    telemetry.lastBlockedFullRebuildReason = nil
    try await modelStore.saveAnalysisTelemetry(telemetry)
  }

  func recordBlockedFullRebuild(_ message: String) async throws {
    var telemetry = try await modelStore.loadAnalysisTelemetry() ?? CompassAnalysisTelemetry()
    telemetry.lastBlockedFullRebuildAt = .now
    telemetry.lastBlockedFullRebuildReason = message
    try await modelStore.saveAnalysisTelemetry(telemetry)
  }

  func currentPromptVersions() -> CompassPromptVersionSet {
    promptVersions
  }
}
