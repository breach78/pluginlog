import AppKit
import Foundation
import SwiftUI

extension JournalBoardView {
  func makeRenderedHistoryEvents() -> [JournalRenderedHistoryEvent] {
    var previousNotesByStream: [HistoryNoteStreamKey: String] = [:]
    var rendered: [JournalRenderedHistoryEvent] = []
    let minimumDay = minimumIncludedDay

    for event in historyEvents {
      let eventDay = Calendar.autoupdatingCurrent.startOfDay(for: event.occurredAt)
      switch event.kind {
      case .projectNoteSaved:
        let key = HistoryNoteStreamKey.project(event.projectID)
        let delta = noteDelta(previous: previousNotesByStream[key], current: event.noteTextSnapshot ?? "")
        previousNotesByStream[key] = event.noteTextSnapshot ?? ""
        if eventDay >= minimumDay, let delta, delta.hasChanges {
          rendered.append(JournalRenderedHistoryEvent(event: event, noteDelta: delta))
        }
      case .taskReminderNoteSaved:
        let delta: JournalNoteDelta?
        if let taskID = event.taskID {
          let key = HistoryNoteStreamKey.task(taskID)
          delta = noteDelta(previous: previousNotesByStream[key], current: event.noteTextSnapshot ?? "")
          previousNotesByStream[key] = event.noteTextSnapshot ?? ""
        } else {
          delta = noteDelta(previous: nil, current: event.noteTextSnapshot ?? "")
        }

        if eventDay >= minimumDay, let delta, delta.hasChanges {
          rendered.append(JournalRenderedHistoryEvent(event: event, noteDelta: delta))
        }
      case .projectCreated, .projectUpdated, .projectTimelineChanged, .projectArchived,
        .projectRestored, .projectDeleted, .taskCreated, .taskCompleted, .taskReopened,
        .taskUpdated, .taskScheduleChanged, .taskMoved, .taskDeleted, .attachmentAdded:
        if eventDay >= minimumDay {
          rendered.append(JournalRenderedHistoryEvent(event: event, noteDelta: nil))
        }
      }
    }

    return rendered
  }

  func makeTimelineDays() -> [Date] {
    let historyDays = historyEvents
      .map { Calendar.autoupdatingCurrent.startOfDay(for: $0.occurredAt) }
      .filter { $0 >= minimumIncludedDay }
    let journalDays = availableJournalDays
      .map { Calendar.autoupdatingCurrent.startOfDay(for: $0) }
      .filter { $0 >= minimumIncludedDay }
    let allKeys = Set((historyDays + journalDays + [today]).map(Self.dayKey(for:)))
    return allKeys
      .compactMap(Self.dateFromDayKey(_:))
      .sorted()
  }

  func daySection(_ section: JournalPreparedDaySection) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      daySectionHeader(for: section)
      daySectionContent(for: section)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  func daySectionHeader(for section: JournalPreparedDaySection) -> some View {
    HStack(alignment: .top, spacing: 16) {
      daySectionTitleBlock(for: section)
      Spacer(minLength: 0)
      daySectionActionCluster(for: section)
    }
  }

  func daySectionTitleBlock(for section: JournalPreparedDaySection) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(section.title)
        .font(JournalTypography.font(size: 18, weight: .bold))

