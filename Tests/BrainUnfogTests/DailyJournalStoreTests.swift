import XCTest
@testable import BrainUnfog

final class DailyJournalStoreTests: XCTestCase {
  func testEntryUsesJournalFolderAndIsoDateFileName() throws {
    let vaultURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = DailyJournalStore(vaultRootURL: vaultURL, calendar: testCalendar)
    let date = try XCTUnwrap(testCalendar.date(from: DateComponents(year: 2026, month: 5, day: 6)))

    let entry = try store.entry(for: date)

    XCTAssertEqual(entry.vaultRelativePath, "raw/journals/2026-05-06.md")
    XCTAssertEqual(
      entry.fileURL.path,
      vaultURL.appendingPathComponent("raw/journals/2026-05-06.md").path
    )
    XCTAssertEqual(entry.text, "")
    XCTAssertFalse(FileManager.default.fileExists(atPath: entry.fileURL.path))
  }

  func testSaveCreatesJournalFileAndNormalizesLineEndings() throws {
    let vaultURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = DailyJournalStore(vaultRootURL: vaultURL, calendar: testCalendar)
    let date = try XCTUnwrap(testCalendar.date(from: DateComponents(year: 2026, month: 5, day: 6)))

    let saved = try store.save("첫 줄\r\n둘째 줄\r셋째 줄", for: date)

    XCTAssertEqual(saved.text, "첫 줄\n둘째 줄\n셋째 줄")
    XCTAssertEqual(
      try String(contentsOf: saved.fileURL, encoding: .utf8),
      "첫 줄\n둘째 줄\n셋째 줄"
    )
  }

  func testEntriesLoadTodayThenPreviousDays() throws {
    let vaultURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = DailyJournalStore(vaultRootURL: vaultURL, calendar: testCalendar)
    let date = try XCTUnwrap(testCalendar.date(from: DateComponents(year: 2026, month: 5, day: 6)))

    let entries = try store.entries(startingAt: date, count: 3)

    XCTAssertEqual(
      entries.map(\.vaultRelativePath),
      [
        "raw/journals/2026-05-06.md",
        "raw/journals/2026-05-05.md",
        "raw/journals/2026-05-04.md",
      ]
    )
  }

  func testPrecedingEntriesLoadOnlyExistingJournalFilesBeforeEarliestLoadedDate() throws {
    let vaultURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: vaultURL) }
    let store = DailyJournalStore(vaultRootURL: vaultURL, calendar: testCalendar)
    let earliestDate = try XCTUnwrap(
      testCalendar.date(from: DateComponents(year: 2026, month: 5, day: 4))
    )
    try store.save("5월 3일", for: try XCTUnwrap(
      testCalendar.date(from: DateComponents(year: 2026, month: 5, day: 3))
    ))
    try store.save("5월 1일", for: try XCTUnwrap(
      testCalendar.date(from: DateComponents(year: 2026, month: 5, day: 1))
    ))

    let entries = try store.precedingEntries(before: earliestDate, count: 3)

    XCTAssertEqual(
      entries.map(\.vaultRelativePath),
      [
        "raw/journals/2026-05-03.md",
        "raw/journals/2026-05-01.md",
      ]
    )
  }

  private var testCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("DailyJournalStore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
