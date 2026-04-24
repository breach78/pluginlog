import Foundation

enum SyncPerformanceCounter {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var contextSaveCountStorage = 0
  private nonisolated(unsafe) static var eventKitFetchCountStorage = 0
  private nonisolated(unsafe) static var workspaceCacheInvalidationCountStorage = 0
  private nonisolated(unsafe) static var normalizedRebuildCountStorage = 0
  private nonisolated(unsafe) static var ekObserverFireCountStorage = 0

  static func recordContextSave() {
    lock.lock()
    contextSaveCountStorage += 1
    lock.unlock()
  }

  static func recordEventKitFetch() {
    lock.lock()
    eventKitFetchCountStorage += 1
    lock.unlock()
  }

  static func recordWorkspaceCacheInvalidation() {
    lock.lock()
    workspaceCacheInvalidationCountStorage += 1
    lock.unlock()
  }

  static func recordNormalizedRebuild() {
    lock.lock()
    normalizedRebuildCountStorage += 1
    lock.unlock()
  }

  static func recordEKObserverFire() {
    lock.lock()
    ekObserverFireCountStorage += 1
    lock.unlock()
  }

  static func snapshot() -> [String: Int] {
    lock.lock()
    defer { lock.unlock() }
    return [
      "contextSaveCount": contextSaveCountStorage,
      "eventKitFetchCount": eventKitFetchCountStorage,
      "workspaceCacheInvalidationCount": workspaceCacheInvalidationCountStorage,
      "normalizedRebuildCount": normalizedRebuildCountStorage,
      "ekObserverFireCount": ekObserverFireCountStorage,
    ]
  }

  static func reset() {
    lock.lock()
    contextSaveCountStorage = 0
    eventKitFetchCountStorage = 0
    workspaceCacheInvalidationCountStorage = 0
    normalizedRebuildCountStorage = 0
    ekObserverFireCountStorage = 0
    lock.unlock()
  }
}
