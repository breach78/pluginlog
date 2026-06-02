import Foundation

enum ProjectOutlineMutationEngine {
  static func visibleIndices(in document: ProjectOutlineDocument) -> [Int] {
    var indices: [Int] = []
    var collapsedDepth: Int?

    for index in document.blocks.indices {
      let block = document.blocks[index]
      if let hiddenDepth = collapsedDepth {
        if block.depth > hiddenDepth {
          continue
        }
        collapsedDepth = nil
      }

      indices.append(index)
      if block.childrenCollapsed, hasChildren(at: index, in: document) {
        collapsedDepth = block.depth
      }
    }

    return indices
  }

  static func visibleIndices(
    in document: ProjectOutlineDocument,
    focusRootID: UUID?
  ) -> [Int] {
    guard let focusRootID,
      let rootIndex = document.blocks.firstIndex(where: { $0.id == focusRootID })
    else {
      return visibleIndices(in: document)
    }

    let rootRange = subtreeRange(at: rootIndex, in: document)
    var indices: [Int] = []
    var collapsedDepth: Int?

    for index in rootRange {
      let block = document.blocks[index]
      if let hiddenDepth = collapsedDepth {
        if block.depth > hiddenDepth {
          continue
        }
        collapsedDepth = nil
      }

      indices.append(index)
      if index != rootIndex,
        block.childrenCollapsed,
        hasChildren(at: index, in: document)
      {
        collapsedDepth = block.depth
      }
    }

    return indices
  }

  static func subtreeRange(at index: Int, in document: ProjectOutlineDocument) -> Range<Int> {
    guard document.blocks.indices.contains(index) else { return index..<index }
    let depth = document.blocks[index].depth
    var end = index + 1
    while end < document.blocks.count, document.blocks[end].depth > depth {
      end += 1
    }
    return index..<end
  }

