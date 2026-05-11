import CoreLocation
@preconcurrency import EventKit
import Foundation

struct ReminderArchiveListDetailSnapshot: Codable, Equatable, Sendable {
  let identifier: String
  let externalIdentifier: String?
  let title: String
  let colorHex: String?
  let calendarTypeRaw: Int?
  let sourceIdentifier: String?
  let sourceTitle: String?
  let sourceTypeRaw: Int?
  let allowsContentModifications: Bool?
  let isImmutable: Bool?
  let isSubscribed: Bool?

  init(
    identifier: String,
    externalIdentifier: String?,
    title: String,
    colorHex: String?,
    calendarTypeRaw: Int?,
    sourceIdentifier: String?,
    sourceTitle: String?,
    sourceTypeRaw: Int?,
    allowsContentModifications: Bool? = nil,
    isImmutable: Bool? = nil,
    isSubscribed: Bool? = nil
  ) {
    self.identifier = identifier
    self.externalIdentifier = externalIdentifier
    self.title = title
    self.colorHex = colorHex
    self.calendarTypeRaw = calendarTypeRaw
    self.sourceIdentifier = sourceIdentifier
    self.sourceTitle = sourceTitle
    self.sourceTypeRaw = sourceTypeRaw
    self.allowsContentModifications = allowsContentModifications
    self.isImmutable = isImmutable
    self.isSubscribed = isSubscribed
  }

  init(calendar: EKCalendar, colorHex: String?) {
    self.init(
      identifier: calendar.calendarIdentifier,
      externalIdentifier: calendar.calendarIdentifier,
      title: calendar.title,
      colorHex: colorHex,
      calendarTypeRaw: calendar.type.rawValue,
      sourceIdentifier: calendar.source?.sourceIdentifier,
      sourceTitle: calendar.source?.title,
      sourceTypeRaw: calendar.source?.sourceType.rawValue,
      allowsContentModifications: calendar.allowsContentModifications,
      isImmutable: calendar.isImmutable,
      isSubscribed: calendar.isSubscribed
    )
  }
}

struct ReminderArchiveDateComponentsSnapshot: Codable, Equatable, Sendable {
  let calendarIdentifier: String?
  let timeZoneIdentifier: String?
  let era: Int?
  let year: Int?
  let month: Int?
  let day: Int?
  let hour: Int?
  let minute: Int?
  let second: Int?
  let nanosecond: Int?
  let weekday: Int?
  let weekdayOrdinal: Int?
  let quarter: Int?
  let weekOfMonth: Int?
  let weekOfYear: Int?
  let yearForWeekOfYear: Int?
  let isLeapMonth: Bool?

  init(
    calendarIdentifier: String? = nil,
    timeZoneIdentifier: String? = nil,
    era: Int? = nil,
    year: Int? = nil,
    month: Int? = nil,
    day: Int? = nil,
    hour: Int? = nil,
    minute: Int? = nil,
    second: Int? = nil,
    nanosecond: Int? = nil,
    weekday: Int? = nil,
    weekdayOrdinal: Int? = nil,
    quarter: Int? = nil,
    weekOfMonth: Int? = nil,
    weekOfYear: Int? = nil,
    yearForWeekOfYear: Int? = nil,
    isLeapMonth: Bool? = nil
  ) {
    self.calendarIdentifier = calendarIdentifier
    self.timeZoneIdentifier = timeZoneIdentifier
    self.era = era
    self.year = year
    self.month = month
    self.day = day
    self.hour = hour
    self.minute = minute
    self.second = second
    self.nanosecond = nanosecond
    self.weekday = weekday
    self.weekdayOrdinal = weekdayOrdinal
    self.quarter = quarter
    self.weekOfMonth = weekOfMonth
    self.weekOfYear = weekOfYear
    self.yearForWeekOfYear = yearForWeekOfYear
    self.isLeapMonth = isLeapMonth
  }

