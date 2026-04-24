import Foundation
import SQLite3

@MainActor
protocol StorageCoordinator: AnyObject {
  var container: AppContainer? { get }
  var paths: ContainerPaths? { get }

  /// Creates a fresh app container layout at the chosen root folder.
  func initializeContainer(at rootURL: URL) async throws
  /// Opens an existing container at the chosen root or initializes an empty root.
  func openOrInitializeContainer(at rootURL: URL) async throws
  /// Restores persisted container access and validates the expected directory structure.
  func openContainer() async throws
  /// Ensures the container still contains the files and folders required by the app.
  func validateStructure() throws
  /// Moves the existing container to a new root while preserving bookmark access.
  func relocateContainer(to newURL: URL) async throws
  /// Clears the in-memory container without deleting any on-disk data.
  func clearActiveContainer()
  /// Computes a lightweight health snapshot used by setup and diagnostics UI.
  func healthStatus() async -> ContainerHealth
}

enum StorageError: LocalizedError {
  case noContainerConfigured
  case securityScopeFailed
  case missingRequiredPath(URL)
  case invalidManifest

  var errorDescription: String? {
    switch self {
    case .noContainerConfigured:
      "컨테이너가 아직 설정되지 않았습니다."
    case .securityScopeFailed:
      "선택한 폴더의 보안 권한을 확보하지 못했습니다."
    case .missingRequiredPath(let url):
      "필수 경로가 누락되었습니다: \(url.path)"
    case .invalidManifest:
      "container.json 파일이 유효하지 않습니다."
    }
  }
}

@MainActor
final class LocalStorageCoordinator: ObservableObject, StorageCoordinator {
  private struct TrashedItemSnapshot {
    let originalURL: URL
    let trashedURL: URL
  }

  private struct MovedItemSnapshot {
    let originalURL: URL
    let destinationURL: URL
  }

  private enum Keys {
    static let bookmarkData = "container.bookmarkData"
    static let rootPath = "container.rootPath"
  }

  @Published private(set) var container: AppContainer?

  private let fileManager: FileManager
  private let userDefaults: UserDefaults
  private var securityScopedRootURL: URL?

  init(fileManager: FileManager = .default, userDefaults: UserDefaults = .standard) {
    self.fileManager = fileManager
    self.userDefaults = userDefaults
  }

  var paths: ContainerPaths? {
    guard let container else { return nil }
    return ContainerPaths(root: container.rootURL)
  }

