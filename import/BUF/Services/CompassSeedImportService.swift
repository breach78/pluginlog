import CryptoKit
import Foundation

struct CompassApprovedSeed: Hashable, Sendable {
  var seedVersion: Int
  var origin: CompassSeedOrigin
  var createdAt: Date
  var approvedAt: Date
  var overview: String
  var corePersona: [CompassHypothesis]
  var currentSeason: [CompassHypothesis]
  var operationalTendencies: [CompassHypothesis]
  var blindSpots: [CompassHypothesis]
  var steeringRules: [CompassSteeringRule]
  var motivationMap: [CompassMotivationSignal]
  var schedulingPreferences: [CompassSchedulingPreference]
  var recommendationGuardrails: [CompassRecommendationGuardrail]
  var baselineGenerationPolicy: CompassBaselineGenerationPolicy
  var notes: String?
  var reviewMarkdown: String?

  init(
    seedVersion: Int = 1,
    origin: CompassSeedOrigin = .assistantUserReviewed,
    createdAt: Date = .now,
    approvedAt: Date = .now,
    overview: String,
    corePersona: [CompassHypothesis] = [],
    currentSeason: [CompassHypothesis] = [],
    operationalTendencies: [CompassHypothesis] = [],
    blindSpots: [CompassHypothesis] = [],
    steeringRules: [CompassSteeringRule] = [],
    motivationMap: [CompassMotivationSignal] = [],
    schedulingPreferences: [CompassSchedulingPreference] = [],
    recommendationGuardrails: [CompassRecommendationGuardrail] = [],
    baselineGenerationPolicy: CompassBaselineGenerationPolicy = CompassBaselineGenerationPolicy(),
    notes: String? = nil,
    reviewMarkdown: String? = nil
  ) {
    self.seedVersion = seedVersion
    self.origin = origin
    self.createdAt = createdAt
    self.approvedAt = approvedAt
    self.overview = overview
    self.corePersona = corePersona
    self.currentSeason = currentSeason
    self.operationalTendencies = operationalTendencies
    self.blindSpots = blindSpots
    self.steeringRules = steeringRules
    self.motivationMap = motivationMap
    self.schedulingPreferences = schedulingPreferences
    self.recommendationGuardrails = recommendationGuardrails
    self.baselineGenerationPolicy = baselineGenerationPolicy
    self.notes = notes
    self.reviewMarkdown = reviewMarkdown
  }
}

struct CompassSeedImportResult: Hashable, Sendable {
  var manifest: CompassSeedManifest
  var importedDaySummaryCount: Int
  var generationID: UUID
}

