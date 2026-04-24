import CryptoKit
import Foundation

protocol CompassJournalProviding: Sendable {
  func availableDays() async throws -> [Date]
  func entries(for day: Date) async throws -> [ObsidianJournalEntry]
  func rootPath() async -> String?
}

struct ObsidianCompassJournalProvider: CompassJournalProviding {
  let rootURL: URL
  let store: ObsidianJournalStore

  func availableDays() async throws -> [Date] {
    try await store.availableDays()
  }

  func entries(for day: Date) async throws -> [ObsidianJournalEntry] {
    try await store.entries(for: day)
  }

  func rootPath() async -> String? {
    rootURL.path
  }
}

protocol CompassGenerationServing: Sendable {
  func loadModelConfiguration() async -> CompassModelConfiguration
  func generate(_ request: CompassGenerationRequest) async -> CompassGenerationResult?
}

extension GeminiCompassService: CompassGenerationServing {}

enum CompassBootstrapServiceError: LocalizedError, Equatable {
  case fullRebuildReasonRequired
  case incrementalUpdateRequired

  var errorDescription: String? {
    switch self {
    case .fullRebuildReasonRequired:
      return "전체 재분석은 허용된 사유가 있을 때만 실행할 수 있습니다."
    case .incrementalUpdateRequired:
      return "저널 변경이 감지됐다. 전체 재분석 대신 증분 갱신을 사용해야 한다."
    }
  }
}

struct CompassBootstrapRunResult: Hashable, Sendable {
  var generationID: UUID
  var reusedCachedArtifacts: Bool
  var indexedDayCount: Int
  var indexedEntryCount: Int
  var generatedDaySummaryCount: Int
  var generatedWeekSummaryCount: Int
  var generatedMonthSummaryCount: Int
  var llmAttemptCount: Int = 0
  var safeguardNote: String? = nil
}

