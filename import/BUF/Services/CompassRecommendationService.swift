import Foundation
import SwiftData

enum CompassRecommendationServiceError: LocalizedError {
  case bootstrapRequired

  var errorDescription: String? {
    switch self {
    case .bootstrapRequired:
      return "나침반 자기모델이 아직 준비되지 않았다."
    }
  }
}

struct CompassWorkspaceProjectSnapshot: Identifiable, Hashable, Sendable {
  var id: UUID
  var title: String
  var colorHex: String?
  var updatedAt: Date
  var deadline: Date?
  var openTaskCount: Int
}

struct CompassWorkspaceTaskSnapshot: Identifiable, Hashable, Sendable {
  var id: UUID
  var projectID: UUID?
  var projectTitle: String?
  var title: String
  var dueDate: Date?
  var startDate: Date?
  var priority: Int
  var isFlagged: Bool
  var boardStage: BoardStage
  var importance: ImportanceLevel
  var requiredWorkDays: Int
  var completedWorkUnits: Int
  var localUpdatedAt: Date
  var createdAt: Date
  var scheduleHasExplicitTime: Bool
  var scheduledDurationMinutes: Int?
}

extension CompassWorkspaceTaskSnapshot {
  var reminderDate: Date? {
    ReminderTaskDateCanonicalizer.unifiedDate(dueDate: dueDate, startDate: startDate)
  }
}

struct CompassWorkspaceBehaviorMetrics: Hashable, Sendable {
  var historyWindowDays: Int
  var totalEventCount: Int
  var activeDayCount: Int
  var taskCreatedCount: Int
  var taskCompletedCount: Int
  var taskReopenedCount: Int
  var taskScheduleChangedCount: Int
  var taskMovedCount: Int
  var noteSavedCount: Int
  var attachmentAddedCount: Int
  var projectChangeCount: Int

  static let empty = CompassWorkspaceBehaviorMetrics(
    historyWindowDays: 14,
    totalEventCount: 0,
    activeDayCount: 0,
    taskCreatedCount: 0,
    taskCompletedCount: 0,
    taskReopenedCount: 0,
    taskScheduleChangedCount: 0,
    taskMovedCount: 0,
    noteSavedCount: 0,
    attachmentAddedCount: 0,
    projectChangeCount: 0
  )
}

struct CompassWorkspaceBehaviorDigest: Identifiable, Hashable, Sendable {
  var id: String
  var title: String
  var summary: String
  var confidence: CompassConfidence
  var evidence: [CompassEvidencePointer]

  init(
    id: String = UUID().uuidString,
    title: String,
    summary: String,
    confidence: CompassConfidence,
    evidence: [CompassEvidencePointer] = []
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.confidence = confidence
    self.evidence = evidence
  }
}

struct CompassWorkspaceTaskHistorySignal: Hashable, Sendable {
  var scheduleChangeCount: Int
  var reopenCount: Int
  var noteSaveCount: Int
  var isDormantSinceCreation: Bool

  init(
    scheduleChangeCount: Int = 0,
    reopenCount: Int = 0,
    noteSaveCount: Int = 0,
    isDormantSinceCreation: Bool = false
  ) {
    self.scheduleChangeCount = scheduleChangeCount
    self.reopenCount = reopenCount
    self.noteSaveCount = noteSaveCount
    self.isDormantSinceCreation = isDormantSinceCreation
  }
}

struct CompassWorkspaceSnapshot: Hashable, Sendable {
  var referenceDate: Date
  var projects: [CompassWorkspaceProjectSnapshot]
  var tasks: [CompassWorkspaceTaskSnapshot]
  var behaviorMetrics: CompassWorkspaceBehaviorMetrics
  var behaviorDigests: [CompassWorkspaceBehaviorDigest]
  var taskHistorySignals: [UUID: CompassWorkspaceTaskHistorySignal]

  init(
    referenceDate: Date,
    projects: [CompassWorkspaceProjectSnapshot],
    tasks: [CompassWorkspaceTaskSnapshot],
    behaviorMetrics: CompassWorkspaceBehaviorMetrics = .empty,
    behaviorDigests: [CompassWorkspaceBehaviorDigest] = [],
    taskHistorySignals: [UUID: CompassWorkspaceTaskHistorySignal] = [:]
  ) {
    self.referenceDate = referenceDate
    self.projects = projects
    self.tasks = tasks
    self.behaviorMetrics = behaviorMetrics
    self.behaviorDigests = behaviorDigests
    self.taskHistorySignals = taskHistorySignals
  }
}

@MainActor
protocol CompassWorkspaceProviding: AnyObject {
  func loadSnapshot(referenceDate: Date) throws -> CompassWorkspaceSnapshot
}

@MainActor
final class SwiftDataCompassWorkspaceProvider: CompassWorkspaceProviding {
  private let modelContainer: ModelContainer
  private let runtimeSnapshotProvider: @MainActor () -> OutlineProjectionRuntimeSnapshot?
  private let calendar: Calendar
  private let historyWindowDays: Int

  init(
    modelContainer: ModelContainer,
    runtimeSnapshotProvider: @escaping @MainActor () -> OutlineProjectionRuntimeSnapshot?,
    calendar: Calendar = .autoupdatingCurrent,
    historyWindowDays: Int = 14
  ) {
    self.modelContainer = modelContainer
    self.runtimeSnapshotProvider = runtimeSnapshotProvider
    self.calendar = calendar
    self.historyWindowDays = historyWindowDays
  }

  func loadSnapshot(referenceDate: Date) throws -> CompassWorkspaceSnapshot {
    let context = ModelContext(modelContainer)
    let referenceDay = calendar.startOfDay(for: referenceDate)
    let runtimeSnapshot = runtimeSnapshotProvider()
    let projectSnapshots = buildProjectSnapshots(from: runtimeSnapshot)
    let taskSnapshots = buildTaskSnapshots(
      from: runtimeSnapshot,
      projectSnapshots: projectSnapshots
    )
    let behavior = try buildBehaviorSnapshot(
      in: context,
      referenceDate: referenceDay,
      projects: projectSnapshots,
      tasks: taskSnapshots
    )

    return CompassWorkspaceSnapshot(
      referenceDate: referenceDay,
      projects: projectSnapshots,
      tasks: taskSnapshots,
      behaviorMetrics: behavior.metrics,
      behaviorDigests: behavior.digests,
      taskHistorySignals: behavior.taskHistorySignals
    )
  }

