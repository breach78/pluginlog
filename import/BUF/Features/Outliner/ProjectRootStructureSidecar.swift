import Foundation

enum ReminderProjectRootNodeRecord: Codable, Equatable {
  case task(reminderExternalIdentifier: String, indent: Int)
  case mirror(reminderExternalIdentifier: String, indent: Int)
  case bullet(id: UUID, text: String, indent: Int)

  private enum CodingKeys: String, CodingKey {
    case kind
    case reminderExternalIdentifier
    case indent
    case id
    case text
  }

  private enum Kind: String, Codable {
    case task
    case mirror
    case bullet
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .kind)
    let indent = try container.decodeIfPresent(Int.self, forKey: .indent) ?? 0

    switch kind {
    case .task:
      self = .task(
        reminderExternalIdentifier: try container.decode(
          String.self,
          forKey: .reminderExternalIdentifier
        ),
        indent: indent
      )
    case .mirror:
      self = .mirror(
        reminderExternalIdentifier: try container.decode(
          String.self,
          forKey: .reminderExternalIdentifier
        ),
        indent: indent
      )
    case .bullet:
      self = .bullet(
        id: try container.decode(UUID.self, forKey: .id),
        text: try container.decode(String.self, forKey: .text),
        indent: indent
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(indent, forKey: .indent)

    switch self {
    case .task(let reminderExternalIdentifier, _):
      try container.encode(Kind.task, forKey: .kind)
      try container.encode(reminderExternalIdentifier, forKey: .reminderExternalIdentifier)
    case .mirror(let reminderExternalIdentifier, _):
      try container.encode(Kind.mirror, forKey: .kind)
      try container.encode(reminderExternalIdentifier, forKey: .reminderExternalIdentifier)
    case .bullet(let id, let text, _):
      try container.encode(Kind.bullet, forKey: .kind)
      try container.encode(id, forKey: .id)
      try container.encode(text, forKey: .text)
    }
  }

  var indent: Int {
    switch self {
    case .task(_, let indent), .mirror(_, let indent), .bullet(_, _, let indent):
      return indent
    }
  }

  func withIndent(_ indent: Int) -> ReminderProjectRootNodeRecord {
    switch self {
    case .task(let reminderExternalIdentifier, _):
      return .task(reminderExternalIdentifier: reminderExternalIdentifier, indent: indent)
    case .mirror(let reminderExternalIdentifier, _):
      return .mirror(reminderExternalIdentifier: reminderExternalIdentifier, indent: indent)
    case .bullet(let id, let text, _):
      return .bullet(id: id, text: text, indent: indent)
    }
  }
}

struct ReminderProjectRootStructureRecord: Codable, Equatable {
  var reminderListExternalIdentifier: String
  var rootNodes: [ReminderProjectRootNodeRecord]
  var createdAt: Date
  var updatedAt: Date
}

enum ReminderProjectRootStructureMutationService {
  static func insertingMirror(
    reminderExternalIdentifier: String,
    into rootNodes: [ReminderProjectRootNodeRecord],
    parentRootBulletID: UUID?,
    insertionSlot: Int?
  ) -> [ReminderProjectRootNodeRecord]? {
    insertingRecord(
      .mirror(reminderExternalIdentifier: reminderExternalIdentifier, indent: 0),
      into: rootNodes,
      parentRootBulletID: parentRootBulletID,
      insertionSlot: insertionSlot
    )
  }

  static func record(
    reminderListExternalIdentifier: String,
    rootNodes: [ReminderProjectRootNodeRecord],
    existing: ReminderProjectRootStructureRecord?,
    now: Date = .now
  ) -> ReminderProjectRootStructureRecord {
    ReminderProjectRootStructureRecord(
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      rootNodes: rootNodes,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now
    )
  }

  static func insertingTask(
    reminderExternalIdentifier: String,
    into rootNodes: [ReminderProjectRootNodeRecord],
    parentRootBulletID: UUID?,
    insertionSlot: Int?
  ) -> [ReminderProjectRootNodeRecord]? {
    insertingRecord(
      .task(reminderExternalIdentifier: reminderExternalIdentifier, indent: 0),
      into: rootNodes,
      parentRootBulletID: parentRootBulletID,
      insertionSlot: insertionSlot
    )
  }

