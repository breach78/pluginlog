import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TimelineProjectListWindowSnapshot: Equatable {
  struct Task: Identifiable, Equatable {
    let id: UUID
    let title: String
    let dateText: String?
    let isCompleted: Bool
    let isOverdue: Bool
  }

  let projectID: UUID
  let title: String
  let colorHex: String?
  let tasks: [Task]
}

@MainActor
final class TimelineProjectListWindowPresenter {
  static let shared = TimelineProjectListWindowPresenter()

  private var window: NSWindow?

  private init() {}

  func present(
    snapshot: TimelineProjectListWindowSnapshot,
    onCompleteTask: @escaping (UUID) -> Void,
    onEditTask: @escaping (UUID) -> Void,
    onReorderTasks: @escaping (UUID, [UUID]) -> Void
  ) {
    let content = TimelineProjectListWindowContent(
      snapshot: snapshot,
      onCompleteTask: onCompleteTask,
      onEditTask: onEditTask,
      onReorderTasks: onReorderTasks
    )

    if let window,
      let hostingController = window.contentViewController
        as? NSHostingController<TimelineProjectListWindowContent>
    {
      window.title = snapshot.title
      hostingController.rootView = content
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let hostingController = NSHostingController(rootView: content)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = snapshot.title
    window.contentViewController = hostingController
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName("TimelineProjectListWindow")
    window.center()
    self.window = window

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

private struct TimelineProjectListWindowContent: View {
  let snapshot: TimelineProjectListWindowSnapshot
  let onCompleteTask: (UUID) -> Void
  let onEditTask: (UUID) -> Void
  let onReorderTasks: (UUID, [UUID]) -> Void

  @State private var tasks: [TimelineProjectListWindowSnapshot.Task]
  @State private var draggingTaskID: UUID?
  @State private var dropIndicator: TimelineProjectListTaskDropIndicator?

  init(
    snapshot: TimelineProjectListWindowSnapshot,
    onCompleteTask: @escaping (UUID) -> Void,
    onEditTask: @escaping (UUID) -> Void,
    onReorderTasks: @escaping (UUID, [UUID]) -> Void
  ) {
    self.snapshot = snapshot
    self.onCompleteTask = onCompleteTask
    self.onEditTask = onEditTask
    self.onReorderTasks = onReorderTasks
    _tasks = State(initialValue: snapshot.tasks)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Divider()

      if tasks.isEmpty {
        Text("할일 없음")
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(tasks) { task in
              dropLine(for: task, placement: .before)
              taskRow(task)
                .opacity(draggingTaskID == task.id ? 0.42 : 1)
                .onDrag {
                  draggingTaskID = task.id
                  return TaskDragPayload.itemProvider(for: task.id)
                }
                .onDrop(
                  of: [UTType.text.identifier],
                  delegate: TimelineProjectListTaskDropDelegate(
                    targetTaskID: task.id,
                    draggingTaskID: $draggingTaskID,
                    dropIndicator: $dropIndicator,
                    onPerformDrop: moveTask
                  )
                )
              dropLine(for: task, placement: .after)
              if task.id != tasks.last?.id {
                Divider()
                  .padding(.leading, 32)
              }
            }
          }
          .padding(.vertical, 6)
        }
      }
    }
    .frame(minWidth: 360, minHeight: 420)
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: snapshot) { _, nextSnapshot in
      tasks = nextSnapshot.tasks
      draggingTaskID = nil
      dropIndicator = nil
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      Circle()
        .fill(projectColor)
        .frame(width: 10, height: 10)

      Text(snapshot.title)
        .font(.system(size: 18, weight: .semibold))
        .lineLimit(1)

      Spacer(minLength: 0)

      Text("\(tasks.count)")
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  @ViewBuilder
  private func dropLine(
    for task: TimelineProjectListWindowSnapshot.Task,
    placement: TimelineProjectDropPlacement
  ) -> some View {
    if dropIndicator
      == TimelineProjectListTaskDropIndicator(targetTaskID: task.id, placement: placement)
    {
      Rectangle()
        .fill(projectColor.opacity(0.9))
        .frame(height: 2)
        .padding(.horizontal, 18)
    }
  }

  private func taskRow(_ task: TimelineProjectListWindowSnapshot.Task) -> some View {
    HStack(alignment: .top, spacing: 10) {
      if task.isCompleted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 14))
          .foregroundStyle(projectColor.opacity(0.9))
          .frame(width: 18, height: 22, alignment: .top)
      } else {
        Button {
          onCompleteTask(task.id)
        } label: {
          Image(systemName: task.isOverdue ? "exclamationmark.circle" : "circle")
            .font(.system(size: 14))
            .foregroundStyle(task.isOverdue ? .red : .secondary)
            .frame(width: 18, height: 22, alignment: .top)
        }
        .buttonStyle(.plain)
      }

      Button {
        onEditTask(task.id)
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text(task.title)
            .font(.system(size: 13))
            .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
            .strikethrough(task.isCompleted, color: Color.secondary.opacity(0.55))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let dateText = task.dateText {
            Text(dateText)
              .font(.system(size: 11))
              .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
              .lineLimit(1)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 9)
  }

  private func moveTask(
    draggedID: UUID,
    targetID: UUID,
    placement: TimelineProjectDropPlacement
  ) {
    guard let reorderedIDs = TimelineBoardReadPath.reorderedTaskIDsAfterDrop(
      tasks.map(\.id),
      draggedID: draggedID,
      targetID: targetID,
      placement: placement
    ) else {
      return
    }

    let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    tasks = reorderedIDs.compactMap { tasksByID[$0] }
    onReorderTasks(snapshot.projectID, reorderedIDs)
    draggingTaskID = nil
    dropIndicator = nil
  }

  private var projectColor: Color {
    ColorHexCodec.color(from: snapshot.colorHex) ?? .accentColor
  }
}

private struct TimelineProjectListTaskDropIndicator: Equatable {
  let targetTaskID: UUID
  let placement: TimelineProjectDropPlacement
}

private struct TimelineProjectListTaskDropDelegate: DropDelegate {
  let targetTaskID: UUID
  @Binding var draggingTaskID: UUID?
  @Binding var dropIndicator: TimelineProjectListTaskDropIndicator?
  let onPerformDrop:
    (_ draggedID: UUID, _ targetID: UUID, _ placement: TimelineProjectDropPlacement) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    draggingTaskID != nil && !info.itemProviders(for: [UTType.text.identifier]).isEmpty
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let draggingTaskID, draggingTaskID != targetTaskID else {
      dropIndicator = nil
      return DropProposal(operation: .move)
    }
    let placement: TimelineProjectDropPlacement = info.location.y < 20 ? .before : .after
    let indicator = TimelineProjectListTaskDropIndicator(
      targetTaskID: targetTaskID,
      placement: placement
    )
    if dropIndicator != indicator {
      dropIndicator = indicator
    }
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggingTaskID = nil
      dropIndicator = nil
    }
    guard
      let draggingTaskID,
      draggingTaskID != targetTaskID,
      let placement = dropIndicator?.placement
    else {
      return false
    }
    onPerformDrop(draggingTaskID, targetTaskID, placement)
    return true
  }

  func dropExited(info: DropInfo) {
    if dropIndicator?.targetTaskID == targetTaskID {
      dropIndicator = nil
    }
  }
}
