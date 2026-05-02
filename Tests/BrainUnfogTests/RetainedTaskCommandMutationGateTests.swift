import XCTest
@testable import BrainUnfog

final class RetainedTaskCommandMutationGateTests: XCTestCase {
  func testSecondAcquireForSameKeyWaitsUntilFirstLeaseReleases() async {
    let gate = RetainedTaskCommandMutationGate()
    let key = RetainedTaskCommandMutationKey.task(UUID())
    let firstLease = await gate.acquire([key])
    let flag = RetainedTaskCommandMutationGateTestFlag()
    let task = Task {
      let secondLease = await gate.acquire([key])
      await flag.markAcquired()
      await secondLease.release()
    }

    try? await Task.sleep(for: .milliseconds(50))
    let didAcquireBeforeRelease = await flag.didAcquire()
    XCTAssertFalse(didAcquireBeforeRelease)

    await firstLease.release()
    _ = await task.result
    let didAcquireAfterRelease = await flag.didAcquire()
    XCTAssertTrue(didAcquireAfterRelease)
  }

  func testDifferentKeysCanAcquireWithoutWaiting() async {
    let gate = RetainedTaskCommandMutationGate()
    let firstLease = await gate.acquire([.task(UUID())])
    let secondLease = await gate.acquire([.task(UUID())])

    await firstLease.release()
    await secondLease.release()
  }

  func testOverlappingProjectKeyWaitsAcrossDifferentTasks() async {
    let gate = RetainedTaskCommandMutationGate()
    let projectID = UUID()
    let firstLease = await gate.acquire([.project(projectID), .task(UUID())])
    let flag = RetainedTaskCommandMutationGateTestFlag()
    let task = Task {
      let secondLease = await gate.acquire([.project(projectID), .task(UUID())])
      await flag.markAcquired()
      await secondLease.release()
    }

    try? await Task.sleep(for: .milliseconds(50))
    let didAcquireBeforeRelease = await flag.didAcquire()
    XCTAssertFalse(didAcquireBeforeRelease)

    await firstLease.release()
    _ = await task.result
    let didAcquireAfterRelease = await flag.didAcquire()
    XCTAssertTrue(didAcquireAfterRelease)
  }
}

private actor RetainedTaskCommandMutationGateTestFlag {
  private var acquired = false

  func didAcquire() -> Bool {
    acquired
  }

  func markAcquired() {
    acquired = true
  }
}
