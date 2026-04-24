import AppKit
import Foundation
import SwiftUI

private struct OutlinerReminderProjectionNodeFingerprint: Equatable {
  let canonicalID: UUID
  let text: String
  let type: OutlineNodeType
  let childNodeIDs: [UUID]
}

enum OutlinerReminderPushPlanner {
  enum SyncSurfaceChange: Equatable {
    case titleChanged(Set<UUID>)
    case noteBodyChanged(Set<UUID>)
    case completionChanged(Set<UUID>)
    case scheduleChanged(Set<UUID>)
    case noReminderChange

    var contentIDs: Set<UUID> {
      switch self {
      case let .titleChanged(contentIDs),
        let .noteBodyChanged(contentIDs),
        let .completionChanged(contentIDs),
        let .scheduleChanged(contentIDs):
        return contentIDs
      case .noReminderChange:
        return []
      }
    }
  }

  private struct TaskSyncSurfaceFingerprint: Equatable {
    let title: String
    let isCompleted: Bool
    let noteBody: String
  }

  static func changedProjectionContentIDs(
    from oldDocument: OutlineDocument,
    to newDocument: OutlineDocument
  ) -> Set<UUID> {
    let oldTreeIndex = OutlineTreeIndex(document: oldDocument)
    let newTreeIndex = OutlineTreeIndex(document: newDocument)
    let changedNodeIDs = changedNodeIDs(
      from: oldDocument,
      to: newDocument
    )
    guard !changedNodeIDs.isEmpty else { return [] }

    var changedContentIDs: Set<UUID> = []
    for nodeID in changedNodeIDs {
      changedContentIDs.formUnion(taskAncestorContentIDs(for: nodeID, using: oldTreeIndex))
      changedContentIDs.formUnion(taskAncestorContentIDs(for: nodeID, using: newTreeIndex))
    }

    return changedContentIDs
  }

  static func classifyTextPatch(
    _ patch: NodePatch,
    oldTreeIndex: OutlineTreeIndex,
    newTreeIndex: OutlineTreeIndex
  ) -> SyncSurfaceChange {
    let changedContentIDs = changedSyncSurfaceContentIDs(
      for: patch.nodeID,
      oldTreeIndex: oldTreeIndex,
      newTreeIndex: newTreeIndex
    )
    guard !changedContentIDs.isEmpty else { return .noReminderChange }

    let currentNode = oldTreeIndex.findNode(id: patch.nodeID)
      ?? newTreeIndex.findNode(id: patch.nodeID)
    if currentNode?.type.isTask == true {
      return .titleChanged(changedContentIDs)
    }

    return .noteBodyChanged(changedContentIDs)
  }

  static func classifyTextPatch(
    _ patch: NodePatch,
    from oldDocument: OutlineDocument,
    to newDocument: OutlineDocument
  ) -> SyncSurfaceChange {
    classifyTextPatch(
      patch,
      oldTreeIndex: OutlineTreeIndex(document: oldDocument),
      newTreeIndex: OutlineTreeIndex(document: newDocument)
    )
  }

  private static func changedNodeIDs(
    from oldDocument: OutlineDocument,
    to newDocument: OutlineDocument
  ) -> Set<UUID> {
    let oldFingerprints = nodeFingerprints(in: oldDocument)
    let newFingerprints = nodeFingerprints(in: newDocument)
    var changedNodeIDs = Set(oldFingerprints.keys).symmetricDifference(newFingerprints.keys)

    for nodeID in newFingerprints.keys {
      guard oldFingerprints[nodeID] != newFingerprints[nodeID] else { continue }
      changedNodeIDs.insert(nodeID)
    }

    return changedNodeIDs
  }

  private static func nodeFingerprints(
    in document: OutlineDocument
  ) -> [UUID: OutlinerReminderProjectionNodeFingerprint] {
    var fingerprints: [UUID: OutlinerReminderProjectionNodeFingerprint] = [:]

    func visit(_ nodes: [OutlineNode]) {
      for node in nodes {
        fingerprints[node.id] = OutlinerReminderProjectionNodeFingerprint(
          canonicalID: node.canonicalID,
          text: node.text,
          type: node.type,
          childNodeIDs: node.children.map(\.id)
        )
        visit(node.children)
      }
    }

    visit(document.rootNodes)
    return fingerprints
  }

  private static func taskAncestorContentIDs(
    for nodeID: UUID,
    using index: OutlineTreeIndex
  ) -> Set<UUID> {
    guard index.findNode(id: nodeID) != nil else {
      return []
    }

    var contentIDs: Set<UUID> = []
    var currentID: UUID? = nodeID
    while let resolvedID = currentID,
          let node = index.findNode(id: resolvedID)
    {
      if node.type.isTask {
        contentIDs.insert(node.canonicalID)
      }
      currentID = index.parentOf(id: resolvedID)
    }
    return contentIDs
  }

  private static func changedSyncSurfaceContentIDs(
    for nodeID: UUID,
    oldTreeIndex: OutlineTreeIndex,
    newTreeIndex: OutlineTreeIndex
  ) -> Set<UUID> {
    let candidateContentIDs =
      taskAncestorContentIDs(for: nodeID, using: oldTreeIndex)
      .union(taskAncestorContentIDs(for: nodeID, using: newTreeIndex))

    return candidateContentIDs.reduce(into: Set<UUID>()) { result, contentID in
      let oldFingerprint = syncSurfaceFingerprint(forTaskContentID: contentID, using: oldTreeIndex)
      let newFingerprint = syncSurfaceFingerprint(forTaskContentID: contentID, using: newTreeIndex)
      if oldFingerprint != newFingerprint {
        result.insert(contentID)
      }
    }
  }

  private static func syncSurfaceFingerprint(
    forTaskContentID contentID: UUID,
    using treeIndex: OutlineTreeIndex
  ) -> TaskSyncSurfaceFingerprint? {
    guard let taskNode = taskNode(contentID: contentID, using: treeIndex) else { return nil }
    let noteBody = ReminderNoteSourceMutationService.plan(
      for: taskNode,
      reminderExternalIdentifierResolver: { node in
        node.reminderExternalIdentifier
      }
    ).normalizedNoteText
    return TaskSyncSurfaceFingerprint(
      title: taskNode.text,
      isCompleted: taskNode.type.isCompleted,
      noteBody: noteBody
    )
  }

  private static func taskNode(
    contentID: UUID,
    using treeIndex: OutlineTreeIndex
  ) -> OutlineNode? {
    treeIndex.taskNode(contentID: contentID)
  }
}

extension OutlinerView {
  func breadcrumbDisplayText(for node: OutlineNode) -> String {
    shortenedBreadcrumbText(node.text)
  }

  func isMirrorCanonical(_ node: OutlineNode) -> Bool {
    currentTreeContainsClone(canonicalID: node.canonicalID)
      || (canonicalInstanceCounts[node.canonicalID] ?? 1) > 1
  }

  func nodeIsCloned(id: UUID) -> Bool {
    guard let node = currentTreeNode(id: id) else { return false }
    return isMirrorCanonical(node)
  }

  func isMirrorRootPlacement(_ node: OutlineNode) -> Bool {
    guard isMirrorCanonical(node) else { return false }

    var currentID = node.id
    while let parentID = currentTreeParentID(of: currentID),
          let parentNode = currentTreeNode(id: parentID) {
      if isMirrorCanonical(parentNode) {
        return false
      }
      currentID = parentID
    }

    return true
  }