  static func insertingRecord(
    _ record: ReminderProjectRootNodeRecord,
    into rootNodes: [ReminderProjectRootNodeRecord],
    parentRootBulletID: UUID?,
    insertionSlot: Int?
  ) -> [ReminderProjectRootNodeRecord]? {
    let normalizedRootNodes = ReminderProjectRootStructureCodec.normalizedRecords(from: rootNodes)
    let container = insertionContainer(
      in: normalizedRootNodes,
      parentRootBulletID: parentRootBulletID
    )
    guard let container,
      let normalizedRecord = normalizedRecord(record, indent: container.childIndent)
    else {
      return nil
    }

    let directChildStarts = directChildStartIndexes(
      in: normalizedRootNodes,
      container: container
    )
    let requestedSlot = insertionSlot ?? directChildStarts.count
    let normalizedSlot = min(max(0, requestedSlot), directChildStarts.count)
    let insertionIndex =
      normalizedSlot < directChildStarts.count
      ? directChildStarts[normalizedSlot]
      : container.endIndex

    var updatedRootNodes = normalizedRootNodes
    updatedRootNodes.insert(normalizedRecord, at: insertionIndex)
    return ReminderProjectRootStructureCodec.normalizedRecords(from: updatedRootNodes)
  }

  static func reorderedRootTaskRecords(
    in rootNodes: [ReminderProjectRootNodeRecord],
    orderedReminderExternalIdentifiers: [String]
  ) -> [ReminderProjectRootNodeRecord]? {
    let normalizedRootNodes = ReminderProjectRootStructureCodec.normalizedRecords(from: rootNodes)
    let rootTaskRecords = normalizedRootNodes.compactMap { record -> ReminderProjectRootNodeRecord? in
      guard case .task(_, let indent) = record, indent == 0 else { return nil }
      return record
    }
    guard !rootTaskRecords.isEmpty else { return nil }

    let rootTaskReminderExternalIdentifiers = rootTaskRecords.compactMap { record -> String? in
      guard case let .task(reminderExternalIdentifier, _) = record else { return nil }
      return ReminderProjectionIdentity.normalized(reminderExternalIdentifier)
    }
    let rootTaskIdentifierSet = Set(rootTaskReminderExternalIdentifiers)
    let filteredOrderedReminderExternalIdentifiers = orderedReminderExternalIdentifiers.compactMap {
      ReminderProjectionIdentity.normalized($0)
    }
    .filter { rootTaskIdentifierSet.contains($0) }
    guard !filteredOrderedReminderExternalIdentifiers.isEmpty else { return nil }

    let visibleIdentifierSet = Set(filteredOrderedReminderExternalIdentifiers)
    var visibleIterator = filteredOrderedReminderExternalIdentifiers.makeIterator()
    let reorderedReminderExternalIdentifiers = rootTaskReminderExternalIdentifiers.map {
      visibleIdentifierSet.contains($0) ? (visibleIterator.next() ?? $0) : $0
    }

    let recordsByReminderExternalIdentifier = Dictionary(
      uniqueKeysWithValues: rootTaskRecords.compactMap { record -> (String, ReminderProjectRootNodeRecord)? in
        guard case let .task(reminderExternalIdentifier, _) = record,
          let normalizedReminderExternalIdentifier = ReminderProjectionIdentity.normalized(
            reminderExternalIdentifier)
        else {
          return nil
        }
        return (normalizedReminderExternalIdentifier, record)
      }
    )

    var reorderedRecords = reorderedReminderExternalIdentifiers.compactMap {
      recordsByReminderExternalIdentifier[$0]
    }
    guard reorderedRecords.count == rootTaskRecords.count else { return nil }

    var updatedRootNodes: [ReminderProjectRootNodeRecord] = []
    updatedRootNodes.reserveCapacity(normalizedRootNodes.count)
    for record in normalizedRootNodes {
      if case .task(_, let indent) = record, indent == 0 {
        updatedRootNodes.append(reorderedRecords.removeFirst())
      } else {
        updatedRootNodes.append(record)
      }
    }

    return ReminderProjectRootStructureCodec.normalizedRecords(from: updatedRootNodes)
  }