  init(_ components: DateComponents) {
    self.init(
      calendarIdentifier: Self.calendarIdentifierString(components.calendar?.identifier),
      timeZoneIdentifier: components.timeZone?.identifier,
      era: components.era,
      year: components.year,
      month: components.month,
      day: components.day,
      hour: components.hour,
      minute: components.minute,
      second: components.second,
      nanosecond: components.nanosecond,
      weekday: components.weekday,
      weekdayOrdinal: components.weekdayOrdinal,
      quarter: components.quarter,
      weekOfMonth: components.weekOfMonth,
      weekOfYear: components.weekOfYear,
      yearForWeekOfYear: components.yearForWeekOfYear,
      isLeapMonth: components.isLeapMonth
    )
  }

  var dateComponents: DateComponents {
    var components = DateComponents()
    if let identifier = calendarIdentifier.flatMap(Self.calendarIdentifier(from:)) {
      components.calendar = Calendar(identifier: identifier)
    }
    components.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    components.era = era
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    components.nanosecond = nanosecond
    components.weekday = weekday
    components.weekdayOrdinal = weekdayOrdinal
    components.quarter = quarter
    components.weekOfMonth = weekOfMonth
    components.weekOfYear = weekOfYear
    components.yearForWeekOfYear = yearForWeekOfYear
    components.isLeapMonth = isLeapMonth
    return components
  }

  var date: Date? {
    var components = dateComponents
    if components.calendar == nil {
      components.calendar = Calendar(identifier: .gregorian)
    }
    return components.date
  }

  private static func calendarIdentifierString(_ identifier: Calendar.Identifier?) -> String? {
    switch identifier {
    case .gregorian:
      return "gregorian"
    case .iso8601:
      return "iso8601"
    case .none:
      return nil
    default:
      return nil
    }
  }

  private static func calendarIdentifier(from rawValue: String) -> Calendar.Identifier? {
    switch rawValue {
    case "gregorian":
      return .gregorian
    case "iso8601":
      return .iso8601
    default:
      return nil
    }
  }
}

struct ReminderArchiveRecurrenceEndSnapshot: Codable, Equatable, Sendable {
  let endDate: Date?
  let occurrenceCount: UInt?

  init(endDate: Date?, occurrenceCount: UInt?) {
    self.endDate = endDate
    self.occurrenceCount = occurrenceCount
  }

  init(_ end: EKRecurrenceEnd) {
    self.init(
      endDate: end.endDate,
      occurrenceCount: end.occurrenceCount > 0 ? UInt(end.occurrenceCount) : nil
    )
  }

  var recurrenceEnd: EKRecurrenceEnd? {
    if let endDate {
      return EKRecurrenceEnd(end: endDate)
    }
    if let occurrenceCount, occurrenceCount > 0 {
      return EKRecurrenceEnd(occurrenceCount: Int(occurrenceCount))
    }
    return nil
  }
}

struct ReminderArchiveRecurrenceDayOfWeekSnapshot: Codable, Equatable, Sendable {
  let dayOfTheWeekRaw: Int
  let weekNumber: Int

  init(dayOfTheWeekRaw: Int, weekNumber: Int) {
    self.dayOfTheWeekRaw = dayOfTheWeekRaw
    self.weekNumber = weekNumber
  }

  init(_ day: EKRecurrenceDayOfWeek) {
    self.init(dayOfTheWeekRaw: day.dayOfTheWeek.rawValue, weekNumber: day.weekNumber)
  }

  var dayOfWeek: EKRecurrenceDayOfWeek? {
    guard let weekday = EKWeekday(rawValue: dayOfTheWeekRaw) else { return nil }
    return EKRecurrenceDayOfWeek(weekday, weekNumber: weekNumber)
  }
}

struct ReminderArchiveRecurrenceRuleSnapshot: Codable, Equatable, Sendable {
  let frequencyRaw: Int
  let interval: Int
  let firstDayOfTheWeek: Int
  let recurrenceEnd: ReminderArchiveRecurrenceEndSnapshot?
  let daysOfTheWeek: [ReminderArchiveRecurrenceDayOfWeekSnapshot]
  let daysOfTheMonth: [Int]
  let monthsOfTheYear: [Int]
  let weeksOfTheYear: [Int]
  let daysOfTheYear: [Int]
  let setPositions: [Int]

