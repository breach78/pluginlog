import Foundation

enum CompassConfidence: String, Codable, CaseIterable, Sendable {
  case low
  case medium
  case high
}

enum CompassInsightAxis: String, Codable, CaseIterable, Sendable {
  case psychology
  case sociology
  case creativity
  case productivity
}

enum CompassHypothesisLayer: String, Codable, CaseIterable, Sendable {
  case corePersona
  case currentSeason
  case operationalTendencies
  case blindSpots
}

enum CompassEvidenceSourceKind: String, Codable, CaseIterable, Sendable {
  case journalEntry
  case journalDaySummary
  case journalPeriodSummary
  case project
  case task
  case historyEvent
  case userAnnotation
}

enum CompassBootstrapStage: String, Codable, CaseIterable, Sendable {
  case idle
  case journalIndex
  case daySummaries
  case periodSummaries
  case selfModel
  case completed
  case failed
}

enum CompassCheckpointStatus: String, Codable, CaseIterable, Sendable {
  case pending
  case inProgress
  case completed
  case failed
}

enum CompassPeriodGranularity: String, Codable, CaseIterable, Sendable {
  case week
  case month
}

enum CompassModelRole: String, Codable, CaseIterable, Hashable, Sendable {
  case primary
  case supporting
  case fallback
}

enum CompassSeedStatus: String, Codable, CaseIterable, Sendable {
  case draft
  case approved
  case superseded

  var title: String {
    switch self {
    case .draft:
      return "Draft"
    case .approved:
      return "Approved"
    case .superseded:
      return "Superseded"
    }
  }
}

enum CompassSeedOrigin: String, Codable, CaseIterable, Sendable {
  case assistantUserReviewed
  case importedExternal
  case appBootstrap

  var title: String {
    switch self {
    case .assistantUserReviewed:
      return "Assistant Reviewed"
    case .importedExternal:
      return "Imported"
    case .appBootstrap:
      return "App Bootstrap"
    }
  }
}

enum CompassSchedulingWindow: String, Codable, CaseIterable, Sendable {
  case morning
  case afternoon
  case evening
  case flexible
}

enum CompassGuardrailSeverity: String, Codable, CaseIterable, Sendable {
  case soft
  case hard
}

struct CompassPromptVersionSet: Codable, Hashable, Sendable {
  var schemaVersion: Int
  var bootstrapPromptVersion: Int
  var deltaPromptVersion: Int
  var recommendationPromptVersion: Int

  static let initial = CompassPromptVersionSet(
    schemaVersion: 1,
    bootstrapPromptVersion: 1,
    deltaPromptVersion: 1,
    recommendationPromptVersion: 1
  )
}

struct CompassModelConfiguration: Codable, Hashable, Sendable {
  var primaryModel: String
  var supportingModel: String
  var fallbackModel: String?

  static let initial = CompassModelConfiguration(
    primaryModel: "gemini-3.1-pro-preview",
    supportingModel: "gemini-2.5-flash",
    fallbackModel: nil
  )
}

struct CompassEvidencePointer: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var sourceKind: CompassEvidenceSourceKind
  var sourceID: String
  var dayKey: String?
  var excerpt: String?
  var recordedAt: Date?
  var weight: Double?

  init(
    id: UUID = UUID(),
    sourceKind: CompassEvidenceSourceKind,
    sourceID: String,
    dayKey: String? = nil,
    excerpt: String? = nil,
    recordedAt: Date? = nil,
    weight: Double? = nil
  ) {
    self.id = id
    self.sourceKind = sourceKind
    self.sourceID = sourceID
    self.dayKey = dayKey
    self.excerpt = excerpt
    self.recordedAt = recordedAt
    self.weight = weight
  }
}

