import CoreGraphics
import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum TaskFieldFocus: Hashable {
  case title(UUID)
  case date(UUID)
}

enum ExternalEditorFocus: Equatable {
  case projectNote
  case taskReminderNote(UUID)
}

struct TaskEscapeCancelCandidate {
  let taskID: UUID
  let allowsDeletingExistingBlankTask: Bool
}

struct TaskReminderNoteFocusRequest: Equatable {
  let taskID: UUID
  let id: Int
}

struct TaskInlineDetailReservationState: Equatable {
  let taskID: UUID
  let height: CGFloat
}

struct TaskDateCellPresentation: Equatable {
  let dateText: String?
  let usesMonthDayOnly: Bool
  let requiredWorkDays: Int
  let isRecurring: Bool
  let hasExplicitTime: Bool
  let isCompleted: Bool
  let dateItemSpacing: CGFloat
  let dateColumnWidth: CGFloat
  let showsSideMetadata: Bool
  let inlineMinHeight: CGFloat
  let horizontalInset: CGFloat
  let rowBaseHeight: CGFloat
}

enum NoteEditorViewportPinning {
  static func constrainedOrigin(_ proposedOrigin: CGPoint) -> CGPoint {
    CGPoint(x: proposedOrigin.x, y: 0)
  }
}

struct TaskAttachmentAggregateItem: Identifiable {
  let attachmentID: UUID
  let relativePath: String
  let originalFilename: String
  let byteSize: Int64
  let taskID: UUID
  let taskTitle: String

  var id: UUID { attachmentID }
}

enum NoteSnapshotVariant: String {
  case rich
  case cheap
}

enum TaskDateSortMode: String {
  case none
  case recent
  case oldest

  var symbolName: String? {
    switch self {
    case .none:
      return nil
    case .recent:
      return "arrow.down"
    case .oldest:
      return "arrow.up"
    }
  }

  func next() -> TaskDateSortMode {
    switch self {
    case .none:
      return .recent
    case .recent:
      return .oldest
    case .oldest:
      return .none
    }
  }
}

struct PendingTaskMoveSelection: Identifiable {
  let taskID: UUID
  let sourceProjectID: UUID
  let taskTitle: String

  var id: UUID { taskID }
}

struct ProjectDetailProjectMenuTarget: Identifiable, Equatable {
  let id: UUID
  let title: String
}

enum ProjectDatePickerTarget: Hashable {
  case start
  case deadline
}

enum ProjectHighlightSection: Equatable {
  case header
  case notes
  case attachments
  case taskDetail(UUID)
}

enum TaskExpandedSurfacePosition {
  case single
  case top
  case middle
  case bottom

  var cornerRadii: RectangleCornerRadii {
    let radius = ProjectDetailSurfaceMetrics.subtleCornerRadius
    switch self {
    case .single:
      return .init(
        topLeading: radius,
        bottomLeading: radius,
        bottomTrailing: radius,
        topTrailing: radius
      )
    case .top:
      return .init(
        topLeading: radius,
        bottomLeading: 0,
        bottomTrailing: 0,
        topTrailing: radius
      )
    case .middle:
      return .init(
        topLeading: 0,
        bottomLeading: 0,
        bottomTrailing: 0,
        topTrailing: 0
      )
    case .bottom:
      return .init(
        topLeading: 0,
        bottomLeading: radius,
        bottomTrailing: radius,
        topTrailing: 0
      )
    }
  }
}

struct AttachmentOwnerCacheKey: Hashable {
  let ownerTypeRaw: String
  let ownerID: UUID
}

extension UTType {
  static let projectDetailAttachmentReference = UTType(
    exportedAs: "com.brainunfog.project-detail-attachment-reference"
  )
}

struct ProjectDetailAttachmentDragPayload: Codable, Hashable, Sendable {
  let attachmentID: UUID
  let sourceOwnerTypeRaw: String
  let sourceOwnerID: UUID
  let sourceBlockID: UUID

  var sourceOwner: AttachmentOwner {
    let ownerType = AttachmentOwnerType(rawValue: sourceOwnerTypeRaw) ?? .task
    switch ownerType {
    case .project:
      return .project(sourceOwnerID)
    case .task:
      return .task(sourceOwnerID)
    }
  }
}

struct AttachmentDragExport: Identifiable, Transferable {
  let id: UUID
  let sourceURL: URL
  let displayFilename: String

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .item) { export in
      SentTransferredFile(try export.materializedURL())
    }
    .suggestedFileName { export in
      export.displayFilename
    }

    ProxyRepresentation(exporting: { export in
      try export.materializedURL()
    })
  }

  private func materializedURL() throws -> URL {
    try ApplePlatformDragBridge.shared.materializeFileExport(
      sourceURL: sourceURL,
      displayFilename: displayFilename,
      exportID: id
    )
  }
}

struct TaskOrderSnapshot {
  let projectID: UUID
  let orderedTaskIDs: [UUID]
  let sequenceAssignments: [UUID: String]
}

final class ProjectTitleLiveTextCache {
  var text: String?

  func clear() {
    text = nil
  }
}

final class TaskDatePresentationCache {
  private struct Entry {
    let signature: Int
    let presentation: TaskDateCellPresentation
  }

  private var entries: [UUID: Entry] = [:]

  func presentation(
    for taskID: UUID,
    signature: Int,
    build: () -> TaskDateCellPresentation
  ) -> TaskDateCellPresentation {
    if let entry = entries[taskID], entry.signature == signature {
      return entry.presentation
    }

    let presentation = build()
    entries[taskID] = Entry(signature: signature, presentation: presentation)
    return presentation
  }

  func invalidate(taskID: UUID? = nil) {
    if let taskID {
      entries.removeValue(forKey: taskID)
    } else {
      entries.removeAll()
    }
  }
}

final class RetainedTaskListItemCache {
  private struct Entry {
    let signature: Int
    let item: ProjectTaskRetainedListItem
  }

  private var entries: [UUID: Entry] = [:]

  func cachedItem(for taskID: UUID) -> ProjectTaskRetainedListItem? {
    entries[taskID]?.item
  }

  func item(
    for taskID: UUID,
    signature: Int,
    build: () -> ProjectTaskRetainedListItem
  ) -> ProjectTaskRetainedListItem {
    if let entry = entries[taskID], entry.signature == signature {
      return entry.item
    }

    let item = build()
    entries[taskID] = Entry(signature: signature, item: item)
    return item
  }

  func removeMissing(keeping taskIDs: Set<UUID>) {
    entries = entries.filter { taskIDs.contains($0.key) }
  }

  func invalidate(taskID: UUID? = nil) {
    if let taskID {
      entries.removeValue(forKey: taskID)
    } else {
      entries.removeAll()
    }
  }
}

enum ProjectDetailSurfaceMetrics {
  static let subtleCornerRadius: CGFloat = 4
}

struct RetainedTaskListOrderChangeHint: Equatable {
  let projectID: UUID
  let rowOrder: [UUID]
  let changedRange: Range<Int>
}

struct TaskRowBoundsPreferenceKey: PreferenceKey {
  static let defaultValue: [UUID: Anchor<CGRect>] = [:]

  static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

struct RootTaskGapShift: Equatable {
  let draggedTaskID: UUID
  let sourceIndex: Int
  let destinationIndex: Int
  let height: CGFloat
  let reorderedTaskIDs: [UUID]
}

struct AttachmentInteractionFeedback: Identifiable, Equatable {
  let id: Int
  let message: String
  let showsUndo: Bool
}
