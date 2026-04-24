import CryptoKit
import Foundation

enum CompassDeltaUpdateServiceError: LocalizedError {
  case bootstrapRequired

  var errorDescription: String? {
    switch self {
    case .bootstrapRequired:
      return "나침반 초기 부트스트랩이 먼저 필요합니다."
    }
  }
}

struct CompassDeltaUpdateRunResult: Hashable, Sendable {
  var generationID: UUID
  var hadChanges: Bool
  var changedDayKeys: [String]
  var removedDayKeys: [String]
  var refreshedDaySummaryCount: Int
  var refreshedWeekSummaryCount: Int
  var refreshedMonthSummaryCount: Int
  var generatedDailyDeltaCount: Int
  var changedHypothesisCount: Int
  var llmAttemptCount: Int = 0
  var safeguardNote: String? = nil
}

actor CompassDeltaUpdateService {
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

  func updateIfNeeded() async throws -> CompassDeltaUpdateRunResult {
    try await modelStore.prepare()

    guard
      let existingManifest = try await modelStore.loadManifest(),
      let existingIndex = try await modelStore.loadJournalIndex(),
      let existingSelfModel = try await modelStore.loadSelfModel()
    else {
      throw CompassDeltaUpdateServiceError.bootstrapRequired
    }

    let availableDays = try await journalProvider.availableDays()
    let sourceWindow = try await buildSourceWindow(from: availableDays)
    let currentSourceRevision = digest(
      sourceWindow.daySnapshots
        .map { "\($0.dayKey):\($0.sourceRevision)" }
        .joined(separator: "\n")
    )

    let currentDayKeys = sourceWindow.daySnapshots.map(\.dayKey)
    let currentDayKeySet = Set(currentDayKeys)
    let previousDayKeySet = Set(existingIndex.availableDayKeys)
    let removedDayKeys = Array(previousDayKeySet.subtracting(currentDayKeySet)).sorted()

    var changedSnapshots: [CompassDeltaDaySnapshot] = []
    for snapshot in sourceWindow.daySnapshots {
      let existingSummary = try await modelStore.loadDaySummary(for: snapshot.dayKey)
      if
        existingSummary == nil
        || existingSummary?.sourceRevision != snapshot.sourceRevision
        || existingSummary?.metadata.promptVersions.bootstrapPromptVersion
          != promptVersions.bootstrapPromptVersion
      {
        changedSnapshots.append(snapshot)
      }
    }

    if changedSnapshots.isEmpty, removedDayKeys.isEmpty, existingIndex.sourceRevision == currentSourceRevision {
      return CompassDeltaUpdateRunResult(
        generationID: existingSelfModel.metadata.generationID,
        hadChanges: false,
        changedDayKeys: [],
        removedDayKeys: [],
        refreshedDaySummaryCount: 0,
        refreshedWeekSummaryCount: 0,
        refreshedMonthSummaryCount: 0,
        generatedDailyDeltaCount: 0,
        changedHypothesisCount: 0
      )
    }

    let generationID = UUID()
    let modelConfiguration = await generator.loadModelConfiguration()
    let circuitBreaker = CompassGenerationCircuitBreaker(
      maxRequests: safeguards.deltaMaxLLMRequests,
      maxKnownTokens: safeguards.deltaMaxKnownTokens,
      maxConsecutiveFailures: safeguards.maxConsecutiveFailures
    )
    let metadata = makeMetadata(
      generationID: generationID,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow.window
    )
    var usageTotals = CompassTokenUsageTotals()

    for dayKey in removedDayKeys {
      try await modelStore.deleteDaySummary(for: dayKey)
      try await modelStore.deleteDailyDelta(for: dayKey)
    }

    var daySummariesByKey: [String: CompassJournalDaySummary] = [:]
    var refreshedDaySummaryCount = 0
    let changedDayKeySet = Set(changedSnapshots.map(\.dayKey))

    for snapshot in sourceWindow.daySnapshots {
      if changedDayKeySet.contains(snapshot.dayKey) {
        let summary = await buildDaySummary(
          for: snapshot,
          metadata: metadata,
          allowLLM: false
        )
        usageTotals.merge(summary.usageTotals)
        try await modelStore.saveDaySummary(summary.summary)
        daySummariesByKey[snapshot.dayKey] = summary.summary
        refreshedDaySummaryCount += 1
      } else if let existing = try await modelStore.loadDaySummary(for: snapshot.dayKey) {
        daySummariesByKey[snapshot.dayKey] = existing
      } else {
        let summary = await buildDaySummary(
          for: snapshot,
          metadata: metadata,
          allowLLM: false
        )
        usageTotals.merge(summary.usageTotals)
        try await modelStore.saveDaySummary(summary.summary)
        daySummariesByKey[snapshot.dayKey] = summary.summary
        refreshedDaySummaryCount += 1
      }
    }

    let currentDaySummaries = daySummariesByKey.values.sorted { $0.dayKey < $1.dayKey }
    let affectedDayKeys = changedDayKeySet.union(removedDayKeys)
    await beginDeltaMonitoring(
      affectedWeekCount: Set(affectedDayKeys.compactMap { periodKey(for: $0, granularity: .week) }).count,
      affectedMonthCount: Set(affectedDayKeys.compactMap { periodKey(for: $0, granularity: .month) }).count
    )

    let weeklyUpdate = try await refreshPeriodSummaries(
      granularity: .week,
      affectedDayKeys: affectedDayKeys,
      daySummaries: currentDaySummaries,
      generationID: generationID,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow.window,
      circuitBreaker: circuitBreaker
    )
    usageTotals.merge(weeklyUpdate.usageTotals)
    try Task.checkCancellation()
    let monthlyUpdate = try await refreshPeriodSummaries(
      granularity: .month,
      affectedDayKeys: affectedDayKeys,
      daySummaries: currentDaySummaries,
      generationID: generationID,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow.window,
      circuitBreaker: circuitBreaker
    )
    usageTotals.merge(monthlyUpdate.usageTotals)
    try Task.checkCancellation()

    let updatedJournalIndex = CompassJournalIndex(
      indexedAt: .now,
      journalRootPath: await journalProvider.rootPath(),
      availableDayKeys: currentDayKeys,
      sourceRevision: currentSourceRevision
    )
    try await modelStore.saveJournalIndex(updatedJournalIndex)

    let patch = await buildPatchedSelfModel(
      previous: existingSelfModel,
      generationID: generationID,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow.window,
      sourceRevision: currentSourceRevision,
      changedDaySummaries: changedSnapshots
        .compactMap { daySummariesByKey[$0.dayKey] }
        .sorted { $0.dayKey < $1.dayKey },
      affectedWeekSummaries: weeklyUpdate.currentSummaries,
      affectedMonthSummaries: monthlyUpdate.currentSummaries,
      recentDaySummaries: Array(currentDaySummaries.suffix(14)),
      circuitBreaker: circuitBreaker
    )
    usageTotals.merge(patch.usageTotals)
    try Task.checkCancellation()
    try await modelStore.saveSelfModel(patch.patch.selfModel)

    let changedHypothesisIDs = Array(patch.patch.changedHypothesisIDs)
    var generatedDailyDeltaCount = 0
    for snapshot in changedSnapshots.sorted(by: { $0.dayKey < $1.dayKey }) {
      guard let daySummary = daySummariesByKey[snapshot.dayKey] else { continue }

      let weekKey = periodKey(for: snapshot.dayKey, granularity: .week)
      let monthKey = periodKey(for: snapshot.dayKey, granularity: .month)
      let weeklySummary = weekKey.flatMap { key in
        weeklyUpdate.currentSummaries.first(where: { $0.periodKey == key })
      }
      let monthlySummary = monthKey.flatMap { key in
        monthlyUpdate.currentSummaries.first(where: { $0.periodKey == key })
      }

      let delta = await buildDailyDelta(
        daySummary: daySummary,
        weeklySummary: weeklySummary,
        monthlySummary: monthlySummary,
        previousSelfModel: existingSelfModel,
        updatedSelfModel: patch.patch.selfModel,
        changedHypothesisIDs: changedHypothesisIDs,
        metadata: metadata,
        allowLLM: false
      )
      usageTotals.merge(delta.usageTotals)
      try await modelStore.saveDailyDelta(delta.delta)
      generatedDailyDeltaCount += 1
    }

    let manifest = CompassStorageManifest(
      schemaVersion: existingManifest.schemaVersion,
      createdAt: existingManifest.createdAt,
      updatedAt: .now,
      promptVersions: promptVersions,
      activeModelConfiguration: modelConfiguration,
      lastFullAnalysisAt: existingManifest.lastFullAnalysisAt,
      lastIncrementalUpdateAt: .now
    )
    try await modelStore.saveManifest(manifest)
    try await safetyService.recordUsageTotals(phase: .delta, totals: usageTotals)
    await runMonitor?.finish(deltaSafeguardNote(circuitBreaker))

    return CompassDeltaUpdateRunResult(
      generationID: generationID,
      hadChanges: true,
      changedDayKeys: changedSnapshots.map(\.dayKey).sorted(),
      removedDayKeys: removedDayKeys,
      refreshedDaySummaryCount: refreshedDaySummaryCount,
      refreshedWeekSummaryCount: weeklyUpdate.generatedCount,
      refreshedMonthSummaryCount: monthlyUpdate.generatedCount,
      generatedDailyDeltaCount: generatedDailyDeltaCount,
      changedHypothesisCount: patch.patch.changedHypothesisIDs.count,
      llmAttemptCount: circuitBreaker.attemptedRequestCount,
      safeguardNote: deltaSafeguardNote(circuitBreaker)
    )
  }

  private func deltaSafeguardNote(_ circuitBreaker: CompassGenerationCircuitBreaker) -> String {
    let base = "변경 일자 요약과 하루 델타는 로컬로 저장하고, 패턴 갱신과 자기모델 패치만 Gemini로 계산했다."
    guard let stopReason = circuitBreaker.stopReason, !stopReason.isEmpty else {
      return base
    }
    return "\(base) \(stopReason)"
  }

  private func beginDeltaMonitoring(affectedWeekCount: Int, affectedMonthCount: Int) async {
    let estimate = CompassRunEstimate(
      phase: .delta,
      estimatedRequestCount: min(
        safeguards.deltaMaxLLMRequests,
        affectedWeekCount + affectedMonthCount + 1
      ),
      requestCap: safeguards.deltaMaxLLMRequests,
      estimatedOutputTokenUpperBound:
        affectedWeekCount * CompassGenerationProfile.periodDigest.defaultMaxOutputTokens
        + affectedMonthCount * CompassGenerationProfile.periodDigest.defaultMaxOutputTokens
        + CompassGenerationProfile.bootstrapSelfModel.defaultMaxOutputTokens,
      knownTokenCap: safeguards.deltaMaxKnownTokens
    )
    await runMonitor?.begin(estimate)
  }

  private func reportProgress(_ circuitBreaker: CompassGenerationCircuitBreaker) async {
    await runMonitor?.update(
      CompassRunProgressSnapshot(
        phase: .delta,
        attemptedRequestCount: circuitBreaker.attemptedRequestCount,
        knownTotalTokens: circuitBreaker.knownTotalTokens,
        requestCap: circuitBreaker.maxRequests,
        knownTokenCap: circuitBreaker.maxKnownTokens,
        stopReason: circuitBreaker.stopReason
      )
    )
  }

  private func buildSourceWindow(
    from availableDays: [Date]
  ) async throws -> CompassDeltaSourceWindow {
    var snapshots: [CompassDeltaDaySnapshot] = []
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
        CompassDeltaDaySnapshot(
          day: day,
          dayKey: dayKey,
          entries: entries,
          sourceRevision: sourceRevision
        )
      )
      indexedEntryCount += entries.count
    }

    let sortedSnapshots = snapshots.sorted { $0.day < $1.day }
    return CompassDeltaSourceWindow(
      window: CompassSourceWindow(
        firstJournalDay: sortedSnapshots.first?.day,
        lastJournalDay: sortedSnapshots.last?.day,
        indexedDayCount: sortedSnapshots.count,
        indexedEntryCount: indexedEntryCount
      ),
      daySnapshots: sortedSnapshots
    )
  }

  private func refreshPeriodSummaries(
    granularity: CompassPeriodGranularity,
    affectedDayKeys: Set<String>,
    daySummaries: [CompassJournalDaySummary],
    generationID: UUID,
    modelConfiguration: CompassModelConfiguration,
    sourceWindow: CompassSourceWindow,
    circuitBreaker: CompassGenerationCircuitBreaker
  ) async throws -> CompassDeltaPeriodUpdate {
    let grouped = Dictionary(grouping: daySummaries) { summary in
      periodKey(for: summary.dayKey, granularity: granularity) ?? "unknown"
    }

    let affectedPeriodKeys = Set(
      affectedDayKeys.compactMap { periodKey(for: $0, granularity: granularity) }
    )

    guard !affectedPeriodKeys.isEmpty else {
      return CompassDeltaPeriodUpdate(currentSummaries: [], generatedCount: 0)
    }

    var currentSummaries: [CompassJournalPeriodSummary] = []
    var generatedCount = 0
    var usageTotals = CompassTokenUsageTotals()

    for periodKey in affectedPeriodKeys.sorted() {
      try Task.checkCancellation()
      let covered = (grouped[periodKey] ?? []).sorted { $0.dayKey < $1.dayKey }

      guard !covered.isEmpty else {
        try await modelStore.deletePeriodSummary(granularity: granularity, periodKey: periodKey)
        continue
      }

      let sourceRevision = digest(
        covered
          .map { "\($0.dayKey):\($0.sourceRevision ?? "none")" }
          .joined(separator: "\n")
      )

      if
        let existing = try await modelStore.loadPeriodSummary(
          granularity: granularity,
          periodKey: periodKey
        ),
        existing.sourceRevision == sourceRevision,
        existing.metadata.promptVersions.bootstrapPromptVersion == promptVersions.bootstrapPromptVersion
      {
        currentSummaries.append(existing)
        continue
      }

      let summary = await buildPeriodSummary(
        granularity: granularity,
        periodKey: periodKey,
        daySummaries: covered,
        sourceRevision: sourceRevision,
        metadata: makeMetadata(
          generationID: generationID,
          modelConfiguration: modelConfiguration,
          sourceWindow: sourceWindow
        ),
        allowLLM: circuitBreaker.shouldAttempt(
          budgetMessage: "증분 갱신 호출 수를 제한해 나머지 기간 갱신은 로컬 요약으로 전환했다.",
          tokenBudgetMessage: "증분 갱신 토큰 예산을 넘어 나머지 기간 갱신은 로컬 요약으로 전환했다."
        ),
        circuitBreaker: circuitBreaker
      )
      usageTotals.merge(summary.usageTotals)
      try await modelStore.savePeriodSummary(summary.summary)
      currentSummaries.append(summary.summary)
      generatedCount += 1
    }

    return CompassDeltaPeriodUpdate(
      currentSummaries: currentSummaries.sorted { $0.periodKey < $1.periodKey },
      generatedCount: generatedCount,
      usageTotals: usageTotals
    )
  }

  private func buildDaySummary(
    for snapshot: CompassDeltaDaySnapshot,
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
    \(encodedJSON(CompassDeltaDaySummaryPromptPayload(dayKey: snapshot.dayKey, entries: snapshot.entries)))
    """

    if
      allowLLM,
      let result = await generator.generate(
        CompassGenerationRequest(prompt: prompt, profile: .journalDigest)
      ),
      let decoded = decodeJSON(CompassDeltaDaySummaryPromptResponse.self, from: result.text)
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

  private func buildPeriodSummary(
    granularity: CompassPeriodGranularity,
    periodKey: String,
    daySummaries: [CompassJournalDaySummary],
    sourceRevision: String,
    metadata: CompassArtifactGenerationMetadata,
    allowLLM: Bool,
    circuitBreaker: CompassGenerationCircuitBreaker
  ) async -> CompassGeneratedPeriodSummary {
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
    \(encodedJSON(CompassDeltaPeriodSummaryPromptPayload(
      granularity: granularity.rawValue,
      periodKey: periodKey,
      daySummaries: daySummaries
    )))
    """

    let resolvedSummary: String
    if
      allowLLM,
      let result = await generator.generate(
        CompassGenerationRequest(prompt: prompt, profile: .periodDigest)
      ),
      let decoded = decodeJSON(CompassDeltaPeriodSummaryPromptResponse.self, from: result.text)
    {
      circuitBreaker.recordSuccess(
        totalTokens: result.usage?.totalTokenCount,
        tokenBudgetMessage: "증분 갱신 토큰 예산을 넘어 나머지 기간 갱신은 로컬 요약으로 전환했다."
      )
      await reportProgress(circuitBreaker)
      let usageTotals = usageTotalsFromResponse(result.usage)
      resolvedSummary = normalizedSummaryText(decoded.summary)
      return CompassGeneratedPeriodSummary(
        summary: CompassJournalPeriodSummary(
          granularity: granularity,
          periodKey: periodKey,
          coveredDayKeys: daySummaries.map(\.dayKey),
          summary: resolvedSummary,
          sourceRevision: sourceRevision,
          metadata: metadata
        ),
        usageTotals: usageTotals
      )
    } else {
      if allowLLM {
        if Task.isCancelled {
          await reportProgress(circuitBreaker)
        } else {
          circuitBreaker.recordFailure(
            "Gemini 증분 기간 요약 오류가 반복돼 나머지 갱신은 로컬 요약으로 전환했다."
          )
          await reportProgress(circuitBreaker)
        }
      }
      resolvedSummary = fallbackPeriodSummary(for: daySummaries)
    }

    return CompassGeneratedPeriodSummary(
      summary: CompassJournalPeriodSummary(
        granularity: granularity,
        periodKey: periodKey,
        coveredDayKeys: daySummaries.map(\.dayKey),
        summary: resolvedSummary,
        sourceRevision: sourceRevision,
        metadata: metadata
      )
    )
  }

  private func buildPatchedSelfModel(
    previous: CompassSelfModel,
    generationID: UUID,
    modelConfiguration: CompassModelConfiguration,
    sourceWindow: CompassSourceWindow,
    sourceRevision: String,
    changedDaySummaries: [CompassJournalDaySummary],
    affectedWeekSummaries: [CompassJournalPeriodSummary],
    affectedMonthSummaries: [CompassJournalPeriodSummary],
    recentDaySummaries: [CompassJournalDaySummary],
    circuitBreaker: CompassGenerationCircuitBreaker
  ) async -> CompassGeneratedDeltaSelfModelPatch {
    let metadata = CompassArtifactGenerationMetadata(
      generationID: generationID,
      createdAt: previous.metadata.createdAt,
      updatedAt: .now,
      promptVersions: promptVersions,
      modelConfiguration: modelConfiguration,
      sourceWindow: sourceWindow
    )

    let prompt = """
    너는 기존 자기모델을 증분 갱신하는 분석기다. 결과는 반드시 JSON만 반환하라.

    출력 스키마:
    {
      "overview": "업데이트된 자기모델 요약",
      "corePersona": [{"axis":"psychology","title":"...","statement":"...","confidence":"high"}],
      "currentSeason": [{"axis":"productivity","title":"...","statement":"...","confidence":"medium"}],
      "operationalTendencies": [{"axis":"productivity","title":"...","statement":"...","confidence":"medium"}],
      "blindSpots": [{"axis":"sociology","title":"...","statement":"...","confidence":"medium"}],
      "steeringRules": [{"title":"...","instruction":"...","rationale":"...","confidence":"high"}]
    }

    제약:
    - 한국어
    - 기존 자기모델을 바탕으로 필요한 부분만 조정하되, 최신 결과는 완성된 전체 자기모델 형태로 반환
    - 새 근거가 약하면 기존 안정적 특성은 함부로 바꾸지 말 것
    - 각 배열은 최대 4개
    - 사용자를 고정적으로 단정하지 말고 패턴 가설로 표현
    - 실행 규칙은 실제 일정/우선순위 제안에 쓸 수 있게 구체적으로 작성

    입력 JSON:
    \(encodedJSON(CompassDeltaSelfModelPromptPayload(
      sourceRevision: sourceRevision,
      existingSelfModel: previous,
      changedDaySummaries: changedDaySummaries,
      affectedWeekSummaries: affectedWeekSummaries,
      affectedMonthSummaries: affectedMonthSummaries,
      recentDaySummaries: recentDaySummaries
    )))
    """

    let evidence = patchEvidence(
      changedDaySummaries: changedDaySummaries,
      affectedWeekSummaries: affectedWeekSummaries,
      affectedMonthSummaries: affectedMonthSummaries
    )

    let shouldAttemptPatch = circuitBreaker.shouldAttempt(
      budgetMessage: "증분 갱신 호출 수를 제한해 자기모델 패치는 로컬 상태를 유지했다.",
      tokenBudgetMessage: "증분 갱신 토큰 예산을 넘어 자기모델 패치는 로컬 상태를 유지했다."
    )
    if shouldAttemptPatch {
      if
        let result = await generator.generate(
          CompassGenerationRequest(
            prompt: prompt,
            profile: .deltaPatch,
            roleOverride: .primary,
            maxOutputTokensOverride: CompassGenerationProfile.bootstrapSelfModel.defaultMaxOutputTokens
          )
        ),
        let decoded = decodeJSON(CompassDeltaSelfModelPromptResponse.self, from: result.text)
      {
        circuitBreaker.recordSuccess(
          totalTokens: result.usage?.totalTokenCount,
          tokenBudgetMessage: "증분 갱신 토큰 예산을 넘어 자기모델 패치는 로컬 상태를 유지했다."
        )
        await reportProgress(circuitBreaker)
        return CompassGeneratedDeltaSelfModelPatch(
          patch: mergePatchedSelfModel(
            previous: previous,
            response: decoded,
            metadata: metadata,
            evidence: evidence
          ),
          usageTotals: usageTotalsFromResponse(result.usage)
        )
      }

      if Task.isCancelled {
        await reportProgress(circuitBreaker)
      } else {
        circuitBreaker.recordFailure(
          "Gemini 자기모델 패치 오류가 반복돼 기존 자기모델을 유지했다."
        )
        await reportProgress(circuitBreaker)
      }
    }

    return CompassGeneratedDeltaSelfModelPatch(
      patch: CompassDeltaSelfModelPatch(
        selfModel: CompassSelfModel(
          metadata: metadata,
          overview: previous.overview,
          corePersona: previous.corePersona,
          currentSeason: previous.currentSeason,
          operationalTendencies: previous.operationalTendencies,
          blindSpots: previous.blindSpots,
          steeringRules: previous.steeringRules
        ),
        changedHypothesisIDs: []
      )
    )
  }

  private func buildDailyDelta(
    daySummary: CompassJournalDaySummary,
    weeklySummary: CompassJournalPeriodSummary?,
    monthlySummary: CompassJournalPeriodSummary?,
    previousSelfModel: CompassSelfModel,
    updatedSelfModel: CompassSelfModel,
    changedHypothesisIDs: [UUID],
    metadata: CompassArtifactGenerationMetadata,
    allowLLM: Bool
  ) async -> CompassGeneratedDailyDelta {
    let prompt = """
    너는 하루 단위 자기모델 변화 요약을 만드는 분석기다. 결과는 반드시 JSON만 반환하라.

    출력 스키마:
    {
      "summary": "오늘 기록이 자기모델에 어떤 변화를 만들었는지 2~4문장으로 설명"
    }

    제약:
    - 한국어
    - 과장 금지
    - 행동 패턴과 실행 함의 중심

    입력 JSON:
    \(encodedJSON(CompassDailyDeltaPromptPayload(
      daySummary: daySummary,
      weeklySummary: weeklySummary,
      monthlySummary: monthlySummary,
      previousOverview: previousSelfModel.overview,
      updatedOverview: updatedSelfModel.overview
    )))
    """

    if
      allowLLM,
      let result = await generator.generate(
        CompassGenerationRequest(prompt: prompt, profile: .deltaPatch)
      ),
      let decoded = decodeJSON(CompassDailyDeltaPromptResponse.self, from: result.text)
    {
      return CompassGeneratedDailyDelta(
        delta: CompassDailyDelta(
          dayKey: daySummary.dayKey,
          summary: normalizedSummaryText(decoded.summary),
          changedHypothesisIDs: changedHypothesisIDs,
          metadata: metadata
        ),
        usageTotals: usageTotalsFromResponse(result.usage)
      )
    }

    return CompassGeneratedDailyDelta(
      delta: CompassDailyDelta(
        dayKey: daySummary.dayKey,
        summary: fallbackDailyDeltaSummary(for: daySummary, updatedOverview: updatedSelfModel.overview),
        changedHypothesisIDs: changedHypothesisIDs,
        metadata: metadata
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

  private func mergePatchedSelfModel(
    previous: CompassSelfModel,
    response: CompassDeltaSelfModelPromptResponse,
    metadata: CompassArtifactGenerationMetadata,
    evidence: [CompassEvidencePointer]
  ) -> CompassDeltaSelfModelPatch {
    let corePersonaMerge = mergeHypotheses(
      incoming: response.corePersona,
      previous: previous.corePersona,
      layer: .corePersona,
      evidence: evidence
    )
    let currentSeasonMerge = mergeHypotheses(
      incoming: response.currentSeason,
      previous: previous.currentSeason,
      layer: .currentSeason,
      evidence: evidence
    )
    let operationalMerge = mergeHypotheses(
      incoming: response.operationalTendencies,
      previous: previous.operationalTendencies,
      layer: .operationalTendencies,
      evidence: evidence
    )
    let blindSpotMerge = mergeHypotheses(
      incoming: response.blindSpots,
      previous: previous.blindSpots,
      layer: .blindSpots,
      evidence: evidence
    )
    let steeringRuleMerge = mergeRules(
      incoming: response.steeringRules,
      previous: previous.steeringRules,
      evidence: evidence
    )

    let model = CompassSelfModel(
      metadata: metadata,
      overview: normalizedSummaryText(response.overview),
      corePersona: corePersonaMerge.items,
      currentSeason: currentSeasonMerge.items,
      operationalTendencies: operationalMerge.items,
      blindSpots: blindSpotMerge.items,
      steeringRules: steeringRuleMerge
    )

    let changedIDs = Set(corePersonaMerge.changedIDs)
      .union(currentSeasonMerge.changedIDs)
      .union(operationalMerge.changedIDs)
      .union(blindSpotMerge.changedIDs)

    return CompassDeltaSelfModelPatch(
      selfModel: model,
      changedHypothesisIDs: Array(changedIDs)
    )
  }

  private func mergeHypotheses(
    incoming: [CompassDeltaSelfModelPromptHypothesis],
    previous: [CompassHypothesis],
    layer: CompassHypothesisLayer,
    evidence: [CompassEvidencePointer]
  ) -> CompassMergedHypothesisResult {
    let previousByKey = Dictionary(
      uniqueKeysWithValues: previous.map { (hypothesisKey(for: $0.axis, title: $0.title), $0) }
    )

    var merged: [CompassHypothesis] = []
    var changedIDs: [UUID] = []

    for payload in incoming {
      let key = hypothesisKey(for: payload.axis, title: payload.title)
      if let existing = previousByKey[key] {
        let statement = normalizedSummaryText(payload.statement)
        let didChange =
          existing.statement != statement
          || existing.confidence != payload.confidence
          || existing.axis != payload.axis

        let next = CompassHypothesis(
          id: existing.id,
          layer: layer,
          axis: payload.axis,
          title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines),
          statement: statement,
          confidence: payload.confidence,
          evidence: didChange ? mergedEvidence(existing.evidence, evidence) : existing.evidence,
          lastUpdatedAt: didChange ? .now : existing.lastUpdatedAt
        )
        merged.append(next)
        if didChange {
          changedIDs.append(existing.id)
        }
      } else {
        let created = CompassHypothesis(
          layer: layer,
          axis: payload.axis,
          title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines),
          statement: normalizedSummaryText(payload.statement),
          confidence: payload.confidence,
          evidence: evidence,
          lastUpdatedAt: .now
        )
        merged.append(created)
        changedIDs.append(created.id)
      }
    }

    return CompassMergedHypothesisResult(items: merged, changedIDs: changedIDs)
  }

  private func mergeRules(
    incoming: [CompassDeltaSelfModelPromptRule],
    previous: [CompassSteeringRule],
    evidence: [CompassEvidencePointer]
  ) -> [CompassSteeringRule] {
    let previousByKey = Dictionary(
      uniqueKeysWithValues: previous.map { (ruleKey(for: $0.title), $0) }
    )

    return incoming.map { payload in
      let key = ruleKey(for: payload.title)
      if let existing = previousByKey[key] {
        let instruction = normalizedSummaryText(payload.instruction)
        let rationale = normalizedSummaryText(payload.rationale)
        let didChange =
          existing.instruction != instruction
          || existing.rationale != rationale
          || existing.confidence != payload.confidence

        return CompassSteeringRule(
          id: existing.id,
          title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines),
          instruction: instruction,
          rationale: rationale,
          confidence: payload.confidence,
          evidence: didChange ? mergedEvidence(existing.evidence, evidence) : existing.evidence,
          lastUpdatedAt: didChange ? .now : existing.lastUpdatedAt
        )
      }

      return CompassSteeringRule(
        title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines),
        instruction: normalizedSummaryText(payload.instruction),
        rationale: normalizedSummaryText(payload.rationale),
        confidence: payload.confidence,
        evidence: evidence,
        lastUpdatedAt: .now
      )
    }
  }

  private func patchEvidence(
    changedDaySummaries: [CompassJournalDaySummary],
    affectedWeekSummaries: [CompassJournalPeriodSummary],
    affectedMonthSummaries: [CompassJournalPeriodSummary]
  ) -> [CompassEvidencePointer] {
    let dayEvidence = changedDaySummaries.map {
      CompassEvidencePointer(
        sourceKind: .journalDaySummary,
        sourceID: $0.dayKey,
        dayKey: $0.dayKey,
        excerpt: $0.summary,
        weight: 0.7
      )
    }

    let periodEvidence = (affectedWeekSummaries + affectedMonthSummaries).map {
      CompassEvidencePointer(
        sourceKind: .journalPeriodSummary,
        sourceID: "\($0.granularity.rawValue)-\($0.periodKey)",
        dayKey: $0.coveredDayKeys.last,
        excerpt: $0.summary,
        weight: 0.9
      )
    }

    return mergedEvidence(periodEvidence, dayEvidence)
  }

  private func mergedEvidence(
    _ existing: [CompassEvidencePointer],
    _ additional: [CompassEvidencePointer]
  ) -> [CompassEvidencePointer] {
    var seen: Set<String> = []
    var merged: [CompassEvidencePointer] = []

    for pointer in existing + additional {
      let key = "\(pointer.sourceKind.rawValue)|\(pointer.sourceID)|\(pointer.dayKey ?? "")"
      if seen.insert(key).inserted {
        merged.append(pointer)
      }
    }

    return merged
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

  private func periodKey(for dayKey: String, granularity: CompassPeriodGranularity) -> String? {
    guard let day = CompassDateKeyCodec.date(fromDayKey: dayKey) else { return nil }
    switch granularity {
    case .week:
      return CompassDateKeyCodec.weekKey(for: day, calendar: calendar)
    case .month:
      return CompassDateKeyCodec.monthKey(for: day)
    }
  }

  private func hypothesisKey(for axis: CompassInsightAxis, title: String) -> String {
    "\(axis.rawValue)|\(normalizedLookupToken(title))"
  }

  private func ruleKey(for title: String) -> String {
    normalizedLookupToken(title)
  }

  private func normalizedLookupToken(_ text: String) -> String {
    text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .autoupdatingCurrent)
      .lowercased()
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

    if trimmed.hasPrefix("```"),
      let fenceStart = trimmed.firstIndex(of: "{"),
      let fenceEnd = trimmed.lastIndex(of: "}")
    {
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

  private func fallbackDailyDeltaSummary(
    for daySummary: CompassJournalDaySummary,
    updatedOverview: String
  ) -> String {
    if updatedOverview.isEmpty {
      return daySummary.summary
    }
    return "\(daySummary.summary)\n\(updatedOverview)"
  }
}

private struct CompassDeltaSourceWindow {
  var window: CompassSourceWindow
  var daySnapshots: [CompassDeltaDaySnapshot]
}

private struct CompassDeltaDaySnapshot {
  var day: Date
  var dayKey: String
  var entries: [ObsidianJournalEntry]
  var sourceRevision: String
}

private struct CompassDeltaPeriodUpdate {
  var currentSummaries: [CompassJournalPeriodSummary]
  var generatedCount: Int
  var usageTotals: CompassTokenUsageTotals = CompassTokenUsageTotals()
}

private struct CompassGeneratedDaySummary {
  var summary: CompassJournalDaySummary
  var usageTotals: CompassTokenUsageTotals = CompassTokenUsageTotals()
}

private struct CompassGeneratedPeriodSummary {
  var summary: CompassJournalPeriodSummary
  var usageTotals: CompassTokenUsageTotals = CompassTokenUsageTotals()
}

private struct CompassGeneratedDeltaSelfModelPatch {
  var patch: CompassDeltaSelfModelPatch
  var usageTotals: CompassTokenUsageTotals = CompassTokenUsageTotals()
}

private struct CompassGeneratedDailyDelta {
  var delta: CompassDailyDelta
  var usageTotals: CompassTokenUsageTotals = CompassTokenUsageTotals()
}

private struct CompassDeltaSelfModelPatch {
  var selfModel: CompassSelfModel
  var changedHypothesisIDs: [UUID]
}

private struct CompassMergedHypothesisResult {
  var items: [CompassHypothesis]
  var changedIDs: [UUID]
}

private struct CompassDeltaDaySummaryPromptPayload: Encodable {
  let dayKey: String
  let entries: [CompassDeltaDaySummaryPromptEntry]

  init(dayKey: String, entries: [ObsidianJournalEntry]) {
    self.dayKey = dayKey
    self.entries = entries
      .sorted { $0.occurredAt < $1.occurredAt }
      .map {
        CompassDeltaDaySummaryPromptEntry(
          id: $0.id,
          occurredAt: $0.occurredAt,
          body: $0.body
        )
      }
  }
}

private struct CompassDeltaDaySummaryPromptEntry: Encodable {
  let id: String
  let occurredAt: Date
  let body: String
}

private struct CompassDeltaDaySummaryPromptResponse: Decodable {
  let summary: String
  let highlights: [String]?
}

private struct CompassDeltaPeriodSummaryPromptPayload: Encodable {
  let granularity: String
  let periodKey: String
  let daySummaries: [CompassDeltaPeriodSummaryPromptDay]

  init(
    granularity: String,
    periodKey: String,
    daySummaries: [CompassJournalDaySummary]
  ) {
    self.granularity = granularity
    self.periodKey = periodKey
    self.daySummaries = daySummaries.map {
      CompassDeltaPeriodSummaryPromptDay(
        dayKey: $0.dayKey,
        summary: $0.summary,
        highlights: $0.highlights
      )
    }
  }
}

private struct CompassDeltaPeriodSummaryPromptDay: Encodable {
  let dayKey: String
  let summary: String
  let highlights: [String]
}

private struct CompassDeltaPeriodSummaryPromptResponse: Decodable {
  let summary: String
}

private struct CompassDeltaSelfModelPromptPayload: Encodable {
  let sourceRevision: String
  let existingSelfModel: CompassDeltaExistingSelfModelPromptPayload
  let changedDaySummaries: [CompassDeltaSelfModelPromptDay]
  let affectedWeekSummaries: [CompassDeltaSelfModelPromptPeriod]
  let affectedMonthSummaries: [CompassDeltaSelfModelPromptPeriod]
  let recentDaySummaries: [CompassDeltaSelfModelPromptDay]

  init(
    sourceRevision: String,
    existingSelfModel: CompassSelfModel,
    changedDaySummaries: [CompassJournalDaySummary],
    affectedWeekSummaries: [CompassJournalPeriodSummary],
    affectedMonthSummaries: [CompassJournalPeriodSummary],
    recentDaySummaries: [CompassJournalDaySummary]
  ) {
    self.sourceRevision = sourceRevision
    self.existingSelfModel = CompassDeltaExistingSelfModelPromptPayload(model: existingSelfModel)
    self.changedDaySummaries = changedDaySummaries.map {
      CompassDeltaSelfModelPromptDay(
        dayKey: $0.dayKey,
        summary: $0.summary,
        highlights: $0.highlights
      )
    }
    self.affectedWeekSummaries = affectedWeekSummaries.map {
      CompassDeltaSelfModelPromptPeriod(periodKey: $0.periodKey, summary: $0.summary)
    }
    self.affectedMonthSummaries = affectedMonthSummaries.map {
      CompassDeltaSelfModelPromptPeriod(periodKey: $0.periodKey, summary: $0.summary)
    }
    self.recentDaySummaries = recentDaySummaries.map {
      CompassDeltaSelfModelPromptDay(
        dayKey: $0.dayKey,
        summary: $0.summary,
        highlights: $0.highlights
      )
    }
  }
}

private struct CompassDeltaExistingSelfModelPromptPayload: Encodable {
  let overview: String
  let corePersona: [CompassDeltaPromptHypothesisPayload]
  let currentSeason: [CompassDeltaPromptHypothesisPayload]
  let operationalTendencies: [CompassDeltaPromptHypothesisPayload]
  let blindSpots: [CompassDeltaPromptHypothesisPayload]
  let steeringRules: [CompassDeltaPromptRulePayload]

  init(model: CompassSelfModel) {
    overview = model.overview
    corePersona = model.corePersona.map { CompassDeltaPromptHypothesisPayload(hypothesis: $0) }
    currentSeason = model.currentSeason.map { CompassDeltaPromptHypothesisPayload(hypothesis: $0) }
    operationalTendencies = model.operationalTendencies.map {
      CompassDeltaPromptHypothesisPayload(hypothesis: $0)
    }
    blindSpots = model.blindSpots.map { CompassDeltaPromptHypothesisPayload(hypothesis: $0) }
    steeringRules = model.steeringRules.map { CompassDeltaPromptRulePayload(rule: $0) }
  }
}

private struct CompassDeltaPromptHypothesisPayload: Encodable {
  let axis: CompassInsightAxis
  let title: String
  let statement: String
  let confidence: CompassConfidence

  init(hypothesis: CompassHypothesis) {
    axis = hypothesis.axis
    title = hypothesis.title
    statement = hypothesis.statement
    confidence = hypothesis.confidence
  }
}

private struct CompassDeltaPromptRulePayload: Encodable {
  let title: String
  let instruction: String
  let rationale: String
  let confidence: CompassConfidence

  init(rule: CompassSteeringRule) {
    title = rule.title
    instruction = rule.instruction
    rationale = rule.rationale
    confidence = rule.confidence
  }
}

private struct CompassDeltaSelfModelPromptPeriod: Encodable {
  let periodKey: String
  let summary: String
}

private struct CompassDeltaSelfModelPromptDay: Encodable {
  let dayKey: String
  let summary: String
  let highlights: [String]
}

private struct CompassDeltaSelfModelPromptResponse: Decodable {
  let overview: String
  let corePersona: [CompassDeltaSelfModelPromptHypothesis]
  let currentSeason: [CompassDeltaSelfModelPromptHypothesis]
  let operationalTendencies: [CompassDeltaSelfModelPromptHypothesis]
  let blindSpots: [CompassDeltaSelfModelPromptHypothesis]
  let steeringRules: [CompassDeltaSelfModelPromptRule]
}

private struct CompassDeltaSelfModelPromptHypothesis: Decodable {
  let axis: CompassInsightAxis
  let title: String
  let statement: String
  let confidence: CompassConfidence
}

private struct CompassDeltaSelfModelPromptRule: Decodable {
  let title: String
  let instruction: String
  let rationale: String
  let confidence: CompassConfidence
}

private struct CompassDailyDeltaPromptPayload: Encodable {
  let daySummary: CompassDailyDeltaPromptDay
  let weeklySummary: CompassDailyDeltaPromptPeriod?
  let monthlySummary: CompassDailyDeltaPromptPeriod?
  let previousOverview: String
  let updatedOverview: String

  init(
    daySummary: CompassJournalDaySummary,
    weeklySummary: CompassJournalPeriodSummary?,
    monthlySummary: CompassJournalPeriodSummary?,
    previousOverview: String,
    updatedOverview: String
  ) {
    self.daySummary = CompassDailyDeltaPromptDay(
      dayKey: daySummary.dayKey,
      summary: daySummary.summary,
      highlights: daySummary.highlights
    )
    self.weeklySummary = weeklySummary.map {
      CompassDailyDeltaPromptPeriod(periodKey: $0.periodKey, summary: $0.summary)
    }
    self.monthlySummary = monthlySummary.map {
      CompassDailyDeltaPromptPeriod(periodKey: $0.periodKey, summary: $0.summary)
    }
    self.previousOverview = previousOverview
    self.updatedOverview = updatedOverview
  }
}

private struct CompassDailyDeltaPromptDay: Encodable {
  let dayKey: String
  let summary: String
  let highlights: [String]
}

private struct CompassDailyDeltaPromptPeriod: Encodable {
  let periodKey: String
  let summary: String
}

private struct CompassDailyDeltaPromptResponse: Decodable {
  let summary: String
}
