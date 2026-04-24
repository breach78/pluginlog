@preconcurrency import EventKit
import Foundation

private enum OutlinerReminderSourceIOError: LocalizedError {
  case gatewayUnavailable
  case missingOwnerCalendar

  var errorDescription: String? {
    switch self {
    case .gatewayUnavailable:
      return "Reminders 연결을 아직 준비하지 못했습니다."
    case .missingOwnerCalendar:
      return "owner calendar를 찾지 못했습니다."
    }
  }
}

@MainActor
extension AppState {
  func fetchOutlinerRemoteReminderIndex(
    for projections: [OutlinerReminderProjection],
    linkedReminderIdentifiersByContentID: [UUID: String]
  ) async throws -> [UUID: OutlinerRemoteReminderImport] {
    let gateway = try outlinerReminderGateway()

    var remoteIndex: [UUID: OutlinerRemoteReminderImport] = [:]
    for projection in projections {
      guard
        let reminderIdentifier = normalizedProjectionValue(
          linkedReminderIdentifiersByContentID[projection.contentID]
        ),
        let reminder = try gateway.reminder(withIdentifier: reminderIdentifier)
      else {
        continue
      }
      remoteIndex[projection.contentID] = makeOutlinerRemoteReminderImport(
        from: reminder,
        contentID: projection.contentID,
        gateway: gateway
      )
    }
    return remoteIndex
  }

  func saveOutlinerReminderProjection(
    _ projection: OutlinerReminderProjection,
    linkedReminderIdentifier: String?,
    calendarIdentifier: String?,
    encodedNoteOverride: String? = nil,
    pendingOperationRecord: ReminderSyncPendingOperationRecord? = nil
  ) async throws -> OutlinerLiveReminderSnapshot {
    let gateway = try outlinerReminderGateway()
    let existingReminder = try resolvedOutlinerReminder(
      using: gateway,
      linkedReminderIdentifier: linkedReminderIdentifier
    )
    let reminder =
      try existingReminder
      ?? makeOutlinerReminder(
        using: gateway,
        calendarIdentifier: calendarIdentifier
      )
    applyOutlinerProjection(
      projection,
      encodedNoteOverride: encodedNoteOverride,
      to: reminder
    )

    if let pendingOperationRecord {
      reminderSyncRecoveryJournal?.enqueue(pendingOperationRecord)
    }

    try gateway.save(reminder)

    let snapshot = makeOutlinerLiveReminderSnapshot(
      from: reminder,
      projection: projection,
      gateway: gateway
    )
    if let pendingOperationRecord {
      reminderSyncRecoveryJournal?.markRemoteWriteCompleted(
        operationID: pendingOperationRecord.operationID,
        reminderIdentifier: snapshot.reminderIdentifier,
        reminderExternalIdentifier: snapshot.reminderExternalIdentifier,
        remoteLastModifiedAt: snapshot.lastModifiedAt
      )
      reminderSyncRecoveryJournal?.remove(operationID: pendingOperationRecord.operationID)
    }
    return snapshot
  }

  func saveOutlinerReminderProjectionMetadata(
    _ projection: OutlinerReminderProjection,
    linkedReminderIdentifier: String?,
    calendarIdentifier: String?,
    metadataPlanOverride: ReminderMetadataMutationPlan? = nil
  ) async throws -> OutlinerLiveReminderSnapshot {
    let gateway = try outlinerReminderGateway()
    let existingReminder = try resolvedOutlinerReminder(
      using: gateway,
      linkedReminderIdentifier: linkedReminderIdentifier
    )
    let reminder =
      try existingReminder
      ?? makeOutlinerReminder(
        using: gateway,
        calendarIdentifier: calendarIdentifier
      )
    let metadataPlan = metadataPlanOverride ?? ReminderMetadataMutationService.plan(for: projection)
    applyOutlinerMetadataPlan(metadataPlan, to: reminder)
    if existingReminder == nil,
       reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    {
      reminder.notes = projection.encodedReminderNote
    }

    try gateway.save(reminder)
    return makeOutlinerLiveReminderSnapshot(
      from: reminder,
      projection: projection,
      gateway: gateway
    )
  }

