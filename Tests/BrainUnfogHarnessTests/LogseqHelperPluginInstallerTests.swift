import XCTest
@testable import BrainUnfogHarness

final class LogseqHelperPluginInstallerTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDown() async throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testBundledPluginResourceContainsRequiredFiles() throws {
    let sourceURL = try LogseqHelperPluginInstaller.bundledSourceURL()

    for filename in ["package.json", "index.html", "index.js", "styles.css", "icon.svg"] {
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: sourceURL.appendingPathComponent(filename, isDirectory: false).path
        ),
        "\(filename) should be bundled with the helper plugin"
      )
    }
  }

  func testInstallCopiesPluginIntoLogseqPluginsDirectory() throws {
    let sourceURL = try makePluginSource(version: "0.1.0", script: "console.log('fresh');")
    let pluginsRootURL = try makeTemporaryDirectory()

    let result = try LogseqHelperPluginInstaller(
      sourceURL: sourceURL,
      pluginsRootURL: pluginsRootURL
    ).install()

    XCTAssertEqual(result.pluginIdentifier, LogseqHelperPluginInstaller.pluginIdentifier)
    XCTAssertEqual(result.version, "0.1.0")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: result.targetURL.appendingPathComponent("index.js", isDirectory: false).path
      )
    )
    XCTAssertTrue(
      try String(
        contentsOf: result.targetURL.appendingPathComponent("index.js", isDirectory: false),
        encoding: .utf8
      ).contains("fresh")
    )
  }

  func testInstallReplacesStalePluginFolder() throws {
    let sourceURL = try makePluginSource(version: "0.2.0", script: "console.log('replacement');")
    let pluginsRootURL = try makeTemporaryDirectory()
    let targetURL = pluginsRootURL.appendingPathComponent(
      LogseqHelperPluginInstaller.pluginIdentifier,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
    try "stale".write(
      to: targetURL.appendingPathComponent("legacy.txt", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )

    let result = try LogseqHelperPluginInstaller(
      sourceURL: sourceURL,
      pluginsRootURL: pluginsRootURL
    ).install()

    XCTAssertEqual(result.version, "0.2.0")
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: result.targetURL.appendingPathComponent("legacy.txt", isDirectory: false).path
      )
    )
    XCTAssertTrue(
      try String(
        contentsOf: result.targetURL.appendingPathComponent("index.js", isDirectory: false),
        encoding: .utf8
      ).contains("replacement")
    )
  }

  private func makePluginSource(version: String, script: String) throws -> URL {
    let root = try makeTemporaryDirectory()
    try """
    {
      "name": "\(LogseqHelperPluginInstaller.pluginIdentifier)",
      "version": "\(version)",
      "main": "index.html",
      "logseq": {
        "id": "\(LogseqHelperPluginInstaller.pluginIdentifier)"
      }
    }
    """.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    try "<script src=\"./index.js\"></script>".write(
      to: root.appendingPathComponent("index.html"),
      atomically: true,
      encoding: .utf8
    )
    try script.write(
      to: root.appendingPathComponent("index.js"),
      atomically: true,
      encoding: .utf8
    )
    return root
  }

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("LogseqHelperPluginInstallerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }
}