  private func buildProjectSnapshots(
    from runtimeSnapshot: OutlineProjectionRuntimeSnapshot?
  ) -> [CompassWorkspaceProjectSnapshot] {
    guard let runtimeSnapshot else { return [] }

    let projectIDs = runtimeSnapshot.projects.map(\.id)
    let projectRecords = WorkspaceProjectRuntimeRecordBuilder.records(
      from: runtimeSnapshot,
      projectIDs: projectIDs
    )
    let openTaskCounts = runtimeSnapshot.projects.reduce(into: [UUID: Int]()) { partialResult, project in
      partialResult[project.id] = project.document.flatten().reduce(into: 0) { count, entry in
        guard entry.node.type.isTask, !entry.node.type.isCompleted else { return }
        count += 1
      }
    }

    return runtimeSnapshot.projects.compactMap { project in
      guard let projectRecord = projectRecords[project.id] else { return nil }
      return CompassWorkspaceProjectSnapshot(
        id: project.id,
        title: projectRecord.title,
        colorHex: projectRecord.colorHex,
        updatedAt: projectRecord.updatedAt,
        deadline: projectRecord.localDeadline,
        openTaskCount: openTaskCounts[project.id] ?? 0
      )
    }
  }

  private func buildTaskSnapshots(
    from runtimeSnapshot: OutlineProjectionRuntimeSnapshot?,
    projectSnapshots: [CompassWorkspaceProjectSnapshot]
  ) -> [CompassWorkspaceTaskSnapshot] {
    guard let runtimeSnapshot else { return [] }

    let activeProjectIDs = Set(projectSnapshots.map(\.id))
    let projectRecords = WorkspaceProjectRuntimeRecordBuilder.records(
      from: runtimeSnapshot,
      projectIDs: Array(activeProjectIDs)
    )

    return runtimeSnapshot.projects.flatMap { project -> [CompassWorkspaceTaskSnapshot] in
      guard activeProjectIDs.contains(project.id) else { return [] }
      let projectRecord = projectRecords[project.id]
      return project.document.flatten().compactMap { entry in
        guard entry.node.type.isTask, !entry.node.type.isCompleted else { return nil }

        let reminderMetadata = runtimeSnapshot.reminderMetadata(for: entry.node)
        let reminderExternalIdentifier = normalized(entry.node.reminderExternalIdentifier)
        let featureSidecar = reminderExternalIdentifier.flatMap {
          runtimeSnapshot.taskFeatureSidecarByReminderExternalIdentifier[$0]
        }
        let remoteModifiedAt = reminderExternalIdentifier.flatMap {
          runtimeSnapshot.reminderModifiedAtByReminderExternalIdentifier[$0]
        }
        let localUpdatedAt = [
          featureSidecar?.updatedAt,
          remoteModifiedAt,
          projectRecord?.updatedAt,
        ]
        .compactMap { $0 }
        .max() ?? .distantPast
        let createdAt = featureSidecar?.createdAt ?? localUpdatedAt

        return CompassWorkspaceTaskSnapshot(
          id: entry.node.canonicalID,
          projectID: project.id,
          projectTitle: projectRecord?.title ?? project.title,
          title: entry.node.text,
          dueDate: reminderMetadata?.dueDate,
          startDate: nil,
          priority: max(0, min(9, reminderMetadata?.priority ?? 0)),
          isFlagged: featureSidecar?.isFlagged ?? false,
          boardStage: featureSidecar?.boardStageRaw.flatMap(BoardStage.init(rawValue:)) ?? .now,
          importance: featureSidecar?.importanceRaw.flatMap(ImportanceLevel.init(rawValue:)) ?? .minor,
          requiredWorkDays: max(0, featureSidecar?.requiredWorkDays ?? 0),
          completedWorkUnits: max(0, featureSidecar?.completedWorkUnits ?? 0),
          localUpdatedAt: localUpdatedAt,
          createdAt: createdAt,
          scheduleHasExplicitTime: reminderMetadata?.hasExplicitTime ?? false,
          scheduledDurationMinutes: featureSidecar?.scheduledDurationMinutes
        )
      }
    }
  }

