import Foundation

enum ProjectListSortPresentationContext {
  case sidebar
  case timeline
}

enum ProjectListSortMode: String, Codable {
  case manual
  case recentlyModified
  case bucketGrouped
  case priority

  private var normalizedWorkspaceMode: ProjectListSortMode {
    switch self {
    case .bucketGrouped:
      return .priority
    default:
      return self
    }
  }

  var nextSidebar: ProjectListSortMode {
    switch normalizedWorkspaceMode {
    case .manual:
      return .recentlyModified
    case .recentlyModified:
      return .priority
    case .priority, .bucketGrouped:
      return .manual
    }
  }

  var nextTimeline: ProjectListSortMode {
    nextSidebar
  }

  var indicatorIconName: String? {
    switch normalizedWorkspaceMode {
    case .manual:
      return nil
    case .recentlyModified:
      return "clock"
    case .bucketGrouped, .priority:
      return "square.grid.2x2.fill"
    }
  }

  var allowsInteractiveReordering: Bool {
    normalizedWorkspaceMode != .recentlyModified
  }

  func helpText(in _: ProjectListSortPresentationContext) -> String {
    switch normalizedWorkspaceMode {
    case .manual:
      return "클릭하면 최근 수정 순으로 정렬합니다."
    case .recentlyModified:
      return "클릭하면 DO / DECIDE / DELEGATE / Area / DELETE 순의 DO 강조 우선순위 모드로 전환합니다."
    case .bucketGrouped, .priority:
      return "클릭하면 현재 수동 순서로 돌아갑니다."
    }
  }

  static func resolved(
    storedRawValue: String?,
    defaults: UserDefaults = .standard,
    primaryKey: String
  ) -> ProjectListSortMode {
    return (ProjectListSortMode(rawValue: storedRawValue ?? "") ?? .manual).normalizedWorkspaceMode
  }
}

enum ProjectOrdering {
  private static let defaultBucketSequence: [ProjectProgressStage] = [
    .do,
    .decide,
    .delegate,
    .area,
    .delete,
  ]
  private static let timelineBucketSequence = defaultBucketSequence

  static func ordered(
    _ descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode
  ) -> [WorkspaceProjectDescriptor] {
    ordered(
      descriptors,
      mode: mode,
      bucketSequence: defaultBucketSequence
    )
  }

  static func orderedForTimeline(
    _ descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode
  ) -> [WorkspaceProjectDescriptor] {
    ordered(
      descriptors,
      mode: mode,
      bucketSequence: timelineBucketSequence
    )
  }

  private static func ordered(
    _ descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode,
    bucketSequence: [ProjectProgressStage]
  ) -> [WorkspaceProjectDescriptor] {
    switch mode {
    case .manual:
      return descriptors.sorted(by: manualComparator)
    case .recentlyModified:
      return descriptors.sorted { lhs, rhs in
        let leftDate = latestActivityDate(for: lhs)
        let rightDate = latestActivityDate(for: rhs)
        if leftDate != rightDate {
          return leftDate > rightDate
        }
        return manualComparator(lhs, rhs)
      }
    case .bucketGrouped, .priority:
      let stageRanks = Dictionary(
        uniqueKeysWithValues: bucketSequence.enumerated().map { ($1, $0) }
      )
      return descriptors.sorted { lhs, rhs in
        let lhsStage = bucketStage(for: lhs)
        let rhsStage = bucketStage(for: rhs)
        let lhsRank = stageRanks[lhsStage] ?? Int.max
        let rhsRank = stageRanks[rhsStage] ?? Int.max
        if lhsRank != rhsRank {
          return lhsRank < rhsRank
        }

        let lhsOrder = groupedBoardOrder(for: lhs)
        let rhsOrder = groupedBoardOrder(for: rhs)
        if lhsOrder != rhsOrder {
          return lhsOrder < rhsOrder
        }

        return manualComparator(lhs, rhs)
      }
    }
  }

  static func allowsInteractiveReordering(in mode: ProjectListSortMode) -> Bool {
    mode.allowsInteractiveReordering
  }

  static func bucketStage(for descriptor: WorkspaceProjectDescriptor) -> ProjectProgressStage {
    descriptor.stage
  }

  static func groupedBoardOrder(for descriptor: WorkspaceProjectDescriptor) -> Int {
    descriptor.boardOrder ?? manualOrder(for: descriptor)
  }

