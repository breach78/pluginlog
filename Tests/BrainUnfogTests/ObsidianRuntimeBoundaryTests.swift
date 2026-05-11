import XCTest

final class ObsidianRuntimeBoundaryTests: XCTestCase {
  func testAppAndFeatureRuntimeEntrypointsDoNotCallLegacyObsidianProjectStorage() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let scannedRoots = [
      repositoryRoot.appendingPathComponent("import/BUF/App", isDirectory: true),
      repositoryRoot.appendingPathComponent("import/BUF/Features", isDirectory: true),
    ]
    let forbiddenRuntimeReferences = [
      "ObsidianProjectMarkdownStore(",
      "ObsidianReminderBootstrapSync",
      "ObsidianReminderImportSync",
      "ObsidianReminderProvisioningSync",
      "ObsidianReminderDeletionSync",
    ]

    let offenders = try scannedRoots.flatMap { root in
      try swiftFiles(under: root).flatMap { fileURL in
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return forbiddenRuntimeReferences.compactMap { reference in
          contents.contains(reference)
            ? "\(relativePath(fileURL, from: repositoryRoot)): \(reference)"
            : nil
        }
      }
    }

    XCTAssertTrue(
      offenders.isEmpty,
      "Runtime App/Features code must not call legacy raw/projects storage:\n\(offenders.joined(separator: "\n"))"
    )
  }

  func testProjectCommandRuntimeDoesNotExposeLegacyMarkdownStoreTypes() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let scannedFiles = [
      repositoryRoot.appendingPathComponent(
        "import/BUF/Services/AppOwnedRetainedProjectCommandService.swift",
        isDirectory: false
      ),
      repositoryRoot.appendingPathComponent(
        "import/BUF/Services/ObsidianRetainedProjectCommandService.swift",
        isDirectory: false
      ),
    ]

    let offenders = try scannedFiles.compactMap { fileURL -> String? in
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      return contents.contains("ObsidianProjectMarkdownStore")
        ? relativePath(fileURL, from: repositoryRoot)
        : nil
    }

    XCTAssertTrue(
      offenders.isEmpty,
      "Project command runtime must return app-owned project snapshots, not markdown store snapshots:\n\(offenders.joined(separator: "\n"))"
    )
  }

  func testTaskCommandRuntimeDoesNotExposeLegacyMarkdownStoreTypes() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fileURL = repositoryRoot.appendingPathComponent(
      "import/BUF/Services/ObsidianRetainedTaskCommandService.swift",
      isDirectory: false
    )

    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let forbiddenReferences = [
      "ObsidianProjectMarkdownStore",
      "ObsidianReminderImportFormatting",
      "raw/projects",
    ]
    let offenders = forbiddenReferences.filter { contents.contains($0) }

    XCTAssertTrue(
      offenders.isEmpty,
      "Task command runtime must route through app-owned storage only, not legacy markdown storage:\n\(offenders.joined(separator: "\n"))"
    )
  }

  func testAppStateDoesNotRetainLegacyProjectDirectoryWatcher() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let scannedFiles = [
      repositoryRoot.appendingPathComponent("import/BUF/App/AppState.swift", isDirectory: false),
      repositoryRoot.appendingPathComponent("import/BUF/App/AppStateSourceIO.swift", isDirectory: false),
      repositoryRoot.appendingPathComponent("import/BUF/App/AppStateLaunchAndSetup.swift", isDirectory: false),
    ]

    let offenders = try scannedFiles.flatMap { fileURL in
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      return ["ObsidianProjectDirectoryWatcher", "obsidianProjectDirectoryWatcher"].compactMap { reference in
        contents.contains(reference)
          ? "\(relativePath(fileURL, from: repositoryRoot)): \(reference)"
          : nil
      }
    }

    XCTAssertTrue(
      offenders.isEmpty,
      "AppState runtime must not retain the legacy raw/projects directory watcher:\n\(offenders.joined(separator: "\n"))"
    )
  }

  func testReminderSnapshotPersistenceDoesNotRunLegacyObsidianProjectMigrations() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fileURL = repositoryRoot.appendingPathComponent(
      "import/BUF/App/AppStateSourceIO.swift",
      isDirectory: false
    )

    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let forbiddenReferences = [
      "LegacyObsidianProjectTaskDurationMigration",
      "LegacyObsidianProjectStageMigration",
      "runLegacyObsidianProjectMigrationsIfNeeded",
    ]
    let offenders = forbiddenReferences.filter { contents.contains($0) }

    XCTAssertTrue(
      offenders.isEmpty,
      "Reminder refresh/import persistence must not call legacy raw/projects migrations:\n\(offenders.joined(separator: "\n"))"
    )
  }

  func testArchitectureDecisionDocumentsAppOwnedRuntimeBoundary() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fileURL = repositoryRoot.appendingPathComponent(
      "docs/decisions/ADR-005-obsidian-vault-retained-architecture.md",
      isDirectory: false
    )

    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertTrue(contents.contains("Project/task runtime state is stored in app-owned SQLite"))
    XCTAssertTrue(contents.contains("The vault must not be used at runtime for:"))
    XCTAssertFalse(contents.contains("Use Obsidian vault as retained project store"))
    XCTAssertFalse(contents.contains("The native app reads\n`raw/projects/*.md` directly"))
    XCTAssertFalse(contents.contains("Watch and scan `raw/projects/`"))
  }

  private func swiftFiles(under root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return []
    }
    var files: [URL] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
      let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else { continue }
      files.append(fileURL)
    }
    return files
  }

  private func relativePath(_ fileURL: URL, from root: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let filePath = fileURL.standardizedFileURL.path
    guard filePath.hasPrefix(rootPath + "/") else {
      return filePath
    }
    return String(filePath.dropFirst(rootPath.count + 1))
  }
}