  func refreshOutlinerReminderProjection(
    _ projection: OutlinerReminderProjection,
    linkedReminderIdentifier: String?
  ) async throws -> OutlinerLiveReminderSnapshot? {
    let gateway = try outlinerReminderGateway()
    guard let reminder = try resolvedOutlinerReminder(
      using: gateway,
      linkedReminderIdentifier: linkedReminderIdentifier
    ) else {
      return nil
    }

    return makeOutlinerLiveReminderSnapshot(
      from: reminder,
      projection: projection,
      gateway: gateway
    )
  }

  func resolvedOutlinerReminderOwnerStatus(
    for taskState: OutlinerIntegratedTaskState,
    currentProjectID: UUID,
    visibleProjectIDs: Set<UUID>,
    projectReminderListIdentifiersByProjectID: [UUID: String]
  ) -> OutlinerReminderOwnerStatus {
    if !taskState.reminderBacked {
      guard
        let calendarIdentifier = normalizedProjectionValue(
          projectReminderListIdentifiersByProjectID[currentProjectID]
        )
      else {
        return .ownerMissing
      }
      return .resolved(projectID: currentProjectID, calendarIdentifier: calendarIdentifier)
    }

    guard let ownerProjectID = taskState.ownerProjectID,
          let ownerCalendarID = normalizedProjectionValue(taskState.ownerCalendarID)
    else {
      return .ownerMissing
    }

    guard visibleProjectIDs.contains(ownerProjectID) else {
      return .ownerMissing
    }

    let actualCalendarIdentifier = normalizedProjectionValue(
      projectReminderListIdentifiersByProjectID[ownerProjectID]
    )
    if actualCalendarIdentifier != ownerCalendarID {
      return .ownerDrift(
        projectID: ownerProjectID,
        expectedCalendarIdentifier: ownerCalendarID,
        actualCalendarIdentifier: actualCalendarIdentifier
      )
    }
    if reminderGateway.calendar(withIdentifier: ownerCalendarID) == nil {
      return .ownerPermissionLost(
        projectID: ownerProjectID,
        calendarIdentifier: ownerCalendarID
      )
    }
    return .resolved(projectID: ownerProjectID, calendarIdentifier: ownerCalendarID)
  }

  private func outlinerReminderGateway() throws -> any ReminderGateway {
    reminderGateway
  }

  private func resolvedOutlinerReminder(
    using gateway: any ReminderGateway,
    linkedReminderIdentifier: String?
  ) throws -> EKReminder? {
    guard let identifier = normalizedProjectionValue(linkedReminderIdentifier) else {
      return nil
    }
    return try gateway.reminder(withIdentifier: identifier)
  }

  private func makeOutlinerReminder(
    using gateway: any ReminderGateway,
    calendarIdentifier: String?
  ) throws -> EKReminder {
    let calendar = try resolvedOutlinerWriteCalendar(
      using: gateway,
      calendarIdentifier: calendarIdentifier
    )
    let reminder = try gateway.makeReminder(in: calendar)
    reminder.calendar = calendar
    return reminder
  }

  private func resolvedOutlinerWriteCalendar(
    using gateway: any ReminderGateway,
    calendarIdentifier: String?
  ) throws -> EKCalendar {
    if let calendarIdentifier = normalizedProjectionValue(calendarIdentifier),
       let calendar = try gateway.calendar(withIdentifier: calendarIdentifier)
    {
      return calendar
    }
    throw OutlinerReminderSourceIOError.missingOwnerCalendar
  }

  private func applyOutlinerProjection(
    _ projection: OutlinerReminderProjection,
    encodedNoteOverride: String?,
    to reminder: EKReminder
  ) {
    let metadataPlan = ReminderMetadataMutationService.plan(for: projection)
    applyOutlinerMetadataPlan(metadataPlan, to: reminder)
    reminder.notes = encodedNoteOverride ?? projection.encodedReminderNote
  }

