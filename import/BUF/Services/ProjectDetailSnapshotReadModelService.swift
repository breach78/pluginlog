import Foundation

enum ProjectDetailSnapshotReadModelService {
  static func snapshot(
    nodeID: UUID,
    treeRepository: WorkspaceTreeRepository,
    documentRepository: NormalizedDocumentReferenceRepository,
    includeArchived: Bool = false,
    includeCompleted: Bool = false,
    taskSortMode: ProjectDetailTaskDateSortMode = .none
  ) async throws -> ProjectDetailSnapshot {
    guard let node = try await treeRepository.fetchNode(id: nodeID) else {
      throw WorkspaceTreeRepositoryError.nodeNotFound
    }

    let breadcrumb = try await treeRepository.breadcrumb(nodeID: nodeID)
    let childNodes = try await treeRepository.childNodes(
      parentID: nodeID,
      includeArchived: includeArchived
    )
    let subtree = try await treeRepository.subtree(nodeID: nodeID, includeArchived: true)
    let visibleSubtreeTasks = subtree.tasks.filter { includeArchived || !$0.isArchived }
    let visibleDirectTasks = sortTasks(
      visibleSubtreeTasks.filter { task in
        task.workspaceNodeID == nodeID && (includeCompleted || !task.isCompleted)
      },
      mode: taskSortMode
    )
    let taskRows = visibleDirectTasks.map(makeTaskRowSnapshot)
    let rootStructureNodes = rootStructureNodes(
      for: node,
      taskRows: taskRows,
      dataDirectory: treeRepository.dataDirectoryURL
    )

    let projectAttachments = try await attachmentReferences(
      ownerType: .project,
      ownerIDs: [nodeID],
      documentRepository: documentRepository,
      includeArchived: includeArchived
    )
    let taskAttachments = try await attachmentReferences(
      ownerType: .task,
      ownerIDs: visibleDirectTasks.map(\.id),
      documentRepository: documentRepository,
      includeArchived: includeArchived
    )

    return ProjectDetailSnapshot(
      node: node,
      projectStartDate: nil,
      projectDeadline: nil,
      breadcrumb: breadcrumb,
      childNodes: childNodes,
      taskRows: taskRows,
      rootStructureNodes: rootStructureNodes,
      projectAttachmentSummary: makeAttachmentSummary(
        ownerType: .project,
        ownerID: nodeID,
        references: projectAttachments[nodeID] ?? []
      ),
      taskAttachmentSummaries: visibleDirectTasks.map { task in
        makeAttachmentSummary(
          ownerType: .task,
          ownerID: task.id,
          references: taskAttachments[task.id] ?? []
        )
      },
      aggregate: try await makeAggregate(
        nodeID: nodeID,
        subtreeNodes: subtree.nodes,
        subtreeTasks: subtree.tasks,
        includeArchived: includeArchived,
        documentRepository: documentRepository
      ),
      includeArchived: includeArchived,
      includeCompleted: includeCompleted,
      taskSortMode: taskSortMode,
      computedAt: .now
    )
  }

  private static func makeAggregate(
    nodeID: UUID,
    subtreeNodes: [WorkspaceNodeRecord],
    subtreeTasks: [TaskRecord],
    includeArchived: Bool,
    documentRepository: NormalizedDocumentReferenceRepository
  ) async throws -> SubtreeAggregateSnapshot {
    let visibleNodes = subtreeNodes.filter { includeArchived || !$0.isArchived }
    let visibleTasks = subtreeTasks.filter { includeArchived || !$0.isArchived }
    let descendantNodes = visibleNodes.filter { $0.id != nodeID }
    let descendantProjectNodeIDs = visibleNodes
      .filter { $0.kind == .project }
      .map(\.id)
    let visibleTaskIDs = visibleTasks.map(\.id)

    let projectAttachments = try await attachmentReferences(
      ownerType: .project,
      ownerIDs: descendantProjectNodeIDs,
      documentRepository: documentRepository,
      includeArchived: includeArchived
    )
    let taskAttachments = try await attachmentReferences(
      ownerType: .task,
      ownerIDs: visibleTaskIDs,
      documentRepository: documentRepository,
      includeArchived: includeArchived
    )

    let attachmentCount =
      projectAttachments.values.reduce(0) { $0 + $1.count }
      + taskAttachments.values.reduce(0) { $0 + $1.count }

    return SubtreeAggregateSnapshot(
      nodeID: nodeID,
      descendantProjectCount: descendantNodes.filter { $0.kind == .project }.count,
      descendantFolderCount: descendantNodes.filter { $0.kind == .folder }.count,
      descendantImportedGroupCount: 0,
      directTaskCount: visibleTasks.filter { $0.workspaceNodeID == nodeID }.count,
      subtreeTaskCount: visibleTasks.count,
      openTaskCount: visibleTasks.filter { !$0.isCompleted }.count,
      completedTaskCount: visibleTasks.filter(\.isCompleted).count,
      archivedTaskCount: subtreeTasks.filter(\.isArchived).count,
      attachmentCount: attachmentCount,
      latestTaskUpdatedAt: visibleTasks.map(\.localUpdatedAt).max()
    )
  }

