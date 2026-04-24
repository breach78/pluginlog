import Foundation

// Phase 0 legacy freeze:
// This block-page query path is maintenance-only during the outliner detail cutover.
// Do not attach new product behavior here; new detail work belongs in the outliner detail path.

enum ProjectDetailBlockPageQueryService {
  static func makePageSnapshot(
    from detailSnapshot: ProjectDetailSnapshot,
    childDetailSnapshotsByNodeID: [UUID: ProjectDetailSnapshot] = [:]
  ) -> BlockPageSnapshot {
    let orderingMode = BlockChildOrderingMode(taskDateSortMode: detailSnapshot.taskSortMode)
    let rootBlock = makeContainerBlock(
      from: detailSnapshot,
      isRoot: true,
      orderingMode: orderingMode,
      childDetailSnapshotsByNodeID: childDetailSnapshotsByNodeID,
      visitedNodeIDs: [detailSnapshot.node.id]
    )

    return BlockPageSnapshot(
      pageID: detailSnapshot.node.id,
      stageSourceProjectID: detailSnapshot.node.projectID ?? detailSnapshot.node.id,
      title: normalizedTitle(detailSnapshot.node.title),
      pageIconName: detailSnapshot.node.iconName,
      pageColorHex: detailSnapshot.node.colorHex,
      breadcrumb: detailSnapshot.breadcrumb.map {
        BlockPageBreadcrumbItem(id: $0.id, title: normalizedTitle($0.title))
      },
      rootBlock: rootBlock,
      orderingMode: orderingMode,
      includeArchived: detailSnapshot.includeArchived,
      includeCompleted: detailSnapshot.includeCompleted,
      computedAt: detailSnapshot.computedAt
    )
  }

  private static func makeContainerBlock(
    from detailSnapshot: ProjectDetailSnapshot,
    isRoot: Bool,
    orderingMode: BlockChildOrderingMode,
    childDetailSnapshotsByNodeID: [UUID: ProjectDetailSnapshot],
    visitedNodeIDs: Set<UUID>
  ) -> BlockNodeSnapshot {
    let taskAttachmentSummariesByOwnerID = detailSnapshot.taskAttachmentSummariesByOwnerID
    let taskBlocks = makeRootBlocks(
      from: detailSnapshot,
      attachmentSummariesByOwnerID: taskAttachmentSummariesByOwnerID,
      orderingMode: orderingMode
    )
    let childBlocks = detailSnapshot.childNodes.compactMap { childNode -> BlockNodeSnapshot? in
      guard !visitedNodeIDs.contains(childNode.id) else { return nil }
      if let childDetailSnapshot = childDetailSnapshotsByNodeID[childNode.id] {
        return makeContainerBlock(
          from: childDetailSnapshot,
          isRoot: false,
          orderingMode: BlockChildOrderingMode(taskDateSortMode: childDetailSnapshot.taskSortMode),
          childDetailSnapshotsByNodeID: childDetailSnapshotsByNodeID,
          visitedNodeIDs: visitedNodeIDs.union([childNode.id])
        )
      }
      return makeStandaloneNodeBlock(from: childNode)
    }

    return makeContainerBlock(
      from: detailSnapshot,
      isRoot: isRoot,
      orderingMode: orderingMode,
      taskBlocks: taskBlocks,
      childBlocks: childBlocks
    )
  }

  private static func makeContainerBlock(
    from detailSnapshot: ProjectDetailSnapshot,
    isRoot: Bool,
    orderingMode: BlockChildOrderingMode,
    taskBlocks: [BlockNodeSnapshot],
    childBlocks: [BlockNodeSnapshot]
  ) -> BlockNodeSnapshot {
    let rootSchedule = BlockScheduleSummary(
      displayedDate: detailSnapshot.projectDeadline ?? detailSnapshot.projectStartDate,
      startDate: detailSnapshot.projectStartDate,
      dueDate: detailSnapshot.projectDeadline,
      hasExplicitTime: false,
      scheduledDurationMinutes: nil
    )
    let body = BlockBodySnapshot(
      metaStrip: BlockMetaStripSnapshot(
        schedule: rootSchedule,
        requiredWorkDays: nil,
        completedWorkUnits: nil
      ),
      note: BlockNoteSnapshot(reminderText: "", markdown: detailSnapshot.node.noteMarkdown),
      attachments: detailSnapshot.projectAttachmentSummary.previews.map(makeAttachmentPreview)
    )
    let children = taskBlocks + childBlocks
    let header = BlockHeaderSnapshot(
      title: normalizedTitle(detailSnapshot.node.title),
      isCompleted: false,
      schedule: rootSchedule,
      attachmentCount: detailSnapshot.projectAttachmentSummary.totalCount,
      childCount: children.count,
      hasNote: body.note.hasContent,
      orderingMode: children.isEmpty ? nil : orderingMode
    )

    return BlockNodeSnapshot(
      id: detailSnapshot.node.id,
      parentNodeID: detailSnapshot.node.parentID,
      kind: BlockKind(workspaceNodeKind: detailSnapshot.node.kind),
      isRoot: isRoot,
      colorHex: detailSnapshot.node.colorHex,
      iconName: detailSnapshot.node.iconName,
      header: header,
      body: body,
      children: children
    )
  }

