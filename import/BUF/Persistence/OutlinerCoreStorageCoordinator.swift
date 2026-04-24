import Foundation
import SwiftData

struct TaskPlacementMigrationGateReport: Equatable {
  var totalRootCloneCount: Int
  var migratedRootCloneCount: Int
  var quarantinedRootCloneCount: Int
}

struct OutlinerCoreStorageMigrationReport: Equatable {
  var projectRecordCount: Int
  var taskContentCount: Int
  var taskPlacementCount: Int
  var crossProjectMirrorContentCount: Int
  var quarantinedRootCount: Int
  var taskPlacementMigrationGate: TaskPlacementMigrationGateReport
}

enum OutlinerCoreStorageCoordinator {
  private struct PlacementSeed {
    let stablePlacementKey: String
    let sourceKind: TaskPlacementSourceKind
    let contentID: UUID
    let projectID: UUID
    let parentStablePlacementKey: String?
    let rowOrder: Int
    let createdAt: Date
    let updatedAt: Date
  }

  private struct MigrationPlan {
    let placementSeeds: [PlacementSeed]
    let quarantineRecordsByContentID: [UUID: [TaskMirrorMigrationQuarantineRecord]]
    let crossProjectMirrorContentCount: Int
    let taskPlacementMigrationGate: TaskPlacementMigrationGateReport
  }

  private enum OrderedMembershipEntry {
    case primary(TaskItem)
    case clone(TaskProjectClonePlacement)

    var taskID: UUID {
      switch self {
      case .primary(let task):
        task.id
      case .clone(let placement):
        placement.taskID
      }
    }

    var projectID: UUID {
      switch self {
      case .primary(let task):
        task.project?.id ?? .nilSentinel
      case .clone(let placement):
        placement.projectID
      }
    }

    var parentTaskID: UUID? {
      switch self {
      case .primary(let task):
        task.parentTaskID
      case .clone(let placement):
        placement.parentTaskID
      }
    }

    var rowOrder: Int {
      switch self {
      case .primary(let task):
        task.rowOrder
      case .clone(let placement):
        placement.rowOrder
      }
    }

    var createdAt: Date {
      switch self {
      case .primary(let task):
        task.createdAt
      case .clone(let placement):
        placement.createdAt
      }
    }

    var updatedAt: Date {
      switch self {
      case .primary(let task):
        task.localUpdatedAt
      case .clone(let placement):
        placement.updatedAt
      }
    }

    var sourceKind: TaskPlacementSourceKind {
      switch self {
      case .primary:
        .primary
      case .clone:
        .clone
      }
    }

    var stablePlacementKey: String {
      switch self {
      case .primary(let task):
        "primary:\(task.id.uuidString)"
      case .clone(let placement):
        "clone:\(placement.id.uuidString)"
      }
    }
  }

  static func materializeCanonicalStorage(
    context: ModelContext
  ) throws -> OutlinerCoreStorageMigrationReport {
    let projects = try context.fetch(
      FetchDescriptor<Project>(
        sortBy: [SortDescriptor(\.createdAt, order: .forward)]
      )
    )
    let tasks = try context.fetch(
      FetchDescriptor<TaskItem>(
        sortBy: [
          SortDescriptor(\.rowOrder, order: .forward),
          SortDescriptor(\.createdAt, order: .forward),
        ]
      )
    )
    let clonePlacements = try context.fetch(
      FetchDescriptor<TaskProjectClonePlacement>(
        sortBy: [
          SortDescriptor(\.projectID, order: .forward),
          SortDescriptor(\.rowOrder, order: .forward),
          SortDescriptor(\.createdAt, order: .forward),
        ]
      )
    )

    let migrationPlan = buildMigrationPlan(tasks: tasks, clonePlacements: clonePlacements)

    try upsertProjectRecords(projects: projects, context: context)
    try upsertTaskContents(
      tasks: tasks,
      quarantineRecordsByContentID: migrationPlan.quarantineRecordsByContentID,
      context: context
    )
    try upsertTaskPlacements(seeds: migrationPlan.placementSeeds, context: context)

    return OutlinerCoreStorageMigrationReport(
      projectRecordCount: projects.count,
      taskContentCount: tasks.count,
      taskPlacementCount: migrationPlan.placementSeeds.count,
      crossProjectMirrorContentCount: migrationPlan.crossProjectMirrorContentCount,
      quarantinedRootCount: migrationPlan.quarantineRecordsByContentID.count,
      taskPlacementMigrationGate: migrationPlan.taskPlacementMigrationGate
    )
  }

