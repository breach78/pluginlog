import AppKit
import SwiftUI

struct TimelineDetailTaskLocalDragModifier: ViewModifier {
  let isEnabled: Bool
  let taskID: UUID
  let projectIDs: [UUID]
  let rowLayouts: [TimelineRowLayout]
  let dayRange: ClosedRange<Int>
  let dayColumnWidth: CGFloat
  let dateForOffset: (Int) -> Date
  let onMoveTaskToDate: (UUID, UUID, Date) -> Void

  @State private var isDragging = false

  @ViewBuilder
  func body(content: Content) -> some View {
    if isEnabled {
      content
        .scaleEffect(isDragging ? 0.98 : 1)
        .highPriorityGesture(
          DragGesture(minimumDistance: 6, coordinateSpace: .named(timelineDetailRowsCoordinateSpaceName))
            .onChanged { _ in
              if !isDragging {
                isDragging = true
              }
              NSCursor.closedHand.set()
            }
            .onEnded { value in
              defer {
                isDragging = false
                NSCursor.arrow.set()
              }
              guard
                let targetOffset = TimelineBoardReadPath.detailTimelineTargetDayOffset(
                  atX: value.location.x,
                  dayColumnWidth: dayColumnWidth,
                  dayRange: dayRange
                ),
                let targetProjectID = TimelineBoardReadPath.detailTimelineTargetProjectID(
                  atY: value.location.y,
                  projectIDs: projectIDs,
                  rowLayouts: rowLayouts
                )
              else {
                return
              }
              onMoveTaskToDate(taskID, targetProjectID, dateForOffset(targetOffset))
            }
        )
    } else {
      content
    }
  }
}

struct TimelineDetailTaskRowDropModifier: ViewModifier {
  let isEnabled: Bool
  let targetProjectID: UUID
  let dayRange: ClosedRange<Int>
  let dayColumnWidth: CGFloat
  let dateForOffset: (Int) -> Date
  let onMoveTaskToDate: (UUID, UUID, Date) -> Void

  @ViewBuilder
  func body(content: Content) -> some View {
    if isEnabled {
      content.onDrop(
        of: [TaskDragPayload.textTypeIdentifier],
        delegate: TimelineDetailTaskRowDropDelegate(
          targetProjectID: targetProjectID,
          dayRange: dayRange,
          dayColumnWidth: dayColumnWidth,
          dateForOffset: dateForOffset,
          onMoveTaskToDate: onMoveTaskToDate
        )
      )
    } else {
      content
    }
  }
}

private struct TimelineDetailTaskRowDropDelegate: DropDelegate {
  let targetProjectID: UUID
  let dayRange: ClosedRange<Int>
  let dayColumnWidth: CGFloat
  let dateForOffset: (Int) -> Date
  let onMoveTaskToDate: (UUID, UUID, Date) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    targetDate(for: info) != nil
      && !info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).isEmpty
      && info.itemProviders(for: [ProjectDragPayload.projectType.identifier]).isEmpty
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    validateDrop(info: info) ? DropProposal(operation: .move) : DropProposal(operation: .cancel)
  }

  func performDrop(info: DropInfo) -> Bool {
    guard let targetDate = targetDate(for: info),
      let provider = info.itemProviders(for: [TaskDragPayload.textTypeIdentifier]).first
    else {
      return false
    }

    provider.loadItem(forTypeIdentifier: TaskDragPayload.textTypeIdentifier, options: nil) {
      item,
      _ in
      guard let taskID = TaskDragPayload.parseTaskID(from: item) else { return }
      Task { @MainActor in
        onMoveTaskToDate(taskID, targetProjectID, targetDate)
      }
    }
    return true
  }

  private func targetDate(for info: DropInfo) -> Date? {
    guard let targetOffset = TimelineBoardReadPath.detailTimelineTargetDayOffset(
      atX: info.location.x,
      dayColumnWidth: dayColumnWidth,
      dayRange: dayRange
    ) else {
      return nil
    }
    return dateForOffset(targetOffset)
  }
}

