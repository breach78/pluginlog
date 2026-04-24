import AppKit
import Foundation
import SwiftData

#if DEBUG
enum DebugTaskListPerfSeedProfile: String {
  case compact
  case mixed
  case rich

  var calendarIdentifier: String {
    switch self {
    case .compact:
      return "debug.project-detail-task-list.perf-1000.compact"
    case .mixed:
      return "debug.project-detail-task-list.perf-1000"
    case .rich:
      return "debug.project-detail-task-list.perf-1000.rich"
    }
  }

  var title: String {
    switch self {
    case .compact:
      return "DEBUG Task List Perf 1000 Compact"
    case .mixed:
      return "DEBUG Task List Perf 1000 Mixed"
    case .rich:
      return "DEBUG Task List Perf 1000 Rich"
    }
  }

  var colorHex: String {
    switch self {
    case .compact:
      return "8C9E7A"
    case .mixed:
      return "A4A19A"
    case .rich:
      return "9C7E72"
    }
  }
}
#endif

struct Phase0RedLineBaselineBundle: Codable {
  struct DiagnosticsSnapshot: Codable {
    let syncPerformanceCounters: [String: Int]
  }

  struct AppSnapshot: Codable {
    let exportedAt: Date
    let appVersion: String
    let buildVersion: String
    let bundleIdentifier: String
    let currentViewMode: String
    let selectedProjectID: UUID?
    let timelineDayColumnWidth: Double
    let includeCompletedSyncEnabled: Bool
    let hasInitialSyncConsent: Bool
    let hasSyncConsentDecision: Bool
    let obsidianProjectsRootPath: String?
    let containerRootPath: String?
  }

  struct ContainerSnapshot: Codable {
    let rootPath: String
    let manifestPath: String
    let sqlitePath: String
    let health: HealthSnapshot
  }

  struct HealthSnapshot: Codable {
    let rootReachable: Bool
    let bookmarkResolved: Bool
    let sqliteReachable: Bool
    let availableBytes: Int64
    let sqliteIntegrityOK: Bool
    let warnings: [String]

    init(_ health: ContainerHealth) {
      self.rootReachable = health.rootReachable
      self.bookmarkResolved = health.bookmarkResolved
      self.sqliteReachable = health.sqliteReachable
      self.availableBytes = health.availableBytes
      self.sqliteIntegrityOK = health.sqliteIntegrityOK
      self.warnings = health.warnings
    }
  }

  struct SyncSnapshot: Codable {
    let lastFullSyncAt: Date?
    let lastPeriodicSyncAt: Date?
    let lastError: String?
    let lastConflictAt: Date?
    let conflictCount: Int
  }

  struct TaskPreview: Codable {
    let id: UUID
    let title: String
    let rowOrder: Int
    let isCompleted: Bool
    let attachmentCount: Int
    let reminderNoteLength: Int
  }

  struct ProjectSummary: Codable {
    let id: UUID
    let title: String
    let calendarIdentifier: String
    let sortOrder: Int
    let isArchived: Bool
    let taskCount: Int
    let incompleteTaskCount: Int
    let completedTaskCount: Int
    let taskAttachmentCount: Int
    let projectAttachmentCount: Int
    let projectNoteLength: Int
    let longestTaskTitleLength: Int
    let longestReminderNoteLength: Int
    let updatedAt: Date
    let firstTaskPreview: [TaskPreview]
    let lastTaskPreview: [TaskPreview]
  }

  struct PreferencesSnapshot: Codable {
    let trackedKeys: [String: String]
  }

  let app: AppSnapshot
  let container: ContainerSnapshot
  let sync: SyncSnapshot
  let diagnostics: DiagnosticsSnapshot
  let projectCount: Int
  let taskCount: Int
  let attachmentCount: Int
  let archivedProjectCount: Int
  let archivedTaskCount: Int
  let projectsByTaskCountDescending: [ProjectSummary]
  let preferences: PreferencesSnapshot
}

struct Phase0RedLineFixtureManifest: Codable {
  struct ExportedFile: Codable {
    let path: String
    let kind: String
    let purpose: String
  }

