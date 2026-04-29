import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension NSUserInterfaceItemIdentifier {
  static let timelineProjectListWindow = NSUserInterfaceItemIdentifier(
    "timelineProjectListWindow")
}

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

  private var windowRecords: [WindowRecord] = []

  private init() {}

  var presentedProjectIDs: [UUID] {
    pruneClosedWindows()
    return windowRecords.compactMap { record in
      guard Self.isLiveWindow(record.window) else { return nil }
      return Self.projectID(for: record.window)
    }
  }

  static func configureWindowLevel(_ window: NSWindow) {
    window.level = .normal
  }

  static func attachAboveApplicationWindow(
    _ window: NSWindow,
    in application: NSApplication = .shared
  ) {
    guard let parentWindow = preferredParentWindow(for: window, in: application) else {
      window.parent?.removeChildWindow(window)
      return
    }

    guard window.parent !== parentWindow else { return }
    window.parent?.removeChildWindow(window)
    parentWindow.addChildWindow(window, ordered: .above)
  }

  static func preferredParentWindow(
    for window: NSWindow,
    in application: NSApplication = .shared
  ) -> NSWindow? {
    if let keyWindow = application.keyWindow,
      keyWindow !== window,
      keyWindow.isVisible,
      keyWindow.identifier != .timelineProjectListWindow
    {
      return keyWindow
    }

    if let mainWindow = application.mainWindow,
      mainWindow !== window,
      mainWindow.isVisible,
      mainWindow.identifier != .timelineProjectListWindow
    {
      return mainWindow
    }

    return application.orderedWindows.first { candidate in
      candidate !== window
        && candidate.isVisible
        && candidate.level == .normal
        && candidate.parent !== window
        && candidate.identifier != .timelineProjectListWindow
    }
  }

  func present(
    snapshot: TimelineProjectListWindowSnapshot,
    onCompleteTask: @escaping (UUID) async -> Bool,
    onEditTask: @escaping (UUID) -> Void,
    onReorderTasks: @escaping (UUID, [UUID]) -> Void,
    onCreateTask: @escaping (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onRenameTask: @escaping (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onDeleteTask: @escaping (UUID, UUID) async -> Bool,
    onRenameProject: @escaping (UUID, String) -> Void
  ) {
    let content = TimelineProjectListWindowContent(
      snapshot: snapshot,
      onCompleteTask: onCompleteTask,
      onEditTask: onEditTask,
      onReorderTasks: onReorderTasks,
      onCreateTask: onCreateTask,
      onRenameTask: onRenameTask,
      onDeleteTask: onDeleteTask,
      onRenameProject: onRenameProject
    )

    pruneClosedWindows()
    let hostingController = NSHostingController(rootView: content)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.identifier = .timelineProjectListWindow
    window.title = snapshot.title
    window.contentViewController = hostingController
    window.isReleasedWhenClosed = false
    Self.configureWindowLevel(window)
    window.setFrameAutosaveName("TimelineProjectListWindow")
    positionNewWindow(window)

    let recordID = UUID()
    let delegate = ProjectListWindowDelegate { [weak self] in
      self?.removeWindowRecord(id: recordID)
    }
    window.delegate = delegate
    windowRecords.append(WindowRecord(id: recordID, window: window, delegate: delegate))

    Self.attachAboveApplicationWindow(window)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @discardableResult
  func refresh(snapshot: TimelineProjectListWindowSnapshot) -> Int {
    pruneClosedWindows()
    var refreshedCount = 0
    for record in windowRecords where Self.isLiveWindow(record.window) {
      guard
        let hostingController = record.window.contentViewController
          as? NSHostingController<TimelineProjectListWindowContent>,
        hostingController.rootView.snapshot.projectID == snapshot.projectID,
        hostingController.rootView.snapshot != snapshot
      else {
        continue
      }

      record.window.title = snapshot.title
      hostingController.rootView = hostingController.rootView.replacing(snapshot: snapshot)
      refreshedCount += 1
    }
    return refreshedCount
  }

  func closeAllWindows() {
    let records = windowRecords
    windowRecords.removeAll()
    for record in records {
      record.window.close()
    }
  }

  private func positionNewWindow(_ window: NSWindow) {
    guard let anchorWindow = windowRecords.last(where: { Self.isLiveWindow($0.window) })?.window else {
      window.center()
      return
    }

    let anchorOrigin = anchorWindow.frame.origin
    let nextOrigin = NSPoint(x: anchorOrigin.x + 28, y: max(anchorOrigin.y - 28, 80))
    window.setFrameOrigin(nextOrigin)
  }

  private func pruneClosedWindows() {
    windowRecords.removeAll { !Self.isLiveWindow($0.window) }
  }

  private func removeWindowRecord(id: UUID) {
    windowRecords.removeAll { $0.id == id }
  }

  private static func isLiveWindow(_ window: NSWindow) -> Bool {
    window.isVisible || window.isMiniaturized
  }

  private static func projectID(for window: NSWindow) -> UUID? {
    guard
      let hostingController = window.contentViewController
        as? NSHostingController<TimelineProjectListWindowContent>
    else {
      return nil
    }
    return hostingController.rootView.snapshot.projectID
  }

  private struct WindowRecord {
    let id: UUID
    let window: NSWindow
    let delegate: ProjectListWindowDelegate
  }

  private final class ProjectListWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
      self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
      onClose()
    }
  }
}

