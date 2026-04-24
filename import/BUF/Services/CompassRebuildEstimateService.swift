import Foundation

struct CompassFullRebuildEstimate: Hashable, Sendable {
  var indexedDayCount: Int
  var indexedEntryCount: Int
  var sourceCharacterCount: Int
  var estimatedPayloadCharacterCount: Int
  var estimatedInputTokenCount: Int
  var estimatedOutputTokenUpperBound: Int
  var estimatedRequestCount: Int
  var supportingRequestCount: Int
  var primaryRequestCount: Int
  var requestCap: Int
  var knownTokenCap: Int
  var primaryModel: String
  var supportingModel: String
}

actor CompassRebuildEstimateService {
  private let journalProvider: any CompassJournalProviding
  private let generator: any CompassGenerationServing
  private let calendar: Calendar
  private let safeguards = CompassGenerationSafeguards.default

  init(
    journalProvider: any CompassJournalProviding,
    generator: any CompassGenerationServing,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.journalProvider = journalProvider
    self.generator = generator
    self.calendar = calendar
  }

  func estimateFullRebuild() async throws -> CompassFullRebuildEstimate {
    let availableDays = try await journalProvider.availableDays()
    let configuration = await generator.loadModelConfiguration()

    var indexedEntryCount = 0
    var sourceCharacterCount = 0
    var daySummaries: [EstimatedDaySummary] = []

    for day in availableDays {
      let entries = try await journalProvider.entries(for: day)
      indexedEntryCount += entries.count
      sourceCharacterCount += entries.reduce(into: 0) { partialResult, entry in
        partialResult += entry.body.count
      }
      daySummaries.append(
        EstimatedDaySummary(
          day: day,
          dayKey: CompassDateKeyCodec.dayKey(for: day),
          summary: fallbackDaySummary(for: entries),
          highlights: fallbackHighlights(for: entries)
        )
      )
    }

    daySummaries.sort { $0.day < $1.day }

    let weekKeys = Set(daySummaries.map { CompassDateKeyCodec.weekKey(for: $0.day, calendar: calendar) })
    let monthKeys = Set(daySummaries.map { CompassDateKeyCodec.monthKey(for: $0.day) })
    let llmWeekCount = min(weekKeys.count, safeguards.bootstrapRecentWeekLLMLimit)
    let llmMonthCount = min(monthKeys.count, safeguards.bootstrapRecentMonthLLMLimit)
    let supportingRequestCount = min(
      safeguards.bootstrapMaxLLMRequests,
      llmWeekCount + llmMonthCount
    )
    let primaryRequestCount = supportingRequestCount < safeguards.bootstrapMaxLLMRequests ? 1 : 0
    let estimatedRequestCount = supportingRequestCount + primaryRequestCount

    let estimatedPayloadCharacterCount =
      estimatedPeriodPayloadCharacterCount(
        granularity: .week,
        daySummaries: daySummaries,
        limit: safeguards.bootstrapRecentWeekLLMLimit
      )
      + estimatedPeriodPayloadCharacterCount(
        granularity: .month,
        daySummaries: daySummaries,
        limit: safeguards.bootstrapRecentMonthLLMLimit
      )
      + estimatedSelfModelPayloadCharacterCount(daySummaries: daySummaries)

    let estimatedInputTokenCount = estimatedTokenCount(forCharacterCount: estimatedPayloadCharacterCount)
    let estimatedOutputTokenUpperBound =
      llmWeekCount * CompassGenerationProfile.periodDigest.defaultMaxOutputTokens
      + llmMonthCount * CompassGenerationProfile.periodDigest.defaultMaxOutputTokens
      + primaryRequestCount * CompassGenerationProfile.bootstrapSelfModel.defaultMaxOutputTokens

    return CompassFullRebuildEstimate(
      indexedDayCount: daySummaries.count,
      indexedEntryCount: indexedEntryCount,
      sourceCharacterCount: sourceCharacterCount,
      estimatedPayloadCharacterCount: estimatedPayloadCharacterCount,
      estimatedInputTokenCount: estimatedInputTokenCount,
      estimatedOutputTokenUpperBound: estimatedOutputTokenUpperBound,
      estimatedRequestCount: estimatedRequestCount,
      supportingRequestCount: supportingRequestCount,
      primaryRequestCount: primaryRequestCount,
      requestCap: safeguards.bootstrapMaxLLMRequests,
      knownTokenCap: safeguards.bootstrapMaxKnownTokens,
      primaryModel: configuration.primaryModel,
      supportingModel: configuration.supportingModel
    )
  }

  private func estimatedPeriodPayloadCharacterCount(
    granularity: CompassPeriodGranularity,
    daySummaries: [EstimatedDaySummary],
    limit: Int
  ) -> Int {
    let grouped = Dictionary(grouping: daySummaries) { summary in
      switch granularity {
      case .week:
        CompassDateKeyCodec.weekKey(for: summary.day, calendar: calendar)
      case .month:
        CompassDateKeyCodec.monthKey(for: summary.day)
      }
    }

    return grouped.keys.sorted().suffix(limit).reduce(into: 0) { partialResult, periodKey in
      let covered = (grouped[periodKey] ?? []).sorted { $0.dayKey < $1.dayKey }
      let payload = EstimatedPeriodPayload(
        granularity: granularity.rawValue,
        periodKey: periodKey,
        daySummaries: covered
      )
      partialResult += encodedCharacterCount(for: payload) + 380
    }
  }

  private func estimatedSelfModelPayloadCharacterCount(
    daySummaries: [EstimatedDaySummary]
  ) -> Int {
    let groupedByWeek = Dictionary(grouping: daySummaries) {
      CompassDateKeyCodec.weekKey(for: $0.day, calendar: calendar)
    }
    let groupedByMonth = Dictionary(grouping: daySummaries) {
      CompassDateKeyCodec.monthKey(for: $0.day)
    }

    let weeklySummaries = groupedByWeek.keys.sorted().suffix(safeguards.bootstrapRecentWeekLLMLimit).map {
      EstimatedPeriodSummary(
        granularity: CompassPeriodGranularity.week.rawValue,
        periodKey: $0,
        summary: fallbackPeriodSummary(
          for: (groupedByWeek[$0] ?? []).map {
            EstimatedSummaryText(dayKey: $0.dayKey, summary: $0.summary)
          }
        )
      )
    }
    let monthlySummaries = groupedByMonth.keys.sorted().suffix(safeguards.bootstrapRecentMonthLLMLimit).map {
      EstimatedPeriodSummary(
        granularity: CompassPeriodGranularity.month.rawValue,
        periodKey: $0,
        summary: fallbackPeriodSummary(
          for: (groupedByMonth[$0] ?? []).map {
            EstimatedSummaryText(dayKey: $0.dayKey, summary: $0.summary)
          }
        )
      )
    }

    let payload = EstimatedSelfModelPayload(
      weeklySummaries: weeklySummaries,
      monthlySummaries: monthlySummaries,
      recentDaySummaries: Array(daySummaries.suffix(14))
    )
    return encodedCharacterCount(for: payload) + 520
  }

  private func estimatedTokenCount(forCharacterCount characterCount: Int) -> Int {
    Int(ceil(Double(max(0, characterCount)) / 4.0))
  }

  private func encodedCharacterCount<Value: Encodable>(for value: Value) -> Int {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value) else { return 0 }
    return data.count
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

  private func fallbackPeriodSummary(for summaries: [EstimatedSummaryText]) -> String {
    let snippets = summaries.map(\.summary).filter { !$0.isEmpty }
    if snippets.isEmpty {
      return "이 기간의 기록이 부족해 패턴 요약이 제한적이다."
    }
    return Array(snippets.prefix(3)).joined(separator: "\n")
  }
}

private struct EstimatedDaySummary: Encodable {
  var day: Date
  var dayKey: String
  var summary: String
  var highlights: [String]
}

private struct EstimatedSummaryText: Encodable {
  var dayKey: String
  var summary: String
}

private struct EstimatedPeriodPayload: Encodable {
  var granularity: String
  var periodKey: String
  var daySummaries: [EstimatedDaySummary]
}

private struct EstimatedPeriodSummary: Encodable {
  var granularity: String
  var periodKey: String
  var summary: String
}

private struct EstimatedSelfModelPayload: Encodable {
  var weeklySummaries: [EstimatedPeriodSummary]
  var monthlySummaries: [EstimatedPeriodSummary]
  var recentDaySummaries: [EstimatedDaySummary]
}