  let exportedAt: Date
  let exportDirectory: String
  let fixtureDatabaseDirectory: String
  let exportedFiles: [ExportedFile]
}

enum Phase0RedLineBaselineError: LocalizedError {
  case containerUnavailable

  var errorDescription: String? {
    switch self {
    case .containerUnavailable:
      return "컨테이너가 준비되지 않아 기준선을 내보낼 수 없습니다."
    }
  }
}

@MainActor
struct Phase0RedLineBaselineExporter {
  private let storageCoordinator: LocalStorageCoordinator
  private let modelContainer: ModelContainer
  private let runtimeSnapshot: OutlineProjectionRuntimeSnapshot?
  private let userDefaults: UserDefaults
  private let fileManager: FileManager
  private let now: () -> Date
  private let bundle: Bundle
  private let currentViewMode: ViewMode
  private let selectedProjectID: UUID?
  private let timelineDayColumnWidth: CGFloat
  private let includeCompletedSyncEnabled: Bool
  private let hasInitialSyncConsent: Bool
  private let hasSyncConsentDecision: Bool
  private let obsidianProjectsRootURL: URL?
  private let containerRootURL: URL?

  init(
    storageCoordinator: LocalStorageCoordinator,
    modelContainer: ModelContainer,
    runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    currentViewMode: ViewMode,
    selectedProjectID: UUID?,
    timelineDayColumnWidth: CGFloat,
    includeCompletedSyncEnabled: Bool,
    hasInitialSyncConsent: Bool,
    hasSyncConsentDecision: Bool,
    obsidianProjectsRootURL: URL?,
    containerRootURL: URL?,
    userDefaults: UserDefaults = .standard,
    fileManager: FileManager = .default,
    bundle: Bundle = .main,
    now: @escaping () -> Date = Date.init
  ) {
    self.storageCoordinator = storageCoordinator
    self.modelContainer = modelContainer
    self.runtimeSnapshot = runtimeSnapshot
    self.userDefaults = userDefaults
    self.fileManager = fileManager
    self.bundle = bundle
    self.now = now
    self.currentViewMode = currentViewMode
    self.selectedProjectID = selectedProjectID
    self.timelineDayColumnWidth = timelineDayColumnWidth
    self.includeCompletedSyncEnabled = includeCompletedSyncEnabled
    self.hasInitialSyncConsent = hasInitialSyncConsent
    self.hasSyncConsentDecision = hasSyncConsentDecision
    self.obsidianProjectsRootURL = obsidianProjectsRootURL
    self.containerRootURL = containerRootURL
  }

