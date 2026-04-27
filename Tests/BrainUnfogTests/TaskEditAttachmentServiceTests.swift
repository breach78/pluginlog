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

  func testDeleteAttachmentRemovesFileInsideRawAssets() throws {
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

    try TaskEditAttachmentService.deleteAttachment(attachment, vaultRootURL: root)

    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
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
}
