import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import CoreGraphics
import AppKit

// MARK: - Node-Based Outline Model

enum OutlineNodeType: Equatable, Codable {
  case bullet
  case task(completed: Bool)
  case reference(targetID: UUID)

  var isTask: Bool {
    switch self {
    case .bullet, .reference: false
    case .task: true
    }
  }

  var isCompleted: Bool {
    switch self {
    case .bullet, .reference: false
    case .task(let completed): completed
    }
  }

  var isReference: Bool {
    switch self {
    case .reference: true
    default: false
    }
  }

  var referenceTargetID: UUID? {
    switch self {
    case .reference(let targetID): targetID
    default: nil
    }
  }
}

struct OutlineNodeAttachment: Identifiable, Equatable, Codable {
  let id: UUID
  let fileName: String
  let filePath: String
  let mimeType: String

  init(id: UUID = UUID(), fileName: String, filePath: String, mimeType: String) {
    self.id = id
    self.fileName = fileName
    self.filePath = filePath
    self.mimeType = mimeType
  }

  static func detectMIMEType(for url: URL) -> String {
    if let utType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
      return utType.preferredMIMEType ?? "application/octet-stream"
    }
    return "application/octet-stream"
  }
}

struct OutlineNode: Identifiable, Equatable {
  let id: UUID
  var canonicalID: UUID
  var text: String
  var type: OutlineNodeType
  var referenceProjectID: UUID?
  var children: [OutlineNode]
  var isCollapsed: Bool

  var migratedTaskItemID: String?
  var reminderIdentifier: String?
  var reminderExternalIdentifier: String?
  var attachments: [OutlineNodeAttachment]

  init(
    id: UUID = UUID(),
    canonicalID: UUID? = nil,
    text: String,
    type: OutlineNodeType = .bullet,
    referenceProjectID: UUID? = nil,
    children: [OutlineNode] = [],
    isCollapsed: Bool = false,
    migratedTaskItemID: String? = nil,
    reminderIdentifier: String? = nil,
    reminderExternalIdentifier: String? = nil,
    attachments: [OutlineNodeAttachment] = []
  ) {
    self.id = id
    self.canonicalID = canonicalID ?? id
    self.text = text
    self.type = type
    self.referenceProjectID = referenceProjectID
    self.children = children
    self.isCollapsed = isCollapsed
    self.migratedTaskItemID = migratedTaskItemID
    self.reminderIdentifier = reminderIdentifier
    self.reminderExternalIdentifier = reminderExternalIdentifier
    self.attachments = attachments
  }
}

struct OutlineDocument: Equatable {
  var rootNodes: [OutlineNode]

  init(rootNodes: [OutlineNode] = []) {
    self.rootNodes = rootNodes
  }

  /// 텍스트에서 ((UUID)), ((projectID:blockID)), [alias](((...))) 형식을 감지한다.
  static func parseBlockReference(_ text: String) -> OutlineParsedBlockReference? {
    OutlineBlockReferenceCodec.parse(text)
  }

  static func blockReferenceSearchQuery(_ text: String) -> String? {
    OutlineBlockReferenceCodec.searchQuery(from: text)
  }

  func applyingTextOverlay(_ overlay: [UUID: String]) -> OutlineDocument {
    guard !overlay.isEmpty else { return self }

    var updated = self
    for (nodeID, text) in overlay {
      updated.updateNode(id: nodeID) { node in
        node.text = text
      }
    }
    return updated
  }

  func flatten() -> [OutlineFlattenedEntry] {
    var result: [OutlineFlattenedEntry] = []
    flattenNodes(rootNodes, depth: 0, into: &result)
    return result
  }

  private func flattenNodes(
    _ nodes: [OutlineNode],
    depth: Int,
    into result: inout [OutlineFlattenedEntry]
  ) {
    for node in nodes {
      result.append(
        OutlineFlattenedEntry(
          id: node.id,
          depth: depth,
          node: node,
          hasChildren: !node.children.isEmpty,
          isCollapsed: node.isCollapsed
        )
      )
      if !node.isCollapsed {
        flattenNodes(node.children, depth: depth + 1, into: &result)
      }
    }
  }
}

struct OutlineFlattenedEntry: Identifiable {
  let id: UUID
  let depth: Int
  let node: OutlineNode
  let hasChildren: Bool
  let isCollapsed: Bool
}

struct OutlineTreeIndex: Equatable {
  let nodesByID: [UUID: OutlineNode]
  let parentByNodeID: [UUID: UUID]
  let nodeIDsByCanonicalID: [UUID: [UUID]]
  let canonicalInstanceCounts: [UUID: Int]

  init(document: OutlineDocument) {
    var nodesByID: [UUID: OutlineNode] = [:]
    var parentByNodeID: [UUID: UUID] = [:]
    var nodeIDsByCanonicalID: [UUID: [UUID]] = [:]
    var canonicalInstanceCounts: [UUID: Int] = [:]

    func walk(_ nodes: [OutlineNode], parentID: UUID?) {
      for node in nodes {
        nodesByID[node.id] = node
        if let parentID {
          parentByNodeID[node.id] = parentID
        }
        nodeIDsByCanonicalID[node.canonicalID, default: []].append(node.id)
        canonicalInstanceCounts[node.canonicalID, default: 0] += 1
        walk(node.children, parentID: node.id)
      }
    }

    walk(document.rootNodes, parentID: nil)
    self.nodesByID = nodesByID
    self.parentByNodeID = parentByNodeID
    self.nodeIDsByCanonicalID = nodeIDsByCanonicalID
    self.canonicalInstanceCounts = canonicalInstanceCounts
  }

  func findNode(id: UUID) -> OutlineNode? {
    nodesByID[id]
  }

  func parentOf(id: UUID) -> UUID? {
    parentByNodeID[id]
  }

  func taskNode(contentID: UUID) -> OutlineNode? {
    nodeIDsByCanonicalID[contentID]?.lazy
      .compactMap { nodesByID[$0] }
      .first { $0.type.isTask }
  }

  func isCloned(canonicalID: UUID) -> Bool {
    (canonicalInstanceCounts[canonicalID] ?? 0) > 1
  }

  static func buildCanonicalInstanceCounts(for projects: [OutlinerProject]) -> [UUID: Int] {
    var counts: [UUID: Int] = [:]
    for project in projects {
      for (canonicalID, count) in OutlineTreeIndex(document: project.document).canonicalInstanceCounts {
        counts[canonicalID, default: 0] += count
      }
    }
    return counts
  }
}

enum OutlineFlattenedEntryFilter {
  static func hidingCompletedSubtrees(
    in entries: [OutlineFlattenedEntry],
    preservingCompletedNodeIDs: Set<UUID> = []
  ) -> [OutlineFlattenedEntry] {
    var filtered: [OutlineFlattenedEntry] = []
    var hiddenCompletedDepth: Int?

    for entry in entries {
      if let activeHiddenCompletedDepth = hiddenCompletedDepth {
        if entry.depth > activeHiddenCompletedDepth {
          continue
        }
        hiddenCompletedDepth = nil
      }

      if entry.node.type.isCompleted {
        if preservingCompletedNodeIDs.contains(entry.id)
          || preservingCompletedNodeIDs.contains(entry.node.canonicalID)
        {
          filtered.append(entry)
          continue
        }
        hiddenCompletedDepth = entry.depth
        continue
      }

      filtered.append(entry)
    }

    return filtered
  }
}

extension OutlineNode {
  func toOutlinerLine(flattenedIndex: Int, depth: Int) -> OutlinerLine {
    let marker: OutlinerLineMarker = switch type {
    case .bullet: .bullet
    case .task(completed: false): .todo
    case .task(completed: true): .done
    case .reference: .bullet
    }
    let rawBody = String(repeating: "\t", count: depth) + marker.visiblePrefix + text
    return OutlinerLine(
      index: flattenedIndex,
      range: NSRange(location: 0, length: (rawBody as NSString).length),
      rawBody: rawBody,
      indentDepth: depth,
      marker: marker
    )
  }
}

extension OutlineNode {
  var isCloneInstance: Bool {
    canonicalID != id
  }
}

extension OutlineDocument {
  static func starterDocument() -> OutlineDocument {
    OutlineDocument(rootNodes: [OutlineNode(text: "", type: .bullet)])
  }

  func ensuringStarterBullet() -> OutlineDocument {
    rootNodes.isEmpty ? Self.starterDocument() : self
  }

  @MainActor
  static let sampleDocument = OutlineDocument(rootNodes: [
    OutlineNode(text: "1 이것이 아웃라이너", type: .bullet, children: [
      OutlineNode(text: "2 이렇게 된다. 그리고 할일을 정리할 수 있다.", type: .bullet),
    ]),
    OutlineNode(text: "3 이렇게 할일이 표시된다.", type: .task(completed: false), children: [
      OutlineNode(text: "4 내용은 이런 것이 된다.", type: .bullet),
      OutlineNode(text: "5 그렇게된다.", type: .bullet),
      OutlineNode(text: "6 아마 아래 이렇게 내용도 들어간다. 나는 그렇게 생각하지 않지만, 너는 너가 생각하는 길을 가야 한다. 내가 3줄짜리를 만들어도 너는 그것을 내가 생각하는 것 이상으로 생각해야 한다. 안그런가.", type: .task(completed: false), children: [
        OutlineNode(text: "7 이것은 중간 내용이된다. 그러니까 할일은 빠지고. 그리고 이것도 긴 글이다. 긴글이 먹는 것을 나는 볼 것이다. 그 칸이 아주 길게 저용되니까 말이다. 내가 너는 아니라고 해도 너는 그렇게 도리것이다. ", type: .bullet, children: [
          OutlineNode(text: "8 이것이 다시 들어가는 것.", type: .bullet),
        ]),
      ]),
      OutlineNode(text: "9 이것은 아니다 아니라고 말한다. 네가 말이 안왼다고. ", type: .task(completed: false), children: [
        OutlineNode(text: "10 이것이 내용이된다.", type: .bullet),
      ]),
    ]),
  ])
}

struct OutlinerProject: Identifiable, Equatable {
  static let defaultTitle = "기본 프로젝트"

  let id: UUID
  var title: String
  var document: OutlineDocument

  init(
    id: UUID = UUID(),
    title: String,
    document: OutlineDocument = OutlineDocument.starterDocument()
  ) {
    self.id = id
    self.title = title
    self.document = document.ensuringStarterBullet()
  }

  @MainActor
  static let sampleProject = OutlinerProject(
    title: defaultTitle,
    document: .sampleDocument
  )
}

struct OutlineParsedBlockReference: Equatable {
  let projectID: UUID?
  let targetID: UUID
  let alias: String?
}

struct OutlineResolvedReference {
  let projectID: UUID
  let projectTitle: String
  let node: OutlineNode
}

struct OutlineBlockReferenceSuggestion: Identifiable, Equatable {
  let projectID: UUID
  let targetID: UUID
  let projectTitle: String
  let blockText: String
  let ancestorText: String

  var id: String {
    "\(projectID.uuidString):\(targetID.uuidString)"
  }

  var displayTitle: String {
    blockText.isEmpty ? "(빈 노드)" : blockText
  }

  var contextText: String {
    var parts: [String] = [projectTitle]
    if !ancestorText.isEmpty {
      parts.append(ancestorText)
    }
    return parts.joined(separator: " > ")
  }
}

enum OutlineBlockReferenceCodec {
  private static let uuidPattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
  private static let plainPattern =
    "^\\(\\(((" + uuidPattern + ")(:(" + uuidPattern + "))?)\\)\\)$"
  private static let aliasPattern =
    "^\\[(.+?)\\]\\(\\(((" + uuidPattern + ")(:(" + uuidPattern + "))?)\\)\\)\\)$"