actor CompassSeedImportService {
  private let journalProvider: any CompassJournalProviding
  private let modelStore: CompassModelStore
  private let loadModelConfiguration: @Sendable () async -> CompassModelConfiguration
  private let promptVersions: CompassPromptVersionSet

  init(
    journalProvider: any CompassJournalProviding,
    modelStore: CompassModelStore,
    loadModelConfiguration: @escaping @Sendable () async -> CompassModelConfiguration = { .initial },
    promptVersions: CompassPromptVersionSet = .initial
  ) {
    self.journalProvider = journalProvider
    self.modelStore = modelStore
    self.loadModelConfiguration = loadModelConfiguration
    self.promptVersions = promptVersions
  }

  func importApprovedSeed(_ seed: CompassApprovedSeed) async throws -> CompassSeedImportResult {
    try await modelStore.prepare()

    let sourceWindow = try await buildSourceWindow()
    let sourceRevision = digest(
      sourceWindow.daySnapshots.map { "\($0.dayKey):\($0.sourceRevision)" }.joined(separator: "\n")
    )
    let modelConfiguration = await loadModelConfiguration()
    let importedAt = Date()
    let generationID = UUID()

    let metadata = CompassArtifactGenerationMetadata(
      generationID: generationID,
      createdAt: seed.createdAt,
      updatedAt: importedAt,
      promptVersions: promptVersions,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow.window
    )

    try await clearPreviousDerivedArtifacts(preservingDayKeys: sourceWindow.daySnapshots.map(\.dayKey))

    for snapshot in sourceWindow.daySnapshots {
      try await modelStore.saveDaySummary(
        CompassJournalDaySummary(
          dayKey: snapshot.dayKey,
          summary: fallbackDaySummary(for: snapshot.entries),
          highlights: fallbackHighlights(for: snapshot.entries),
          sourceRevision: snapshot.sourceRevision,
          metadata: metadata
        )
      )
    }

    let selfModel = CompassSelfModel(
      metadata: metadata,
      overview: seed.overview,
      corePersona: seed.corePersona,
      currentSeason: seed.currentSeason,
      operationalTendencies: seed.operationalTendencies,
      blindSpots: seed.blindSpots,
      steeringRules: seed.steeringRules,
      motivationMap: seed.motivationMap,
      schedulingPreferences: seed.schedulingPreferences,
      recommendationGuardrails: seed.recommendationGuardrails
    )

    let journalIndex = CompassJournalIndex(
      indexedAt: importedAt,
      journalRootPath: await journalProvider.rootPath(),
      availableDayKeys: sourceWindow.daySnapshots.map(\.dayKey),
      sourceRevision: sourceRevision
    )
    let manifest = CompassStorageManifest(
      createdAt: importedAt,
      updatedAt: importedAt,
      promptVersions: promptVersions,
      activeModelConfiguration: modelConfiguration,
      lastFullAnalysisAt: seed.approvedAt,
      lastIncrementalUpdateAt: nil
    )
    let seedManifest = CompassSeedManifest(
      schemaVersion: manifest.schemaVersion,
      seedVersion: seed.seedVersion,
      status: .approved,
      origin: seed.origin,
      createdAt: seed.createdAt,
      approvedAt: seed.approvedAt,
      importedAt: importedAt,
      journalWindow: sourceWindow.window,
      baselineGenerationPolicy: seed.baselineGenerationPolicy,
      notes: seed.notes
    )
    let bootstrapState = CompassBootstrapState(
      generationID: generationID,
      currentStage: .completed,
      startedAt: seed.createdAt,
      updatedAt: importedAt,
      completedAt: importedAt,
      lastError: nil,
      checkpoints: [
        CompassBootstrapCheckpoint(
          stage: .journalIndex,
          status: .completed,
          updatedAt: importedAt,
          detail: "승인된 seed 기준으로 저널 인덱스를 작성했다."
        ),
        CompassBootstrapCheckpoint(
          stage: .daySummaries,
          status: .completed,
          updatedAt: importedAt,
          detail: "승인된 seed와 맞추기 위해 로컬 일간 요약을 저장했다."
        ),
        CompassBootstrapCheckpoint(
          stage: .selfModel,
          status: .completed,
          updatedAt: importedAt,
          detail: "사용자 승인 baseline seed를 자기모델로 반영했다."
        ),
        CompassBootstrapCheckpoint(
          stage: .completed,
          status: .completed,
          updatedAt: importedAt,
          detail: "초기 baseline seed import가 완료됐다."
        ),
      ]
    )

    try await modelStore.saveManifest(manifest)
    try await modelStore.saveBootstrapState(bootstrapState)
    try await modelStore.saveSelfModel(selfModel)
    try await modelStore.saveJournalIndex(journalIndex)
    try await modelStore.saveSeedManifest(seedManifest)

    if let reviewMarkdown = seed.reviewMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
      !reviewMarkdown.isEmpty
    {
      try await modelStore.saveSeedReview(reviewMarkdown)
    } else {
      try await modelStore.deleteSeedReview()
    }

    var telemetry = try await modelStore.loadAnalysisTelemetry() ?? CompassAnalysisTelemetry()
    telemetry.lastBlockedFullRebuildAt = nil
    telemetry.lastBlockedFullRebuildReason = nil
    try await modelStore.saveAnalysisTelemetry(telemetry)

    return CompassSeedImportResult(
      manifest: seedManifest,
      importedDaySummaryCount: sourceWindow.daySnapshots.count,
      generationID: generationID
    )
  }

  private func clearPreviousDerivedArtifacts(preservingDayKeys liveDayKeys: [String]) async throws {
    let liveDayKeySet = Set(liveDayKeys)
    for dayKey in try await modelStore.availableDaySummaryKeys() where !liveDayKeySet.contains(dayKey) {
      try await modelStore.deleteDaySummary(for: dayKey)
    }
    for dayKey in try await modelStore.availableDailyDeltaKeys() {
      try await modelStore.deleteDailyDelta(for: dayKey)
    }
    for periodKey in try await modelStore.availablePeriodSummaryKeys(granularity: .week) {
      try await modelStore.deletePeriodSummary(granularity: .week, periodKey: periodKey)
    }
    for periodKey in try await modelStore.availablePeriodSummaryKeys(granularity: .month) {
      try await modelStore.deletePeriodSummary(granularity: .month, periodKey: periodKey)
    }
  }

  private func buildSourceWindow() async throws -> CompassSeedSourceWindow {
    let availableDays = try await journalProvider.availableDays()
    var snapshots: [CompassSeedDaySnapshot] = []
    var indexedEntryCount = 0

    for day in availableDays {
      let entries = try await journalProvider.entries(for: day)
      let dayKey = CompassDateKeyCodec.dayKey(for: day)
      let sourceRevision = digest(
        entries
          .sorted { $0.occurredAt < $1.occurredAt }
          .map {
            "\($0.id)|\($0.occurredAt.timeIntervalSince1970)|\($0.body.replacingOccurrences(of: "\n", with: "\\n"))"
          }
          .joined(separator: "\n")
      )
      snapshots.append(
        CompassSeedDaySnapshot(
          day: day,
          dayKey: dayKey,
          entries: entries,
          sourceRevision: sourceRevision
        )
      )
      indexedEntryCount += entries.count
    }

    let sortedSnapshots = snapshots.sorted { $0.day < $1.day }
    return CompassSeedSourceWindow(
      window: CompassSourceWindow(
        firstJournalDay: sortedSnapshots.first?.day,
        lastJournalDay: sortedSnapshots.last?.day,
        indexedDayCount: sortedSnapshots.count,
        indexedEntryCount: indexedEntryCount
      ),
      daySnapshots: sortedSnapshots
    )
  }

  private func digest(_ string: String) -> String {
    let hash = SHA256.hash(data: Data(string.utf8))
    return hash.prefix(12).map { String(format: "%02x", $0) }.joined()
  }

  private func fallbackDaySummary(for entries: [ObsidianJournalEntry]) -> String {
    let snippets = entries
      .flatMap { $0.body.components(separatedBy: .newlines) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    if snippets.isEmpty {
      return "기록이 거의 없어 하루 흐름을 압축하기 어렵다."
    }

    return Array(snippets.prefix(3)).joined(separator: " ")
  }

  private func fallbackHighlights(for entries: [ObsidianJournalEntry]) -> [String] {
    let snippets = entries
      .flatMap { $0.body.components(separatedBy: .newlines) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return Array(snippets.prefix(4))
  }
}

private struct CompassSeedSourceWindow {
  var window: CompassSourceWindow
  var daySnapshots: [CompassSeedDaySnapshot]
}

private struct CompassSeedDaySnapshot {
  var day: Date
  var dayKey: String
  var entries: [ObsidianJournalEntry]
  var sourceRevision: String
}