final class TimelineDetailDateContextRowView: NSView {
  weak var coordinator: TimelineDetailDateContextRowRegion.Coordinator?

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point),
      NSApp.currentEvent?.type == .rightMouseDown
    else {
      return nil
    }
    return self
  }

  override func rightMouseDown(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    coordinator?.presentMenu(from: self, event: event, location: location)
  }
}

struct TimelineDetailDateContextRowRegion: NSViewRepresentable {
  let projectID: UUID
  let projectTitle: String
  let dayRange: ClosedRange<Int>
  let dayColumnWidth: CGFloat
  let dateForOffset: (Int) -> Date
  let onCreateTask: (String, UUID, Date) -> Void

  @MainActor
  final class Coordinator: NSObject {
    var projectID: UUID?
    var projectTitle = ""
    var dayRange: ClosedRange<Int> = 0...0
    var dayColumnWidth: CGFloat = 0
    var dateForOffset: ((Int) -> Date)?
    var onCreateTask: ((String, UUID, Date) -> Void)?
    weak var hostView: TimelineDetailDateContextRowView?
    var lastLocation: CGPoint = .zero
    var targetDate: Date?
    var popover: NSPopover?

    func presentMenu(from view: TimelineDetailDateContextRowView, event: NSEvent, location: CGPoint) {
      lastLocation = location
      targetDate = resolvedDate(atX: location.x)

      AppKitContextMenuRenderer.shared.present(
        [
          .action("할일 추가", isEnabled: canCreateTask) { [weak self] in
            self?.openQuickAddPopover()
          }
        ],
        with: event,
        for: view
      )
    }

    func openQuickAddPopover() {
      guard let hostView, let projectID, let targetDate else { return }
      popover?.close()

      let popover = NSPopover()
      popover.behavior = .transient
      popover.contentSize = NSSize(width: ScheduleUITokens.Panel.quickAddWidth, height: 134)
      popover.contentViewController = NSHostingController(
        rootView: ScheduleQuickAddPopoverContent(
          projects: [ScheduleQuickAddProjectOption(id: projectID, title: projectTitle)],
          defaultProjectID: projectID,
          onSubmit: { [weak self] title, projectID in
            guard let self else { return }
            self.onCreateTask?(title, projectID, targetDate)
            self.closePopover()
          },
          onCancel: { [weak self] in
            self?.closePopover()
          }
        )
      )
      popover.show(
        relativeTo: CGRect(x: lastLocation.x, y: lastLocation.y, width: 1, height: 1),
        of: hostView,
        preferredEdge: .maxY
      )
      self.popover = popover
    }

    private var canCreateTask: Bool {
      projectID != nil && targetDate != nil
    }

    private func resolvedDate(atX x: CGFloat) -> Date? {
      guard let dateForOffset,
        let offset = TimelineBoardReadPath.detailTimelineTargetDayOffset(
          atX: x,
          dayColumnWidth: dayColumnWidth,
          dayRange: dayRange
        )
      else {
        return nil
      }
      return dateForOffset(offset)
    }

    private func closePopover() {
      popover?.close()
      popover = nil
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> TimelineDetailDateContextRowView {
    let view = TimelineDetailDateContextRowView()
    view.coordinator = context.coordinator
    context.coordinator.hostView = view
    return view
  }

  func updateNSView(_ nsView: TimelineDetailDateContextRowView, context: Context) {
    context.coordinator.hostView = nsView
    context.coordinator.projectID = projectID
    context.coordinator.projectTitle = projectTitle
    context.coordinator.dayRange = dayRange
    context.coordinator.dayColumnWidth = dayColumnWidth
    context.coordinator.dateForOffset = dateForOffset
    context.coordinator.onCreateTask = onCreateTask
  }
}
