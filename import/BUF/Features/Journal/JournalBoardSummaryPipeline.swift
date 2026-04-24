import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

let journalCacheSchemaVersion = 6
let journalDaySummaryPromptVersion = 6
let journalLongNoteThresholdCharacterCount = 300
let journalLongNoteThresholdLineCount = 12
let journalLongNoteChunkCharacterLimit = 260
let journalLongNoteChunkLineLimit = 6
let journalLongNoteChunkSummarySystemPrompt = """
이 텍스트는 긴 노트의 일부다. 핵심 내용만 1~2문장으로 압축해.
"""
let journalUnavailableFoundationSummaryText = "Apple 요약을 아직 받지 못했습니다."
let journalUnavailableGeminiSummaryText = "Gemini 요약을 아직 받지 못했습니다."

let journalProjectFactSummarySystemPrompt = """
제공된 데이터는 사용자의 특정 프로젝트 작업 로그와 메모다. 의미 없는 타건 테스트(ㅁㄴㅇㄹ, 가벽받 등)는 쓰레기 데이터로 버리지 말고 '앱 퍼포먼스 및 안정성 테스트'로 해석해라. 개별 작업을 단순 나열하지 말고, 이 프로젝트에서 오늘 어떤 '목적과 진척'이 있었는지 1~2줄의 건조하고 명확한 팩트 위주로 요약하라.
"""

let journalDailyInsightSystemPrompt = """
너는 창작자이자 앱 개발자인 사용자의 하루 작업 로그를 분석하여 깊이 있는 통찰을 제공하는 어시스턴트다. 제공된 데이터는 온디바이스 AI가 사실 기반으로 1차 압축한 '프로젝트별 핵심 작업 요약본'이다. 이를 바탕으로 오늘 하루의 흐름을 분석한 글을 작성하라.

[작성 원칙: 매우 엄격하게 지킬 것]
1. 문체 제한: 반드시 '~한다', '~했다', '~이다' 형태의 건조하고 명확한 해라체(평어)를 사용한다. '~합니다', '~해요', '~입니다' 같은 높임말이나 부드러운 문체는 절대 금지한다.
2. 기계적인 포맷 금지: '오늘의 모멘텀은...', '작업들의 연결성은...', '결론적으로...', '내일을 위한 과제는...' 같은 소제목, 넘버링 리스트, 상투적인 도입부나 결론부를 절대 사용하지 마라. 인공지능이 쓴 티를 내지 말고, 자연스럽게 이어지는 산문(Prose) 에세이 형태로 작성하라.
3. 분량 및 단락: 특정 카테고리를 억지로 가정하지 말고, 데이터에서 드러나는 사실에만 집중하라. 분량에 제한을 두지 않으며, 가독성을 위해 자연스럽게 여러 문단으로 나누어 작성하라.

[글 속에 자연스럽게 녹여내야 할 핵심 맥락]
- 모멘텀: 오늘 가장 에너지가 많이 투입되었거나, 유의미한 진척을 이뤄낸 활동의 본질 서술.
- 연결성: 서로 다른 프로젝트 사이에서 발생한 맥락의 교차점이나 시너지가 있다면 발견해서 언급할 것. 단, 억지로 지어내지 말 것.
- 궤적과 통찰: 오늘의 작업 패턴과 해결된 문제들을 바탕으로, 다음 스텝에 대한 객관적인 평가나 직관을 글의 흐름 속에 자연스럽게 남길 것.
"""

struct JournalProjectLogPayload: Identifiable, Encodable, Hashable {
  let id: String
  let projectID: UUID
  let project: String
  let planned: [String]
  let executed: [String]
  let journaled: [String]

  enum CodingKeys: String, CodingKey {
    case project
    case planned
    case executed
    case journaled
  }
}

struct JournalProjectLogPartition: Hashable {
  var planned: [String] = []
  var executed: [String] = []
  var journaled: [String] = []

  var isEmpty: Bool {
    planned.isEmpty && executed.isEmpty && journaled.isEmpty
  }
}

struct JournalProjectLogAccumulator {
  let projectID: UUID
  let project: String
  var planned: [String] = []
  var executed: [String] = []
  var journaled: [String] = []

  mutating func append(_ partition: JournalProjectLogPartition) {
    planned.append(contentsOf: partition.planned)
    executed.append(contentsOf: partition.executed)
    journaled.append(contentsOf: partition.journaled)
  }

  func payload() -> JournalProjectLogPayload? {
    let resolvedPlanned = journalDeduplicatedLogs(planned)
    let resolvedExecuted = journalDeduplicatedLogs(executed)
    let resolvedJournaled = journalDeduplicatedLogs(journaled)
    guard !resolvedPlanned.isEmpty || !resolvedExecuted.isEmpty || !resolvedJournaled.isEmpty else {
      return nil
    }
    return JournalProjectLogPayload(
      id: "project-log-\(projectID.uuidString)",
      projectID: projectID,
      project: project,
      planned: resolvedPlanned,
      executed: resolvedExecuted,
      journaled: resolvedJournaled
    )
  }
}

struct JournalTextChunkPayload: Encodable, Hashable {
  let index: Int
  let text: String
}

struct JournalChunkReducePayload: Encodable, Hashable {
  let chunks: [String]
}

struct JournalProjectSummaryPayload: Encodable, Hashable {
  let project: String
  let summary: String
}

struct JournalJournalNotePayload: Encodable, Hashable {
  let time: String
  let note: String
}

struct JournalDailyInsightInputPayload: Encodable, Hashable {
  let date: String
  let projectSummaries: [JournalProjectSummaryPayload]
  let journalNotes: [JournalJournalNotePayload]
}

func journalEncodedJSONString<Value: Encodable>(_ value: Value) -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

  guard let data = try? encoder.encode(value),
    let string = String(data: data, encoding: .utf8)
  else {
    return "{}"
  }

  return string
}

private func journalDeduplicatedLogs(_ logs: [String]) -> [String] {
  var orderedLogs: [String] = []
  var counts: [String: Int] = [:]

  for log in logs {
    let normalized = log.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { continue }
    if counts[normalized] == nil {
      orderedLogs.append(normalized)
    }
    counts[normalized, default: 0] += 1
  }

  return orderedLogs.map { log in
    let count = counts[log, default: 0]
    return count > 1 ? "\(log) (x\(count))" : log
  }
}