  private static func attachmentReferences(
    ownerType: AttachmentOwnerType,
    ownerIDs: [UUID],
    documentRepository: NormalizedDocumentReferenceRepository,
    includeArchived: Bool
  ) async throws -> [UUID: [AttachmentReferenceRecord]] {
    var grouped: [UUID: [AttachmentReferenceRecord]] = [:]
    for ownerID in Set(ownerIDs) {
      let references = try await documentRepository.references(ownerType: ownerType, ownerID: ownerID)
        .filter { includeArchived || !$0.isArchived }
      if !references.isEmpty {
        grouped[ownerID] = references
      }
    }
    return grouped
  }

  private static func makeTaskRowSnapshot(_ task: TaskRecord) -> TaskRowSnapshot {
    let renderFingerprint = taskRowFingerprint(task)
    return TaskRowSnapshot(
      id: task.id,
      workspaceNodeID: task.workspaceNodeID,
      parentTaskID: task.parentTaskID,
      reminderExternalIdentifier: task.reminderExternalIdentifier,
      title: task.title,
      isCompleted: task.isCompleted,
      completionDate: task.completionDate,
      displayedDate: displayedDate(for: task),
      startDate: task.startDate,
      dueDate: task.dueDate,
      scheduleHasExplicitTime: task.scheduleHasExplicitTime,
      scheduledDurationMinutes: task.scheduledDurationMinutes,
      recurrenceRuleRaw: task.recurrenceRuleRaw,
      attachmentCount: max(0, task.attachmentCount),
      reminderNoteText: task.reminderNoteText,
      hasReminderNote: !task.reminderNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      requiredWorkDays: max(0, task.requiredWorkDays),
      completedWorkUnits: max(0, task.completedWorkUnits),
      completedWorkUnitDates: normalizedCompletedWorkUnitDates(for: task),
      preparationScheduleOverridesRaw: task.preparationScheduleOverridesRaw,
      rowOrder: task.rowOrder,
      priority: task.priority,
      isFlagged: task.isFlagged,
      isArchived: task.isArchived,
      localUpdatedAt: task.localUpdatedAt,
      createdAt: task.createdAt,
      renderFingerprint: renderFingerprint
    )
  }

