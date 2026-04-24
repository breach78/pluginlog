import Foundation

@MainActor
final class ProjectDetailTaskListPerformanceRecorder {
  static let shared = ProjectDetailTaskListPerformanceRecorder()
  static let isEnabled = false

  static let currentPhase = "phase-task-list-perf-rich-detail-invalidate-drop"
  static let directoryURL = URL(fileURLWithPath: "/tmp/brain-unfog/project-detail-task-list", isDirectory: true)
  static let latestSummaryURL = directoryURL.appendingPathComponent("latest.json")
  static let historyDirectoryURL = directoryURL.appendingPathComponent("history", isDirectory: true)

  struct DiagnosisSnapshot: Codable {
    let projectID: String
    let tasks: Int
    let completed: Int
    let persistentTitleEditors: Int
    let liveReminderNoteEditors: Int
    let editingNoteHosts: Int
    let referenceLiveNoteHosts: Int
    let referenceFrozenNoteHosts: Int
    let visibleOpenNotes: Int
    let linkifiedTitles: Int
    let reminderNotes: Int
    let attachments: Int
    let visibleInlineDetails: Int
    let fixedVisibleDetailRows: Int
    let fixedCompactRows: Int
    let sort: String
    let showCompleted: Bool
    let candidates: [String]
  }

  struct SyncEvent {
    let elapsedMS: Int
    let rows: Int
    let mounted: Int
    let measured: Int
    let hostedViews: Int
    let pinned: Int
    let animated: Bool
    let fastPath: Bool
    let virtualizationPressure: Bool
  }

  struct RelayoutEvent {
    let elapsedMS: Int
    let rows: Int
    let mounted: Int
    let mountedRatio: Int
    let measured: Int
    let reused: Int
    let hostedViews: Int
    let animated: Bool
    let virtualizationPressure: Bool
    let reason: String
  }

  struct WindowSyncEvent {
    let elapsedMS: Int
    let rows: Int
    let mounted: Int
    let hostedViews: Int
    let instantMounted: Int
    let immediate: Bool
    let refreshedContent: Bool
    let virtualizationPressure: Bool
  }

  struct PrewarmEvent {
    let elapsedMS: Int
    let tasks: Int
    let titleHeightChanges: Int
    let blockHeightChanges: Int
    let noteHeightChanges: Int
    let detailHeightChanges: Int
    let primedDetails: Int
    let candidate: String
  }

  struct NumericSummary: Codable {
    let count: Int
    let averageMS: Double
    let p95MS: Int
    let maxMS: Int
  }

  struct SessionSummary: Codable {
    let schemaVersion: Int
    let phase: String
    let sessionID: String
    let projectID: String
    let flushReason: String
    let latestSummaryPath: String
    let historySummaryPath: String
    let processIdentifier: Int32
    let bundleIdentifier: String
    let startedAt: Date
    let updatedAt: Date
    let diagnosis: DiagnosisSnapshot?
    let sync: NumericSummary
    let relayout: NumericSummary
    let prewarm: NumericSummary
    let windowSync: NumericSummary
    let latestSync: SyncEventSnapshot?
    let latestRelayout: RelayoutEventSnapshot?
    let latestPrewarm: PrewarmEventSnapshot?
    let latestWindowSync: WindowSyncEventSnapshot?
  }

  struct SyncEventSnapshot: Codable {
    let elapsedMS: Int
    let rows: Int
    let mounted: Int
    let measured: Int
    let hostedViews: Int
    let pinned: Int
    let animated: Bool
    let fastPath: Bool
    let virtualizationPressure: Bool
  }

  struct RelayoutEventSnapshot: Codable {
    let elapsedMS: Int
    let rows: Int
    let mounted: Int
    let mountedRatio: Int
    let measured: Int
    let reused: Int
    let hostedViews: Int
    let animated: Bool
    let virtualizationPressure: Bool
    let reason: String
  }

  struct PrewarmEventSnapshot: Codable {
    let elapsedMS: Int
    let tasks: Int
    let titleHeightChanges: Int
    let blockHeightChanges: Int
    let noteHeightChanges: Int
    let detailHeightChanges: Int
    let primedDetails: Int
    let candidate: String
  }

  struct WindowSyncEventSnapshot: Codable {
    let elapsedMS: Int
    let rows: Int
    let mounted: Int
    let hostedViews: Int
    let instantMounted: Int
    let immediate: Bool
    let refreshedContent: Bool
    let virtualizationPressure: Bool
  }

  private struct Session {
    let startedAt: Date
    var updatedAt: Date
    var projectID: UUID
    var diagnosis: DiagnosisSnapshot?
    var syncEvents: [SyncEvent] = []
    var relayoutEvents: [RelayoutEvent] = []
    var prewarmEvents: [PrewarmEvent] = []
    var windowSyncEvents: [WindowSyncEvent] = []
  }

  private var sessions: [UUID: Session] = [:]
  private let fileManager = FileManager.default

  private init() {}

