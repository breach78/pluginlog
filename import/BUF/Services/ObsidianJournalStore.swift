import Foundation

struct ObsidianJournalEntry: Identifiable, Hashable, Sendable {
  let id: String
  let day: Date
  let occurredAt: Date
  let body: String
}

enum ObsidianJournalStoreError: LocalizedError {
  case emptyEntry

  var errorDescription: String? {
    switch self {
    case .emptyEntry:
      return "저널 엔트리가 비어 있습니다."
    }
  }
}

struct ObsidianJournalDaySummaryBackup: Equatable, Sendable {
  let markdown: String
  let providerSignature: String
  let summaryInputSignature: String?
  let usage: GeminiGenerateContentSummaryService.SummaryUsage?
}

enum ObsidianJournalDaySummaryBackupLoadResult: Equatable, Sendable {
  case missing
  case malformed
  case loaded(ObsidianJournalDaySummaryBackup)
}

actor ObsidianJournalStore {
  private static let managedSectionHeader = "## Brain Unfog"
  private static let summaryBackupSectionHeader = "## Brain Unfog Day Summary Backup"

  private let rootURL: URL
  private let fileManager: FileManager

  init(rootURL: URL, fileManager: FileManager = FileManager()) {
    self.rootURL = rootURL
    self.fileManager = fileManager
  }

  func prepareDirectory() throws {
    do {
      try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    } catch {
      AppLogger.notes.error(
        "prepare journal directory failed. root=\(self.rootURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  func entries(for day: Date) throws -> [ObsidianJournalEntry] {
    try prepareDirectory()
    let fileURL = journalFileURL(for: day)
    guard itemExists(at: fileURL) else { return [] }
    let contents = try readText(at: fileURL)
    return parseEntries(from: contents, for: day)
  }

  @discardableResult
  func appendEntry(_ text: String, at occurredAt: Date) throws -> ObsidianJournalEntry {
    try saveEntry(text, existingEntryID: nil, at: occurredAt)
  }

  @discardableResult
  func saveEntry(_ text: String, existingEntryID: String?, at occurredAt: Date) throws
    -> ObsidianJournalEntry
  {
    let normalizedBody = normalizedEntryBody(text)
    guard !normalizedBody.isEmpty else {
      throw ObsidianJournalStoreError.emptyEntry
    }

    try prepareDirectory()

    let day = Calendar.autoupdatingCurrent.startOfDay(for: occurredAt)
    let fileURL = journalFileURL(for: day)
    let existingContents = itemExists(at: fileURL) ? try readText(at: fileURL) : ""
    let existingEntries = parseEntries(from: existingContents, for: day)

    let entry: ObsidianJournalEntry
    let updatedEntries: [ObsidianJournalEntry]
    if let existingEntryID,
      let existingEntry = existingEntries.first(where: { $0.id == existingEntryID })
    {
      entry = ObsidianJournalEntry(
        id: existingEntry.id,
        day: existingEntry.day,
        occurredAt: existingEntry.occurredAt,
        body: normalizedBody
      )
      updatedEntries = existingEntries.map { currentEntry in
        currentEntry.id == existingEntryID ? entry : currentEntry
      }
    } else {
      entry = ObsidianJournalEntry(
        id: "\(dayFileName(for: day))-\(Int(occurredAt.timeIntervalSince1970))-\(UUID().uuidString)",
        day: day,
        occurredAt: occurredAt,
        body: normalizedBody
      )
      updatedEntries = existingEntries + [entry]
    }

    let updatedContents = updatedContentsByReplacingManagedEntries(updatedEntries, in: existingContents, day: day)
    try write(updatedContents, to: fileURL)
    return entry
  }

  func saveDaySummaryBackup(
    _ markdown: String,
    for day: Date,
    providerSignature: String,
    summaryInputSignature: String?,
    usage: GeminiGenerateContentSummaryService.SummaryUsage?
  ) throws {
    let normalizedMarkdown = normalizedEntryBody(markdown)
    guard !normalizedMarkdown.isEmpty else { return }

    try prepareDirectory()

    let fileURL = journalFileURL(for: day)
    let existingContents = itemExists(at: fileURL) ? try readText(at: fileURL) : ""
    let updatedContents = updatedContentsByReplacingSummaryBackup(
      normalizedMarkdown,
      in: existingContents,
      day: day,
      providerSignature: providerSignature,
      summaryInputSignature: summaryInputSignature,
      usage: usage
    )
    try write(updatedContents, to: fileURL)
  }

  func loadDaySummaryBackup(for day: Date) throws -> ObsidianJournalDaySummaryBackupLoadResult {
    try prepareDirectory()

    let fileURL = journalFileURL(for: day)
    guard itemExists(at: fileURL) else { return .missing }

    let contents = try readText(at: fileURL)
    return parseDaySummaryBackup(from: contents)
  }

  func availableDays() throws -> [Date] {
    try prepareDirectory()

    let urls = try fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"

    return urls
      .filter { $0.pathExtension.lowercased() == "md" }
      .compactMap { formatter.date(from: $0.deletingPathExtension().lastPathComponent) }
      .sorted()
  }

  private func write(_ contents: String, to fileURL: URL) throws {
    let data = Data(contents.utf8)
    let directory = fileURL.deletingLastPathComponent()
    let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
    let backupName = ".\(fileURL.lastPathComponent).bak"
    let backupURL = directory.appendingPathComponent(backupName)

    do {
      try data.write(to: tempURL, options: .atomic)

      do {
        _ = try fileManager.replaceItemAt(
          fileURL,
          withItemAt: tempURL,
          backupItemName: backupName,
          options: [.usingNewMetadataOnly]
        )
        if itemExists(at: backupURL) {
          try? fileManager.removeItem(at: backupURL)
        }
      } catch {
        if isFileNotFound(error) {
          try fileManager.moveItem(at: tempURL, to: fileURL)
        } else {
          throw error
        }
      }
    } catch {
      if !itemExists(at: fileURL), itemExists(at: backupURL) {
        try? fileManager.moveItem(at: backupURL, to: fileURL)
      }
      if itemExists(at: tempURL) {
        try? fileManager.removeItem(at: tempURL)
      }
      AppLogger.notes.error(
        "write journal failed. file=\(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  private func readText(at fileURL: URL) throws -> String {
    do {
      return try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
      let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
      if String(data: data, encoding: .utf8) == nil {
        AppLogger.notes.error(
          "journal file contains invalid UTF-8; falling back to lossy decode. file=\(fileURL.path, privacy: .public)"
        )
      }
      return String(decoding: data, as: UTF8.self)
    }
  }

  private func parseEntries(from contents: String, for day: Date) -> [ObsidianJournalEntry] {
    let lines = normalizedLineEndings(contents).components(separatedBy: "\n")
    guard let sectionRange = managedSectionRange(in: lines) else { return [] }

    var entries: [ObsidianJournalEntry] = []
    var currentOccurredAt: Date?
    var currentBodyLines: [String] = []
    var ordinal = 0

    func flushCurrentEntry() {
      guard let occurredAt = currentOccurredAt else { return }
      let body = trimmedBody(from: currentBodyLines)
      guard !body.isEmpty else {
        currentBodyLines.removeAll(keepingCapacity: true)
        currentOccurredAt = nil
        return
      }

      entries.append(
        ObsidianJournalEntry(
          id: "\(dayFileName(for: day))-\(ordinal)-\(Int(occurredAt.timeIntervalSince1970))",
          day: day,
          occurredAt: occurredAt,
          body: body
        )
      )
      ordinal += 1
      currentBodyLines.removeAll(keepingCapacity: true)
      currentOccurredAt = nil
    }

    for line in lines[sectionRange] {
      if line.hasPrefix("## ") {
        break
      }

      if line.hasPrefix("- ") {
        flushCurrentEntry()
        let (occurredAt, initialBody) = parsedBulletHeader(line, day: day)
        currentOccurredAt = occurredAt
        currentBodyLines = initialBody.map { [$0] } ?? []
        continue
      }

      guard currentOccurredAt != nil else { continue }

      if line.hasPrefix("  ") {
        currentBodyLines.append(String(line.dropFirst(2)))
      } else if line.isEmpty {
        currentBodyLines.append("")
      }
    }

    flushCurrentEntry()
    return entries
  }

  private func updatedContentsByAppending(_ entry: ObsidianJournalEntry, to contents: String) -> String {
    updatedContentsByReplacingManagedEntries([entry], in: contents, day: entry.day)
  }

  private func updatedContentsByReplacingManagedEntries(
    _ entries: [ObsidianJournalEntry],
    in contents: String,
    day: Date
  ) -> String {
    let sortedEntries = entries.sorted { lhs, rhs in
      if lhs.occurredAt != rhs.occurredAt {
        return lhs.occurredAt < rhs.occurredAt
      }
      return lhs.id < rhs.id
    }
    let renderedEntryLines = sortedEntries.flatMap(renderedBulletLines)
    return updatedContentsByReplacingSection(
      header: Self.managedSectionHeader,
      renderedLines: renderedEntryLines,
      in: contents,
      day: day
    )
  }

  private func renderedBulletLines(for entry: ObsidianJournalEntry) -> [String] {
    let normalizedBody = normalizedEntryBody(entry.body)
    let bodyLines = normalizedBody.components(separatedBy: "\n")
    let timePrefix = "[\(timeString(for: entry.occurredAt))]"

    guard let firstLine = bodyLines.first else {
      return ["- \(timePrefix)"]
    }

    var rendered = ["- \(timePrefix) \(firstLine)"]
    for line in bodyLines.dropFirst() {
      rendered.append("  \(line)")
    }
    return rendered
  }

  private func updatedContentsByReplacingSummaryBackup(
    _ markdown: String,
    in contents: String,
    day: Date,
    providerSignature: String,
    summaryInputSignature: String?,
    usage: GeminiGenerateContentSummaryService.SummaryUsage?
  ) -> String {
    var renderedLines: [String] = [
      "<!-- generated-by: Brain Unfog -->",
      "<!-- provider: \(providerSignature) -->",
      "<!-- generated-at: \(iso8601String(from: .now)) -->",
    ]

    if let summaryInputSignature, !summaryInputSignature.isEmpty {
      renderedLines.append("<!-- summary-input-signature: \(summaryInputSignature) -->")
    }

    if let usage {
      let promptTokens = usage.promptTokenCount.map(String.init) ?? "n/a"
      let outputTokens = usage.candidatesTokenCount.map(String.init) ?? "n/a"
      let thoughtsTokens = usage.thoughtsTokenCount.map(String.init) ?? "n/a"
      let totalTokens = usage.totalTokenCount.map(String.init) ?? "n/a"
      renderedLines.append(
        "<!-- tokens: prompt=\(promptTokens) output=\(outputTokens) thoughts=\(thoughtsTokens) total=\(totalTokens) -->"
      )
    }

    renderedLines.append(contentsOf: normalizedLineEndings(markdown).components(separatedBy: "\n"))

    return updatedContentsByReplacingSection(
      header: Self.summaryBackupSectionHeader,
      renderedLines: renderedLines,
      in: contents,
      day: day
    )
  }

  private func parseDaySummaryBackup(
    from contents: String
  ) -> ObsidianJournalDaySummaryBackupLoadResult {
    let lines = normalizedLineEndings(contents).components(separatedBy: "\n")
    guard let sectionRange = sectionRange(in: lines, matching: Self.summaryBackupSectionHeader) else {
      return .missing
    }

    var providerSignature: String?
    var summaryInputSignature: String?
    var usage: GeminiGenerateContentSummaryService.SummaryUsage?
    var markdownLines: [String] = []

    for line in lines[sectionRange] {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if let provider = metadataValue(in: trimmed, key: "provider") {
        providerSignature = provider
        continue
      }
      if let signature = metadataValue(in: trimmed, key: "summary-input-signature") {
        summaryInputSignature = signature
        continue
      }
      if let parsedUsage = parsedSummaryUsage(from: trimmed) {
        usage = parsedUsage
        continue
      }
      if trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") {
        continue
      }
      markdownLines.append(line)
    }

    let markdown = normalizedEntryBody(markdownLines.joined(separator: "\n"))
    guard let providerSignature, !providerSignature.isEmpty, !markdown.isEmpty else {
      AppLogger.notes.error("journal day summary backup is malformed")
      return .malformed
    }

    return .loaded(
      ObsidianJournalDaySummaryBackup(
        markdown: markdown,
        providerSignature: providerSignature,
        summaryInputSignature: summaryInputSignature,
        usage: usage
      )
    )
  }

  private func updatedContentsByReplacingSection(
    header: String,
    renderedLines: [String],
    in contents: String,
    day: Date
  ) -> String {
    var lines = normalizedLineEndings(contents).components(separatedBy: "\n")

    if lines.count == 1, lines[0].isEmpty {
      return (
        ["# \(dayFileName(for: day))", "", header, ""]
          + renderedLines
          + [""]
      ).joined(separator: "\n")
    }

    if let sectionRange = sectionRange(in: lines, matching: header) {
      let replacementLines = [""] + renderedLines + [""]
      lines.replaceSubrange(sectionRange, with: replacementLines)
      return lines.joined(separator: "\n")
    }

    while lines.last?.isEmpty == true {
      lines.removeLast()
    }

    lines.append("")
    lines.append(header)
    lines.append("")
    lines.append(contentsOf: renderedLines)
    lines.append("")
    return lines.joined(separator: "\n")
  }

  private func managedSectionRange(in lines: [String]) -> Range<Int>? {
    sectionRange(in: lines, matching: Self.managedSectionHeader)
  }

  private func sectionRange(in lines: [String], matching header: String) -> Range<Int>? {
    guard
      let headerIndex = lines.firstIndex(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines) == header
      })
    else {
      return nil
    }

    var endIndex = lines.count
    for index in (headerIndex + 1)..<lines.count where lines[index].hasPrefix("## ") {
      endIndex = index
      break
    }
    return (headerIndex + 1)..<endIndex
  }

  private func metadataValue(in line: String, key: String) -> String? {
    let prefix = "<!-- \(key): "
    guard line.hasPrefix(prefix), line.hasSuffix(" -->") else { return nil }
    let start = line.index(line.startIndex, offsetBy: prefix.count)
    let end = line.index(line.endIndex, offsetBy: -4)
    return String(line[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func parsedSummaryUsage(
    from line: String
  ) -> GeminiGenerateContentSummaryService.SummaryUsage? {
    guard
      let payload = metadataValue(in: line, key: "tokens"),
      !payload.isEmpty
    else {
      return nil
    }

    var values: [String: Int?] = [:]
    for pair in payload.split(separator: " ") {
      let components = pair.split(separator: "=", maxSplits: 1).map(String.init)
      guard components.count == 2 else { continue }
      values[components[0]] = components[1] == "n/a" ? nil : Int(components[1])
    }

    return GeminiGenerateContentSummaryService.SummaryUsage(
      promptTokenCount: values["prompt"] ?? nil,
      candidatesTokenCount: values["output"] ?? nil,
      thoughtsTokenCount: values["thoughts"] ?? nil,
      totalTokenCount: values["total"] ?? nil
    )
  }

  private func parsedBulletHeader(_ line: String, day: Date) -> (Date, String?) {
    let fallbackDate = day
    let remainder = String(line.dropFirst(2))

    guard remainder.hasPrefix("["),
      let closingBracket = remainder.firstIndex(of: "]")
    else {
      return (fallbackDate, remainder.trimmingCharacters(in: .whitespaces))
    }

    let timeCandidate = String(remainder[remainder.index(after: remainder.startIndex)..<closingBracket])
    let occurredAt = date(on: day, withTime: timeCandidate) ?? fallbackDate
    let trailingStart = remainder.index(after: closingBracket)
    let trailing = String(remainder[trailingStart...]).trimmingCharacters(in: .whitespaces)
    return (occurredAt, trailing.isEmpty ? nil : trailing)
  }

  private func normalizedEntryBody(_ text: String) -> String {
    let normalized = normalizedLineEndings(text)
    let lines = normalized.components(separatedBy: "\n")
    var trimmed = lines

    while trimmed.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
      trimmed.removeFirst()
    }
    while trimmed.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
      trimmed.removeLast()
    }

    return trimmed.joined(separator: "\n")
  }

  private func trimmedBody(from lines: [String]) -> String {
    normalizedEntryBody(lines.joined(separator: "\n"))
  }

  private func normalizedLineEndings(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private func journalFileURL(for day: Date) -> URL {
    rootURL.appendingPathComponent("\(dayFileName(for: day)).md")
  }

  private func dayFileName(for day: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: day)
  }

  private func timeString(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  private func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .autoupdatingCurrent
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private func date(on day: Date, withTime time: String) -> Date? {
    let parts = time.split(separator: ":")
    guard parts.count == 2,
      let hour = Int(parts[0]),
      let minute = Int(parts[1])
    else {
      return nil
    }

    return Calendar.autoupdatingCurrent.date(
      bySettingHour: hour,
      minute: minute,
      second: 0,
      of: day
    )
  }

  private func itemExists(at url: URL) -> Bool {
    (try? url.checkResourceIsReachable()) ?? false
  }

  private func isFileNotFound(_ error: Error) -> Bool {
    guard let cocoaError = error as? CocoaError else { return false }
    switch cocoaError.code {
    case .fileNoSuchFile, .fileReadNoSuchFile:
      return true
    default:
      return false
    }
  }
}
