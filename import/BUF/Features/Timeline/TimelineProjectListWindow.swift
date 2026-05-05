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
    let notePreviewText: String?
    let isCompleted: Bool
    let isOverdue: Bool
  }

  let projectID: UUID
  let title: String
  let colorHex: String?
  let tasks: [Task]
}

struct TimelineProjectMoveOption: Identifiable, Equatable {
  let id: UUID
  let title: String
}

enum TimelineProjectListPresentation {
  case window
  case embedded
}

struct TimelineProjectListActions {
  let onToggleTaskCompletion: (UUID, Bool) async -> Bool
  let onEditTask: (UUID) -> Void
  let onReorderTasks: (UUID, [UUID], Bool) -> Void
  let onCreateTask: (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?
  let onRenameTask: (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?
  let onDeleteTask: (UUID, UUID) async -> Bool
  let onRenameProject: (UUID, String) -> Void
  let moveOptions: () -> [TimelineProjectMoveOption]
  let onMoveTask: (UUID, UUID, UUID) async -> Bool

  init(
    onToggleTaskCompletion: @escaping (UUID, Bool) async -> Bool,
    onEditTask: @escaping (UUID) -> Void,
    onReorderTasks: @escaping (UUID, [UUID], Bool) -> Void,
    onCreateTask: @escaping (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onRenameTask: @escaping (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onDeleteTask: @escaping (UUID, UUID) async -> Bool,
    onRenameProject: @escaping (UUID, String) -> Void,
    moveOptions: @escaping () -> [TimelineProjectMoveOption] = { [] },
    onMoveTask: @escaping (UUID, UUID, UUID) async -> Bool = { _, _, _ in false }
  ) {
    self.onToggleTaskCompletion = onToggleTaskCompletion
    self.onEditTask = onEditTask
    self.onReorderTasks = onReorderTasks
    self.onCreateTask = onCreateTask
    self.onRenameTask = onRenameTask
    self.onDeleteTask = onDeleteTask
    self.onRenameProject = onRenameProject
    self.moveOptions = moveOptions
    self.onMoveTask = onMoveTask
  }
}

struct TimelineProjectListInlineEditorConfiguration {
  let initialExpandedTaskID: UUID?
  let workspaceTreeRevision: Int
  let vaultRootURL: URL?
  let initialFields: (TimelineProjectListWindowSnapshot.Task) -> RetainedTaskEditFields
  let loadFields: (UUID, RetainedTaskEditFields) async -> RetainedTaskEditFields
  let saveFields: (UUID, RetainedTaskEditFields) async throws -> Void
  let onSyncEditingChanged: (UUID, Bool) -> Void
  let onSyncEditingActivity: () -> Void
}

enum TimelineProjectListTaskOrderPolicy {
  static func reorderedTasks(
    _ orderedTaskIDs: [UUID],
    tasksByID: [UUID: TimelineProjectListWindowSnapshot.Task]
  ) -> [TimelineProjectListWindowSnapshot.Task] {
    orderedTaskIDs.compactMap { tasksByID[$0] }
  }

  static func openTaskIDs(
    from tasks: [TimelineProjectListWindowSnapshot.Task]
  ) -> [UUID] {
    tasks.filter { !$0.isCompleted }.map(\.id)
  }
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
    window.level = .floating
    if let panel = window as? NSPanel {
      panel.isFloatingPanel = true
      panel.hidesOnDeactivate = true
    }
  }

  func present(
    snapshot: TimelineProjectListWindowSnapshot,
    onToggleTaskCompletion: @escaping (UUID, Bool) async -> Bool,
    onEditTask: @escaping (UUID) -> Void,
    onReorderTasks: @escaping (UUID, [UUID], Bool) -> Void,
    onCreateTask: @escaping (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onRenameTask: @escaping (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onDeleteTask: @escaping (UUID, UUID) async -> Bool,
    onRenameProject: @escaping (UUID, String) -> Void
  ) {
    present(
      snapshot: snapshot,
      actions: TimelineProjectListActions(
        onToggleTaskCompletion: onToggleTaskCompletion,
        onEditTask: onEditTask,
        onReorderTasks: onReorderTasks,
        onCreateTask: onCreateTask,
        onRenameTask: onRenameTask,
        onDeleteTask: onDeleteTask,
        onRenameProject: onRenameProject
      )
    )
  }

  func present(
    snapshot: TimelineProjectListWindowSnapshot,
    actions: TimelineProjectListActions
  ) {
    let content = TimelineProjectListContent(
      snapshot: snapshot,
      presentation: .window,
      actions: actions
    )

    pruneClosedWindows()
    let hostingController = NSHostingController(rootView: content)
    let window = NSPanel(
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

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  @discardableResult
  func refresh(snapshot: TimelineProjectListWindowSnapshot) -> Int {
    pruneClosedWindows()
    var refreshedCount = 0
    for record in windowRecords where Self.isLiveWindow(record.window) {
      guard
        let hostingController = record.window.contentViewController
          as? NSHostingController<TimelineProjectListContent>,
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
        as? NSHostingController<TimelineProjectListContent>
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

struct TimelineProjectListContent: View {
  let snapshot: TimelineProjectListWindowSnapshot
  let presentation: TimelineProjectListPresentation
  let actions: TimelineProjectListActions
  let onOpenProjectWindow: (() -> Void)?
  let onClosePanel: (() -> Void)?
  let inlineEditorConfiguration: TimelineProjectListInlineEditorConfiguration?

  @ObservedObject private var sessionStore: TimelineProjectListSessionStore
  @State private var isCreatingTask = false
  @State private var isRenamingTask = false
  @State private var completingTaskIDs: Set<UUID> = []
  @State private var deletingTaskIDs: Set<UUID> = []
  @State private var movingTaskIDs: Set<UUID> = []
  @State private var showsCompletedTasks = false
  @State private var showsTaskNotes = false
  @State private var writeQueue = TimelineProjectListWriteQueue()
  @State private var expandedTaskID: UUID?

  init(
    snapshot: TimelineProjectListWindowSnapshot,
    presentation: TimelineProjectListPresentation = .window,
    actions: TimelineProjectListActions,
    onOpenProjectWindow: (() -> Void)? = nil,
    onClosePanel: (() -> Void)? = nil,
    inlineEditorConfiguration: TimelineProjectListInlineEditorConfiguration? = nil,
    sessionStore: TimelineProjectListSessionStore? = nil
  ) {
    self.snapshot = snapshot
    self.presentation = presentation
    self.actions = actions
    self.onOpenProjectWindow = onOpenProjectWindow
    self.onClosePanel = onClosePanel
    self.inlineEditorConfiguration = inlineEditorConfiguration
    _sessionStore = ObservedObject(
      wrappedValue: sessionStore ?? TimelineProjectListSessionStore(snapshot: snapshot)
    )
    _expandedTaskID = State(initialValue: inlineEditorConfiguration?.initialExpandedTaskID)
  }

  func replacing(snapshot: TimelineProjectListWindowSnapshot) -> TimelineProjectListContent {
    sessionStore.applySnapshot(snapshot)
    return TimelineProjectListContent(
      snapshot: snapshot,
      presentation: presentation,
      actions: actions,
      onOpenProjectWindow: onOpenProjectWindow,
      onClosePanel: onClosePanel,
      inlineEditorConfiguration: inlineEditorConfiguration,
      sessionStore: sessionStore
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Divider()

      if visibleTasks.isEmpty && session.draftAnchor == nil {
        Text("할일 없음")
          .font(projectListEmptyStateFont)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            if session.draftAnchor == .beginning {
              draftRow(anchor: .beginning)
            }

            ForEach(visibleTasks) { task in
              dropLine(for: task, placement: .before)
              taskRow(task)
                .opacity(session.draggingTaskID == task.id || movingTaskIDs.contains(task.id) ? 0.42 : 1)
                .onDrag {
                  updateSession { session in
                    session.beginDragging(taskID: task.id)
                  }
                  return TaskDragPayload.itemProvider(for: task.id)
                } preview: {
                  TimelineProjectListHiddenDragPreview()
                }
                .onDrop(
                  of: [UTType.text.identifier],
                  delegate: TimelineProjectListTaskDropDelegate(
                    targetTaskID: task.id,
                    draggingTaskID: draggingTaskIDBinding,
                    dropIndicator: dropIndicatorBinding,
                    onPreviewDrop: previewTaskDrop,
                    onPerformDrop: commitTaskDrop
                  )
                )
              if expandedTaskID == task.id {
                inlineTaskEditor(for: task)
              }
              dropLine(for: task, placement: .after)
              if session.draftAnchor == .after(task.id) {
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
    .frame(
      minWidth: presentation == .window ? 360 : 0,
      maxWidth: .infinity,
      minHeight: presentation == .window ? 420 : 320,
      maxHeight: .infinity,
      alignment: .topLeading
    )
    .background(Color(nsColor: .windowBackgroundColor))
    .onExitCommand {
      handleExitCommand()
    }
    .onChange(of: snapshot) { _, nextSnapshot in
      sessionStore.applySnapshot(nextSnapshot)
      guard let expandedTaskID else { return }
      if !nextSnapshot.tasks.contains(where: { $0.id == expandedTaskID }) {
        self.expandedTaskID = nil
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      Circle()
        .fill(projectColor)
        .frame(width: 10, height: 10)

      Text(snapshot.title)
        .font(projectListTitleFont)
        .lineLimit(1)
        .contextMenu {
          Button {
            requestProjectRename()
          } label: {
            Label("이름 변경", systemImage: "pencil")
          }
        }

      if let onOpenProjectWindow {
        Button {
          onOpenProjectWindow()
        } label: {
          Image(systemName: "arrow.up.right.square")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("프로젝트 창 열기")
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

      Button {
        toggleTaskNotes()
      } label: {
        Image(systemName: "note.text")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(showsTaskNotes ? projectColor : Color.secondary)
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.borderless)
      .help(showsTaskNotes ? "노트 미리보기 숨기기" : "노트 미리보기 보기")
      .accessibilityLabel("노트 미리보기")

      Text("\(visibleTasks.count)")
        .font(projectListCountFont)
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

      if let onClosePanel {
        Button {
          onClosePanel()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("닫기")
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  @ViewBuilder
  private func dropLine(
    for task: TimelineProjectListWindowSnapshot.Task,
    placement: TimelineProjectDropPlacement
  ) -> some View {
    if session.dropIndicator
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
      Button {
        cancelInlineEditing()
        toggleTaskCompletion(task.id, isCompleted: task.isCompleted)
      } label: {
        Image(systemName: completionMarkerName(for: task))
          .font(.system(size: 14))
          .foregroundStyle(completionMarkerColor(for: task))
          .frame(width: 18, height: 22, alignment: .top)
          .offset(y: 3)
      }
      .buttonStyle(.plain)
      .disabled(completingTaskIDs.contains(task.id))

      if session.editingTaskID == task.id {
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
      Button(inlineEditorConfiguration == nil ? "패널 열기" : "편집 열기") {
        cancelInlineEditing()
        openTask(task)
      }
      moveTaskMenu(for: task)
      Divider()
      Button("삭제", role: .destructive) {
        deleteTask(task.id)
      }
      .disabled(deletingTaskIDs.contains(task.id))
    }
  }

  @ViewBuilder
  private func moveTaskMenu(
    for task: TimelineProjectListWindowSnapshot.Task
  ) -> some View {
    let targets = actions.moveOptions().filter { $0.id != snapshot.projectID }
    if !targets.isEmpty {
      Menu("이동") {
        ForEach(targets) { target in
          Button(target.title) {
            moveTaskToProject(task.id, targetProjectID: target.id)
          }
        }
      }
      .disabled(movingTaskIDs.contains(task.id))
    }
  }

  private func taskMarkerName(_ task: TimelineProjectListWindowSnapshot.Task) -> String {
    task.isOverdue ? "exclamationmark.circle" : "circle"
  }

  private func completionMarkerName(for task: TimelineProjectListWindowSnapshot.Task) -> String {
    if completingTaskIDs.contains(task.id) {
      return task.isCompleted ? "circle" : "checkmark.circle"
    }
    return task.isCompleted ? "checkmark.circle.fill" : taskMarkerName(task)
  }

  private func completionMarkerColor(for task: TimelineProjectListWindowSnapshot.Task) -> Color {
    if task.isCompleted {
      return projectColor.opacity(0.9)
    }
    return task.isOverdue ? .red : .secondary
  }

  private func taskTitleContent(_ task: TimelineProjectListWindowSnapshot.Task) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(task.title)
          .font(projectListBodyFont)
          .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
          .strikethrough(task.isCompleted, color: Color.secondary.opacity(0.55))
          .lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .layoutPriority(1)

        if let dateText = task.dateText {
          Text(dateText)
            .font(projectListDateFont)
            .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
      }

      if showsTaskNotes,
        expandedTaskID != task.id,
        let notePreviewText = task.notePreviewText
      {
        TimelineProjectListNotePreviewText(markdown: notePreviewText)
          .font(projectListNoteFont)
          .foregroundStyle(Color.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
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
            openTask(task)
          }
      )
  }

  @ViewBuilder
  private func inlineTaskEditor(
    for task: TimelineProjectListWindowSnapshot.Task
  ) -> some View {
    if let configuration = inlineEditorConfiguration {
      TimelineTaskEditPopoverContent(
        initialFields: configuration.initialFields(task),
        presentationStyle: .inlinePanel,
        reloadToken: TaskEditReloadToken.workspacePanel(
          projectID: snapshot.projectID,
          taskID: task.id,
          workspaceTreeRevision: configuration.workspaceTreeRevision
        ),
        vaultRootURL: configuration.vaultRootURL,
        loadFields: {
          await configuration.loadFields(task.id, configuration.initialFields(task))
        },
        saveFields: { fields in
          try await configuration.saveFields(task.id, fields)
        },
        onSyncEditingChanged: { isEditing in
          configuration.onSyncEditingChanged(task.id, isEditing)
        },
        onSyncEditingActivity: configuration.onSyncEditingActivity,
        onCancel: {
          if expandedTaskID == task.id {
            expandedTaskID = nil
          }
        }
      )
      .id(task.id)
      .padding(.leading, 32)
      .padding(.trailing, 12)
      .padding(.bottom, 10)
    }
  }

  private func openTask(_ task: TimelineProjectListWindowSnapshot.Task) {
    if inlineEditorConfiguration != nil {
      cancelDraftIfEmpty()
      expandedTaskID = expandedTaskID == task.id ? nil : task.id
      return
    }
    actions.onEditTask(task.id)
  }

  private func inlineTitleEditor(
    for task: TimelineProjectListWindowSnapshot.Task
  ) -> some View {
    EscapeAwareTextField(
      text: editingTitleBinding,
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
        text: draftTitleBinding,
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
      get: { session.focusedDraftAnchor == anchor },
      set: { isFocused in
        updateSession { session in
          if isFocused {
            session.focusedEditingTaskID = nil
            session.focusedDraftAnchor = anchor
          } else if session.focusedDraftAnchor == anchor {
            session.focusedDraftAnchor = nil
          }
        }
      }
    )
  }

  private func editingFocusBinding(for taskID: UUID) -> Binding<Bool> {
    Binding(
      get: { session.focusedEditingTaskID == taskID },
      set: { isFocused in
        updateSession { session in
          if isFocused {
            session.focusedDraftAnchor = nil
            session.focusedEditingTaskID = taskID
          } else if session.focusedEditingTaskID == taskID {
            session.focusedEditingTaskID = nil
          }
        }
      }
    )
  }

  private func previewTaskDrop(
    draggedID: UUID,
    targetID: UUID,
    placement: TimelineProjectDropPlacement
  ) -> Bool {
    var didPreview = false
    MotionTransaction.perform(
      .interactionPreview,
      context: MotionContext(tier: .hotPath, isDragging: true)
    ) {
      updateSession { session in
        didPreview = session.previewDrop(
          draggedID: draggedID,
          targetID: targetID,
          placement: placement
        )
      }
    }
    return didPreview
  }

  private func commitTaskDrop() {
    let orderedTaskIDs = MotionTransaction.withResult(
      .interactionCommit,
      context: MotionContext(tier: .hotPath, isDragging: true)
    ) {
      commitSessionDrop()
    }
    guard !orderedTaskIDs.isEmpty else { return }
    actions.onReorderTasks(
      snapshot.projectID,
      orderedTaskIDs,
      true
    )
  }

  private func toggleTaskCompletion(_ taskID: UUID, isCompleted: Bool) {
    guard !completingTaskIDs.contains(taskID) else { return }
    completingTaskIDs.insert(taskID)
    Task { @MainActor in
      let didToggle = await actions.onToggleTaskCompletion(taskID, isCompleted)
      completingTaskIDs.remove(taskID)
      guard didToggle else { return }
      setTaskCompletion(
        taskID,
        isCompleted: TimelineTaskCompletionTogglePolicy.nextIsCompleted(
          currentIsCompleted: isCompleted
        )
      )
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func deleteTask(_ taskID: UUID) {
    guard !deletingTaskIDs.contains(taskID) else { return }
    cancelInlineEditing()
    deletingTaskIDs.insert(taskID)
    Task { @MainActor in
      let didDelete = await actions.onDeleteTask(snapshot.projectID, taskID)
      deletingTaskIDs.remove(taskID)
      guard didDelete else { return }
      removeTaskFromWindow(taskID)
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func moveTaskToProject(_ taskID: UUID, targetProjectID: UUID) {
    guard targetProjectID != snapshot.projectID else { return }
    guard !movingTaskIDs.contains(taskID) else { return }
    cancelInlineEditing()
    cancelDraftIfEmpty()
    movingTaskIDs.insert(taskID)
    Task { @MainActor in
      let didMove = await actions.onMoveTask(snapshot.projectID, taskID, targetProjectID)
      movingTaskIDs.remove(taskID)
      guard didMove else { return }
      removeTaskFromWindow(taskID)
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func toggleCompletedTasks() {
    cancelInlineEditing()
    cancelDraftIfEmpty()
    showsCompletedTasks.toggle()
  }

  private func toggleTaskNotes() {
    cancelInlineEditing()
    cancelDraftIfEmpty()
    showsTaskNotes.toggle()
  }

  private func requestProjectRename() {
    cancelInlineEditing()
    cancelDraftIfEmpty()
    actions.onRenameProject(snapshot.projectID, snapshot.title)
  }

  private func startEditing(_ task: TimelineProjectListWindowSnapshot.Task) {
    guard !isRenamingTask, !isCreatingTask else { return }
    updateSession { session in
      session.startEditing(task)
    }
    DispatchQueue.main.async {
      updateSession { session in
        session.focusedEditingTaskID = task.id
      }
    }
  }

  private func submitInlineTitle(
    for task: TimelineProjectListWindowSnapshot.Task,
    createDraftBelow: Bool
  ) {
    let title = session.editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isRenamingTask else { return }
    guard title != task.title else {
      updateSession { session in
        session.editingTaskID = nil
        session.editingTitle = ""
        session.focusedEditingTaskID = nil
      }
      if createDraftBelow {
        startDraft(after: task.id)
      }
      return
    }
    guard submitRenameOptimistically(taskID: task.id) != nil else {
      return
    }
    if createDraftBelow {
      startDraft(after: task.id)
    }
    isRenamingTask = true

    writeQueue.enqueue {
      defer { isRenamingTask = false }
      guard let updatedTask = await actions.onRenameTask(snapshot.projectID, task.id, title) else {
        updateSession { session in
          session.failOptimisticRename(taskID: task.id)
        }
        return
      }
      updateSession { session in
        session.resolveOptimisticRename(taskID: task.id, updatedTask: updatedTask)
      }
    }
  }

  private func startDraft(after taskID: UUID?) {
    guard !isCreatingTask, !isRenamingTask else { return }
    updateSession { session in
      session.startDraft(after: taskID)
    }
    focusDraft(taskID.map(TimelineProjectListDraftAnchor.after) ?? .beginning)
  }

  private func cancelInlineEditing() {
    guard !isRenamingTask else { return }
    updateSession { session in
      session.editingTaskID = nil
      session.editingTitle = ""
      session.focusedEditingTaskID = nil
    }
  }

  private func cancelDraftIfEmpty() {
    guard TimelineProjectListDraftPolicy.shouldCancelDraft(title: session.draftTitle) else {
      return
    }
    updateSession { session in
      session.draftAnchor = nil
      session.draftTitle = ""
      session.focusedDraftAnchor = nil
    }
  }

  private func handleExitCommand() {
    if session.draftAnchor != nil {
      cancelDraftIfEmpty()
      return
    }
    cancelInlineEditing()
  }

  private func submitInlineDraft(anchor: TimelineProjectListDraftAnchor) {
    let title = session.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isCreatingTask else { return }
    let temporaryID = UUID()
    guard submitDraftOptimistically(temporaryID: temporaryID) != nil else { return }
    isCreatingTask = true

    writeQueue.enqueue {
      defer { isCreatingTask = false }
      guard let createdTask = await actions.onCreateTask(snapshot.projectID, title) else {
        updateSession { session in
          session.failOptimisticCreate(temporaryID: temporaryID)
        }
        return
      }

      updateSession { session in
        session.resolveOptimisticCreate(temporaryID: temporaryID, createdTask: createdTask)
      }
      enqueueTaskOrderSave(registerUndo: false)
      focusDraft(.after(createdTask.id))
    }
  }

  private func focusDraft(_ anchor: TimelineProjectListDraftAnchor) {
    DispatchQueue.main.async {
      updateSession { session in
        session.focusedDraftAnchor = anchor
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) {
      if session.draftAnchor == anchor {
        updateSession { session in
          session.focusedDraftAnchor = anchor
        }
      }
    }
  }

  private func replaceTask(_ task: TimelineProjectListWindowSnapshot.Task) {
    updateSession { session in
      session.replaceTask(task)
    }
  }

  private func setTaskCompletion(_ taskID: UUID, isCompleted: Bool) {
    updateSession { session in
      session.setTaskCompletion(taskID, isCompleted: isCompleted)
    }
  }

  private func removeTaskFromWindow(_ taskID: UUID) {
    updateSession { session in
      session.removeTask(taskID)
    }
  }

  private func submitDraftOptimistically(temporaryID: UUID)
    -> TimelineProjectListWindowSnapshot.Task?
  {
    var createdTask: TimelineProjectListWindowSnapshot.Task?
    updateSession { session in
      createdTask = session.submitDraftOptimistically(temporaryID: temporaryID)
    }
    return createdTask
  }

  private func submitRenameOptimistically(taskID: UUID)
    -> TimelineProjectListWindowSnapshot.Task?
  {
    var renamedTask: TimelineProjectListWindowSnapshot.Task?
    updateSession { session in
      renamedTask = session.submitRenameOptimistically(taskID: taskID)
    }
    return renamedTask
  }

  private func commitSessionDrop() -> [UUID] {
    var orderedTaskIDs: [UUID] = []
    updateSession { session in
      orderedTaskIDs = session.commitDrop()
    }
    return orderedTaskIDs
  }

  private func enqueueTaskOrderSave(registerUndo: Bool) {
    writeQueue.enqueue {
      let orderedTaskIDs = session.persistableOpenTaskIDs
      actions.onReorderTasks(
        snapshot.projectID,
        orderedTaskIDs,
        registerUndo
      )
    }
  }

  private func updateSession(_ mutate: (inout TimelineProjectListSession) -> Void) {
    sessionStore.update(mutate)
  }

  private var session: TimelineProjectListSession {
    sessionStore.session
  }

  private var draftTitleBinding: Binding<String> {
    Binding(
      get: { session.draftTitle },
      set: { title in
        updateSession { session in
          session.updateDraftTitle(title)
        }
      }
    )
  }

  private var editingTitleBinding: Binding<String> {
    Binding(
      get: { session.editingTitle },
      set: { title in
        updateSession { session in
          session.updateEditingTitle(title)
        }
      }
    )
  }

  private var draggingTaskIDBinding: Binding<UUID?> {
    Binding(
      get: { session.draggingTaskID },
      set: { taskID in
        updateSession { session in
          session.draggingTaskID = taskID
        }
      }
    )
  }

  private var dropIndicatorBinding: Binding<TimelineProjectListTaskDropIndicator?> {
    Binding(
      get: { session.dropIndicator },
      set: { indicator in
        updateSession { session in
          session.dropIndicator = indicator
        }
      }
    )
  }

  private var projectColor: Color {
    ColorHexCodec.color(from: snapshot.colorHex) ?? .accentColor
  }

  private var projectListTitleFont: Font {
    switch presentation {
    case .window:
      return .system(size: 18, weight: .semibold)
    case .embedded:
      return AppInputTypography.font(size: Self.embeddedTextSize, weight: .semibold)
    }
  }

  private var projectListBodyFont: Font {
    switch presentation {
    case .window:
      return .system(size: 13)
    case .embedded:
      return AppInputTypography.font(size: Self.embeddedTextSize)
    }
  }

  private var projectListCountFont: Font {
    switch presentation {
    case .window:
      return .system(size: 13, weight: .medium).monospacedDigit()
    case .embedded:
      return AppInputTypography.font(size: Self.embeddedTextSize, weight: .medium)
        .monospacedDigit()
    }
  }

  private var projectListDateFont: Font {
    switch presentation {
    case .window:
      return .system(size: 11)
    case .embedded:
      return AppInputTypography.font(size: Self.embeddedTextSize)
    }
  }

  private var projectListNoteFont: Font {
    switch presentation {
    case .window:
      return .system(size: 11)
    case .embedded:
      return AppInputTypography.font(size: max(Self.embeddedTextSize - 1, 10))
    }
  }

  private var projectListEmptyStateFont: Font {
    switch presentation {
    case .window:
      return .system(size: 14)
    case .embedded:
      return AppInputTypography.font(size: Self.embeddedTextSize)
    }
  }

  private var visibleTasks: [TimelineProjectListWindowSnapshot.Task] {
    session.visibleTasks(showsCompletedTasks: showsCompletedTasks)
  }

  private var openTaskIDs: [UUID] {
    session.openTaskIDs
  }

  private static let embeddedTextSize: CGFloat = 12 * 1.3 * 0.9
}

private struct TimelineProjectListHiddenDragPreview: View {
  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .accessibilityHidden(true)
  }
}

private struct TimelineProjectListNotePreviewText: View {
  let markdown: String

  var body: some View {
    renderedText
      .fixedSize(horizontal: false, vertical: true)
  }

  private var renderedText: Text {
    guard let attributed = try? AttributedString(
      markdown: markdown,
      options: AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .full,
        failurePolicy: .returnPartiallyParsedIfPossible
      )
    ) else {
      return Text(markdown)
    }
    return Text(attributed)
  }
}

private struct TimelineProjectListTaskDropDelegate: DropDelegate {
  let targetTaskID: UUID
  @Binding var draggingTaskID: UUID?
  @Binding var dropIndicator: TimelineProjectListTaskDropIndicator?
  let onPreviewDrop:
    (_ draggedID: UUID, _ targetID: UUID, _ placement: TimelineProjectDropPlacement) -> Bool
  let onPerformDrop:
    () -> Void

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
    if dropIndicator != indicator,
      onPreviewDrop(draggingTaskID, targetTaskID, placement)
    {
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
      draggingTaskID != nil,
      draggingTaskID != targetTaskID
    else {
      return false
    }
    onPerformDrop()
    return true
  }

  func dropExited(info: DropInfo) {
    if dropIndicator?.targetTaskID == targetTaskID {
      dropIndicator = nil
    }
  }
}
