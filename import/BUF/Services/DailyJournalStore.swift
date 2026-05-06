import Foundation

struct DailyJournalEntry: Identifiable, Equatable {
  let date: Date
  let fileURL: URL
  let vaultRelativePath: String
  let text: String

  var id: Date {
    date
  }
}

struct DailyJournalStore {
  let vaultRootURL: URL
  var calendar: Calendar
  let fileManager: FileManager

  init(
    vaultRootURL: URL,
    calendar: Calendar = .autoupdatingCurrent,
    fileManager: FileManager = .default
  ) {
    self.vaultRootURL = vaultRootURL.standardizedFileURL
    self.calendar = calendar
    self.fileManager = fileManager
  }

  var journalRootURL: URL {
    ObsidianVaultLayout(vaultRootURL: vaultRootURL, fileManager: fileManager).rawJournalsRootURL
  }

  func entry(for date: Date) throws -> DailyJournalEntry {
    let normalizedDate = startOfDay(for: date)
    let fileURL = fileURL(for: normalizedDate)
    let text: String
    if fileManager.fileExists(atPath: fileURL.path) {
      text = try String(contentsOf: fileURL, encoding: .utf8)
    } else {
      text = ""
    }
    return DailyJournalEntry(
      date: normalizedDate,
      fileURL: fileURL,
      vaultRelativePath: vaultRelativePath(for: normalizedDate),
      text: text
    )
  }

  func entries(startingAt date: Date, count: Int) throws -> [DailyJournalEntry] {
    guard count > 0 else { return [] }
    let startDate = startOfDay(for: date)
    return try (0..<count).map { offset in
      let date = calendar.date(byAdding: .day, value: -offset, to: startDate) ?? startDate
      return try entry(for: date)
    }
  }

  func precedingEntries(before earliestDate: Date, count: Int) throws -> [DailyJournalEntry] {
    try existingJournalDates(before: earliestDate, count: count).map { date in
      try entry(for: date)
    }
  }

  @discardableResult
  func save(_ text: String, for date: Date) throws -> DailyJournalEntry {
    let normalizedDate = startOfDay(for: date)
    let normalizedText = DailyJournalTextPolicy.normalized(text)
    try fileManager.createDirectory(
      at: journalRootURL,
      withIntermediateDirectories: true
    )
    try normalizedText.write(
      to: fileURL(for: normalizedDate),
      atomically: true,
      encoding: .utf8
    )
    return try entry(for: normalizedDate)
  }

  func fileURL(for date: Date) -> URL {
    journalRootURL.appendingPathComponent(fileName(for: date), isDirectory: false)
  }

  func vaultRelativePath(for date: Date) -> String {
    "raw/journals/\(fileName(for: date))"
  }

  func fileName(for date: Date) -> String {
    "\(DailyJournalDatePolicy.fileStem(for: startOfDay(for: date), calendar: calendar)).md"
  }

  func startOfDay(for date: Date) -> Date {
    calendar.startOfDay(for: date)
  }

  private func existingJournalDates(before earliestDate: Date, count: Int) throws -> [Date] {
    guard count > 0 else { return [] }
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: journalRootURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return []
    }

    let cutoffDate = startOfDay(for: earliestDate)
    return try fileManager.contentsOfDirectory(
      at: journalRootURL,
      includingPropertiesForKeys: nil
    )
    .compactMap { date(fromFileURL: $0) }
    .filter { $0 < cutoffDate }
    .sorted(by: >)
    .prefix(count)
    .map { $0 }
  }

  private func date(fromFileURL fileURL: URL) -> Date? {
    guard fileURL.pathExtension == "md" else { return nil }
    let stem = fileURL.deletingPathExtension().lastPathComponent
    guard stem.count == 10 else { return nil }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: stem) else { return nil }
    return startOfDay(for: date)
  }
}

enum DailyJournalDatePolicy {
  static func fileStem(for date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

enum DailyJournalTextPolicy {
  static func normalized(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  static func isDirty(currentText: String, committedText: String) -> Bool {
    normalized(currentText) != normalized(committedText)
  }
}
