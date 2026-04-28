import Foundation

let projectDetailEmbeddedFixedWidth: CGFloat = 0

enum ProjectListSortPresentationContext {
  case sidebar
  case timeline
}

enum ProjectListSortMode: String, CaseIterable, Hashable {
  case manual
  case recent
  case title
  case priority
  case bucketGrouped

  var allowsInteractiveReordering: Bool { self == .manual || self == .priority }

  var indicatorIconName: String? {
    switch self {
    case .manual: "line.3.horizontal"
    case .recent: "clock"
    case .title: "textformat"
    case .priority, .bucketGrouped: "square.grid.2x2"
    }
  }

  var nextSidebar: ProjectListSortMode {
    switch self {
    case .manual: .recent
    case .recent: .title
    case .title: .manual
    case .priority, .bucketGrouped: .manual
    }
  }

  var nextTimeline: ProjectListSortMode {
    switch self {
    case .manual: .recent
    case .recent: .title
    case .title: .priority
    case .priority, .bucketGrouped: .manual
    }
  }

  func helpText(in context: ProjectListSortPresentationContext) -> String {
    switch (context, self) {
    case (.sidebar, .manual): "수동 순서"
    case (.sidebar, .recent): "최근 업데이트 순서"
    case (.sidebar, .title): "제목 순서"
    case (.sidebar, .priority), (.sidebar, .bucketGrouped): "진행 단계 순서"
    case (.timeline, .priority), (.timeline, .bucketGrouped): "진행 단계 순서"
    case (.timeline, .manual): "수동 순서"
    case (.timeline, .recent): "최근 업데이트 순서"
    case (.timeline, .title): "제목 순서"
    }
  }

  static func resolved(storedRawValue: String?, primaryKey: String) -> ProjectListSortMode {
    _ = primaryKey
    guard let storedRawValue, let value = ProjectListSortMode(rawValue: storedRawValue) else {
      return .manual
    }
    return value == .bucketGrouped ? .priority : value
  }

  static func resolvedTimeline(storedRawValue: String?) -> ProjectListSortMode {
    guard let storedRawValue, let value = ProjectListSortMode(rawValue: storedRawValue) else {
      return .manual
    }
    switch value {
    case .manual:
      return .manual
    case .bucketGrouped:
      return .priority
    case .recent, .title, .priority:
      return value
    }
  }
}

enum ProjectOrdering {
  static func ordered(
    _ descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode
  ) -> [WorkspaceProjectDescriptor] {
    switch mode {
    case .manual:
      return descriptors.sorted(by: manualSort)
    case .recent:
      return descriptors.sorted {
        if $0.latestActivityAt != $1.latestActivityAt { return $0.latestActivityAt > $1.latestActivityAt }
        return titleSort($0, $1)
      }
    case .title:
      return descriptors.sorted(by: titleSort)
    case .priority, .bucketGrouped:
      return orderedForTimeline(descriptors, mode: .priority)
    }
  }

  static func orderedForTimeline(
    _ descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode
  ) -> [WorkspaceProjectDescriptor] {
    guard mode == .priority || mode == .bucketGrouped else {
      return ordered(descriptors, mode: mode)
    }
    return descriptors.sorted {
      if $0.stage.rawValue != $1.stage.rawValue { return $0.stage.rawValue < $1.stage.rawValue }
      return manualSort($0, $1)
    }
  }

  private static func manualSort(_ lhs: WorkspaceProjectDescriptor, _ rhs: WorkspaceProjectDescriptor) -> Bool {
    let lhsOrder = lhs.workspaceSortKey ?? Int64(lhs.boardOrder ?? Int.max)
    let rhsOrder = rhs.workspaceSortKey ?? Int64(rhs.boardOrder ?? Int.max)
    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
    return titleSort(lhs, rhs)
  }

  private static func titleSort(_ lhs: WorkspaceProjectDescriptor, _ rhs: WorkspaceProjectDescriptor) -> Bool {
    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
  }
}

enum WorkspaceSearchEntityKind: Hashable {
  case project
  case task
}

enum WorkspaceSearchMatchKind: Hashable {
  case projectTitle
  case taskTitle
}

struct WorkspaceSearchDisposition: Hashable {
  let sectionRank: Int
  let sectionHeaderTitle: String?
  let statusLabel: String?
  let isDimmed: Bool
}

struct WorkspaceSearchResult: Identifiable, Equatable {
  let id: String
  let entityKind: WorkspaceSearchEntityKind
  let matchKind: WorkspaceSearchMatchKind
  let title: String
  let subtitle: String
  let preview: String
  let navigationTarget: WorkspaceNavigationTarget
  let disposition: WorkspaceSearchDisposition
}

