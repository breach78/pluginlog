import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TimelineProjectListContent: View {
  let snapshot: TimelineProjectListWindowSnapshot
  let presentation: TimelineProjectListPresentation
  let actions: TimelineProjectListActions
  let onOpenProjectWindow: (() -> Void)?
  let onClosePanel: (() -> Void)?
  let inlineEditorConfiguration: TimelineProjectListInlineEditorConfiguration?

  @ObservedObject private var sessionStore: TimelineProjectListSessionStore
  @State private var pendingCreateCount = 0
  @State private var isRenamingTask = false
  @State private var completingTaskIDs: Set<UUID> = []
  @State private var deletingTaskIDs: Set<UUID> = []
  @State private var movingTaskIDs: Set<UUID> = []
  @State private var showsCompletedTasks: Bool
  @State private var showsTaskNotes: Bool
  @State private var writeQueue = TimelineProjectListWriteQueue()
  @State private var expandedTaskID: UUID?
  @State private var expandedTaskCloseRequestID = 0
  @State private var pendingExpandedTaskIDAfterClose: UUID?
  @State private var pendingTaskOpenTask: Task<Void, Never>?
  @State private var projectNoteText: String
  @State private var projectNoteHeight: CGFloat = 0
  @State private var lastCommittedProjectNoteText: String
  @State private var projectNoteAutoSaveTask: Task<Void, Never>?
  @State private var isSavingProjectNote = false
  @State private var saveProjectNoteAgainAfterCurrent = false
  @State private var projectNoteErrorText: String?
  @State private var draftScrollRequestID = 0

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
    let displayPreferences = TimelineProjectListDisplayPreferenceStore.load(
      for: snapshot.projectID
    )
    _showsCompletedTasks = State(initialValue: displayPreferences.showsCompletedTasks)
    _showsTaskNotes = State(initialValue: displayPreferences.showsTaskNotes)
    _expandedTaskID = State(initialValue: inlineEditorConfiguration?.initialExpandedTaskID)
    _projectNoteText = State(initialValue: snapshot.projectNoteText)
    _lastCommittedProjectNoteText = State(
      initialValue: TimelineProjectNoteAutoSavePolicy.normalized(snapshot.projectNoteText)
    )
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

      scrollContent
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
      applyProjectNoteTextFromSnapshot(nextSnapshot.projectNoteText)
      guard let expandedTaskID else { return }
      if !nextSnapshot.tasks.contains(where: { $0.id == expandedTaskID }) {
        self.expandedTaskID = nil
      }
    }
    .onChange(of: projectNoteText) { _, _ in
      scheduleProjectNoteAutoSave()
    }
    .onDisappear {
      cancelPendingTaskOpen()
      flushProjectNoteOnDisappear()
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

  private var projectNoteSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topTrailing) {
        LinkedTextEditor(
          text: $projectNoteText,
          measuredHeight: $projectNoteHeight,
          font: projectNoteNSFont,
          vaultRootURL: inlineEditorConfiguration?.vaultRootURL,
          allowsNewlines: true,
          lineHeightMultiple: 1.08,
          markdownPresentationMode: .livePreview,
          allowsMailMessageDrops: true
        )
        .frame(minHeight: projectNoteMinimumHeight)
        .frame(height: max(projectNoteMinimumHeight, projectNoteHeight))
        .timelineProjectNoteFieldBackground()

        if projectNoteErrorText != nil {
          Image(systemName: "exclamationmark.circle")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.red)
            .padding(8)
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
  }

  private var scrollContent: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          projectNoteSection

          Divider()

          taskListSection

          Color.clear
            .frame(height: Self.taskListBottomScrollReserve)
            .accessibilityHidden(true)
        }
      }
      .onAppear {
        scrollInitialFocusedTaskIntoView(with: proxy)
      }
      .onChange(of: session.focusedDraftAnchor) { _, anchor in
        scrollFocusedDraftIntoView(anchor, with: proxy)
      }
    }
  }

  @ViewBuilder
  private var taskListSection: some View {
    if visibleTasks.isEmpty && session.draftAnchor == nil {
      Text("할일 없음")
        .font(projectListEmptyStateFont)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    } else {
      let rows = visibleTaskRows
      let lastTaskID = rows.last?.task.id
      LazyVStack(alignment: .leading, spacing: 0) {
        if session.draftAnchor == .beginning {
          draftRow(anchor: .beginning)
        }

        ForEach(rows) { row in
          let task = row.task
          dropLine(for: task, placement: .before)
          VStack(alignment: .leading, spacing: 0) {
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
          }
          .id(TimelineProjectListScrollTarget.task(task.id))
          .background {
            if expandedTaskID == task.id {
              TimelineProjectListOutsideClickMonitor {
                requestExpandedTaskEditorClose()
              }
            } else if session.editingTaskID == task.id {
              TimelineProjectListOutsideClickMonitor {
                finishInlineTitleEditingFromOutside(for: task)
              }
            }
          }
          dropLine(for: task, placement: .after)
          if session.draftAnchor == .after(task.id) {
            draftRow(anchor: .after(task.id))
          }
          if task.id != lastTaskID {
            Divider()
              .padding(.leading, 32)
          }
        }
      }
      .padding(.vertical, 6)
    }
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
        taskTitleContent(task)
      } else {
        taskTitleContent(task)
          .contentShape(Rectangle())
          .onTapGesture(count: 2) {
            cancelPendingTaskOpen()
            startEditing(task)
          }
          .onTapGesture(count: 1) {
            scheduleTaskOpen(task)
          }
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
        if session.editingTaskID == task.id {
          inlineTitleEditor(for: task)
            .layoutPriority(1)
        } else {
          taskTitleLabel(for: task)
        }

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
        TimelineProjectListNotePreviewText(
          markdown: notePreviewText,
          presentation: presentation
        )
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func taskTitleLabel(for task: TimelineProjectListWindowSnapshot.Task) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Text(task.title)
        .font(projectListBodyFont)
        .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
        .lineLimit(3)
        .layoutPriority(1)

      taskMetadataIndicators(task.metadataIndicators, isCompleted: task.isCompleted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .layoutPriority(1)
  }

  @ViewBuilder
  private func taskMetadataIndicators(
    _ indicators: TimelineProjectListWindowSnapshot.Task.MetadataIndicators,
    isCompleted: Bool
  ) -> some View {
    if !indicators.isEmpty {
      HStack(spacing: 3) {
        if indicators.hasNote {
          Image(systemName: "note.text")
            .help("노트 있음")
        }
        if indicators.attachmentCount > 0 {
          Image(systemName: "paperclip")
            .help(
              indicators.attachmentCount > 1
                ? "첨부파일 \(indicators.attachmentCount)개" : "첨부파일 있음"
            )
        }
        if indicators.isRecurring {
          Image(systemName: "repeat")
            .help("반복 할일")
        }
      }
      .font(projectListDateFont.weight(.semibold))
      .foregroundStyle(Color.secondary.opacity(isCompleted ? 0.55 : 0.8))
      .imageScale(.small)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
    }
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
        closeRequestID: expandedTaskCloseRequestID,
        initialFocus: configuration.initialExpandedTaskID == task.id
          ? configuration.initialFocus
          : .none,
        onCancel: {
          completeExpandedTaskEditorClose(for: task.id)
        }
      )
      .id(task.id)
      .padding(.leading, 32)
      .padding(.trailing, 12)
      .padding(.bottom, 10)
    }
  }

  private func openTask(_ task: TimelineProjectListWindowSnapshot.Task) {
    cancelPendingTaskOpen()
    if inlineEditorConfiguration != nil {
      cancelDraftIfEmpty()
      if expandedTaskID == nil {
        expandedTaskID = task.id
      } else if expandedTaskID == task.id {
        return
      } else {
        requestExpandedTaskEditorClose(nextExpandedTaskID: task.id)
      }
      return
    }
    actions.onEditTask(task.id)
  }

  private func scheduleTaskOpen(_ task: TimelineProjectListWindowSnapshot.Task) {
    cancelPendingTaskOpen()
    pendingTaskOpenTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: Self.taskOpenDelayNanoseconds)
      guard !Task.isCancelled else { return }
      guard session.editingTaskID != task.id else { return }
      cancelInlineEditing()
      openTask(task)
    }
  }

  private func cancelPendingTaskOpen() {
    pendingTaskOpenTask?.cancel()
    pendingTaskOpenTask = nil
  }

  private func requestExpandedTaskEditorClose(nextExpandedTaskID: UUID? = nil) {
    guard expandedTaskID != nil else {
      expandedTaskID = nextExpandedTaskID
      return
    }
    pendingExpandedTaskIDAfterClose = nextExpandedTaskID
    expandedTaskCloseRequestID &+= 1
  }

  private func completeExpandedTaskEditorClose(for taskID: UUID) {
    guard expandedTaskID == taskID else { return }
    let nextTaskID = pendingExpandedTaskIDAfterClose
    pendingExpandedTaskIDAfterClose = nil
    guard let nextTaskID, visibleTasks.contains(where: { $0.id == nextTaskID }) else {
      expandedTaskID = nil
      return
    }
    expandedTaskID = nextTaskID == taskID ? nil : nextTaskID
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
      onEscape: {
        submitInlineTitle(for: task, createDraftBelow: false)
      }
    )
      .frame(height: 22)
      .disabled(isRenamingTask)
      .onExitCommand {
        submitInlineTitle(for: task, createDraftBelow: false)
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
        focusRingType: .none,
        onSubmit: {
          submitInlineDraft(anchor: anchor)
        },
        onEscape: cancelDraftIfEmpty
      )
      .frame(height: 22)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 9)
    .id(TimelineProjectListScrollTarget.draft(anchor))
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
    TimelineProjectListDisplayPreferenceStore.saveShowsCompletedTasks(
      showsCompletedTasks,
      for: snapshot.projectID
    )
  }

  private func toggleTaskNotes() {
    cancelInlineEditing()
    cancelDraftIfEmpty()
    showsTaskNotes.toggle()
    TimelineProjectListDisplayPreferenceStore.saveShowsTaskNotes(
      showsTaskNotes,
      for: snapshot.projectID
    )
  }

  private func requestProjectRename() {
    cancelInlineEditing()
    cancelDraftIfEmpty()
    actions.onRenameProject(snapshot.projectID, snapshot.title)
  }

  private func applyProjectNoteTextFromSnapshot(_ nextText: String) {
    guard !TimelineProjectNoteAutoSavePolicy.isDirty(
      currentText: projectNoteText,
      committedText: lastCommittedProjectNoteText
    ) else { return }
    let normalizedNextText = TimelineProjectNoteAutoSavePolicy.normalized(nextText)
    projectNoteAutoSaveTask?.cancel()
    projectNoteAutoSaveTask = nil
    projectNoteText = normalizedNextText
    lastCommittedProjectNoteText = normalizedNextText
    projectNoteErrorText = nil
  }

  @MainActor
  private func scheduleProjectNoteAutoSave() {
    guard TimelineProjectNoteAutoSavePolicy.isDirty(
      currentText: projectNoteText,
      committedText: lastCommittedProjectNoteText
    ) else {
      projectNoteAutoSaveTask?.cancel()
      projectNoteAutoSaveTask = nil
      projectNoteErrorText = nil
      return
    }
    projectNoteAutoSaveTask?.cancel()
    projectNoteAutoSaveTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: Self.projectNoteAutoSaveDelayNanoseconds)
      } catch {
        return
      }
      projectNoteAutoSaveTask = nil
      _ = await savePendingProjectNote()
    }
  }

  private func flushProjectNoteOnDisappear() {
    guard isSavingProjectNote || TimelineProjectNoteAutoSavePolicy.isDirty(
      currentText: projectNoteText,
      committedText: lastCommittedProjectNoteText
    ) else { return }
    projectNoteAutoSaveTask?.cancel()
    projectNoteAutoSaveTask = nil
    Task { @MainActor in
      _ = await savePendingProjectNote(afterCurrent: true)
    }
  }

  @MainActor
  private func savePendingProjectNote(afterCurrent: Bool = false) async -> Bool {
    guard !isSavingProjectNote else {
      if afterCurrent {
        saveProjectNoteAgainAfterCurrent = true
      } else {
        scheduleProjectNoteAutoSave()
      }
      return true
    }
    let noteText = TimelineProjectNoteAutoSavePolicy.normalized(projectNoteText)
    guard TimelineProjectNoteAutoSavePolicy.isDirty(
      currentText: noteText,
      committedText: lastCommittedProjectNoteText
    ) else {
      projectNoteErrorText = nil
      return true
    }
    isSavingProjectNote = true
    projectNoteErrorText = nil
    guard let savedNoteText = await actions.onSaveProjectNote(snapshot.projectID, noteText) else {
      isSavingProjectNote = false
      saveProjectNoteAgainAfterCurrent = false
      projectNoteErrorText = "저장 실패"
      return false
    }
    let committedText = TimelineProjectNoteAutoSavePolicy.normalized(savedNoteText)
    lastCommittedProjectNoteText = committedText
    if TimelineProjectNoteAutoSavePolicy.normalized(projectNoteText) == committedText {
      projectNoteText = committedText
    }
    isSavingProjectNote = false
    let shouldSaveAgain = saveProjectNoteAgainAfterCurrent
    saveProjectNoteAgainAfterCurrent = false
    if TimelineProjectNoteAutoSavePolicy.isDirty(
      currentText: projectNoteText,
      committedText: committedText
    ) {
      scheduleProjectNoteAutoSave()
    } else if shouldSaveAgain {
      return await savePendingProjectNote(afterCurrent: true)
    }
    return true
  }

  private func startEditing(_ task: TimelineProjectListWindowSnapshot.Task) {
    guard !isRenamingTask, !isCreatingTask else { return }
    cancelPendingTaskOpen()
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
    if expandedTaskID != nil {
      requestExpandedTaskEditorClose()
      return
    }
    if session.editingTaskID != nil {
      submitCurrentInlineTitle()
      return
    }
    if session.draftAnchor != nil {
      cancelDraftIfEmpty()
      return
    }
  }

  private func submitCurrentInlineTitle() {
    guard let editingTaskID = session.editingTaskID,
      let task = session.tasks.first(where: { $0.id == editingTaskID })
    else {
      cancelInlineEditing()
      return
    }
    submitInlineTitle(for: task, createDraftBelow: false)
  }

  private func finishInlineTitleEditingFromOutside(
    for task: TimelineProjectListWindowSnapshot.Task
  ) {
    guard session.editingTaskID == task.id else { return }
    let title = session.editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      cancelInlineEditing()
      return
    }
    submitInlineTitle(for: task, createDraftBelow: false)
  }

  private func submitInlineDraft(anchor _: TimelineProjectListDraftAnchor) {
    let title = session.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isRenamingTask else { return }
    let temporaryID = UUID()
    guard submitDraftOptimistically(temporaryID: temporaryID) != nil else { return }
    pendingCreateCount += 1

    writeQueue.enqueue {
      defer { pendingCreateCount = max(0, pendingCreateCount - 1) }
      guard let createdTask = await actions.onCreateTask(snapshot.projectID, title) else {
        updateSession { session in
          session.failOptimisticCreate(temporaryID: temporaryID)
        }
        return
      }

      MotionTransaction.withoutAnimation {
        updateSession { session in
          session.resolveOptimisticCreate(temporaryID: temporaryID, createdTask: createdTask)
        }
      }
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func focusDraft(_ anchor: TimelineProjectListDraftAnchor) {
    DispatchQueue.main.async {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        updateSession { session in
          session.focusedDraftAnchor = anchor
        }
      }
    }
  }

  private func scrollFocusedDraftIntoView(
    _ anchor: TimelineProjectListDraftAnchor?,
    with proxy: ScrollViewProxy
  ) {
    guard let anchor else { return }
    draftScrollRequestID &+= 1
    let requestID = draftScrollRequestID

    DispatchQueue.main.async {
      guard draftScrollRequestID == requestID else { return }
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        proxy.scrollTo(
          TimelineProjectListScrollTarget.draft(anchor),
          anchor: Self.focusedDraftScrollAnchor
        )
      }
    }
  }

  private func scrollInitialFocusedTaskIntoView(with proxy: ScrollViewProxy) {
    guard inlineEditorConfiguration?.initialFocus == .note,
      let taskID = inlineEditorConfiguration?.initialExpandedTaskID
    else {
      return
    }

    DispatchQueue.main.async {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        proxy.scrollTo(
          TimelineProjectListScrollTarget.task(taskID),
          anchor: Self.focusedTaskScrollAnchor
        )
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
    withAnimation(Self.taskInsertionAnimation) {
      updateSession { session in
        createdTask = session.submitDraftOptimistically(temporaryID: temporaryID)
      }
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

  private var projectListEmptyStateFont: Font {
    switch presentation {
    case .window:
      return .system(size: 14)
    case .embedded:
      return AppInputTypography.font(size: Self.embeddedTextSize)
    }
  }

  private var projectNoteNSFont: NSFont {
    switch presentation {
    case .window:
      return .systemFont(ofSize: 12)
    case .embedded:
      return AppInputTypography.nsFont(size: max(Self.embeddedTextSize - 1, 10))
    }
  }

  private var projectNoteMinimumHeight: CGFloat {
    switch presentation {
    case .window:
      return 78
    case .embedded:
      return 68
    }
  }

  private var visibleTasks: [TimelineProjectListWindowSnapshot.Task] {
    session.visibleTasks(showsCompletedTasks: showsCompletedTasks)
  }

  private var visibleTaskRows: [TimelineProjectListTaskRow] {
    visibleTasks.map { task in
      TimelineProjectListTaskRow(id: session.viewID(for: task.id), task: task)
    }
  }

  private var isCreatingTask: Bool {
    pendingCreateCount > 0
  }

  private var openTaskIDs: [UUID] {
    session.openTaskIDs
  }

  static let embeddedTextSize: CGFloat = 12 * 1.3 * 0.9
  private static let taskInsertionAnimation = Animation.easeOut(duration: 0.16)
  private static let taskListBottomScrollReserve: CGFloat = 72
  private static let focusedTaskScrollAnchor = UnitPoint(x: 0.5, y: 0.18)
  private static let focusedDraftScrollAnchor = UnitPoint(x: 0.5, y: 0.88)
  private static let projectNoteAutoSaveDelayNanoseconds: UInt64 = 650_000_000
  private static let taskOpenDelayNanoseconds: UInt64 = 240_000_000
}
