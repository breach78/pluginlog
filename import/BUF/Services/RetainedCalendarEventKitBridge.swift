import Foundation
@preconcurrency import EventKit

struct RetainedCalendarBridgeApplyResult: Equatable, Sendable {
  let projectID: UUID
  let taskID: UUID
  let calendarEventExternalIdentifier: String?
  let calendarBridgeDecision: RetainedCalendarBridgeDecision
  let calendarWriteMarker: RetainedCalendarBridgeWriteMarker?
}

struct RetainedCalendarEventWriteResult: Equatable, Sendable {
  let externalIdentifier: String
  let title: String?
  let startDate: Date?
  let durationMinutes: Int?

  init(
    externalIdentifier: String,
    title: String? = nil,
    startDate: Date? = nil,
    durationMinutes: Int? = nil
  ) {
    self.externalIdentifier = externalIdentifier
    self.title = title
    self.startDate = startDate
    self.durationMinutes = durationMinutes
  }
}

@MainActor
protocol RetainedCalendarEventWriting: AnyObject {
  func upsertOwnedEvent(
    _ request: RetainedCalendarBridgeUpsertRequest,
    marker: RetainedCalendarBridgeWriteMarker?
  ) async throws -> RetainedCalendarEventWriteResult

  func removeOwnedEvent(
    externalIdentifier: String,
    marker: RetainedCalendarBridgeWriteMarker?
  ) async throws -> Bool
}

enum RetainedCalendarBridgeApplyError: LocalizedError, Equatable {
  case graphNotConfigured
  case retainedProjectionFailed(String)
  case projectNotFound(UUID)
  case taskNotFound(UUID)
  case unmanagedTask(UUID)
  case calendarIdentityChanged(expected: String?, actual: String?)
  case staleCalendarDecision(expected: RetainedCalendarBridgeDecision, actual: RetainedCalendarBridgeDecision)
  case calendarPolicyBlocked(RetainedCalendarBridgeBlocker)
  case ownedEventMissing(String)
  case missingWrittenExternalIdentifier
  case createdEventRollbackFailed(writeError: String, rollbackError: String)

  var errorDescription: String? {
    switch self {
    case .graphNotConfigured:
      return "Logseq graph is not configured for retained calendar writes."
    case .retainedProjectionFailed(let message):
      return "Retained calendar write blocked: \(message)"
    case .projectNotFound(let projectID):
      return "Retained calendar project not found: \(projectID.uuidString)"
    case .taskNotFound(let taskID):
      return "Retained calendar task not found: \(taskID.uuidString)"
    case .unmanagedTask(let taskID):
      return "Retained calendar task is not in the managed Logseq task section: \(taskID.uuidString)"
    case .calendarIdentityChanged(let expected, let actual):
      return "Retained calendar identity changed before write. expected=\(expected ?? "nil") actual=\(actual ?? "nil")"
    case .staleCalendarDecision(let expected, let actual):
      return "Retained calendar decision changed before write. expected=\(expected) actual=\(actual)"
    case .calendarPolicyBlocked(let blocker):
      return "Retained calendar policy blocked write: \(blocker)"
    case .ownedEventMissing(let externalIdentifier):
      return "Retained app-managed Calendar event is missing: \(externalIdentifier)"
    case .missingWrittenExternalIdentifier:
      return "Calendar write did not return a stable external identifier."
    case .createdEventRollbackFailed(let writeError, let rollbackError):
      return "Created calendar event could not be rolled back. write=\(writeError) rollback=\(rollbackError)"
    }
  }
}

enum RetainedCalendarEventWriterError: LocalizedError, Equatable {
  case accessDenied
  case writableSourceUnavailable
  case ownedCalendarAmbiguous
  case ownedCalendarMissing
  case ownedEventMissing(String)
  case eventMatchAmbiguous(String)
  case foreignEvent(String)
  case missingExternalIdentifier
  case saveFailed(String)
  case removeFailed(String)