actor CompassBootstrapService {
  private let journalProvider: any CompassJournalProviding
  private let modelStore: CompassModelStore
  private let generator: any CompassGenerationServing
  private let safetyService: CompassSafetyService
  private let calendar: Calendar
  private let runMonitor: CompassRunMonitor?
  private let safeguards = CompassGenerationSafeguards.default
  private let promptVersions = CompassPromptVersionSet.initial

  init(
    journalProvider: any CompassJournalProviding,
    modelStore: CompassModelStore,
    generator: any CompassGenerationServing,
    runMonitor: CompassRunMonitor? = nil,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.journalProvider = journalProvider
    self.modelStore = modelStore
    self.generator = generator
    self.safetyService = CompassSafetyService(modelStore: modelStore)
    self.runMonitor = runMonitor
    self.calendar = calendar
  }

  func bootstrap(
    forceRebuild: Bool = false,
    rebuildReason: CompassFullRebuildReason? = nil
  ) async throws -> CompassBootstrapRunResult {
    try await modelStore.prepare()

    let availableDays = try await journalProvider.availableDays()
    let sourceWindow = try await buildSourceWindow(from: availableDays)
    let weekKeys = Set(availableDays.map { CompassDateKeyCodec.weekKey(for: $0, calendar: calendar) })
    let monthKeys = Set(availableDays.map { CompassDateKeyCodec.monthKey(for: $0) })
    let currentSourceRevision = digest(
      sourceWindow.daySnapshots.map { "\($0.dayKey):\($0.sourceRevision)" }.joined(separator: "\n")
    )
    let existingManifest = try await modelStore.loadManifest()
    let existingIndex = try await modelStore.loadJournalIndex()
    let existingSelfModel = try await modelStore.loadSelfModel()

    if forceRebuild {
      guard let rebuildReason else {
        try await safetyService.recordBlockedFullRebuild(
          blockedFullRebuildMessage()
        )
        throw CompassBootstrapServiceError.fullRebuildReasonRequired
      }
      try await safetyService.recordFullRebuildReason(rebuildReason)
    }

    if
      !forceRebuild,
      let cachedResult = try await loadCachedResultIfAvailable(
        sourceWindow: sourceWindow,
        sourceRevision: currentSourceRevision,
        expectedWeekKeys: weekKeys,
        expectedMonthKeys: monthKeys
      )
    {
      return cachedResult
    }

    let automaticReason = automaticFullRebuildReason(
      manifest: existingManifest,
      journalIndex: existingIndex,
      selfModel: existingSelfModel
    )

    if !forceRebuild, automaticReason == nil, existingManifest != nil, existingIndex != nil, existingSelfModel != nil
    {
      try await safetyService.recordBlockedFullRebuild(
        "저널 변경은 전체 재분석이 아니라 증분 갱신으로 처리해야 한다."
      )
      throw CompassBootstrapServiceError.incrementalUpdateRequired
    }

    let generationID = UUID()
    let modelConfiguration = await generator.loadModelConfiguration()
    let circuitBreaker = CompassGenerationCircuitBreaker(
      maxRequests: safeguards.bootstrapMaxLLMRequests,
      maxKnownTokens: safeguards.bootstrapMaxKnownTokens,
      maxConsecutiveFailures: safeguards.maxConsecutiveFailures
    )
    await beginBootstrapMonitoring(weekKeyCount: weekKeys.count, monthKeyCount: monthKeys.count)
    var bootstrapState = makeBootstrapState(generationID: generationID)
    var usageTotals = CompassTokenUsageTotals()

    mark(&bootstrapState, stage: .journalIndex, status: .inProgress)
    try await modelStore.saveBootstrapState(bootstrapState)

    let journalIndex = CompassJournalIndex(
      indexedAt: .now,
      journalRootPath: await journalProvider.rootPath(),
      availableDayKeys: sourceWindow.daySnapshots.map(\.dayKey),
      sourceRevision: currentSourceRevision
    )
    try await modelStore.saveJournalIndex(journalIndex)

    mark(&bootstrapState, stage: .journalIndex, status: .completed)
    mark(&bootstrapState, stage: .daySummaries, status: .inProgress)
    try await modelStore.saveBootstrapState(bootstrapState)

    var generatedDaySummaryCount = 0
    var resolvedDaySummaries: [CompassJournalDaySummary] = []
    for snapshot in sourceWindow.daySnapshots {
      try Task.checkCancellation()
      if
        !forceRebuild,
        let existing = try await modelStore.loadDaySummary(for: snapshot.dayKey),
        existing.sourceRevision == snapshot.sourceRevision,
        existing.metadata.promptVersions.bootstrapPromptVersion == promptVersions.bootstrapPromptVersion
      {
        resolvedDaySummaries.append(existing)
        continue
      }

      let metadata = makeMetadata(
        generationID: generationID,
        modelConfiguration: modelConfiguration,
        sourceWindow: sourceWindow.window
      )
      let summary = await buildDaySummary(
        for: snapshot,
        metadata: metadata,
        allowLLM: false
      )
      usageTotals.merge(summary.usageTotals)
      try await modelStore.saveDaySummary(summary.summary)
      resolvedDaySummaries.append(summary.summary)
      generatedDaySummaryCount += 1
    }

    resolvedDaySummaries.sort { $0.dayKey < $1.dayKey }

    mark(&bootstrapState, stage: .daySummaries, status: .completed)
    mark(&bootstrapState, stage: .periodSummaries, status: .inProgress)
    try await modelStore.saveBootstrapState(bootstrapState)

    let weeklySummaries = await buildPeriodSummaries(
      granularity: .week,
      daySummaries: resolvedDaySummaries,
      generationID: generationID,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow.window,
      forceRebuild: forceRebuild,
      circuitBreaker: circuitBreaker
    )
    usageTotals.merge(weeklySummaries.usageTotals)
    try Task.checkCancellation()

    let monthlySummaries = await buildPeriodSummaries(
      granularity: .month,
      daySummaries: resolvedDaySummaries,
      generationID: generationID,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow.window,
      forceRebuild: forceRebuild,
      circuitBreaker: circuitBreaker
    )
    usageTotals.merge(monthlySummaries.usageTotals)
    try Task.checkCancellation()

    for summary in weeklySummaries.summaries {
      try await modelStore.savePeriodSummary(summary)
    }
    for summary in monthlySummaries.summaries {
      try await modelStore.savePeriodSummary(summary)
    }

    mark(&bootstrapState, stage: .periodSummaries, status: .completed)
    mark(&bootstrapState, stage: .selfModel, status: .inProgress)
    try await modelStore.saveBootstrapState(bootstrapState)

    let selfModel = await buildSelfModel(
      generationID: generationID,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow.window,
      sourceRevision: currentSourceRevision,
      weeklySummaries: weeklySummaries.summaries,
      monthlySummaries: monthlySummaries.summaries,
      daySummaries: resolvedDaySummaries,
      circuitBreaker: circuitBreaker
    )
    usageTotals.merge(selfModel.usageTotals)
    try Task.checkCancellation()
    try await modelStore.saveSelfModel(selfModel.selfModel)

    let manifest = CompassStorageManifest(
      schemaVersion: existingManifest?.schemaVersion ?? CompassStorageManifest.currentSchemaVersion,
      createdAt: existingManifest?.createdAt ?? .now,
      updatedAt: .now,
      promptVersions: promptVersions,
      activeModelConfiguration: modelConfiguration,
      lastFullAnalysisAt: .now,
      lastIncrementalUpdateAt: existingManifest?.lastIncrementalUpdateAt
    )
    try await modelStore.saveManifest(manifest)
    try await safetyService.recordUsageTotals(phase: .bootstrap, totals: usageTotals)
    try await safetyService.recordFullRebuildReason(
      forceRebuild ? rebuildReason ?? .manualUserRequest : automaticReason ?? .initialBootstrap
    )

    mark(&bootstrapState, stage: .selfModel, status: .completed)
    bootstrapState.currentStage = .completed
    bootstrapState.updatedAt = .now
    bootstrapState.completedAt = .now
    bootstrapState.lastError = nil
    try await modelStore.saveBootstrapState(bootstrapState)
    await runMonitor?.finish(bootstrapSafeguardNote(circuitBreaker))

    return CompassBootstrapRunResult(
      generationID: generationID,
      reusedCachedArtifacts: false,
      indexedDayCount: sourceWindow.window.indexedDayCount,
      indexedEntryCount: sourceWindow.window.indexedEntryCount,
      generatedDaySummaryCount: generatedDaySummaryCount,
      generatedWeekSummaryCount: weeklySummaries.generatedCount,
      generatedMonthSummaryCount: monthlySummaries.generatedCount,
      llmAttemptCount: circuitBreaker.attemptedRequestCount,
      safeguardNote: bootstrapSafeguardNote(circuitBreaker)
    )
  }

  private func buildSourceWindow(
    from availableDays: [Date]
  ) async throws -> CompassBootstrapSourceWindow {
    var snapshots: [CompassBootstrapDaySnapshot] = []
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
        CompassBootstrapDaySnapshot(
          day: day,
          dayKey: dayKey,
          entries: entries,
          sourceRevision: sourceRevision
        )
      )
      indexedEntryCount += entries.count
    }

    let sortedSnapshots = snapshots.sorted { $0.day < $1.day }
    return CompassBootstrapSourceWindow(
      window: CompassSourceWindow(
        firstJournalDay: sortedSnapshots.first?.day,
        lastJournalDay: sortedSnapshots.last?.day,
        indexedDayCount: sortedSnapshots.count,
        indexedEntryCount: indexedEntryCount
      ),
      daySnapshots: sortedSnapshots
    )
  }

  private func loadCachedResultIfAvailable(
    sourceWindow: CompassBootstrapSourceWindow,
    sourceRevision: String,
    expectedWeekKeys: Set<String>,
    expectedMonthKeys: Set<String>
  ) async throws -> CompassBootstrapRunResult? {
    guard let manifest = try await modelStore.loadManifest() else { return nil }
    guard manifest.schemaVersion == CompassStorageManifest.currentSchemaVersion else { return nil }
    guard manifest.promptVersions.bootstrapPromptVersion == promptVersions.bootstrapPromptVersion else {
      return nil
    }
    guard let journalIndex = try await modelStore.loadJournalIndex() else { return nil }
    guard journalIndex.sourceRevision == sourceRevision else { return nil }
    guard let selfModel = try await modelStore.loadSelfModel() else { return nil }
    guard selfModel.metadata.promptVersions.schemaVersion == promptVersions.schemaVersion else {
      return nil
    }
    guard selfModel.metadata.promptVersions.bootstrapPromptVersion == promptVersions.bootstrapPromptVersion
    else {
      return nil
    }

    let expectedDayKeys = Set(sourceWindow.daySnapshots.map(\.dayKey))
    let actualDayKeys = Set(try await modelStore.availableDaySummaryKeys())
    let actualWeekKeys = Set(try await modelStore.availablePeriodSummaryKeys(granularity: .week))
    let actualMonthKeys = Set(try await modelStore.availablePeriodSummaryKeys(granularity: .month))

    guard actualDayKeys == expectedDayKeys else { return nil }
    guard actualWeekKeys == expectedWeekKeys else { return nil }
    guard actualMonthKeys == expectedMonthKeys else { return nil }

    return CompassBootstrapRunResult(
      generationID: selfModel.metadata.generationID,
      reusedCachedArtifacts: true,
      indexedDayCount: sourceWindow.window.indexedDayCount,
      indexedEntryCount: sourceWindow.window.indexedEntryCount,
      generatedDaySummaryCount: 0,
      generatedWeekSummaryCount: 0,
      generatedMonthSummaryCount: 0
    )
  }

  private func automaticFullRebuildReason(
    manifest: CompassStorageManifest?,
    journalIndex: CompassJournalIndex?,
    selfModel: CompassSelfModel?
  ) -> CompassFullRebuildReason? {
    if manifest == nil, journalIndex == nil, selfModel == nil {
      return .initialBootstrap
    }

    guard let manifest, let journalIndex, let selfModel else {
      return .storageCorruption
    }

    guard !journalIndex.availableDayKeys.isEmpty || selfModel.metadata.sourceWindow.indexedDayCount == 0 else {
      return .journalIndexMismatch
    }

    if manifest.schemaVersion != CompassStorageManifest.currentSchemaVersion
      || selfModel.metadata.promptVersions.schemaVersion != promptVersions.schemaVersion
    {
      return .schemaVersionChanged
    }

    if manifest.promptVersions != promptVersions || selfModel.metadata.promptVersions != promptVersions {
      return .promptVersionChanged
    }

    return nil
  }

  private func blockedFullRebuildMessage() -> String {
    let reasons = CompassFullRebuildReason.allowedUserFacingReasons.map(\.title).joined(separator: ", ")
    return "전체 재분석은 허용된 사유에서만 가능하다: \(reasons)"
  }

  private func bootstrapSafeguardNote(_ circuitBreaker: CompassGenerationCircuitBreaker) -> String {
    let base = "일별 저널은 로컬 요약으로 저장하고, 최근 기간 패턴과 자기모델만 Gemini로 계산했다."
    guard let stopReason = circuitBreaker.stopReason, !stopReason.isEmpty else {
      return base
    }
    return "\(base) \(stopReason)"
  }

  private func beginBootstrapMonitoring(weekKeyCount: Int, monthKeyCount: Int) async {
    let estimate = CompassRunEstimate(
      phase: .bootstrap,
      estimatedRequestCount: min(
        safeguards.bootstrapMaxLLMRequests,
        min(weekKeyCount, safeguards.bootstrapRecentWeekLLMLimit)
          + min(monthKeyCount, safeguards.bootstrapRecentMonthLLMLimit)
          + 1
      ),
      requestCap: safeguards.bootstrapMaxLLMRequests,
      estimatedOutputTokenUpperBound:
        min(weekKeyCount, safeguards.bootstrapRecentWeekLLMLimit)
        * CompassGenerationProfile.periodDigest.defaultMaxOutputTokens
        + min(monthKeyCount, safeguards.bootstrapRecentMonthLLMLimit)
        * CompassGenerationProfile.periodDigest.defaultMaxOutputTokens
        + CompassGenerationProfile.bootstrapSelfModel.defaultMaxOutputTokens,
      knownTokenCap: safeguards.bootstrapMaxKnownTokens
    )
    await runMonitor?.begin(estimate)
  }

  private func reportProgress(_ circuitBreaker: CompassGenerationCircuitBreaker) async {
    await runMonitor?.update(
      CompassRunProgressSnapshot(
        phase: .bootstrap,
        attemptedRequestCount: circuitBreaker.attemptedRequestCount,
        knownTotalTokens: circuitBreaker.knownTotalTokens,
        requestCap: circuitBreaker.maxRequests,
        knownTokenCap: circuitBreaker.maxKnownTokens,
        stopReason: circuitBreaker.stopReason
      )
    )
  }

  private func buildDaySummary(
    for snapshot: CompassBootstrapDaySnapshot,
    metadata: CompassArtifactGenerationMetadata,
    allowLLM: Bool
  ) async -> CompassGeneratedDaySummary {
    let prompt = """
    너는 하루 저널을 구조화하는 분석기다. 결과는 반드시 JSON만 반환하라.

    출력 스키마:
    {
      "summary": "하루의 흐름을 2~4문장으로 사실 위주 요약",
      "highlights": ["핵심 포인트", "핵심 포인트"]
    }

    제약:
    - 한국어
    - highlights는 최대 4개
    - 근거 없는 해석 금지
    - 사실과 관찰 중심

    입력 JSON:
    \(encodedJSON(CompassDaySummaryPromptPayload(dayKey: snapshot.dayKey, entries: snapshot.entries)))
    """

    if
      allowLLM,
      let result = await generator.generate(
        CompassGenerationRequest(prompt: prompt, profile: .journalDigest)
      ),
      let decoded = decodeJSON(CompassDaySummaryPromptResponse.self, from: result.text)
    {
      return CompassGeneratedDaySummary(
        summary: CompassJournalDaySummary(
          dayKey: snapshot.dayKey,
          summary: normalizedSummaryText(decoded.summary),
          highlights: normalizedHighlights(decoded.highlights),
          sourceRevision: snapshot.sourceRevision,
          metadata: metadata
        ),
        usageTotals: usageTotalsFromResponse(result.usage)
      )
    }

    return CompassGeneratedDaySummary(
      summary: CompassJournalDaySummary(
        dayKey: snapshot.dayKey,
        summary: fallbackDaySummary(for: snapshot.entries),
        highlights: fallbackHighlights(for: snapshot.entries),
        sourceRevision: snapshot.sourceRevision,
        metadata: metadata
      )
    )
  }

  private func buildPeriodSummaries(
    granularity: CompassPeriodGranularity,
    daySummaries: [CompassJournalDaySummary],
    generationID: UUID,
    modelConfiguration: CompassModelConfiguration,
    sourceWindow: CompassSourceWindow,
    forceRebuild: Bool,
    circuitBreaker: CompassGenerationCircuitBreaker
  ) async -> CompassPeriodSummaryCollection {
    let grouped = Dictionary(grouping: daySummaries) { summary in
      guard let day = CompassDateKeyCodec.date(fromDayKey: summary.dayKey) else {
        return "unknown"
      }
      switch granularity {
      case .week:
        return CompassDateKeyCodec.weekKey(for: day, calendar: calendar)
      case .month:
        return CompassDateKeyCodec.monthKey(for: day)
      }
    }

    var summaries: [CompassJournalPeriodSummary] = []
    var generatedCount = 0
    var usageTotals = CompassTokenUsageTotals()
    let sortedPeriodKeys = grouped.keys.sorted()
    let llmEligibleKeys = Set(
      sortedPeriodKeys.suffix(
        granularity == .week
          ? safeguards.bootstrapRecentWeekLLMLimit
          : safeguards.bootstrapRecentMonthLLMLimit
      )
    )

    for periodKey in sortedPeriodKeys {
      if Task.isCancelled { break }
      let resolvedDaySummaries = (grouped[periodKey] ?? []).sorted { $0.dayKey < $1.dayKey }
      let sourceRevision = digest(
        resolvedDaySummaries
          .map { "\($0.dayKey):\($0.sourceRevision ?? "none")" }
          .joined(separator: "\n")
      )
      let existingSummary = try? await modelStore.loadPeriodSummary(
        granularity: granularity,
        periodKey: periodKey
      )

      if
        !forceRebuild,
        let existing = existingSummary ?? nil,
        existing.sourceRevision == sourceRevision,
        existing.metadata.promptVersions.bootstrapPromptVersion == promptVersions.bootstrapPromptVersion
      {
        summaries.append(existing)
        continue
      }

      let metadata = makeMetadata(
        generationID: generationID,
        modelConfiguration: modelConfiguration,
        sourceWindow: sourceWindow
      )
      let resolvedSummary: String
      if
        llmEligibleKeys.contains(periodKey),
        circuitBreaker.shouldAttempt(
          budgetMessage: "초기 분석 호출 수를 제한해 나머지 기간 요약은 로컬로 전환했다.",
          tokenBudgetMessage: "초기 분석 토큰 예산을 넘어 나머지 기간 요약은 로컬로 전환했다."
        )
      {
        let prompt = """
        너는 여러 날의 저널 요약을 묶어 패턴을 정리하는 분석기다. 결과는 반드시 JSON만 반환하라.

        출력 스키마:
        {
          "summary": "이 기간의 반복 패턴, 집중 축, 흐름을 3~5문장으로 요약"
        }

        제약:
        - 한국어
        - 사실 기반
        - 과잉 심리 해석 금지

        입력 JSON:
        \(encodedJSON(CompassPeriodSummaryPromptPayload(
          granularity: granularity.rawValue,
          periodKey: periodKey,
          daySummaries: resolvedDaySummaries
        )))
        """

        if
          let result = await generator.generate(
            CompassGenerationRequest(prompt: prompt, profile: .periodDigest)
          ),
          let decoded = decodeJSON(CompassPeriodSummaryPromptResponse.self, from: result.text)
        {
          circuitBreaker.recordSuccess(
            totalTokens: result.usage?.totalTokenCount,
            tokenBudgetMessage: "초기 분석 토큰 예산을 넘어 나머지 기간 요약은 로컬로 전환했다."
          )
          usageTotals.merge(usageTotalsFromResponse(result.usage))
          await reportProgress(circuitBreaker)
          resolvedSummary = normalizedSummaryText(decoded.summary)
        } else {
          if Task.isCancelled {
            await reportProgress(circuitBreaker)
            resolvedSummary = fallbackPeriodSummary(for: resolvedDaySummaries)
            summaries.append(
              CompassJournalPeriodSummary(
                granularity: granularity,
                periodKey: periodKey,
                coveredDayKeys: resolvedDaySummaries.map(\.dayKey),
                summary: resolvedSummary,
                sourceRevision: sourceRevision,
                metadata: metadata
              )
            )
            generatedCount += 1
            break
          }
          circuitBreaker.recordFailure(
            "Gemini 기간 요약 오류가 반복돼 나머지 기간은 로컬 요약으로 전환했다."
          )
          await reportProgress(circuitBreaker)
          resolvedSummary = fallbackPeriodSummary(for: resolvedDaySummaries)
        }
      } else {
        await reportProgress(circuitBreaker)
        resolvedSummary = fallbackPeriodSummary(for: resolvedDaySummaries)
      }

      summaries.append(
        CompassJournalPeriodSummary(
          granularity: granularity,
          periodKey: periodKey,
          coveredDayKeys: resolvedDaySummaries.map(\.dayKey),
          summary: resolvedSummary,
          sourceRevision: sourceRevision,
          metadata: metadata
        )
      )
      generatedCount += 1
    }

    return CompassPeriodSummaryCollection(
      summaries: summaries.sorted { $0.periodKey < $1.periodKey },
      generatedCount: generatedCount,
      usageTotals: usageTotals
    )
  }

  private func buildSelfModel(
    generationID: UUID,
    modelConfiguration: CompassModelConfiguration,
    sourceWindow: CompassSourceWindow,
    sourceRevision: String,
    weeklySummaries: [CompassJournalPeriodSummary],
    monthlySummaries: [CompassJournalPeriodSummary],
    daySummaries: [CompassJournalDaySummary],
    circuitBreaker: CompassGenerationCircuitBreaker
  ) async -> CompassGeneratedSelfModel {
    let metadata = makeMetadata(
      generationID: generationID,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow
    )

    let prompt = """
    너는 사용자의 장기 저널을 바탕으로 실행 지향 자기모델을 만드는 분석기다. 결과는 반드시 JSON만 반환하라.

    출력 스키마:
    {
      "overview": "자기모델 요약",
      "corePersona": [{"axis":"psychology","title":"...","statement":"...","confidence":"high"}],
      "currentSeason": [{"axis":"productivity","title":"...","statement":"...","confidence":"medium"}],
      "operationalTendencies": [{"axis":"productivity","title":"...","statement":"...","confidence":"medium"}],
      "blindSpots": [{"axis":"sociology","title":"...","statement":"...","confidence":"medium"}],
      "steeringRules": [{"title":"...","instruction":"...","rationale":"...","confidence":"high"}]
    }

    제약:
    - 한국어
    - 각 배열은 최대 4개
    - 사용자를 고정적으로 단정하지 말고 패턴 가설로 표현
    - 실행 규칙은 실제 일정/우선순위 제안에 쓸 수 있게 구체적으로 작성

    입력 JSON:
    \(encodedJSON(CompassSelfModelPromptPayload(
      sourceRevision: sourceRevision,
      weeklySummaries: weeklySummaries,
      monthlySummaries: monthlySummaries,
      recentDaySummaries: Array(daySummaries.suffix(14))
    )))
    """

    let dayEvidence = Array(daySummaries.suffix(6)).map {
      CompassEvidencePointer(
        sourceKind: .journalDaySummary,
        sourceID: $0.dayKey,
        dayKey: $0.dayKey,
        excerpt: $0.summary,
        weight: 0.7
      )
    }
    let periodEvidence = (weeklySummaries + monthlySummaries).prefix(4).map {
      CompassEvidencePointer(
        sourceKind: .journalPeriodSummary,
        sourceID: "\($0.granularity.rawValue)-\($0.periodKey)",
        dayKey: $0.coveredDayKeys.last,
        excerpt: $0.summary,
        weight: 0.9
      )
    }
    let blendedEvidence = Array(periodEvidence) + Array(dayEvidence.prefix(2))

    let shouldAttemptSelfModel = circuitBreaker.shouldAttempt(
      budgetMessage: "초기 분석 호출 수를 제한해 자기모델 생성은 로컬 요약으로 마쳤다.",
      tokenBudgetMessage: "초기 분석 토큰 예산을 넘어 자기모델 생성은 로컬 요약으로 마쳤다."
    )
    if shouldAttemptSelfModel {
      if
        let result = await generator.generate(
          CompassGenerationRequest(prompt: prompt, profile: .bootstrapSelfModel)
        ),
        let decoded = decodeJSON(CompassSelfModelPromptResponse.self, from: result.text)
      {
        circuitBreaker.recordSuccess(
          totalTokens: result.usage?.totalTokenCount,
          tokenBudgetMessage: "초기 분석 토큰 예산을 넘어 자기모델 생성은 로컬 요약으로 마쳤다."
        )
        await reportProgress(circuitBreaker)
        return CompassGeneratedSelfModel(
          selfModel: CompassSelfModel(
            metadata: metadata,
            overview: normalizedSummaryText(decoded.overview),
            corePersona: decoded.corePersona.map {
              $0.hypothesis(layer: .corePersona, evidence: Array(periodEvidence))
            },
            currentSeason: decoded.currentSeason.map {
              $0.hypothesis(layer: .currentSeason, evidence: Array(dayEvidence))
            },
            operationalTendencies: decoded.operationalTendencies.map {
              $0.hypothesis(layer: .operationalTendencies, evidence: blendedEvidence)
            },
            blindSpots: decoded.blindSpots.map {
              $0.hypothesis(layer: .blindSpots, evidence: Array(dayEvidence))
            },
            steeringRules: decoded.steeringRules.map {
              $0.rule(evidence: blendedEvidence)
            }
          ),
          usageTotals: usageTotalsFromResponse(result.usage)
        )
      }

      if Task.isCancelled {
        await reportProgress(circuitBreaker)
      } else {
        circuitBreaker.recordFailure(
          "Gemini 자기모델 생성 오류가 반복돼 로컬 요약으로 마쳤다."
        )
        await reportProgress(circuitBreaker)
      }
    }

    return CompassGeneratedSelfModel(
      selfModel: CompassSelfModel(
        metadata: metadata,
        overview: fallbackSelfModelOverview(
          weeklySummaries: weeklySummaries,
          monthlySummaries: monthlySummaries,
          daySummaries: daySummaries
        )
      )
    )
  }

  private func usageTotalsFromResponse(
    _ usage: GeminiGenerateContentSummaryService.SummaryUsage?
  ) -> CompassTokenUsageTotals {
    var totals = CompassTokenUsageTotals()
    totals.record(
      promptTokenCount: usage?.promptTokenCount,
      candidatesTokenCount: usage?.candidatesTokenCount,
      thoughtsTokenCount: usage?.thoughtsTokenCount,
      totalTokenCount: usage?.totalTokenCount
    )
    if usage == nil {
      totals.requestCount = 0
    }
    return totals
  }

  private func makeMetadata(
    generationID: UUID,
    modelConfiguration: CompassModelConfiguration,
    sourceWindow: CompassSourceWindow
  ) -> CompassArtifactGenerationMetadata {
    CompassArtifactGenerationMetadata(
      generationID: generationID,
      createdAt: .now,
      updatedAt: .now,
      promptVersions: promptVersions,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow
    )
  }

  private func makeBootstrapState(generationID: UUID) -> CompassBootstrapState {
    CompassBootstrapState(
      generationID: generationID,
      currentStage: .idle,
      startedAt: .now,
      updatedAt: .now,
      completedAt: nil,
      lastError: nil,
      checkpoints: [
        CompassBootstrapCheckpoint(stage: .journalIndex),
        CompassBootstrapCheckpoint(stage: .daySummaries),
        CompassBootstrapCheckpoint(stage: .periodSummaries),
        CompassBootstrapCheckpoint(stage: .selfModel),
      ]
    )
  }

  private func mark(
    _ state: inout CompassBootstrapState,
    stage: CompassBootstrapStage,
    status: CompassCheckpointStatus,
    detail: String? = nil
  ) {
    state.currentStage = stage
    state.updatedAt = .now
    if status == .failed {
      state.lastError = detail
    }

    if let index = state.checkpoints.firstIndex(where: { $0.stage == stage }) {
      state.checkpoints[index].status = status
      state.checkpoints[index].updatedAt = .now
      state.checkpoints[index].detail = detail
    } else {
      state.checkpoints.append(
        CompassBootstrapCheckpoint(
          stage: stage,
          status: status,
          updatedAt: .now,
          detail: detail
        )
      )
    }
  }

  private func encodedJSON<Value: Encodable>(_ value: Value) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601

    guard let data = try? encoder.encode(value),
      let string = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return string
  }

  private func decodeJSON<Value: Decodable>(_ type: Value.Type, from text: String) -> Value? {
    let candidates = extractedJSONCandidates(from: text)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    for candidate in candidates {
      guard let data = candidate.data(using: .utf8) else { continue }
      if let decoded = try? decoder.decode(Value.self, from: data) {
        return decoded
      }
    }

    return nil
  }

  private func extractedJSONCandidates(from text: String) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    var candidates: [String] = [trimmed]

    if trimmed.hasPrefix("```"), let fenceStart = trimmed.firstIndex(of: "{"), let fenceEnd = trimmed.lastIndex(of: "}") {
      candidates.append(String(trimmed[fenceStart...fenceEnd]))
    }

    if let objectStart = trimmed.firstIndex(of: "{"), let objectEnd = trimmed.lastIndex(of: "}") {
      candidates.append(String(trimmed[objectStart...objectEnd]))
    }

    return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
  }

  private func digest(_ string: String) -> String {
    let hash = SHA256.hash(data: Data(string.utf8))
    return hash.prefix(12).map { String(format: "%02x", $0) }.joined()
  }

  private func normalizedSummaryText(_ text: String) -> String {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    return normalized.isEmpty ? "기록을 정리했다." : normalized
  }

  private func normalizedHighlights(_ highlights: [String]?) -> [String] {
    guard let highlights else { return [] }
    return Array(
      NSOrderedSet(
        array: highlights
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      )
    ) as? [String] ?? []
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

  private func fallbackPeriodSummary(for summaries: [CompassJournalDaySummary]) -> String {
    let snippets = summaries.map(\.summary).filter { !$0.isEmpty }
    if snippets.isEmpty {
      return "이 기간의 기록이 부족해 패턴 요약이 제한적이다."
    }
    return Array(snippets.prefix(3)).joined(separator: "\n")
  }

  private func fallbackSelfModelOverview(
    weeklySummaries: [CompassJournalPeriodSummary],
    monthlySummaries: [CompassJournalPeriodSummary],
    daySummaries: [CompassJournalDaySummary]
  ) -> String {
    let candidates = (weeklySummaries + monthlySummaries).map(\.summary) + daySummaries.map(\.summary)
    let joined = candidates
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .prefix(2)
      .joined(separator: "\n")
    return joined.isEmpty ? "초기 자기모델을 만들 만큼 충분한 기록이 아직 없다." : joined
  }
}