  func export() async throws -> URL {
    guard let paths = storageCoordinator.paths else {
      throw Phase0RedLineBaselineError.containerUnavailable
    }

    let exportDate = now()
    let exportDirectory = paths.exportsDirectory
      .appendingPathComponent("phase0-red-line-freeze", isDirectory: true)
      .appendingPathComponent(Self.timestampFormatter.string(from: exportDate), isDirectory: true)

    try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

    let context = modelContainer.mainContext
    try context.save()

    let projects = try context.fetch(
      FetchDescriptor<ProjectRecord>(
        sortBy: [
          SortDescriptor(\ProjectRecord.updatedAt, order: .reverse),
          SortDescriptor(\ProjectRecord.createdAt, order: .forward),
        ]
      )
    )
    let tasks = try context.fetch(
      FetchDescriptor<TaskContent>(
        sortBy: [
          SortDescriptor(\TaskContent.localUpdatedAt, order: .reverse),
          SortDescriptor(\TaskContent.createdAt, order: .forward),
        ]
      )
    )
    let placements = try context.fetch(
      FetchDescriptor<TaskPlacement>(
        sortBy: [
          SortDescriptor(\TaskPlacement.projectID, order: .forward),
          SortDescriptor(\TaskPlacement.rowOrder, order: .forward),
          SortDescriptor(\TaskPlacement.createdAt, order: .forward),
        ]
      )
    )
    let attachments = try context.fetch(FetchDescriptor<AttachmentEntity>())
    let health = await storageCoordinator.healthStatus()

    let projectAttachmentCounts = Dictionary(
      grouping: attachments.filter { $0.ownerType == .project && !$0.isArchived },
      by: \.ownerID
    ).mapValues(\.count)
    let primaryPlacementByTaskID = Dictionary(
      placements.lazy
        .filter { $0.sourceKind == .primary }
        .map { ($0.contentID, $0) },
      uniquingKeysWith: { current, _ in current }
    )
    let anyPlacementByTaskID = Dictionary(
      placements.map { ($0.contentID, $0) },
      uniquingKeysWith: { current, _ in current }
    )
    let syncPerformanceCounters = SyncPerformanceCounter.snapshot()
    let tasksByProjectID = tasks.reduce(into: [UUID: [TaskContent]]()) { result, task in
      guard let projectID = resolvedProjectID(
        for: task,
        primaryPlacementByTaskID: primaryPlacementByTaskID,
        anyPlacementByTaskID: anyPlacementByTaskID
      ) else { return }
      result[projectID, default: []].append(task)
    }
    let archivedProjectIDs = Set(projects.filter(\.isArchived).map(\.id))

    let bundle = Phase0RedLineBaselineBundle(
      app: makeAppSnapshot(exportedAt: exportDate),
      container: Phase0RedLineBaselineBundle.ContainerSnapshot(
        rootPath: paths.root.path,
        manifestPath: paths.manifestURL.path,
        sqlitePath: paths.sqliteURL.path,
        health: .init(health)
      ),
      sync: Phase0RedLineBaselineBundle.SyncSnapshot(
        lastFullSyncAt: nil,
        lastPeriodicSyncAt: nil,
        lastError: nil,
        lastConflictAt: runtimeConflictTimestamp(),
        conflictCount: runtimeConflictCount()
      ),
      diagnostics: Phase0RedLineBaselineBundle.DiagnosticsSnapshot(
        syncPerformanceCounters: syncPerformanceCounters
      ),
      projectCount: projects.count,
      taskCount: tasks.count,
      attachmentCount: attachments.count,
      archivedProjectCount: projects.filter(\.isArchived).count,
      archivedTaskCount: tasks.filter { task in
        guard let projectID = resolvedProjectID(
          for: task,
          primaryPlacementByTaskID: primaryPlacementByTaskID,
          anyPlacementByTaskID: anyPlacementByTaskID
        ) else { return false }
        return archivedProjectIDs.contains(projectID)
      }.count,
      projectsByTaskCountDescending: makeProjectSummaries(
        from: projects,
        tasksByProjectID: tasksByProjectID,
        primaryPlacementByTaskID: primaryPlacementByTaskID,
        projectAttachmentCounts: projectAttachmentCounts
      ),
      preferences: .init(trackedKeys: trackedPreferenceSnapshot())
    )

    try writeJSON(bundle, to: exportDirectory.appendingPathComponent("baseline.json"))
    try writeREADME(for: bundle, to: exportDirectory.appendingPathComponent("README.md"))
    try writeRegressionChecklist(
      for: bundle,
      to: exportDirectory.appendingPathComponent("regression-checklist.md")
    )

    let containerExportDirectory = exportDirectory.appendingPathComponent("container", isDirectory: true)
    try fileManager.createDirectory(at: containerExportDirectory, withIntermediateDirectories: true)
    try copyIfExists(paths.manifestURL, to: containerExportDirectory.appendingPathComponent("container.json"))
    try copySQLiteArtifacts(from: paths.sqliteURL, toDirectory: containerExportDirectory)
    try copyDirectoryIfExists(
      paths.cacheDirectory.appendingPathComponent("project-task-attachment-index", isDirectory: true),
      to: exportDirectory.appendingPathComponent("project-task-attachment-index", isDirectory: true)
    )
    try writeFixtureManifest(
      exportedAt: exportDate,
      exportDirectory: exportDirectory,
      containerExportDirectory: containerExportDirectory
    )

    return exportDirectory
  }