  private static func upsertProjectRecords(
    projects: [Project],
    context: ModelContext
  ) throws {
    let existing = try context.fetch(FetchDescriptor<ProjectRecord>())
    var recordsByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
    let validIDs = Set(projects.map(\.id))

    for project in projects {
      let record =
        recordsByID[project.id]
        ?? {
          let created = ProjectRecord(
            id: project.id,
            isDirty: project.isDirty,
            isArchived: project.isArchived,
            archivedAt: project.archivedAt,
            startDate: project.startDate,
            deadline: project.deadline,
            noteMarkdown: project.projectNoteMarkdown,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
          )
          context.insert(created)
          recordsByID[project.id] = created
          return created
        }()

      record.applyCanonicalIdentity(
        title: project.title,
        colorHex: project.colorHex,
        reminderListIdentifier: project.calendarIdentifier,
        reminderListExternalIdentifier: project.calendarExternalIdentifier
      )
    }

    for stale in existing where !validIDs.contains(stale.id) {
      context.delete(stale)
    }
  }

  private static func upsertTaskContents(
    tasks: [TaskItem],
    quarantineRecordsByContentID: [UUID: [TaskMirrorMigrationQuarantineRecord]],
    context: ModelContext
  ) throws {
    let existing = try context.fetch(FetchDescriptor<TaskContent>())
    var contentsByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
    let validIDs = Set(tasks.map(\.id))
    let orderedChildIDsByParent = orderedChildContentIDsByParent(tasks: tasks)

    for task in tasks {
      let content =
        contentsByID[task.id]
        ?? {
          let created = TaskContent(id: task.id, title: task.title, createdAt: task.createdAt)
          context.insert(created)
          contentsByID[task.id] = created
          return created
        }()

      content.title = task.title
      content.childContentIDs = orderedChildIDsByParent[task.id] ?? []
      content.reminderIdentifier = task.reminderIdentifier
      content.reminderExternalIdentifier = task.reminderExternalIdentifier
      content.reminderOwnerProjectID = task.project?.id
      content.reminderOwnerCalendarID = task.project?.calendarIdentifier
      content.parentTaskRemoteExternalIdentifier = task.parentTaskRemoteExternalIdentifier
      content.isCompleted = task.isCompleted
      content.completionDate = task.completionDate
      content.startDate = task.startDate
      content.dueDate = task.dueDate
      content.scheduleHasExplicitTime = task.scheduleHasExplicitTime
      content.scheduledDurationMinutes = task.scheduledDurationMinutes
      content.priority = task.priority
      content.recurrenceRuleRaw = task.recurrenceRuleRaw
      content.isFlagged = task.isFlagged
      content.reminderNoteText = task.reminderNoteText
      content.reminderRawPayloadRaw = task.reminderRawPayloadRaw
      content.attachmentCount = task.attachmentCount
      content.lastSyncedReminderTitle = task.lastSyncedReminderTitle
      content.lastSyncedReminderNoteBody = task.lastSyncedReminderNoteBody
      content.lastSyncedReminderModifiedAt = task.lastSyncedReminderModifiedAt
      content.reminderNoteConflictExcerpt = task.reminderNoteConflictExcerpt
      content.requiredWorkDays = task.requiredWorkDays
      content.completedWorkUnits = task.completedWorkUnits
      content.completedWorkUnitDatesRaw = task.completedWorkUnitDatesRaw
      content.preparationScheduleOverridesRaw = task.preparationScheduleOverridesRaw
      content.mirrorQuarantineRecords = quarantineRecordsByContentID[task.id] ?? []
      content.isDirty = task.isDirty
      content.remoteLastModifiedAt = task.remoteLastModifiedAt
      content.localUpdatedAt = task.localUpdatedAt
      content.createdAt = task.createdAt
    }

    for stale in existing where !validIDs.contains(stale.id) {
      context.delete(stale)
    }
  }