  private static func rootStructureNodes(
    for node: WorkspaceNodeRecord,
    taskRows: [TaskRowSnapshot],
    dataDirectory: URL
  ) -> [ProjectDetailRootStructureNodeSnapshot] {
    guard
      let reminderListExternalIdentifier = ReminderProjectionIdentity.normalized(
        node.reminderListExternalIdentifier),
      let rootStructureRecord = ReminderProjectionSidecarReadService.rootStructureRecord(
        reminderListExternalIdentifier: reminderListExternalIdentifier,
        dataDirectory: dataDirectory
      )
    else {
      return []
    }

    let normalizedRecords = ReminderProjectRootStructureCodec.normalizedRecords(
      from: rootStructureRecord.rootNodes
    )
    let taskRowsByReminderExternalIdentifier: [String: TaskRowSnapshot] = Dictionary(
      uniqueKeysWithValues: taskRows.compactMap { taskRow in
        guard
          let reminderExternalIdentifier = ReminderProjectionIdentity.normalized(
            taskRow.reminderExternalIdentifier)
        else {
          return nil
        }
        return (reminderExternalIdentifier, taskRow)
      }
    )
    let rootTaskRows = taskRows.filter { $0.parentTaskID == nil }
    var consumedRootTaskIDs: Set<UUID> = []
    var flatNodes: [FlatRootStructureNode] = []

    for record in normalizedRecords {
      switch record {
      case .task(let reminderExternalIdentifier, let indent):
        guard
          let taskRow = taskRowsByReminderExternalIdentifier[
            ReminderProjectionIdentity.normalized(reminderExternalIdentifier)
              ?? reminderExternalIdentifier]
        else {
          continue
        }
        consumedRootTaskIDs.insert(taskRow.id)
        flatNodes.append(
          FlatRootStructureNode(
            indent: indent,
            kind: .task,
            id: taskRow.id,
            title: taskRow.title,
            taskID: taskRow.id
          )
        )

      case .mirror:
        continue

      case .bullet(let id, let text, let indent):
        flatNodes.append(
          FlatRootStructureNode(
            indent: indent,
            kind: .bullet,
            id: id,
            title: text,
            taskID: nil
          )
        )
      }
    }

    for taskRow in rootTaskRows where consumedRootTaskIDs.contains(taskRow.id) == false {
      flatNodes.append(
        FlatRootStructureNode(
          indent: 0,
          kind: .task,
          id: taskRow.id,
          title: taskRow.title,
          taskID: taskRow.id
        )
      )
    }

    var cursor = 0
    return buildRootStructureNodes(
      flatNodes,
      cursor: &cursor,
      depth: 0,
      parentNodeID: node.id
    )
  }

  private struct FlatRootStructureNode {
    let indent: Int
    let kind: ProjectDetailRootStructureNodeKind
    let id: UUID
    let title: String
    let taskID: UUID?
  }

  private static func buildRootStructureNodes(
    _ nodes: [FlatRootStructureNode],
    cursor: inout Int,
    depth: Int,
    parentNodeID: UUID?
  ) -> [ProjectDetailRootStructureNodeSnapshot] {
    var built: [ProjectDetailRootStructureNodeSnapshot] = []

    while cursor < nodes.count {
      let entry = nodes[cursor]
      if entry.indent < depth {
        break
      }
      guard entry.indent == depth else {
        cursor += 1
        continue
      }

      cursor += 1
      let children =
        entry.kind == .bullet
        ? buildRootStructureNodes(nodes, cursor: &cursor, depth: depth + 1, parentNodeID: entry.id)
        : []
      built.append(
        ProjectDetailRootStructureNodeSnapshot(
          id: entry.id,
          parentNodeID: parentNodeID,
          kind: entry.kind,
          title: entry.title,
          taskID: entry.taskID,
          children: children
        )
      )
    }

    return built
  }

  private static func makeAttachmentSummary(
    ownerType: AttachmentOwnerType,
    ownerID: UUID,
    references: [AttachmentReferenceRecord]
  ) -> AttachmentSummarySnapshot {
    let previews = references
      .sorted { lhs, rhs in
        if lhs.updatedAt == rhs.updatedAt {
          return lhs.originalFilename.localizedCaseInsensitiveCompare(rhs.originalFilename)
            == .orderedAscending
        }
        return lhs.updatedAt > rhs.updatedAt
      }
      .prefix(6)
      .map {
        AttachmentReferencePreviewSnapshot(
          id: $0.id,
          ownerID: $0.ownerID,
          originalFilename: $0.originalFilename,
          mimeType: $0.mimeType,
          byteSize: $0.byteSize,
          updatedAt: $0.updatedAt
        )
      }

    return AttachmentSummarySnapshot(
      ownerType: ownerType,
      ownerID: ownerID,
      totalCount: references.count,
      latestUpdatedAt: references.map(\.updatedAt).max(),
      previews: Array(previews),
      summaryFingerprint: attachmentSummaryFingerprint(references)
    )
  }