  private func makeAppSnapshot(exportedAt: Date) -> Phase0RedLineBaselineBundle.AppSnapshot {
    Phase0RedLineBaselineBundle.AppSnapshot(
      exportedAt: exportedAt,
      appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
      buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
      bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
      currentViewMode: currentViewMode.rawValue,
      selectedProjectID: selectedProjectID,
      timelineDayColumnWidth: Double(timelineDayColumnWidth),
      includeCompletedSyncEnabled: includeCompletedSyncEnabled,
      hasInitialSyncConsent: hasInitialSyncConsent,
      hasSyncConsentDecision: hasSyncConsentDecision,
      obsidianProjectsRootPath: obsidianProjectsRootURL?.path,
      containerRootPath: containerRootURL?.path
    )
  }

  private func runtimeConflictCount() -> Int {
    guard let runtimeSnapshot else { return 0 }
    return runtimeSnapshot.taskSourceRuntimeStateByReminderExternalIdentifier.values.reduce(into: 0) {
      partialResult, runtimeState in
      if let raw = runtimeState.noteConflictStateRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty
      {
        partialResult += 1
      }
    }
  }

  private func runtimeConflictTimestamp() -> Date? {
    guard let runtimeSnapshot else { return nil }
    return runtimeSnapshot.taskSourceRuntimeStateByReminderExternalIdentifier.values.compactMap {
      runtimeState in
      guard let raw = runtimeState.noteConflictStateRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty
      else {
        return nil
      }
      return runtimeState.lastObservedReminderModifiedAt
    }
    .max()
  }

