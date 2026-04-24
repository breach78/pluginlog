import Foundation
import SwiftData
import SwiftUI

let journalPaperWidth: CGFloat = 800
let journalMetaColumnWidth: CGFloat = 156

// Composition root only.
// Keep AppKit text-system implementation in JournalBoardTextSystem.swift.
// Keep summary/cache/retry implementation in JournalBoardSummaryPipeline.swift.
struct JournalBoardView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.modelContext) private var modelContext

  let isActive: Bool
  let onSelectProject: (UUID) -> Void

  @Query var historyEvents: [ProjectHistoryEvent]

  @State var mutableJournalEntriesByDayKey: [String: [ObsidianJournalEntry]] = [:]
  @State var preparedDaySections: [JournalPreparedDaySection] = []
  @State var journalDraft: String = ""
  @State var journalDraftEntryID: String?
  @State var journalDraftOccurredAt: Date?
  @State var isDraftFocused = false
  @State var journalDraftEditorHeight: CGFloat = journalDraftEditorMinimumHeight
  @State var isDraftDirty = false
  @State var isApplyingDraftSeed = false
  @State var isLoadingEntries = false
  @State var isPreparingSections = false
  @State var didAutoScrollToToday = false
  @State var needsInitialViewportPin = false
  @State var scrollRequestID = 0
  @State var detailPopoverDayID: String?
  @State var retryingDaySummaryIDs: Set<String> = []
  @State var journalSourceRevision = 0
  @State var availableJournalDays: [Date] = []
  @State var calendarDayRevision = 0
  @State var draftAutosaveTask: Task<Void, Never>?
  @State var renderedHistoryEventsCache: [JournalRenderedHistoryEvent] = []
  @State var timelineDaysCache: [Date] = []
  @State var projectTitleSignatureCache: Int = 0
  @State var projectTitlesByIDCache: [UUID: String] = [:]

  let editorSessionID = "journal.board.draft"
  let clusterGapSeconds: TimeInterval = 25 * 60
  let maxVisibleDetailsPerItem = 6

  enum HistoryNoteStreamKey: Hashable {
    case project(UUID)
    case task(UUID)
  }

  init(
    isActive: Bool,
    onSelectProject: @escaping (UUID) -> Void
  ) {
    self.isActive = isActive
    self.onSelectProject = onSelectProject

    _historyEvents = Query(
      sort: [
        SortDescriptor(\ProjectHistoryEvent.occurredAt, order: .forward),
        SortDescriptor(\ProjectHistoryEvent.createdAt, order: .forward),
      ]
    )
  }

  var body: some View {
    journalBoardRoot
  }

  var today: Date {
    Calendar.autoupdatingCurrent.startOfDay(for: .now)
  }

  var minimumIncludedDay: Date {
    Calendar.autoupdatingCurrent.startOfDay(for: appState.journalMinimumIncludedDay)
  }

  var timelineDays: [Date] {
    timelineDaysCache
  }

  var mutableDays: [Date] {
    [today]
  }

  var availableJournalDayKeys: Set<String> {
    Set(availableJournalDays.map(Self.dayKey(for:)))
  }

  var frozenDayCacheStore: JournalFrozenDayCacheStore {
    JournalFrozenDayCacheStore(
      rootURL: appState.storageCoordinator.paths?.cacheDirectory,
      namespace: appState.journalSummaryProviderSignature,
      fallbackNamespaces: appState.journalSummaryLegacyProviderSignatures
    )
  }

  var reloadSignature: String {
    guard isActive else { return "inactive" }
    let latestEventSignature =
      historyEvents.last.map { "\($0.id.uuidString)-\(Int($0.occurredAt.timeIntervalSince1970))" }
      ?? "none"
    return "\(historyEvents.count)-\(latestEventSignature)-\(projectTitleSignature)-\(appState.journalSummaryProviderSignature)-\(journalSourceRevision)-\(calendarDayRevision)"
  }

  var projectTitleSignature: Int {
    projectTitleSignatureCache
  }

  var projectTitlesByID: [UUID: String] {
    projectTitlesByIDCache
  }

  var journalProjectDescriptors: [WorkspaceProjectDescriptor] {
    ReminderRuntimeProjectionReadModelService.workspaceProjectDescriptors(
      runtimeSnapshot: appState.cachedOutlinerRuntimeProjectionSnapshot,
      context: modelContext
    )
  }

  func refreshAvailableJournalDays() async {
    availableJournalDays = await appState.loadAvailableJournalDaysFromSource()
  }

  @MainActor
  func refreshDerivedJournalCaches() {
    let orderedDescriptors = journalProjectDescriptors.sorted { lhs, rhs in
      let lhsOrder = lhs.workspaceSortKey ?? Int64.max
      let rhsOrder = rhs.workspaceSortKey ?? Int64.max
      if lhsOrder != rhsOrder {
        return lhsOrder < rhsOrder
      }
      let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
      if titleComparison != .orderedSame {
        return titleComparison == .orderedAscending
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
    projectTitlesByIDCache = Dictionary(
      uniqueKeysWithValues: orderedDescriptors.map { ($0.id, $0.title) }
    )

    var titleHasher = Hasher()
    for descriptor in orderedDescriptors {
      titleHasher.combine(descriptor.id)
      titleHasher.combine(descriptor.title)
    }
    projectTitleSignatureCache = titleHasher.finalize()

    renderedHistoryEventsCache = makeRenderedHistoryEvents()
    timelineDaysCache = makeTimelineDays()
  }

  func scheduleDraftAutosave() {
    draftAutosaveTask?.cancel()
    guard isDraftFocused else { return }

    draftAutosaveTask = Task {
      do {
        try await Task.sleep(for: .seconds(1.2))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await commitDraftIfNeeded()
    }
  }

  func monitorCalendarDayBoundary() async {
    while !Task.isCancelled && isActive {
      let calendar = Calendar.autoupdatingCurrent
      guard let nextDay = calendar.date(byAdding: .day, value: 1, to: today) else { return }
      let nextBoundary = calendar.startOfDay(for: nextDay)
      let sleepInterval = max(0, nextBoundary.timeIntervalSinceNow + 1)
      do {
        try await Task.sleep(for: .seconds(sleepInterval))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await MainActor.run {
        calendarDayRevision += 1
      }
    }
  }

  var renderedHistoryEvents: [JournalRenderedHistoryEvent] {
    renderedHistoryEventsCache
  }

  func prepareJournalBoard(forceScroll: Bool) async {
    guard !isLoadingEntries else { return }

    await refreshAvailableJournalDays()
    await MainActor.run {
      refreshDerivedJournalCaches()
    }

    if preparedDaySections.isEmpty {
      needsInitialViewportPin = true
      await seedPreparedSectionsForImmediateDisplay()

      if forceScroll || !didAutoScrollToToday {
        didAutoScrollToToday = true
        scrollRequestID += 1
      }
    }

    isLoadingEntries = true
    defer { isLoadingEntries = false }

    await loadMutableJournalEntries()
    await rebuildPreparedSections(forceScroll: false)
  }

  func seedPreparedSectionsForImmediateDisplay() async {
    let calendar = Calendar.autoupdatingCurrent
    var seededSections: [JournalPreparedDaySection] = []

    for day in timelineDays {
      let dayKey = Self.dayKey(for: day)

      if calendar.isDateInToday(day) {
        let journalEntries = mutableJournalEntriesByDayKey[dayKey] ?? []
        let rawItems = mergedFeedItems(for: day, journalEntries: journalEntries)
        let todaySection = await preparedTodaySection(
          for: day,
          rawItems: rawItems,
          journalEntries: journalEntries
        )
        seededSections.append(todaySection)
        continue
      }

      if let cachedSection = await reusableFrozenSection(for: day) {
        seededSections.append(cachedSection)
      }
    }

    if !seededSections.isEmpty {
      preparedDaySections = seededSections
    }
  }

  func loadMutableJournalEntries() async {
    var loaded: [String: [ObsidianJournalEntry]] = [:]

    for day in mutableDays {
      let entries = await appState.loadJournalEntriesFromSource(for: day)
      loaded[Self.dayKey(for: day)] = entries.sorted { lhs, rhs in
        if lhs.occurredAt != rhs.occurredAt {
          return lhs.occurredAt < rhs.occurredAt
        }
        return lhs.id < rhs.id
      }
    }

    mutableJournalEntriesByDayKey = loaded
  }

  func rebuildPreparedSections(forceScroll: Bool) async {
    guard !isPreparingSections else { return }

    isPreparingSections = true
    defer { isPreparingSections = false }

    let calendar = Calendar.autoupdatingCurrent
    let todayKey = Self.dayKey(for: today)
    var nextSections: [JournalPreparedDaySection] = []
    var nextDraftSeed: ObsidianJournalEntry?

    for day in timelineDays {
      let dayKey = Self.dayKey(for: day)
      let frozen = isFrozenDay(day)
      let isPastDay = !calendar.isDateInToday(day)

      if isPastDay, let cachedSection = await reusableFrozenSection(for: day) {
        nextSections.append(cachedSection)
        continue
      }

      let journalEntries: [ObsidianJournalEntry]
      if frozen {
        journalEntries = await appState.loadJournalEntriesFromSource(for: day)
      } else {
        journalEntries = mutableJournalEntriesByDayKey[dayKey] ?? []
      }

      let preparedSection: JournalPreparedDaySection?
      if calendar.isDateInToday(day) {
        var rawItems = mergedFeedItems(for: day, journalEntries: journalEntries)

        if dayKey == todayKey,
          case .journal(let lastEntry) = rawItems.last
        {
          nextDraftSeed = lastEntry
          rawItems.removeLast()
        }

        preparedSection = await preparedTodaySection(
          for: day,
          rawItems: rawItems,
          journalEntries: journalEntries
        )
      } else {
        preparedSection = await preparedPastDaySection(
          for: day,
          journalEntries: journalEntries
        )
      }

      guard let preparedSection else {
        continue
      }

      nextSections.append(preparedSection)

      if isPastDay {
        await persistFrozenSectionIfNeeded(preparedSection)
      }
    }

    preparedDaySections = nextSections
    syncDraftSeedIfPossible(with: nextDraftSeed)

    if needsInitialViewportPin || forceScroll || !didAutoScrollToToday {
      didAutoScrollToToday = true
      scrollRequestID += 1
    }
  }

  func isFrozenDay(_ day: Date) -> Bool {
    guard let mutableCutoff = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: today)
    else {
      return false
    }
    return day < Calendar.autoupdatingCurrent.startOfDay(for: mutableCutoff)
  }

  func noteDelta(previous: String?, current: String) -> JournalNoteDelta? {
    let normalizedCurrent = normalizedNoteText(current)

    guard let previous else {
      guard !normalizedCurrent.isEmpty else { return nil }
      return JournalNoteDelta(addedLines: normalizedNoteTextLines(normalizedCurrent), removedLines: [])
    }

    let normalizedPrevious = normalizedNoteText(previous)
    guard normalizedPrevious != normalizedCurrent else { return nil }

    let previousLines = normalizedNoteTextLines(normalizedPrevious)
    let currentLines = normalizedNoteTextLines(normalizedCurrent)
    let prefixCount = commonPrefixCount(previousLines, currentLines)
    let suffixCount = commonSuffixCount(
      Array(previousLines.dropFirst(prefixCount)),
      Array(currentLines.dropFirst(prefixCount))
    )

    let previousRemovedEndIndex = max(prefixCount, previousLines.count - suffixCount)
    let currentAddedEndIndex = max(prefixCount, currentLines.count - suffixCount)

    let removedLines = Array(previousLines[prefixCount..<previousRemovedEndIndex])
    let addedLines = Array(currentLines[prefixCount..<currentAddedEndIndex])
    let delta = JournalNoteDelta(addedLines: addedLines, removedLines: removedLines)
    return delta.hasChanges ? delta : nil
  }

  func normalizedNoteText(_ text: String) -> String {
    var normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    while normalized.hasSuffix("\n") {
      normalized.removeLast()
    }

    return normalized
  }

  func normalizedNoteTextLines(_ text: String) -> [String] {
    guard !text.isEmpty else { return [] }
    return text.components(separatedBy: "\n")
  }

  func commonPrefixCount(_ lhs: [String], _ rhs: [String]) -> Int {
    var count = 0
    while count < lhs.count, count < rhs.count, lhs[count] == rhs[count] {
      count += 1
    }
    return count
  }

  func commonSuffixCount(_ lhs: [String], _ rhs: [String]) -> Int {
    var count = 0
    while count < lhs.count,
      count < rhs.count,
      lhs[lhs.count - 1 - count] == rhs[rhs.count - 1 - count]
    {
      count += 1
    }
    return count
  }

  func syncDraftSeedIfPossible(with entry: ObsidianJournalEntry?) {
    guard !isDraftFocused, !isDraftDirty else { return }

    isApplyingDraftSeed = true
    journalDraftEntryID = entry?.id
    journalDraftOccurredAt = entry?.occurredAt
    journalDraft = entry?.body ?? ""
    isDraftDirty = false
    isApplyingDraftSeed = false
  }

  func commitDraftIfNeeded(force: Bool = false) async {
    let trimmed = journalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard force || isDraftDirty else { return }

    defer { isDraftDirty = false }
    guard !trimmed.isEmpty else { return }

    let occurredAt = journalDraftOccurredAt ?? .now
    guard
      let savedEntry = await appState.saveJournalEntryToSource(
        trimmed,
        existingEntryID: journalDraftEntryID,
        occurredAt: occurredAt
      )
    else {
      return
    }

    let todayKey = Self.dayKey(for: savedEntry.day)
    var entries = mutableJournalEntriesByDayKey[todayKey] ?? []
    if let existingIndex = entries.firstIndex(where: { $0.id == savedEntry.id }) {
      entries[existingIndex] = savedEntry
    } else {
      entries.append(savedEntry)
    }
    entries.sort { lhs, rhs in
      if lhs.occurredAt != rhs.occurredAt {
        return lhs.occurredAt < rhs.occurredAt
      }
      return lhs.id < rhs.id
    }

    mutableJournalEntriesByDayKey[todayKey] = entries

    isApplyingDraftSeed = true
    journalDraftEntryID = savedEntry.id
    journalDraftOccurredAt = savedEntry.occurredAt
    journalDraft = savedEntry.body
    isApplyingDraftSeed = false

    await rebuildPreparedSections(forceScroll: false)
  }

  static func dayKey(for day: Date) -> String {
    dayKeyFormatter.string(from: day)
  }

  static func dateFromDayKey(_ dayKey: String) -> Date? {
    dayKeyFormatter.date(from: dayKey)
  }

  static func todayEditorKey(for day: Date) -> String {
    "journal-editor-\(dayKey(for: day))"
  }

  static let scrollBottomKey = "journal-scroll-bottom"

  static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.autoupdatingCurrent
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy.MM.dd EEEE"
    return formatter
  }()

  static let dayKeyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "HH:mm"
    return formatter
  }()
}

extension String {
  func removingPrefix(_ prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    return dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
