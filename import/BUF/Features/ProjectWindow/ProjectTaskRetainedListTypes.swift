import SwiftUI

struct ProjectTaskRetainedListItem: Identifiable {
  let id: UUID
  let rowRenderSignature: Int
  let rowMeasurementSignature: Int
  let rowContent: AnyView
  let rowMeasurementContent: AnyView
  let detailRenderSignature: Int
  let detailMeasurementSignature: Int
  let detailContent: AnyView
  let detailMeasurementContent: AnyView
  let readOnlyDetailSnapshot: ProjectTaskReadOnlyDetailSnapshot?
  let detailIsVisible: Bool
  let fixedRowHeight: CGFloat?
  let fixedDetailHeight: CGFloat?
}

struct ProjectTaskReadOnlyAttachmentSnapshot: Equatable {
  let filename: String
  let byteSize: Int64?
  let availability: NoteDisplayAttachmentAvailability
  let isLegacy: Bool
}

struct ProjectTaskReadOnlyDetailSnapshot {
  let textBlocks: [String]
  let attachments: [ProjectTaskReadOnlyAttachmentSnapshot]
  let placeholder: String
  let noteRegionHeight: CGFloat
  let fontSize: CGFloat
  let lineSpacing: CGFloat
  let verticalContentOffset: CGFloat
  let onActivate: () -> Void
}

@MainActor
final class ProjectTaskRetainedListFrameStore {
  var rowFrames: [UUID: CGRect] = [:]
  var liveWindowTaskIDs: Set<UUID> = []
}

struct ProjectTaskRetainedListLayoutFootprint: Equatable {
  struct Entry: Equatable {
    let rowMeasurementSignature: Int
    let detailMeasurementSignature: Int
    let detailIsVisible: Bool
    let fixedRowHeight: Int?
    let fixedDetailHeight: Int?
  }

  let rowOrder: [UUID]
  let availableWidth: CGFloat
  let entries: [UUID: Entry]
}

@MainActor
protocol ProjectTaskRetainedListRowLayoutDelegate: AnyObject {
  func projectTaskRetainedListRowNeedsRelayout(_ taskID: UUID)
}