  static func token(projectID: UUID, nodeID: UUID) -> String {
    "((\(projectID.uuidString):\(nodeID.uuidString)))"
  }

  static func aliasToken(alias: String, projectID: UUID, nodeID: UUID) -> String {
    "[\(alias)](((\(projectID.uuidString):\(nodeID.uuidString))))"
  }

  static func parse(_ text: String) -> OutlineParsedBlockReference? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let parsed = parse(trimmed, pattern: aliasPattern, aliasGroup: 1, payloadGroup: 2) {
      return parsed
    }
    return parse(trimmed, pattern: plainPattern, aliasGroup: nil, payloadGroup: 1)
  }

  static func searchQuery(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard parse(trimmed) == nil else { return nil }
    guard trimmed.hasPrefix("((") else { return nil }
    if trimmed.hasSuffix("))") {
      return nil
    }
    return String(trimmed.dropFirst(2))
  }

  private static func parse(
    _ text: String,
    pattern: String,
    aliasGroup: Int?,
    payloadGroup: Int
  ) -> OutlineParsedBlockReference? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let payloadRange = Range(match.range(at: payloadGroup), in: text) else {
      return nil
    }

    let alias: String?
    if let aliasGroup,
       let aliasRange = Range(match.range(at: aliasGroup), in: text) {
      alias = String(text[aliasRange])
    } else {
      alias = nil
    }

    return parsePayload(String(text[payloadRange]), alias: alias)
  }

  private static func parsePayload(
    _ payload: String,
    alias: String?
  ) -> OutlineParsedBlockReference? {
    let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
    switch parts.count {
    case 1:
      guard let targetID = UUID(uuidString: parts[0]) else { return nil }
      return OutlineParsedBlockReference(projectID: nil, targetID: targetID, alias: alias)
    case 2:
      guard let projectID = UUID(uuidString: parts[0]),
            let targetID = UUID(uuidString: parts[1]) else { return nil }
      return OutlineParsedBlockReference(projectID: projectID, targetID: targetID, alias: alias)
    default:
      return nil
    }
  }
}

enum OutlinerProjectGraph {
  static func project(
    id: UUID,
    in projects: [OutlinerProject]
  ) -> OutlinerProject? {
    projects.first(where: { $0.id == id })
  }

  static func resolveReference(
    node: OutlineNode,
    defaultProjectID: UUID,
    in projects: [OutlinerProject]
  ) -> OutlineResolvedReference? {
    guard case .reference(let targetID) = node.type else { return nil }
    let preferredProjectID = node.referenceProjectID ?? defaultProjectID
    if let resolved = resolveNode(
      projectID: preferredProjectID,
      targetID: targetID,
      in: projects
    ) {
      return resolved
    }

    for project in projects where project.id != preferredProjectID {
      if let resolved = resolveNode(projectID: project.id, targetID: targetID, in: projects) {
        return resolved
      }
    }
    return nil
  }

  static func resolveCloneSource(
    canonicalID: UUID,
    preferredProjectID: UUID,
    in projects: [OutlinerProject]
  ) -> OutlineResolvedReference? {
    if let resolved = resolveCanonicalNode(
      canonicalID: canonicalID,
      projectID: preferredProjectID,
      in: projects
    ) {
      return resolved
    }

    for project in projects where project.id != preferredProjectID {
      if let resolved = resolveCanonicalNode(
        canonicalID: canonicalID,
        projectID: project.id,
        in: projects
      ) {
        return resolved
      }
    }
    return nil
  }

  static func referenceSuggestions(
    query: String,
    currentProjectID: UUID,
    excluding excludedNodeID: UUID? = nil,
    in projects: [OutlinerProject]
  ) -> [OutlineBlockReferenceSuggestion] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    var suggestions: [OutlineBlockReferenceSuggestion] = []
    for project in projects {
      for entry in project.document.flatten() where !entry.node.type.isReference {
        guard entry.id != excludedNodeID else { continue }
        let blockText = entry.node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ancestorText = breadcrumbText(for: entry.id, in: project.document)
        let searchableText = [
          blockText,
          ancestorText,
          project.title,
        ]
          .joined(separator: " ")
          .lowercased()

        guard normalizedQuery.isEmpty || searchableText.contains(normalizedQuery) else {
          continue
        }

        suggestions.append(
          OutlineBlockReferenceSuggestion(
            projectID: project.id,
            targetID: entry.node.canonicalID,
            projectTitle: project.title,
            blockText: blockText,
            ancestorText: ancestorText
          )
        )
      }
    }

    suggestions.sort { lhs, rhs in
      let lhsCurrent = lhs.projectID == currentProjectID ? 0 : 1
      let rhsCurrent = rhs.projectID == currentProjectID ? 0 : 1
      if lhsCurrent != rhsCurrent {
        return lhsCurrent < rhsCurrent
      }

      let lhsStarts = lhs.displayTitle.lowercased().hasPrefix(normalizedQuery) ? 0 : 1
      let rhsStarts = rhs.displayTitle.lowercased().hasPrefix(normalizedQuery) ? 0 : 1
      if lhsStarts != rhsStarts {
        return lhsStarts < rhsStarts
      }

      if lhs.projectTitle != rhs.projectTitle {
        return lhs.projectTitle.localizedStandardCompare(rhs.projectTitle) == .orderedAscending
      }

      return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }

    return Array(suggestions.prefix(8))
  }

  private static func resolveNode(
    projectID: UUID,
    targetID: UUID,
    in projects: [OutlinerProject]
  ) -> OutlineResolvedReference? {
    guard let project = project(id: projectID, in: projects),
          let targetNode = OutlineNodeTreeNavigator.findNode(
            id: targetID,
            in: project.document.rootNodes
          ) else {
      return nil
    }
    return OutlineResolvedReference(
      projectID: projectID,
      projectTitle: project.title,
      node: targetNode
    )
  }

  private static func breadcrumbText(
    for nodeID: UUID,
    in document: OutlineDocument
  ) -> String {
    var titles: [String] = []
    var currentID = OutlineNodeTreeNavigator.parentOf(id: nodeID, in: document.rootNodes)
    while let resolvedCurrentID = currentID {
      guard let node = OutlineNodeTreeNavigator.findNode(
        id: resolvedCurrentID,
        in: document.rootNodes
      ) else {
        break
      }
      titles.append(node.text.isEmpty ? "(빈 노드)" : node.text)
      currentID = OutlineNodeTreeNavigator.parentOf(
        id: resolvedCurrentID,
        in: document.rootNodes
      )
    }
    return titles.reversed().joined(separator: " > ")
  }

  private static func resolveCanonicalNode(
    canonicalID: UUID,
    projectID: UUID,
    in projects: [OutlinerProject]
  ) -> OutlineResolvedReference? {
    guard let project = project(id: projectID, in: projects) else { return nil }
    guard let targetNode = project.document.flatten()
      .map(\.node)
      .first(where: { $0.canonicalID == canonicalID }) else {
      return nil
    }
    return OutlineResolvedReference(
      projectID: projectID,
      projectTitle: project.title,
      node: targetNode
    )
  }
}

enum OutlineNodeCloneEngine {
  static func instanceCount(
    canonicalID: UUID,
    in projects: [OutlinerProject]
  ) -> Int {
    projects.reduce(0) { partialResult, project in
      partialResult + flattenedNodes(in: project.document.rootNodes).filter { $0.canonicalID == canonicalID }.count
    }
  }

  static func buildCanonicalInstanceCounts(
    for projects: [OutlinerProject]
  ) -> [UUID: Int] {
    var counts: [UUID: Int] = [:]
    for project in projects {
      for node in flattenedNodes(in: project.document.rootNodes) {
        counts[node.canonicalID, default: 0] += 1
      }
    }
    return counts
  }

  static func cloneInstance(
    of source: OutlineNode,
    preservingRootID rootID: UUID? = nil
  ) -> OutlineNode {
    OutlineNode(
      id: rootID ?? UUID(),
      canonicalID: source.canonicalID,
      text: source.text,
      type: source.type,
      referenceProjectID: source.referenceProjectID,
      children: source.children.map { cloneInstance(of: $0) },
      isCollapsed: source.isCollapsed,
      migratedTaskItemID: source.migratedTaskItemID,
      reminderIdentifier: source.reminderIdentifier,
      reminderExternalIdentifier: source.reminderExternalIdentifier,
      attachments: source.attachments
    )
  }

  static func replaceNode(
    nodeID: UUID,
    withCloneOf source: OutlineNode,
    in document: OutlineDocument
  ) -> OutlineDocument {
    var updated = document
    updated.updateNode(id: nodeID) { node in
      let preservedCollapse = node.isCollapsed
      node = cloneInstance(of: source, preservingRootID: node.id)
      node.isCollapsed = preservedCollapse
    }
    return updated
  }

  static func insertClone(
    of source: OutlineNode,
    targetID: UUID,
    placement: OutlineNodeDragDropEngine.Placement,
    in document: OutlineDocument
  ) -> OutlineDocument {
    let cloneNode = cloneInstance(of: source)
    var updated = document
    switch placement {
    case .above:
      updated.insertBefore(nodeID: targetID, newNode: cloneNode)
    case .below:
      updated.insertAfter(nodeID: targetID, newNode: cloneNode)
    case .child:
      updated.updateNode(id: targetID) { parent in
        parent.children.append(cloneNode)
        parent.isCollapsed = false
      }
    }
    return updated
  }

  static func detach(
    nodeID: UUID,
    in document: OutlineDocument
  ) -> OutlineDocument {
    var updated = document
    updated.updateNode(id: nodeID) { node in
      node = detachedClone(of: node, preservingRootID: node.id)
    }
    return updated
  }

  static func synchronize(
    projects: [OutlinerProject],
    preferredProjectID: UUID,
    preferredSourceNodeIDs: Set<UUID> = []
  ) -> [OutlinerProject] {
    let orderedProjects = prioritizedProjects(projects, preferredProjectID: preferredProjectID)
    let canonicalSources = canonicalSources(
      from: orderedProjects,
      preferredSourceNodeIDs: preferredSourceNodeIDs
    )
    return projects.map { project in
      var mutable = project
      mutable.document = OutlineDocument(
        rootNodes: synchronizeNodes(project.document.rootNodes, canonicalSources: canonicalSources)
      )
      return mutable
    }
  }

  static func migrateLegacyReferences(
    projects: [OutlinerProject]
  ) -> [OutlinerProject] {
    let sourceProjects = projects
    let migrated = projects.map { project in
      var mutable = project
      mutable.document = OutlineDocument(
        rootNodes: migrateLegacyReferenceNodes(
          project.document.rootNodes,
          currentProjectID: project.id,
          projects: sourceProjects
        )
      )
      return mutable
    }
    return synchronize(projects: migrated, preferredProjectID: migrated.first?.id ?? UUID())
  }

  private static func detachedClone(
    of source: OutlineNode,
    preservingRootID rootID: UUID? = nil
  ) -> OutlineNode {
    let detachedID = UUID()
    return OutlineNode(
      id: rootID ?? detachedID,
      canonicalID: detachedID,
      text: source.text,
      type: source.type,
      referenceProjectID: nil,
      children: source.children.map { detachedClone(of: $0) },
      isCollapsed: source.isCollapsed,
      migratedTaskItemID: source.migratedTaskItemID,
      reminderIdentifier: source.reminderIdentifier,
      reminderExternalIdentifier: source.reminderExternalIdentifier,
      attachments: source.attachments
    )
  }

