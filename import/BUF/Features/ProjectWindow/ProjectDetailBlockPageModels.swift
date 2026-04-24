import Foundation

enum BlockKind: String, Codable, Hashable, Sendable, CaseIterable {
  case project
  case task
  case bullet
  case folder
  case smartCollection
}

extension BlockKind {
  init(workspaceNodeKind: WorkspaceNodeKind) {
    switch workspaceNodeKind {
    case .rootSpace, .project:
      self = .project
    case .folder:
      self = .folder
    case .smartCollection:
      self = .smartCollection
    }
  }
}

enum BlockDisclosureEmphasis: String, Codable, Hashable, Sendable {
  case subdued
  case emphasized
}

enum BlockChildOrderingMode: String, Codable, Hashable, Sendable, CaseIterable {
  case manual
  case dateAscending
  case dateDescending

  init(taskDateSortMode: ProjectDetailTaskDateSortMode) {
    switch taskDateSortMode {
    case .none:
      self = .manual
    case .recent:
      self = .dateAscending
    case .oldest:
      self = .dateDescending
    }
  }

  var taskDateSortMode: ProjectDetailTaskDateSortMode {
    switch self {
    case .manual:
      return .none
    case .dateAscending:
      return .recent
    case .dateDescending:
      return .oldest
    }
  }
}

struct BlockCollapseStateContract: Hashable, Sendable {
  let rootBlockIsExpandedByDefault: Bool
  let nonRootBlocksAreExpandedByDefault: Bool
  let persistsPerBlockDisclosureState: Bool

  static let projectDetailDefault = BlockCollapseStateContract(
    rootBlockIsExpandedByDefault: true,
    nonRootBlocksAreExpandedByDefault: false,
    persistsPerBlockDisclosureState: true
  )

  func resolvedIsExpanded(persistedValue: Bool?, isRootBlock: Bool) -> Bool {
    if isRootBlock {
      return rootBlockIsExpandedByDefault
    }

    if let persistedValue {
      return persistedValue
    }

    return nonRootBlocksAreExpandedByDefault
  }
}

struct BlockScheduleSummary: Hashable, Sendable {
  let displayedDate: Date?
  let startDate: Date?
  let dueDate: Date?
  let hasExplicitTime: Bool
  let scheduledDurationMinutes: Int?

  static let empty = BlockScheduleSummary(
    displayedDate: nil,
    startDate: nil,
    dueDate: nil,
    hasExplicitTime: false,
    scheduledDurationMinutes: nil
  )

  var hasMeaningfulContent: Bool {
    displayedDate != nil || startDate != nil || dueDate != nil || hasExplicitTime
      || scheduledDurationMinutes != nil
  }
}

struct BlockNoteSnapshot: Hashable, Sendable {
  let reminderText: String
  let markdown: String

  static let empty = BlockNoteSnapshot(reminderText: "", markdown: "")

  var hasContent: Bool {
    !reminderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct BlockMetaStripSnapshot: Hashable, Sendable {
  let schedule: BlockScheduleSummary
  let requiredWorkDays: Int?
  let completedWorkUnits: Int?

  var hasMeaningfulContent: Bool {
    schedule.hasMeaningfulContent || requiredWorkDays != nil || completedWorkUnits != nil
  }
}

struct BlockAttachmentPreviewSnapshot: Identifiable, Hashable, Sendable {
  let id: UUID
  let originalFilename: String
  let mimeType: String
  let byteSize: Int64
  let updatedAt: Date
}

struct BlockBodySnapshot: Hashable, Sendable {
  let metaStrip: BlockMetaStripSnapshot
  let note: BlockNoteSnapshot
  let attachments: [BlockAttachmentPreviewSnapshot]

  var hasMeaningfulContent: Bool {
    metaStrip.hasMeaningfulContent || note.hasContent || !attachments.isEmpty
  }
}

struct BlockHeaderSnapshot: Hashable, Sendable {
  let title: String
  let isCompleted: Bool
  let schedule: BlockScheduleSummary
  let attachmentCount: Int
  let childCount: Int
  let hasNote: Bool
  let orderingMode: BlockChildOrderingMode?
  let disclosureEmphasis: BlockDisclosureEmphasis

  init(
    title: String,
    isCompleted: Bool,
    schedule: BlockScheduleSummary,
    attachmentCount: Int,
    childCount: Int,
    hasNote: Bool,
    orderingMode: BlockChildOrderingMode?
  ) {
    self.title = title
    self.isCompleted = isCompleted
    self.schedule = schedule
    self.attachmentCount = max(0, attachmentCount)
    self.childCount = max(0, childCount)
    self.hasNote = hasNote
    self.orderingMode = orderingMode
    self.disclosureEmphasis = BlockHeaderSnapshot.resolveDisclosureEmphasis(
      schedule: schedule,
      attachmentCount: attachmentCount,
      childCount: childCount,
      hasNote: hasNote
    )
  }

  private static func resolveDisclosureEmphasis(
    schedule: BlockScheduleSummary,
    attachmentCount: Int,
    childCount: Int,
    hasNote: Bool
  ) -> BlockDisclosureEmphasis {
    if hasNote || schedule.hasMeaningfulContent || attachmentCount > 0 || childCount > 0
    {
      return .emphasized
    }

    return .subdued
  }
}

struct BlockNodeSnapshot: Identifiable, Hashable, Sendable {
  let id: UUID
  let parentNodeID: UUID?
  let kind: BlockKind
  let isRoot: Bool
  let colorHex: String?
  let iconName: String?
  let header: BlockHeaderSnapshot
  let body: BlockBodySnapshot?
  let children: [BlockNodeSnapshot]
}

struct BlockPageBreadcrumbItem: Identifiable, Hashable, Sendable {
  let id: UUID
  let title: String
}

struct BlockPageSnapshot: Hashable, Sendable {
  let pageID: UUID
  let stageSourceProjectID: UUID
  let title: String
  let pageIconName: String?
  let pageColorHex: String?
  let breadcrumb: [BlockPageBreadcrumbItem]
  let rootBlock: BlockNodeSnapshot
  let orderingMode: BlockChildOrderingMode
  let includeArchived: Bool
  let includeCompleted: Bool
  let computedAt: Date
}