  private static func upsertTaskPlacements(
    seeds: [PlacementSeed],
    context: ModelContext
  ) throws {
    let existing = try context.fetch(FetchDescriptor<TaskPlacement>())
    var placementsByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.stablePlacementKey, $0) })
    var placementIDsByStableKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.stablePlacementKey, $0.id) })
    let validKeys = Set(seeds.map(\.stablePlacementKey))

    for seed in seeds {
      let placement =
        placementsByKey[seed.stablePlacementKey]
        ?? {
          let created = TaskPlacement(
            stablePlacementKey: seed.stablePlacementKey,
            sourceKindRaw: seed.sourceKind.rawValue,
            contentID: seed.contentID,
            projectID: seed.projectID,
            createdAt: seed.createdAt
          )
          context.insert(created)
          placementsByKey[seed.stablePlacementKey] = created
          placementIDsByStableKey[seed.stablePlacementKey] = created.id
          return created
        }()

      placement.sourceKind = seed.sourceKind
      placement.contentID = seed.contentID
      placement.projectID = seed.projectID
      placement.parentPlacementID = nil
      placement.rowOrder = seed.rowOrder
      placement.isCollapsed = false
      placement.createdAt = seed.createdAt
      placement.updatedAt = seed.updatedAt
      placementIDsByStableKey[seed.stablePlacementKey] = placement.id
    }

    for seed in seeds {
      guard
        let parentStablePlacementKey = seed.parentStablePlacementKey,
        let placement = placementsByKey[seed.stablePlacementKey],
        let parentPlacementID = placementIDsByStableKey[parentStablePlacementKey]
      else { continue }

      placement.parentPlacementID = parentPlacementID
    }

    for stale in existing where !validKeys.contains(stale.stablePlacementKey) {
      context.delete(stale)
    }
  }

  private static func buildMigrationPlan(
    tasks: [TaskItem],
    clonePlacements: [TaskProjectClonePlacement]
  ) -> MigrationPlan {
    let orderedTasks = tasks.sorted(by: stableTaskOrder(_:_:))
    let tasksByID = Dictionary(uniqueKeysWithValues: orderedTasks.map { ($0.id, $0) })
    let canonicalChildrenByParent = Dictionary(grouping: orderedTasks) { task in
      task.parentTaskID ?? .nilSentinel
    }
    let totalRootCloneCount = clonePlacements.filter { $0.parentTaskID == nil }.count
    let projectIDs = Set(orderedTasks.compactMap { $0.project?.id }).union(clonePlacements.map(\.projectID))

    var placementSeeds: [PlacementSeed] = []
    var quarantineRecordsByContentID: [UUID: [TaskMirrorMigrationQuarantineRecord]] = [:]
    var quarantinedRootCloneCount = 0
    var migratedRootCloneCount = 0

    for projectID in projectIDs.sorted(by: stableUUIDOrder(_:_:)) {
      let duplicateMembershipTaskIDs = duplicateMembershipTaskIDs(
        projectID: projectID,
        tasks: orderedTasks,
        clonePlacements: clonePlacements
      )
      let rootEntries = orderedRootEntries(
        projectID: projectID,
        tasks: orderedTasks,
        clonePlacements: clonePlacements
      )
      var seenSeeds: Set<String> = []

      func appendSubtree(
        _ node: OrderedMembershipEntry,
        parentPlacementKey: String?
      ) {
        let seed = placementSeed(from: node, parentStablePlacementKey: parentPlacementKey)
        if !seenSeeds.insert(seed.stablePlacementKey).inserted { return }
        placementSeeds.append(seed)

        let childEntries = orderedEntries(
          projectID: projectID,
          parentTaskID: node.taskID,
          tasks: tasks,
          clonePlacements: clonePlacements
        )
        for child in childEntries {
          appendSubtree(child, parentPlacementKey: seed.stablePlacementKey)
        }
      }

      for entry in rootEntries {
        switch entry {
        case .primary:
          appendSubtree(entry, parentPlacementKey: nil)
        case .clone(let placement):
          if let reason = mirrorMigrationDriftReason(
            for: placement,
            projectID: projectID,
            tasks: orderedTasks,
            tasksByID: tasksByID,
            clonePlacements: clonePlacements,
            canonicalChildrenByParent: canonicalChildrenByParent,
            duplicateMembershipTaskIDs: duplicateMembershipTaskIDs
          ) {
            quarantineRecordsByContentID[placement.taskID, default: []].append(
              TaskMirrorMigrationQuarantineRecord(projectID: projectID, reason: reason)
            )
            quarantinedRootCloneCount += 1
            continue
          }
          migratedRootCloneCount += 1
          appendSubtree(entry, parentPlacementKey: nil)
        }
      }
    }

    var visibleProjectsByContentID: [UUID: Set<UUID>] = [:]
    for seed in placementSeeds {
      let subtree = canonicalSubtreeTaskIDs(
        rootTaskID: seed.contentID,
        canonicalChildrenByParent: canonicalChildrenByParent
      )
      guard !subtree.hasCycle else { continue }
      for taskID in subtree.taskIDs {
        visibleProjectsByContentID[taskID, default: []].insert(seed.projectID)
      }
    }

    let crossProjectMirrorContentCount = visibleProjectsByContentID.values.filter { $0.count > 1 }.count
    let taskPlacementMigrationGate = TaskPlacementMigrationGateReport(
      totalRootCloneCount: totalRootCloneCount,
      migratedRootCloneCount: migratedRootCloneCount,
      quarantinedRootCloneCount: quarantinedRootCloneCount
    )

    return MigrationPlan(
      placementSeeds: placementSeeds.sorted(by: placementSeedComparator(_:_:)),
      quarantineRecordsByContentID: quarantineRecordsByContentID.mapValues { records in
        Array(Set(records)).sorted { lhs, rhs in
          if lhs.projectID == rhs.projectID {
            return lhs.reason < rhs.reason
          }
          return lhs.projectID.uuidString < rhs.projectID.uuidString
        }
      },
      crossProjectMirrorContentCount: crossProjectMirrorContentCount,
      taskPlacementMigrationGate: taskPlacementMigrationGate
    )
  }

  private static func placementSeed(
    from entry: OrderedMembershipEntry,
    parentStablePlacementKey: String? = nil
  ) -> PlacementSeed {
    PlacementSeed(
      stablePlacementKey: entry.stablePlacementKey,
      sourceKind: entry.sourceKind,
      contentID: entry.taskID,
      projectID: entry.projectID,
      parentStablePlacementKey: parentStablePlacementKey,
      rowOrder: entry.rowOrder,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt
    )
  }

  private static func mirrorMigrationDriftReason(
    for rootPlacement: TaskProjectClonePlacement,
    projectID: UUID,
    tasks: [TaskItem],
    tasksByID: [UUID: TaskItem],
    clonePlacements: [TaskProjectClonePlacement],
    canonicalChildrenByParent: [UUID: [TaskItem]],
    duplicateMembershipTaskIDs: Set<UUID>
  ) -> String? {
    guard rootPlacement.parentTaskID == nil else {
      return "orphaned clone root lost its mirrored ancestor"
    }

    guard tasksByID[rootPlacement.taskID] != nil else {
      return "missing shared content record for mirrored root"
    }

    if duplicateMembershipTaskIDs.contains(rootPlacement.taskID) {
      return "duplicate memberships for mirrored root content"
    }

    let canonicalSubtree = canonicalSubtreeTaskIDs(
      rootTaskID: rootPlacement.taskID,
      canonicalChildrenByParent: canonicalChildrenByParent
    )
    if canonicalSubtree.hasCycle {
      return "canonical subtree contains a cycle"
    }

    let canonicalTaskIDs = canonicalSubtree.taskIDs
    let visibleMembershipTaskIDs = visibleTaskTreeTaskIDs(
      rootTaskID: rootPlacement.taskID,
      projectID: projectID,
      tasks: tasks,
      clonePlacements: clonePlacements
    )

    if firstDuplicate(in: visibleMembershipTaskIDs) != nil {
      return "duplicate memberships appeared inside mirrored subtree"
    }

    let visibleMembershipTaskIDSet = Set(visibleMembershipTaskIDs)
    let canonicalTaskIDSet = Set(canonicalTaskIDs)
    if visibleMembershipTaskIDSet != canonicalTaskIDSet {
      let missingCount = canonicalTaskIDSet.subtracting(visibleMembershipTaskIDSet).count
      let extraCount = visibleMembershipTaskIDSet.subtracting(canonicalTaskIDSet).count
      return "content drift detected (missing: \(missingCount), extra: \(extraCount))"
    }

    for taskID in canonicalTaskIDs {
      if duplicateMembershipTaskIDs.contains(taskID) {
        return "duplicate memberships appeared inside mirrored subtree"
      }

      guard let visibleMembershipEntry = membershipEntry(
        taskID: taskID,
        projectID: projectID,
        tasks: tasks,
        clonePlacements: clonePlacements
      ) else {
        return "missing membership for mirrored content descendant"
      }

      let expectedParentTaskID = taskID == rootPlacement.taskID ? nil : tasksByID[taskID]?.parentTaskID
      if visibleMembershipEntry.parentTaskID != expectedParentTaskID {
        return "parent linkage drift detected inside mirrored subtree"
      }
    }

    for parentTaskID in canonicalTaskIDs {
      let expectedChildIDs = (canonicalChildrenByParent[parentTaskID] ?? []).map(\.id)
      let visibleChildIDs = orderedEntries(
        projectID: projectID,
        parentTaskID: parentTaskID,
        tasks: tasks,
        clonePlacements: clonePlacements
      )
      .map(\.taskID)
      .filter { canonicalTaskIDSet.contains($0) }

      if visibleChildIDs != expectedChildIDs {
        return "row-order drift detected inside mirrored subtree"
      }
    }

    return nil
  }

  private static func orderedChildContentIDsByParent(tasks: [TaskItem]) -> [UUID: [UUID]] {
    let orderedTasks = tasks.sorted(by: stableTaskOrder(_:_:))

    return Dictionary(grouping: orderedTasks) { task in
      task.parentTaskID ?? .nilSentinel
    }
    .reduce(into: [:]) { result, entry in
      guard entry.key != .nilSentinel else { return }
      result[entry.key] = entry.value.map(\.id)
    }
  }

  private static func visibleTaskTreeTaskIDs(
    rootTaskID: UUID,
    projectID: UUID,
    tasks: [TaskItem],
    clonePlacements: [TaskProjectClonePlacement]
  ) -> [UUID] {
    guard membershipEntry(
      taskID: rootTaskID,
      projectID: projectID,
      tasks: tasks,
      clonePlacements: clonePlacements
    ) != nil else {
      return []
    }

    var taskIDs: [UUID] = []
    var visited: Set<UUID> = []

    func appendTree(_ taskID: UUID) {
      guard visited.insert(taskID).inserted else { return }
      taskIDs.append(taskID)
      let childEntries = orderedEntries(
        projectID: projectID,
        parentTaskID: taskID,
        tasks: tasks,
        clonePlacements: clonePlacements
      )
      for childEntry in childEntries {
        appendTree(childEntry.taskID)
      }
    }

    appendTree(rootTaskID)
    return taskIDs
  }

  private static func orderedRootEntries(
    projectID: UUID,
    tasks: [TaskItem],
    clonePlacements: [TaskProjectClonePlacement]
  ) -> [OrderedMembershipEntry] {
    let membershipTaskIDs = membershipTaskIDs(
      projectID: projectID,
      tasks: tasks,
      clonePlacements: clonePlacements
    )

    return membershipEntries(
      projectID: projectID,
      tasks: tasks,
      clonePlacements: clonePlacements
    )
    .filter { entry in
      guard let parentTaskID = entry.parentTaskID else { return true }
      return !membershipTaskIDs.contains(parentTaskID)
    }
    .sorted(by: orderedMembershipEntryComparator(_:_:))
  }

  private static func orderedEntries(
    projectID: UUID,
    parentTaskID: UUID?,
    tasks: [TaskItem],
    clonePlacements: [TaskProjectClonePlacement]
  ) -> [OrderedMembershipEntry] {
    membershipEntries(
      projectID: projectID,
      tasks: tasks,
      clonePlacements: clonePlacements
    )
    .filter { $0.parentTaskID == parentTaskID }
    .sorted(by: orderedMembershipEntryComparator(_:_:))
  }

  private static func membershipEntry(
    taskID: UUID,
    projectID: UUID,
    tasks: [TaskItem],
    clonePlacements: [TaskProjectClonePlacement]
  ) -> OrderedMembershipEntry? {
    if let task = tasks.first(where: { $0.id == taskID && $0.project?.id == projectID }) {
      return .primary(task)
    }
    if let placement = clonePlacements.first(where: { $0.taskID == taskID && $0.projectID == projectID }) {
      return .clone(placement)
    }
    return nil
  }

  private static func membershipEntries(
    projectID: UUID,
    tasks: [TaskItem],
    clonePlacements: [TaskProjectClonePlacement]
  ) -> [OrderedMembershipEntry] {
    let primaryEntries = tasks
      .filter { $0.project?.id == projectID }
      .map(OrderedMembershipEntry.primary)
    let cloneEntries = clonePlacements
      .filter { $0.projectID == projectID }
      .map(OrderedMembershipEntry.clone)
    return primaryEntries + cloneEntries
  }

  private static func membershipTaskIDs(
    projectID: UUID,
    tasks: [TaskItem],
    clonePlacements: [TaskProjectClonePlacement]
  ) -> Set<UUID> {
    var taskIDs = Set(tasks.filter { $0.project?.id == projectID }.map(\.id))
    taskIDs.formUnion(clonePlacements.filter { $0.projectID == projectID }.map(\.taskID))
    return taskIDs
  }

  private static func duplicateMembershipTaskIDs(
    projectID: UUID,
    tasks: [TaskItem],
    clonePlacements: [TaskProjectClonePlacement]
  ) -> Set<UUID> {
    let membershipIDs = membershipEntries(
      projectID: projectID,
      tasks: tasks,
      clonePlacements: clonePlacements
    )
    .map(\.taskID)

    var seen: Set<UUID> = []
    var duplicates: Set<UUID> = []
    for taskID in membershipIDs {
      if !seen.insert(taskID).inserted {
        duplicates.insert(taskID)
      }
    }
    return duplicates
  }

  private static func canonicalSubtreeTaskIDs(
    rootTaskID: UUID,
    canonicalChildrenByParent: [UUID: [TaskItem]]
  ) -> (taskIDs: [UUID], hasCycle: Bool) {
    var result: [UUID] = []
    var visited: Set<UUID> = []
    var activePath: Set<UUID> = []
    var detectedCycle = false

    func append(_ taskID: UUID) {
      guard !detectedCycle else { return }
      if activePath.contains(taskID) {
        detectedCycle = true
        return
      }
      guard visited.insert(taskID).inserted else { return }

      activePath.insert(taskID)
      result.append(taskID)

      for child in canonicalChildrenByParent[taskID] ?? [] {
        append(child.id)
      }

      activePath.remove(taskID)
    }

    append(rootTaskID)
    return (result, detectedCycle)
  }

  private static func firstDuplicate<T: Hashable>(in values: [T]) -> T? {
    var seen: Set<T> = []
    for value in values where !seen.insert(value).inserted {
      return value
    }
    return nil
  }

  private static func stableTaskOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
    if lhs.rowOrder != rhs.rowOrder {
      return lhs.rowOrder < rhs.rowOrder
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private static func orderedMembershipEntryComparator(_ lhs: OrderedMembershipEntry, _ rhs: OrderedMembershipEntry) -> Bool {
    if lhs.rowOrder != rhs.rowOrder {
      return lhs.rowOrder < rhs.rowOrder
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.taskID.uuidString < rhs.taskID.uuidString
  }

  private static func placementSeedComparator(_ lhs: PlacementSeed, _ rhs: PlacementSeed) -> Bool {
    if lhs.projectID != rhs.projectID {
      return lhs.projectID.uuidString < rhs.projectID.uuidString
    }
    if lhs.rowOrder != rhs.rowOrder {
      return lhs.rowOrder < rhs.rowOrder
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.stablePlacementKey < rhs.stablePlacementKey
  }

  private static func stableUUIDOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
  }
}

private extension UUID {
  static let nilSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
