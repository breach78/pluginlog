import AppKit
import Foundation

extension OutlinerView {
  func selectProject(_ projectID: UUID, persist: Bool = true) {
    syncCurrentProjectSnapshot()
    guard let project = syncedProjects.first(where: { $0.id == projectID }) else { return }
    currentProjectID = project.id
    replaceCurrentDocument(project.document)
    pendingSelectionRequest = nil
    focusedNodeID = nil
    clearBlockSelection()
    zoomPath = []
    zoomScreenHistory = []
    if persist {
      syncEditorSessionState(triggerAutoPush: false)
    }
  }

  func updateZoomScreen(to newZoomPath: [UUID], recordHistory: Bool = true) {
    guard newZoomPath != zoomPath else { return }
    if recordHistory {
      zoomScreenHistory.append(zoomPath)
    }
    zoomPath = newZoomPath
    clearBlockSelection()
    pendingSelectionRequest = nil
    focusedNodeID = nil
  }

  func handleZoomIn(id: UUID) {
    updateZoomScreen(to: ancestryPath(to: id))
  }

  func handleZoomInShortcut() {
    guard let focusedNodeID,
      let focusedNode = OutlineNodeTreeNavigator.findNode(id: focusedNodeID, in: uiDocument.rootNodes),
      !focusedNode.type.isReference
    else {
      return
    }
    handleZoomIn(id: focusedNodeID)
  }

  func handleZoomOutShortcut() {
    guard !zoomPath.isEmpty else { return }
    if zoomPath.count == 1 {
      updateZoomScreen(to: [])
    } else {
      updateZoomScreen(to: Array(zoomPath.dropLast()))
    }
  }

  func handleNavigateBackShortcut() {
    guard !zoomScreenHistory.isEmpty else { return }
    let previousZoomPath = zoomScreenHistory.removeLast()
    updateZoomScreen(to: previousZoomPath, recordHistory: false)
  }

  func handleReminderDueShortcut(_ preset: OutlinerReminderQuickDuePreset) {
    guard let focusedNodeID,
      let focusedNode = OutlineNodeTreeNavigator.findNode(id: focusedNodeID, in: uiDocument.rootNodes),
      focusedNode.type.isTask
    else {
      return
    }
    setReminderDuePreset(preset, for: focusedNodeID)
  }

  func handleClearReminderDueShortcut() {
    guard let focusedNodeID,
      let focusedNode = OutlineNodeTreeNavigator.findNode(id: focusedNodeID, in: uiDocument.rootNodes),
      focusedNode.type.isTask
    else {
      return
    }
    clearReminderDue(for: focusedNodeID)
  }

  func handleCycleReminderRecurrenceShortcut() {
    guard let focusedNodeID,
      let focusedNode = OutlineNodeTreeNavigator.findNode(id: focusedNodeID, in: uiDocument.rootNodes),
      focusedNode.type.isTask
    else {
      return
    }
    cycleReminderRecurrence(for: focusedNodeID)
  }

  func handleCycleReminderPriorityShortcut() {
    guard let focusedNodeID,
      let focusedNode = OutlineNodeTreeNavigator.findNode(id: focusedNodeID, in: uiDocument.rootNodes),
      focusedNode.type.isTask
    else {
      return
    }
    cycleReminderPriority(for: focusedNodeID)
  }

  func handleBreadcrumbNavigation(_ targetID: UUID?) {
    guard let targetID else {
      updateZoomScreen(to: [])
      return
    }

    updateZoomScreen(to: ancestryPath(to: targetID))
  }

  func blockReferenceToken(for nodeID: UUID) -> String {
    let canonicalID = OutlineNodeTreeNavigator.findNode(id: nodeID, in: uiDocument.rootNodes)?
      .canonicalID ?? nodeID
    return OutlineBlockReferenceCodec.token(projectID: currentProjectID, nodeID: canonicalID)
  }

