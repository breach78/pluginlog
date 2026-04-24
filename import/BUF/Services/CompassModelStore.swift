import Foundation

struct CompassStorageLayout: Hashable, Sendable {
  let rootURL: URL

  var aiDirectory: URL {
    rootURL.appendingPathComponent("ai", conformingTo: .directory)
  }

  var compassDirectory: URL {
    aiDirectory.appendingPathComponent("compass", conformingTo: .directory)
  }

  var dailySummariesDirectory: URL {
    compassDirectory.appendingPathComponent("day-summaries", conformingTo: .directory)
  }

  var periodSummariesDirectory: URL {
    compassDirectory.appendingPathComponent("period-summaries", conformingTo: .directory)
  }

  var deltasDirectory: URL {
    compassDirectory.appendingPathComponent("deltas", conformingTo: .directory)
  }

  var evidenceDirectory: URL {
    compassDirectory.appendingPathComponent("evidence", conformingTo: .directory)
  }

  var manifestURL: URL {
    compassDirectory.appendingPathComponent("manifest.json", conformingTo: .json)
  }

  var bootstrapStateURL: URL {
    compassDirectory.appendingPathComponent("bootstrap-state.json", conformingTo: .json)
  }

  var selfModelURL: URL {
    compassDirectory.appendingPathComponent("self-model.json", conformingTo: .json)
  }

  var journalIndexURL: URL {
    compassDirectory.appendingPathComponent("journal-index.json", conformingTo: .json)
  }

  var analysisTelemetryURL: URL {
    compassDirectory.appendingPathComponent("analysis-telemetry.json", conformingTo: .json)
  }

  var seedManifestURL: URL {
    compassDirectory.appendingPathComponent("seed-manifest.json", conformingTo: .json)
  }

  var seedReviewURL: URL {
    compassDirectory.appendingPathComponent("seed-review.md")
  }

  var requiredDirectories: [URL] {
    [
      aiDirectory,
      compassDirectory,
      dailySummariesDirectory,
      periodSummariesDirectory,
      deltasDirectory,
      evidenceDirectory,
    ]
  }

  func daySummaryURL(for dayKey: String) -> URL {
    dailySummariesDirectory.appendingPathComponent(dayKey, conformingTo: .json)
  }

  func daySummaryURL(for day: Date) -> URL {
    daySummaryURL(for: CompassDateKeyCodec.dayKey(for: day))
  }

  func dailyDeltaURL(for dayKey: String) -> URL {
    deltasDirectory.appendingPathComponent(dayKey, conformingTo: .json)
  }

  func dailyDeltaURL(for day: Date) -> URL {
    dailyDeltaURL(for: CompassDateKeyCodec.dayKey(for: day))
  }

  func periodSummaryURL(
    granularity: CompassPeriodGranularity,
    periodKey: String
  ) -> URL {
    periodSummariesDirectory.appendingPathComponent(
      "\(granularity.rawValue)-\(periodKey)",
      conformingTo: .json
    )
  }
}

