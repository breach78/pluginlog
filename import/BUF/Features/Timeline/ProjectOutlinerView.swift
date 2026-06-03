import SwiftUI
import UniformTypeIdentifiers

struct ProjectOutlinerView: View {
  @Binding var document: ProjectOutlineDocument

  let tasks: [TimelineProjectListWindowSnapshot.Task]
  let projectTitle: String
  let projectColor: Color
  let showsCompletedTasks: Bool
  let temporarilyVisibleCompletedTaskIDs: Set<UUID>
  let pendingTaskBlockIDs: Set<UUID>
  let recurringCompletionCounts: [UUID: Int]
  let highlightedTaskID: UUID?
  let highlightRequestID: Int
  let moveOptions: [TimelineProjectMoveOption]
  let taskEditConfiguration: TimelineProjectListInlineEditorConfiguration?
  let onCreateTaskBlock: (UUID) -> Void
  let onRenameTask: (UUID, String) -> Void
  let onToggleTaskCompletion: (UUID, Bool) -> Void
  let onDeleteTaskBlock: (UUID) -> Void
  let onDeleteTask: (UUID) -> Void
  let onOpenTask: (UUID) -> Void
  let onOpenTaskSection: (UUID, TaskEditAuxiliarySection) -> Void
  let onImportAttachmentFiles: (UUID, [URL], Int) -> Void
  let onOpenAttachment: (ProjectOutlineInlineAttachment) -> Void
  let onRenameAttachment: (ProjectOutlineInlineAttachment) -> Void
  let onDeleteAttachment: (ProjectOutlineInlineAttachment) -> Void
  let onMoveBlockToProject: (UUID, UUID) -> Void

  @State private var focusedBlockID: UUID?
  @State private var focusRequestID: UInt64 = 0
  @State private var focusPlacement: ProjectOutlineFocusPlacement = .preserve
  @State private var blockSelection: ProjectOutlineBlockSelection?
  @State private var zoomRootBlockID: UUID?
  @State private var blockToRevealAfterZoomOut: UUID?
  @State private var rowHeights: [UUID: CGFloat] = [:]
  @State private var draggingBlockIDs: [UUID] = []
  @State private var dropIndicator: ProjectOutlineDropIndicator?
  @State private var blockToReveal: UUID?
  @State private var blockRevealRequestID: UInt64 = 0
  @State private var highlightedBlockID: UUID?
  @State private var handledHighlightRequestID: Int?
  @State private var initialOutlineGlobalMinY: CGFloat?
  @State private var outlineGlobalMinY: CGFloat = 0
  @State private var outlineViewportHeight: CGFloat = 700

  private var tasksByID: [UUID: TimelineProjectListWindowSnapshot.Task] {
    Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
  }

  var body: some View {
    ScrollViewReader { proxy in
      outlinerContent(proxy: proxy)
    }
  }

  @ViewBuilder
  private func outlinerContent(proxy: ScrollViewProxy) -> some View {
    let displayContext = displayContext
    let virtualizedRange = virtualizedRange(for: displayContext)
    LazyVStack(alignment: .leading, spacing: 0) {
      zoomBreadcrumb
      if document.blocks.isEmpty {
        emptyDocumentButton
      } else {
        virtualizedRows(displayContext: displayContext, range: virtualizedRange)
      }
    }
    .padding(.vertical, 12)
    .background(outlinePositionReader)
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
    .onChange(of: blockRevealRequestID) { _, _ in
      guard let blockToReveal else { return }
      DispatchQueue.main.async {
        proxy.scrollTo(blockToReveal)
      }
    }
    .onAppear {
      highlightRequestedTaskIfNeeded()
    }
    .onChange(of: highlightRequestID) { _, _ in
      highlightRequestedTaskIfNeeded()
    }
    .onChange(of: highlightedTaskID) { _, _ in
      handledHighlightRequestID = nil
      highlightRequestedTaskIfNeeded()
    }
    .onChange(of: document.blocks) { _, blocks in
      if let zoomRootBlockID, !blocks.contains(where: { $0.id == zoomRootBlockID }) {
        self.zoomRootBlockID = nil
      }
      highlightRequestedTaskIfNeeded()
    }
    .onPreferenceChange(ProjectOutlineGlobalMinYPreferenceKey.self) { minY in
      if initialOutlineGlobalMinY == nil {
        initialOutlineGlobalMinY = minY
      }
      outlineGlobalMinY = minY
      outlineViewportHeight = currentOutlineViewportHeight()
    }
  }

