@preconcurrency import EventKit
import Foundation

enum ReminderFetchScope {
  case incompleteOnly
  case all
}

@MainActor
protocol ReminderGateway: AnyObject {
  var eventStore: EKEventStore { get }

  /// Requests the highest available Reminders permission for the app session.
  func requestAccess() async throws -> Bool
  /// Returns all reminder lists the app can currently see.
  func fetchAllCalendars() async throws -> [EKCalendar]
  /// Returns a potentially merged reminder snapshot for a specific list.
  func fetchReminders(in calendar: EKCalendar, scope: ReminderFetchScope) async throws
    -> [EKReminder]
  /// Returns a potentially merged reminder snapshot for a group of lists.
  func fetchReminders(in calendars: [EKCalendar], scope: ReminderFetchScope) async throws
    -> [EKReminder]

  func defaultCalendarIdentifierForNewReminders() -> String?
  func calendar(withIdentifier identifier: String) -> EKCalendar?
  func reminder(withIdentifier identifier: String) -> EKReminder?
  func reminders(withExternalIdentifier externalIdentifier: String) -> [EKReminder]
  func lastModifiedDate(for reminder: EKReminder) -> Date?
  /// Creates an unsaved reminder instance already attached to its target calendar.
  func makeReminder(in calendar: EKCalendar) -> EKReminder
  /// Creates a new Reminders list suitable for app-managed project sync.
  func createCalendar(title: String) throws -> EKCalendar

  func save(_ reminder: EKReminder) throws
  func remove(_ reminder: EKReminder) throws
  func save(_ calendar: EKCalendar) throws
  func remove(_ calendar: EKCalendar) throws
}

extension ReminderGateway {
  func fetchReminders(in calendars: [EKCalendar], scope: ReminderFetchScope) async throws
    -> [EKReminder]
  {
    var mergedReminders: [String: EKReminder] = [:]

    for calendar in calendars {
      for reminder in try await fetchReminders(in: calendar, scope: scope) {
        mergedReminders[reminder.calendarItemIdentifier] = reminder
      }
    }

    return Array(mergedReminders.values)
  }
}

enum ReminderGatewayError: LocalizedError {
  case noAvailableReminderSource

  var errorDescription: String? {
    switch self {
    case .noAvailableReminderSource:
      "리마인더 목록을 생성할 수 있는 계정을 찾지 못했습니다."
    }
  }
}

private struct ReminderSnapshot: @unchecked Sendable {
  let reminders: [EKReminder]
}

@MainActor
final class EventKitReminderGateway: ReminderGateway {
  let eventStore = EKEventStore()
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  func requestAccess() async throws -> Bool {
    let authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    switch authorizationStatus {
    case .fullAccess, .authorized:
      return true
    case .denied, .restricted, .writeOnly:
      return false
    case .notDetermined:
      let promptAttemptedKey = ReminderAccessPromptPolicy.promptAttemptedKey
      let currentIdentity = AppPermissionPromptIdentity.current()
      guard ReminderAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: authorizationStatus,
        promptAttempted: ReminderAccessPromptPolicy.promptAttemptedForCurrentIdentity(
          storedIdentity: userDefaults.string(
            forKey: ReminderAccessPromptPolicy.promptAttemptedIdentityKey
          ),
          currentIdentity: currentIdentity,
          legacyPromptAttempted: userDefaults.bool(forKey: promptAttemptedKey)
        )
      ) else {
        return false
      }
      userDefaults.set(true, forKey: promptAttemptedKey)
      if let currentIdentity {
        userDefaults.set(
          currentIdentity,
          forKey: ReminderAccessPromptPolicy.promptAttemptedIdentityKey
        )
      }
    @unknown default:
      return false
    }