private struct CompassBootstrapSourceWindow {
  var window: CompassSourceWindow
  var daySnapshots: [CompassBootstrapDaySnapshot]
}

private struct CompassBootstrapDaySnapshot {
  var day: Date
  var dayKey: String
  var entries: [ObsidianJournalEntry]
  var sourceRevision: String
}

private struct CompassPeriodSummaryCollection {
  var summaries: [CompassJournalPeriodSummary]
  var generatedCount: Int
  var usageTotals: CompassTokenUsageTotals = CompassTokenUsageTotals()
}

private struct CompassGeneratedDaySummary {
  var summary: CompassJournalDaySummary
  var usageTotals: CompassTokenUsageTotals = CompassTokenUsageTotals()
}

private struct CompassGeneratedSelfModel {
  var selfModel: CompassSelfModel
  var usageTotals: CompassTokenUsageTotals = CompassTokenUsageTotals()
}

private struct CompassDaySummaryPromptPayload: Encodable {
  let dayKey: String
  let entries: [CompassDaySummaryPromptEntry]

  init(dayKey: String, entries: [ObsidianJournalEntry]) {
    self.dayKey = dayKey
    self.entries = entries
      .sorted { $0.occurredAt < $1.occurredAt }
      .map {
        CompassDaySummaryPromptEntry(
          id: $0.id,
          occurredAt: $0.occurredAt,
          body: $0.body
        )
      }
  }
}

