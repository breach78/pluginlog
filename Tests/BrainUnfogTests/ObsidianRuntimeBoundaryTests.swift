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
        "import/BUF/Services/RetainedProjectCommandFacade.swift",
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
      "import/BUF/Services/RetainedTaskCommandFacade.swift",
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

  func testRuntimeLifecycleDoesNotRunLegacyObsidianProjectMigrations() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let scannedFiles = [
      repositoryRoot.appendingPathComponent("import/BUF/App/AppStateSourceIO.swift", isDirectory: false),
      repositoryRoot.appendingPathComponent("import/BUF/App/AppStateLaunchAndSetup.swift", isDirectory: false),
    ]

    let forbiddenReferences = [
      "LegacyObsidianProjectMigrationRunner",
      "LegacyObsidianProjectTaskDurationMigration",
      "LegacyObsidianProjectStageMigration",
      "runLegacyProjectMigrationsAfterSetupIfNeeded",
      "runLegacyObsidianProjectMigrationsIfNeeded",
    ]
    let offenders = try scannedFiles.flatMap { fileURL in
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      return forbiddenReferences.compactMap { reference in
        contents.contains(reference)
          ? "\(relativePath(fileURL, from: repositoryRoot)): \(reference)"
          : nil
      }
    }

    XCTAssertTrue(
      offenders.isEmpty,
      "Reminder refresh/import persistence must not call legacy raw/projects migrations:\n\(offenders.joined(separator: "\n"))"
    )
  }

  func testProductionTargetDoesNotContainLegacyRawProjectsRuntimeServices() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let forbiddenServicePaths = [
      "import/BUF/Services/Legacy/ObsidianProjectDirectoryWatcher.swift",
      "import/BUF/Services/Migrations/LegacyObsidianProjectMigrationRunner.swift",
      "import/BUF/Services/Migrations/LegacyObsidianProjectStageMigration.swift",
      "import/BUF/Services/Migrations/LegacyObsidianProjectTaskDurationMigration.swift",
      "import/BUF/Services/ObsidianChangedProjectProjectionRefresh.swift",
      "import/BUF/Services/ObsidianProjectDeletionSync.swift",
      "import/BUF/Services/ObsidianProjectMarkdownStore.swift",
      "import/BUF/Services/ObsidianProjectNoteModels.swift",
      "import/BUF/Services/ObsidianProjectNoteParser.swift",
      "import/BUF/Services/ObsidianProjectNoteRenderer.swift",
      "import/BUF/Services/ObsidianReminderArchiveStore.swift",
      "import/BUF/Services/ObsidianReminderBootstrapSync.swift",
      "import/BUF/Services/ObsidianReminderDeletionSync.swift",
      "import/BUF/Services/ObsidianReminderImportFormatting.swift",
      "import/BUF/Services/ObsidianReminderImportSync.swift",
      "import/BUF/Services/ObsidianReminderListFileNaming.swift",
      "import/BUF/Services/ObsidianReminderOutlineStateStore.swift",
      "import/BUF/Services/ObsidianReminderProvisioningSync.swift",
      "import/BUF/Services/ObsidianRetainedProjectionAdapter.swift",
      "import/BUF/Services/ObsidianTaskOpenService.swift",
      "import/BUF/App/AppStateObsidianHelperPlugin.swift",
      "import/BUF/Services/ObsidianHelperPluginInstaller.swift",
      "import/BUF/Services/ProjectLifecycleStore.swift",
      "import/BUF/Services/ProjectMarkdownStore.swift",
    ]

    let offenders = forbiddenServicePaths.filter { relativePath in
      FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(relativePath).path)
    }

    XCTAssertTrue(
      offenders.isEmpty,
      "Legacy raw/projects runtime services must not remain in the production target:\n\(offenders.joined(separator: "\n"))"
    )
  }

  func testBundledObsidianHelperPluginDoesNotShipLegacyProjectStorage() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let pluginRoot = repositoryRoot.appendingPathComponent(
      "import/BUF/Resources/ObsidianHelperPlugin",
      isDirectory: true
    )
    guard FileManager.default.fileExists(atPath: pluginRoot.path) else {
      return
    }

    let offenders = try allFiles(under: pluginRoot).flatMap { fileURL in
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      return ["raw/projects", "PROJECTS_ROOT_PATH"].compactMap { reference in
        contents.contains(reference)
          ? "\(relativePath(fileURL, from: repositoryRoot)): \(reference)"
          : nil
      }
    }

    XCTAssertTrue(
      offenders.isEmpty,
      "Bundled helper plugin resources must not contain legacy raw/projects project storage:\n\(offenders.joined(separator: "\n"))"
    )
  }

  func testFeatureInventoryDocumentsAppOwnedRuntimeBoundary() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let docPaths = [
      "docs/feature-inventory-checklist-current.html",
      "docs/feature-inventory-checklist.html",
    ]
    let forbiddenPhrases = [
      ".buf/raw/projects",
      "Obsidian과 Reminders 동기화",
      "Reminders에서 Obsidian으로 첫 가져오기",
      "Obsidian 프로젝트 노트",
      "프로젝트 마크다운 저장소",
      "Obsidian과 Reminders에 반영",
      "Obsidian 노트에 동기화",
      "Obsidian 작업 트리",
    ]

    let offenders = try docPaths.flatMap { docPath in
      let fileURL = repositoryRoot.appendingPathComponent(docPath, isDirectory: false)
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      return forbiddenPhrases.compactMap { phrase in
        contents.contains(phrase) ? "\(docPath): \(phrase)" : nil
      }
    }

    XCTAssertTrue(
      offenders.isEmpty,
      "Current feature inventory docs must describe app-owned runtime storage, not legacy Obsidian project storage:\n\(offenders.joined(separator: "\n"))"
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

  private func allFiles(under root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return []
    }
    var files: [URL] = []
    for case let fileURL as URL in enumerator {
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
