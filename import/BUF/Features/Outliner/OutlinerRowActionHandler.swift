import Foundation

struct NodePatch: Equatable, Sendable {
  let nodeID: UUID
  let canonicalID: UUID
  let oldText: String
  let newText: String
  let isCloned: Bool
}

struct DraftSessionBridge {
  let commitPatch: (NodePatch) -> Void
}

enum OutlinerEditingGranularityFlags {
  private static let useNodeDraftBufferKey = "debug.outliner.editing.useNodeDraftBuffer"
  private static let useNodePatchCommitKey = "debug.outliner.editing.useNodePatchCommit"
  private static let useDeferredIndexingKey = "debug.outliner.editing.useDeferredIndexing"
  private static let useSyncGateKey = "debug.outliner.editing.useSyncGate"
  private static let useTextOverlayKey = "debug.outliner.editing.useTextOverlay"
  private static let useBackgroundPersistenceKey =
    "debug.outliner.editing.useBackgroundPersistence"
  private static let enablePatchIntegrityCheckKey =
    "debug.outliner.editing.enablePatchIntegrityCheck"

  static var useNodeDraftBuffer: Bool {
    resolvedBool(forKey: useNodeDraftBufferKey, defaultValue: true)
  }

  static var useNodePatchCommit: Bool {
    resolvedBool(forKey: useNodePatchCommitKey, defaultValue: true)
  }

  static var useDeferredIndexing: Bool {
    resolvedBool(forKey: useDeferredIndexingKey, defaultValue: true)
  }

  static var useSyncGate: Bool {
    resolvedBool(forKey: useSyncGateKey, defaultValue: true)
  }

  static var useTextOverlay: Bool {
    resolvedBool(forKey: useTextOverlayKey, defaultValue: true)
  }

  static var useBackgroundPersistence: Bool {
    resolvedBool(forKey: useBackgroundPersistenceKey, defaultValue: true)
  }

  static var enablePatchIntegrityCheck: Bool {
#if DEBUG
    resolvedBool(forKey: enablePatchIntegrityCheckKey, defaultValue: true) && useNodePatchCommit
#else
    false
#endif
  }

  private static func resolvedBool(forKey key: String, defaultValue: Bool) -> Bool {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: key) != nil else { return defaultValue }
    return defaults.bool(forKey: key)
  }
}

struct OutlinerEditingIntegrityMismatch: Equatable {
  let projectID: UUID
  let titleMatches: Bool
  let documentMatches: Bool
  let taskStatesMatch: Bool
  let expectedTaskStateCount: Int
  let persistedTaskStateCount: Int
}

enum OutlinerEditingIntegrityVerifier {
  static func mismatch(
    projectID: UUID,
    expectedProject: OutlinerProject,
    expectedTaskStates: [UUID: OutlinerIntegratedTaskState],
    persistedSnapshot: OutlinerIntegratedStore.Snapshot?
  ) -> OutlinerEditingIntegrityMismatch? {
    guard let persistedSnapshot,
          let persistedProject = persistedSnapshot.projects.first(where: { $0.id == projectID })
    else {
      return OutlinerEditingIntegrityMismatch(
        projectID: projectID,
        titleMatches: false,
        documentMatches: false,
        taskStatesMatch: false,
        expectedTaskStateCount: expectedTaskStates.count,
        persistedTaskStateCount: persistedSnapshot?.taskStatesByContentID.count ?? 0
      )
    }

    let titleMatches = persistedProject.title == expectedProject.title
    let documentMatches = persistedProject.document == expectedProject.document
    let taskStatesMatch = persistedSnapshot.taskStatesByContentID == expectedTaskStates
    guard !(titleMatches && documentMatches && taskStatesMatch) else { return nil }

    return OutlinerEditingIntegrityMismatch(
      projectID: projectID,
      titleMatches: titleMatches,
      documentMatches: documentMatches,
      taskStatesMatch: taskStatesMatch,
      expectedTaskStateCount: expectedTaskStates.count,
      persistedTaskStateCount: persistedSnapshot.taskStatesByContentID.count
    )
  }
}

