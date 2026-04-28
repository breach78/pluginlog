import Foundation

actor ObsidianProjectMarkdownStore: ProjectMarkdownStore {
  struct Snapshot: Equatable, Sendable {
    var fileURL: URL
    var vaultRelativePath: String
    var note: ObsidianProjectNote
    var rawMarkdown: String
    var contentModificationDate: Date?

    var normalizedContentHash: String {
      note.normalizedContentHash
    }
  }

  struct WriteBaseline: Equatable, Sendable {
    var normalizedContentHash: String
    var contentModificationDate: Date?

    init(snapshot: Snapshot) {
      self.normalizedContentHash = snapshot.normalizedContentHash
      self.contentModificationDate = snapshot.contentModificationDate
    }
  }

  enum StoreError: LocalizedError, Equatable {
    case missingExpectedBaseline
    case staleExpectedBaseline
    case conflictingReminderListIdentity(existing: String?, requested: String?)
    case unsafeProjectFile(URL)

    var errorDescription: String? {
      switch self {
      case .missingExpectedBaseline:
        return "기존 Obsidian 프로젝트 노트 수정에는 expected baseline이 필요합니다."
      case .staleExpectedBaseline:
        return "Obsidian 프로젝트 노트가 명령 준비 이후 변경되어 쓰기를 중단했습니다."
      case .conflictingReminderListIdentity:
        return "기존 Obsidian 프로젝트 노트의 Reminder list identity가 요청과 충돌합니다."
      case .unsafeProjectFile(let url):
        return "raw/projects 밖의 Obsidian 파일은 프로젝트 노트로 처리하지 않습니다. \(url.path)"
      }
    }
  }

  typealias ProjectNoteSnapshot = Snapshot

  private let vaultRootURL: URL
  private let fileManager: FileManager

  init(vaultRootURL: URL, fileManager: FileManager = .default) {
    self.vaultRootURL = vaultRootURL.standardizedFileURL
    self.fileManager = fileManager
  }

  var projectsRootURL: URL {
    vaultRootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
  }

  func prepareProjectDirectory() async throws {
    try prepareProjectDirectorySync()
  }

  @discardableResult
  func createProjectStub(preferredTitle: String = "새 프로젝트") async throws -> Snapshot {
    try prepareProjectDirectorySync()
    let note = ObsidianProjectNote(
      frontmatter: ObsidianProjectFrontmatter(
        tags: ["프로젝트"],
        reminderListExternalIdentifier: nil,
        preservedLines: []
      ),
      bodyMarkdown: "- ",
      tasks: [],
      diagnostics: [],
      normalizedContentHash: ""
    )
    let fileName = uniqueProjectFileName(preferredTitle: preferredTitle)
    let fileURL = projectsRootURL.appendingPathComponent(fileName, isDirectory: false)
    guard isDirectMarkdownProjectFile(fileURL) else {
      throw StoreError.unsafeProjectFile(fileURL)
    }

    try ObsidianProjectNoteRenderer.render(note).write(
      to: fileURL,
      atomically: true,
      encoding: .utf8
    )
    let snapshot = try loadSnapshot(at: fileURL)
    postWriteNotification(fileURL: snapshot.fileURL)
    return snapshot
  }

  func vaultRoot() -> URL {
    vaultRootURL
  }

  func availableProjectFileName(preferredTitle: String) async throws -> String {
    try prepareProjectDirectorySync()
    return uniqueProjectFileName(preferredTitle: preferredTitle)
  }

  func loadProjectNotesInScope() async throws -> [Snapshot] {
    try prepareProjectDirectorySync()
    let contents = try fileManager.contentsOfDirectory(
      at: projectsRootURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsPackageDescendants]
    )

    return try contents
      .filter(isDirectMarkdownProjectFile)
      .compactMap(loadSnapshotIfInScope)
      .sorted(by: snapshotSort)
  }

  func loadProjectNotesInScope(matchingProjectIDs projectIDs: Set<UUID>) async throws -> [Snapshot] {
    guard !projectIDs.isEmpty else {
      return try await loadProjectNotesInScope()
    }
    try prepareProjectDirectorySync()
    let contents = try fileManager.contentsOfDirectory(
      at: projectsRootURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsPackageDescendants]
    )

    var matchingSnapshots: [Snapshot] = []
    for fileURL in contents where isDirectMarkdownProjectFile(fileURL) {
      guard let listID = try reminderListExternalIdentifier(in: fileURL) else { continue }
      let projectID = RetainedProjectionBuilder.derivedProjectID(for: listID)
      guard projectIDs.contains(projectID),
        let snapshot = try loadSnapshotIfInScope(at: fileURL)
      else {
        continue
      }
      matchingSnapshots.append(snapshot)
    }
    return matchingSnapshots.sorted(by: snapshotSort)
  }

  func loadProjectNotesInScope(at fileURLs: [URL]) async throws -> [Snapshot] {
    try prepareProjectDirectorySync()
    var seenPaths: Set<String> = []
    return try fileURLs
      .filter(isDirectMarkdownProjectFile)
      .filter { fileURL in
        seenPaths.insert(canonicalPath(fileURL)).inserted
      }
      .filter { fileManager.fileExists(atPath: $0.path) }
      .compactMap(loadSnapshotIfInScope)
      .sorted(by: snapshotSort)
  }

  @discardableResult
  func writeProjectNote(
    _ note: ObsidianProjectNote,
    preferredFileName: String,
    expectedBaseline: WriteBaseline? = nil,
    allowClaimingUnownedProject: Bool = false,
    allowReplacingReminderListIdentity: Bool = false
  ) async throws -> Snapshot {
    try prepareProjectDirectorySync()
    let fileURL = projectsRootURL.appendingPathComponent(
      safeMarkdownFileName(preferredFileName),
      isDirectory: false
    )
    guard isDirectMarkdownProjectFile(fileURL) else {
      throw StoreError.unsafeProjectFile(fileURL)
    }
    let rendered = ObsidianProjectNoteRenderer.render(note)
    if fileManager.fileExists(atPath: fileURL.path) {
      let existingSnapshot = try loadSnapshot(at: fileURL)
      if normalizedForWriteComparison(existingSnapshot.rawMarkdown)
        == normalizedForWriteComparison(rendered)
      {
        return existingSnapshot
      }

      try validateExistingFileIdentity(
        existingSnapshot,
        requestedNote: note,
        allowClaimingUnownedProject: allowClaimingUnownedProject,
        allowReplacingReminderListIdentity: allowReplacingReminderListIdentity
      )
      guard let expectedBaseline else {
        throw StoreError.missingExpectedBaseline
      }
      guard expectedBaseline.normalizedContentHash == existingSnapshot.normalizedContentHash,
        expectedBaseline.contentModificationDate == existingSnapshot.contentModificationDate
      else {
        throw StoreError.staleExpectedBaseline
      }
    }
    try rendered.write(to: fileURL, atomically: true, encoding: .utf8)
    let snapshot = try loadSnapshot(at: fileURL)
    postWriteNotification(fileURL: snapshot.fileURL)
    return snapshot
  }

  func removeProjectNote(
    _ snapshot: Snapshot,
    expectedBaseline: WriteBaseline
  ) async throws {
    try prepareProjectDirectorySync()
    let fileURL = snapshot.fileURL.standardizedFileURL
    guard isDirectMarkdownProjectFile(fileURL) else {
      throw StoreError.unsafeProjectFile(fileURL)
    }
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    let currentSnapshot = try loadSnapshot(at: fileURL)
    guard expectedBaseline.normalizedContentHash == currentSnapshot.normalizedContentHash,
      expectedBaseline.contentModificationDate == currentSnapshot.contentModificationDate
    else {
      throw StoreError.staleExpectedBaseline
    }
    try backupDeletedProjectNote(fileURL: fileURL, snapshot: currentSnapshot)
    try fileManager.removeItem(at: fileURL)
    postWriteNotification(fileURL: fileURL)
  }

  private func backupDeletedProjectNote(fileURL: URL, snapshot: Snapshot) throws {
    let backupDirectory = vaultRootURL
      .appendingPathComponent(".buf", isDirectory: true)
      .appendingPathComponent("deleted-project-notes", isDirectory: true)
      .appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(
      at: backupDirectory,
      withIntermediateDirectories: true
    )
    try snapshot.rawMarkdown.write(
      to: backupDirectory.appendingPathComponent(fileURL.lastPathComponent),
      atomically: true,
      encoding: .utf8
    )
    try snapshot.vaultRelativePath.write(
      to: backupDirectory.appendingPathComponent("original-path.txt"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func prepareProjectDirectorySync() throws {
    try fileManager.createDirectory(
      at: projectsRootURL,
      withIntermediateDirectories: true
    )
  }

  private func postWriteNotification(fileURL: URL) {
    NotificationCenter.default.post(
      name: .obsidianProjectMarkdownStoreDidWriteMarkdown,
      object: nil,
      userInfo: [ObsidianProjectMarkdownStoreWriteNotification.fileURLKey: fileURL]
    )
  }

  private func loadSnapshotIfInScope(at fileURL: URL) throws -> Snapshot? {
    let snapshot = try loadSnapshot(at: fileURL)
    guard ObsidianProjectNoteScope.isSyncScopeCandidate(
      snapshot.note,
      vaultRelativePath: snapshot.vaultRelativePath
    ) else {
      return nil
    }
    return snapshot
  }

  private func reminderListExternalIdentifier(in fileURL: URL) throws -> String? {
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    return ObsidianProjectNoteParser.parseFrontmatterOnly(content)?.reminderListExternalIdentifier
  }

  private func loadSnapshot(at fileURL: URL) throws -> Snapshot {
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
    return Snapshot(
      fileURL: fileURL.standardizedFileURL,
      vaultRelativePath: vaultRelativePath(for: fileURL),
      note: ObsidianProjectNoteParser.parse(content),
      rawMarkdown: content,
      contentModificationDate: values?.contentModificationDate
    )
  }

  private func isDirectMarkdownProjectFile(_ fileURL: URL) -> Bool {
    let resolvedFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedProjectsRoot = projectsRootURL.standardizedFileURL.resolvingSymlinksInPath()
    guard resolvedFile.pathExtension.lowercased() == "md" else { return false }
    return resolvedFile.deletingLastPathComponent() == resolvedProjectsRoot
  }

  private func canonicalPath(_ fileURL: URL) -> String {
    fileURL.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private func vaultRelativePath(for fileURL: URL) -> String {
    let rootPath = vaultRootURL.standardizedFileURL.path
    let filePath = fileURL.standardizedFileURL.path
    guard filePath.hasPrefix(rootPath + "/") else {
      return fileURL.lastPathComponent
    }
    return String(filePath.dropFirst(rootPath.count + 1))
  }

  private func safeMarkdownFileName(_ preferredFileName: String) -> String {
    let base = preferredFileName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
    let safeBase = base.isEmpty ? "Untitled" : base
    return safeBase.lowercased().hasSuffix(".md") ? safeBase : "\(safeBase).md"
  }

  private func uniqueProjectFileName(preferredTitle: String) -> String {
    let base = safeMarkdownBaseName(preferredTitle)
    for index in 1..<10_000 {
      let title = index == 1 ? base : "\(base) \(index)"
      let fileName = safeMarkdownFileName(title)
      let fileURL = projectsRootURL.appendingPathComponent(fileName, isDirectory: false)
      if !fileManager.fileExists(atPath: fileURL.path) {
        return fileName
      }
    }
    return safeMarkdownFileName("\(base) \(UUID().uuidString)")
  }

  private func safeMarkdownBaseName(_ preferredTitle: String) -> String {
    let fileName = safeMarkdownFileName(preferredTitle.isEmpty ? "새 프로젝트" : preferredTitle)
    guard fileName.lowercased().hasSuffix(".md") else { return fileName }
    return String(fileName.dropLast(3))
  }

  private func validateExistingFileIdentity(
    _ existingSnapshot: Snapshot,
    requestedNote: ObsidianProjectNote,
    allowClaimingUnownedProject: Bool,
    allowReplacingReminderListIdentity: Bool
  ) throws {
    let requestedListID = normalized(requestedNote.reminderListExternalIdentifier)
    let existingListID = normalized(existingSnapshot.note.reminderListExternalIdentifier)
    if allowReplacingReminderListIdentity,
      existingListID != nil,
      requestedListID != nil
    {
      return
    }
    if allowClaimingUnownedProject,
      existingListID == nil,
      requestedListID != nil,
      existingSnapshot.note.isProjectTagged
    {
      return
    }
    guard requestedListID == nil || requestedListID == existingListID else {
      throw StoreError.conflictingReminderListIdentity(
        existing: existingListID,
        requested: requestedListID
      )
    }
  }

  private func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  private func normalizedForWriteComparison(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private func snapshotSort(_ lhs: Snapshot, _ rhs: Snapshot) -> Bool {
    lhs.vaultRelativePath.localizedStandardCompare(rhs.vaultRelativePath) == .orderedAscending
  }
}