  func shortenedBreadcrumbText(_ text: String) -> String {
    let collapsed = text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    let resolved = collapsed.isEmpty ? "(빈 노드)" : collapsed
    let maxLength = OutlinerCanvasMetrics.breadcrumbMaxTextLength
    guard resolved.count > maxLength else { return resolved }

    let cutoff = resolved.index(resolved.startIndex, offsetBy: maxLength - 3)
    let prefix = resolved[..<cutoff].trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(prefix)..."
  }

  func ancestryPath(to nodeID: UUID) -> [UUID] {
    guard currentTreeNode(id: nodeID) != nil else { return [] }

    var path: [UUID] = [nodeID]
    var currentID = nodeID

    while let parentID = currentTreeParentID(of: currentID) {
      path.append(parentID)
      currentID = parentID
    }

    return path.reversed()
  }

  func resolvedNode(
    id nodeID: UUID,
    in projects: [OutlinerProject]
  ) -> OutlineNode? {
    for project in projects {
      if let node = OutlineNodeTreeNavigator.findNode(id: nodeID, in: project.document.rootNodes) {
        return node
      }
    }
    return nil
  }

  func resolvedContentID(for nodeID: UUID) -> UUID? {
    resolvedNode(id: nodeID, in: syncedProjects)?.canonicalID
  }

