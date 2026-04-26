import Foundation

struct ObsidianHelperPluginInstallResult: Equatable {
  let pluginIdentifier: String
  let targetURL: URL
  let version: String?
}

struct ObsidianHelperPluginInstaller {
  enum InstallError: LocalizedError, Equatable {
    case bundledSourceMissing
    case obsidianConfigDirectoryMissing(URL)
    case manifestMissing(URL)
    case mainScriptMissing(URL)
    case stylesheetMissing(URL)
    case unownedExistingPluginDirectory(URL)

    var errorDescription: String? {
      switch self {
      case .bundledSourceMissing:
        "번들에 Obsidian helper plugin 리소스가 없습니다."
      case .obsidianConfigDirectoryMissing(let url):
        "Obsidian config directory is missing: \(url.path)"
      case .manifestMissing(let url):
        "Obsidian helper manifest.json을 찾지 못했습니다: \(url.path)"
      case .mainScriptMissing(let url):
        "Obsidian helper main.js를 찾지 못했습니다: \(url.path)"
      case .stylesheetMissing(let url):
        "Obsidian helper styles.css를 찾지 못했습니다: \(url.path)"
      case .unownedExistingPluginDirectory(let url):
        "Existing Obsidian helper plugin directory is not owned by Brain Unfog: \(url.path)"
      }
    }
  }

  static let pluginIdentifier = "brain-unfog-helper"
  static let bundledResourceName = "ObsidianHelperPlugin"
  static let resourceBundleName = "pluginlog-harness_BrainUnfogHarness.bundle"
  static let ownershipMarkerFilename = ".brain-unfog-helper-owned"

  let sourceURL: URL
  let vaultRootURL: URL
  let fileManager: FileManager

  init(
    sourceURL: URL,
    vaultRootURL: URL,
    fileManager: FileManager = .default
  ) {
    self.sourceURL = sourceURL
    self.vaultRootURL = vaultRootURL.standardizedFileURL
    self.fileManager = fileManager
  }

  static func bundledSourceURL() throws -> URL {
    if let sourceURL = bundledSourceURL(inResourceDirectory: Bundle.main.resourceURL) {
      return sourceURL
    }
    if let sourceURL = Bundle.module.url(forResource: bundledResourceName, withExtension: nil) {
      return sourceURL
    }
    throw InstallError.bundledSourceMissing
  }

  static func bundledSourceURL(inResourceDirectory resourceDirectory: URL?) -> URL? {
    guard let resourceDirectory else { return nil }
    let sourceURL = resourceDirectory
      .appendingPathComponent(resourceBundleName, isDirectory: true)
      .appendingPathComponent(bundledResourceName, isDirectory: true)
    return FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil
  }

  static func installBundled(
    toVaultRootURL vaultRootURL: URL,
    fileManager: FileManager = .default
  ) throws -> ObsidianHelperPluginInstallResult {
    try ObsidianHelperPluginInstaller(
      sourceURL: bundledSourceURL(),
      vaultRootURL: vaultRootURL,
      fileManager: fileManager
    ).install()
  }

  func install() throws -> ObsidianHelperPluginInstallResult {
    try validateSource()

    let layout = ObsidianVaultLayout(vaultRootURL: vaultRootURL, fileManager: fileManager)
    guard layout.candidateState() == .existingVault else {
      throw InstallError.obsidianConfigDirectoryMissing(layout.obsidianConfigURL)
    }

    let pluginsRootURL = layout.obsidianConfigURL.appendingPathComponent("plugins", isDirectory: true)
    try fileManager.createDirectory(
      at: pluginsRootURL,
      withIntermediateDirectories: true
    )

    let targetURL = pluginsRootURL.appendingPathComponent(Self.pluginIdentifier, isDirectory: true)
    let temporaryURL = pluginsRootURL.appendingPathComponent(
      ".\(Self.pluginIdentifier)-installing-\(UUID().uuidString)",
      isDirectory: true
    )
    if fileManager.fileExists(atPath: temporaryURL.path) {
      try fileManager.removeItem(at: temporaryURL)
    }

    try fileManager.copyItem(at: sourceURL, to: temporaryURL)
    if fileManager.fileExists(atPath: targetURL.path) {
      guard fileManager.fileExists(
        atPath: targetURL
          .appendingPathComponent(Self.ownershipMarkerFilename, isDirectory: false)
          .path
      ) else {
        try? fileManager.removeItem(at: temporaryURL)
        throw InstallError.unownedExistingPluginDirectory(targetURL)
      }
      try fileManager.removeItem(at: targetURL)
    }
    try fileManager.moveItem(at: temporaryURL, to: targetURL)

    return ObsidianHelperPluginInstallResult(
      pluginIdentifier: Self.pluginIdentifier,
      targetURL: targetURL,
      version: try manifestVersion(at: targetURL)
    )
  }

  private func validateSource() throws {
    let manifestURL = sourceURL.appendingPathComponent("manifest.json", isDirectory: false)
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      throw InstallError.manifestMissing(manifestURL)
    }
    let mainScriptURL = sourceURL.appendingPathComponent("main.js", isDirectory: false)
    guard fileManager.fileExists(atPath: mainScriptURL.path) else {
      throw InstallError.mainScriptMissing(mainScriptURL)
    }
    let stylesheetURL = sourceURL.appendingPathComponent("styles.css", isDirectory: false)
    guard fileManager.fileExists(atPath: stylesheetURL.path) else {
      throw InstallError.stylesheetMissing(stylesheetURL)
    }
    let markerURL = sourceURL.appendingPathComponent(Self.ownershipMarkerFilename, isDirectory: false)
    guard fileManager.fileExists(atPath: markerURL.path) else {
      throw InstallError.unownedExistingPluginDirectory(sourceURL)
    }
  }

  private func manifestVersion(at pluginURL: URL) throws -> String? {
    let manifestURL = pluginURL.appendingPathComponent("manifest.json", isDirectory: false)
    let data = try Data(contentsOf: manifestURL)
    let object = try JSONSerialization.jsonObject(with: data)
    return (object as? [String: Any])?["version"] as? String
  }
}
