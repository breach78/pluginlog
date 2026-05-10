import Foundation

struct TaskEditAttachment: Equatable, Identifiable, Sendable {
  let displayName: String
  let relativePath: String
  let fileURL: URL

  var id: String { relativePath }
}

enum TaskEditAttachmentService {
  enum AttachmentError: LocalizedError, Equatable {
    case obsidianVaultNotConfigured
    case invalidAttachmentLocation(String)
    case sourceUnavailable(URL)

    var errorDescription: String? {
      switch self {
      case .obsidianVaultNotConfigured:
        "Obsidian vault not configured"
      case .invalidAttachmentLocation(let name):
        "첨부파일 위치가 raw/assets 폴더가 아닙니다: \(name)"
      case .sourceUnavailable(let url):
        "첨부파일을 읽을 수 없습니다: \(url.lastPathComponent)"
      }
    }
  }

  static func copyFilesToRawAssets(
    sourceURLs: [URL],
    vaultRootURL: URL?,
    fileManager: FileManager = .default
  ) throws -> [TaskEditAttachment] {
    guard let vaultRootURL else { throw AttachmentError.obsidianVaultNotConfigured }
    let assetsRootURL = rawAssetsRootURL(vaultRootURL: vaultRootURL)
    try fileManager.createDirectory(at: assetsRootURL, withIntermediateDirectories: true)

    return try sourceURLs.map { sourceURL in
      let source = sourceURL.standardizedFileURL
      guard fileManager.fileExists(atPath: source.path) else {
        throw AttachmentError.sourceUnavailable(source)
      }
      let destination = uniqueDestinationURL(
        for: source.lastPathComponent,
        in: assetsRootURL,
        fileManager: fileManager
      )
      try fileManager.copyItem(at: source, to: destination)
      return attachment(for: destination, vaultRootURL: vaultRootURL)
    }
  }

  static func attachments(in noteText: String, vaultRootURL: URL?) -> [TaskEditAttachment] {
    guard let vaultRootURL else { return [] }
    guard let regex = attachmentLinkRegex else { return [] }
    let nsRange = NSRange(noteText.startIndex..<noteText.endIndex, in: noteText)
    return regex.matches(in: noteText, range: nsRange).compactMap { match in
      guard
        let labelRange = Range(match.range(at: 1), in: noteText),
        let pathRange = Range(match.range(at: 2), in: noteText)
      else { return nil }
      let relativePath = String(noteText[pathRange])
      let decodedPath = relativePath.removingPercentEncoding ?? relativePath
      return TaskEditAttachment(
        displayName: String(noteText[labelRange]),
        relativePath: relativePath,
        fileURL: vaultRootURL.appendingPathComponent(decodedPath).standardizedFileURL
      )
    }
  }

  static func attachmentLinkCount(in noteText: String) -> Int {
    guard let regex = attachmentLinkRegex else { return 0 }
    return regex.numberOfMatches(
      in: noteText,
      range: NSRange(noteText.startIndex..<noteText.endIndex, in: noteText)
    )
  }

