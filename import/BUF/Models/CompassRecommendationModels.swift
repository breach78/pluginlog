import Foundation

struct CompassNorthStar: Hashable, Sendable {
  var title: String
  var summary: String
  var workMode: String
  var caution: String?

  init(
    title: String,
    summary: String,
    workMode: String,
    caution: String? = nil
  ) {
    self.title = title
    self.summary = summary
    self.workMode = workMode
    self.caution = caution
  }
}

struct CompassPriorityRecommendation: Identifiable, Hashable, Sendable {
  var id: String
  var taskID: UUID?
  var projectID: UUID?
  var title: String
  var projectTitle: String?
  var rationale: String
  var estimatedMinutes: Int?
  var dueDate: Date?
  var isOverdue: Bool
  var evidence: [CompassEvidencePointer]

  init(
    id: String = UUID().uuidString,
    taskID: UUID? = nil,
    projectID: UUID? = nil,
    title: String,
    projectTitle: String? = nil,
    rationale: String,
    estimatedMinutes: Int? = nil,
    dueDate: Date? = nil,
    isOverdue: Bool = false,
    evidence: [CompassEvidencePointer] = []
  ) {
    self.id = id
    self.taskID = taskID
    self.projectID = projectID
    self.title = title
    self.projectTitle = projectTitle
    self.rationale = rationale
    self.estimatedMinutes = estimatedMinutes
    self.dueDate = dueDate
    self.isOverdue = isOverdue
    self.evidence = evidence
  }
}

struct CompassMissingTaskSuggestion: Identifiable, Hashable, Sendable {
  var id: String
  var projectID: UUID?
  var projectTitle: String?
  var title: String
  var suggestedTaskTitle: String
  var rationale: String
  var evidence: [CompassEvidencePointer]

  init(
    id: String = UUID().uuidString,
    projectID: UUID? = nil,
    projectTitle: String? = nil,
    title: String,
    suggestedTaskTitle: String,
    rationale: String,
    evidence: [CompassEvidencePointer] = []
  ) {
    self.id = id
    self.projectID = projectID
    self.projectTitle = projectTitle
    self.title = title
    self.suggestedTaskTitle = suggestedTaskTitle
    self.rationale = rationale
    self.evidence = evidence
  }
}

struct CompassScheduleSuggestion: Identifiable, Hashable, Sendable {
  var id: String
  var title: String
  var summary: String
  var startHour: Int?
  var startMinute: Int?
  var durationMinutes: Int
  var taskIDs: [UUID]

  init(
    id: String = UUID().uuidString,
    title: String,
    summary: String,
    startHour: Int? = nil,
    startMinute: Int? = nil,
    durationMinutes: Int,
    taskIDs: [UUID] = []
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.startHour = startHour
    self.startMinute = startMinute
    self.durationMinutes = max(15, durationMinutes)
    self.taskIDs = taskIDs
  }
}

struct CompassPatternInsight: Identifiable, Hashable, Sendable {
  var id: String
  var title: String
  var summary: String
  var confidence: CompassConfidence
  var evidence: [CompassEvidencePointer]

  init(
    id: String = UUID().uuidString,
    title: String,
    summary: String,
    confidence: CompassConfidence,
    evidence: [CompassEvidencePointer] = []
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.confidence = confidence
    self.evidence = evidence
  }
}

struct CompassBoardSnapshot: Hashable, Sendable {
  var generatedAt: Date
  var northStar: CompassNorthStar
  var priorities: [CompassPriorityRecommendation]
  var missingSuggestions: [CompassMissingTaskSuggestion]
  var scheduleSuggestions: [CompassScheduleSuggestion]
  var patternInsights: [CompassPatternInsight]
  var evidenceHighlights: [CompassEvidencePointer]
  var selfModelOverview: String
  var analysisStatus: CompassAnalysisStatus?

  init(
    generatedAt: Date = .now,
    northStar: CompassNorthStar,
    priorities: [CompassPriorityRecommendation] = [],
    missingSuggestions: [CompassMissingTaskSuggestion] = [],
    scheduleSuggestions: [CompassScheduleSuggestion] = [],
    patternInsights: [CompassPatternInsight] = [],
    evidenceHighlights: [CompassEvidencePointer] = [],
    selfModelOverview: String = "",
    analysisStatus: CompassAnalysisStatus? = nil
  ) {
    self.generatedAt = generatedAt
    self.northStar = northStar
    self.priorities = priorities
    self.missingSuggestions = missingSuggestions
    self.scheduleSuggestions = scheduleSuggestions
    self.patternInsights = patternInsights
    self.evidenceHighlights = evidenceHighlights
    self.selfModelOverview = selfModelOverview
    self.analysisStatus = analysisStatus
  }
}

