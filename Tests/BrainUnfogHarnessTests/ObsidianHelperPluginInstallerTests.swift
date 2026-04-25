import XCTest
@testable import BrainUnfogHarness

final class ObsidianHelperPluginInstallerTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testBundledPluginResourceContainsRequiredFilesAndManifest() throws {
    let sourceURL = try ObsidianHelperPluginInstaller.bundledSourceURL()

    for filename in [
      "manifest.json",
      "main.js",
      "styles.css",
      ObsidianHelperPluginInstaller.ownershipMarkerFilename,
    ] {
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: sourceURL.appendingPathComponent(filename, isDirectory: false).path
        ),
        "\(filename) should be bundled with the helper plugin"
      )
    }

    let manifest = try manifestObject(
      at: sourceURL.appendingPathComponent("manifest.json", isDirectory: false)
    )
    XCTAssertEqual(manifest["id"] as? String, ObsidianHelperPluginInstaller.pluginIdentifier)
    XCTAssertEqual(manifest["name"] as? String, "Brain Unfog Helper")
    XCTAssertEqual(manifest["version"] as? String, "0.1.0")
    XCTAssertNotNil(manifest["minAppVersion"] as? String)
    XCTAssertNotNil(manifest["description"] as? String)
    XCTAssertNotNil(manifest["author"] as? String)
    XCTAssertEqual(manifest["isDesktopOnly"] as? Bool, true)
    XCTAssertFalse(ObsidianHelperPluginInstaller.pluginIdentifier.contains("obsidian"))
  }

  func testInstallCopiesPluginIntoExistingObsidianPluginsDirectory() throws {
    let sourceURL = try makePluginSource(version: "0.1.0", script: "window.__buf = 'fresh';")
    let vaultURL = try makeVault(withObsidianDirectory: true)

    let result = try ObsidianHelperPluginInstaller(
      sourceURL: sourceURL,
      vaultRootURL: vaultURL
    ).install()

    XCTAssertEqual(result.pluginIdentifier, ObsidianHelperPluginInstaller.pluginIdentifier)
    XCTAssertEqual(result.version, "0.1.0")
    XCTAssertEqual(result.targetURL.lastPathComponent, ObsidianHelperPluginInstaller.pluginIdentifier)
    XCTAssertTrue(
      try String(
        contentsOf: result.targetURL.appendingPathComponent("main.js", isDirectory: false),
        encoding: .utf8
      ).contains("fresh")
    )
  }

  func testInstallReplacesStalePluginFolder() throws {
    let sourceURL = try makePluginSource(version: "0.2.0", script: "window.__buf = 'replacement';")
    let vaultURL = try makeVault(withObsidianDirectory: true)
    let targetURL = vaultURL
      .appendingPathComponent(".obsidian", isDirectory: true)
      .appendingPathComponent("plugins", isDirectory: true)
      .appendingPathComponent(ObsidianHelperPluginInstaller.pluginIdentifier, isDirectory: true)
    try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
    try "stale".write(
      to: targetURL.appendingPathComponent("legacy.txt", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try "owned".write(
      to: targetURL.appendingPathComponent(
        ObsidianHelperPluginInstaller.ownershipMarkerFilename,
        isDirectory: false
      ),
      atomically: true,
      encoding: .utf8
    )

    let result = try ObsidianHelperPluginInstaller(
      sourceURL: sourceURL,
      vaultRootURL: vaultURL
    ).install()

    XCTAssertEqual(result.version, "0.2.0")
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: result.targetURL.appendingPathComponent("legacy.txt", isDirectory: false).path
      )
    )
    XCTAssertTrue(
      try String(
        contentsOf: result.targetURL.appendingPathComponent("main.js", isDirectory: false),
        encoding: .utf8
      ).contains("replacement")
    )
  }

  func testInstallRefusesToReplaceUnownedExistingPluginFolder() throws {
    let sourceURL = try makePluginSource(version: "0.2.0", script: "window.__buf = 'replacement';")
    let vaultURL = try makeVault(withObsidianDirectory: true)
    let targetURL = vaultURL
      .appendingPathComponent(".obsidian", isDirectory: true)
      .appendingPathComponent("plugins", isDirectory: true)
      .appendingPathComponent(ObsidianHelperPluginInstaller.pluginIdentifier, isDirectory: true)
    try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
    let unownedFileURL = targetURL.appendingPathComponent("manual.txt", isDirectory: false)
    try "manual content".write(to: unownedFileURL, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(
      try ObsidianHelperPluginInstaller(
        sourceURL: sourceURL,
        vaultRootURL: vaultURL
      ).install()
    ) { error in
      XCTAssertEqual(
        error as? ObsidianHelperPluginInstaller.InstallError,
        .unownedExistingPluginDirectory(targetURL)
      )
    }
    XCTAssertEqual(try String(contentsOf: unownedFileURL, encoding: .utf8), "manual content")
  }

  func testInstallFailsWithoutObsidianDirectoryAndDoesNotCreateIt() throws {
    let sourceURL = try makePluginSource(version: "0.1.0", script: "")
    let vaultURL = try makeVault(withObsidianDirectory: false)
    let obsidianURL = vaultURL.appendingPathComponent(".obsidian", isDirectory: true)

    XCTAssertThrowsError(
      try ObsidianHelperPluginInstaller(
        sourceURL: sourceURL,
        vaultRootURL: vaultURL
      ).install()
    ) { error in
      XCTAssertEqual(
        error as? ObsidianHelperPluginInstaller.InstallError,
        .obsidianConfigDirectoryMissing(obsidianURL)
      )
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: obsidianURL.path))
  }

  func testInstallDoesNotCreateOrModifyCommunityPluginsConfig() throws {
    let sourceURL = try makePluginSource(version: "0.1.0", script: "")
    let vaultURL = try makeVault(withObsidianDirectory: true)
    let configURL = vaultURL
      .appendingPathComponent(".obsidian", isDirectory: true)
      .appendingPathComponent("community-plugins.json", isDirectory: false)

    _ = try ObsidianHelperPluginInstaller(
      sourceURL: sourceURL,
      vaultRootURL: vaultURL
    ).install()

    XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
  }

  func testInstallDoesNotModifyExistingObsidianSettingsFiles() throws {
    let sourceURL = try makePluginSource(version: "0.1.0", script: "")
    let vaultURL = try makeVault(withObsidianDirectory: true)
    let obsidianURL = vaultURL.appendingPathComponent(".obsidian", isDirectory: true)
    let protectedFiles = [
      "app.json": "{\"legacy\":true}",
      "appearance.json": "{\"theme\":\"system\"}",
      "hotkeys.json": "{\"x\":[]}",
      "community-plugins.json": "[\"manual-plugin\"]",
    ]
    for (name, content) in protectedFiles {
      try content.write(
        to: obsidianURL.appendingPathComponent(name, isDirectory: false),
        atomically: true,
        encoding: .utf8
      )
    }

    _ = try ObsidianHelperPluginInstaller(
      sourceURL: sourceURL,
      vaultRootURL: vaultURL
    ).install()

    for (name, content) in protectedFiles {
      let url = obsidianURL.appendingPathComponent(name, isDirectory: false)
      XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), content)
    }
  }

  func testBundledHelperDoesNotContainSyncBrainOrWriteOperations() throws {
    let sourceURL = try ObsidianHelperPluginInstaller.bundledSourceURL()
    let script = try String(
      contentsOf: sourceURL.appendingPathComponent("main.js", isDirectory: false),
      encoding: .utf8
    )
    let forbiddenSnippets = [
      "vault.modify",
      "vault.process",
      "vault.create",
      "vault.delete",
      "requestUrl",
      "fetch(",
      "XMLHttpRequest",
      "WebSocket",
      "EventKit",
      "EKEvent",
      "Reminders",
      "Calendar",
    ]
    for snippet in forbiddenSnippets {
      XCTAssertFalse(script.contains(snippet), "helper main.js must not contain \(snippet)")
    }
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

  private func manifestObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
  }
}
