import Foundation

enum GeminiCompassInvocationOutcome: Sendable {
  case success(String, GeminiGenerateContentSummaryService.SummaryUsage?)
  case cancelled
  case failed
}

protocol GeminiCompassModelInvoking: Sendable {
  func generate(
    prompt: String,
    model: String,
    temperature: Double,
    maxOutputTokens: Int
  ) async -> GeminiCompassInvocationOutcome
}

extension GeminiGenerateContentSummaryService: GeminiCompassModelInvoking {
  func generate(
    prompt: String,
    model: String,
    temperature: Double,
    maxOutputTokens: Int
  ) async -> GeminiCompassInvocationOutcome {
    switch await summarize(
      prompt: prompt,
      model: model,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens
    ) {
    case .success(let text, let usage):
      return .success(text, usage)
    case .cancelled:
      return .cancelled
    case .failed:
      return .failed
    }
  }
}

enum CompassGenerationProfile: String, CaseIterable, Hashable, Sendable {
  case bootstrapSelfModel
  case journalDigest
  case periodDigest
  case deltaPatch
  case recommendation
  case custom

  var defaultRole: CompassModelRole {
    switch self {
    case .bootstrapSelfModel, .recommendation:
      return .primary
    case .journalDigest, .periodDigest, .deltaPatch, .custom:
      return .supporting
    }
  }

  var defaultTemperature: Double {
    switch self {
    case .bootstrapSelfModel:
      return 0.35
    case .journalDigest, .periodDigest:
      return 0.25
    case .deltaPatch:
      return 0.3
    case .recommendation:
      return 0.4
    case .custom:
      return 0.3
    }
  }

  var defaultMaxOutputTokens: Int {
    switch self {
    case .bootstrapSelfModel:
      return 3200
    case .journalDigest:
      return 1200
    case .periodDigest:
      return 1800
    case .deltaPatch:
      return 1600
    case .recommendation:
      return 2200
    case .custom:
      return 1800
    }
  }
}

struct CompassGenerationRequest: Sendable {
  var prompt: String
  var profile: CompassGenerationProfile
  var roleOverride: CompassModelRole?
  var temperatureOverride: Double?
  var maxOutputTokensOverride: Int?

  init(
    prompt: String,
    profile: CompassGenerationProfile,
    roleOverride: CompassModelRole? = nil,
    temperatureOverride: Double? = nil,
    maxOutputTokensOverride: Int? = nil
  ) {
    self.prompt = prompt
    self.profile = profile
    self.roleOverride = roleOverride
    self.temperatureOverride = temperatureOverride
    self.maxOutputTokensOverride = maxOutputTokensOverride
  }
}

struct CompassGenerationResult: Hashable, Sendable {
  var text: String
  var modelName: String
  var role: CompassModelRole
  var profile: CompassGenerationProfile
  var generatedAt: Date
  var usage: GeminiGenerateContentSummaryService.SummaryUsage?
}

actor GeminiCompassService {
  static let shared = GeminiCompassService()

  private let configurationStore: CompassModelConfigurationStore
  private let invoker: any GeminiCompassModelInvoking

  init(
    configurationStore: CompassModelConfigurationStore = .shared,
    invoker: any GeminiCompassModelInvoking = GeminiGenerateContentSummaryService.shared
  ) {
    self.configurationStore = configurationStore
    self.invoker = invoker
  }

  func loadModelConfiguration() async -> CompassModelConfiguration {
    await configurationStore.loadConfiguration()
  }

  func saveModelConfiguration(_ configuration: CompassModelConfiguration) async {
    await configurationStore.saveConfiguration(configuration)
  }

  @discardableResult
  func saveModel(_ rawValue: String?, for role: CompassModelRole) async -> CompassModelConfiguration {
    await configurationStore.saveModel(rawValue, for: role)
  }

  func bootstrapSelfModel(prompt: String) async -> CompassGenerationResult? {
    await generate(
      CompassGenerationRequest(
        prompt: prompt,
        profile: .bootstrapSelfModel
      )
    )
  }

  func generateJournalDigest(prompt: String) async -> CompassGenerationResult? {
    await generate(
      CompassGenerationRequest(
        prompt: prompt,
        profile: .journalDigest
      )
    )
  }

  func generatePeriodDigest(prompt: String) async -> CompassGenerationResult? {
    await generate(
      CompassGenerationRequest(
        prompt: prompt,
        profile: .periodDigest
      )
    )
  }

  func generateDeltaPatch(prompt: String) async -> CompassGenerationResult? {
    await generate(
      CompassGenerationRequest(
        prompt: prompt,
        profile: .deltaPatch
      )
    )
  }

  func generateRecommendations(prompt: String) async -> CompassGenerationResult? {
    await generate(
      CompassGenerationRequest(
        prompt: prompt,
        profile: .recommendation
      )
    )
  }

  func generate(_ request: CompassGenerationRequest) async -> CompassGenerationResult? {
    let configuration = await configurationStore.loadConfiguration()
    let role = request.roleOverride ?? request.profile.defaultRole
    let modelName = resolvedModelName(for: role, configuration: configuration)
    let temperature = request.temperatureOverride ?? request.profile.defaultTemperature
    let maxOutputTokens = request.maxOutputTokensOverride ?? request.profile.defaultMaxOutputTokens

    switch await invoker.generate(
      prompt: request.prompt,
      model: modelName,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens
    ) {
    case .success(let text, let usage):
      let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { return nil }
      return CompassGenerationResult(
        text: normalized,
        modelName: modelName,
        role: role,
        profile: request.profile,
        generatedAt: .now,
        usage: usage
      )
    case .cancelled, .failed:
      return nil
    }
  }

  private func resolvedModelName(
    for role: CompassModelRole,
    configuration: CompassModelConfiguration
  ) -> String {
    switch role {
    case .primary:
      return configuration.primaryModel
    case .supporting:
      return configuration.supportingModel
    case .fallback:
      return configuration.fallbackModel ?? configuration.supportingModel
    }
  }
}