enum WorkspaceSearchService {
  static func sorted(results: [WorkspaceSearchResult]) -> [WorkspaceSearchResult] {
    results.sorted {
      if $0.disposition.sectionRank != $1.disposition.sectionRank {
        return $0.disposition.sectionRank < $1.disposition.sectionRank
      }
      return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  static func projectResults(
    from items: [WorkspaceSidebarProjectItem],
    rawQuery: String
  ) -> [WorkspaceSearchResult] {
    let token = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return [] }
    return items.compactMap { item in
      guard let projectID = item.projectID,
        matches(item.title, token: token)
      else {
        return nil
      }
      return WorkspaceSearchResult(
        id: "project-\(projectID.uuidString)",
        entityKind: .project,
        matchKind: .projectTitle,
        title: item.title,
        subtitle: item.breadcrumbText.isEmpty ? "Project note" : item.breadcrumbText,
        preview: "",
        navigationTarget: .projectTop(projectID: projectID),
        disposition: WorkspaceSearchDisposition(
          sectionRank: 0,
          sectionHeaderTitle: "Projects",
          statusLabel: nil,
          isDimmed: false
        )
      )
    }
  }

  static func taskResults(
    projectSnapshots: [UUID: WorkspaceProjectRuntimeRecord],
    scheduleEntriesByProjectID: [UUID: [ScheduleSliceEntry]],
    rawQuery: String
  ) -> [WorkspaceSearchResult] {
    let token = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return [] }

    return scheduleEntriesByProjectID.flatMap { element -> [WorkspaceSearchResult] in
      let (projectID, entries) = element
      guard let project = projectSnapshots[projectID], !project.isArchived else { return [] }

      return entries.compactMap { entry in
        guard !entry.isArchived, matches(entry.title, token: token) else { return nil }

        return WorkspaceSearchResult(
          id: "task-\(projectID.uuidString)-\(entry.taskID.uuidString)",
          entityKind: .task,
          matchKind: .taskTitle,
          title: entry.title,
          subtitle: project.title,
          preview: entry.reminderNoteText,
          navigationTarget: .taskRow(projectID: projectID, taskID: entry.taskID),
          disposition: WorkspaceSearchDisposition(
            sectionRank: entry.isCompleted ? 2 : 1,
            sectionHeaderTitle: entry.isCompleted ? "Completed tasks" : "Tasks",
            statusLabel: entry.isCompleted ? "완료" : nil,
            isDimmed: entry.isCompleted
          )
        )
      }
    }
  }

  private static func matches(_ source: String, token: String) -> Bool {
    source.range(
      of: token,
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .autoupdatingCurrent
    ) != nil
  }
}

enum ReminderProjectionIdentity {
  static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  static func projectID(for reminderListExternalIdentifier: String) -> UUID {
    RetainedProjectionBuilder.derivedProjectID(for: reminderListExternalIdentifier)
  }

  static func taskID(for reminderExternalIdentifier: String) -> UUID {
    stableUUID(namespace: "reminder-task", value: reminderExternalIdentifier)
  }

  static func noteNodeID(
    parentReminderExternalIdentifier: String?,
    path: [Int],
    text: String
  ) -> UUID {
    stableUUID(
      namespace: normalized(parentReminderExternalIdentifier) ?? "root",
      value: path.map(String.init).joined(separator: ".") + "|" + text
    )
  }

  private static func stableUUID(namespace: String, value: String) -> UUID {
    let source = Array("\(namespace)|\(value)".utf8)
    let a = fnv1a64(seed: 0xcbf2_9ce4_8422_2325, source)
    let b = fnv1a64(seed: 0x8422_2325_cbf2_9ce4, source.reversed())
    var bytes: [UInt8] = []
    for number in [a, b] {
      bytes.append(contentsOf: stride(from: 56, through: 0, by: -8).map {
        UInt8((number >> UInt64($0)) & 0xff)
      })
    }
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }

  private static func fnv1a64<S: Sequence>(seed: UInt64, _ bytes: S) -> UInt64 where S.Element == UInt8 {
    bytes.reduce(seed) { hash, byte in
      (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
  }
}

struct ReminderProjectRootStructureRecord: Equatable, Codable {
  var rootNodes: [String] = []
}

enum ReminderTaskDateCanonicalizer {
  static func unifiedDate(dueDate: Date?, startDate: Date?, displayedDate: Date?) -> Date? {
    dueDate ?? startDate ?? displayedDate
  }
}

struct CalendarEventFieldsWrite {
  enum Mutation {
    case timing(ScheduleInteractionPreview, ScheduleCalendarRecurringEditScope)
    case fields(ScheduleCalendarEventEditFields, ScheduleCalendarRecurringEditScope)
  }

  let event: ScheduleCalendarEvent
  let mutation: Mutation
}