  private func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private func buildBehaviorSnapshot(
    in context: ModelContext,
    referenceDate: Date,
    projects: [CompassWorkspaceProjectSnapshot],
    tasks: [CompassWorkspaceTaskSnapshot]
  ) throws -> CompassWorkspaceBehaviorSnapshot {
    let historyStart = calendar.date(byAdding: .day, value: -(historyWindowDays - 1), to: referenceDate)
      ?? referenceDate
    let historyDescriptor = FetchDescriptor<ProjectHistoryEvent>(
      predicate: #Predicate { $0.occurredAt >= historyStart },
      sortBy: [
        SortDescriptor(\.occurredAt, order: .reverse),
        SortDescriptor(\.createdAt, order: .reverse),
      ]
    )

    let activeProjectIDs = Set(projects.map(\.id))
    let recentEvents = try context.fetch(historyDescriptor)
      .filter { activeProjectIDs.contains($0.projectID) }
    let openTaskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    let projectByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })

    var taskSignals: [UUID: CompassWorkspaceTaskHistorySignal] = [:]
    var scheduleChangeEventsByTaskID: [UUID: [ProjectHistoryEvent]] = [:]
    var reopenEventsByTaskID: [UUID: [ProjectHistoryEvent]] = [:]
    var noteEventsByProjectID: [UUID: [ProjectHistoryEvent]] = [:]
    var completionEventsByProjectID: [UUID: [ProjectHistoryEvent]] = [:]
    var completionEvents: [ProjectHistoryEvent] = []

    for event in recentEvents {
      switch event.kind {
      case .taskCompleted:
        completionEvents.append(event)
        completionEventsByProjectID[event.projectID, default: []].append(event)
      case .projectNoteSaved, .taskReminderNoteSaved:
        noteEventsByProjectID[event.projectID, default: []].append(event)
      default:
        break
      }

      guard let taskID = event.taskID else { continue }
      var signal = taskSignals[taskID] ?? CompassWorkspaceTaskHistorySignal()
      switch event.kind {
      case .taskScheduleChanged:
        signal.scheduleChangeCount += 1
        scheduleChangeEventsByTaskID[taskID, default: []].append(event)
      case .taskReopened:
        signal.reopenCount += 1
        reopenEventsByTaskID[taskID, default: []].append(event)
      case .taskReminderNoteSaved:
        signal.noteSaveCount += 1
      default:
        break
      }
      taskSignals[taskID] = signal
    }

    for task in tasks {
      var signal = taskSignals[task.id] ?? CompassWorkspaceTaskHistorySignal()
      signal.isDormantSinceCreation = isDormant(task, referenceDate: referenceDate)
      taskSignals[task.id] = signal
    }

    let metrics = CompassWorkspaceBehaviorMetrics(
      historyWindowDays: historyWindowDays,
      totalEventCount: recentEvents.count,
      activeDayCount: Set(recentEvents.map { calendar.startOfDay(for: $0.occurredAt) }).count,
      taskCreatedCount: recentEvents.filter { $0.kind == .taskCreated }.count,
      taskCompletedCount: completionEvents.count,
      taskReopenedCount: recentEvents.filter { $0.kind == .taskReopened }.count,
      taskScheduleChangedCount: recentEvents.filter { $0.kind == .taskScheduleChanged }.count,
      taskMovedCount: recentEvents.filter { $0.kind == .taskMoved }.count,
      noteSavedCount: recentEvents.filter {
        $0.kind == .projectNoteSaved || $0.kind == .taskReminderNoteSaved
      }.count,
      attachmentAddedCount: recentEvents.filter { $0.kind == .attachmentAdded }.count,
      projectChangeCount: recentEvents.filter {
        $0.kind == .projectUpdated
          || $0.kind == .projectTimelineChanged
          || $0.kind == .projectArchived
          || $0.kind == .projectRestored
      }.count
    )

    var digests: [CompassWorkspaceBehaviorDigest] = []

    if completionEvents.count >= 2 {
      let titles = completionEvents.compactMap(\.taskTitleSnapshot)
      digests.append(
        CompassWorkspaceBehaviorDigest(
          id: "completion-momentum",
          title: "최근 마무리 흐름",
          summary:
            "최근 \(historyWindowDays)일 동안 \(completionEvents.count)개의 할일을 완료했다. 실제로 끝내는 흐름이 있는 영역을 오늘의 발판으로 삼는 편이 좋다\(titles.isEmpty ? "." : ": \(compassTitlePreview(from: titles)).")",
          confidence: completionEvents.count >= 4 ? .high : .medium,
          evidence: completionEvents.prefix(3).map(historyEvidence)
        )
      )
    }

    let repeatedScheduleTasks = taskSignals
      .filter { taskID, signal in
        signal.scheduleChangeCount >= 2 && openTaskByID[taskID] != nil
      }
      .sorted { lhs, rhs in
        if lhs.value.scheduleChangeCount == rhs.value.scheduleChangeCount {
          return (openTaskByID[lhs.key]?.localUpdatedAt ?? .distantPast)
            > (openTaskByID[rhs.key]?.localUpdatedAt ?? .distantPast)
        }
        return lhs.value.scheduleChangeCount > rhs.value.scheduleChangeCount
      }

    if !repeatedScheduleTasks.isEmpty {
      let taskTitles = repeatedScheduleTasks.compactMap { openTaskByID[$0.key]?.title }
      let evidence = repeatedScheduleTasks
        .flatMap { scheduleChangeEventsByTaskID[$0.key] ?? [] }
        .prefix(3)
        .map(historyEvidence)
      digests.append(
        CompassWorkspaceBehaviorDigest(
          id: "repeated-reschedule",
          title: "일정이 자주 다시 잡히는 일",
          summary:
            "\(compassTitlePreview(from: taskTitles)) 같은 일이 최근 \(historyWindowDays)일 동안 여러 번 다시 잡혔다. 중요하지만 계속 밀리거나 범위가 흔들리는 신호일 수 있다.",
          confidence: repeatedScheduleTasks.first?.value.scheduleChangeCount ?? 0 >= 3 ? .high : .medium,
          evidence: evidence
        )
      )
    }

    let reopenedTasks = taskSignals
      .filter { taskID, signal in
        signal.reopenCount > 0 && openTaskByID[taskID] != nil
      }
      .sorted { lhs, rhs in
        if lhs.value.reopenCount == rhs.value.reopenCount {
          return (openTaskByID[lhs.key]?.localUpdatedAt ?? .distantPast)
            > (openTaskByID[rhs.key]?.localUpdatedAt ?? .distantPast)
        }
        return lhs.value.reopenCount > rhs.value.reopenCount
      }

    if !reopenedTasks.isEmpty {
      let taskTitles = reopenedTasks.compactMap { openTaskByID[$0.key]?.title }
      let evidence = reopenedTasks
        .flatMap { reopenEventsByTaskID[$0.key] ?? [] }
        .prefix(3)
        .map(historyEvidence)
      digests.append(
        CompassWorkspaceBehaviorDigest(
          id: "reopened-work",
          title: "완료 기준이 흔들린 일",
          summary:
            "\(compassTitlePreview(from: taskTitles)) 같은 일이 한 번 닫혔다가 다시 열렸다. 완료 정의나 범위가 아직 안정되지 않았을 수 있다.",
          confidence: .medium,
          evidence: evidence
        )
      )
    }

    let dormantTasks = tasks.filter { taskSignals[$0.id]?.isDormantSinceCreation == true }
      .sorted { lhs, rhs in
        lhs.createdAt < rhs.createdAt
      }

    if !dormantTasks.isEmpty {
      digests.append(
        CompassWorkspaceBehaviorDigest(
          id: "created-but-idle",
          title: "만들어 두고 진전이 붙지 않은 일",
          summary:
            "\(compassTitlePreview(from: dormantTasks.map(\.title))) 같은 일이 생성된 뒤 실제 업데이트가 거의 붙지 않았다. 잊힌 일인지, 아직 범위가 안 잡힌 일인지 확인이 필요하다.",
          confidence: dormantTasks.count >= 3 ? .high : .medium,
          evidence: dormantTasks.prefix(3).map(taskSnapshotEvidence)
        )
      )
    }

    let noteHeavyProjects = projectByID.keys.compactMap { projectID -> CompassWorkspaceProjectSnapshot? in
      let noteCount = noteEventsByProjectID[projectID, default: []].count
      let completionCount = completionEventsByProjectID[projectID, default: []].count
      guard noteCount >= 3, completionCount == 0 else { return nil }
      return projectByID[projectID]
    }

    if !noteHeavyProjects.isEmpty {
      let evidence = noteHeavyProjects
        .flatMap { noteEventsByProjectID[$0.id] ?? [] }
        .prefix(3)
        .map(historyEvidence)
      digests.append(
        CompassWorkspaceBehaviorDigest(
          id: "note-heavy-no-completion",
          title: "메모는 늘었지만 완료가 붙지 않은 프로젝트",
          summary:
            "\(compassTitlePreview(from: noteHeavyProjects.map(\.title))) 쪽은 메모와 구상 활동은 많았지만 최근 완료 흐름이 없다. 생각과 실행을 다시 연결할 필요가 있다.",
          confidence: .medium,
          evidence: evidence
        )
      )
    }

    return CompassWorkspaceBehaviorSnapshot(
      metrics: metrics,
      digests: Array(digests.prefix(5)),
      taskHistorySignals: taskSignals
    )
  }

  private func isDormant(_ task: CompassWorkspaceTaskSnapshot, referenceDate: Date) -> Bool {
    let ageInDays = calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: task.createdAt),
      to: referenceDate
    ).day ?? 0
    guard ageInDays >= 3 else { return false }
    let untouchedSinceCreation = task.localUpdatedAt.timeIntervalSince(task.createdAt) < 12 * 3600
    return untouchedSinceCreation && task.completedWorkUnits == 0
  }

  private func taskSnapshotEvidence(for task: CompassWorkspaceTaskSnapshot) -> CompassEvidencePointer {
    CompassEvidencePointer(
      sourceKind: .task,
      sourceID: task.id.uuidString,
      dayKey: task.dueDate.map { CompassDateKeyCodec.dayKey(for: $0) },
      excerpt: task.title,
      recordedAt: task.localUpdatedAt,
      weight: 0.8
    )
  }

  private func historyEvidence(for event: ProjectHistoryEvent) -> CompassEvidencePointer {
    CompassEvidencePointer(
      sourceKind: .historyEvent,
      sourceID: event.id.uuidString,
      dayKey: CompassDateKeyCodec.dayKey(for: event.occurredAt),
      excerpt: event.detailTextSnapshot ?? event.taskTitleSnapshot ?? event.attachmentFilename,
      recordedAt: event.occurredAt,
      weight: 0.75
    )
  }
}

