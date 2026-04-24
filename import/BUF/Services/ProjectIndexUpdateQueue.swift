import Foundation

@MainActor
final class ProjectIndexUpdateQueue {
  typealias StoreProvider = @MainActor (UUID) -> ProjectDocumentStore?
  typealias FlushObserver = @MainActor (Set<UUID>) async -> Void

  private let debounceDelay: Duration
  private let storeProvider: StoreProvider
  private let flushObserver: FlushObserver?
  private var pendingPlansByProjectID: [UUID: ProjectReadModelRefreshPlan] = [:]
  private var flushTask: Task<Void, Never>?

  init(
    debounceDelay: Duration = .milliseconds(800),
    storeProvider: @escaping StoreProvider,
    flushObserver: FlushObserver? = nil
  ) {
    self.debounceDelay = debounceDelay
    self.storeProvider = storeProvider
    self.flushObserver = flushObserver
  }

  func enqueue(_ plan: ProjectReadModelRefreshPlan, for projectID: UUID) {
    guard !plan.isNone else { return }
    let existingPlan = pendingPlansByProjectID[projectID] ?? .none
    pendingPlansByProjectID[projectID] = existingPlan.merged(with: plan)
    scheduleFlush()
  }

  func cancelPendingFlush() {
    flushTask?.cancel()
    flushTask = nil
  }

  func flushNow(projectIDs: Set<UUID>? = nil) async {
    flushTask?.cancel()
    flushTask = nil

    let selectedPlansByProjectID: [UUID: ProjectReadModelRefreshPlan]
    if let projectIDs {
      selectedPlansByProjectID = pendingPlansByProjectID.filter { projectIDs.contains($0.key) }
      pendingPlansByProjectID = pendingPlansByProjectID.filter { !projectIDs.contains($0.key) }
    } else {
      selectedPlansByProjectID = pendingPlansByProjectID
      pendingPlansByProjectID = [:]
    }

    guard !selectedPlansByProjectID.isEmpty else { return }
    await flush(plansByProjectID: selectedPlansByProjectID)
  }

  private func scheduleFlush() {
    flushTask?.cancel()
    let debounceDelay = self.debounceDelay
    flushTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: debounceDelay)
      } catch {
        return
      }

      guard let self else { return }
      guard !Task.isCancelled else { return }
      flushTask = nil
      await flush()
    }
  }

  private func flush() async {
    let plansByProjectID = pendingPlansByProjectID
    pendingPlansByProjectID = [:]
    await flush(plansByProjectID: plansByProjectID)
  }

  private func flush(
    plansByProjectID: [UUID: ProjectReadModelRefreshPlan]
  ) async {
    var failedPlansByProjectID: [UUID: ProjectReadModelRefreshPlan] = [:]
    var refreshedProjectIDs: Set<UUID> = []

    for projectID in plansByProjectID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard let plan = plansByProjectID[projectID] else { continue }
      guard let store = storeProvider(projectID) else { continue }

      do {
        try await store.refreshIndexes(using: plan)
        refreshedProjectIDs.insert(projectID)
      } catch {
        let existingPlan = failedPlansByProjectID[projectID] ?? .none
        failedPlansByProjectID[projectID] = existingPlan.merged(with: plan)
      }
    }

    if !refreshedProjectIDs.isEmpty {
      await flushObserver?(refreshedProjectIDs)
    }

    guard !failedPlansByProjectID.isEmpty else { return }
    for (projectID, plan) in failedPlansByProjectID {
      let existingPlan = pendingPlansByProjectID[projectID] ?? .none
      pendingPlansByProjectID[projectID] = existingPlan.merged(with: plan)
    }
    scheduleFlush()
  }
}