  private var emptyDocumentButton: some View {
    Button("첫 불릿 추가", systemImage: "plus") {
      let block = ProjectOutlineBlock(depth: 0, text: "")
      document.blocks = [block]
      requestFocus(block.id)
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 9)
    .padding(.vertical, 16)
  }

  private var outlinePositionReader: some View {
    GeometryReader { proxy in
      Color.clear
        .preference(
          key: ProjectOutlineGlobalMinYPreferenceKey.self,
          value: proxy.frame(in: .global).minY
        )
    }
  }

  @ViewBuilder
  private func virtualizedRows(
    displayContext: ProjectOutlinerDisplayContext,
    range: ProjectOutlineVirtualizedRange
  ) -> some View {
    Color.clear
      .frame(height: range.topSpacerHeight)
      .accessibilityHidden(true)

    ForEach(Array(displayContext.blocks[range.indices])) { visibleBlock in
      outlineRow(visibleBlock: visibleBlock, selectedIDs: displayContext.selectedIDs)
    }

    Color.clear
      .frame(height: range.bottomSpacerHeight)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private func outlineRow(
    visibleBlock: ProjectOutlinerVisibleBlock,
    selectedIDs: Set<UUID>
  ) -> some View {
    let blockID = visibleBlock.id
    if let blockBinding = binding(for: blockID) {
      ProjectOutlineRowView(
        block: blockBinding,
        task: visibleBlock.block.taskBinding?.taskID.flatMap { tasksByID[$0] },
        projectColor: projectColor,
        isFocused: focusedBlockID == blockID,
        focusRequestID: focusRequestID,
        focusPlacement: focusedBlockID == blockID ? focusPlacement : .preserve,
        isBlockSelectionActive: blockSelection != nil,
        isBlockSelected: selectedIDs.contains(blockID),
        isHighlighted: highlightedBlockID == blockID,
        displayDepth: visibleBlock.displayDepth,
        blockColorToken: visibleBlock.block.colorToken,
        hidesMarker: zoomRootBlockID == blockID,
        isCreatingTask: pendingTaskBlockIDs.contains(blockID),
        recurringCompletionCount: visibleBlock.block.taskBinding?.taskID.flatMap {
          recurringCompletionCounts[$0]
        } ?? 0,
        moveOptions: moveOptions,
        taskEditConfiguration: taskEditConfiguration,
        hasChildren: visibleBlock.hasVisibleChildren,
        isCollapsed: visibleBlock.block.childrenCollapsed,
        dropPlacement: dropIndicator?.targetID == blockID ? dropIndicator?.placement : nil,
        measuredHeight: Binding(
          get: { rowHeights[blockID] ?? 24 },
          set: { rowHeights[blockID] = $0 }
        ),
        onCommand: { command in
          handle(command, blockID: blockID)
        },
        onFocus: {
          blockSelection = nil
          requestFocus(blockID)
        },
        onReveal: {
          requestReveal(blockID)
        },
        onDeleteBlock: {
          deleteBlock(blockID: blockID)
        },
        onMoveToProject: { targetProjectID in
          onMoveBlockToProject(blockID, targetProjectID)
        },
        onZoomIn: {
          zoomIn(blockID: blockID)
        },
        onToggleFold: {
          toggleFold(blockID: blockID)
        },
        onRenameTask: onRenameTask,
        onToggleTaskCompletion: onToggleTaskCompletion,
        onOpenTask: onOpenTask,
        onOpenTaskSection: onOpenTaskSection,
        onImportAttachmentFiles: { urls, offset in
          onImportAttachmentFiles(blockID, urls, offset)
        },
        onOpenAttachment: onOpenAttachment,
        onRenameAttachment: onRenameAttachment,
        onDeleteAttachment: onDeleteAttachment,
        onBeginDrag: {
          draggingBlockIDs = draggingIDs(startingAt: blockID)
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
          draggingBlockIDs: $draggingBlockIDs,
          dropIndicator: $dropIndicator
        )
      )
    }
  }

  private var visibleBlockIDs: [UUID] {
    displayContext.visibleIDs
  }

  private var displayContext: ProjectOutlinerDisplayContext {
    ProjectOutlinerDisplayContext(
      document: document,
      focusRootID: zoomRootBlockID,
      hiddenTaskIDs: hiddenTaskIDs,
      selection: blockSelection
    )
  }

  private var hiddenTaskIDs: Set<UUID> {
    guard !showsCompletedTasks else { return [] }
    return Set(
      tasks
        .filter { $0.isCompleted && !temporarilyVisibleCompletedTaskIDs.contains($0.id) }
        .map(\.id)
    )
  }

  private var selectedBlockIDs: Set<UUID> {
    displayContext.selectedIDs
  }

  private func draggingIDs(startingAt blockID: UUID) -> [UUID] {
    let selectedIDs = blockSelection?.selectedIDs(
      in: visibleBlockIDs,
      depths: visibleDepthsByID
    ) ?? []
    return selectedIDs.contains(blockID) ? selectedIDs : [blockID]
  }

  private var visibleDepthsByID: [UUID: Int] {
    displayContext.visibleDepthsByID
  }

  private func virtualizedRange(
    for displayContext: ProjectOutlinerDisplayContext
  ) -> ProjectOutlineVirtualizedRange {
    ProjectOutlineVirtualizationPolicy.range(
      itemIDs: displayContext.visibleIDs,
      rowHeights: rowHeights,
      scrollOffset: currentScrollOffset(),
      viewportHeight: outlineViewportHeight,
      pinnedIDs: pinnedVirtualizedBlockIDs
    )
  }

  private var pinnedVirtualizedBlockIDs: Set<UUID> {
    Set(
      [
        focusedBlockID,
        highlightedBlockID,
        dropIndicator?.targetID,
        blockToReveal,
        blockToRevealAfterZoomOut,
      ].compactMap { $0 }
    )
  }

  private func currentScrollOffset() -> CGFloat {
    guard let initialOutlineGlobalMinY else { return 0 }
    return max(0, initialOutlineGlobalMinY - outlineGlobalMinY)
  }

  private func currentOutlineViewportHeight() -> CGFloat {
    guard let contentView = NSApplication.shared.keyWindow?.contentView else {
      return outlineViewportHeight
    }
    let initialY = initialOutlineGlobalMinY ?? outlineGlobalMinY
    return max(220, contentView.bounds.height - max(0, initialY))
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

  private func hasVisibleChildren(blockID: UUID) -> Bool {
    ProjectOutlineVisibilityPolicy.hasVisibleChildren(
      blockID: blockID,
      in: document,
      hiddenTaskIDs: hiddenTaskIDs
    )
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
      indentFocusedBlockOrSelection(blockID: blockID)
    case .shiftTab:
      outdentFocusedBlockOrSelection(blockID: blockID)
    case .backspaceAtStart:
      handleBackspaceAtStart(blockID: blockID, currentTextOverride: nil)
    case .mergeBackspaceAtStart(let text):
      handleBackspaceAtStart(blockID: blockID, currentTextOverride: text)
    case .deleteAtEnd:
      _ = ProjectOutlineMutationEngine.deleteAtEnd(blockID: blockID, in: &document)
    case .commandEnter:
      handleCommandEnter(blockID: blockID)
    case .commandShiftUp:
      guard !isFirstVisibleChildOfZoomRoot(blockID) else { return }
      if ProjectOutlineMutationEngine.moveBlockUp(id: blockID, in: &document) {
        requestFocus(blockID)
      }
    case .commandShiftDown:
      guard !isLastVisibleChildOfZoomRoot(blockID) else { return }
      if ProjectOutlineMutationEngine.moveBlockDown(id: blockID, in: &document) {
        requestFocus(blockID)
      }
    case .commandUp, .commandDown:
      toggleFold(blockID: blockID)
    case .escape:
      requestFocus(nil)
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
      focusAdjacentBlock(from: blockID, offset: -1, placement: .end)
    case .focusNext:
      focusAdjacentBlock(from: blockID, offset: 1, placement: .start)
    case .focusPreviousAt(let offset):
      focusAdjacentBlock(from: blockID, offset: -1, placement: .offset(offset))
    case .focusNextAt(let offset):
      focusAdjacentBlock(from: blockID, offset: 1, placement: .offset(offset))
    case .extendBlockSelectionUp:
      extendBlockSelection(from: blockID, offset: -1)
    case .extendBlockSelectionDown:
      extendBlockSelection(from: blockID, offset: 1)
    case .exitBlockSelectionUp:
      exitBlockSelection(offset: -1)
    case .exitBlockSelectionDown:
      exitBlockSelection(offset: 1)
    case .exitBlockSelectionLeft:
      exitBlockSelectionToHorizontalEdge(start: true)
    case .exitBlockSelectionRight:
      exitBlockSelectionToHorizontalEdge(start: false)
    case .clearBlockSelection:
      clearBlockSelection(focusAnchor: true)
    case .deleteBlockSelection:
      deleteSelectedBlocks()
    case .selectAllVisibleBlocks:
      selectAllVisibleBlocks(anchor: blockID)
    }
  }

  private func indentFocusedBlockOrSelection(blockID: UUID) {
    guard let blockSelection else {
      _ = ProjectOutlineMutationEngine.indentBlock(id: blockID, in: &document)
      return
    }
    _ = ProjectOutlineMutationEngine.indentSelection(
      ids: blockSelection.selectedIDs(in: visibleBlockIDs, depths: visibleDepthsByID),
      in: &document
    )
  }

  private func outdentFocusedBlockOrSelection(blockID: UUID) {
    guard let blockSelection else {
      guard !isDirectChildOfZoomRoot(blockID) else { return }
      _ = ProjectOutlineMutationEngine.outdentBlock(id: blockID, in: &document)
      return
    }
    let selectedIDs = blockSelection.selectedIDs(in: visibleBlockIDs, depths: visibleDepthsByID)
    guard !selectedIDs.contains(where: isDirectChildOfZoomRoot) else { return }
    _ = ProjectOutlineMutationEngine.outdentSelection(ids: selectedIDs, in: &document)
  }

  private func handleEnter(blockID: UUID, offset: Int) {
    guard let block = document.blocks.first(where: { $0.id == blockID }) else { return }
    if block.isTaskBlock {
      if block.taskBinding?.taskID == nil,
        !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        onCreateTaskBlock(blockID)
      }
      let result = hasVisibleChildren(blockID: blockID) && !block.childrenCollapsed
        ? ProjectOutlineMutationEngine.insertFirstChild(blockID: blockID, in: &document)
        : ProjectOutlineMutationEngine.insertSiblingAfterSubtree(blockID: blockID, in: &document)
      if let result {
        requestFocus(result.focusedBlockID)
      }
      return
    }

    let shouldFocusSplitStart = offset > 0 && offset < block.text.utf16.count
    if let result = ProjectOutlineMutationEngine.insertFromEnter(
      blockID: blockID,
      textOffset: offset,
      hasExpandedChildrenOverride: hasVisibleChildren(blockID: blockID) && !block.childrenCollapsed,
      in: &document
    ) {
      requestFocus(result.focusedBlockID, placement: shouldFocusSplitStart ? .start : .preserve)
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
    requestFocus(blockID)
  }

  private func handleCommandEnter(blockID: UUID) {
    guard let block = document.blocks.first(where: { $0.id == blockID }) else { return }
    if block.isTaskBlock {
      convertTaskBlockToBullet(blockID: blockID, block: block)
      return
    }
    onCreateTaskBlock(blockID)
  }

  private func convertTaskBlockToBullet(blockID: UUID, block: ProjectOutlineBlock) {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return }
    if let taskID = block.taskBinding?.taskID {
      document.blocks[index].text = tasksByID[taskID]?.title ?? block.text
      onDeleteTask(taskID)
    }
    document.blocks[index].taskBinding = nil
    requestFocus(blockID)
  }

