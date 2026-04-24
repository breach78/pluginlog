import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
// Root view shell + assembly only.
// Budget + split fence enforced by OutlinerReductionMilestoneTests.swift.
// OutlinerView.swift
// OutlinerFoundation.swift
// OutlinerInteractionOperations.swift
// OutlinerViewOperations.swift
// OutlinerViewSync.swift
// OutlinerReminderSync.swift
// OutlinerInlineEditors.swift
// OutlinerNodeRowViews.swift
struct OutlinerView: View {
  @EnvironmentObject var appState: AppState
  let renderProfile: OutlineRenderProfile = .logseqBaseline
  let outlinerSyncSessionID = "outliner-sync"
  @State var outlinerEditingSessionID = "outliner-edit-\(UUID().uuidString)"
  let preferredProjectID: UUID?
  let showsTaskAccessoryBand: Bool
  let hideCompletedOverride: Binding<Bool>?
  let topFadeHeight: CGFloat
  let usesIntrinsicProjectHeadingFadeMask: Bool
  var projects: [OutlinerProject] {
    projectedProjectsOverride ?? appState.resolvedRuntimeProjectionProjects()
  }
  @State var currentProjectID = OutlinerProject.sampleProject.id
  @State private var projectedProjectsOverride: [OutlinerProject]? = nil
  @StateObject private var selectionState = OutlinerSelectionState()
  @StateObject private var viewportState = OutlinerViewportState()
  @StateObject private var editState = OutlinerEditState()
  @State var firstSyncCompleted = false
  @StateObject var liveSync = OutlinerLiveSyncController()
  @State var integratedTaskStatesByContentID: [UUID: OutlinerTaskSessionOverlayState] = [:]
  var sidecarMetadataByReminderIdentifier: [String: OutlinerTaskSidecarMetadata] {
    appState.resolvedOutlinerSidecarMetadataByReminderIdentifier()
  }
  var sidecarMetadataByNodeID: [UUID: OutlinerTaskSidecarMetadata] {
    appState.resolvedOutlinerSidecarMetadataByNodeID()
  }
  var reminderMetadataByReminderIdentifier: [String: ReminderMetadataSnapshot] {
    appState.resolvedOutlinerReminderMetadataByReminderIdentifier()
  }
  var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot] {
    appState.resolvedOutlinerReminderMetadataByNodeID()
  }
  @State var completedVisibilityGraceNodeIDs: Set<UUID> = []
  @State var completedVisibilityGraceTasks: [UUID: Task<Void, Never>] = [:]
  @State var hasRestoredPersistedState = false
  @State var isRestoringPersistedState = false
  @StateObject var outlineUndoManager = OutlineUndoManager()
  @State var autoPushTask: Task<Void, Never>?
  @State var reminderNoteDirectCommitTask: Task<Void, Never>?
  @State var isAutoPushing = false
  @State var hasPendingAutoPush = false
  @State var hasPendingDirectReminderNoteCommit = false
  @State var pendingReminderPushContentIDs: Set<UUID> = []
  @State var reminderPushEditingBoundary: ReminderSubtreeCommitBoundary?
  @State var pendingAutoPushDeferredBoundary: ReminderSubtreeCommitBoundary?
  @State var reminderPushLastEditedAtByContentID: [UUID: Date] = [:]
  var taskFeatureSidecarByReminderExternalIdentifier: [String: ReminderTaskFeatureSidecarRecord] {
    appState.resolvedTaskFeatureSidecarByReminderExternalIdentifier()
  }
  var taskSourceRuntimeStateByReminderExternalIdentifier:
    [String: ReminderTaskSourceRuntimeState] {
    appState.resolvedTaskSourceRuntimeStateByReminderExternalIdentifier()
  }
  @State var pendingProjectDetailSnapshotReload = false
  @State var projectDetailSnapshotReloadTask: Task<Void, Never>?
  @State var hasPendingRemotePull = false
  @State var reminderConflictResolutionContentIDs: Set<UUID> = []
  @State var expandedReminderConflictDiffContentIDs: Set<UUID> = []
  @StateObject var localKeyMonitor = OutlineLocalKeyMonitor()
  @State var canonicalInstanceCounts: [UUID: Int] = [:]
  @State private var currentDocumentTreeIndex = OutlineTreeIndex(
    document: OutlinerProject.sampleProject.document
  )
  @State private var pendingTextOverlay: [UUID: String] = [:]
  @State var initialRestoreTask: Task<Void, Never>?
  @State var initialSnapshotRefreshTask: Task<Void, Never>?
  @State var hoverResumeTask: Task<Void, Never>?
  @State var currentProjectAccentColorHex: String?
  init(
    preferredProjectID: UUID? = nil,
    showsTaskAccessoryBand: Bool = true,
    hideCompleted: Binding<Bool>? = nil,
    topFadeHeight: CGFloat = OutlinerCanvasMetrics.topFadeHeight,
    usesIntrinsicProjectHeadingFadeMask: Bool = true
  ) {
    self.preferredProjectID = preferredProjectID
    self.showsTaskAccessoryBand = showsTaskAccessoryBand
    self.hideCompletedOverride = hideCompleted
    self.topFadeHeight = topFadeHeight
    self.usesIntrinsicProjectHeadingFadeMask = usesIntrinsicProjectHeadingFadeMask
  }

  var focusedNodeID: UUID? {
    get { selectionState.focusedNodeID }
    nonmutating set { selectionState.focusedNodeID = newValue }
  }

  var pendingSelectionRequest: OutlineNodeSelectionRequest? {
    get { selectionState.pendingSelectionRequest }
    nonmutating set { selectionState.pendingSelectionRequest = newValue }
  }

  var isProjectTitleFocused: Bool {
    get { selectionState.isProjectTitleFocused }
    nonmutating set { selectionState.isProjectTitleFocused = newValue }
  }

  var selectedNodeIDs: Set<UUID> {
    get { selectionState.selectedNodeIDs }
    nonmutating set { selectionState.selectedNodeIDs = newValue }
  }

  var selectedNodeOrder: [UUID] {
    get { selectionState.selectedNodeOrder }
    nonmutating set { selectionState.selectedNodeOrder = newValue }
  }

  var blockSelectionLeadNodeID: UUID? {
    get { selectionState.blockSelectionLeadNodeID }
    nonmutating set { selectionState.blockSelectionLeadNodeID = newValue }
  }

  var blockSelectionDirection: OutlineBlockSelectionDirection? {
    get { selectionState.blockSelectionDirection }
    nonmutating set { selectionState.blockSelectionDirection = newValue }
  }

  var zoomPath: [UUID] {
    get { viewportState.zoomPath }
    nonmutating set { viewportState.zoomPath = newValue }
  }

  var zoomScreenHistory: [[UUID]] {
    get { viewportState.zoomScreenHistory }
    nonmutating set { viewportState.zoomScreenHistory = newValue }
  }

  var localHideCompleted: Bool {
    get { editState.localHideCompleted }
    nonmutating set { editState.localHideCompleted = newValue }
  }

  var isSearchBarVisible: Bool {
    get { editState.isSearchBarVisible }
    nonmutating set { editState.isSearchBarVisible = newValue }
  }

  var searchQuery: String {
    get { editState.searchQuery }
    nonmutating set { editState.searchQuery = newValue }
  }

  var dropTargetNodeID: UUID? {
    get { editState.dropTargetNodeID }
    nonmutating set { editState.dropTargetNodeID = newValue }
  }

  var dropPlacement: OutlineNodeDragDropEngine.Placement? {
    get { editState.dropPlacement }
    nonmutating set { editState.dropPlacement = newValue }
  }

  var hoveredNodeID: UUID? {
    get { editState.hoveredNodeID }
    nonmutating set { editState.hoveredNodeID = newValue }
  }

  var isHoverSuppressedForScroll: Bool {
    get { editState.isHoverSuppressedForScroll }
    nonmutating set { editState.isHoverSuppressedForScroll = newValue }
  }

  var visibleEntries: [OutlineFlattenedEntry] {
    get { viewportState.visibleEntries }
    nonmutating set { viewportState.visibleEntries = newValue }
  }

  var visibleTreeNodes: [OutlineVisibleTreeNode] {
    get { viewportState.visibleTreeNodes }
    nonmutating set { viewportState.visibleTreeNodes = newValue }
  }

  var visibleRowCount: Int {
    get { viewportState.visibleRowCount }
    nonmutating set { viewportState.visibleRowCount = newValue }
  }

  var virtualizationViewportHeight: CGFloat {
    get { viewportState.virtualizationViewportHeight }
    nonmutating set { viewportState.virtualizationViewportHeight = newValue }
  }

  var virtualizationVisibleStartIndex: Int {
    get { viewportState.virtualizationVisibleStartIndex }
    nonmutating set { viewportState.virtualizationVisibleStartIndex = newValue }
  }

  var isPreviewMode: Bool {
    AppRuntimeEnvironment.isRunningPreview
  }

  var effectiveDocument: OutlineDocument {
    guard OutlinerEditingGranularityFlags.useTextOverlay else { return document }
    return document.applyingTextOverlay(pendingTextOverlay)
  }

  var document: OutlineDocument {
    get {
      guard let currentProject = projects.first(where: { $0.id == currentProjectID }) else {
        return OutlinerProject.sampleProject.document
      }
      return currentProject.document
    }
    nonmutating set {
      replaceCurrentProjectDocument(newValue)
    }
  }

  var effectiveProjects: [OutlinerProject] {
    projects.map { project in
      guard project.id == currentProjectID else { return project }
      var updated = project
      updated.document = effectiveDocument
      return updated
    }
  }

  var uiDocument: OutlineDocument {
    OutlinerEditingGranularityFlags.useTextOverlay ? effectiveDocument : document
  }

  var syncedProjects: [OutlinerProject] {
    effectiveProjects
  }

  var hasLocalSyncWorkInFlight: Bool {
    isAutoPushing || autoPushTask != nil || reminderNoteDirectCommitTask != nil
  }

  var hasPendingTextOverlayWork: Bool {
    OutlinerEditingGranularityFlags.useTextOverlay && !pendingTextOverlay.isEmpty
  }

  var currentProjectTitle: String {
    syncedProjects.first(where: { $0.id == currentProjectID })?.title
      ?? OutlinerProject.defaultTitle
  }

  var currentProjectStage: ProjectProgressStage {
    appState.resolvedProjectProgressStage(forProjectID: currentProjectID)
  }

  var hideCompletedBinding: Binding<Bool> {
    hideCompletedOverride ?? Binding(
      get: { localHideCompleted },
      set: { localHideCompleted = $0 }
    )
  }

  var hideCompleted: Bool {
    hideCompletedBinding.wrappedValue
  }

  private var searchQueryBinding: Binding<String> {
    Binding(
      get: { searchQuery },
      set: { searchQuery = $0 }
    )
  }

  private var projectTitleAccentColor: NSColor {
    ColorHexCodec.nsColor(from: currentProjectAccentColorHex) ?? .labelColor
  }

  private var draftSession: DraftSessionBridge {
    DraftSessionBridge { patch in
      if OutlinerEditingGranularityFlags.useNodePatchCommit {
        handleNodePatch(patch)
      } else {
        handleTextChange(id: patch.nodeID, newText: patch.newText)
      }
    }
  }

  func replaceCurrentDocument(_ newDocument: OutlineDocument) {
    pendingTextOverlay = [:]
    replaceCurrentProjectDocument(newDocument)
  }

  func replaceProjectedProjects(
    _ nextProjects: [OutlinerProject],
    persistToAppState: Bool = true
  ) {
    if persistToAppState {
      projectedProjectsOverride = nil
      appState.installRuntimeProjectionProjects(nextProjects)
    } else {
      projectedProjectsOverride = nextProjects
    }
  }

  func installCurrentDocumentTreeIndex(_ newDocument: OutlineDocument) {
    currentDocumentTreeIndex = OutlineTreeIndex(document: newDocument)
  }

  func replaceCurrentProjectDocument(_ newDocument: OutlineDocument) {
    let nextProjects = projects.map { project in
      guard project.id == currentProjectID else { return project }
      return OutlinerProject(id: project.id, title: project.title, document: newDocument)
    }
    replaceProjectedProjects(nextProjects)
    currentDocumentTreeIndex = OutlineTreeIndex(document: newDocument)
  }

  func updatePendingTextOverlay(for nodeID: UUID, newText: String) {
    guard OutlinerEditingGranularityFlags.useTextOverlay else { return }

    var nextOverlay = pendingTextOverlay
    if let baseNode = OutlineNodeTreeNavigator.findNode(id: nodeID, in: document.rootNodes),
       baseNode.text == newText {
      nextOverlay.removeValue(forKey: nodeID)
    } else {
      nextOverlay[nodeID] = newText
    }
    pendingTextOverlay = nextOverlay
    currentDocumentTreeIndex = OutlineTreeIndex(
      document: document.applyingTextOverlay(nextOverlay)
    )
  }

  func snapshotCurrentDocumentTreeIndex() -> OutlineTreeIndex {
    currentDocumentTreeIndex
  }

  func currentTreeContainsClone(canonicalID: UUID) -> Bool {
    currentDocumentTreeIndex.isCloned(canonicalID: canonicalID)
  }

  func currentTreeNode(id: UUID) -> OutlineNode? {
    currentDocumentTreeIndex.findNode(id: id)
  }

  func currentTreeParentID(of id: UUID) -> UUID? {
    currentDocumentTreeIndex.parentOf(id: id)
  }

  func refreshCanonicalInstanceCounts(for projects: [OutlinerProject]) {
    canonicalInstanceCounts = OutlineTreeIndex.buildCanonicalInstanceCounts(for: projects)
  }

  private var orderedSelectedNodeIDs: [UUID] {
    uiDocument.flatten().map(\.id).filter { selectedNodeIDs.contains($0) }
  }

  func clearBlockSelection() {
    OutlineSelectionDiagnostics.log(
      "clearBlockSelection selectedCount=\(selectedNodeIDs.count) orderCount=\(selectedNodeOrder.count)"
    )
    selectedNodeIDs = []
    selectedNodeOrder = []
    blockSelectionLeadNodeID = nil
    blockSelectionDirection = nil
  }

  private func expandedSelectionIDs(for rootIDs: [UUID]) -> Set<UUID> {
    var expanded: Set<UUID> = []

    func collectSubtreeIDs(from node: OutlineNode) {
      expanded.insert(node.id)
      for child in node.children {
        collectSubtreeIDs(from: child)
      }
    }

    for rootID in rootIDs {
      guard let node = OutlineNodeTreeNavigator.findNode(id: rootID, in: uiDocument.rootNodes) else {
        expanded.insert(rootID)
        continue
      }
      collectSubtreeIDs(from: node)
    }

    return expanded
  }

  func exitActiveEditing() {
    OutlineSelectionDiagnostics.log(
      "exitActiveEditing focusedNodeID=\(focusedNodeID?.uuidString ?? "nil") responder=\(OutlineSelectionDiagnostics.describeResponder((NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder))"
    )
    pendingSelectionRequest = nil
    focusedNodeID = nil
    let window = NSApp.keyWindow ?? NSApp.mainWindow
    window?.endEditing(for: nil)
    if let responder = window?.firstResponder as? NSTextView, responder.isEditable {
      window?.makeFirstResponder(nil)
    } else if let control = window?.firstResponder as? NSControl, control.currentEditor() != nil {
      window?.makeFirstResponder(nil)
    }
  }

  func setBlockSelection(_ ids: [UUID], direction: OutlineBlockSelectionDirection?) {
    var seen = Set<UUID>()
    let uniqueIDs = ids.filter { seen.insert($0).inserted }
    OutlineSelectionDiagnostics.log(
      "setBlockSelection ids=\(uniqueIDs.map(\.uuidString).joined(separator: ",")) direction=\(direction.map { String(describing: $0) } ?? "nil")"
    )
    selectedNodeOrder = uniqueIDs
    selectedNodeIDs = expandedSelectionIDs(for: uniqueIDs)
    blockSelectionLeadNodeID = uniqueIDs.last
    blockSelectionDirection = direction
  }

  func appendBlockSelection(_ id: UUID, direction: OutlineBlockSelectionDirection) {
    var updated = selectedNodeOrder
    if !updated.contains(id) {
      updated.append(id)
    }
    setBlockSelection(updated, direction: direction)
  }

  func dropLastBlockSelection() {
    guard !selectedNodeOrder.isEmpty else { return }
    var updated = selectedNodeOrder
    updated.removeLast()
    setBlockSelection(updated, direction: updated.isEmpty ? nil : blockSelectionDirection)
  }

  func previousVisibleSelectedCandidate(before id: UUID) -> UUID? {
    guard let index = visibleEntries.firstIndex(where: { $0.id == id }), index > 0 else {
      return nil
    }
    return visibleEntries[index - 1].id
  }

  func nextVisibleSelectedCandidate(after id: UUID) -> UUID? {
    guard let startIndex = visibleEntries.firstIndex(where: { $0.id == id }) else { return nil }
    var index = startIndex + 1
    while index < visibleEntries.count {
      let candidateID = visibleEntries[index].id
      if !isDescendantOfSelectedNode(candidateID) {
        return candidateID
      }
      index += 1
    }
    return nil
  }

  func isDescendantOfSelectedNode(_ nodeID: UUID) -> Bool {
    var currentID = nodeID
    while let parentID = OutlineNodeTreeNavigator.parentOf(id: currentID, in: document.rootNodes) {
      if selectedNodeIDs.contains(parentID) {
        return true
      }
      currentID = parentID
    }
    return false
  }

  private func installLocalKeyMonitorIfNeeded() {
    guard localKeyMonitor.token == nil else { return }
    OutlineSelectionDiagnostics.log("installLocalKeyMonitor")
    localKeyMonitor.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handleLocalKeyDown(event)
    }
  }

  private func removeLocalKeyMonitor() {
    guard let token = localKeyMonitor.token else { return }
    OutlineSelectionDiagnostics.log("removeLocalKeyMonitor")
    NSEvent.removeMonitor(token)
    localKeyMonitor.token = nil
  }

  private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
    let flags = OutlineSelectionDiagnostics.navigationRelevantModifiers(event.modifierFlags)
    OutlineSelectionDiagnostics.log(
      "localKeyDown keyCode=\(event.keyCode) modifiers=\(OutlineSelectionDiagnostics.describeModifiers(flags)) selectedCount=\(selectedNodeIDs.count) orderCount=\(selectedNodeOrder.count) lead=\(blockSelectionLeadNodeID?.uuidString ?? "nil") responder=\(OutlineSelectionDiagnostics.describeResponder((NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder))"
    )

    if flags == .command, event.keyCode == 9, handlePasteMirrorsFromPasteboard() {
      return nil
    }

    if flags == .command, event.keyCode == 51, !selectedNodeIDs.isEmpty {
      let selectedRootIDs = topLevelSelectedNodeIDsInDocumentOrder()
      guard !selectedRootIDs.isEmpty else { return nil }
      handleDeleteSelectedSubtrees(selectedRootIDs: selectedRootIDs)
      return nil
    }

    if event.keyCode == 53, !selectedNodeIDs.isEmpty {
      clearBlockSelection()
      return nil
    }

    guard !selectedNodeIDs.isEmpty else { return event }
    guard let leadID = blockSelectionLeadNodeID ?? selectedNodeOrder.last ?? selectedNodeOrder.first else {
      return event
    }

    if flags == .shift {
      switch event.keyCode {
      case 126:
        handleShiftMoveUp(id: leadID)
        return nil
      case 125:
        handleShiftMoveDown(id: leadID)
        return nil
      default:
        break
      }
    }

    if flags.isEmpty {
      switch event.keyCode {
      case 126:
        handleSelectionMoveUp()
        return nil
      case 125:
        handleSelectionMoveDown()
        return nil
      default:
        break
      }
    }

    return event
  }

  private var zoomNode: OutlineNode? {
    guard let zoomID = zoomPath.last else { return nil }
    return OutlineNodeTreeNavigator.findNode(id: zoomID, in: uiDocument.rootNodes)
  }

  private var visibleProjectionInputs: OutlineVisibleProjectionInputs {
    OutlineVisibleProjectionInputs(
      document: uiDocument,
      hideCompleted: hideCompleted,
      preservedCompletedNodeIDs: completedVisibilityGraceNodeIDs,
      searchQuery: searchQuery,
      zoomPath: zoomPath,
      currentProjectID: currentProjectID
    )
  }

  private var virtualizationWindow: OutlineVirtualizationWindow {
    OutlineVirtualizationWindow.resolved(
      rowCount: visibleRowCount,
      viewportHeight: virtualizationViewportHeight,
      visibleStartIndex: virtualizationVisibleStartIndex
    )
  }

  private func buildVisibleEntries(using inputs: OutlineVisibleProjectionInputs) -> [OutlineFlattenedEntry] {
    let entries: [OutlineFlattenedEntry]
    if let zoomID = inputs.zoomPath.last,
      let zoomNode = OutlineNodeTreeNavigator.findNode(id: zoomID, in: inputs.document.rootNodes)
    {
      let zoomDoc = OutlineDocument(rootNodes: [zoomNode])
      entries = zoomDoc.flatten()
    } else {
      entries = inputs.document.flatten()
    }
    var filtered = entries
    if inputs.hideCompleted {
      filtered = OutlineFlattenedEntryFilter.hidingCompletedSubtrees(
        in: filtered,
        preservingCompletedNodeIDs: inputs.preservedCompletedNodeIDs
      )
    }
    if !inputs.searchQuery.isEmpty {
      let query = inputs.searchQuery.lowercased()
      let matchingIDs = Set(
        filtered.filter { $0.node.text.lowercased().contains(query) }.map(\.id)
      )
      var visibleIDs = matchingIDs
      for id in matchingIDs {
        var current = id
        while let parentID = OutlineNodeTreeNavigator.parentOf(id: current, in: inputs.document.rootNodes) {
          visibleIDs.insert(parentID)
          current = parentID
        }
      }
      filtered = filtered.filter { visibleIDs.contains($0.id) }
    }
    return filtered
  }

  private func buildVisibleTree(from entries: [OutlineFlattenedEntry]) -> [OutlineVisibleTreeNode] {
    var nextIndex = 0
    return buildVisibleTree(
      from: entries,
      expectedDepth: entries.first?.depth ?? 0,
      nextIndex: &nextIndex
    )
  }

  private func buildVisibleTree(
    from entries: [OutlineFlattenedEntry],
    expectedDepth: Int,
    nextIndex: inout Int
  ) -> [OutlineVisibleTreeNode] {
    var nodes: [OutlineVisibleTreeNode] = []

    while nextIndex < entries.count {
      let entry = entries[nextIndex]

      if entry.depth < expectedDepth {
        break
      }

      guard entry.depth == expectedDepth else {
        break
      }

      let rowIndex = nextIndex
      nextIndex += 1
      let children = buildVisibleTree(
        from: entries,
        expectedDepth: expectedDepth + 1,
        nextIndex: &nextIndex
      )
      let rowCount = 1 + children.reduce(0) { $0 + $1.rowCount }
      nodes.append(
        OutlineVisibleTreeNode(
          entry: entry,
          rowIndex: rowIndex,
          rowCount: rowCount,
          children: children
        )
      )
    }

    return nodes
  }

  private func rebuildVisibleProjection(using inputs: OutlineVisibleProjectionInputs) {
    let rebuiltEntries = buildVisibleEntries(using: inputs)
    let rebuiltTreeNodes = buildVisibleTree(from: rebuiltEntries)
    _ = viewportState.applyVisibleProjection(
      entries: rebuiltEntries,
      treeNodes: rebuiltTreeNodes
    )
    OutlineRenderPerformanceDiagnostics.logVisibleProjectionRebuild(
      entryCount: rebuiltEntries.count,
      visibleTreeRootCount: rebuiltTreeNodes.count
    )
  }

  private func updateVirtualizationViewportHeightIfNeeded(_ height: CGFloat) {
    guard abs(height - virtualizationViewportHeight) > 0.5 else { return }

    let previousWindow = virtualizationWindow
    let nextWindow = OutlineVirtualizationWindow.resolved(
      rowCount: visibleRowCount,
      viewportHeight: height,
      visibleStartIndex: virtualizationVisibleStartIndex
    )
    virtualizationViewportHeight = height

    if previousWindow != nextWindow {
      OutlineRenderPerformanceDiagnostics.logViewportWindowChange(
        reason: "viewportHeight",
        previousWindow: previousWindow,
        nextWindow: nextWindow,
        rowCount: visibleRowCount,
        viewportHeight: height
      )
    }
  }

  private func updateVirtualizationScrollPositionIfNeeded(_ treeMinY: CGFloat) {
    let nextVisibleStartIndex = OutlineVirtualizationWindow.visibleStartIndex(treeMinY: treeMinY)
    guard nextVisibleStartIndex != virtualizationVisibleStartIndex else { return }

    let previousWindow = virtualizationWindow
    let nextWindow = OutlineVirtualizationWindow.resolved(
      rowCount: visibleRowCount,
      viewportHeight: virtualizationViewportHeight,
      visibleStartIndex: nextVisibleStartIndex
    )
    virtualizationVisibleStartIndex = nextVisibleStartIndex

    if previousWindow != nextWindow {
      OutlineRenderPerformanceDiagnostics.logViewportWindowChange(
        reason: "scrollRowBucket",
        previousWindow: previousWindow,
        nextWindow: nextWindow,
        rowCount: visibleRowCount,
        viewportHeight: virtualizationViewportHeight
      )
    }
  }

  private func noteScrollHoverActivity() {
    if !isHoverSuppressedForScroll {
      isHoverSuppressedForScroll = true
    }
    if hoveredNodeID != nil {
      hoveredNodeID = nil
    }
    hoverResumeTask?.cancel()
    hoverResumeTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(140))
      guard !Task.isCancelled else { return }
      isHoverSuppressedForScroll = false
    }
  }

  private var focusedNode: OutlineNode? {
    guard let focusedNodeID else { return nil }
    return OutlineNodeTreeNavigator.findNode(id: focusedNodeID, in: uiDocument.rootNodes)
  }

  private var breadcrumbPath: [OutlineBreadcrumbItem] {
    guard let zoomID = zoomPath.last else { return [] }
    return Array(ancestryPath(to: zoomID).dropLast()).compactMap { id in
      guard let node = OutlineNodeTreeNavigator.findNode(id: id, in: uiDocument.rootNodes) else {
        return nil
      }
      return OutlineBreadcrumbItem(
        id: id,
        text: breadcrumbDisplayText(for: node),
        isProject: false
      )
    }
  }

  private var contextBreadcrumbPath: [OutlineBreadcrumbItem] {
    [OutlineBreadcrumbItem(id: nil, text: shortenedBreadcrumbText(currentProjectTitle), isProject: true)]
      + breadcrumbPath
  }

  private var showsInitialRestoreLoadingState: Bool {
    !isPreviewMode && !hasRestoredPersistedState
  }

  private var isProjectDetailContext: Bool {
    preferredProjectID != nil
  }

  private func scheduleInitialSnapshotRefreshIfNeeded(
    delay: Duration = .milliseconds(150)
  ) {
    guard !isProjectDetailContext else { return }
    guard firstSyncCompleted || !resolvedReminderLinksByContentID().isEmpty else { return }
    initialSnapshotRefreshTask?.cancel()
    initialSnapshotRefreshTask = Task { @MainActor in
      defer {
        initialSnapshotRefreshTask = nil
      }
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      guard !Task.isCancelled else { return }
      await refreshLinkedSnapshots()
    }
  }

  private func scheduleInitialRestoreIfNeeded() {
    guard !isPreviewMode else {
      hasRestoredPersistedState = true
      rebuildVisibleProjection(using: visibleProjectionInputs)
      return
    }
    guard !hasRestoredPersistedState else {
      rebuildVisibleProjection(using: visibleProjectionInputs)
      applyPreferredProjectSelectionIfNeeded()
      scheduleInitialSnapshotRefreshIfNeeded()
      return
    }
    if appState.cachedOutlinerRuntimeProjectionSnapshot != nil {
      restorePersistedStateIfNeeded()
      applyPreferredProjectSelectionIfNeeded()
      scheduleInitialSnapshotRefreshIfNeeded()
      return
    }
    guard initialRestoreTask == nil else { return }

    initialRestoreTask = Task { @MainActor in
      defer {
        initialRestoreTask = nil
      }
      await refreshRuntimeProjectionSnapshotFromSourceIfAvailable()
      restorePersistedStateIfNeeded()
      applyPreferredProjectSelectionIfNeeded()
      scheduleInitialSnapshotRefreshIfNeeded()
    }
  }

  var shouldDeferProjectDetailSnapshotReload: Bool {
    hasActiveReminderPushEditingFocus || hasLocalSyncWorkInFlight || hasPendingTextOverlayWork
  }

  func scheduleProjectDetailSnapshotReloadIfNeeded(
    after delay: Duration = .milliseconds(250)
  ) {
    guard !isPreviewMode else { return }
    guard preferredProjectID != nil else { return }
    guard hasRestoredPersistedState, !isRestoringPersistedState else { return }
    guard !shouldDeferProjectDetailSnapshotReload else {
      pendingProjectDetailSnapshotReload = true
      return
    }

    pendingProjectDetailSnapshotReload = false
    projectDetailSnapshotReloadTask?.cancel()
    projectDetailSnapshotReloadTask = Task { @MainActor in
      defer {
        projectDetailSnapshotReloadTask = nil
      }
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      guard !Task.isCancelled else { return }
      await reloadProjectDetailSnapshotFromStoreIfNeeded()
    }
  }

  func scheduleProjectDetailSnapshotReloadAfterDeferralIfNeeded() {
    guard pendingProjectDetailSnapshotReload else { return }
    scheduleProjectDetailSnapshotReloadIfNeeded(after: .milliseconds(150))
  }

  func reloadProjectDetailSnapshotFromStoreIfNeeded() async {
    guard !isPreviewMode else { return }
    guard let preferredProjectID else { return }
    guard hasRestoredPersistedState, !isRestoringPersistedState else { return }
    guard !shouldDeferProjectDetailSnapshotReload else {
      pendingProjectDetailSnapshotReload = true
      return
    }
    if firstSyncCompleted {
      await pullRemoteChanges()
      pendingProjectDetailSnapshotReload = false
      return
    }
    await refreshRuntimeProjectionSnapshotFromSourceIfAvailable()
    guard let runtimeSnapshot = appState.resolvedScopedOutlinerRuntimeProjectionSnapshot(
      for: preferredProjectID
    ),
      let project = runtimeSnapshot.projects.first
    else {
      return
    }

    let nextProjects = [project]
    let nextReminderLinks = reminderLinksByContentID(from: runtimeSnapshot)
    let didChange =
      projects != nextProjects
      || sidecarMetadataByReminderIdentifier != runtimeSnapshot.featureSidecarByReminderIdentifier
      || sidecarMetadataByNodeID != runtimeSnapshot.featureSidecarByNodeID
      || reminderMetadataByReminderIdentifier != runtimeSnapshot.reminderMetadataByReminderIdentifier
      || reminderMetadataByNodeID != runtimeSnapshot.reminderMetadataByNodeID
      || taskFeatureSidecarByReminderExternalIdentifier
        != runtimeSnapshot.taskFeatureSidecarByReminderExternalIdentifier
      || taskSourceRuntimeStateByReminderExternalIdentifier
        != runtimeSnapshot.taskSourceRuntimeStateByReminderExternalIdentifier
      || resolvedReminderLinksByContentID() != nextReminderLinks
      || firstSyncCompleted != true
    guard didChange else {
      pendingProjectDetailSnapshotReload = false
      return
    }

    applyRuntimeProjectionSnapshot(
      runtimeSnapshot,
      firstSyncCompletedValue: true,
      persistedProjectionSidecars: appState.resolvedRuntimeProjectionSidecarPayload(),
      installProjectFeatureOwner: false,
      persistProjectOwner: false
    )

    if let focusedNodeID,
       OutlineNodeTreeNavigator.findNode(id: focusedNodeID, in: project.document.rootNodes) == nil {
      self.focusedNodeID = nil
      pendingSelectionRequest = nil
    }
    pendingProjectDetailSnapshotReload = false
  }

  func refreshRuntimeProjectionSnapshotFromSourceIfAvailable() async {
    let projectIDs = appState.resolvedRuntimeProjectionProjectIDs()
    if projectIDs.isEmpty { return }
    _ = await appState.recomputeCachedRuntimeProjectionProjects(projectIDs)
  }

  var body: some View {
    HStack(spacing: 0) {
      ZStack {
        Color.white
        VStack(spacing: 0) {
          if isSearchBarVisible {
            HStack(spacing: 8) {
              Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
              TextField("검색...", text: searchQueryBinding)
                .textFieldStyle(.plain)
                .font(.sandoll(size: 13))
              if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
              }
              Button(action: {
                searchQuery = ""
                isSearchBarVisible = false
              }) {
                Text("닫기")
                  .font(.sandoll(size: 11))
              }
              .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            Divider()
          }
          if showsInitialRestoreLoadingState {
            VStack(spacing: 10) {
              ProgressView()
                .controlSize(.regular)
              Text("프로젝트 디테일을 여는 중...")
                .font(.sandoll(size: 13))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 28)
          } else {
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 0) {
                if zoomPath.isEmpty {
                  OutlineProjectHeading(
                    title: currentProjectTitle,
                    accentColor: projectTitleAccentColor,
                    selectedStage: currentProjectStage,
                    topFadeHeight: topFadeHeight,
                    usesIntrinsicFadeMask: usesIntrinsicProjectHeadingFadeMask,
                    onUpdateTitle: updateCurrentProjectTitle,
                    onTitleFocusAttempt: beginProjectTitleEditing,
                    onTitleFocusChange: handleProjectTitleFocusChange
                  ) { stage in
                    updateCurrentProjectStage(stage)
                  }
                    .padding(.bottom, 12)
                } else if renderProfile.showsBreadcrumbChrome {
                  OutlineBreadcrumb(path: contextBreadcrumbPath) {
                    targetID in
                    handleBreadcrumbNavigation(targetID)
                  }
                  .padding(.bottom, 8)
                }
                OutlineVisibleTreeRenderer(
                  nodes: visibleTreeNodes,
                  visibleWindow: virtualizationWindow,
                  dropTargetNodeID: dropTargetNodeID,
                  dropPlacement: dropPlacement,
                  updateDropPlacement: handleDropPlacementChange,
                  performDrop: handleDropNode(transfer:location:targetEntry:)
                ) { entry in
                  outlineRowView(for: entry)
                }
                .background {
                  GeometryReader { proxy in
                    Color.clear.preference(
                      key: OutlineVirtualizationTreeMinYPreferenceKey.self,
                      value: proxy.frame(in: .named(OutlineVirtualizationCoordinateSpace.viewport)).minY
                    )
                  }
                }
              }
              .padding(.horizontal, OutlinerCanvasMetrics.horizontalPadding)
              .padding(.vertical, OutlinerCanvasMetrics.verticalPadding)
            }
            .coordinateSpace(name: OutlineVirtualizationCoordinateSpace.viewport)
            .background {
              GeometryReader { proxy in
                Color.clear.preference(
                  key: OutlineVirtualizationViewportHeightPreferenceKey.self,
                  value: proxy.size.height
                )
              }
            }
            .onPreferenceChange(OutlineVirtualizationViewportHeightPreferenceKey.self) { height in
              updateVirtualizationViewportHeightIfNeeded(height)
            }
            .onPreferenceChange(OutlineVirtualizationTreeMinYPreferenceKey.self) { minY in
              noteScrollHoverActivity()
              updateVirtualizationScrollPositionIfNeeded(minY)
            }
            .overlay(alignment: .top) {
              OutlineScrollTopFadeOverlay(fadeHeight: topFadeHeight)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
    .background(
      Group {
        Button("") {
          isSearchBarVisible.toggle()
          if !isSearchBarVisible { searchQuery = "" }
        }
        .keyboardShortcut("f", modifiers: .command)

        Button("") {
          handleZoomInShortcut()
        }
        .keyboardShortcut(".", modifiers: [.command, .shift])

        Button("") {
          handleZoomOutShortcut()
        }
        .keyboardShortcut(",", modifiers: [.command, .shift])

        Button("") {
          handleNavigateBackShortcut()
        }
        .keyboardShortcut("[", modifiers: .command)

        Button("") {
          handleReminderDueShortcut(.today)
        }
        .keyboardShortcut("1", modifiers: [.command, .shift])

        Button("") {
          handleReminderDueShortcut(.tomorrow)
        }
        .keyboardShortcut("2", modifiers: [.command, .shift])

        Button("") {
          handleReminderDueShortcut(.dayAfterTomorrow)
        }
        .keyboardShortcut("3", modifiers: [.command, .shift])

        Button("") {
          handleClearReminderDueShortcut()
        }
        .keyboardShortcut("0", modifiers: [.command, .shift])

        Button("") {
          handleCycleReminderRecurrenceShortcut()
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Button("") {
          handleCycleReminderPriorityShortcut()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])

        OutlineSelectionKeyResponder(
          isActive: !selectedNodeIDs.isEmpty,
          onEscape: { clearBlockSelection() },
          onMoveUp: { handleSelectionMoveUp() },
          onMoveDown: { handleSelectionMoveDown() },
          onShiftMoveUp: {
            guard let leadID = blockSelectionLeadNodeID ?? selectedNodeOrder.last ?? selectedNodeOrder.first else {
              return
            }
            handleShiftMoveUp(id: leadID)
          },
          onShiftMoveDown: {
            guard let leadID = blockSelectionLeadNodeID ?? selectedNodeOrder.last ?? selectedNodeOrder.first else {
              return
            }
            handleShiftMoveDown(id: leadID)
          }
        )
        .frame(width: 0, height: 0)
      }
      .opacity(0)
      .frame(width: 0, height: 0)
    )
    .onAppear {
      OutlineSelectionDiagnostics.resetLog()
      OutlineSelectionDiagnostics.log("outline.onAppear")
      installLocalKeyMonitorIfNeeded()
      refreshCurrentProjectAccentColorHex()
      scheduleInitialRestoreIfNeeded()
    }
    .onChange(of: visibleProjectionInputs) { _, newValue in
      rebuildVisibleProjection(using: newValue)
    }
    .onChange(of: currentProjectID) { _, _ in
      completedVisibilityGraceTasks.values.forEach { $0.cancel() }
      completedVisibilityGraceTasks.removeAll()
      completedVisibilityGraceNodeIDs.removeAll()
      refreshCurrentProjectAccentColorHex()
      synchronizeReminderPushEditingState()
    }
    .onChange(of: appState.runtimeProjectionRevision) { _, _ in
      refreshCurrentProjectAccentColorHex()
      if hasRestoredPersistedState {
        scheduleProjectDetailSnapshotReloadIfNeeded(after: .zero)
      } else {
        scheduleInitialRestoreIfNeeded()
      }
    }
    .onChange(of: preferredProjectID) { _, _ in
      applyPreferredProjectSelectionIfNeeded()
    }
    .onChange(of: appState.workspaceTreeRevision) { _, _ in
      scheduleProjectDetailSnapshotReloadIfNeeded()
    }
    .onChange(of: focusedNodeID) { _, _ in
      synchronizeReminderPushEditingState()
    }
    .onChange(of: isProjectTitleFocused) { _, _ in
      synchronizeReminderPushEditingState()
    }
    .onDisappear {
      removeLocalKeyMonitor()
      initialRestoreTask?.cancel()
      initialRestoreTask = nil
      completedVisibilityGraceTasks.values.forEach { $0.cancel() }
      completedVisibilityGraceTasks.removeAll()
      completedVisibilityGraceNodeIDs.removeAll()
      initialSnapshotRefreshTask?.cancel()
      initialSnapshotRefreshTask = nil
      hoverResumeTask?.cancel()
      hoverResumeTask = nil
      projectDetailSnapshotReloadTask?.cancel()
      projectDetailSnapshotReloadTask = nil
      autoPushTask?.cancel()
      autoPushTask = nil
      let hasPendingDirectReminderNoteCommit =
        pendingReminderNoteSourceDirectCommitContentIDs(excluding: nil).isEmpty == false
      reminderPushEditingBoundary = nil
      pendingAutoPushDeferredBoundary = nil
      hasPendingAutoPush = false
      if hasPendingDirectReminderNoteCommit {
        syncEditorSessionState(triggerAutoPush: false)
        commitPendingReminderNoteSourceDirectSaveIfNeeded(excluding: nil)
      }
      appState.endEditorSession(id: outlinerEditingSessionID)
      appState.endEditorSession(id: outlinerSyncSessionID)
    }
    .onCommand(Selector(("undo:"))) {
      if handleTextEditingUndo(isRedo: false) {
        return
      }
      if let snapshot = outlineUndoManager.undo(current: uiDocument, currentFocusedNodeID: focusedNodeID) {
        commitDocumentChange(snapshot.document, pushUndoSnapshot: false)
        pendingSelectionRequest = nil
        focusedNodeID = snapshot.focusedNodeID
      }
    }
    .onCommand(Selector(("redo:"))) {
      if handleTextEditingUndo(isRedo: true) {
        return
      }
      if let snapshot = outlineUndoManager.redo(current: uiDocument, currentFocusedNodeID: focusedNodeID) {
        commitDocumentChange(snapshot.document, pushUndoSnapshot: false)
        pendingSelectionRequest = nil
        focusedNodeID = snapshot.focusedNodeID
      }
    }
    .onCommand(#selector(NSText.paste(_:))) {
      if handlePasteMirrorsFromPasteboard() {
        return
      }
      if let responder = activeEditableTextResponder {
        responder.paste(nil)
      }
    }
  }

  // MARK: - Row Builder (extracted to help Swift type-checker)

  @ViewBuilder
  private func outlineRowView(for entry: OutlineFlattenedEntry) -> some View {
    let isFocused = !isProjectTitleFocused && focusedNodeID == entry.id
    let isSelected = selectedNodeIDs.contains(entry.id)
    let showsAccessoryBand = renderProfile.showsAccessoryBand && showsTaskAccessoryBand
    let reminderMetadata = showsAccessoryBand
      ? resolvedReminderMetadata(for: entry.id)
      : .empty
    let reminderReadOnlySurface = showsAccessoryBand && isFocused
      ? resolvedReminderReadOnlySurface(for: entry.id)
      : nil
    let reminderConflictSurface = showsAccessoryBand && isFocused
      ? resolvedReminderConflictSurface(for: entry.id)
      : nil
    let rowActionHandler = ClosureOutlinerRowActionHandler(
      normalizeTextBeforeCommit: { id, text in
        applyQuickReminderTokens(for: id, text: text)
      },
      onTextEdit: { id, newText in handleTextChange(id: id, newText: newText) },
      onToggleComplete: { id in handleToggleCompleted(id: id) },
      onToggleCollapse: { id in handleToggleCollapse(id: id) },
      onToggleType: { id in handleToggleType(id: id) },
      onConvertReferenceToBullet: { id in handleConvertReferenceToBullet(id: id) },
      onCopyBlockReference: { id in copyBlockReference(for: id) },
      onCopySelectedBlockReferences: {
        guard selectedNodeIDs.count > 1 else { return }
        copySelectedBlockReferences()
      },
      onZoomIn: { id in handleZoomIn(id: id) },
      onDeleteSubtree: { id in
        let selectedRootIDs = topLevelSelectedNodeIDsInDocumentOrder()
        guard selectedRootIDs.count > 1, selectedNodeIDs.contains(id) else {
          handleDeleteSubtree(id: id)
          return
        }
        handleDeleteSelectedSubtrees(selectedRootIDs: selectedRootIDs)
      },
      onInsertNewline: { id, committedText, cursorPosition in
        handleInsertNewline(id: id, committedText: committedText, cursorPosition: cursorPosition)
      },
      onDeleteBackwardAtStart: { id in handleDeleteBackward(id: id) },
      onIndent: { id, cursorPosition in handleIndent(id: id, cursorPosition: cursorPosition) },
      onOutdent: { id, cursorPosition in handleOutdent(id: id, cursorPosition: cursorPosition) },
      onMoveLeftFromStart: { id in handleMoveLeftFromStart(id: id) },
      onMoveRightFromEnd: { id in handleMoveRightFromEnd(id: id) },
      onMoveUp: { id in handleMoveUp(id: id) },
      onMoveDown: { id in handleMoveDown(id: id) },
      onShiftMoveUp: { id in handleShiftMoveUp(id: id) },
      onShiftMoveDown: { id in handleShiftMoveDown(id: id) },
      onCommitAndToggleType: { id, committedText in
        handleCommitAndToggleType(id: id, committedText: committedText)
      },
      onCommandToggleSelection: { id in handleCommandToggleSelection(id: id) },
      onTextEditingBegan: { id in
        beginReminderPushEditing(for: id)
      },
      onTextEditingEnded: { id in
        handleNodeEditingEnded(id: id)
      },
      onFocus: { id, cursorPosition in
        OutlineSelectionDiagnostics.log(
          "row.onFocus id=\(id.uuidString) cursor=\(cursorPosition.map(String.init) ?? "nil")"
        )
        clearBlockSelection()
        if let cursorPosition {
          requestFocus(on: id, cursorPosition: cursorPosition)
        } else {
          pendingSelectionRequest = nil
          focusedNodeID = id
        }
      },
      onHoverChange: { id, hovering in
        guard !isHoverSuppressedForScroll else {
          if hoveredNodeID == id {
            hoveredNodeID = nil
          }
          return
        }
        if hovering {
          hoveredNodeID = id
        } else if hoveredNodeID == id {
          hoveredNodeID = nil
        }
      },
      onAddAttachment: { id in handleAddAttachment(id: id) },
      onResolveReminderConflict: { id, action in
        resolveReminderConflict(for: id, action: action)
      },
      referenceSuggestions: renderProfile.showsReferenceSuggestions
        ? { text in
          referenceSuggestions(for: text, excluding: entry.id)
        }
        : { _ in [] },
      onInsertReferenceSuggestion: { id, suggestion in
        handleInsertReferenceSuggestion(id: id, suggestion: suggestion)
      },
      onRequestedCursorApplied: { id in
        if pendingSelectionRequest?.nodeID == id {
          pendingSelectionRequest = nil
        }
      },
      onNavigateToReference: { targetID, projectID in
        handleNavigateToReference(targetID: targetID, projectID: projectID)
      },
      onReminderAction: { id, action in
        switch action {
        case let .applyDuePreset(preset):
          setReminderDuePreset(preset, for: id)
        case .clearDue:
          clearReminderDue(for: id)
        case let .setDue(date, hasExplicitTime):
          setReminderDueDate(date, hasExplicitTime: hasExplicitTime, for: id)
        case let .setRecurrence(recurrence):
          setReminderRecurrence(recurrence, for: id)
        case .cycleRecurrence:
          cycleReminderRecurrence(for: id)
        case let .setPriority(priority):
          setReminderPriority(priority, for: id)
        case .cyclePriority:
          cycleReminderPriority(for: id)
        }
      }
    )

    let row = OutlineNodeRow(
      entry: entry,
      renderProfile: renderProfile,
      displayDepth: 0,
      isMirrorPlacement: isMirrorRootPlacement(entry.node),
      isFocused: isFocused,
      isHovered: hoveredNodeID == entry.id,
      isSelected: isSelected,
      dragTransfer: OutlineNodeIDTransfer(nodeID: entry.id, projectID: currentProjectID),
      showsAccessoryBand: showsAccessoryBand,
      reminderMetadata: reminderMetadata,
      reminderReadOnlySurface: reminderReadOnlySurface,
      reminderConflictSurface: reminderConflictSurface,
      draftSession: draftSession,
      actionHandler: rowActionHandler,
      isCloned: nodeIsCloned(id: entry.id),
      requestedCursorPosition: pendingSelectionRequest?.nodeID == entry.id
        ? pendingSelectionRequest?.cursorPosition
        : nil
    )

    let rowWithDrop = row
      .onDrop(
        of: [UTType.json],
        delegate: OutlineNodeRowDropDelegate(
          targetEntry: entry,
          placementResolver: { dropLocation, targetEntry in
            OutlineNodeDragDropEngine.placementFromDropLocation(
              dropLocation: dropLocation,
              depth: targetEntry.depth
            )
          },
          updatePlacement: handleDropPlacementChange,
          performDrop: handleDropNode(transfer:location:targetEntry:)
        )
      )
      .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
      handleDropFile(providers: providers, nodeID: entry.id)
    }

    if row.shouldShowAccessoryBand {
      VStack(spacing: 0) {
        rowWithDrop
        row.accessoryBand
      }
    } else {
      rowWithDrop
    }
  }

}

// MARK: - Outline Undo Manager

#if DEBUG
@MainActor
private enum OutlinerPreviewFactory {
  static func makeAppState() -> AppState {
    let appState = AppState(isPreviewAppState: true)
    appState.isLaunching = false
    appState.boardsLoaded = true
    appState.hasInitialSyncConsent = true
    appState.hasSyncConsentDecision = true
    appState.syncStatus = "Preview"
    return appState
  }
}

@MainActor
private struct OutlinerViewPreviewHost: View {
  @StateObject private var appState: AppState

  init() {
    _appState = StateObject(wrappedValue: OutlinerPreviewFactory.makeAppState())
  }

  var body: some View {
    OutlinerView()
      .frame(width: projectDetailDetachedWindowContentWidth)
      .frame(minHeight: 900, maxHeight: 900)
      .environmentObject(appState)
      .preferredColorScheme(.light)
      .padding(0)
  }
}

#Preview(
  "Outliner",
  traits: .fixedLayout(width: projectDetailDetachedWindowContentWidth, height: 900)
) {
  OutlinerViewPreviewHost()
}
#endif

