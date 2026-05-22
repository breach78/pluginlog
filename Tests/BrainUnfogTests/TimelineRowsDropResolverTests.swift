import CoreGraphics
import XCTest
@testable import BrainUnfog

@MainActor
final class TimelineRowsDropResolverTests: XCTestCase {
  func testResolverMapsLocalPointToTimelineProjectAndDate() {
    let firstProjectID = UUID()
    let secondProjectID = UUID()
    let baseDate = Date(timeIntervalSince1970: 0)
    let metrics = TimelineRowMetrics(height: 40, spacing: 8, contentInsetY: 4)
    let resolver = TimelineDetailRowsDropResolver()

    resolver.configure(
      projectIDs: [firstProjectID, secondProjectID],
      rowLayouts: [
        TimelineRowLayout(topY: 0, metrics: metrics),
        TimelineRowLayout(topY: metrics.stride, metrics: metrics),
      ],
      dayRange: -1...3,
      dayColumnWidth: 50,
      dateForOffset: { offset in
        baseDate.addingTimeInterval(Double(offset) * 86_400)
      }
    )

    let target = resolver.target(forLocalPoint: CGPoint(x: 125, y: 55))

    XCTAssertEqual(target?.projectID, secondProjectID)
    XCTAssertEqual(target?.date, baseDate.addingTimeInterval(86_400))
  }

  func testResolverReturnsNilOutsideKnownRows() {
    let projectID = UUID()
    let metrics = TimelineRowMetrics(height: 40, spacing: 8, contentInsetY: 4)
    let resolver = TimelineDetailRowsDropResolver()

    resolver.configure(
      projectIDs: [projectID],
      rowLayouts: [
        TimelineRowLayout(topY: 0, metrics: metrics)
      ],
      dayRange: -1...3,
      dayColumnWidth: 50,
      dateForOffset: { _ in Date(timeIntervalSince1970: 0) }
    )

    XCTAssertNil(resolver.target(forLocalPoint: CGPoint(x: 25, y: 60)))
  }
}