  private static func makeStandaloneNodeBlock(from node: WorkspaceNodeRecord) -> BlockNodeSnapshot {
    let note = BlockNoteSnapshot(reminderText: "", markdown: node.noteMarkdown)
    let body = BlockBodySnapshot(
      metaStrip: BlockMetaStripSnapshot(
        schedule: .empty,
        requiredWorkDays: nil,
        completedWorkUnits: nil
      ),
      note: note,
      attachments: []
    )
    let header = BlockHeaderSnapshot(
      title: normalizedTitle(node.title),
      isCompleted: false,
      schedule: .empty,
      attachmentCount: 0,
      childCount: 0,
      hasNote: note.hasContent,
      orderingMode: nil
    )

    return BlockNodeSnapshot(
      id: node.id,
      parentNodeID: node.parentID,
      kind: BlockKind(workspaceNodeKind: node.kind),
      isRoot: false,
      colorHex: node.colorHex,
      iconName: node.iconName,
      header: header,
      body: body,
      children: []
    )
  }

  private static func makeTaskBlock(
    taskRow: TaskRowSnapshot,
    parentNodeID: UUID,
    attachmentSummary: AttachmentSummarySnapshot?,
    children: [BlockNodeSnapshot],
    orderingMode: BlockChildOrderingMode
  ) -> BlockNodeSnapshot {
    let note = BlockNoteSnapshot(
      reminderText: taskRow.reminderNoteText,
      markdown: ""
    )
    let schedule = BlockScheduleSummary(
      displayedDate: taskRow.displayedDate,
      startDate: taskRow.startDate,
      dueDate: taskRow.dueDate,
      hasExplicitTime: taskRow.scheduleHasExplicitTime,
      scheduledDurationMinutes: taskRow.scheduledDurationMinutes
    )
    let body = BlockBodySnapshot(
      metaStrip: BlockMetaStripSnapshot(
        schedule: schedule,
        requiredWorkDays: taskRow.requiredWorkDays > 0 ? taskRow.requiredWorkDays : nil,
        completedWorkUnits: taskRow.requiredWorkDays > 0 ? taskRow.completedWorkUnits : nil
      ),
      note: note,
      attachments: attachmentSummary?.previews.map(makeAttachmentPreview) ?? []
    )
    let attachmentCount = attachmentSummary?.totalCount ?? taskRow.attachmentCount
    let header = BlockHeaderSnapshot(
      title: normalizedTitle(taskRow.title),
      isCompleted: taskRow.isCompleted,
      schedule: schedule,
      attachmentCount: attachmentCount,
      childCount: children.count,
      hasNote: note.hasContent,
      orderingMode: children.isEmpty ? nil : orderingMode
    )

    return BlockNodeSnapshot(
      id: taskRow.id,
      parentNodeID: parentNodeID,
      kind: .task,
      isRoot: false,
      colorHex: nil,
      iconName: nil,
      header: header,
      body: body,
      children: children
    )
  }

  private static func makeBulletBlock(
    node: ProjectDetailRootStructureNodeSnapshot,
    children: [BlockNodeSnapshot]
  ) -> BlockNodeSnapshot {
    let note = BlockNoteSnapshot.empty
    let body = BlockBodySnapshot(
      metaStrip: BlockMetaStripSnapshot(
        schedule: .empty,
        requiredWorkDays: nil,
        completedWorkUnits: nil
      ),
      note: note,
      attachments: []
    )
    let header = BlockHeaderSnapshot(
      title: normalizedTitle(node.title),
      isCompleted: false,
      schedule: .empty,
      attachmentCount: 0,
      childCount: children.count,
      hasNote: false,
      orderingMode: children.isEmpty ? nil : .manual
    )

    return BlockNodeSnapshot(
      id: node.id,
      parentNodeID: node.parentNodeID,
      kind: .bullet,
      isRoot: false,
      colorHex: nil,
      iconName: nil,
      header: header,
      body: body,
      children: children
    )
  }