  static func noteTextByAppendingAttachments(
    _ attachments: [TaskEditAttachment],
    to noteText: String
  ) -> String {
    guard !attachments.isEmpty else { return noteText }
    let normalized = noteText
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .newlines)
    let linkLines = attachments.map { "[\($0.displayName)](\($0.relativePath))" }
    guard !normalized.isEmpty else {
      return linkLines.joined(separator: "\n")
    }
    return (Array(normalized.components(separatedBy: "\n")) + linkLines)
      .joined(separator: "\n")
  }

  static func noteTextByRemovingAttachmentLinks(from noteText: String) -> String {
    let normalized = noteText
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return normalized
      .components(separatedBy: "\n")
      .filter { !isStandaloneAttachmentLink($0) }
      .joined(separator: "\n")
      .trimmingCharacters(in: .newlines)
  }

  static func exportFilename(for attachment: TaskEditAttachment) -> String {
    let displayName = sanitized(attachment.displayName)
    guard let extensionLockedName = nameByApplyingSourceExtension(
      to: displayName,
      sourceExtension: attachment.fileURL.pathExtension
    ) else {
      return displayName
    }
    return extensionLockedName
  }

  static func exportSuggestedName(for attachment: TaskEditAttachment) -> String {
    let filename = exportFilename(for: attachment)
    let sourceExtension = attachment.fileURL.pathExtension
    guard !sourceExtension.isEmpty,
      (filename as NSString).pathExtension.caseInsensitiveCompare(sourceExtension) == .orderedSame
    else {
      return filename
    }
    return (filename as NSString).deletingPathExtension
  }

  static func editableFilenameStem(for attachment: TaskEditAttachment) -> String {
    let displayName = sanitized(attachment.displayName)
    let sourceExtension = attachment.fileURL.pathExtension
    guard !sourceExtension.isEmpty,
      (displayName as NSString).pathExtension.caseInsensitiveCompare(sourceExtension) == .orderedSame
    else {
      return displayName
    }
    return (displayName as NSString).deletingPathExtension
  }

  static func renamedDisplayName(
    for attachment: TaskEditAttachment,
    rawStem: String
  ) -> String? {
    let trimmedStem = rawStem.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedStem.isEmpty else { return nil }
    let sanitizedStem = sanitized(trimmedStem)
    return nameByApplyingSourceExtension(
      to: sanitizedStem,
      sourceExtension: attachment.fileURL.pathExtension
    ) ?? sanitizedStem
  }

  @discardableResult
  static func deleteAttachment(
    _ attachment: TaskEditAttachment,
    vaultRootURL: URL?,
    fileManager: FileManager = .default
  ) throws -> URL? {
    guard let vaultRootURL else { throw AttachmentError.obsidianVaultNotConfigured }
    let assetsRootURL = rawAssetsRootURL(vaultRootURL: vaultRootURL).standardizedFileURL
    let fileURL = attachment.fileURL.standardizedFileURL
    guard fileURL.path.hasPrefix("\(assetsRootURL.path)/") else {
      throw AttachmentError.invalidAttachmentLocation(attachment.displayName)
    }
    guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
    var trashedURL: NSURL?
    try fileManager.trashItem(at: fileURL, resultingItemURL: &trashedURL)
    return trashedURL as URL?
  }

  private static func rawAssetsRootURL(vaultRootURL: URL) -> URL {
    vaultRootURL
      .standardizedFileURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("assets", isDirectory: true)
  }

  private static func isStandaloneAttachmentLink(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    return attachmentLinkRegex?.firstMatch(in: trimmed, range: range)?.range == range
  }

  private static let attachmentLinkRegex = try? NSRegularExpression(
    pattern: #"!?\[([^\]]+)\]\((raw/assets/[^)]+)\)"#
  )

  private static func attachment(for fileURL: URL, vaultRootURL: URL) -> TaskEditAttachment {
    let fileName = fileURL.lastPathComponent
    return TaskEditAttachment(
      displayName: fileName,
      relativePath: "raw/assets/\(encodedPathComponent(fileName))",
      fileURL: fileURL.standardizedFileURL
    )
  }

  private static func uniqueDestinationURL(
    for rawFileName: String,
    in directoryURL: URL,
    fileManager: FileManager
  ) -> URL {
    let sanitizedFileName = sanitized(rawFileName)
    let baseURL = directoryURL.appendingPathComponent(sanitizedFileName)
    guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }

    let ext = baseURL.pathExtension
    let stem = baseURL.deletingPathExtension().lastPathComponent
    var suffix = 2
    while true {
      let candidateName =
        ext.isEmpty
        ? "\(stem)-\(suffix)"
        : "\(stem)-\(suffix).\(ext)"
      let candidateURL = directoryURL.appendingPathComponent(candidateName)
      if !fileManager.fileExists(atPath: candidateURL.path) {
        return candidateURL
      }
      suffix += 1
    }
  }

  private static func sanitized(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = trimmed.isEmpty ? "attachment" : trimmed
    let invalid = CharacterSet(charactersIn: "/\\:")
    return fallback
      .components(separatedBy: invalid)
      .joined(separator: "-")
  }

  private static func nameByApplyingSourceExtension(
    to filename: String,
    sourceExtension: String
  ) -> String? {
    guard !sourceExtension.isEmpty else { return nil }
    let name = filename as NSString
    let stem =
      name.pathExtension.isEmpty
      ? filename
      : name.deletingPathExtension
    return "\(stem).\(sourceExtension)"
  }

  private static func encodedPathComponent(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "#%?[]()")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}