private struct CompassDaySummaryPromptEntry: Encodable {
  let id: String
  let occurredAt: Date
  let body: String
}

private struct CompassDaySummaryPromptResponse: Decodable {
  let summary: String
  let highlights: [String]?
}

private struct CompassPeriodSummaryPromptPayload: Encodable {
  let granularity: String
  let periodKey: String
  let daySummaries: [CompassPeriodSummaryPromptDay]

  init(
    granularity: String,
    periodKey: String,
    daySummaries: [CompassJournalDaySummary]
  ) {
    self.granularity = granularity
    self.periodKey = periodKey
    self.daySummaries = daySummaries.map {
      CompassPeriodSummaryPromptDay(
        dayKey: $0.dayKey,
        summary: $0.summary,
        highlights: $0.highlights
      )
    }
  }
}

private struct CompassPeriodSummaryPromptDay: Encodable {
  let dayKey: String
  let summary: String
  let highlights: [String]
}

private struct CompassPeriodSummaryPromptResponse: Decodable {
  let summary: String
}

private struct CompassSelfModelPromptPayload: Encodable {
  let sourceRevision: String
  let weeklySummaries: [CompassSelfModelPromptPeriod]
  let monthlySummaries: [CompassSelfModelPromptPeriod]
  let recentDaySummaries: [CompassSelfModelPromptDay]