protocol OutlinerRowActionHandler {
  func normalizeTextBeforeCommit(nodeID: UUID, text: String) -> String
  func onTextEdit(nodeID: UUID, newText: String)
  func onToggleComplete(nodeID: UUID)
  func onToggleCollapse(nodeID: UUID)
  func onToggleType(nodeID: UUID)
  func onConvertReferenceToBullet(nodeID: UUID)
  func onCopyBlockReference(nodeID: UUID)
  func onCopySelectedBlockReferences()
  func onZoomIn(nodeID: UUID)
  func onDeleteSubtree(nodeID: UUID)
  func onInsertNewline(nodeID: UUID, committedText: String, cursorPosition: Int)
  func onDeleteBackwardAtStart(nodeID: UUID)
  func onIndent(nodeID: UUID, cursorPosition: Int)
  func onOutdent(nodeID: UUID, cursorPosition: Int)
  func onMoveLeftFromStart(nodeID: UUID)
  func onMoveRightFromEnd(nodeID: UUID)
  func onMoveUp(nodeID: UUID)
  func onMoveDown(nodeID: UUID)
  func onShiftMoveUp(nodeID: UUID)
  func onShiftMoveDown(nodeID: UUID)
  func onCommitAndToggleType(nodeID: UUID, committedText: String)
  func onCommandToggleSelection(nodeID: UUID)
  func onTextEditingBegan(nodeID: UUID)
  func onTextEditingEnded(nodeID: UUID)
  func onFocus(nodeID: UUID, cursorPosition: Int?)
  func onHoverChange(nodeID: UUID, isHovering: Bool)
  func onAddAttachment(nodeID: UUID)
  func onResolveReminderConflict(nodeID: UUID, action: OutlineNodeReminderConflictAction)
  func referenceSuggestions(for text: String) -> [OutlineBlockReferenceSuggestion]
  func onInsertReferenceSuggestion(nodeID: UUID, suggestion: OutlineBlockReferenceSuggestion)
  func onRequestedCursorApplied(nodeID: UUID)
  func onNavigateToReference(targetID: UUID, projectID: UUID?)
  func onReminderAction(nodeID: UUID, action: OutlinerReminderEditorAction)
}

final class ClosureOutlinerRowActionHandler: OutlinerRowActionHandler {
  private let normalizeTextBeforeCommitClosure: (UUID, String) -> String
  private let onTextEditClosure: (UUID, String) -> Void
  private let onToggleCompleteClosure: (UUID) -> Void
  private let onToggleCollapseClosure: (UUID) -> Void
  private let onToggleTypeClosure: (UUID) -> Void
  private let onConvertReferenceToBulletClosure: (UUID) -> Void
  private let onCopyBlockReferenceClosure: (UUID) -> Void
  private let onCopySelectedBlockReferencesClosure: () -> Void
  private let onZoomInClosure: (UUID) -> Void
  private let onDeleteSubtreeClosure: (UUID) -> Void
  private let onInsertNewlineClosure: (UUID, String, Int) -> Void
  private let onDeleteBackwardAtStartClosure: (UUID) -> Void
  private let onIndentClosure: (UUID, Int) -> Void
  private let onOutdentClosure: (UUID, Int) -> Void
  private let onMoveLeftFromStartClosure: (UUID) -> Void
  private let onMoveRightFromEndClosure: (UUID) -> Void
  private let onMoveUpClosure: (UUID) -> Void
  private let onMoveDownClosure: (UUID) -> Void
  private let onShiftMoveUpClosure: (UUID) -> Void
  private let onShiftMoveDownClosure: (UUID) -> Void
  private let onCommitAndToggleTypeClosure: (UUID, String) -> Void
  private let onCommandToggleSelectionClosure: (UUID) -> Void
  private let onTextEditingBeganClosure: (UUID) -> Void
  private let onTextEditingEndedClosure: (UUID) -> Void
  private let onFocusClosure: (UUID, Int?) -> Void
  private let onHoverChangeClosure: (UUID, Bool) -> Void
  private let onAddAttachmentClosure: (UUID) -> Void
  private let onResolveReminderConflictClosure: (UUID, OutlineNodeReminderConflictAction) -> Void
  private let referenceSuggestionsClosure: (String) -> [OutlineBlockReferenceSuggestion]
  private let onInsertReferenceSuggestionClosure: (UUID, OutlineBlockReferenceSuggestion) -> Void
  private let onRequestedCursorAppliedClosure: (UUID) -> Void
  private let onNavigateToReferenceClosure: (UUID, UUID?) -> Void
  private let onReminderActionClosure: (UUID, OutlinerReminderEditorAction) -> Void

