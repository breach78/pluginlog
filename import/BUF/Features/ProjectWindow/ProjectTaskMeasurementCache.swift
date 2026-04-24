import CoreGraphics
import Foundation

@MainActor
final class ProjectTaskMeasurementCache {
  private struct Entry {
    var rowMeasurementSignature: Int
    var detailMeasurementSignature: Int
    var rowHeight: CGFloat?
    var expandedDetailHeight: CGFloat?
  }

  private var widthBucket: Int = 0
  private var entries: [UUID: Entry] = [:]

  private let defaultRowHeight: CGFloat = 42
  private let defaultCollapsedDetailHeight: CGFloat = 1
  private let defaultExpandedDetailHeight: CGFloat = 132

  func updateWidth(_ width: CGFloat) {
    let bucket = Int(max(0, floor(width)))
    guard widthBucket != bucket else { return }
    widthBucket = bucket
    entries.removeAll()
  }

  func prepare(taskID: UUID, rowMeasurementSignature: Int, detailMeasurementSignature: Int) {
    guard let existing = entries[taskID] else {
      entries[taskID] = Entry(
        rowMeasurementSignature: rowMeasurementSignature,
        detailMeasurementSignature: detailMeasurementSignature,
        rowHeight: nil,
        expandedDetailHeight: nil
      )
      return
    }

    var updated = existing
    if existing.rowMeasurementSignature != rowMeasurementSignature {
      updated.rowMeasurementSignature = rowMeasurementSignature
      updated.rowHeight = nil
    }
    if existing.detailMeasurementSignature != detailMeasurementSignature {
      updated.detailMeasurementSignature = detailMeasurementSignature
      updated.expandedDetailHeight = nil
    }
    entries[taskID] = updated
  }

  func removeMissing(keeping taskIDs: Set<UUID>) {
    entries = entries.filter { taskIDs.contains($0.key) }
  }

  func estimatedHeights(for taskID: UUID, detailIsVisible: Bool) -> (rowHeight: CGFloat, detailHeight: CGFloat) {
    let entry = entries[taskID]
    let rowHeight = max(defaultRowHeight, ceil(entry?.rowHeight ?? defaultRowHeight))
    let detailHeight: CGFloat
    if detailIsVisible {
      detailHeight = max(
        defaultCollapsedDetailHeight,
        ceil(entry?.expandedDetailHeight ?? defaultExpandedDetailHeight)
      )
    } else {
      detailHeight = defaultCollapsedDetailHeight
    }
    return (rowHeight, detailHeight)
  }

  func store(rowHeight: CGFloat, expandedDetailHeight: CGFloat, for taskID: UUID) {
    guard var entry = entries[taskID] else { return }
    entry.rowHeight = max(defaultRowHeight, ceil(rowHeight))
    entry.expandedDetailHeight = max(
      defaultCollapsedDetailHeight,
      ceil(expandedDetailHeight)
    )
    entries[taskID] = entry
  }
}
