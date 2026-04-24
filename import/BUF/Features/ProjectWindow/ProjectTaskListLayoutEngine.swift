import CoreGraphics
import Foundation

struct ProjectTaskRetainedListLayoutResult {
  let shellFrames: [UUID: CGRect]
  let rowFrames: [UUID: CGRect]
  let contentHeight: CGFloat
}

struct ProjectTaskRetainedListLayoutEngine {
  func makeLayout(
    rowOrder: [UUID],
    availableWidth: CGFloat,
    rowHeights: [UUID: CGFloat],
    detailHeights: [UUID: CGFloat],
    previousLayout: ProjectTaskRetainedListLayoutResult? = nil,
    reusableRange: Range<Int>? = nil
  ) -> ProjectTaskRetainedListLayoutResult {
    let width = max(0, floor(availableWidth))
    guard width > 1 else {
      return ProjectTaskRetainedListLayoutResult(
        shellFrames: [:],
        rowFrames: [:],
        contentHeight: 0
      )
    }

    var nextMinY: CGFloat = 0
    var shellFrames: [UUID: CGRect] = [:]
    var rowFrames: [UUID: CGRect] = [:]
    let normalizedReusableRange =
      reusableRange.map { max(0, $0.lowerBound)..<min(rowOrder.count, $0.upperBound) }

    var reusablePrefixCount = 0
    if let previousLayout, let normalizedReusableRange {
      for index in 0..<normalizedReusableRange.lowerBound {
        let taskID = rowOrder[index]
        guard
          let shellFrame = previousLayout.shellFrames[taskID],
          let rowFrame = previousLayout.rowFrames[taskID]
        else {
          reusablePrefixCount = 0
          break
        }
        shellFrames[taskID] = shellFrame
        rowFrames[taskID] = rowFrame
        nextMinY = shellFrame.maxY
        reusablePrefixCount = index + 1
      }
    }

    let recomputeUpperBound = normalizedReusableRange?.upperBound ?? rowOrder.count

    for taskID in rowOrder.dropFirst(reusablePrefixCount).prefix(recomputeUpperBound - reusablePrefixCount) {
      let rowHeight = max(1, ceil(rowHeights[taskID] ?? 1))
      let detailHeight = max(0, ceil(detailHeights[taskID] ?? 0))
      shellFrames[taskID] = CGRect(x: 0, y: nextMinY, width: width, height: rowHeight + detailHeight)
      rowFrames[taskID] = CGRect(x: 0, y: nextMinY, width: width, height: rowHeight)
      nextMinY += rowHeight + detailHeight
    }

    if let previousLayout, let normalizedReusableRange {
      let suffixStart = normalizedReusableRange.upperBound
      if suffixStart < rowOrder.count {
        let suffixAnchorTaskID = rowOrder[suffixStart]
        if let anchorFrame = previousLayout.shellFrames[suffixAnchorTaskID],
          abs(anchorFrame.minY - nextMinY) <= 0.5
        {
          for taskID in rowOrder.dropFirst(suffixStart) {
            guard
              let shellFrame = previousLayout.shellFrames[taskID],
              let rowFrame = previousLayout.rowFrames[taskID]
            else { break }
            shellFrames[taskID] = shellFrame
            rowFrames[taskID] = rowFrame
            nextMinY = shellFrame.maxY
          }
        } else if let anchorFrame = previousLayout.shellFrames[suffixAnchorTaskID] {
          let deltaY = nextMinY - anchorFrame.minY
          var translatedSuffix = true
          var translatedMaxY = nextMinY

          for taskID in rowOrder.dropFirst(suffixStart) {
            guard
              let shellFrame = previousLayout.shellFrames[taskID],
              let rowFrame = previousLayout.rowFrames[taskID]
            else {
              translatedSuffix = false
              break
            }

            let translatedShellFrame = shellFrame.offsetBy(dx: 0, dy: deltaY)
            let translatedRowFrame = rowFrame.offsetBy(dx: 0, dy: deltaY)
            shellFrames[taskID] = translatedShellFrame
            rowFrames[taskID] = translatedRowFrame
            translatedMaxY = translatedShellFrame.maxY
          }

          if translatedSuffix {
            nextMinY = translatedMaxY
          } else {
            for taskID in rowOrder.dropFirst(suffixStart) {
              let rowHeight = max(1, ceil(rowHeights[taskID] ?? 1))
              let detailHeight = max(0, ceil(detailHeights[taskID] ?? 0))
              shellFrames[taskID] = CGRect(
                x: 0, y: nextMinY, width: width, height: rowHeight + detailHeight)
              rowFrames[taskID] = CGRect(x: 0, y: nextMinY, width: width, height: rowHeight)
              nextMinY += rowHeight + detailHeight
            }
          }
        } else {
          for taskID in rowOrder.dropFirst(suffixStart) {
            let rowHeight = max(1, ceil(rowHeights[taskID] ?? 1))
            let detailHeight = max(0, ceil(detailHeights[taskID] ?? 0))
            shellFrames[taskID] = CGRect(
              x: 0, y: nextMinY, width: width, height: rowHeight + detailHeight)
            rowFrames[taskID] = CGRect(x: 0, y: nextMinY, width: width, height: rowHeight)
            nextMinY += rowHeight + detailHeight
          }
        }
      }
    }

    return ProjectTaskRetainedListLayoutResult(
      shellFrames: shellFrames,
      rowFrames: rowFrames,
      contentHeight: max(0, ceil(nextMinY))
    )
  }
}
