import Foundation

actor LogseqProjectPageStore {
  struct ProjectIdentity: Equatable, Sendable {
    var projectID: UUID
    var title: String
    var reminderListExternalIdentifier: String?
  }

  struct TaskRecord: Equatable, Sendable {
    var taskID: UUID?
    var title: String
    var isCompleted: Bool
    var date: String?
    var duration: String?
    var repeatRule: String?
    var reminderExternalIdentifier: String?
    var calendarEventExternalIdentifier: String?
  }

  struct PageSnapshot: Equatable, Sendable {
    var fileURL: URL
    var title: String
    var projectID: UUID?
    var reminderListExternalIdentifier: String?
    var usesProjectTag: Bool
    var isBUFOwned: Bool
    var hasManagedTaskSection: Bool
    var noteMarkdown: String
    var managedTasks: [TaskRecord]
    var externalTasks: [TaskRecord]
    var canSafelyPersistProjectNote: Bool
  }

  enum UpsertDisposition: Equatable, Sendable {
    case created
    case updated
  }

  enum StoreError: LocalizedError {
    case emptyTitle
    case pageNotOwned
    case projectIdentityMismatch
    case managedSectionUnavailable
    case managedTasksChangedSinceLoad
    case externalTasksChangedSinceLoad

    var errorDescription: String? {
      switch self {
      case .emptyTitle:
        return "프로젝트 제목이 비어 있습니다."
      case .pageNotOwned:
        return "BUF가 소유하지 않은 Logseq 페이지는 이 슬라이스에서 수정할 수 없습니다."
      case .projectIdentityMismatch:
        return "기존 Logseq 페이지의 BUF 프로젝트 식별자가 요청과 일치하지 않습니다."
      case .managedSectionUnavailable:
        return "기존 페이지에 BUF 관리 섹션이 없어 관리 작업을 쓸 수 없습니다."
      case .managedTasksChangedSinceLoad:
        return "Logseq 관리 작업 섹션이 명령 준비 이후 변경되어 덮어쓰기를 중단했습니다."
      case .externalTasksChangedSinceLoad:
        return "Logseq 작업 블록이 동기화 준비 이후 변경되어 덮어쓰기를 중단했습니다."
      }
    }
  }

  private struct PropertyLine: Equatable {
    var key: String
    var rawKey: String
    var value: String
  }

  private struct ParsedPage {
    var propertyLines: [PropertyLine]
    var title: String
    var projectID: UUID?
    var reminderListExternalIdentifier: String?
    var usesProjectTag: Bool
    var hasManagedTaskSection: Bool
    var noteMarkdown: String
    var managedTasks: [TaskRecord]
    var externalTasks: [TaskRecord]
  }

  private static let managedSectionHeader = "## Brain Unfog Managed Tasks"
  private static let generatedComment = "<!-- generated-by: Brain Unfog -->"

  private let pagesRootURL: URL
  private let preferredFilenameFormat: LogseqPageFilenameFormat
  private let fileManager: FileManager

  init(
    pagesRootURL: URL,
    preferredFilenameFormat: LogseqPageFilenameFormat? = nil,
    fileManager: FileManager = .default
  ) {
    self.pagesRootURL = pagesRootURL
    self.fileManager = fileManager
    self.preferredFilenameFormat =
      preferredFilenameFormat
      ?? LogseqPageFilenameCodec(
        graphRootURL: pagesRootURL.deletingLastPathComponent(),
        fileManager: fileManager
      ).format
  }

  func preparePagesDirectory() throws {
    try fileManager.createDirectory(
      at: pagesRootURL,
      withIntermediateDirectories: true
    )
  }

  func loadProjectPage(
    for identity: ProjectIdentity
  ) throws -> PageSnapshot? {
    let resolvedTitle = normalizedTitle(identity.title)
    guard !resolvedTitle.isEmpty else { throw StoreError.emptyTitle }
    try preparePagesDirectory()

    guard let fileURL = try resolvedOwnedPageURL(for: identity) else {
      return nil
    }

    let parsedPage = try parsePage(at: fileURL)
    guard pageIsInScope(parsedPage) else { return nil }
    return pageSnapshot(for: fileURL, parsedPage: parsedPage)
  }

  func loadClaimableTaggedPage(
    for identity: ProjectIdentity
  ) throws -> PageSnapshot? {
    let resolvedTitle = normalizedTitle(identity.title)
    guard !resolvedTitle.isEmpty else { throw StoreError.emptyTitle }
    try preparePagesDirectory()

    let normalizedReminderListExternalIdentifier = normalizedOptionalValue(
      identity.reminderListExternalIdentifier
    )

    let candidates: [PageSnapshot] = try candidatePageURLs(matchingTitle: resolvedTitle)
      .compactMap { fileURL -> PageSnapshot? in
        let parsedPage = try parsePage(at: fileURL)
        guard parsedPage.projectID == nil, parsedPage.usesProjectTag else {
          return nil
        }
        if let reminderListExternalIdentifier = parsedPage.reminderListExternalIdentifier,
          let normalizedReminderListExternalIdentifier,
          reminderListExternalIdentifier != normalizedReminderListExternalIdentifier
        {
          return nil
        }
        return pageSnapshot(for: fileURL, parsedPage: parsedPage)
      }
      .sorted { lhs, rhs in
        lhs.fileURL.lastPathComponent.localizedStandardCompare(rhs.fileURL.lastPathComponent)
          == .orderedAscending
      }

    guard candidates.count == 1 else {
      return nil
    }

    return candidates[0]
  }

  func loadProjectPagesInScope() throws -> [PageSnapshot] {
    try preparePagesDirectory()

    return try allPageURLs()
      .compactMap { fileURL in
        let parsedPage = try parsePage(at: fileURL)
        guard pageIsInScope(parsedPage) else {
          return nil
        }
        return pageSnapshot(for: fileURL, parsedPage: parsedPage)
      }
      .sorted { lhs, rhs in
        let titleCompare = lhs.title.localizedStandardCompare(rhs.title)
        if titleCompare != .orderedSame {
          return titleCompare == .orderedAscending
        }
        return lhs.fileURL.lastPathComponent.localizedStandardCompare(rhs.fileURL.lastPathComponent)
          == .orderedAscending
      }
  }

  func loadProjectPagesInScope(at fileURLs: [URL]) throws -> [PageSnapshot] {
    try preparePagesDirectory()

    return try fileURLs
      .filter { $0.pathExtension.lowercased() == "md" }
      .filter { fileManager.fileExists(atPath: $0.path) }
      .compactMap { fileURL in
        let parsedPage = try parsePage(at: fileURL)
        guard pageIsInScope(parsedPage) else {
          return nil
        }
        return pageSnapshot(for: fileURL, parsedPage: parsedPage)
      }
      .sorted { lhs, rhs in
        let titleCompare = lhs.title.localizedStandardCompare(rhs.title)
        if titleCompare != .orderedSame {
          return titleCompare == .orderedAscending
        }
        return lhs.fileURL.lastPathComponent.localizedStandardCompare(rhs.fileURL.lastPathComponent)
          == .orderedAscending
      }
  }

  @discardableResult
  func upsertPage(
    _ identity: ProjectIdentity,
    noteMarkdown: String,
    managedTasks: [TaskRecord]
  ) throws -> UpsertDisposition {
    let resolvedTitle = normalizedTitle(identity.title)
    guard !resolvedTitle.isEmpty else { throw StoreError.emptyTitle }
    try preparePagesDirectory()

    if let fileURL = try resolvedOwnedPageURL(for: identity) {
      let parsedPage = try parsePage(at: fileURL)
      guard pageMatches(identity: identity, parsedPage: parsedPage) else {
        throw StoreError.pageNotOwned
      }
      if !managedTasks.isEmpty && !parsedPage.hasManagedTaskSection {
        throw StoreError.managedSectionUnavailable
      }
      if !parsedPage.externalTasks.isEmpty {
        throw StoreError.managedSectionUnavailable
      }

      let rendered = renderPage(
        propertyLines: parsedPage.propertyLines,
        existingUsesProjectReferenceTag: parsedPage.usesProjectTag && usesReferenceProjectTag(parsedPage.propertyLines),
        identity: ProjectIdentity(
          projectID: identity.projectID,
          title: resolvedTitle,
          reminderListExternalIdentifier: identity.reminderListExternalIdentifier
        ),
        noteMarkdown: noteMarkdown,
        managedTasks: managedTasks,
        includeManagedSection: parsedPage.hasManagedTaskSection
      )
      let destinationURL = try destinationPageURL(
        currentFileURL: fileURL,
        title: resolvedTitle,
        identity: identity
      )
      try write(rendered, to: destinationURL)
      if !sameFileURL(destinationURL, fileURL), fileManager.fileExists(atPath: fileURL.path) {
        try fileManager.removeItem(at: fileURL)
      }
      return .updated
    }

    if try !candidatePageURLs(matchingTitle: resolvedTitle).isEmpty {
      throw StoreError.pageNotOwned
    }

    let fileURL = preferredFileURL(for: resolvedTitle)
    let rendered = renderPage(
      propertyLines: [],
      existingUsesProjectReferenceTag: false,
      identity: ProjectIdentity(
        projectID: identity.projectID,
        title: resolvedTitle,
        reminderListExternalIdentifier: identity.reminderListExternalIdentifier
      ),
      noteMarkdown: noteMarkdown,
      managedTasks: managedTasks,
      includeManagedSection: true
    )
    try write(rendered, to: fileURL)
    return .created
  }

  @discardableResult
  func updateManagedTasks(
    in page: PageSnapshot,
    expectedManagedTasks: [TaskRecord],
    managedTasks: [TaskRecord]
  ) throws -> UpsertDisposition {
    let parsedPage = try parsePage(at: page.fileURL)
    guard pageSnapshotMatches(parsedPage: parsedPage, snapshot: page) else {
      throw StoreError.pageNotOwned
    }
    guard parsedPage.hasManagedTaskSection, parsedPage.externalTasks.isEmpty else {
      throw StoreError.managedSectionUnavailable
    }
    guard parsedPage.managedTasks == expectedManagedTasks else {
      throw StoreError.managedTasksChangedSinceLoad
    }

    let rendered = renderPage(
      propertyLines: parsedPage.propertyLines,
      existingUsesProjectReferenceTag: parsedPage.usesProjectTag && usesReferenceProjectTag(parsedPage.propertyLines),
      identity: ProjectIdentity(
        projectID: retainedProjectID(for: parsedPage, fallback: page.projectID),
        title: parsedPage.title,
        reminderListExternalIdentifier: parsedPage.reminderListExternalIdentifier
      ),
      noteMarkdown: parsedPage.noteMarkdown,
      managedTasks: managedTasks,
      includeManagedSection: true
    )
    try write(rendered, to: page.fileURL)
    return .updated
  }

  @discardableResult
  func claimTaggedPage(
    at fileURL: URL,
    as identity: ProjectIdentity,
    noteMarkdown: String,
    managedTasks: [TaskRecord]
  ) throws -> UpsertDisposition {
    let resolvedTitle = normalizedTitle(identity.title)
    guard !resolvedTitle.isEmpty else { throw StoreError.emptyTitle }
    try preparePagesDirectory()

    let parsedPage = try parsePage(at: fileURL)
    guard parsedPage.projectID == nil, parsedPage.usesProjectTag else {
      throw StoreError.pageNotOwned
    }
    guard parsedPage.externalTasks.isEmpty else {
      throw StoreError.managedSectionUnavailable
    }
    let normalizedReminderListExternalIdentifier = normalizedOptionalValue(
      identity.reminderListExternalIdentifier
    )
    if let reminderListExternalIdentifier = parsedPage.reminderListExternalIdentifier,
      let normalizedReminderListExternalIdentifier,
      reminderListExternalIdentifier != normalizedReminderListExternalIdentifier
    {
      throw StoreError.projectIdentityMismatch
    }

    let rendered = renderPage(
      propertyLines: parsedPage.propertyLines,
      existingUsesProjectReferenceTag: usesReferenceProjectTag(parsedPage.propertyLines),
      identity: ProjectIdentity(
        projectID: identity.projectID,
        title: resolvedTitle,
        reminderListExternalIdentifier: identity.reminderListExternalIdentifier
      ),
      noteMarkdown: noteMarkdown,
      managedTasks: managedTasks,
      includeManagedSection: true
    )
    let destinationURL = try destinationPageURL(
      currentFileURL: fileURL,
      title: resolvedTitle,
      identity: identity
    )
    try write(rendered, to: destinationURL)
    if !sameFileURL(destinationURL, fileURL), fileManager.fileExists(atPath: fileURL.path) {
      try fileManager.removeItem(at: fileURL)
    }
    return .updated
  }

  @discardableResult
  func writeReminderProvisioning(
    to page: PageSnapshot,
    reminderListExternalIdentifier: String,
    externalTaskReminderIdentifiersByIndex: [Int: String]
  ) throws -> UpsertDisposition {
    let normalizedReminderListExternalIdentifier = normalizedOptionalValue(
      reminderListExternalIdentifier
    )
    guard let normalizedReminderListExternalIdentifier else {
      throw StoreError.projectIdentityMismatch
    }

    let parsedPage = try parsePage(at: page.fileURL)
    if let existingReminderListExternalIdentifier = parsedPage.reminderListExternalIdentifier,
      existingReminderListExternalIdentifier != normalizedReminderListExternalIdentifier
    {
      throw StoreError.projectIdentityMismatch
    }
    guard parsedPage.externalTasks == page.externalTasks else {
      throw StoreError.externalTasksChangedSinceLoad
    }
    guard externalTaskReminderIdentifiersByIndex.keys.allSatisfy({ page.externalTasks.indices.contains($0) }) else {
      throw StoreError.externalTasksChangedSinceLoad
    }

    var lines = normalizedLineEndings(try readText(at: page.fileURL))
      .components(separatedBy: "\n")
    upsertReminderListExternalIdentifier(
      normalizedReminderListExternalIdentifier,
      into: &lines
    )
    upsertExternalTaskReminderIdentifiers(
      externalTaskReminderIdentifiersByIndex,
      into: &lines
    )

    var rendered = lines.joined(separator: "\n")
    if !rendered.hasSuffix("\n") {
      rendered += "\n"
    }
    try write(rendered, to: page.fileURL)
    return .updated
  }

  @discardableResult
  func updateExternalTask(
    in page: PageSnapshot,
    expectedExternalTasks: [TaskRecord],
    taskIndex: Int,
    task: TaskRecord
  ) throws -> UpsertDisposition {
    guard expectedExternalTasks.indices.contains(taskIndex) else {
      throw StoreError.externalTasksChangedSinceLoad
    }
    let parsedPage = try parsePage(at: page.fileURL)
    guard pageSnapshotMatches(parsedPage: parsedPage, snapshot: page) else {
      throw StoreError.pageNotOwned
    }
    guard parsedPage.externalTasks == expectedExternalTasks else {
      throw StoreError.externalTasksChangedSinceLoad
    }

    var lines = normalizedLineEndings(try readText(at: page.fileURL))
      .components(separatedBy: "\n")
    updateExternalTaskRecord(
      at: taskIndex,
      with: task,
      in: &lines
    )

    var rendered = lines.joined(separator: "\n")
    if !rendered.hasSuffix("\n") {
      rendered += "\n"
    }
    try write(rendered, to: page.fileURL)
    return .updated
  }

  private func resolvedOwnedPageURL(
    for identity: ProjectIdentity
  ) throws -> URL? {
    let matches = try loadProjectPagesInScope().filter { snapshot in
      if snapshot.projectID == identity.projectID {
        return true
      }
      guard let reminderListExternalIdentifier = normalizedOptionalValue(
        identity.reminderListExternalIdentifier
      ) else {
        return false
      }
      return snapshot.reminderListExternalIdentifier == reminderListExternalIdentifier
    }

    guard matches.count == 1 else {
      return nil
    }
    return matches[0].fileURL
  }

  private func candidatePageURLs(
    matchingTitle title: String
  ) throws -> [URL] {
    try allPageURLs().filter { fileURL in
      return LogseqPageFilenameCodec.possibleTitles(forFileNamed: fileURL.lastPathComponent)
        .contains(title)
    }
  }

  private func preferredFileURL(for title: String) -> URL {
    pagesRootURL.appendingPathComponent(
      LogseqPageFilenameCodec.filename(
        for: title,
        format: preferredFilenameFormat
      ),
      isDirectory: false
    )
  }

  private func parsePage(
    at fileURL: URL
  ) throws -> ParsedPage {
    let contents = try readText(at: fileURL)
    let normalizedContents = normalizedLineEndings(contents)
    let lines = normalizedContents.components(separatedBy: "\n")
    let propertyRange = leadingPropertyRange(in: lines)
    let propertyLines = parsePropertyLines(from: Array(lines[propertyRange]))
    let bodyLines = Array(lines.dropFirst(propertyRange.count))
    let managedRange = managedSectionRange(in: bodyLines)
    let managedTasks = managedRange.map { range in
      parseTasks(
        in: Array(bodyLines[range]).dropFirst(
          bodyLines[range].first == Self.managedSectionHeader ? 1 : 0
        ),
        skipGeneratedComment: true
      )
    } ?? []
    let bodyWithoutManagedSection = removingManagedSection(
      from: bodyLines,
      managedRange: managedRange
    )
    let externalTasks = parseTasks(in: bodyWithoutManagedSection, skipGeneratedComment: false)
    let propertiesByKey = propertyLines.reduce(into: [String: String]()) { partialResult, line in
      partialResult[line.key] = partialResult[line.key] ?? line.value
    }

    return ParsedPage(
      propertyLines: propertyLines,
      title: normalizedTitle(
        explicitTitleProperty(from: propertyLines)
          ?? decodedTitle(for: fileURL)
      ),
      projectID: UUID(uuidString: propertiesByKey["brain_unfog_project_id"] ?? ""),
      reminderListExternalIdentifier: normalizedOptionalValue(
        propertiesByKey["reminder_list_external_id"]
      ),
      usesProjectTag: pageUsesProjectScope(propertyLines),
      hasManagedTaskSection: managedRange != nil,
      noteMarkdown: trimmedMarkdown(from: bodyWithoutManagedSection),
      managedTasks: managedTasks,
      externalTasks: externalTasks
    )
  }

  private func renderPage(
    propertyLines: [PropertyLine],
    existingUsesProjectReferenceTag: Bool,
    identity: ProjectIdentity,
    noteMarkdown: String,
    managedTasks: [TaskRecord],
    includeManagedSection: Bool
  ) -> String {
    let renderedProperties = renderPropertyLines(
      updating: propertyLines,
      identity: identity,
      useReferenceProjectTag: existingUsesProjectReferenceTag
    )
    let trimmedNote = trimmedMarkdown(noteMarkdown)
    var sections: [String] = []

    if !renderedProperties.isEmpty {
      sections.append(renderedProperties.joined(separator: "\n"))
    }
    if !trimmedNote.isEmpty {
      sections.append(trimmedNote)
    }
    if includeManagedSection {
      sections.append(renderManagedSection(tasks: managedTasks))
    }

    return sections.joined(separator: "\n\n")
      .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
  }

  private func renderPropertyLines(
    updating existing: [PropertyLine],
    identity: ProjectIdentity,
    useReferenceProjectTag: Bool
  ) -> [String] {
    var lines = existing
    let tagsValue = updatedTagsValue(
      existing: propertyValue(forKey: "tags", in: lines),
      useReferenceTag: useReferenceProjectTag
    )
    upsertProperty(
      rawKey: "tags",
      key: "tags",
      value: tagsValue,
      into: &lines
    )
    if propertyValue(forKey: "brain_unfog_project_id", in: lines) != nil
      || normalizedOptionalValue(identity.reminderListExternalIdentifier) == nil
    {
      upsertProperty(
        rawKey: "brain_unfog_project_id",
        key: "brain_unfog_project_id",
        value: identity.projectID.uuidString.lowercased(),
        into: &lines
      )
    }

    if let reminderListExternalIdentifier = normalizedOptionalValue(identity.reminderListExternalIdentifier) {
      upsertProperty(
        rawKey: "reminder_list_external_id",
        key: "reminder_list_external_id",
        value: reminderListExternalIdentifier,
        into: &lines
      )
    } else {
      removeProperty(key: "reminder_list_external_id", from: &lines)
    }

    if preferredFilenameFormat == .legacy,
      LogseqPageFilenameCodec(format: preferredFilenameFormat)
        .requiresExplicitTitleProperty(pageTitle: identity.title)
    {
      upsertProperty(
        rawKey: "title",
        key: "title",
        value: identity.title,
        into: &lines
      )
    } else {
      removeProperty(key: "title", from: &lines)
    }

    return lines.map { propertyLine in
      "\(propertyLine.rawKey):: \(propertyLine.value)"
    }
  }

  private func renderManagedSection(
    tasks: [TaskRecord]
  ) -> String {
    var lines = [Self.managedSectionHeader, Self.generatedComment]

    for task in tasks {
      let trimmedTitle = normalizedTitle(task.title)
      let marker = task.isCompleted ? "DONE" : "TODO"
      lines.append("- \(marker) \(trimmedTitle)")
      if let taskID = task.taskID {
        lines.append("  brain_unfog_task_id:: \(taskID.uuidString.lowercased())")
      }
      if let reminderExternalIdentifier = normalizedOptionalValue(task.reminderExternalIdentifier) {
        lines.append("  reminder_external_id:: \(reminderExternalIdentifier)")
      }
      if let calendarEventExternalIdentifier = normalizedOptionalValue(
        task.calendarEventExternalIdentifier
      ) {
        lines.append("  calendar_event_external_id:: \(calendarEventExternalIdentifier)")
      }
      if let date = normalizedOptionalValue(task.date) {
        lines.append("  date:: \(date)")
      }
      if let duration = normalizedOptionalValue(task.duration) {
        lines.append("  duration:: \(duration)")
      }
      if let repeatRule = normalizedOptionalValue(task.repeatRule) {
        lines.append("  repeat:: \(repeatRule)")
      }
    }

    return lines.joined(separator: "\n")
  }

  private func parseTasks<S: Sequence>(
    in sourceLines: S,
    skipGeneratedComment: Bool
  ) -> [TaskRecord] where S.Element == String {
    let lines = Array(sourceLines)
    var tasks: [TaskRecord] = []
    var index = 0

    while index < lines.count {
      let line = lines[index]
      if skipGeneratedComment && line == Self.generatedComment {
        index += 1
        continue
      }
      guard let parsedTask = parseTaskLine(line) else {
        index += 1
        continue
      }

      var task = parsedTask.task
      let taskIndent = parsedTask.indent
      index += 1

      while index < lines.count {
        let nextLine = lines[index]
        if skipGeneratedComment && nextLine == Self.generatedComment {
          index += 1
          continue
        }
        if nextLine.hasPrefix("## ") {
          break
        }
        if parseTaskLine(nextLine) != nil {
          break
        }

        let nextIndent = indentationWidth(of: nextLine)
        if nextIndent <= taskIndent {
          break
        }

        if let property = parsePropertyLine(nextLine) {
          switch property.key {
          case "brain_unfog_task_id":
            task.taskID = UUID(uuidString: property.value)
          case "reminder_external_id":
            task.reminderExternalIdentifier = normalizedOptionalValue(property.value)
          case "calendar_event_external_id":
            task.calendarEventExternalIdentifier = normalizedOptionalValue(property.value)
          case "date":
            task.date = normalizedOptionalValue(property.value)
          case "duration":
            task.duration = normalizedOptionalValue(property.value)
          case "repeat":
            task.repeatRule = normalizedOptionalValue(property.value)
          default:
            break
          }
        }
        index += 1
      }

      tasks.append(task)
    }

    return tasks
  }

  private func parseTaskLine(
    _ line: String
  ) -> (indent: Int, task: TaskRecord)? {
    let indent = indentationWidth(of: line)
    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
    guard trimmedLine.hasPrefix("- ") else { return nil }

    let remainder = String(trimmedLine.dropFirst(2))
    if remainder.hasPrefix("TODO ") {
      return (
        indent,
        TaskRecord(
          taskID: nil,
          title: String(remainder.dropFirst(5)),
          isCompleted: false,
          date: nil,
          duration: nil,
          repeatRule: nil,
          reminderExternalIdentifier: nil,
          calendarEventExternalIdentifier: nil
        )
      )
    }
    if remainder.hasPrefix("DONE ") {
      return (
        indent,
        TaskRecord(
          taskID: nil,
          title: String(remainder.dropFirst(5)),
          isCompleted: true,
          date: nil,
          duration: nil,
          repeatRule: nil,
          reminderExternalIdentifier: nil,
          calendarEventExternalIdentifier: nil
        )
      )
    }
    return nil
  }

  private func upsertReminderListExternalIdentifier(
    _ reminderListExternalIdentifier: String,
    into lines: inout [String]
  ) {
    let propertyRange = leadingPropertyRange(in: lines)
    var propertyLines = parsePropertyLines(from: Array(lines[propertyRange]))
    upsertProperty(
      rawKey: "reminder_list_external_id",
      key: "reminder_list_external_id",
      value: reminderListExternalIdentifier,
      into: &propertyLines
    )
    var replacement = propertyLines.map { "\($0.rawKey):: \($0.value)" }
    if !replacement.isEmpty,
      propertyRange.upperBound < lines.count,
      !lines[propertyRange.upperBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      replacement.append("")
    }
    lines.replaceSubrange(propertyRange, with: replacement)
  }

  private func upsertExternalTaskReminderIdentifiers(
    _ identifiersByExternalTaskIndex: [Int: String],
    into lines: inout [String]
  ) {
    guard !identifiersByExternalTaskIndex.isEmpty else { return }

    let propertyRange = leadingPropertyRange(in: lines)
    let bodyStart = propertyRange.upperBound
    let managedRange = managedSectionRange(in: Array(lines.dropFirst(bodyStart))).map {
      (bodyStart + $0.lowerBound)..<(bodyStart + $0.upperBound)
    }

    var externalTaskIndex = 0
    var lineIndex = bodyStart
    while lineIndex < lines.count {
      if let managedRange, managedRange.contains(lineIndex) {
        lineIndex = managedRange.upperBound
        continue
      }
      guard let parsedTask = parseTaskLine(lines[lineIndex]) else {
        lineIndex += 1
        continue
      }

      if let reminderExternalIdentifier = normalizedOptionalValue(
        identifiersByExternalTaskIndex[externalTaskIndex]
      ) {
        upsertTaskProperty(
          key: "reminder_external_id",
          rawKey: "reminder_external_id",
          value: reminderExternalIdentifier,
          taskLineIndex: lineIndex,
          taskIndent: parsedTask.indent,
          managedRange: managedRange,
          in: &lines
        )
      }

      externalTaskIndex += 1
      lineIndex += 1
    }
  }

  private func updateExternalTaskRecord(
    at targetExternalTaskIndex: Int,
    with task: TaskRecord,
    in lines: inout [String]
  ) {
    let propertyRange = leadingPropertyRange(in: lines)
    let bodyStart = propertyRange.upperBound
    let managedRange = managedSectionRange(in: Array(lines.dropFirst(bodyStart))).map {
      (bodyStart + $0.lowerBound)..<(bodyStart + $0.upperBound)
    }

    var externalTaskIndex = 0
    var lineIndex = bodyStart
    while lineIndex < lines.count {
      if let managedRange, managedRange.contains(lineIndex) {
        lineIndex = managedRange.upperBound
        continue
      }
      guard let parsedTask = parseTaskLine(lines[lineIndex]) else {
        lineIndex += 1
        continue
      }
      guard externalTaskIndex == targetExternalTaskIndex else {
        externalTaskIndex += 1
        lineIndex += 1
        continue
      }

      updateTaskMarker(at: lineIndex, isCompleted: task.isCompleted, in: &lines)
      upsertOrRemoveTaskProperty(
        key: "reminder_external_id",
        rawKey: "reminder_external_id",
        value: task.reminderExternalIdentifier,
        taskLineIndex: lineIndex,
        taskIndent: parsedTask.indent,
        managedRange: managedRange,
        in: &lines
      )
      upsertOrRemoveTaskProperty(
        key: "date",
        rawKey: "date",
        value: task.date,
        taskLineIndex: lineIndex,
        taskIndent: parsedTask.indent,
        managedRange: managedRange,
        in: &lines
      )
      upsertOrRemoveTaskProperty(
        key: "duration",
        rawKey: "duration",
        value: task.duration,
        taskLineIndex: lineIndex,
        taskIndent: parsedTask.indent,
        managedRange: managedRange,
        in: &lines
      )
      upsertOrRemoveTaskProperty(
        key: "repeat",
        rawKey: "repeat",
        value: task.repeatRule,
        taskLineIndex: lineIndex,
        taskIndent: parsedTask.indent,
        managedRange: managedRange,
        in: &lines
      )
      return
    }
  }

  private func updateTaskMarker(
    at lineIndex: Int,
    isCompleted: Bool,
    in lines: inout [String]
  ) {
    let replacement = isCompleted ? "DONE" : "TODO"
    if let range = lines[lineIndex].range(of: "- TODO ") {
      lines[lineIndex].replaceSubrange(range, with: "- \(replacement) ")
      return
    }
    if let range = lines[lineIndex].range(of: "- DONE ") {
      lines[lineIndex].replaceSubrange(range, with: "- \(replacement) ")
    }
  }

  private func upsertOrRemoveTaskProperty(
    key: String,
    rawKey: String,
    value: String?,
    taskLineIndex: Int,
    taskIndent: Int,
    managedRange: Range<Int>?,
    in lines: inout [String]
  ) {
    guard let value = normalizedOptionalValue(value) else {
      removeTaskProperty(
        key: key,
        taskLineIndex: taskLineIndex,
        taskIndent: taskIndent,
        managedRange: managedRange,
        in: &lines
      )
      return
    }
    upsertTaskProperty(
      key: key,
      rawKey: rawKey,
      value: value,
      taskLineIndex: taskLineIndex,
      taskIndent: taskIndent,
      managedRange: managedRange,
      in: &lines
    )
  }

  private func removeTaskProperty(
    key: String,
    taskLineIndex: Int,
    taskIndent: Int,
    managedRange: Range<Int>?,
    in lines: inout [String]
  ) {
    let endIndex = taskBlockEndIndex(
      from: taskLineIndex,
      taskIndent: taskIndent,
      managedRange: managedRange,
      in: lines
    )
    var lineIndex = taskLineIndex + 1
    while lineIndex < endIndex {
      if let property = parsePropertyLine(lines[lineIndex]), property.key == key {
        lines.remove(at: lineIndex)
        return
      }
      lineIndex += 1
    }
  }

  private func upsertTaskProperty(
    key: String,
    rawKey: String,
    value: String,
    taskLineIndex: Int,
    taskIndent: Int,
    managedRange: Range<Int>?,
    in lines: inout [String]
  ) {
    let endIndex = taskBlockEndIndex(
      from: taskLineIndex,
      taskIndent: taskIndent,
      managedRange: managedRange,
      in: lines
    )
    var insertionIndex = taskLineIndex + 1
    var lineIndex = taskLineIndex + 1
    while lineIndex < endIndex {
      if let property = parsePropertyLine(lines[lineIndex]), property.key == key {
        let indent = String(repeating: " ", count: indentationWidth(of: lines[lineIndex]))
        lines[lineIndex] = "\(indent)\(property.rawKey):: \(value)"
        return
      }
      lineIndex += 1
    }

    insertionIndex = min(insertionIndex, lines.count)
    let indent = String(repeating: " ", count: taskIndent + 2)
    lines.insert("\(indent)\(rawKey):: \(value)", at: insertionIndex)
  }

  private func taskBlockEndIndex(
    from taskLineIndex: Int,
    taskIndent: Int,
    managedRange: Range<Int>?,
    in lines: [String]
  ) -> Int {
    var lineIndex = taskLineIndex + 1
    while lineIndex < lines.count {
      if let managedRange, managedRange.contains(lineIndex) {
        break
      }
      let line = lines[lineIndex]
      if line.hasPrefix("## ") {
        break
      }
      if parseTaskLine(line) != nil {
        break
      }
      if indentationWidth(of: line) <= taskIndent,
        !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        break
      }
      lineIndex += 1
    }
    return lineIndex
  }

  private func leadingPropertyRange(
    in lines: [String]
  ) -> Range<Int> {
    var upperBound = 0
    while upperBound < lines.count {
      let line = lines[upperBound]
      if line.isEmpty {
        upperBound += 1
        continue
      }
      guard parsePropertyLine(line) != nil else {
        break
      }
      upperBound += 1
    }

    return 0..<upperBound
  }

  private func parsePropertyLines(
    from lines: [String]
  ) -> [PropertyLine] {
    lines.compactMap(parsePropertyLine)
  }

  private func parsePropertyLine(
    _ line: String
  ) -> PropertyLine? {
    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
    guard let separatorRange = trimmedLine.range(of: "::") else { return nil }
    let rawKey = String(trimmedLine[..<separatorRange.lowerBound]).trimmingCharacters(
      in: .whitespaces
    )
    guard !rawKey.isEmpty else { return nil }
    let valueStart = separatorRange.upperBound
    let value = String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespaces)
    return PropertyLine(
      key: rawKey.lowercased(),
      rawKey: rawKey,
      value: value
    )
  }

  private func managedSectionRange(
    in lines: [String]
  ) -> Range<Int>? {
    guard let startIndex = lines.firstIndex(of: Self.managedSectionHeader) else { return nil }
    var endIndex = startIndex + 1
    while endIndex < lines.count {
      if lines[endIndex].hasPrefix("## ") {
        break
      }
      endIndex += 1
    }
    return startIndex..<endIndex
  }

  private func removingManagedSection(
    from lines: [String],
    managedRange: Range<Int>?
  ) -> [String] {
    guard let managedRange else { return lines }
    return Array(lines[..<managedRange.lowerBound]) + Array(lines[managedRange.upperBound...])
  }

  private func explicitTitleProperty(
    from propertyLines: [PropertyLine]
  ) -> String? {
    propertyValue(forKey: "title", in: propertyLines)
  }

  private func pageUsesProjectScope(
    _ propertyLines: [PropertyLine]
  ) -> Bool {
    guard let tagsValue = propertyValue(forKey: "tags", in: propertyLines) else { return false }
    return tagsContainProjectScope(tagsValue)
  }

  private func pageIsInScope(_ parsedPage: ParsedPage) -> Bool {
    parsedPage.usesProjectTag
      || parsedPage.projectID != nil
      || parsedPage.reminderListExternalIdentifier != nil
  }

  private func pageMatches(
    identity: ProjectIdentity,
    parsedPage: ParsedPage
  ) -> Bool {
    let identityReminderListExternalIdentifier = normalizedOptionalValue(
      identity.reminderListExternalIdentifier
    )
    let projectMatches = parsedPage.projectID == identity.projectID
    let reminderMatches =
      identityReminderListExternalIdentifier != nil
      && parsedPage.reminderListExternalIdentifier == identityReminderListExternalIdentifier

    guard projectMatches || reminderMatches else { return false }
    if let projectID = parsedPage.projectID, projectID != identity.projectID {
      return false
    }
    if let reminderListExternalIdentifier = parsedPage.reminderListExternalIdentifier {
      guard let identityReminderListExternalIdentifier,
        reminderListExternalIdentifier == identityReminderListExternalIdentifier
      else {
        return false
      }
    }
    return true
  }

  private func pageSnapshotMatches(
    parsedPage: ParsedPage,
    snapshot: PageSnapshot
  ) -> Bool {
    guard parsedPage.projectID != nil || parsedPage.reminderListExternalIdentifier != nil else {
      return false
    }
    if parsedPage.projectID != snapshot.projectID {
      return false
    }
    if parsedPage.reminderListExternalIdentifier != snapshot.reminderListExternalIdentifier {
      return false
    }
    return true
  }

  private func retainedProjectID(
    for parsedPage: ParsedPage,
    fallback: UUID?
  ) -> UUID {
    if let projectID = parsedPage.projectID {
      return projectID
    }
    if let reminderListExternalIdentifier = parsedPage.reminderListExternalIdentifier {
      return RetainedProjectionBuilder.derivedProjectID(for: reminderListExternalIdentifier)
    }
    return fallback ?? UUID()
  }

  private func usesReferenceProjectTag(
    _ propertyLines: [PropertyLine]
  ) -> Bool {
    guard let tagsValue = propertyValue(forKey: "tags", in: propertyLines) else { return false }
    return tagsValue.contains("[[프로젝트]]")
  }

  private func updatedTagsValue(
    existing: String?,
    useReferenceTag: Bool
  ) -> String {
    let requiredToken = useReferenceTag ? "[[프로젝트]]" : "프로젝트"
    guard let existing = normalizedOptionalValue(existing), !existing.isEmpty else {
      return requiredToken
    }
    guard !tagsContainProjectScope(existing) else { return existing }
    return existing + ", " + requiredToken
  }

  private func tagsContainProjectScope(
    _ value: String
  ) -> Bool {
    let normalized = value.replacingOccurrences(of: ",", with: " ")
    let tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
    return tokens.contains("프로젝트") || tokens.contains("[[프로젝트]]")
  }

  private func upsertProperty(
    rawKey: String,
    key: String,
    value: String,
    into lines: inout [PropertyLine]
  ) {
    if let existingIndex = lines.firstIndex(where: { $0.key == key }) {
      lines[existingIndex].value = value
      return
    }
    lines.append(PropertyLine(key: key, rawKey: rawKey, value: value))
  }

  private func removeProperty(
    key: String,
    from lines: inout [PropertyLine]
  ) {
    lines.removeAll { $0.key == key }
  }

  private func propertyValue(
    forKey key: String,
    in lines: [PropertyLine]
  ) -> String? {
    lines.first(where: { $0.key == key })?.value
  }

  private func decodedTitle(
    for fileURL: URL
  ) -> String {
    let titles = LogseqPageFilenameCodec.possibleTitles(forFileNamed: fileURL.lastPathComponent)
    if fileURL.lastPathComponent.contains("___"),
      let namespaceTitle = titles.first(where: { $0.contains("/") })
    {
      return namespaceTitle
    }
    if fileURL.lastPathComponent.localizedCaseInsensitiveContains("%2f"),
      let slashDecodedTitle = titles.first(where: { $0.contains("/") })
    {
      return slashDecodedTitle
    }
    return titles.sorted { lhs, rhs in
      lhs.localizedStandardCompare(rhs) == .orderedAscending
    }.first ?? fileURL.deletingPathExtension().lastPathComponent
  }

  private func indentationWidth(
    of line: String
  ) -> Int {
    line.prefix { $0 == " " || $0 == "\t" }.count
  }

  private func normalizedTitle(
    _ title: String
  ) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func normalizedOptionalValue(
    _ value: String?
  ) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private func trimmedMarkdown(
    _ markdown: String
  ) -> String {
    trimmedMarkdown(
      from: normalizedLineEndings(markdown).components(separatedBy: "\n")
    )
  }

  private func trimmedMarkdown(
    from lines: [String]
  ) -> String {
    var start = 0
    var end = lines.count

    while start < end && lines[start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      start += 1
    }
    while end > start && lines[end - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      end -= 1
    }

    return lines[start..<end].joined(separator: "\n")
  }

  private func normalizedLineEndings(
    _ contents: String
  ) -> String {
    contents
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private func readText(
    at fileURL: URL
  ) throws -> String {
    do {
      return try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
      let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
      return String(decoding: data, as: UTF8.self)
    }
  }

  private func pageSnapshot(
    for fileURL: URL,
    parsedPage: ParsedPage
  ) -> PageSnapshot {
    let hasRetainedIdentity =
      parsedPage.projectID != nil
      || parsedPage.reminderListExternalIdentifier != nil
    return PageSnapshot(
      fileURL: fileURL,
      title: parsedPage.title,
      projectID: parsedPage.projectID,
      reminderListExternalIdentifier: parsedPage.reminderListExternalIdentifier,
      usesProjectTag: parsedPage.usesProjectTag,
      isBUFOwned: hasRetainedIdentity,
      hasManagedTaskSection: parsedPage.hasManagedTaskSection,
      noteMarkdown: parsedPage.noteMarkdown,
      managedTasks: parsedPage.managedTasks,
      externalTasks: parsedPage.externalTasks,
      canSafelyPersistProjectNote: hasRetainedIdentity && parsedPage.externalTasks.isEmpty
    )
  }

  private func allPageURLs() throws -> [URL] {
    try fileManager.contentsOfDirectory(
      at: pagesRootURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension.lowercased() == "md" }
  }

  private func destinationPageURL(
    currentFileURL: URL,
    title: String,
    identity: ProjectIdentity
  ) throws -> URL {
    let preferredURL = preferredFileURL(for: title)
    guard !sameFileURL(preferredURL, currentFileURL) else { return currentFileURL }
    guard fileManager.fileExists(atPath: preferredURL.path) else { return preferredURL }

    let parsedPage = try parsePage(at: preferredURL)
    guard pageMatches(identity: identity, parsedPage: parsedPage) else {
      throw StoreError.pageNotOwned
    }
    return preferredURL
  }

  private func sameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.resolvingSymlinksInPath().standardizedFileURL
      == rhs.resolvingSymlinksInPath().standardizedFileURL
  }

  private func write(
    _ contents: String,
    to fileURL: URL
  ) throws {
    let data = Data(contents.utf8)
    let tempURL = fileURL.deletingLastPathComponent()
      .appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)
    let backupName = ".\(fileURL.lastPathComponent).bak"
    let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)

    do {
      try data.write(to: tempURL, options: .atomic)
      do {
        _ = try fileManager.replaceItemAt(
          fileURL,
          withItemAt: tempURL,
          backupItemName: backupName,
          options: [.usingNewMetadataOnly]
        )
        if fileManager.fileExists(atPath: backupURL.path) {
          try? fileManager.removeItem(at: backupURL)
        }
      } catch {
        if !fileManager.fileExists(atPath: fileURL.path) {
          try fileManager.moveItem(at: tempURL, to: fileURL)
        } else {
          throw error
        }
      }
    } catch {
      if !fileManager.fileExists(atPath: fileURL.path), fileManager.fileExists(atPath: backupURL.path) {
        try? fileManager.moveItem(at: backupURL, to: fileURL)
      }
      if fileManager.fileExists(atPath: tempURL.path) {
        try? fileManager.removeItem(at: tempURL)
      }
      throw error
    }
    NotificationCenter.default.post(
      name: .logseqProjectPageStoreDidWriteMarkdown,
      object: self,
      userInfo: [LogseqProjectPageStoreWriteNotification.fileURLKey: fileURL]
    )
  }
}