  private static func sortTasks(
    _ tasks: [TaskRecord],
    mode: ProjectDetailTaskDateSortMode
  ) -> [TaskRecord] {
    switch mode {
    case .none:
      return tasks.sorted(by: taskRowOrderComparator)
    case .recent:
      return tasks.sorted { lhs, rhs in
        compareTaskDate(lhs, rhs, ascending: true)
      }
    case .oldest:
      return tasks.sorted { lhs, rhs in
        compareTaskDate(lhs, rhs, ascending: false)
      }
    }
  }

  private static func compareTaskDate(
    _ lhs: TaskRecord,
    _ rhs: TaskRecord,
    ascending: Bool
  ) -> Bool {
    let left = displayedDate(for: lhs)
    let right = displayedDate(for: rhs)

    switch (left, right) {
    case (let l?, let r?):
      if l == r {
        return taskRowOrderComparator(lhs, rhs)
      }
      return ascending ? (l < r) : (l > r)
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    case (nil, nil):
      return taskRowOrderComparator(lhs, rhs)
    }
  }

  private static func taskRowOrderComparator(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
    if lhs.rowOrder == rhs.rowOrder {
      if lhs.createdAt == rhs.createdAt {
        return lhs.id.uuidString < rhs.id.uuidString
      }
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.rowOrder < rhs.rowOrder
  }

  private static func displayedDate(for task: TaskRecord) -> Date? {
    task.reminderDate
  }

  private static func normalizedCompletedWorkUnitDates(for task: TaskRecord) -> [Date] {
    let requiredCount = max(0, task.completedWorkUnits)
    guard requiredCount > 0 else { return [] }

    var dates = decodedCompletedWorkUnitDates(raw: task.completedWorkUnitDatesRaw)
    if dates.count > requiredCount {
      dates = Array(dates.prefix(requiredCount))
    }
    if dates.count < requiredCount {
      let fallbackDate = task.completionDate ?? task.localUpdatedAt
      dates.append(contentsOf: Array(repeating: fallbackDate, count: requiredCount - dates.count))
    }
    return dates
  }

  private static func decodedCompletedWorkUnitDates(raw: String) -> [Date] {
    guard
      !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([TimeInterval].self, from: data)
    else {
      return []
    }

    return decoded
      .filter(\.isFinite)
      .map(Date.init(timeIntervalSince1970:))
  }

  private static func taskRowFingerprint(_ task: TaskRecord) -> Int {
    var hasher = Hasher()
    hasher.combine(task.id)
    hasher.combine(task.workspaceNodeID)
    hasher.combine(task.parentTaskID)
    hasher.combine(task.parentTaskRemoteExternalIdentifier)
    hasher.combine(task.title)
    hasher.combine(task.isCompleted)
    hasher.combine(task.completionDate?.timeIntervalSinceReferenceDate)
    hasher.combine(task.startDate?.timeIntervalSinceReferenceDate)
    hasher.combine(task.dueDate?.timeIntervalSinceReferenceDate)
    hasher.combine(task.scheduleHasExplicitTime)
    hasher.combine(task.scheduledDurationMinutes)
    hasher.combine(task.recurrenceRuleRaw)
    hasher.combine(task.attachmentCount)
    hasher.combine(task.reminderNoteText)
    hasher.combine(task.requiredWorkDays)
    hasher.combine(task.completedWorkUnits)
    hasher.combine(task.completedWorkUnitDatesRaw)
    hasher.combine(task.preparationScheduleOverridesRaw)
    hasher.combine(task.rowOrder)
    hasher.combine(task.priority)
    hasher.combine(task.isFlagged)
    hasher.combine(task.isArchived)
    hasher.combine(task.localUpdatedAt.timeIntervalSinceReferenceDate)
    hasher.combine(task.createdAt.timeIntervalSinceReferenceDate)
    return hasher.finalize()
  }

  private static func attachmentSummaryFingerprint(_ references: [AttachmentReferenceRecord]) -> Int {
    var hasher = Hasher()
    hasher.combine(references.count)
    for reference in references.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
      hasher.combine(reference.id)
      hasher.combine(reference.ownerID)
      hasher.combine(reference.originalFilename)
      hasher.combine(reference.mimeType)
      hasher.combine(reference.byteSize)
      hasher.combine(reference.updatedAt.timeIntervalSinceReferenceDate)
      hasher.combine(reference.isArchived)
    }
    return hasher.finalize()
  }
}