func journalMakeLongTextChunks(from text: String) -> [String] {
  let normalizedLines = text
    .replacingOccurrences(of: "\r\n", with: "\n")
    .replacingOccurrences(of: "\r", with: "\n")
    .components(separatedBy: "\n")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

  guard !normalizedLines.isEmpty else { return [] }

  var chunks: [String] = []
  var currentLines: [String] = []
  var currentCharacterCount = 0

  func flushCurrentChunk() {
    guard !currentLines.isEmpty else { return }
    chunks.append(currentLines.joined(separator: "\n"))
    currentLines.removeAll(keepingCapacity: true)
    currentCharacterCount = 0
  }

  for line in normalizedLines {
    let fragments: [String]
    if line.count > journalLongNoteChunkCharacterLimit {
      var resolved: [String] = []
      var startIndex = line.startIndex
      while startIndex < line.endIndex {
        let endIndex = line.index(
          startIndex,
          offsetBy: journalLongNoteChunkCharacterLimit,
          limitedBy: line.endIndex
        )
          ?? line.endIndex
        resolved.append(String(line[startIndex..<endIndex]))
        startIndex = endIndex
      }
      fragments = resolved
    } else {
      fragments = [line]
    }

    for fragment in fragments {
      let needsFlush =
        !currentLines.isEmpty
        && (currentCharacterCount + fragment.count > journalLongNoteChunkCharacterLimit
          || currentLines.count >= journalLongNoteChunkLineLimit)

      if needsFlush {
        flushCurrentChunk()
      }

      currentLines.append(fragment)
      currentCharacterCount += fragment.count
    }
  }

  flushCurrentChunk()
  return chunks
}

func journalLongTextSummaryMode(for text: String) -> JournalLongTextSummaryMode {
  let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !normalized.isEmpty else { return .emptyInput }

  let chunks = journalMakeLongTextChunks(from: normalized)
  guard !chunks.isEmpty else { return .emptyInput }
  if chunks.count == 1 {
    let lineCount = normalized.components(separatedBy: "\n").count
    let needsSummary =
      normalized.count > journalLongNoteThresholdCharacterCount
      || lineCount > journalLongNoteThresholdLineCount
    return needsSummary ? .singleChunkSummary : .passthrough
  }
  return .chunkedSummary
}

struct JournalFrozenDayCachePayload: Codable {
  let version: Int
  let section: JournalPreparedDaySection
}