private struct CompassWorkspaceBehaviorSnapshot {
  let metrics: CompassWorkspaceBehaviorMetrics
  let digests: [CompassWorkspaceBehaviorDigest]
  let taskHistorySignals: [UUID: CompassWorkspaceTaskHistorySignal]
}

@MainActor
final class CompassRecommendationService {
  private let modelStore: CompassModelStore
  private let generator: any CompassGenerationServing
  private let workspaceProvider: any CompassWorkspaceProviding
  private let safetyService: CompassSafetyService
  private let calendar: Calendar

  init(
    modelStore: CompassModelStore,
    generator: any CompassGenerationServing,
    workspaceProvider: any CompassWorkspaceProviding,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.modelStore = modelStore
    self.generator = generator
    self.workspaceProvider = workspaceProvider
    self.safetyService = CompassSafetyService(modelStore: modelStore)
    self.calendar = calendar
  }

  func generateSnapshot(referenceDate: Date = .now) async throws -> CompassBoardSnapshot {
    guard let selfModel = try await modelStore.loadSelfModel() else {
      throw CompassRecommendationServiceError.bootstrapRequired
    }

    let workspace = try workspaceProvider.loadSnapshot(referenceDate: referenceDate)
    let recentDeltas = try await loadRecentDeltas(limit: 7)
    let recentDaySummaries = try await loadRecentDaySummaries(limit: 7)
    let candidateTasks = selectCandidateTasks(
      from: workspace.tasks,
      referenceDate: referenceDate,
      taskHistorySignals: workspace.taskHistorySignals
    )
    let evidenceHighlights = resolveEvidenceHighlights(
      selfModel: selfModel,
      daySummaries: recentDaySummaries,
      deltas: recentDeltas,
      behaviorDigests: workspace.behaviorDigests
    )

    let prompt = recommendationPrompt(
      selfModel: selfModel,
      workspace: workspace,
      candidateTasks: candidateTasks,
      recentDeltas: recentDeltas,
      recentDaySummaries: recentDaySummaries
    )

    if
      let result = await generator.generate(
        CompassGenerationRequest(prompt: prompt, profile: .recommendation)
      ),
      let response = decodeJSON(CompassRecommendationPromptResponse.self, from: result.text)
    {
      try await safetyService.recordUsage(phase: .recommendation, usage: result.usage)
      let analysisStatus = try await safetyService.loadAnalysisStatus()
      return resolvedSnapshot(
        from: response,
        selfModel: selfModel,
        workspace: workspace,
        evidenceHighlights: evidenceHighlights,
        analysisStatus: analysisStatus
      )
    }

    let analysisStatus = try await safetyService.loadAnalysisStatus()
    return fallbackSnapshot(
      selfModel: selfModel,
      workspace: workspace,
      evidenceHighlights: evidenceHighlights,
      referenceDate: referenceDate,
      analysisStatus: analysisStatus
    )
  }

  private func loadRecentDeltas(limit: Int) async throws -> [CompassDailyDelta] {
    let keys = try await modelStore.availableDailyDeltaKeys().suffix(limit)
    var deltas: [CompassDailyDelta] = []
    for key in keys {
      if let delta = try await modelStore.loadDailyDelta(for: key) {
        deltas.append(delta)
      }
    }
    return deltas.sorted { $0.dayKey < $1.dayKey }
  }

  private func loadRecentDaySummaries(limit: Int) async throws -> [CompassJournalDaySummary] {
    let keys = try await modelStore.availableDaySummaryKeys().suffix(limit)
    var summaries: [CompassJournalDaySummary] = []
    for key in keys {
      if let summary = try await modelStore.loadDaySummary(for: key) {
        summaries.append(summary)
      }
    }
    return summaries.sorted { $0.dayKey < $1.dayKey }
  }

  private func selectCandidateTasks(
    from tasks: [CompassWorkspaceTaskSnapshot],
    referenceDate: Date,
    taskHistorySignals: [UUID: CompassWorkspaceTaskHistorySignal]
  ) -> [CompassWorkspaceTaskSnapshot] {
    let today = calendar.startOfDay(for: referenceDate)
    return tasks
      .sorted { lhs, rhs in
        let leftScore = priorityScore(
          for: lhs,
          today: today,
          historySignal: taskHistorySignals[lhs.id]
        )
        let rightScore = priorityScore(
          for: rhs,
          today: today,
          historySignal: taskHistorySignals[rhs.id]
        )
        if leftScore == rightScore {
          if let leftDue = lhs.dueDate, let rightDue = rhs.dueDate, leftDue != rightDue {
            return leftDue < rightDue
          }
          return lhs.localUpdatedAt > rhs.localUpdatedAt
        }
        return leftScore > rightScore
      }
      .prefix(10)
      .map { $0 }
  }

  private func priorityScore(
    for task: CompassWorkspaceTaskSnapshot,
    today: Date,
    historySignal: CompassWorkspaceTaskHistorySignal?
  ) -> Int {
    var score = 0
    if task.isFlagged { score += 12 }
    score += min(max(task.priority, 0), 9)
    if task.importance == .important { score += 8 }
    if task.boardStage == .now { score += 6 }
    if let dueDate = task.reminderDate {
      let day = calendar.startOfDay(for: dueDate)
      if day < today {
        score += 20
      } else if calendar.isDate(day, inSameDayAs: today) {
        score += 16
      } else if let delta = calendar.dateComponents([.day], from: today, to: day).day, delta <= 2 {
        score += 10
      }
    }
    if let anchor = task.reminderDate,
      calendar.isDate(anchor, inSameDayAs: today)
    {
      score += 5
    }
    if task.requiredWorkDays > 0 {
      score += min(task.requiredWorkDays - task.completedWorkUnits, 4)
    }
    if let historySignal {
      if historySignal.scheduleChangeCount >= 2 {
        score += min(historySignal.scheduleChangeCount * 2, 6)
      }
      if historySignal.reopenCount > 0 {
        score += min(historySignal.reopenCount * 3, 5)
      }
      if historySignal.isDormantSinceCreation {
        score += 3
      }
    }
    return score
  }