  private func applyOutlinerMetadataPlan(
    _ metadataPlan: ReminderMetadataMutationPlan,
    to reminder: EKReminder
  ) {
    reminder.title = metadataPlan.title
    reminder.isCompleted = metadataPlan.isCompleted
    reminder.completionDate = metadataPlan.isCompleted ? (reminder.completionDate ?? .now) : nil
    reminder.priority = metadataPlan.priority
    reminder.startDateComponents = nil
    reminder.dueDateComponents = normalizedOutlinerDateComponentsForPush(
      from: metadataPlan.dueDate,
      existing: reminder.dueDateComponents,
      hasExplicitTime: metadataPlan.hasExplicitTime
    )
    reminder.recurrenceRules = metadataPlan.recurrence.map(outlinerRecurrenceRules(from:))
  }

  private func makeOutlinerLiveReminderSnapshot(
    from reminder: EKReminder,
    projection: OutlinerReminderProjection,
    gateway: any ReminderGateway
  ) -> OutlinerLiveReminderSnapshot {
    let parsedBody = ReminderNoteSourceCodec.normalizeReminderRawNote(reminder.notes)
    let reminderTitle = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let dueDateComponents = reminder.dueDateComponents
    let recurrence = outlinerRecurrenceSample(from: reminder.recurrenceRules)
    return OutlinerLiveReminderSnapshot(
      contentID: projection.contentID,
      reminderIdentifier: reminder.calendarItemIdentifier,
      reminderExternalIdentifier: reminder.calendarItemExternalIdentifier,
      calendarIdentifier: reminder.calendar.calendarIdentifier,
      calendarTitle: reminder.calendar.title,
      rawPreservationPayloadRaw: ReminderSyncRawPreservationCodec.encode(reminder: reminder),
      title: reminderTitle?.isEmpty == false ? reminderTitle! : projection.title,
      encodedNote: reminder.notes ?? "",
      parsedBody: parsedBody,
      dueDateText: formattedOutlinerDueDateText(from: dueDateComponents),
      recurrenceText: recurrence?.displayText ?? "반복 없음",
      requiredWorkDays: projection.syncContract.requiredWorkDays,
      isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate,
      lastModifiedText: formattedOutlinerLastModifiedText(for: reminder, gateway: gateway),
      lastModifiedAt: gateway.lastModifiedDate(for: reminder),
      restoredAppSnippetText: OutlinerReminderProjectionBuilder.restoredAppSnippetText(
        for: projection,
        reminderTitle: reminderTitle ?? projection.title,
        reminderBody: parsedBody
      ),
      dueDate: dueDateComponents.flatMap { Calendar.current.date(from: $0) },
      hasExplicitTime: dueDateComponents.map(outlinerHasExplicitTime(in:)) ?? false,
      recurrence: recurrence,
      priority: reminder.priority
    )
  }

  private func makeOutlinerRemoteReminderImport(
    from reminder: EKReminder,
    contentID: UUID?,
    gateway: any ReminderGateway
  ) -> OutlinerRemoteReminderImport {
    let parsedBody = ReminderNoteSourceCodec.normalizeReminderRawNote(reminder.notes)
    let reminderTitle = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let dueDateComponents = reminder.dueDateComponents
    let recurrence = outlinerRecurrenceSample(from: reminder.recurrenceRules)
    return OutlinerRemoteReminderImport(
      contentID: contentID,
      reminderIdentifier: reminder.calendarItemIdentifier,
      reminderExternalIdentifier: reminder.calendarItemExternalIdentifier,
      calendarIdentifier: reminder.calendar.calendarIdentifier,
      rawPreservationPayloadRaw: ReminderSyncRawPreservationCodec.encode(reminder: reminder),
      title: reminderTitle?.isEmpty == false ? reminderTitle! : "새 할일",
      encodedNote: reminder.notes ?? "",
      parsedBody: parsedBody,
      dueDateText: formattedOutlinerDueDateText(from: dueDateComponents),
      recurrenceText: recurrence?.displayText ?? "반복 없음",
      requiredWorkDays: 0,
      isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate,
      lastModifiedText: formattedOutlinerLastModifiedText(for: reminder, gateway: gateway),
      lastModifiedAt: gateway.lastModifiedDate(for: reminder),
      dueDate: dueDateComponents.flatMap { Calendar.current.date(from: $0) },
      hasExplicitTime: dueDateComponents.map(outlinerHasExplicitTime(in:)) ?? false,
      recurrence: recurrence,
      priority: reminder.priority
    )
  }