actor JournalFrozenDayCacheStore {
  private let primaryDirectoryURL: URL?
  private let fallbackDirectoryURLs: [URL]
  private let fileManager = FileManager()

  init(rootURL: URL?, namespace: String, fallbackNamespaces: [String] = []) {
    let frozenRootURL =
      rootURL?
      .appendingPathComponent("journal", conformingTo: .directory)
      .appendingPathComponent("frozen-days", conformingTo: .directory)

    primaryDirectoryURL =
      frozenRootURL?
      .appendingPathComponent(namespace, conformingTo: .directory)

    fallbackDirectoryURLs = fallbackNamespaces.compactMap { fallbackNamespace in
      frozenRootURL?
        .appendingPathComponent(fallbackNamespace, conformingTo: .directory)
    }
  }

  func load(dayKey: String) -> JournalPreparedDaySection? {
    for fileURL in fileURLs(for: dayKey) {
      guard itemExists(at: fileURL) else { continue }

      do {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(JournalFrozenDayCachePayload.self, from: data)
        guard payload.version == journalCacheSchemaVersion else { continue }
        return payload.section
      } catch {
        AppLogger.ui.error(
          "load frozen journal day cache failed. key=\(dayKey, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    return nil
  }

  func save(_ section: JournalPreparedDaySection) {
    guard let fileURL = fileURL(for: section.id) else { return }

    do {
      try prepareDirectoryIfNeeded()
      let payload = JournalFrozenDayCachePayload(
        version: journalCacheSchemaVersion,
        section: section
      )
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(payload)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.ui.error(
        "save frozen journal day cache failed. key=\(section.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func prepareDirectoryIfNeeded() throws {
    guard let primaryDirectoryURL else { return }
    try fileManager.createDirectory(at: primaryDirectoryURL, withIntermediateDirectories: true)
  }

  private func fileURL(for dayKey: String) -> URL? {
    primaryDirectoryURL?.appendingPathComponent("\(dayKey).json", conformingTo: .json)
  }

  private func fileURLs(for dayKey: String) -> [URL] {
    let candidateDirectories = [primaryDirectoryURL] + fallbackDirectoryURLs
    return candidateDirectories.compactMap { directoryURL in
      directoryURL?.appendingPathComponent("\(dayKey).json", conformingTo: .json)
    }
  }

  private func itemExists(at url: URL) -> Bool {
    (try? url.checkResourceIsReachable()) ?? false
  }
}

struct JournalSummaryResolution: Hashable {
  let text: String
  let source: JournalSummarySource
  let usage: GeminiGenerateContentSummaryService.SummaryUsage?
  let failureReason: JournalSummaryFailureReason?
}

actor LocalLLMService {
  static let shared = LocalLLMService()

  private var summaryCache: [String: JournalSummaryResolution] = [:]
  private enum FoundationSummaryAttempt {
    case success(String)
    case failure(JournalSummaryFailureReason)
  }

  func summary(
    for cacheKey: String,
    prompt: String,
    forceRefresh: Bool = false,
    maximumResponseTokens: Int = 2200
  ) async -> JournalSummaryResolution {
    if !forceRefresh, let cached = summaryCache[cacheKey] {
      return cached
    }

    switch await generateFoundationSummary(
      prompt: prompt,
      maximumResponseTokens: maximumResponseTokens
    ) {
    case .success(let generated):
      let resolved = JournalSummaryResolution(
        text: normalizedSummary(generated),
        source: .foundation,
        usage: nil,
        failureReason: nil
      )
      summaryCache[cacheKey] = resolved
      return resolved
    case .failure(let reason):
      return unavailableResolution(reason: reason)
    }
  }

  func summarizeLongText(
    _ text: String,
    cacheKeyPrefix: String,
    forceRefresh: Bool = false
  ) async -> String {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }

    switch journalLongTextSummaryMode(for: normalized) {
    case .emptyInput:
      return ""
    case .passthrough:
      return normalized
    case .singleChunkSummary:
      let prompt = """
      \(journalLongNoteChunkSummarySystemPrompt)

      입력 JSON:
      \(journalEncodedJSONString(JournalTextChunkPayload(index: 0, text: normalized)))
      """
      let resolution = await summary(
        for: "\(cacheKeyPrefix)-single",
        prompt: prompt,
        forceRefresh: forceRefresh,
        maximumResponseTokens: 180
      )
      return resolution.source == .unavailable
        ? normalized
        : resolution.text.trimmingCharacters(in: .whitespacesAndNewlines)
    case .chunkedSummary:
      break
    }

    let chunks = journalMakeLongTextChunks(from: normalized)

    let chunkSummaries = await withTaskGroup(of: (Int, String?).self, returning: [String].self) { group in
      for (index, chunk) in chunks.enumerated() {
        group.addTask {
          let prompt = """
          \(journalLongNoteChunkSummarySystemPrompt)

          입력 JSON:
          \(journalEncodedJSONString(JournalTextChunkPayload(index: index, text: chunk)))
          """
          let resolution = await self.summary(
            for: "\(cacheKeyPrefix)-chunk-\(index)",
            prompt: prompt,
            forceRefresh: forceRefresh,
            maximumResponseTokens: 180
          )
          let text = resolution.source == .unavailable ? nil : resolution.text
          return (index, text)
        }
      }

      var pairs: [(Int, String)] = []
      for await pair in group {
        if let text = pair.1?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
          pairs.append((pair.0, text))
        }
      }

      return pairs.sorted(by: { $0.0 < $1.0 }).map(\.1)
    }

    guard !chunkSummaries.isEmpty else {
      AppLogger.app.error(
        "long text summary fallback used: \(JournalSummaryFailureReason.longTextChunkSummaryUnavailable.rawValue, privacy: .public)"
      )
      return normalized
    }

    let reducedSource = chunkSummaries.joined(separator: "\n")
    let needsReducePass =
      reducedSource.count > journalLongNoteThresholdCharacterCount
      || reducedSource.components(separatedBy: "\n").count > journalLongNoteThresholdLineCount

    guard needsReducePass else {
      return reducedSource.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let reducePrompt = """
    \(journalLongNoteChunkSummarySystemPrompt)

    입력 JSON:
    \(journalEncodedJSONString(JournalChunkReducePayload(chunks: chunkSummaries)))
    """
    let reduceResolution = await summary(
      for: "\(cacheKeyPrefix)-reduce",
      prompt: reducePrompt,
      forceRefresh: forceRefresh,
      maximumResponseTokens: 220
    )

    guard reduceResolution.source != .unavailable else {
      AppLogger.app.error(
        "long text reduce fallback used: \(JournalSummaryFailureReason.longTextReduceUnavailable.rawValue, privacy: .public)"
      )
      return reducedSource
    }
    return reduceResolution.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func unavailableResolution(reason: JournalSummaryFailureReason) -> JournalSummaryResolution {
    JournalSummaryResolution(
      text: journalUnavailableFoundationSummaryText,
      source: .unavailable,
      usage: nil,
      failureReason: reason
    )
  }

  private func generateFoundationSummary(
    prompt: String,
    maximumResponseTokens: Int = 2200
  ) async -> FoundationSummaryAttempt {
#if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      let model = SystemLanguageModel.default
      guard model.isAvailable else {
        AppLogger.app.error("foundation summary unavailable: model is not available")
        return .failure(.foundationModelUnavailable)
      }

      let session = LanguageModelSession(model: model)
      let options = GenerationOptions(
        sampling: .greedy,
        temperature: 0.15,
        maximumResponseTokens: maximumResponseTokens
      )

      do {
        let response = try await session.respond(to: prompt, options: options)
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
          AppLogger.app.error("foundation summary response contained no readable text output")
          return .failure(.foundationEmptyResponse)
        }
        return .success(content)
      } catch is CancellationError {
        AppLogger.app.error("foundation summary request failed: cancelled")
        return .failure(.foundationRequestCancelled)
      } catch {
        AppLogger.app.error(
          "foundation summary request failed: \(error.localizedDescription, privacy: .public)"
        )
        return .failure(.foundationRequestFailed)
      }
    }
#endif

    AppLogger.app.error("foundation summary unavailable: FoundationModels not supported")
    return .failure(.foundationModelUnavailable)
  }

  private func normalizedSummary(_ text: String) -> String {
    var lines = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    if let firstLine = lines.first,
      firstLine.contains("요약한 내용입니다")
        || firstLine.contains("정리한 내용입니다")
        || firstLine.hasPrefix("다음은 ")
    {
      lines.removeFirst()
    }

    let normalized = lines.joined(separator: "\n")
    return normalized.isEmpty ? "기록을 정리했습니다." : normalized
  }
}

actor GeminiAPIService {
  static let shared = GeminiAPIService()

  private var summaryCache: [String: JournalSummaryResolution] = [:]

  func summary(
    for cacheKey: String,
    prompt: String,
    model: String,
    forceRefresh: Bool = false,
    temperature: Double = 0.25,
    maximumResponseTokens: Int = 2400
  ) async -> JournalSummaryResolution {
    if !forceRefresh, let cached = summaryCache[cacheKey] {
      return cached
    }

    switch await GeminiGenerateContentSummaryService.shared.summarize(
      prompt: prompt,
      model: model,
      temperature: temperature,
      maxOutputTokens: maximumResponseTokens
    ) {
    case .success(let text, let usage):
      let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else {
        return JournalSummaryResolution(
          text: journalUnavailableGeminiSummaryText,
          source: .unavailable,
          usage: nil,
          failureReason: .geminiEmptyResponse
        )
      }
      let resolution = JournalSummaryResolution(
        text: normalized,
        source: .gemini,
        usage: usage,
        failureReason: nil
      )
      summaryCache[cacheKey] = resolution
      return resolution

    case .cancelled:
      return JournalSummaryResolution(
        text: journalUnavailableGeminiSummaryText,
        source: .unavailable,
        usage: nil,
        failureReason: .geminiRequestCancelled
      )

    case .failed:
      return JournalSummaryResolution(
        text: journalUnavailableGeminiSummaryText,
        source: .unavailable,
        usage: nil,
        failureReason: .geminiRequestFailed
      )
    }
  }
}

extension JournalBoardView {
  func shouldShowDaySummaryRefreshButton(for section: JournalPreparedDaySection) -> Bool {
    !section.isToday
  }

  func daySummaryItem(in section: JournalPreparedDaySection) -> JournalPreparedItem? {
    section.items.first(where: \.isDaySummary)
  }

  func frozenSectionReuseDecision(
    _ section: JournalPreparedDaySection,
    events: [JournalRenderedHistoryEvent]? = nil,
    journalEntries: [ObsidianJournalEntry]? = nil
  ) -> JournalFrozenSectionReuseDecision {
    guard let daySummary = daySummaryItem(in: section) else {
      return .reuseWithoutDaySummary
    }

    switch daySummary.summarySource {
    case .backup:
      return .invalidateBackupSummary
    case .fallback:
      return .invalidateFallbackSummary
    case .unavailable:
      return .invalidateUnavailableSummary
    case .foundation, .gemini:
      guard let cachedSignature = daySummary.summaryInputSignature else {
        return .invalidateMissingSummaryInputSignature
      }
      guard let expectedEvents = events, let expectedJournalEntries = journalEntries else {
        return .reuseMatchingCurrentSignature
      }

      let expectedProjectPayloads = projectLogPayloads(for: expectedEvents)
      let expectedJournalNotePayloads = journalNotePayloads(for: expectedJournalEntries)
      let currentSignature = daySummaryFeedMergeParitySentinel(
        projectPayloads: expectedProjectPayloads,
        journalNotePayloads: expectedJournalNotePayloads
      )
      if cachedSignature == currentSignature {
        return .reuseMatchingCurrentSignature
      }

      let legacySignature = legacyDaySummaryInputSignature(
        for: expectedEvents,
        journalEntries: expectedJournalEntries
      )
      if cachedSignature == legacySignature {
        return .reuseMatchingLegacySignature
      }

      return .invalidateSummaryInputMismatch
    }
  }

  func canReuseFrozenSection(
    _ section: JournalPreparedDaySection,
    events: [JournalRenderedHistoryEvent]? = nil,
    journalEntries: [ObsidianJournalEntry]? = nil
  ) -> Bool {
    frozenSectionReuseDecision(
      section,
      events: events,
      journalEntries: journalEntries
    ).allowsReuse
  }

  func reusableFrozenSection(for day: Date) async -> JournalPreparedDaySection? {
    let dayKey = Self.dayKey(for: day)
    guard let cachedSection = await frozenDayCacheStore.load(dayKey: dayKey) else {
      return nil
    }

    let daySummary = daySummaryItem(in: cachedSection)
    let hasJournalDay = availableJournalDayKeys.contains(dayKey)

    let needsJournalEntries =
      hasJournalDay
      || daySummary?.summarySource == .foundation

    let journalEntries =
      needsJournalEntries ? await appState.loadJournalEntriesFromSource(for: day) : []

    let decision = frozenSectionReuseDecision(
      cachedSection,
      events: dayEvents(for: day),
      journalEntries: journalEntries
    )
    if decision.allowsReuse {
      return JournalPreparedDaySection(
        id: cachedSection.id,
        day: cachedSection.day,
        title: cachedSection.title,
        summary: cachedSection.summary,
        detailLines: preparedDayDetailLines(for: day, journalEntries: journalEntries),
        items: cachedSection.items,
        isToday: cachedSection.isToday
      )
    }

    AppLogger.app.info(
      "journal frozen section invalidated. key=\(dayKey, privacy: .public) reason=\(String(describing: decision), privacy: .public)"
    )
    return nil
  }

  func shouldPersistFrozenSection(_ section: JournalPreparedDaySection) -> Bool {
    guard !section.isToday else { return false }
    guard let daySummary = daySummaryItem(in: section) else { return true }

    switch daySummary.summarySource {
    case .foundation, .gemini:
      return daySummary.summaryInputSignature != nil
    case .backup, .fallback, .unavailable:
      return false
    }
  }

  func daySummaryBackupPersistenceDecision(
    for section: JournalPreparedDaySection
  ) -> JournalDaySummaryBackupPersistenceDecision {
    guard let daySummary = daySummaryItem(in: section) else {
      return .skipMissingDaySummary
    }

    switch daySummary.summarySource {
    case .backup:
      return .skipBackupSummary
    case .fallback:
      return .skipFallbackSummary
    case .unavailable:
      return .skipUnavailableSummary
    case .foundation, .gemini:
      break
    }

    let markdown = markdownText(for: daySummary)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return markdown.isEmpty ? .skipEmptyMarkdown : .persistGeneratedSummary
  }

  func persistFrozenSectionIfNeeded(_ section: JournalPreparedDaySection) async {
    guard shouldPersistFrozenSection(section) else { return }
    await frozenDayCacheStore.save(section)
    await persistDaySummaryBackupIfNeeded(from: section)
  }

  func persistDaySummaryBackupIfNeeded(from section: JournalPreparedDaySection) async {
    let decision = daySummaryBackupPersistenceDecision(for: section)
    guard decision == .persistGeneratedSummary, let daySummary = daySummaryItem(in: section) else {
      return
    }

    let markdown = markdownText(for: daySummary)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    await appState.saveJournalDaySummaryBackupToSource(
      markdown,
      for: section.day,
      summaryInputSignature: daySummary.summaryInputSignature,
      usage: daySummary.summaryUsage
    )
  }

  func summarySourceMarker(for source: JournalSummarySource) -> String? {
    switch source {
    case .foundation:
      return "a"
    case .gemini:
      return "m"
    case .backup:
      return "b"
    case .fallback:
      return "f"
    case .unavailable:
      return nil
    }
  }

  func daySummaryRefreshHelpText(for section: JournalPreparedDaySection) -> String {
    let defaultText = "현재 모델로 다시 요약"
    guard let daySummary = daySummaryItem(in: section) else {
      return defaultText
    }

    switch daySummary.summarySource {
    case .foundation, .gemini:
      return defaultText
    case .backup:
      return "저장된 백업 요약을 표시 중. \(defaultText)"
    case .fallback:
      if daySummary.summaryFailureReason == .noSummaryInputs {
        return "요약 입력이 부족해 기록 기반 임시 요약을 표시 중. \(defaultText)"
      }
      return "AI 실패 후 기록 기반 임시 요약을 표시 중. \(defaultText)"
    case .unavailable:
      return "요약을 아직 받지 못했습니다. \(defaultText)"
    }
  }

  @ViewBuilder
  func daySummaryRefreshControl(for section: JournalPreparedDaySection) -> some View {
    if retryingDaySummaryIDs.contains(section.id) {
      ProgressView()
        .controlSize(.small)
        .frame(width: 28, height: 28)
    } else if shouldShowDaySummaryRefreshButton(for: section) {
      Button {
        Task {
          await retryDaySummary(for: section)
        }
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 28, height: 28)
          .overlaySurface(
            cornerRadius: 8,
            fillColor: .black,
            strokeColor: .black,
            style: journalChromeButtonSurfaceStyle
          )
      }
      .buttonStyle(.plain)
      .help(daySummaryRefreshHelpText(for: section))
    }
  }

  func retryDaySummary(for section: JournalPreparedDaySection) async {
    guard !section.isToday else { return }
    guard !retryingDaySummaryIDs.contains(section.id) else { return }

    retryingDaySummaryIDs.insert(section.id)
    defer { retryingDaySummaryIDs.remove(section.id) }

    let day = section.day
    let dayEvents = renderedHistoryEvents.filter {
      Calendar.autoupdatingCurrent.isDate($0.event.occurredAt, inSameDayAs: day)
    }
    guard !dayEvents.isEmpty else { return }

    let journalEntries = await appState.loadJournalEntriesFromSource(for: day)
    let refreshPolicy = JournalSummaryRefreshPolicy.forceRetry(.userRefreshButton)
    if let retryTrigger = refreshPolicy.retryTrigger {
      AppLogger.app.info(
        "journal day summary retry requested. key=\(section.id, privacy: .public) trigger=\(retryTrigger.rawValue, privacy: .public)"
      )
    }
    let refreshedSummaryItem = await preparedPastDaySummaryItem(
      for: day,
      events: dayEvents,
      journalEntries: journalEntries,
      refreshPolicy: refreshPolicy
    )

    var refreshedItems = section.items.filter { !$0.isDaySummary }
    refreshedItems.insert(refreshedSummaryItem, at: 0)

    let refreshedSection = JournalPreparedDaySection(
      id: section.id,
      day: day,
      title: section.title,
      summary: section.summary,
      detailLines: preparedDayDetailLines(for: day, journalEntries: journalEntries),
      items: refreshedItems,
      isToday: false
    )

    if let index = preparedDaySections.firstIndex(where: { $0.id == section.id }) {
      preparedDaySections[index] = refreshedSection
    }

    await persistFrozenSectionIfNeeded(refreshedSection)
  }

  func preparedPastDaySummaryItem(
    for day: Date,
    events: [JournalRenderedHistoryEvent],
    journalEntries: [ObsidianJournalEntry],
    refreshPolicy: JournalSummaryRefreshPolicy = .reuseCachedResults
  ) async -> JournalPreparedItem {
    let cluster = JournalSystemCluster(
      id: "day-summary-\(Self.dayKey(for: day))",
      projectID: events.first?.event.projectID ?? UUID(),
      day: day,
      startAt: events.first?.event.occurredAt ?? day,
      endAt: events.last?.event.occurredAt ?? day,
      events: events,
      journalEntries: [],
      presentationStyle: .retrospective
    )

    let dayKey = Self.dayKey(for: day)
    let detailPayloads = projectLogPayloads(for: events)
    let signatureJournalNotePayloads = journalNotePayloads(for: journalEntries)
    let stepOneProjectPayloads = await summaryProjectLogPayloads(
      for: events,
      dayKey: dayKey,
      forceRefreshSummary: refreshPolicy.forceRefreshSummary
    )
    let stepThreeJournalNotePayloads = await summaryJournalNotePayloads(
      for: journalEntries,
      dayKey: dayKey,
      forceRefreshSummary: refreshPolicy.forceRefreshSummary
    )
    let detailLines = preparedDayDetailLines(from: detailPayloads, journalEntries: journalEntries)
    let summaryInputSignature = daySummaryFeedMergeParitySentinel(
      projectPayloads: detailPayloads,
      journalNotePayloads: signatureJournalNotePayloads
    )
    let projectSummaries = await projectSummaryPayloads(
      for: day,
      dayKey: dayKey,
      projectPayloads: stepOneProjectPayloads,
      summaryInputSignature: summaryInputSignature,
      forceRefreshSummary: refreshPolicy.forceRefreshSummary
    )
    let summaryResolution = await resolvedPastDaySummaryResolution(
      for: day,
      dayKey: dayKey,
      events: events,
      journalEntries: journalEntries,
      projectSummaries: projectSummaries,
      journalNotePayloads: stepThreeJournalNotePayloads,
      summaryInputSignature: summaryInputSignature,
      refreshPolicy: refreshPolicy
    )

    return JournalPreparedItem(
      id: "day-summary-\(Self.dayKey(for: day))",
      sortDate: cluster.startAt,
      kind: .system,
      label: "하루 요약",
      isDaySummary: true,
      lines: preparedSummaryDisplayLines(from: summaryResolution.text),
      detailLines: detailLines,
      journalLines: [],
      inlineDetailLineCount: 0,
      meta: [],
      summarySource: summaryResolution.source,
      summaryFailureReason: summaryResolution.failureReason,
      summaryInputSignature: summaryInputSignature,
      summaryUsage: summaryResolution.usage,
      sourceJournalEntryID: nil
    )
  }

  func resolvedPastDaySummaryResolution(
    for day: Date,
    dayKey: String,
    events: [JournalRenderedHistoryEvent],
    journalEntries: [ObsidianJournalEntry],
    projectSummaries: [JournalProjectSummaryPayload],
    journalNotePayloads: [JournalJournalNotePayload],
    summaryInputSignature: String,
    refreshPolicy: JournalSummaryRefreshPolicy
  ) async -> JournalSummaryResolution {
    let daySummaryCacheKey =
      "day-summary-\(dayKey)-v\(journalDaySummaryPromptVersion)-\(appState.journalSummaryProviderSignature)-\(summaryInputSignature)"

    let upstreamResolution: JournalSummaryResolution
    if !projectSummaries.isEmpty || !journalNotePayloads.isEmpty {
      let generated = await GeminiAPIService.shared.summary(
        for: daySummaryCacheKey,
        prompt: dailyInsightPrompt(
          for: day,
          projectSummaries: projectSummaries,
          journalNotePayloads: journalNotePayloads
        ),
        model: appState.geminiSummaryModelName,
        forceRefresh: refreshPolicy.forceRefreshSummary,
        temperature: 0.25,
        maximumResponseTokens: 2400
      )
      if generated.source != .unavailable {
        return generated
      }
      upstreamResolution = generated
    } else {
      upstreamResolution = JournalSummaryResolution(
        text: "",
        source: .unavailable,
        usage: nil,
        failureReason: .noSummaryInputs
      )
    }

    if let backupResolution = await matchedDaySummaryBackupResolution(
      for: day,
      dayKey: dayKey,
      summaryInputSignature: summaryInputSignature,
      upstreamFailureReason: upstreamResolution.failureReason
    ) {
      return backupResolution
    }

    let failureReason = upstreamResolution.failureReason ?? .geminiRequestFailed
    AppLogger.app.error(
      "journal day summary fallback used. key=\(dayKey, privacy: .public) reason=\(failureReason.rawValue, privacy: .public)"
    )
    return daySummaryFallbackResolution(
      events: events,
      journalEntries: journalEntries,
      failureReason: failureReason
    )
  }

  func matchedDaySummaryBackupResolution(
    for day: Date,
    dayKey: String,
    summaryInputSignature: String,
    upstreamFailureReason: JournalSummaryFailureReason?
  ) async -> JournalSummaryResolution? {
    let (decision, backup) = await daySummaryBackupLoadDecision(
      for: day,
      summaryInputSignature: summaryInputSignature
    )
    switch decision {
    case .loadedMatchingBackup:
      guard let backup else { return nil }
      return JournalSummaryResolution(
        text: backup.markdown,
        source: .backup,
        usage: backup.usage,
        failureReason: upstreamFailureReason
      )
    case .missingBackup, .malformedBackup, .backupProviderMismatch, .backupSummaryInputMismatch:
      AppLogger.app.info(
        "journal day summary backup skipped. key=\(dayKey, privacy: .public) reason=\(String(describing: decision), privacy: .public)"
      )
      return nil
    }
  }

  func daySummaryBackupLoadDecision(
    for day: Date,
    summaryInputSignature: String
  ) async -> (JournalDaySummaryBackupLoadDecision, ObsidianJournalDaySummaryBackup?) {
    switch await appState.loadJournalDaySummaryBackupFromSource(for: day) {
    case .missing:
      return (.missingBackup, nil)
    case .malformed:
      return (.malformedBackup, nil)
    case .loaded(let backup):
      guard backup.providerSignature == appState.journalSummaryProviderSignature else {
        return (.backupProviderMismatch, nil)
      }
      guard backup.summaryInputSignature == summaryInputSignature else {
        return (.backupSummaryInputMismatch, nil)
      }
      return (.loadedMatchingBackup, backup)
    }
  }

  func daySummaryFallbackResolution(
    events: [JournalRenderedHistoryEvent],
    journalEntries: [ObsidianJournalEntry],
    failureReason: JournalSummaryFailureReason
  ) -> JournalSummaryResolution {
    JournalSummaryResolution(
      text: deterministicDaySummary(
        for: events,
        journalEntries: journalEntries,
        failureReason: failureReason
      ),
      source: .fallback,
      usage: nil,
      failureReason: failureReason
    )
  }

  func daySummaryFallbackLead(for failureReason: JournalSummaryFailureReason) -> String {
    switch failureReason {
    case .noSummaryInputs:
      return "요약 입력이 부족해 기록 기반으로 정리했다."
    case .malformedBackup, .missingBackup, .backupProviderMismatch, .backupSummaryInputMismatch:
      return "저장된 백업을 재사용하지 않고 기록 기반으로 정리했다."
    default:
      return "AI 응답이 없어 기록 기반으로 정리했다."
    }
  }

  func deterministicDaySummary(
    for events: [JournalRenderedHistoryEvent],
    journalEntries: [ObsidianJournalEntry],
    failureReason: JournalSummaryFailureReason
  ) -> String {
    let completedTitles = events
      .filter { $0.event.kind == .taskCompleted }
      .map { historyTaskTitle(for: $0.event) }
    let createdTitles = events
      .filter { $0.event.kind == .taskCreated }
      .map { historyTaskTitle(for: $0.event) }
    let reopenedTitles = events
      .filter { $0.event.kind == .taskReopened }
      .map { historyTaskTitle(for: $0.event) }
    let noteAddedLines = events.flatMap { $0.noteDelta?.addedLines ?? [] }
    let noteRemovedLines = events.flatMap { $0.noteDelta?.removedLines ?? [] }
    let journalLines = journalEntries.flatMap { entry in
      normalizedDisplayLines(entry.body)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    var sentences: [String] = [daySummaryFallbackLead(for: failureReason)]

    if !createdTitles.isEmpty {
      sentences.append("\(titlePreview(from: createdTitles))를 만들었다.")
    }
    if !completedTitles.isEmpty {
      sentences.append("\(titlePreview(from: completedTitles))를 마쳤다.")
    }
    if !reopenedTitles.isEmpty {
      sentences.append("\(titlePreview(from: reopenedTitles)) 완료를 다시 열었다.")
    }
    if !noteAddedLines.isEmpty {
      sentences.append("작업 메모에는 \(linePreview(from: noteAddedLines)) 같은 내용이 더해졌다.")
    }
    if !noteRemovedLines.isEmpty {
      sentences.append("지운 메모는 \(linePreview(from: noteRemovedLines)) 쪽이었다.")
    }
    if !journalLines.isEmpty {
      sentences.append("개인 메모에는 \(linePreview(from: journalLines)) 같은 판단이 남았다.")
    }

    if sentences.count == 1 {
      let projectTitles = events.map { projectTitlesByID[$0.event.projectID] ?? "프로젝트" }
      if !projectTitles.isEmpty {
        sentences.append("\(titlePreview(from: projectTitles)) 중심으로 작업 기록이 남았다.")
      } else if !journalLines.isEmpty {
        sentences.append("개인 메모를 다시 확인해야 한다.")
      } else {
        sentences.append("상세 기록을 다시 확인해야 한다.")
      }
    }

    return sentences.prefix(4).joined(separator: " ")
  }

  func projectLogPayloads(for events: [JournalRenderedHistoryEvent]) -> [JournalProjectLogPayload] {
    var orderedProjectIDs: [UUID] = []
    var accumulators: [UUID: JournalProjectLogAccumulator] = [:]

    for renderedEvent in events {
      let projectID = renderedEvent.event.projectID
      if accumulators[projectID] == nil {
        orderedProjectIDs.append(projectID)
        accumulators[projectID] = JournalProjectLogAccumulator(
          projectID: projectID,
          project: projectTitlesByID[projectID] ?? "프로젝트"
        )
      }

      let partition = projectLogPartition(for: renderedEvent)
      guard !partition.isEmpty else { continue }

      var accumulator =
        accumulators[projectID]
        ?? JournalProjectLogAccumulator(
          projectID: projectID,
          project: projectTitlesByID[projectID] ?? "프로젝트"
        )
      accumulator.append(partition)
      accumulators[projectID] = accumulator
    }

    return orderedProjectIDs.compactMap { accumulators[$0]?.payload() }
  }

  func projectLogPartition(for renderedEvent: JournalRenderedHistoryEvent)
    -> JournalProjectLogPartition
  {
    let event = renderedEvent.event

    switch event.kind {
    case .projectCreated:
      return JournalProjectLogPartition(journaled: ["projectCreated: 프로젝트 시작"])

    case .projectUpdated:
      return JournalProjectLogPartition(
        journaled: ["projectUpdated: \(historyChangeLogText(for: event))"]
      )

    case .projectTimelineChanged:
      return JournalProjectLogPartition(
        journaled: ["projectTimelineChanged: \(historyChangeLogText(for: event))"]
      )

    case .projectArchived:
      return JournalProjectLogPartition(
        journaled: ["projectArchived: \(historyChangeLogText(for: event))"]
      )

    case .projectRestored:
      return JournalProjectLogPartition(
        journaled: ["projectRestored: \(historyChangeLogText(for: event))"]
      )

    case .projectDeleted:
      return JournalProjectLogPartition(
        journaled: ["projectDeleted: \(historyChangeLogText(for: event))"]
      )

    case .taskCreated:
      return JournalProjectLogPartition(
        planned: ["taskCreated: \(historyTaskTitle(for: event).trimmingCharacters(in: .whitespacesAndNewlines))"]
      )

    case .taskCompleted:
      return JournalProjectLogPartition(
        executed: ["taskCompleted: \(historyTaskTitle(for: event).trimmingCharacters(in: .whitespacesAndNewlines))"]
      )

    case .taskReopened:
      return JournalProjectLogPartition(
        executed: ["taskReopened: \(historyTaskTitle(for: event).trimmingCharacters(in: .whitespacesAndNewlines))"]
      )

    case .taskUpdated:
      return JournalProjectLogPartition(
        journaled: ["taskUpdated: \(historyTaskTitle(for: event)) · \(historyChangeLogText(for: event))"]
      )

    case .taskScheduleChanged:
      return JournalProjectLogPartition(
        journaled: ["taskScheduleChanged: \(historyTaskTitle(for: event)) · \(historyChangeLogText(for: event))"]
      )

    case .taskMoved:
      return JournalProjectLogPartition(
        journaled: ["taskMoved: \(historyTaskTitle(for: event)) · \(historyChangeLogText(for: event))"]
      )

    case .taskDeleted:
      return JournalProjectLogPartition(
        journaled: ["taskDeleted: \(historyTaskTitle(for: event))"]
      )

    case .attachmentAdded:
      return JournalProjectLogPartition(
        journaled: [
          "attachmentAdded: \(historyAttachmentTitle(for: event).trimmingCharacters(in: .whitespacesAndNewlines))"
        ]
      )

    case .projectNoteSaved, .taskReminderNoteSaved:
      guard let delta = renderedEvent.noteDelta else { return JournalProjectLogPartition() }

      let logPrefix = event.kind == .projectNoteSaved ? "projectNoteSaved" : "taskReminderNoteSaved"
      let owner = noteOwnerPrefix(for: event)
      var journaled: [String] = []

      let addedText = delta.addedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if !addedText.isEmpty {
        let ownerPrefix = owner.map { "\($0) " } ?? ""
        journaled.append("\(logPrefix): + \(ownerPrefix)\(addedText)")
      }

      let removedText = delta.removedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if !removedText.isEmpty {
        let ownerPrefix = owner.map { "\($0) " } ?? ""
        journaled.append("\(logPrefix): - \(ownerPrefix)\(removedText)")
      }

      return JournalProjectLogPartition(journaled: journaled)
    }
  }

  func journalNotePayloads(for entries: [ObsidianJournalEntry]) -> [JournalJournalNotePayload] {
    entries
      .sorted { lhs, rhs in
        if lhs.occurredAt != rhs.occurredAt {
          return lhs.occurredAt < rhs.occurredAt
        }
        return lhs.id < rhs.id
      }
      .compactMap { entry in
        let normalized = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return JournalJournalNotePayload(
          time: Self.timeFormatter.string(from: entry.occurredAt),
          note: normalized
        )
      }
  }

  func summaryProjectLogPayloads(
    for events: [JournalRenderedHistoryEvent],
    dayKey: String,
    forceRefreshSummary: Bool
  ) async -> [JournalProjectLogPayload] {
    var orderedProjectIDs: [UUID] = []
    var accumulators: [UUID: JournalProjectLogAccumulator] = [:]

    for renderedEvent in events {
      let projectID = renderedEvent.event.projectID
      if accumulators[projectID] == nil {
        orderedProjectIDs.append(projectID)
        accumulators[projectID] = JournalProjectLogAccumulator(
          projectID: projectID,
          project: projectTitlesByID[projectID] ?? "프로젝트"
        )
      }

      let partition = await summaryProjectLogPartition(
        for: renderedEvent,
        dayKey: dayKey,
        forceRefreshSummary: forceRefreshSummary
      )
      guard !partition.isEmpty else { continue }

      var accumulator =
        accumulators[projectID]
        ?? JournalProjectLogAccumulator(
          projectID: projectID,
          project: projectTitlesByID[projectID] ?? "프로젝트"
        )
      accumulator.append(partition)
      accumulators[projectID] = accumulator
    }

    return orderedProjectIDs.compactMap { projectID in
      guard var payload = accumulators[projectID]?.payload() else { return nil }
      payload = JournalProjectLogPayload(
        id: "summary-project-log-\(projectID.uuidString)",
        projectID: payload.projectID,
        project: payload.project,
        planned: payload.planned,
        executed: payload.executed,
        journaled: payload.journaled
      )
      return payload
    }
  }

  func summaryProjectLogPartition(
    for renderedEvent: JournalRenderedHistoryEvent,
    dayKey: String,
    forceRefreshSummary: Bool
  ) async -> JournalProjectLogPartition {
    let event = renderedEvent.event

    switch event.kind {
    case .projectCreated:
      return JournalProjectLogPartition(journaled: ["projectCreated: 프로젝트 시작"])

    case .projectUpdated:
      return JournalProjectLogPartition(
        journaled: ["projectUpdated: \(historyChangeLogText(for: event))"]
      )

    case .projectTimelineChanged:
      return JournalProjectLogPartition(
        journaled: ["projectTimelineChanged: \(historyChangeLogText(for: event))"]
      )

    case .projectArchived:
      return JournalProjectLogPartition(
        journaled: ["projectArchived: \(historyChangeLogText(for: event))"]
      )

    case .projectRestored:
      return JournalProjectLogPartition(
        journaled: ["projectRestored: \(historyChangeLogText(for: event))"]
      )

    case .projectDeleted:
      return JournalProjectLogPartition(
        journaled: ["projectDeleted: \(historyChangeLogText(for: event))"]
      )

    case .taskCreated:
      return JournalProjectLogPartition(
        planned: ["taskCreated: \(historyTaskTitle(for: event).trimmingCharacters(in: .whitespacesAndNewlines))"]
      )

    case .taskCompleted:
      return JournalProjectLogPartition(
        executed: ["taskCompleted: \(historyTaskTitle(for: event).trimmingCharacters(in: .whitespacesAndNewlines))"]
      )

    case .taskReopened:
      return JournalProjectLogPartition(
        executed: ["taskReopened: \(historyTaskTitle(for: event).trimmingCharacters(in: .whitespacesAndNewlines))"]
      )

    case .taskUpdated:
      return JournalProjectLogPartition(
        journaled: ["taskUpdated: \(historyTaskTitle(for: event)) · \(historyChangeLogText(for: event))"]
      )

    case .taskScheduleChanged:
      return JournalProjectLogPartition(
        journaled: ["taskScheduleChanged: \(historyTaskTitle(for: event)) · \(historyChangeLogText(for: event))"]
      )

    case .taskMoved:
      return JournalProjectLogPartition(
        journaled: ["taskMoved: \(historyTaskTitle(for: event)) · \(historyChangeLogText(for: event))"]
      )

    case .taskDeleted:
      return JournalProjectLogPartition(
        journaled: ["taskDeleted: \(historyTaskTitle(for: event))"]
      )

    case .attachmentAdded:
      return JournalProjectLogPartition(
        journaled: [
          "attachmentAdded: \(historyAttachmentTitle(for: event).trimmingCharacters(in: .whitespacesAndNewlines))"
        ]
      )

    case .projectNoteSaved, .taskReminderNoteSaved:
      guard let delta = renderedEvent.noteDelta else { return JournalProjectLogPartition() }

      let logPrefix = event.kind == .projectNoteSaved ? "projectNoteSaved" : "taskReminderNoteSaved"
      let owner = noteOwnerPrefix(for: event)
      var journaled: [String] = []

      let addedText = delta.addedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if !addedText.isEmpty {
        let summarized = await summarizedPipelineText(
          addedText,
          cacheKeyPrefix: "\(dayKey)-\(event.id.uuidString)-added",
          forceRefreshSummary: forceRefreshSummary
        )
        let ownerPrefix = owner.map { "\($0) " } ?? ""
        journaled.append("\(logPrefix): + \(ownerPrefix)\(summarized)")
      }

      let removedText = delta.removedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if !removedText.isEmpty {
        let summarized = await summarizedPipelineText(
          removedText,
          cacheKeyPrefix: "\(dayKey)-\(event.id.uuidString)-removed",
          forceRefreshSummary: forceRefreshSummary
        )
        let ownerPrefix = owner.map { "\($0) " } ?? ""
        journaled.append("\(logPrefix): - \(ownerPrefix)\(summarized)")
      }

      return JournalProjectLogPartition(journaled: journaled)
    }
  }

  func summaryJournalNotePayloads(
    for entries: [ObsidianJournalEntry],
    dayKey: String,
    forceRefreshSummary: Bool
  ) async -> [JournalJournalNotePayload] {
    var payloads: [JournalJournalNotePayload] = []

    for entry in entries.sorted(by: { lhs, rhs in
      if lhs.occurredAt != rhs.occurredAt {
        return lhs.occurredAt < rhs.occurredAt
      }
      return lhs.id < rhs.id
    }) {
      let normalized = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { continue }

      let summarized = await summarizedPipelineText(
        normalized,
        cacheKeyPrefix: "\(dayKey)-journal-\(entry.id)",
        forceRefreshSummary: forceRefreshSummary
      )
      payloads.append(
        JournalJournalNotePayload(
          time: Self.timeFormatter.string(from: entry.occurredAt),
          note: summarized
        )
      )
    }

    return payloads
  }

  func summarizedPipelineText(
    _ text: String,
    cacheKeyPrefix: String,
    forceRefreshSummary: Bool
  ) async -> String {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }

    if normalized.count > journalLongNoteThresholdCharacterCount
      || normalized.components(separatedBy: "\n").count > journalLongNoteThresholdLineCount
    {
      return await LocalLLMService.shared.summarizeLongText(
        normalized,
        cacheKeyPrefix: cacheKeyPrefix,
        forceRefresh: forceRefreshSummary
      )
    }

    return normalized
  }

  func projectSummaryPayloads(
    for day: Date,
    dayKey: String,
    projectPayloads: [JournalProjectLogPayload],
    summaryInputSignature: String,
    forceRefreshSummary: Bool
  ) async -> [JournalProjectSummaryPayload] {
    var results: [JournalProjectSummaryPayload] = []

    for payload in projectPayloads {
      let cacheKey =
        "project-summary-\(dayKey)-\(payload.projectID.uuidString)-v\(journalDaySummaryPromptVersion)-\(appState.journalSummaryProviderSignature)-\(summaryInputSignature)"
      let resolution = await LocalLLMService.shared.summary(
        for: cacheKey,
        prompt: projectPurposeSummaryPrompt(for: payload),
        forceRefresh: forceRefreshSummary,
        maximumResponseTokens: 360
      )
      let normalized = resolution.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty, resolution.source != .unavailable else { continue }
      results.append(
        JournalProjectSummaryPayload(
          project: payload.project,
          summary: normalized
        )
      )
    }

    return results
  }

  func projectPurposeSummaryPrompt(for payload: JournalProjectLogPayload) -> String {
    """
    \(journalProjectFactSummarySystemPrompt)

    입력 JSON:
    \(journalEncodedJSONString(payload))
    """
  }

  func dailyInsightPrompt(
    for day: Date,
    projectSummaries: [JournalProjectSummaryPayload],
    journalNotePayloads: [JournalJournalNotePayload]
  ) -> String {
    let payload = JournalDailyInsightInputPayload(
      date: Self.dayFormatter.string(from: day),
      projectSummaries: projectSummaries,
      journalNotes: journalNotePayloads
    )

    return """
    \(journalDailyInsightSystemPrompt)

    입력 JSON:
    \(journalEncodedJSONString(payload))
    """
  }

  func daySummaryFeedMergeParitySentinel(
    projectPayloads: [JournalProjectLogPayload],
    journalNotePayloads: [JournalJournalNotePayload]
  ) -> String {
    var hasher = Hasher()

    for payload in projectPayloads {
      hasher.combine(payload.projectID)
      hasher.combine(payload.project)
      hasher.combine(payload.planned.joined(separator: "\n"))
      hasher.combine(payload.executed.joined(separator: "\n"))
      hasher.combine(payload.journaled.joined(separator: "\n"))
    }

    for payload in journalNotePayloads {
      hasher.combine(payload.time)
      hasher.combine(payload.note)
    }

    return String(hasher.finalize())
  }

  func daySummaryInputSignature(
    projectPayloads: [JournalProjectLogPayload],
    journalNotePayloads: [JournalJournalNotePayload]
  ) -> String {
    daySummaryFeedMergeParitySentinel(
      projectPayloads: projectPayloads,
      journalNotePayloads: journalNotePayloads
    )
  }

  func legacyDaySummaryInputSignature(
    for events: [JournalRenderedHistoryEvent],
    journalEntries: [ObsidianJournalEntry]
  ) -> String {
    var hasher = Hasher()

    for renderedEvent in events {
      let event = renderedEvent.event
      hasher.combine(event.id)
      hasher.combine(event.projectID)
      hasher.combine(event.kind.rawValue)
      hasher.combine(event.occurredAt.timeIntervalSinceReferenceDate)
      hasher.combine(event.createdAt.timeIntervalSinceReferenceDate)
      hasher.combine(event.taskID)
      hasher.combine(event.taskTitleSnapshot ?? "")
      hasher.combine(event.attachmentFilename ?? "")
      hasher.combine(renderedEvent.noteDelta?.addedLines.joined(separator: "\n") ?? "")
      hasher.combine(renderedEvent.noteDelta?.removedLines.joined(separator: "\n") ?? "")
    }

    for entry in journalEntries {
      hasher.combine(entry.id)
      hasher.combine(entry.occurredAt.timeIntervalSinceReferenceDate)
      hasher.combine(entry.body)
    }

    return String(hasher.finalize())
  }

  func aiSummaryPrompt(
    for cluster: JournalSystemCluster,
    projectTitle: String,
    detailLines: [JournalPreparedLine],
    journalEntries: [ObsidianJournalEntry]
  ) -> String {
    let rawDetails = detailLines
      .map { line in line.segments.map(\.text).joined() }
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n- ")

    let rawNotes = journalEntries
      .sorted { lhs, rhs in
        if lhs.occurredAt != rhs.occurredAt {
          return lhs.occurredAt < rhs.occurredAt
        }
        return lhs.id < rhs.id
      }
      .map { entry in
        let noteBody = normalizedDisplayLines(entry.body)
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .joined(separator: " / ")
        return "[\(Self.timeFormatter.string(from: entry.occurredAt))] \(noteBody)"
      }
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n- ")

    return """
    당신은 개인 작업 저널을 하루 단위로 정리하는 편집자다.
    항상 한국어로만 쓴다.
    이 출력은 어제의 회고 화면에 들어간다.
    프로젝트명과 시간, 숫자 메타는 반복하지 않는다.
    실제로 무엇을 만들고, 끝내고, 고쳤는지 가능한 한 구체적으로 쓴다.
    추상적으로 "정리했다", "진행했다"로만 쓰지 않는다.
    사용자 메모는 반복해서 복붙하지 말고, 그 안의 판단, 불만, 의도, 우선순위 변화를 읽어 "의견"으로 요약한다.
    삭제가 실제로 있을 때만 언급한다.
    없는 사실은 추측하지 않는다.

    출력 형식은 정확히 두 줄:
    요약: <1~2문장. 작업 맥락이 보이게>
    의견: <사용자 판단/의도/불만 1문장. 없으면 '없음'>

    프로젝트: \(projectTitle)
    구간: \(clusterTimeRange(cluster))

    시스템 기록:
    - \(rawDetails.isEmpty ? "없음" : rawDetails)

    사용자 메모:
    - \(rawNotes.isEmpty ? "없음" : rawNotes)
    """
  }

  func noteOwnerPrefix(for event: ProjectHistoryEvent) -> String? {
    let taskTitle = event.taskTitleSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return taskTitle.isEmpty ? nil : taskTitle
  }
}
