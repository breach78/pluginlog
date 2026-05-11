import Foundation

enum SyncPerformanceOperation: String, CaseIterable, Sendable {
  case remindersFetch
  case projectionBuild
  case monthLayout
  case dragFrameUpdate
  case editorSave
}

struct SyncPerformanceOperationSnapshot: Equatable, Sendable {
  let count: Int
  let totalNanoseconds: UInt64
  let maxNanoseconds: UInt64
}

enum SyncPerformanceCounter {
  private struct OperationAccumulator {
    var count = 0
    var totalNanoseconds: UInt64 = 0
    var maxNanoseconds: UInt64 = 0

    mutating func record(durationNanoseconds: UInt64) {
      count += 1
      totalNanoseconds += durationNanoseconds
      maxNanoseconds = max(maxNanoseconds, durationNanoseconds)
    }

    var snapshot: SyncPerformanceOperationSnapshot {
      SyncPerformanceOperationSnapshot(
        count: count,
        totalNanoseconds: totalNanoseconds,
        maxNanoseconds: maxNanoseconds
      )
    }
  }

  private static let lock = NSLock()
  private nonisolated(unsafe) static var contextSaveCountStorage = 0
  private nonisolated(unsafe) static var eventKitFetchCountStorage = 0
  private nonisolated(unsafe) static var workspaceCacheInvalidationCountStorage = 0
  private nonisolated(unsafe) static var normalizedRebuildCountStorage = 0
  private nonisolated(unsafe) static var ekObserverFireCountStorage = 0
  private nonisolated(unsafe) static var operationStorage: [String: OperationAccumulator] = [:]

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

  static func record(
    _ operation: SyncPerformanceOperation,
    durationNanoseconds: UInt64
  ) {
    lock.lock()
    operationStorage[operation.rawValue, default: OperationAccumulator()]
      .record(durationNanoseconds: durationNanoseconds)
    lock.unlock()
  }

  static func measure<T>(
    _ operation: SyncPerformanceOperation,
    _ body: () throws -> T
  ) rethrows -> T {
    let start = DispatchTime.now().uptimeNanoseconds
    defer {
      record(
        operation,
        durationNanoseconds: DispatchTime.now().uptimeNanoseconds - start
      )
    }
    return try body()
  }

  static func measureAsync<T>(
    _ operation: SyncPerformanceOperation,
    _ body: () async throws -> T
  ) async rethrows -> T {
    let start = DispatchTime.now().uptimeNanoseconds
    defer {
      record(
        operation,
        durationNanoseconds: DispatchTime.now().uptimeNanoseconds - start
      )
    }
    return try await body()
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

  static func operationSnapshot() -> [String: SyncPerformanceOperationSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    return operationStorage.mapValues(\.snapshot)
  }

  static func reset() {
    lock.lock()
    contextSaveCountStorage = 0
    eventKitFetchCountStorage = 0
    workspaceCacheInvalidationCountStorage = 0
    normalizedRebuildCountStorage = 0
    ekObserverFireCountStorage = 0
    operationStorage = [:]
    lock.unlock()
  }
}
