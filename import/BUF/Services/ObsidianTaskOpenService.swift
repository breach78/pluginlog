import Foundation

enum ObsidianTaskOpenServiceError: LocalizedError, Equatable {
  case vaultNotConfigured
  case invalidOpenURL
  case projectNotFound(UUID)
  case taskNotFound(UUID)
  case duplicateReminderListExternalIdentifier(String)
  case duplicateReminderExternalIdentifier(String)
  case damagedTaskMetadata(line: Int, rawLine: String)

  var errorDescription: String? {
    switch self {
    case .vaultNotConfigured:
      return "Obsidian vault가 설정되지 않았습니다."
    case .invalidOpenURL:
      return "Obsidian 열기 링크를 만들지 못했습니다."
    case .projectNotFound(let projectID):
      return "Obsidian 프로젝트 노트를 찾지 못했습니다. \(projectID.uuidString)"
    case .taskNotFound(let taskID):
      return "Obsidian 프로젝트 노트에서 할일을 찾지 못했습니다. \(taskID.uuidString)"
    case .duplicateReminderListExternalIdentifier(let identifier):
      return "중복된 reminder_list_external_id가 발견되었습니다. \(identifier)"
    case .duplicateReminderExternalIdentifier(let identifier):
      return "중복된 reminder_external_id가 발견되었습니다. \(identifier)"
    case .damagedTaskMetadata(_, let rawLine):
      return "손상된 Obsidian task metadata가 발견되었습니다. \(rawLine)"
    }
  }
}

enum ObsidianDeepLinking {
  static let taskFocusAction = "brain-unfog-focus-task"

  static func projectNoteURL(fileURL: URL) throws -> URL {
    var components = URLComponents()
    components.scheme = "obsidian"
    components.host = "open"
    components.percentEncodedQuery = encodedQuery([
      ("path", fileURL.standardizedFileURL.path)
    ])
    guard let url = components.url else {
      throw ObsidianTaskOpenServiceError.invalidOpenURL
    }
    return url
  }

  static func taskBlockURL(
    fileURL: URL,
    blockIdentifier: String
  ) throws -> URL {
    let fileTarget = fileURL.standardizedFileURL.path + "#" + normalizedBlockIdentifier(blockIdentifier)
    var components = URLComponents()
    components.scheme = "obsidian"
    components.host = "open"
    components.percentEncodedQuery = encodedQuery([
      ("path", fileTarget),
    ])
    guard let url = components.url else {
      throw ObsidianTaskOpenServiceError.invalidOpenURL
    }
    return url
  }

  static func taskFocusURL(
    vaultRootURL: URL,
    fileURL: URL,
    blockIdentifier: String?,
    reminderExternalIdentifier: String
  ) throws -> URL {
    var queryItems = [
      ("path", fileURL.standardizedFileURL.path),
      ("file", vaultRelativePath(fileURL: fileURL, vaultRootURL: vaultRootURL)),
      ("reminder_external_id", reminderExternalIdentifier),
    ]
    if let blockIdentifier = normalized(blockIdentifier) {
      queryItems.append(("block", normalizedBlockIdentifier(blockIdentifier)))
    }

    var components = URLComponents()
    components.scheme = "obsidian"
    components.host = taskFocusAction
    components.percentEncodedQuery = encodedQuery(queryItems)
    guard let url = components.url else {
      throw ObsidianTaskOpenServiceError.invalidOpenURL
    }
    return url
  }

  private static func vaultRelativePath(fileURL: URL, vaultRootURL: URL) -> String {
    let filePath = fileURL.standardizedFileURL.path
    let vaultPath = vaultRootURL.standardizedFileURL.path
    let vaultPrefix = vaultPath.hasSuffix("/") ? vaultPath : "\(vaultPath)/"
    guard filePath.hasPrefix(vaultPrefix) else {
      return fileURL.lastPathComponent
    }
    return String(filePath.dropFirst(vaultPrefix.count))
  }

