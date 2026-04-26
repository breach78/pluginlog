import Foundation

struct ObsidianProjectNote: Equatable, Sendable {
  var frontmatter: ObsidianProjectFrontmatter?
  var bodyMarkdown: String
  var tasks: [ObsidianProjectTask]
  var diagnostics: [ObsidianProjectNoteDiagnostic]
  var normalizedContentHash: String

  var reminderListExternalIdentifier: String? {
    frontmatter?.reminderListExternalIdentifier
  }

  var tags: [String] {
    frontmatter?.tags ?? []
  }

  var isProjectTagged: Bool {
    tags.contains("프로젝트")
  }

  var isSyncScopeCandidate: Bool {
    isProjectTagged || reminderListExternalIdentifier != nil
  }
}

struct ObsidianProjectFrontmatter: Equatable, Sendable {
  var tags: [String]
  var reminderListExternalIdentifier: String?
  var preservedLines: [String]
  var hideCompletedTasks: Bool = true
  var isArchived: Bool = false
}

struct ObsidianProjectTask: Equatable, Sendable {
  var bodyLineIndex: Int
  var metadataLineIndex: Int?
  var indentation: String
  var title: String
  var isCompleted: Bool
  var blockIdentifier: String?
  var metadata: ObsidianTaskMetadata?
  var rawMetadataLine: String?
  var metadataIsDamaged: Bool
  var subtreeMarkdown: String

  var reminderExternalIdentifier: String? {
    metadata?.reminderExternalIdentifier
  }
}

struct ObsidianTaskMetadata: Equatable, Sendable {
  var reminderExternalIdentifier: String?
  var date: String?
  var time: String?
  var durationMinutes: Int?
  var repeatRule: String?
}

enum ObsidianProjectNoteDiagnostic: Equatable, Sendable {
  case unclosedFrontmatter
  case damagedTaskMetadata(line: Int, rawLine: String)
}

enum ObsidianProjectNoteValidationIssue: Equatable, Sendable {
  case duplicateReminderListExternalIdentifier(String)
  case duplicateReminderExternalIdentifier(String)
  case damagedTaskMetadata(line: Int, rawLine: String)
}

enum ObsidianProjectNoteValidation {
  static func issues(in notes: [ObsidianProjectNote]) -> [ObsidianProjectNoteValidationIssue] {
    var issues: [ObsidianProjectNoteValidationIssue] = []
    var seenListIDs: Set<String> = []
    var duplicatedListIDs: Set<String> = []
    var seenTaskIDs: Set<String> = []
    var duplicatedTaskIDs: Set<String> = []

    for note in notes {
      for diagnostic in note.diagnostics {
        if case let .damagedTaskMetadata(line, rawLine) = diagnostic {
          issues.append(.damagedTaskMetadata(line: line, rawLine: rawLine))
        }
      }

      if let listID = normalized(note.reminderListExternalIdentifier),
        !seenListIDs.insert(listID).inserted,
        duplicatedListIDs.insert(listID).inserted
      {
        issues.append(.duplicateReminderListExternalIdentifier(listID))
      }

      for task in note.tasks {
        guard let taskID = normalized(task.reminderExternalIdentifier) else { continue }
        if !seenTaskIDs.insert(taskID).inserted,
          duplicatedTaskIDs.insert(taskID).inserted
        {
          issues.append(.duplicateReminderExternalIdentifier(taskID))
        }
      }
    }

    return issues
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}

enum ObsidianProjectNoteScope {
  static func isSyncScopeCandidate(
    _ note: ObsidianProjectNote,
    vaultRelativePath: String
  ) -> Bool {
    let normalizedPath = vaultRelativePath
      .replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return normalizedPath.hasPrefix("raw/projects/")
      && normalizedPath.lowercased().hasSuffix(".md")
      && note.isSyncScopeCandidate
  }
}