  private static func prioritizedProjects(
    _ projects: [OutlinerProject],
    preferredProjectID: UUID
  ) -> [OutlinerProject] {
    guard let preferredIndex = projects.firstIndex(where: { $0.id == preferredProjectID }) else {
      return projects
    }
    var ordered = projects
    ordered.swapAt(0, preferredIndex)
    return ordered
  }

  private static func canonicalSources(
    from projects: [OutlinerProject],
    preferredSourceNodeIDs: Set<UUID>
  ) -> [UUID: OutlineNode] {
    var sources: [UUID: OutlineNode] = [:]
    for project in projects {
      for node in flattenedNodes(in: project.document.rootNodes) {
        if preferredSourceNodeIDs.contains(node.id) || sources[node.canonicalID] == nil {
          sources[node.canonicalID] = node
        }
      }
    }
    return sources
  }

  private static func synchronizeNodes(
    _ nodes: [OutlineNode],
    canonicalSources: [UUID: OutlineNode]
  ) -> [OutlineNode] {
    nodes.map { node in
      let source = canonicalSources[node.canonicalID] ?? node
      return synchronizeNode(node, source: source, canonicalSources: canonicalSources)
    }
  }

  private static func synchronizeNode(
    _ node: OutlineNode,
    source: OutlineNode,
    canonicalSources: [UUID: OutlineNode]
  ) -> OutlineNode {
    var updated = node
    updated.canonicalID = source.canonicalID
    updated.text = source.text
    updated.type = source.type
    updated.referenceProjectID = nil
    updated.migratedTaskItemID = source.migratedTaskItemID
    updated.reminderIdentifier = source.reminderIdentifier
    updated.reminderExternalIdentifier = source.reminderExternalIdentifier
    updated.attachments = source.attachments
    updated.children = synchronizeChildren(
      existingChildren: node.children,
      sourceChildren: source.children,
      canonicalSources: canonicalSources
    )
    return updated
  }

  private static func synchronizeChildren(
    existingChildren: [OutlineNode],
    sourceChildren: [OutlineNode],
    canonicalSources: [UUID: OutlineNode]
  ) -> [OutlineNode] {
    var remainingChildren = existingChildren
    var result: [OutlineNode] = []

    for sourceChild in sourceChildren {
      let canonicalSource = canonicalSources[sourceChild.canonicalID] ?? sourceChild
      if let existingIndex = remainingChildren.firstIndex(where: { $0.canonicalID == sourceChild.canonicalID }) {
        let existingChild = remainingChildren.remove(at: existingIndex)
        result.append(
          synchronizeNode(
            existingChild,
            source: canonicalSource,
            canonicalSources: canonicalSources
          )
        )
      } else {
        result.append(cloneInstance(of: canonicalSource))
      }
    }

    return result
  }

  private static func flattenedNodes(in nodes: [OutlineNode]) -> [OutlineNode] {
    nodes.flatMap { node in
      [node] + flattenedNodes(in: node.children)
    }
  }

  private static func migrateLegacyReferenceNodes(
    _ nodes: [OutlineNode],
    currentProjectID: UUID,
    projects: [OutlinerProject]
  ) -> [OutlineNode] {
    nodes.map { node in
      if case .reference = node.type,
         let resolved = OutlineNodeTreeNavigator.resolveReference(
          node: node,
          defaultProjectID: currentProjectID,
          in: projects
         ) {
        let replacement = cloneInstance(of: resolved.node, preservingRootID: node.id)
        var migrated = replacement
        migrated.isCollapsed = node.isCollapsed
        return migrated
      }

      var migrated = node
      migrated.children = migrateLegacyReferenceNodes(
        node.children,
        currentProjectID: currentProjectID,
        projects: projects
      )
      if migrated.canonicalID == migrated.id || migrated.canonicalID.uuidString.isEmpty {
        migrated.canonicalID = migrated.id
      }
      return migrated
    }
  }
}

// MARK: - Node Tree Navigator

enum OutlineNodeTreeNavigator {
  /// 트리 전체에서 id가 일치하는 노드를 찾는다.
  static func findNode(id: UUID, in nodes: [OutlineNode]) -> OutlineNode? {
    for node in nodes {
      if node.id == id { return node }
      if let found = findNode(id: id, in: node.children) { return found }
    }
    return nil
  }

  /// id 노드의 부모 노드 ID를 반환한다. 루트이면 nil.
  static func parentOf(id: UUID, in nodes: [OutlineNode]) -> UUID? {
    for node in nodes {
      for child in node.children {
        if child.id == id { return node.id }
      }
      if let found = parentOf(id: id, in: node.children) { return found }
    }
    return nil
  }

  /// flatten된 순서에서 nodeID 바로 앞의 visible 노드 ID를 반환한다.
  static func previousVisibleNode(
    before nodeID: UUID,
    in document: OutlineDocument
  ) -> UUID? {
    let flat = document.flatten()
    guard let index = flat.firstIndex(where: { $0.id == nodeID }), index > 0 else { return nil }
    return flat[index - 1].id
  }

  /// flatten된 순서에서 nodeID 바로 뒤의 visible 노드 ID를 반환한다.
  static func nextVisibleNode(
    after nodeID: UUID,
    in document: OutlineDocument
  ) -> UUID? {
    let flat = document.flatten()
    guard let index = flat.firstIndex(where: { $0.id == nodeID }),
      index + 1 < flat.count
    else { return nil }
    return flat[index + 1].id
  }

  /// nodeID가 targetID의 subtree 안에 있는지 확인한다. (순환 방지용)
  static func isDescendant(
    nodeID: UUID,
    of targetID: UUID,
    in nodes: [OutlineNode]
  ) -> Bool {
    guard let target = findNode(id: targetID, in: nodes) else { return false }
    return findNode(id: nodeID, in: target.children) != nil
  }

  /// reference 노드가 가리키는 원본 노드를 반환한다.
  static func resolveReference(
    node: OutlineNode,
    in document: OutlineDocument
  ) -> OutlineNode? {
    guard case .reference(let targetID) = node.type else { return nil }
    return findNode(id: targetID, in: document.rootNodes)
  }

  static func resolveReference(
    node: OutlineNode,
    defaultProjectID: UUID,
    in projects: [OutlinerProject]
  ) -> OutlineResolvedReference? {
    OutlinerProjectGraph.resolveReference(
      node: node,
      defaultProjectID: defaultProjectID,
      in: projects
    )
  }

  /// 노드의 sibling 배열에서의 인덱스를 반환한다.
  static func siblingIndex(
    of nodeID: UUID,
    in nodes: [OutlineNode]
  ) -> (siblings: [OutlineNode], index: Int)? {
    for i in 0..<nodes.count {
      if nodes[i].id == nodeID {
        return (nodes, i)
      }
    }
    for node in nodes {
      if let result = siblingIndex(of: nodeID, in: node.children) {
        return result
      }
    }
    return nil
  }
}

// MARK: - Drag & Drop Support

struct OutlineNodeIDTransfer: Codable, Transferable {
  let nodeID: UUID
  let projectID: UUID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .json)
  }
}

enum OutlineNodeDragDropEngine {
  /// placement: .above → targetID의 같은 sibling 위치에 바로 위 삽입
  ///            .below → targetID의 같은 sibling 위치에 바로 아래 삽입
  ///            .child → targetID의 마지막 자식으로 삽입
  enum Placement {
    case above
    case below
    case child
  }

  static func move(
    sourceID: UUID,
    targetID: UUID,
    placement: Placement,
    in document: OutlineDocument
  ) -> OutlineDocument? {
    move(sourceIDs: [sourceID], targetID: targetID, placement: placement, in: document)
  }

  static func move(
    sourceIDs: [UUID],
    targetID: UUID,
    placement: Placement,
    in document: OutlineDocument
  ) -> OutlineDocument? {
    var seen = Set<UUID>()
    let uniqueSourceIDs = sourceIDs.filter { seen.insert($0).inserted }
    guard !uniqueSourceIDs.isEmpty else { return nil }
    guard !uniqueSourceIDs.contains(targetID) else { return nil }
    guard !uniqueSourceIDs.contains(where: {
      OutlineNodeTreeNavigator.isDescendant(
        nodeID: targetID,
        of: $0,
        in: document.rootNodes
      )
    }) else { return nil }

    let sourceNodes = uniqueSourceIDs.compactMap {
      OutlineNodeTreeNavigator.findNode(id: $0, in: document.rootNodes)
    }
    guard sourceNodes.count == uniqueSourceIDs.count else { return nil }

    var doc = document
    for sourceID in uniqueSourceIDs {
      guard doc.removeNode(id: sourceID) != nil else { return nil }
    }

    switch placement {
    case .above:
      for node in sourceNodes {
        doc.insertBefore(nodeID: targetID, newNode: node)
      }
    case .below:
      var anchorID = targetID
      for node in sourceNodes {
        doc.insertAfter(nodeID: anchorID, newNode: node)
        anchorID = node.id
      }
    case .child:
      doc.updateNode(id: targetID) { parent in
        parent.children.append(contentsOf: sourceNodes)
        parent.isCollapsed = false
      }
    }

    return doc
  }

  static func insertReference(
    targetReference: OutlineParsedBlockReference,
    alias: String?,
    targetID: UUID,
    placement: Placement,
    in document: OutlineDocument
  ) -> OutlineDocument {
    let referenceNode = OutlineNode(
      text: alias ?? "",
      type: .reference(targetID: targetReference.targetID),
      referenceProjectID: targetReference.projectID
    )
    var updated = document

    switch placement {
    case .above:
      updated.insertBefore(nodeID: targetID, newNode: referenceNode)
    case .below:
      updated.insertAfter(nodeID: targetID, newNode: referenceNode)
    case .child:
      updated.updateNode(id: targetID) { parent in
        parent.children.append(referenceNode)
      }
    }

    return updated
  }

  /// Logseq처럼 drop zone을 해석한다.
  /// row 상단 16px 안이면 .above, 그 외에 X 오프셋이 충분히 크면 .child, 나머지는 .below
  static func placementFromDropLocation(
    dropLocation: CGPoint,
    depth: Int
  ) -> Placement {
    if dropLocation.y <= OutlineRowLayoutSpec.dragDropTopThreshold {
      return .above
    }

    if isNestedDrop(dropLocation: dropLocation, depth: depth) {
      return .child
    }

    return .below
  }

  static func placementFromBottomSlotLocation(
    dropLocation: CGPoint,
    depth: Int
  ) -> Placement {
    isNestedDrop(dropLocation: dropLocation, depth: depth) ? .child : .below
  }

  private static func isNestedDrop(
    dropLocation: CGPoint,
    depth: Int
  ) -> Bool {
    let normalizedX = dropLocation.x - (CGFloat(depth) * OutlineRowLayoutSpec.indentWidth)
    return normalizedX > OutlineRowLayoutSpec.dragDropNestedThreshold
  }
}

// MARK: - Node Mutation Helpers

extension OutlineDocument {
  /// 트리 안에서 nodeID에 해당하는 노드를 transform 클로저로 변경한다.
  mutating func updateNode(id: UUID, transform: (inout OutlineNode) -> Void) {
    rootNodes = Self.updatedNodes(rootNodes, targetID: id, transform: transform)
  }

  private static func updatedNodes(
    _ nodes: [OutlineNode],
    targetID: UUID,
    transform: (inout OutlineNode) -> Void
  ) -> [OutlineNode] {
    nodes.map { node in
      var mutable = node
      if mutable.id == targetID {
        transform(&mutable)
      } else {
        mutable.children = updatedNodes(mutable.children, targetID: targetID, transform: transform)
      }
      return mutable
    }
  }