  private static func normalizedBlockIdentifier(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("^") ? trimmed : "^\(trimmed)"
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  private static func encodedQuery(_ items: [(String, String)]) -> String {
    items.map { name, value in
      "\(name)=\(percentEncodedQueryValue(value))"
    }.joined(separator: "&")
  }

  private static func percentEncodedQueryValue(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}

@MainActor
enum ObsidianTaskOpenService {
  static func openProjectNoteFile(
    fileURL: URL,
    documentOpener: any PlatformDocumentOpening
  ) throws {
    try openWithFileFallback(
      primaryURL: ObsidianDeepLinking.projectNoteURL(fileURL: fileURL),
      fallbackFileURL: fileURL,
      documentOpener: documentOpener
    )
  }

  static func openProjectNote(
    vaultRootURL: URL?,
    projectID: UUID,
    documentOpener: any PlatformDocumentOpening
  ) async throws {
    guard let vaultRootURL else {
      throw ObsidianTaskOpenServiceError.vaultNotConfigured
    }
    let snapshot = try await projectSnapshot(vaultRootURL: vaultRootURL, projectID: projectID)
    try openWithFileFallback(
      primaryURL: ObsidianDeepLinking.projectNoteURL(fileURL: snapshot.fileURL),
      fallbackFileURL: snapshot.fileURL,
      documentOpener: documentOpener
    )
  }

  static func openTask(
    vaultRootURL: URL?,
    projectID: UUID,
    taskID: UUID,
    documentOpener: any PlatformDocumentOpening
  ) async throws {
    guard let vaultRootURL else {
      throw ObsidianTaskOpenServiceError.vaultNotConfigured
    }
    let snapshot = try await projectSnapshot(vaultRootURL: vaultRootURL, projectID: projectID)
    let task = try taskSnapshot(in: snapshot, taskID: taskID)
    let openURL: URL
    if let reminderExternalIdentifier = normalized(task.reminderExternalIdentifier) {
      openURL = try ObsidianDeepLinking.taskFocusURL(
        vaultRootURL: vaultRootURL,
        fileURL: snapshot.fileURL,
        blockIdentifier: task.blockIdentifier,
        reminderExternalIdentifier: reminderExternalIdentifier
      )
    } else {
      openURL = try ObsidianDeepLinking.projectNoteURL(fileURL: snapshot.fileURL)
    }

    try openWithFileFallback(
      primaryURL: openURL,
      fallbackFileURL: snapshot.fileURL,
      documentOpener: documentOpener
    )
  }

  private static func projectSnapshot(
    vaultRootURL: URL,
    projectID: UUID
  ) async throws -> ObsidianProjectMarkdownStore.Snapshot {
    guard projectsRootExists(vaultRootURL: vaultRootURL) else {
      throw ObsidianTaskOpenServiceError.projectNotFound(projectID)
    }
    let store = ObsidianProjectMarkdownStore(vaultRootURL: vaultRootURL)
    let snapshots = try await store.loadProjectNotesInScope()
    let matchingSnapshots = snapshots.filter { snapshot in
      guard let listID = normalized(snapshot.note.reminderListExternalIdentifier) else {
        return false
      }
      return RetainedProjectionBuilder.derivedProjectID(for: listID) == projectID
    }
    guard matchingSnapshots.count <= 1 else {
      let identifier = matchingSnapshots
        .compactMap { normalized($0.note.reminderListExternalIdentifier) }
        .sorted()
        .joined(separator: ", ")
      throw ObsidianTaskOpenServiceError.duplicateReminderListExternalIdentifier(identifier)
    }
    guard let snapshot = matchingSnapshots.first else {
      throw ObsidianTaskOpenServiceError.projectNotFound(projectID)
    }
    try validate([snapshot.note])
    return snapshot
  }

  private static func projectsRootExists(vaultRootURL: URL) -> Bool {
    let projectsRootURL = vaultRootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    var isDirectory = ObjCBool(false)
    return FileManager.default.fileExists(
      atPath: projectsRootURL.path,
      isDirectory: &isDirectory
    ) && isDirectory.boolValue
  }

  private static func taskSnapshot(
    in snapshot: ObsidianProjectMarkdownStore.Snapshot,
    taskID: UUID
  ) throws -> ObsidianProjectTask {
    guard let task = snapshot.note.tasks.first(where: { task in
      guard let identifier = normalized(task.reminderExternalIdentifier) else {
        return false
      }
      return ReminderProjectionIdentity.taskID(for: identifier) == taskID
    }) else {
      throw ObsidianTaskOpenServiceError.taskNotFound(taskID)
    }
    return task
  }

  private static func validate(_ notes: [ObsidianProjectNote]) throws {
    for issue in ObsidianProjectNoteValidation.issues(in: notes) {
      switch issue {
      case .duplicateReminderListExternalIdentifier(let identifier):
        throw ObsidianTaskOpenServiceError.duplicateReminderListExternalIdentifier(identifier)
      case .duplicateReminderExternalIdentifier(let identifier):
        throw ObsidianTaskOpenServiceError.duplicateReminderExternalIdentifier(identifier)
      case .damagedTaskMetadata(let line, let rawLine):
        throw ObsidianTaskOpenServiceError.damagedTaskMetadata(line: line, rawLine: rawLine)
      }
    }
  }

  private static func openWithFileFallback(
    primaryURL: URL,
    fallbackFileURL: URL,
    documentOpener: any PlatformDocumentOpening
  ) throws {
    do {
      try documentOpener.open(primaryURL)
    } catch {
      try documentOpener.open(fallbackFileURL)
    }
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