  private func makeProjectSummaries(
    from projects: [ProjectRecord],
    tasksByProjectID: [UUID: [TaskContent]],
    primaryPlacementByTaskID: [UUID: TaskPlacement],
    projectAttachmentCounts: [UUID: Int]
  ) -> [Phase0RedLineBaselineBundle.ProjectSummary] {
    projects
      .map { project in
        let projectTasks = tasksByProjectID[project.id, default: []]
        let orderedTasks = projectTasks.sorted { lhs, rhs in
          let lhsRowOrder = primaryPlacementByTaskID[lhs.id]?.rowOrder ?? .max
          let rhsRowOrder = primaryPlacementByTaskID[rhs.id]?.rowOrder ?? .max
          if lhsRowOrder == rhsRowOrder {
            return lhs.createdAt < rhs.createdAt
          }
          return lhsRowOrder < rhsRowOrder
        }
        let firstPreview = orderedTasks.prefix(8).map {
          makeTaskPreview($0, rowOrder: primaryPlacementByTaskID[$0.id]?.rowOrder ?? .max)
        }
        let lastPreview = orderedTasks.suffix(8).map {
          makeTaskPreview($0, rowOrder: primaryPlacementByTaskID[$0.id]?.rowOrder ?? .max)
        }
        let title = project.resolvedTitle

        return Phase0RedLineBaselineBundle.ProjectSummary(
          id: project.id,
          title: title,
          calendarIdentifier: project.projectReminderListIdentifier,
          sortOrder: Int(project.projectWorkspaceSortKey ?? 0),
          isArchived: project.isArchived,
          taskCount: projectTasks.count,
          incompleteTaskCount: projectTasks.filter { !$0.isCompleted }.count,
          completedTaskCount: projectTasks.filter(\.isCompleted).count,
          taskAttachmentCount: projectTasks.reduce(0) { $0 + max(0, $1.attachmentCount) },
          projectAttachmentCount: projectAttachmentCounts[project.id] ?? 0,
          projectNoteLength: project.noteMarkdown.count,
          longestTaskTitleLength: projectTasks.map { $0.title.count }.max() ?? 0,
          longestReminderNoteLength: projectTasks.map { $0.reminderNoteText.count }.max() ?? 0,
          updatedAt: project.updatedAt,
          firstTaskPreview: firstPreview,
          lastTaskPreview: lastPreview
        )
      }
      .sorted { lhs, rhs in
        if lhs.taskCount == rhs.taskCount {
          return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.taskCount > rhs.taskCount
      }
  }

  private func makeTaskPreview(_ task: TaskContent, rowOrder: Int)
    -> Phase0RedLineBaselineBundle.TaskPreview
  {
    Phase0RedLineBaselineBundle.TaskPreview(
      id: task.id,
      title: task.title,
      rowOrder: rowOrder == .max ? 0 : rowOrder,
      isCompleted: task.isCompleted,
      attachmentCount: task.attachmentCount,
      reminderNoteLength: task.reminderNoteText.count
    )
  }

  private func resolvedProjectID(
    for task: TaskContent,
    primaryPlacementByTaskID: [UUID: TaskPlacement],
    anyPlacementByTaskID: [UUID: TaskPlacement]
  ) -> UUID? {
    if let projectID = primaryPlacementByTaskID[task.id]?.projectID {
      return projectID
    }
    if let projectID = task.reminderOwnerProjectID {
      return projectID
    }
    return anyPlacementByTaskID[task.id]?.projectID
  }

  private func trackedPreferenceSnapshot() -> [String: String] {
    let prefixes = [
      "project.showCompletedTasks.",
      "project.taskDateSortMode.",
      "project.manualProgress.",
      "workspace.timelineProjectListSortMode",
      "timeline.dayColumnWidth",
      "sync.",
      "obsidian."
    ]

    let representation = userDefaults.dictionaryRepresentation()
    return representation
      .filter { key, _ in
        prefixes.contains { prefix in key.hasPrefix(prefix) || key == prefix }
      }
      .mapValues { stringifyPreferenceValue($0) }
      .sorted { $0.key < $1.key }
      .reduce(into: [String: String]()) { partialResult, entry in
        partialResult[entry.key] = entry.value
      }
  }

  private func stringifyPreferenceValue(_ value: Any) -> String {
    switch value {
    case let string as String:
      return string
    case let number as NSNumber:
      return number.stringValue
    case let bool as Bool:
      return bool ? "true" : "false"
    case let array as [String]:
      return array.joined(separator: ",")
    case let data as Data:
      return "Data(\(data.count) bytes)"
    default:
      return String(describing: value)
    }
  }

  private func formattedSyncPerformanceCounterLines(for counters: [String: Int]) -> String {
    counters.keys.sorted().map { key in
      "- \(key): \(counters[key, default: 0])"
    }
    .joined(separator: "\n")
  }

  private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
  }

  private func writeREADME(for bundle: Phase0RedLineBaselineBundle, to url: URL) throws {
    let markdown = """
    # Phase 0 Red Line Freeze

    Exported at: \(Self.readmeFormatter.string(from: bundle.app.exportedAt))

    This bundle captures a regression baseline before deeper reminder metadata + note-source architecture work.

    Included:
    - `baseline.json`: semantic project/task/attachment summary
    - `regression-checklist.md`: manual regression checklist for major UI flows
    - `fixture-manifest.json`: machine-readable export manifest
    - `container/container.json`: storage manifest copy
    - `container/main.sqlite*`: database copy for fixture recovery
    - `project-task-attachment-index/`: cached task attachment aggregate state if present

    Summary:
    - Projects: \(bundle.projectCount)
    - Tasks: \(bundle.taskCount)
    - Attachments: \(bundle.attachmentCount)
    - Archived projects: \(bundle.archivedProjectCount)
    - Archived tasks: \(bundle.archivedTaskCount)
    - Conflicts logged: \(bundle.sync.conflictCount)

    Refresh diagnostics:
    \(formattedSyncPerformanceCounterLines(for: bundle.diagnostics.syncPerformanceCounters))
    """
    try markdown.write(to: url, atomically: true, encoding: .utf8)
  }