  init(
    frequencyRaw: Int,
    interval: Int,
    firstDayOfTheWeek: Int,
    recurrenceEnd: ReminderArchiveRecurrenceEndSnapshot?,
    daysOfTheWeek: [ReminderArchiveRecurrenceDayOfWeekSnapshot],
    daysOfTheMonth: [Int],
    monthsOfTheYear: [Int],
    weeksOfTheYear: [Int],
    daysOfTheYear: [Int],
    setPositions: [Int]
  ) {
    self.frequencyRaw = frequencyRaw
    self.interval = interval
    self.firstDayOfTheWeek = firstDayOfTheWeek
    self.recurrenceEnd = recurrenceEnd
    self.daysOfTheWeek = daysOfTheWeek
    self.daysOfTheMonth = daysOfTheMonth
    self.monthsOfTheYear = monthsOfTheYear
    self.weeksOfTheYear = weeksOfTheYear
    self.daysOfTheYear = daysOfTheYear
    self.setPositions = setPositions
  }

  init(_ rule: EKRecurrenceRule) {
    self.init(
      frequencyRaw: rule.frequency.rawValue,
      interval: max(1, rule.interval),
      firstDayOfTheWeek: rule.firstDayOfTheWeek,
      recurrenceEnd: rule.recurrenceEnd.map(ReminderArchiveRecurrenceEndSnapshot.init),
      daysOfTheWeek: (rule.daysOfTheWeek ?? []).map(ReminderArchiveRecurrenceDayOfWeekSnapshot.init),
      daysOfTheMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
      monthsOfTheYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
      weeksOfTheYear: (rule.weeksOfTheYear ?? []).map(\.intValue),
      daysOfTheYear: (rule.daysOfTheYear ?? []).map(\.intValue),
      setPositions: (rule.setPositions ?? []).map(\.intValue)
    )
  }

  var recurrenceRule: EKRecurrenceRule? {
    guard let frequency = EKRecurrenceFrequency(rawValue: frequencyRaw) else { return nil }
    return EKRecurrenceRule(
      recurrenceWith: frequency,
      interval: max(1, interval),
      daysOfTheWeek: daysOfTheWeek.compactMap(\.dayOfWeek).nilIfEmpty,
      daysOfTheMonth: daysOfTheMonth.map(NSNumber.init(value:)).nilIfEmpty,
      monthsOfTheYear: monthsOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
      weeksOfTheYear: weeksOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
      daysOfTheYear: daysOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
      setPositions: setPositions.map(NSNumber.init(value:)).nilIfEmpty,
      end: recurrenceEnd?.recurrenceEnd
    )
  }
}

struct ReminderArchiveStructuredLocationSnapshot: Codable, Equatable, Sendable {
  let title: String?
  let latitude: Double?
  let longitude: Double?
  let altitude: Double?
  let horizontalAccuracy: Double?
  let verticalAccuracy: Double?
  let timestamp: Date?
  let radius: Double

  init(
    title: String?,
    latitude: Double? = nil,
    longitude: Double? = nil,
    altitude: Double? = nil,
    horizontalAccuracy: Double? = nil,
    verticalAccuracy: Double? = nil,
    timestamp: Date? = nil,
    radius: Double
  ) {
    self.title = title
    self.latitude = latitude
    self.longitude = longitude
    self.altitude = altitude
    self.horizontalAccuracy = horizontalAccuracy
    self.verticalAccuracy = verticalAccuracy
    self.timestamp = timestamp
    self.radius = radius
  }

  init(_ location: EKStructuredLocation) {
    self.init(
      title: location.title,
      latitude: location.geoLocation?.coordinate.latitude,
      longitude: location.geoLocation?.coordinate.longitude,
      altitude: location.geoLocation?.altitude,
      horizontalAccuracy: location.geoLocation?.horizontalAccuracy,
      verticalAccuracy: location.geoLocation?.verticalAccuracy,
      timestamp: location.geoLocation?.timestamp,
      radius: location.radius
    )
  }