struct CompassHypothesis: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var layer: CompassHypothesisLayer
  var axis: CompassInsightAxis
  var title: String
  var statement: String
  var confidence: CompassConfidence
  var evidence: [CompassEvidencePointer]
  var lastUpdatedAt: Date

  init(
    id: UUID = UUID(),
    layer: CompassHypothesisLayer,
    axis: CompassInsightAxis,
    title: String,
    statement: String,
    confidence: CompassConfidence,
    evidence: [CompassEvidencePointer] = [],
    lastUpdatedAt: Date = .now
  ) {
    self.id = id
    self.layer = layer
    self.axis = axis
    self.title = title
    self.statement = statement
    self.confidence = confidence
    self.evidence = evidence
    self.lastUpdatedAt = lastUpdatedAt
  }
}

struct CompassSteeringRule: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var title: String
  var instruction: String
  var rationale: String
  var confidence: CompassConfidence
  var evidence: [CompassEvidencePointer]
  var lastUpdatedAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    instruction: String,
    rationale: String,
    confidence: CompassConfidence,
    evidence: [CompassEvidencePointer] = [],
    lastUpdatedAt: Date = .now
  ) {
    self.id = id
    self.title = title
    self.instruction = instruction
    self.rationale = rationale
    self.confidence = confidence
    self.evidence = evidence
    self.lastUpdatedAt = lastUpdatedAt
  }
}

struct CompassSourceWindow: Codable, Hashable, Sendable {
  var firstJournalDay: Date?
  var lastJournalDay: Date?
  var indexedDayCount: Int
  var indexedEntryCount: Int

  init(
    firstJournalDay: Date? = nil,
    lastJournalDay: Date? = nil,
    indexedDayCount: Int = 0,
    indexedEntryCount: Int = 0
  ) {
    self.firstJournalDay = firstJournalDay
    self.lastJournalDay = lastJournalDay
    self.indexedDayCount = indexedDayCount
    self.indexedEntryCount = indexedEntryCount
  }
}

struct CompassArtifactGenerationMetadata: Codable, Hashable, Sendable {
  var generationID: UUID
  var createdAt: Date
  var updatedAt: Date
  var promptVersions: CompassPromptVersionSet
  var modelConfiguration: CompassModelConfiguration
  var sourceWindow: CompassSourceWindow

  init(
    generationID: UUID = UUID(),
    createdAt: Date = .now,
    updatedAt: Date = .now,
    promptVersions: CompassPromptVersionSet = .initial,
    modelConfiguration: CompassModelConfiguration = .initial,
    sourceWindow: CompassSourceWindow = CompassSourceWindow()
  ) {
    self.generationID = generationID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.promptVersions = promptVersions
    self.modelConfiguration = modelConfiguration
    self.sourceWindow = sourceWindow
  }
}

struct CompassMotivationSignal: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var axis: CompassInsightAxis
  var title: String
  var statement: String
  var confidence: CompassConfidence
  var evidence: [CompassEvidencePointer]
  var lastUpdatedAt: Date

  init(
    id: UUID = UUID(),
    axis: CompassInsightAxis,
    title: String,
    statement: String,
    confidence: CompassConfidence,
    evidence: [CompassEvidencePointer] = [],
    lastUpdatedAt: Date = .now
  ) {
    self.id = id
    self.axis = axis
    self.title = title
    self.statement = statement
    self.confidence = confidence
    self.evidence = evidence
    self.lastUpdatedAt = lastUpdatedAt
  }
}

struct CompassSchedulingPreference: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var title: String
  var instruction: String
  var preferredWindow: CompassSchedulingWindow
  var maxFocusBlockMinutes: Int?
  var confidence: CompassConfidence
  var evidence: [CompassEvidencePointer]
  var lastUpdatedAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    instruction: String,
    preferredWindow: CompassSchedulingWindow = .flexible,
    maxFocusBlockMinutes: Int? = nil,
    confidence: CompassConfidence,
    evidence: [CompassEvidencePointer] = [],
    lastUpdatedAt: Date = .now
  ) {
    self.id = id
    self.title = title
    self.instruction = instruction
    self.preferredWindow = preferredWindow
    self.maxFocusBlockMinutes = maxFocusBlockMinutes
    self.confidence = confidence
    self.evidence = evidence
    self.lastUpdatedAt = lastUpdatedAt
  }
}