  func markCompletedNodeVisibleDuringHideCompletedGrace(_ nodeID: UUID) {
    let preservedIdentityID =
      currentTreeNode(id: nodeID)?.canonicalID ?? nodeID
    completedVisibilityGraceTasks[preservedIdentityID]?.cancel()
    completedVisibilityGraceNodeIDs.insert(preservedIdentityID)
    completedVisibilityGraceTasks[preservedIdentityID] = Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      completedVisibilityGraceNodeIDs.remove(preservedIdentityID)
      completedVisibilityGraceTasks[preservedIdentityID] = nil
    }
  }

  func clearCompletedNodeHideCompletedGrace(_ nodeID: UUID) {
    let preservedIdentityID =
      currentTreeNode(id: nodeID)?.canonicalID ?? nodeID
    completedVisibilityGraceTasks[preservedIdentityID]?.cancel()
    completedVisibilityGraceTasks[preservedIdentityID] = nil
    completedVisibilityGraceNodeIDs.remove(preservedIdentityID)
  }

  func resolvedTaskState(
    for contentID: UUID,
    defaultTitle: String
  ) -> OutlinerIntegratedTaskState {
    var taskState = OutlinerIntegratedTaskState(
      content: TaskContent(id: contentID, title: defaultTitle)
    )

    if let projectionTask = appState.resolvedRuntimeProjectionTaskSnapshot(forTaskID: contentID) {
      let taskRecord = projectionTask.taskRecord
      taskState.reminderIdentifier = projectionTask.reminderIdentifier
      taskState.reminderExternalIdentifier = taskRecord.reminderExternalIdentifier
      taskState.ownerProjectID = taskRecord.reminderOwnerProjectID
      taskState.ownerCalendarID = taskRecord.reminderOwnerCalendarID
      taskState.reminderNoteText = taskRecord.reminderNoteText
      taskState.featureSidecar = OutlinerTaskSidecarMetadata(
        requiredWorkDays: max(0, taskRecord.requiredWorkDays),
        scheduledDurationMinutes: taskRecord.scheduledDurationMinutes,
        attachmentPreviews: []
      )
      taskState.reminderMetadata = ReminderMetadataSnapshot(
        dueDate: taskRecord.dueDate,
        completionDate: taskRecord.completionDate,
        hasExplicitTime: taskRecord.scheduleHasExplicitTime,
        recurrence: OutlinerIntegratedStore.decodeRecurrence(rawValue: taskRecord.recurrenceRuleRaw),
        priority: taskRecord.priority
      )
      taskState.baseline = ReminderSyncBaseline(
        lastSyncedReminderTitle: taskRecord.title,
        lastSyncedReminderNoteBody: taskRecord.reminderNoteText,
        lastSyncedReminderModifiedAt: projectionTask.remoteLastModifiedAt,
        reminderNoteConflictExcerpt: nil
      )
      taskState.remoteLastModifiedAt = projectionTask.remoteLastModifiedAt
      taskState.localUpdatedAt = taskRecord.localUpdatedAt
      taskState.isFlagged = taskRecord.isFlagged
    } else if let runtimeNode = runtimeProjectionTaskNode(for: contentID) {
      taskState.reminderIdentifier = normalizedNonEmptyString(runtimeNode.reminderIdentifier)
      taskState.reminderExternalIdentifier = normalizedNonEmptyString(
        runtimeNode.reminderExternalIdentifier
      )
      taskState.ownerProjectID = runtimeProjectionTaskOwnerProjectID(for: contentID)
      taskState.parentTaskRemoteExternalIdentifier = resolvedParentReminderExternalIdentifier(
        for: runtimeNode.id,
        in: syncedProjects
      )
    }

    if let runtimeNode = runtimeProjectionTaskNode(for: contentID) {
      taskState.reminderMetadata = resolvedPersistedReminderMetadata(
        forNodeID: runtimeNode.id,
        reminderIdentifier: taskState.reminderIdentifier,
        fallback: taskState.reminderMetadata
      )
    } else {
      taskState.reminderMetadata = resolvedPersistedReminderMetadata(
        forNodeID: nil,
        reminderIdentifier: taskState.reminderIdentifier,
        fallback: taskState.reminderMetadata
      )
    }

    if let reminderExternalIdentifier = normalizedNonEmptyString(taskState.reminderExternalIdentifier),
       let runtimeState = noteSourceRuntimeState(for: reminderExternalIdentifier)
    {
      taskState.reminderRawPayloadRaw =
        normalizedNonEmptyString(runtimeState.lastObservedReminderRawPayloadRaw)
      if let lastObservedReminderModifiedAt = runtimeState.lastObservedReminderModifiedAt {
        taskState.baseline.lastSyncedReminderModifiedAt = lastObservedReminderModifiedAt
        taskState.remoteLastModifiedAt = lastObservedReminderModifiedAt
      }
    }

    if taskState.parentTaskRemoteExternalIdentifier == nil,
       let runtimeNode = runtimeProjectionTaskNode(for: contentID) {
      taskState.parentTaskRemoteExternalIdentifier = resolvedParentReminderExternalIdentifier(
        for: runtimeNode.id,
        in: syncedProjects
      )
    }

    if let overlay = integratedTaskStatesByContentID[contentID] {
      taskState.reminderNoteConflictExcerpt =
        normalizedNonEmptyString(overlay.reminderNoteConflictExcerpt)
    }

    return taskState
  }

  func resolvedReminderExternalIdentifier(for taskNode: OutlineNode) -> String? {
    if let reminderExternalIdentifier = taskNode.reminderExternalIdentifier?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !reminderExternalIdentifier.isEmpty
    {
      return reminderExternalIdentifier
    }

    return resolvedTaskState(for: taskNode.canonicalID, defaultTitle: taskNode.text)
      .reminderExternalIdentifier
  }

  func mutateTaskSessionOverlay(
    for contentID: UUID,
    _ mutate: (inout OutlinerTaskSessionOverlayState) -> Void
  ) {
    var overlay = integratedTaskStatesByContentID[contentID] ?? OutlinerTaskSessionOverlayState()
    mutate(&overlay)
    if overlay.isEmpty {
      integratedTaskStatesByContentID.removeValue(forKey: contentID)
    } else {
      integratedTaskStatesByContentID[contentID] = overlay
    }
  }

  func clearTaskSessionOverlay(for contentID: UUID) {
    integratedTaskStatesByContentID.removeValue(forKey: contentID)
  }

  func pendingRemovalReference(for contentID: UUID) -> ReminderTaskReference? {
    guard let overlay = integratedTaskStatesByContentID[contentID],
          overlay.hasPendingRemovalReference
    else {
      return nil
    }
    return ReminderTaskReference(
      taskID: contentID,
      reminderIdentifier: overlay.pendingRemovalReminderIdentifier,
      reminderExternalIdentifier: overlay.pendingRemovalReminderExternalIdentifier
    )
  }

  func runtimeProjectionTaskNode(for contentID: UUID) -> OutlineNode? {
    for project in syncedProjects {
      if let node = project.document.flatten().first(where: {
        $0.node.type.isTask && $0.node.canonicalID == contentID
      })?.node {
        return node
      }
    }
    return nil
  }

  func runtimeProjectionTaskOwnerProjectID(for contentID: UUID) -> UUID? {
    ProjectIdentityResolver.projectID(
      for: contentID,
      in: appState.resolvedRuntimeProjectionSnapshot()
    )
  }

  func resolvedParentReminderExternalIdentifier(
    for nodeID: UUID,
    in projects: [OutlinerProject]
  ) -> String? {
    for project in projects {
      guard let parentID = OutlineNodeTreeNavigator.parentOf(
        id: nodeID,
        in: project.document.rootNodes
      ),
      let parentNode = OutlineNodeTreeNavigator.findNode(
        id: parentID,
        in: project.document.rootNodes
      ) else {
        continue
      }
      return resolvedReminderExternalIdentifier(for: parentNode)
    }
    return nil
  }

  func reminderSubtreeCommitBoundary(for nodeID: UUID?) -> ReminderSubtreeCommitBoundary? {
    ReminderSubtreeCommitBoundaryEngine.editingBoundary(
      for: nodeID,
      in: uiDocument,
      isProjectTitleFocused: isProjectTitleFocused
    )
  }

  func enqueueReminderPushContentIDs<S: Sequence>(_ contentIDs: S) where S.Element == UUID {
    let normalizedContentIDs = Set(contentIDs)
    guard !normalizedContentIDs.isEmpty else { return }
    pendingReminderPushContentIDs.formUnion(normalizedContentIDs)
    for contentID in normalizedContentIDs {
      reminderPushLastEditedAtByContentID[contentID] = .now
    }
  }

  func changedReminderProjectionContentIDs(
    from oldDocument: OutlineDocument,
    to newDocument: OutlineDocument
  ) -> Set<UUID> {
    OutlinerReminderPushPlanner.changedProjectionContentIDs(
      from: oldDocument,
      to: newDocument
    )
  }

  func resolvedFeatureSidecarMetadata(for nodeID: UUID) -> OutlinerTaskSidecarMetadata {
    guard let contentID = resolvedContentID(for: nodeID),
          let node = resolvedNode(id: nodeID, in: syncedProjects)
    else {
      return .empty
    }

    let taskState = resolvedTaskState(for: contentID, defaultTitle: node.text)
    return taskState.featureSidecar
  }

  func mergedReminderMetadata(
    _ metadata: ReminderMetadataSnapshot,
    fallback: ReminderMetadataSnapshot
  ) -> ReminderMetadataSnapshot {
    var merged = metadata
    if merged.dueDate == nil {
      merged.dueDate = fallback.dueDate
      merged.hasExplicitTime = fallback.hasExplicitTime
    } else if fallback.dueDate == nil {
      merged.hasExplicitTime = metadata.hasExplicitTime
    }
    if merged.recurrence == nil {
      merged.recurrence = fallback.recurrence
    }
    if merged.priority == 0 {
      merged.priority = fallback.priority
    }
    if merged.completionDate == nil {
      merged.completionDate = fallback.completionDate
    }
    return merged
  }

  func resolvedPersistedReminderMetadata(
    forNodeID nodeID: UUID?,
    reminderIdentifier: String?,
    fallback: ReminderMetadataSnapshot
  ) -> ReminderMetadataSnapshot {
    var metadata = fallback
    if let reminderIdentifier,
       let reminderMetadata = reminderMetadataByReminderIdentifier[reminderIdentifier]
    {
      metadata = mergedReminderMetadata(reminderMetadata, fallback: metadata)
    }
    if let nodeID,
       let nodeMetadata = reminderMetadataByNodeID[nodeID]
    {
      metadata = mergedReminderMetadata(nodeMetadata, fallback: metadata)
    }
    return metadata
  }

  func resolvedReminderMetadata(for nodeID: UUID) -> ReminderMetadataSnapshot {
    guard let contentID = resolvedContentID(for: nodeID),
          let node = resolvedNode(id: nodeID, in: syncedProjects)
    else {
      return .empty
    }

    let taskState = resolvedTaskState(for: contentID, defaultTitle: node.text)
    return resolvedPersistedReminderMetadata(
      forNodeID: nodeID,
      reminderIdentifier: taskState.reminderIdentifier,
      fallback: taskState.reminderMetadata
    )
  }

  func badgeData(for entry: OutlineFlattenedEntry) -> OutlineNodeBadgeData? {
    guard entry.node.type.isTask else { return nil }
    let badge = resolvedReminderMetadata(for: entry.id).badgeData
    return badge.isEmpty ? nil : badge
  }

  func nodeBasedProjections(for contentIDs: Set<UUID>? = nil) -> [OutlinerReminderProjection] {
    var projections: [OutlinerReminderProjection] = []
    var seenCanonicalIDs: Set<UUID> = []

    var flattenedIndex = 0
    func visit(_ nodes: [OutlineNode], depth: Int) {
      for node in nodes {
        let nodeIndex = flattenedIndex
        flattenedIndex += 1

        if node.type.isTask,
           seenCanonicalIDs.insert(node.canonicalID).inserted,
           contentIDs?.contains(node.canonicalID) ?? true
        {
          let taskLine = node.toOutlinerLine(flattenedIndex: nodeIndex, depth: depth)
          let descendants = collectDescendantLines(of: node, baseDepth: depth, startIndex: nodeIndex + 1)
          let persistedFeatureSidecar = resolvedFeatureSidecarMetadata(for: node.id)
          let persistedReminderMetadata = resolvedReminderMetadata(for: node.id)
          let taskState = resolvedTaskState(for: node.canonicalID, defaultTitle: node.text)
          let noteSourceMutation = ReminderNoteSourceMutationService.plan(
            for: node,
            reminderExternalIdentifierResolver: resolvedReminderExternalIdentifier(for:)
          )
          let noteLines = noteSourceMutation.normalizedNoteText.isEmpty
            ? []
            : noteSourceMutation.normalizedNoteText.components(separatedBy: "\n")
          let syncContract = OutlinerSyncContractBuilder.contract(
            for: taskLine,
            descendants: descendants,
            projectedNoteLines: noteLines,
            persistedFeatureSidecar: persistedFeatureSidecar.hasMeaningfulContent ? persistedFeatureSidecar : nil,
            persistedReminderMetadata: persistedReminderMetadata.hasMeaningfulContent ? persistedReminderMetadata : nil
          )
          let noteText = noteSourceMutation.normalizedNoteText
          let encodedReminderNote = noteSourceMutation.normalizedNoteText
          let parsedReminderBody = noteSourceMutation.normalizedNoteText

          projections.append(
            OutlinerReminderProjection(
              nodeID: node.id,
              contentID: node.canonicalID,
              taskLine: taskLine,
              descendantLines: descendants,
              projectedNoteLines: noteLines,
              syncContract: syncContract,
              baseline: taskState.baseline,
              reminderIdentifier: taskState.reminderIdentifier,
              reminderExternalIdentifier: taskState.reminderExternalIdentifier,
              reminderOwnerProjectID: taskState.ownerProjectID,
              reminderOwnerCalendarID: taskState.ownerCalendarID,
              parentTaskRemoteExternalIdentifier: taskState.parentTaskRemoteExternalIdentifier,
              attachmentCount: max(taskState.attachmentCount, persistedFeatureSidecar.attachmentPreviews.count),
              remoteLastModifiedAt: taskState.remoteLastModifiedAt,
              localUpdatedAt: taskState.localUpdatedAt,
              noteText: noteText,
              encodedReminderNote: encodedReminderNote,
              parsedReminderBody: parsedReminderBody,
              appProjectionSnippetText: "",
              restoredAppSnippetText: "",
              fullSubtreeSnippetText: "",
              anchorCount: 0,
              omittedLineCount: 0
            )
          )
        }

        if !node.isCollapsed {
          visit(node.children, depth: depth + 1)
        }
      }
    }

    visit(uiDocument.rootNodes, depth: 0)
    return projections
  }

  func collectDescendantLines(
    of node: OutlineNode,
    baseDepth: Int,
    startIndex: Int
  ) -> [OutlinerLine] {
    var result: [OutlinerLine] = []
    var idx = startIndex
    func collect(_ children: [OutlineNode], depth: Int) {
      for child in children {
        result.append(child.toOutlinerLine(flattenedIndex: idx, depth: depth))
        idx += 1
        collect(child.children, depth: depth + 1)
      }
    }
    collect(node.children, depth: baseDepth + 1)
    return result
  }

  func projectedNoteLines(for node: OutlineNode, taskDepth: Int) -> [String] {
    var result: [String] = []
    for child in node.children {
      if child.type.isTask {
        result.append(
          OutlinerTaskAnchorCodec.anchorLine(
            for: child.toOutlinerLine(flattenedIndex: 0, depth: taskDepth + 1),
            relativeIndentDepth: 0
          )
        )
      } else {
        let relativeIndent = 0
        // reference 노드는 원본 텍스트를 해석하여 사용한다
        let displayText: String
        if let target = OutlineNodeTreeNavigator.resolveReference(
          node: child,
          defaultProjectID: currentProjectID,
          in: syncedProjects
        ) {
          displayText = child.text.isEmpty ? target.node.text : child.text
        } else {
          displayText = child.text
        }
        result.append(
          String(repeating: "\t", count: relativeIndent)
            + child.toOutlinerLine(flattenedIndex: 0, depth: taskDepth + 1).marker.visiblePrefix
            + displayText
        )
      }
    }
    return result
  }

  func isReferenceSearchActive(for text: String) -> Bool {
    OutlineDocument.blockReferenceSearchQuery(text) != nil
  }

  func syncCurrentProjectSnapshot() {
    replaceCurrentProjectDocument(uiDocument)
  }

  func updateCurrentProjectTitle(_ newTitle: String) {
    let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedTitle = trimmed.isEmpty ? OutlinerProject.defaultTitle : trimmed
    Task { @MainActor in
      await appState.updateProjectDocumentTitle(resolvedTitle, projectID: currentProjectID)
    }
  }

  func updateCurrentProjectStage(_ stage: ProjectProgressStage) {
    appState.setProjectDocumentStage(stage, projectID: currentProjectID)
  }

  func applyPreferredProjectSelectionIfNeeded() {
    guard let preferredProjectID else { return }
    guard currentProjectID != preferredProjectID else { return }
    guard syncedProjects.contains(where: { $0.id == preferredProjectID }) else { return }
    selectProject(preferredProjectID, persist: false)
  }

  func canonicalNodeGroups(
    in projects: [OutlinerProject]
  ) -> [[UUID]] {
    var groupsByCanonicalID: [UUID: [UUID]] = [:]
    var orderedCanonicalIDs: [UUID] = []

    func collect(_ nodes: [OutlineNode]) {
      for node in nodes {
        if groupsByCanonicalID[node.canonicalID] == nil {
          groupsByCanonicalID[node.canonicalID] = []
          orderedCanonicalIDs.append(node.canonicalID)
        }
        groupsByCanonicalID[node.canonicalID, default: []].append(node.id)
        collect(node.children)
      }
    }

    for project in projects {
      collect(project.document.rootNodes)
    }

    return orderedCanonicalIDs.compactMap { groupsByCanonicalID[$0] }
  }

  func canonicalPeerNodeIDs(
    for nodeID: UUID,
    in projects: [OutlinerProject]
  ) -> [UUID] {
    for group in canonicalNodeGroups(in: projects) where group.contains(nodeID) {
      return group
    }
    return [nodeID]
  }

  func normalizeSharedSidecarMetadata(
    in projects: [OutlinerProject]
  ) {
    let nodeGroups = canonicalNodeGroups(in: projects)
    let validNodeIDs = Set(nodeGroups.flatMap(\.self))
    replaceSidecarMetadataByNodeID(
      sidecarMetadataByNodeID.filter { validNodeIDs.contains($0.key) }
    )

    for group in nodeGroups {
      guard let sharedMetadata = group.compactMap({ sidecarMetadataByNodeID[$0] }).first else {
        continue
      }
      for nodeID in group {
        replaceSidecarMetadataByNodeID(for: nodeID, with: sharedMetadata)
      }
    }
  }

  func normalizeSharedReminderMetadata(
    in projects: [OutlinerProject]
  ) {
    let nodeGroups = canonicalNodeGroups(in: projects)
    let validNodeIDs = Set(nodeGroups.flatMap(\.self))
    replaceReminderMetadataByNodeID(reminderMetadataByNodeID.filter { validNodeIDs.contains($0.key) })

    for group in nodeGroups {
      guard let sharedMetadata = group.compactMap({ reminderMetadataByNodeID[$0] }).first else {
        continue
      }
      for nodeID in group {
        replaceReminderMetadataByNodeID(for: nodeID, metadata: sharedMetadata)
      }
    }
  }

  func synchronizeMirrorAuxiliaryState(in projects: [OutlinerProject]) {
    normalizeSharedSidecarMetadata(in: projects)
    normalizeSharedReminderMetadata(in: projects)
    let validContentIDs = Set(
      projects.flatMap { $0.document.flatten().map { $0.node.canonicalID } }
    )
    liveSync.normalizeMirrorState(validContentIDs: validContentIDs)
  }

  func synchronizedProjects(
    withCurrentDocument newDocument: OutlineDocument,
    preferredCanonicalSourceNodeIDs: Set<UUID> = []
  ) -> [OutlinerProject] {
    let updatedProjects = projects.map { project -> OutlinerProject in
      guard project.id == currentProjectID else { return project }
      return OutlinerProject(id: project.id, title: project.title, document: newDocument)
    }
    return OutlineNodeCloneEngine.synchronize(
      projects: updatedProjects,
      preferredProjectID: currentProjectID,
      preferredSourceNodeIDs: preferredCanonicalSourceNodeIDs
    )
  }

  func preferredMirroredSubtreeSourceIDs(
    around affectedNodeIDs: [UUID],
    oldDocument: OutlineDocument,
    newDocument: OutlineDocument
  ) -> Set<UUID> {
    for nodeID in affectedNodeIDs {
      let anchorID: UUID?
      if OutlineNodeTreeNavigator.findNode(id: nodeID, in: newDocument.rootNodes) != nil {
        anchorID = nodeID
      } else if let parentID = OutlineNodeTreeNavigator.parentOf(id: nodeID, in: oldDocument.rootNodes),
                OutlineNodeTreeNavigator.findNode(id: parentID, in: newDocument.rootNodes) != nil {
        anchorID = parentID
      } else {
        anchorID = nil
      }

      guard let anchorID else { continue }

      var rootID = anchorID
      var currentID = anchorID

      while let parentID = OutlineNodeTreeNavigator.parentOf(id: currentID, in: newDocument.rootNodes),
            let parentNode = OutlineNodeTreeNavigator.findNode(id: parentID, in: newDocument.rootNodes),
            parentNode.isCloneInstance {
        rootID = parentID
        currentID = parentID
      }

      guard let rootNode = OutlineNodeTreeNavigator.findNode(id: rootID, in: newDocument.rootNodes),
            rootNode.isCloneInstance else {
        continue
      }

      var ids: Set<UUID> = []
      func collect(_ node: OutlineNode) {
        ids.insert(node.id)
        for child in node.children {
          collect(child)
        }
      }
      collect(rootNode)
      return ids
    }

    return []
  }

  func commitMirroredSubtreeChange(
    _ newDocument: OutlineDocument,
    around affectedNodeIDs: [UUID],
    pushUndoSnapshot: Bool = true,
    triggerAutoPush: Bool = true
  ) {
    commitDocumentChange(
      newDocument,
      pushUndoSnapshot: pushUndoSnapshot,
      triggerAutoPush: triggerAutoPush,
      preferredCanonicalSourceNodeIDs: preferredMirroredSubtreeSourceIDs(
        around: affectedNodeIDs,
        oldDocument: uiDocument,
        newDocument: newDocument
      )
    )
  }

  func commitMirroredSubtreeChange(
    _ newDocument: OutlineDocument,
    around nodeID: UUID,
    pushUndoSnapshot: Bool = true,
    triggerAutoPush: Bool = true
  ) {
    commitMirroredSubtreeChange(
      newDocument,
      around: [nodeID],
      pushUndoSnapshot: pushUndoSnapshot,
      triggerAutoPush: triggerAutoPush
    )
  }

  func applyDocumentMutation(
    pushUndoSnapshot: Bool = true,
    triggerAutoPush: Bool = true,
    _ mutation: (inout OutlineDocument) -> Void
  ) {
    var updated = uiDocument
    mutation(&updated)
    commitDocumentChange(
      updated,
      pushUndoSnapshot: pushUndoSnapshot,
      triggerAutoPush: triggerAutoPush
    )
  }

  func resolvedCloneSource(
    canonicalID: UUID,
    preferredProjectID: UUID
  ) -> OutlineResolvedReference? {
    OutlinerProjectGraph.resolveCloneSource(
      canonicalID: canonicalID,
      preferredProjectID: preferredProjectID,
      in: syncedProjects
    )
  }

  func canCloneResolvedNode(
    _ sourceNode: OutlineNode,
    in projectID: UUID,
    from sourceID: UUID
  ) -> Bool {
    guard projectID == currentProjectID else { return true }
    guard sourceNode.id != sourceID else { return false }
    return !OutlineNodeTreeNavigator.isDescendant(
      nodeID: sourceNode.id,
      of: sourceID,
      in: uiDocument.rootNodes
    )
  }

  func canInsertClone(
    of sourceNode: OutlineNode,
    from projectID: UUID,
    onto targetID: UUID
  ) -> Bool {
    guard projectID == currentProjectID else { return true }
    guard sourceNode.id != targetID else { return false }
    return !OutlineNodeTreeNavigator.isDescendant(
      nodeID: targetID,
      of: sourceNode.id,
      in: uiDocument.rootNodes
    )
  }

  func handleConvertReferenceToBullet(id: UUID) {
    var updatedDocument = uiDocument
    updatedDocument.updateNode(id: id) { node in
      node.type = .bullet
      node.referenceProjectID = nil
    }
    commitMirroredSubtreeChange(updatedDocument, around: id)
  }

  func referenceSuggestions(
    for text: String,
    excluding nodeID: UUID
  ) -> [OutlineBlockReferenceSuggestion] {
    guard renderProfile.showsReferenceSuggestions else { return [] }
    guard isReferenceSearchActive(for: text) else { return [] }
    let query = OutlineDocument.blockReferenceSearchQuery(text) ?? ""
    return OutlinerProjectGraph.referenceSuggestions(
      query: query,
      currentProjectID: currentProjectID,
      excluding: nodeID,
      in: syncedProjects
    )
  }

  func handleToggleCompleted(id: UUID) {
    let wasCompleted = OutlineNodeTreeNavigator.findNode(id: id, in: uiDocument.rootNodes)?.type.isCompleted ?? false
    var updatedDocument = uiDocument
    updatedDocument.updateNode(id: id) { node in
      if case .task(let completed) = node.type {
        node.type = .task(completed: !completed)
      }
    }
    if wasCompleted {
      clearCompletedNodeHideCompletedGrace(id)
    } else if hideCompleted {
      markCompletedNodeVisibleDuringHideCompletedGrace(id)
    }
    if nodeIsCloned(id: id) {
      commitMirroredSubtreeChange(updatedDocument, around: id)
    } else {
      outlineUndoManager.pushSnapshot(uiDocument, focusedNodeID: focusedNodeID)
      commitTextOnlyChange(updatedDocument, directMetadataNodeID: id)
    }
  }

  func handleToggleCollapse(id: UUID) {
    if nodeIsCloned(id: id) {
      applyDocumentMutation { doc in
        doc.updateNode(id: id) { $0.isCollapsed.toggle() }
      }
    } else {
      var updatedDocument = uiDocument
      updatedDocument.updateNode(id: id) { $0.isCollapsed.toggle() }
      outlineUndoManager.pushSnapshot(uiDocument, focusedNodeID: focusedNodeID)
      commitTextOnlyChange(updatedDocument)
    }
  }

  func handleToggleType(id: UUID) {
    var updatedDocument = uiDocument
    updatedDocument.updateNode(id: id) { node in
      switch node.type {
      case .bullet, .reference:
        node.type = .task(completed: false)
      case .task:
        node.type = .bullet
      }
    }
    if nodeIsCloned(id: id) {
      commitMirroredSubtreeChange(updatedDocument, around: id)
    } else {
      outlineUndoManager.pushSnapshot(uiDocument, focusedNodeID: focusedNodeID)
      commitTextOnlyChange(updatedDocument)
    }
  }

  func handleCommitAndToggleType(id: UUID, committedText: String) {
    if !selectedNodeIDs.isEmpty { clearBlockSelection() }
    var updatedDocument = uiDocument
    updatedDocument.updateNode(id: id) { node in
      node.text = committedText
      node.referenceProjectID = nil
      switch node.type {
      case .bullet, .reference:
        node.type = .task(completed: false)
      case .task:
        node.type = .bullet
      }
    }
    commitMirroredSubtreeChange(updatedDocument, around: id)
  }

  func requestFocus(on nodeID: UUID, cursorPosition: Int = 0) {
    focusedNodeID = nodeID
    if OutlineNodeTreeNavigator.findNode(id: nodeID, in: uiDocument.rootNodes) != nil {
      pendingSelectionRequest = OutlineNodeSelectionRequest(
        nodeID: nodeID,
        cursorPosition: cursorPosition
      )
    } else {
      pendingSelectionRequest = nil
    }
  }

  func beginProjectTitleEditing() {
    clearBlockSelection()
    pendingSelectionRequest = nil
    focusedNodeID = nil
  }

  func handleProjectTitleFocusChange(_ focused: Bool) {
    isProjectTitleFocused = focused
    if focused {
      beginProjectTitleEditing()
    }
    synchronizeReminderPushEditingState()
  }

  func handleNodeEditingEnded(id: UUID) {
    discardEmptyBlurredBulletIfNeeded(id: id)
    endReminderPushEditing(for: id)
  }

  func discardEmptyBlurredBulletIfNeeded(id: UUID) {
    guard let node = OutlineNodeTreeNavigator.findNode(id: id, in: uiDocument.rootNodes) else {
      return
    }
    guard node.type == .bullet else { return }
    guard node.children.isEmpty else { return }
    guard node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    var updatedDocument = uiDocument
    guard updatedDocument.removeNode(id: id) != nil else { return }
    if updatedDocument.rootNodes.isEmpty {
      updatedDocument = OutlineDocument.starterDocument()
    }

    if nodeIsCloned(id: id) {
      commitMirroredSubtreeChange(updatedDocument, around: id, pushUndoSnapshot: false)
    } else {
      handleStructuralChange(updatedDocument)
    }

    if focusedNodeID == id {
      focusedNodeID = nil
      pendingSelectionRequest = nil
    }
  }

  func handleDeleteBackward(id: UUID) {
    clearBlockSelection()
    if let result = OutlineNodeDeletionEngine.deleteBackwardAtStart(nodeID: id, in: uiDocument) {
      if nodeIsCloned(id: id) {
        commitMirroredSubtreeChange(result.document, around: id)
      } else {
        outlineUndoManager.pushSnapshot(uiDocument, focusedNodeID: focusedNodeID)
        handleStructuralChange(result.document)
      }
      if let focusNodeID = result.focusNodeID {
        if let cursorPosition = result.cursorPosition {
          requestFocus(on: focusNodeID, cursorPosition: cursorPosition)
        } else {
          requestFocus(on: focusNodeID)
        }
      } else {
        focusedNodeID = nil
        pendingSelectionRequest = nil
      }
    }
  }

  func handleDeleteSubtree(id: UUID) {
    clearBlockSelection()
    let result = OutlineNodeDeletionEngine.deleteSubtree(nodeID: id, in: uiDocument)
    commitMirroredSubtreeChange(result.document, around: id)
    if let nextFocusID = result.nextFocusID {
      requestFocus(on: nextFocusID)
    } else {
      focusedNodeID = nil
      pendingSelectionRequest = nil
    }
  }

  func handleDeleteSelectedSubtrees(selectedRootIDs: [UUID]) {
    let orderedRootIDs = selectedRootIDs.filter { selectedNodeIDs.contains($0) }
    guard orderedRootIDs.count > 1 else {
      if let onlyID = orderedRootIDs.first {
        handleDeleteSubtree(id: onlyID)
      }
      return
    }

    let flat = uiDocument.flatten()
    let removedNodeIDs = selectedNodeIDs
    let previousFocusID = flat.firstIndex(where: { removedNodeIDs.contains($0.id) }).flatMap { index in
      index > 0 ? flat[index - 1].id : nil
    }
    let nextFocusID = flat.lastIndex(where: { removedNodeIDs.contains($0.id) }).flatMap { index in
      index + 1 < flat.count ? flat[index + 1].id : nil
    }

    var updatedDocument = uiDocument
    for rootID in orderedRootIDs.reversed() {
      _ = updatedDocument.removeNode(id: rootID)
    }

    let resolvedFocusID: UUID?
    if updatedDocument.rootNodes.isEmpty {
      updatedDocument = OutlineDocument.starterDocument()
      resolvedFocusID = updatedDocument.rootNodes.first?.id
    } else {
      resolvedFocusID = previousFocusID ?? nextFocusID
    }

    clearBlockSelection()
    commitMirroredSubtreeChange(updatedDocument, around: orderedRootIDs)
    if let resolvedFocusID {
      requestFocus(on: resolvedFocusID)
    } else {
      focusedNodeID = nil
      pendingSelectionRequest = nil
    }
  }

  func handleIndent(id: UUID, cursorPosition: Int) {
    clearBlockSelection()
    if let result = OutlineNodeReparentEngine.indent(nodeID: id, in: uiDocument) {
      if nodeIsCloned(id: id) {
        commitMirroredSubtreeChange(result, around: id)
      } else {
        outlineUndoManager.pushSnapshot(uiDocument, focusedNodeID: focusedNodeID)
        handleStructuralChange(result)
      }
      requestFocus(on: id, cursorPosition: cursorPosition)
    }
  }

  func handleOutdent(id: UUID, cursorPosition: Int) {
    clearBlockSelection()
    if let result = OutlineNodeReparentEngine.outdent(nodeID: id, in: uiDocument) {
      if nodeIsCloned(id: id) {
        commitMirroredSubtreeChange(result, around: id)
      } else {
        outlineUndoManager.pushSnapshot(uiDocument, focusedNodeID: focusedNodeID)
        handleStructuralChange(result)
      }
      requestFocus(on: id, cursorPosition: cursorPosition)
    }
  }

  func handleMoveUp(id: UUID) {
    clearBlockSelection()
    if let prevID = OutlineNodeTreeNavigator.previousVisibleNode(before: id, in: uiDocument) {
      pendingSelectionRequest = nil
      focusedNodeID = prevID
    }
  }

  func handleMoveDown(id: UUID) {
    clearBlockSelection()
    if let nextID = OutlineNodeTreeNavigator.nextVisibleNode(after: id, in: uiDocument) {
      pendingSelectionRequest = nil
      focusedNodeID = nextID
    }
  }

  func handleMoveLeftFromStart(id: UUID) {
    clearBlockSelection()
    guard let previousID = OutlineNodeTreeNavigator.previousVisibleNode(before: id, in: uiDocument),
          let previousNode = OutlineNodeTreeNavigator.findNode(id: previousID, in: uiDocument.rootNodes) else {
      return
    }
    requestFocus(on: previousID, cursorPosition: previousNode.text.utf16.count)
  }

  func handleMoveRightFromEnd(id: UUID) {
    clearBlockSelection()
    guard let nextID = OutlineNodeTreeNavigator.nextVisibleNode(after: id, in: uiDocument) else {
      return
    }
    requestFocus(on: nextID, cursorPosition: 0)
  }

  func handleCommandToggleSelection(id: UUID) {
    OutlineSelectionDiagnostics.log("commandToggleSelection id=\(id.uuidString)")
    exitActiveEditing()
    var updated = selectedNodeOrder
    if let index = updated.firstIndex(of: id) {
      updated.remove(at: index)
    } else {
      updated.append(id)
    }
    setBlockSelection(updated, direction: nil)
  }

  func beginLineSelectionIfNeeded(id: UUID) -> Bool {
    guard selectedNodeIDs.isEmpty else { return false }
    OutlineSelectionDiagnostics.log("beginLineSelectionIfNeeded id=\(id.uuidString)")
    exitActiveEditing()
    setBlockSelection([id], direction: nil)
    return true
  }

  func handleSelectionMoveUp() {
    OutlineSelectionDiagnostics.log(
      "handleSelectionMoveUp selectedRoot=\(selectedNodeOrder.first?.uuidString ?? "nil")"
    )
    guard let selectedRootID = selectedNodeOrder.first,
          let previousID = previousVisibleSelectedCandidate(before: selectedRootID) else {
      OutlineSelectionDiagnostics.log("handleSelectionMoveUp.noPrevious")
      return
    }
    setBlockSelection([previousID], direction: nil)
  }

  func handleSelectionMoveDown() {
    OutlineSelectionDiagnostics.log(
      "handleSelectionMoveDown selectedRoot=\(selectedNodeOrder.last?.uuidString ?? "nil")"
    )
    guard let selectedRootID = selectedNodeOrder.last,
          let nextID = OutlineNodeTreeNavigator.nextVisibleNode(after: selectedRootID, in: uiDocument) else {
      OutlineSelectionDiagnostics.log("handleSelectionMoveDown.noNext")
      return
    }
    setBlockSelection([nextID], direction: nil)
  }

  func handleShiftMoveUp(id: UUID) {
    if beginLineSelectionIfNeeded(id: id) {
      return
    }
    if selectedNodeOrder.count == 1 {
      guard let prevID = previousVisibleSelectedCandidate(before: selectedNodeOrder[0]) else { return }
      appendBlockSelection(prevID, direction: OutlineBlockSelectionDirection.up)
      pendingSelectionRequest = nil
      focusedNodeID = nil
      return
    }

    if blockSelectionDirection == .up {
      guard let selectionLeadID = selectedNodeOrder.last,
            let prevID = previousVisibleSelectedCandidate(before: selectionLeadID) else {
        return
      }
      appendBlockSelection(prevID, direction: OutlineBlockSelectionDirection.up)
      pendingSelectionRequest = nil
      focusedNodeID = nil
    } else {
      dropLastBlockSelection()
      pendingSelectionRequest = nil
      focusedNodeID = nil
    }
  }

  func handleShiftMoveDown(id: UUID) {
    if beginLineSelectionIfNeeded(id: id) {
      return
    }
    if selectedNodeOrder.count == 1 {
      guard let nextID = nextVisibleSelectedCandidate(after: selectedNodeOrder[0]) else { return }
      appendBlockSelection(nextID, direction: OutlineBlockSelectionDirection.down)
      pendingSelectionRequest = nil
      focusedNodeID = nil
      return
    }

    if blockSelectionDirection == .down {
      guard let selectionLeadID = selectedNodeOrder.last,
            let nextID = nextVisibleSelectedCandidate(after: selectionLeadID) else {
        return
      }
      appendBlockSelection(nextID, direction: OutlineBlockSelectionDirection.down)
      pendingSelectionRequest = nil
      focusedNodeID = nil
    } else {
      dropLastBlockSelection()
      pendingSelectionRequest = nil
      focusedNodeID = nil
    }
  }

  func handleTextEditingUndo(isRedo: Bool) -> Bool {
    guard let responder = activeEditableTextResponder else { return false }
    if isRedo {
      responder.undoManager?.redo()
    } else {
      responder.undoManager?.undo()
    }
    return true
  }

  var activeEditableTextResponder: NSTextView? {
    let responder = NSApp.keyWindow?.firstResponder ?? NSApp.mainWindow?.firstResponder
    guard let textView = responder as? NSTextView, textView.isEditable else { return nil }
    return textView
  }

  func handleAddAttachment(id: UUID) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    if panel.runModal() == .OK, let url = panel.url {
      let attachment = OutlineNodeAttachment(
        fileName: url.lastPathComponent,
        filePath: url.path,
        mimeType: OutlineNodeAttachment.detectMIMEType(for: url)
      )
      var updatedDocument = uiDocument
      updatedDocument.updateNode(id: id) { $0.attachments.append(attachment) }
      commitMirroredSubtreeChange(updatedDocument, around: id)
    }
  }

  func handleInsertReferenceSuggestion(
    id: UUID,
    suggestion: OutlineBlockReferenceSuggestion
  ) {
    guard let resolved = resolvedCloneSource(
      canonicalID: suggestion.targetID,
      preferredProjectID: suggestion.projectID
    ),
      canCloneResolvedNode(resolved.node, in: resolved.projectID, from: id) else {
      return
    }
    commitMirroredSubtreeChange(
      OutlineNodeCloneEngine.replaceNode(
        nodeID: id,
        withCloneOf: resolved.node,
        in: uiDocument
      ),
      around: id
    )
  }

  func canReferenceTarget(
    _ targetID: UUID,
    in projectID: UUID,
    from sourceID: UUID
  ) -> Bool {
    guard projectID == currentProjectID else { return true }
    guard targetID != sourceID else { return false }
    return !OutlineNodeTreeNavigator.isDescendant(
      nodeID: targetID,
      of: sourceID,
      in: uiDocument.rootNodes
    )
  }

  func handleNavigateToReference(targetID: UUID, projectID: UUID?) {
    let resolvedProjectID = projectID ?? currentProjectID
    if resolvedProjectID != currentProjectID {
      selectProject(resolvedProjectID, persist: false)
    }
    // zoom 안에 있으면 zoomPath를 정리하여 원본이 보이도록 한다
    if !zoomPath.isEmpty {
      // 원본이 현재 zoom 스코프에 있는지 확인
      if let zoomID = zoomPath.last,
         let zoomNode = OutlineNodeTreeNavigator.findNode(id: zoomID, in: uiDocument.rootNodes),
         OutlineNodeTreeNavigator.findNode(id: targetID, in: [zoomNode]) == nil {
        // 원본이 현재 zoom 안에 없으면 zoom을 해제한다
        zoomPath = []
      }
    }
    pendingSelectionRequest = nil
    focusedNodeID = targetID
  }

  func dragPreviewText(for nodeID: UUID) -> String {
    let draggedRoots = draggedRootNodeIDs(for: OutlineNodeIDTransfer(nodeID: nodeID, projectID: currentProjectID))
    if draggedRoots.count > 1 {
      return "\(draggedRoots.count)개 노드 이동"
    }
    guard let node = OutlineNodeTreeNavigator.findNode(id: nodeID, in: uiDocument.rootNodes) else {
      return "(빈 노드)"
    }
    return node.text.isEmpty ? "(빈 노드)" : node.text
  }

  func topLevelSelectedNodeIDsInDocumentOrder() -> [UUID] {
    uiDocument.flatten().map(\.id).filter { selectedNodeIDs.contains($0) && !isDescendantOfSelectedNode($0) }
  }

  func draggedRootNodeIDs(for transfer: OutlineNodeIDTransfer) -> [UUID] {
    guard transfer.projectID == currentProjectID, selectedNodeIDs.contains(transfer.nodeID) else {
      return [transfer.nodeID]
    }
    let selectedRoots = topLevelSelectedNodeIDsInDocumentOrder()
    return selectedRoots.isEmpty ? [transfer.nodeID] : selectedRoots
  }

  func handleDropNode(
    transfer: OutlineNodeIDTransfer,
    location: CGPoint,
    targetEntry: OutlineFlattenedEntry
  ) {
    let placement = OutlineNodeDragDropEngine.placementFromDropLocation(
      dropLocation: location,
      depth: targetEntry.depth
    )
    let draggedRootIDs = draggedRootNodeIDs(for: transfer)

    if shouldCreateReferenceOnDrop(transfer: transfer),
       draggedRootIDs.count == 1,
       let sourceProject = syncedProjects.first(where: { $0.id == transfer.projectID }),
       let sourceNode = OutlineNodeTreeNavigator.findNode(
        id: transfer.nodeID,
        in: sourceProject.document.rootNodes
       ),
       canInsertClone(of: sourceNode, from: transfer.projectID, onto: targetEntry.id) {
      let newDoc = OutlineNodeCloneEngine.insertClone(
        of: sourceNode,
        targetID: targetEntry.id,
        placement: placement,
        in: uiDocument
      )
      commitDocumentChange(newDoc)
      dropTargetNodeID = nil
      dropPlacement = nil
      return
    }
    if let newDoc = OutlineNodeDragDropEngine.move(
      sourceIDs: draggedRootIDs,
      targetID: targetEntry.id,
      placement: placement,
      in: uiDocument
    ) {
      commitMirroredSubtreeChange(newDoc, around: draggedRootIDs + [targetEntry.id])
      setBlockSelection(draggedRootIDs, direction: nil)
      focusedNodeID = nil
      pendingSelectionRequest = nil
      dropTargetNodeID = nil
      dropPlacement = nil
      return
    }
    dropTargetNodeID = nil
    dropPlacement = nil
  }

  func shouldCreateReferenceOnDrop(transfer: OutlineNodeIDTransfer) -> Bool {
    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return transfer.projectID != currentProjectID || flags.contains(.option)
  }

  func handleDropPlacementChange(
    entryID: UUID,
    placement: OutlineNodeDragDropEngine.Placement?
  ) {
    if let placement {
      dropTargetNodeID = entryID
      dropPlacement = placement
    } else if dropTargetNodeID == entryID {
      dropTargetNodeID = nil
      dropPlacement = nil
    }
  }

  func handleDropFile(providers: [NSItemProvider], nodeID: UUID) -> Bool {
    guard let provider = providers.first else { return false }
    _ = provider.loadObject(ofClass: URL.self) { url, error in
      guard let url, error == nil else { return }
      DispatchQueue.main.async {
        let attachment = OutlineNodeAttachment(
          fileName: url.lastPathComponent,
          filePath: url.path,
          mimeType: OutlineNodeAttachment.detectMIMEType(for: url)
        )
        var updatedDocument = uiDocument
        updatedDocument.updateNode(id: nodeID) { $0.attachments.append(attachment) }
        commitMirroredSubtreeChange(updatedDocument, around: nodeID)
      }
    }
    return true
  }

  func commitDocumentChange(
    _ newDocument: OutlineDocument,
    pushUndoSnapshot: Bool = true,
    triggerAutoPush: Bool = true,
    commitReminderNoteDirectly: Bool = true,
    preferredCanonicalSourceNodeIDs: Set<UUID> = []
  ) {
    let previousDocument = uiDocument
    let previousProjections = nodeBasedProjections()
    let changedReminderProjectionContentIDs = changedReminderProjectionContentIDs(
      from: previousDocument,
      to: newDocument
    )
    if pushUndoSnapshot {
      outlineUndoManager.pushSnapshot(previousDocument, focusedNodeID: focusedNodeID)
    }
    let synchronized = synchronizedProjects(
      withCurrentDocument: newDocument,
      preferredCanonicalSourceNodeIDs: preferredCanonicalSourceNodeIDs
    )
    storePendingRemovalReferences(from: previousProjections, in: synchronized)
    replaceProjectedProjects(synchronized)
    replaceCurrentDocument(synchronized.first(where: { $0.id == currentProjectID })?.document ?? newDocument)
    refreshCanonicalInstanceCounts(for: synchronized)
    synchronizeMirrorAuxiliaryState(in: synchronized)
    if firstSyncCompleted || !resolvedReminderLinksByContentID().isEmpty {
      appState.beginEditorSession(
        id: outlinerSyncSessionID,
        syncRelevant: true,
        syncKind: ReminderSyncEditGate.SessionKind.subtree,
        projectID: currentProjectID
      )
    }
    if !changedReminderProjectionContentIDs.isEmpty {
      enqueueReminderPushContentIDs(changedReminderProjectionContentIDs)
    }
    let shouldTriggerAutoPush =
      !commitReminderNoteDirectly
      && triggerAutoPush
      && !changedReminderProjectionContentIDs.isEmpty
    syncEditorSessionState(triggerAutoPush: shouldTriggerAutoPush)
    guard commitReminderNoteDirectly else { return }
    commitPendingReminderNoteSourceDirectSaveIfNeeded(
      excluding: reminderPushEditingBoundary
    )
  }

  func storePendingRemovalReferences(
    from previousProjections: [OutlinerReminderProjection],
    in projects: [OutlinerProject]
  ) {
    let nextContentIDs = Set(
      projects.flatMap { project in
        project.document.flatten().compactMap { entry in
          entry.node.type.isTask ? entry.node.canonicalID : nil
        }
      }
    )
    let removedProjections = previousProjections.filter { !nextContentIDs.contains($0.contentID) }
    let removedContentIDs = Set(removedProjections.map(\.contentID))

    for projection in removedProjections {
      guard normalizedNonEmptyString(projection.reminderIdentifier) != nil
        || normalizedNonEmptyString(projection.reminderExternalIdentifier) != nil
      else {
        continue
      }
      mutateTaskSessionOverlay(for: projection.contentID) { overlay in
        overlay.storePendingRemovalReference(
          reminderIdentifier: projection.reminderIdentifier,
          reminderExternalIdentifier: projection.reminderExternalIdentifier
        )
      }
    }

    for contentID in Array(integratedTaskStatesByContentID.keys)
    where nextContentIDs.contains(contentID) && !removedContentIDs.contains(contentID) {
      mutateTaskSessionOverlay(for: contentID) { overlay in
        overlay.clearPendingRemovalReference()
      }
    }
  }

  /// Lightweight commit for text-only edits on non-clone nodes.
  /// Skips clone synchronization, instance count rebuild, and mirror normalization.
  func commitTextOnlyChange(
    _ newDocument: OutlineDocument,
    directMetadataNodeID: UUID? = nil,
    commitReminderNoteDirectly: Bool = true
  ) {
    let changedReminderProjectionContentIDs = changedReminderProjectionContentIDs(
      from: uiDocument,
      to: newDocument
    )
    applyCurrentProjectTextOnlyDocument(newDocument)
    var queuedReminderProjectionContentIDs = changedReminderProjectionContentIDs
    if let directMetadataNodeID,
       let directContentID = resolvedContentID(for: directMetadataNodeID)
    {
      queuedReminderProjectionContentIDs.remove(directContentID)
    }
    if !queuedReminderProjectionContentIDs.isEmpty {
      enqueueReminderPushContentIDs(queuedReminderProjectionContentIDs)
    }
    if let directMetadataNodeID {
      syncEditorSessionState(triggerAutoPush: false)
      commitReminderMetadataDirectSave(for: directMetadataNodeID)
      if !queuedReminderProjectionContentIDs.isEmpty {
        commitPendingReminderNoteSourceDirectSaveIfNeeded(
          excluding: reminderPushEditingBoundary
        )
      }
      return
    }
    syncEditorSessionState(triggerAutoPush: false)
    guard commitReminderNoteDirectly else { return }
    commitPendingReminderNoteSourceDirectSaveIfNeeded(
      excluding: reminderPushEditingBoundary
    )
  }

  func applyCurrentProjectTextOnlyDocument(_ newDocument: OutlineDocument) {
    replaceCurrentDocument(newDocument)
  }
}
