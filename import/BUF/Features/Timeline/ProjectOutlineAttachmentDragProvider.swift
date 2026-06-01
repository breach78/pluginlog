import AppKit
import Foundation
import UniformTypeIdentifiers

enum ProjectOutlineAttachmentDragProvider {
  static func pasteboardWriter(for attachment: ProjectOutlineInlineAttachment) -> NSPasteboardWriting {
    let taskAttachment = attachment.taskEditAttachment
    let exportFilename = TaskEditAttachmentService.exportFilename(for: taskAttachment)
    let delegate = FilePromiseDelegate(
      sourceURL: attachment.fileURL,
      exportFilename: exportFilename
    )
    let provider = NSFilePromiseProvider(
      fileType: fileType(for: attachment.fileURL),
      delegate: delegate
    )
    provider.userInfo = delegate
    return provider
  }

  private static func fileType(for url: URL) -> String {
    if let type = UTType(filenameExtension: url.pathExtension) {
      return type.identifier
    }
    return UTType.data.identifier
  }
}

private final class FilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
  private let sourceURL: URL
  private let exportFilename: String

  init(sourceURL: URL, exportFilename: String) {
    self.sourceURL = sourceURL
    self.exportFilename = exportFilename
  }

  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider,
    fileNameForType fileType: String
  ) -> String {
    exportFilename
  }

  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider,
    writePromiseTo url: URL,
    completionHandler: @escaping ((any Error)?) -> Void
  ) {
    do {
      try copySourceFile(to: destinationURL(for: url))
      completionHandler(nil)
    } catch {
      completionHandler(error)
    }
  }

  private func destinationURL(for promisedURL: URL) -> URL {
    if promisedURL.hasDirectoryPath {
      return uniqueDestination(in: promisedURL)
    }
    if FileManager.default.fileExists(atPath: promisedURL.path) {
      return uniqueDestination(in: promisedURL.deletingLastPathComponent())
    }
    return promisedURL
  }

  private func uniqueDestination(in directoryURL: URL) -> URL {
    let baseURL = directoryURL.appendingPathComponent(exportFilename)
    guard FileManager.default.fileExists(atPath: baseURL.path) else {
      return baseURL
    }

    let filename = (exportFilename as NSString).deletingPathExtension
    let pathExtension = (exportFilename as NSString).pathExtension
    for suffix in 2...999 {
      let candidateName = pathExtension.isEmpty
        ? "\(filename) \(suffix)"
        : "\(filename) \(suffix).\(pathExtension)"
      let candidateURL = directoryURL.appendingPathComponent(candidateName)
      if !FileManager.default.fileExists(atPath: candidateURL.path) {
        return candidateURL
      }
    }
    return directoryURL.appendingPathComponent("\(UUID().uuidString)-\(exportFilename)")
  }

  private func copySourceFile(to destinationURL: URL) throws {
    do {
      try FileManager.default.linkItem(at: sourceURL, to: destinationURL)
    } catch {
      try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
  }
}