struct CompassRecommendationGuardrail: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var title: String
  var rule: String
  var severity: CompassGuardrailSeverity
  var confidence: CompassConfidence
  var evidence: [CompassEvidencePointer]
  var lastUpdatedAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    rule: String,
    severity: CompassGuardrailSeverity = .hard,
    confidence: CompassConfidence,
    evidence: [CompassEvidencePointer] = [],
    lastUpdatedAt: Date = .now
  ) {
    self.id = id
    self.title = title
    self.rule = rule
    self.severity = severity
    self.confidence = confidence
    self.evidence = evidence
    self.lastUpdatedAt = lastUpdatedAt
  }
}

struct CompassBaselineGenerationPolicy: Codable, Hashable, Sendable {
  var allowAutomaticOverwrite: Bool
  var allowWeeklyMergeProposal: Bool
  var requireUserApprovalForBaselineChange: Bool

  init(
    allowAutomaticOverwrite: Bool = false,
    allowWeeklyMergeProposal: Bool = true,
    requireUserApprovalForBaselineChange: Bool = true
  ) {
    self.allowAutomaticOverwrite = allowAutomaticOverwrite
    self.allowWeeklyMergeProposal = allowWeeklyMergeProposal
    self.requireUserApprovalForBaselineChange = requireUserApprovalForBaselineChange
  }
}

struct CompassSeedManifest: Codable, Hashable, Sendable {
  var schemaVersion: Int
  var seedVersion: Int
  var status: CompassSeedStatus
  var origin: CompassSeedOrigin
  var createdAt: Date
  var approvedAt: Date?
  var importedAt: Date?
  var journalWindow: CompassSourceWindow
  var baselineGenerationPolicy: CompassBaselineGenerationPolicy
  var notes: String?

  init(
    schemaVersion: Int = CompassStorageManifest.currentSchemaVersion,
    seedVersion: Int = 1,
    status: CompassSeedStatus = .approved,
    origin: CompassSeedOrigin = .assistantUserReviewed,
    createdAt: Date = .now,
    approvedAt: Date? = nil,
    importedAt: Date? = nil,
    journalWindow: CompassSourceWindow = CompassSourceWindow(),
    baselineGenerationPolicy: CompassBaselineGenerationPolicy = CompassBaselineGenerationPolicy(),
    notes: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.seedVersion = seedVersion
    self.status = status
    self.origin = origin
    self.createdAt = createdAt
    self.approvedAt = approvedAt
    self.importedAt = importedAt
    self.journalWindow = journalWindow
    self.baselineGenerationPolicy = baselineGenerationPolicy
    self.notes = notes
  }
}

struct CompassSelfModel: Codable, Hashable, Sendable {
  var metadata: CompassArtifactGenerationMetadata
  var overview: String
  var corePersona: [CompassHypothesis]
  var currentSeason: [CompassHypothesis]
  var operationalTendencies: [CompassHypothesis]
  var blindSpots: [CompassHypothesis]
  var steeringRules: [CompassSteeringRule]
  var motivationMap: [CompassMotivationSignal]
  var schedulingPreferences: [CompassSchedulingPreference]
  var recommendationGuardrails: [CompassRecommendationGuardrail]

