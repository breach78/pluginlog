import Foundation

struct ArchivedProjectTaskBundle: Codable, Equatable, Sendable {
  var archivedTaskID: UUID
  var reminderIdentifier: String?
  var reminderExternalIdentifier: String
  var title: String
  var isCompleted: Bool
  var completionDate: Date?
  var unifiedReminderDate: Date?
  var priority: Int
  var reminderNoteText: String
}

struct ArchivedProjectBundle: Codable, Equatable {
  var archivedProjectID: UUID
  var title: String
  var colorHex: String?
  var archivedAt: Date
  var reminderListIdentifier: String
  var reminderListExternalIdentifier: String
  var workspaceNodeIDs: [UUID]
  var workspaceOrderIndex: Int?
  var projectRootStructure: ReminderProjectRootStructureRecord?
  var projectTaskOrder: ReminderProjectTaskOrderRecord?
  var projectFeature: ReminderProjectFeatureSidecarRecord?
  var taskBundles: [ArchivedProjectTaskBundle]
  var taskFeatureSidecarByTaskID: [UUID: ReminderTaskFeatureSidecarRecord]
  var taskSourceRuntimeStateByTaskID: [UUID: ReminderTaskSourceRuntimeState]
}

struct ArchivedProjectBundleDescriptor: Equatable {
  var projectID: UUID
  var title: String
  var colorHex: String?
  var archivedAt: Date
}

extension ArchivedProjectBundle: @unchecked Sendable {}

struct ArchivedProjectBundleStore {
  let directoryURL: URL

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  private static let decoder = JSONDecoder()

  func allBundles(fileManager: FileManager = .default) -> [ArchivedProjectBundle] {
    let directoryExists =
      (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    guard directoryExists else { return [] }

    let fileURLs =
      (try? fileManager.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []

    return fileURLs
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .compactMap { load(fileURL: $0, fileManager: fileManager) }
  }

  func bundle(for projectID: UUID, fileManager: FileManager = .default) -> ArchivedProjectBundle? {
    load(fileURL: bundleURL(for: projectID), fileManager: fileManager)
  }

  func save(
    _ bundle: ArchivedProjectBundle,
    fileManager: FileManager = .default
  ) throws {
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let data = try Self.encoder.encode(bundle)
    try data.write(to: bundleURL(for: bundle.archivedProjectID), options: .atomic)
  }

  func remove(
    projectID: UUID,
    fileManager: FileManager = .default
  ) throws {
    let fileURL = bundleURL(for: projectID)
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    try fileManager.removeItem(at: fileURL)
  }

  private func bundleURL(for projectID: UUID) -> URL {
    directoryURL
      .appendingPathComponent(projectID.uuidString, isDirectory: false)
      .appendingPathExtension("json")
  }

  private func load(
    fileURL: URL,
    fileManager: FileManager
  ) -> ArchivedProjectBundle? {
    guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? Self.decoder.decode(ArchivedProjectBundle.self, from: data)
  }
}

enum ArchivedProjectBundleStoreFactory {
  static func make(dataDirectory: URL?) -> ArchivedProjectBundleStore? {
    guard let dataDirectory else { return nil }
    return ArchivedProjectBundleStore(
      directoryURL: dataDirectory.appendingPathComponent(
        "archived-project-bundles",
        isDirectory: true
      )
    )
  }
}

enum ArchivedProjectBundleOwner {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var dataDirectory: URL?

  static func install(dataDirectory: URL?) {
    lock.lock()
    defer { lock.unlock() }
    self.dataDirectory = dataDirectory
  }

  static func reset() {
    install(dataDirectory: nil)
  }

  static func allBundles() -> [ArchivedProjectBundle] {
    resolvedStore()?.allBundles() ?? []
  }

  static func bundle(for projectID: UUID) -> ArchivedProjectBundle? {
    resolvedStore()?.bundle(for: projectID)
  }

  static func descriptors() -> [ArchivedProjectBundleDescriptor] {
    allBundles()
      .map {
        ArchivedProjectBundleDescriptor(
          projectID: $0.archivedProjectID,
          title: $0.title,
          colorHex: $0.colorHex,
          archivedAt: $0.archivedAt
        )
      }
      .sorted {
        if $0.archivedAt != $1.archivedAt {
          return $0.archivedAt > $1.archivedAt
        }
        return $0.projectID.uuidString < $1.projectID.uuidString
      }
  }

  private static func resolvedStore() -> ArchivedProjectBundleStore? {
    lock.lock()
    let currentDataDirectory = dataDirectory
    lock.unlock()
    return ArchivedProjectBundleStoreFactory.make(dataDirectory: currentDataDirectory)
  }
}