  /// nodeID 노드를 트리에서 제거하고 반환한다.
  mutating func removeNode(id: UUID) -> OutlineNode? {
    let (updated, removed) = Self.nodesRemoving(rootNodes, targetID: id)
    rootNodes = updated
    return removed
  }

  private static func nodesRemoving(
    _ nodes: [OutlineNode],
    targetID: UUID
  ) -> ([OutlineNode], OutlineNode?) {
    var result: [OutlineNode] = []
    var removed: OutlineNode?
    for node in nodes {
      if node.id == targetID {
        removed = node
        continue
      }
      var mutable = node
      let (updatedChildren, childRemoved) = nodesRemoving(mutable.children, targetID: targetID)
      mutable.children = updatedChildren
      if childRemoved != nil { removed = childRemoved }
      result.append(mutable)
    }
    return (result, removed)
  }

  /// nodeID의 sibling 배열에서 nodeID 바로 뒤에 newNode를 삽입한다.
  mutating func insertAfter(nodeID: UUID, newNode: OutlineNode) {
    rootNodes = Self.nodesInsertingAfter(rootNodes, targetID: nodeID, newNode: newNode)
  }

  private static func nodesInsertingAfter(
    _ nodes: [OutlineNode],
    targetID: UUID,
    newNode: OutlineNode
  ) -> [OutlineNode] {
    var result: [OutlineNode] = []
    for node in nodes {
      var mutable = node
      if mutable.id == targetID {
        result.append(mutable)
        result.append(newNode)
        continue
      }
      mutable.children = nodesInsertingAfter(mutable.children, targetID: targetID, newNode: newNode)
      result.append(mutable)
    }
    return result
  }

  /// nodeID의 sibling 배열에서 nodeID 바로 앞에 newNode를 삽입한다.
  mutating func insertBefore(nodeID: UUID, newNode: OutlineNode) {
    rootNodes = Self.nodesInsertingBefore(rootNodes, targetID: nodeID, newNode: newNode)
  }

  private static func nodesInsertingBefore(
    _ nodes: [OutlineNode],
    targetID: UUID,
    newNode: OutlineNode
  ) -> [OutlineNode] {
    var result: [OutlineNode] = []
    for node in nodes {
      var mutable = node
      if mutable.id == targetID {
        result.append(newNode)
        result.append(mutable)
        continue
      }
      mutable.children = nodesInsertingBefore(mutable.children, targetID: targetID, newNode: newNode)
      result.append(mutable)
    }
    return result
  }
}

// MARK: - Reorder Engine

enum OutlineNodeReorderEngine {
  static func canMoveSubtree(
    nodeID: UUID,
    direction: OutlinerReorderDirection,
    in document: OutlineDocument
  ) -> Bool {
    moveSubtree(nodeID: nodeID, direction: direction, in: document) != nil
  }

  static func moveSubtree(
    nodeID: UUID,
    direction: OutlinerReorderDirection,
    in document: OutlineDocument
  ) -> OutlineDocument? {
    guard let (siblings, index) = OutlineNodeTreeNavigator.siblingIndex(
      of: nodeID,
      in: document.rootNodes
    ) else { return nil }

    switch direction {
    case .up:
      guard index > 0 else { return nil }
      let previousSiblingID = siblings[index - 1].id
      var updated = document
      guard let node = updated.removeNode(id: nodeID) else { return nil }
      updated.insertBefore(nodeID: previousSiblingID, newNode: node)
      return updated

    case .down:
      guard index + 1 < siblings.count else { return nil }
      let nextSiblingID = siblings[index + 1].id
      var updated = document
      guard let node = updated.removeNode(id: nodeID) else { return nil }
      updated.insertAfter(nodeID: nextSiblingID, newNode: node)
      return updated
    }
  }
}

// MARK: - Reparent Engine

enum OutlineNodeReparentEngine {
  static func canIndent(nodeID: UUID, in document: OutlineDocument) -> Bool {
    indent(nodeID: nodeID, in: document) != nil
  }

  static func canOutdent(nodeID: UUID, in document: OutlineDocument) -> Bool {
    outdent(nodeID: nodeID, in: document) != nil
  }

  /// Tab: 바로 위 sibling의 마지막 child로 이동.
  static func indent(nodeID: UUID, in document: OutlineDocument) -> OutlineDocument? {
    guard let (siblings, index) = OutlineNodeTreeNavigator.siblingIndex(
      of: nodeID,
      in: document.rootNodes
    ) else { return nil }
    guard index > 0 else { return nil }

    let previousSiblingID = siblings[index - 1].id
    var updated = document
    guard let node = updated.removeNode(id: nodeID) else { return nil }
    updated.updateNode(id: previousSiblingID) { parent in
      parent.children.append(node)
    }
    return updated
  }

  /// Shift-Tab: 부모 밖으로 꺼내서 부모의 다음 sibling 위치에 놓음.
  /// 현재 노드 뒤에 있던 sibling들은 현재 노드의 children 끝에 붙는다.
  static func outdent(nodeID: UUID, in document: OutlineDocument) -> OutlineDocument? {
    guard let parentID = OutlineNodeTreeNavigator.parentOf(
      id: nodeID,
      in: document.rootNodes
    ) else { return nil }

    guard let parentNode = OutlineNodeTreeNavigator.findNode(
      id: parentID,
      in: document.rootNodes
    ) else { return nil }

    guard let childIndex = parentNode.children.firstIndex(where: { $0.id == nodeID }) else {
      return nil
    }

    let trailingSiblings = Array(parentNode.children[(childIndex + 1)...])
    var updated = document

    // 1. trailing siblings를 부모에서 제거
    for sibling in trailingSiblings {
      _ = updated.removeNode(id: sibling.id)
    }

    // 2. 현재 노드를 부모에서 제거
    guard var node = updated.removeNode(id: nodeID) else { return nil }

    // 3. trailing siblings를 현재 노드의 children 끝에 붙인다
    node.children.append(contentsOf: trailingSiblings)

    // 4. 현재 노드를 부모의 다음 sibling 위치에 삽입
    updated.insertAfter(nodeID: parentID, newNode: node)
    return updated
  }
}

// MARK: - Deletion Engine

enum OutlineNodeDeletionEngine {
  struct DeleteBackwardAtStartResult {
    let document: OutlineDocument
    let focusNodeID: UUID?
    let cursorPosition: Int?
  }

  /// 노드를 삭제하고, 다음 포커스 대상 ID를 반환한다.
  static func deleteNode(
    nodeID: UUID,
    in document: OutlineDocument
  ) -> (document: OutlineDocument, nextFocusID: UUID?) {
    let flat = document.flatten()
    let currentIndex = flat.firstIndex(where: { $0.id == nodeID })
    let nextFocusID: UUID?

    if let idx = currentIndex, idx > 0 {
      nextFocusID = flat[idx - 1].id
    } else if let idx = currentIndex, idx + 1 < flat.count {
      nextFocusID = flat[idx + 1].id
    } else {
      nextFocusID = nil
    }

    var updated = document
    if let node = OutlineNodeTreeNavigator.findNode(id: nodeID, in: document.rootNodes),
      node.isCloneInstance
    {
      _ = updated.removeNode(id: nodeID)
    } else if let node = OutlineNodeTreeNavigator.findNode(id: nodeID, in: document.rootNodes),
      !node.children.isEmpty
    {
      // children이 있으면 부모의 같은 위치에 승격
      let children = node.children
      _ = updated.removeNode(id: nodeID)
      // children을 삭제된 위치에 삽입 — 이전 sibling 뒤 또는 부모의 children 맨 앞
      if let parentID = OutlineNodeTreeNavigator.parentOf(id: nodeID, in: document.rootNodes) {
        updated.updateNode(id: parentID) { parent in
          if let idx = parent.children.firstIndex(where: { $0.id == nodeID }) {
            parent.children.remove(at: idx)
            parent.children.insert(contentsOf: children, at: idx)
          }
        }
        // removeNode에서 이미 제거되었으므로 updateNode에서 찾을 수 없을 수 있다.
        // 이 경우 이미 제거된 상태이므로, children을 직접 삽입한다.
      } else {
        // 루트 노드였으면 rootNodes에서의 위치에 children을 삽입
        if let idx = updated.rootNodes.firstIndex(where: { $0.id == nodeID }) {
          updated.rootNodes.remove(at: idx)
          updated.rootNodes.insert(contentsOf: children, at: idx)
        }
      }
    } else {
      _ = updated.removeNode(id: nodeID)
    }

    return (updated, nextFocusID)
  }

  /// 명시적 삭제: 현재 노드와 그 subtree를 통째로 제거한다.
  static func deleteSubtree(
    nodeID: UUID,
    in document: OutlineDocument
  ) -> (document: OutlineDocument, nextFocusID: UUID?) {
    let flat = document.flatten()
    let currentIndex = flat.firstIndex(where: { $0.id == nodeID })
    var nextFocusID: UUID?

    if let idx = currentIndex, idx > 0 {
      nextFocusID = flat[idx - 1].id
    } else if let idx = currentIndex, idx + 1 < flat.count {
      nextFocusID = flat[idx + 1].id
    } else {
      nextFocusID = nil
    }

    var updated = document
    _ = updated.removeNode(id: nodeID)
    if updated.rootNodes.isEmpty {
      updated = OutlineDocument.starterDocument()
      nextFocusID = updated.rootNodes.first?.id
    }
    return (updated, nextFocusID)
  }

  static func deleteBackwardAtStart(
    nodeID: UUID,
    in document: OutlineDocument
  ) -> DeleteBackwardAtStartResult? {
    guard let node = OutlineNodeTreeNavigator.findNode(id: nodeID, in: document.rootNodes) else {
      return nil
    }

    if !node.children.isEmpty {
      let result = deleteSubtree(nodeID: nodeID, in: document)
      return DeleteBackwardAtStartResult(
        document: result.document,
        focusNodeID: result.nextFocusID,
        cursorPosition: nil
      )
    }

    guard let result = OutlineNodeInsertionEngine.mergeWithPrevious(nodeID: nodeID, in: document) else {
      return nil
    }

    return DeleteBackwardAtStartResult(
      document: result.document,
      focusNodeID: result.mergedNodeID,
      cursorPosition: result.cursorPosition
    )
  }
}

struct OutlineNodeEditingResult {
  let document: OutlineDocument
  let focusedNodeID: UUID
  let cursorPosition: Int
}

// MARK: - Insertion Engine

enum OutlineNodeInsertionEngine {
  /// 현재 노드 바로 다음 sibling 위치에 새 노드를 삽입한다.
  static func insertAfter(
    nodeID: UUID,
    text: String,
    type: OutlineNodeType,
    in document: OutlineDocument
  ) -> OutlineNodeEditingResult {
    let newNode = OutlineNode(text: text, type: type)
    var updated = document
    updated.insertAfter(nodeID: nodeID, newNode: newNode)
    return OutlineNodeEditingResult(
      document: updated,
      focusedNodeID: newNode.id,
      cursorPosition: 0
    )
  }

  /// Enter 키 동작을 아웃라이너 방식으로 처리한다.
  static func insertNewline(
    nodeID: UUID,
    cursorPosition: Int,
    isZoomRoot: Bool,
    in document: OutlineDocument
  ) -> OutlineNodeEditingResult? {
    guard let node = OutlineNodeTreeNavigator.findNode(id: nodeID, in: document.rootNodes) else {
      return nil
    }

    let siblingInsertionType = siblingInsertedNodeType(from: node.type)
    let textLength = node.text.utf16Length
    let clampedCursor = max(0, min(cursorPosition, textLength))

    if node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      if let updated = OutlineNodeReparentEngine.outdent(nodeID: nodeID, in: document) {
        return OutlineNodeEditingResult(
          document: updated,
          focusedNodeID: nodeID,
          cursorPosition: 0
        )
      }

      return insertAfter(
        nodeID: nodeID,
        text: "",
        type: siblingInsertionType,
        in: document
      )
    }