  private func formattedOutlinerLastModifiedText(
    for reminder: EKReminder,
    gateway: any ReminderGateway
  ) -> String {
    guard let lastModifiedDate = gateway.lastModifiedDate(for: reminder) else {
      return "알 수 없음"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
    formatter.dateFormat = "M월 d일 a h:mm"
    return formatter.string(from: lastModifiedDate)
  }

  private func formattedOutlinerDueDateText(from components: DateComponents?) -> String {
    guard let components else { return "없음" }
    let calendar = components.calendar ?? Calendar.autoupdatingCurrent
    guard let date = calendar.date(from: components) else { return "없음" }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = components.timeZone ?? TimeZone(identifier: "Asia/Seoul")
    formatter.calendar = calendar
    formatter.dateFormat = outlinerHasExplicitTime(in: components) ? "M월 d일 a h:mm" : "M월 d일"
    return formatter.string(from: date)
  }

  private func outlinerRecurrenceSample(
    from rules: [EKRecurrenceRule]?
  ) -> OutlinerRecurrenceSample? {
    guard let first = rules?.first else { return nil }
    switch first.frequency {
    case .daily:
      return .daily(interval: max(1, first.interval))
    case .weekly:
      return .weekly(
        interval: max(1, first.interval),
        weekdays: (first.daysOfTheWeek ?? []).map(\.dayOfTheWeek.rawValue)
      )
    case .monthly:
      return .monthly(interval: max(1, first.interval))
    case .yearly:
      return .yearly(interval: max(1, first.interval))
    @unknown default:
      return nil
    }
  }

  private func outlinerRecurrenceRules(
    from sample: OutlinerRecurrenceSample
  ) -> [EKRecurrenceRule] {
    switch sample {
    case let .daily(interval):
      return [EKRecurrenceRule(recurrenceWith: .daily, interval: max(1, interval), end: nil)]
    case let .weekly(interval, weekdays):
      let daysOfWeek = weekdays.compactMap { rawValue -> EKRecurrenceDayOfWeek? in
        guard let weekday = EKWeekday(rawValue: rawValue) else { return nil }
        return EKRecurrenceDayOfWeek(weekday)
      }
      return [EKRecurrenceRule(
        recurrenceWith: .weekly,
        interval: max(1, interval),
        daysOfTheWeek: daysOfWeek.isEmpty ? nil : daysOfWeek,
        daysOfTheMonth: nil,
        monthsOfTheYear: nil,
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nil,
        end: nil
      )]
    case let .monthly(interval):
      return [EKRecurrenceRule(recurrenceWith: .monthly, interval: max(1, interval), end: nil)]
    case let .yearly(interval):
      return [EKRecurrenceRule(recurrenceWith: .yearly, interval: max(1, interval), end: nil)]
    }
  }

  private func normalizedOutlinerDateComponentsForPush(
    from localDate: Date?,
    existing: DateComponents?,
    hasExplicitTime: Bool
  ) -> DateComponents? {
    guard let localDate else { return nil }

    let calendar = Calendar.autoupdatingCurrent
    guard !hasExplicitTime else {
      var components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second, .timeZone],
        from: localDate
      )
      components.calendar = existing?.calendar ?? calendar
      components.timeZone = existing?.timeZone ?? components.timeZone ?? .current
      return components
    }

    return calendar.dateComponents([.year, .month, .day], from: localDate)
  }

  private func outlinerHasExplicitTime(in components: DateComponents) -> Bool {
    components.hour != nil || components.minute != nil || components.second != nil
  }
}