  var errorDescription: String? {
    switch self {
    case .accessDenied:
      return "Calendar access is not available for retained Calendar writes."
    case .writableSourceUnavailable:
      return "No writable Calendar source is available for retained Calendar writes."
    case .ownedCalendarAmbiguous:
      return "Retained owned Calendar resolution is ambiguous."
    case .ownedCalendarMissing:
      return "Retained owned Calendar is missing or not stably identified."
    case .ownedEventMissing(let identifier):
      return "Retained owned Calendar event is missing: \(identifier)"
    case .eventMatchAmbiguous(let identifier):
      return "Calendar event identifier is ambiguous: \(identifier)"
    case .foreignEvent(let identifier):
      return "Calendar event is not in the retained app-managed Calendar: \(identifier)"
    case .missingExternalIdentifier:
      return "Saved Calendar event has no external identifier."
    case .saveFailed(let message):
      return message
    case .removeFailed(let message):
      return message
    }
  }
}

@MainActor
enum RetainedCalendarEventKitBridge {
  static func apply(
    commandResult: RetainedTaskCommandResult,
    graphRootURL: URL?,
    eventWriter: RetainedCalendarEventWriting = EventKitRetainedCalendarEventWriter()
  ) async throws -> RetainedCalendarBridgeApplyResult {
    // Legacy safety seam: retained task scheduling must never write Apple Calendar events.
    _ = graphRootURL
    _ = eventWriter
    return RetainedCalendarBridgeApplyResult(
      projectID: commandResult.projectID,
      taskID: commandResult.taskID,
      calendarEventExternalIdentifier: nil,
      calendarBridgeDecision: .noAction,
      calendarWriteMarker: nil
    )
  }

  private static func applyUpsert(
    _ request: RetainedCalendarBridgeUpsertRequest,
    commandResult: RetainedTaskCommandResult,
    graphRootURL: URL?,
    eventWriter: RetainedCalendarEventWriting
  ) async throws -> RetainedCalendarBridgeApplyResult {
    let context = try await context(
      graphRootURL: graphRootURL,
      projectID: commandResult.projectID,
      taskID: commandResult.taskID,
      expectedCalendarEventExternalIdentifier: request.externalIdentifier
    )
    try validateCurrentDecision(commandResult.calendarBridgeDecision, for: context.task)
    let writeResult = try await eventWriter.upsertOwnedEvent(
      request,
      marker: commandResult.calendarWriteMarker
    )
    let resolvedIdentifier = try normalizedWrittenIdentifier(writeResult.externalIdentifier)

    if resolvedIdentifier != context.task.identity.calendarEventExternalIdentifier {
      do {
        try await updateCalendarIdentity(
          resolvedIdentifier,
          using: context
        )
      } catch {
        if request.externalIdentifier == nil {
          try await rollbackCreatedEvent(
            resolvedIdentifier,
            eventWriter: eventWriter,
            writeError: error
          )
        }
        throw error
      }
    }

    let finalDecision = RetainedCalendarBridgeDecision.upsert(
      RetainedCalendarBridgeUpsertRequest(
        externalIdentifier: resolvedIdentifier,
        title: writeResult.title ?? request.title,
        startDate: writeResult.startDate ?? request.startDate,
        durationMinutes: writeResult.durationMinutes ?? request.durationMinutes
      )
    )
    return RetainedCalendarBridgeApplyResult(
      projectID: commandResult.projectID,
      taskID: commandResult.taskID,
      calendarEventExternalIdentifier: resolvedIdentifier,
      calendarBridgeDecision: finalDecision,
      calendarWriteMarker: RetainedCalendarBridgeWriteLoopGuard.marker(
        taskID: commandResult.taskID,
        decision: finalDecision
      )
    )
  }

  private static func applyRemoval(
    externalIdentifier: String,
    commandResult: RetainedTaskCommandResult,
    graphRootURL: URL?,
    eventWriter: RetainedCalendarEventWriting
  ) async throws -> RetainedCalendarBridgeApplyResult {
    let context = try await context(
      graphRootURL: graphRootURL,
      projectID: commandResult.projectID,
      taskID: commandResult.taskID,
      expectedCalendarEventExternalIdentifier: externalIdentifier
    )
    try validateCurrentDecision(commandResult.calendarBridgeDecision, for: context.task)
    let didRemove = try await eventWriter.removeOwnedEvent(
      externalIdentifier: externalIdentifier,
      marker: commandResult.calendarWriteMarker
    )
    guard didRemove else {
      throw RetainedCalendarBridgeApplyError.ownedEventMissing(externalIdentifier)
    }
    try await updateCalendarIdentity(nil, using: context)
    return RetainedCalendarBridgeApplyResult(
      projectID: commandResult.projectID,
      taskID: commandResult.taskID,
      calendarEventExternalIdentifier: nil,
      calendarBridgeDecision: .noAction,
      calendarWriteMarker: commandResult.calendarWriteMarker
    )
  }