  func touchSession(_ sessionID: UUID, projectID: UUID) {
    guard Self.isEnabled else { return }
    if sessions[sessionID] == nil {
      sessions[sessionID] = Session(
        startedAt: .now,
        updatedAt: .now,
        projectID: projectID
      )
      return
    }
    sessions[sessionID]?.updatedAt = .now
    sessions[sessionID]?.projectID = projectID
  }

  func recordSync(
    sessionID: UUID,
    projectID: UUID,
    elapsedMS: Int,
    rows: Int,
    mounted: Int,
    measured: Int,
    hostedViews: Int,
    pinned: Int,
    animated: Bool,
    fastPath: Bool,
    virtualizationPressure: Bool
  ) {
    guard Self.isEnabled else { return }
    touchSession(sessionID, projectID: projectID)
    sessions[sessionID]?.syncEvents.append(
      SyncEvent(
        elapsedMS: elapsedMS,
        rows: rows,
        mounted: mounted,
        measured: measured,
        hostedViews: hostedViews,
        pinned: pinned,
        animated: animated,
        fastPath: fastPath,
        virtualizationPressure: virtualizationPressure
      )
    )
    sessions[sessionID]?.updatedAt = .now
  }

  func recordRelayout(
    sessionID: UUID,
    projectID: UUID,
    elapsedMS: Int,
    rows: Int,
    mounted: Int,
    mountedRatio: Int,
    measured: Int,
    reused: Int,
    hostedViews: Int,
    animated: Bool,
    virtualizationPressure: Bool,
    reason: String
  ) {
    guard Self.isEnabled else { return }
    touchSession(sessionID, projectID: projectID)
    sessions[sessionID]?.relayoutEvents.append(
      RelayoutEvent(
        elapsedMS: elapsedMS,
        rows: rows,
        mounted: mounted,
        mountedRatio: mountedRatio,
        measured: measured,
            reused: reused,
            hostedViews: hostedViews,
            animated: animated,
            virtualizationPressure: virtualizationPressure,
            reason: reason
          )
        )
    sessions[sessionID]?.updatedAt = .now
  }

  func recordPrewarm(
    sessionID: UUID,
    projectID: UUID,
    elapsedMS: Int,
    tasks: Int,
    titleHeightChanges: Int,
    blockHeightChanges: Int,
    noteHeightChanges: Int,
    detailHeightChanges: Int,
    primedDetails: Int,
    candidate: String
  ) {
    guard Self.isEnabled else { return }
    touchSession(sessionID, projectID: projectID)
    sessions[sessionID]?.prewarmEvents.append(
      PrewarmEvent(
        elapsedMS: elapsedMS,
        tasks: tasks,
        titleHeightChanges: titleHeightChanges,
        blockHeightChanges: blockHeightChanges,
        noteHeightChanges: noteHeightChanges,
        detailHeightChanges: detailHeightChanges,
        primedDetails: primedDetails,
        candidate: candidate
      )
    )
    sessions[sessionID]?.updatedAt = .now
  }

  func recordWindowSync(
    sessionID: UUID,
    projectID: UUID,
    elapsedMS: Int,
    rows: Int,
    mounted: Int,
    hostedViews: Int,
    instantMounted: Int,
    immediate: Bool,
    refreshedContent: Bool,
    virtualizationPressure: Bool
  ) {
    guard Self.isEnabled else { return }
    touchSession(sessionID, projectID: projectID)
    sessions[sessionID]?.windowSyncEvents.append(
      WindowSyncEvent(
        elapsedMS: elapsedMS,
        rows: rows,
        mounted: mounted,
        hostedViews: hostedViews,
        instantMounted: instantMounted,
        immediate: immediate,
        refreshedContent: refreshedContent,
        virtualizationPressure: virtualizationPressure
      )
    )
    sessions[sessionID]?.updatedAt = .now
  }

  func recordDiagnosis(
    sessionID: UUID,
    projectID: UUID,
    tasks: Int,
    completed: Int,
    persistentTitleEditors: Int,
    liveReminderNoteEditors: Int,
    editingNoteHosts: Int,
    referenceLiveNoteHosts: Int,
    referenceFrozenNoteHosts: Int,
    visibleOpenNotes: Int,
    linkifiedTitles: Int,
    reminderNotes: Int,
    attachments: Int,
    visibleInlineDetails: Int,
    fixedVisibleDetailRows: Int,
    fixedCompactRows: Int,
    sort: String,
    showCompleted: Bool,
    candidates: [String]
  ) {
    guard Self.isEnabled else { return }
    touchSession(sessionID, projectID: projectID)
    sessions[sessionID]?.diagnosis = DiagnosisSnapshot(
      projectID: projectID.uuidString,
      tasks: tasks,
      completed: completed,
      persistentTitleEditors: persistentTitleEditors,
      liveReminderNoteEditors: liveReminderNoteEditors,
      editingNoteHosts: editingNoteHosts,
      referenceLiveNoteHosts: referenceLiveNoteHosts,
      referenceFrozenNoteHosts: referenceFrozenNoteHosts,
      visibleOpenNotes: visibleOpenNotes,
      linkifiedTitles: linkifiedTitles,
      reminderNotes: reminderNotes,
      attachments: attachments,
      visibleInlineDetails: visibleInlineDetails,
      fixedVisibleDetailRows: fixedVisibleDetailRows,
      fixedCompactRows: fixedCompactRows,
      sort: sort,
      showCompleted: showCompleted,
      candidates: candidates
    )
    sessions[sessionID]?.updatedAt = .now
  }

