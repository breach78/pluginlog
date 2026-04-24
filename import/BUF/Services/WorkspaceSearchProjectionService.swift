import Foundation

struct WorkspaceSearchIndexCandidate: Equatable {
  let kind: WorkspaceSearchMatchKind
  let fieldText: String
  let preview: String
}

struct WorkspaceSearchIndexEntry: Equatable {
  let id: String
  let entityKind: WorkspaceSearchEntityKind
  let disposition: WorkspaceSearchResultDisposition
  let projectID: UUID
  let taskID: UUID?
  let title: String
  let subtitlePrefix: String
  let candidates: [WorkspaceSearchIndexCandidate]
  let corpus: String
  let isExcludedFromSearch: Bool
}

enum WorkspaceSearchProjectionService {
  static func runtimeIndex(
    snapshot: OutlineProjectionRuntimeSnapshot,
    descriptors: [WorkspaceProjectDescriptor],
    breadcrumbTextByProjectID: [UUID: String] = [:]
  ) -> [WorkspaceSearchIndexEntry] {
    let projectsByID = Dictionary(
      uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) }
    )
    let descriptorsByID = Dictionary(
      uniqueKeysWithValues: descriptors.map { ($0.id, $0) }
    )

    return normalizedProjectIDs(descriptors.map(\.id)).flatMap { projectID in
      guard let descriptor = descriptorsByID[projectID],
            let project = projectsByID[projectID]
      else {
        return [WorkspaceSearchIndexEntry]()
      }

      let breadcrumbText = breadcrumbTextByProjectID[projectID]?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      var projectCandidates = [
        WorkspaceSearchIndexCandidate(
          kind: .projectTitle,
          fieldText: descriptor.title,
          preview: descriptor.title
        ),
      ]
      if !breadcrumbText.isEmpty {
        projectCandidates.append(
          WorkspaceSearchIndexCandidate(
            kind: .projectNote,
            fieldText: breadcrumbText,
            preview: breadcrumbText
          )
        )
      }

      let projectEntry = WorkspaceSearchIndexEntry(
        id: "workspace-project-\(projectID.uuidString)",
        entityKind: .project,
        disposition: descriptor.isArchived ? .archivedProject : .regular,
        projectID: projectID,
        taskID: nil,
        title: descriptor.title,
        subtitlePrefix: descriptor.title,
        candidates: projectCandidates,
        corpus: [descriptor.title, breadcrumbText]
          .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
          .joined(separator: "\n"),
        isExcludedFromSearch: false
      )

      let taskEntries = project.document.flatten().compactMap { entry -> WorkspaceSearchIndexEntry? in
        guard entry.node.type.isTask else { return nil }
        let taskTitle = entry.node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = taskTitle.isEmpty ? "제목 없는 할일" : entry.node.text
        let reminderNoteText = ReminderNoteSourceMutationService.plan(
          for: entry.node,
          reminderExternalIdentifierResolver: { $0.reminderExternalIdentifier }
        ).normalizedNoteText
        let taskCandidates = [
          WorkspaceSearchIndexCandidate(kind: .taskTitle, fieldText: taskTitle, preview: displayTitle),
          WorkspaceSearchIndexCandidate(
            kind: .taskReminderNote,
            fieldText: reminderNoteText,
            preview: reminderNoteText
          ),
        ]

        return WorkspaceSearchIndexEntry(
          id: "workspace-task-\(entry.node.canonicalID.uuidString)",
          entityKind: .task,
          disposition: entry.node.type.isCompleted ? .completedTask : .regular,
          projectID: projectID,
          taskID: entry.node.canonicalID,
          title: displayTitle,
          subtitlePrefix: taskSubtitlePrefix(
            projectTitle: descriptor.title,
            nodeID: entry.id,
            document: project.document
          ),
          candidates: taskCandidates,
          corpus: [taskTitle, reminderNoteText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n"),
          isExcludedFromSearch: entry.node.type.isCompleted
            && snapshot.reminderMetadata(for: entry.node)?.recurrence != nil
        )
      }

      return [projectEntry] + taskEntries
    }
  }

  static func canonicalIndex(
    projectIDs: [UUID],
    searchEntriesByProjectID: [UUID: [SearchCorpusEntry]],
    breadcrumbTextByProjectID: [UUID: String] = [:]
  ) -> [WorkspaceSearchIndexEntry] {
    normalizedProjectIDs(projectIDs).flatMap { projectID in
      let breadcrumbText = breadcrumbTextByProjectID[projectID]?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      let breadcrumbCandidate = breadcrumbText.flatMap { text -> WorkspaceSearchIndexCandidate? in
        guard !text.isEmpty else { return nil }
        return WorkspaceSearchIndexCandidate(kind: .projectNote, fieldText: text, preview: text)
      }

      return (searchEntriesByProjectID[projectID] ?? []).map { entry in
        var candidates = entry.candidates.map {
          WorkspaceSearchIndexCandidate(kind: $0.kind, fieldText: $0.fieldText, preview: $0.preview)
        }
        var corpus = entry.corpus
        var subtitlePrefix = entry.subtitlePrefix

        if entry.entityKind == .project, let breadcrumbCandidate {
          candidates.append(breadcrumbCandidate)
          corpus = [entry.corpus, breadcrumbCandidate.fieldText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
          subtitlePrefix = breadcrumbCandidate.fieldText.isEmpty
            ? entry.subtitlePrefix
            : "\(breadcrumbCandidate.fieldText) / \(entry.title)"
        }

        return WorkspaceSearchIndexEntry(
          id: entry.id,
          entityKind: entry.entityKind,
          disposition: entry.disposition,
          projectID: entry.projectID,
          taskID: entry.taskID,
          title: entry.title,
          subtitlePrefix: subtitlePrefix,
          candidates: candidates,
          corpus: corpus,
          isExcludedFromSearch: entry.isExcludedFromSearch
        )
      }
    }
  }

  private static func normalizedProjectIDs(_ projectIDs: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    return projectIDs.filter { seen.insert($0).inserted }
  }

  private static func taskSubtitlePrefix(
    projectTitle: String,
    nodeID: UUID,
    document: OutlineDocument
  ) -> String {
    var ancestorTitles: [String] = []
    var currentParentID = OutlineNodeTreeNavigator.parentOf(id: nodeID, in: document.rootNodes)

    while let parentID = currentParentID,
          let parentNode = OutlineNodeTreeNavigator.findNode(id: parentID, in: document.rootNodes)
    {
      let trimmedText = parentNode.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedText.isEmpty {
        ancestorTitles.append(trimmedText)
      }
      currentParentID = OutlineNodeTreeNavigator.parentOf(id: parentID, in: document.rootNodes)
    }

    return ([projectTitle] + ancestorTitles.reversed()).joined(separator: " / ")
  }
}
