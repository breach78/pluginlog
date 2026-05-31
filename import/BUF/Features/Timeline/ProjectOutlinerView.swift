import SwiftUI
import UniformTypeIdentifiers

struct ProjectOutlinerView: View {
  @Binding var document: ProjectOutlineDocument

  let tasks: [TimelineProjectListWindowSnapshot.Task]
  let projectTitle: String
  let projectColor: Color
  let pendingTaskBlockIDs: Set<UUID>
  let recurringCompletionCounts: [UUID: Int]
  let onCreateTaskBlock: (UUID) -> Void
  let onRenameTask: (UUID, String) -> Void
  let onToggleTaskCompletion: (UUID, Bool) -> Void
  let onDeleteTaskBlock: (UUID) -> Void
  let onOpenTask: (UUID) -> Void
  let onOpenTaskSection: (UUID, TaskEditAuxiliarySection) -> Void

  @State private var focusedBlockID: UUID?
  @State private var zoomRootBlockID: UUID?
  @State private var blockToRevealAfterZoomOut: UUID?
  @State private var rowHeights: [UUID: CGFloat] = [:]
  @State private var draggingBlockID: UUID?
  @State private var dropIndicator: ProjectOutlineDropIndicator?

  private var tasksByID: [UUID: TimelineProjectListWindowSnapshot.Task] {
    Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
  }

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        zoomBreadcrumb
        if document.blocks.isEmpty {
          Button("첫 불릿 추가", systemImage: "plus") {
            let block = ProjectOutlineBlock(depth: 0, text: "")
            document.blocks = [block]
            focusedBlockID = block.id
          }
          .buttonStyle(.borderless)
          .padding(.horizontal, 18)
          .padding(.vertical, 16)
        } else {
          ForEach(visibleBlockIDs, id: \.self) { blockID in
            if let blockBinding = binding(for: blockID),
              let block = document.blocks.first(where: { $0.id == blockID })
            {
              ProjectOutlineRowView(
                block: blockBinding,
                task: block.taskBinding?.taskID.flatMap { tasksByID[$0] },
                projectColor: projectColor,
                isFocused: focusedBlockID == blockID,
                displayDepth: displayDepth(for: block),
                hidesMarker: zoomRootBlockID == blockID,
                isCreatingTask: pendingTaskBlockIDs.contains(blockID),
                recurringCompletionCount: block.taskBinding?.taskID.flatMap {
                  recurringCompletionCounts[$0]
                } ?? 0,
                hasChildren: hasChildren(blockID: blockID),
                dropPlacement: dropIndicator?.targetID == blockID ? dropIndicator?.placement : nil,
                measuredHeight: Binding(
                  get: { rowHeights[blockID] ?? 24 },
                  set: { rowHeights[blockID] = $0 }
                ),
                onCommand: { command in
                  handle(command, blockID: blockID)
                },
                onFocus: {
                  focusedBlockID = blockID
                },
                onDeleteBlock: {
                  deleteBlock(blockID: blockID)
                },
                onZoomIn: {
                  zoomIn(blockID: blockID)
                },
                onRenameTask: onRenameTask,
                onToggleTaskCompletion: onToggleTaskCompletion,
                onOpenTask: onOpenTask,
                onOpenTaskSection: onOpenTaskSection,
                onBeginDrag: {
                  draggingBlockID = blockID
                }
              )
              .id(blockID)
              .onDrop(
                of: [UTType.text.identifier],
                delegate: ProjectOutlineBlockDropDelegate(
                  targetID: blockID,
                  rowHeight: rowHeights[blockID] ?? 24,
                  focusRootID: zoomRootBlockID,
                  document: $document,
                  draggingBlockID: $draggingBlockID,
                  dropIndicator: $dropIndicator
                )
              )
            }
          }
        }
      }
      .padding(.vertical, 12)
      .transaction { transaction in
        transaction.animation = nil
      }
      .onChange(of: blockToRevealAfterZoomOut) { _, blockID in
        guard let blockID else { return }
        DispatchQueue.main.async {
          proxy.scrollTo(blockID, anchor: .center)
          blockToRevealAfterZoomOut = nil
        }
      }
      .onChange(of: document.blocks) { _, blocks in
        if let zoomRootBlockID, !blocks.contains(where: { $0.id == zoomRootBlockID }) {
          self.zoomRootBlockID = nil
        }
      }
    }
  }

  private var visibleBlockIDs: [UUID] {
    ProjectOutlineMutationEngine.visibleIndices(
      in: document,
      focusRootID: zoomRootBlockID
    )
    .map { document.blocks[$0].id }
  }

  private func binding(for blockID: UUID) -> Binding<ProjectOutlineBlock>? {
    guard document.blocks.contains(where: { $0.id == blockID }) else { return nil }
    return Binding(
      get: {
        document.blocks.first(where: { $0.id == blockID })
          ?? ProjectOutlineBlock(id: blockID, depth: 0, text: "")
      },
      set: { nextBlock in
        guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
          return
        }
        document.blocks[index] = nextBlock
      }
    )
  }

  private func hasChildren(blockID: UUID) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return false }
    return ProjectOutlineMutationEngine.hasChildren(at: index, in: document)
  }

  private func displayDepth(for block: ProjectOutlineBlock) -> Int {
    guard let zoomRootBlockID,
      let root = document.blocks.first(where: { $0.id == zoomRootBlockID })
    else {
      return block.depth
    }
    return max(0, block.depth - root.depth)
  }

  private func handle(_ command: ProjectOutlineTextCommand, blockID: UUID) {
    switch command {
    case .enter(let offset):
      handleEnter(blockID: blockID, offset: offset)
    case .tab:
      _ = ProjectOutlineMutationEngine.indentBlock(id: blockID, in: &document)
    case .shiftTab:
      guard !isDirectChildOfZoomRoot(blockID) else { return }
      _ = ProjectOutlineMutationEngine.outdentBlock(id: blockID, in: &document)
    case .backspaceAtStart:
      handleBackspaceAtStart(blockID: blockID)
    case .deleteAtEnd:
      _ = ProjectOutlineMutationEngine.deleteAtEnd(blockID: blockID, in: &document)
    case .commandEnter:
      handleCommandEnter(blockID: blockID)
    case .commandShiftUp:
      guard !isFirstVisibleChildOfZoomRoot(blockID) else { return }
      if ProjectOutlineMutationEngine.moveBlockUp(id: blockID, in: &document) {
        focusedBlockID = blockID
      }
    case .commandShiftDown:
      guard !isLastVisibleChildOfZoomRoot(blockID) else { return }
      if ProjectOutlineMutationEngine.moveBlockDown(id: blockID, in: &document) {
        focusedBlockID = blockID
      }
    case .commandUp, .commandDown:
      toggleFold(blockID: blockID)
    case .escape:
      focusedBlockID = nil
    case .convertToTask:
      convertBlockToPendingTask(blockID)
    case .zoomIn:
      zoomIn(blockID: blockID)
    case .zoomOut:
      zoomOutOneLevel()
    case .zoomHome:
      zoomHome()
    case .zoomPreviousSibling:
      zoomToSibling(previous: true)
    case .zoomNextSibling:
      zoomToSibling(previous: false)
    case .focusPrevious:
      focusAdjacentBlock(from: blockID, offset: -1)
    case .focusNext:
      focusAdjacentBlock(from: blockID, offset: 1)
    }
  }

  private func handleEnter(blockID: UUID, offset: Int) {
    guard let block = document.blocks.first(where: { $0.id == blockID }) else { return }
    if block.isTaskBlock {
      if block.taskBinding?.taskID == nil,
        !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        onCreateTaskBlock(blockID)
      }
      if let result = ProjectOutlineMutationEngine.insertSiblingAfterSubtree(
        blockID: blockID,
        in: &document
      ) {
        focusedBlockID = result.focusedBlockID
      }
      return
    }

    if let result = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: blockID,
      textOffset: offset,
      in: &document
    ) {
      focusedBlockID = result.focusedBlockID
    }
  }

  private func convertBlockToPendingTask(_ blockID: UUID) {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      !document.blocks[index].isTaskBlock
    else {
      return
    }
    document.blocks[index].text = ""
    document.blocks[index].taskBinding = ProjectOutlineTaskBinding(
      taskID: nil,
      taskExternalIdentifier: nil
    )
    focusedBlockID = blockID
  }

  private func handleCommandEnter(blockID: UUID) {
    guard let block = document.blocks.first(where: { $0.id == blockID }) else { return }
    if let taskID = block.taskBinding?.taskID, let task = tasksByID[taskID] {
      onToggleTaskCompletion(taskID, task.isCompleted)
    } else {
      onCreateTaskBlock(blockID)
    }
  }

  private func handleBackspaceAtStart(blockID: UUID) {
    _ = ProjectOutlineMutationEngine.backspaceAtStart(blockID: blockID, in: &document)
  }

  private func deleteBlock(blockID: UUID) {
    guard blockID != zoomRootBlockID else { return }
    guard let block = document.blocks.first(where: { $0.id == blockID }) else { return }
    if block.isTaskBlock {
      onDeleteTaskBlock(blockID)
    } else {
      _ = ProjectOutlineMutationEngine.deleteBlockReattachingChildren(
        id: blockID,
        in: &document
      )
    }
  }

  private func toggleFold(blockID: UUID) {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      ProjectOutlineMutationEngine.hasChildren(at: index, in: document)
    else {
      return
    }
    document.blocks[index].childrenCollapsed.toggle()
  }

  @ViewBuilder
  private var zoomBreadcrumb: some View {
    if let currentZoomRootID = zoomRootBlockID,
      let root = document.blocks.first(where: { $0.id == currentZoomRootID })
    {
      let ancestors = ProjectOutlineMutationEngine.ancestorIDs(
        for: currentZoomRootID,
        in: document
      )
      HStack(spacing: 5) {
        Button(projectTitle) {
          zoomHome()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.secondary)

        ForEach(ancestors, id: \.self) { ancestorID in
          Text("›")
            .foregroundStyle(Color.secondary.opacity(0.5))
          Button(blockTitle(for: ancestorID)) {
            zoomRootBlockID = ancestorID
            focusedBlockID = ancestorID
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.secondary)
        }

        Text("›")
          .foregroundStyle(Color.secondary.opacity(0.5))
        Text(blockDisplayTitle(root))
          .lineLimit(1)
          .foregroundStyle(Color.primary.opacity(0.72))
      }
      .font(.system(size: 12, weight: .semibold))
      .padding(.horizontal, 18)
      .padding(.bottom, 8)
    }
  }

  private func blockTitle(for blockID: UUID) -> String {
    guard let block = document.blocks.first(where: { $0.id == blockID }) else {
      return "블록"
    }
    return blockDisplayTitle(block)
  }

  private func blockDisplayTitle(_ block: ProjectOutlineBlock) -> String {
    if let taskID = block.taskBinding?.taskID,
      let task = tasksByID[taskID],
      !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return task.title
    }
    let title = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? "빈 블록" : String(title.prefix(20))
  }

  private func zoomIn(blockID: UUID) {
    guard ProjectOutlineMutationEngine.hasChildren(blockID: blockID, in: document) else {
      focusedBlockID = blockID
      return
    }
    zoomRootBlockID = blockID
    focusedBlockID = blockID
  }

  private func zoomOutOneLevel() {
    guard let zoomRootBlockID else { return }
    blockToRevealAfterZoomOut = zoomRootBlockID
    self.zoomRootBlockID = ProjectOutlineMutationEngine.parentID(
      for: zoomRootBlockID,
      in: document
    )
    focusedBlockID = zoomRootBlockID
  }

  private func zoomHome() {
    guard let zoomRootBlockID else { return }
    blockToRevealAfterZoomOut = zoomRootBlockID
    self.zoomRootBlockID = nil
    focusedBlockID = zoomRootBlockID
  }

  private func zoomToSibling(previous: Bool) {
    guard let zoomRootBlockID else { return }
    let nextID = previous
      ? ProjectOutlineMutationEngine.previousSiblingID(for: zoomRootBlockID, in: document)
      : ProjectOutlineMutationEngine.nextSiblingID(for: zoomRootBlockID, in: document)
    guard let nextID else { return }
    self.zoomRootBlockID = nextID
    focusedBlockID = nextID
  }

  private func focusAdjacentBlock(from blockID: UUID, offset: Int) {
    guard let currentPosition = visibleBlockIDs.firstIndex(of: blockID) else { return }
    let nextPosition = currentPosition + offset
    guard visibleBlockIDs.indices.contains(nextPosition) else { return }
    focusedBlockID = visibleBlockIDs[nextPosition]
  }

  private func isDirectChildOfZoomRoot(_ blockID: UUID) -> Bool {
    guard let zoomRootBlockID else { return false }
    return ProjectOutlineMutationEngine.parentID(for: blockID, in: document) == zoomRootBlockID
  }

  private func isFirstVisibleChildOfZoomRoot(_ blockID: UUID) -> Bool {
    guard let zoomRootBlockID,
      let rootIndex = document.blocks.firstIndex(where: { $0.id == zoomRootBlockID })
    else {
      return false
    }
    let visible = ProjectOutlineMutationEngine.visibleIndices(
      in: document,
      focusRootID: zoomRootBlockID
    )
    guard let firstChildIndex = visible.dropFirst().first else { return false }
    return document.blocks[rootIndex].depth + 1 == document.blocks[firstChildIndex].depth
      && document.blocks[firstChildIndex].id == blockID
  }

  private func isLastVisibleChildOfZoomRoot(_ blockID: UUID) -> Bool {
    guard let zoomRootBlockID,
      let rootIndex = document.blocks.firstIndex(where: { $0.id == zoomRootBlockID })
    else {
      return false
    }
    let visible = ProjectOutlineMutationEngine.visibleIndices(
      in: document,
      focusRootID: zoomRootBlockID
    )
    guard let lastChildIndex = visible.dropFirst().last else { return false }
    return document.blocks[rootIndex].depth + 1 == document.blocks[lastChildIndex].depth
      && document.blocks[lastChildIndex].id == blockID
  }
}