  init(
    sourceRevision: String,
    weeklySummaries: [CompassJournalPeriodSummary],
    monthlySummaries: [CompassJournalPeriodSummary],
    recentDaySummaries: [CompassJournalDaySummary]
  ) {
    self.sourceRevision = sourceRevision
    self.weeklySummaries = weeklySummaries.map {
      CompassSelfModelPromptPeriod(
        periodKey: $0.periodKey,
        summary: $0.summary
      )
    }
    self.monthlySummaries = monthlySummaries.map {
      CompassSelfModelPromptPeriod(
        periodKey: $0.periodKey,
        summary: $0.summary
      )
    }
    self.recentDaySummaries = recentDaySummaries.map {
      CompassSelfModelPromptDay(
        dayKey: $0.dayKey,
        summary: $0.summary,
        highlights: $0.highlights
      )
    }
  }
}

private struct CompassSelfModelPromptPeriod: Encodable {
  let periodKey: String
  let summary: String
}

private struct CompassSelfModelPromptDay: Encodable {
  let dayKey: String
  let summary: String
  let highlights: [String]
}

private struct CompassSelfModelPromptResponse: Decodable {
  let overview: String
  let corePersona: [CompassSelfModelPromptHypothesis]
  let currentSeason: [CompassSelfModelPromptHypothesis]
  let operationalTendencies: [CompassSelfModelPromptHypothesis]
  let blindSpots: [CompassSelfModelPromptHypothesis]
  let steeringRules: [CompassSelfModelPromptRule]
}

private struct CompassSelfModelPromptHypothesis: Decodable {
  let axis: CompassInsightAxis
  let title: String
  let statement: String
  let confidence: CompassConfidence

  func hypothesis(
    layer: CompassHypothesisLayer,
    evidence: [CompassEvidencePointer]
  ) -> CompassHypothesis {
    CompassHypothesis(
      layer: layer,
      axis: axis,
      title: title,
      statement: statement,
      confidence: confidence,
      evidence: evidence,
      lastUpdatedAt: .now
    )
  }
}

private struct CompassSelfModelPromptRule: Decodable {
  let title: String
  let instruction: String
  let rationale: String
  let confidence: CompassConfidence

  func rule(evidence: [CompassEvidencePointer]) -> CompassSteeringRule {
    CompassSteeringRule(
      title: title,
      instruction: instruction,
      rationale: rationale,
      confidence: confidence,
      evidence: evidence,
      lastUpdatedAt: .now
    )
  }
}
