import Foundation

struct ObsidianVaultLayout {
  enum LayoutError: LocalizedError, Equatable {
    case missingObsidianConfigDirectory(URL)

    var errorDescription: String? {
      switch self {
      case .missingObsidianConfigDirectory(let url):
        "Obsidian vault config directory is missing: \(url.path)"
      }
    }
  }

  enum CandidateState: Equatable {
    case existingVault
    case candidateMissingObsidianDirectory
  }

  let vaultRootURL: URL
  let fileManager: FileManager

  init(vaultRootURL: URL, fileManager: FileManager = .default) {
    self.vaultRootURL = vaultRootURL.standardizedFileURL
    self.fileManager = fileManager
  }

  var sidecarRootURL: URL {
    vaultRootURL.appendingPathComponent(".buf", isDirectory: true)
  }

  var rawProjectsRootURL: URL {
    vaultRootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
  }

  var rawJournalsRootURL: URL {
    vaultRootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("journals", isDirectory: true)
  }

  var rawArchiveRootURL: URL {
    vaultRootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("archive", isDirectory: true)
  }

  var obsidianConfigURL: URL {
    vaultRootURL.appendingPathComponent(".obsidian", isDirectory: true)
  }

  func candidateState() -> CandidateState {
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: obsidianConfigURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      return .existingVault
    }
    return .candidateMissingObsidianDirectory
  }

  func prepareAppDirectories() throws {
    guard candidateState() == .existingVault else {
      throw LayoutError.missingObsidianConfigDirectory(obsidianConfigURL)
    }

    try fileManager.createDirectory(
      at: sidecarRootURL,
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: rawProjectsRootURL,
      withIntermediateDirectories: true
    )
  }
}