  init(
    normalizeTextBeforeCommit: @escaping (UUID, String) -> String,
    onTextEdit: @escaping (UUID, String) -> Void,
    onToggleComplete: @escaping (UUID) -> Void,
    onToggleCollapse: @escaping (UUID) -> Void,
    onToggleType: @escaping (UUID) -> Void,
    onConvertReferenceToBullet: @escaping (UUID) -> Void,
    onCopyBlockReference: @escaping (UUID) -> Void,
    onCopySelectedBlockReferences: @escaping () -> Void = {},
    onZoomIn: @escaping (UUID) -> Void,
    onDeleteSubtree: @escaping (UUID) -> Void,
    onInsertNewline: @escaping (UUID, String, Int) -> Void,
    onDeleteBackwardAtStart: @escaping (UUID) -> Void,
    onIndent: @escaping (UUID, Int) -> Void,
    onOutdent: @escaping (UUID, Int) -> Void,
    onMoveLeftFromStart: @escaping (UUID) -> Void,
    onMoveRightFromEnd: @escaping (UUID) -> Void,
    onMoveUp: @escaping (UUID) -> Void,
    onMoveDown: @escaping (UUID) -> Void,
    onShiftMoveUp: @escaping (UUID) -> Void,
    onShiftMoveDown: @escaping (UUID) -> Void,
    onCommitAndToggleType: @escaping (UUID, String) -> Void,
    onCommandToggleSelection: @escaping (UUID) -> Void,
    onTextEditingBegan: @escaping (UUID) -> Void = { _ in },
    onTextEditingEnded: @escaping (UUID) -> Void = { _ in },
    onFocus: @escaping (UUID, Int?) -> Void,
    onHoverChange: @escaping (UUID, Bool) -> Void,
    onAddAttachment: @escaping (UUID) -> Void,
    onResolveReminderConflict: @escaping (UUID, OutlineNodeReminderConflictAction) -> Void,
    referenceSuggestions: @escaping (String) -> [OutlineBlockReferenceSuggestion] = { _ in [] },
    onInsertReferenceSuggestion: @escaping (UUID, OutlineBlockReferenceSuggestion) -> Void,
    onRequestedCursorApplied: @escaping (UUID) -> Void = { _ in },
    onNavigateToReference: @escaping (UUID, UUID?) -> Void = { _, _ in },
    onReminderAction: @escaping (UUID, OutlinerReminderEditorAction) -> Void
  ) {
    normalizeTextBeforeCommitClosure = normalizeTextBeforeCommit
    onTextEditClosure = onTextEdit
    onToggleCompleteClosure = onToggleComplete
    onToggleCollapseClosure = onToggleCollapse
    onToggleTypeClosure = onToggleType
    onConvertReferenceToBulletClosure = onConvertReferenceToBullet
    onCopyBlockReferenceClosure = onCopyBlockReference
    onCopySelectedBlockReferencesClosure = onCopySelectedBlockReferences
    onZoomInClosure = onZoomIn
    onDeleteSubtreeClosure = onDeleteSubtree
    onInsertNewlineClosure = onInsertNewline
    onDeleteBackwardAtStartClosure = onDeleteBackwardAtStart
    onIndentClosure = onIndent
    onOutdentClosure = onOutdent
    onMoveLeftFromStartClosure = onMoveLeftFromStart
    onMoveRightFromEndClosure = onMoveRightFromEnd
    onMoveUpClosure = onMoveUp
    onMoveDownClosure = onMoveDown
    onShiftMoveUpClosure = onShiftMoveUp
    onShiftMoveDownClosure = onShiftMoveDown
    onCommitAndToggleTypeClosure = onCommitAndToggleType
    onCommandToggleSelectionClosure = onCommandToggleSelection
    onTextEditingBeganClosure = onTextEditingBegan
    onTextEditingEndedClosure = onTextEditingEnded
    onFocusClosure = onFocus
    onHoverChangeClosure = onHoverChange
    onAddAttachmentClosure = onAddAttachment
    onResolveReminderConflictClosure = onResolveReminderConflict
    referenceSuggestionsClosure = referenceSuggestions
    onInsertReferenceSuggestionClosure = onInsertReferenceSuggestion
    onRequestedCursorAppliedClosure = onRequestedCursorApplied
    onNavigateToReferenceClosure = onNavigateToReference
    onReminderActionClosure = onReminderAction
  }