  init(
    metadata: CompassArtifactGenerationMetadata = CompassArtifactGenerationMetadata(),
    overview: String = "",
    corePersona: [CompassHypothesis] = [],
    currentSeason: [CompassHypothesis] = [],
    operationalTendencies: [CompassHypothesis] = [],
    blindSpots: [CompassHypothesis] = [],
    steeringRules: [CompassSteeringRule] = [],
    motivationMap: [CompassMotivationSignal] = [],
    schedulingPreferences: [CompassSchedulingPreference] = [],
    recommendationGuardrails: [CompassRecommendationGuardrail] = []
  ) {
    self.metadata = metadata
    self.overview = overview
    self.corePersona = corePersona
    self.currentSeason = currentSeason
    self.operationalTendencies = operationalTendencies
    self.blindSpots = blindSpots
    self.steeringRules = steeringRules
    self.motivationMap = motivationMap
    self.schedulingPreferences = schedulingPreferences
    self.recommendationGuardrails = recommendationGuardrails
  }

  private enum CodingKeys: String, CodingKey {
    case metadata
    case overview
    case corePersona
    case currentSeason
    case operationalTendencies
    case blindSpots
    case steeringRules
    case motivationMap
    case schedulingPreferences
    case recommendationGuardrails
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    metadata =
      try container.decodeIfPresent(CompassArtifactGenerationMetadata.self, forKey: .metadata)
      ?? CompassArtifactGenerationMetadata()
    overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? ""
    corePersona = try container.decodeIfPresent([CompassHypothesis].self, forKey: .corePersona) ?? []
    currentSeason =
      try container.decodeIfPresent([CompassHypothesis].self, forKey: .currentSeason) ?? []
    operationalTendencies =
      try container.decodeIfPresent([CompassHypothesis].self, forKey: .operationalTendencies) ?? []
    blindSpots = try container.decodeIfPresent([CompassHypothesis].self, forKey: .blindSpots) ?? []
    steeringRules =
      try container.decodeIfPresent([CompassSteeringRule].self, forKey: .steeringRules) ?? []
    motivationMap =
      try container.decodeIfPresent([CompassMotivationSignal].self, forKey: .motivationMap) ?? []
    schedulingPreferences =
      try container.decodeIfPresent([CompassSchedulingPreference].self, forKey: .schedulingPreferences)
      ?? []
    recommendationGuardrails =
      try container.decodeIfPresent(
        [CompassRecommendationGuardrail].self,
        forKey: .recommendationGuardrails
      ) ?? []
  }
}

struct CompassBootstrapCheckpoint: Codable, Hashable, Sendable {
  var stage: CompassBootstrapStage
  var status: CompassCheckpointStatus
  var updatedAt: Date
  var detail: String?

  init(
    stage: CompassBootstrapStage,
    status: CompassCheckpointStatus = .pending,
    updatedAt: Date = .now,
    detail: String? = nil
  ) {
    self.stage = stage
    self.status = status
    self.updatedAt = updatedAt
    self.detail = detail
  }
}

struct CompassBootstrapState: Codable, Hashable, Sendable {
  var generationID: UUID
  var currentStage: CompassBootstrapStage
  var startedAt: Date
  var updatedAt: Date
  var completedAt: Date?
  var lastError: String?
  var checkpoints: [CompassBootstrapCheckpoint]

  init(
    generationID: UUID = UUID(),
    currentStage: CompassBootstrapStage = .idle,
    startedAt: Date = .now,
    updatedAt: Date = .now,
    completedAt: Date? = nil,
    lastError: String? = nil,
    checkpoints: [CompassBootstrapCheckpoint] = []
  ) {
    self.generationID = generationID
    self.currentStage = currentStage
    self.startedAt = startedAt
    self.updatedAt = updatedAt
    self.completedAt = completedAt
    self.lastError = lastError
    self.checkpoints = checkpoints
  }
}

struct CompassJournalIndex: Codable, Hashable, Sendable {
  var indexedAt: Date
  var journalRootPath: String?
  var availableDayKeys: [String]
  var sourceRevision: String?

  init(
    indexedAt: Date = .now,
    journalRootPath: String? = nil,
    availableDayKeys: [String] = [],
    sourceRevision: String? = nil
  ) {
    self.indexedAt = indexedAt
    self.journalRootPath = journalRootPath
    self.availableDayKeys = availableDayKeys
    self.sourceRevision = sourceRevision
  }
}

