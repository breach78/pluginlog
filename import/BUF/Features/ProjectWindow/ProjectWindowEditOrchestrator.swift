import SwiftUI

@MainActor
final class ProjectWindowEditOrchestrator: ObservableObject {
  private var deferredSaveTask: Task<Void, Never>?
  private var projectMetaSaveTask: Task<Void, Never>?
  private var normalizedProjectDetailRefreshTask: Task<Void, Never>?

  func cancelDeferredSave() {
    deferredSaveTask?.cancel()
    deferredSaveTask = nil
  }

  func cancelAll() {
    cancelDeferredSave()
    projectMetaSaveTask?.cancel()
    projectMetaSaveTask = nil
    normalizedProjectDetailRefreshTask?.cancel()
    normalizedProjectDetailRefreshTask = nil
  }

  func scheduleProjectMetaSave(
    delay: Duration = .milliseconds(220),
    shouldSave: @escaping @MainActor () -> Bool,
    save: @escaping @MainActor () throws -> Void,
    markSaved: @escaping @MainActor () -> Void,
    onError: @escaping @MainActor (Error) -> Void
  ) {
    projectMetaSaveTask?.cancel()
    projectMetaSaveTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }

      guard let self else { return }
      guard !Task.isCancelled else {
        self.projectMetaSaveTask = nil
        return
      }
      guard shouldSave() else {
        self.projectMetaSaveTask = nil
        return
      }

      do {
        try save()
        markSaved()
      } catch {
        onError(error)
      }

      self.projectMetaSaveTask = nil
    }
  }

  func scheduleDeferredSave(
    waitUntilReady: @escaping @MainActor () async -> Bool,
    save: @escaping @MainActor () throws -> Void,
    onSaved: @escaping @MainActor () -> Void,
    onError: @escaping @MainActor (Error) -> Void
  ) {
    cancelDeferredSave()
    deferredSaveTask = Task { @MainActor [weak self] in
      let isReady = await waitUntilReady()
      guard let self else { return }
      guard isReady, !Task.isCancelled else {
        self.deferredSaveTask = nil
        return
      }

      do {
        try save()
        onSaved()
      } catch {
        onError(error)
      }

      self.deferredSaveTask = nil
    }
  }

  func scheduleNormalizedProjectSnapshotRefresh(
    refresh: @escaping @MainActor () async throws -> ProjectDetailSnapshot?,
    applySnapshot: @escaping @MainActor (ProjectDetailSnapshot?) -> Void,
    onFailure: @escaping (Error) -> Void
  ) {
    normalizedProjectDetailRefreshTask?.cancel()
    normalizedProjectDetailRefreshTask = Task { [weak self] in
      guard let self else { return }

      do {
        let snapshot = try await refresh()
        try Task.checkCancellation()
        await MainActor.run {
          applySnapshot(snapshot)
          self.normalizedProjectDetailRefreshTask = nil
        }
      } catch is CancellationError {
        await MainActor.run {
          self.normalizedProjectDetailRefreshTask = nil
        }
      } catch {
        guard !Task.isCancelled else {
          await MainActor.run {
            self.normalizedProjectDetailRefreshTask = nil
          }
          return
        }

        await MainActor.run {
          applySnapshot(nil)
          self.normalizedProjectDetailRefreshTask = nil
        }
        onFailure(error)
      }
    }
  }
}
