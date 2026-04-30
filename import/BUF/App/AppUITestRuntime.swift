import Foundation

enum AppUITestRuntime {
  static let modeEnvironmentKey = "BRAIN_UNFOG_UI_TEST_MODE"
  static let rootEnvironmentKey = "BRAIN_UNFOG_UI_TEST_ROOT"
  static let resetEnvironmentKey = "BRAIN_UNFOG_UI_TEST_RESET"
  static let modeArgument = "--ui-test-mode"
  static let rootArgument = "--ui-test-root"
  static let resetArgument = "--ui-test-reset"

  struct Configuration {
    let rootURL: URL
    let vaultRootURL: URL
    let containerRootURL: URL
    let shouldReset: Bool
    let seed: Seed

    init?(
      environment: [String: String] = ProcessInfo.processInfo.environment,
      arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
      let isModeEnabled =
        Self.isEnabled(environment[AppUITestRuntime.modeEnvironmentKey])
        || arguments.contains(AppUITestRuntime.modeArgument)
      guard isModeEnabled else { return nil }
      let rootURL = Self.rootURL(
        from: environment[AppUITestRuntime.rootEnvironmentKey]
          ?? Self.argumentValue(after: AppUITestRuntime.rootArgument, in: arguments)
      )
      self.rootURL = rootURL
      self.vaultRootURL = rootURL.appendingPathComponent("vault", isDirectory: true)
      self.containerRootURL = rootURL.appendingPathComponent("container", isDirectory: true)
      self.shouldReset =
        Self.isEnabled(environment[AppUITestRuntime.resetEnvironmentKey])
        || arguments.contains(AppUITestRuntime.resetArgument)
      self.seed = .default
    }

    var userDefaults: UserDefaults {
      let suiteName = "com.brainunfog.app.ui-test-runtime"
      let defaults = UserDefaults(suiteName: suiteName) ?? .standard
      if shouldReset {
        defaults.removePersistentDomain(forName: suiteName)
      }
      return defaults
    }

    private static func isEnabled(_ value: String?) -> Bool {
      switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "1", "true", "yes", "on":
        true
      default:
        false
      }
    }

    private static func rootURL(from rawPath: String?) -> URL {
      if let rawPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rawPath.isEmpty
      {
        return URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
      }
      return FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("Brain Unfog", isDirectory: true)
        .appendingPathComponent("UI Test Runtime", isDirectory: true)
        .standardizedFileURL
    }

