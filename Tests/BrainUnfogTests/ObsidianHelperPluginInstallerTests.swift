import XCTest
@testable import BrainUnfog

final class ObsidianHelperPluginInstallerTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testInstallIsDisabledAndDoesNotCreatePluginFolder() throws {
    let sourceURL = try makePluginSource(version: "0.1.0", script: "")
    let vaultURL = try makeVault(withObsidianDirectory: true)
    let pluginsRootURL = vaultURL
      .appendingPathComponent(".obsidian", isDirectory: true)
      .appendingPathComponent("plugins", isDirectory: true)

    XCTAssertFalse(ObsidianHelperPluginAvailability.isEnabled)
    XCTAssertThrowsError(
      try ObsidianHelperPluginInstaller(
        sourceURL: sourceURL,
        vaultRootURL: vaultURL
      ).install()
    ) { error in
      XCTAssertEqual(error as? ObsidianHelperPluginInstaller.InstallError, .disabled)
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: pluginsRootURL.path))
  }

  func testInstallBundledIsDisabledAndLeavesExistingPluginFolderUntouched() throws {
    let vaultURL = try makeVault(withObsidianDirectory: true)
    let targetURL = vaultURL
      .appendingPathComponent(".obsidian", isDirectory: true)
      .appendingPathComponent("plugins", isDirectory: true)
      .appendingPathComponent(ObsidianHelperPluginInstaller.pluginIdentifier, isDirectory: true)
    try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
    let manualURL = targetURL.appendingPathComponent("manual.txt", isDirectory: false)
    try "manual content".write(to: manualURL, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(
      try ObsidianHelperPluginInstaller.installBundled(toVaultRootURL: vaultURL)
    ) { error in
      XCTAssertEqual(error as? ObsidianHelperPluginInstaller.InstallError, .disabled)
    }

    XCTAssertEqual(try String(contentsOf: manualURL, encoding: .utf8), "manual content")
  }

  private func makePluginSource(version: String, script: String) throws -> URL {
    let root = try makeTemporaryDirectory(named: "ObsidianHelperPluginSource")
    try """
    {
      "id": "\(ObsidianHelperPluginInstaller.pluginIdentifier)",
      "name": "Brain Unfog Helper",
      "version": "\(version)",
      "minAppVersion": "1.5.0",
      "description": "Test helper",
      "author": "Brain Unfog",
      "isDesktopOnly": true
    }
    """.write(to: root.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    try script.write(
      to: root.appendingPathComponent("main.js", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try ".brain-unfog-test {}".write(
      to: root.appendingPathComponent("styles.css", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try "owned".write(
      to: root.appendingPathComponent(
        ObsidianHelperPluginInstaller.ownershipMarkerFilename,
        isDirectory: false
      ),
      atomically: true,
      encoding: .utf8
    )
    return root
  }

  private func makeVault(withObsidianDirectory: Bool) throws -> URL {
    let root = try makeTemporaryDirectory(named: "ObsidianHelperPluginVault")
    if withObsidianDirectory {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(".obsidian", isDirectory: true),
        withIntermediateDirectories: true
      )
    }
    return root
  }

  private func makeTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryRoots.append(url)
    return url
  }
}