  private func resolveEvidenceHighlights(
    selfModel: CompassSelfModel,
    daySummaries: [CompassJournalDaySummary],
    deltas: [CompassDailyDelta],
    behaviorDigests: [CompassWorkspaceBehaviorDigest]
  ) -> [CompassEvidencePointer] {
    var resolved: [CompassEvidencePointer] = []
    var seen: Set<String> = []

    let selfModelEvidence = (
      selfModel.currentSeason.flatMap(\.evidence)
      + selfModel.operationalTendencies.flatMap(\.evidence)
      + selfModel.blindSpots.flatMap(\.evidence)
      + selfModel.steeringRules.flatMap(\.evidence)
    )

    for pointer in selfModelEvidence {
      let key = "\(pointer.sourceKind.rawValue)|\(pointer.sourceID)|\(pointer.dayKey ?? "")"
      if seen.insert(key).inserted {
        resolved.append(pointer)
      }
      if resolved.count >= 4 {
        break
      }
    }

    for pointer in behaviorDigests.flatMap(\.evidence) {
      let key = "\(pointer.sourceKind.rawValue)|\(pointer.sourceID)|\(pointer.dayKey ?? "")"
      if seen.insert(key).inserted {
        resolved.append(pointer)
      }
      if resolved.count >= 6 {
        break
      }
    }

    let deltaDayKeys = Set(deltas.map(\.dayKey))
    for summary in daySummaries where deltaDayKeys.contains(summary.dayKey) {
      let pointer = CompassEvidencePointer(
        sourceKind: .journalDaySummary,
        sourceID: summary.dayKey,
        dayKey: summary.dayKey,
        excerpt: summary.summary,
        weight: 0.75
      )
      let key = "\(pointer.sourceKind.rawValue)|\(pointer.sourceID)|\(pointer.dayKey ?? "")"
      if seen.insert(key).inserted {
        resolved.append(pointer)
      }
      if resolved.count >= 8 {
        break
      }
    }

    return resolved
  }

  private func recommendationPrompt(
    selfModel: CompassSelfModel,
    workspace: CompassWorkspaceSnapshot,
    candidateTasks: [CompassWorkspaceTaskSnapshot],
    recentDeltas: [CompassDailyDelta],
    recentDaySummaries: [CompassJournalDaySummary]
  ) -> String {
    """
    너는 사용자의 오늘 실행을 정렬하는 나침반 대시보드 생성기다. 결과는 반드시 JSON만 반환하라.

    출력 스키마:
    {
      "northStar": {
        "title": "오늘의 방향 한 줄",
        "summary": "왜 이 방향이 중요한지 2~4문장",
        "workMode": "오늘의 작업 모드",
        "caution": "오늘 피해야 할 함정"
      },
      "priorities": [
        {
          "taskID": "기존 작업 UUID",
          "title": "작업명",
          "rationale": "오늘 이 작업을 미는 이유",
          "estimatedMinutes": 90
        }
      ],
      "missingSuggestions": [
        {
          "projectID": "관련 프로젝트 UUID 또는 null",
          "title": "빠진 일의 성격",
          "suggestedTaskTitle": "실제로 생성할 할일 제목",
          "rationale": "왜 빠진 일이라고 보는지"
        }
      ],
      "scheduleSuggestions": [
        {
          "title": "시간 블록 제목",
          "summary": "이 시간 배치의 의도",
          "startHour": 9,
          "startMinute": 30,
          "durationMinutes": 90,
          "taskIDs": ["작업 UUID"]
        }
      ],
      "patternInsights": [
        {
          "title": "패턴명",
          "summary": "최근 패턴 설명",
          "confidence": "high"
        }
      ]
    }

    제약:
    - 한국어
    - priorities는 최대 3개
    - missingSuggestions는 최대 3개
    - scheduleSuggestions는 최대 3개
    - patternInsights는 최대 4개
    - priorities의 taskID는 입력에 준 후보 task ID만 사용
    - missingSuggestions는 근거 없는 새 프로젝트를 만들지 말 것
    - 사용자를 단정하지 말고 최근 기록과 자기모델에 근거한 실행 판단을 할 것
    - recentBehaviorDigests는 앱 안에서 실제로 벌어진 생성/완료/재오픈/일정조정/메모 활동을 압축한 것이다. 저널과 함께 강한 근거로 사용할 것

    입력 JSON:
    \(encodedJSON(CompassRecommendationPromptPayload(
      selfModel: selfModel,
      workspace: workspace,
      candidateTasks: candidateTasks,
      recentDeltas: recentDeltas,
      recentDaySummaries: recentDaySummaries
    )))
    """
  }

