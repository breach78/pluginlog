import Foundation

struct CompassSeedPackage: Codable, Hashable, Sendable {
  struct EvidenceRecord: Codable, Hashable, Sendable {
    var sourceKind: CompassEvidenceSourceKind
    var sourceID: String
    var dayKey: String?
    var excerpt: String?
    var recordedAt: Date?
    var weight: Double?

    func makeEvidencePointer() -> CompassEvidencePointer {
      CompassEvidencePointer(
        sourceKind: sourceKind,
        sourceID: sourceID,
        dayKey: dayKey,
        excerpt: excerpt,
        recordedAt: recordedAt,
        weight: weight
      )
    }
  }

  struct HypothesisRecord: Codable, Hashable, Sendable {
    var axis: CompassInsightAxis
    var title: String
    var statement: String
    var confidence: CompassConfidence
    var evidence: [EvidenceRecord]
    var lastUpdatedAt: Date?

    func makeHypothesis(
      layer: CompassHypothesisLayer,
      fallbackUpdatedAt: Date
    ) -> CompassHypothesis {
      CompassHypothesis(
        layer: layer,
        axis: axis,
        title: title,
        statement: statement,
        confidence: confidence,
        evidence: evidence.map { $0.makeEvidencePointer() },
        lastUpdatedAt: lastUpdatedAt ?? fallbackUpdatedAt
      )
    }
  }

  struct SteeringRuleRecord: Codable, Hashable, Sendable {
    var title: String
    var instruction: String
    var rationale: String
    var confidence: CompassConfidence
    var evidence: [EvidenceRecord]
    var lastUpdatedAt: Date?

    func makeRule(fallbackUpdatedAt: Date) -> CompassSteeringRule {
      CompassSteeringRule(
        title: title,
        instruction: instruction,
        rationale: rationale,
        confidence: confidence,
        evidence: evidence.map { $0.makeEvidencePointer() },
        lastUpdatedAt: lastUpdatedAt ?? fallbackUpdatedAt
      )
    }
  }

  struct MotivationSignalRecord: Codable, Hashable, Sendable {
    var axis: CompassInsightAxis
    var title: String
    var statement: String
    var confidence: CompassConfidence
    var evidence: [EvidenceRecord]
    var lastUpdatedAt: Date?

    func makeSignal(fallbackUpdatedAt: Date) -> CompassMotivationSignal {
      CompassMotivationSignal(
        axis: axis,
        title: title,
        statement: statement,
        confidence: confidence,
        evidence: evidence.map { $0.makeEvidencePointer() },
        lastUpdatedAt: lastUpdatedAt ?? fallbackUpdatedAt
      )
    }
  }

  struct SchedulingPreferenceRecord: Codable, Hashable, Sendable {
    var title: String
    var instruction: String
    var preferredWindow: CompassSchedulingWindow
    var maxFocusBlockMinutes: Int?
    var confidence: CompassConfidence
    var evidence: [EvidenceRecord]
    var lastUpdatedAt: Date?

    func makePreference(fallbackUpdatedAt: Date) -> CompassSchedulingPreference {
      CompassSchedulingPreference(
        title: title,
        instruction: instruction,
        preferredWindow: preferredWindow,
        maxFocusBlockMinutes: maxFocusBlockMinutes,
        confidence: confidence,
        evidence: evidence.map { $0.makeEvidencePointer() },
        lastUpdatedAt: lastUpdatedAt ?? fallbackUpdatedAt
      )
    }
  }

  struct RecommendationGuardrailRecord: Codable, Hashable, Sendable {
    var title: String
    var rule: String
    var severity: CompassGuardrailSeverity
    var confidence: CompassConfidence
    var evidence: [EvidenceRecord]
    var lastUpdatedAt: Date?

    func makeGuardrail(fallbackUpdatedAt: Date) -> CompassRecommendationGuardrail {
      CompassRecommendationGuardrail(
        title: title,
        rule: rule,
        severity: severity,
        confidence: confidence,
        evidence: evidence.map { $0.makeEvidencePointer() },
        lastUpdatedAt: lastUpdatedAt ?? fallbackUpdatedAt
      )
    }
  }

  var schemaVersion: Int
  var seedVersion: Int
  var origin: CompassSeedOrigin
  var createdAt: Date
  var approvedAt: Date
  var overview: String
  var corePersona: [HypothesisRecord]
  var currentSeason: [HypothesisRecord]
  var operationalTendencies: [HypothesisRecord]
  var blindSpots: [HypothesisRecord]
  var steeringRules: [SteeringRuleRecord]
  var motivationMap: [MotivationSignalRecord]
  var schedulingPreferences: [SchedulingPreferenceRecord]
  var recommendationGuardrails: [RecommendationGuardrailRecord]
  var baselineGenerationPolicy: CompassBaselineGenerationPolicy
  var notes: String?
  var reviewMarkdownPath: String?

  func makeApprovedSeed(reviewMarkdown: String?) -> CompassApprovedSeed {
    CompassApprovedSeed(
      seedVersion: seedVersion,
      origin: origin,
      createdAt: createdAt,
      approvedAt: approvedAt,
      overview: overview,
      corePersona: corePersona.map {
        $0.makeHypothesis(layer: .corePersona, fallbackUpdatedAt: approvedAt)
      },
      currentSeason: currentSeason.map {
        $0.makeHypothesis(layer: .currentSeason, fallbackUpdatedAt: approvedAt)
      },
      operationalTendencies: operationalTendencies.map {
        $0.makeHypothesis(layer: .operationalTendencies, fallbackUpdatedAt: approvedAt)
      },
      blindSpots: blindSpots.map {
        $0.makeHypothesis(layer: .blindSpots, fallbackUpdatedAt: approvedAt)
      },
      steeringRules: steeringRules.map { $0.makeRule(fallbackUpdatedAt: approvedAt) },
      motivationMap: motivationMap.map { $0.makeSignal(fallbackUpdatedAt: approvedAt) },
      schedulingPreferences: schedulingPreferences.map {
        $0.makePreference(fallbackUpdatedAt: approvedAt)
      },
      recommendationGuardrails: recommendationGuardrails.map {
        $0.makeGuardrail(fallbackUpdatedAt: approvedAt)
      },
      baselineGenerationPolicy: baselineGenerationPolicy,
      notes: notes,
      reviewMarkdown: reviewMarkdown
    )
  }
}

struct CompassSeedPackageLoader {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func loadApprovedSeed(from url: URL) throws -> CompassApprovedSeed {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try Data(contentsOf: url)
    let package = try decoder.decode(CompassSeedPackage.self, from: data)
    let reviewMarkdown = try loadReviewMarkdown(for: package, packageURL: url)
    return package.makeApprovedSeed(reviewMarkdown: reviewMarkdown)
  }

  private func loadReviewMarkdown(
    for package: CompassSeedPackage,
    packageURL: URL
  ) throws -> String? {
    guard let reviewMarkdownPath = package.reviewMarkdownPath?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ), !reviewMarkdownPath.isEmpty else {
      return nil
    }

    let reviewURL = packageURL.deletingLastPathComponent()
      .appendingPathComponent(reviewMarkdownPath)
    guard fileManager.fileExists(atPath: reviewURL.path) else {
      throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: reviewURL.path])
    }
    return try String(contentsOf: reviewURL, encoding: .utf8)
  }
}