// MARK: - Outline Undo Manager

struct OutlineUndoSnapshot {
  let document: OutlineDocument
  let focusedNodeID: UUID?
}

@MainActor
final class OutlineUndoManager: ObservableObject {
  private var undoStack: [OutlineUndoSnapshot] = []
  private var redoStack: [OutlineUndoSnapshot] = []
  private let maxHistory = 50

  @Published private(set) var canUndo = false
  @Published private(set) var canRedo = false

  func pushSnapshot(_ document: OutlineDocument, focusedNodeID: UUID?) {
    undoStack.append(OutlineUndoSnapshot(document: document, focusedNodeID: focusedNodeID))
    if undoStack.count > maxHistory {
      undoStack.removeFirst()
    }
    redoStack.removeAll()
    updateFlags()
  }

  func undo(current: OutlineDocument, currentFocusedNodeID: UUID?) -> OutlineUndoSnapshot? {
    guard let previous = undoStack.popLast() else { return nil }
    redoStack.append(OutlineUndoSnapshot(document: current, focusedNodeID: currentFocusedNodeID))
    updateFlags()
    return previous
  }

  func redo(current: OutlineDocument, currentFocusedNodeID: UUID?) -> OutlineUndoSnapshot? {
    guard let next = redoStack.popLast() else { return nil }
    undoStack.append(OutlineUndoSnapshot(document: current, focusedNodeID: currentFocusedNodeID))
    updateFlags()
    return next
  }

  private func updateFlags() {
    canUndo = !undoStack.isEmpty
    canRedo = !redoStack.isEmpty
  }
}

private extension String {
  func leadingIndentPrefix() -> String {
    var prefix = ""
    let tabScalar = Unicode.Scalar(9)!
    for scalar in unicodeScalars {
      guard scalar == tabScalar else { break }
      prefix.unicodeScalars.append(scalar)
    }
    return prefix
  }

  func dropLeadingIndent() -> String {
    String(dropFirst(leadingIndentPrefix().count))
  }
}