  func copyBlockReferences(for nodeIDs: [UUID]) {
    guard !nodeIDs.isEmpty else { return }
    let tokenString = nodeIDs.map { blockReferenceToken(for: $0) }.joined(separator: "\n")
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(tokenString, forType: outlineMirrorPasteboardType)
    pasteboard.setString(tokenString, forType: .string)
  }

  func copyBlockReference(for nodeID: UUID) {
    copyBlockReferences(for: [nodeID])
  }

  func copySelectedBlockReferences() {
    copyBlockReferences(for: topLevelSelectedNodeIDsInDocumentOrder())
  }

  func parsedMirrorReferencesFromPasteboard() -> [OutlineParsedBlockReference] {
    let pasteboard = NSPasteboard.general
    let raw = pasteboard.string(forType: outlineMirrorPasteboardType)
      ?? pasteboard.string(forType: .string)
    guard let raw else { return [] }
    return raw
      .components(separatedBy: .newlines)
      .compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return OutlineDocument.parseBlockReference(trimmed)
      }
  }

  func mirrorPasteAnchorID() -> UUID? {
    if let selectedRootID = topLevelSelectedNodeIDsInDocumentOrder().last {
      return selectedRootID
    }
    if let focusedNodeID,
      OutlineNodeTreeNavigator.findNode(id: focusedNodeID, in: uiDocument.rootNodes) != nil
    {
      return focusedNodeID
    }
    return visibleEntries.last?.id
  }

  @discardableResult
  func handlePasteMirrorsFromPasteboard() -> Bool {
    let references = parsedMirrorReferencesFromPasteboard()
    guard !references.isEmpty,
      let initialAnchorID = mirrorPasteAnchorID()
    else {
      return false
    }

    var updatedDocument = uiDocument
    var insertionAnchorID = initialAnchorID
    var insertedNodeIDs: [UUID] = []

    for reference in references {
      let preferredProjectID = reference.projectID ?? currentProjectID
      guard let resolved = resolvedCloneSource(
        canonicalID: reference.targetID,
        preferredProjectID: preferredProjectID
      ),
        canInsertClone(of: resolved.node, from: resolved.projectID, onto: insertionAnchorID)
      else {
        continue
      }

      let cloneNode = OutlineNodeCloneEngine.cloneInstance(of: resolved.node)
      updatedDocument.insertAfter(nodeID: insertionAnchorID, newNode: cloneNode)
      insertionAnchorID = cloneNode.id
      insertedNodeIDs.append(cloneNode.id)
    }

    guard !insertedNodeIDs.isEmpty else { return false }

    exitActiveEditing()
    commitDocumentChange(updatedDocument)
    setBlockSelection(insertedNodeIDs, direction: nil)
    focusedNodeID = nil
    pendingSelectionRequest = nil
    return true
  }

  func documentByApplyingTextChange(
    id: UUID,
    newText: String,
    to baseDocument: OutlineDocument
  ) -> OutlineDocument {
    if let reference = OutlineDocument.parseBlockReference(newText),
      let resolved = resolvedCloneSource(
        canonicalID: reference.targetID,
        preferredProjectID: reference.projectID ?? currentProjectID
      ),
      canCloneResolvedNode(resolved.node, in: resolved.projectID, from: id)
    {
      return OutlineNodeCloneEngine.replaceNode(
        nodeID: id,
        withCloneOf: resolved.node,
        in: baseDocument
      )
    }

    var updatedDocument = baseDocument
    updatedDocument.updateNode(id: id) { node in
      node.text = newText
      node.referenceProjectID = nil
    }
    return updatedDocument
  }

  func handleTextChange(id: UUID, newText: String) {
    applyTextCommit(id: id, newText: newText, isClonedOverride: nil)
  }

  func handleNodePatch(_ patch: NodePatch) {
    if !selectedNodeIDs.isEmpty { clearBlockSelection() }

    let previousDocument = uiDocument
    let previousTreeIndex = snapshotCurrentDocumentTreeIndex()
    let updatedDocument = documentByApplyingTextChange(
      id: patch.nodeID,
      newText: patch.newText,
      to: previousDocument
    )
    let updatedTreeIndex = OutlineTreeIndex(document: updatedDocument)

    if patch.isCloned {
      commitMirroredSubtreeChange(updatedDocument, around: patch.nodeID, pushUndoSnapshot: false)
      return
    }

    guard let currentNode = previousTreeIndex.findNode(id: patch.nodeID),
      let updatedNode = updatedTreeIndex.findNode(id: patch.nodeID),
      currentNode.canonicalID == patch.canonicalID,
      updatedNode.canonicalID == patch.canonicalID,
      !currentNode.type.isReference,
      currentNode.type == updatedNode.type,
      currentNode.referenceProjectID == updatedNode.referenceProjectID
    else {
      commitDocumentChange(updatedDocument, pushUndoSnapshot: false)
      return
    }

    if OutlinerEditingGranularityFlags.useTextOverlay {
      updatePendingTextOverlay(for: patch.nodeID, newText: patch.newText)
    } else {
      applyCurrentProjectTextOnlyDocument(updatedDocument)
    }

    let syncSurfaceChange: OutlinerReminderPushPlanner.SyncSurfaceChange
    if OutlinerEditingGranularityFlags.useSyncGate {
      syncSurfaceChange = OutlinerReminderPushPlanner.classifyTextPatch(
        patch,
        oldTreeIndex: previousTreeIndex,
        newTreeIndex: updatedTreeIndex
      )
    } else {
      syncSurfaceChange = .noteBodyChanged(changedReminderProjectionContentIDs(
        from: previousDocument,
        to: updatedDocument
      ))
    }
    let changedContentIDs = syncSurfaceChange.contentIDs
    if !changedContentIDs.isEmpty {
      switch syncSurfaceChange {
      case .titleChanged:
        commitReminderMetadataDirectSave(for: patch.nodeID)
      case .completionChanged, .scheduleChanged, .noteBodyChanged:
        enqueueReminderPushContentIDs(changedContentIDs)
      case .noReminderChange:
        break
      }
    }

    syncEditorSessionState(triggerAutoPush: false)
    commitPendingReminderNoteSourceDirectSaveIfNeeded(
      excluding: reminderPushEditingBoundary
    )
  }

  private func applyTextCommit(id: UUID, newText: String, isClonedOverride: Bool?) {
    if !selectedNodeIDs.isEmpty { clearBlockSelection() }
    let updatedDocument = documentByApplyingTextChange(id: id, newText: newText, to: uiDocument)
    if isClonedOverride ?? nodeIsCloned(id: id) {
      commitMirroredSubtreeChange(updatedDocument, around: id, pushUndoSnapshot: false)
    } else {
      commitTextOnlyChange(updatedDocument)
    }
  }

  func handleStructuralChange(
    _ newDocument: OutlineDocument,
    triggerAutoPush: Bool = true
  ) {
    commitDocumentChange(
      newDocument,
      pushUndoSnapshot: false,
      triggerAutoPush: triggerAutoPush
    )
  }

  func handleInsertNewline(id: UUID, committedText: String, cursorPosition: Int) {
    clearBlockSelection()
    let baseDocument: OutlineDocument
    if let currentNode = OutlineNodeTreeNavigator.findNode(id: id, in: uiDocument.rootNodes),
      currentNode.text == committedText
    {
      baseDocument = uiDocument
    } else {
      baseDocument = documentByApplyingTextChange(id: id, newText: committedText, to: uiDocument)
    }

    if let result = OutlineNodeInsertionEngine.insertNewline(
      nodeID: id,
      cursorPosition: cursorPosition,
      isZoomRoot: zoomPath.last == id,
      in: baseDocument
    ) {
      if nodeIsCloned(id: id) {
        commitMirroredSubtreeChange(result.document, around: id)
      } else {
        outlineUndoManager.pushSnapshot(uiDocument, focusedNodeID: focusedNodeID)
        handleStructuralChange(result.document)
      }
      requestFocus(on: result.focusedNodeID, cursorPosition: result.cursorPosition)
    }
  }
}