private struct TimelineProjectListWindowContent: View {
  let snapshot: TimelineProjectListWindowSnapshot
  let onCompleteTask: (UUID) async -> Bool
  let onEditTask: (UUID) -> Void
  let onReorderTasks: (UUID, [UUID]) -> Void
  let onCreateTask: (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?
  let onRenameTask: (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?
  let onDeleteTask: (UUID, UUID) async -> Bool
  let onRenameProject: (UUID, String) -> Void

  @State private var tasks: [TimelineProjectListWindowSnapshot.Task]
  @State private var draggingTaskID: UUID?
  @State private var dropIndicator: TimelineProjectListTaskDropIndicator?
  @State private var editingTaskID: UUID?
  @State private var editingTitle = ""
  @State private var draftAnchor: TimelineProjectListDraftAnchor?
  @State private var draftTitle = ""
  @State private var isCreatingTask = false
  @State private var isRenamingTask = false
  @State private var completingTaskIDs: Set<UUID> = []
  @State private var deletingTaskIDs: Set<UUID> = []
  @State private var focusedEditingTaskID: UUID?
  @State private var focusedDraftAnchor: TimelineProjectListDraftAnchor?
  @State private var showsCompletedTasks = false

  init(
    snapshot: TimelineProjectListWindowSnapshot,
    onCompleteTask: @escaping (UUID) async -> Bool,
    onEditTask: @escaping (UUID) -> Void,
    onReorderTasks: @escaping (UUID, [UUID]) -> Void,
    onCreateTask: @escaping (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onRenameTask: @escaping (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onDeleteTask: @escaping (UUID, UUID) async -> Bool,
    onRenameProject: @escaping (UUID, String) -> Void
  ) {
    self.snapshot = snapshot
    self.onCompleteTask = onCompleteTask
    self.onEditTask = onEditTask
    self.onReorderTasks = onReorderTasks
    self.onCreateTask = onCreateTask
    self.onRenameTask = onRenameTask
    self.onDeleteTask = onDeleteTask
    self.onRenameProject = onRenameProject
    _tasks = State(initialValue: snapshot.tasks)
  }

  func replacing(snapshot: TimelineProjectListWindowSnapshot) -> TimelineProjectListWindowContent {
    TimelineProjectListWindowContent(
      snapshot: snapshot,
      onCompleteTask: onCompleteTask,
      onEditTask: onEditTask,
      onReorderTasks: onReorderTasks,
      onCreateTask: onCreateTask,
      onRenameTask: onRenameTask,
      onDeleteTask: onDeleteTask,
      onRenameProject: onRenameProject
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Divider()

      if visibleTasks.isEmpty && draftAnchor == nil {
        Text("할일 없음")
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            if draftAnchor == .beginning {
              draftRow(anchor: .beginning)
            }

            ForEach(visibleTasks) { task in
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
              if draftAnchor == .after(task.id) {
                draftRow(anchor: .after(task.id))
              }
              if task.id != visibleTasks.last?.id {
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
    .onExitCommand {
      handleExitCommand()
    }
    .onChange(of: snapshot) { _, nextSnapshot in
      tasks = nextSnapshot.tasks
      draggingTaskID = nil
      dropIndicator = nil
      editingTaskID = nil
      editingTitle = ""
      draftAnchor = nil
      draftTitle = ""
      isCreatingTask = false
      isRenamingTask = false
      completingTaskIDs = []
      deletingTaskIDs = []
      focusedEditingTaskID = nil
      focusedDraftAnchor = nil
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
        .contextMenu {
          Button {
            requestProjectRename()
          } label: {
            Label("이름 변경", systemImage: "pencil")
          }
        }

      Spacer(minLength: 0)

      Button {
        toggleCompletedTasks()
      } label: {
        Image(systemName: showsCompletedTasks ? "checkmark.circle.fill" : "checkmark.circle")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(showsCompletedTasks ? projectColor : Color.secondary)
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.borderless)
      .help(showsCompletedTasks ? "완료항목 숨기기" : "완료항목 보기")
      .accessibilityLabel("완료항목 보기")

      Text("\(visibleTasks.count)")
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)

      Button {
        startDraft(after: visibleTasks.last?.id)
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 13, weight: .semibold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.borderless)
      .disabled(isCreatingTask)
      .help("할일 추가")
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
          cancelInlineEditing()
          completeTask(task.id)
        } label: {
          Image(systemName: completingTaskIDs.contains(task.id) ? "checkmark.circle" : taskMarkerName(task))
            .font(.system(size: 14))
            .foregroundStyle(task.isOverdue ? .red : .secondary)
            .frame(width: 18, height: 22, alignment: .top)
        }
        .buttonStyle(.plain)
        .disabled(completingTaskIDs.contains(task.id))
      }

      if editingTaskID == task.id {
        inlineTitleEditor(for: task)
      } else {
        taskTitleContent(task)
          .contentShape(Rectangle())
          .gesture(taskTitleClickGesture(for: task))
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 9)
    .contextMenu {
      Button("제목 수정") {
        startEditing(task)
      }
      Button("패널 열기") {
        cancelInlineEditing()
        onEditTask(task.id)
      }
      Divider()
      Button("삭제", role: .destructive) {
        deleteTask(task.id)
      }
      .disabled(deletingTaskIDs.contains(task.id))
    }
  }

  private func taskMarkerName(_ task: TimelineProjectListWindowSnapshot.Task) -> String {
    task.isOverdue ? "exclamationmark.circle" : "circle"
  }

  private func taskTitleContent(_ task: TimelineProjectListWindowSnapshot.Task) -> some View {
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
  }

  private func taskTitleClickGesture(
    for task: TimelineProjectListWindowSnapshot.Task
  ) -> some Gesture {
    TapGesture(count: 2)
      .onEnded {
        startEditing(task)
      }
      .exclusively(
        before: TapGesture(count: 1)
          .onEnded {
            cancelInlineEditing()
            onEditTask(task.id)
          }
      )
  }

  private func inlineTitleEditor(
    for task: TimelineProjectListWindowSnapshot.Task
  ) -> some View {
    EscapeAwareTextField(
      text: $editingTitle,
      isFocused: editingFocusBinding(for: task.id),
      placeholder: "제목",
      onSubmit: {
        submitInlineTitle(for: task, createDraftBelow: true)
      },
      onEscape: cancelInlineEditing
    )
      .frame(height: 22)
      .disabled(isRenamingTask)
      .onExitCommand {
        cancelInlineEditing()
      }
  }

  private func draftRow(anchor: TimelineProjectListDraftAnchor) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: "plus.circle")
        .font(.system(size: 14))
        .foregroundStyle(projectColor.opacity(0.9))
        .frame(width: 18, height: 22, alignment: .center)

      EscapeAwareTextField(
        text: $draftTitle,
        isFocused: draftFocusBinding(for: anchor),
        placeholder: "새 할일",
        onSubmit: {
          submitInlineDraft(anchor: anchor)
        },
        onEscape: cancelDraftIfEmpty
      )
      .frame(height: 22)
      .disabled(isCreatingTask)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 9)
    .onExitCommand {
      cancelDraftIfEmpty()
    }
  }

  private func draftFocusBinding(
    for anchor: TimelineProjectListDraftAnchor
  ) -> Binding<Bool> {
    Binding(
      get: { focusedDraftAnchor == anchor },
      set: { isFocused in
        if isFocused {
          focusedEditingTaskID = nil
          focusedDraftAnchor = anchor
        } else if focusedDraftAnchor == anchor {
          focusedDraftAnchor = nil
        }
      }
    )
  }

  private func editingFocusBinding(for taskID: UUID) -> Binding<Bool> {
    Binding(
      get: { focusedEditingTaskID == taskID },
      set: { isFocused in
        if isFocused {
          focusedDraftAnchor = nil
          focusedEditingTaskID = taskID
        } else if focusedEditingTaskID == taskID {
          focusedEditingTaskID = nil
        }
      }
    )
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
    onReorderTasks(snapshot.projectID, openTaskIDs)
    draggingTaskID = nil
    dropIndicator = nil
  }

  private func completeTask(_ taskID: UUID) {
    guard !completingTaskIDs.contains(taskID) else { return }
    completingTaskIDs.insert(taskID)
    Task { @MainActor in
      let didComplete = await onCompleteTask(taskID)
      completingTaskIDs.remove(taskID)
      guard didComplete else { return }
      markTaskCompleted(taskID)
      onReorderTasks(snapshot.projectID, openTaskIDs)
    }
  }

  private func deleteTask(_ taskID: UUID) {
    guard !deletingTaskIDs.contains(taskID) else { return }
    cancelInlineEditing()
    deletingTaskIDs.insert(taskID)
    Task { @MainActor in
      let didDelete = await onDeleteTask(snapshot.projectID, taskID)
      deletingTaskIDs.remove(taskID)
      guard didDelete else { return }
      removeTaskFromWindow(taskID)
      onReorderTasks(snapshot.projectID, openTaskIDs)
    }
  }

  private func toggleCompletedTasks() {
    cancelInlineEditing()
    cancelDraftIfEmpty()
    showsCompletedTasks.toggle()
  }

  private func requestProjectRename() {
    cancelInlineEditing()
    cancelDraftIfEmpty()
    onRenameProject(snapshot.projectID, snapshot.title)
  }

  private func startEditing(_ task: TimelineProjectListWindowSnapshot.Task) {
    guard !isRenamingTask, !isCreatingTask else { return }
    draftAnchor = nil
    draftTitle = ""
    focusedDraftAnchor = nil
    editingTaskID = task.id
    editingTitle = task.title
    DispatchQueue.main.async {
      focusedEditingTaskID = task.id
    }
  }

  private func submitInlineTitle(
    for task: TimelineProjectListWindowSnapshot.Task,
    createDraftBelow: Bool
  ) {
    let title = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isRenamingTask else { return }
    guard title != task.title else {
      editingTaskID = nil
      editingTitle = ""
      focusedEditingTaskID = nil
      if createDraftBelow {
        startDraft(after: task.id)
      }
      return
    }
    isRenamingTask = true

    Task { @MainActor in
      defer { isRenamingTask = false }
      guard let updatedTask = await onRenameTask(snapshot.projectID, task.id, title) else {
        return
      }
      replaceTask(updatedTask)
      editingTaskID = nil
      editingTitle = ""
      focusedEditingTaskID = nil
      if createDraftBelow {
        startDraft(after: updatedTask.id)
      }
    }
  }

  private func startDraft(after taskID: UUID?) {
    guard !isCreatingTask, !isRenamingTask else { return }
    editingTaskID = nil
    editingTitle = ""
    focusedEditingTaskID = nil
    let anchor: TimelineProjectListDraftAnchor = taskID.map(TimelineProjectListDraftAnchor.after) ?? .beginning
    draftAnchor = anchor
    draftTitle = ""
    focusDraft(anchor)
  }

  private func cancelInlineEditing() {
    guard !isRenamingTask else { return }
    editingTaskID = nil
    editingTitle = ""
    focusedEditingTaskID = nil
  }

  private func cancelDraftIfEmpty() {
    guard TimelineProjectListDraftPolicy.shouldCancelDraft(title: draftTitle) else { return }
    draftAnchor = nil
    draftTitle = ""
    focusedDraftAnchor = nil
  }

  private func handleExitCommand() {
    if draftAnchor != nil {
      cancelDraftIfEmpty()
      return
    }
    cancelInlineEditing()
  }

  private func submitInlineDraft(anchor: TimelineProjectListDraftAnchor) {
    let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isCreatingTask else { return }
    isCreatingTask = true

    Task { @MainActor in
      defer { isCreatingTask = false }
      guard let createdTask = await onCreateTask(snapshot.projectID, title) else {
        return
      }

      if !tasks.contains(where: { $0.id == createdTask.id }) {
        insertCreatedTask(createdTask, after: anchor.taskID)
      }
      onReorderTasks(snapshot.projectID, openTaskIDs)
      let nextAnchor = TimelineProjectListDraftAnchor.after(createdTask.id)
      draftAnchor = nextAnchor
      draftTitle = ""
      focusDraft(nextAnchor)
    }
  }

  private func focusDraft(_ anchor: TimelineProjectListDraftAnchor) {
    DispatchQueue.main.async {
      focusedDraftAnchor = anchor
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) {
      if draftAnchor == anchor {
        focusedDraftAnchor = anchor
      }
    }
  }

  private func replaceTask(_ task: TimelineProjectListWindowSnapshot.Task) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    tasks[index] = task
  }

  private func markTaskCompleted(_ taskID: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
    let task = tasks[index]
    tasks[index] = TimelineProjectListWindowSnapshot.Task(
      id: task.id,
      title: task.title,
      dateText: task.dateText,
      isCompleted: true,
      isOverdue: false
    )
    cancelInlineEditingIfNeeded(for: taskID)
    cancelDraftIfNeeded(after: taskID)
  }

  private func removeTaskFromWindow(_ taskID: UUID) {
    let orderedIDs = TimelineProjectTaskManualOrderStore.removedTaskIDs(
      tasks.map(\.id),
      removedID: taskID
    )
    let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    tasks = orderedIDs.compactMap { tasksByID[$0] }
    cancelInlineEditingIfNeeded(for: taskID)
    cancelDraftIfNeeded(after: taskID)
  }

  private func cancelInlineEditingIfNeeded(for taskID: UUID) {
    if editingTaskID == taskID {
      editingTaskID = nil
      editingTitle = ""
      focusedEditingTaskID = nil
    }
  }

  private func cancelDraftIfNeeded(after taskID: UUID) {
    if draftAnchor == .after(taskID) {
      draftAnchor = nil
      draftTitle = ""
      focusedDraftAnchor = nil
    }
  }

  private func insertCreatedTask(
    _ task: TimelineProjectListWindowSnapshot.Task,
    after anchorID: UUID?
  ) {
    let orderedIDs = TimelineProjectTaskManualOrderStore.insertedTaskIDs(
      tasks.map(\.id),
      insertedID: task.id,
      after: anchorID
    )
    var tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    tasksByID[task.id] = task
    tasks = orderedIDs.compactMap { tasksByID[$0] }
  }

  private var projectColor: Color {
    ColorHexCodec.color(from: snapshot.colorHex) ?? .accentColor
  }

  private var visibleTasks: [TimelineProjectListWindowSnapshot.Task] {
    showsCompletedTasks ? tasks : tasks.filter { !$0.isCompleted }
  }

  private var openTaskIDs: [UUID] {
    tasks.filter { !$0.isCompleted }.map(\.id)
  }
}

private enum TimelineProjectListDraftAnchor: Hashable {
  case beginning
  case after(UUID)

  var taskID: UUID? {
    switch self {
    case .beginning:
      return nil
    case .after(let taskID):
      return taskID
    }
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
