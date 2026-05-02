import Foundation

enum RetainedTaskCommandMutationKey: Hashable, Sendable {
  case project(UUID)
  case task(UUID)
}

struct RetainedTaskCommandMutationLease: Sendable {
  fileprivate let keys: Set<RetainedTaskCommandMutationKey>
  fileprivate let gate: RetainedTaskCommandMutationGate

  func release() async {
    await gate.release(keys)
  }
}

actor RetainedTaskCommandMutationGate {
  private struct Waiter {
    let keys: Set<RetainedTaskCommandMutationKey>
    let continuation: CheckedContinuation<Void, Never>
  }

  private var activeKeys: Set<RetainedTaskCommandMutationKey> = []
  private var waiters: [Waiter] = []

  func acquire(_ keys: Set<RetainedTaskCommandMutationKey>) async -> RetainedTaskCommandMutationLease {
    guard !keys.isEmpty else {
      return RetainedTaskCommandMutationLease(keys: [], gate: self)
    }

    if activeKeys.isDisjoint(with: keys) {
      activeKeys.formUnion(keys)
      return RetainedTaskCommandMutationLease(keys: keys, gate: self)
    }

    await withCheckedContinuation { continuation in
      waiters.append(Waiter(keys: keys, continuation: continuation))
    }
    return RetainedTaskCommandMutationLease(keys: keys, gate: self)
  }

  fileprivate func release(_ keys: Set<RetainedTaskCommandMutationKey>) {
    guard !keys.isEmpty else { return }
    activeKeys.subtract(keys)
    resumeUnblockedWaiters()
  }

  private func resumeUnblockedWaiters() {
    var index = waiters.startIndex
    while index < waiters.endIndex {
      let waiter = waiters[index]
      if activeKeys.isDisjoint(with: waiter.keys) {
        waiters.remove(at: index)
        activeKeys.formUnion(waiter.keys)
        waiter.continuation.resume()
      } else {
        index += 1
      }
    }
  }
}