  var structuredLocation: EKStructuredLocation? {
    guard let title else { return nil }
    let location = EKStructuredLocation(title: title)
    if let latitude, let longitude {
      location.geoLocation = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        altitude: altitude ?? 0,
        horizontalAccuracy: horizontalAccuracy ?? kCLLocationAccuracyThreeKilometers,
        verticalAccuracy: verticalAccuracy ?? -1,
        timestamp: timestamp ?? .now
      )
    }
    location.radius = radius
    return location
  }
}

struct ReminderArchiveAlarmSnapshot: Codable, Equatable, Sendable {
  let relativeOffset: TimeInterval?
  let absoluteDate: Date?
  let structuredLocation: ReminderArchiveStructuredLocationSnapshot?
  let proximityRaw: Int
  let typeRaw: Int
  let emailAddress: String?
  let soundName: String?
  let urlString: String?

  init(
    relativeOffset: TimeInterval?,
    absoluteDate: Date?,
    structuredLocation: ReminderArchiveStructuredLocationSnapshot?,
    proximityRaw: Int,
    typeRaw: Int,
    emailAddress: String?,
    soundName: String?,
    urlString: String?
  ) {
    self.relativeOffset = relativeOffset
    self.absoluteDate = absoluteDate
    self.structuredLocation = structuredLocation
    self.proximityRaw = proximityRaw
    self.typeRaw = typeRaw
    self.emailAddress = emailAddress
    self.soundName = soundName
    self.urlString = urlString
  }

  init(_ alarm: EKAlarm) {
    self.init(
      relativeOffset: alarm.absoluteDate == nil ? alarm.relativeOffset : nil,
      absoluteDate: alarm.absoluteDate,
      structuredLocation: alarm.structuredLocation.map(ReminderArchiveStructuredLocationSnapshot.init),
      proximityRaw: alarm.proximity.rawValue,
      typeRaw: alarm.type.rawValue,
      emailAddress: alarm.emailAddress,
      soundName: alarm.soundName,
      urlString: nil
    )
  }

  var alarm: EKAlarm {
    let alarm = absoluteDate.map(EKAlarm.init(absoluteDate:))
      ?? EKAlarm(relativeOffset: relativeOffset ?? 0)
    alarm.structuredLocation = structuredLocation?.structuredLocation
    if let proximity = EKAlarmProximity(rawValue: proximityRaw) {
      alarm.proximity = proximity
    }
    alarm.emailAddress = emailAddress
    alarm.soundName = soundName
    return alarm
  }
}

struct ReminderArchiveTaskDetailSnapshot: Codable, Equatable, Sendable {
  let identifier: String
  let externalIdentifier: String?
  let calendarIdentifier: String
  let title: String
  let location: String?
  let notes: String?
  let urlString: String?
  let creationDate: Date?
  let lastModifiedDate: Date?
  let timeZoneIdentifier: String?
  let startDateComponents: ReminderArchiveDateComponentsSnapshot?
  let dueDateComponents: ReminderArchiveDateComponentsSnapshot?
  let isCompleted: Bool
  let completionDate: Date?
  let priority: Int
  let recurrenceRules: [ReminderArchiveRecurrenceRuleSnapshot]
  let alarms: [ReminderArchiveAlarmSnapshot]

  init(
    identifier: String,
    externalIdentifier: String?,
    calendarIdentifier: String,
    title: String,
    location: String?,
    notes: String?,
    urlString: String?,
    creationDate: Date?,
    lastModifiedDate: Date?,
    timeZoneIdentifier: String?,
    startDateComponents: ReminderArchiveDateComponentsSnapshot?,
    dueDateComponents: ReminderArchiveDateComponentsSnapshot?,
    isCompleted: Bool,
    completionDate: Date?,
    priority: Int,
    recurrenceRules: [ReminderArchiveRecurrenceRuleSnapshot],
    alarms: [ReminderArchiveAlarmSnapshot]
  ) {
    self.identifier = identifier
    self.externalIdentifier = externalIdentifier
    self.calendarIdentifier = calendarIdentifier
    self.title = title
    self.location = location
    self.notes = notes
    self.urlString = urlString
    self.creationDate = creationDate
    self.lastModifiedDate = lastModifiedDate
    self.timeZoneIdentifier = timeZoneIdentifier
    self.startDateComponents = startDateComponents
    self.dueDateComponents = dueDateComponents
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.priority = priority
    self.recurrenceRules = recurrenceRules
    self.alarms = alarms
  }

