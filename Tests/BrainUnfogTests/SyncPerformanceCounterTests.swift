import XCTest
@testable import BrainUnfog

final class SyncPerformanceCounterTests: XCTestCase {
  func testMeasureRecordsOperationDurationAndReset() throws {
    SyncPerformanceCounter.reset()
    defer { SyncPerformanceCounter.reset() }

    let value = SyncPerformanceCounter.measure(.editorSave) {
      Thread.sleep(forTimeInterval: 0.001)
      return 42
    }

    XCTAssertEqual(value, 42)
    let snapshot = SyncPerformanceCounter.operationSnapshot()
    let editorSave = try XCTUnwrap(snapshot[SyncPerformanceOperation.editorSave.rawValue])
    XCTAssertEqual(editorSave.count, 1)
    XCTAssertGreaterThan(editorSave.totalNanoseconds, 0)
    XCTAssertGreaterThan(editorSave.maxNanoseconds, 0)

    SyncPerformanceCounter.reset()
    XCTAssertNil(
      SyncPerformanceCounter.operationSnapshot()[SyncPerformanceOperation.editorSave.rawValue]
    )
  }

  func testMeasureAsyncRecordsOperationOnThrowingPath() async throws {
    SyncPerformanceCounter.reset()
    defer { SyncPerformanceCounter.reset() }

    do {
      _ = try await SyncPerformanceCounter.measureAsync(.remindersFetch) {
        try await Task.sleep(nanoseconds: 1_000_000)
        throw TestError.expected
      }
      XCTFail("Expected measureAsync body to throw.")
    } catch TestError.expected {
      let snapshot = SyncPerformanceCounter.operationSnapshot()
      let remindersFetch = try XCTUnwrap(
        snapshot[SyncPerformanceOperation.remindersFetch.rawValue]
      )
      XCTAssertEqual(remindersFetch.count, 1)
      XCTAssertGreaterThan(remindersFetch.totalNanoseconds, 0)
      XCTAssertGreaterThan(remindersFetch.maxNanoseconds, 0)
    }
  }

  func testDiagnosticReportIncludesCountersAndOperationDurations() {
    SyncPerformanceCounter.reset()
    defer { SyncPerformanceCounter.reset() }

    SyncPerformanceCounter.recordEventKitFetch()
    SyncPerformanceCounter.record(.monthLayout, durationNanoseconds: 2_500_000)

    let report = SyncPerformanceCounter.diagnosticReport()

    XCTAssertTrue(report.contains("eventKitFetchCount=1"))
    XCTAssertTrue(report.contains("monthLayout: count=1"))
    XCTAssertTrue(report.contains("total=2.50 ms"))
    XCTAssertTrue(report.contains("avg=2.50 ms"))
    XCTAssertTrue(report.contains("max=2.50 ms"))
  }

  private enum TestError: Error {
    case expected
  }
}