  private func resolvedSnapshot(
    from response: CompassRecommendationPromptResponse,
    selfModel: CompassSelfModel,
    workspace: CompassWorkspaceSnapshot,
    evidenceHighlights: [CompassEvidencePointer],
    analysisStatus: CompassAnalysisStatus?
  ) -> CompassBoardSnapshot {
    let taskLookup = Dictionary(uniqueKeysWithValues: workspace.tasks.map { ($0.id.uuidString, $0) })
    let projectLookup = Dictionary(uniqueKeysWithValues: workspace.projects.map { ($0.id.uuidString, $0) })

    let priorities = (response.priorities ?? []).prefix(3).map { payload in
      let task = payload.taskID.flatMap { taskLookup[$0] }
      let evidence = task.map { [taskEvidence(for: $0)] } ?? []
      return CompassPriorityRecommendation(
        taskID: task?.id,
        projectID: task?.projectID,
        title: task?.title ?? payload.title,
        projectTitle: task?.projectTitle,
        rationale: normalizedText(payload.rationale),
        estimatedMinutes: payload.estimatedMinutes,
        dueDate: task?.dueDate,
        isOverdue: task.map { isOverdue($0, today: workspace.referenceDate) } ?? false,
        evidence: evidence
      )
    }

    let missingSuggestions = (response.missingSuggestions ?? []).prefix(3).map { payload in
      let project = payload.projectID.flatMap { projectLookup[$0] }
      let evidence = evidenceHighlights.prefix(2).map { $0 }
      return CompassMissingTaskSuggestion(
        projectID: project?.id,
        projectTitle: project?.title,
        title: payload.title,
        suggestedTaskTitle: payload.suggestedTaskTitle,
        rationale: normalizedText(payload.rationale),
        evidence: evidence
      )
    }

    let scheduleSuggestions = (response.scheduleSuggestions ?? []).prefix(3).map { payload in
      let taskIDs = (payload.taskIDs ?? []).compactMap { UUID(uuidString: $0) }
      return CompassScheduleSuggestion(
        title: payload.title,
        summary: normalizedText(payload.summary),
        startHour: payload.startHour,
        startMinute: payload.startMinute,
        durationMinutes: payload.durationMinutes ?? 60,
        taskIDs: taskIDs
      )
    }

    let aiPatternInsights = (response.patternInsights ?? []).map { payload in
      CompassPatternInsight(
        title: payload.title,
        summary: normalizedText(payload.summary),
        confidence: payload.confidence,
        evidence: evidenceHighlights
      )
    }
    let aiPatternTitles = Set(aiPatternInsights.map(\.title))
    let behaviorPatternInsights = workspace.behaviorDigests
      .filter { !aiPatternTitles.contains($0.title) }
      .map {
        CompassPatternInsight(
          title: $0.title,
          summary: $0.summary,
          confidence: $0.confidence,
          evidence: $0.evidence
        )
      }
    let patternInsights = Array((aiPatternInsights + behaviorPatternInsights).prefix(4))

    let northStar = CompassNorthStar(
      title: response.northStar?.title ?? "오늘의 북극성",
      summary: normalizedText(response.northStar?.summary ?? selfModel.overview),
      workMode: response.northStar?.workMode ?? "Focused Execution",
      caution: response.northStar?.caution
    )

    return CompassBoardSnapshot(
      generatedAt: .now,
      northStar: northStar,
      priorities: priorities,
      missingSuggestions: missingSuggestions,
      scheduleSuggestions: scheduleSuggestions,
      patternInsights: patternInsights,
      evidenceHighlights: evidenceHighlights,
      selfModelOverview: selfModel.overview,
      analysisStatus: analysisStatus
    )
  }

  private func fallbackSnapshot(
    selfModel: CompassSelfModel,
    workspace: CompassWorkspaceSnapshot,
    evidenceHighlights: [CompassEvidencePointer],
    referenceDate: Date,
    analysisStatus: CompassAnalysisStatus?
  ) -> CompassBoardSnapshot {
    let candidateTasks = selectCandidateTasks(
      from: workspace.tasks,
      referenceDate: referenceDate,
      taskHistorySignals: workspace.taskHistorySignals
    )
    let topTasks = Array(candidateTasks.prefix(3))
    let priorities = topTasks.map { task in
      CompassPriorityRecommendation(
        taskID: task.id,
        projectID: task.projectID,
        title: task.title,
        projectTitle: task.projectTitle,
        rationale: fallbackRationale(
          for: task,
          selfModel: selfModel,
          today: workspace.referenceDate,
          historySignal: workspace.taskHistorySignals[task.id]
        ),
        estimatedMinutes: task.scheduledDurationMinutes ?? inferredDuration(for: task, selfModel: selfModel),
        dueDate: task.dueDate,
        isOverdue: isOverdue(task, today: workspace.referenceDate),
        evidence: [taskEvidence(for: task)]
      )
    }

    let missingSuggestions = selfModel.blindSpots.prefix(2).map { blindSpot in
      CompassMissingTaskSuggestion(
        projectID: workspace.projects.first?.id,
        projectTitle: workspace.projects.first?.title,
        title: blindSpot.title,
        suggestedTaskTitle: "\(blindSpot.title) 점검",
        rationale: blindSpot.statement,
        evidence: blindSpot.evidence
      )
    }

    let scheduleSuggestions = makeFallbackScheduleSuggestions(
      for: topTasks,
      referenceDate: referenceDate,
      selfModel: selfModel
    )
    let activityInsights = workspace.behaviorDigests.map {
      CompassPatternInsight(
        title: $0.title,
        summary: $0.summary,
        confidence: $0.confidence,
        evidence: $0.evidence
      )
    }
    let modelInsights = (
      selfModel.currentSeason
      + selfModel.operationalTendencies
      + selfModel.blindSpots
    )
    .map {
      CompassPatternInsight(
        title: $0.title,
        summary: $0.statement,
        confidence: $0.confidence,
        evidence: $0.evidence
      )
    }
    let patternInsights = Array((activityInsights + modelInsights).prefix(4))

    let steeringRule = selfModel.steeringRules.first
    let northStar = CompassNorthStar(
      title: steeringRule?.title ?? "오늘의 북극성",
      summary: steeringRule?.instruction ?? selfModel.overview,
      workMode: inferredWorkMode(from: selfModel),
      caution: selfModel.blindSpots.first?.statement
    )

    return CompassBoardSnapshot(
      generatedAt: .now,
      northStar: northStar,
      priorities: priorities,
      missingSuggestions: Array(missingSuggestions),
      scheduleSuggestions: scheduleSuggestions,
      patternInsights: patternInsights,
      evidenceHighlights: evidenceHighlights,
      selfModelOverview: selfModel.overview,
      analysisStatus: analysisStatus
    )
  }

  private func makeFallbackScheduleSuggestions(
    for tasks: [CompassWorkspaceTaskSnapshot],
    referenceDate: Date,
    selfModel: CompassSelfModel
  ) -> [CompassScheduleSuggestion] {
    let seeds: [(Int, Int)] = [(9, 30), (13, 30), (16, 30)]
    return Array(tasks.prefix(3).enumerated()).map { index, task in
      let slot = seeds[min(index, seeds.count - 1)]
      return CompassScheduleSuggestion(
        title: index == 0 ? "첫 집중 블록" : "후속 실행 블록",
        summary: "\(task.title) 을(를) 실제 전진 단위로 끝낸다.",
        startHour: slot.0,
        startMinute: slot.1,
        durationMinutes: task.scheduledDurationMinutes ?? inferredDuration(for: task, selfModel: selfModel),
        taskIDs: [task.id]
      )
    }
  }