  func initializeContainer(at rootURL: URL) async throws {
    let paths = ContainerPaths(root: rootURL)

    for directory in paths.requiredDirectories {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    if !fileManager.fileExists(atPath: paths.sqliteURL.path) {
      fileManager.createFile(atPath: paths.sqliteURL.path, contents: nil)
    }

    let bookmarkData = try rootURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    let manifest = AppContainer(
      rootURL: rootURL,
      bookmarkData: bookmarkData,
      schemaVersion: 1,
      createdAt: .now
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(manifest)
    try data.write(to: paths.manifestURL, options: .atomic)

    userDefaults.set(bookmarkData, forKey: Keys.bookmarkData)
    userDefaults.set(rootURL.path, forKey: Keys.rootPath)
    container = manifest
    updateSecurityScopedRootURL(to: rootURL)
  }

  func openOrInitializeContainer(at rootURL: URL) async throws {
    let paths = ContainerPaths(root: rootURL)
    var isDirectory: ObjCBool = false
    let rootExists = fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory)
    if rootExists && !isDirectory.boolValue {
      throw StorageError.missingRequiredPath(rootURL)
    }

    let hasManifest = fileManager.fileExists(atPath: paths.manifestURL.path)
    let hasSQLite = fileManager.fileExists(atPath: paths.sqliteURL.path)
    if !rootExists || (!hasManifest && !hasSQLite) {
      try await initializeContainer(at: rootURL)
      return
    }

    guard hasManifest else {
      throw StorageError.missingRequiredPath(paths.manifestURL)
    }
    guard hasSQLite else {
      throw StorageError.missingRequiredPath(paths.sqliteURL)
    }

    try createMissingDirectoriesIfNeeded(paths: paths)
    var manifest = try decodeManifest(at: paths.manifestURL)
    let bookmarkData = try rootURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    manifest.rootURL = rootURL
    manifest.bookmarkData = bookmarkData
    try writeManifest(manifest, to: paths.manifestURL)

    userDefaults.set(bookmarkData, forKey: Keys.bookmarkData)
    userDefaults.set(rootURL.path, forKey: Keys.rootPath)
    container = manifest
    updateSecurityScopedRootURL(to: rootURL)
    try validateStructure()
  }

  func openContainer() async throws {
    var bookmarkOpenError: Error?

    if let bookmarkData = userDefaults.data(forKey: Keys.bookmarkData) {
      do {
        try openUsingBookmark(bookmarkData)
        return
      } catch {
        bookmarkOpenError = error
        AppLogger.storage.error(
          "bookmark open failed: \(error.localizedDescription, privacy: .public)")
      }
    }

    if try openUsingFallbackLocations() {
      return
    }

    if let bookmarkOpenError {
      throw bookmarkOpenError
    }

    throw StorageError.noContainerConfigured
  }

  func validateStructure() throws {
    guard let paths else {
      throw StorageError.noContainerConfigured
    }

    for directory in paths.requiredDirectories {
      var isDirectory: ObjCBool = false
      let exists = fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
      if !exists || !isDirectory.boolValue {
        throw StorageError.missingRequiredPath(directory)
      }
    }

    if !fileManager.fileExists(atPath: paths.manifestURL.path) {
      throw StorageError.missingRequiredPath(paths.manifestURL)
    }

    if !fileManager.fileExists(atPath: paths.sqliteURL.path) {
      throw StorageError.missingRequiredPath(paths.sqliteURL)
    }
  }

  func relocateContainer(to newURL: URL) async throws {
    guard let currentPaths = paths else {
      throw StorageError.noContainerConfigured
    }

    if currentPaths.root == newURL {
      return
    }

    let previousContainer = container
    let previousBookmarkData = userDefaults.data(forKey: Keys.bookmarkData)
    let previousRootPath = userDefaults.string(forKey: Keys.rootPath)
    let previousRootURL = currentPaths.root

    var trashedItems: [TrashedItemSnapshot] = []
    var movedItems: [MovedItemSnapshot] = []

    do {
      try fileManager.createDirectory(at: newURL, withIntermediateDirectories: true)

      let existing = try fileManager.contentsOfDirectory(atPath: newURL.path)
      if !existing.isEmpty {
        for item in existing {
          let target = newURL.appendingPathComponent(item)
          let trashedURL = try moveItemToTrash(target)
          trashedItems.append(TrashedItemSnapshot(originalURL: target, trashedURL: trashedURL))
        }
      }

      let oldItems = try fileManager.contentsOfDirectory(
        at: currentPaths.root, includingPropertiesForKeys: nil)
      for item in oldItems {
        let target = newURL.appendingPathComponent(item.lastPathComponent)
        try fileManager.moveItem(at: item, to: target)
        movedItems.append(MovedItemSnapshot(originalURL: item, destinationURL: target))
      }

      let bookmarkData = try newURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )

      var manifest =
        container
        ?? AppContainer(
          rootURL: newURL, bookmarkData: bookmarkData, schemaVersion: 1, createdAt: .now)
      manifest.rootURL = newURL
      manifest.bookmarkData = bookmarkData

      let newPaths = ContainerPaths(root: newURL)
      try writeManifest(manifest, to: newPaths.manifestURL)

      userDefaults.set(bookmarkData, forKey: Keys.bookmarkData)
      userDefaults.set(newURL.path, forKey: Keys.rootPath)
      container = manifest
      updateSecurityScopedRootURL(to: newURL)

      try validateStructure()
    } catch {
      AppLogger.storage.error(
        "relocate container failed. old=\(previousRootURL.path, privacy: .public) new=\(newURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      rollbackRelocation(movedItems: movedItems, trashedItems: trashedItems)
      container = previousContainer
      if let previousBookmarkData {
        userDefaults.set(previousBookmarkData, forKey: Keys.bookmarkData)
      } else {
        userDefaults.removeObject(forKey: Keys.bookmarkData)
      }
      if let previousRootPath {
        userDefaults.set(previousRootPath, forKey: Keys.rootPath)
      } else {
        userDefaults.removeObject(forKey: Keys.rootPath)
      }
      updateSecurityScopedRootURL(to: previousRootURL)
      throw error
    }
  }

  func clearActiveContainer() {
    container = nil
    updateSecurityScopedRootURL(to: nil)
  }

  func healthStatus() async -> ContainerHealth {
    guard let paths else { return .unknown }
    let rootURL = paths.root
    let sqliteURL = paths.sqliteURL
    let bookmarkResolved = container != nil

    return await Task.detached(priority: .utility) {
      Self.computeHealth(
        rootURL: rootURL,
        sqliteURL: sqliteURL,
        bookmarkResolved: bookmarkResolved
      )
    }.value
  }

  deinit {
    securityScopedRootURL?.stopAccessingSecurityScopedResource()
  }

  nonisolated private static func computeHealth(
    rootURL: URL,
    sqliteURL: URL,
    bookmarkResolved: Bool
  ) -> ContainerHealth {
    let fileManager = FileManager.default
    var warnings: [String] = []

    var isDirectory: ObjCBool = false
    let rootReachable =
      fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory)
      && isDirectory.boolValue

    let sqliteReachable = fileManager.fileExists(atPath: sqliteURL.path)
    let availableBytes =
      (try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage) ?? 0

    let sqliteIntegrityOK = checkSQLiteIntegrity(at: sqliteURL)
    if !sqliteIntegrityOK {
      warnings.append("SQLite integrity check failed")
    }

    if availableBytes < 200 * 1024 * 1024 {
      warnings.append("Low disk capacity (<200MB)")
    }

    return ContainerHealth(
      rootReachable: rootReachable,
      bookmarkResolved: bookmarkResolved,
      sqliteReachable: sqliteReachable,
      availableBytes: Int64(availableBytes),
      sqliteIntegrityOK: sqliteIntegrityOK,
      warnings: warnings
    )
  }

