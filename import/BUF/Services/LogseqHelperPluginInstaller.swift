import Foundation

struct LogseqHelperPluginInstallResult: Equatable {
  let pluginIdentifier: String
  let targetURL: URL
  let version: String?
}

struct LogseqHelperPluginInstaller {
  enum InstallError: LocalizedError {
    case bundledSourceMissing
    case packageManifestMissing(URL)

    var errorDescription: String? {
      switch self {
      case .bundledSourceMissing:
        "번들에 Logseq helper plugin 리소스가 없습니다."
      case .packageManifestMissing(let url):
        "Logseq helper plugin package.json을 찾지 못했습니다: \(url.path)"
      }
    }
  }

  static let pluginIdentifier = "brain-unfog-logseq-helper"
  static let bundledResourceName = "LogseqHelperPlugin"

  let sourceURL: URL
  let pluginsRootURL: URL
  let fileManager: FileManager

  init(
    sourceURL: URL,
    pluginsRootURL: URL,
    fileManager: FileManager = .default
  ) {
    self.sourceURL = sourceURL
    self.pluginsRootURL = pluginsRootURL
    self.fileManager = fileManager
  }

  static func defaultPluginsRootURL(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL {
    homeDirectory
      .appendingPathComponent(".logseq", isDirectory: true)
      .appendingPathComponent("plugins", isDirectory: true)
  }

  static func bundledSourceURL() throws -> URL {
    guard let sourceURL = Bundle.module.url(forResource: bundledResourceName, withExtension: nil) else {
      throw InstallError.bundledSourceMissing
    }
    return sourceURL
  }

  static func installBundled(
    pluginsRootURL: URL = defaultPluginsRootURL(),
    fileManager: FileManager = .default
  ) throws -> LogseqHelperPluginInstallResult {
    try LogseqHelperPluginInstaller(
      sourceURL: bundledSourceURL(),
      pluginsRootURL: pluginsRootURL,
      fileManager: fileManager
    ).install()
  }

  func install() throws -> LogseqHelperPluginInstallResult {
    try validateSource()
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
      try fileManager.removeItem(at: targetURL)
    }
    try fileManager.moveItem(at: temporaryURL, to: targetURL)

    return LogseqHelperPluginInstallResult(
      pluginIdentifier: Self.pluginIdentifier,
      targetURL: targetURL,
      version: try manifestVersion(at: targetURL)
    )
  }

  private func validateSource() throws {
    let packageURL = sourceURL.appendingPathComponent("package.json", isDirectory: false)
    guard fileManager.fileExists(atPath: packageURL.path) else {
      throw InstallError.packageManifestMissing(packageURL)
    }
  }

  private func manifestVersion(at pluginURL: URL) throws -> String? {
    let packageURL = pluginURL.appendingPathComponent("package.json", isDirectory: false)
    let data = try Data(contentsOf: packageURL)
    let object = try JSONSerialization.jsonObject(with: data)
    return (object as? [String: Any])?["version"] as? String
  }
}
