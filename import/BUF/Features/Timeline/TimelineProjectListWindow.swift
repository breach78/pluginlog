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
  @State private var temporarilyVisibleCompletedTaskIDs: Set<UUID> = []
  @State private var deletingTaskIDs: Set<UUID> = []
  @State private var movingTaskIDs: Set<UUID> = []
  @State private var showsCompletedTasks: Bool
  @State private var showsTaskNotes: Bool
  @State private var writeQueue = TimelineProjectListWriteQueue()
  @State private var expandedTaskID: UUID?
  @State private var expandedTaskCloseRequestID = 0
  @State private var pendingExpandedTaskIDAfterClose: UUID?
  @State private var taskEditFocusRequests: [UUID: Int] = [:]
  @State private var taskEditFocuses: [UUID: TimelineTaskEditInitialFocus] = [:]
  @State private var highlightedOutlineTaskID: UUID?
  @State private var outlineHighlightRequestID = 0
  @State private var expandedTaskAuxiliarySections: [UUID: Set<TaskEditAuxiliarySection>] = [:]
  @State private var projectNoteText: String
  @State private var projectOutlineDocument: ProjectOutlineDocument
  @State private var lastCommittedProjectNoteText: String
  @State private var projectOutlineNeedsSave = false
  @State private var projectNoteAutoSaveTask: Task<Void, Never>?
  @State private var isSavingProjectNote = false
  @State private var saveProjectNoteAgainAfterCurrent = false
  @State private var projectNoteErrorText: String?
  @State private var showsLowerTaskList = false
  @State private var draftScrollRequestID = 0
  @State private var pendingOutlineTaskBlockIDs: Set<UUID> = []
  @State private var movingOutlineBlockIDs: Set<UUID> = []
  @State private var recurringCompletionCounts: [UUID: Int] = [:]
  @State private var pendingOutlineAttachmentRename: ProjectOutlineInlineAttachment?
  @State private var isRenamingOutlineAttachment = false

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
    _expandedTaskID = State(initialValue: nil)
    _highlightedOutlineTaskID = State(initialValue: inlineEditorConfiguration?.initialExpandedTaskID)
    _outlineHighlightRequestID = State(
      initialValue: inlineEditorConfiguration?.initialFocusRequestID ?? 0
    )
    _projectNoteText = State(initialValue: snapshot.projectNoteText)
    _projectOutlineDocument = State(
      initialValue: Self.outlineDocument(
        from: snapshot.projectNoteText,
        knownTaskIDs: Set(snapshot.tasks.map(\.id))
      )
    )
    _lastCommittedProjectNoteText = State(
      initialValue: TimelineProjectNoteAutoSavePolicy.normalized(snapshot.projectNoteText)
    )
  }

  func replacing(
    snapshot: TimelineProjectListWindowSnapshot,
    inlineEditorConfiguration: TimelineProjectListInlineEditorConfiguration? = nil
  ) -> TimelineProjectListContent {
    sessionStore.applySnapshot(snapshot)
    return TimelineProjectListContent(
      snapshot: snapshot,
      presentation: presentation,
      actions: actions,
      onOpenProjectWindow: onOpenProjectWindow,
      onClosePanel: onClosePanel,
      inlineEditorConfiguration: inlineEditorConfiguration ?? self.inlineEditorConfiguration,
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
      pruneOutlineTaskBindings(knownTaskIDs: Set(nextSnapshot.tasks.map(\.id)))
      appendMissingOutlineTaskBlocksIfNeeded(tasks: nextSnapshot.tasks)
      guard let expandedTaskID else { return }
      if !nextSnapshot.tasks.contains(where: { $0.id == expandedTaskID }) {
        self.expandedTaskID = nil
      }
      taskEditFocusRequests = taskEditFocusRequests.filter { taskID, _ in
        nextSnapshot.tasks.contains(where: { $0.id == taskID })
      }
      taskEditFocuses = taskEditFocuses.filter { taskID, _ in
        nextSnapshot.tasks.contains(where: { $0.id == taskID })
      }
      expandedTaskAuxiliarySections = expandedTaskAuxiliarySections.filter { taskID, _ in
        nextSnapshot.tasks.contains(where: { $0.id == taskID })
      }
      recurringCompletionCounts = recurringCompletionCounts.filter { taskID, _ in
        nextSnapshot.tasks.contains(where: { $0.id == taskID })
      }
      temporarilyVisibleCompletedTaskIDs = temporarilyVisibleCompletedTaskIDs.filter { taskID in
        nextSnapshot.tasks.contains(where: { $0.id == taskID })
      }
    }
    .onChange(of: inlineEditorConfiguration?.initialFocusRequestID) { _, _ in
      highlightInitialTaskIfNeeded()
    }
    .onChange(of: inlineEditorConfiguration?.initialExpandedTaskID) { _, _ in
      highlightInitialTaskIfNeeded()
    }
    .onChange(of: projectNoteText) { _, _ in
      scheduleProjectNoteAutoSave()
    }
    .onAppear {
      syncProjectOutlineDocumentAfterInitialPrune()
      appendMissingOutlineTaskBlocksIfNeeded(tasks: session.tasks)
    }
    .onDisappear {
      flushProjectNoteOnDisappear()
    }
    .sheet(item: $pendingOutlineAttachmentRename) { attachment in
      WorkspaceRenameAttachmentSheetContent(
        originalNameStem: TaskEditAttachmentService.editableFilenameStem(
          for: attachment.taskEditAttachment
        ),
        fixedExtension: attachment.fileURL.pathExtension.isEmpty
          ? nil
          : attachment.fileURL.pathExtension,
        isRenaming: isRenamingOutlineAttachment,
        onSubmit: { name in
          renameOutlineAttachment(attachment, rawStem: name)
        },
        onCancel: {
          pendingOutlineAttachmentRename = nil
        }
      )
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

      Text("\(visibleTasks.count)")
        .font(projectListCountFont)
        .foregroundStyle(.secondary)

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
    .padding(.horizontal, 9)
    .padding(.vertical, 14)
  }

  private var projectNoteSection: some View {
    ZStack(alignment: .topTrailing) {
      ProjectOutlinerView(
        document: projectOutlineDocumentBinding,
        tasks: session.tasks,
        projectTitle: snapshot.title,
        projectColor: projectColor,
        showsCompletedTasks: showsCompletedTasks,
        temporarilyVisibleCompletedTaskIDs: temporarilyVisibleCompletedTaskIDs,
        pendingTaskBlockIDs: pendingOutlineTaskBlockIDs,
        recurringCompletionCounts: recurringCompletionCounts,
        highlightedTaskID: highlightedOutlineTaskID,
        highlightRequestID: outlineHighlightRequestID,
        moveOptions: actions.moveOptions().filter { $0.id != snapshot.projectID },
        taskEditConfiguration: inlineEditorConfiguration,
        onCreateTaskBlock: createOutlineTaskBlock,
        onRenameTask: renameOutlineTask,
        onToggleTaskCompletion: toggleTaskCompletion,
        onDeleteTaskBlock: deleteOutlineTaskBlock,
        onDeleteTask: deleteOutlineTask,
        onOpenTask: openOutlineTask,
        onOpenTaskSection: openOutlineTaskSection,
        onImportAttachmentFiles: importOutlineAttachmentFiles,
        onOpenAttachment: openOutlineAttachment,
        onRenameAttachment: { attachment in
          pendingOutlineAttachmentRename = attachment
        },
        onDeleteAttachment: deleteOutlineAttachment,
        onMoveBlockToProject: moveOutlineBlockToProject
      )
      .timelineProjectNoteFieldBackground()

      if projectNoteErrorText != nil {
        Image(systemName: "exclamationmark.circle")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.red)
          .padding(8)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
  }

  private var projectOutlineDocumentBinding: Binding<ProjectOutlineDocument> {
    Binding(
      get: { projectOutlineDocument },
      set: { nextDocument in
        projectOutlineDocument = nextDocument
        markProjectOutlineChanged()
      }
    )
  }

  private var scrollContent: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          projectNoteSection
        }
      }
      .onChange(of: session.focusedDraftAnchor) { _, anchor in
        scrollFocusedDraftIntoView(anchor, with: proxy)
      }
    }
  }

  private var lowerTaskListSection: some View {
    DisclosureGroup(isExpanded: $showsLowerTaskList) {
      taskListSection
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "checklist")
          .font(.system(size: 12, weight: .semibold))
        Text("할일 목록")
          .font(projectListCountFont)
        Text("\(visibleTasks.count)")
          .font(projectListCountFont)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
    }
    .disclosureGroupStyle(.automatic)
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
      let moveTargets = actions.moveOptions().filter { $0.id != snapshot.projectID }
      VStack(alignment: .leading, spacing: 0) {
        if session.draftAnchor == .beginning {
          draftRow(anchor: .beginning)
        }

        ForEach(rows) { row in
          let task = row.task
          dropLine(for: task, placement: .before)
          VStack(alignment: .leading, spacing: 0) {
            taskRow(task, moveTargets: moveTargets)
              .opacity(session.draggingTaskID == task.id || movingTaskIDs.contains(task.id) ? 0.42 : 1)
              .onDrag {
                updateSession { session in
                  session.beginDragging(taskID: task.id)
                }
                return TaskDragPayload.itemProvider(for: task.id)
              } preview: {
                TimelineProjectListHiddenDragPreview()
              }
              .draggable(TaskDragPayload.payloadString(for: task.id)) {
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
                let closingTaskID = task.id
                DispatchQueue.main.async {
                  guard expandedTaskID == closingTaskID else { return }
                  if session.editingTaskID == closingTaskID {
                    finishInlineTitleEditingFromOutside(for: task)
                  }
                  requestExpandedTaskEditorClose()
                }
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

  private func taskRow(
    _ task: TimelineProjectListWindowSnapshot.Task,
    moveTargets: [TimelineProjectMoveOption]
  ) -> some View {
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
      moveTaskMenu(for: task, targets: moveTargets)
      Divider()
      Button("삭제", role: .destructive) {
        deleteTask(task.id)
      }
      .disabled(deletingTaskIDs.contains(task.id))
    }
  }

  @ViewBuilder
  private func moveTaskMenu(
    for task: TimelineProjectListWindowSnapshot.Task,
    targets: [TimelineProjectMoveOption]
  ) -> some View {
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

        if session.editingTaskID == task.id,
          let configuration = inlineEditorConfiguration
        {
          taskEditAuxiliaryControls(for: task, configuration: configuration)
        } else if let dateText = task.dateText {
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
          .contentShape(Rectangle())
          .onTapGesture {
            openTaskForNoteEditing(task)
          }
      }
    }
  }

  private func taskEditAuxiliaryControls(
    for task: TimelineProjectListWindowSnapshot.Task,
    configuration: TimelineProjectListInlineEditorConfiguration
  ) -> some View {
    HStack(spacing: 5) {
      taskEditAuxiliaryButton(
        for: task,
        configuration: configuration,
        section: .attachments,
        systemImage: "paperclip",
        title: nil,
        help: "첨부파일"
      )

      taskEditAuxiliaryButton(
        for: task,
        configuration: configuration,
        section: .schedule,
        systemImage: task.dateText == nil ? "calendar.badge.clock" : nil,
        title: task.dateText,
        help: "날짜와 시간"
      )

      taskEditAuxiliaryButton(
        for: task,
        configuration: configuration,
        section: .recurrence,
        systemImage: "repeat",
        title: nil,
        help: "반복"
      )
    }
    .font(projectListDateFont.weight(.semibold))
    .imageScale(.small)
    .fixedSize(horizontal: true, vertical: false)
  }

  private func taskEditAuxiliaryButton(
    for task: TimelineProjectListWindowSnapshot.Task,
    configuration: TimelineProjectListInlineEditorConfiguration,
    section: TaskEditAuxiliarySection,
    systemImage: String?,
    title: String?,
    help: String
  ) -> some View {
    let hasValue = taskEditAuxiliarySectionHasValue(
      section,
      task: task,
      configuration: configuration
    )
    let isVisible = TaskEditAuxiliarySectionVisibilityPolicy.isVisible(
      section,
      expandedSections: expandedTaskAuxiliarySectionsValue(for: task, configuration: configuration),
      hasValue: hasValue
    )
    return Button {
      toggleTaskEditAuxiliarySection(
        section,
        task: task,
        configuration: configuration,
        hasValue: hasValue
      )
    } label: {
      Group {
        if let title {
          Text(title)
            .lineLimit(1)
        } else if let systemImage {
          Image(systemName: systemImage)
        } else {
          EmptyView()
        }
      }
      .foregroundStyle(isVisible ? projectColor.opacity(0.9) : Color.secondary.opacity(0.72))
      .padding(.horizontal, title == nil ? 0 : 4)
      .frame(minWidth: title == nil ? 22 : 0, minHeight: 20)
      .background(
        RoundedRectangle(cornerRadius: 5)
          .fill(isVisible ? projectColor.opacity(0.08) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private func expandedTaskAuxiliarySectionsBinding(
    for task: TimelineProjectListWindowSnapshot.Task,
    configuration: TimelineProjectListInlineEditorConfiguration
  ) -> Binding<Set<TaskEditAuxiliarySection>> {
    Binding(
      get: {
        expandedTaskAuxiliarySectionsValue(for: task, configuration: configuration)
      },
      set: { nextSections in
        expandedTaskAuxiliarySections[task.id] = nextSections
      }
    )
  }

  private func expandedTaskAuxiliarySectionsValue(
    for task: TimelineProjectListWindowSnapshot.Task,
    configuration: TimelineProjectListInlineEditorConfiguration
  ) -> Set<TaskEditAuxiliarySection> {
    expandedTaskAuxiliarySections[task.id]
      ?? initialTaskAuxiliarySections(for: task, configuration: configuration)
  }

  private func toggleTaskEditAuxiliarySection(
    _ section: TaskEditAuxiliarySection,
    task: TimelineProjectListWindowSnapshot.Task,
    configuration: TimelineProjectListInlineEditorConfiguration,
    hasValue: Bool
  ) {
    expandedTaskAuxiliarySections[task.id] =
      TaskEditAuxiliarySectionVisibilityPolicy.toggledSections(
        expandedTaskAuxiliarySectionsValue(for: task, configuration: configuration),
        section: section,
        hasValue: hasValue
      )
  }

  private func initialTaskAuxiliarySections(
    for task: TimelineProjectListWindowSnapshot.Task,
    configuration: TimelineProjectListInlineEditorConfiguration
  ) -> Set<TaskEditAuxiliarySection> {
    let fields = configuration.initialFields(task)
    let attachments = TaskEditAttachmentService.attachments(
      in: fields.noteText,
      vaultRootURL: configuration.vaultRootURL
    )
    return TaskEditAuxiliarySectionVisibilityPolicy.initialExpandedSections(
      hasAttachments: !attachments.isEmpty || task.metadataIndicators.attachmentCount > 0,
      hasDate: fields.day != nil || task.dateText != nil,
      hasTime: fields.timeMinutes != nil,
      durationMinutes: TimelineTaskEditDurationPolicy.savedDuration(
        hasDate: fields.day != nil,
        hasTime: fields.timeMinutes != nil,
        durationMinutes: fields.durationMinutes
      ),
      recurrenceRuleRaw: fields.recurrenceRuleRaw
    )
  }

  private func taskEditAuxiliarySectionHasValue(
    _ section: TaskEditAuxiliarySection,
    task: TimelineProjectListWindowSnapshot.Task,
    configuration: TimelineProjectListInlineEditorConfiguration
  ) -> Bool {
    let fields = configuration.initialFields(task)
    switch section {
    case .attachments:
      return task.metadataIndicators.attachmentCount > 0
        || !TaskEditAttachmentService.attachments(
          in: fields.noteText,
          vaultRootURL: configuration.vaultRootURL
        ).isEmpty
    case .schedule:
      let duration = TimelineTaskEditDurationPolicy.savedDuration(
        hasDate: fields.day != nil,
        hasTime: fields.timeMinutes != nil,
        durationMinutes: fields.durationMinutes
      )
      return task.dateText != nil
        || fields.day != nil
        || fields.timeMinutes != nil
        || duration != nil
    case .recurrence:
      return task.metadataIndicators.isRecurring
        || !(fields.recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ?? true)
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
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture(count: 2)
        .onEnded {
          openTaskForTitleEditing(task)
        }
        .exclusively(
          before: TapGesture()
            .onEnded {
              openTaskForNoteEditing(task)
            }
        )
    )
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
        dragTaskID: task.id,
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
        expandedAuxiliarySections: expandedTaskAuxiliarySectionsBinding(
          for: task,
          configuration: configuration
        ),
        closeRequestID: expandedTaskCloseRequestID,
        initialFocus: taskEditFocuses[task.id]
          ?? (
            configuration.initialExpandedTaskID == task.id
              ? configuration.initialFocus
              : .none
          ),
        focusRequestID: taskEditFocusRequests[task.id]
          ?? (
            configuration.initialExpandedTaskID == task.id
              ? configuration.initialFocusRequestID
              : 0
          ),
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
    openTask(task, focus: .note)
  }

  private func openTask(
    _ task: TimelineProjectListWindowSnapshot.Task,
    focus: TimelineTaskEditInitialFocus
  ) {
    if inlineEditorConfiguration != nil {
      cancelDraftIfEmpty()
      requestOutlineTaskHighlight(task.id)
      return
    }
    actions.onEditTask(task.id)
  }

  private func openTaskForTitleEditing(_ task: TimelineProjectListWindowSnapshot.Task) {
    openTask(task, focus: .title)
    if inlineEditorConfiguration != nil {
      startEditing(task)
    }
  }

  private func openTaskForNoteEditing(_ task: TimelineProjectListWindowSnapshot.Task) {
    cancelInlineEditing()
    openTask(task, focus: .note)
  }

  private func requestExpandedTaskEditorClose(nextExpandedTaskID: UUID? = nil) {
    guard expandedTaskID != nil else {
      expandedTaskID = nextExpandedTaskID
      return
    }
    pendingExpandedTaskIDAfterClose = nextExpandedTaskID
    expandedTaskCloseRequestID &+= 1
  }

  private func switchExpandedTaskEditor(to taskID: UUID) {
    if let currentTaskID = expandedTaskID {
      expandedTaskAuxiliarySections.removeValue(forKey: currentTaskID)
      taskEditFocusRequests.removeValue(forKey: currentTaskID)
      taskEditFocuses.removeValue(forKey: currentTaskID)
    }
    pendingExpandedTaskIDAfterClose = nil
    expandedTaskID = taskID
  }

  private func completeExpandedTaskEditorClose(for taskID: UUID) {
    guard expandedTaskID == taskID else { return }
    expandedTaskAuxiliarySections.removeValue(forKey: taskID)
    let nextTaskID = pendingExpandedTaskIDAfterClose
    pendingExpandedTaskIDAfterClose = nil
    guard let nextTaskID, visibleTasks.contains(where: { $0.id == nextTaskID }) else {
      taskEditFocusRequests.removeValue(forKey: taskID)
      taskEditFocuses.removeValue(forKey: taskID)
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
        onEscape: cancelDraftIfEmpty,
        onTab: {
          submitInlineDraftAndOpenNote(anchor: anchor)
        }
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
    let wasRecurring = session.tasks.first(where: { $0.id == taskID })?.metadataIndicators.isRecurring == true
    completingTaskIDs.insert(taskID)
    Task { @MainActor in
      let didToggle = await actions.onToggleTaskCompletion(taskID, isCompleted)
      completingTaskIDs.remove(taskID)
      guard didToggle else { return }
      let nextIsCompleted = TimelineTaskCompletionTogglePolicy.nextIsCompleted(
        currentIsCompleted: isCompleted
      )
      setTaskCompletion(taskID, isCompleted: nextIsCompleted)
      updateTemporaryCompletedVisibility(taskID: taskID, isCompleted: nextIsCompleted)
      if wasRecurring && nextIsCompleted {
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          recurringCompletionCounts[taskID, default: 0] += 1
          setTaskCompletion(taskID, isCompleted: false)
        }
      }
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
      removeOutlineTaskBlock(for: taskID)
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

  private func moveOutlineBlockToProject(_ blockID: UUID, targetProjectID: UUID) {
    guard targetProjectID != snapshot.projectID else { return }
    guard !movingOutlineBlockIDs.contains(blockID) else { return }
    guard let blocks = ProjectOutlineMutationEngine.normalizedSubtree(
      blockID: blockID,
      in: projectOutlineDocument
    ) else {
      return
    }

    let taskIDs = uniqueTaskIDs(in: blocks)
    cancelInlineEditing()
    cancelDraftIfEmpty()
    movingOutlineBlockIDs.insert(blockID)

    Task { @MainActor in
      defer { movingOutlineBlockIDs.remove(blockID) }

      guard ProjectOutlineMutationEngine.removeSubtree(
        blockID: blockID,
        from: &projectOutlineDocument
      ) != nil else {
        projectNoteErrorText = "이동 실패"
        return
      }
      markProjectOutlineChanged()

      guard await savePendingProjectNote() else {
        ProjectOutlineMutationEngine.appendNormalizedSubtree(blocks, to: &projectOutlineDocument)
        markProjectOutlineChanged()
        projectNoteErrorText = "이동 실패"
        return
      }

      for taskID in taskIDs {
        let didMoveTask = await actions.onMoveTask(snapshot.projectID, taskID, targetProjectID)
        guard didMoveTask else {
          ProjectOutlineMutationEngine.appendNormalizedSubtree(blocks, to: &projectOutlineDocument)
          markProjectOutlineChanged()
          _ = await savePendingProjectNote()
          projectNoteErrorText = "이동 실패"
          return
        }
      }

      let didAppend = await actions.onAppendProjectOutlineBlocks(targetProjectID, blocks)
      guard didAppend else {
        projectNoteErrorText = "이동 실패"
        return
      }

      for taskID in taskIDs {
        removeTaskFromWindow(taskID)
      }
      enqueueTaskOrderSave(registerUndo: false)
      projectNoteErrorText = nil
    }
  }

  private func uniqueTaskIDs(in blocks: [ProjectOutlineBlock]) -> [UUID] {
    var seen = Set<UUID>()
    var taskIDs: [UUID] = []
    for taskID in blocks.compactMap({ $0.taskBinding?.taskID }) where seen.insert(taskID).inserted {
      taskIDs.append(taskID)
    }
    return taskIDs
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

  private func updateTemporaryCompletedVisibility(taskID: UUID, isCompleted: Bool) {
    guard isCompleted, !showsCompletedTasks else {
      temporarilyVisibleCompletedTaskIDs.remove(taskID)
      return
    }
    temporarilyVisibleCompletedTaskIDs.insert(taskID)
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard session.tasks.first(where: { $0.id == taskID })?.isCompleted == true else {
        temporarilyVisibleCompletedTaskIDs.remove(taskID)
        return
      }
      temporarilyVisibleCompletedTaskIDs.remove(taskID)
    }
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
    let committedBeforeUpdate = lastCommittedProjectNoteText
    projectNoteAutoSaveTask?.cancel()
    projectNoteAutoSaveTask = nil
    if projectNoteText != normalizedNextText {
      projectNoteText = normalizedNextText
    }
    if !projectOutlineNeedsSave,
      committedBeforeUpdate != normalizedNextText
    {
      projectOutlineDocument = Self.outlineDocument(
        from: normalizedNextText,
        knownTaskIDs: Set(session.tasks.map(\.id))
      )
    }
    lastCommittedProjectNoteText = normalizedNextText
    projectNoteErrorText = nil
  }

  private func markProjectOutlineChanged() {
    projectOutlineNeedsSave = true
    scheduleProjectNoteAutoSave()
  }

  private func syncProjectOutlineDocumentAfterInitialPrune() {
    guard projectOutlineNeedsSave else { return }
    scheduleProjectNoteAutoSave()
  }

  @MainActor
  private func scheduleProjectNoteAutoSave() {
    guard projectOutlineNeedsSave || TimelineProjectNoteAutoSavePolicy.isDirty(
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
    guard isSavingProjectNote || projectOutlineNeedsSave || TimelineProjectNoteAutoSavePolicy.isDirty(
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
    if validateOutlineTaskBindingsBeforeSave() {
      projectOutlineNeedsSave = true
    }
    if projectOutlineNeedsSave {
      projectNoteText = Self.markdown(from: projectOutlineDocument)
    }
    let noteText = TimelineProjectNoteAutoSavePolicy.normalized(projectNoteText)
    guard TimelineProjectNoteAutoSavePolicy.isDirty(
      currentText: noteText,
      committedText: lastCommittedProjectNoteText
    ) else {
      projectOutlineNeedsSave = false
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
    projectOutlineNeedsSave = false
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

  private func validateOutlineTaskBindingsBeforeSave() -> Bool {
    pruneOutlineTaskBindings(knownTaskIDs: Set(session.tasks.map(\.id)), scheduleSave: false)
  }

  private func appendMissingOutlineTaskBlocksIfNeeded(
    tasks: [TimelineProjectListWindowSnapshot.Task]
  ) {
    let appendableTasks = tasks.filter { !deletingTaskIDs.contains($0.id) }
    let didAppend = ProjectOutlineTaskListMigrationPolicy.appendMissingTaskBlocks(
      to: &projectOutlineDocument,
      taskIDs: appendableTasks.map(\.id)
    )
    guard didAppend else { return }
    markProjectOutlineChanged()
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

  private func createOutlineTaskBlock(_ blockID: UUID) {
    guard !isCreatingTask,
      let blockIndex = projectOutlineDocument.blocks.firstIndex(where: { $0.id == blockID })
    else {
      return
    }
    let title = projectOutlineDocument.blocks[blockIndex].text
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    pendingCreateCount += 1

    Task { @MainActor in
      pendingOutlineTaskBlockIDs.insert(blockID)
      defer {
        pendingCreateCount = max(0, pendingCreateCount - 1)
        pendingOutlineTaskBlockIDs.remove(blockID)
      }
      guard let createdTask = await actions.onCreateTask(snapshot.projectID, title) else {
        projectNoteErrorText = "할일 생성 실패"
        return
      }
      updateSession { session in
        session.insertCreatedTask(createdTask, after: nil)
      }
      guard let currentIndex = projectOutlineDocument.blocks.firstIndex(where: { $0.id == blockID })
      else {
        return
      }
      projectOutlineDocument.blocks[currentIndex].text = ""
      projectOutlineDocument.blocks[currentIndex].taskBinding = ProjectOutlineTaskBinding(
        taskID: createdTask.id,
        taskExternalIdentifier: nil
      )
      markProjectOutlineChanged()
      projectNoteErrorText = nil
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func importOutlineAttachmentFiles(
    blockID: UUID,
    sourceURLs: [URL],
    insertionOffset: Int
  ) {
    guard !sourceURLs.isEmpty else { return }
    guard let vaultRootURL = inlineEditorConfiguration?.vaultRootURL else {
      projectNoteErrorText = "첨부파일 저장 위치 없음"
      return
    }

    Task { @MainActor in
      do {
        let importedAttachments = try await Task.detached {
          try TaskEditAttachmentService.copyFilesToRawAssets(
            sourceURLs: sourceURLs,
            vaultRootURL: vaultRootURL
          )
        }.value
        let insertion = importedAttachments
          .map { ProjectOutlineAttachmentInlineCodec.markdownLink(for: ProjectOutlineInlineAttachment($0)) }
          .joined(separator: " ")
        guard !insertion.isEmpty,
          let blockIndex = projectOutlineDocument.blocks.firstIndex(where: { $0.id == blockID })
        else {
          return
        }
        let currentText = projectOutlineDocument.blocks[blockIndex].text
        projectOutlineDocument.blocks[blockIndex].text = ProjectOutlineTextInsertionPolicy.insert(
          insertion,
          into: currentText,
          utf16Offset: insertionOffset
        )
        markProjectOutlineChanged()
        projectNoteErrorText = nil
      } catch {
        projectNoteErrorText = error.localizedDescription
      }
    }
  }

  private func openOutlineAttachment(_ attachment: ProjectOutlineInlineAttachment) {
    NSWorkspace.shared.open(attachment.fileURL)
  }

  private func renameOutlineAttachment(
    _ attachment: ProjectOutlineInlineAttachment,
    rawStem: String
  ) {
    guard !isRenamingOutlineAttachment,
      let displayName = TaskEditAttachmentService.renamedDisplayName(
        for: attachment.taskEditAttachment,
        rawStem: rawStem
      )
    else {
      pendingOutlineAttachmentRename = nil
      return
    }
    isRenamingOutlineAttachment = true
    defer {
      isRenamingOutlineAttachment = false
      pendingOutlineAttachmentRename = nil
    }
    let replacement = ProjectOutlineInlineAttachment(
      displayName: displayName,
      relativePath: attachment.relativePath,
      fileURL: attachment.fileURL
    )
    replaceOutlineAttachment(relativePath: attachment.relativePath, with: replacement)
  }

  private func deleteOutlineAttachment(_ attachment: ProjectOutlineInlineAttachment) {
    replaceOutlineAttachment(relativePath: attachment.relativePath, with: nil)
  }

  private func replaceOutlineAttachment(
    relativePath: String,
    with replacement: ProjectOutlineInlineAttachment?
  ) {
    for blockIndex in projectOutlineDocument.blocks.indices {
      let currentText = projectOutlineDocument.blocks[blockIndex].text
      let nextText = ProjectOutlineAttachmentInlineCodec.markdownByReplacingAllAttachments(
        in: currentText,
        matching: relativePath,
        with: replacement
      )
      if nextText != currentText {
        projectOutlineDocument.blocks[blockIndex].text = nextText
        markProjectOutlineChanged()
      }
    }
  }

  private func deleteRemovedOutlineAttachmentFiles(
    oldMarkdown: String,
    newMarkdown: String
  ) {
    guard let vaultRootURL = inlineEditorConfiguration?.vaultRootURL else { return }
    let removedAttachments = ProjectOutlineAttachmentCleanupPolicy.removedAttachments(
      oldMarkdown: oldMarkdown,
      newMarkdown: newMarkdown,
      vaultRootURL: vaultRootURL
    )
    guard !removedAttachments.isEmpty else { return }

    Task { @MainActor in
      for attachment in removedAttachments {
        do {
          try TaskEditAttachmentService.deleteAttachment(
            attachment.taskEditAttachment,
            vaultRootURL: vaultRootURL
          )
        } catch {
          projectNoteErrorText = error.localizedDescription
        }
      }
    }
  }

  private func renameOutlineTask(_ taskID: UUID, title: String) {
    guard !isRenamingTask else { return }
    isRenamingTask = true
    Task { @MainActor in
      defer { isRenamingTask = false }
      guard let updatedTask = await actions.onRenameTask(snapshot.projectID, taskID, title) else {
        projectNoteErrorText = "이름 변경 실패"
        return
      }
      replaceTask(updatedTask)
      projectNoteErrorText = nil
    }
  }

  private func deleteOutlineTaskBlock(_ blockID: UUID) {
    guard let block = projectOutlineDocument.blocks.first(where: { $0.id == blockID }),
      let taskID = block.taskBinding?.taskID
    else {
      _ = ProjectOutlineMutationEngine.deleteBlockReattachingChildren(
        id: blockID,
        in: &projectOutlineDocument
      )
      markProjectOutlineChanged()
      return
    }
    guard !deletingTaskIDs.contains(taskID) else { return }
    deletingTaskIDs.insert(taskID)
    Task { @MainActor in
      let didDelete = await actions.onDeleteTask(snapshot.projectID, taskID)
      deletingTaskIDs.remove(taskID)
      guard didDelete else { return }
      _ = ProjectOutlineMutationEngine.deleteBlockReattachingChildren(
        id: blockID,
        in: &projectOutlineDocument
      )
      markProjectOutlineChanged()
      removeTaskFromWindow(taskID)
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func deleteOutlineTask(_ taskID: UUID) {
    guard !deletingTaskIDs.contains(taskID) else { return }
    deletingTaskIDs.insert(taskID)
    Task { @MainActor in
      let didDelete = await actions.onDeleteTask(snapshot.projectID, taskID)
      deletingTaskIDs.remove(taskID)
      guard didDelete else { return }
      removeTaskFromWindow(taskID)
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func removeOutlineTaskBlock(for taskID: UUID) {
    guard let block = projectOutlineDocument.blocks.first(where: {
      $0.taskBinding?.taskID == taskID
    }) else {
      return
    }
    _ = ProjectOutlineMutationEngine.deleteBlockReattachingChildren(
      id: block.id,
      in: &projectOutlineDocument
    )
    markProjectOutlineChanged()
  }

  @discardableResult
  private func pruneOutlineTaskBindings(
    knownTaskIDs: Set<UUID>,
    scheduleSave: Bool = true
  ) -> Bool {
    let didPrune = ProjectOutlineTaskBindingPrunePolicy.pruneUnknownTaskBlocks(
      in: &projectOutlineDocument,
      knownTaskIDs: knownTaskIDs
    )
    if didPrune, scheduleSave {
      markProjectOutlineChanged()
    }
    return didPrune
  }

  private func openOutlineTask(_ taskID: UUID) {
    guard let task = session.tasks.first(where: { $0.id == taskID }) else { return }
    openTask(task, focus: .none)
  }

  private func openOutlineTaskSection(_ taskID: UUID, section: TaskEditAuxiliarySection) {
    guard let task = session.tasks.first(where: { $0.id == taskID }) else { return }
    if let configuration = inlineEditorConfiguration {
      var sections = expandedTaskAuxiliarySectionsValue(for: task, configuration: configuration)
      sections.insert(section)
      expandedTaskAuxiliarySections[taskID] = sections
    }
    openTask(task, focus: .none)
  }

  private func requestOutlineTaskHighlight(_ taskID: UUID) {
    highlightedOutlineTaskID = taskID
    outlineHighlightRequestID &+= 1
  }

  private func highlightInitialTaskIfNeeded() {
    guard let taskID = inlineEditorConfiguration?.initialExpandedTaskID else { return }
    highlightedOutlineTaskID = taskID
    outlineHighlightRequestID = inlineEditorConfiguration?.initialFocusRequestID
      ?? outlineHighlightRequestID + 1
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
    guard let create = beginInlineDraftCreate() else { return }

    writeQueue.enqueue {
      defer { pendingCreateCount = max(0, pendingCreateCount - 1) }
      guard let createdTask = await actions.onCreateTask(snapshot.projectID, create.title) else {
        updateSession { session in
          session.failOptimisticCreate(temporaryID: create.temporaryID)
        }
        return
      }

      MotionTransaction.withoutAnimation {
        updateSession { session in
          session.resolveOptimisticCreate(temporaryID: create.temporaryID, createdTask: createdTask)
        }
      }
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func submitInlineDraftAndOpenNote(anchor _: TimelineProjectListDraftAnchor) {
    guard let create = beginInlineDraftCreate() else { return }

    writeQueue.enqueue {
      defer { pendingCreateCount = max(0, pendingCreateCount - 1) }
      guard let createdTask = await actions.onCreateTask(snapshot.projectID, create.title) else {
        updateSession { session in
          session.failOptimisticCreate(temporaryID: create.temporaryID)
        }
        return
      }

      MotionTransaction.withoutAnimation {
        updateSession { session in
          session.resolveOptimisticCreate(temporaryID: create.temporaryID, createdTask: createdTask)
        }
      }
      openTask(createdTask, focus: .note)
      enqueueTaskOrderSave(registerUndo: false)
    }
  }

  private func beginInlineDraftCreate() -> (temporaryID: UUID, title: String)? {
    let title = session.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !isRenamingTask else { return nil }
    let temporaryID = UUID()
    guard submitDraftOptimistically(temporaryID: temporaryID) != nil else { return nil }
    pendingCreateCount += 1
    return (temporaryID, title)
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

  private static func outlineDocument(
    from markdown: String,
    knownTaskIDs: Set<UUID> = []
  ) -> ProjectOutlineDocument {
    var document = ProjectOutlineMarkdownCodec.document(from: markdown)
    ProjectOutlineTaskBindingPrunePolicy.pruneUnknownTaskBlocks(
      in: &document,
      knownTaskIDs: knownTaskIDs
    )
    if document.blocks.isEmpty {
      return ProjectOutlineDocument(blocks: [ProjectOutlineBlock(depth: 0, text: "")])
    }
    return document
  }

  private static func markdown(from document: ProjectOutlineDocument) -> String {
    if document.blocks.count == 1,
      let block = document.blocks.first,
      block.text.isEmpty,
      block.taskBinding == nil,
      !block.childrenCollapsed
    {
      return ""
    }
    return ProjectOutlineMarkdownCodec.markdown(from: document)
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
      return .systemFont(ofSize: 14)
    case .embedded:
      return AppInputTypography.nsFont(size: 15)
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
    session.visibleTasks(
      showsCompletedTasks: showsCompletedTasks,
      temporarilyVisibleCompletedTaskIDs: temporarilyVisibleCompletedTaskIDs
    )
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

  static let embeddedTextSize: CGFloat = 15
  private static let taskInsertionAnimation = Animation.easeOut(duration: 0.16)
  private static let taskListBottomScrollReserve: CGFloat = 72
  private static let focusedTaskScrollAnchor = UnitPoint(x: 0.5, y: 0.5)
  private static let focusedDraftScrollAnchor = UnitPoint(x: 0.5, y: 0.88)
  private static let projectNoteAutoSaveDelayNanoseconds: UInt64 = 650_000_000
}
