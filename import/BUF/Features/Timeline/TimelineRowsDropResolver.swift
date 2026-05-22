import AppKit
import SwiftUI

@MainActor
final class TimelineDetailRowsDropResolver: ObservableObject {
  weak var coordinateView: NSView?
  private var projectIDs: [UUID] = []
  private var rowLayouts: [TimelineRowLayout] = []
  private var dayRange: ClosedRange<Int> = 0...0
  private var dayColumnWidth: CGFloat = 1
  private var dateForOffset: (Int) -> Date = { _ in .now }

  func configure(
    projectIDs: [UUID],
    rowLayouts: [TimelineRowLayout],
    dayRange: ClosedRange<Int>,
    dayColumnWidth: CGFloat,
    dateForOffset: @escaping (Int) -> Date
  ) {
    self.projectIDs = projectIDs
    self.rowLayouts = rowLayouts
    self.dayRange = dayRange
    self.dayColumnWidth = dayColumnWidth
    self.dateForOffset = dateForOffset
  }

  func target(forScreenPoint screenPoint: NSPoint) -> (projectID: UUID, date: Date)? {
    guard let coordinateView, let window = coordinateView.window else { return nil }
    let windowPoint = window.convertPoint(fromScreen: screenPoint)
    let localPoint = coordinateView.convert(windowPoint, from: nil)
    guard coordinateView.bounds.contains(localPoint) else { return nil }
    return target(forLocalPoint: localPoint)
  }

  func target(forLocalPoint localPoint: CGPoint) -> (projectID: UUID, date: Date)? {
    guard
      let targetOffset = TimelineBoardReadPath.detailTimelineTargetDayOffset(
        atX: localPoint.x,
        dayColumnWidth: dayColumnWidth,
        dayRange: dayRange
      ),
      let projectID = TimelineBoardReadPath.detailTimelineTargetProjectID(
        atY: localPoint.y,
        projectIDs: projectIDs,
        rowLayouts: rowLayouts
      )
    else {
      return nil
    }

    return (projectID, dateForOffset(targetOffset))
  }
}

struct TimelineDetailRowsDropResolverHost: NSViewRepresentable {
  @ObservedObject var resolver: TimelineDetailRowsDropResolver
  let projectIDs: [UUID]
  let rowLayouts: [TimelineRowLayout]
  let dayRange: ClosedRange<Int>
  let dayColumnWidth: CGFloat
  let dateForOffset: (Int) -> Date

  func makeNSView(context: Context) -> TimelineDetailRowsDropResolverView {
    let view = TimelineDetailRowsDropResolverView()
    view.resolver = resolver
    resolver.coordinateView = view
    return view
  }

  func updateNSView(_ nsView: TimelineDetailRowsDropResolverView, context: Context) {
    nsView.resolver = resolver
    resolver.coordinateView = nsView
    resolver.configure(
      projectIDs: projectIDs,
      rowLayouts: rowLayouts,
      dayRange: dayRange,
      dayColumnWidth: dayColumnWidth,
      dateForOffset: dateForOffset
    )
  }

  static func dismantleNSView(
    _ nsView: TimelineDetailRowsDropResolverView,
    coordinator: Void
  ) {
    resolverForDismantle(nsView)?.coordinateView = nil
  }

  private static func resolverForDismantle(_ nsView: TimelineDetailRowsDropResolverView)
    -> TimelineDetailRowsDropResolver?
  {
    nsView.resolver
  }
}

final class TimelineDetailRowsDropResolverView: NSView {
  weak var resolver: TimelineDetailRowsDropResolver?

  override var isFlipped: Bool { true }
}

struct TimelineProjectListPopoverTaskDragModifier: ViewModifier {
  let taskID: UUID
  @ObservedObject var resolver: TimelineDetailRowsDropResolver
  let onMoveTaskToDate: (UUID, UUID, Date) -> Void
  let onCancel: () -> Void

  @State private var isDragging = false

  func body(content: Content) -> some View {
    content
      .scaleEffect(isDragging ? 0.98 : 1)
      .highPriorityGesture(
        DragGesture(minimumDistance: 6)
          .onChanged { _ in
            if !isDragging {
              isDragging = true
            }
            NSCursor.closedHand.set()
          }
          .onEnded { _ in
            defer {
              isDragging = false
              NSCursor.arrow.set()
            }
            guard let target = resolver.target(forScreenPoint: NSEvent.mouseLocation) else {
              onCancel()
              return
            }
            onMoveTaskToDate(taskID, target.projectID, target.date)
          }
      )
  }
}
