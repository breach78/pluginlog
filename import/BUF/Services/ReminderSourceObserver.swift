import Combine
@preconcurrency import EventKit
import Foundation

@MainActor
final class ReminderSourceObserver: ObservableObject {
  private final class StoreObserverBox: @unchecked Sendable {
    let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
      self.token = token
    }

    func unregister() {
      NotificationCenter.default.removeObserver(token)
    }
  }

  private struct ReminderListOwnerState: Equatable {
    let identifier: String
    let externalIdentifier: String
    let title: String
    let colorHex: String?
  }

  private struct ReminderTaskOwnerState: Equatable {
    let identifier: String
    let externalIdentifier: String?
    let sourceListIdentifier: String
    let title: String
    let noteText: String
    let isCompleted: Bool
    let dueDate: Date?
    let scheduleHasExplicitTime: Bool
    let recurrenceRuleRaw: String?
    let priority: Int
    let modifiedAt: Date
  }

  private struct ReminderOwnerStates {
    let listsByIdentifier: [String: ReminderListOwnerState]
    let tasksByIdentifier: [String: ReminderTaskOwnerState]
  }

  typealias SourceInvalidationHandler = @MainActor (SyncReason) async -> Bool
  typealias ExternalOwnerChangeHandler = @MainActor (AppCommand) async -> Bool

  @Published private(set) var status: String = "Idle"

  private let gateway: ReminderGateway
  private let invalidateSource: SourceInvalidationHandler
  private let handleExternalOwnerChange: ExternalOwnerChangeHandler
  private let eventDebounceDelay: Duration
  private let eventFollowUpDelay: Duration
  private let authorizationStatusProvider: () -> EKAuthorizationStatus

  private var storeObserver: StoreObserverBox?
  private var eventDebounceTask: Task<Void, Never>?
  private var knownReminderListsByIdentifier: [String: ReminderListOwnerState] = [:]
  private var knownReminderTasksByIdentifier: [String: ReminderTaskOwnerState] = [:]

  init(
    gateway: ReminderGateway,
    invalidateSource: @escaping SourceInvalidationHandler,
    handleExternalOwnerChange: @escaping ExternalOwnerChangeHandler,
    eventDebounceDelay: Duration = .milliseconds(900),
    eventFollowUpDelay: Duration = .seconds(2),
    authorizationStatusProvider: @escaping () -> EKAuthorizationStatus = {
      EKEventStore.authorizationStatus(for: .reminder)
    }
  ) {
    self.gateway = gateway
    self.invalidateSource = invalidateSource
    self.handleExternalOwnerChange = handleExternalOwnerChange
    self.eventDebounceDelay = eventDebounceDelay
    self.eventFollowUpDelay = eventFollowUpDelay
    self.authorizationStatusProvider = authorizationStatusProvider
  }

  deinit {
    eventDebounceTask?.cancel()
    storeObserver?.unregister()
  }

  func bootstrap() async {
    registerEventStoreObserverIfNeeded()
    guard await ensureReminderAccessIfNeeded() else { return }
    await invalidateReminderSource(reason: .bootstrap)
    await refreshKnownReminderOwners()
  }

  func startObserving() async {
    registerEventStoreObserverIfNeeded()
    guard await ensureReminderAccessIfNeeded() else { return }
    status = "Observing"
  }

  func refresh(reason: SyncReason) async {
    registerEventStoreObserverIfNeeded()
    guard await ensureReminderAccessIfNeeded() else { return }
    await invalidateReminderSource(reason: reason)
    await refreshKnownReminderOwners()
  }

  func stop() {
    eventDebounceTask?.cancel()
    eventDebounceTask = nil
    storeObserver?.unregister()
    storeObserver = nil
  }

  private func invalidateReminderSource(reason: SyncReason) async {
    status = "Refreshing"
    let didRefresh = await invalidateSource(reason)
    status = didRefresh ? "Refreshed (\(reason.rawValue))" : "Refresh skipped (\(reason.rawValue))"
  }

  private func applyExternalReminderOwnerChanges() async {
    guard let currentReminderOwners = await loadReminderOwnerStates() else {
      status = "External change skipped (unreadable owner state)"
      return
    }

    defer {
      knownReminderListsByIdentifier = currentReminderOwners.listsByIdentifier
      knownReminderTasksByIdentifier = currentReminderOwners.tasksByIdentifier
    }

    let commands = externalOwnerChangeCommands(from: currentReminderOwners)
    guard !commands.isEmpty else {
      status = "External change skipped (no scoped owner delta)"
      return
    }

    status = "Applying external owner change"
    var didApply = false
    for command in commands {
      let didApplyCommand = await handleExternalOwnerChange(command)
      didApply = didApply || didApplyCommand
    }
    status = didApply
      ? "Refreshed (\(SyncReason.eventStoreChanged.rawValue))"
      : "Refresh skipped (\(SyncReason.eventStoreChanged.rawValue))"
  }

  private func refreshKnownReminderOwners() async {
    if let states = await loadReminderOwnerStates() {
      knownReminderListsByIdentifier = states.listsByIdentifier
      knownReminderTasksByIdentifier = states.tasksByIdentifier
    }
  }

  private func loadReminderOwnerStates() async -> ReminderOwnerStates? {
    let provider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    guard let lists = try? await provider.fetchAllLists(),
      let itemsByListIdentifier = try? await provider.fetchItemsByList(for: lists)
    else {
      return nil
    }

    let listsByIdentifier = Dictionary(
      uniqueKeysWithValues: lists.map { list in
        (
          list.identifier,
          ReminderListOwnerState(
            identifier: list.identifier,
            externalIdentifier: list.externalIdentifier ?? list.identifier,
            title: list.title.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: list.colorHex
          )
        )
      }
    )

    var tasksByIdentifier: [String: ReminderTaskOwnerState] = [:]
    for list in lists {
      for item in itemsByListIdentifier[list.identifier, default: []] {
        tasksByIdentifier[item.identifier] = ReminderTaskOwnerState(
          identifier: item.identifier,
          externalIdentifier: normalizedOwnerID(item.externalIdentifier),
          sourceListIdentifier: item.sourceListIdentifier,
          title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
          noteText: ReminderNoteSourceCodec.normalizeReminderRawNote(item.notes),
          isCompleted: item.isCompleted,
          dueDate: item.dueDate,
          scheduleHasExplicitTime: item.scheduleHasExplicitTime,
          recurrenceRuleRaw: normalizedOwnerID(item.recurrenceRuleRaw),
          priority: item.priority,
          modifiedAt: item.modifiedAt
        )
      }
    }

    return ReminderOwnerStates(
      listsByIdentifier: listsByIdentifier,
      tasksByIdentifier: tasksByIdentifier
    )
  }

  private func externalOwnerChangeCommands(
    from currentReminderOwners: ReminderOwnerStates
  ) -> [AppCommand] {
    var commands: [AppCommand] = []
    if let listCommand = reminderListExternalOwnerChangeCommand(
      from: currentReminderOwners.listsByIdentifier
    ) {
      commands.append(listCommand)
    }
    if let taskCommand = reminderTaskExternalOwnerChangeCommand(
      from: currentReminderOwners.tasksByIdentifier
    ) {
      commands.append(taskCommand)
    }
    return commands
  }

  private func reminderListExternalOwnerChangeCommand(
    from currentReminderLists: [String: ReminderListOwnerState]
  ) -> AppCommand? {
    guard !knownReminderListsByIdentifier.isEmpty else { return nil }

    var changedIdentifiers: [String] = []
    var changedExternalIdentifiers: [String] = []

    for (identifier, currentState) in currentReminderLists {
      guard let previousState = knownReminderListsByIdentifier[identifier] else { continue }
      guard previousState.title != currentState.title || previousState.colorHex != currentState.colorHex
      else {
        continue
      }
      changedIdentifiers.append(currentState.identifier)
      changedExternalIdentifiers.append(currentState.externalIdentifier)
    }

    for (identifier, previousState) in knownReminderListsByIdentifier
    where currentReminderLists[identifier] == nil
    {
      changedIdentifiers.append(previousState.identifier)
      changedExternalIdentifiers.append(previousState.externalIdentifier)
    }

    let normalizedIdentifiers = uniqueOwnerIDs(changedIdentifiers)
    let normalizedExternalIdentifiers = uniqueOwnerIDs(changedExternalIdentifiers)
    guard !normalizedIdentifiers.isEmpty || !normalizedExternalIdentifiers.isEmpty else { return nil }

    return .externalOwnerChange(
      ownerStore: .reminder,
      ownerIDs: uniqueOwnerIDs(normalizedIdentifiers + normalizedExternalIdentifiers),
      changedFields: [.listMetadata]
    )
  }

  private func reminderTaskExternalOwnerChangeCommand(
    from currentReminderTasks: [String: ReminderTaskOwnerState]
  ) -> AppCommand? {
    guard !knownReminderTasksByIdentifier.isEmpty else { return nil }

    var changedOwnerIDs: [String] = []

    for (identifier, currentState) in currentReminderTasks {
      guard let previousState = knownReminderTasksByIdentifier[identifier] else {
        changedOwnerIDs.append(contentsOf: reminderTaskOwnerIDs(for: currentState))
        continue
      }
      guard previousState != currentState else { continue }
      changedOwnerIDs.append(contentsOf: reminderTaskOwnerIDs(for: currentState))
    }

    for (identifier, previousState) in knownReminderTasksByIdentifier
    where currentReminderTasks[identifier] == nil
    {
      changedOwnerIDs.append(contentsOf: reminderTaskOwnerIDs(for: previousState))
    }

    let normalizedOwnerIDs = uniqueOwnerIDs(changedOwnerIDs)
    guard !normalizedOwnerIDs.isEmpty else { return nil }

    return .externalOwnerChange(
      ownerStore: .reminder,
      ownerIDs: normalizedOwnerIDs,
      changedFields: AppOwnerField.reminderTaskExternalChangeFields
    )
  }

  private func reminderTaskOwnerIDs(for state: ReminderTaskOwnerState) -> [String] {
    [
      state.identifier,
      state.externalIdentifier,
      state.sourceListIdentifier,
    ]
    .compactMap(normalizedOwnerID)
  }

  private func uniqueOwnerIDs(_ ownerIDs: [String]) -> [String] {
    Array(NSOrderedSet(array: ownerIDs.compactMap(normalizedOwnerID))) as? [String] ?? []
  }

  private func normalizedOwnerID(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func ensureReminderAccessIfNeeded() async -> Bool {
    let authorizationStatus = authorizationStatusProvider()
    switch authorizationStatus {
    case .notDetermined:
      do {
        let granted = try await gateway.requestAccess()
        status = granted ? "Refreshing" : "Reminders access denied"
        return granted
      } catch {
        status = "Refresh failed: \(error.localizedDescription)"
        AppLogger.sync.error(
          "request reminders access failed: \(error.localizedDescription, privacy: .public)"
        )
        return false
      }
    case .restricted, .denied:
      status = "Reminders access denied"
      return false
    case .fullAccess, .writeOnly, .authorized:
      return true
    @unknown default:
      return true
    }
  }

  private func registerEventStoreObserverIfNeeded() {
    guard storeObserver == nil else { return }

    let token = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: gateway.eventStore,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        SyncPerformanceCounter.recordEKObserverFire()

        self.eventDebounceTask?.cancel()
        self.eventDebounceTask = Task { @MainActor [weak self] in
          do {
            try await Task.sleep(for: self?.eventDebounceDelay ?? .milliseconds(900))
          } catch {
            return
          }

          guard let self else { return }
          guard await self.ensureReminderAccessIfNeeded() else { return }
          AppLogger.sync.info("event store changed; scheduling reminder source refresh")
          await self.invalidateReminderSource(reason: .eventStoreChanged)

          // Reminders/iCloud can publish EKEventStoreChanged before fetchReminders returns
          // the committed item. A delayed pull closes that transient partial-snapshot gap.
          do {
            try await Task.sleep(for: self.eventFollowUpDelay)
          } catch {
            return
          }
          guard await self.ensureReminderAccessIfNeeded() else { return }
          AppLogger.sync.info("event store changed; scheduling delayed reminder source refresh")
          await self.invalidateReminderSource(reason: .eventStoreChanged)
        }
      }
    }

    storeObserver = StoreObserverBox(token: token)
  }
}