  private func handleBackspaceAtStart(
    blockID: UUID,
    currentTextOverride: String?
  ) {
    if mergeTaskBackspaceAtStart(
      blockID: blockID,
      currentTextOverride: currentTextOverride
    ) {
      return
    }
    let visibleIDsBeforeMutation = visibleBlockIDs
    let previousID = visibleIDsBeforeMutation
      .firstIndex(of: blockID)
      .flatMap { index in index > 0 ? visibleIDsBeforeMutation[index - 1] : nil }
    guard let result = ProjectOutlineMutationEngine.backspaceAtStartResult(
      blockID: blockID,
      in: &document
    ) else {
      return
    }
    if !document.blocks.contains(where: { $0.id == blockID }) {
      let focusedID = result.focusedBlockID ?? previousID
      let placement = result.focusOffset.map(ProjectOutlineFocusPlacement.offset) ?? .end
      invalidateMeasuredHeight(for: focusedID)
      requestFocus(focusedID, placement: placement)
    } else if let focusedID = result.focusedBlockID {
      let placement = result.focusOffset.map(ProjectOutlineFocusPlacement.offset) ?? .preserve
      invalidateMeasuredHeight(for: focusedID)
      requestFocus(focusedID, placement: placement)
    }
  }

  private func mergeTaskBackspaceAtStart(
    blockID: UUID,
    currentTextOverride: String?
  ) -> Bool {
    guard let currentIndex = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return false
    }
    let visibleIDsBeforeMutation = visibleBlockIDs
    guard let visiblePosition = visibleIDsBeforeMutation.firstIndex(of: blockID),
      visiblePosition > 0,
      let previousIndex = document.blocks.firstIndex(where: {
        $0.id == visibleIDsBeforeMutation[visiblePosition - 1]
      })
    else {
      return false
    }