  private func fallbackRationale(
    for task: CompassWorkspaceTaskSnapshot,
    selfModel: CompassSelfModel,
    today: Date,
    historySignal: CompassWorkspaceTaskHistorySignal?
  ) -> String {
    if let historySignal, historySignal.scheduleChangeCount >= 2 {
      return "여러 번 다시 잡힌 일이라 이번에는 실제로 닫을 단위를 정해 밀어야 한다."
    }
    if let historySignal, historySignal.reopenCount > 0 {
      return "한 번 닫았다가 다시 열린 적이 있어 완료 기준과 범위를 다시 세우는 편이 좋다."
    }
    if let historySignal, historySignal.isDormantSinceCreation {
      return "만들어 둔 뒤 실제 진전이 거의 붙지 않은 일이라 잊히기 전에 다시 붙여야 한다."
    }
    if isOverdue(task, today: today) {
      return "이미 시한이 지났고, 지금 미루는 비용이 가장 크다."
    }
    if let dueDate = task.dueDate, calendar.isDate(dueDate, inSameDayAs: today) {
      return "오늘 일정과 직접 맞닿아 있어 오늘 안에 밀어야 한다."
    }
    if task.isFlagged || task.importance == .important {
      return "현재 시스템에서 중요 신호가 이미 높게 잡혀 있다."
    }
    if let schedulingPreference = selfModel.schedulingPreferences.first {
      return schedulingPreference.instruction
    }
    if let steering = selfModel.steeringRules.first {
      return steering.instruction
    }
    if let motivation = selfModel.motivationMap.first {
      return motivation.statement
    }
    return "최근 자기모델과 작업 후보를 기준으로 오늘 가장 전진 가능성이 높다."
  }

  private func inferredDuration(for task: CompassWorkspaceTaskSnapshot, selfModel: CompassSelfModel) -> Int {
    if let preferredBlock = selfModel.schedulingPreferences.first?.maxFocusBlockMinutes {
      return max(30, min(preferredBlock, 120))
    }
    if task.requiredWorkDays > 0 {
      return 75
    }
    if task.isFlagged || task.importance == .important {
      return 90
    }
    return 60
  }

  private func inferredWorkMode(from selfModel: CompassSelfModel) -> String {
    if let preference = selfModel.schedulingPreferences.first?.title, !preference.isEmpty {
      return preference
    }
    if let steering = selfModel.steeringRules.first?.title, !steering.isEmpty {
      return steering
    }
    if let motivation = selfModel.motivationMap.first?.title, !motivation.isEmpty {
      return motivation
    }
    if let tendency = selfModel.operationalTendencies.first?.title, !tendency.isEmpty {
      return tendency
    }
    return "Focused Execution"
  }

  private func isOverdue(_ task: CompassWorkspaceTaskSnapshot, today: Date) -> Bool {
    guard let dueDate = task.dueDate else { return false }
    return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: today)
  }

  private func taskEvidence(for task: CompassWorkspaceTaskSnapshot) -> CompassEvidencePointer {
    CompassEvidencePointer(
      sourceKind: .task,
      sourceID: task.id.uuidString,
      dayKey: task.dueDate.map { CompassDateKeyCodec.dayKey(for: $0) },
      excerpt: task.title,
      recordedAt: task.localUpdatedAt,
      weight: 0.8
    )
  }

  private func encodedJSON<Value: Encodable>(_ value: Value) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601

    guard let data = try? encoder.encode(value),
      let string = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return string
  }

  private func decodeJSON<Value: Decodable>(_ type: Value.Type, from text: String) -> Value? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var candidates = [trimmed]
    if let objectStart = trimmed.firstIndex(of: "{"), let objectEnd = trimmed.lastIndex(of: "}") {
      candidates.append(String(trimmed[objectStart...objectEnd]))
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    for candidate in candidates {
      guard let data = candidate.data(using: .utf8) else { continue }
      if let decoded = try? decoder.decode(Value.self, from: data) {
        return decoded
      }
    }

    return nil
  }

  private func normalizedText(_ text: String) -> String {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    return normalized.isEmpty ? "정리된 근거가 부족하다." : normalized
  }
}

private struct CompassRecommendationPromptPayload: Encodable {
  let referenceDate: Date
  let selfModel: CompassRecommendationPromptSelfModel
  let candidateTasks: [CompassRecommendationPromptTask]
  let projects: [CompassRecommendationPromptProject]
  let behaviorMetrics: CompassRecommendationPromptBehaviorMetrics
  let behaviorDigests: [CompassRecommendationPromptBehaviorDigest]
  let recentDeltas: [CompassRecommendationPromptDelta]
  let recentDaySummaries: [CompassRecommendationPromptDaySummary]

  init(
    selfModel: CompassSelfModel,
    workspace: CompassWorkspaceSnapshot,
    candidateTasks: [CompassWorkspaceTaskSnapshot],
    recentDeltas: [CompassDailyDelta],
    recentDaySummaries: [CompassJournalDaySummary]
  ) {
    referenceDate = workspace.referenceDate
    self.selfModel = CompassRecommendationPromptSelfModel(model: selfModel)
    self.candidateTasks = candidateTasks.map { CompassRecommendationPromptTask(task: $0) }
    self.projects = workspace.projects.map { CompassRecommendationPromptProject(project: $0) }
    self.behaviorMetrics = CompassRecommendationPromptBehaviorMetrics(metrics: workspace.behaviorMetrics)
    self.behaviorDigests = workspace.behaviorDigests.map {
      CompassRecommendationPromptBehaviorDigest(digest: $0)
    }
    self.recentDeltas = recentDeltas.map { CompassRecommendationPromptDelta(delta: $0) }
    self.recentDaySummaries = recentDaySummaries.map {
      CompassRecommendationPromptDaySummary(summary: $0)
    }
  }
}

private struct CompassRecommendationPromptSelfModel: Encodable {
  let overview: String
  let currentSeason: [CompassRecommendationPromptHypothesis]
  let operationalTendencies: [CompassRecommendationPromptHypothesis]
  let blindSpots: [CompassRecommendationPromptHypothesis]
  let steeringRules: [CompassRecommendationPromptRule]
  let motivationMap: [CompassRecommendationPromptMotivation]
  let schedulingPreferences: [CompassRecommendationPromptSchedulingPreference]
  let recommendationGuardrails: [CompassRecommendationPromptGuardrail]

  init(model: CompassSelfModel) {
    overview = model.overview
    currentSeason = model.currentSeason.map { CompassRecommendationPromptHypothesis(hypothesis: $0) }
    operationalTendencies = model.operationalTendencies.map {
      CompassRecommendationPromptHypothesis(hypothesis: $0)
    }
    blindSpots = model.blindSpots.map { CompassRecommendationPromptHypothesis(hypothesis: $0) }
    steeringRules = model.steeringRules.map { CompassRecommendationPromptRule(rule: $0) }
    motivationMap = model.motivationMap.map { CompassRecommendationPromptMotivation(signal: $0) }
    schedulingPreferences = model.schedulingPreferences.map {
      CompassRecommendationPromptSchedulingPreference(preference: $0)
    }
    recommendationGuardrails = model.recommendationGuardrails.map {
      CompassRecommendationPromptGuardrail(guardrail: $0)
    }
  }
}

private struct CompassRecommendationPromptHypothesis: Encodable {
  let axis: CompassInsightAxis
  let title: String
  let statement: String
  let confidence: CompassConfidence