struct CompassJournalDaySummary: Codable, Hashable, Sendable {
  var dayKey: String
  var summary: String
  var highlights: [String]
  var sourceRevision: String?
  var metadata: CompassArtifactGenerationMetadata

  init(
    dayKey: String,
    summary: String,
    highlights: [String] = [],
    sourceRevision: String? = nil,
    metadata: CompassArtifactGenerationMetadata = CompassArtifactGenerationMetadata()
  ) {
    self.dayKey = dayKey
    self.summary = summary
    self.highlights = highlights
    self.sourceRevision = sourceRevision
    self.metadata = metadata
  }
}

struct CompassJournalPeriodSummary: Identifiable, Codable, Hashable, Sendable {
  var granularity: CompassPeriodGranularity
  var periodKey: String
  var coveredDayKeys: [String]
  var summary: String
  var sourceRevision: String?
  var metadata: CompassArtifactGenerationMetadata

  var id: String { "\(granularity.rawValue)-\(periodKey)" }

  init(
    granularity: CompassPeriodGranularity,
    periodKey: String,
    coveredDayKeys: [String],
    summary: String,
    sourceRevision: String? = nil,
    metadata: CompassArtifactGenerationMetadata = CompassArtifactGenerationMetadata()
  ) {
    self.granularity = granularity
    self.periodKey = periodKey
    self.coveredDayKeys = coveredDayKeys
    self.summary = summary
    self.sourceRevision = sourceRevision
    self.metadata = metadata
  }
}

struct CompassDailyDelta: Codable, Hashable, Sendable {
  var dayKey: String
  var summary: String
  var changedHypothesisIDs: [UUID]
  var metadata: CompassArtifactGenerationMetadata

  init(
    dayKey: String,
    summary: String,
    changedHypothesisIDs: [UUID] = [],
    metadata: CompassArtifactGenerationMetadata = CompassArtifactGenerationMetadata()
  ) {
    self.dayKey = dayKey
    self.summary = summary
    self.changedHypothesisIDs = changedHypothesisIDs
    self.metadata = metadata
  }
}

struct CompassStorageManifest: Codable, Hashable, Sendable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int
  var createdAt: Date
  var updatedAt: Date
  var promptVersions: CompassPromptVersionSet
  var activeModelConfiguration: CompassModelConfiguration
  var lastFullAnalysisAt: Date?
  var lastIncrementalUpdateAt: Date?

  init(
    schemaVersion: Int = CompassStorageManifest.currentSchemaVersion,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    promptVersions: CompassPromptVersionSet = .initial,
    activeModelConfiguration: CompassModelConfiguration = .initial,
    lastFullAnalysisAt: Date? = nil,
    lastIncrementalUpdateAt: Date? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.promptVersions = promptVersions
    self.activeModelConfiguration = activeModelConfiguration
    self.lastFullAnalysisAt = lastFullAnalysisAt
    self.lastIncrementalUpdateAt = lastIncrementalUpdateAt
  }
}

enum CompassReanalysisPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
  case automaticIncremental
  case manualRefreshOnly

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automaticIncremental:
      return "자동 증분 갱신"
    case .manualRefreshOnly:
      return "수동 갱신만"
    }
  }

  var summary: String {
    switch self {
    case .automaticIncremental:
      return "나침반을 열 때 변경된 저널만 자동 반영한다."
    case .manualRefreshOnly:
      return "저장된 자기모델만 읽고, 사용자가 갱신을 눌렀을 때만 변경분을 반영한다."
    }
  }
}

enum CompassActionPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
  case approvalRequired
  case recommendationOnly

  var id: String { rawValue }

  var title: String {
    switch self {
    case .approvalRequired:
      return "승인 후 반영"
    case .recommendationOnly:
      return "추천만 보기"
    }
  }

  var summary: String {
    switch self {
    case .approvalRequired:
      return "추천을 확인한 뒤 할일과 일정 반영을 직접 승인한다."
    case .recommendationOnly:
      return "실제 프로젝트와 일정은 건드리지 않고 추천만 본다."
    }
  }
}