extension CompassBoardSnapshot {
  static let preview = CompassBoardSnapshot(
    northStar: CompassNorthStar(
      title: "오늘은 설계가 아니라 연결을 끝낸다",
      summary: "이미 정리된 구조를 실제 할일과 일정으로 내려서 오늘 안에 마찰 구간을 닫는 날로 잡는다.",
      workMode: "Execution Bridge",
      caution: "결정만 하고 시스템 반영을 미루는 패턴을 반복하지 않는다."
    ),
    priorities: [
      CompassPriorityRecommendation(
        taskID: UUID(),
        projectID: UUID(),
        title: "Compass 추천 모델을 실제 작업 후보와 연결하기",
        projectTitle: "Brain Unfog",
        rationale: "설계는 충분하다. 오늘은 앱 내부 데이터와 AI 판단을 연결하는 지점이 실제 전진을 만든다.",
        estimatedMinutes: 90,
        dueDate: .now.addingTimeInterval(4 * 3600),
        isOverdue: false,
        evidence: [
          CompassEvidencePointer(
            sourceKind: .journalPeriodSummary,
            sourceID: "week-2026-W12",
            dayKey: "2026-03-18",
            excerpt: "설계에서 실행 연결로 무게중심이 이동했다.",
            weight: 0.9
          )
        ]
      ),
      CompassPriorityRecommendation(
        taskID: UUID(),
        projectID: UUID(),
        title: "증분 갱신 결과를 나침반 카드에 노출하기",
        projectTitle: "Brain Unfog",
        rationale: "기존 자기모델이 실제 화면에서 읽히지 않으면 부트스트랩 자산이 죽은 데이터로 남는다.",
        estimatedMinutes: 70,
        dueDate: .now.addingTimeInterval(7 * 3600),
        isOverdue: false
      ),
      CompassPriorityRecommendation(
        taskID: UUID(),
        projectID: UUID(),
        title: "반영 액션에 필요한 버튼 계약 정리",
        projectTitle: "Brain Unfog",
        rationale: "다음 페이즈에서 실제 할일/일정 반영을 붙이기 위한 UI 계약을 먼저 닫아야 한다.",
        estimatedMinutes: 45,
        dueDate: .now.addingTimeInterval(10 * 3600),
        isOverdue: false
      ),
    ],
    missingSuggestions: [
      CompassMissingTaskSuggestion(
        projectID: UUID(),
        projectTitle: "Brain Unfog",
        title: "빠진 연결 작업",
        suggestedTaskTitle: "Compass 카드에서 제안 수락 플로우 설계",
        rationale: "반복 기록상 '좋은 판단' 다음 단계의 시스템 반영이 늦어지는 패턴이 있다."
      )
    ],
    scheduleSuggestions: [
      CompassScheduleSuggestion(
        title: "오전 깊은 연결 작업",
        summary: "우선순위 1개만 붙잡고 추천 엔진과 카드 구조를 끝낸다.",
        startHour: 9,
        startMinute: 30,
        durationMinutes: 100
      ),
      CompassScheduleSuggestion(
        title: "오후 시스템 반영 정리",
        summary: "남은 두 항목을 묶어서 액션 흐름과 카드 메타를 다듬는다.",
        startHour: 14,
        startMinute: 0,
        durationMinutes: 110
      ),
    ],
    patternInsights: [
      CompassPatternInsight(
        title: "설계 후 연결 누락",
        summary: "의사결정과 구조 설계는 빠르지만 실제 프로젝트/할일 반영은 한 박자 늦어지는 편이다.",
        confidence: .high
      ),
      CompassPatternInsight(
        title: "큰 문제 먼저 해결",
        summary: "구현 세부보다 시스템 구조를 먼저 닫을 때 에너지가 오른다.",
        confidence: .medium
      ),
    ],
    evidenceHighlights: [
      CompassEvidencePointer(
        sourceKind: .journalDaySummary,
        sourceID: "2026-03-19",
        dayKey: "2026-03-19",
        excerpt: "빠진 일을 실제 프로젝트에 넣고 오늘 일정으로 반영하는 흐름이 필요하다.",
        weight: 0.8
      )
    ],
    selfModelOverview: "구조 설계 자체보다 설계 결과를 실행 체계에 연결하는 시점에서 실제 진전과 마찰이 함께 드러난다.",
    analysisStatus: CompassAnalysisStatus(
      schemaVersion: 1,
      promptVersions: .initial,
      activeModelConfiguration: .initial,
      lastFullAnalysisAt: .now.addingTimeInterval(-86400),
      lastIncrementalUpdateAt: .now.addingTimeInterval(-3600),
      usageLedger: CompassUsageLedger(
        bootstrap: CompassTokenUsageTotals(requestCount: 5, promptTokenCount: 4200, candidatesTokenCount: 1800, thoughtsTokenCount: 900, totalTokenCount: 6900),
        delta: CompassTokenUsageTotals(requestCount: 2, promptTokenCount: 1100, candidatesTokenCount: 420, thoughtsTokenCount: 180, totalTokenCount: 1700),
        recommendation: CompassTokenUsageTotals(requestCount: 4, promptTokenCount: 900, candidatesTokenCount: 520, thoughtsTokenCount: 0, totalTokenCount: 1420),
        updatedAt: .now
      ),
      rebuildPolicySummary: "전체 재분석은 자동으로 반복하지 않고, 저널 변경은 증분 갱신으로 처리한다.",
      allowedRebuildReasons: CompassFullRebuildReason.allowedUserFacingReasons,
      lastBlockedRebuildReason: "저널 변경은 증분 갱신으로 처리해야 한다.",
      lastBlockedRebuildAt: .now.addingTimeInterval(-1800),
      seedManifest: nil,
      hasSeedReview: false
    )
  )
}