  init(reminder: EKReminder, modifiedAt: Date?) {
    self.init(
      identifier: reminder.calendarItemIdentifier,
      externalIdentifier: reminder.calendarItemExternalIdentifier,
      calendarIdentifier: reminder.calendar.calendarIdentifier,
      title: reminder.title,
      location: reminder.location,
      notes: reminder.notes,
      urlString: reminder.url?.absoluteString,
      creationDate: reminder.creationDate,
      lastModifiedDate: modifiedAt ?? reminder.lastModifiedDate,
      timeZoneIdentifier: reminder.timeZone?.identifier,
      startDateComponents: reminder.startDateComponents.map(ReminderArchiveDateComponentsSnapshot.init),
      dueDateComponents: reminder.dueDateComponents.map(ReminderArchiveDateComponentsSnapshot.init),
      isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate,
      priority: reminder.priority,
      recurrenceRules: (reminder.recurrenceRules ?? []).map(ReminderArchiveRecurrenceRuleSnapshot.init),
      alarms: (reminder.alarms ?? []).map(ReminderArchiveAlarmSnapshot.init)
    )
  }
}

struct ReminderArchiveSnapshot: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let archivedAt: Date
  let sourceVaultRelativePath: String
  let listDetail: ReminderArchiveListDetailSnapshot?
  let list: ReminderListImportSnapshot
  let items: [ReminderItemImportSnapshot]
  let taskDetails: [ReminderArchiveTaskDetailSnapshot]

  init(
    schemaVersion: Int = 1,
    archivedAt: Date,
    sourceVaultRelativePath: String,
    listDetail: ReminderArchiveListDetailSnapshot? = nil,
    list: ReminderListImportSnapshot,
    items: [ReminderItemImportSnapshot],
    taskDetails: [ReminderArchiveTaskDetailSnapshot] = []
  ) {
    self.schemaVersion = schemaVersion
    self.archivedAt = archivedAt
    self.sourceVaultRelativePath = sourceVaultRelativePath
    self.listDetail = listDetail
    self.list = list
    self.items = items
    self.taskDetails = taskDetails
  }
}

@MainActor
struct ReminderArchiveSnapshotBuilder {
  let gateway: ReminderGateway

  func snapshot(
    forListIdentifier listIdentifier: String,
    archivedAt: Date,
    sourceVaultRelativePath: String
  ) async throws -> ReminderArchiveSnapshot? {
    guard let calendar = gateway.calendar(withIdentifier: listIdentifier) else { return nil }
    let importProvider = ReminderGatewayImportSnapshotProvider(gateway: gateway)
    let batch = try await importProvider.fetchBatch(forListIdentifiers: [listIdentifier])
    let list = batch.lists.first ?? importProvider.listSnapshot(for: calendar)
    let reminders = try await gateway.fetchReminders(in: calendar, scope: .all)
    return ReminderArchiveSnapshot(
      archivedAt: archivedAt,
      sourceVaultRelativePath: sourceVaultRelativePath,
      listDetail: ReminderArchiveListDetailSnapshot(calendar: calendar, colorHex: list.colorHex),
      list: list,
      items: batch.itemsByListIdentifier[list.identifier] ?? [],
      taskDetails: reminders.map {
        ReminderArchiveTaskDetailSnapshot(
          reminder: $0,
          modifiedAt: gateway.lastModifiedDate(for: $0)
        )
      }.sorted { lhs, rhs in
        lhs.identifier.localizedStandardCompare(rhs.identifier) == .orderedAscending
      }
    )
  }
}

private extension Array {
  var nilIfEmpty: [Element]? {
    isEmpty ? nil : self
  }
}