enum CompassPreferenceKeys {
  static let reanalysisPolicy = "compass.reanalysisPolicy"
  static let actionPolicy = "compass.actionPolicy"
}

enum CompassFullRebuildReason: String, Codable, CaseIterable, Sendable {
  case initialBootstrap
  case manualUserRequest
  case schemaVersionChanged
  case promptVersionChanged
  case storageCorruption
  case journalIndexMismatch

  static var allowedUserFacingReasons: [CompassFullRebuildReason] {
    [
      .manualUserRequest,
      .schemaVersionChanged,
      .promptVersionChanged,
      .storageCorruption,
      .journalIndexMismatch,
    ]
  }

  var title: String {
    switch self {
    case .initialBootstrap:
      return "초기 분석"
    case .manualUserRequest:
      return "사용자 명시 요청"
    case .schemaVersionChanged:
      return "스키마 버전 변경"
    case .promptVersionChanged:
      return "프롬프트 버전 변경"
    case .storageCorruption:
      return "저장 자산 손상"
    case .journalIndexMismatch:
      return "저널 인덱스 오류"
    }
  }
}

enum CompassUsagePhase: String, Codable, CaseIterable, Sendable {
  case bootstrap
  case delta
  case recommendation
}

struct CompassTokenUsageTotals: Codable, Hashable, Sendable {
  var requestCount: Int
  var promptTokenCount: Int
  var candidatesTokenCount: Int
  var thoughtsTokenCount: Int
  var totalTokenCount: Int

  init(
    requestCount: Int = 0,
    promptTokenCount: Int = 0,
    candidatesTokenCount: Int = 0,
    thoughtsTokenCount: Int = 0,
    totalTokenCount: Int = 0
  ) {
    self.requestCount = requestCount
    self.promptTokenCount = promptTokenCount
    self.candidatesTokenCount = candidatesTokenCount
    self.thoughtsTokenCount = thoughtsTokenCount
    self.totalTokenCount = totalTokenCount
  }

  mutating func record(
    promptTokenCount: Int?,
    candidatesTokenCount: Int?,
    thoughtsTokenCount: Int?,
    totalTokenCount: Int?
  ) {
    record(
      promptTokenCount: promptTokenCount,
      candidatesTokenCount: candidatesTokenCount,
      thoughtsTokenCount: thoughtsTokenCount,
      totalTokenCount: totalTokenCount,
      requestCount: 1
    )
  }

  mutating func record(
    promptTokenCount: Int?,
    candidatesTokenCount: Int?,
    thoughtsTokenCount: Int?,
    totalTokenCount: Int?,
    requestCount: Int
  ) {
    self.requestCount += max(0, requestCount)
    self.promptTokenCount += max(0, promptTokenCount ?? 0)
    self.candidatesTokenCount += max(0, candidatesTokenCount ?? 0)
    self.thoughtsTokenCount += max(0, thoughtsTokenCount ?? 0)
    self.totalTokenCount += max(0, totalTokenCount ?? 0)
  }

  mutating func merge(_ other: CompassTokenUsageTotals) {
    requestCount += other.requestCount
    promptTokenCount += other.promptTokenCount
    candidatesTokenCount += other.candidatesTokenCount
    thoughtsTokenCount += other.thoughtsTokenCount
    totalTokenCount += other.totalTokenCount
  }
}

struct CompassUsageLedger: Codable, Hashable, Sendable {
  var bootstrap: CompassTokenUsageTotals
  var delta: CompassTokenUsageTotals
  var recommendation: CompassTokenUsageTotals
  var updatedAt: Date