  func normalizeTextBeforeCommit(nodeID: UUID, text: String) -> String {
    normalizeTextBeforeCommitClosure(nodeID, text)
  }

  func onTextEdit(nodeID: UUID, newText: String) { onTextEditClosure(nodeID, newText) }
  func onToggleComplete(nodeID: UUID) { onToggleCompleteClosure(nodeID) }
  func onToggleCollapse(nodeID: UUID) { onToggleCollapseClosure(nodeID) }
  func onToggleType(nodeID: UUID) { onToggleTypeClosure(nodeID) }
  func onConvertReferenceToBullet(nodeID: UUID) { onConvertReferenceToBulletClosure(nodeID) }
  func onCopyBlockReference(nodeID: UUID) { onCopyBlockReferenceClosure(nodeID) }
  func onCopySelectedBlockReferences() { onCopySelectedBlockReferencesClosure() }
  func onZoomIn(nodeID: UUID) { onZoomInClosure(nodeID) }
  func onDeleteSubtree(nodeID: UUID) { onDeleteSubtreeClosure(nodeID) }
  func onInsertNewline(nodeID: UUID, committedText: String, cursorPosition: Int) {
    onInsertNewlineClosure(nodeID, committedText, cursorPosition)
  }
  func onDeleteBackwardAtStart(nodeID: UUID) { onDeleteBackwardAtStartClosure(nodeID) }
  func onIndent(nodeID: UUID, cursorPosition: Int) { onIndentClosure(nodeID, cursorPosition) }
  func onOutdent(nodeID: UUID, cursorPosition: Int) { onOutdentClosure(nodeID, cursorPosition) }
  func onMoveLeftFromStart(nodeID: UUID) { onMoveLeftFromStartClosure(nodeID) }
  func onMoveRightFromEnd(nodeID: UUID) { onMoveRightFromEndClosure(nodeID) }
  func onMoveUp(nodeID: UUID) { onMoveUpClosure(nodeID) }
  func onMoveDown(nodeID: UUID) { onMoveDownClosure(nodeID) }
  func onShiftMoveUp(nodeID: UUID) { onShiftMoveUpClosure(nodeID) }
  func onShiftMoveDown(nodeID: UUID) { onShiftMoveDownClosure(nodeID) }
  func onCommitAndToggleType(nodeID: UUID, committedText: String) {
    onCommitAndToggleTypeClosure(nodeID, committedText)
  }
  func onCommandToggleSelection(nodeID: UUID) { onCommandToggleSelectionClosure(nodeID) }
  func onTextEditingBegan(nodeID: UUID) { onTextEditingBeganClosure(nodeID) }
  func onTextEditingEnded(nodeID: UUID) { onTextEditingEndedClosure(nodeID) }
  func onFocus(nodeID: UUID, cursorPosition: Int?) { onFocusClosure(nodeID, cursorPosition) }
  func onHoverChange(nodeID: UUID, isHovering: Bool) {
    onHoverChangeClosure(nodeID, isHovering)
  }
  func onAddAttachment(nodeID: UUID) { onAddAttachmentClosure(nodeID) }
  func onResolveReminderConflict(nodeID: UUID, action: OutlineNodeReminderConflictAction) {
    onResolveReminderConflictClosure(nodeID, action)
  }
  func referenceSuggestions(for text: String) -> [OutlineBlockReferenceSuggestion] {
    referenceSuggestionsClosure(text)
  }
  func onInsertReferenceSuggestion(nodeID: UUID, suggestion: OutlineBlockReferenceSuggestion) {
    onInsertReferenceSuggestionClosure(nodeID, suggestion)
  }
  func onRequestedCursorApplied(nodeID: UUID) { onRequestedCursorAppliedClosure(nodeID) }
  func onNavigateToReference(targetID: UUID, projectID: UUID?) {
    onNavigateToReferenceClosure(targetID, projectID)
  }
  func onReminderAction(nodeID: UUID, action: OutlinerReminderEditorAction) {
    onReminderActionClosure(nodeID, action)
  }
}
