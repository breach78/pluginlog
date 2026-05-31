import SwiftUI
import UniformTypeIdentifiers

struct ProjectOutlinerView: View {
  @Binding var document: ProjectOutlineDocument

  let tasks: [TimelineProjectListWindowSnapshot.Task]
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
  @State private var rowHeights: [UUID: CGFloat] = [:]
  @State private var draggingBlockID: UUID?
  @State private var dropIndicator: ProjectOutlineDropIndicator?

  private var tasksByID: [UUID: TimelineProjectListWindowSnapshot.Task] {
    Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
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
              onRenameTask: onRenameTask,
              onToggleTaskCompletion: onToggleTaskCompletion,
              onOpenTask: onOpenTask,
              onOpenTaskSection: onOpenTaskSection,
              onBeginDrag: {
                draggingBlockID = blockID
              }
            )
            .onDrop(
              of: [UTType.text.identifier],
              delegate: ProjectOutlineBlockDropDelegate(
                targetID: blockID,
                rowHeight: rowHeights[blockID] ?? 24,
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
  }

  private var visibleBlockIDs: [UUID] {
    ProjectOutlineMutationEngine.visibleIndices(in: document).map { document.blocks[$0].id }
  }

  private func binding(for blockID: UUID) -> Binding<ProjectOutlineBlock>? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
    return Binding(
      get: { document.blocks[index] },
      set: { document.blocks[index] = $0 }
    )
  }

  private func hasChildren(blockID: UUID) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return false }
    return ProjectOutlineMutationEngine.hasChildren(at: index, in: document)
  }

  private func handle(_ command: ProjectOutlineTextCommand, blockID: UUID) {
    switch command {
    case .enter(let offset):
      if let result = ProjectOutlineMutationEngine.insertFromEnter(
        blockID: blockID,
        textOffset: offset,
        in: &document
      ) {
        focusedBlockID = result.focusedBlockID
      }
    case .tab:
      _ = ProjectOutlineMutationEngine.indentBlock(id: blockID, in: &document)
    case .shiftTab:
      _ = ProjectOutlineMutationEngine.outdentBlock(id: blockID, in: &document)
    case .backspaceAtStart:
      handleBackspaceAtStart(blockID: blockID)
    case .deleteAtEnd:
      _ = ProjectOutlineMutationEngine.deleteAtEnd(blockID: blockID, in: &document)
    case .commandEnter:
      handleCommandEnter(blockID: blockID)
    case .commandShiftUp:
      if ProjectOutlineMutationEngine.moveBlockUp(id: blockID, in: &document) {
        focusedBlockID = blockID
      }
    case .commandShiftDown:
      if ProjectOutlineMutationEngine.moveBlockDown(id: blockID, in: &document) {
        focusedBlockID = blockID
      }
    case .commandUp, .commandDown:
      toggleFold(blockID: blockID)
    case .escape:
      focusedBlockID = nil
    }
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
}

private struct ProjectOutlineRowView: View {
  @Binding var block: ProjectOutlineBlock
  let task: TimelineProjectListWindowSnapshot.Task?
  let projectColor: Color
  let isFocused: Bool
  let isCreatingTask: Bool
  let recurringCompletionCount: Int
  let hasChildren: Bool
  let dropPlacement: ProjectOutlineDropPlacement?
  @Binding var measuredHeight: CGFloat
  let onCommand: (ProjectOutlineTextCommand) -> Void
  let onFocus: () -> Void
  let onDeleteBlock: () -> Void
  let onRenameTask: (UUID, String) -> Void
  let onToggleTaskCompletion: (UUID, Bool) -> Void
  let onOpenTask: (UUID) -> Void
  let onOpenTaskSection: (UUID, TaskEditAuxiliarySection) -> Void
  let onBeginDrag: () -> Void

  @State private var taskTitleDraft = ""
  @FocusState private var isTaskTitleFocused: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      HStack(spacing: 0) {
        ForEach(0..<block.depth, id: \.self) { _ in
          Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 9.5)
        }
      }
      .frame(height: max(24, measuredHeight))

      marker

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
          .padding(.leading, CGFloat(block.depth) * 20 + 40)
          .padding(.trailing, 18)
      }
    }
    .overlay(alignment: .leading) {
      if dropPlacement == .child {
        ProjectOutlineDropIndicatorLine()
          .padding(.leading, CGFloat(block.depth + 1) * 20 + 40)
          .padding(.trailing, 18)
      }
    }
    .contentShape(Rectangle())
    .contextMenu {
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
          guard let task else { return }
          onToggleTaskCompletion(task.id, task.isCompleted)
        } label: {
          Image(systemName: task?.isCompleted == true ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 14))
            .foregroundStyle(task?.isCompleted == true ? projectColor : Color.secondary)
            .frame(width: 18, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(task == nil || isCreatingTask)
      } else {
        Button {
          if hasChildren {
            onCommand(.commandUp)
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
          TextField("할일", text: taskTitleBinding(for: task))
            .textFieldStyle(.plain)
            .font(projectOutlinerFont)
            .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
            .strikethrough(task.isCompleted)
            .focused($isTaskTitleFocused)
            .disabled(isCreatingTask)
            .onSubmit {
              submitTaskTitle(task)
            }
            .onChange(of: isTaskTitleFocused) { _, focused in
              if focused {
                taskTitleDraft = task.title
              } else {
                submitTaskTitle(task)
              }
            }
        } else {
          Text(isCreatingTask ? "할일 생성 중..." : "불러오는 중...")
            .font(projectOutlinerFont)
            .foregroundStyle(Color.secondary)
        }

        Spacer(minLength: 8)

        if let task {
          if let dateText = task.dateText {
            Button(dateText) {
              onOpenTaskSection(task.id, .schedule)
            }
            .buttonStyle(.borderless)
            .font(projectOutlinerChipFont)
            .foregroundStyle(Color.secondary)
          }

          if task.metadataIndicators.isRecurring {
            if recurringCompletionCount > 0 {
              Text("\(recurringCompletionCount)")
                .font(projectOutlinerChipFont)
                .foregroundStyle(projectColor)
                .monospacedDigit()
            }
            Button {
              onOpenTaskSection(task.id, .recurrence)
            } label: {
              Image(systemName: "repeat")
            }
            .buttonStyle(.borderless)
            .font(projectOutlinerChipFont)
            .foregroundStyle(Color.secondary)
          }
        }
      }
    }
    .frame(minHeight: 24)
    .onAppear {
      if let task, taskTitleDraft.isEmpty {
        taskTitleDraft = task.title
      }
    }
  }

  private func taskTitleBinding(for task: TimelineProjectListWindowSnapshot.Task) -> Binding<String> {
    Binding(
      get: { taskTitleDraft.isEmpty ? task.title : taskTitleDraft },
      set: { taskTitleDraft = $0 }
    )
  }

  private func submitTaskTitle(_ task: TimelineProjectListWindowSnapshot.Task) {
    let title = taskTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title != task.title else { return }
    onRenameTask(task.id, title)
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