  init(
    bootstrap: CompassTokenUsageTotals = CompassTokenUsageTotals(),
    delta: CompassTokenUsageTotals = CompassTokenUsageTotals(),
    recommendation: CompassTokenUsageTotals = CompassTokenUsageTotals(),
    updatedAt: Date = .now
  ) {
    self.bootstrap = bootstrap
    self.delta = delta
    self.recommendation = recommendation
    self.updatedAt = updatedAt
  }

  var total: CompassTokenUsageTotals {
    var totals = CompassTokenUsageTotals()
    totals.merge(bootstrap)
    totals.merge(delta)
    totals.merge(recommendation)
    return totals
  }

  mutating func record(
    phase: CompassUsagePhase,
    promptTokenCount: Int?,
    candidatesTokenCount: Int?,
    thoughtsTokenCount: Int?,
    totalTokenCount: Int?,
    requestCount: Int = 1
  ) {
    switch phase {
    case .bootstrap:
      bootstrap.record(
        promptTokenCount: promptTokenCount,
        candidatesTokenCount: candidatesTokenCount,
        thoughtsTokenCount: thoughtsTokenCount,
        totalTokenCount: totalTokenCount,
        requestCount: requestCount
      )
    case .delta:
      delta.record(
        promptTokenCount: promptTokenCount,
        candidatesTokenCount: candidatesTokenCount,
        thoughtsTokenCount: thoughtsTokenCount,
        totalTokenCount: totalTokenCount,
        requestCount: requestCount
      )
    case .recommendation:
      recommendation.record(
        promptTokenCount: promptTokenCount,
        candidatesTokenCount: candidatesTokenCount,
        thoughtsTokenCount: thoughtsTokenCount,
        totalTokenCount: totalTokenCount,
        requestCount: requestCount
      )
    }

    updatedAt = .now
  }
}

struct CompassAnalysisTelemetry: Codable, Hashable, Sendable {
  var usageLedger: CompassUsageLedger
  var lastFullRebuildReason: CompassFullRebuildReason?
  var lastBlockedFullRebuildAt: Date?
  var lastBlockedFullRebuildReason: String?

  init(
    usageLedger: CompassUsageLedger = CompassUsageLedger(),
    lastFullRebuildReason: CompassFullRebuildReason? = nil,
    lastBlockedFullRebuildAt: Date? = nil,
    lastBlockedFullRebuildReason: String? = nil
  ) {
    self.usageLedger = usageLedger
    self.lastFullRebuildReason = lastFullRebuildReason
    self.lastBlockedFullRebuildAt = lastBlockedFullRebuildAt
    self.lastBlockedFullRebuildReason = lastBlockedFullRebuildReason
  }
}

struct CompassAnalysisStatus: Hashable, Sendable {
  var schemaVersion: Int
  var promptVersions: CompassPromptVersionSet
  var activeModelConfiguration: CompassModelConfiguration
  var lastFullAnalysisAt: Date?
  var lastIncrementalUpdateAt: Date?
  var usageLedger: CompassUsageLedger
  var rebuildPolicySummary: String
  var allowedRebuildReasons: [CompassFullRebuildReason]
  var lastBlockedRebuildReason: String?
  var lastBlockedRebuildAt: Date?
  var seedManifest: CompassSeedManifest?
  var hasSeedReview: Bool

  var totalUsage: CompassTokenUsageTotals {
    usageLedger.total
  }
}

enum CompassDateKeyCodec {
  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM"
    return formatter
  }()

  static func dayKey(for date: Date) -> String {
    dayFormatter.string(from: date)
  }

  static func date(fromDayKey key: String) -> Date? {
    dayFormatter.date(from: key)
  }

  static func monthKey(for date: Date) -> String {
    monthFormatter.string(from: date)
  }

  static func weekKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    let year = components.yearForWeekOfYear ?? 0
    let week = components.weekOfYear ?? 0
    return String(format: "%04d-W%02d", year, week)
  }
}