  func flushSession(sessionID: UUID, reason: String) {
    guard Self.isEnabled else {
      sessions.removeValue(forKey: sessionID)
      return
    }
    guard let session = sessions.removeValue(forKey: sessionID) else { return }

    do {
      try fileManager.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
      try fileManager.createDirectory(at: Self.historyDirectoryURL, withIntermediateDirectories: true)

      let savedAt = Date()
      let historyURL = Self.historyDirectoryURL.appendingPathComponent(
        archiveFileName(for: session, sessionID: sessionID, savedAt: savedAt, reason: reason)
      )
      let summary = SessionSummary(
        schemaVersion: 1,
        phase: Self.currentPhase,
        sessionID: sessionID.uuidString,
        projectID: session.projectID.uuidString,
        flushReason: reason,
        latestSummaryPath: Self.latestSummaryURL.path,
        historySummaryPath: historyURL.path,
        processIdentifier: ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "BUF",
        startedAt: session.startedAt,
        updatedAt: session.updatedAt,
        diagnosis: session.diagnosis,
        sync: numericSummary(for: session.syncEvents.map(\.elapsedMS)),
        relayout: numericSummary(for: session.relayoutEvents.map(\.elapsedMS)),
        prewarm: numericSummary(for: session.prewarmEvents.map(\.elapsedMS)),
        windowSync: numericSummary(for: session.windowSyncEvents.map(\.elapsedMS)),
        latestSync: session.syncEvents.last.map {
          SyncEventSnapshot(
            elapsedMS: $0.elapsedMS,
            rows: $0.rows,
            mounted: $0.mounted,
            measured: $0.measured,
            hostedViews: $0.hostedViews,
            pinned: $0.pinned,
            animated: $0.animated,
            fastPath: $0.fastPath,
            virtualizationPressure: $0.virtualizationPressure
          )
        },
        latestRelayout: session.relayoutEvents.last.map {
          RelayoutEventSnapshot(
            elapsedMS: $0.elapsedMS,
            rows: $0.rows,
            mounted: $0.mounted,
            mountedRatio: $0.mountedRatio,
            measured: $0.measured,
            reused: $0.reused,
            hostedViews: $0.hostedViews,
            animated: $0.animated,
            virtualizationPressure: $0.virtualizationPressure,
            reason: $0.reason
          )
        },
        latestPrewarm: session.prewarmEvents.last.map {
          PrewarmEventSnapshot(
            elapsedMS: $0.elapsedMS,
            tasks: $0.tasks,
            titleHeightChanges: $0.titleHeightChanges,
            blockHeightChanges: $0.blockHeightChanges,
            noteHeightChanges: $0.noteHeightChanges,
            detailHeightChanges: $0.detailHeightChanges,
            primedDetails: $0.primedDetails,
            candidate: $0.candidate
          )
        },
        latestWindowSync: session.windowSyncEvents.last.map {
          WindowSyncEventSnapshot(
            elapsedMS: $0.elapsedMS,
            rows: $0.rows,
            mounted: $0.mounted,
            hostedViews: $0.hostedViews,
            instantMounted: $0.instantMounted,
            immediate: $0.immediate,
            refreshedContent: $0.refreshedContent,
            virtualizationPressure: $0.virtualizationPressure
          )
        }
      )

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(summary)
      try data.write(to: Self.latestSummaryURL, options: .atomic)
      try data.write(to: historyURL, options: .atomic)

      AppLogger.ui.info(
        "task-list perf summary saved project=\(session.projectID.uuidString, privacy: .public) reason=\(reason, privacy: .public) latest=\(Self.latestSummaryURL.path, privacy: .public)"
      )
    } catch {
      AppLogger.ui.error(
        "task-list perf summary save failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func archiveFileName(
    for session: Session,
    sessionID: UUID,
    savedAt: Date,
    reason: String
  ) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: savedAt).replacingOccurrences(of: ":", with: "-")
    let sanitizedReason = reason
      .replacingOccurrences(of: " ", with: "-")
      .replacingOccurrences(of: "/", with: "-")
    return "\(timestamp)-\(Self.currentPhase)-\(session.projectID.uuidString)-\(sessionID.uuidString)-\(sanitizedReason).json"
  }

  private func numericSummary(for values: [Int]) -> NumericSummary {
    guard !values.isEmpty else {
      return NumericSummary(count: 0, averageMS: 0, p95MS: 0, maxMS: 0)
    }
    let sortedValues = values.sorted()
    let total = values.reduce(0, +)
    let index = min(sortedValues.count - 1, Int(Double(sortedValues.count - 1) * 0.95))
    let average = Double(total) / Double(values.count)
    return NumericSummary(
      count: values.count,
      averageMS: (average * 100).rounded() / 100,
      p95MS: sortedValues[index],
      maxMS: sortedValues.last ?? 0
    )
  }
}