  private static func makeRootBlocks(
    from detailSnapshot: ProjectDetailSnapshot,
    attachmentSummariesByOwnerID: [UUID: AttachmentSummarySnapshot],
    orderingMode: BlockChildOrderingMode
  ) -> [BlockNodeSnapshot] {
    guard detailSnapshot.rootStructureNodes.isEmpty == false else {
      return makeTaskBlocks(
        from: detailSnapshot.taskRows,
        rootParentNodeID: detailSnapshot.node.id,
        attachmentSummariesByOwnerID: attachmentSummariesByOwnerID,
        orderingMode: orderingMode
      )
    }

    let taskRowsByID = Dictionary(uniqueKeysWithValues: detailSnapshot.taskRows.map { ($0.id, $0) })
    let rowsByParentID = Dictionary(grouping: detailSnapshot.taskRows, by: \.parentTaskID)

    func buildTaskBlock(from row: TaskRowSnapshot, parentNodeID: UUID) -> BlockNodeSnapshot {
      let childBlocks = orderedTaskRows(
        rowsByParentID[row.id] ?? [],
        orderingMode: orderingMode
      ).map { childRow in
        buildTaskBlock(from: childRow, parentNodeID: row.id)
      }

      return makeTaskBlock(
        taskRow: row,
        parentNodeID: parentNodeID,
        attachmentSummary: attachmentSummariesByOwnerID[row.id],
        children: childBlocks,
        orderingMode: orderingMode
      )
    }

    func buildStructureNode(
      _ node: ProjectDetailRootStructureNodeSnapshot
    ) -> BlockNodeSnapshot? {
      switch node.kind {
      case .bullet:
        let childBlocks = node.children.compactMap(buildStructureNode)
        return makeBulletBlock(node: node, children: childBlocks)
      case .task, .mirror:
        guard let taskID = node.taskID, let row = taskRowsByID[taskID] else {
          return nil
        }
        return buildTaskBlock(from: row, parentNodeID: node.parentNodeID ?? detailSnapshot.node.id)
      }
    }

    return detailSnapshot.rootStructureNodes.compactMap(buildStructureNode)
  }

  private static func makeTaskBlocks(
    from taskRows: [TaskRowSnapshot],
    rootParentNodeID: UUID,
    attachmentSummariesByOwnerID: [UUID: AttachmentSummarySnapshot],
    orderingMode: BlockChildOrderingMode
  ) -> [BlockNodeSnapshot] {
    let rowsByParentID = Dictionary(grouping: taskRows, by: \.parentTaskID)
    let rowIDs = Set(taskRows.map(\.id))

    func buildBlock(from row: TaskRowSnapshot, parentNodeID: UUID) -> BlockNodeSnapshot {
      let childBlocks = orderedTaskRows(
        rowsByParentID[row.id] ?? [],
        orderingMode: orderingMode
      ).map { childRow in
        buildBlock(from: childRow, parentNodeID: row.id)
      }

      return makeTaskBlock(
        taskRow: row,
        parentNodeID: parentNodeID,
        attachmentSummary: attachmentSummariesByOwnerID[row.id],
        children: childBlocks,
        orderingMode: orderingMode
      )
    }

    let rootRows = taskRows.filter { row in
      guard let parentTaskID = row.parentTaskID else { return true }
      return !rowIDs.contains(parentTaskID)
    }
    return orderedTaskRows(rootRows, orderingMode: orderingMode).map { row in
      buildBlock(from: row, parentNodeID: rootParentNodeID)
    }
  }

  private static func orderedTaskRows(
    _ rows: [TaskRowSnapshot],
    orderingMode: BlockChildOrderingMode
  ) -> [TaskRowSnapshot] {
    switch orderingMode {
    case .manual:
      return rows.sorted(by: taskRowOrderComparator)
    case .dateAscending:
      return rows.sorted { lhs, rhs in
        compareTaskRows(lhs, rhs, ascending: true)
      }
    case .dateDescending:
      return rows.sorted { lhs, rhs in
        compareTaskRows(lhs, rhs, ascending: false)
      }
    }
  }

  private static func compareTaskRows(
    _ lhs: TaskRowSnapshot,
    _ rhs: TaskRowSnapshot,
    ascending: Bool
  ) -> Bool {
    let left = lhs.reminderDate
    let right = rhs.reminderDate

    switch (left, right) {
    case (let left?, let right?):
      if left == right {
        return taskRowOrderComparator(lhs, rhs)
      }
      return ascending ? (left < right) : (left > right)
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    case (nil, nil):
      return taskRowOrderComparator(lhs, rhs)
    }
  }

  private static func taskRowOrderComparator(
    _ lhs: TaskRowSnapshot,
    _ rhs: TaskRowSnapshot
  ) -> Bool {
    if lhs.rowOrder == rhs.rowOrder {
      if lhs.createdAt == rhs.createdAt {
        return lhs.id.uuidString < rhs.id.uuidString
      }
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.rowOrder < rhs.rowOrder
  }

  private static func makeAttachmentPreview(
    from preview: AttachmentReferencePreviewSnapshot
  ) -> BlockAttachmentPreviewSnapshot {
    BlockAttachmentPreviewSnapshot(
      id: preview.id,
      originalFilename: preview.originalFilename,
      mimeType: preview.mimeType,
      byteSize: preview.byteSize,
      updatedAt: preview.updatedAt
    )
  }

  private static func normalizedTitle(_ title: String) -> String {
    normalizedOptionalString(title) ?? "제목 없음"
  }

  private static func normalizedOptionalString(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}