  private struct InsertionContainer {
    let startIndex: Int
    let endIndex: Int
    let childIndent: Int
  }

  private static func normalizedRecord(
    _ record: ReminderProjectRootNodeRecord,
    indent: Int
  ) -> ReminderProjectRootNodeRecord? {
    switch record {
    case let .task(reminderExternalIdentifier, _):
      guard
        let normalizedReminderExternalIdentifier = ReminderProjectionIdentity.normalized(
          reminderExternalIdentifier)
      else {
        return nil
      }
      return .task(
        reminderExternalIdentifier: normalizedReminderExternalIdentifier,
        indent: indent
      )

    case let .mirror(reminderExternalIdentifier, _):
      guard
        let normalizedReminderExternalIdentifier = ReminderProjectionIdentity.normalized(
          reminderExternalIdentifier)
      else {
        return nil
      }
      return .mirror(
        reminderExternalIdentifier: normalizedReminderExternalIdentifier,
        indent: indent
      )

    case let .bullet(id, text, _):
      return .bullet(id: id, text: text, indent: indent)
    }
  }

  private static func insertionContainer(
    in rootNodes: [ReminderProjectRootNodeRecord],
    parentRootBulletID: UUID?
  ) -> InsertionContainer? {
    guard let parentRootBulletID else {
      return InsertionContainer(
        startIndex: 0,
        endIndex: rootNodes.count,
        childIndent: 0
      )
    }

    guard
      let bulletIndex = rootNodes.firstIndex(where: { record in
        guard case let .bullet(id, _, _) = record else { return false }
        return id == parentRootBulletID
      })
    else {
      return nil
    }

    let bulletIndent = rootNodes[bulletIndex].indent
    let endIndex =
      rootNodes[(bulletIndex + 1)...].firstIndex(where: { $0.indent <= bulletIndent })
      ?? rootNodes.count
    return InsertionContainer(
      startIndex: bulletIndex + 1,
      endIndex: endIndex,
      childIndent: bulletIndent + 1
    )
  }

  private static func directChildStartIndexes(
    in rootNodes: [ReminderProjectRootNodeRecord],
    container: InsertionContainer
  ) -> [Int] {
    guard container.startIndex < container.endIndex else { return [] }
    return Array(container.startIndex..<container.endIndex).filter { index in
      rootNodes[index].indent == container.childIndent
    }
  }
}

enum ReminderProjectRootStructureCodec {
  static let rootBulletParentPrefix = "root-bullet:"

  private enum ExistingNodeKey: Hashable {
    case task(String)
    case mirror(String)
    case bullet(UUID)
  }

  struct Materialization {
    var rootNodes: [OutlineNode]
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata]
    var consumedBaseReminderExternalIdentifiers: Set<String>
    var consumedMirrorReminderExternalIdentifiers: Set<String>
  }

  private struct MaterializedEntry {
    var indent: Int
    var node: OutlineNode
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata]
    var consumedBaseReminderExternalIdentifiers: Set<String>
    var consumedMirrorReminderExternalIdentifiers: Set<String>