  private struct Context {
    let store: LogseqProjectPageStore
    let page: LogseqProjectPageStore.PageSnapshot
    let task: RetainedTask
    let managedTaskIndex: Int
  }

  private static func context(
    graphRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    expectedCalendarEventExternalIdentifier: String?
  ) async throws -> Context {
    guard let graphRootURL else {
      throw RetainedCalendarBridgeApplyError.graphNotConfigured
    }
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRootURL.appendingPathComponent("pages", isDirectory: true)
    )
    let pages = try await loadPages(from: store)
    let snapshot = try retainedSnapshot(from: pages)
    guard let project = snapshot.projects.first(where: { $0.identity.projectID == projectID }) else {
      throw RetainedCalendarBridgeApplyError.projectNotFound(projectID)
    }
    guard let task = project.tasks.first(where: { $0.identity.taskID == taskID }) else {
      throw RetainedCalendarBridgeApplyError.taskNotFound(taskID)
    }
    guard task.isManagedTask else {
      throw RetainedCalendarBridgeApplyError.unmanagedTask(taskID)
    }
    guard task.identity.calendarEventExternalIdentifier == expectedCalendarEventExternalIdentifier else {
      throw RetainedCalendarBridgeApplyError.calendarIdentityChanged(
        expected: expectedCalendarEventExternalIdentifier,
        actual: task.identity.calendarEventExternalIdentifier
      )
    }
    guard let page = pages.first(where: { $0.projectID == projectID }),
      let managedTaskIndex = page.managedTasks.firstIndex(where: { $0.taskID == taskID })
    else {
      throw RetainedCalendarBridgeApplyError.unmanagedTask(taskID)
    }
    return Context(store: store, page: page, task: task, managedTaskIndex: managedTaskIndex)
  }

  private static func loadPages(
    from store: LogseqProjectPageStore
  ) async throws -> [LogseqProjectPageStore.PageSnapshot] {
    do {
      return try await store.loadProjectPagesInScope()
    } catch {
      throw RetainedCalendarBridgeApplyError.retainedProjectionFailed(error.localizedDescription)
    }
  }

  private static func validateCurrentDecision(
    _ expected: RetainedCalendarBridgeDecision,
    for task: RetainedTask
  ) throws {
    let actual = RetainedCalendarBridgePolicy.decision(for: task)
    guard actual == expected else {
      throw RetainedCalendarBridgeApplyError.staleCalendarDecision(
        expected: expected,
        actual: actual
      )
    }
  }

  private static func retainedSnapshot(
    from pages: [LogseqProjectPageStore.PageSnapshot]
  ) throws -> RetainedWorkspaceSnapshot {
    do {
      return try RetainedProjectionBuilder.build(.init(pages: pages))
    } catch {
      throw RetainedCalendarBridgeApplyError.retainedProjectionFailed(error.localizedDescription)
    }
  }

  private static func updateCalendarIdentity(
    _ calendarEventExternalIdentifier: String?,
    using context: Context
  ) async throws {
    var managedTasks = context.page.managedTasks
    managedTasks[context.managedTaskIndex].calendarEventExternalIdentifier =
      normalizedIdentifier(calendarEventExternalIdentifier)
    try await context.store.updateManagedTasks(
      in: context.page,
      expectedManagedTasks: context.page.managedTasks,
      managedTasks: managedTasks
    )
  }

  private static func rollbackCreatedEvent(
    _ externalIdentifier: String,
    eventWriter: RetainedCalendarEventWriting,
    writeError: Error
  ) async throws {
    do {
      guard try await eventWriter.removeOwnedEvent(externalIdentifier: externalIdentifier, marker: nil) else {
        throw RetainedCalendarBridgeApplyError.ownedEventMissing(externalIdentifier)
      }
    } catch {
      throw RetainedCalendarBridgeApplyError.createdEventRollbackFailed(
        writeError: writeError.localizedDescription,
        rollbackError: error.localizedDescription
      )
    }
  }

  private static func normalizedWrittenIdentifier(_ value: String?) throws -> String {
    guard let value = normalizedIdentifier(value) else {
      throw RetainedCalendarBridgeApplyError.missingWrittenExternalIdentifier
    }
    return value
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

@MainActor
final class EventKitRetainedCalendarEventWriter: RetainedCalendarEventWriting {
  private static let ownedCalendarIdentifierKey = "retained.calendar.ownedCalendarIdentifier"
  private static let ownedCalendarTitle = "Brain Unfog Schedule"

  private let eventStore: EKEventStore
  private let userDefaults: UserDefaults

  init(
    eventStore: EKEventStore = EKEventStore(),
    userDefaults: UserDefaults = .standard
  ) {
    self.eventStore = eventStore
    self.userDefaults = userDefaults
  }

  func upsertOwnedEvent(
    _ request: RetainedCalendarBridgeUpsertRequest,
    marker _: RetainedCalendarBridgeWriteMarker?
  ) async throws -> RetainedCalendarEventWriteResult {
    guard try await requestAccessIfNeeded() else {
      throw RetainedCalendarEventWriterError.accessDenied
    }
    let event: EKEvent
    if let externalIdentifier = request.externalIdentifier {
      let ownedCalendar = try resolvedStoredOwnedCalendar()
      guard let resolvedEvent = try resolvedUniqueEvent(
        externalIdentifier: externalIdentifier,
        ownedCalendarIdentifier: ownedCalendar.calendarIdentifier
      ) else {
        throw RetainedCalendarEventWriterError.ownedEventMissing(externalIdentifier)
      }
      event = resolvedEvent
      event.calendar = ownedCalendar
    } else {
      let ownedCalendar = try resolvedOrCreateOwnedCalendar()
      event = EKEvent(eventStore: eventStore)
      event.calendar = ownedCalendar
    }
    let resolvedTitle = normalizedTitle(request.title)
    let resolvedDurationMinutes = max(5, request.durationMinutes)
    event.title = resolvedTitle
    event.startDate = request.startDate
    event.endDate = Calendar.autoupdatingCurrent.date(
      byAdding: .minute,
      value: resolvedDurationMinutes,
      to: request.startDate
    ) ?? request.startDate
    event.isAllDay = false
    event.recurrenceRules = nil

    do {
      try eventStore.save(event, span: .thisEvent)
    } catch {
      throw RetainedCalendarEventWriterError.saveFailed(error.localizedDescription)
    }
    guard let externalIdentifier = normalizedIdentifier(event.calendarItemExternalIdentifier) else {
      throw RetainedCalendarEventWriterError.missingExternalIdentifier
    }
    return RetainedCalendarEventWriteResult(
      externalIdentifier: externalIdentifier,
      title: resolvedTitle,
      startDate: request.startDate,
      durationMinutes: resolvedDurationMinutes
    )
  }

  func removeOwnedEvent(
    externalIdentifier: String,
    marker _: RetainedCalendarBridgeWriteMarker?
  ) async throws -> Bool {
    guard try await requestAccessIfNeeded() else {
      throw RetainedCalendarEventWriterError.accessDenied
    }
    let ownedCalendar = try resolvedStoredOwnedCalendar()
    guard let event = try resolvedUniqueEvent(
      externalIdentifier: externalIdentifier,
      ownedCalendarIdentifier: ownedCalendar.calendarIdentifier
    ) else {
      throw RetainedCalendarEventWriterError.ownedEventMissing(externalIdentifier)
    }
    do {
      try eventStore.remove(event, span: .thisEvent)
      return true
    } catch {
      throw RetainedCalendarEventWriterError.removeFailed(error.localizedDescription)
    }
  }

  private func resolvedUniqueEvent(
    externalIdentifier: String,
    ownedCalendarIdentifier: String
  ) throws -> EKEvent? {
    guard let externalIdentifier = normalizedIdentifier(externalIdentifier) else { return nil }
    var candidates = eventStore.calendarItems(withExternalIdentifier: externalIdentifier)
      .compactMap { $0 as? EKEvent }
    if let event = eventStore.event(withIdentifier: externalIdentifier) {
      candidates.append(event)
    }
    let uniqueCandidates = uniqueEvents(candidates)
    guard uniqueCandidates.count <= 1 else {
      throw RetainedCalendarEventWriterError.eventMatchAmbiguous(externalIdentifier)
    }
    guard let event = uniqueCandidates.first else { return nil }
    guard event.calendar.calendarIdentifier == ownedCalendarIdentifier else {
      throw RetainedCalendarEventWriterError.foreignEvent(externalIdentifier)
    }
    return event
  }

  private func resolvedStoredOwnedCalendar() throws -> EKCalendar {
    if let identifier = normalizedIdentifier(userDefaults.string(forKey: Self.ownedCalendarIdentifierKey)),
      let calendar = eventStore.calendar(withIdentifier: identifier),
      calendar.title == Self.ownedCalendarTitle
    {
      return calendar
    }

    throw RetainedCalendarEventWriterError.ownedCalendarMissing
  }

  private func resolvedOrCreateOwnedCalendar() throws -> EKCalendar {
    if let calendar = try? resolvedStoredOwnedCalendar() {
      return calendar
    }

    let titleMatches = eventStore.calendars(for: .event).filter { $0.title == Self.ownedCalendarTitle }
    if !titleMatches.isEmpty {
      throw RetainedCalendarEventWriterError.ownedCalendarAmbiguous
    }

    guard let source = preferredEventSource() else {
      throw RetainedCalendarEventWriterError.writableSourceUnavailable
    }
    let calendar = EKCalendar(for: .event, eventStore: eventStore)
    calendar.source = source
    calendar.title = Self.ownedCalendarTitle
    if let defaultColor = eventStore.defaultCalendarForNewEvents?.cgColor {
      calendar.cgColor = defaultColor
    }
    do {
      try eventStore.saveCalendar(calendar, commit: true)
    } catch {
      throw RetainedCalendarEventWriterError.saveFailed(error.localizedDescription)
    }
    userDefaults.set(calendar.calendarIdentifier, forKey: Self.ownedCalendarIdentifierKey)
    return calendar
  }

  private func preferredEventSource() -> EKSource? {
    if let source = eventStore.defaultCalendarForNewEvents?.source {
      return source
    }
    let preferredSourceTypes: [EKSourceType] = [.local, .calDAV, .exchange]
    for sourceType in preferredSourceTypes {
      if let source = eventStore.sources.first(where: { $0.sourceType == sourceType }) {
        return source
      }
    }
    return eventStore.sources.first
  }

  private func requestAccessIfNeeded() async throws -> Bool {
    let authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    switch authorizationStatus {
    case .authorized, .fullAccess:
      return true
    case .notDetermined:
      let promptAttemptedKey = ScheduleCalendarAccessPromptPolicy.promptAttemptedKey
      guard ScheduleCalendarAccessPromptPolicy.shouldRequestAccess(
        authorizationStatus: authorizationStatus,
        promptAttempted: userDefaults.bool(forKey: promptAttemptedKey)
      ) else {
        return false
      }
      userDefaults.set(true, forKey: promptAttemptedKey)
      return try await eventStore.requestFullAccessToEvents()
    case .denied, .restricted, .writeOnly:
      return false
    @unknown default:
      return false
    }
  }

  private func uniqueEvents(_ events: [EKEvent]) -> [EKEvent] {
    var seen: Set<String> = []
    return events.filter { event in
      let key = [
        event.eventIdentifier,
        event.calendarItemExternalIdentifier,
        event.calendarItemIdentifier,
        event.calendar?.calendarIdentifier,
      ]
      .compactMap { $0 }
      .joined(separator: "|")
      return seen.insert(key).inserted
    }
  }

  private func normalizedTitle(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled Event" : trimmed
  }

  private func normalizedIdentifier(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