    let atEnd = clampedCursor >= textLength
    let hasChildren = !node.children.isEmpty
    let onChildLevel = isZoomRoot || (hasChildren && !node.isCollapsed && atEnd)

    if !atEnd {
      return splitAt(nodeID: nodeID, cursorPosition: clampedCursor, in: document)
    }

    if onChildLevel {
      let newNode = OutlineNode(text: "", type: childInsertedNodeType())
      var updated = document
      updated.updateNode(id: nodeID) { parent in
        parent.children.insert(newNode, at: 0)
        parent.isCollapsed = false
      }
      return OutlineNodeEditingResult(
        document: updated,
        focusedNodeID: newNode.id,
        cursorPosition: 0
      )
    }

    return insertAfter(
      nodeID: nodeID,
      text: "",
      type: siblingInsertionType,
      in: document
    )
  }

  /// 커서 위치에서 텍스트를 분리하여 새 노드를 만든다.
  static func splitAt(
    nodeID: UUID,
    cursorPosition: Int,
    in document: OutlineDocument
  ) -> OutlineNodeEditingResult? {
    guard let node = OutlineNodeTreeNavigator.findNode(id: nodeID, in: document.rootNodes) else {
      return nil
    }

    let (beforeText, afterText) = node.text.splitAtUTF16Offset(cursorPosition)
    let movedChildren = node.children

    var updated = document
    updated.updateNode(id: nodeID) { n in
      n.text = beforeText
      n.children = []
    }

    let newNode = OutlineNode(
      text: afterText,
      type: siblingInsertedNodeType(from: node.type),
      referenceProjectID: node.referenceProjectID,
      children: movedChildren
    )
    updated.insertAfter(nodeID: nodeID, newNode: newNode)
    return OutlineNodeEditingResult(
      document: updated,
      focusedNodeID: newNode.id,
      cursorPosition: 0
    )
  }

  /// 현재 노드를 이전 visible 노드와 병합한다.
  /// 반환: 병합된 노드 ID와 병합 지점(이전 노드 텍스트 끝 위치).
  static func mergeWithPrevious(
    nodeID: UUID,
    in document: OutlineDocument
  ) -> (document: OutlineDocument, mergedNodeID: UUID, cursorPosition: Int)? {
    guard let previousID = OutlineNodeTreeNavigator.previousVisibleNode(
      before: nodeID,
      in: document
    ) else { return nil }

    guard let previousNode = OutlineNodeTreeNavigator.findNode(
      id: previousID,
      in: document.rootNodes
    ) else { return nil }

    guard let currentNode = OutlineNodeTreeNavigator.findNode(
      id: nodeID,
      in: document.rootNodes
    ) else { return nil }

    let cursorPosition = previousNode.text.utf16Length
    let mergedText = previousNode.text + currentNode.text

    var updated = document
    updated.updateNode(id: previousID) { n in
      n.text = mergedText
      n.children.append(contentsOf: currentNode.children)
    }
    _ = updated.removeNode(id: nodeID)

    return (updated, previousID, cursorPosition)
  }

  private static func siblingInsertedNodeType(from type: OutlineNodeType) -> OutlineNodeType {
    switch type {
    case .task:
      return .task(completed: false)
    case .bullet:
      return .bullet
    case .reference:
      return .bullet
    }
  }

  private static func childInsertedNodeType() -> OutlineNodeType {
    .bullet
  }
}

enum OutlinerLineMarker: String {
  case bullet
  case todo
  case done
  case plain

  var visiblePrefix: String {
    switch self {
    case .bullet:
      "• "
    case .todo:
      "☐ "
    case .done:
      "☑ "
    case .plain:
      ""
    }
  }

  var isTask: Bool {
    switch self {
    case .todo, .done:
      true
    case .bullet, .plain:
      false
    }
  }
}

struct OutlinerLine: Identifiable {
  let index: Int
  let range: NSRange
  let rawBody: String
  let indentDepth: Int
  let marker: OutlinerLineMarker

  var id: Int { index }

  var markerPrefixUTF16Count: Int {
    marker.visiblePrefix.utf16.count
  }

  var indentPrefix: String {
    String(repeating: OutlinerDocumentParser.indentUnit, count: indentDepth)
  }

  var indentPrefixUTF16Count: Int {
    indentPrefix.utf16.count
  }

  var content: String {
    switch marker {
    case .plain:
      rawBody.dropLeadingIndent()
    case .bullet, .todo, .done:
      rawBody
        .dropLeadingIndent()
        .dropMarkerPrefix(marker.visiblePrefix)
    }
  }

  var visibleText: String {
    indentPrefix + marker.visiblePrefix + content
  }
}

struct OutlinerReminderProjection: Identifiable {
  let nodeID: UUID
  let contentID: UUID
  let taskLine: OutlinerLine
  let descendantLines: [OutlinerLine]
  let projectedNoteLines: [String]
  let syncContract: OutlinerSyncContract
  let baseline: ReminderSyncBaseline
  let reminderIdentifier: String?
  let reminderExternalIdentifier: String?
  let reminderOwnerProjectID: UUID?
  let reminderOwnerCalendarID: String?
  let parentTaskRemoteExternalIdentifier: String?
  let attachmentCount: Int
  let remoteLastModifiedAt: Date?
  let localUpdatedAt: Date
  let noteText: String
  let encodedReminderNote: String
  let parsedReminderBody: String
  let appProjectionSnippetText: String
  let restoredAppSnippetText: String
  let fullSubtreeSnippetText: String
  let anchorCount: Int
  let omittedLineCount: Int

  var id: UUID { nodeID }
  var title: String { taskLine.content }
  var sourceLineNumber: Int { taskLine.index + 1 }
  var noteLineCount: Int { projectedNoteLines.count }
  var isRoundTripStable: Bool {
    appProjectionSnippetText == restoredAppSnippetText && noteText == parsedReminderBody
  }
}

struct OutlinerInboundMergePreview {
  let editedReminderNote: String
  let parsedBody: String
  let parsedAnchorCount: Int
  let restoredAppSnippetText: String
  let warnings: [String]
}

struct OutlinerSyncContract {
  let reminderOwnedFields: [OutlinerSyncField]
  let appOwnedFields: [OutlinerSyncField]
  let attachmentPreviews: [OutlinerAttachmentPreview]
  let attachmentCount: Int
  let requiredWorkDays: Int
  let scheduledDurationMinutes: Int?
  let reminderPayload: OutlinerReminderPayload
}

struct OutlinerSyncField: Identifiable {
  let key: String
  let label: String
  let value: String
  let storage: String
  let note: String

  var id: String { key }
}

struct OutlinerAttachmentPreview: Codable, Hashable, Identifiable {
  let filename: String
  let detail: String

  var id: String { filename }
}

struct OutlinerReminderPayload {
  let dueDate: Date?
  let hasExplicitTime: Bool
  let recurrence: OutlinerRecurrenceSample?
  let priority: Int
}

enum OutlinerRecurrenceSample: Codable, Equatable {
  case daily(interval: Int)
  case weekly(interval: Int, weekdays: [Int])
  case monthly(interval: Int)
  case yearly(interval: Int)

  private enum CodingKeys: String, CodingKey {
    case kind
    case interval
    case weekdays
  }

  private enum Kind: String, Codable {
    case daily
    case weekly
    case monthly
    case yearly
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .kind)
    let interval = max(1, try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1)

    switch kind {
    case .daily:
      self = .daily(interval: interval)
    case .weekly:
      let weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
      self = .weekly(interval: interval, weekdays: weekdays)
    case .monthly:
      self = .monthly(interval: interval)
    case .yearly:
      self = .yearly(interval: interval)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case let .daily(interval):
      try container.encode(Kind.daily, forKey: .kind)
      try container.encode(max(1, interval), forKey: .interval)
    case let .weekly(interval, weekdays):
      try container.encode(Kind.weekly, forKey: .kind)
      try container.encode(max(1, interval), forKey: .interval)
      try container.encode(weekdays, forKey: .weekdays)
    case let .monthly(interval):
      try container.encode(Kind.monthly, forKey: .kind)
      try container.encode(max(1, interval), forKey: .interval)
    case let .yearly(interval):
      try container.encode(Kind.yearly, forKey: .kind)
      try container.encode(max(1, interval), forKey: .interval)
    }
  }

  var displayText: String {
    switch self {
    case let .daily(interval):
      return interval <= 1 ? "매일" : "\(interval)일마다"
    case let .weekly(_, weekdays):
      let names = weekdays.compactMap { weekdayName(for: $0) }
      return names.isEmpty ? "매주" : "매주 " + names.joined(separator: "/")
    case let .monthly(interval):
      return interval <= 1 ? "매월" : "\(interval)개월마다"
    case let .yearly(interval):
      return interval <= 1 ? "매년" : "\(interval)년마다"
    }
  }

  private func weekdayName(for rawValue: Int) -> String? {
    switch rawValue {
    case 1:
      return "일"
    case 2:
      return "월"
    case 3:
      return "화"
    case 4:
      return "수"
    case 5:
      return "목"
    case 6:
      return "금"
    case 7:
      return "토"
    default:
      return nil
    }
  }
}

enum OutlinerReorderDirection {
  case up
  case down
}

enum OutlinerDocumentParser {
  static let indentUnit = "\t"

  static let screenshotReplicaText = [
    "• 1 이것이 아웃라이너",
    "\t• 2 이렇게 된다. 그리고 할일을 정리할 수 있다.",
    "☐ 3 이렇게 할일이 표시된다.",
    "\t• 4 내용은 이런 것이 된다.",
    "\t• 5 그렇게된다.",
    "\t☐ 6 아마 아래 이렇게 내용도 들어간다.",
    "\t• 7 이것은 중간 내용이된다. 그러니까 할일은 빠지고.",
    "\t\t• 8 이것이 다시 들어가는 것.",
    "\t☐ 9 이것은",
    "\t\t• 10 이것이 내용이된다.",
  ].joined(separator: "\n")

  static func visibleLineRanges(in text: String) -> [NSRange] {
    let nsText = text as NSString
    guard nsText.length > 0 else {
      return [NSRange(location: 0, length: 0)]
    }

    var ranges: [NSRange] = []
    var cursor = 0

    while cursor < nsText.length {
      let fullLineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
      var visibleRange = fullLineRange
      if visibleRange.length > 0,
        nsText.character(at: NSMaxRange(visibleRange) - 1) == 10
      {
        visibleRange.length -= 1
      }

      ranges.append(visibleRange)
      cursor = NSMaxRange(fullLineRange)
    }

    if nsText.length > 0, nsText.character(at: nsText.length - 1) == 10 {
      ranges.append(NSRange(location: nsText.length, length: 0))
    }

    return ranges
  }

  static func lines(from text: String) -> [OutlinerLine] {
    let nsText = text as NSString
    guard nsText.length > 0 else {
      return [
        OutlinerLine(
          index: 0,
          range: NSRange(location: 0, length: 0),
          rawBody: "",
          indentDepth: 0,
          marker: .plain
        )
      ]
    }

    var lines: [OutlinerLine] = []
    var cursor = 0
    var index = 0

    while cursor < nsText.length {
      let fullLineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
      var visibleRange = fullLineRange
      if visibleRange.length > 0,
        nsText.character(at: NSMaxRange(visibleRange) - 1) == 10
      {
        visibleRange.length -= 1
      }

      let rawBody = nsText.substring(with: visibleRange)
      lines.append(parsedLine(from: rawBody, index: index, range: visibleRange))
      cursor = NSMaxRange(fullLineRange)
      index += 1
    }

    return lines
  }

