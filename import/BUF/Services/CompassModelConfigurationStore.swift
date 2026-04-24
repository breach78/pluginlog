import Foundation

actor CompassModelConfigurationStore {
  static let shared = CompassModelConfigurationStore()

  private enum Keys {
    static let primaryModel = "compass.models.primary"
    static let supportingModel = "compass.models.supporting"
    static let fallbackModel = "compass.models.fallback"
  }

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  init(suiteName: String) {
    self.userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
  }

  func loadConfiguration() -> CompassModelConfiguration {
    let primaryModel = normalizedPrimaryModel(
      userDefaults.string(forKey: Keys.primaryModel)
    )
    let supportingModel = normalizedSupportingModel(
      userDefaults.string(forKey: Keys.supportingModel)
    )
    let fallbackModel = normalizedOptionalModel(
      userDefaults.string(forKey: Keys.fallbackModel)
    )

    return CompassModelConfiguration(
      primaryModel: primaryModel,
      supportingModel: supportingModel,
      fallbackModel: fallbackModel
    )
  }

  func saveConfiguration(_ configuration: CompassModelConfiguration) {
    let normalized = normalizedConfiguration(configuration)
    userDefaults.set(normalized.primaryModel, forKey: Keys.primaryModel)
    userDefaults.set(normalized.supportingModel, forKey: Keys.supportingModel)
    if let fallbackModel = normalized.fallbackModel {
      userDefaults.set(fallbackModel, forKey: Keys.fallbackModel)
    } else {
      userDefaults.removeObject(forKey: Keys.fallbackModel)
    }
  }

  @discardableResult
  func saveModel(_ rawValue: String?, for role: CompassModelRole) -> CompassModelConfiguration {
    var configuration = loadConfiguration()

    switch role {
    case .primary:
      configuration.primaryModel = normalizedPrimaryModel(rawValue)
    case .supporting:
      configuration.supportingModel = normalizedSupportingModel(rawValue)
    case .fallback:
      configuration.fallbackModel = normalizedOptionalModel(rawValue)
    }

    saveConfiguration(configuration)
    return configuration
  }

  func reset() {
    userDefaults.removeObject(forKey: Keys.primaryModel)
    userDefaults.removeObject(forKey: Keys.supportingModel)
    userDefaults.removeObject(forKey: Keys.fallbackModel)
  }

  private func normalizedConfiguration(
    _ configuration: CompassModelConfiguration
  ) -> CompassModelConfiguration {
    CompassModelConfiguration(
      primaryModel: normalizedPrimaryModel(configuration.primaryModel),
      supportingModel: normalizedSupportingModel(configuration.supportingModel),
      fallbackModel: normalizedOptionalModel(configuration.fallbackModel)
    )
  }

  private func normalizedPrimaryModel(_ rawValue: String?) -> String {
    normalizedRequiredModel(rawValue, fallback: CompassModelConfiguration.initial.primaryModel)
  }

  private func normalizedSupportingModel(_ rawValue: String?) -> String {
    normalizedRequiredModel(rawValue, fallback: CompassModelConfiguration.initial.supportingModel)
  }

  private func normalizedRequiredModel(_ rawValue: String?, fallback: String) -> String {
    let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? fallback : trimmed
  }

  private func normalizedOptionalModel(_ rawValue: String?) -> String? {
    let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