  static func reorderedBucketProjects(
    from visibleProjects: [WorkspaceProjectDescriptor],
    moving source: IndexSet,
    to destination: Int
  ) -> [WorkspaceProjectDescriptor]? {
    guard let firstSourceIndex = source.first, visibleProjects.indices.contains(firstSourceIndex) else {
      return nil
    }

    let targetStage = bucketStage(for: visibleProjects[firstSourceIndex])
    let movedProjects = source.compactMap { index in
      visibleProjects.indices.contains(index) ? visibleProjects[index] : nil
    }
    guard !movedProjects.isEmpty else {
      return nil
    }
    guard movedProjects.allSatisfy({ bucketStage(for: $0) == targetStage }) else {
      return nil
    }

    let reordered = reorderedProjects(from: visibleProjects, moving: source, to: destination)
    return reordered.filter { bucketStage(for: $0) == targetStage }
  }

  static func reorderedBucketProjects(
    from visibleProjects: [WorkspaceProjectDescriptor],
    draggedID: UUID,
    targetID: UUID,
    placementAfter: Bool
  ) -> [WorkspaceProjectDescriptor]? {
    var reordered = visibleProjects
    guard
      let sourceIndex = reordered.firstIndex(where: { $0.id == draggedID }),
      let targetIndex = reordered.firstIndex(where: { $0.id == targetID })
    else {
      return nil
    }

    let targetStage = bucketStage(for: reordered[sourceIndex])
    let draggedProject = reordered.remove(at: sourceIndex)
    var adjustedTargetIndex = targetIndex
    if sourceIndex < adjustedTargetIndex {
      adjustedTargetIndex -= 1
    }
    let rawInsertionIndex = placementAfter ? adjustedTargetIndex + 1 : adjustedTargetIndex
    let insertionIndex = min(max(0, rawInsertionIndex), reordered.count)
    reordered.insert(draggedProject, at: insertionIndex)
    return reordered.filter { bucketStage(for: $0) == targetStage }
  }

  static func latestActivityDate(for descriptor: WorkspaceProjectDescriptor) -> Date {
    descriptor.latestActivityAt
  }

  private static func manualComparator(
    _ lhs: WorkspaceProjectDescriptor,
    _ rhs: WorkspaceProjectDescriptor
  ) -> Bool {
    let lhsOrder = manualOrder(for: lhs)
    let rhsOrder = manualOrder(for: rhs)
    if lhsOrder != rhsOrder {
      return lhsOrder < rhsOrder
    }

    let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
    if titleComparison != .orderedSame {
      return titleComparison == .orderedAscending
    }

    return lhs.id.uuidString < rhs.id.uuidString
  }

  private static func reorderedProjects(
    from projects: [WorkspaceProjectDescriptor],
    moving source: IndexSet,
    to destination: Int
  ) -> [WorkspaceProjectDescriptor] {
    let movingProjects = source.sorted().compactMap { index in
      projects.indices.contains(index) ? projects[index] : nil
    }
    let sourceSet = Set(source)
    var remaining: [WorkspaceProjectDescriptor] = []
    remaining.reserveCapacity(projects.count - movingProjects.count)

    for (index, project) in projects.enumerated() where !sourceSet.contains(index) {
      remaining.append(project)
    }

    let removalCountBeforeDestination = source.filter { $0 < destination }.count
    let adjustedDestination = min(
      max(0, destination - removalCountBeforeDestination),
      remaining.count
    )
    remaining.insert(contentsOf: movingProjects, at: adjustedDestination)
    return remaining
  }

  private static func manualOrder(for descriptor: WorkspaceProjectDescriptor) -> Int {
    Int(descriptor.workspaceSortKey ?? Int64.max)
  }
}

enum ProjectOrderMutationService {
  static func captureManualSortOrders(projectIDs: [UUID]) -> [UUID: Int] {
    let identifiers = Array(NSOrderedSet(array: projectIDs)) as? [UUID] ?? projectIDs
    return Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { ($1, $0) })
  }

  static func orderedProjectIDs(from snapshot: [UUID: Int]) -> [UUID] {
    snapshot.keys.sorted { lhs, rhs in
      let lhsOrder = snapshot[lhs] ?? Int.max
      let rhsOrder = snapshot[rhs] ?? Int.max
      if lhsOrder != rhsOrder {
        return lhsOrder < rhsOrder
      }
      return lhs.uuidString < rhs.uuidString
    }
  }
}