  static func parsedLine(from rawBody: String, index: Int, range: NSRange) -> OutlinerLine {
    let bodyWithoutIndent = rawBody.dropLeadingIndent()
    let marker: OutlinerLineMarker

    if bodyWithoutIndent.hasPrefix(OutlinerLineMarker.todo.visiblePrefix) {
      marker = .todo
    } else if bodyWithoutIndent.hasPrefix(OutlinerLineMarker.done.visiblePrefix) {
      marker = .done
    } else if bodyWithoutIndent.hasPrefix(OutlinerLineMarker.bullet.visiblePrefix) {
      marker = .bullet
    } else {
      marker = .plain
    }

    return OutlinerLine(
      index: index,
      range: range,
      rawBody: rawBody,
      indentDepth: rawBody.leadingIndentDepth(),
      marker: marker
    )
  }

  static func normalizeVisibleText(_ text: String) -> String {
    let nsText = text as NSString
    guard nsText.length > 0 else { return text }

    var normalized: [String] = []
    var cursor = 0

    while cursor < nsText.length {
      let fullLineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
      var visibleRange = fullLineRange
      let hasLineBreak =
        visibleRange.length > 0 && nsText.character(at: NSMaxRange(visibleRange) - 1) == 10
      if hasLineBreak {
        visibleRange.length -= 1
      }

      let rawBody = nsText.substring(with: visibleRange)
      normalized.append(normalizedLineBody(rawBody))
      if hasLineBreak {
        normalized.append("\n")
      }
      cursor = NSMaxRange(fullLineRange)
    }

    return normalized.joined()
  }

  static func continuationPrefix(for line: OutlinerLine) -> String {
    line.indentPrefix + line.marker.visiblePrefix
  }

  static func normalizedLineBody(_ line: String) -> String {
    let indent = line.leadingIndentPrefix()
    let body = String(line.dropFirst(indent.count))

    if body.hasPrefix("- ") || body.hasPrefix("* ") {
      return indent + OutlinerLineMarker.bullet.visiblePrefix + String(body.dropFirst(2))
    }

    if body.hasPrefix("[] ") {
      return indent + OutlinerLineMarker.todo.visiblePrefix + String(body.dropFirst(3))
    }

    if body.hasPrefix("[ ] ") {
      return indent + OutlinerLineMarker.todo.visiblePrefix + String(body.dropFirst(4))
    }

    if body.hasPrefix("[x] ") || body.hasPrefix("[X] ") {
      return indent + OutlinerLineMarker.done.visiblePrefix + String(body.dropFirst(4))
    }

    return line
  }
}

enum OutlinerReminderProjectionBuilder {
  static let syncListName = "123123"

  static func projections(
    from text: String,
    metadataProvider: ((OutlinerLine) -> OutlinerTaskSidecarMetadata?)? = nil
  ) -> [OutlinerReminderProjection] {
    let lines = OutlinerDocumentParser.lines(from: text)
    return lines.compactMap { line -> OutlinerReminderProjection? in
      guard line.marker.isTask else { return nil }
      let descendants = descendantLines(for: line, within: lines)
      let noteLines = projectedNoteLines(for: line, descendants: descendants)
      let syncContract = OutlinerSyncContractBuilder.contract(
        for: line,
        descendants: descendants,
        projectedNoteLines: noteLines,
        persistedFeatureSidecar: metadataProvider?(line)
      )
      let noteText = noteLines.joined(separator: "\n")
      let encodedReminderNote = ReminderNoteCodec.compose(
        body: noteText,
        attachmentCount: 0
      )
      let parsedReminderBody = ReminderNoteCodec.parse(encodedReminderNote).body
      let appProjectionSnippetText = appProjectionSnippetText(for: line, descendants: descendants)
      let restoredAppSnippetText = restoredAppSnippetText(
        taskTitle: line.content,
        taskMarker: line.marker,
        noteBody: parsedReminderBody,
        descendantTaskQueue: descendants.filter { $0.marker.isTask }
      )
      let anchorCount = noteLines.count { OutlinerTaskAnchorCodec.parse(line: $0) != nil }
      let omittedLineCount = max(0, descendants.count - projectedAppLineCount(for: line, descendants: descendants))

      return OutlinerReminderProjection(
        nodeID: UUID(),
        contentID: UUID(),
        taskLine: line,
        descendantLines: descendants,
        projectedNoteLines: noteLines,
        syncContract: syncContract,
        baseline: ReminderSyncBaseline(
          lastSyncedReminderTitle: line.content,
          lastSyncedReminderNoteBody: ""
        ),
        reminderIdentifier: nil,
        reminderExternalIdentifier: nil,
        reminderOwnerProjectID: nil,
        reminderOwnerCalendarID: nil,
        parentTaskRemoteExternalIdentifier: nil,
        attachmentCount: syncContract.attachmentCount,
        remoteLastModifiedAt: nil,
        localUpdatedAt: .now,
        noteText: noteText,
        encodedReminderNote: encodedReminderNote,
        parsedReminderBody: parsedReminderBody,
        appProjectionSnippetText: appProjectionSnippetText,
        restoredAppSnippetText: restoredAppSnippetText,
        fullSubtreeSnippetText: fullSubtreeSnippetText(for: line, descendants: descendants),
        anchorCount: anchorCount,
        omittedLineCount: omittedLineCount
      )
    }
  }

  static func focusedProjection(
    in text: String,
    selectionLocation: Int,
    metadataProvider: ((OutlinerLine) -> OutlinerTaskSidecarMetadata?)? = nil
  ) -> OutlinerReminderProjection? {
    let projections = projections(from: text, metadataProvider: metadataProvider)
    guard !projections.isEmpty else { return nil }

    let lines = OutlinerDocumentParser.lines(from: text)
    let currentLineIndex =
      lines.first(where: { selectionLocation >= $0.range.location && selectionLocation <= NSMaxRange($0.range) })?.index
      ?? lines.last?.index
      ?? 0

    return projections
      .filter { projection in
        let coveredRange = projection.taskLine.index...(projection.taskLine.index + projection.descendantLines.count)
        return coveredRange.contains(currentLineIndex)
      }
      .max(by: { $0.taskLine.indentDepth < $1.taskLine.indentDepth })
      ?? projections.first
  }

  static func focusedProjection(
    in text: String,
    sourceLineIndex: Int,
    metadataProvider: ((OutlinerLine) -> OutlinerTaskSidecarMetadata?)? = nil
  ) -> OutlinerReminderProjection? {
    let projections = projections(from: text, metadataProvider: metadataProvider)
    guard !projections.isEmpty else { return nil }

    return projections
      .filter { projection in
        let coveredRange = projection.taskLine.index...(projection.taskLine.index + projection.descendantLines.count)
        return coveredRange.contains(sourceLineIndex)
      }
      .max(by: { $0.taskLine.indentDepth < $1.taskLine.indentDepth })
      ?? projections.first
  }

  static func inboundMergePreview(
    for projection: OutlinerReminderProjection,
    editedReminderNote: String
  ) -> OutlinerInboundMergePreview {
    let parsedNote = ReminderNoteCodec.parse(editedReminderNote)
    let parsedLines = parsedNote.body.isEmpty ? [] : parsedNote.body.components(separatedBy: "\n")
    let parsedAnchorCount = parsedLines.count { OutlinerTaskAnchorCodec.parse(line: $0) != nil }
    let descendantTaskQueue = projection.descendantLines.filter { $0.marker.isTask }
    let restored = restoredAppSnippetText(
      taskTitle: projection.taskLine.content,
      taskMarker: projection.taskLine.marker,
      noteBody: parsedNote.body,
      descendantTaskQueue: descendantTaskQueue
    )

    var warnings: [String] = []
    if parsedAnchorCount < projection.anchorCount {
      warnings.append("일부 ➕ 앵커가 사라져서, 해당 하위 task 위치 연결이 약해집니다.")
    }
    if parsedAnchorCount > projection.anchorCount {
      warnings.append("원본보다 많은 ➕ 앵커가 들어와 추가 하위 task처럼 복원될 수 있습니다.")
    }
    if parsedNote.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      warnings.append("본문이 비어 있어도 하위 task sidecar는 앱에 그대로 남습니다.")
    }