      if !section.summary.isEmpty {
        Text(section.summary)
          .font(JournalTypography.font(size: 12))
          .foregroundStyle(.secondary)
      }
    }
  }

  func daySectionActionCluster(for section: JournalPreparedDaySection) -> some View {
    HStack(alignment: .top, spacing: 10) {
      if shouldShowDayDetailButton(for: section) {
        dayDetailButton(for: section)
      }

      daySummaryRefreshControl(for: section)
    }
  }

  func daySectionContent(for section: JournalPreparedDaySection) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      daySectionItemRows(for: section)

      if section.isToday {
        journalEditorRow
          .id(Self.todayEditorKey(for: section.day))
          .padding(.vertical, 18)

        Divider()
      }
    }
  }

  func daySectionItemRows(for section: JournalPreparedDaySection) -> some View {
    ForEach(section.items) { item in
      journalItemRow(item)
        .padding(.vertical, 18)

      Divider()
    }
  }

  func journalItemRow(_ item: JournalPreparedItem) -> some View {
    HStack(alignment: .top, spacing: 24) {
      journalItemPrimaryColumn(for: item)
      journalItemMetaColumn(for: item)
    }
  }

  func journalItemPrimaryColumn(for item: JournalPreparedItem) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      journalItemLabel(for: item)
      journalItemContent(for: item)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
  }

  @ViewBuilder
  func journalItemLabel(for item: JournalPreparedItem) -> some View {
    if !item.isDaySummary {
      Text(item.label)
        .font(JournalTypography.font(size: 11))
        .foregroundStyle(.secondary.opacity(0.85))
        .textCase(.uppercase)
    }
  }

  @ViewBuilder
  func journalItemContent(for item: JournalPreparedItem) -> some View {
    if item.isDaySummary {
      JournalMarkdownLabel(markdown: markdownText(for: item))
    } else {
      journalItemLineStack(for: item)
    }
  }

  func journalItemLineStack(for item: JournalPreparedItem) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(item.lines.enumerated()), id: \.offset) { _, line in
        segmentedLineView(line)
      }
    }
  }

  @ViewBuilder
  func journalItemMetaColumn(for item: JournalPreparedItem) -> some View {
    if !item.isDaySummary && !item.meta.isEmpty {
      VStack(alignment: .trailing, spacing: 4) {
        ForEach(Array(item.meta.enumerated()), id: \.offset) { _, meta in
          Text(meta.text)
            .font(JournalTypography.font(size: 11))
            .foregroundStyle(color(for: meta.tone))
            .frame(width: journalMetaColumnWidth, alignment: .trailing)
        }

        if let summarySourceMarker = summarySourceMarker(for: item.summarySource) {
          Text(summarySourceMarker)
            .font(JournalTypography.font(size: 11, weight: .bold))
            .foregroundStyle(.secondary.opacity(0.9))
            .frame(width: journalMetaColumnWidth, alignment: .trailing)
        }
      }
    }
  }

  var journalEditorRow: some View {
    HStack(alignment: .top, spacing: 24) {
      journalEditorPrimaryColumn
      journalEditorMetaColumn
    }
  }

  var journalEditorPrimaryColumn: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Journals")
        .font(JournalTypography.font(size: 11))
        .foregroundStyle(.secondary.opacity(0.85))
        .textCase(.uppercase)

      ZStack(alignment: .topLeading) {
        journalEditorPlaceholder
        journalEditorInputField
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  var journalEditorPlaceholder: some View {
    if journalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Text("지금 어떤 상태인지 적습니다.")
        .font(JournalTypography.font())
        .foregroundStyle(.tertiary)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  var journalEditorInputField: some View {
    if isActive {
      JournalDraftEditor(
        text: $journalDraft,
        height: $journalDraftEditorHeight,
        isFocused: $isDraftFocused
      )
      .frame(height: journalDraftEditorHeight)
    } else {
      Color.clear
        .frame(height: journalDraftEditorHeight)
    }
  }

  var journalEditorMetaColumn: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Text(editorMetaTimeText)
        .font(JournalTypography.font(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: journalMetaColumnWidth, alignment: .trailing)

      Text("자동 저장")
        .font(JournalTypography.font(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: journalMetaColumnWidth, alignment: .trailing)

      if journalDraftEntryID != nil {
        Text("이어쓰기")
          .font(JournalTypography.font(size: 11))
          .foregroundStyle(color(for: .added))
          .frame(width: journalMetaColumnWidth, alignment: .trailing)
      }
    }
  }

  @ViewBuilder
  func segmentedLineView(_ line: JournalPreparedLine) -> some View {
    let text = line.segments.reduce(Text("")) { partial, segment in
      partial + styledSegmentText(segment, role: line.role)
    }

    switch line.role {
    case .summary:
      text
        .font(JournalTypography.font(size: 16, weight: .bold))
        .lineSpacing(3)
    case .detail:
      text
        .font(JournalTypography.font(size: 14))
        .lineSpacing(2)
    case .body:
      text
        .font(JournalTypography.font())
        .lineSpacing(4)
    case .commentary:
      text
        .font(JournalTypography.font(size: 15))
        .lineSpacing(4)
    }
  }

  func styledSegmentText(_ segment: JournalPreparedSegment, role: JournalLineRole) -> Text {
    var text = Text(segment.text)
      .foregroundColor(segmentColor(segment.tone))

    if segment.strikethrough {
      text = text.strikethrough(true, color: segmentColor(segment.tone))
    }

    return text
  }

  func color(for tone: JournalTone) -> Color {
    switch tone {
    case .primary:
      return .secondary
    case .secondary:
      return .secondary.opacity(0.82)
    case .added:
      return .blue.opacity(0.88)
    case .removed:
      return .red.opacity(0.78)
    case .commentary:
      return Color(nsColor: .systemBlue).opacity(0.92)
    }
  }

  func segmentColor(_ tone: JournalTone) -> Color {
    switch tone {
    case .primary:
      return .primary
    case .secondary:
      return .secondary
    case .added:
      return .blue.opacity(0.88)
    case .removed:
      return .red.opacity(0.82)
    case .commentary:
      return Color(nsColor: .systemBlue)
    }
  }

  var editorMetaTimeText: String {
    let targetDate = journalDraftOccurredAt ?? .now
    return Self.timeFormatter.string(from: targetDate)
  }

  func markdownText(for item: JournalPreparedItem) -> String {
    item.lines
      .map { line in line.segments.map(\.text).joined() }
      .joined(separator: "\n")
  }

  func shouldShowDayDetailButton(for section: JournalPreparedDaySection) -> Bool {
    !section.detailLines.isEmpty
  }

  func mergedFeedItems(for day: Date, journalEntries: [ObsidianJournalEntry]) -> [JournalRawFeedItem] {
    let journalItems = journalEntries.map { JournalRawFeedItem.journal($0) }
    let systemItems = liveSystemClusters(for: day).map { JournalRawFeedItem.system($0) }

    return (systemItems + journalItems).sorted { lhs, rhs in
      if lhs.sortDate != rhs.sortDate {
        return lhs.sortDate < rhs.sortDate
      }
      return lhs.id < rhs.id
    }
  }

  func preparedTodaySection(
    for day: Date,
    rawItems: [JournalRawFeedItem],
    journalEntries: [ObsidianJournalEntry]
  ) async -> JournalPreparedDaySection {
    let systemCount = rawItems.reduce(into: 0) { partial, item in
      if case .system = item {
        partial += 1
      }
    }

    var items: [JournalPreparedItem] = []
    items.reserveCapacity(rawItems.count)

    for rawItem in rawItems {
      switch rawItem {
      case .system(let cluster):
        items.append(await preparedSystemItem(for: cluster))
      case .journal(let entry):
        items.append(preparedJournalItem(for: entry))
      }
    }

    return JournalPreparedDaySection(
      id: Self.dayKey(for: day),
      day: day,
      title: dayTitle(for: day),
      summary: daySummary(for: day, systemCount: systemCount, journalCount: journalEntries.count),
      detailLines: preparedDayDetailLines(for: day, journalEntries: journalEntries),
      items: items,
      isToday: true
    )
  }

  func preparedPastDaySection(
    for day: Date,
    journalEntries: [ObsidianJournalEntry]
  ) async -> JournalPreparedDaySection? {
    let dayEvents = renderedHistoryEvents.filter {
      Calendar.autoupdatingCurrent.isDate($0.event.occurredAt, inSameDayAs: day)
    }

    if dayEvents.isEmpty && journalEntries.isEmpty {
      return nil
    }

    var items: [JournalPreparedItem] = []

    if !dayEvents.isEmpty {
      items.append(
        await preparedPastDaySummaryItem(for: day, events: dayEvents, journalEntries: journalEntries)
      )
    }

    items.append(contentsOf: journalEntries.map(preparedJournalItem(for:)))

    return JournalPreparedDaySection(
      id: Self.dayKey(for: day),
      day: day,
      title: dayTitle(for: day),
      summary: "",
      detailLines: preparedDayDetailLines(for: day, journalEntries: journalEntries),
      items: items,
      isToday: false
    )
  }

  func retrospectiveSegments(for day: Date, journalEntries: [ObsidianJournalEntry])
    -> [JournalRetrospectiveSegment]
  {
    let dayEvents = renderedHistoryEvents.filter {
      Calendar.autoupdatingCurrent.isDate($0.event.occurredAt, inSameDayAs: day)
    }

    let atoms =
      (dayEvents.map { JournalTimelineAtom.system($0) }
      + journalEntries.map { JournalTimelineAtom.journal($0) })
      .sorted { lhs, rhs in
        if lhs.sortDate != rhs.sortDate {
          return lhs.sortDate < rhs.sortDate
        }
        return lhs.id < rhs.id
      }

    guard !atoms.isEmpty else { return [] }

    var segments: [JournalRetrospectiveSegment] = []
    var currentEvents: [JournalRenderedHistoryEvent] = []
    var currentJournalEntries: [ObsidianJournalEntry] = []
    var segmentIndex = 0

    func flush() {
      guard !currentEvents.isEmpty || !currentJournalEntries.isEmpty else { return }
      segments.append(
        JournalRetrospectiveSegment(
          id: "segment-\(Self.dayKey(for: day))-\(segmentIndex)",
          day: day,
          events: currentEvents,
          journalEntries: currentJournalEntries
        )
      )
      segmentIndex += 1
      currentEvents.removeAll(keepingCapacity: true)
      currentJournalEntries.removeAll(keepingCapacity: true)
    }

    for atom in atoms {
      switch atom {
      case .system(let event):
        if !currentJournalEntries.isEmpty {
          flush()
        }
        currentEvents.append(event)
      case .journal(let entry):
        currentJournalEntries.append(entry)
      }
    }

    flush()
    return segments
  }

  func retrospectiveSystemItems(for segment: JournalRetrospectiveSegment) -> [JournalRawFeedItem] {
    guard !segment.events.isEmpty else { return [] }

    var orderedProjectIDs: [UUID] = []
    var groupedEvents: [UUID: [JournalRenderedHistoryEvent]] = [:]
    var journalEntriesByProject: [UUID: [ObsidianJournalEntry]] = [:]

    for event in segment.events {
      let projectID = event.event.projectID
      if groupedEvents[projectID] == nil {
        orderedProjectIDs.append(projectID)
      }
      groupedEvents[projectID, default: []].append(event)
    }

    for journalEntry in segment.journalEntries {
      let projectID =
        segment.events
        .last(where: { $0.event.occurredAt <= journalEntry.occurredAt })?
        .event.projectID
        ?? orderedProjectIDs.last

      if let projectID {
        journalEntriesByProject[projectID, default: []].append(journalEntry)
      }
    }

    return orderedProjectIDs.enumerated().compactMap { index, projectID in
      guard
        let projectEvents = groupedEvents[projectID],
        let startAt = projectEvents.first?.event.occurredAt,
        let endAt = projectEvents.last?.event.occurredAt
      else {
        return nil
      }

      return .system(
        JournalSystemCluster(
          id: "retro-\(segment.id)-\(index)-\(projectID.uuidString)",
          projectID: projectID,
          day: segment.day,
          startAt: startAt,
          endAt: endAt,
          events: projectEvents,
          journalEntries: journalEntriesByProject[projectID] ?? [],
          presentationStyle: .retrospective
        )
      )
    }
  }

  func liveSystemClusters(for day: Date) -> [JournalSystemCluster] {
    let dayEvents = renderedHistoryEvents.filter {
      Calendar.autoupdatingCurrent.isDate($0.event.occurredAt, inSameDayAs: day)
    }
    guard !dayEvents.isEmpty else { return [] }

    var clusters: [JournalSystemCluster] = []
    var currentProjectID: UUID?
    var currentEvents: [JournalRenderedHistoryEvent] = []
    var currentStartAt: Date?
    var currentEndAt: Date?

    func flushCurrentCluster() {
      guard
        let currentProjectID,
        let currentStartAt,
        let currentEndAt,
        !currentEvents.isEmpty
      else {
        currentEvents.removeAll(keepingCapacity: true)
        return
      }

      clusters.append(
        JournalSystemCluster(
          id: "\(currentProjectID.uuidString)-\(Int(currentStartAt.timeIntervalSince1970))-\(currentEvents.count)",
          projectID: currentProjectID,
          day: day,
          startAt: currentStartAt,
          endAt: currentEndAt,
          events: currentEvents,
          journalEntries: [],
          presentationStyle: .live
        )
      )
      currentEvents.removeAll(keepingCapacity: true)
    }

    for renderedEvent in dayEvents {
      let event = renderedEvent.event
      let isCompatibleWithCurrentCluster =
        currentProjectID == event.projectID
        && (currentEndAt.map {
          event.occurredAt.timeIntervalSince($0) <= clusterGapSeconds
        } ?? false)

      if !isCompatibleWithCurrentCluster {
        flushCurrentCluster()
        currentProjectID = event.projectID
        currentStartAt = event.occurredAt
      }

      currentEvents.append(renderedEvent)
      currentEndAt = event.occurredAt
    }

    flushCurrentCluster()
    return clusters
  }

  func preparedJournalItem(for entry: ObsidianJournalEntry) -> JournalPreparedItem {
    let bodyLines = normalizedDisplayLines(entry.body)
    let preparedLines = bodyLines.map { line in
      JournalPreparedLine(role: .body, segments: [JournalPreparedSegment(line)])
    }

    return JournalPreparedItem(
      id: "journal-\(entry.id)",
      sortDate: entry.occurredAt,
      kind: .journal,
      label: "Journals",
      isDaySummary: false,
      lines: preparedLines.isEmpty
        ? [JournalPreparedLine(role: .body, segments: [JournalPreparedSegment("")])]
        : preparedLines,
      detailLines: [],
      journalLines: [],
      inlineDetailLineCount: 0,
      meta: [
        JournalPreparedMeta(text: Self.timeFormatter.string(from: entry.occurredAt), tone: .secondary),
        JournalPreparedMeta(text: "기록", tone: .secondary),
      ],
      summarySource: .unavailable,
      summaryFailureReason: nil,
      summaryInputSignature: nil,
      summaryUsage: nil,
      sourceJournalEntryID: entry.id
    )
  }

  func preparedSystemItem(for cluster: JournalSystemCluster) async -> JournalPreparedItem {
    let projectTitle = projectTitlesByID[cluster.projectID] ?? "프로젝트"
    let detailLines = preparedDetailLines(for: cluster)
    let journalLines = preparedJournalLines(for: cluster.journalEntries)

    if cluster.presentationStyle == .live {
      let inlineDetailLineCount = min(maxVisibleDetailsPerItem, detailLines.count)
      let liveLines =
        inlineDetailLineCount > 0
        ? Array(detailLines.prefix(inlineDetailLineCount))
        : [JournalPreparedLine(
          role: .detail,
          segments: [JournalPreparedSegment("기록 없음", tone: .secondary)]
        )]

      return JournalPreparedItem(
        id: "system-\(cluster.id)",
        sortDate: cluster.startAt,
        kind: .system,
        label: projectTitle,
        isDaySummary: false,
        lines: liveLines,
        detailLines: detailLines,
        journalLines: [],
        inlineDetailLineCount: inlineDetailLineCount,
        meta: systemMeta(for: cluster),
        summarySource: .unavailable,
        summaryFailureReason: nil,
        summaryInputSignature: nil,
        summaryUsage: nil,
        sourceJournalEntryID: nil
      )
    }

    let fallbackSummary = deterministicSummary(for: cluster)
    let fallbackOpinion = deterministicOpinion(for: cluster.journalEntries)
    let summaryPrompt = aiSummaryPrompt(
      for: cluster,
      projectTitle: projectTitle,
      detailLines: detailLines,
      journalEntries: cluster.journalEntries
    )
    let summaryResolution = await LocalLLMService.shared.summary(
      for: "\(cluster.id)-\(appState.journalSummaryProviderSignature)",
      prompt: summaryPrompt
    )
    let lines = parsedRetrospectiveLines(
      from: summaryResolution.text,
      fallbackSummary: fallbackSummary,
      fallbackOpinion: fallbackOpinion
    )

    return JournalPreparedItem(
      id: "system-\(cluster.id)",
      sortDate: cluster.startAt,
      kind: .system,
      label: projectTitle,
      isDaySummary: false,
      lines: lines,
      detailLines: detailLines,
      journalLines: journalLines,
      inlineDetailLineCount: 0,
      meta: systemMeta(for: cluster),
      summarySource: summaryResolution.source,
      summaryFailureReason: summaryResolution.failureReason,
      summaryInputSignature: nil,
      summaryUsage: summaryResolution.usage,
      sourceJournalEntryID: nil
    )
  }

  func preparedDetailLines(for cluster: JournalSystemCluster) -> [JournalPreparedLine] {
    var lines: [JournalPreparedLine] = []

    for renderedEvent in cluster.events {
      let event = renderedEvent.event

      switch event.kind {
      case .projectCreated:
        lines.append(
          JournalPreparedLine(
            role: .detail,
            segments: [
              JournalPreparedSegment("프로젝트 시작", tone: .secondary)
            ]
          )
        )

      case .projectUpdated, .projectTimelineChanged, .projectArchived, .projectRestored,
        .projectDeleted:
        lines.append(historyChangePreparedLine(for: event))

      case .taskCreated:
        lines.append(
          JournalPreparedLine(
            role: .detail,
            segments: [
              JournalPreparedSegment("+ ", tone: .added),
              JournalPreparedSegment(historyTaskTitle(for: event))
            ]
          )
        )

      case .taskCompleted:
        lines.append(
          JournalPreparedLine(
            role: .detail,
            segments: [
              JournalPreparedSegment("완료 ", tone: .secondary),
              JournalPreparedSegment(historyTaskTitle(for: event))
            ]
          )
        )

      case .taskReopened:
        lines.append(
          JournalPreparedLine(
            role: .detail,
            segments: [
              JournalPreparedSegment("취소 ", tone: .removed),
              JournalPreparedSegment(historyTaskTitle(for: event))
            ]
          )
        )

      case .taskUpdated, .taskScheduleChanged, .taskMoved, .taskDeleted:
        lines.append(historyChangePreparedLine(for: event))

      case .attachmentAdded:
        lines.append(
          JournalPreparedLine(
            role: .detail,
            segments: [
              JournalPreparedSegment("첨부 ", tone: .added),
              JournalPreparedSegment(historyAttachmentTitle(for: event))
            ]
          )
        )

      case .projectNoteSaved, .taskReminderNoteSaved:
        if let delta = renderedEvent.noteDelta {
          let noteOwnerPrefix = noteOwnerPrefix(for: event)

          for line in delta.addedLines {
            var segments: [JournalPreparedSegment] = [
              JournalPreparedSegment("+ ", tone: .added)
            ]
            if let noteOwnerPrefix {
              segments.append(JournalPreparedSegment("\(noteOwnerPrefix) ", tone: .secondary))
            }
            segments.append(JournalPreparedSegment(line))
            lines.append(JournalPreparedLine(role: .detail, segments: segments))
          }

          for line in delta.removedLines {
            var segments: [JournalPreparedSegment] = [
              JournalPreparedSegment("- ", tone: .removed)
            ]
            if let noteOwnerPrefix {
              segments.append(JournalPreparedSegment("\(noteOwnerPrefix) ", tone: .secondary))
            }
            segments.append(JournalPreparedSegment(line, tone: .removed, strikethrough: true))
            lines.append(JournalPreparedLine(role: .detail, segments: segments))
          }
        }
      }
    }

    return lines
  }

  func preparedJournalLines(for entries: [ObsidianJournalEntry]) -> [JournalPreparedLine] {
    var lines: [JournalPreparedLine] = []

    for entry in entries.sorted(by: { lhs, rhs in
      if lhs.occurredAt != rhs.occurredAt {
        return lhs.occurredAt < rhs.occurredAt
      }
      return lhs.id < rhs.id
    }) {
      let bodyLines = normalizedDisplayLines(entry.body)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

      guard !bodyLines.isEmpty else { continue }

      for (index, line) in bodyLines.enumerated() {
        var segments: [JournalPreparedSegment] = []
        if index == 0 {
          segments.append(
            JournalPreparedSegment("[\(Self.timeFormatter.string(from: entry.occurredAt))] ", tone: .secondary)
          )
        }
        segments.append(JournalPreparedSegment(line, tone: .commentary))
        lines.append(JournalPreparedLine(role: .body, segments: segments))
      }
    }

    return lines
  }

  func preparedSummaryDisplayLines(from text: String) -> [JournalPreparedLine] {
    let lines = normalizedDisplayLines(text)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    if lines.isEmpty {
      return [JournalPreparedLine(role: .body, segments: [JournalPreparedSegment("기록을 정리했습니다.")])]
    }

    return lines.map { line in
      JournalPreparedLine(role: .body, segments: [JournalPreparedSegment(line)])
    }
  }

  func preparedDayDetailLines(for day: Date, journalEntries: [ObsidianJournalEntry])
    -> [JournalPreparedLine]
  {
    preparedDayDetailLines(
      from: projectLogPayloads(for: dayEvents(for: day)),
      journalEntries: journalEntries
    )
  }

  func preparedDayDetailLines(
    from projectPayloads: [JournalProjectLogPayload],
    journalEntries: [ObsidianJournalEntry]
  ) -> [JournalPreparedLine] {
    var lines: [JournalPreparedLine] = []

    if !projectPayloads.isEmpty {
      for (index, payload) in projectPayloads.enumerated() {
        if index > 0 {
          lines.append(JournalPreparedLine(role: .detail, segments: [JournalPreparedSegment("")]))
        }

        lines.append(
          JournalPreparedLine(
            role: .summary,
            segments: [JournalPreparedSegment(payload.project)]
          )
        )

        let sections: [(String, [String])] = [
          ("Planned", payload.planned),
          ("Executed", payload.executed),
          ("Journaled", payload.journaled),
        ]

        for (sectionTitle, sectionLogs) in sections {
          guard !sectionLogs.isEmpty else { continue }
          lines.append(
            JournalPreparedLine(
              role: .detail,
              segments: [JournalPreparedSegment(sectionTitle, tone: .secondary)]
            )
          )

          for log in sectionLogs {
            let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append(
              JournalPreparedLine(
                role: .detail,
                segments: [
                  JournalPreparedSegment("• ", tone: .secondary),
                  JournalPreparedSegment(trimmed)
                ]
              )
            )
          }
        }
      }
    }

    let noteLines = preparedTimelineJournalLines(for: journalEntries)
    if !noteLines.isEmpty {
      if !lines.isEmpty {
        lines.append(JournalPreparedLine(role: .detail, segments: [JournalPreparedSegment("")]))
      }

      lines.append(
        JournalPreparedLine(
          role: .summary,
          segments: [JournalPreparedSegment("Journals", tone: .commentary)]
        )
      )
      lines.append(contentsOf: noteLines)
    }

    return lines
  }

  func dayEvents(for day: Date) -> [JournalRenderedHistoryEvent] {
    renderedHistoryEvents.filter {
      Calendar.autoupdatingCurrent.isDate($0.event.occurredAt, inSameDayAs: day)
    }
  }

  func preparedTimelineEventLines(for renderedEvent: JournalRenderedHistoryEvent)
    -> [JournalPreparedLine]
  {
    let event = renderedEvent.event
    let prefix = timelinePrefix(for: event.occurredAt, projectID: event.projectID)

    switch event.kind {
    case .projectCreated:
      return [
        JournalPreparedLine(
          role: .detail,
          segments: prefix + [JournalPreparedSegment("프로젝트 시작")]
        )
      ]

    case .projectUpdated, .projectTimelineChanged, .projectArchived, .projectRestored,
      .projectDeleted:
      let line = historyChangePreparedLine(for: event)
      return [
        JournalPreparedLine(role: line.role, segments: prefix + line.segments)
      ]

    case .taskCreated:
      return [
        JournalPreparedLine(
          role: .detail,
          segments: prefix
            + [
              JournalPreparedSegment("+ ", tone: .added),
              JournalPreparedSegment(historyTaskTitle(for: event))
            ]
        )
      ]

    case .taskCompleted:
      return [
        JournalPreparedLine(
          role: .detail,
          segments: prefix
            + [
              JournalPreparedSegment("완료 ", tone: .secondary),
              JournalPreparedSegment(historyTaskTitle(for: event))
            ]
        )
      ]

    case .taskReopened:
      return [
        JournalPreparedLine(
          role: .detail,
          segments: prefix
            + [
              JournalPreparedSegment("취소 ", tone: .removed),
              JournalPreparedSegment(historyTaskTitle(for: event))
            ]
        )
      ]

    case .taskUpdated, .taskScheduleChanged, .taskMoved, .taskDeleted:
      let line = historyChangePreparedLine(for: event)
      return [
        JournalPreparedLine(role: line.role, segments: prefix + line.segments)
      ]

    case .attachmentAdded:
      return [
        JournalPreparedLine(
          role: .detail,
          segments: prefix
            + [
              JournalPreparedSegment("첨부 ", tone: .added),
              JournalPreparedSegment(historyAttachmentTitle(for: event))
            ]
        )
      ]

    case .projectNoteSaved, .taskReminderNoteSaved:
      guard let delta = renderedEvent.noteDelta else { return [] }
      let owner = noteOwnerPrefix(for: event)
      var lines: [JournalPreparedLine] = []

      for line in delta.addedLines {
        var segments = prefix
        segments.append(JournalPreparedSegment("+ ", tone: .added))
        if let owner, !owner.isEmpty {
          segments.append(JournalPreparedSegment("\(owner) ", tone: .secondary))
        }
        segments.append(JournalPreparedSegment(line))
        lines.append(JournalPreparedLine(role: .detail, segments: segments))
      }

      for line in delta.removedLines {
        var segments = prefix
        segments.append(JournalPreparedSegment("- ", tone: .removed))
        if let owner, !owner.isEmpty {
          segments.append(JournalPreparedSegment("\(owner) ", tone: .secondary))
        }
        segments.append(JournalPreparedSegment(line, tone: .removed, strikethrough: true))
        lines.append(JournalPreparedLine(role: .detail, segments: segments))
      }

      return lines
    }
  }

  func preparedTimelineJournalLines(for entries: [ObsidianJournalEntry]) -> [JournalPreparedLine] {
    entries.flatMap(preparedTimelineJournalLines(for:))
  }

  func preparedTimelineJournalLines(for entry: ObsidianJournalEntry) -> [JournalPreparedLine] {
    let bodyLines = normalizedDisplayLines(entry.body)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    return bodyLines.enumerated().map { index, line in
      var segments: [JournalPreparedSegment] = []
      if index == 0 {
        segments.append(
          JournalPreparedSegment("[\(Self.timeFormatter.string(from: entry.occurredAt))] ", tone: .secondary)
        )
        segments.append(JournalPreparedSegment("내 노트 · ", tone: .secondary))
      } else {
        segments.append(JournalPreparedSegment("      ", tone: .secondary))
      }
      segments.append(JournalPreparedSegment(line, tone: .commentary))
      return JournalPreparedLine(role: .detail, segments: segments)
    }
  }

  func timelinePrefix(for date: Date, projectID: UUID) -> [JournalPreparedSegment] {
    let projectTitle = projectTitlesByID[projectID] ?? "프로젝트"
    return [
      JournalPreparedSegment("[\(Self.timeFormatter.string(from: date))] ", tone: .secondary),
      JournalPreparedSegment("\(projectTitle) · ", tone: .secondary),
    ]
  }

  func systemMeta(for cluster: JournalSystemCluster) -> [JournalPreparedMeta] {
    var meta: [JournalPreparedMeta] = [
      JournalPreparedMeta(text: clusterTimeRange(cluster), tone: .secondary)
    ]

    let countsByKind = Dictionary(grouping: cluster.events) { $0.event.kind }.mapValues(\.count)
    let noteAddedCount = cluster.events.reduce(into: 0) { partial, renderedEvent in
      partial += renderedEvent.noteDelta?.addedLines.count ?? 0
    }
    let noteRemovedCount = cluster.events.reduce(into: 0) { partial, renderedEvent in
      partial += renderedEvent.noteDelta?.removedLines.count ?? 0
    }

    if let count = countsByKind[.taskCompleted], count > 0 {
      meta.append(JournalPreparedMeta(text: "완료 \(count)", tone: .secondary))
    }
    if let count = countsByKind[.taskCreated], count > 0 {
      meta.append(JournalPreparedMeta(text: "생성 \(count)", tone: .added))
    }
    if noteAddedCount > 0 {
      meta.append(JournalPreparedMeta(text: "추가 \(noteAddedCount)", tone: .added))
    }
    if noteRemovedCount > 0 {
      meta.append(JournalPreparedMeta(text: "삭제 \(noteRemovedCount)", tone: .removed))
    }
    if let count = countsByKind[.attachmentAdded], count > 0 {
      meta.append(JournalPreparedMeta(text: "첨부 \(count)", tone: .secondary))
    }

    return meta
  }

  func parsedRetrospectiveLines(
    from text: String,
    fallbackSummary: String,
    fallbackOpinion: String?
  ) -> [JournalPreparedLine] {
    let normalizedLines = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    var summaryParts: [String] = []
    var opinionParts: [String] = []

    for line in normalizedLines {
      if let trimmed = line.removingPrefix("요약:") ?? line.removingPrefix("Summary:") {
        summaryParts.append(trimmed)
      } else if let trimmed = line.removingPrefix("의견:") ?? line.removingPrefix("Comment:") {
        if trimmed.caseInsensitiveCompare("없음") != .orderedSame {
          opinionParts.append(trimmed)
        }
      } else if opinionParts.isEmpty {
        summaryParts.append(line)
      } else {
        opinionParts.append(line)
      }
    }

    let summaryText = summaryParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let opinionText = opinionParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

    var lines: [JournalPreparedLine] = [
      JournalPreparedLine(
        role: .summary,
        segments: [JournalPreparedSegment(summaryText.isEmpty ? fallbackSummary : summaryText)]
      )
    ]

    let resolvedOpinion = opinionText.isEmpty ? fallbackOpinion : opinionText
    if let resolvedOpinion, !resolvedOpinion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      lines.append(
        JournalPreparedLine(
          role: .commentary,
          segments: [JournalPreparedSegment(resolvedOpinion, tone: .commentary)]
        )
      )
    }

    return lines
  }

  func deterministicSummary(for cluster: JournalSystemCluster) -> String {
    let completedTitles = cluster.events
      .filter { $0.event.kind == .taskCompleted }
      .map { historyTaskTitle(for: $0.event) }
    let createdTitles = cluster.events
      .filter { $0.event.kind == .taskCreated }
      .map { historyTaskTitle(for: $0.event) }
    let reopenedTitles = cluster.events
      .filter { $0.event.kind == .taskReopened }
      .map { historyTaskTitle(for: $0.event) }
    let noteAddedLines = cluster.events.flatMap { $0.noteDelta?.addedLines ?? [] }
    let noteRemovedLines = cluster.events.flatMap { $0.noteDelta?.removedLines ?? [] }

    var sentences: [String] = []

    if !createdTitles.isEmpty {
      sentences.append("\(titlePreview(from: createdTitles)) 등을 만들었다.")
    }
    if !completedTitles.isEmpty {
      sentences.append("\(titlePreview(from: completedTitles))를 마쳤다.")
    }
    if !reopenedTitles.isEmpty {
      sentences.append("\(titlePreview(from: reopenedTitles)) 완료를 다시 열었다.")
    }
    if !noteAddedLines.isEmpty {
      sentences.append("노트에는 \(linePreview(from: noteAddedLines)) 같은 내용이 더해졌다.")
    }
    if !noteRemovedLines.isEmpty {
      sentences.append("지워진 메모는 \(linePreview(from: noteRemovedLines)) 쪽이었다.")
    }

    if sentences.isEmpty {
      return "이 구간의 작업 기록을 정리했다."
    }

    return sentences.prefix(3).joined(separator: " ")
  }

  func deterministicOpinion(for entries: [ObsidianJournalEntry]) -> String? {
    let noteLines = entries.flatMap { entry in
      normalizedDisplayLines(entry.body)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    guard !noteLines.isEmpty else { return nil }
    return linePreview(from: noteLines, limit: 1)
  }

  func dayDetailButton(for section: JournalPreparedDaySection) -> some View {
    Button {
      detailPopoverDayID = section.id
    } label: {
      Text("+")
        .font(JournalTypography.font(size: 14, weight: .bold))
        .frame(width: 28, height: 28)
        .overlaySurface(
          cornerRadius: 8,
          fillColor: .black,
          strokeColor: .black,
          style: journalChromeButtonSurfaceStyle
        )
    }
    .buttonStyle(.plain)
    .popover(
      isPresented: Binding(
        get: { detailPopoverDayID == section.id },
        set: { isPresented in
          if !isPresented && detailPopoverDayID == section.id {
            detailPopoverDayID = nil
          }
        }
      ),
      arrowEdge: .trailing
    ) {
      dayDetailPopover(section)
    }
  }

  func dayDetailPopover(_ section: JournalPreparedDaySection) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(section.title)
            .font(JournalTypography.font(size: 12))
            .foregroundStyle(.secondary)

          ForEach(Array(section.detailLines.enumerated()), id: \.offset) { _, line in
            segmentedLineView(line)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 320)
    }
    .padding(18)
    .frame(width: 420, alignment: .leading)
    .overlaySurface(
      cornerRadius: 14,
      fillColor: Color(nsColor: .textBackgroundColor),
      strokeColor: .black,
      style: journalDetailPopoverSurfaceStyle
    )
  }

  func historyTaskTitle(for event: ProjectHistoryEvent) -> String {
    let trimmed = event.taskTitleSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "제목 없음 할일" : trimmed
  }

  func historyChangeLogText(for event: ProjectHistoryEvent) -> String {
    let trimmed = event.detailTextSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmed.isEmpty {
      return trimmed
    }
    switch event.kind {
    case .taskDeleted:
      return "할일을 삭제했다."
    case .projectArchived:
      return "프로젝트를 아카이브했다."
    case .projectRestored:
      return "프로젝트를 복원했다."
    case .projectDeleted:
      return "프로젝트를 영구 삭제했다."
    default:
      return historyTaskTitle(for: event)
    }
  }

  func historyChangePreparedLine(for event: ProjectHistoryEvent) -> JournalPreparedLine {
    let label: String
    let tone: JournalTone
    switch event.kind {
    case .projectUpdated:
      label = "프로젝트 수정 "
      tone = .secondary
    case .projectTimelineChanged:
      label = "프로젝트 기간 "
      tone = .secondary
    case .projectArchived:
      label = "아카이브 "
      tone = .removed
    case .projectRestored:
      label = "복원 "
      tone = .added
    case .projectDeleted:
      label = "프로젝트 삭제 "
      tone = .removed
    case .taskUpdated:
      label = "수정 "
      tone = .secondary
    case .taskScheduleChanged:
      label = "일정 "
      tone = .secondary
    case .taskMoved:
      label = "이동 "
      tone = .secondary
    case .taskDeleted:
      label = "삭제 "
      tone = .removed
    default:
      label = ""
      tone = .secondary
    }

    let summary = historyChangeLogText(for: event)
    var segments: [JournalPreparedSegment] = []
    if !label.isEmpty {
      segments.append(JournalPreparedSegment(label, tone: tone))
    }
    segments.append(
      JournalPreparedSegment(
        summary,
        tone: event.kind == .taskDeleted || event.kind == .projectDeleted ? .removed : .primary
      )
    )
    return JournalPreparedLine(role: .detail, segments: segments)
  }

  func historyAttachmentTitle(for event: ProjectHistoryEvent) -> String {
    if let filename = event.attachmentFilename, !filename.isEmpty {
      if let taskTitle = event.taskTitleSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines),
        !taskTitle.isEmpty
      {
        return "\(taskTitle) · \(filename)"
      }
      return filename
    }
    return event.taskTitleSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? (event.taskTitleSnapshot ?? "첨부")
      : "첨부"
  }

  func clusterTimeRange(_ cluster: JournalSystemCluster) -> String {
    let startText = Self.timeFormatter.string(from: cluster.startAt)
    let endText = Self.timeFormatter.string(from: cluster.endAt)
    return startText == endText ? startText : "\(startText)-\(endText)"
  }

  func dayTitle(for day: Date) -> String {
    let base = Self.dayFormatter.string(from: day)
    if Calendar.autoupdatingCurrent.isDateInToday(day) {
      return "\(base) · 오늘"
    }
    return base
  }

  func daySummary(for day: Date, systemCount: Int, journalCount: Int) -> String {
    if systemCount == 0 && journalCount == 0 {
      return Calendar.autoupdatingCurrent.isDateInToday(day)
        ? "지금부터 기록이 이어집니다."
        : "기록이 없습니다."
    }

    if !Calendar.autoupdatingCurrent.isDateInToday(day) {
      return ""
    }

    var parts: [String] = []
    if systemCount > 0 {
      parts.append("시스템 \(systemCount)")
    }
    if journalCount > 0 {
      parts.append("Journals \(journalCount)")
    }
    return parts.joined(separator: " · ")
  }

  func normalizedDisplayLines(_ text: String) -> [String] {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
  }

  func titlePreview(from titles: [String], limit: Int = 2) -> String {
    let unique = Array(NSOrderedSet(array: titles)) as? [String] ?? titles
    let preview = unique
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .prefix(limit)

    let joined = preview.joined(separator: ", ")
    if unique.count > limit, !joined.isEmpty {
      return "\(joined) 외 \(unique.count - limit)건"
    }
    return joined.isEmpty ? "기록된 항목" : joined
  }

  func linePreview(from lines: [String], limit: Int = 1) -> String {
    let unique = Array(NSOrderedSet(array: lines)) as? [String] ?? lines
    let preview = unique
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .prefix(limit)
      .joined(separator: " / ")

    if preview.isEmpty {
      return "메모"
    }
    if unique.count > limit {
      return "\(preview) 외 \(unique.count - limit)줄"
    }
    return preview
  }
}