    do {
      let granted = try await eventStore.requestFullAccessToReminders()
      if !granted {
        AppLogger.sync.error("reminders access request was denied")
      }
      return granted
    } catch {
      AppLogger.sync.error(
        "request reminders access failed: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  func fetchAllCalendars() async throws -> [EKCalendar] {
    let authorization = EKEventStore.authorizationStatus(for: .reminder)
    switch authorization {
    case .notDetermined:
      let granted = try await requestAccess()
      if !granted {
        AppLogger.sync.error("fetch calendars aborted because reminders access is denied")
        return []
      }
    case .denied, .restricted, .writeOnly:
      AppLogger.sync.error("fetch calendars aborted because reminders access is unavailable")
      return []
    case .fullAccess, .authorized:
      break
    @unknown default:
      break
    }

    var calendars = eventStore.calendars(for: .reminder)
    if !calendars.isEmpty {
      return calendars
    }

    // EventKit can transiently return empty calendars right after store changes.
    for attempt in 0..<3 {
      if attempt == 1 {
        eventStore.reset()
      }

      try? await Task.sleep(for: .milliseconds(240))
      calendars = eventStore.calendars(for: .reminder)
      if !calendars.isEmpty {
        break
      }
    }

    if calendars.isEmpty {
      AppLogger.sync.info("reminders calendar fetch returned an empty snapshot after retries")
    }

    return calendars
  }

  func fetchReminders(in calendar: EKCalendar, scope: ReminderFetchScope) async throws
    -> [EKReminder]
  {
    SyncPerformanceCounter.recordEventKitFetch()
    return try await fetchRemindersImpl(in: [calendar], scope: scope)
  }

  func fetchReminders(in calendars: [EKCalendar], scope: ReminderFetchScope) async throws
    -> [EKReminder]
  {
    SyncPerformanceCounter.recordEventKitFetch()
    return try await fetchRemindersImpl(in: calendars, scope: scope)
  }

  private func fetchRemindersImpl(in calendars: [EKCalendar], scope: ReminderFetchScope) async throws
    -> [EKReminder]
  {
    let calendarIdentifiers = uniqueCalendarIdentifiers(from: calendars)
    guard !calendarIdentifiers.isEmpty else { return [] }
    let calendarIdentifierSummary = calendarIdentifiers.joined(separator: ",")
    var mergedReminders: [String: EKReminder] = [:]
    var lastError: Error?

    // EventKit can briefly return partial reminder snapshots while the store is churning.
    // Merge a few reads so a transient miss does not become permanent local drift.
    for attempt in 0..<3 {
      if attempt == 1 {
        eventStore.reset()
      }

      let activeCalendars = resolvedCalendars(
        for: calendarIdentifiers,
        fallbackCalendars: calendars
      )
      let predicate = predicate(for: activeCalendars, scope: scope)
      do {
        let snapshot = try await fetchReminderSnapshot(matching: predicate)
        lastError = nil

        for reminder in snapshot.reminders {
          let reminderIdentifier = reminder.calendarItemIdentifier
          if let existing = mergedReminders[reminderIdentifier] {
            let existingModifiedAt = existing.lastModifiedDate ?? .distantPast
            let incomingModifiedAt = reminder.lastModifiedDate ?? .distantPast
            if incomingModifiedAt >= existingModifiedAt {
              mergedReminders[reminderIdentifier] = reminder
            }
          } else {
            mergedReminders[reminderIdentifier] = reminder
          }
        }

        if calendarIdentifiers.count == 1, !snapshot.reminders.isEmpty {
          break
        }
      } catch {
        lastError = error
        AppLogger.sync.error(
          "fetch reminders failed. calendars=\(calendarIdentifierSummary, privacy: .public) attempt=\(attempt + 1, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
        if attempt == 2 {
          if mergedReminders.isEmpty {
            throw error
          }
          break
        }
      }

      if attempt < 2 {
        try? await Task.sleep(for: .milliseconds(180))
      }
    }

    if let lastError, mergedReminders.isEmpty {
      throw lastError
    }

    return Array(mergedReminders.values)
  }

  func calendar(withIdentifier identifier: String) -> EKCalendar? {
    eventStore.calendar(withIdentifier: identifier)
  }

  func defaultCalendarIdentifierForNewReminders() -> String? {
    eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
  }

  func reminder(withIdentifier identifier: String) -> EKReminder? {
    eventStore.calendarItem(withIdentifier: identifier) as? EKReminder
  }

  func reminders(withExternalIdentifier externalIdentifier: String) -> [EKReminder] {
    eventStore.calendarItems(withExternalIdentifier: externalIdentifier)
      .compactMap { $0 as? EKReminder }
  }

  func lastModifiedDate(for reminder: EKReminder) -> Date? {
    reminder.lastModifiedDate
  }

  func makeReminder(in calendar: EKCalendar) -> EKReminder {
    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = calendar
    return reminder
  }

  func createCalendar(title: String) throws -> EKCalendar {
    guard let source = preferredReminderSource() else {
      AppLogger.sync.error(
        "create reminder calendar failed because no source is available. title=\(title, privacy: .public)"
      )
      throw ReminderGatewayError.noAvailableReminderSource
    }

    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.source = source
    calendar.title = title

    if let defaultColor = eventStore.defaultCalendarForNewReminders()?.cgColor {
      calendar.cgColor = defaultColor
    }

    try save(calendar)
    return calendar
  }

  func save(_ reminder: EKReminder) throws {
    do {
      try eventStore.save(reminder, commit: true)
    } catch {
      AppLogger.sync.error(
        "save reminder failed. calendar=\(reminder.calendar.calendarIdentifier, privacy: .public) id=\(reminder.calendarItemIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  func remove(_ reminder: EKReminder) throws {
    do {
      try eventStore.remove(reminder, commit: true)
    } catch {
      AppLogger.sync.error(
        "remove reminder failed. calendar=\(reminder.calendar.calendarIdentifier, privacy: .public) id=\(reminder.calendarItemIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  func save(_ calendar: EKCalendar) throws {
    do {
      try eventStore.saveCalendar(calendar, commit: true)
    } catch {
      AppLogger.sync.error(
        "save calendar failed. id=\(calendar.calendarIdentifier, privacy: .public) title=\(calendar.title, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  func remove(_ calendar: EKCalendar) throws {
    do {
      try eventStore.removeCalendar(calendar, commit: true)
    } catch {
      AppLogger.sync.error(
        "remove calendar failed. id=\(calendar.calendarIdentifier, privacy: .public) title=\(calendar.title, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  private func preferredReminderSource() -> EKSource? {
    if let source = eventStore.defaultCalendarForNewReminders()?.source {
      return source
    }

    return eventStore.sources.first(where: { $0.sourceType == .calDAV })
      ?? eventStore.sources.first(where: { $0.sourceType == .exchange })
      ?? eventStore.sources.first(where: { $0.sourceType == .local })
      ?? eventStore.sources.first
  }

  private func uniqueCalendarIdentifiers(from calendars: [EKCalendar]) -> [String] {
    var identifiers: [String] = []
    identifiers.reserveCapacity(calendars.count)

    for calendar in calendars {
      let identifier = calendar.calendarIdentifier
      if !identifiers.contains(identifier) {
        identifiers.append(identifier)
      }
    }

    return identifiers
  }

  private func resolvedCalendars(
    for identifiers: [String],
    fallbackCalendars: [EKCalendar]
  ) -> [EKCalendar] {
    var fallbackByIdentifier: [String: EKCalendar] = [:]
    for calendar in fallbackCalendars {
      fallbackByIdentifier[calendar.calendarIdentifier] = calendar
    }
    let resolved = identifiers.compactMap { identifier in
      fallbackByIdentifier[identifier] ?? eventStore.calendar(withIdentifier: identifier)
    }
    return resolved.isEmpty ? fallbackCalendars : resolved
  }

  private func predicate(for calendar: EKCalendar, scope: ReminderFetchScope) -> NSPredicate {
    predicate(for: [calendar], scope: scope)
  }

  private func predicate(for calendars: [EKCalendar], scope: ReminderFetchScope) -> NSPredicate {
    switch scope {
    case .incompleteOnly:
      return eventStore.predicateForIncompleteReminders(
        withDueDateStarting: nil,
        ending: nil,
        calendars: calendars
      )
    case .all:
      return eventStore.predicateForReminders(in: calendars)
    }
  }

  private func fetchReminderSnapshot(matching predicate: NSPredicate) async throws
    -> ReminderSnapshot
  {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<ReminderSnapshot, Error>) in
      eventStore.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: ReminderSnapshot(reminders: reminders ?? []))
      }
    }
  }
}

enum ReminderAccessPromptPolicy {
  static let promptAttemptedKey = "reminders.accessPromptAttempted"
  static let promptAttemptedIdentityKey = "reminders.accessPromptAttemptedIdentity"

  static func shouldRequestAccess(
    authorizationStatus: EKAuthorizationStatus,
    promptAttempted: Bool
  ) -> Bool {
    switch authorizationStatus {
    case .notDetermined:
      return !promptAttempted
    case .fullAccess, .authorized, .writeOnly, .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  static func promptAttemptedForCurrentIdentity(
    storedIdentity: String?,
    currentIdentity: String?,
    legacyPromptAttempted: Bool
  ) -> Bool {
    guard let currentIdentity else {
      return legacyPromptAttempted
    }
    return storedIdentity == currentIdentity
  }
}

enum AppPermissionPromptIdentity {
  static func current(bundle: Bundle = .main) -> String? {
    guard let executableURL = bundle.executableURL else {
      return bundle.bundleIdentifier
    }
    let values = try? executableURL.resourceValues(
      forKeys: [.contentModificationDateKey, .fileSizeKey]
    )
    let bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
    let fileSize = values?.fileSize ?? 0
    let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    return "\(bundleIdentifier):\(fileSize):\(modifiedAt)"
  }
}

@MainActor
final class PreviewReminderGateway: ReminderGateway {
  private lazy var previewEventStore = EKEventStore()

  var eventStore: EKEventStore {
    previewEventStore
  }

  func requestAccess() async throws -> Bool { true }

  func fetchAllCalendars() async throws -> [EKCalendar] { [] }

  func fetchReminders(in calendar: EKCalendar, scope: ReminderFetchScope) async throws -> [EKReminder] {
    []
  }

  func defaultCalendarIdentifierForNewReminders() -> String? { nil }

  func calendar(withIdentifier identifier: String) -> EKCalendar? { nil }

  func reminder(withIdentifier identifier: String) -> EKReminder? { nil }

  func reminders(withExternalIdentifier externalIdentifier: String) -> [EKReminder] { [] }

  func lastModifiedDate(for reminder: EKReminder) -> Date? { nil }

  func makeReminder(in calendar: EKCalendar) -> EKReminder {
    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = calendar
    return reminder
  }

  func createCalendar(title: String) throws -> EKCalendar {
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = title
    return calendar
  }

  func save(_ reminder: EKReminder) throws {}
  func remove(_ reminder: EKReminder) throws {}
  func save(_ calendar: EKCalendar) throws {}
  func remove(_ calendar: EKCalendar) throws {}
}

struct ReminderProjectListSnapshot: Sendable {
  let identifier: String
  let externalIdentifier: String
  let title: String
  let colorHex: String?
}

struct ReminderTaskRemoteMetadata: Sendable {
  let identifier: String
  let externalIdentifier: String?
  let modifiedAt: Date
}

struct ReminderTaskRemoteSnapshot: Sendable {
  let identifier: String
  let externalIdentifier: String?
  let calendarIdentifier: String
  let title: String
  let noteText: String
  let isCompleted: Bool
  let completionDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let hasExplicitTime: Bool
  let priority: Int
  let recurrenceRuleRaw: String?
  let modifiedAt: Date

  init(
    identifier: String,
    externalIdentifier: String?,
    calendarIdentifier: String,
    title: String,
    noteText: String,
    isCompleted: Bool = false,
    completionDate: Date? = nil,
    startDate: Date? = nil,
    dueDate: Date?,
    hasExplicitTime: Bool,
    priority: Int,
    recurrenceRuleRaw: String? = nil,
    modifiedAt: Date
  ) {
    self.identifier = identifier
    self.externalIdentifier = externalIdentifier
    self.calendarIdentifier = calendarIdentifier
    self.title = title
    self.noteText = noteText
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.startDate = startDate
    self.dueDate = dueDate
    self.hasExplicitTime = hasExplicitTime
    self.priority = priority
    self.recurrenceRuleRaw = recurrenceRuleRaw
    self.modifiedAt = modifiedAt
  }
}

struct ReminderTaskReference: Sendable {
  let taskID: UUID
  let reminderIdentifier: String?
  let reminderExternalIdentifier: String?
}

struct ReminderProjectListReference: Sendable {
  let projectID: UUID
  let listIdentifier: String
}

struct ReminderArchivedTaskSnapshot: Sendable {
  let taskID: UUID
  let title: String
  let isCompleted: Bool
  let completionDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let hasExplicitTime: Bool
  let priority: Int
  let reminderNoteText: String
  let attachmentCount: Int
  let recurrenceRuleRaw: String?
  let detail: ReminderArchiveTaskDetailSnapshot?

  init(
    taskID: UUID,
    title: String,
    isCompleted: Bool,
    completionDate: Date?,
    startDate: Date?,
    dueDate: Date?,
    hasExplicitTime: Bool,
    priority: Int,
    reminderNoteText: String,
    attachmentCount: Int,
    recurrenceRuleRaw: String?,
    detail: ReminderArchiveTaskDetailSnapshot? = nil
  ) {
    self.taskID = taskID
    self.title = title
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.startDate = startDate
    self.dueDate = dueDate
    self.hasExplicitTime = hasExplicitTime
    self.priority = priority
    self.reminderNoteText = reminderNoteText
    self.attachmentCount = attachmentCount
    self.recurrenceRuleRaw = recurrenceRuleRaw
    self.detail = detail
  }
}

struct ReminderArchivedProjectSnapshot: Sendable {
  let projectID: UUID
  let title: String
  let colorHex: String?
  let tasks: [ReminderArchivedTaskSnapshot]
  let detail: ReminderArchiveListDetailSnapshot?

  init(
    projectID: UUID,
    title: String,
    colorHex: String?,
    tasks: [ReminderArchivedTaskSnapshot],
    detail: ReminderArchiveListDetailSnapshot? = nil
  ) {
    self.projectID = projectID
    self.title = title
    self.colorHex = colorHex
    self.tasks = tasks
    self.detail = detail
  }
}

struct ReminderProjectRestoreResult: Sendable {
  let list: ReminderProjectListSnapshot
  let taskMetadataByTaskID: [UUID: ReminderTaskRemoteMetadata]
}

struct ReminderProjectCleanupResult: Sendable {
  let removedCount: Int
  let failedProjectIDs: [UUID]
}

@MainActor
protocol ReminderProjectProvider: AnyObject {
  var reminderGateway: ReminderGateway? { get }
  var defaultCalendarIdentifierForNewReminders: String? { get }

  func requestAccess() async throws -> Bool
  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch?
  func fetchArchiveSnapshot(
    forListIdentifier identifier: String,
    archivedAt: Date,
    sourceVaultRelativePath: String
  ) async throws -> ObsidianReminderArchiveSnapshot?
  func createProjectList(title: String) throws -> ReminderProjectListSnapshot
  func removeProjectList(identifier: String) throws
  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot?
  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot?
  func createTaskReminder(
    inProject identifier: String,
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata?
  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool
  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot?
  func setTaskTitle(
    for task: ReminderTaskReference,
    title: String
  ) throws -> ReminderTaskRemoteMetadata?
  func setTaskCompletion(
    for task: ReminderTaskReference,
    isCompleted: Bool,
    completionDate: Date?
  ) throws -> ReminderTaskRemoteMetadata?
  func setTaskReminderNote(
    for task: ReminderTaskReference,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata?
  func setTaskSchedule(
    for task: ReminderTaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws -> ReminderTaskRemoteMetadata?
  func setTaskRecurrence(
    for task: ReminderTaskReference,
    recurrenceRuleRaw: String?
  ) throws -> ReminderTaskRemoteMetadata?
  func setTaskPresentation(
    for task: ReminderTaskReference,
    priority: Int
  ) throws -> ReminderTaskRemoteMetadata?
  func moveTaskReminder(
    for task: ReminderTaskReference,
    toProject identifier: String
  ) throws -> ReminderTaskRemoteMetadata?
  func restoreArchivedProject(
    _ project: ReminderArchivedProjectSnapshot
  ) throws -> ReminderProjectRestoreResult
  func removeArchivedProjectLists(
    _ projects: [ReminderProjectListReference]
  ) -> ReminderProjectCleanupResult
}

extension ReminderProjectProvider {
  func deleteReminderTask(for task: ReminderTaskReference) throws -> Bool {
    try removeTaskReminder(for: task)
  }
}

extension ReminderProjectProvider {
  var reminderGateway: ReminderGateway? { nil }

  func fetchProjectListsInCurrentOrder() async throws -> [ReminderProjectListSnapshot] {
    guard let gateway = reminderGateway else { return [] }
    return try await gateway.fetchAllCalendars().map { calendar in
      ReminderProjectListSnapshot(
        identifier: calendar.calendarIdentifier,
        externalIdentifier: calendar.calendarIdentifier,
        title: calendar.title,
        colorHex: ColorHexCodec.hexString(from: calendar.color)
      )
    }
  }

  func fetchImportSnapshotBatch(
    forListIdentifiers identifiers: [String]
  ) async throws -> ReminderImportSnapshotBatch? {
    guard let gateway = reminderGateway else { return nil }
    return try await ReminderGatewayImportSnapshotProvider(gateway: gateway)
      .fetchBatch(forListIdentifiers: identifiers)
  }

  func fetchArchiveSnapshot(
    forListIdentifier identifier: String,
    archivedAt: Date,
    sourceVaultRelativePath: String
  ) async throws -> ObsidianReminderArchiveSnapshot? {
    if let gateway = reminderGateway {
      return try await ObsidianReminderArchiveSnapshotBuilder(gateway: gateway).snapshot(
        forListIdentifier: identifier,
        archivedAt: archivedAt,
        sourceVaultRelativePath: sourceVaultRelativePath
      )
    }

    guard let batch = try await fetchImportSnapshotBatch(forListIdentifiers: [identifier]),
      let list = batch.lists.first(where: {
        Self.normalized($0.identifier) == identifier
          || Self.normalized($0.externalIdentifier) == identifier
      })
    else {
      return nil
    }

    return ObsidianReminderArchiveSnapshot(
      archivedAt: archivedAt,
      sourceVaultRelativePath: sourceVaultRelativePath,
      list: list,
      items: batch.itemsByListIdentifier[list.identifier] ?? []
    )
  }

  private static func normalized(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}

@MainActor
final class EventKitReminderProjectProvider: ReminderProjectProvider {
  private let gateway: ReminderGateway

  init(gateway: ReminderGateway) {
    self.gateway = gateway
  }

  var reminderGateway: ReminderGateway? {
    gateway
  }

  var defaultCalendarIdentifierForNewReminders: String? {
    gateway.defaultCalendarIdentifierForNewReminders()
  }

  func requestAccess() async throws -> Bool {
    try await gateway.requestAccess()
  }

  func createProjectList(title: String) throws -> ReminderProjectListSnapshot {
    makeProjectListSnapshot(try gateway.createCalendar(title: title))
  }

  func removeProjectList(identifier: String) throws {
    guard let calendar = gateway.calendar(withIdentifier: identifier) else { return }
    try gateway.remove(calendar)
  }

  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot? {
    guard let calendar = gateway.calendar(withIdentifier: identifier) else { return nil }
    calendar.title = title
    try gateway.save(calendar)
    return makeProjectListSnapshot(calendar)
  }

  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot? {
    guard let calendar = gateway.calendar(withIdentifier: identifier) else { return nil }

    if let color = ColorHexCodec.nsColor(from: colorHex) {
      calendar.cgColor = color.cgColor
    } else if let defaultColor = gateway.eventStore.defaultCalendarForNewReminders()?.cgColor {
      calendar.cgColor = defaultColor
    }

    try gateway.save(calendar)
    return makeProjectListSnapshot(calendar)
  }

  func createTaskReminder(
    inProject identifier: String,
    title: String,
    dueDate: Date?,
    hasExplicitTime: Bool,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let calendar = gateway.calendar(withIdentifier: identifier) else { return nil }
    let reminder = gateway.makeReminder(in: calendar)
    reminder.title = title
    reminder.startDateComponents = nil
    reminder.dueDateComponents = normalizedDateComponentsForDirectSave(
      from: dueDate,
      existing: reminder.dueDateComponents,
      hasExplicitTime: hasExplicitTime
    )
    reminder.notes = ReminderNoteSourceCodec.normalize(noteText)
    try gateway.save(reminder)
    return ReminderTaskRemoteMetadata(
      identifier: reminder.calendarItemIdentifier,
      externalIdentifier: reminder.calendarItemExternalIdentifier,
      modifiedAt: gateway.lastModifiedDate(for: reminder) ?? .now
    )
  }

  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool {
    guard let reminder = resolvedReminder(for: task) else { return false }
    try gateway.remove(reminder)
    return true
  }

  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot? {
    guard let reminder = resolvedReminder(for: task) else { return nil }
    let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    let startDate = reminder.startDateComponents.flatMap { Calendar.current.date(from: $0) }
    let hasExplicitTime =
      reminder.dueDateComponents?.hour != nil
      || reminder.dueDateComponents?.minute != nil
      || reminder.dueDateComponents?.second != nil
    return ReminderTaskRemoteSnapshot(
      identifier: reminder.calendarItemIdentifier,
      externalIdentifier: reminder.calendarItemExternalIdentifier,
      calendarIdentifier: reminder.calendar.calendarIdentifier,
      title: reminder.title,
      noteText: ReminderNoteSourceCodec.normalizeReminderRawNote(reminder.notes),
      isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate,
      startDate: startDate,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      priority: reminder.priority,
      recurrenceRuleRaw: ReminderRecurrenceCodec.rawValue(from: reminder.recurrenceRules),
      modifiedAt: gateway.lastModifiedDate(for: reminder) ?? .now
    )
  }

  func setTaskTitle(
    for task: ReminderTaskReference,
    title: String
  ) throws -> ReminderTaskRemoteMetadata? {
    try mutateReminder(for: task) { reminder in
      reminder.title = title
    }
  }

  func setTaskCompletion(
    for task: ReminderTaskReference,
    isCompleted: Bool,
    completionDate: Date?
  ) throws -> ReminderTaskRemoteMetadata? {
    try mutateReminder(for: task) { reminder in
      reminder.isCompleted = isCompleted
      reminder.completionDate = isCompleted ? (completionDate ?? .now) : nil
    }
  }

  func setTaskReminderNote(
    for task: ReminderTaskReference,
    noteText: String
  ) throws -> ReminderTaskRemoteMetadata? {
    try mutateReminder(for: task) { reminder in
      reminder.notes = ReminderNoteSourceCodec.normalize(noteText)
    }
  }

  func setTaskSchedule(
    for task: ReminderTaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let reminder = resolvedReminder(for: task) else { return nil }
    let existingDueDateComponents = reminder.dueDateComponents
    let nextDueDateComponents = normalizedDateComponentsForDirectSave(
      from: dueDate,
      existing: existingDueDateComponents,
      hasExplicitTime: hasExplicitTime
    )

    reminder.startDateComponents = nil
    let assignmentSteps = ReminderDueDateComponentsPolicy.assignmentSteps(
      existing: existingDueDateComponents,
      next: nextDueDateComponents
    )
    for dueDateComponents in assignmentSteps {
      reminder.dueDateComponents = dueDateComponents
      try gateway.save(reminder)
    }
    return ReminderTaskRemoteMetadata(
      identifier: reminder.calendarItemIdentifier,
      externalIdentifier: reminder.calendarItemExternalIdentifier,
      modifiedAt: gateway.lastModifiedDate(for: reminder) ?? .now
    )
  }

  func setTaskRecurrence(
    for task: ReminderTaskReference,
    recurrenceRuleRaw: String?
  ) throws -> ReminderTaskRemoteMetadata? {
    try mutateReminder(for: task) { reminder in
      reminder.recurrenceRules = ReminderRecurrenceCodec.recurrenceRules(
        fromRawValue: recurrenceRuleRaw
      )
    }
  }

  func setTaskPresentation(
    for task: ReminderTaskReference,
    priority: Int
  ) throws -> ReminderTaskRemoteMetadata? {
    try mutateReminder(for: task) { reminder in
      reminder.priority = max(0, min(9, priority))
    }
  }

  func moveTaskReminder(
    for task: ReminderTaskReference,
    toProject identifier: String
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let calendar = gateway.calendar(withIdentifier: identifier) else { return nil }
    return try mutateReminder(for: task) { reminder in
      reminder.calendar = calendar
    }
  }

  func restoreArchivedProject(
    _ project: ReminderArchivedProjectSnapshot
  ) throws -> ReminderProjectRestoreResult {
    let calendar = try gateway.createCalendar(title: project.title)

    do {
      if let color = ColorHexCodec.nsColor(from: project.colorHex) {
        calendar.cgColor = color.cgColor
        try gateway.save(calendar)
      }

      var taskMetadataByTaskID: [UUID: ReminderTaskRemoteMetadata] = [:]
      for task in project.tasks {
        let reminder = gateway.makeReminder(in: calendar)
        applyArchivedTask(task, to: reminder)
        try gateway.save(reminder)
        taskMetadataByTaskID[task.taskID] = ReminderTaskRemoteMetadata(
          identifier: reminder.calendarItemIdentifier,
          externalIdentifier: reminder.calendarItemExternalIdentifier,
          modifiedAt: gateway.lastModifiedDate(for: reminder) ?? .now
        )
      }

      return ReminderProjectRestoreResult(
        list: makeProjectListSnapshot(calendar),
        taskMetadataByTaskID: taskMetadataByTaskID
      )
    } catch {
      try? gateway.remove(calendar)
      throw error
    }
  }

  func removeArchivedProjectLists(
    _ projects: [ReminderProjectListReference]
  ) -> ReminderProjectCleanupResult {
    var removedCount = 0
    var failedProjectIDs: [UUID] = []

    for project in projects {
      guard let calendar = gateway.calendar(withIdentifier: project.listIdentifier) else {
        continue
      }

      do {
        try gateway.remove(calendar)
        removedCount += 1
      } catch {
        failedProjectIDs.append(project.projectID)
        AppLogger.sync.error(
          "removeArchivedProjectLists failed project=\(project.projectID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    return ReminderProjectCleanupResult(
      removedCount: removedCount,
      failedProjectIDs: failedProjectIDs
    )
  }

  private func makeProjectListSnapshot(_ calendar: EKCalendar) -> ReminderProjectListSnapshot {
    ReminderProjectListSnapshot(
      identifier: calendar.calendarIdentifier,
      externalIdentifier: calendar.calendarIdentifier,
      title: calendar.title,
      colorHex: ColorHexCodec.hexString(from: calendar.color)
    )
  }

  private func resolvedReminder(for task: ReminderTaskReference) -> EKReminder? {
    if let reminderID = task.reminderIdentifier,
      let reminder = gateway.reminder(withIdentifier: reminderID)
    {
      return reminder
    }

    guard let externalIdentifier = task.reminderExternalIdentifier,
      !externalIdentifier.isEmpty
    else {
      return nil
    }

    if let reminder = gateway.reminder(withIdentifier: externalIdentifier) {
      return reminder
    }

    let matches = gateway.reminders(withExternalIdentifier: externalIdentifier)
    if matches.count > 1 {
      AppLogger.sync.error(
        "resolvedReminder found multiple reminder matches for external identifier")
    }
    return ReminderTaskAdoptionPolicy.uniqueMatch(from: matches)
  }

  private func mutateReminder(
    for task: ReminderTaskReference,
    mutation: (EKReminder) -> Void
  ) throws -> ReminderTaskRemoteMetadata? {
    guard let reminder = resolvedReminder(for: task) else { return nil }
    mutation(reminder)
    try gateway.save(reminder)
    return ReminderTaskRemoteMetadata(
      identifier: reminder.calendarItemIdentifier,
      externalIdentifier: reminder.calendarItemExternalIdentifier,
      modifiedAt: gateway.lastModifiedDate(for: reminder) ?? .now
    )
  }

  private func applyArchivedTask(_ task: ReminderArchivedTaskSnapshot, to reminder: EKReminder) {
    if let detail = task.detail {
      applyArchivedTaskDetail(detail, fallback: task, to: reminder)
      return
    }

    applyArchivedTaskFallback(task, to: reminder)
  }

  private func applyArchivedTaskDetail(
    _ detail: ReminderArchiveTaskDetailSnapshot,
    fallback task: ReminderArchivedTaskSnapshot,
    to reminder: EKReminder
  ) {
    reminder.title = detail.title
    reminder.location = detail.location
    reminder.notes = ReminderNoteSourceCodec.normalize(detail.notes)
    reminder.url = detail.urlString.flatMap(URL.init(string:))
    reminder.timeZone = detail.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    reminder.isCompleted = detail.isCompleted
    reminder.completionDate = detail.completionDate
    reminder.priority = max(0, min(9, detail.priority))
    reminder.startDateComponents = detail.startDateComponents?.dateComponents
      ?? dateComponentsForArchivedRestore(
        from: task.startDate,
        hasExplicitTime: task.hasExplicitTime
      )
    reminder.dueDateComponents = detail.dueDateComponents?.dateComponents
      ?? dateComponentsForArchivedRestore(
        from: task.dueDate,
        hasExplicitTime: task.hasExplicitTime
      )
    reminder.recurrenceRules = detail.recurrenceRules.compactMap(\.recurrenceRule)
    reminder.alarms = detail.alarms.map(\.alarm)
  }

  private func applyArchivedTaskFallback(_ task: ReminderArchivedTaskSnapshot, to reminder: EKReminder) {
    reminder.title = task.title
    reminder.isCompleted = task.isCompleted
    reminder.completionDate = task.completionDate
    reminder.priority = max(0, min(9, task.priority))
    reminder.startDateComponents = dateComponentsForArchivedRestore(
      from: task.startDate,
      hasExplicitTime: task.hasExplicitTime
    )
    reminder.dueDateComponents = dateComponentsForArchivedRestore(
      from: task.dueDate,
      hasExplicitTime: task.hasExplicitTime
    )
    reminder.notes = ReminderNoteSourceCodec.normalize(task.reminderNoteText)
    reminder.recurrenceRules = ReminderRecurrenceCodec.recurrenceRules(
      fromRawValue: task.recurrenceRuleRaw
    )
  }

  private func dateComponentsForArchivedRestore(
    from date: Date?,
    hasExplicitTime: Bool
  ) -> DateComponents? {
    guard let date else { return nil }
    let calendar = Calendar.autoupdatingCurrent
    if !hasExplicitTime {
      return calendar.dateComponents([.year, .month, .day], from: date)
    }

    return calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second, .timeZone],
      from: date
    )
  }

  private func normalizedDateComponentsForDirectSave(
    from localDate: Date?,
    existing: DateComponents?,
    hasExplicitTime: Bool
  ) -> DateComponents? {
    ReminderDueDateComponentsPolicy.components(
      from: localDate,
      existing: existing,
      hasExplicitTime: hasExplicitTime
    )
  }
}

enum ReminderDueDateComponentsPolicy {
  static func components(
    from localDate: Date?,
    existing: DateComponents?,
    hasExplicitTime: Bool,
    calendar: Calendar = .autoupdatingCurrent
  ) -> DateComponents? {
    guard let localDate else { return nil }

    if !hasExplicitTime {
      var components = calendar.dateComponents([.year, .month, .day], from: localDate)
      components.calendar = existing?.calendar ?? calendar
      return components
    }

    var components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second, .timeZone],
      from: localDate
    )
    components.calendar = existing?.calendar ?? calendar
    components.timeZone = existing?.timeZone ?? components.timeZone ?? .current
    return components
  }

  static func shouldClearExistingDueDateBeforeAssigning(
    existing: DateComponents?,
    next: DateComponents?
  ) -> Bool {
    guard let existing, let next else { return false }
    guard sameDay(existing, next) else { return false }
    return !sameStoredDueDate(existing, next)
  }

  static func assignmentSteps(
    existing: DateComponents?,
    next: DateComponents?
  ) -> [DateComponents?] {
    guard shouldClearExistingDueDateBeforeAssigning(existing: existing, next: next) else {
      return [next]
    }
    return [nil, next]
  }

  private static func sameDay(_ lhs: DateComponents, _ rhs: DateComponents) -> Bool {
    lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
  }

  private static func sameStoredDueDate(
    _ lhs: DateComponents,
    _ rhs: DateComponents
  ) -> Bool {
    let lhsHasTime = hasExplicitTime(lhs)
    let rhsHasTime = hasExplicitTime(rhs)
    guard lhsHasTime == rhsHasTime else { return false }
    guard lhsHasTime else { return true }
    return (lhs.hour ?? 0) == (rhs.hour ?? 0)
      && (lhs.minute ?? 0) == (rhs.minute ?? 0)
      && (lhs.second ?? 0) == (rhs.second ?? 0)
  }

  private static func hasExplicitTime(_ components: DateComponents) -> Bool {
    components.hour != nil || components.minute != nil || components.second != nil
  }
}