    private static func argumentValue(after name: String, in arguments: [String]) -> String? {
      guard let index = arguments.firstIndex(of: name) else { return nil }
      let valueIndex = arguments.index(after: index)
      guard valueIndex < arguments.endIndex else { return nil }
      return arguments[valueIndex]
    }
  }

  struct Seed {
    let projects: [Project]

    static let `default` = Seed(projects: [
      Project(
        listIdentifier: "ui-test-list",
        title: "UI 테스트 리스트",
        colorHex: "#5856D6",
        tasks: [
          Task(
            externalIdentifier: "ui-test-task-1",
            title: "UI 테스트 할일",
            noteText: "테스트 모드에서 자유롭게 수정해도 실제 리마인더에는 반영되지 않습니다.",
            isCompleted: false,
            encodedDate: "2026-04-30",
            durationMinutes: nil
          ),
          Task(
            externalIdentifier: "ui-test-task-2",
            title: "시간 테스트 할일",
            noteText: "시간, 날짜, 제목, 완료 상태 테스트용 할일입니다.",
            isCompleted: false,
            encodedDate: "2026-04-30 09:00",
            durationMinutes: 30
          ),
          Task(
            externalIdentifier: "ui-test-task-3",
            title: "완료된 테스트 할일",
            noteText: "",
            isCompleted: true,
            encodedDate: nil,
            durationMinutes: nil
          ),
        ]
      ),
      Project(
        listIdentifier: "schedule-test-list",
        title: "일정 테스트 리스트",
        colorHex: "#34C759",
        tasks: [
          Task(
            externalIdentifier: "schedule-test-task-1",
            title: "드래그 일정 테스트",
            noteText: "스케줄 뷰 드래그 테스트용입니다.",
            isCompleted: false,
            encodedDate: "2026-05-01 10:00",
            durationMinutes: 45
          ),
          Task(
            externalIdentifier: "schedule-test-task-2",
            title: "올데이 테스트",
            noteText: "",
            isCompleted: false,
            encodedDate: "2026-05-01",
            durationMinutes: nil
          ),
        ]
      ),
    ])
  }

  struct Project {
    let listIdentifier: String
    let title: String
    let colorHex: String?
    let tasks: [Task]
  }

  struct Task {
    let externalIdentifier: String
    let title: String
    let noteText: String
    let isCompleted: Bool
    let encodedDate: String?
    let durationMinutes: Int?

    var schedule: ReminderScheduleMetadataCodec.DecodedDate? {
      ReminderScheduleMetadataCodec.decodeDate(encodedDate)
    }
  }

  @MainActor
  static func prepare(
    configuration: Configuration,
    storageCoordinator: LocalStorageCoordinator,
    reminderProjectProvider: ReminderProjectProvider
  ) async throws {
    if configuration.shouldReset {
      try? FileManager.default.removeItem(at: configuration.rootURL)
    }

    try prepareSeedVault(configuration: configuration)
    try await storageCoordinator.openOrInitializeContainer(at: configuration.containerRootURL)
    installRetainedStores(dataDirectory: storageCoordinator.paths?.dataDirectory)
    replaceBridgeRecords(seed: configuration.seed)
    upsertBaselines(seed: configuration.seed)
    if let provider = reminderProjectProvider as? UITestReminderProjectProvider {
      provider.reset(seed: configuration.seed)
    }
  }

  private static func prepareSeedVault(configuration: Configuration) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: configuration.vaultRootURL.appendingPathComponent(".obsidian", isDirectory: true),
      withIntermediateDirectories: true
    )
    let projectsRootURL = configuration.vaultRootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try fileManager.createDirectory(at: projectsRootURL, withIntermediateDirectories: true)

    for project in configuration.seed.projects {
      let fileURL = projectsRootURL.appendingPathComponent("\(project.title).md")
      guard configuration.shouldReset || !fileManager.fileExists(atPath: fileURL.path) else {
        continue
      }
      try markdown(for: project).write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  private static func markdown(for project: Project) -> String {
    let tasks = project.tasks.map { task in
      var metadata: [String] = [#""reminder_external_id":"\#(task.externalIdentifier)""#]
      if let schedule = task.schedule {
        let day = ReminderScheduleMetadataCodec.encodeDate(
          schedule.date,
          hasExplicitTime: false
        )
        if let day {
          metadata.append(#""date":"\#(day)""#)
        }
        if schedule.hasExplicitTime {
          let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute],
            from: schedule.date
          )
          let hour = String(format: "%02d", components.hour ?? 0)
          let minute = String(format: "%02d", components.minute ?? 0)
          metadata.append(#""time":"\#(hour):\#(minute)""#)
        }
      }
      if let durationMinutes = task.durationMinutes {
        metadata.append(#""duration":\#(durationMinutes)"#)
      }
      return """
      - [\(task.isCompleted ? "x" : " ")] \(task.title)
        %% brain-unfog: {\(metadata.joined(separator: ","))} %%
      """
    }

    return """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: \(project.listIdentifier)
    ---

    \(tasks.joined(separator: "\n"))
    """
  }

  private static func installRetainedStores(dataDirectory: URL?) {
    TaskIdentityBridgeStore.install(dataDirectory: dataDirectory)
    ReminderPendingBindingStore.install(dataDirectory: dataDirectory)
    ReminderDeletedTaskTombstoneStore.install(dataDirectory: dataDirectory)
    ReminderSyncBaselineStore.install(dataDirectory: dataDirectory)
  }

  private static func replaceBridgeRecords(seed: Seed) {
    var projectRecords: [ProjectIdentityBridgeRecord] = []
    var taskRecords: [TaskIdentityBridgeRecord] = []
    for project in seed.projects {
      let projectID = RetainedProjectionBuilder.derivedProjectID(for: project.listIdentifier)
      projectRecords.append(
        ProjectIdentityBridgeRecord(
          projectID: projectID,
          title: project.title,
          reminderListExternalIdentifier: project.listIdentifier,
          createdAt: .now,
          updatedAt: .now
        )
      )
      for task in project.tasks {
        taskRecords.append(
          TaskIdentityBridgeRecord(
            taskID: ReminderProjectionIdentity.taskID(for: task.externalIdentifier),
            title: task.title,
            reminderExternalIdentifier: task.externalIdentifier,
            ownerProjectID: projectID,
            createdAt: .now,
            updatedAt: .now
          )
        )
      }
    }
    TaskIdentityBridgeStore.replaceAll(projects: projectRecords, tasks: taskRecords)
  }

  private static func upsertBaselines(seed: Seed) {
    for project in seed.projects {
      for task in project.tasks {
        ReminderSyncBaselineStore.upsert(
          reminderExternalIdentifier: task.externalIdentifier,
          state: ReminderSyncTaskState(
            title: task.title,
            isCompleted: task.isCompleted,
            date: task.encodedDate,
            repeatRule: nil,
            noteText: task.noteText
          ),
          remoteModifiedAt: .now
        )
      }
    }
  }
}

@MainActor
extension AppState {
  func launchUITestRuntime(configuration: AppUITestRuntime.Configuration) async {
    do {
      applySetupPendingState()
      try await AppUITestRuntime.prepare(
        configuration: configuration,
        storageCoordinator: storageCoordinator,
        reminderProjectProvider: reminderProjectProvider
      )
      refreshContainerRootURL()
      obsidianVaultRootURL = configuration.vaultRootURL
      hasInitialSyncConsent = false
      hasSyncConsentDecision = true
      includeCompletedSyncEnabled = true
      await prepareWorkspaceIfSetupComplete(
        shouldRefreshHealth: true,
        startStartupSync: false
      )
      syncStatus = "UI Test Ready"
    } catch {
      reportError(error, logMessage: "launchUITestRuntime failed")
      syncStatus = "UI test setup failed"
    }
  }
}

@MainActor
final class UITestReminderProjectProvider: ReminderProjectProvider {
  private struct TaskRecord {
    var identifier: String
    var externalIdentifier: String
    var listIdentifier: String
    var title: String
    var noteText: String
    var isCompleted: Bool
    var completionDate: Date?
    var dueDate: Date?
    var hasExplicitTime: Bool
    var durationMinutes: Int?
    var priority: Int
    var recurrenceRuleRaw: String?
    var modifiedAt: Date
  }

  private var listsByIdentifier: [String: ReminderProjectListSnapshot] = [:]
  private var listOrder: [String] = []
  private var tasksByExternalIdentifier: [String: TaskRecord] = [:]
  private(set) var createdTaskCount = 0
  private var writeClock: TimeInterval = 1_700_000_000

  init(seed: AppUITestRuntime.Seed) {
    reset(seed: seed)
  }

  var reminderGateway: ReminderGateway? { nil }
  var defaultCalendarIdentifierForNewReminders: String? { listOrder.first }

  func reset(seed: AppUITestRuntime.Seed) {
    listsByIdentifier = [:]
    listOrder = []
    tasksByExternalIdentifier = [:]
    createdTaskCount = 0
    for project in seed.projects {
      listsByIdentifier[project.listIdentifier] = ReminderProjectListSnapshot(
        identifier: project.listIdentifier,
        externalIdentifier: project.listIdentifier,
        title: project.title,
        colorHex: project.colorHex
      )
      listOrder.append(project.listIdentifier)
      for task in project.tasks {
        let schedule = task.schedule
        tasksByExternalIdentifier[task.externalIdentifier] = TaskRecord(
          identifier: task.externalIdentifier,
          externalIdentifier: task.externalIdentifier,
          listIdentifier: project.listIdentifier,
          title: task.title,
          noteText: task.noteText,
          isCompleted: task.isCompleted,
          completionDate: task.isCompleted ? nextModifiedAt() : nil,
          dueDate: schedule?.date,
          hasExplicitTime: schedule?.hasExplicitTime ?? false,
          durationMinutes: task.durationMinutes,
          priority: 0,
          recurrenceRuleRaw: nil,
          modifiedAt: nextModifiedAt()
        )
      }
    }
  }

  func requestAccess() async throws -> Bool { true }

  func fetchProjectListsInCurrentOrder() async throws -> [ReminderProjectListSnapshot] {
    listOrder.compactMap { listsByIdentifier[$0] }
  }

  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch? {
    let requested = Set(identifiers)
    let lists = listOrder.compactMap { listID -> ReminderListImportSnapshot? in
      guard requested.isEmpty || requested.contains(listID),
        let list = listsByIdentifier[listID]
      else {
        return nil
      }
      return ReminderListImportSnapshot(
        identifier: list.identifier,
        externalIdentifier: list.externalIdentifier,
        title: list.title,
        colorHex: list.colorHex
      )
    }
    let itemsByListIdentifier = Dictionary(
      grouping: tasksByExternalIdentifier.values.filter { task in
        requested.isEmpty || requested.contains(task.listIdentifier)
      },
      by: \.listIdentifier
    ).mapValues { tasks in
      tasks
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        .map(importSnapshot)
    }
    return ReminderImportSnapshotBatch(lists: lists, itemsByListIdentifier: itemsByListIdentifier)
  }

  func createProjectList(title: String) throws -> ReminderProjectListSnapshot {
    let identifier = "ui-test-list-created-\(listsByIdentifier.count + 1)"
    let snapshot = ReminderProjectListSnapshot(
      identifier: identifier,
      externalIdentifier: identifier,
      title: title,
      colorHex: nil
    )
    listsByIdentifier[identifier] = snapshot
    listOrder.append(identifier)
    return snapshot
  }

  func removeProjectList(identifier: String) throws {
    listsByIdentifier.removeValue(forKey: identifier)
    listOrder.removeAll { $0 == identifier }
    tasksByExternalIdentifier = tasksByExternalIdentifier.filter { $0.value.listIdentifier != identifier }
  }

  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot? {
    guard let list = listsByIdentifier[identifier] else { return nil }
    let next = ReminderProjectListSnapshot(
      identifier: list.identifier,
      externalIdentifier: list.externalIdentifier,
      title: title,
      colorHex: list.colorHex
    )
    listsByIdentifier[identifier] = next
    return next
  }

  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot? {
    guard let list = listsByIdentifier[identifier] else { return nil }
    let next = ReminderProjectListSnapshot(
      identifier: list.identifier,
      externalIdentifier: list.externalIdentifier,
      title: list.title,
      colorHex: colorHex
    )
    listsByIdentifier[identifier] = next
    return next
  }

  func createTaskReminder(
    inProject identifier: String,
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    guard listsByIdentifier[identifier] != nil else { return nil }
    createdTaskCount += 1
    let externalIdentifier = "ui-test-created-task-\(createdTaskCount)"
    tasksByExternalIdentifier[externalIdentifier] = TaskRecord(
      identifier: externalIdentifier,
      externalIdentifier: externalIdentifier,
      listIdentifier: identifier,
      title: title,
      noteText: ReminderNoteSourceCodec.normalize(noteText),
      isCompleted: false,
      completionDate: nil,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      durationMinutes: nil,
      priority: 0,
      recurrenceRuleRaw: nil,
      modifiedAt: nextModifiedAt()
    )
    return metadata(forExternalIdentifier: externalIdentifier)
  }

  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool {
    guard let identifier = resolvedExternalIdentifier(for: task) else { return false }
    return tasksByExternalIdentifier.removeValue(forKey: identifier) != nil
  }

  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot? {
    guard let identifier = resolvedExternalIdentifier(for: task),
      let record = tasksByExternalIdentifier[identifier]
    else {
      return nil
    }
    return remoteSnapshot(record)
  }

  func setTaskTitle(
    for task: ReminderTaskReference,
    title: String
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let identifier = resolvedExternalIdentifier(for: task),
      var record = tasksByExternalIdentifier[identifier]
    else {
      return nil
    }
    record.title = title
    record.modifiedAt = nextModifiedAt()
    tasksByExternalIdentifier[identifier] = record
    return metadata(forExternalIdentifier: identifier)
  }

  func setTaskCompletion(
    for task: ReminderTaskReference,
    isCompleted: Bool,
    completionDate: Date?
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let identifier = resolvedExternalIdentifier(for: task),
      var record = tasksByExternalIdentifier[identifier]
    else {
      return nil
    }
    record.isCompleted = isCompleted
    record.completionDate = isCompleted ? completionDate : nil
    record.modifiedAt = nextModifiedAt()
    tasksByExternalIdentifier[identifier] = record
    return metadata(forExternalIdentifier: identifier)
  }

  func setTaskReminderNote(
    for task: ReminderTaskReference,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let identifier = resolvedExternalIdentifier(for: task),
      var record = tasksByExternalIdentifier[identifier]
    else {
      return nil
    }
    record.noteText = ReminderNoteSourceCodec.normalize(noteText)
    record.modifiedAt = nextModifiedAt()
    tasksByExternalIdentifier[identifier] = record
    return metadata(forExternalIdentifier: identifier)
  }

  func setTaskSchedule(
    for task: ReminderTaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let identifier = resolvedExternalIdentifier(for: task),
      var record = tasksByExternalIdentifier[identifier]
    else {
      return nil
    }
    record.dueDate = dueDate
    record.hasExplicitTime = dueDate != nil && hasExplicitTime
    record.modifiedAt = nextModifiedAt()
    tasksByExternalIdentifier[identifier] = record
    return metadata(forExternalIdentifier: identifier)
  }

  func setTaskRecurrence(
    for task: ReminderTaskReference,
    recurrenceRuleRaw: String?
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let identifier = resolvedExternalIdentifier(for: task),
      var record = tasksByExternalIdentifier[identifier]
    else {
      return nil
    }
    record.recurrenceRuleRaw = recurrenceRuleRaw
    record.modifiedAt = nextModifiedAt()
    tasksByExternalIdentifier[identifier] = record
    return metadata(forExternalIdentifier: identifier)
  }

  func setTaskPresentation(
    for task: ReminderTaskReference,
    priority: Int
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let identifier = resolvedExternalIdentifier(for: task),
      var record = tasksByExternalIdentifier[identifier]
    else {
      return nil
    }
    record.priority = priority
    record.modifiedAt = nextModifiedAt()
    tasksByExternalIdentifier[identifier] = record
    return metadata(forExternalIdentifier: identifier)
  }

  func moveTaskReminder(
    for task: ReminderTaskReference,
    toProject identifier: String
  ) throws -> ReminderTaskRemoteMetadata? {
    guard listsByIdentifier[identifier] != nil,
      let externalIdentifier = resolvedExternalIdentifier(for: task),
      var record = tasksByExternalIdentifier[externalIdentifier]
    else {
      return nil
    }
    record.listIdentifier = identifier
    record.modifiedAt = nextModifiedAt()
    tasksByExternalIdentifier[externalIdentifier] = record
    return metadata(forExternalIdentifier: externalIdentifier)
  }

  func restoreArchivedProject(
    _ project: ReminderArchivedProjectSnapshot
  ) throws -> ReminderProjectRestoreResult {
    let listIdentifier = "ui-test-restored-list-\(listsByIdentifier.count + 1)"
    let list = ReminderProjectListSnapshot(
      identifier: listIdentifier,
      externalIdentifier: listIdentifier,
      title: project.title,
      colorHex: project.colorHex
    )
    listsByIdentifier[listIdentifier] = list
    listOrder.append(listIdentifier)
    var metadataByTaskID: [UUID: ReminderTaskRemoteMetadata] = [:]
    for task in project.tasks {
      let externalIdentifier = "ui-test-restored-task-\(tasksByExternalIdentifier.count + 1)"
      tasksByExternalIdentifier[externalIdentifier] = TaskRecord(
        identifier: externalIdentifier,
        externalIdentifier: externalIdentifier,
        listIdentifier: listIdentifier,
        title: task.title,
        noteText: task.reminderNoteText,
        isCompleted: task.isCompleted,
        completionDate: task.completionDate,
        dueDate: task.dueDate,
        hasExplicitTime: task.hasExplicitTime,
        durationMinutes: nil,
        priority: task.priority,
        recurrenceRuleRaw: task.recurrenceRuleRaw,
        modifiedAt: nextModifiedAt()
      )
      metadataByTaskID[task.taskID] = metadata(forExternalIdentifier: externalIdentifier)
    }
    return ReminderProjectRestoreResult(list: list, taskMetadataByTaskID: metadataByTaskID)
  }

  func removeArchivedProjectLists(
    _ projects: [ReminderProjectListReference]
  ) -> ReminderProjectCleanupResult {
    var removedCount = 0
    var failedProjectIDs: [UUID] = []
    for project in projects {
      if listsByIdentifier[project.listIdentifier] == nil {
        failedProjectIDs.append(project.projectID)
        continue
      }
      try? removeProjectList(identifier: project.listIdentifier)
      removedCount += 1
    }
    return ReminderProjectCleanupResult(
      removedCount: removedCount,
      failedProjectIDs: failedProjectIDs
    )
  }

  private func resolvedExternalIdentifier(for task: ReminderTaskReference) -> String? {
    if let externalIdentifier = task.reminderExternalIdentifier,
      tasksByExternalIdentifier[externalIdentifier] != nil
    {
      return externalIdentifier
    }
    if let reminderIdentifier = task.reminderIdentifier,
      tasksByExternalIdentifier[reminderIdentifier] != nil
    {
      return reminderIdentifier
    }
    return tasksByExternalIdentifier.values.first {
      ReminderProjectionIdentity.taskID(for: $0.externalIdentifier) == task.taskID
    }?.externalIdentifier
  }

  private func metadata(forExternalIdentifier identifier: String) -> ReminderTaskRemoteMetadata? {
    guard let record = tasksByExternalIdentifier[identifier] else { return nil }
    return ReminderTaskRemoteMetadata(
      identifier: record.identifier,
      externalIdentifier: record.externalIdentifier,
      modifiedAt: record.modifiedAt
    )
  }

  private func remoteSnapshot(_ record: TaskRecord) -> ReminderTaskRemoteSnapshot {
    ReminderTaskRemoteSnapshot(
      identifier: record.identifier,
      externalIdentifier: record.externalIdentifier,
      calendarIdentifier: record.listIdentifier,
      title: record.title,
      noteText: record.noteText,
      isCompleted: record.isCompleted,
      completionDate: record.completionDate,
      startDate: nil,
      dueDate: record.dueDate,
      hasExplicitTime: record.hasExplicitTime,
      priority: record.priority,
      recurrenceRuleRaw: record.recurrenceRuleRaw,
      modifiedAt: record.modifiedAt
    )
  }

  private func importSnapshot(_ record: TaskRecord) -> ReminderItemImportSnapshot {
    let list = listsByIdentifier[record.listIdentifier]
    return ReminderItemImportSnapshot(
      identifier: record.identifier,
      externalIdentifier: record.externalIdentifier,
      parentExternalIdentifier: nil,
      sourceListIdentifier: record.listIdentifier,
      sourceListTitle: list?.title ?? "",
      title: record.title,
      notes: record.noteText,
      attachmentCount: 0,
      isCompleted: record.isCompleted,
      completionDate: record.completionDate,
      startDate: nil,
      dueDate: record.dueDate,
      scheduleHasExplicitTime: record.hasExplicitTime,
      scheduledDurationMinutes: record.durationMinutes,
      priority: record.priority,
      recurrenceRuleRaw: record.recurrenceRuleRaw,
      isFlagged: false,
      requiredWorkDays: 0,
      createdAt: record.modifiedAt,
      modifiedAt: record.modifiedAt
    )
  }

  private func nextModifiedAt() -> Date {
    writeClock += 1
    return Date(timeIntervalSince1970: writeClock)
  }
}
