import XCTest
@testable import BrainUnfog

final class TaskEditAttachmentServiceTests: XCTestCase {
  func testCopyFilesToRawAssetsCreatesUniqueMarkdownLinks() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("TaskEditAttachmentServiceTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("input", isDirectory: true)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)

    let first = input.appendingPathComponent("Report File.pdf")
    let second = input.appendingPathComponent("Report File.pdf.copy")
    try "one".write(to: first, atomically: true, encoding: .utf8)
    try "two".write(to: second, atomically: true, encoding: .utf8)

    let copied = try TaskEditAttachmentService.copyFilesToRawAssets(
      sourceURLs: [first, second],
      vaultRootURL: root
    )

    XCTAssertEqual(copied.count, 2)
    XCTAssertTrue(FileManager.default.fileExists(atPath: copied[0].fileURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: copied[1].fileURL.path))
    XCTAssertEqual(copied[0].relativePath, "raw/assets/Report%20File.pdf")

    let note = TaskEditAttachmentService.noteTextByAppendingAttachments(copied, to: "memo")
    XCTAssertTrue(note.contains("[Report File.pdf](raw/assets/Report%20File.pdf)"))
    XCTAssertEqual(TaskEditAttachmentService.attachments(in: note, vaultRootURL: root), copied)
    XCTAssertEqual(
      TaskEditAttachmentService.noteTextByRemovingAttachmentLinks(from: note),
      "memo"
    )
  }

  func testAttachmentLinkCountCountsRawAssetMarkdownLinksWithoutVault() {
    let note = """
      memo
      [Report.pdf](raw/assets/Report.pdf)
      ![Image.png](raw/assets/Image.png)
      [Website](https://example.com)
      """

    XCTAssertEqual(TaskEditAttachmentService.attachmentLinkCount(in: note), 2)
  }

  func testDeleteAttachmentMovesFileInsideRawAssetsToTrash() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("TaskEditAttachmentDeleteTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let assets = root
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    let file = assets.appendingPathComponent("delete-me.txt")
    try "delete".write(to: file, atomically: true, encoding: .utf8)

    let attachment = TaskEditAttachment(
      displayName: "delete-me.txt",
      relativePath: "raw/assets/delete-me.txt",
      fileURL: file
    )

    let trashedURL = try TaskEditAttachmentService.deleteAttachment(attachment, vaultRootURL: root)
    defer {
      if let trashedURL {
        try? FileManager.default.removeItem(at: trashedURL)
      }
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    XCTAssertNotNil(trashedURL)
  }

  func testCopyFilesToRawAssetsAddsNumberWhenFileAlreadyExists() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("TaskEditAttachmentDuplicateTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("input", isDirectory: true)
    let assets = root
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try "existing".write(
      to: assets.appendingPathComponent("Report File.pdf"),
      atomically: true,
      encoding: .utf8
    )
    let source = input.appendingPathComponent("Report File.pdf")
    try "new".write(to: source, atomically: true, encoding: .utf8)

    let copied = try TaskEditAttachmentService.copyFilesToRawAssets(
      sourceURLs: [source],
      vaultRootURL: root
    )

    XCTAssertEqual(copied.first?.relativePath, "raw/assets/Report%20File-2.pdf")
    XCTAssertTrue(FileManager.default.fileExists(atPath: assets.appendingPathComponent("Report File-2.pdf").path))
  }

  func testExportFilenameUsesDisplayNameAndPreservesSourceExtensionWhenMissing() {
    let attachment = TaskEditAttachment(
      displayName: "Readable Korean Name",
      relativePath: "raw/assets/source.pdf",
      fileURL: URL(fileURLWithPath: "/tmp/source.pdf")
    )

    XCTAssertEqual(
      TaskEditAttachmentService.exportFilename(for: attachment),
      "Readable Korean Name.pdf"
    )
  }

  func testExportFilenameSanitizesPathSeparators() {
    let attachment = TaskEditAttachment(
      displayName: "Folder:Name/Report.pdf",
      relativePath: "raw/assets/Report.pdf",
      fileURL: URL(fileURLWithPath: "/tmp/Report.pdf")
    )

    XCTAssertEqual(
      TaskEditAttachmentService.exportFilename(for: attachment),
      "Folder-Name-Report.pdf"
    )
  }

  func testExportFilenameKeepsStoredFileExtensionWhenDisplayNameHasDifferentExtension() {
    let attachment = TaskEditAttachment(
      displayName: "Readable Name.txt",
      relativePath: "raw/assets/source.pdf",
      fileURL: URL(fileURLWithPath: "/tmp/source.pdf")
    )

    XCTAssertEqual(
      TaskEditAttachmentService.exportFilename(for: attachment),
      "Readable Name.pdf"
    )
  }

  func testExportSuggestedNameOmitsExtensionToAvoidFinderAddingItTwice() {
    let attachment = TaskEditAttachment(
      displayName: "라인업.pdf",
      relativePath: "raw/assets/source.pdf",
      fileURL: URL(fileURLWithPath: "/tmp/source.pdf")
    )

    XCTAssertEqual(
      TaskEditAttachmentService.exportFilename(for: attachment),
      "라인업.pdf"
    )
    XCTAssertEqual(
      TaskEditAttachmentService.exportSuggestedName(for: attachment),
      "라인업"
    )
  }

  func testRenamedDisplayNameChangesStemOnlyAndKeepsSourceExtension() {
    let attachment = TaskEditAttachment(
      displayName: "Old Name.pdf",
      relativePath: "raw/assets/source.pdf",
      fileURL: URL(fileURLWithPath: "/tmp/source.pdf")
    )

    XCTAssertEqual(
      TaskEditAttachmentService.editableFilenameStem(for: attachment),
      "Old Name"
    )
    XCTAssertEqual(
      TaskEditAttachmentService.renamedDisplayName(for: attachment, rawStem: "New:Name/Final"),
      "New-Name-Final.pdf"
    )
  }
}