  private func writeRegressionChecklist(for bundle: Phase0RedLineBaselineBundle, to url: URL) throws {
    let largestProjects = bundle.projectsByTaskCountDescending.prefix(5)
    let largestProjectLines = largestProjects.map { project in
      "- [ ] \(project.title) (`tasks: \(project.taskCount)`, `done: \(project.completedTaskCount)`, `attachments: \(project.taskAttachmentCount + project.projectAttachmentCount)`)"
    }
    .joined(separator: "\n")

    let markdown = """
    # Regression Checklist

    Exported at: \(Self.readmeFormatter.string(from: bundle.app.exportedAt))

    ## Core Workspace
    - [ ] Setup launches without missing-container errors
    - [ ] Workspace search focuses and returns projects/tasks
    - [ ] View mode switching works for journal, timeline, schedule

    ## Project Window
    - [ ] Large project opens without hang
    - [ ] Task selection, title edit, note edit, block reason edit all work
    - [ ] Inline task detail open/close works
    - [ ] Drag and drop between projects works
    - [ ] Completed toggle and sorting work

    ## Timeline / Schedule / Journal
    - [ ] Timeline hover cards and date navigation work
    - [ ] Schedule selection, drag, resize, and scroll feel stable
    - [ ] Journal loading and detail surfaces work

    ## Reminder Metadata / Note Source / Persistence
    - [ ] Reminder metadata refresh and note-source parse/serialize run without new conflicts
    - [ ] Calendar mirrors still load
    - [ ] Project attachments and task attachments render correctly
    - [ ] Container can reopen from exported fixture database

    ## Priority Large Projects
    \(largestProjectLines.isEmpty ? "- [ ] No projects exported yet" : largestProjectLines)
    """
    try markdown.write(to: url, atomically: true, encoding: .utf8)
  }

  private func writeFixtureManifest(
    exportedAt: Date,
    exportDirectory: URL,
    containerExportDirectory: URL
  ) throws {
    let manifest = Phase0RedLineFixtureManifest(
      exportedAt: exportedAt,
      exportDirectory: exportDirectory.path,
      fixtureDatabaseDirectory: containerExportDirectory.path,
      exportedFiles: [
        .init(
          path: exportDirectory.appendingPathComponent("baseline.json").path,
          kind: "semantic-baseline",
          purpose: "Counts and representative summaries for regression comparison"
        ),
        .init(
          path: exportDirectory.appendingPathComponent("regression-checklist.md").path,
          kind: "manual-checklist",
          purpose: "Manual flow verification after later phases"
        ),
        .init(
          path: exportDirectory.appendingPathComponent("README.md").path,
          kind: "readme",
          purpose: "Human-readable description of the freeze bundle"
        ),
        .init(
          path: containerExportDirectory.appendingPathComponent("container.json").path,
          kind: "fixture-manifest",
          purpose: "Container manifest copy for fixture restoration"
        ),
        .init(
          path: containerExportDirectory.appendingPathComponent("main.sqlite").path,
          kind: "fixture-database",
          purpose: "SQLite fixture for regression recovery"
        ),
      ]
    )
    try writeJSON(manifest, to: exportDirectory.appendingPathComponent("fixture-manifest.json"))
  }

  private func copySQLiteArtifacts(from sqliteURL: URL, toDirectory directory: URL) throws {
    let baseName = sqliteURL.lastPathComponent
    let shmURL = sqliteURL.deletingLastPathComponent().appendingPathComponent("\(baseName)-shm")
    let walURL = sqliteURL.deletingLastPathComponent().appendingPathComponent("\(baseName)-wal")

    try copyIfExists(sqliteURL, to: directory.appendingPathComponent(baseName))
    try copyIfExists(shmURL, to: directory.appendingPathComponent(shmURL.lastPathComponent))
    try copyIfExists(walURL, to: directory.appendingPathComponent(walURL.lastPathComponent))
  }

  private func copyIfExists(_ source: URL, to destination: URL) throws {
    guard fileManager.fileExists(atPath: source.path) else { return }
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.copyItem(at: source, to: destination)
  }

  private func copyDirectoryIfExists(_ source: URL, to destination: URL) throws {
    guard fileManager.fileExists(atPath: source.path) else { return }
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.copyItem(at: source, to: destination)
  }

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return formatter
  }()

  private static let readmeFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