actor CompassModelStore {
  private let layout: CompassStorageLayout
  private let fileManager: FileManager

  init(rootURL: URL, fileManager: FileManager = FileManager()) {
    self.layout = CompassStorageLayout(rootURL: rootURL)
    self.fileManager = fileManager
  }

  func prepare() throws {
    for directory in layout.requiredDirectories {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }

  func validateStructure() throws {
    for directory in layout.requiredDirectories {
      var isDirectory: ObjCBool = false
      let exists = fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
      guard exists, isDirectory.boolValue else {
        throw StorageError.missingRequiredPath(directory)
      }
    }
  }

  func saveManifest(_ manifest: CompassStorageManifest) throws {
    try prepare()
    try writeJSON(manifest, to: layout.manifestURL)
  }

  func loadManifest() throws -> CompassStorageManifest? {
    try loadJSON(CompassStorageManifest.self, from: layout.manifestURL)
  }

  func saveBootstrapState(_ state: CompassBootstrapState) throws {
    try prepare()
    try writeJSON(state, to: layout.bootstrapStateURL)
  }

  func loadBootstrapState() throws -> CompassBootstrapState? {
    try loadJSON(CompassBootstrapState.self, from: layout.bootstrapStateURL)
  }

  func saveSelfModel(_ selfModel: CompassSelfModel) throws {
    try prepare()
    try writeJSON(selfModel, to: layout.selfModelURL)
  }

  func loadSelfModel() throws -> CompassSelfModel? {
    try loadJSON(CompassSelfModel.self, from: layout.selfModelURL)
  }

  func saveJournalIndex(_ index: CompassJournalIndex) throws {
    try prepare()
    try writeJSON(index, to: layout.journalIndexURL)
  }

  func loadJournalIndex() throws -> CompassJournalIndex? {
    try loadJSON(CompassJournalIndex.self, from: layout.journalIndexURL)
  }

  func saveAnalysisTelemetry(_ telemetry: CompassAnalysisTelemetry) throws {
    try prepare()
    try writeJSON(telemetry, to: layout.analysisTelemetryURL)
  }

  func loadAnalysisTelemetry() throws -> CompassAnalysisTelemetry? {
    try loadJSON(CompassAnalysisTelemetry.self, from: layout.analysisTelemetryURL)
  }

  func saveSeedManifest(_ manifest: CompassSeedManifest) throws {
    try prepare()
    try writeJSON(manifest, to: layout.seedManifestURL)
  }

  func loadSeedManifest() throws -> CompassSeedManifest? {
    try loadJSON(CompassSeedManifest.self, from: layout.seedManifestURL)
  }

  func saveSeedReview(_ markdown: String) throws {
    try prepare()
    try writeText(markdown, to: layout.seedReviewURL)
  }

  func loadSeedReview() throws -> String? {
    try loadText(from: layout.seedReviewURL)
  }

  func deleteSeedReview() throws {
    try prepare()
    try deleteItem(at: layout.seedReviewURL)
  }

  func saveDaySummary(_ summary: CompassJournalDaySummary) throws {
    try prepare()
    try writeJSON(summary, to: layout.daySummaryURL(for: summary.dayKey))
  }

  func deleteDaySummary(for dayKey: String) throws {
    try prepare()
    try deleteItem(at: layout.daySummaryURL(for: dayKey))
  }

  func loadDaySummary(for dayKey: String) throws -> CompassJournalDaySummary? {
    try loadJSON(CompassJournalDaySummary.self, from: layout.daySummaryURL(for: dayKey))
  }

  func loadDaySummary(for day: Date) throws -> CompassJournalDaySummary? {
    try loadDaySummary(for: CompassDateKeyCodec.dayKey(for: day))
  }

  func availableDaySummaryKeys() throws -> [String] {
    try prepare()
    return try fileManager.contentsOfDirectory(
      at: layout.dailySummariesDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension.lowercased() == "json" }
    .map { $0.deletingPathExtension().lastPathComponent }
    .sorted()
  }

  func savePeriodSummary(_ summary: CompassJournalPeriodSummary) throws {
    try prepare()
    try writeJSON(
      summary,
      to: layout.periodSummaryURL(
        granularity: summary.granularity,
        periodKey: summary.periodKey
      )
    )
  }

  func deletePeriodSummary(
    granularity: CompassPeriodGranularity,
    periodKey: String
  ) throws {
    try prepare()
    try deleteItem(at: layout.periodSummaryURL(granularity: granularity, periodKey: periodKey))
  }

  func loadPeriodSummary(
    granularity: CompassPeriodGranularity,
    periodKey: String
  ) throws -> CompassJournalPeriodSummary? {
    try loadJSON(
      CompassJournalPeriodSummary.self,
      from: layout.periodSummaryURL(granularity: granularity, periodKey: periodKey)
    )
  }

  func availablePeriodSummaryKeys(
    granularity: CompassPeriodGranularity
  ) throws -> [String] {
    try prepare()
    let prefix = "\(granularity.rawValue)-"
    return try fileManager.contentsOfDirectory(
      at: layout.periodSummariesDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension.lowercased() == "json" }
    .map { $0.deletingPathExtension().lastPathComponent }
    .filter { $0.hasPrefix(prefix) }
    .map { String($0.dropFirst(prefix.count)) }
    .sorted()
  }

  func saveDailyDelta(_ delta: CompassDailyDelta) throws {
    try prepare()
    try writeJSON(delta, to: layout.dailyDeltaURL(for: delta.dayKey))
  }

  func deleteDailyDelta(for dayKey: String) throws {
    try prepare()
    try deleteItem(at: layout.dailyDeltaURL(for: dayKey))
  }

  func loadDailyDelta(for dayKey: String) throws -> CompassDailyDelta? {
    try loadJSON(CompassDailyDelta.self, from: layout.dailyDeltaURL(for: dayKey))
  }

  func loadDailyDelta(for day: Date) throws -> CompassDailyDelta? {
    try loadDailyDelta(for: CompassDateKeyCodec.dayKey(for: day))
  }

  func availableDailyDeltaKeys() throws -> [String] {
    try prepare()
    return try fileManager.contentsOfDirectory(
      at: layout.deltasDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension.lowercased() == "json" }
    .map { $0.deletingPathExtension().lastPathComponent }
    .sorted()
  }

  func storageLayout() -> CompassStorageLayout {
    layout
  }

  private func writeJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(value)
    let directory = url.deletingLastPathComponent()
    let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
    let backupURL = directory.appendingPathComponent(".\(url.lastPathComponent).bak")

    do {
      try data.write(to: tempURL, options: .atomic)

      do {
        _ = try fileManager.replaceItemAt(
          url,
          withItemAt: tempURL,
          backupItemName: backupURL.lastPathComponent,
          options: [.usingNewMetadataOnly]
        )
        if fileManager.fileExists(atPath: backupURL.path) {
          try? fileManager.removeItem(at: backupURL)
        }
      } catch {
        if isFileNotFound(error) {
          try fileManager.moveItem(at: tempURL, to: url)
        } else {
          throw error
        }
      }
    } catch {
      if !fileManager.fileExists(atPath: url.path),
        fileManager.fileExists(atPath: backupURL.path)
      {
        try? fileManager.moveItem(at: backupURL, to: url)
      }
      if fileManager.fileExists(atPath: tempURL.path) {
        try? fileManager.removeItem(at: tempURL)
      }
      AppLogger.storage.error(
        "compass write failed. file=\(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  private func writeText(_ value: String, to url: URL) throws {
    let data = Data(value.utf8)
    let directory = url.deletingLastPathComponent()
    let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
    let backupURL = directory.appendingPathComponent(".\(url.lastPathComponent).bak")

    do {
      try data.write(to: tempURL, options: .atomic)

      do {
        _ = try fileManager.replaceItemAt(
          url,
          withItemAt: tempURL,
          backupItemName: backupURL.lastPathComponent,
          options: [.usingNewMetadataOnly]
        )
        if fileManager.fileExists(atPath: backupURL.path) {
          try? fileManager.removeItem(at: backupURL)
        }
      } catch {
        if isFileNotFound(error) {
          try fileManager.moveItem(at: tempURL, to: url)
        } else {
          throw error
        }
      }
    } catch {
      if !fileManager.fileExists(atPath: url.path),
        fileManager.fileExists(atPath: backupURL.path)
      {
        try? fileManager.moveItem(at: backupURL, to: url)
      }
      if fileManager.fileExists(atPath: tempURL.path) {
        try? fileManager.removeItem(at: tempURL)
      }
      AppLogger.storage.error(
        "compass write failed. file=\(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  private func loadJSON<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
    try prepare()
    guard fileManager.fileExists(atPath: url.path) else { return nil }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      return try decoder.decode(Value.self, from: data)
    } catch {
      AppLogger.storage.error(
        "compass read failed. file=\(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  private func loadText(from url: URL) throws -> String? {
    try prepare()
    guard fileManager.fileExists(atPath: url.path) else { return nil }

    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      AppLogger.storage.error(
        "compass read failed. file=\(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  private func isFileNotFound(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSCocoaErrorDomain else { return false }
    return nsError.code == NSFileNoSuchFileError
  }

  private func deleteItem(at url: URL) throws {
    guard fileManager.fileExists(atPath: url.path) else { return }

    do {
      try fileManager.removeItem(at: url)
    } catch {
      AppLogger.storage.error(
        "compass delete failed. file=\(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }
}