    var canHostChildren: Bool {
      switch node.type {
      case .bullet, .reference:
        return true
      case .task:
        return false
      }
    }
  }

  private struct BuildResult {
    var nodes: [OutlineNode]
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata]
    var consumedBaseReminderExternalIdentifiers: Set<String>
    var consumedMirrorReminderExternalIdentifiers: Set<String>
  }

  static func rootBulletParentIdentifier(for bulletID: UUID) -> String {
    "\(rootBulletParentPrefix)\(bulletID.uuidString.lowercased())"
  }

  static func rootNodes(from nodes: [OutlineNode]) -> [ReminderProjectRootNodeRecord] {
    flattenedRecords(from: nodes, indent: 0)
  }

  static func normalizedRecords(
    from records: [ReminderProjectRootNodeRecord]
  ) -> [ReminderProjectRootNodeRecord] {
    normalized(records)
  }

  static func materialize(
    record: ReminderProjectRootStructureRecord,
    projectSnapshot: ReminderMetadataSnapshotEngine.ProjectSnapshot,
    globalTasksByExternalIdentifier: [String: ReminderMetadataSnapshotEngine.TaskSnapshot],
    mirrorRootsByReminderExternalIdentifier: [String: ReminderMetadataSnapshotEngine.MirrorRootSnapshot],
    taskFeatureSidecarsByReminderExternalIdentifier:
      [String: ReminderTaskFeatureSidecarRecord]
  ) -> Materialization {
    let normalizedRecords = normalized(record.rootNodes)
    let entries = normalizedRecords.compactMap { record -> MaterializedEntry? in
      switch record {
      case .task(let reminderExternalIdentifier, let indent):
        guard let task = projectSnapshot.tasksByExternalIdentifier[reminderExternalIdentifier] else {
          return nil
        }
        let tree = ReminderNoteSourceLoader.loadTaskTree(
          from: task,
          tasksByExternalIdentifier: projectSnapshot.tasksByExternalIdentifier,
          taskFeatureSidecarsByReminderExternalIdentifier:
            taskFeatureSidecarsByReminderExternalIdentifier
        )
        return MaterializedEntry(
          indent: indent,
          node: tree.root,
          reminderMetadataByNodeID: tree.reminderMetadataByNodeID,
          featureSidecarByNodeID: tree.featureSidecarByNodeID,
          consumedBaseReminderExternalIdentifiers: [reminderExternalIdentifier],
          consumedMirrorReminderExternalIdentifiers: []
        )

      case .mirror(let reminderExternalIdentifier, let indent):
        guard
          let mirrorRoot = mirrorRootsByReminderExternalIdentifier[reminderExternalIdentifier],
          globalTasksByExternalIdentifier[reminderExternalIdentifier] != nil
        else {
          return nil
        }
        let tree = ReminderNoteSourceLoader.loadTaskTree(
          from: mirrorRoot.task,
          tasksByExternalIdentifier: globalTasksByExternalIdentifier,
          taskFeatureSidecarsByReminderExternalIdentifier:
            taskFeatureSidecarsByReminderExternalIdentifier
        )
        let mirroredTree = OutlineProjectionRuntimeSnapshot.mirroredTaskTree(
          from: tree,
          placement: mirrorRoot.placement,
          sourceProjectID: mirrorRoot.sourceProjectID
        )
        return MaterializedEntry(
          indent: indent,
          node: mirroredTree.root,
          reminderMetadataByNodeID: mirroredTree.reminderMetadataByNodeID,
          featureSidecarByNodeID: mirroredTree.featureSidecarByNodeID,
          consumedBaseReminderExternalIdentifiers: [],
          consumedMirrorReminderExternalIdentifiers: [reminderExternalIdentifier]
        )

      case .bullet(let id, let text, let indent):
        return MaterializedEntry(
          indent: indent,
          node: OutlineNode(
            id: id,
            canonicalID: id,
            text: text,
            type: .bullet
          ),
          reminderMetadataByNodeID: [:],
          featureSidecarByNodeID: [:],
          consumedBaseReminderExternalIdentifiers: [],
          consumedMirrorReminderExternalIdentifiers: []
        )
      }
    }

    var cursor = 0
    let buildResult = build(entries, cursor: &cursor, depth: 0)
    return Materialization(
      rootNodes: buildResult.nodes,
      reminderMetadataByNodeID: buildResult.reminderMetadataByNodeID,
      featureSidecarByNodeID: buildResult.featureSidecarByNodeID,
      consumedBaseReminderExternalIdentifiers: buildResult.consumedBaseReminderExternalIdentifiers,
      consumedMirrorReminderExternalIdentifiers:
        buildResult.consumedMirrorReminderExternalIdentifiers
    )
  }

  static func rebuildRootNodes(
    from record: ReminderProjectRootStructureRecord,
    existingNodes: [OutlineNode]
  ) -> [OutlineNode] {
    let normalizedRecords = normalized(record.rootNodes)
    let existingNodesByKey = existingNodesByKey(from: existingNodes)
    var consumedKeys: Set<ExistingNodeKey> = []
    let entries = normalizedRecords.compactMap { record -> MaterializedEntry? in
      switch record {
      case .task(let reminderExternalIdentifier, let indent):
        let key = ExistingNodeKey.task(reminderExternalIdentifier)
        guard let node = existingNodesByKey[key] else { return nil }
        consumedKeys.insert(key)
        return MaterializedEntry(
          indent: indent,
          node: skeletonNode(from: node),
          reminderMetadataByNodeID: [:],
          featureSidecarByNodeID: [:],
          consumedBaseReminderExternalIdentifiers: [],
          consumedMirrorReminderExternalIdentifiers: []
        )

      case .mirror(let reminderExternalIdentifier, let indent):
        let key = ExistingNodeKey.mirror(reminderExternalIdentifier)
        guard let node = existingNodesByKey[key] else { return nil }
        consumedKeys.insert(key)
        return MaterializedEntry(
          indent: indent,
          node: skeletonNode(from: node),
          reminderMetadataByNodeID: [:],
          featureSidecarByNodeID: [:],
          consumedBaseReminderExternalIdentifiers: [],
          consumedMirrorReminderExternalIdentifiers: []
        )

      case .bullet(let id, let text, let indent):
        let key = ExistingNodeKey.bullet(id)
        let node =
          existingNodesByKey[key].map { bulletNode in
            skeletonNode(from: bulletNode, fallbackText: text)
          }
          ?? OutlineNode(
            id: id,
            canonicalID: id,
            text: text,
            type: .bullet
          )
        consumedKeys.insert(key)
        return MaterializedEntry(
          indent: indent,
          node: node,
          reminderMetadataByNodeID: [:],
          featureSidecarByNodeID: [:],
          consumedBaseReminderExternalIdentifiers: [],
          consumedMirrorReminderExternalIdentifiers: []
        )
      }
    }

    var cursor = 0
    let buildResult = build(entries, cursor: &cursor, depth: 0)
    let trailingRootNodes = existingNodes.filter { node in
      guard let key = existingNodeKey(for: node) else { return true }
      return consumedKeys.contains(key) == false
    }
    return buildResult.nodes + trailingRootNodes
  }

  private static func flattenedRecords(
    from nodes: [OutlineNode],
    indent: Int
  ) -> [ReminderProjectRootNodeRecord] {
    nodes.flatMap { node in
      if node.type.isTask {
        guard
          let reminderExternalIdentifier = ReminderProjectionIdentity.normalized(
            node.reminderExternalIdentifier)
        else {
          return [ReminderProjectRootNodeRecord]()
        }
        let record: ReminderProjectRootNodeRecord =
          if node.referenceProjectID != nil || node.isCloneInstance {
            .mirror(reminderExternalIdentifier: reminderExternalIdentifier, indent: indent)
          } else {
            .task(reminderExternalIdentifier: reminderExternalIdentifier, indent: indent)
          }
        return [record]
      }

      let bulletRecord = ReminderProjectRootNodeRecord.bullet(
        id: node.id,
        text: node.text,
        indent: indent
      )
      return [bulletRecord] + flattenedRecords(from: node.children, indent: indent + 1)
    }
  }

  private static func existingNodesByKey(
    from rootNodes: [OutlineNode]
  ) -> [ExistingNodeKey: OutlineNode] {
    var nodesByKey: [ExistingNodeKey: OutlineNode] = [:]
    for entry in OutlineDocument(rootNodes: rootNodes).flatten() {
      guard let key = existingNodeKey(for: entry.node) else { continue }
      nodesByKey[key] = entry.node
    }
    return nodesByKey
  }

  private static func existingNodeKey(for node: OutlineNode) -> ExistingNodeKey? {
    if node.type.isTask {
      guard
        let reminderExternalIdentifier = ReminderProjectionIdentity.normalized(
          node.reminderExternalIdentifier)
      else {
        return nil
      }
      return node.referenceProjectID != nil || node.isCloneInstance
        ? .mirror(reminderExternalIdentifier)
        : .task(reminderExternalIdentifier)
    }

    return node.type == .bullet ? .bullet(node.id) : nil
  }

  private static func skeletonNode(
    from node: OutlineNode,
    fallbackText: String? = nil
  ) -> OutlineNode {
    var skeleton = node
    skeleton.children = []
    if let fallbackText, skeleton.type == .bullet {
      skeleton.text = fallbackText
    }
    return skeleton
  }

  private static func normalized(
    _ records: [ReminderProjectRootNodeRecord]
  ) -> [ReminderProjectRootNodeRecord] {
    var normalized: [ReminderProjectRootNodeRecord] = []
    var bulletPathDepths: [Int] = []

    for record in records {
      let maxAllowedIndent = bulletPathDepths.count
      let normalizedIndent = min(max(0, record.indent), maxAllowedIndent)
      let normalizedRecord = record.withIndent(normalizedIndent)
      normalized.append(normalizedRecord)

      bulletPathDepths = bulletPathDepths.filter { $0 < normalizedIndent }
      if case .bullet(_, _, _) = normalizedRecord {
        bulletPathDepths.append(normalizedIndent)
      }
    }

    return normalized
  }

  private static func build(
    _ entries: [MaterializedEntry],
    cursor: inout Int,
    depth: Int
  ) -> BuildResult {
    var nodes: [OutlineNode] = []
    var reminderMetadataByNodeID: [UUID: ReminderMetadataSnapshot] = [:]
    var featureSidecarByNodeID: [UUID: OutlinerTaskSidecarMetadata] = [:]
    var consumedBaseReminderExternalIdentifiers: Set<String> = []
    var consumedMirrorReminderExternalIdentifiers: Set<String> = []

    while cursor < entries.count {
      let entry = entries[cursor]
      if entry.indent < depth {
        break
      }
      guard entry.indent == depth else {
        cursor += 1
        continue
      }

      cursor += 1
      var node = entry.node
      reminderMetadataByNodeID.merge(
        entry.reminderMetadataByNodeID,
        uniquingKeysWith: { _, rhs in rhs }
      )
      featureSidecarByNodeID.merge(
        entry.featureSidecarByNodeID,
        uniquingKeysWith: { _, rhs in rhs }
      )
      consumedBaseReminderExternalIdentifiers.formUnion(
        entry.consumedBaseReminderExternalIdentifiers
      )
      consumedMirrorReminderExternalIdentifiers.formUnion(
        entry.consumedMirrorReminderExternalIdentifiers
      )

      if entry.canHostChildren {
        let childResult = build(entries, cursor: &cursor, depth: depth + 1)
        node.children = childResult.nodes
        reminderMetadataByNodeID.merge(
          childResult.reminderMetadataByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        featureSidecarByNodeID.merge(
          childResult.featureSidecarByNodeID,
          uniquingKeysWith: { _, rhs in rhs }
        )
        consumedBaseReminderExternalIdentifiers.formUnion(
          childResult.consumedBaseReminderExternalIdentifiers
        )
        consumedMirrorReminderExternalIdentifiers.formUnion(
          childResult.consumedMirrorReminderExternalIdentifiers
        )
      }

      nodes.append(node)
    }

    return BuildResult(
      nodes: nodes,
      reminderMetadataByNodeID: reminderMetadataByNodeID,
      featureSidecarByNodeID: featureSidecarByNodeID,
      consumedBaseReminderExternalIdentifiers: consumedBaseReminderExternalIdentifiers,
      consumedMirrorReminderExternalIdentifiers: consumedMirrorReminderExternalIdentifiers
    )
  }
}