    let currentBlock = document.blocks[currentIndex]
    let previousBlock = document.blocks[previousIndex]
    guard currentBlock.isTaskBlock || previousBlock.isTaskBlock else { return false }
    guard !ProjectOutlineMutationEngine.hasChildren(at: currentIndex, in: document) else {
      return true
    }

    let previousText = displayText(for: previousBlock)
    let currentText = currentTextOverride ?? displayText(for: currentBlock)
    let focusOffset = previousText.utf16.count
    let mergedText = previousText + currentText

    if let previousTaskID = previousBlock.taskBinding?.taskID {
      document.blocks[previousIndex].text = mergedText
      onRenameTask(previousTaskID, mergedText)
    } else if previousBlock.isTaskBlock {
      document.blocks[previousIndex].text = mergedText
    } else {
      document.blocks[previousIndex].text = mergedText
    }

    if let currentTaskID = currentBlock.taskBinding?.taskID {
      onDeleteTask(currentTaskID)
    }
    document.blocks.remove(at: currentIndex)
    invalidateMeasuredHeight(for: previousBlock.id)
    requestFocus(previousBlock.id, placement: .offset(focusOffset))
    return true
  }

  private func displayText(for block: ProjectOutlineBlock) -> String {
    block.taskBinding?.taskID.flatMap { tasksByID[$0]?.title } ?? block.text
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

  private func extendBlockSelection(from blockID: UUID, offset: Int) {
    let visibleIDs = visibleBlockIDs
    let anchorID = blockSelection?.anchorID ?? blockID
    let selectedIDs = blockSelection?.selectedIDs(
      in: visibleIDs,
      depths: visibleDepthsByID
    )
    let edgeID = offset < 0 ? selectedIDs?.first : selectedIDs?.last
    guard let currentPosition = visibleIDs.firstIndex(of: edgeID ?? blockID) else { return }
    let nextPosition = currentPosition + offset
    let nextHeadID = visibleIDs.indices.contains(nextPosition)
      ? visibleIDs[nextPosition]
      : visibleIDs[currentPosition]
    blockSelection = ProjectOutlineBlockSelection(anchorID: anchorID, headID: nextHeadID)
    requestFocus(anchorID)
  }

  private func exitBlockSelection(offset: Int) {
    let visibleIDs = visibleBlockIDs
    guard let blockSelection,
      let targetID = blockSelection.adjacentID(
        afterSelectionBy: offset,
        in: visibleIDs,
        depths: visibleDepthsByID
      )
    else {
      clearBlockSelection(focusAnchor: true)
      return
    }
    self.blockSelection = nil
    requestFocus(targetID, placement: offset < 0 ? .end : .start)
  }

  private func exitBlockSelectionToHorizontalEdge(start: Bool) {
    guard let blockSelection else { return }
    let visibleIDs = visibleBlockIDs
    let selectedIDs = blockSelection.selectedIDs(
      in: visibleIDs,
      depths: visibleDepthsByID
    )
    let targetID = start
      ? selectedIDs.first
      : selectedIDs.last
    self.blockSelection = nil
    requestFocus(targetID ?? blockSelection.anchorID, placement: start ? .start : .end)
  }

  private func clearBlockSelection(focusAnchor: Bool) {
    let anchorID = blockSelection?.anchorID
    blockSelection = nil
    if focusAnchor {
      requestFocus(anchorID, placement: .preserve)
    }
  }

  private func selectAllVisibleBlocks(anchor blockID: UUID) {
    guard let lastID = visibleBlockIDs.last else { return }
    blockSelection = ProjectOutlineBlockSelection(anchorID: blockID, headID: lastID)
    requestFocus(blockID)
  }

  private func deleteSelectedBlocks() {
    let selectedIDs = selectedBlockIDs
    guard !selectedIDs.isEmpty else { return }
    for blockID in visibleBlockIDs.reversed() where selectedIDs.contains(blockID) {
      deleteBlock(blockID: blockID)
    }
    blockSelection = nil
    requestFocus(nil)
  }

  private func toggleFold(blockID: UUID) {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      hasVisibleChildren(blockID: blockID)
    else {
      return
    }
    document.blocks[index].childrenCollapsed.toggle()
  }

  @ViewBuilder
  private var zoomBreadcrumb: some View {
    if let currentZoomRootID = zoomRootBlockID {
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
            requestFocus(ancestorID)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.secondary)
        }
      }
      .font(projectOutlinerChipFont)
      .padding(.horizontal, 9)
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
    guard hasVisibleChildren(blockID: blockID) else {
      requestFocus(blockID)
      return
    }
    zoomRootBlockID = blockID
    requestFocus(blockID)
  }

  private func zoomOutOneLevel() {
    guard let zoomRootBlockID else { return }
    blockToRevealAfterZoomOut = zoomRootBlockID
    self.zoomRootBlockID = ProjectOutlineMutationEngine.parentID(
      for: zoomRootBlockID,
      in: document
    )
    requestFocus(zoomRootBlockID)
  }

  private func zoomHome() {
    guard let zoomRootBlockID else { return }
    blockToRevealAfterZoomOut = zoomRootBlockID
    self.zoomRootBlockID = nil
    requestFocus(zoomRootBlockID)
  }

  private func zoomToSibling(previous: Bool) {
    guard let zoomRootBlockID else { return }
    let nextID = previous
      ? ProjectOutlineMutationEngine.previousSiblingID(for: zoomRootBlockID, in: document)
      : ProjectOutlineMutationEngine.nextSiblingID(for: zoomRootBlockID, in: document)
    guard let nextID else { return }
    self.zoomRootBlockID = nextID
    requestFocus(nextID)
  }

  private func focusAdjacentBlock(
    from blockID: UUID,
    offset: Int,
    placement: ProjectOutlineFocusPlacement
  ) {
    guard let currentPosition = visibleBlockIDs.firstIndex(of: blockID) else { return }
    let nextPosition = currentPosition + offset
    guard visibleBlockIDs.indices.contains(nextPosition) else {
      requestFocus(blockID, placement: offset < 0 ? .start : .end)
      return
    }
    requestFocus(visibleBlockIDs[nextPosition], placement: placement)
  }

  private func requestFocus(
    _ blockID: UUID?,
    placement: ProjectOutlineFocusPlacement = .preserve
  ) {
    focusedBlockID = blockID
    focusPlacement = placement
    focusRequestID &+= 1
    if let blockID {
      requestReveal(blockID)
    }
  }

  private func requestReveal(_ blockID: UUID) {
    blockToReveal = blockID
    blockRevealRequestID &+= 1
  }

  private func highlightRequestedTaskIfNeeded() {
    guard handledHighlightRequestID != highlightRequestID else { return }
    guard let highlightedTaskID,
      let blockID = document.blocks.first(where: { $0.taskBinding?.taskID == highlightedTaskID })?.id
    else {
      return
    }
    handledHighlightRequestID = highlightRequestID
    highlightedBlockID = blockID
    requestReveal(blockID)
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      if highlightedBlockID == blockID {
        highlightedBlockID = nil
      }
    }
  }

  private func invalidateMeasuredHeight(for blockID: UUID?) {
    guard let blockID else { return }
    rowHeights[blockID] = 24
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

private struct ProjectOutlineGlobalMinYPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

private struct ProjectOutlineRowView: View {
  @Binding var block: ProjectOutlineBlock
  let task: TimelineProjectListWindowSnapshot.Task?
  let projectColor: Color
  let isFocused: Bool
  let focusRequestID: UInt64
  let focusPlacement: ProjectOutlineFocusPlacement
  let isBlockSelectionActive: Bool
  let isBlockSelected: Bool
  let isHighlighted: Bool
  let displayDepth: Int
  let blockColorToken: ProjectOutlineBlockColor?
  let hidesMarker: Bool
  let isCreatingTask: Bool
  let recurringCompletionCount: Int
  let moveOptions: [TimelineProjectMoveOption]
  let taskEditConfiguration: TimelineProjectListInlineEditorConfiguration?
  let hasChildren: Bool
  let isCollapsed: Bool
  let dropPlacement: ProjectOutlineDropPlacement?
  @Binding var measuredHeight: CGFloat
  let onCommand: (ProjectOutlineTextCommand) -> Void
  let onFocus: () -> Void
  let onReveal: () -> Void
  let onDeleteBlock: () -> Void
  let onMoveToProject: (UUID) -> Void
  let onZoomIn: () -> Void
  let onToggleFold: () -> Void
  let onRenameTask: (UUID, String) -> Void
  let onToggleTaskCompletion: (UUID, Bool) -> Void
  let onOpenTask: (UUID) -> Void
  let onOpenTaskSection: (UUID, TaskEditAuxiliarySection) -> Void
  let onImportAttachmentFiles: ([URL], Int) -> Void
  let onOpenAttachment: (ProjectOutlineInlineAttachment) -> Void
  let onRenameAttachment: (ProjectOutlineInlineAttachment) -> Void
  let onDeleteAttachment: (ProjectOutlineInlineAttachment) -> Void
  let onBeginDrag: () -> Void

  @State private var taskTitleDraft = ""
  @State private var taskTitleDraftTaskID: UUID?
  @State private var scheduleMenuTaskID: UUID?
  @State private var isHoveringMarker = false

  var body: some View {
    let palette = ProjectOutlineBlockColorPalette.style(for: blockColorToken)
    HStack(alignment: .top, spacing: 8) {
      HStack(spacing: 0) {
        ForEach(0..<displayDepth, id: \.self) { _ in
          Color.clear
            .frame(width: projectOutlinerIndentWidth)
            .overlay {
              Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 2, height: max(30, measuredHeight + 6))
                .offset(x: -2)
            }
        }
      }
      .frame(height: max(24, measuredHeight))

      if !hidesMarker {
        marker
          .offset(y: 2)
      }

      if block.isTaskBlock {
        taskContent(task)
      } else {
        ProjectOutlineTextEditor(
          text: $block.text,
          measuredHeight: $measuredHeight,
          vaultRootURL: taskEditConfiguration?.vaultRootURL,
          isFocused: isFocused,
          focusRequestID: focusRequestID,
          focusPlacement: focusPlacement,
          isBlockSelectionActive: isBlockSelectionActive,
          font: projectOutlinerNSFont,
          textColor: palette.nsTextColor,
          onCommand: onCommand,
          onReveal: onReveal,
          onImportFiles: onImportAttachmentFiles,
          onOpenAttachment: onOpenAttachment,
          onRenameAttachment: onRenameAttachment,
          onDeleteAttachment: onDeleteAttachment,
          onFocus: onFocus
        )
        .frame(minHeight: 24)
        .frame(height: measuredHeight)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 5)
        .fill(rowBackgroundColor(palette: palette))
    }
    .onTapGesture {
      onFocus()
    }
    .overlay(alignment: dropPlacement == .before ? .topLeading : .bottomLeading) {
      if dropPlacement == .before || dropPlacement == .after {
        ProjectOutlineDropIndicatorLine()
          .padding(.leading, CGFloat(displayDepth) * projectOutlinerIndentWidth + projectOutlinerDropIndicatorBaseLeading)
          .padding(.trailing, 18)
      }
    }
    .overlay(alignment: .leading) {
      if dropPlacement == .child {
        ProjectOutlineDropIndicatorLine()
          .padding(.leading, CGFloat(displayDepth + 1) * projectOutlinerIndentWidth + projectOutlinerDropIndicatorBaseLeading)
          .padding(.trailing, 18)
      }
    }
    .contentShape(Rectangle())
    .contextMenu {
      if hasChildren || block.isTaskBlock {
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
      if !moveOptions.isEmpty {
        Menu("이동") {
          ForEach(moveOptions) { option in
            Button(option.title) {
              onMoveToProject(option.id)
            }
          }
        }
      }
      Button("블록 삭제", role: .destructive) {
        onDeleteBlock()
      }
      Divider()
      Menu("노드 색") {
        Button {
          block.colorToken = nil
        } label: {
          Label("색 없음", systemImage: block.colorToken == nil ? "checkmark" : "circle")
        }
        ForEach(ProjectOutlineBlockColor.allCases, id: \.rawValue) { color in
          Button {
            block.colorToken = color
          } label: {
            HStack {
              Circle()
                .fill(ProjectOutlineBlockColorPalette.style(for: color).backgroundColor)
                .frame(width: 12, height: 12)
              Text(ProjectOutlineBlockColorPalette.name(for: color))
              if block.colorToken == color {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      }
    }
    .onHover { isHoveringMarker = $0 }
  }

  private func rowBackgroundColor(palette: ProjectOutlineBlockColorPalette.Style) -> Color {
    if isBlockSelected {
      return Color.accentColor.opacity(0.12)
    }
    if isHighlighted {
      return Color.yellow.opacity(0.28)
    }
    return palette.backgroundColor
  }

  private var marker: some View {
    ZStack(alignment: .leading) {
      markerControl
      if hasChildren {
        foldHandle
          .opacity(isHoveringMarker ? 1 : 0)
          .offset(x: -16)
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

  @ViewBuilder
  private var markerControl: some View {
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
        ZStack {
          if hasChildren && isCollapsed {
            Circle()
              .fill(Color.secondary.opacity(0.10))
              .frame(width: 20, height: 20)
          }
          Circle()
            .fill(Color.secondary.opacity(isCollapsed ? 0.34 : 0.28))
            .frame(width: hasChildren ? 7 : 6, height: hasChildren ? 7 : 6)
        }
        .frame(width: projectOutlinerBulletHitSize, height: projectOutlinerBulletHitSize)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private var foldHandle: some View {
    Button {
      onToggleFold()
    } label: {
      Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(Color.secondary.opacity(0.72))
        .frame(width: 14, height: 18)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(isCollapsed ? "하위 항목 펼치기" : "하위 항목 접기")
  }

  private func taskContent(_ task: TimelineProjectListWindowSnapshot.Task?) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .top, spacing: 8) {
        if let task {
          ProjectOutlineTextEditor(
            text: taskTitleBinding(for: task),
            measuredHeight: $measuredHeight,
            vaultRootURL: nil,
            isFocused: isFocused,
            focusRequestID: focusRequestID,
            focusPlacement: focusPlacement,
            isBlockSelectionActive: isBlockSelectionActive,
            font: projectOutlinerNSFont,
            textColor: ProjectOutlineBlockColorPalette.style(for: blockColorToken).nsTextColor,
            onCommand: { command in
              submitTaskTitle(task)
              onCommand(command)
            },
            onReveal: onReveal,
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
              vaultRootURL: nil,
              isFocused: isFocused,
              focusRequestID: focusRequestID,
              focusPlacement: focusPlacement,
              isBlockSelectionActive: isBlockSelectionActive,
              font: projectOutlinerNSFont,
              textColor: ProjectOutlineBlockColorPalette.style(for: blockColorToken).nsTextColor,
              onCommand: onCommand,
              onReveal: onReveal,
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
          scheduleMenuChip(for: task)
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
      if block.text == title {
        block.text = ""
      }
    }
  }

  private func scheduleMenuChip(for task: TimelineProjectListWindowSnapshot.Task) -> some View {
    Button {
      scheduleMenuTaskID = task.id
    } label: {
      if let dateText = task.dateText {
        HStack(spacing: 3) {
          Text(dateText)
            .lineLimit(1)
          if task.metadataIndicators.isRecurring {
            Image(systemName: "repeat")
              .imageScale(.small)
          }
        }
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
    .help("날짜와 반복")
    .popover(
      isPresented: Binding(
        get: { scheduleMenuTaskID == task.id },
        set: { isPresented in
          if !isPresented {
            scheduleMenuTaskID = nil
          }
        }
      ),
      arrowEdge: .bottom
    ) {
      if let taskEditConfiguration {
        ProjectOutlineSchedulePopover(
          task: task,
          initialFields: taskEditConfiguration.initialFields(task),
          loadFields: {
            await taskEditConfiguration.loadFields(
              task.id,
              taskEditConfiguration.initialFields(task)
            )
          },
          saveFields: { fields in
            try await taskEditConfiguration.saveFields(task.id, fields)
          },
          recurringCompletionCount: recurringCompletionCount,
          projectColor: projectColor
        )
      } else {
        ProjectOutlineScheduleFallbackMenu(
          task: task,
          recurringCompletionCount: recurringCompletionCount,
          projectColor: projectColor,
          onSelect: { section in
            scheduleMenuTaskID = nil
            onOpenTaskSection(task.id, section)
          }
        )
      }
    }
  }

  private func taskTitleBinding(for task: TimelineProjectListWindowSnapshot.Task) -> Binding<String> {
    Binding(
      get: {
        if !block.text.isEmpty {
          return block.text
        }
        if taskTitleDraftTaskID == task.id {
          return taskTitleDraft
        }
        return task.title
      },
      set: {
        block.text = ""
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