    return OutlinerInboundMergePreview(
      editedReminderNote: editedReminderNote,
      parsedBody: parsedNote.body,
      parsedAnchorCount: parsedAnchorCount,
      restoredAppSnippetText: restored,
      warnings: warnings
    )
  }

  static func restoredAppSnippetText(
    for projection: OutlinerReminderProjection,
    reminderTitle: String,
    reminderBody: String
  ) -> String {
    restoredAppSnippetText(
      taskTitle: reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? projection.title
        : reminderTitle,
      taskMarker: projection.taskLine.marker,
      noteBody: reminderBody,
      descendantTaskQueue: projection.descendantLines.filter { $0.marker.isTask }
    )
  }

  static func applyRemoteReminder(
    to fullText: String,
    projection: OutlinerReminderProjection,
    collapsedLineIndices: Set<Int>,
    reminderTitle: String,
    reminderBody: String,
    isCompleted: Bool
  ) -> OutlinerRemoteApplyResult? {
    let lines = OutlinerDocumentParser.lines(from: fullText)
    guard let subtreeRange = OutlinerTreeNavigator.subtreeRange(
      for: projection.taskLine.index,
      within: lines
    ) else {
      return nil
    }

    let originalLineBodies = lines.map(\.rawBody)
    let replacementBodies = mergedSubtreeLineBodies(
      for: projection,
      reminderTitle: reminderTitle,
      reminderBody: reminderBody,
      isCompleted: isCompleted
    )

    guard subtreeRange.lowerBound <= originalLineBodies.count - 1 else { return nil }

    var updatedLineBodies = originalLineBodies
    updatedLineBodies.replaceSubrange(subtreeRange, with: replacementBodies)
    let updatedText = updatedLineBodies.joined(separator: "\n")
    let lineDelta = replacementBodies.count - subtreeRange.count
    let remappedCollapsed = remapCollapsedLineIndices(
      currentCollapsedLineIndices: collapsedLineIndices,
      oldSubtreeRange: subtreeRange,
      lineDelta: lineDelta,
      updatedText: updatedText
    )

    return OutlinerRemoteApplyResult(
      text: updatedText,
      selectedSourceLineIndex: subtreeRange.lowerBound,
      remappedCollapsedLineIndices: remappedCollapsed
    )
  }

  static func importedSubtreeLineBodies(
    reminderTitle: String,
    reminderBody: String,
    isCompleted: Bool
  ) -> [String] {
    let normalizedTitle = reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let rootTitle = normalizedTitle.isEmpty ? "새 할일" : normalizedTitle
    let rootLine = (isCompleted ? OutlinerLineMarker.done : OutlinerLineMarker.todo).visiblePrefix + rootTitle

    let trimmedBody = reminderBody.trimmingCharacters(in: .newlines)
    guard !trimmedBody.isEmpty else {
      return [rootLine]
    }

    let descendantLines = trimmedBody.components(separatedBy: "\n").map { rawLine -> String in
      if let anchor = OutlinerTaskAnchorCodec.parse(line: rawLine) {
        return String(repeating: OutlinerDocumentParser.indentUnit, count: anchor.indentDepth + 1)
          + OutlinerLineMarker.todo.visiblePrefix
          + anchor.displayedTitle
      }

      let parsed = OutlinerDocumentParser.parsedLine(
        from: rawLine,
        index: 0,
        range: NSRange(location: 0, length: (rawLine as NSString).length)
      )
      return String(repeating: OutlinerDocumentParser.indentUnit, count: parsed.indentDepth + 1)
        + parsed.marker.visiblePrefix
        + parsed.content
    }

    return [rootLine] + descendantLines
  }

  private static func descendantLines(
    for taskLine: OutlinerLine,
    within lines: [OutlinerLine]
  ) -> [OutlinerLine] {
    guard taskLine.index + 1 < lines.count else { return [] }

    var descendants: [OutlinerLine] = []

    for line in lines[(taskLine.index + 1)...] {
      if line.indentDepth <= taskLine.indentDepth {
        break
      }
      descendants.append(line)
    }

    return descendants
  }

  private static func projectedNoteLines(
    for taskLine: OutlinerLine,
    descendants: [OutlinerLine]
  ) -> [String] {
    guard !descendants.isEmpty else { return [] }

    var result: [String] = []
    var index = 0

    while index < descendants.count {
      let line = descendants[index]

      if line.marker.isTask {
        result.append(
          OutlinerTaskAnchorCodec.anchorLine(
            for: line,
            relativeIndentDepth: max(0, line.indentDepth - taskLine.indentDepth - 1)
          )
        )
        index += 1
        while index < descendants.count, descendants[index].indentDepth > line.indentDepth {
          index += 1
        }
        continue
      }

      result.append(noteLineText(for: line, taskIndentDepth: taskLine.indentDepth))
      index += 1
    }

    return result
  }

  private static func noteLineText(for line: OutlinerLine, taskIndentDepth: Int) -> String {
    let relativeIndent = max(0, line.indentDepth - taskIndentDepth - 1)
    return String(repeating: OutlinerDocumentParser.indentUnit, count: relativeIndent)
      + line.marker.visiblePrefix
      + line.content
  }

  private static func appProjectionSnippetText(
    for taskLine: OutlinerLine,
    descendants: [OutlinerLine]
  ) -> String {
    let header = taskLine.marker.visiblePrefix + taskLine.content
    guard !descendants.isEmpty else { return header }

    var detailLines: [String] = []
    var index = 0
    while index < descendants.count {
      let line = descendants[index]
      detailLines.append(
        String(
          repeating: OutlinerDocumentParser.indentUnit,
          count: max(1, line.indentDepth - taskLine.indentDepth)
        ) + line.marker.visiblePrefix + line.content
      )

      if line.marker.isTask {
        index += 1
        while index < descendants.count, descendants[index].indentDepth > line.indentDepth {
          index += 1
        }
        continue
      }

      index += 1
    }

    return ([header] + detailLines).joined(separator: "\n")
  }

  private static func projectedAppLineCount(
    for taskLine: OutlinerLine,
    descendants: [OutlinerLine]
  ) -> Int {
    let headerOnly = appProjectionSnippetText(for: taskLine, descendants: descendants)
    return max(0, headerOnly.components(separatedBy: "\n").count - 1)
  }

  private static func fullSubtreeSnippetText(
    for taskLine: OutlinerLine,
    descendants: [OutlinerLine]
  ) -> String {
    let header = taskLine.marker.visiblePrefix + taskLine.content
    let detailLines = descendants.map { line in
      String(repeating: OutlinerDocumentParser.indentUnit, count: max(1, line.indentDepth - taskLine.indentDepth))
        + line.marker.visiblePrefix
        + line.content
    }
    return ([header] + detailLines).joined(separator: "\n")
  }

  private static func restoredAppSnippetText(
    taskTitle: String,
    taskMarker: OutlinerLineMarker,
    noteBody: String,
    descendantTaskQueue: [OutlinerLine]
  ) -> String {
    let trimmedBody = noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
    let header = taskMarker.visiblePrefix + taskTitle
    guard !trimmedBody.isEmpty else { return header }

    var remainingTasks = descendantTaskQueue[...]
    let restoredLines = noteBody.components(separatedBy: "\n").map { rawLine in
      if let anchor = OutlinerTaskAnchorCodec.parse(line: rawLine) {
        let canonicalTaskLine = remainingTasks.popFirst()
        return String(repeating: OutlinerDocumentParser.indentUnit, count: anchor.indentDepth + 1)
          + (canonicalTaskLine?.marker.visiblePrefix ?? OutlinerLineMarker.todo.visiblePrefix)
          + (canonicalTaskLine?.content ?? anchor.displayedTitle)
      }

      let parsed = OutlinerDocumentParser.parsedLine(
        from: rawLine,
        index: 0,
        range: NSRange(location: 0, length: (rawLine as NSString).length)
      )
      return String(repeating: OutlinerDocumentParser.indentUnit, count: parsed.indentDepth + 1)
        + parsed.marker.visiblePrefix
        + parsed.content
    }
    return ([header] + restoredLines).joined(separator: "\n")
  }

  private static func mergedSubtreeLineBodies(
    for projection: OutlinerReminderProjection,
    reminderTitle: String,
    reminderBody: String,
    isCompleted: Bool
  ) -> [String] {
    let normalizedTitle = reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let rootTitle = normalizedTitle.isEmpty ? projection.title : normalizedTitle
    let rootLine = String(repeating: OutlinerDocumentParser.indentUnit, count: projection.taskLine.indentDepth)
      + (isCompleted ? OutlinerLineMarker.done : OutlinerLineMarker.todo).visiblePrefix
      + rootTitle

    var remainingTaskSubtrees = preservedTaskSubtrees(from: projection)
    let noteLines =
      reminderBody.trimmingCharacters(in: .newlines).isEmpty
      ? []
      : reminderBody.components(separatedBy: "\n")

    var mergedDescendants: [String] = []
    for rawLine in noteLines {
      if let anchor = OutlinerTaskAnchorCodec.parse(line: rawLine),
        let matchedSubtree = takeMatchingTaskSubtree(
          for: anchor.displayedTitle,
          from: &remainingTaskSubtrees
        )
      {
        mergedDescendants.append(
          contentsOf: rebasedTaskSubtreeLines(
            matchedSubtree,
            targetRootIndentDepth: projection.taskLine.indentDepth + 1 + anchor.indentDepth
          )
        )
        continue
      }

      let parsed = OutlinerDocumentParser.parsedLine(
        from: rawLine,
        index: 0,
        range: NSRange(location: 0, length: (rawLine as NSString).length)
      )
      let absoluteIndentDepth = projection.taskLine.indentDepth + 1 + parsed.indentDepth
      mergedDescendants.append(
        String(repeating: OutlinerDocumentParser.indentUnit, count: absoluteIndentDepth)
          + parsed.marker.visiblePrefix
          + parsed.content
      )
    }

    for preservedSubtree in remainingTaskSubtrees {
      mergedDescendants.append(contentsOf: rebasedTaskSubtreeLines(
        preservedSubtree,
        targetRootIndentDepth: preservedSubtree.rootLine.indentDepth
      ))
    }

    return [rootLine] + mergedDescendants
  }

  private static func preservedTaskSubtrees(
    from projection: OutlinerReminderProjection
  ) -> [OutlinerPreservedTaskSubtree] {
    let descendants = projection.descendantLines
    guard !descendants.isEmpty else { return [] }

    var taskSubtrees: [OutlinerPreservedTaskSubtree] = []
    var index = 0

    while index < descendants.count {
      let line = descendants[index]
      guard line.marker.isTask else {
        index += 1
        continue
      }

      var subtreeLines = [line]
      index += 1
      while index < descendants.count, descendants[index].indentDepth > line.indentDepth {
        subtreeLines.append(descendants[index])
        index += 1
      }

      taskSubtrees.append(
        OutlinerPreservedTaskSubtree(
          rootLine: line,
          allLines: subtreeLines
        )
      )
    }

    return taskSubtrees
  }

  private static func takeMatchingTaskSubtree(
    for displayedTitle: String,
    from remainingTaskSubtrees: inout [OutlinerPreservedTaskSubtree]
  ) -> OutlinerPreservedTaskSubtree? {
    guard !remainingTaskSubtrees.isEmpty else { return nil }

    let normalizedTitle = displayedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedTitle.isEmpty {
      let exactMatches = remainingTaskSubtrees.enumerated().filter {
        $0.element.rootLine.content == normalizedTitle
      }
      if exactMatches.count == 1, let match = exactMatches.first {
        return remainingTaskSubtrees.remove(at: match.offset)
      }
    }

    return remainingTaskSubtrees.removeFirst()
  }

  private static func rebasedTaskSubtreeLines(
    _ subtree: OutlinerPreservedTaskSubtree,
    targetRootIndentDepth: Int
  ) -> [String] {
    let indentDelta = targetRootIndentDepth - subtree.rootLine.indentDepth
    return subtree.allLines.map { line in
      let rebasedIndent = max(0, line.indentDepth + indentDelta)
      return String(repeating: OutlinerDocumentParser.indentUnit, count: rebasedIndent)
        + line.marker.visiblePrefix
        + line.content
    }
  }

  private static func remapCollapsedLineIndices(
    currentCollapsedLineIndices: Set<Int>,
    oldSubtreeRange: ClosedRange<Int>,
    lineDelta: Int,
    updatedText: String
  ) -> Set<Int> {
    let remappedIndices = currentCollapsedLineIndices.compactMap { index -> Int? in
      if index < oldSubtreeRange.lowerBound {
        return index
      }
      if index > oldSubtreeRange.upperBound {
        return index + lineDelta
      }
      if index == oldSubtreeRange.lowerBound {
        return oldSubtreeRange.lowerBound
      }
      return nil
    }

    let updatedLines = OutlinerDocumentParser.lines(from: updatedText)
    let validCollapsed = Set(updatedLines.compactMap { line -> Int? in
      OutlinerTreeNavigator.hasDescendants(for: line.index, within: updatedLines) ? line.index : nil
    })
    return Set(remappedIndices).intersection(validCollapsed)
  }
}

struct OutlinerRemoteApplyResult {
  let text: String
  let selectedSourceLineIndex: Int
  let remappedCollapsedLineIndices: Set<Int>
}

private struct OutlinerPreservedTaskSubtree {
  let rootLine: OutlinerLine
  let allLines: [OutlinerLine]
}

enum OutlinerReparentDirection {
  case indent
  case outdent
}

enum OutlinerTreeNavigator {
  static func subtreeRange(
    for sourceLineIndex: Int,
    within lines: [OutlinerLine]
  ) -> ClosedRange<Int>? {
    guard let line = lines.first(where: { $0.index == sourceLineIndex }) else { return nil }
    var endIndex = line.index
    guard line.index + 1 < lines.count else { return line.index...endIndex }

    for candidate in lines[(line.index + 1)...] {
      if candidate.indentDepth <= line.indentDepth {
        break
      }
      endIndex = candidate.index
    }

    return line.index...endIndex
  }

  static func descendantCount(for sourceLineIndex: Int, within lines: [OutlinerLine]) -> Int {
    guard let sourceRange = subtreeRange(for: sourceLineIndex, within: lines) else { return 0 }
    return max(0, sourceRange.upperBound - sourceRange.lowerBound)
  }

  static func hasDescendants(for sourceLineIndex: Int, within lines: [OutlinerLine]) -> Bool {
    descendantCount(for: sourceLineIndex, within: lines) > 0
  }