  init(hypothesis: CompassHypothesis) {
    axis = hypothesis.axis
    title = hypothesis.title
    statement = hypothesis.statement
    confidence = hypothesis.confidence
  }
}

private struct CompassRecommendationPromptRule: Encodable {
  let title: String
  let instruction: String
  let rationale: String
  let confidence: CompassConfidence

  init(rule: CompassSteeringRule) {
    title = rule.title
    instruction = rule.instruction
    rationale = rule.rationale
    confidence = rule.confidence
  }
}

private struct CompassRecommendationPromptMotivation: Encodable {
  let axis: CompassInsightAxis
  let title: String
  let statement: String
  let confidence: CompassConfidence

  init(signal: CompassMotivationSignal) {
    axis = signal.axis
    title = signal.title
    statement = signal.statement
    confidence = signal.confidence
  }
}

private struct CompassRecommendationPromptSchedulingPreference: Encodable {
  let title: String
  let instruction: String
  let preferredWindow: CompassSchedulingWindow
  let maxFocusBlockMinutes: Int?
  let confidence: CompassConfidence

  init(preference: CompassSchedulingPreference) {
    title = preference.title
    instruction = preference.instruction
    preferredWindow = preference.preferredWindow
    maxFocusBlockMinutes = preference.maxFocusBlockMinutes
    confidence = preference.confidence
  }
}

private struct CompassRecommendationPromptGuardrail: Encodable {
  let title: String
  let rule: String
  let severity: CompassGuardrailSeverity
  let confidence: CompassConfidence

  init(guardrail: CompassRecommendationGuardrail) {
    title = guardrail.title
    rule = guardrail.rule
    severity = guardrail.severity
    confidence = guardrail.confidence
  }
}

private struct CompassRecommendationPromptTask: Encodable {
  let taskID: String
  let projectID: String?
  let projectTitle: String?
  let title: String
  let dueDate: Date?
  let startDate: Date?
  let priority: Int
  let isFlagged: Bool
  let boardStage: String
  let importance: String
  let requiredWorkDays: Int
  let completedWorkUnits: Int
  let localUpdatedAt: Date
  let scheduleHasExplicitTime: Bool
  let scheduledDurationMinutes: Int?

  init(task: CompassWorkspaceTaskSnapshot) {
    taskID = task.id.uuidString
    projectID = task.projectID?.uuidString
    projectTitle = task.projectTitle
    title = task.title
    dueDate = task.dueDate
    startDate = task.startDate
    priority = task.priority
    isFlagged = task.isFlagged
    boardStage = task.boardStage.rawValue
    importance = task.importance.rawValue
    requiredWorkDays = task.requiredWorkDays
    completedWorkUnits = task.completedWorkUnits
    localUpdatedAt = task.localUpdatedAt
    scheduleHasExplicitTime = task.scheduleHasExplicitTime
    scheduledDurationMinutes = task.scheduledDurationMinutes
  }
}

private struct CompassRecommendationPromptProject: Encodable {
  let projectID: String
  let title: String
  let deadline: Date?
  let openTaskCount: Int

  init(project: CompassWorkspaceProjectSnapshot) {
    projectID = project.id.uuidString
    title = project.title
    deadline = project.deadline
    openTaskCount = project.openTaskCount
  }
}

private struct CompassRecommendationPromptBehaviorMetrics: Encodable {
  let historyWindowDays: Int
  let totalEventCount: Int
  let activeDayCount: Int
  let taskCreatedCount: Int
  let taskCompletedCount: Int
  let taskReopenedCount: Int
  let taskScheduleChangedCount: Int
  let taskMovedCount: Int
  let noteSavedCount: Int
  let attachmentAddedCount: Int
  let projectChangeCount: Int

  init(metrics: CompassWorkspaceBehaviorMetrics) {
    historyWindowDays = metrics.historyWindowDays
    totalEventCount = metrics.totalEventCount
    activeDayCount = metrics.activeDayCount
    taskCreatedCount = metrics.taskCreatedCount
    taskCompletedCount = metrics.taskCompletedCount
    taskReopenedCount = metrics.taskReopenedCount
    taskScheduleChangedCount = metrics.taskScheduleChangedCount
    taskMovedCount = metrics.taskMovedCount
    noteSavedCount = metrics.noteSavedCount
    attachmentAddedCount = metrics.attachmentAddedCount
    projectChangeCount = metrics.projectChangeCount
  }
}

private struct CompassRecommendationPromptBehaviorDigest: Encodable {
  let title: String
  let summary: String
  let confidence: CompassConfidence

  init(digest: CompassWorkspaceBehaviorDigest) {
    title = digest.title
    summary = digest.summary
    confidence = digest.confidence
  }
}

private struct CompassRecommendationPromptDelta: Encodable {
  let dayKey: String
  let summary: String

  init(delta: CompassDailyDelta) {
    dayKey = delta.dayKey
    summary = delta.summary
  }
}

private struct CompassRecommendationPromptDaySummary: Encodable {
  let dayKey: String
  let summary: String
  let highlights: [String]

  init(summary: CompassJournalDaySummary) {
    dayKey = summary.dayKey
    self.summary = summary.summary
    highlights = summary.highlights
  }
}

private struct CompassRecommendationPromptResponse: Decodable {
  let northStar: CompassRecommendationPromptNorthStar?
  let priorities: [CompassRecommendationPromptPriority]?
  let missingSuggestions: [CompassRecommendationPromptMissingSuggestion]?
  let scheduleSuggestions: [CompassRecommendationPromptSchedule]?
  let patternInsights: [CompassRecommendationPromptPattern]?
}

private struct CompassRecommendationPromptNorthStar: Decodable {
  let title: String
  let summary: String
  let workMode: String
  let caution: String?
}

private struct CompassRecommendationPromptPriority: Decodable {
  let taskID: String?
  let title: String
  let rationale: String
  let estimatedMinutes: Int?
}

private struct CompassRecommendationPromptMissingSuggestion: Decodable {
  let projectID: String?
  let title: String
  let suggestedTaskTitle: String
  let rationale: String
}

private struct CompassRecommendationPromptSchedule: Decodable {
  let title: String
  let summary: String
  let startHour: Int?
  let startMinute: Int?
  let durationMinutes: Int?
  let taskIDs: [String]?
}

private struct CompassRecommendationPromptPattern: Decodable {
  let title: String
  let summary: String
  let confidence: CompassConfidence
}

private func compassTitlePreview(from titles: [String], limit: Int = 2) -> String {
  let normalized = titles
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  guard !normalized.isEmpty else { return "이 일들" }
  let preview = normalized.prefix(limit).joined(separator: ", ")
  let remainder = normalized.count - min(normalized.count, limit)
  if remainder > 0 {
    return "\(preview) 외 \(remainder)개"
  }
  return preview
}