private struct ProjectOutlineRowView: View {
  @Binding var block: ProjectOutlineBlock
  let task: TimelineProjectListWindowSnapshot.Task?
  let projectColor: Color
  let isFocused: Bool
  let displayDepth: Int
  let hidesMarker: Bool
  let isCreatingTask: Bool
  let recurringCompletionCount: Int
  let hasChildren: Bool
  let dropPlacement: ProjectOutlineDropPlacement?
  @Binding var measuredHeight: CGFloat
  let onCommand: (ProjectOutlineTextCommand) -> Void
  let onFocus: () -> Void
  let onDeleteBlock: () -> Void
  let onZoomIn: () -> Void
  let onRenameTask: (UUID, String) -> Void
  let onToggleTaskCompletion: (UUID, Bool) -> Void
  let onOpenTask: (UUID) -> Void
  let onOpenTaskSection: (UUID, TaskEditAuxiliarySection) -> Void
  let onBeginDrag: () -> Void

  @State private var taskTitleDraft = ""
  @State private var taskTitleDraftTaskID: UUID?

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      HStack(spacing: 0) {
        ForEach(0..<displayDepth, id: \.self) { _ in
          Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 9.5)
        }
      }
      .frame(height: max(24, measuredHeight))

      if !hidesMarker {
        marker
      }

      if block.isTaskBlock {
        taskContent(task)
      } else {
        ProjectOutlineTextEditor(
          text: $block.text,
          measuredHeight: $measuredHeight,
          isFocused: isFocused,
          font: projectOutlinerNSFont,
          onCommand: onCommand,
          onFocus: onFocus
        )
        .frame(minHeight: 24)
        .frame(height: measuredHeight)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 3)
    .overlay(alignment: dropPlacement == .before ? .topLeading : .bottomLeading) {
      if dropPlacement == .before || dropPlacement == .after {
        ProjectOutlineDropIndicatorLine()
          .padding(.leading, CGFloat(displayDepth) * 20 + 40)
          .padding(.trailing, 18)
      }
    }
    .overlay(alignment: .leading) {
      if dropPlacement == .child {
        ProjectOutlineDropIndicatorLine()
          .padding(.leading, CGFloat(displayDepth + 1) * 20 + 40)
          .padding(.trailing, 18)
      }
    }
    .contentShape(Rectangle())
    .contextMenu {
      if hasChildren {
        Button("줌인") {
          onZoomIn()
        }
      }
      if let task {
        Button("편집 열기") {
          onOpenTask(task.id)
        }
        Divider()
      }
      Button("블록 삭제", role: .destructive) {
        onDeleteBlock()
      }
    }
  }

  private var marker: some View {
    Group {
      if block.isTaskBlock {
        Button {
          if let task {
            onToggleTaskCompletion(task.id, task.isCompleted)
          }
        } label: {
          Image(systemName: task?.isCompleted == true ? "checkmark.square.fill" : "square")
            .font(.system(size: 14))
            .foregroundStyle(task?.isCompleted == true ? projectColor : Color.secondary)
            .frame(width: 18, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(task == nil || isCreatingTask)
      } else {
        Button {
          if hasChildren {
            onZoomIn()
          } else {
            onFocus()
          }
        } label: {
          Circle()
            .fill(hasChildren && !block.childrenCollapsed ? Color.clear : Color.secondary.opacity(0.28))
            .overlay(Circle().stroke(Color.secondary.opacity(0.28), lineWidth: 1))
            .frame(width: hasChildren ? 7 : 6, height: hasChildren ? 7 : 6)
            .frame(width: 18, height: 22)
        }
        .buttonStyle(.plain)
      }
    }
    .onDrag {
      onBeginDrag()
      return NSItemProvider(object: block.id.uuidString as NSString)
    } preview: {
      Color.clear
        .frame(width: 1, height: 1)
    }
  }

  private func taskContent(_ task: TimelineProjectListWindowSnapshot.Task?) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if let task {
          ProjectOutlineTextEditor(
            text: taskTitleBinding(for: task),
            measuredHeight: $measuredHeight,
            isFocused: isFocused,
            font: projectOutlinerNSFont,
            onCommand: { command in
              submitTaskTitle(task)
              onCommand(command)
            },
            onFocus: onFocus,
            onBlur: {
              submitTaskTitle(task)
            }
          )
          .frame(minHeight: 24)
          .frame(height: measuredHeight)
          .opacity(task.isCompleted ? 0.55 : 1)
            .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
            .strikethrough(task.isCompleted)
            .disabled(isCreatingTask)
        } else {
          if block.taskBinding?.taskID == nil {
            ProjectOutlineTextEditor(
              text: $block.text,
              measuredHeight: $measuredHeight,
              isFocused: isFocused,
              font: projectOutlinerNSFont,
              onCommand: onCommand,
              onFocus: onFocus,
              onBlur: commitPendingTaskIfNeeded
            )
            .frame(minHeight: 24)
            .frame(height: measuredHeight)
              .disabled(isCreatingTask)
          } else {
            Text("불러오는 중...")
              .font(projectOutlinerFont)
              .foregroundStyle(Color.secondary)
          }
        }

        Spacer(minLength: 8)

        if let task {
          scheduleChip(for: task)

          recurrenceChip(for: task)
        }
      }
    }
    .frame(minHeight: 24)
    .onAppear {
      if let task, taskTitleDraftTaskID != task.id {
        taskTitleDraftTaskID = task.id
        taskTitleDraft = task.title
      }
    }
    .onChange(of: task?.title) { _, title in
      guard !isFocused, let task, let title else { return }
      taskTitleDraftTaskID = task.id
      taskTitleDraft = title
    }
  }

  private func scheduleChip(for task: TimelineProjectListWindowSnapshot.Task) -> some View {
    Button {
      onOpenTaskSection(task.id, .schedule)
    } label: {
      if let dateText = task.dateText {
        Text(dateText)
          .lineLimit(1)
      } else {
        Image(systemName: "calendar.badge.clock")
      }
    }
    .buttonStyle(.plain)
    .font(projectOutlinerChipFont)
    .foregroundStyle(task.dateText == nil ? Color.secondary.opacity(0.7) : Color.secondary)
    .padding(.horizontal, task.dateText == nil ? 0 : 4)
    .frame(minWidth: task.dateText == nil ? 20 : 0, minHeight: 20)
    .background(
      RoundedRectangle(cornerRadius: 5)
        .fill(task.dateText == nil ? Color.clear : projectColor.opacity(0.08))
    )
    .help("날짜와 시간")
  }

  private func recurrenceChip(for task: TimelineProjectListWindowSnapshot.Task) -> some View {
    HStack(spacing: 3) {
      if recurringCompletionCount > 0 {
        Text("\(recurringCompletionCount)")
          .foregroundStyle(projectColor)
          .monospacedDigit()
      }
      Button {
        onOpenTaskSection(task.id, .recurrence)
      } label: {
        Image(systemName: "repeat")
      }
      .buttonStyle(.plain)
      .foregroundStyle(
        task.metadataIndicators.isRecurring ? Color.secondary : Color.secondary.opacity(0.45)
      )
      .help("반복")
    }
    .font(projectOutlinerChipFont)
  }

  private func taskTitleBinding(for task: TimelineProjectListWindowSnapshot.Task) -> Binding<String> {
    Binding(
      get: {
        taskTitleDraftTaskID == task.id ? taskTitleDraft : task.title
      },
      set: {
        taskTitleDraftTaskID = task.id
        taskTitleDraft = $0
      }
    )
  }

  private func submitTaskTitle(_ task: TimelineProjectListWindowSnapshot.Task) {
    let title = taskTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title != task.title else { return }
    onRenameTask(task.id, title)
  }

  private func commitPendingTaskIfNeeded() {
    guard block.taskBinding?.taskID == nil,
      !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }
    onCommand(.commandEnter)
  }
}

private struct ProjectOutlineDropIndicatorLine: View {
  var body: some View {
    Rectangle()
      .fill(Color.accentColor)
      .frame(height: 2)
      .cornerRadius(1)
      .allowsHitTesting(false)
  }
}

private let projectOutlinerFont = Font.system(size: 18, weight: .regular)
private let projectOutlinerChipFont = Font.system(size: 12, weight: .semibold)

@MainActor
private var projectOutlinerNSFont: NSFont {
  NSFont.systemFont(ofSize: 18)
}