  static func normalizedSubtree(
    blockID: UUID,
    in document: ProjectOutlineDocument
  ) -> [ProjectOutlineBlock]? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return nil
    }
    return normalizedBlocks(Array(document.blocks[subtreeRange(at: index, in: document)]))
  }

  @discardableResult
  static func removeSubtree(
    blockID: UUID,
    from document: inout ProjectOutlineDocument
  ) -> [ProjectOutlineBlock]? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return nil
    }
    let range = subtreeRange(at: index, in: document)
    let removed = Array(document.blocks[range])
    document.blocks.removeSubrange(range)
    return normalizedBlocks(removed)
  }

  static func appendNormalizedSubtree(
    _ blocks: [ProjectOutlineBlock],
    to document: inout ProjectOutlineDocument
  ) {
    let normalized = normalizedBlocks(blocks)
    guard !normalized.isEmpty else { return }
    if document.blocks.count == 1,
      let block = document.blocks.first,
      block.text.isEmpty,
      block.taskBinding == nil,
      !block.childrenCollapsed,
      block.colorToken == nil
    {
      document.blocks = normalized
    } else {
      document.blocks.append(contentsOf: normalized)
    }
  }

  @discardableResult
  static func insertSiblingAfterSubtree(
    blockID: UUID,
    in document: inout ProjectOutlineDocument
  ) -> ProjectOutlineInsertionResult? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return nil
    }
    let inserted = ProjectOutlineBlock(depth: document.blocks[index].depth, text: "")
    document.blocks.insert(inserted, at: subtreeRange(at: index, in: document).upperBound)
    return ProjectOutlineInsertionResult(insertedBlockID: inserted.id, focusedBlockID: inserted.id)
  }

  @discardableResult
  static func insertFirstChild(
    blockID: UUID,
    in document: inout ProjectOutlineDocument
  ) -> ProjectOutlineInsertionResult? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return nil
    }
    let inserted = ProjectOutlineBlock(depth: document.blocks[index].depth + 1, text: "")
    document.blocks.insert(inserted, at: index + 1)
    return ProjectOutlineInsertionResult(insertedBlockID: inserted.id, focusedBlockID: inserted.id)
  }

  static func hasChildren(at index: Int, in document: ProjectOutlineDocument) -> Bool {
    let next = index + 1
    guard document.blocks.indices.contains(index), document.blocks.indices.contains(next) else {
      return false
    }
    return document.blocks[next].depth > document.blocks[index].depth
  }

  static func hasChildren(blockID: UUID, in document: ProjectOutlineDocument) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return false
    }
    return hasChildren(at: index, in: document)
  }

  static func parentID(for blockID: UUID, in document: ProjectOutlineDocument) -> UUID? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      let parentIndex = parentIndex(for: index, in: document)
    else {
      return nil
    }
    return document.blocks[parentIndex].id
  }

  static func ancestorIDs(for blockID: UUID, in document: ProjectOutlineDocument) -> [UUID] {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return []
    }
    var ancestors: [UUID] = []
    var currentIndex = index
    while let parentIndex = parentIndex(for: currentIndex, in: document) {
      ancestors.insert(document.blocks[parentIndex].id, at: 0)
      currentIndex = parentIndex
    }
    return ancestors
  }

  static func previousSiblingID(for blockID: UUID, in document: ProjectOutlineDocument) -> UUID? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      let siblingIndex = previousSiblingIndex(before: index, in: document)
    else {
      return nil
    }
    return document.blocks[siblingIndex].id
  }

  static func nextSiblingID(for blockID: UUID, in document: ProjectOutlineDocument) -> UUID? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      let siblingIndex = nextSiblingIndex(after: index, in: document)
    else {
      return nil
    }
    return document.blocks[siblingIndex].id
  }

  @discardableResult
  static func indentBlock(id blockID: UUID, in document: inout ProjectOutlineDocument) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      previousSiblingIndex(before: index, in: document) != nil
    else {
      return false
    }

    shiftDepths(in: subtreeRange(at: index, in: document), by: 1, document: &document)
    return true
  }

  @discardableResult
  static func outdentBlock(id blockID: UUID, in document: inout ProjectOutlineDocument) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      document.blocks[index].depth > 0
    else {
      return false
    }

    let originalRange = subtreeRange(at: index, in: document)
    guard let parentIndex = parentIndex(for: index, in: document) else { return false }
    let parentRange = subtreeRange(at: parentIndex, in: document)
    var subtree = Array(document.blocks[originalRange])
    for subtreeIndex in subtree.indices {
      subtree[subtreeIndex].depth = max(0, subtree[subtreeIndex].depth - 1)
    }

    document.blocks.removeSubrange(originalRange)
    let insertionIndex = parentRange.upperBound - originalRange.count
    document.blocks.insert(contentsOf: subtree, at: insertionIndex)
    return true
  }

  @discardableResult
  static func indentSelection(ids selectedIDs: [UUID], in document: inout ProjectOutlineDocument) -> Bool {
    guard let selection = selectedRootRanges(for: selectedIDs, in: document),
      let firstRoot = selection.rootIndices.first,
      previousSiblingIndex(before: firstRoot, in: document) != nil
    else {
      return false
    }

    shiftDepths(in: selection.movingRange, by: 1, document: &document)
    return true
  }

  @discardableResult
  static func outdentSelection(ids selectedIDs: [UUID], in document: inout ProjectOutlineDocument) -> Bool {
    guard let selection = selectedRootRanges(for: selectedIDs, in: document),
      let firstRoot = selection.rootIndices.first,
      document.blocks[firstRoot].depth > 0,
      let parentIndex = parentIndex(for: firstRoot, in: document)
    else {
      return false
    }

    let parentRange = subtreeRange(at: parentIndex, in: document)
    var movingSubtree = Array(document.blocks[selection.movingRange])
    for index in movingSubtree.indices {
      movingSubtree[index].depth = max(0, movingSubtree[index].depth - 1)
    }

    document.blocks.removeSubrange(selection.movingRange)
    let insertionIndex = parentRange.upperBound - selection.movingRange.count
    document.blocks.insert(contentsOf: movingSubtree, at: insertionIndex)
    return true
  }

  @discardableResult
  static func moveBlockUp(id blockID: UUID, in document: inout ProjectOutlineDocument) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      let siblingIndex = previousSiblingIndex(before: index, in: document)
    else {
      return false
    }

    let movingRange = subtreeRange(at: index, in: document)
    let movingSubtree = Array(document.blocks[movingRange])
    document.blocks.removeSubrange(movingRange)
    document.blocks.insert(contentsOf: movingSubtree, at: siblingIndex)
    return true
  }

  @discardableResult
  static func moveBlockDown(id blockID: UUID, in document: inout ProjectOutlineDocument) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
      let siblingIndex = nextSiblingIndex(after: index, in: document)
    else {
      return false
    }

    let movingRange = subtreeRange(at: index, in: document)
    let siblingRange = subtreeRange(at: siblingIndex, in: document)
    let movingSubtree = Array(document.blocks[movingRange])
    document.blocks.removeSubrange(movingRange)
    let insertionIndex = siblingRange.upperBound - movingRange.count
    document.blocks.insert(contentsOf: movingSubtree, at: insertionIndex)
    return true
  }

  @discardableResult
  static func moveBlock(
    id blockID: UUID,
    to targetID: UUID,
    placement: ProjectOutlineDropPlacement,
    in document: inout ProjectOutlineDocument
  ) -> Bool {
    guard blockID != targetID,
      let sourceIndex = document.blocks.firstIndex(where: { $0.id == blockID }),
      let targetIndex = document.blocks.firstIndex(where: { $0.id == targetID })
    else {
      return false
    }

    let sourceRange = subtreeRange(at: sourceIndex, in: document)
    guard !sourceRange.contains(targetIndex) else { return false }

    var movingSubtree = Array(document.blocks[sourceRange])
    document.blocks.removeSubrange(sourceRange)

    guard let adjustedTargetIndex = document.blocks.firstIndex(where: { $0.id == targetID }) else {
      return false
    }
    let insertionIndex: Int
    let targetDepth = document.blocks[adjustedTargetIndex].depth
    let nextRootDepth: Int
    switch placement {
    case .before:
      insertionIndex = adjustedTargetIndex
      nextRootDepth = targetDepth
    case .after:
      insertionIndex = subtreeRange(at: adjustedTargetIndex, in: document).upperBound
      nextRootDepth = targetDepth
    case .child:
      insertionIndex = subtreeRange(at: adjustedTargetIndex, in: document).upperBound
      nextRootDepth = targetDepth + 1
    }

    let depthDelta = nextRootDepth - movingSubtree[0].depth
    for index in movingSubtree.indices {
      movingSubtree[index].depth = max(0, movingSubtree[index].depth + depthDelta)
    }
    document.blocks.insert(contentsOf: movingSubtree, at: insertionIndex)
    return true
  }

  @discardableResult
  static func deleteBlockReattachingChildren(
    id blockID: UUID,
    in document: inout ProjectOutlineDocument
  ) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return false
    }

    let range = subtreeRange(at: index, in: document)
    let deletedDepth = document.blocks[index].depth
    let deletedIsTaskBlock = document.blocks[index].isTaskBlock
    let descendants = Array(document.blocks[range.dropFirst()])
    let previousSiblingIndex = previousSiblingIndex(before: index, in: document)
    let hasReattachTarget =
      if deletedIsTaskBlock {
        previousSiblingIndex.map { document.blocks[$0].isTaskBlock } ?? false
      } else {
        previousSiblingIndex != nil
      }
    document.blocks.removeSubrange(range)

    guard !descendants.isEmpty else { return true }
    let reattached = descendants.map { block in
      var next = block
      if !hasReattachTarget {
        next.depth = max(deletedDepth, next.depth - 1)
      }
      return next
    }
    document.blocks.insert(contentsOf: reattached, at: index)
    return true
  }

  @discardableResult
  static func backspaceAtStart(
    blockID: UUID,
    in document: inout ProjectOutlineDocument
  ) -> Bool {
    backspaceAtStartResult(blockID: blockID, in: &document) != nil
  }

  @discardableResult
  static func backspaceAtStartResult(
    blockID: UUID,
    in document: inout ProjectOutlineDocument
  ) -> ProjectOutlineBackspaceResult? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return nil
    }
    let visible = visibleIndices(in: document)
    guard let visiblePosition = visible.firstIndex(of: index), visiblePosition > 0 else {
      return outdentBlock(id: blockID, in: &document)
        ? ProjectOutlineBackspaceResult(focusedBlockID: blockID, focusOffset: nil)
        : nil
    }

    let previousIndex = visible[visiblePosition - 1]
    guard !document.blocks[previousIndex].isTaskBlock,
      !document.blocks[index].isTaskBlock
    else {
      return outdentBlock(id: blockID, in: &document)
        ? ProjectOutlineBackspaceResult(focusedBlockID: blockID, focusOffset: nil)
        : nil
    }
    guard !hasChildren(at: index, in: document) else { return nil }

    if document.blocks[index].text.isEmpty {
      document.blocks.remove(at: index)
      return ProjectOutlineBackspaceResult(
        focusedBlockID: document.blocks[previousIndex].id,
        focusOffset: document.blocks[previousIndex].text.utf16.count
      )
    }

    let mergeOffset = document.blocks[previousIndex].text.utf16.count
    let currentText = document.blocks[index].text
    document.blocks[previousIndex].text += currentText
    document.blocks.remove(at: index)
    return ProjectOutlineBackspaceResult(
      focusedBlockID: document.blocks[previousIndex].id,
      focusOffset: mergeOffset
    )
  }

  @discardableResult
  static func deleteAtEnd(
    blockID: UUID,
    in document: inout ProjectOutlineDocument
  ) -> Bool {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return false
    }
    let visible = visibleIndices(in: document)
    guard let visiblePosition = visible.firstIndex(of: index),
      visiblePosition + 1 < visible.count
    else {
      return false
    }

    let nextIndex = visible[visiblePosition + 1]
    guard !document.blocks[index].isTaskBlock,
      !document.blocks[nextIndex].isTaskBlock
    else {
      return false
    }

    document.blocks[index].text += document.blocks[nextIndex].text
    document.blocks.remove(at: nextIndex)
    return true
  }

  @discardableResult
  static func insertFromEnter(
    blockID: UUID,
    textOffset: Int,
    hasExpandedChildrenOverride: Bool? = nil,
    in document: inout ProjectOutlineDocument
  ) -> ProjectOutlineInsertionResult? {
    guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else {
      return nil
    }

    let clampedOffset = min(max(0, textOffset), document.blocks[index].text.count)
    if clampedOffset == 0 {
      let inserted = ProjectOutlineBlock(depth: document.blocks[index].depth, text: "")
      document.blocks.insert(inserted, at: index)
      return ProjectOutlineInsertionResult(insertedBlockID: inserted.id, focusedBlockID: blockID)
    }

    if clampedOffset < document.blocks[index].text.count {
      let text = document.blocks[index].text
      let splitIndex = text.index(text.startIndex, offsetBy: clampedOffset)
      document.blocks[index].text = String(text[..<splitIndex])
      let inserted = ProjectOutlineBlock(
        depth: document.blocks[index].depth,
        text: String(text[splitIndex...])
      )
      document.blocks.insert(inserted, at: subtreeRange(at: index, in: document).upperBound)
      return ProjectOutlineInsertionResult(insertedBlockID: inserted.id, focusedBlockID: inserted.id)
    }

    let insertIndex: Int
    let insertDepth: Int
    let hasExpandedChildren = hasExpandedChildrenOverride
      ?? (hasChildren(at: index, in: document) && !document.blocks[index].childrenCollapsed)
    if hasExpandedChildren {
      insertIndex = index + 1
      insertDepth = document.blocks[index].depth + 1
    } else {
      insertIndex = subtreeRange(at: index, in: document).upperBound
      insertDepth = document.blocks[index].depth
    }

    let inserted = ProjectOutlineBlock(depth: insertDepth, text: "")
    document.blocks.insert(inserted, at: insertIndex)
    return ProjectOutlineInsertionResult(insertedBlockID: inserted.id, focusedBlockID: inserted.id)
  }

  private static func shiftDepths(
    in range: Range<Int>,
    by delta: Int,
    document: inout ProjectOutlineDocument
  ) {
    for index in range {
      document.blocks[index].depth = max(0, document.blocks[index].depth + delta)
    }
  }

  private static func normalizedBlocks(_ blocks: [ProjectOutlineBlock]) -> [ProjectOutlineBlock] {
    guard let rootDepth = blocks.first?.depth else { return [] }
    return blocks.map { block in
      var next = block
      next.depth = max(0, block.depth - rootDepth)
      return next
    }
  }

  private static func selectedRootRanges(
    for selectedIDs: [UUID],
    in document: ProjectOutlineDocument
  ) -> (rootIndices: [Int], movingRange: Range<Int>)? {
    let selectedSet = Set(selectedIDs)
    guard !selectedSet.isEmpty else { return nil }

    let selectedIndices = document.blocks.indices.filter {
      selectedSet.contains(document.blocks[$0].id)
    }
    guard let firstSelected = selectedIndices.first,
      let lastSelected = selectedIndices.last
    else {
      return nil
    }

    let rootIndices = selectedIndices.filter { index in
      guard let parentIndex = parentIndex(for: index, in: document) else { return true }
      return !selectedSet.contains(document.blocks[parentIndex].id)
    }
    guard !rootIndices.isEmpty else { return nil }

    let rootDepth = document.blocks[rootIndices[0]].depth
    guard rootIndices.allSatisfy({ document.blocks[$0].depth == rootDepth }) else {
      return nil
    }

    let firstRange = subtreeRange(at: rootIndices[0], in: document)
    let lastRange = subtreeRange(at: rootIndices[rootIndices.count - 1], in: document)
    let movingRange = firstRange.lowerBound..<lastRange.upperBound
    guard movingRange.lowerBound == firstSelected,
      movingRange.upperBound == lastSelected + 1
    else {
      return nil
    }
    guard movingRange.allSatisfy({ selectedSet.contains(document.blocks[$0].id) }) else {
      return nil
    }

    let parentIDs = Set(rootIndices.map { parentIndex(for: $0, in: document).map { document.blocks[$0].id } })
    guard parentIDs.count == 1 else { return nil }
    return (rootIndices, movingRange)
  }

  private static func parentIndex(for index: Int, in document: ProjectOutlineDocument) -> Int? {
    guard document.blocks.indices.contains(index) else { return nil }
    let parentDepth = document.blocks[index].depth - 1
    guard parentDepth >= 0 else { return nil }
    var cursor = index - 1
    while cursor >= 0 {
      if document.blocks[cursor].depth == parentDepth {
        return cursor
      }
      cursor -= 1
    }
    return nil
  }

  private static func previousSiblingIndex(
    before index: Int,
    in document: ProjectOutlineDocument
  ) -> Int? {
    guard document.blocks.indices.contains(index) else { return nil }
    let depth = document.blocks[index].depth
    var cursor = index - 1
    while cursor >= 0 {
      if document.blocks[cursor].depth == depth {
        return cursor
      }
      if document.blocks[cursor].depth < depth {
        return nil
      }
      cursor -= 1
    }
    return nil
  }

  private static func nextSiblingIndex(
    after index: Int,
    in document: ProjectOutlineDocument
  ) -> Int? {
    guard document.blocks.indices.contains(index) else { return nil }
    let depth = document.blocks[index].depth
    var cursor = subtreeRange(at: index, in: document).upperBound
    while cursor < document.blocks.count {
      if document.blocks[cursor].depth == depth {
        return cursor
      }
      if document.blocks[cursor].depth < depth {
        return nil
      }
      cursor += 1
    }
    return nil
  }
}