  nonisolated private static func checkSQLiteIntegrity(at url: URL) -> Bool {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
      sqlite3_close(db)
      return false
    }
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA quick_check(1);", -1, &statement, nil) == SQLITE_OK else {
      sqlite3_finalize(statement)
      return false
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW,
      let value = sqlite3_column_text(statement, 0)
    else {
      return false
    }

    return String(cString: value).lowercased() == "ok"
  }

  private func openUsingBookmark(_ bookmarkData: Data) throws {
    var isStale = false
    let resolvedURL = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    updateSecurityScopedRootURL(to: resolvedURL)

    let paths = ContainerPaths(root: resolvedURL)
    try createMissingDirectoriesIfNeeded(paths: paths)

    var manifest = try decodeManifest(at: paths.manifestURL)

    if isStale {
      let refreshedBookmark = try resolvedURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      userDefaults.set(refreshedBookmark, forKey: Keys.bookmarkData)
      manifest.bookmarkData = refreshedBookmark
      try writeManifest(manifest, to: paths.manifestURL)
    }

    manifest.rootURL = resolvedURL
    container = manifest

    try validateStructure()

    userDefaults.set(resolvedURL.path, forKey: Keys.rootPath)
  }

  private func openUsingFallbackLocations() throws -> Bool {
    for rootURL in fallbackCandidateRoots() {
      let paths = ContainerPaths(root: rootURL)
      guard fileManager.fileExists(atPath: paths.manifestURL.path),
        fileManager.fileExists(atPath: paths.sqliteURL.path)
      else {
        continue
      }

      try createMissingDirectoriesIfNeeded(paths: paths)

      var manifest = try decodeManifest(at: paths.manifestURL)
      manifest.rootURL = rootURL

      if let bookmarkData = try? rootURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      ) {
        manifest.bookmarkData = bookmarkData
        userDefaults.set(bookmarkData, forKey: Keys.bookmarkData)
        updateSecurityScopedRootURL(to: rootURL)
      }

      try writeManifest(manifest, to: paths.manifestURL)

      container = manifest
      try validateStructure()
      userDefaults.set(rootURL.path, forKey: Keys.rootPath)
      return true
    }

    return false
  }

  private func createMissingDirectoriesIfNeeded(paths: ContainerPaths) throws {
    for directory in paths.requiredDirectories {
      var isDirectory: ObjCBool = false
      let exists = fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
      if !exists {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        continue
      }

      if !isDirectory.boolValue {
        throw StorageError.missingRequiredPath(directory)
      }
    }
  }

  private func fallbackCandidateRoots() -> [URL] {
    var roots: [URL] = []

    if let path = userDefaults.string(forKey: Keys.rootPath), !path.isEmpty {
      roots.append(URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
    }

    let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
      .standardizedFileURL
    roots.append(cwd)

    var unique: [URL] = []
    var seen = Set<String>()
    for root in roots {
      let key = root.path
      if seen.insert(key).inserted {
        unique.append(root)
      }
    }

    return unique
  }

  private func decodeManifest(at url: URL) throws -> AppContainer {
    let manifestData = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    guard let manifest = try? decoder.decode(AppContainer.self, from: manifestData) else {
      throw StorageError.invalidManifest
    }
    return manifest
  }

  private func writeManifest(_ manifest: AppContainer, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: url, options: .atomic)
  }

  private func moveItemToTrash(_ url: URL) throws -> URL {
    var trashedURL: NSURL?
    try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
    return (trashedURL as URL?) ?? url
  }

  private func rollbackRelocation(
    movedItems: [MovedItemSnapshot],
    trashedItems: [TrashedItemSnapshot]
  ) {
    for snapshot in movedItems.reversed() {
      guard fileManager.fileExists(atPath: snapshot.destinationURL.path) else { continue }
      do {
        try fileManager.moveItem(at: snapshot.destinationURL, to: snapshot.originalURL)
      } catch {
        AppLogger.storage.error(
          "relocate rollback failed while restoring moved item. source=\(snapshot.destinationURL.path, privacy: .public) dest=\(snapshot.originalURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    for snapshot in trashedItems.reversed() {
      guard fileManager.fileExists(atPath: snapshot.trashedURL.path) else { continue }
      do {
        try fileManager.moveItem(at: snapshot.trashedURL, to: snapshot.originalURL)
      } catch {
        AppLogger.storage.error(
          "relocate rollback failed while restoring trashed item. source=\(snapshot.trashedURL.path, privacy: .public) dest=\(snapshot.originalURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  private func updateSecurityScopedRootURL(to newURL: URL?) {
    guard securityScopedRootURL?.path != newURL?.path else { return }

    securityScopedRootURL?.stopAccessingSecurityScopedResource()
    securityScopedRootURL = nil

    guard let newURL else { return }
    if newURL.startAccessingSecurityScopedResource() {
      securityScopedRootURL = newURL
    }
  }
}