  static func parentSourceLineIndex(
    for sourceLineIndex: Int,
    within lines: [OutlinerLine]
  ) -> Int? {
    guard let line = lines.first(where: { $0.index == sourceLineIndex }) else { return nil }
    guard line.indentDepth > 0 else { return nil }

    for candidateIndex in stride(from: line.index - 1, through: 0, by: -1) {
      let candidate = lines[candidateIndex]
      if candidate.indentDepth == line.indentDepth - 1 {
        return candidate.index
      }
    }

    return nil
  }
}

enum OutlinerSyncContractBuilder {
  private static let previewCalendar = Calendar(identifier: .gregorian)

  static func contract(
    for taskLine: OutlinerLine,
    descendants: [OutlinerLine],
    projectedNoteLines: [String],
    persistedFeatureSidecar: OutlinerTaskSidecarMetadata? = nil,
    persistedReminderMetadata: ReminderMetadataSnapshot? = nil
  ) -> OutlinerSyncContract {
    let descendantTodoCount = descendants.filter { $0.marker.isTask }.count
    let noteContextLineCount = max(0, projectedNoteLines.count - descendantTodoCount)
    let computedAttachmentCount = min(3, max(0, noteContextLineCount))
    let computedRequiredWorkDays = max(
      1,
      min(4, descendantTodoCount + (projectedNoteLines.isEmpty ? 0 : 1))
    )
    let computedScheduledDurationMinutes =
      max(20, 25 + (projectedNoteLines.count * 15) + (descendantTodoCount * 20))
    let attachmentPreviews =
      persistedFeatureSidecar?.attachmentPreviews
      ?? attachmentPreviews(for: taskLine, attachmentCount: computedAttachmentCount)
    let attachmentCount = persistedFeatureSidecar?.attachmentPreviews.count ?? computedAttachmentCount
    let requiredWorkDays = persistedFeatureSidecar?.requiredWorkDays ?? computedRequiredWorkDays
    let scheduledDurationMinutes =
      persistedFeatureSidecar?.scheduledDurationMinutes ?? computedScheduledDurationMinutes
    let includesExplicitTime = persistedReminderMetadata?.hasExplicitTime ?? false
    let dueDate = persistedReminderMetadata?.dueDate
    let dueDateText = dueDateText(for: dueDate, includesExplicitTime: includesExplicitTime)
    let recurrence = persistedReminderMetadata?.recurrence
    let recurrenceText = recurrence?.displayText ?? "반복 없음"
    let noteValue =
      projectedNoteLines.isEmpty
      ? "(빈 note)"
      : "\(projectedNoteLines.count)줄, 하위 task \(descendantTodoCount)개는 ➕ 앵커로 표시"

    let reminderOwnedFields = [
      OutlinerSyncField(
        key: "title",
        label: "제목",
        value: taskLine.content,
        storage: "Reminders.title",
        note: "앱 task 제목과 1:1 양방향 sync"
      ),
      OutlinerSyncField(
        key: "completion",
        label: "완료",
        value: taskLine.marker == .done ? "완료" : "미완료",
        storage: "Reminders.isCompleted",
        note: "체크 상태는 reminder 자체가 원본"
      ),
      OutlinerSyncField(
        key: "dueDate",
        label: "날짜",
        value: dueDateText,
        storage: "Reminders.dueDate",
        note: includesExplicitTime ? "시간 포함 일정으로 push" : "하루 종일 due로 push"
      ),
      OutlinerSyncField(
        key: "recurrence",
        label: "반복",
        value: recurrenceText,
        storage: "Reminders.recurrenceRule",
        note: recurrenceText == "반복 없음" ? "반복 rule 없음" : "반복 규칙 문자열로 sync"
      ),
      OutlinerSyncField(
        key: "requiredWorkDays",
        label: "예상 작업일",
        value: "\(requiredWorkDays)일",
        storage: "Reminders.alarms(relativeOffset)",
        note: "due 기준 상대 알람으로 역산"
      ),
      OutlinerSyncField(
        key: "noteBody",
        label: "노트 본문",
        value: noteValue,
        storage: "Reminders.notes body",
        note: "줄바꿈은 블록 경계, child task는 ☑t:<external-id> anchor"
      ),
    ]

    let appOwnedFields = [
      OutlinerSyncField(
        key: "scheduledDuration",
        label: "예상 소요",
        value: "\(scheduledDurationMinutes)분",
        storage: "Task.scheduledDurationMinutes",
        note: "Reminders에 대응 필드가 없어 앱이 단독 보존"
      ),
      OutlinerSyncField(
        key: "attachments",
        label: "첨부 원본",
        value: attachmentCount == 0 ? "없음" : "\(attachmentCount)개 파일 세트",
        storage: "Attachment store",
        note: "note에는 아무 메타도 남기지 않고 실물 파일과 개수는 앱 저장소가 관리"
      ),
      OutlinerSyncField(
        key: "editorState",
        label: "편집 상태",
        value: "collapse, row order, block ID",
        storage: "Outline sidecar",
        note: "drag 순서와 canonical 제목, 접힘 상태를 같이 유지"
      ),
    ]

    return OutlinerSyncContract(
      reminderOwnedFields: reminderOwnedFields,
      appOwnedFields: appOwnedFields,
      attachmentPreviews: attachmentPreviews,
      attachmentCount: attachmentCount,
      requiredWorkDays: requiredWorkDays,
      scheduledDurationMinutes: scheduledDurationMinutes,
      reminderPayload: OutlinerReminderPayload(
        dueDate: dueDate,
        hasExplicitTime: includesExplicitTime,
        recurrence: recurrence,
        priority: persistedReminderMetadata?.priority ?? 0
      )
    )
  }

  private static func dueDateText(
    for dueDate: Date?,
    includesExplicitTime: Bool
  ) -> String {
    guard let dueDate else { return "없음" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.calendar = previewCalendar
    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
    formatter.dateFormat = includesExplicitTime ? "M월 d일 a h:mm" : "M월 d일"
    return formatter.string(from: dueDate)
  }

  private static func attachmentPreviews(
    for taskLine: OutlinerLine,
    attachmentCount: Int
  ) -> [OutlinerAttachmentPreview] {
    guard attachmentCount > 0 else { return [] }

    let candidates = [
      OutlinerAttachmentPreview(
        filename: "brief-\(taskLine.index + 1).pdf",
        detail: "회의 정리 PDF"
      ),
      OutlinerAttachmentPreview(
        filename: "capture-\(taskLine.index + 1).png",
        detail: "참고 스크린샷"
      ),
      OutlinerAttachmentPreview(
        filename: "source-\(taskLine.index + 1).txt",
        detail: "원본 텍스트 메모"
      ),
    ]

    return Array(candidates.prefix(attachmentCount))
  }
}

enum OutlinerTaskAnchorCodec {
  static let marker = "➕"

  struct ParsedAnchor {
    let indentDepth: Int
    let displayedTitle: String
  }

  static func anchorLine(for line: OutlinerLine, relativeIndentDepth: Int) -> String {
    String(repeating: OutlinerDocumentParser.indentUnit, count: relativeIndentDepth)
      + marker
      + " "
      + line.content
  }

  static func parse(line: String) -> ParsedAnchor? {
    let indentDepth = line.leadingIndentDepth()
    let trimmed = line.dropLeadingIndent()
    guard trimmed.hasPrefix(marker) else { return nil }
    let displayedTitle = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return ParsedAnchor(
      indentDepth: indentDepth,
      displayedTitle: displayedTitle
    )
  }
}

private extension String {
  var utf16Length: Int {
    (self as NSString).length
  }

  func splitAtUTF16Offset(_ offset: Int) -> (String, String) {
    let nsString = self as NSString
    let clampedOffset = max(0, min(offset, nsString.length))
    return (
      nsString.substring(to: clampedOffset),
      nsString.substring(from: clampedOffset)
    )
  }

  func leadingIndentPrefix() -> String {
    var prefix = ""
    let tabScalar = Unicode.Scalar(9)!
    for scalar in unicodeScalars {
      guard scalar == tabScalar else { break }
      prefix.unicodeScalars.append(scalar)
    }
    return prefix
  }

  func leadingIndentDepth() -> Int {
    leadingIndentPrefix().count
  }

  func dropLeadingIndent() -> String {
    String(dropFirst(leadingIndentDepth()))
  }

  func dropMarkerPrefix(_ prefix: String) -> String {
    guard hasPrefix(prefix) else { return self }
    return String(dropFirst(prefix.count))
  }
}

// MARK: - Inline Formatting

enum OutlineInlineFormatter {
  private static let hangulBaselineOffset: CGFloat = -3
  private static let hangulPattern: String = "[\\u{1100}-\\u{11FF}\\u{3130}-\\u{318F}\\u{AC00}-\\u{D7A3}]"

  /// Markdown 마크업을 NSAttributedString으로 변환한다.
  static func attributedString(
    from text: String,
    fontSize: CGFloat,
    baseFont: NSFont,
    paragraphStyle: NSParagraphStyle? = nil
  ) -> NSAttributedString {
    var baseAttributes: [NSAttributedString.Key: Any] = [
      .font: baseFont,
      .foregroundColor: NSColor.textColor,
    ]
    if let paragraphStyle {
      baseAttributes[.paragraphStyle] = paragraphStyle
    }

    let result = NSMutableAttributedString(
      string: text,
      attributes: baseAttributes
    )

    applyBaselineOffset(to: result, forPattern: hangulPattern, offset: hangulBaselineOffset)

    // code: `text`
    applyPattern("`(.+?)`", to: result, fontSize: fontSize) { _, _ in
      let codeFont = baseFont.withSize(max(11, fontSize - 1))
      return [
        .font: codeFont,
        .backgroundColor: NSColor.quaternaryLabelColor,
      ]
    }

    // bold: **text**
    applyPattern("\\*\\*(.+?)\\*\\*", to: result, fontSize: fontSize) { _, _ in
      let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
      return [.font: boldFont]
    }

    // italic: *text* (단, ** 안에 포함된 것은 제외)
    applyPattern("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", to: result, fontSize: fontSize) { _, _ in
      let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
      return [.font: italicFont]
    }

    return result
  }

  private static func applyBaselineOffset(
    to attrString: NSMutableAttributedString,
    forPattern pattern: String,
    offset: CGFloat
  ) {
    guard offset != 0 else { return }
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
    let fullRange = NSRange(location: 0, length: attrString.length)

    for match in regex.matches(in: attrString.string, range: fullRange) {
      attrString.addAttribute(
        .baselineOffset,
        value: NSNumber(value: Double(offset)),
        range: match.range
      )
    }
  }

  private static func applyPattern(
    _ pattern: String,
    to attrString: NSMutableAttributedString,
    fontSize: CGFloat,
    attributes: (NSRange, String) -> [NSAttributedString.Key: Any]
  ) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
    let fullRange = NSRange(location: 0, length: attrString.length)
    let matches = regex.matches(in: attrString.string, range: fullRange)

    // 역순으로 적용하여 range가 변하지 않게
    // 주의: 마커 문자(**,*,`)도 스타일이 적용된다. 마커를 숨기려면
    // matchRange 대신 contentRange에만 적용하고 마커는 foregroundColor를 .clear로.
    // 현재 구현은 마커 포함 전체에 스타일을 건다 (Logseq 방식).
    for match in matches.reversed() {
      let matchRange = match.range
      let contentRange = match.range(at: 1)
      let content = (attrString.string as NSString).substring(with: contentRange)
      let attrs = attributes(matchRange, content)
      attrString.addAttributes(attrs, range: matchRange)
    }
  }
}

// MARK: - Metadata Badge

struct OutlineNodeBadgeData {
  var dueDate: Date?
  var hasExplicitTime: Bool
  var recurrenceText: String?
  var priority: Int

  var isEmpty: Bool {
    dueDate == nil && recurrenceText == nil && priority == 0
  }
}
